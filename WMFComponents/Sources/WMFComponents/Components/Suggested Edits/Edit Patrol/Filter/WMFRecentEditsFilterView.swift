import SwiftUI
import WMFData

/// SwiftUI filter screen for the Edit Patrol feed. Renders the same grouped layout as
/// Android's filter activity (user status, latest revisions, automated contributions,
/// contribution quality [ORES damaging], user intent [ORES good-faith], significance).
public struct WMFRecentEditsFilterView: View {

    @ObservedObject var appEnvironment = WMFAppEnvironment.current
    @ObservedObject var viewModel: WMFRecentEditsFilterViewModel

    private var theme: WMFTheme { appEnvironment.theme }

    public init(viewModel: WMFRecentEditsFilterViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ZStack {
            Color(uiColor: theme.paperBackground).ignoresSafeArea()

            List {
                ForEach(viewModel.groups) { group in
                    Section(header: Text(group.header)
                        .font(Font(WMFFont.for(.boldSubheadline)))
                        .foregroundColor(Color(uiColor: theme.secondaryText))
                    ) {
                        ForEach(group.types, id: \.self) { type in
                            row(type)
                        }
                    }
                }
            }
            .listStyle(.grouped)
            .accessibilityIdentifier("edit-patrol-filter-list")
        }
    }

    @ViewBuilder
    private func row(_ type: WMFRecentEditsFilterType) -> some View {
        Button {
            viewModel.toggle(type)
        } label: {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.title(for: type))
                        .font(Font(WMFFont.for(.body)))
                        .foregroundColor(Color(uiColor: theme.text))
                    if let subtitle = viewModel.subtitle(for: type) {
                        Text(subtitle)
                            .font(Font(WMFFont.for(.caption1)))
                            .foregroundColor(Color(uiColor: theme.secondaryText))
                    }
                }
                Spacer()
                if viewModel.isSelected(type) {
                    Image(systemName: "checkmark")
                        .foregroundColor(Color(uiColor: theme.accent))
                        .accessibilityIdentifier("edit-patrol-filter-check-\(type.id)")
                }
            }
        }
        .listRowBackground(Color(uiColor: theme.paperBackground))
        .accessibilityIdentifier("edit-patrol-filter-row-\(type.id)")
    }
}
