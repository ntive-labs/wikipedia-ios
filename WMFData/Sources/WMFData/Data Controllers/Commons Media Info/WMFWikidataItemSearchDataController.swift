import Foundation

/// Data controller backing the "add a depicts tag" search field in the tags editor.
///
/// Ports Android's `SuggestedEditsImageTagDialog` search, which calls Wikidata
/// `action=wbsearchentities&type=item&limit=20` with the app language for both `language` and
/// `uselang`, and maps each result to an `ImageTag`.
public final class WMFWikidataItemSearchDataController {

    public enum WMFWikidataItemSearchError: Error {
        case mediaWikiServiceUnavailable
        case failureCreatingRequestURL
        case serviceError(Error)
    }

    struct SearchResponse: Decodable {
        struct Result: Decodable {
            let id: String
            let label: String?
            let description: String?
        }
        let search: [Result]?
    }

    var service = WMFDataEnvironment.current.mediaWikiService
    private let wikidataProject: WMFProject = .wikidata

    /// Android parity: `action=wbsearchentities&type=item&limit=20`.
    static let searchLimit = 20

    public init() { }

    /// Searches Wikidata items matching `term`, returning selectable depicts tags.
    /// - Parameters:
    ///   - term: The user's search text.
    ///   - languageCode: The language used for both `language` and `uselang` (Android uses
    ///     `WikipediaApp.appOrSystemLanguageCode` for both).
    public func search(term: String, languageCode: String) async throws -> [WMFDepictsTag] {
        guard let service else { throw WMFWikidataItemSearchError.mediaWikiServiceUnavailable }
        guard let url = URL.mediaWikiAPIURL(project: wikidataProject) else {
            throw WMFWikidataItemSearchError.failureCreatingRequestURL
        }

        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let parameters = Self.searchParameters(term: trimmed, languageCode: languageCode)
        let request = WMFMediaWikiServiceRequest(url: url, method: .GET, backend: .mediaWiki, parameters: parameters)

        let response: SearchResponse = try await withCheckedThrowingContinuation { continuation in
            service.performDecodableGET(request: request) { (result: Result<SearchResponse, Error>) in
                switch result {
                case .success(let response): continuation.resume(returning: response)
                case .failure(let error): continuation.resume(throwing: WMFWikidataItemSearchError.serviceError(error))
                }
            }
        }

        return Self.tags(from: response)
    }

    // MARK: - Pure helpers (unit tested)

    static func searchParameters(term: String, languageCode: String) -> [String: Any] {
        return [
            "action": "wbsearchentities",
            "type": "item",
            "limit": String(searchLimit),
            "search": term,
            "language": languageCode,
            "uselang": languageCode,
            "format": "json",
            "formatversion": "2"
        ]
    }

    static func tags(from response: SearchResponse) -> [WMFDepictsTag] {
        return (response.search ?? []).map { result in
            WMFDepictsTag(wikidataID: result.id, label: result.label ?? result.id, description: result.description, isSelected: false)
        }
    }
}
