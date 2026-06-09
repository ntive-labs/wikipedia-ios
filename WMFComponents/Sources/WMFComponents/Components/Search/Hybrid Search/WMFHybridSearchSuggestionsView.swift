import SwiftUI

/// Title-only suggestion list shown while the user is typing a hybrid search query,
/// with a "Search for:" row pinned to the bottom when no title matches the query.
public struct WMFHybridSearchSuggestionsView: View {

    @ObservedObject var viewModel: WMFHybridSearchSuggestionsViewModel
    @ObservedObject var appEnvironment = WMFAppEnvironment.current

    private var theme: WMFTheme {
        return appEnvironment.theme
    }

    public init(viewModel: WMFHybridSearchSuggestionsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(viewModel.titles, id: \.self) { title in
                        Button {
                            viewModel.onSuggestionTap(title)
                        } label: {
                            Text(title.wmfAttributedString(boldingFirstMatchOf: viewModel.searchTerm, font: WMFFont.for(.callout), boldFont: WMFFont.for(.boldCallout)))
                                .foregroundStyle(Color(theme.text))
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 16)
                .padding(.bottom, 64)
            }

            if !viewModel.hasAnyMatch {
                searchForRow
            }
        }
        .background(Color(theme.paperBackground))
    }

    private var searchForRow: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color(theme.border))
                .frame(height: 1)
            Button {
                viewModel.onSearchForTap(viewModel.searchTerm)
            } label: {
                Text(searchForText)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .background(Color(theme.paperBackground))
    }

    private var searchForText: AttributedString {
        var label = AttributedString(viewModel.localizedStrings.searchForLabel + " ")
        label.foregroundColor = theme.text
        var term = AttributedString(viewModel.searchTerm)
        term.foregroundColor = theme.link
        var result = label + term
        result.font = WMFFont.for(.mediumFootnote)
        return result
    }
}

// MARK: - Previews

#Preview("Suggestions with match") {
    let viewModel = WMFHybridSearchSuggestionsViewModel(
        titles: ["Pluto", "Pluto (mythology)", "Plutonium", "Plutarch"],
        searchTerm: "pluto",
        onSuggestionTap: { _ in },
        onSearchForTap: { _ in }
    )

    return WMFHybridSearchSuggestionsView(viewModel: viewModel)
}

#Preview("Question with no title match") {
    let viewModel = WMFHybridSearchSuggestionsViewModel(
        titles: ["Pluto", "IAU definition of planet"],
        searchTerm: "When was Pluto unlisted as a planet?",
        onSuggestionTap: { _ in },
        onSearchForTap: { _ in }
    )

    return WMFHybridSearchSuggestionsView(viewModel: viewModel)
}
