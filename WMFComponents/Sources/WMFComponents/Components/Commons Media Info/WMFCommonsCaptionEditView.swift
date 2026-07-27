import SwiftUI
import WMFData

/// Commons caption editor view (add / translate). Publishes via `wbsetlabel`.
struct WMFCommonsCaptionEditView: View {

    @ObservedObject var appEnvironment = WMFAppEnvironment.current
    @ObservedObject var viewModel: WMFCommonsCaptionEditViewModel

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

                    ZStack(alignment: .topLeading) {
                        if viewModel.captionText.isEmpty {
                            Text(viewModel.localizedStrings.placeholder)
                                .font(Font(WMFFont.for(.body)))
                                .foregroundColor(Color(theme.secondaryText))
                                .padding(.top, 8)
                                .padding(.leading, 5)
                        }
                        TextEditor(text: $viewModel.captionText)
                            .font(Font(WMFFont.for(.body)))
                            .foregroundColor(Color(theme.text))
                            .frame(minHeight: 120)
                            .scrollContentBackground(.hidden)
                            .accessibilityIdentifier("commons-caption-text-field")
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(theme.border), lineWidth: 1)
                    )

                    HStack(spacing: 8) {
                        Image(uiImage: WMFSFSymbolIcon.for(symbol: .infoCircle) ?? UIImage())
                            .foregroundColor(Color(theme.secondaryText))
                        Text(viewModel.localizedStrings.licenseNotice)
                            .font(Font(WMFFont.for(.footnote)))
                            .foregroundColor(Color(theme.secondaryText))
                    }
                    .accessibilityIdentifier("commons-caption-license-notice")

                    if viewModel.state == .error, let message = viewModel.errorMessage {
                        Text(message)
                            .font(Font(WMFFont.for(.footnote)))
                            .foregroundColor(Color(theme.destructive))
                            .accessibilityIdentifier("commons-caption-error")
                    }

                    publishButton

                    Spacer()
                }
                .padding(16)
            }
        }
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
            .accessibilityIdentifier("commons-caption-publish-button")
            Spacer()
        }
    }
}
