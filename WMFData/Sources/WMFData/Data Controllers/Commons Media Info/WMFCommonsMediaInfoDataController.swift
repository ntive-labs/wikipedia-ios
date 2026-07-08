import Foundation

/// Data controller responsible for reading and writing structured MediaInfo metadata (captions and
/// "depicts" tags) for Commons media files. This is the iOS port of Android's
/// `FilePageViewModel.loadImageInfo()` + `ImageTagsProvider` + `SuggestedEditsImageTagsViewModel`.
///
/// Reads (Commons `commons.wikimedia.org`, unless a non-Commons fallback is used):
/// - `action=query&prop=imageinfo|entityterms` — image info + the MediaInfo caption (label).
/// - `action=query&meta=userinfo&prop=info&inprop=protection` — edit-protection state.
/// - `action=wbgetclaims&property=P180` (Commons) + `action=query&prop=entityterms` (Wikidata) —
///   the "depicts" tags resolved to Wikidata labels.
///
/// Writes:
/// - `action=wbsetlabel` (Commons) — add / translate a caption.
/// - `action=wbeditentity` (Commons) — add P180 depicts statements.
///
/// The caption contract mirrors Android `Service.postLabelEdit`; the depicts contract mirrors
/// `SuggestedEditsImageTagsViewModel.publishImageTags`.
public final class WMFCommonsMediaInfoDataController {

    // MARK: - Nested Types

    /// Whether the caption edit adds the first label in the user's language, or translates an
    /// existing label into another language. Determines the edit tag applied to the edit.
    public enum CaptionEditType: Sendable {
        case add
        case translate

        var editTag: WMFEditTag {
            switch self {
            case .add:
                return .appImageCaptionAdd
            case .translate:
                return .appImageCaptionTranslate
            }
        }
    }

    /// Result of a successful caption publish.
    public struct CaptionPublishResult: Sendable {
        public let newRevisionID: Int?
        public let succeeded: Bool
    }

    /// Result of a successful depicts (P180) publish.
    public struct DepictsPublishResult: Sendable {
        public let newRevisionID: Int?
        public let succeeded: Bool
    }

    public enum WMFCommonsMediaInfoError: Error {
        case mediaWikiServiceUnavailable
        case failureCreatingRequestURL
        case unexpectedResponse
        case invalidFileTitle
        case noImageInfo
        case serviceError(Error)
    }

    // MARK: - Properties

    var service = WMFDataEnvironment.current.mediaWikiService

    /// Structured metadata always lives on the Commons wiki, regardless of the article's wiki.
    private let commonsProject: WMFProject = .commons
    private let wikidataProject: WMFProject = .wikidata

    /// Commons `site` parameter expected by the Wikibase API.
    static let commonsSiteName = "commonswiki"

    /// Android's `Service.PREFERRED_THUMB_SIZE`.
    static let preferredThumbSize = 330

    public init() { }

    // MARK: - Orchestrated Media Info Load (parity: FilePageViewModel.loadImageInfo)

    /// Loads the full media-info payload for a Commons file, composing image info + caption,
    /// edit-protection, and depicts tags — mirroring Android's `FilePageViewModel.loadImageInfo()`.
    ///
    /// - Parameters:
    ///   - fileTitle: The file title, with or without the `File:` prefix.
    ///   - pageLanguageCode: The language of the surface the file was opened from (used for caption /
    ///     metadata language, matching Android's `pageTitle.wikiSite.languageCode`).
    ///   - allowEdit: Whether the launching context permits editing (Android's `allowEdit`).
    public func fetchMediaInfo(fileTitle: String, pageLanguageCode: String, allowEdit: Bool = true) async throws -> WMFCommonsMediaInfo {

        let entityLang = Self.uselang(for: pageLanguageCode)

        // 1. Image info + entity terms (caption) from Commons.
        let imageInfoResponse = try await fetchImageInfoEntityTerms(project: commonsProject, fileTitle: fileTitle, metadataLanguage: pageLanguageCode, entityLanguage: entityLang)

        guard let firstPage = imageInfoResponse.query?.firstPage else {
            throw WMFCommonsMediaInfoError.noImageInfo
        }

        // The structured caption is the first entityterms label (Android: pageTitle.description).
        let captionValue = firstPage.entityterms?.label?.first
        let caption: WMFMediaInfoCaption? = captionValue.map { WMFMediaInfoCaption(languageCode: pageLanguageCode, value: $0) }

        guard let imageInfo = firstPage.imageinfo?.first else {
            // Parity: Android falls back to the file's own wiki when Commons has no imageinfo.
            // The gallery / lead-image entry points always resolve a Commons File: title, so we treat
            // the absence of imageinfo as "not on Commons / not editable" here.
            throw WMFCommonsMediaInfoError.noImageInfo
        }

        let isFromCommons = !firstPage.isImageShared
        let pageID = firstPage.pageid ?? 0

        // 2. + 3. Protection and depicts, in parallel (Android uses `async { }` for both).
        async let protectedResult = fetchProtection(fileTitle: fileTitle)
        async let depictsResult = fetchDepicts(pageID: pageID, wikidataLanguageCode: pageLanguageCode)

        // Android swallows depicts errors (emptyMap). Do the same so a depicts failure doesn't block
        // the whole screen.
        let depicts = (try? await depictsResult) ?? []
        let isEditProtected = (try? await protectedResult) ?? false

        let metadata = Self.metadata(from: imageInfo.extmetadata)

        return WMFCommonsMediaInfo(
            pageID: pageID,
            title: Self.normalizedFileTitle(fileTitle),
            isFromCommons: isFromCommons,
            thumbURL: imageInfo.thumburl.flatMap { URL(string: $0) },
            fullURL: imageInfo.url.flatMap { URL(string: $0) },
            mimeType: imageInfo.mime,
            thumbnailWidth: imageInfo.thumbwidth,
            thumbnailHeight: imageInfo.thumbheight,
            metadata: metadata,
            caption: caption,
            isEditProtected: isEditProtected,
            depicts: depicts,
            allowEdit: allowEdit,
            languageCode: pageLanguageCode
        )
    }

    // MARK: - Image Info + Entity Terms (read)

    func fetchImageInfoEntityTerms(project: WMFProject, fileTitle: String, metadataLanguage: String, entityLanguage: String) async throws -> ImageInfoResponse {
        guard let service else { throw WMFCommonsMediaInfoError.mediaWikiServiceUnavailable }
        guard let url = URL.mediaWikiAPIURL(project: project) else { throw WMFCommonsMediaInfoError.failureCreatingRequestURL }

        let parameters = Self.imageInfoParameters(fileTitle: fileTitle, metadataLanguage: metadataLanguage, entityLanguage: entityLanguage)
        let request = WMFMediaWikiServiceRequest(url: url, method: .GET, backend: .mediaWiki, parameters: parameters)

        return try await withCheckedThrowingContinuation { continuation in
            service.performDecodableGET(request: request) { (result: Result<ImageInfoResponse, Error>) in
                switch result {
                case .success(let response): continuation.resume(returning: response)
                case .failure(let error): continuation.resume(throwing: WMFCommonsMediaInfoError.serviceError(error))
                }
            }
        }
    }

    // MARK: - Protection (read) — parity: getProtectionWithUserInfo

    /// Returns whether the file is edit-protected for the current user, mirroring Android's
    /// `MwQueryResult.isEditProtected` (a protection entry of type `edit` whose required level is not
    /// in the user's groups).
    public func fetchProtection(fileTitle: String) async throws -> Bool {
        guard let service else { throw WMFCommonsMediaInfoError.mediaWikiServiceUnavailable }
        guard let url = URL.mediaWikiAPIURL(project: commonsProject) else { throw WMFCommonsMediaInfoError.failureCreatingRequestURL }

        let parameters = Self.protectionParameters(fileTitle: fileTitle)
        let request = WMFMediaWikiServiceRequest(url: url, method: .GET, backend: .mediaWiki, parameters: parameters)

        let response: ProtectionResponse = try await withCheckedThrowingContinuation { continuation in
            service.performDecodableGET(request: request) { (result: Result<ProtectionResponse, Error>) in
                switch result {
                case .success(let response): continuation.resume(returning: response)
                case .failure(let error): continuation.resume(throwing: WMFCommonsMediaInfoError.serviceError(error))
                }
            }
        }

        return Self.isEditProtected(from: response)
    }

    // MARK: - Depicts (read) — parity: ImageTagsProvider.getImageTags

    /// Reads the P180 "depicts" claims for a file from Commons and resolves them to Wikidata labels.
    /// Returns an empty array on any failure, matching Android's `getImageTags` (which returns
    /// `emptyMap()` on exception).
    public func fetchDepicts(pageID: Int, wikidataLanguageCode: String) async throws -> [WMFDepictsTag] {
        guard let service else { throw WMFCommonsMediaInfoError.mediaWikiServiceUnavailable }
        guard let commonsURL = URL.mediaWikiAPIURL(project: commonsProject),
              let wikidataURL = URL.mediaWikiAPIURL(project: wikidataProject) else {
            throw WMFCommonsMediaInfoError.failureCreatingRequestURL
        }

        // 1. wbgetclaims on Commons for M<pageID> / P180.
        let claimsRequest = WMFMediaWikiServiceRequest(url: commonsURL, method: .GET, backend: .mediaWiki, parameters: Self.claimsParameters(pageID: pageID))
        let claimsResponse: ClaimsResponse = try await withCheckedThrowingContinuation { continuation in
            service.performDecodableGET(request: claimsRequest) { (result: Result<ClaimsResponse, Error>) in
                switch result {
                case .success(let response): continuation.resume(returning: response)
                case .failure(let error): continuation.resume(throwing: WMFCommonsMediaInfoError.serviceError(error))
                }
            }
        }

        let ids = Self.depictsItemIDs(from: claimsResponse)
        guard !ids.isEmpty else { return [] }

        // 2. Resolve labels on Wikidata via prop=entityterms.
        let uselang = Self.uselang(for: wikidataLanguageCode)
        let termsRequest = WMFMediaWikiServiceRequest(url: wikidataURL, method: .GET, backend: .mediaWiki, parameters: Self.entityTermsParameters(ids: ids, language: uselang))
        let termsResponse: EntityTermsResponse = try await withCheckedThrowingContinuation { continuation in
            service.performDecodableGET(request: termsRequest) { (result: Result<EntityTermsResponse, Error>) in
                switch result {
                case .success(let response): continuation.resume(returning: response)
                case .failure(let error): continuation.resume(throwing: WMFCommonsMediaInfoError.serviceError(error))
                }
            }
        }

        return Self.depictsTags(ids: ids, from: termsResponse)
    }

    // MARK: - Read Captions (parity: getEntitiesByTitleSuspend)

    /// Fetches the existing MediaInfo caption labels for a Commons file.
    /// - Returns: a dictionary of `languageCode -> caption value`. Empty means no caption yet.
    public func fetchCaptions(fileTitle: String, languageCode: String? = nil, completion: @escaping (Result<[String: String], Error>) -> Void) {

        guard let service else {
            completion(.failure(WMFCommonsMediaInfoError.mediaWikiServiceUnavailable))
            return
        }
        guard let url = URL.mediaWikiAPIURL(project: commonsProject) else {
            completion(.failure(WMFCommonsMediaInfoError.failureCreatingRequestURL))
            return
        }

        let parameters = Self.captionsFetchParameters(fileTitle: fileTitle, languageCode: languageCode)
        let request = WMFMediaWikiServiceRequest(url: url, method: .GET, backend: .mediaWiki, parameters: parameters)

        service.performDecodableGET(request: request) { (result: Result<EntitiesResponse, Error>) in
            switch result {
            case .success(let response):
                completion(.success(Self.labels(from: response)))
            case .failure(let error):
                completion(.failure(WMFCommonsMediaInfoError.serviceError(error)))
            }
        }
    }

    /// Convenience helper to fetch the caption value for a single language (nil if none yet).
    public func fetchCaption(fileTitle: String, languageCode: String, completion: @escaping (Result<String?, Error>) -> Void) {
        fetchCaptions(fileTitle: fileTitle, languageCode: languageCode) { result in
            switch result {
            case .success(let labels): completion(.success(labels[languageCode]))
            case .failure(let error): completion(.failure(error))
            }
        }
    }

    // MARK: - Write Caption (parity: postLabelEdit / wbsetlabel)

    /// Publishes a structured caption (MediaInfo label) for a Commons file via `action=wbsetlabel`.
    ///
    /// The caption is submitted using the selected `languageCode` **directly** (Android bug-fix
    /// `bffdf572f2`): we must NOT normalize the language via a `siteinfo` lookup the way article /
    /// Wikidata descriptions do, or captions get saved in the wrong language.
    public func publishCaption(fileTitle: String, languageCode: String, caption: String, editType: CaptionEditType, additionalTags: [WMFEditTag] = [], summary: String? = nil, completion: @escaping (Result<CaptionPublishResult, Error>) -> Void) {

        guard let service else {
            completion(.failure(WMFCommonsMediaInfoError.mediaWikiServiceUnavailable))
            return
        }
        guard let url = URL.mediaWikiAPIURL(project: commonsProject) else {
            completion(.failure(WMFCommonsMediaInfoError.failureCreatingRequestURL))
            return
        }

        let parameters = Self.captionPublishParameters(fileTitle: fileTitle, languageCode: languageCode, caption: caption, editType: editType, additionalTags: additionalTags, summary: summary)
        let request = WMFMediaWikiServiceRequest(url: url, method: .POST, backend: .mediaWiki, tokenType: .csrf, parameters: parameters)

        service.perform(request: request) { result in
            switch result {
            case .success(let response):
                let entity = response?["entity"] as? [String: Any]
                let newRevisionID = entity?["lastrevid"] as? Int
                let successValue = response?["success"] as? Int ?? 0
                guard successValue > 0 else {
                    completion(.failure(WMFCommonsMediaInfoError.unexpectedResponse))
                    return
                }
                completion(.success(CaptionPublishResult(newRevisionID: newRevisionID, succeeded: true)))
            case .failure(let error):
                completion(.failure(WMFCommonsMediaInfoError.serviceError(error)))
            }
        }
    }

    // MARK: - Write Depicts (parity: publishImageTags / wbeditentity P180)

    /// Publishes P180 "depicts" statements for a Commons file via `action=wbeditentity`, mirroring
    /// `SuggestedEditsImageTagsViewModel.publishImageTags` exactly (claim JSON, summary, and
    /// `matags = app-image-tag-add`).
    public func publishDepicts(pageID: Int, tags: [WMFDepictsTag], completion: @escaping (Result<DepictsPublishResult, Error>) -> Void) {

        guard let service else {
            completion(.failure(WMFCommonsMediaInfoError.mediaWikiServiceUnavailable))
            return
        }
        guard let url = URL.mediaWikiAPIURL(project: commonsProject) else {
            completion(.failure(WMFCommonsMediaInfoError.failureCreatingRequestURL))
            return
        }
        guard !tags.isEmpty else {
            completion(.failure(WMFCommonsMediaInfoError.unexpectedResponse))
            return
        }

        let parameters = Self.depictsPublishParameters(pageID: pageID, tags: tags)
        let request = WMFMediaWikiServiceRequest(url: url, method: .POST, backend: .mediaWiki, tokenType: .csrf, parameters: parameters)

        service.perform(request: request) { result in
            switch result {
            case .success(let response):
                let entity = response?["entity"] as? [String: Any]
                let newRevisionID = entity?["lastrevid"] as? Int
                let successValue = response?["success"] as? Int ?? 0
                guard successValue > 0 else {
                    completion(.failure(WMFCommonsMediaInfoError.unexpectedResponse))
                    return
                }
                completion(.success(DepictsPublishResult(newRevisionID: newRevisionID, succeeded: true)))
            case .failure(let error):
                completion(.failure(WMFCommonsMediaInfoError.serviceError(error)))
            }
        }
    }

    /// Async variant of ``publishDepicts(pageID:tags:completion:)`` for use from Swift view models.
    public func publishDepicts(pageID: Int, tags: [WMFDepictsTag]) async throws -> DepictsPublishResult {
        try await withCheckedThrowingContinuation { continuation in
            publishDepicts(pageID: pageID, tags: tags) { result in
                switch result {
                case .success(let value): continuation.resume(returning: value)
                case .failure(let error): continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Helpers

    /// Ensures the file title carries the `File:` namespace prefix expected by the API.
    static func normalizedFileTitle(_ rawTitle: String) -> String {
        let trimmed = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("file:") {
            return trimmed
        }
        return "File:\(trimmed)"
    }

    /// Mirrors Android's `LanguageUtil.convertToUselangIfNeeded`. For our purposes the language code is
    /// used directly; the seam exists so future variant handling can be added in one place.
    static func uselang(for languageCode: String) -> String {
        return languageCode
    }

    // MARK: - Parameter Builders (pure functions, unit tested)

    static func imageInfoParameters(fileTitle: String, metadataLanguage: String, entityLanguage: String) -> [String: Any] {
        return [
            "action": "query",
            "prop": "imageinfo|entityterms",
            "iiprop": "timestamp|user|url|mime|extmetadata",
            "iiurlwidth": String(preferredThumbSize),
            "iiextmetadatalanguage": metadataLanguage,
            "wbetlanguage": entityLanguage,
            "titles": normalizedFileTitle(fileTitle),
            "format": "json",
            "formatversion": "2"
        ]
    }

    static func protectionParameters(fileTitle: String) -> [String: Any] {
        return [
            "action": "query",
            "meta": "userinfo",
            "prop": "info",
            "inprop": "protection",
            "uiprop": "groups",
            "titles": normalizedFileTitle(fileTitle),
            "format": "json",
            "formatversion": "2"
        ]
    }

    static func claimsParameters(pageID: Int) -> [String: Any] {
        return [
            "action": "wbgetclaims",
            "entity": "M\(pageID)",
            "property": "P180",
            "format": "json",
            "formatversion": "2"
        ]
    }

    static func entityTermsParameters(ids: [String], language: String) -> [String: Any] {
        return [
            "action": "query",
            "prop": "entityterms",
            "titles": ids.joined(separator: "|"),
            "wbetlanguage": language,
            "format": "json",
            "formatversion": "2"
        ]
    }

    static func captionsFetchParameters(fileTitle: String, languageCode: String?) -> [String: Any] {
        var parameters: [String: Any] = [
            "action": "wbgetentities",
            "sites": commonsSiteName,
            "titles": normalizedFileTitle(fileTitle),
            "props": "labels",
            "format": "json",
            "formatversion": "2"
        ]
        if let languageCode, !languageCode.isEmpty {
            parameters["languages"] = languageCode
        }
        return parameters
    }

    /// Builds the ordered list of edit tags applied to a caption edit.
    static func editTags(for editType: CaptionEditType, additionalTags: [WMFEditTag]) -> [WMFEditTag] {
        var tags: [WMFEditTag] = [editType.editTag]
        for tag in additionalTags where !tags.contains(tag) {
            tags.append(tag)
        }
        return tags
    }

    static func captionPublishParameters(fileTitle: String, languageCode: String, caption: String, editType: CaptionEditType, additionalTags: [WMFEditTag], summary: String?) -> [String: String] {
        var parameters: [String: String] = [
            "action": "wbsetlabel",
            "language": languageCode,
            "uselang": languageCode,
            "site": commonsSiteName,
            "title": normalizedFileTitle(fileTitle),
            "value": caption,
            "matags": editTags(for: editType, additionalTags: additionalTags).map { $0.rawValue }.joined(separator: ","),
            "format": "json",
            "formatversion": "2",
            "errorformat": "html",
            "errorsuselocal": "1"
        ]
        if let summary, !summary.isEmpty {
            parameters["summary"] = summary
        }
        return parameters
    }

    /// Builds the `action=wbeditentity` request body for adding P180 depicts statements.
    /// The `data` JSON and `summary` string are byte-for-byte compatible with Android's
    /// `SuggestedEditsImageTagsViewModel.publishImageTags`.
    static func depictsPublishParameters(pageID: Int, tags: [WMFDepictsTag]) -> [String: String] {
        let mID = "M\(pageID)"
        return [
            "action": "wbeditentity",
            "id": mID,
            "data": depictsClaimJSON(pageID: pageID, tags: tags),
            "summary": depictsSummary(tags: tags),
            "matags": WMFEditTag.appImageTagAdd.rawValue,
            "format": "json",
            "formatversion": "2",
            "errorformat": "html",
            "errorsuselocal": "1"
        ]
    }

    /// Builds the `{"claims":[...]}` JSON of P180 statements, mirroring Android's manual string build.
    static func depictsClaimJSON(pageID: Int, tags: [WMFDepictsTag]) -> String {
        let mID = "M\(pageID)"
        var claimStr = "{\"claims\":["
        var first = true
        for tag in tags {
            if !first { claimStr += "," }
            first = false
            claimStr += "{\"mainsnak\":" +
                "{\"snaktype\":\"value\",\"property\":\"P180\"," +
                "\"datavalue\":{\"value\":" +
                "{\"entity-type\":\"item\",\"id\":\"\(tag.wikidataID)\"}," +
                "\"type\":\"wikibase-entityid\"},\"datatype\":\"wikibase-item\"}," +
                "\"type\":\"statement\"," +
                "\"id\":\"\(mID)$\(UUID().uuidString)\"," +
                "\"rank\":\"normal\"}"
        }
        claimStr += "]}"
        return claimStr
    }

    /// Builds the `/* add-depicts: <id>|<label>, ... */` edit summary (Android parity: labels have
    /// `|` and `,` stripped).
    static func depictsSummary(tags: [WMFDepictsTag]) -> String {
        var commentStr = "/* add-depicts: "
        var first = true
        for tag in tags {
            if !first { commentStr += "," }
            first = false
            let sanitizedLabel = tag.label.replacingOccurrences(of: "|", with: "").replacingOccurrences(of: ",", with: "")
            commentStr += tag.wikidataID + "|" + sanitizedLabel
        }
        commentStr += " */"
        return commentStr
    }

    // MARK: - Response Parsing (pure functions, unit tested)

    /// Flattens the first MediaInfo entity's labels into a `languageCode -> value` dictionary.
    static func labels(from response: EntitiesResponse) -> [String: String] {
        guard let entity = response.entities?.values.first, let labels = entity.labels else {
            return [:]
        }
        return labels.mapValues { $0.value }
    }

    /// Extracts the P180 depicts item ids (Q-ids) from a wbgetclaims response.
    static func depictsItemIDs(from response: ClaimsResponse) -> [String] {
        guard let claims = response.claims?["P180"] else { return [] }
        return claims.compactMap { $0.mainsnak?.datavalue?.entityID }
    }

    /// Resolves Q-ids to `WMFDepictsTag`, preserving claim order and best-effort labels (falling back
    /// to the Q-id when no label was returned).
    static func depictsTags(ids: [String], from response: EntityTermsResponse) -> [WMFDepictsTag] {
        var labelByID: [String: String] = [:]
        for page in response.query?.pages ?? [] {
            if let title = page.title, let label = page.entityterms?.label?.first {
                labelByID[title] = label
            }
        }
        return ids.map { id in
            WMFDepictsTag(wikidataID: id, label: labelByID[id] ?? id, description: nil, isSelected: false)
        }
    }

    /// Android parity for `MwQueryResult.isEditProtected`.
    static func isEditProtected(from response: ProtectionResponse) -> Bool {
        guard let page = response.query?.firstPage else { return false }
        let groups = response.query?.userinfo?.groups ?? []
        for protection in page.protection ?? [] where protection.type == "edit" {
            if !groups.contains(protection.level) {
                return true
            }
        }
        return false
    }

    static func metadata(from extmetadata: [String: ExtMetadataValue]?) -> WMFCommonsMediaMetadata? {
        guard let extmetadata else { return nil }
        func value(_ key: String) -> String? {
            let v = extmetadata[key]?.stringValue
            return (v?.isEmpty ?? true) ? nil : v
        }
        let metadata = WMFCommonsMediaMetadata(
            imageDescription: value("ImageDescription"),
            artist: value("Artist"),
            dateTime: value("DateTimeOriginal") ?? value("DateTime"),
            credit: value("Credit"),
            licenseShortName: value("LicenseShortName"),
            licenseURL: value("LicenseUrl")
        )
        return metadata
    }
}
