import SwiftUI
import WMFData

/// The File Media Info screen — iOS analogue of Android's `FilePageView`.
/// Renders the image, filename, structured caption (or "Add caption" CTA), depicts tags
/// (or "Add image tags" CTA), author/date/license, and a "view on Commons" link.
struct WMFFileMediaInfoView: View {

    @ObservedObject var appEnvironment = WMFAppEnvironment.current
    @ObservedObject var viewModel: WMFFileMediaInfoViewModel

    private var theme: WMFTheme { appEnvironment.theme }

    private var isRTL: Bool {
        viewModel.semanticContentAttribute == .forceRightToLeft
    }

    var body: some View {
        ZStack {
            Color(theme.paperBackground)
                .ignoresSafeArea()

            switch viewModel.state {
            case .loading:
                ProgressView()
                    .accessibilityIdentifier("file-media-info-loading")
            case .error:
                errorView
            case .loaded:
                content
            }
        }
        .environment(\.layoutDirection, isRTL ? .rightToLeft : .leftToRight)
        .onAppear {
            if viewModel.mediaInfo == nil {
                viewModel.loadMediaInfo()
            }
        }
    }

    // MARK: - Content

    private var content: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 20) {
                imageView
                filenameView
                Divider().background(Color(theme.border))
                captionSection
                Divider().background(Color(theme.border))
                tagsSection
                Divider().background(Color(theme.border))
                metadataSection
                viewOnCommonsButton
            }
            .padding(16)
        }
        .accessibilityIdentifier("file-media-info-scroll")
        .refreshable {
            viewModel.loadMediaInfo()
        }
    }

    @ViewBuilder
    private var imageView: some View {
        if let thumbnail = viewModel.thumbnail {
            Image(uiImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity)
                .frame(maxHeight: 260)
                .clipped()
                .cornerRadius(8)
                .accessibilityIdentifier("file-media-info-thumbnail")
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(theme.midBackground))
                .frame(height: 200)
                .overlay(ProgressView())
                .accessibilityIdentifier("file-media-info-thumbnail")
        }
    }

    private var filenameView: some View {
        Text(displayFilename)
            .font(Font(WMFFont.for(.boldTitle3)))
            .foregroundColor(Color(theme.text))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("file-media-info-filename")
    }

    private var displayFilename: String {
        (viewModel.mediaInfo?.title ?? viewModel.commonsTitle)
            .replacingOccurrences(of: "File:", with: "")
            .replacingOccurrences(of: "_", with: " ")
    }

    // MARK: - Caption

    @ViewBuilder
    private var captionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(viewModel.localizedStrings.captionHeader)

            if let info = viewModel.mediaInfo {
                if let caption = info.caption, !caption.value.isEmpty {
                    Text(caption.value)
                        .font(Font(WMFFont.for(.body)))
                        .foregroundColor(Color(theme.text))
                        .accessibilityIdentifier("file-media-info-caption-value")
                } else if info.shouldShowAddCaption {
                    ctaButton(
                        title: info.shouldShowTranslateCaption
                            ? viewModel.localizedStrings.translateCaptionButtonTitle
                            : viewModel.localizedStrings.addCaptionButtonTitle,
                        identifier: "file-media-info-add-caption-button"
                    ) {
                        viewModel.tappedAddCaption(isTranslation: info.shouldShowTranslateCaption)
                    }
                } else {
                    placeholderText(viewModel.localizedStrings.noCaptionPlaceholder)
                        .accessibilityIdentifier("file-media-info-caption-value")
                }
            }
        }
    }

    // MARK: - Tags

    @ViewBuilder
    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(viewModel.localizedStrings.tagsHeader)

            if let info = viewModel.mediaInfo {
                if !info.depicts.isEmpty {
                    WMFDepictsChipsView(tags: info.depicts, theme: theme)
                        .accessibilityIdentifier("file-media-info-tags-value")
                } else if info.shouldShowAddTags {
                    ctaButton(
                        title: viewModel.localizedStrings.addTagsButtonTitle,
                        identifier: "file-media-info-add-tags-button"
                    ) {
                        viewModel.tappedAddTags()
                    }
                } else {
                    placeholderText(viewModel.localizedStrings.noTagsPlaceholder)
                        .accessibilityIdentifier("file-media-info-tags-value")
                }
            }
        }
    }

    // MARK: - Metadata

    @ViewBuilder
    private var metadataSection: some View {
        if let metadata = viewModel.mediaInfo?.metadata {
            VStack(alignment: .leading, spacing: 12) {
                if let author = metadata.author.map(Self.plainText), !author.isEmpty {
                    metadataRow(header: viewModel.localizedStrings.authorHeader, value: author)
                }
                if let date = metadata.dateTime.map(Self.plainText), !date.isEmpty {
                    metadataRow(header: viewModel.localizedStrings.dateHeader, value: date)
                }
                if let license = metadata.licenseShortName.map(Self.plainText), !license.isEmpty {
                    metadataRow(header: viewModel.localizedStrings.licenseHeader, value: license)
                        .accessibilityIdentifier("file-media-info-license-value")
                }
            }
        }
    }

    /// Lightweight HTML strip for `extmetadata` fields (Android uses `StringUtil.fromHtml`).
    private static func plainText(_ html: String) -> String {
        guard html.contains("<") || html.contains("&") else { return html }
        let stripped = html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        return stripped
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var viewOnCommonsButton: some View {
        HStack {
            Spacer()
            let configuration = WMFSmallButton.Configuration(style: .quiet)
            WMFSmallButton(configuration: configuration, title: viewModel.localizedStrings.viewOnCommonsButtonTitle) {
                viewModel.tappedViewOnCommons()
            }
            .accessibilityIdentifier("file-media-info-view-on-commons-button")
            Spacer()
        }
        .padding(.top, 8)
    }

    // MARK: - Error

    private var errorView: some View {
        VStack(spacing: 16) {
            Text(viewModel.localizedStrings.errorTitle)
                .font(Font(WMFFont.for(.headline)))
                .foregroundColor(Color(theme.text))
                .multilineTextAlignment(.center)
            let configuration = WMFSmallButton.Configuration(style: .neutral)
            WMFSmallButton(configuration: configuration, title: viewModel.localizedStrings.errorRetryButtonTitle) {
                viewModel.loadMediaInfo()
            }
            .accessibilityIdentifier("file-media-info-error-retry-button")
        }
        .padding(24)
    }

    // MARK: - Building blocks

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(Font(WMFFont.for(.semiboldSubheadline)))
            .foregroundColor(Color(theme.secondaryText))
            .textCase(.uppercase)
    }

    private func placeholderText(_ text: String) -> some View {
        Text(text)
            .font(Font(WMFFont.for(.body)))
            .foregroundColor(Color(theme.secondaryText))
    }

    private func metadataRow(header: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(header)
                .font(Font(WMFFont.for(.mediumFootnote)))
                .foregroundColor(Color(theme.secondaryText))
            Text(value)
                .font(Font(WMFFont.for(.subheadline)))
                .foregroundColor(Color(theme.text))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func ctaButton(title: String, identifier: String, action: @escaping () -> Void) -> some View {
        let configuration = WMFSmallButton.Configuration(
            style: .primary,
            trailingIcon: WMFSFSymbolIcon.for(symbol: .plusCircleFill, font: .mediumSubheadline)
        )
        return HStack {
            WMFSmallButton(configuration: configuration, title: title, action: action)
                .accessibilityIdentifier(identifier)
            Spacer()
        }
    }
}

/// Simple wrapping chips row for existing depicts tags.
struct WMFDepictsChipsView: View {
    let tags: [WMFDepictsTag]
    let theme: WMFTheme

    var body: some View {
        WMFCommonsFlowLayout(spacing: 8) {
            ForEach(tags) { tag in
                Text(tag.label)
                    .font(Font(WMFFont.for(.subheadline)))
                    .foregroundColor(Color(theme.text))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule().fill(Color(theme.midBackground))
                    )
                    .accessibilityIdentifier("file-media-info-tag-\(tag.wikidataID)")
            }
        }
    }
}

/// Minimal wrapping flow layout used for depicts chips.
struct WMFCommonsFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rows: [[LayoutSubviews.Element]] = [[]]
        var currentRowWidth: CGFloat = 0
        var totalHeight: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentRowWidth + size.width > maxWidth, !(rows.last?.isEmpty ?? true) {
                totalHeight += rowHeight + spacing
                rows.append([])
                currentRowWidth = 0
                rowHeight = 0
            }
            rows[rows.count - 1].append(subview)
            currentRowWidth += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight += rowHeight
        return CGSize(width: maxWidth == .infinity ? currentRowWidth : maxWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let maxWidth = bounds.width
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.minX + maxWidth, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
