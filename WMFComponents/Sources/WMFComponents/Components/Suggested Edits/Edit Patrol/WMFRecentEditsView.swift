import SwiftUI
import WMFData

/// SwiftUI list for the Edit Patrol recent-changes feed. Renders day-bucketed
/// sections, a local search field, an empty state, and ORES quality/intent cues.
public struct WMFRecentEditsView: View {

    @ObservedObject var appEnvironment = WMFAppEnvironment.current
    @ObservedObject var viewModel: WMFRecentEditsViewModel

    private var theme: WMFTheme { appEnvironment.theme }

    public init(viewModel: WMFRecentEditsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ZStack {
            Color(uiColor: theme.paperBackground)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                searchBar

                if viewModel.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
        }
        .onAppear {
            if !viewModel.hasPerformedInitialFetch {
                viewModel.fetchRecentEdits()
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(Color(uiColor: theme.secondaryText))
            TextField(viewModel.localizedStrings.searchPlaceholder, text: $viewModel.currentQuery)
                .font(Font(WMFFont.for(.body)))
                .foregroundColor(Color(uiColor: theme.text))
                .accessibilityIdentifier("edit-patrol-search")
                .autocorrectionDisabled(true)
        }
        .padding(10)
        .background(Color(uiColor: theme.midBackground))
        .cornerRadius(10)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var list: some View {
        List {
            ForEach(viewModel.sections) { section in
                Section(header: Text(section.title)
                    .font(Font(WMFFont.for(.boldSubheadline)))
                    .foregroundColor(Color(uiColor: theme.secondaryText))
                    .accessibilityIdentifier("edit-patrol-section-header")
                ) {
                    ForEach(section.items) { item in
                        Button {
                            viewModel.didTapItem(item)
                        } label: {
                            row(item)
                        }
                        .listRowBackground(Color(uiColor: theme.paperBackground))
                        .accessibilityIdentifier("edit-patrol-row-\(item.rcid)")
                    }
                }
            }

            if !viewModel.sections.isEmpty {
                loadMoreRow
            }
        }
        .listStyle(.plain)
        .accessibilityIdentifier("edit-patrol-list")
    }

    private var loadMoreRow: some View {
        HStack {
            Spacer()
            if viewModel.isLoading {
                ProgressView()
            } else {
                Button(action: { viewModel.loadMoreIfNeeded() }) {
                    Text(verbatim: "•••")
                        .foregroundColor(Color(uiColor: theme.link))
                }
                .accessibilityIdentifier("edit-patrol-load-more")
            }
            Spacer()
        }
        .listRowBackground(Color(uiColor: theme.paperBackground))
    }

    @ViewBuilder
    private func row(_ item: WMFRecentEditsViewModel.ItemViewModel) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.title)
                .font(Font(WMFFont.for(.boldHeadline)))
                .foregroundColor(Color(uiColor: theme.text))
                .accessibilityIdentifier("edit-patrol-row-title")

            if !item.comment.isEmpty {
                Text(item.comment)
                    .font(Font(WMFFont.for(.subheadline)))
                    .foregroundColor(Color(uiColor: theme.secondaryText))
                    .lineLimit(2)
            }

            HStack(spacing: 8) {
                Text(item.isAnonymous ? viewModel.localizedStrings.editSummaryAnonymous : item.username)
                    .font(Font(WMFFont.for(.caption1)))
                    .foregroundColor(Color(uiColor: theme.link))

                Text(byteChangeString(item.byteChange))
                    .font(Font(WMFFont.for(.boldCaption1)))
                    .foregroundColor(Color(uiColor: byteChangeColor(item.byteChange)))
            }

            if item.hasORESScores {
                oresCue(item)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func oresCue(_ item: WMFRecentEditsViewModel.ItemViewModel) -> some View {
        HStack(spacing: 12) {
            if let damaging = item.oresDamaging {
                Text("\(viewModel.localizedStrings.oresDamagingPrefix) \(percent(damaging))")
                    .accessibilityIdentifier("edit-patrol-ores-damaging")
            }
            if let goodfaith = item.oresGoodFaith {
                Text("\(viewModel.localizedStrings.oresGoodFaithPrefix) \(percent(goodfaith))")
                    .accessibilityIdentifier("edit-patrol-ores-goodfaith")
            }
        }
        .font(Font(WMFFont.for(.caption2)))
        .foregroundColor(Color(uiColor: theme.secondaryText))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 44))
                .foregroundColor(Color(uiColor: theme.secondaryText))
            Text(viewModel.localizedStrings.emptyTitle)
                .font(Font(WMFFont.for(.boldHeadline)))
                .foregroundColor(Color(uiColor: theme.text))
            Text(viewModel.localizedStrings.emptySubtitle)
                .font(Font(WMFFont.for(.subheadline)))
                .foregroundColor(Color(uiColor: theme.secondaryText))
                .multilineTextAlignment(.center)
            Button(action: { viewModel.didTapFilter() }) {
                Text(viewModel.localizedStrings.filter)
                    .font(Font(WMFFont.for(.boldSubheadline)))
                    .foregroundColor(Color(uiColor: theme.link))
            }
            .accessibilityIdentifier("edit-patrol-empty-filter-button")
            Spacer()
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("edit-patrol-empty")
    }

    // MARK: - Formatting

    private func percent(_ value: Float) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private func byteChangeString(_ change: Int) -> String {
        change > 0 ? "+\(change)" : "\(change)"
    }

    private func byteChangeColor(_ change: Int) -> UIColor {
        if change == 0 { return theme.secondaryText }
        return change > 0 ? theme.accent : theme.destructive
    }
}
