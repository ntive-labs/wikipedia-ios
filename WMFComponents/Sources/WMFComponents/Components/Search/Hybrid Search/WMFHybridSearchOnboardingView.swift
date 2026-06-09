import SwiftUI

/// Onboarding screen for the hybrid search experiment. Mirrors Android's HybridSearchOnboardingScreen.
public struct WMFHybridSearchOnboardingView: View {

    // MARK: - Properties

    @ObservedObject var appEnvironment = WMFAppEnvironment.current

    let viewModel: WMFHybridSearchOnboardingViewModel

    public init(viewModel: WMFHybridSearchOnboardingViewModel) {
        self.viewModel = viewModel
    }

    private var theme: WMFTheme {
        appEnvironment.theme
    }

    // MARK: - Body

    public var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: true) {
                VStack(alignment: .leading, spacing: 0) {
                    header
                        .padding(.top, 44)
                        .padding(.bottom, 32)

                    infoRow(systemImageName: "bubble.left",
                            title: viewModel.localizedStrings.askQuestionsTitle,
                            description: viewModel.localizedStrings.askQuestionsDescription)
                        .padding(.vertical, 12)

                    infoRow(systemImageName: "timer",
                            title: viewModel.localizedStrings.betaFeatureTitle,
                            description: viewModel.localizedStrings.betaFeatureDescription)
                        .padding(.vertical, 12)

                    infoRow(systemImageName: "lightbulb",
                            title: viewModel.localizedStrings.needInspirationTitle,
                            description: viewModel.localizedStrings.needInspirationDescription)
                        .padding(.top, 12)
                        .padding(.bottom, 4)

                    exampleQueryChips
                        .padding(.leading, 36)
                        .padding(.top, 8)
                        .padding(.bottom, 24)
                }
                .padding(.horizontal, 24)
            }

            Divider()
                .overlay(Color(theme.border))

            buttonArea
        }
        .background(Color(theme.paperBackground).ignoresSafeArea())
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(viewModel.localizedStrings.betaTag.localizedUppercase)
                .font(Font(WMFFont.for(.caption1)))
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color(theme.link)))

            Text(viewModel.localizedStrings.title)
                .font(Font(WMFFont.for(.boldTitle1)))
                .foregroundColor(Color(theme.text))
        }
    }

    // MARK: - Info Rows

    private func infoRow(systemImageName: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImageName)
                .font(Font(WMFFont.for(.boldCallout)))
                .foregroundColor(Color(theme.link))
                .frame(width: 24, alignment: .center)
                .padding(.top, 2)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Font(WMFFont.for(.boldCallout)))
                    .foregroundColor(Color(theme.text))
                Text(description)
                    .font(Font(WMFFont.for(.subheadline)))
                    .foregroundColor(Color(theme.secondaryText))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Example Query Chips

    private var exampleQueryChips: some View {
        WMFHybridSearchOnboardingFlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
            ForEach(viewModel.exampleQueries, id: \.self) { query in
                Button(action: {
                    viewModel.onExampleQueryTap?(query)
                }, label: {
                    Text(query)
                        .font(Font(WMFFont.for(.subheadline)))
                        .foregroundColor(Color(theme.secondaryText))
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color(theme.border), lineWidth: 1)
                        )
                })
            }
        }
    }

    // MARK: - Bottom Bar

    private var buttonArea: some View {
        HStack(spacing: 24) {
            WMFLargeButton(style: .neutral, title: viewModel.localizedStrings.learnMoreButtonTitle) {
                viewModel.onLearnMore?()
            }

            WMFLargeButton(style: .primary, title: viewModel.localizedStrings.getStartedButtonTitle) {
                viewModel.onGetStarted?()
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(Color(theme.paperBackground).ignoresSafeArea())
    }
}

// MARK: - Flow Layout

/// A simple left-aligned wrapping flow layout, equivalent to Compose's FlowRow.
fileprivate struct WMFHybridSearchOnboardingFlowLayout: Layout {

    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxRowWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
            if x > 0 && x + size.width > maxWidth {
                x = 0
                y += rowHeight + verticalSpacing
                rowHeight = 0
            }
            x += size.width
            maxRowWidth = max(maxRowWidth, x)
            x += horizontalSpacing
            rowHeight = max(rowHeight, size.height)
        }

        return CGSize(width: maxWidth.isFinite ? maxWidth : maxRowWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + verticalSpacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + horizontalSpacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Preview

#Preview {
    WMFHybridSearchOnboardingView(viewModel: WMFHybridSearchOnboardingViewModel(
        localizedStrings: WMFHybridSearchOnboardingViewModel.LocalizedStrings(
            betaTag: "Beta",
            title: "A new way to search",
            askQuestionsTitle: "Ask questions, get answers",
            askQuestionsDescription: "This experimental feature understands natural language. Instead of searching for keywords, describe what you want to know.",
            betaFeatureTitle: "Beta feature",
            betaFeatureDescription: "Available for a limited time during this experiment.",
            needInspirationTitle: "Need inspiration?",
            needInspirationDescription: "Use one of the search examples below.",
            exampleQueries: [
                "When was Pluto unlisted as a planet?",
                "first Olympics",
                "RNA vs DNA",
                "Why do people put pineapple on pizza?",
                "What are the biggest cities in Europe?"
            ],
            learnMoreButtonTitle: "Learn more",
            getStartedButtonTitle: "Get started"
        ),
        languageCode: "en"
    ))
}
