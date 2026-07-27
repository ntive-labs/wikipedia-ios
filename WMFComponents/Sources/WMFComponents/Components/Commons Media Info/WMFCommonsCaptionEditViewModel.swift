import Foundation
import WMFData

/// View model for the Commons caption editor — iOS analogue of Android's caption path
/// (`DescriptionEditActivity` with `Action.ADD_CAPTION` → `postLabelEdit`).
@MainActor
public final class WMFCommonsCaptionEditViewModel: ObservableObject {

    public enum State: Equatable {
        case editing
        case publishing
        case published
        case error
    }

    public struct LocalizedStrings: Sendable {
        public let title: String
        public let instructions: String
        public let placeholder: String
        public let licenseNotice: String
        public let publishButtonTitle: String
        public let publishingButtonTitle: String
        public let errorTitle: String

        public init(title: String, instructions: String, placeholder: String, licenseNotice: String, publishButtonTitle: String, publishingButtonTitle: String, errorTitle: String) {
            self.title = title
            self.instructions = instructions
            self.placeholder = placeholder
            self.licenseNotice = licenseNotice
            self.publishButtonTitle = publishButtonTitle
            self.publishingButtonTitle = publishingButtonTitle
            self.errorTitle = errorTitle
        }
    }

    // MARK: - Inputs

    public let localizedStrings: LocalizedStrings
    public let commonsTitle: String
    public let languageCode: String
    public let isTranslation: Bool

    /// Called after a successful publish. The coordinator uses this to pop back and refresh the
    /// File Media Info screen in place (parity with Android's post-edit reload).
    public var didPublishSuccessfully: (() -> Void)?

    // MARK: - Published state

    @Published public var captionText: String = ""
    @Published public private(set) var state: State = .editing
    @Published public private(set) var errorMessage: String?

    // MARK: - Private

    private let dataController: WMFCommonsMediaInfoDataController

    public init(
        localizedStrings: LocalizedStrings,
        commonsTitle: String,
        languageCode: String,
        isTranslation: Bool,
        dataController: WMFCommonsMediaInfoDataController = WMFCommonsMediaInfoDataController()
    ) {
        self.localizedStrings = localizedStrings
        self.commonsTitle = commonsTitle
        self.languageCode = languageCode
        self.isTranslation = isTranslation
        self.dataController = dataController
    }

    public var canPublish: Bool {
        !captionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && state != .publishing
    }

    public func publish() {
        let value = captionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        state = .publishing
        errorMessage = nil
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.dataController.publishCaption(
                    title: self.commonsTitle,
                    languageCode: self.languageCode,
                    value: value,
                    isTranslation: self.isTranslation
                )
                self.state = .published
                self.didPublishSuccessfully?()
            } catch {
                self.errorMessage = (error as NSError).localizedDescription
                self.state = .error
            }
        }
    }
}
