import Foundation

public final class WMFHybridSearchSuggestionsViewModel: ObservableObject {

    public struct LocalizedStrings {
        public let searchForLabel: String

        public init(searchForLabel: String = "Search for:") {
            self.searchForLabel = searchForLabel
        }
    }

    @Published public var titles: [String]
    @Published public var searchTerm: String

    public let localizedStrings: LocalizedStrings
    let onSuggestionTap: (String) -> Void
    let onSearchForTap: (String) -> Void

    public init(
        titles: [String] = [],
        searchTerm: String = "",
        localizedStrings: LocalizedStrings = LocalizedStrings(),
        onSuggestionTap: @escaping (String) -> Void,
        onSearchForTap: @escaping (String) -> Void
    ) {
        self.titles = titles
        self.searchTerm = searchTerm
        self.localizedStrings = localizedStrings
        self.onSuggestionTap = onSuggestionTap
        self.onSearchForTap = onSearchForTap
    }

    /// Mirrors Android: the "Search for:" row is only shown when no suggestion title contains the current term.
    var hasAnyMatch: Bool {
        guard !searchTerm.isEmpty else {
            return false
        }

        return titles.contains { $0.localizedCaseInsensitiveContains(searchTerm) }
    }
}
