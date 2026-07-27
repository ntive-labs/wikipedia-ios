import Foundation

/// Searches Wikidata items for the depicts (P180) tags editor.
/// Parity: Android `SuggestedEditsImageTagDialog` → `Service.searchEntities` (`wbsearchentities`).
public actor WMFWikidataItemSearchDataController {

    private let service: WMFService?

    public init(service: WMFService? = WMFDataEnvironment.current.mediaWikiService) {
        self.service = service
    }

    /// Parity: Android `searchEntities(search, language, uselang)` with `type=item&limit=20`.
    public func search(term: String, languageCode: String) async throws -> [WMFDepictsTag] {

        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return []
        }

        guard let service else {
            throw WMFDataControllerError.mediaWikiServiceUnavailable
        }
        guard let url = URL.mediaWikiAPIURL(project: .wikidata) else {
            throw WMFDataControllerError.failureCreatingRequestURL
        }

        let parameters: [String: Any] = [
            "action": "wbsearchentities",
            "type": "item",
            "limit": 20,
            "search": trimmed,
            "language": languageCode,
            "uselang": languageCode,
            "format": "json"
        ]

        let request = WMFMediaWikiServiceRequest(url: url, method: .GET, backend: .mediaWiki, parameters: parameters)

        let response: WMFWikidataSearchResponse = try await withCheckedThrowingContinuation { continuation in
            service.performDecodableGET(request: request) { (result: Result<WMFWikidataSearchResponse, Error>) in
                switch result {
                case .success(let value):
                    continuation.resume(returning: value)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }

        return (response.search ?? []).compactMap { result in
            guard let id = result.id, let label = result.label else {
                return nil
            }
            return WMFDepictsTag(wikidataID: id, label: label, description: result.description)
        }
    }
}
