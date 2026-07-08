import UIKit
import WMFData

/// View model backing ``WMFCommonsCaptionEditViewController``.
///
/// Drives the editor used to add or translate a structured MediaInfo caption (label) for a Commons
/// file, saved via ``WMFCommonsMediaInfoDataController`` (`action=wbsetlabel`). This mirrors Android's
/// caption-editing behaviour layered on the shared description-edit UI.
@MainActor
public final class WMFCommonsCaptionEditViewModel {

    // MARK: - Localized Strings

    public struct LocalizedStrings {
        public let addTitle: String
        public let editTitle: String
        public let translateTitle: String
        /// Format with two arguments: file title, then language display name.
        public let subtitleFormat: String
        public let placeholder: String
        public let publishButtonTitle: String
        public let licenseText: String
        public let loginText: String
        /// Format with two arguments: current count, then maximum.
        public let characterCountWarningFormat: String
        public let lengthWarning: String
        public let publishedToastTitle: String

        public init(addTitle: String, editTitle: String, translateTitle: String, subtitleFormat: String, placeholder: String, publishButtonTitle: String, licenseText: String, loginText: String, characterCountWarningFormat: String, lengthWarning: String, publishedToastTitle: String) {
            self.addTitle = addTitle
            self.editTitle = editTitle
            self.translateTitle = translateTitle
            self.subtitleFormat = subtitleFormat
            self.placeholder = placeholder
            self.publishButtonTitle = publishButtonTitle
            self.licenseText = licenseText
            self.loginText = loginText
            self.characterCountWarningFormat = characterCountWarningFormat
            self.lengthWarning = lengthWarning
            self.publishedToastTitle = publishedToastTitle
        }
    }

    // MARK: - Configuration

    public struct Config {
        public let fileTitle: String
        public let languageCode: String
        public let languageDisplayName: String
        public let imageThumbnailURL: URL?
        public let editType: WMFCommonsMediaInfoDataController.CaptionEditType
        public let existingCaption: String?

        public init(fileTitle: String, languageCode: String, languageDisplayName: String, imageThumbnailURL: URL?, editType: WMFCommonsMediaInfoDataController.CaptionEditType, existingCaption: String?) {
            self.fileTitle = fileTitle
            self.languageCode = languageCode
            self.languageDisplayName = languageDisplayName
            self.imageThumbnailURL = imageThumbnailURL
            self.editType = editType
            self.existingCaption = existingCaption
        }
    }

    // MARK: - Properties

    let config: Config
    let localizedStrings: LocalizedStrings

    /// Captions skip the article punctuation/capitalization rules but keep a minimum length and a
    /// max-character warning. Android caps captions at 250 characters.
    let maxCaptionLength = 250
    let minCaptionLength = 2

    private let dataController: WMFCommonsMediaInfoDataController

    /// Called on the main thread once a publish succeeds, passing the new revision id (if any).
    public var onPublishSucceeded: ((_ newRevisionID: Int?) -> Void)?
    /// Called on the main thread when a publish fails.
    public var onPublishFailed: ((Error) -> Void)?

    public init(config: Config, localizedStrings: LocalizedStrings, dataController: WMFCommonsMediaInfoDataController = WMFCommonsMediaInfoDataController()) {
        self.config = config
        self.localizedStrings = localizedStrings
        self.dataController = dataController
    }

    // MARK: - Derived Display Values

    /// The file title without the `File:` namespace prefix, for display.
    var displayFileTitle: String {
        let title = config.fileTitle
        if let range = title.range(of: "File:", options: [.caseInsensitive, .anchored]) {
            return String(title[range.upperBound...])
        }
        return title
    }

    var navigationTitle: String {
        switch config.editType {
        case .translate:
            return localizedStrings.translateTitle
        case .add:
            return config.existingCaption == nil ? localizedStrings.addTitle : localizedStrings.editTitle
        }
    }

    var subtitle: String {
        return String.localizedStringWithFormat(localizedStrings.subtitleFormat, displayFileTitle, config.languageDisplayName)
    }

    // MARK: - Validation

    func trimmedCaption(from text: String?) -> String {
        return (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func isValid(_ text: String?) -> Bool {
        return trimmedCaption(from: text).count >= minCaptionLength
    }

    func isOverLengthLimit(_ text: String?) -> Bool {
        return (text?.count ?? 0) > maxCaptionLength
    }

    func characterCountText(for text: String?) -> String {
        return String.localizedStringWithFormat(localizedStrings.characterCountWarningFormat, String(text?.count ?? 0), String(maxCaptionLength))
    }

    // MARK: - Networking

    func publish(caption: String) {
        let trimmed = trimmedCaption(from: caption)
        dataController.publishCaption(fileTitle: config.fileTitle, languageCode: config.languageCode, caption: trimmed, editType: config.editType) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let publishResult):
                    self.onPublishSucceeded?(publishResult.newRevisionID)
                case .failure(let error):
                    self.onPublishFailed?(error)
                }
            }
        }
    }
}
