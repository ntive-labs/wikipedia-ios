import Foundation

/// Data controller for the Edit Patrol recent-changes feed.
///
/// Ports Android's `SuggestedEditsRecentEditsViewModel.getRecentEditsCall`,
/// `SuggestedEditsRecentEditsFilterTypes` filtering, the patrol-eligibility rule
/// from `SuggestedEditsTasksFragmentViewModel`, and the revert-candidate cache
/// from `EditingSuggestionsProvider`.
///
/// Mirrors the conventions of `WMFWatchlistDataController` (completion-handler
/// networking through `WMFDataEnvironment.current.mediaWikiService`, user-defaults
/// backed filter persistence). Undo / rollback / thank / watch continue to reuse
/// `WMFWatchlistDataController` — this controller only adds the missing
/// feed / ORES / eligibility / candidate-advance layer.
public final class WMFRecentEditsDataController {

    /// Shared instance — used so the revert-candidate cache survives across screens
    /// (parallel to Android's `EditingSuggestionsProvider` object).
    public static let shared = WMFRecentEditsDataController()

    var service = WMFDataEnvironment.current.mediaWikiService
    private let userDefaultsStore = WMFDataEnvironment.current.userDefaultsStore

    /// Server page size (matches Android's `pageSize = 50`).
    public static let pageSize = 50

    /// In-session cache of resolved user info, keyed by username. Mirrors Android's
    /// `cachedUserInfo` list passed into `getRecentEditsCall`.
    private var userInfoCache: [String: UserInfoRecord] = [:]

    // MARK: Revert-candidate cache state (ports EditingSuggestionsProvider)

    private let candidateLock = NSLock()
    private var revertCandidateLang: String = ""
    private var revertCandidateCache: [WMFRecentEdits.Item] = []
    private var revertCandidateLastRevID: UInt = 0
    private var revertCandidateLastTimestamp: Date = Date()

    public init() { }

    // MARK: - Filter Settings

    public func loadFilterSettings() -> WMFRecentEditsFilterSettings {
        let key = WMFUserDefaultsKey.recentEditsFilterSettings.rawValue
        return (try? userDefaultsStore?.load(key: key)) ?? WMFRecentEditsFilterSettings()
    }

    public func saveFilterSettings(_ filterSettings: WMFRecentEditsFilterSettings) {
        let key = WMFUserDefaultsKey.recentEditsFilterSettings.rawValue
        try? userDefaultsStore?.save(key: key, value: filterSettings)
    }

    /// Ports `SuggestedEditsRecentEditsViewModel.filtersCount()` exactly.
    public func activeFilterCount() -> Int {
        let included = loadFilterSettings().includedTypes

        let userStatusGroup = Set(WMFRecentEditsFilterType.userRegistrationGroup + WMFRecentEditsFilterType.userExperienceGroup)
        let findSelectedUserStatus = included.intersection(userStatusGroup)

        // Non-default user status = symmetric difference against the defaults.
        let defaultUserStatusSet = WMFRecentEditsFilterType.defaultFilterUserStatus
        let nonDefaultUserStatus = findSelectedUserStatus.symmetricDifference(defaultUserStatusSet)

        // ORES-related (default is empty).
        let oresGroup = Set(WMFRecentEditsFilterType.goodfaithGroup + WMFRecentEditsFilterType.damagingGroup)
        let findSelectedOres = included.subtracting(findSelectedUserStatus).intersection(oresGroup)

        // Remaining selected filters.
        let findSelectedOthers = included.subtracting(findSelectedOres)
        let defaultOthersSet = WMFRecentEditsFilterType.defaultFilterOthers
        let nonDefaultOthers = defaultOthersSet.subtracting(findSelectedOthers)

        return nonDefaultUserStatus.count + nonDefaultOthers.count + findSelectedOres.count
    }

    // MARK: - Onboarding

    public func hasPresentedOnboarding() -> Bool {
        let key = WMFUserDefaultsKey.recentEditsOnboarding.rawValue
        return (try? userDefaultsStore?.load(key: key)) ?? false
    }

    public func setHasPresentedOnboarding(_ value: Bool) {
        let key = WMFUserDefaultsKey.recentEditsOnboarding.rawValue
        try? userDefaultsStore?.save(key: key, value: value)
    }

    // MARK: - Session cache

    public func clearCache() {
        candidateLock.lock()
        userInfoCache.removeAll()
        candidateLock.unlock()
    }

    // MARK: - Fetch recent edits

    /// Fetches a page of recent edits and applies the two-stage filtering that Android
    /// performs (server ORES/bot/minor/latest gating, then client-side ORES + user
    /// experience/registration filtering).
    ///
    /// Mirrors `getRecentEditsCall`, returning the filtered list, the full unfiltered
    /// list, and the continuation token.
    public func fetchRecentEdits(project: WMFProject, count: Int = WMFRecentEditsDataController.pageSize, startTimestamp: Date = Date(), direction: String = "older", continueString: String? = nil, completion: @escaping (Result<WMFRecentEdits, Error>) -> Void) {

        guard let service else {
            completion(.failure(WMFDataControllerError.mediaWikiServiceUnavailable))
            return
        }

        guard let url = URL.mediaWikiAPIURL(project: project) else {
            completion(.failure(WMFDataControllerError.failureCreatingRequestURL))
            return
        }

        let filterSettings = loadFilterSettings()
        let activeFilterCount = self.activeFilterCount()

        var parameters: [String: Any] = [
            "action": "query",
            "list": "recentchanges",
            "rcprop": "title|timestamp|ids|oresscores|sizes|tags|user|parsedcomment|comment|flags",
            "rcnamespace": "0",
            "rctype": "edit|new",
            "rclimit": String(count),
            "rcstart": DateFormatter.mediaWikiAPIDateFormatter.string(from: startTimestamp),
            "rcdir": direction,
            "errorsuselocal": "1",
            "errorformat": "html",
            "format": "json",
            "formatversion": "2"
        ]

        if let latest = latestRevisionsValue(filterSettings: filterSettings) {
            parameters["rctoponly"] = latest
        }

        let show = showCriteriaString(filterSettings: filterSettings)
        if !show.isEmpty {
            parameters["rcshow"] = show
        }

        if let continueString {
            parameters["rccontinue"] = continueString
        }

        parameters["variant"] = project.languageVariantCode

        let request = WMFMediaWikiServiceRequest(url: url, method: .GET, backend: .mediaWiki, parameters: parameters)
        service.performDecodableGET(request: request) { [weak self] (result: Result<RecentChangesAPIResponse, Error>) in
            guard let self else { return }

            switch result {
            case .success(let apiResponse):
                if let errors = apiResponse.errors, !errors.isEmpty {
                    completion(.failure(WMFDataControllerError.mediaWikiResponseError(errors[0])))
                    return
                }

                let allChanges = (apiResponse.query?.recentChanges ?? []).compactMap { $0.item(project: project) }

                // Stage 1: client-side ORES damaging + good-faith filtering.
                let oresFiltered = self.filterORESScores(self.filterORESScores(allChanges, isDamagingGroup: true), isDamagingGroup: false)

                // Stage 2: user experience + registration filtering (needs list=users enrichment).
                let usernames = oresFiltered
                    .filter { !$0.isAnon }
                    .map { $0.username }
                    .reduce(into: [String]()) { acc, name in if !acc.contains(name) { acc.append(name) } }

                self.enrichUserInfo(usernames: usernames, project: project) {
                    let experienceFiltered = self.filterUserExperience(oresFiltered)
                    let registrationFiltered = self.filterUserRegistration(experienceFiltered)
                    let finalItems = registrationFiltered.sorted { $0.timestamp > $1.timestamp }

                    let recentEdits = WMFRecentEdits(items: finalItems, unfilteredItems: allChanges, continueString: apiResponse.continuation?.rcContinue, activeFilterCount: activeFilterCount)
                    completion(.success(recentEdits))
                }

            case .failure(let error):
                completion(.failure(WMFDataControllerError.serviceError(error)))
            }
        }
    }

    /// Fetches `list=users` info for the distinct non-anon usernames that aren't already
    /// cached, then invokes `completion`. Mirrors Android's `service.userInfo(...)` step.
    private func enrichUserInfo(usernames: [String], project: WMFProject, completion: @escaping () -> Void) {
        let missing = usernames.filter { userInfoCache[$0] == nil }
        guard !missing.isEmpty, let service, let url = URL.mediaWikiAPIURL(project: project) else {
            completion()
            return
        }

        let parameters: [String: Any] = [
            "action": "query",
            "list": "users",
            "usprop": "editcount|groups|registration|rights",
            "ususers": missing.joined(separator: "|"),
            "errorsuselocal": "1",
            "errorformat": "html",
            "format": "json",
            "formatversion": "2"
        ]

        let request = WMFMediaWikiServiceRequest(url: url, method: .GET, backend: .mediaWiki, parameters: parameters)
        service.performDecodableGET(request: request) { [weak self] (result: Result<UsersAPIResponse, Error>) in
            guard let self else {
                completion()
                return
            }

            if case .success(let response) = result {
                for user in response.query?.users ?? [] {
                    self.userInfoCache[user.name] = UserInfoRecord(name: user.name, editCount: user.editCount ?? -1, registrationDate: user.registrationDate)
                }
            }
            completion()
        }
    }

    // MARK: - Request-building helpers (port latestRevisions / showCriteriaString)

    private func latestRevisionsValue(filterSettings: WMFRecentEditsFilterSettings) -> String? {
        let included = filterSettings.includedTypes
        let group = WMFRecentEditsFilterType.latestRevisionsGroup
        if !group.allSatisfy({ included.contains($0) }) && !included.contains(.latestRevision) {
            return WMFRecentEditsFilterType.notLatestRevision.value
        }
        return nil
    }

    private func showCriteriaString(filterSettings: WMFRecentEditsFilterSettings) -> String {
        let included = filterSettings.includedTypes
        var list: [String] = []

        if !WMFRecentEditsFilterType.botEditsGroup.allSatisfy({ included.contains($0) }) {
            if included.contains(.bot) { list.append(WMFRecentEditsFilterType.bot.value) }
            if included.contains(.human) { list.append(WMFRecentEditsFilterType.human.value) }
        }

        if !WMFRecentEditsFilterType.minorEditsGroup.allSatisfy({ included.contains($0) }) {
            if included.contains(.minorEdits) { list.append(WMFRecentEditsFilterType.minorEdits.value) }
            if included.contains(.nonMinorEdits) { list.append(WMFRecentEditsFilterType.nonMinorEdits.value) }
        }

        let oresGroup = Set(WMFRecentEditsFilterType.goodfaithGroup + WMFRecentEditsFilterType.damagingGroup)
        if !included.isDisjoint(with: oresGroup) {
            list.append("oresreview")
        }

        return list.joined(separator: "|")
    }

    // MARK: - Client-side filters (ports of the Android companion functions)

    /// Ports `filterOresScores`. When a damaging/good-faith bucket is active, keep only
    /// items that have ORES and whose score falls into a selected range; drop items with
    /// no ORES. Otherwise pass through.
    func filterORESScores(_ items: [WMFRecentEdits.Item], isDamagingGroup: Bool) -> [WMFRecentEdits.Item] {
        let included = loadFilterSettings().includedTypes
        let filterGroup = isDamagingGroup ? WMFRecentEditsFilterType.damagingGroup : WMFRecentEditsFilterType.goodfaithGroup
        let selected = included.intersection(Set(filterGroup))
        guard !selected.isEmpty else { return items }

        let ranges = selected.compactMap { $0.scoreRange }

        return items.filter { item in
            let score: Float?
            if isDamagingGroup {
                score = item.oresDamaging
            } else {
                score = item.oresGoodFaith
            }
            // Items without ORES are dropped when an ORES filter is active.
            guard let score else { return false }
            return ranges.contains { score >= $0.min && score <= $0.max }
        }
    }

    /// Ports `filterUserExperience`.
    func filterUserExperience(_ items: [WMFRecentEdits.Item]) -> [WMFRecentEdits.Item] {
        let included = loadFilterSettings().includedTypes
        let group = Set(WMFRecentEditsFilterType.userExperienceGroup)
        let selected = included.intersection(group)
        guard !selected.isEmpty else { return items }

        let now = Date()
        let nonAnon = items.filter { !$0.isAnon }.filter { item in
            guard let record = userInfoCache[item.username] else { return false }
            let editsCount = record.editCount
            let diffDays = record.diffDays(from: now)
            for type in selected {
                guard let range = type.experienceRange else { continue }
                let requiredMinEdits = range.edits.min
                let requiredMaxEdits = range.edits.max
                let requiredMinDays = range.days.min
                let requiredMaxDays = range.days.max

                let qualified: Bool
                if requiredMaxEdits == -1 && requiredMaxDays == -1 { // Experienced users
                    qualified = editsCount >= requiredMinEdits && diffDays >= requiredMinDays
                } else if requiredMinEdits == 0 && requiredMinDays == 0 { // Newcomers
                    qualified = (requiredMinEdits...requiredMaxEdits).contains(editsCount) && (Int64(requiredMinDays)...Int64(requiredMaxDays)).contains(diffDays)
                } else { // Learners
                    qualified = true
                }
                if qualified { return true }
            }
            return false
        }
        let anon = items.filter { $0.isAnon }
        return nonAnon + anon
    }

    /// Ports `filterUserRegistration`.
    func filterUserRegistration(_ items: [WMFRecentEdits.Item]) -> [WMFRecentEdits.Item] {
        let included = loadFilterSettings().includedTypes
        let registrationGroup = WMFRecentEditsFilterType.userRegistrationGroup
        let experienceGroup = Set(WMFRecentEditsFilterType.userExperienceGroup)

        let containsAllRegistration = registrationGroup.allSatisfy { included.contains($0) }
        let anonAndExperience = included.contains(.unregistered) && !included.isDisjoint(with: experienceGroup)

        // 1. Skip when: both anon and non-anon selected; or anon and user experiences selected.
        if !containsAllRegistration && !anonAndExperience {
            // 2. Filter to only anon items when only "UNREGISTERED" selected.
            if included.contains(.unregistered) {
                return items.filter { $0.isAnon }
            }
            // 3. Otherwise filter to only non-anon items.
            return items.filter { !$0.isAnon }
        }
        return items
    }

    // MARK: - Patrol eligibility (ports SuggestedEditsTasksFragmentViewModel)

    public func fetchPatrolEligibility(project: WMFProject, completion: @escaping (Result<WMFPatrolEligibility, Error>) -> Void) {

        guard let service else {
            completion(.failure(WMFDataControllerError.mediaWikiServiceUnavailable))
            return
        }

        guard let url = URL.mediaWikiAPIURL(project: project) else {
            completion(.failure(WMFDataControllerError.failureCreatingRequestURL))
            return
        }

        let parameters: [String: Any] = [
            "action": "query",
            "meta": "userinfo",
            "uiprop": "rights|groups|editcount|registrationdate|blockinfo",
            "errorsuselocal": "1",
            "errorformat": "html",
            "format": "json",
            "formatversion": "2"
        ]

        let request = WMFMediaWikiServiceRequest(url: url, method: .GET, backend: .mediaWiki, parameters: parameters)
        service.performDecodableGET(request: request) { (result: Result<UserInfoAPIResponse, Error>) in
            switch result {
            case .success(let response):
                guard let userInfo = response.query?.userInfo else {
                    completion(.failure(WMFDataControllerError.unexpectedResponse))
                    return
                }

                let editCount = userInfo.editCount ?? -1
                let hasRollback = (userInfo.rights ?? []).contains("rollback")
                let isSysop = (userInfo.groups ?? []).contains("sysop")
                let isBlocked = userInfo.blockid != nil

                let isEligible: Bool
                if project.languageCode == "ig" {
                    // Igbo: 500+ edits and 30+ days of tenure.
                    var tenureOK = false
                    if let regDate = userInfo.registrationDateValue {
                        tenureOK = regDate.addingTimeInterval(30 * 24 * 60 * 60) < Date()
                    }
                    isEligible = editCount >= 500 && tenureOK
                } else {
                    isEligible = hasRollback || isSysop
                }

                let eligibility = WMFPatrolEligibility(isEligible: isEligible && !isBlocked, isBlocked: isBlocked, editCount: editCount, hasRollbackRights: hasRollback, isSysop: isSysop)
                completion(.success(eligibility))

            case .failure(let error):
                completion(.failure(WMFDataControllerError.serviceError(error)))
            }
        }
    }

    // MARK: - Revert-candidate cache (ports EditingSuggestionsProvider)

    /// Ports `populateRevertCandidateCache`: seed the deque from the tapped item and
    /// everything newer than it. `items` should be the sub-list `[0...tappedIndex]`.
    public func populateRevertCandidateCache(project: WMFProject, items: [WMFRecentEdits.Item]) {
        candidateLock.lock()
        defer { candidateLock.unlock() }

        revertCandidateLang = project.languageCode ?? ""
        revertCandidateCache.removeAll()
        revertCandidateLastRevID = 0

        for item in items {
            revertCandidateCache.insert(item, at: 0) // addFirst
            if item.revisionID > revertCandidateLastRevID {
                revertCandidateLastRevID = item.revisionID
                revertCandidateLastTimestamp = item.timestamp
            }
        }
    }

    /// Ports `getNextRevertCandidate`: pop the next cached candidate, or fetch newer
    /// changes (from the last recorded timestamp) until one is available. Uses a bounded
    /// async retry with backoff rather than Android's blocking `Thread.sleep`.
    public func nextRevertCandidate(project: WMFProject, maxRetries: Int = 8, completion: @escaping (Result<WMFRecentEdits.Item, Error>) -> Void) {

        candidateLock.lock()
        let lang = project.languageCode ?? ""
        if revertCandidateLang != lang {
            revertCandidateCache.removeAll()
            revertCandidateLastRevID = 0
        }
        revertCandidateLang = lang

        if !revertCandidateCache.isEmpty {
            let item = revertCandidateCache.removeFirst()
            candidateLock.unlock()
            completion(.success(item))
            return
        }
        candidateLock.unlock()

        fetchNextCandidateFromNetwork(project: project, retriesRemaining: maxRetries, completion: completion)
    }

    private func fetchNextCandidateFromNetwork(project: WMFProject, retriesRemaining: Int, completion: @escaping (Result<WMFRecentEdits.Item, Error>) -> Void) {

        // If we have been reset, fetch a few *older* changes; otherwise fetch *newer*
        // changes starting from the last recorded timestamp.
        candidateLock.lock()
        let lastRevID = revertCandidateLastRevID
        let lastTimestamp = revertCandidateLastTimestamp
        candidateLock.unlock()

        let direction = lastRevID == 0 ? "older" : "newer"
        let start = lastRevID == 0 ? Date() : lastTimestamp

        fetchRecentEdits(project: project, startTimestamp: start, direction: direction) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let recentEdits):
                self.candidateLock.lock()

                let filtered = recentEdits.items.sorted { $0.revisionID < $1.revisionID }
                let all = recentEdits.unfilteredItems

                var maxRevID: UInt = 0
                for candidate in all {
                    if candidate.revisionID > maxRevID { maxRevID = candidate.revisionID }
                    if candidate.timestamp > self.revertCandidateLastTimestamp {
                        self.revertCandidateLastTimestamp = candidate.timestamp
                    }
                }
                for candidate in filtered where candidate.revisionID > self.revertCandidateLastRevID {
                    self.revertCandidateCache.append(candidate)
                }
                if maxRevID > self.revertCandidateLastRevID {
                    self.revertCandidateLastRevID = maxRevID
                }

                if !self.revertCandidateCache.isEmpty {
                    let item = self.revertCandidateCache.removeFirst()
                    self.candidateLock.unlock()
                    completion(.success(item))
                    return
                }
                self.candidateLock.unlock()

                // Nothing new yet — retry with backoff until data comes in.
                if retriesRemaining > 0 {
                    DispatchQueue.global().asyncAfter(deadline: .now() + 3.0) {
                        self.fetchNextCandidateFromNetwork(project: project, retriesRemaining: retriesRemaining - 1, completion: completion)
                    }
                } else {
                    completion(.failure(WMFRecentEditsDataControllerError.noCandidateAvailable))
                }

            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
}

// MARK: - Errors

public enum WMFRecentEditsDataControllerError: Error {
    case noCandidateAvailable
}

// MARK: - Internal user-info record

struct UserInfoRecord {
    let name: String
    let editCount: Int
    let registrationDate: Date?

    /// Days between registration and `now`, mirroring Android's `diffDays`.
    func diffDays(from now: Date) -> Int64 {
        guard let registrationDate else { return 0 }
        let seconds = now.timeIntervalSince(registrationDate)
        return Int64(seconds / (24 * 60 * 60))
    }
}

// MARK: - Private API response models

private extension WMFRecentEditsDataController {

    struct RecentChangesAPIResponse: Decodable {
        struct Query: Decodable {
            let recentChanges: [RecentChange]?
            enum CodingKeys: String, CodingKey {
                case recentChanges = "recentchanges"
            }
        }

        struct Continuation: Decodable {
            let rcContinue: String?
            enum CodingKeys: String, CodingKey {
                case rcContinue = "rccontinue"
            }
        }

        let query: Query?
        let continuation: Continuation?
        let errors: [WMFMediaWikiError]?

        enum CodingKeys: String, CodingKey {
            case query
            case continuation = "continue"
            case errors
        }

        struct RecentChange: Decodable {
            let title: String
            let pageID: Int
            let curRev: UInt
            let revFrom: UInt
            let rcid: UInt
            let user: String
            let anon: Bool
            let bot: Bool
            let isNew: Bool
            let minor: Bool
            let oldLen: Int
            let newLen: Int
            let timestamp: String
            let parsedComment: String
            let comment: String?
            let tags: [String]?
            let oresDamaging: Float?
            let oresGoodFaith: Float?

            enum CodingKeys: String, CodingKey {
                case title, user, anon, bot, minor, timestamp, comment, tags
                case pageID = "pageid"
                case curRev = "revid"
                case revFrom = "old_revid"
                case rcid
                case isNew = "new"
                case oldLen = "oldlen"
                case newLen = "newlen"
                case parsedComment = "parsedcomment"
                case oresScores = "oresscores"
            }

            struct ORESScores: Codable {
                struct Score: Codable {
                    let trueProb: Float?
                    enum CodingKeys: String, CodingKey {
                        case trueProb = "true"
                    }
                }
                let damaging: Score?
                let goodfaith: Score?
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                title = (try? container.decode(String.self, forKey: .title)) ?? ""
                pageID = (try? container.decode(Int.self, forKey: .pageID)) ?? 0
                curRev = (try? container.decode(UInt.self, forKey: .curRev)) ?? 0
                revFrom = (try? container.decode(UInt.self, forKey: .revFrom)) ?? 0
                rcid = (try? container.decode(UInt.self, forKey: .rcid)) ?? 0
                user = (try? container.decode(String.self, forKey: .user)) ?? ""
                anon = (try? container.decode(Bool.self, forKey: .anon)) ?? false
                bot = (try? container.decode(Bool.self, forKey: .bot)) ?? false
                isNew = (try? container.decode(Bool.self, forKey: .isNew)) ?? false
                minor = (try? container.decode(Bool.self, forKey: .minor)) ?? false
                oldLen = (try? container.decode(Int.self, forKey: .oldLen)) ?? 0
                newLen = (try? container.decode(Int.self, forKey: .newLen)) ?? 0
                timestamp = (try? container.decode(String.self, forKey: .timestamp)) ?? ""
                parsedComment = (try? container.decode(String.self, forKey: .parsedComment)) ?? ""
                comment = try? container.decode(String.self, forKey: .comment)
                tags = try? container.decode([String].self, forKey: .tags)

                // `oresscores` is an object when present, or an empty array/absent when the
                // wiki has no ORES. Decoding the keyed struct fails for the array case,
                // which `try?` converts to nil (no ORES) — mirroring Android's guard.
                let ores = try? container.decode(ORESScores.self, forKey: .oresScores)
                oresDamaging = ores?.damaging?.trueProb
                oresGoodFaith = ores?.goodfaith?.trueProb
            }
        }
    }

    struct UsersAPIResponse: Codable {
        struct Query: Codable {
            let users: [User]?
        }
        struct User: Codable {
            let name: String
            let editCount: Int?
            let registration: String?
            let registrationDateString: String?

            enum CodingKeys: String, CodingKey {
                case name
                case editCount = "editcount"
                case registration
                case registrationDateString = "registrationdate"
            }

            var registrationDate: Date? {
                if let registrationDateString, let date = DateFormatter.mediaWikiAPIDateFormatter.date(from: registrationDateString) {
                    return date
                }
                if let registration, let date = DateFormatter.mediaWikiAPIDateFormatter.date(from: registration) {
                    return date
                }
                return nil
            }
        }
        let query: Query?
        let errors: [WMFMediaWikiError]?
    }

    struct UserInfoAPIResponse: Codable {
        struct Query: Codable {
            let userInfo: UserInfo?
            enum CodingKeys: String, CodingKey {
                case userInfo = "userinfo"
            }
        }
        struct UserInfo: Codable {
            let id: Int?
            let name: String?
            let editCount: Int?
            let registrationDateString: String?
            let groups: [String]?
            let rights: [String]?
            let blockid: Int?

            enum CodingKeys: String, CodingKey {
                case id, name, groups, rights, blockid
                case editCount = "editcount"
                case registrationDateString = "registrationdate"
            }

            var registrationDateValue: Date? {
                guard let registrationDateString else { return nil }
                return DateFormatter.mediaWikiAPIDateFormatter.date(from: registrationDateString)
            }
        }
        let query: Query?
    }
}

// MARK: - Mapping to public model

private extension WMFRecentEditsDataController.RecentChangesAPIResponse.RecentChange {
    func item(project: WMFProject) -> WMFRecentEdits.Item? {
        guard let timestampDate = DateFormatter.mediaWikiAPIDateFormatter.date(from: timestamp) else {
            return nil
        }
        return WMFRecentEdits.Item(
            title: title,
            pageID: pageID,
            revisionID: curRev,
            oldRevisionID: revFrom,
            rcid: rcid,
            username: user,
            isAnon: anon,
            isBot: bot,
            isMinor: minor,
            isNew: isNew,
            timestamp: timestampDate,
            parsedComment: parsedComment,
            comment: comment ?? "",
            tags: tags ?? [],
            byteLength: newLen,
            oldByteLength: oldLen,
            oresDamaging: oresDamaging,
            oresGoodFaith: oresGoodFaith,
            project: project)
    }
}
