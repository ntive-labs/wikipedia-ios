import UIKit
import WMFComponents
import WMFData
import WMFNativeLocalizations

/// Coordinator for the native Commons File Media Info screen and its caption / depicts editors.
///
/// Parity: this is the iOS analogue of Android's `FilePageActivity` launch + the
/// `DescriptionEditActivity` (caption) and `SuggestedEditsImageTagEditActivity` (depicts) flows,
/// including the post-publish success feedback and in-place metadata refresh.
final class MediaFileInfoCoordinator: NSObject, Coordinator {

    // MARK: - Coordinator

    var navigationController: UINavigationController

    // MARK: - Properties

    private let theme: Theme
    private let dataStore: MWKDataStore
    private let commonsTitle: String
    private let allowEdit: Bool
    private let languageCode: String
    private let articleProject: WMFProject?

    private weak var mediaInfoViewController: WMFFileMediaInfoViewController?

    // MARK: - Lifecycle

    init(navigationController: UINavigationController, theme: Theme, dataStore: MWKDataStore, commonsTitle: String, languageCode: String, allowEdit: Bool = true) {
        self.navigationController = navigationController
        self.theme = theme
        self.dataStore = dataStore
        self.commonsTitle = commonsTitle
        self.allowEdit = allowEdit
        self.languageCode = languageCode
        self.articleProject = WMFProject.wikipedia(WMFLanguage(languageCode: languageCode, languageVariantCode: nil))
        super.init()
    }

    // MARK: - Start

    @discardableResult
    func start() -> Bool {
        let viewModel = WMFFileMediaInfoViewModel(
            localizedStrings: Self.mediaInfoLocalizedStrings(),
            commonsTitle: commonsTitle,
            metadataLanguageCode: languageCode,
            captionLanguageCode: languageCode,
            allowEdit: allowEdit,
            articleProject: articleProject
        )

        viewModel.didTapViewOnCommons = { [weak self] url in
            self?.navigationController.navigate(to: url)
        }

        viewModel.didTapAddCaption = { [weak self] info, isTranslation in
            self?.presentCaptionEditor(for: info, isTranslation: isTranslation)
        }

        viewModel.didTapAddTags = { [weak self] info in
            self?.presentDepictsEditor(for: info)
        }

        let mediaInfoVC = WMFFileMediaInfoViewController(viewModel: viewModel)
        self.mediaInfoViewController = mediaInfoVC

        // Tie this coordinator's lifetime to the pushed view controller so the CTA closures stay alive.
        objc_setAssociatedObject(mediaInfoVC, &MediaFileInfoCoordinator.associatedKey, self, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

        navigationController.pushViewController(mediaInfoVC, animated: true)
        return true
    }

    private static var associatedKey: UInt8 = 0

    // MARK: - Caption editor

    private func presentCaptionEditor(for info: WMFCommonsMediaInfo, isTranslation: Bool) {
        let viewModel = WMFCommonsCaptionEditViewModel(
            localizedStrings: Self.captionLocalizedStrings(isTranslation: isTranslation),
            commonsTitle: info.title,
            languageCode: languageCode,
            isTranslation: isTranslation
        )

        let editorVC = WMFCommonsCaptionEditViewController(viewModel: viewModel)

        viewModel.didPublishSuccessfully = { [weak self, weak editorVC] in
            editorVC?.dismiss(animated: true) {
                self?.handlePublishSuccess(actionTitle: CommonStrings.mediaInfoCaptionPublishedToastTitle)
            }
        }

        let editorNav = WMFComponentNavigationController(rootViewController: editorVC, modalPresentationStyle: .formSheet)
        navigationController.present(editorNav, animated: true)
    }

    // MARK: - Depicts editor

    private func presentDepictsEditor(for info: WMFCommonsMediaInfo) {
        let viewModel = WMFCommonsDepictsEditViewModel(
            localizedStrings: Self.depictsLocalizedStrings(),
            commonsTitle: info.title,
            pageID: info.pageID,
            languageCode: languageCode
        )

        let editorVC = WMFCommonsDepictsEditViewController(viewModel: viewModel)

        viewModel.didPublishSuccessfully = { [weak self, weak editorVC] in
            editorVC?.dismiss(animated: true) {
                self?.handlePublishSuccess(actionTitle: CommonStrings.mediaInfoTagsPublishedToastTitle)
            }
        }

        let editorNav = WMFComponentNavigationController(rootViewController: editorVC, modalPresentationStyle: .formSheet)
        navigationController.present(editorNav, animated: true)
    }

    // MARK: - Success feedback + refresh

    private func handlePublishSuccess(actionTitle: String) {
        // Parity: Android shows a Suggested Edits success snackbar and reloads the file page metadata.
        mediaInfoViewController?.reloadMediaInfo()

        let image = UIImage(systemName: "checkmark.circle.fill")
        if UIAccessibility.isVoiceOverRunning {
            UIAccessibility.post(notification: .announcement, argument: actionTitle)
        } else {
            WMFToastManager.sharedInstance.showRichToast(actionTitle, subtitle: nil, image: image, dismissPreviousToasts: true, completion: {})
        }
    }

    // MARK: - Localized strings

    private static func mediaInfoLocalizedStrings() -> WMFFileMediaInfoViewModel.LocalizedStrings {
        WMFFileMediaInfoViewModel.LocalizedStrings(
            title: CommonStrings.mediaInfoTitle,
            captionHeader: CommonStrings.mediaInfoCaptionHeader,
            addCaptionButtonTitle: CommonStrings.mediaInfoAddCaptionButton,
            translateCaptionButtonTitle: CommonStrings.mediaInfoTranslateCaptionButton,
            tagsHeader: CommonStrings.mediaInfoTagsHeader,
            addTagsButtonTitle: CommonStrings.mediaInfoAddTagsButton,
            authorHeader: CommonStrings.mediaInfoAuthorHeader,
            dateHeader: CommonStrings.mediaInfoDateHeader,
            licenseHeader: CommonStrings.mediaInfoLicenseHeader,
            viewOnCommonsButtonTitle: CommonStrings.mediaInfoViewOnCommonsButton,
            errorTitle: CommonStrings.mediaInfoErrorTitle,
            errorRetryButtonTitle: CommonStrings.mediaInfoErrorRetryButton,
            noCaptionPlaceholder: CommonStrings.mediaInfoNoCaptionPlaceholder,
            noTagsPlaceholder: CommonStrings.mediaInfoNoTagsPlaceholder
        )
    }

    private static func captionLocalizedStrings(isTranslation: Bool) -> WMFCommonsCaptionEditViewModel.LocalizedStrings {
        WMFCommonsCaptionEditViewModel.LocalizedStrings(
            title: isTranslation ? CommonStrings.mediaInfoTranslateCaptionButton : CommonStrings.mediaInfoAddCaptionButton,
            instructions: CommonStrings.mediaInfoCaptionEditorInstructions,
            placeholder: CommonStrings.mediaInfoCaptionEditorPlaceholder,
            licenseNotice: CommonStrings.mediaInfoCaptionLicenseNotice,
            publishButtonTitle: CommonStrings.mediaInfoPublishButton,
            publishingButtonTitle: CommonStrings.mediaInfoPublishingButton,
            errorTitle: CommonStrings.mediaInfoErrorTitle
        )
    }

    private static func depictsLocalizedStrings() -> WMFCommonsDepictsEditViewModel.LocalizedStrings {
        WMFCommonsDepictsEditViewModel.LocalizedStrings(
            title: CommonStrings.mediaInfoAddTagsButton,
            instructions: CommonStrings.mediaInfoTagsEditorInstructions,
            searchPlaceholder: CommonStrings.mediaInfoTagsSearchPlaceholder,
            cc0Notice: CommonStrings.mediaInfoCC0Notice,
            publishButtonTitle: CommonStrings.mediaInfoPublishButton,
            publishingButtonTitle: CommonStrings.mediaInfoPublishingButton,
            exitConfirmationTitle: CommonStrings.mediaInfoTagsExitTitle,
            exitConfirmationMessage: CommonStrings.mediaInfoTagsExitMessage,
            exitConfirmationDiscard: CommonStrings.mediaInfoTagsExitDiscard,
            exitConfirmationKeepEditing: CommonStrings.mediaInfoTagsExitKeepEditing,
            errorTitle: CommonStrings.mediaInfoErrorTitle
        )
    }
}
