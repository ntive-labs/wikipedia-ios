import Foundation

/// View model for the hybrid search experiment onboarding screen. Mirrors Android's HybridSearchOnboardingActivity.
public final class WMFHybridSearchOnboardingViewModel {

    // MARK: - Localization

    public struct LocalizedStrings {
        public let betaTag: String
        public let title: String
        public let askQuestionsTitle: String
        public let askQuestionsDescription: String
        public let betaFeatureTitle: String
        public let betaFeatureDescription: String
        public let needInspirationTitle: String
        public let needInspirationDescription: String
        public let exampleQueries: [String]
        public let learnMoreButtonTitle: String
        public let getStartedButtonTitle: String

        public init(betaTag: String, title: String, askQuestionsTitle: String, askQuestionsDescription: String, betaFeatureTitle: String, betaFeatureDescription: String, needInspirationTitle: String, needInspirationDescription: String, exampleQueries: [String], learnMoreButtonTitle: String, getStartedButtonTitle: String) {
            self.betaTag = betaTag
            self.title = title
            self.askQuestionsTitle = askQuestionsTitle
            self.askQuestionsDescription = askQuestionsDescription
            self.betaFeatureTitle = betaFeatureTitle
            self.betaFeatureDescription = betaFeatureDescription
            self.needInspirationTitle = needInspirationTitle
            self.needInspirationDescription = needInspirationDescription
            self.exampleQueries = exampleQueries
            self.learnMoreButtonTitle = learnMoreButtonTitle
            self.getStartedButtonTitle = getStartedButtonTitle
        }
    }

    // MARK: - Properties

    let localizedStrings: LocalizedStrings
    let languageCode: String?

    public var onGetStarted: (() -> Void)?
    public var onExampleQueryTap: ((String) -> Void)?
    public var onLearnMore: (() -> Void)?

    /// Untranslated example queries for Greek, matching Android's strings_no_translate.xml.
    private static let greekExampleQueries = [
        "Πότε ο Πλούτωνας έπαψε να θεωρείται πλανήτης;",
        "Πρώτοι Ολυμπιακοί Αγώνες",
        "RNA vs DNA",
        "Η μεγαλύτερη λίμνη στην Ελλάδα",
        "Εθνικό πιάτο στην Ελλάδα"
    ]

    /// Untranslated example queries for French, matching Android's strings_no_translate.xml.
    private static let frenchExampleQueries = [
        "Pourquoi les étoiles semblent-elles scintiller la nuit ?",
        "Origine des Jeux Olympiques",
        "ADN ou ARN",
        "Pourquoi rêvons-nous ?",
        "Comment les langues disparaissent-elles ?"
    ]

    var exampleQueries: [String] {
        if languageCode?.caseInsensitiveCompare("el") == .orderedSame {
            return Self.greekExampleQueries
        }
        if languageCode?.caseInsensitiveCompare("fr") == .orderedSame {
            return Self.frenchExampleQueries
        }
        return localizedStrings.exampleQueries
    }

    // MARK: - Lifecycle

    public init(localizedStrings: LocalizedStrings, languageCode: String?, onGetStarted: (() -> Void)? = nil, onExampleQueryTap: ((String) -> Void)? = nil, onLearnMore: (() -> Void)? = nil) {
        self.localizedStrings = localizedStrings
        self.languageCode = languageCode
        self.onGetStarted = onGetStarted
        self.onExampleQueryTap = onExampleQueryTap
        self.onLearnMore = onLearnMore
    }
}
