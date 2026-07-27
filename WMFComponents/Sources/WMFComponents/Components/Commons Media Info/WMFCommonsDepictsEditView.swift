import SwiftUI
import WMFData

/// Commons depicts (P180 image tags) editor view. Publishes via `wbeditentity`.
struct WMFCommonsDepictsEditView: View {

    @ObservedObject var appEnvironment = WMFAppEnvironment.current
    @ObservedObject var viewModel: WMFCommonsDepictsEditViewModel

    private var theme: WMFTheme { appEnvironment.theme }

    var body: some View {
        ZStack {
            Color(theme.paperBackground)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(viewModel.localizedStrings.instructions)
                        .font(Font(WMFFont.for(.callout)))
                        .foregroundColor(Color(theme.secondaryText))

                    searchField

                    if !viewModel.searchResults.isEmpty {
                        searchResultsList
                    }

                    if !viewModel.selectedTags.isEmpty {
                        selectedChips
                    }

                    cc0Notice

                    if viewModel.state == .error, let message = viewModel.errorMessage {
                        Text(message)
                            .font(Font(WMFFont.for(.footnote)))
                            .foregroundColor(Color(theme.destructive))
                            .accessibilityIdentifier("commons-depicts-error")
                    }

                    publishButton

                    Spacer()
                }
                .padding(16)
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(uiImage: WMFSFSymbolIcon.for(symbol: .magnifyingGlass) ?? UIImage())
                .foregroundColor(Color(theme.secondaryText))
            TextField(viewModel.localizedStrings.searchPlaceholder, text: $viewModel.searchTerm)
                .font(Font(WMFFont.for(.body)))
                .foregroundColor(Color(theme.text))
                .autocorrectionDisabled()
                .onChange(of: viewModel.searchTerm) { _ in
                    viewModel.performSearch()
                }
                .accessibilityIdentifier("commons-depicts-search-field")
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(theme.border), lineWidth: 1)
        )
    }

    private var searchResultsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(viewModel.searchResults) { tag in
                Button {
                    viewModel.selectTag(tag)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tag.label)
                            .font(Font(WMFFont.for(.body)))
                            .foregroundColor(Color(theme.text))
                        if let description = tag.description, !description.isEmpty {
                            Text(description)
                                .font(Font(WMFFont.for(.footnote)))
                                .foregroundColor(Color(theme.secondaryText))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                }
                .accessibilityIdentifier("commons-depicts-result-\(tag.wikidataID)")
                Divider().background(Color(theme.border))
            }
        }
    }

    private var selectedChips: some View {
        WMFCommonsFlowLayout(spacing: 8) {
            ForEach(viewModel.selectedTags) { tag in
                HStack(spacing: 4) {
                    Text(tag.label)
                        .font(Font(WMFFont.for(.subheadline)))
                        .foregroundColor(Color(theme.paperBackground))
                    Image(uiImage: WMFSFSymbolIcon.for(symbol: .close) ?? UIImage())
                        .foregroundColor(Color(theme.paperBackground))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color(theme.link)))
                .onTapGesture {
                    viewModel.removeTag(tag)
                }
                .accessibilityIdentifier("commons-depicts-chip-\(tag.wikidataID)")
            }
        }
    }

    private var cc0Notice: some View {
        HStack(spacing: 8) {
            Image(uiImage: WMFSFSymbolIcon.for(symbol: .infoCircle) ?? UIImage())
                .foregroundColor(Color(theme.secondaryText))
            Text(viewModel.localizedStrings.cc0Notice)
                .font(Font(WMFFont.for(.footnote)))
                .foregroundColor(Color(theme.secondaryText))
        }
        .accessibilityIdentifier("commons-depicts-cc0-notice")
    }

    private var publishButton: some View {
        let title = viewModel.state == .publishing
            ? viewModel.localizedStrings.publishingButtonTitle
            : viewModel.localizedStrings.publishButtonTitle
        let configuration = WMFSmallButton.Configuration(style: .primary)
        return HStack {
            Spacer()
            WMFSmallButton(configuration: configuration, title: title) {
                viewModel.publish()
            }
            .disabled(!viewModel.canPublish)
            .opacity(viewModel.canPublish ? 1 : 0.5)
            .accessibilityIdentifier("commons-depicts-publish-button")
            Spacer()
        }
    }
}
