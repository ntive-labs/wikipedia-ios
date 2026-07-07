import Foundation
import WMFComponents
import WMFData
import WMF
import WMFNativeLocalizations

@objc extension WMFImageGalleryViewController {
    @objc static func closeButtonImage() -> UIImage? {
        return WMFSFSymbolIcon.for(symbol: .close)
    }
}

// MARK: - Commons Caption Editing (Objective-C entry points)

@objc extension WMFImageGalleryViewController {

    /// SF Symbol used for the "Add caption" affordance in the gallery detail overlay.
    @objc static func captionEditButtonImage() -> UIImage? {
        return WMFSFSymbolIcon.for(symbol: .pencil)
    }

    /// Presents the Commons caption editor for the given image.
    ///
    /// Resolves the Commons `File:` title from the image info, looks up any existing caption in the
    /// user's primary content language to decide add vs. edit + prefill, then presents
    /// ``WMFCommonsCaptionEditViewController``. Publishing writes a structured MediaInfo label via
    /// `action=wbsetlabel`, tagged `app-image-caption-add`, mirroring Android's gallery caption flow.
    @objc(wmf_presentCommonsCaptionEditorForImageInfo:)
    func wmf_presentCommonsCaptionEditor(for imageInfo: MWKImageInfo) {

        guard let fileTitle = imageInfo.canonicalPageTitle else {
            return
        }

        let dataStore = MWKDataStore.shared()
        guard let appLanguage = dataStore.languageLinkController.appLanguage else {
            return
        }

        let languageCode = appLanguage.languageCode
        let languageDisplayName = appLanguage.localizedName

        let dataController = WMFCommonsMediaInfoDataController()

        // Look up an existing caption in the primary language so we can prefill and title the screen
        // correctly. If the lookup fails we still let the user add a caption.
        dataController.fetchCaption(fileTitle: fileTitle, languageCode: languageCode) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                let existingCaption: String?
                switch result {
                case .success(let caption):
                    existingCaption = caption
                case .failure:
                    existingCaption = nil
                }

                self.presentCaptionEditor(fileTitle: fileTitle, languageCode: languageCode, languageDisplayName: languageDisplayName, imageThumbnailURL: imageInfo.imageThumbURL, existingCaption: existingCaption, dataStore: dataStore)
            }
        }
    }
}

// MARK: - Commons Caption Editing (presentation helpers)

extension WMFImageGalleryViewController {

    fileprivate func presentCaptionEditor(fileTitle: String, languageCode: String, languageDisplayName: String, imageThumbnailURL: URL?, existingCaption: String?, dataStore: MWKDataStore) {

        let theme = Theme.withName(UserDefaults.standard.themeName) ?? Theme.standard

        let config = WMFCommonsCaptionEditViewModel.Config(
            fileTitle: fileTitle,
            languageCode: languageCode,
            languageDisplayName: languageDisplayName,
            imageThumbnailURL: imageThumbnailURL,
            editType: .add,
            existingCaption: existingCaption
        )

        let localizedStrings = Self.captionEditLocalizedStrings()
        let viewModel = WMFCommonsCaptionEditViewModel(config: config, localizedStrings: localizedStrings)

        let showsLoginPrompt = !dataStore.authenticationManager.authStateIsPermanent
        let captionEditVC = WMFCommonsCaptionEditViewController(viewModel: viewModel, showsLoginPrompt: showsLoginPrompt)

        let navigationController = WMFComponentNavigationController(rootViewController: captionEditVC, modalPresentationStyle: .pageSheet)

        let publishedToastTitle = localizedStrings.publishedToastTitle
        viewModel.onPublishSucceeded = { [weak captionEditVC] _ in
            captionEditVC?.dismiss(animated: true) {
                WMFToastManager.sharedInstance.showToast(publishedToastTitle, sticky: false, dismissPreviousToasts: true)
            }
        }

        viewModel.onPublishFailed = { [weak captionEditVC] error in
            guard let captionEditVC else { return }
            captionEditVC.handlePublishFailure()
            WMFImageGalleryViewController.handleCaptionPublishFailure(error, in: captionEditVC, fileTitle: fileTitle, theme: theme)
        }

        captionEditVC.didTapClose = { [weak captionEditVC] in
            captionEditVC?.dismiss(animated: true)
        }

        present(navigationController, animated: true)
    }

    fileprivate static func handleCaptionPublishFailure(_ error: Error, in viewController: UIViewController, fileTitle: String, theme: Theme) {

        // Unwrap the data controller error to reach the resolved blocked / abuse-filter display error.
        if case WMFCommonsMediaInfoDataController.WMFCommonsMediaInfoError.serviceError(let inner) = error,
           let mediaWikiError = inner as? MediaWikiFetcher.MediaWikiFetcherError,
           case .mediaWikiAPIResponseError(let displayError) = mediaWikiError {

            let linkBaseURL = displayError.linkBaseURL

            if displayError.code.contains("block") {
                viewController.wmf_showBlockedPanel(messageHtml: displayError.messageHtml, linkBaseURL: linkBaseURL, currentTitle: fileTitle, theme: theme)
                return
            } else if displayError.code.contains("abusefilter") {
                if displayError.code == "abusefilter-disallowed" {
                    viewController.wmf_showAbuseFilterDisallowPanel(messageHtml: displayError.messageHtml, linkBaseURL: linkBaseURL, currentTitle: fileTitle, theme: theme, goBackIsOnlyDismiss: true)
                } else {
                    viewController.wmf_showAbuseFilterWarningPanel(messageHtml: displayError.messageHtml, linkBaseURL: linkBaseURL, currentTitle: fileTitle, theme: theme, goBackIsOnlyDismiss: true, publishAnywayTapHandler: {})
                }
                return
            }
        }

        WMFToastManager.sharedInstance.showErrorAlert(error as NSError, sticky: true, dismissPreviousToasts: true, tapCallBack: nil)
    }

    fileprivate static func captionEditLocalizedStrings() -> WMFCommonsCaptionEditViewModel.LocalizedStrings {
        return WMFCommonsCaptionEditViewModel.LocalizedStrings(
            addTitle: WMFLocalizedString("commons-caption-add-title", value: "Add caption", comment: "Title for the screen where a user adds a caption to a Commons image."),
            editTitle: WMFLocalizedString("commons-caption-edit-title", value: "Edit caption", comment: "Title for the screen where a user edits an existing caption on a Commons image."),
            translateTitle: WMFLocalizedString("commons-caption-translate-title", value: "Translate caption", comment: "Title for the screen where a user translates a caption on a Commons image into another language."),
            subtitleFormat: WMFLocalizedString("commons-caption-subtitle", value: "Caption for %1$@ in %2$@", comment: "Subtitle describing which file and language a caption is being written for. %1$@ is replaced with the file name, %2$@ with the language name."),
            placeholder: WMFLocalizedString("commons-caption-placeholder", value: "Describe this file", comment: "Placeholder text shown in the caption text field before the user types."),
            publishButtonTitle: WMFLocalizedString("commons-caption-publish", value: "Publish caption", comment: "Title for the button that publishes a Commons image caption."),
            licenseText: WMFLocalizedString("commons-caption-license", value: "By publishing this caption, I agree to release my contribution under the CC0 license.", comment: "Text informing the user that publishing a caption releases it under the CC0 license."),
            loginText: WMFLocalizedString("commons-caption-login-attribution", value: "Edits will be attributed to the IP address of your device. Log in for more privacy.", comment: "Attribution notice shown to logged-out users in the caption editor, encouraging them to log in."),
            characterCountWarningFormat: WMFLocalizedString("commons-caption-length-warning", value: "%1$@ / %2$@", comment: "Displays how many caption characters were entered. %1$@ is the number of characters entered, %2$@ is the maximum recommended number."),
            lengthWarning: WMFLocalizedString("commons-caption-too-long", value: "Captions should be short, single-sentence descriptions.", comment: "Warning reminding the user to keep captions short."),
            publishedToastTitle: WMFLocalizedString("commons-caption-published", value: "Caption published", comment: "Toast shown after a Commons image caption is successfully published.")
        )
    }
}
