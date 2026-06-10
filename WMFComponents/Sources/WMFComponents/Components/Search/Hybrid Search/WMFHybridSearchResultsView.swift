import SwiftUI

public struct WMFHybridSearchResultsView: View {

    @ObservedObject var viewModel: WMFHybridSearchResultsViewModel
    @ObservedObject var appEnvironment = WMFAppEnvironment.current

    private var theme: WMFTheme {
        return appEnvironment.theme
    }

    public init(viewModel: WMFHybridSearchResultsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        Group {
            switch viewModel.loadState {
            case .loading:
                WMFHybridSearchSkeletonView(group: viewModel.group)
            case .error:
                errorView
            case .empty:
                noResultsView
            case .loaded:
                resultsList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(theme.paperBackground))
    }

    // MARK: - Loaded

    private var resultsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                switch viewModel.group {
                case .control:
                    lexicalSection
                case .lexicalSemantic:
                    lexicalSection
                    sectionDivider
                    semanticSection
                case .semanticLexical:
                    semanticSection
                    sectionDivider
                    lexicalSection
                }
            }
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private var sectionDivider: some View {
        if !viewModel.lexicalItems.isEmpty && !viewModel.semanticItems.isEmpty {
            Rectangle()
                .fill(Color(theme.border))
                .frame(height: 1)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
        }
    }

    private var lexicalSection: some View {
        ForEach(viewModel.lexicalItems) { item in
            WMFHybridSearchLexicalRow(item: item, theme: theme) {
                viewModel.onTapLexical(item)
            }
        }
    }

    @ViewBuilder
    private var semanticSection: some View {
        WMFHybridSearchSemanticHeader(
            theme: theme,
            betaTag: viewModel.localizedStrings.betaTag,
            headerDescription: viewModel.localizedStrings.headerDescription,
            learnMore: viewModel.localizedStrings.learnMore,
            turnOffExperiment: viewModel.localizedStrings.turnOffExperiment,
            onLearnMore: viewModel.onLearnMore,
            onTurnOffExperiment: viewModel.onTurnOffExperiment
        )
        .padding(.top, 8)
        .padding(.horizontal, 16)

        if viewModel.semanticItems.isEmpty {
            Text(viewModel.localizedStrings.semanticResultsEmpty)
                .font(Font(WMFFont.for(.callout)))
                .foregroundStyle(Color(theme.secondaryText))
                .padding(16)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(viewModel.semanticItems) { item in
                        WMFHybridSearchSemanticCard(
                            item: item,
                            theme: theme,
                            ratingLabel: item.rating == WMFHybridSearchSemanticItem.Rating.none ? viewModel.localizedStrings.rateResult : viewModel.localizedStrings.rated,
                            thumbsUpAccessibilityLabel: viewModel.localizedStrings.rateThumbsUpAccessibility,
                            thumbsDownAccessibilityLabel: viewModel.localizedStrings.rateThumbsDownAccessibility,
                            onTap: {
                                viewModel.onTapSemantic(item)
                            },
                            onRate: { isUp in
                                viewModel.rate(item: item, isUp: isUp)
                            }
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)
            }
        }
    }

    // MARK: - Empty / Error

    private var noResultsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(viewModel.localizedStrings.noResultsHeader)
                    .font(Font(WMFFont.for(.boldTitle3)))
                    .foregroundStyle(Color(theme.text))
                Text(viewModel.localizedStrings.noResultsDescription)
                    .font(Font(WMFFont.for(.callout)))
                    .foregroundStyle(Color(theme.secondaryText))
                noResultsSuggestionRow(viewModel.localizedStrings.noResultsRephraseSuggestion)
                noResultsSuggestionRow(viewModel.localizedStrings.noResultsRelatedTopicSuggestion)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
    }

    private func noResultsSuggestionRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(verbatim: "\u{2022}")
            Text(text)
        }
        .font(Font(WMFFont.for(.callout)))
        .foregroundStyle(Color(theme.secondaryText))
    }

    private var errorView: some View {
        VStack {
            Spacer()
            Text(viewModel.localizedStrings.errorMessage)
                .font(Font(WMFFont.for(.callout)))
                .foregroundStyle(Color(theme.secondaryText))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
    }
}

// MARK: - Semantic Section Header

struct WMFHybridSearchSemanticHeader: View {

    let theme: WMFTheme
    let betaTag: String
    let headerDescription: String
    let learnMore: String
    let turnOffExperiment: String
    let onLearnMore: () -> Void
    let onTurnOffExperiment: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(betaTag.uppercased())
                    .font(Font(WMFFont.for(.caption2)))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color(theme.link)))
                Menu {
                    Button(action: onLearnMore) {
                        Text(learnMore)
                    }
                    Button(role: .destructive, action: onTurnOffExperiment) {
                        Text(turnOffExperiment)
                    }
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 17))
                        .foregroundStyle(Color(theme.text))
                        .frame(width: 36, height: 36)
                        .contentShape(Circle())
                }
                Spacer()
            }
            Text(headerDescription)
                .font(Font(WMFFont.for(.footnote)))
                .foregroundStyle(Color(theme.secondaryText))
        }
    }
}

// MARK: - Semantic Card

struct WMFHybridSearchSemanticCard: View {

    static let cardWidth: CGFloat = 292
    static let cardHeight: CGFloat = 400
    static let cornerRadius: CGFloat = 24

    let item: WMFHybridSearchSemanticItem
    let theme: WMFTheme
    let ratingLabel: String
    let thumbsUpAccessibilityLabel: String
    let thumbsDownAccessibilityLabel: String
    let onTap: () -> Void
    let onRate: (Bool) -> Void

    private var snippetStyles: HtmlUtils.Styles {
        HtmlUtils.Styles(
            font: WMFFont.for(.callout),
            boldFont: WMFFont.for(.boldCallout),
            italicsFont: WMFFont.for(.italicCallout),
            boldItalicsFont: WMFFont.for(.boldItalicCallout),
            color: theme.text,
            linkColor: theme.link,
            lineSpacing: 3
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            snippet
            ratingRow
            Rectangle()
                .fill(Color(theme.border))
                .frame(width: 48, height: 1)
                .padding(.horizontal, 16)
            articleRow
        }
        .frame(width: Self.cardWidth, height: Self.cardHeight)
        .background(
            RoundedRectangle(cornerRadius: Self.cornerRadius)
                .fill(Color(theme.midBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Self.cornerRadius)
                .stroke(Color(theme.border), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius))
    }

    private var snippet: some View {
        WMFHtmlText(html: item.snippetHTML, styles: snippetStyles)
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .clipped()
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
    }

    private var ratingRow: some View {
        HStack(spacing: 0) {
            Text(ratingLabel)
                .font(Font(WMFFont.for(.caption1)))
                .foregroundStyle(Color(theme.secondaryText))
            Spacer(minLength: 8)
            if item.rating != .down {
                ratingButton(
                    isUp: true,
                    isSelected: item.rating == .up,
                    accessibilityLabel: thumbsUpAccessibilityLabel
                )
            }
            if item.rating != .up {
                ratingButton(
                    isUp: false,
                    isSelected: item.rating == .down,
                    accessibilityLabel: thumbsDownAccessibilityLabel
                )
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 44)
        .animation(.easeInOut(duration: 0.2), value: item.rating)
    }

    private func ratingButton(isUp: Bool, isSelected: Bool, accessibilityLabel: String) -> some View {
        Button {
            onRate(isUp)
        } label: {
            Image(systemName: thumbSymbolName(isUp: isUp, isSelected: isSelected))
                .font(.system(size: 15))
                .foregroundStyle(Color(theme.secondaryText))
                .frame(width: 40, height: 40)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(item.rating != WMFHybridSearchSemanticItem.Rating.none)
        .accessibilityLabel(accessibilityLabel)
    }

    private func thumbSymbolName(isUp: Bool, isSelected: Bool) -> String {
        let base = isUp ? "hand.thumbsup" : "hand.thumbsdown"
        return isSelected ? base + ".fill" : base
    }

    private var articleRow: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(Font(WMFFont.for(.boldCallout)))
                        .foregroundStyle(Color(theme.text))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if let description = item.description, !description.isEmpty {
                        Text(description)
                            .font(Font(WMFFont.for(.footnote)))
                            .foregroundStyle(Color(theme.secondaryText))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if let thumbnailURL = item.thumbnailURL {
                    WMFHybridSearchThumbnail(url: thumbnailURL, size: 56, theme: theme)
                }
            }
            .padding(16)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Lexical Row

struct WMFHybridSearchLexicalRow: View {

    let item: WMFHybridSearchLexicalItem
    let theme: WMFTheme
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title.wmfAttributedString(boldingFirstMatchOf: item.boldedMatchTerm, font: WMFFont.for(.callout), boldFont: WMFFont.for(.boldCallout)))
                        .foregroundStyle(Color(theme.text))
                        .multilineTextAlignment(.leading)
                    if let description = item.description, !description.isEmpty {
                        Text(description)
                            .font(Font(WMFFont.for(.footnote)))
                            .foregroundStyle(Color(theme.secondaryText))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 0)
                if let thumbnailURL = item.thumbnailURL {
                    WMFHybridSearchThumbnail(url: thumbnailURL, size: 40, theme: theme)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Shared Helpers

struct WMFHybridSearchThumbnail: View {

    let url: URL
    let size: CGFloat
    let theme: WMFTheme

    var body: some View {
        AsyncImage(url: url) { image in
            image
                .resizable()
                .scaledToFill()
        } placeholder: {
            Color(theme.border)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

extension String {

    /// Returns an attributed string in `font`, with the first case-insensitive occurrence of `term` set in `boldFont`.
    func wmfAttributedString(boldingFirstMatchOf term: String?, font: UIFont, boldFont: UIFont) -> AttributedString {
        var attributed = AttributedString(self)
        attributed.font = font

        if let term, !term.isEmpty,
           let range = attributed.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) {
            attributed[range].font = boldFont
        }

        return attributed
    }
}

// MARK: - Previews

#Preview("Semantic first (loaded)") {
    let plutoSnippet = "In 2006, the International Astronomical Union (IAU) adopted a formal definition of <b>planet</b>. Pluto does not clear the neighborhood around its orbit, so it was reclassified as a <i>dwarf planet</i>."
    let iauSnippet = "The definition of <b>planet</b> adopted in August 2006 states that, in the Solar System, a planet must orbit the Sun, have enough mass to assume hydrostatic equilibrium, and clear the neighborhood around its orbit."

    let viewModel = WMFHybridSearchResultsViewModel(
        group: .semanticLexical,
        loadState: .loaded,
        lexicalItems: [
            WMFHybridSearchLexicalItem(title: "Pluto", description: "Dwarf planet in the outer Solar System", boldedMatchTerm: "pluto"),
            WMFHybridSearchLexicalItem(title: "Pluto (mythology)", description: "Ancient Greek god of the underworld", boldedMatchTerm: "pluto")
        ],
        semanticItems: [
            WMFHybridSearchSemanticItem(id: "1", snippetHTML: plutoSnippet, title: "Pluto", description: "Dwarf planet in the outer Solar System"),
            WMFHybridSearchSemanticItem(id: "2", snippetHTML: iauSnippet, title: "IAU definition of planet", description: "2006 formal definition", rating: .up)
        ],
        onTapLexical: { _ in },
        onTapSemantic: { _ in },
        onRate: { _, _ in },
        onLearnMore: {},
        onTurnOffExperiment: {}
    )

    return WMFHybridSearchResultsView(viewModel: viewModel)
}

#Preview("Lexical first, semantic empty") {
    let viewModel = WMFHybridSearchResultsViewModel(
        group: .lexicalSemantic,
        loadState: .loaded,
        lexicalItems: [
            WMFHybridSearchLexicalItem(title: "Pluto", description: "Dwarf planet in the outer Solar System", boldedMatchTerm: "pluto"),
            WMFHybridSearchLexicalItem(title: "Pluto (Disney)", description: "Disney cartoon character", boldedMatchTerm: "pluto")
        ],
        semanticItems: [],
        onTapLexical: { _ in },
        onTapSemantic: { _ in },
        onRate: { _, _ in },
        onLearnMore: {},
        onTurnOffExperiment: {}
    )

    return WMFHybridSearchResultsView(viewModel: viewModel)
}

#Preview("No results") {
    let viewModel = WMFHybridSearchResultsViewModel(
        group: .semanticLexical,
        loadState: .empty,
        onTapLexical: { _ in },
        onTapSemantic: { _ in },
        onRate: { _, _ in },
        onLearnMore: {},
        onTurnOffExperiment: {}
    )

    return WMFHybridSearchResultsView(viewModel: viewModel)
}

#Preview("Error") {
    let viewModel = WMFHybridSearchResultsViewModel(
        group: .semanticLexical,
        loadState: .error,
        onTapLexical: { _ in },
        onTapSemantic: { _ in },
        onRate: { _, _ in },
        onLearnMore: {},
        onTurnOffExperiment: {}
    )

    return WMFHybridSearchResultsView(viewModel: viewModel)
}
