import SwiftUI

/// Loading skeleton for hybrid search results, mirroring Android's HybridSearchSkeletonLoader:
/// list-item placeholders for lexical rows and a horizontal row of card placeholders for semantic results,
/// ordered according to the experiment group.
public struct WMFHybridSearchSkeletonView: View {

    @ObservedObject var appEnvironment = WMFAppEnvironment.current
    @State private var isPulsing = false

    private var theme: WMFTheme {
        return appEnvironment.theme
    }

    let group: WMFHybridSearchGroup

    public init(group: WMFHybridSearchGroup) {
        self.group = group
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                switch group {
                case .control:
                    listItemPlaceholders(count: 15)
                case .lexicalSemantic:
                    listItemPlaceholders(count: 3)
                    cardRowPlaceholder
                case .semanticLexical:
                    cardRowPlaceholder
                    listItemPlaceholders(count: 3)
                }
            }
            .padding(.vertical, 12)
        }
        .scrollDisabled(true)
        .background(Color(theme.paperBackground))
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
        .accessibilityHidden(true)
    }

    private func listItemPlaceholders(count: Int) -> some View {
        ForEach(0..<count, id: \.self) { _ in
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 0) {
                        placeholderBar(height: 16)
                        Color.clear
                            .frame(height: 16)
                            .frame(maxWidth: .infinity)
                    }
                    placeholderBar(height: 16)
                }
                placeholderBox(size: 52)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 24)
        }
    }

    private var cardRowPlaceholder: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 0) {
                placeholderBar(height: 16)
                Color.clear
                    .frame(height: 16)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 16)
            placeholderBar(height: 16)
                .padding(.horizontal, 16)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(0..<3, id: \.self) { _ in
                        cardPlaceholder
                    }
                }
                .padding(.horizontal, 16)
            }
            .scrollDisabled(true)
        }
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    private var cardPlaceholder: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(0..<16, id: \.self) { _ in
                placeholderBar(height: 16)
            }
        }
        .padding(16)
        .frame(width: 292, height: 400, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(theme.midBackground))
        )
    }

    private func placeholderBar(height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color(theme.border))
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .opacity(isPulsing ? 0.45 : 1)
    }

    private func placeholderBox(size: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color(theme.border))
            .frame(width: size, height: size)
            .opacity(isPulsing ? 0.45 : 1)
    }
}

// MARK: - Previews

#Preview("Lexical first") {
    WMFHybridSearchSkeletonView(group: .lexicalSemantic)
}

#Preview("Semantic first") {
    WMFHybridSearchSkeletonView(group: .semanticLexical)
}

#Preview("Control") {
    WMFHybridSearchSkeletonView(group: .control)
}
