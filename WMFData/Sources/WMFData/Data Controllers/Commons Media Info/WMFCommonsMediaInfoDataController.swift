import Foundation

/// Data controller responsible for reading and writing structured MediaInfo captions (labels)
/// for Commons media files.
///
/// A "caption" on Commons is a language-specific MediaInfo `label`, distinct from the file page's
/// wikitext description (`extmetadata.ImageDescription`). Captions are written with the Wikibase
/// `action=wbsetlabel` API against the Commons wiki, and read with `action=wbgetentities`.
///
/// This mirrors the Android app's `Service.postLabelEdit` / `getEntitiesByTitleSuspend` contract.
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

    public enum WMFCommonsMediaInfoError: Error {
        case mediaWikiServiceUnavailable
        case failureCreatingRequestURL
        case unexpectedResponse
        case invalidFileTitle
        case serviceError(Error)
    }

    // MARK: - Response Models (internal for @testable access)

    struct CaptionPublishResponse: Decodable {
        struct Entity: Decodable {
            let lastrevid: Int?
        }
        let entity: Entity?
        let success: Int?
    }

    struct EntitiesResponse: Decodable {
        struct Entity: Decodable {
            struct Label: Decodable {
                let language: String
                let value: String
            }
            let labels: [String: Label]?
            let lastrevid: Int?
        }
        let entities: [String: Entity]?
    }

    // MARK: - Properties

    var service = WMFDataEnvironment.current.mediaWikiService

    /// Captions always live on the Commons wiki, regardless of the article's wiki.
    private let project: WMFProject = .commons

    /// Commons `site` parameter expected by the Wikibase API.
    static let commonsSiteName = "commonswiki"

    public init() { }

    // MARK: - Read Captions

    /// Fetches the existing MediaInfo caption labels for a Commons file.
    ///
    /// - Parameters:
    ///   - fileTitle: The file title, with or without the `File:` prefix.
    ///   - languageCode: Optional. When provided, only that language's label is requested.
    ///   - completion: A dictionary of `languageCode -> caption value`. An empty dictionary means
    ///     the file has no caption in the requested language(s) yet.
    public func fetchCaptions(fileTitle: String, languageCode: String? = nil, completion: @escaping (Result<[String: String], Error>) -> Void) {

        guard let service else {
            completion(.failure(WMFCommonsMediaInfoError.mediaWikiServiceUnavailable))
            return
        }

        guard let url = URL.mediaWikiAPIURL(project: project) else {
            completion(.failure(WMFCommonsMediaInfoError.failureCreatingRequestURL))
            return
        }

        let parameters = Self.fetchParameters(fileTitle: fileTitle, languageCode: languageCode)
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

    /// Convenience helper to fetch the caption value for a single language.
    /// Returns `nil` when there is no caption in that language yet.
    public func fetchCaption(fileTitle: String, languageCode: String, completion: @escaping (Result<String?, Error>) -> Void) {
        fetchCaptions(fileTitle: fileTitle, languageCode: languageCode) { result in
            switch result {
            case .success(let labels):
                completion(.success(labels[languageCode]))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    // MARK: - Write Caption

    /// Publishes a structured caption (MediaInfo label) for a Commons file via `action=wbsetlabel`.
    ///
    /// Important parity note (matches Android bug fix `bffdf572f2`, 2024-12-16): the caption is
    /// submitted using the selected `languageCode` **directly**. We must NOT normalize the language
    /// via a `siteinfo` lookup the way article/Wikidata descriptions do, or captions get saved in the
    /// wrong language.
    ///
    /// - Parameters:
    ///   - fileTitle: The file title, with or without the `File:` prefix.
    ///   - languageCode: The caption's language code, used verbatim (e.g. "en").
    ///   - caption: The caption text to save.
    ///   - editType: `.add` for a first label, `.translate` for translating an existing one. Drives the edit tag.
    ///   - additionalTags: Extra edit tags to apply (e.g. `.appSuggestedEdit` when launched from Suggested Edits).
    ///   - summary: Optional edit summary.
    ///   - completion: The publish result, or an error. Blocked / abuse-filter errors are surfaced as
    ///     `MediaWikiFetcherError.mediaWikiAPIResponseError` by the underlying service.
    public func publishCaption(fileTitle: String, languageCode: String, caption: String, editType: CaptionEditType, additionalTags: [WMFEditTag] = [], summary: String? = nil, completion: @escaping (Result<CaptionPublishResult, Error>) -> Void) {

        guard let service else {
            completion(.failure(WMFCommonsMediaInfoError.mediaWikiServiceUnavailable))
            return
        }

        guard let url = URL.mediaWikiAPIURL(project: project) else {
            completion(.failure(WMFCommonsMediaInfoError.failureCreatingRequestURL))
            return
        }

        let parameters = Self.publishParameters(fileTitle: fileTitle, languageCode: languageCode, caption: caption, editType: editType, additionalTags: additionalTags, summary: summary)

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

    // MARK: - Parameter Builders (pure functions, unit tested)

    /// Ensures the file title carries the `File:` namespace prefix expected by the API.
    static func normalizedFileTitle(_ rawTitle: String) -> String {
        let trimmed = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("file:") {
            return trimmed
        }
        return "File:\(trimmed)"
    }

    /// Builds the ordered list of edit tags applied to a caption edit.
    static func editTags(for editType: CaptionEditType, additionalTags: [WMFEditTag]) -> [WMFEditTag] {
        var tags: [WMFEditTag] = [editType.editTag]
        for tag in additionalTags where !tags.contains(tag) {
            tags.append(tag)
        }
        return tags
    }

    /// Builds the `action=wbsetlabel` request body. All values are `String` so the request can be
    /// posted as a form body by the MediaWiki service.
    static func publishParameters(fileTitle: String, languageCode: String, caption: String, editType: CaptionEditType, additionalTags: [WMFEditTag], summary: String?) -> [String: String] {

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

    /// Builds the `action=wbgetentities` query for reading caption labels.
    static func fetchParameters(fileTitle: String, languageCode: String?) -> [String: Any] {
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

    /// Flattens the first MediaInfo entity's labels into a `languageCode -> value` dictionary.
    static func labels(from response: EntitiesResponse) -> [String: String] {
        guard let entity = response.entities?.values.first, let labels = entity.labels else {
            return [:]
        }
        return labels.mapValues { $0.value }
    }
}
