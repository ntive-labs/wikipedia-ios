import Foundation

/// Experiment group for the hybrid search A/B/C test. Raw values match
/// `WMFHybridSearchDataController.assignedGroupName` in WMFData.
public enum WMFHybridSearchGroup: String {
    case control
    case lexicalSemantic
    case semanticLexical
}

/// Overall load state of the hybrid search results screen.
public enum WMFHybridSearchLoadState: Equatable {
    case loading
    case loaded
    case error
    case empty
}

/// A standard (lexical) search result row.
public struct WMFHybridSearchLexicalItem: Identifiable, Equatable {
    public let id: String
    public let title: String
    public let description: String?
    public let thumbnailURL: URL?
    /// When set, the first case-insensitive occurrence of this term within the title is bolded.
    public let boldedMatchTerm: String?

    public init(id: String = UUID().uuidString, title: String, description: String? = nil, thumbnailURL: URL? = nil, boldedMatchTerm: String? = nil) {
        self.id = id
        self.title = title
        self.description = description
        self.thumbnailURL = thumbnailURL
        self.boldedMatchTerm = boldedMatchTerm
    }
}

/// A semantic search result card.
public struct WMFHybridSearchSemanticItem: Identifiable, Equatable {

    public enum Rating: Equatable {
        case none
        case up
        case down
    }

    public let id: String
    /// Simple HTML snippet (supports <b>/<i> emphasis) shown at the top of the card.
    public let snippetHTML: String
    public let title: String
    public let description: String?
    public let thumbnailURL: URL?
    /// Anchor of the article section this snippet was sourced from, if any.
    public let fragment: String?
    public var rating: Rating

    public init(id: String, snippetHTML: String, title: String, description: String? = nil, thumbnailURL: URL? = nil, fragment: String? = nil, rating: Rating = .none) {
        self.id = id
        self.snippetHTML = snippetHTML
        self.title = title
        self.description = description
        self.thumbnailURL = thumbnailURL
        self.fragment = fragment
        self.rating = rating
    }
}

public final class WMFHybridSearchResultsViewModel: ObservableObject {

    public struct LocalizedStrings {
        public let betaTag: String
        public let headerDescription: String
        public let learnMore: String
        public let turnOffExperiment: String
        public let rateResult: String
        public let rated: String
        public let rateThumbsUpAccessibility: String
        public let rateThumbsDownAccessibility: String
        public let semanticResultsEmpty: String
        public let errorMessage: String
        public let noResultsHeader: String
        public let noResultsDescription: String
        public let noResultsRephraseSuggestion: String
        public let noResultsRelatedTopicSuggestion: String

        public init(
            betaTag: String = "Beta",
            headerDescription: String = "Sourced from human generated Wikipedia articles",
            learnMore: String = "Learn more",
            turnOffExperiment: String = "Turn off this experiment",
            rateResult: String = "Rate this result",
            rated: String = "Rated",
            rateThumbsUpAccessibility: String = "Rate thumbs up",
            rateThumbsDownAccessibility: String = "Rate thumbs down",
            semanticResultsEmpty: String = "Enhanced search is temporarily unavailable.",
            errorMessage: String = "Something went wrong. Please try again later.",
            noResultsHeader: String = "No results",
            noResultsDescription: String = "This topic isn't returning article excerpts at this moment. Here are some things you can try:",
            noResultsRephraseSuggestion: String = "Rephrase your search",
            noResultsRelatedTopicSuggestion: String = "Try a related topic"
        ) {
            self.betaTag = betaTag
            self.headerDescription = headerDescription
            self.learnMore = learnMore
            self.turnOffExperiment = turnOffExperiment
            self.rateResult = rateResult
            self.rated = rated
            self.rateThumbsUpAccessibility = rateThumbsUpAccessibility
            self.rateThumbsDownAccessibility = rateThumbsDownAccessibility
            self.semanticResultsEmpty = semanticResultsEmpty
            self.errorMessage = errorMessage
            self.noResultsHeader = noResultsHeader
            self.noResultsDescription = noResultsDescription
            self.noResultsRephraseSuggestion = noResultsRephraseSuggestion
            self.noResultsRelatedTopicSuggestion = noResultsRelatedTopicSuggestion
        }
    }

    public let group: WMFHybridSearchGroup
    public let localizedStrings: LocalizedStrings

    @Published public var loadState: WMFHybridSearchLoadState
    @Published public var lexicalItems: [WMFHybridSearchLexicalItem]
    @Published public var semanticItems: [WMFHybridSearchSemanticItem] {
        didSet {
            if oldValue.map(\.id) != semanticItems.map(\.id) {
                impressedSemanticCardIDs.removeAll()
            }
        }
    }

    let onTapLexical: (WMFHybridSearchLexicalItem) -> Void
    let onTapSemantic: (WMFHybridSearchSemanticItem) -> Void
    let onTapSemanticLink: (URL, WMFHybridSearchSemanticItem) -> Void
    let onSemanticCardImpression: (WMFHybridSearchSemanticItem, Int) -> Void
    let onRate: (WMFHybridSearchSemanticItem, Bool) -> Void
    let onLearnMore: () -> Void
    let onTurnOffExperiment: () -> Void

    private var impressedSemanticCardIDs: Set<String> = []

    public init(
        group: WMFHybridSearchGroup,
        loadState: WMFHybridSearchLoadState = .loading,
        lexicalItems: [WMFHybridSearchLexicalItem] = [],
        semanticItems: [WMFHybridSearchSemanticItem] = [],
        localizedStrings: LocalizedStrings = LocalizedStrings(),
        onTapLexical: @escaping (WMFHybridSearchLexicalItem) -> Void,
        onTapSemantic: @escaping (WMFHybridSearchSemanticItem) -> Void,
        onTapSemanticLink: @escaping (URL, WMFHybridSearchSemanticItem) -> Void = { _, _ in },
        onSemanticCardImpression: @escaping (WMFHybridSearchSemanticItem, Int) -> Void = { _, _ in },
        onRate: @escaping (WMFHybridSearchSemanticItem, Bool) -> Void,
        onLearnMore: @escaping () -> Void,
        onTurnOffExperiment: @escaping () -> Void
    ) {
        self.group = group
        self.loadState = loadState
        self.lexicalItems = lexicalItems
        self.semanticItems = semanticItems
        self.localizedStrings = localizedStrings
        self.onTapLexical = onTapLexical
        self.onTapSemantic = onTapSemantic
        self.onTapSemanticLink = onTapSemanticLink
        self.onSemanticCardImpression = onSemanticCardImpression
        self.onRate = onRate
        self.onLearnMore = onLearnMore
        self.onTurnOffExperiment = onTurnOffExperiment
    }

    /// Reports a semantic card as visible (≥50% within the horizontal scroller), notifying via
    /// `onSemanticCardImpression` once per card per result set.
    func reportSemanticCardVisible(item: WMFHybridSearchSemanticItem, index: Int) {
        guard impressedSemanticCardIDs.insert(item.id).inserted else {
            return
        }

        onSemanticCardImpression(item, index)
    }

    /// Records a rating for a semantic item (first rating wins, mirroring Android) and notifies via `onRate`.
    public func rate(item: WMFHybridSearchSemanticItem, isUp: Bool) {
        guard let index = semanticItems.firstIndex(where: { $0.id == item.id }),
              semanticItems[index].rating == WMFHybridSearchSemanticItem.Rating.none else {
            return
        }

        semanticItems[index].rating = isUp ? .up : .down
        onRate(semanticItems[index], isUp)
    }
}
