import Foundation

/// Data controller for the hybrid (lexical + semantic) search A/B/C experiment.
/// Mirrors the Android implementation (HybridSearchAbCTest + SemanticSearchService).
public final class WMFHybridSearchDataController {

    // MARK: - Nested Types

    public enum GroupName: String {
        case control
        case lexicalSemantic
        case semanticLexical
    }

    // MARK: - Properties

    public static let shared = WMFHybridSearchDataController()

    /// Plain UserDefaults keys, readable from launch arguments (test/dev seams).
    static let bucketOverrideUserDefaultsKey = "WMFHybridSearchBucketOverride"
    static let supportedLanguagesOverrideUserDefaultsKey = "WMFHybridSearchSupportedLanguagesOverride"
    static let semanticSearchBaseURLUserDefaultsKey = "WMFSemanticSearchBaseURL"

    private static let defaultSemanticSearchBaseURLString = "https://semantic-search.wmcloud.org/"
    private static let defaultSupportedLanguages = ["el", "fr"]
    private static let experimentPercentage = 33

    private let service: WMFService?
    private let experimentStore: WMFKeyValueStore?
    private var assignmentCache: WMFExperimentsDataController.BucketValue?

    private var userDefaultsStore: WMFKeyValueStore? { WMFDataEnvironment.current.userDefaultsStore }

    // This setup allows us to try instantiation multiple times in case the first attempt fails (like for example, if sharedCacheStore is not available yet).
    private var _experimentsDataController: WMFExperimentsDataController?
    private var experimentsDataController: WMFExperimentsDataController? {
        if _experimentsDataController == nil,
           let store = experimentStore ?? WMFDataEnvironment.current.sharedCacheStore {
            _experimentsDataController = WMFExperimentsDataController(store: store)
        }
        return _experimentsDataController
    }

    // MARK: - Lifecycle

    public init(service: WMFService? = WMFDataEnvironment.current.basicService,
                experimentStore: WMFKeyValueStore? = WMFDataEnvironment.current.sharedCacheStore) {
        self.service = service
        self.experimentStore = experimentStore
    }

    // MARK: - Local Settings

    public var isHybridSearchOnboardingShown: Bool {
        get { (try? userDefaultsStore?.load(key: WMFUserDefaultsKey.hybridSearchOnboardingShown.rawValue)) ?? false }
        set { try? userDefaultsStore?.save(key: WMFUserDefaultsKey.hybridSearchOnboardingShown.rawValue, value: newValue) }
    }

    public var isHybridSearchEnabled: Bool {
        get { (try? userDefaultsStore?.load(key: WMFUserDefaultsKey.hybridSearchEnabled.rawValue)) ?? false }
        set { try? userDefaultsStore?.save(key: WMFUserDefaultsKey.hybridSearchEnabled.rawValue, value: newValue) }
    }

    /// Stands in for Android's remote config `hybridSearchLanguages`. Stored in standard UserDefaults so it can be set via launch arguments.
    public var supportedLanguagesOverride: [String]? {
        get {
            if let array = UserDefaults.standard.stringArray(forKey: Self.supportedLanguagesOverrideUserDefaultsKey) {
                return array
            }

            if let commaSeparated = UserDefaults.standard.string(forKey: Self.supportedLanguagesOverrideUserDefaultsKey) {
                return commaSeparated.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            }

            return nil
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.supportedLanguagesOverrideUserDefaultsKey)
        }
    }

    // MARK: - Experiment

    /// Android's HybridSearchAbCTest reads this from remote config (default true). iOS has no equivalent remote flag yet, so the test is always considered active.
    private var isTestActive: Bool {
        return true
    }

    public var assignedGroupName: String {
        return assignedGroup.rawValue
    }

    private var assignedGroup: GroupName {
        if let overrideValue = UserDefaults.standard.string(forKey: Self.bucketOverrideUserDefaultsKey),
           let overrideGroup = GroupName(rawValue: overrideValue) {
            return overrideGroup
        }

        if let assignmentCache {
            return groupName(for: assignmentCache)
        }

        guard let experimentsDataController else {
            return .control
        }

        let bucket = (try? experimentsDataController.determineBucketForExperiment(.hybridSearch, withPercentage: Self.experimentPercentage)) ?? .hybridSearchControl
        assignmentCache = bucket
        return groupName(for: bucket)
    }

    private func groupName(for bucket: WMFExperimentsDataController.BucketValue) -> GroupName {
        switch bucket {
        case .hybridSearchLexicalSemantic:
            return .lexicalSemantic
        case .hybridSearchSemanticLexical:
            return .semanticLexical
        default:
            return .control
        }
    }

    public func isTestGroupUser() -> Bool {
        return assignedGroup != .control
    }

    public func isLanguageSupported(_ languageCode: String?) -> Bool {
        guard let languageCode else {
            return false
        }

        let supportedLanguages = supportedLanguagesOverride ?? Self.defaultSupportedLanguages
        return supportedLanguages.contains { $0.caseInsensitiveCompare(languageCode) == .orderedSame }
    }

    public func shouldShowOnboarding(languageCode: String?) -> Bool {
        return isTestActive && isTestGroupUser() && isLanguageSupported(languageCode) && !isHybridSearchOnboardingShown
    }

    public func isHybridSearchActive(languageCode: String?) -> Bool {
        return isTestActive && isHybridSearchEnabled && isTestGroupUser() && isLanguageSupported(languageCode)
    }

    public func shouldInstrument(languageCode: String?) -> Bool {
        return isTestActive && isLanguageSupported(languageCode)
    }

    // MARK: - Semantic Search

    public func fetchSemanticSearchResults(query: String, languageCode: String, count: Int = 3) async throws -> [WMFSemanticSearchResult] {
        guard let service else {
            throw WMFDataControllerError.basicServiceUnavailable
        }

        guard let url = semanticSearchURL() else {
            throw WMFDataControllerError.failureCreatingRequestURL
        }

        let parameters: [String: Any] = [
            "query": query,
            "k": String(count),
            "table": Self.semanticSearchTableName(for: languageCode),
            "include_text": "true"
        ]

        let request = WMFBasicServiceRequest(url: url, method: .GET, parameters: parameters, acceptType: .json)

        let response: WMFSemanticSearchResponse = try await withCheckedThrowingContinuation { continuation in
            service.performDecodableGET(request: request) { (result: Result<WMFSemanticSearchResponse, Error>) in
                continuation.resume(with: result)
            }
        }

        return response.results
    }

    /// Semantic search via the MediaWiki full-text search API (Android `fullTextSearchResponse`),
    /// used for every supported language except Greek: the standard full-text search request with
    /// `cirrusSemanticSearch=true`, snippet + sectiontitle generator props, and the `x-search-id`
    /// response header surfaced for analytics.
    public func fetchSemanticSearchResultsViaFullTextSearch(query: String, languageCode: String, count: Int = 3) async throws -> WMFSemanticFullTextSearchResults {
        guard let service else {
            throw WMFDataControllerError.basicServiceUnavailable
        }

        let project = WMFProject.wikipedia(WMFLanguage(languageCode: languageCode, languageVariantCode: nil))
        guard let url = URL.mediaWikiAPIURL(project: project) else {
            throw WMFDataControllerError.failureCreatingRequestURL
        }

        // Mirrors Android Service.fullTextSearchResponse.
        let parameters: [String: Any] = [
            "action": "query",
            "format": "json",
            "formatversion": "2",
            "converttitles": "",
            "prop": "description|pageimages|pageprops|coordinates|info",
            "ppprop": "mainpage|disambiguation",
            "generator": "search",
            "gsrnamespace": "0",
            "gsrwhat": "text",
            "inprop": "varianttitles|displaytitle",
            "gsrinfo": "",
            "gsrprop": "redirecttitle|snippet|sectiontitle",
            "piprop": "thumbnail",
            "pilicense": "any",
            "pithumbsize": "320",
            "gsrsearch": query,
            "gsrlimit": String(count),
            "gsroffset": "0",
            "cirrusSemanticSearch": "true"
        ]

        let request = WMFBasicServiceRequest(url: url, method: .GET, parameters: parameters, acceptType: .json)

        let (response, httpResponse): (WMFMediaWikiFullTextSearchResponse, HTTPURLResponse?) = try await withCheckedThrowingContinuation { continuation in
            service.performDecodableGET(request: request) { (result: Result<(WMFMediaWikiFullTextSearchResponse, HTTPURLResponse?), Error>) in
                continuation.resume(with: result)
            }
        }

        let pages = (response.query?.pages ?? []).sorted { ($0.index ?? Int.max) < ($1.index ?? Int.max) }
        let results = pages.map { page in
            WMFSemanticFullTextSearchResults.Result(
                title: page.title,
                snippetHTML: page.snippet ?? "",
                sectionTitle: page.sectiontitle,
                description: page.description,
                thumbnailURL: page.thumbnail?.source.flatMap { URL(string: $0) }
            )
        }
        let xSearchId = httpResponse?.value(forHTTPHeaderField: "x-search-id") ?? ""

        return WMFSemanticFullTextSearchResults(results: results, xSearchId: xSearchId)
    }

    private func semanticSearchURL() -> URL? {
        let baseURLString = UserDefaults.standard.string(forKey: Self.semanticSearchBaseURLUserDefaultsKey) ?? Self.defaultSemanticSearchBaseURLString
        return URL(string: baseURLString)?.appendingPathComponent("api/search")
    }

    private static func semanticSearchTableName(for languageCode: String) -> String {
        switch languageCode {
        case "el":
            return "elwiki_sections"
        default:
            return ""
        }
    }

    /// Converts the raw wikitext emphasis markup in semantic search section text to HTML, and strips empty parentheses.
    /// Faithful port of Android's SearchResultsViewModel.postProcessSectionText. TODO: remove this when server-side parsing is done.
    static func postProcessSectionText(_ text: String) -> String {
        return text
            .replacingOccurrences(of: #"\([\s,.;]*\)"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "(?s)'''(.*?)'''", with: "<b>$1</b>", options: .regularExpression)
            .replacingOccurrences(of: "(?s)''(.*?)''", with: "<i>$1</i>", options: .regularExpression)
    }
}

// MARK: - Response Models

public struct WMFSemanticSearchResult: Decodable {

    /// Raw page title as returned by the API (with underscores).
    public let rawTitle: String
    public let sectionHeader: String
    public let sectionIndex: Int
    public let sectionText: String
    public let url: String

    enum CodingKeys: String, CodingKey {
        case rawTitle = "page_title"
        case sectionHeader = "section_header"
        case sectionIndex = "section_index"
        case sectionText = "section_text"
        case url
    }

    /// Page title for display, with underscores replaced by spaces.
    public var title: String {
        return rawTitle.replacingOccurrences(of: "_", with: " ")
    }

    /// Section text snippet with wikitext emphasis markup converted to HTML.
    public var processedSnippetHTML: String {
        return WMFHybridSearchDataController.postProcessSectionText(sectionText)
    }

    public init(rawTitle: String, sectionHeader: String, sectionIndex: Int, sectionText: String, url: String) {
        self.rawTitle = rawTitle
        self.sectionHeader = sectionHeader
        self.sectionIndex = sectionIndex
        self.sectionText = sectionText
        self.url = url
    }
}

/// Semantic results from the MediaWiki full-text search API (`cirrusSemanticSearch=true`),
/// the non-Greek semantic path introduced by Android 6240fa0d02.
public struct WMFSemanticFullTextSearchResults {

    public struct Result {
        public let title: String
        /// Cirrus search snippet (already HTML).
        public let snippetHTML: String
        /// Raw section title from the API (spaces, not underscores), if the match was within a section.
        public let sectionTitle: String?
        public let description: String?
        public let thumbnailURL: URL?

        /// Section anchor fragment: the section title with spaces replaced by underscores
        /// (Android `StringUtil.addUnderscores` parity).
        public var fragment: String? {
            guard let sectionTitle, !sectionTitle.isEmpty else {
                return nil
            }
            return sectionTitle.replacingOccurrences(of: " ", with: "_")
        }

        public init(title: String, snippetHTML: String, sectionTitle: String?, description: String?, thumbnailURL: URL?) {
            self.title = title
            self.snippetHTML = snippetHTML
            self.sectionTitle = sectionTitle
            self.description = description
            self.thumbnailURL = thumbnailURL
        }
    }

    public let results: [Result]
    /// Value of the `x-search-id` response header, or empty when absent.
    public let xSearchId: String

    public init(results: [Result], xSearchId: String) {
        self.results = results
        self.xSearchId = xSearchId
    }
}

struct WMFMediaWikiFullTextSearchResponse: Decodable {

    struct Query: Decodable {
        let pages: [Page]?
    }

    struct Page: Decodable {
        let title: String
        let index: Int?
        let snippet: String?
        let sectiontitle: String?
        let description: String?
        let thumbnail: Thumbnail?
    }

    struct Thumbnail: Decodable {
        let source: String?
    }

    let query: Query?
}

struct WMFSemanticSearchResponse: Decodable {
    let languageCode: String
    let query: String
    let results: [WMFSemanticSearchResult]

    enum CodingKeys: String, CodingKey {
        case languageCode = "language_code"
        case query
        case results = "semantic_search_results"
    }
}
