import UIKit
import WMFData

/// View model backing ``WMFCommonsTagsEditViewController``.
///
/// Drives the editor used to add structured "depicts" (Wikidata P180) tags to a Commons file,
/// published via ``WMFCommonsMediaInfoDataController.publishDepicts`` (`action=wbeditentity`). This is
/// the iOS port of Android's `SuggestedEditsImageTagsFragment` + `SuggestedEditsImageTagDialog`.
@MainActor
public final class WMFCommonsTagsEditViewModel {

    // MARK: - Localized Strings

    public struct LocalizedStrings {
        public let title: String
        /// Format with one argument: the file name.
        public let subtitleFormat: String
        public let addTagButtonTitle: String
        public let publishButtonTitle: String
        public let cc0NoticeText: String
        public let searchTitle: String
        public let searchPlaceholder: String
        public let exitConfirmationTitle: String
        public let exitConfirmationMessage: String
        public let exitConfirmationDiscard: String
        public let exitConfirmationKeepEditing: String
        public let publishedToastTitle: String

        public init(title: String, subtitleFormat: String, addTagButtonTitle: String, publishButtonTitle: String, cc0NoticeText: String, searchTitle: String, searchPlaceholder: String, exitConfirmationTitle: String, exitConfirmationMessage: String, exitConfirmationDiscard: String, exitConfirmationKeepEditing: String, publishedToastTitle: String) {
            self.title = title
            self.subtitleFormat = subtitleFormat
            self.addTagButtonTitle = addTagButtonTitle
            self.publishButtonTitle = publishButtonTitle
            self.cc0NoticeText = cc0NoticeText
            self.searchTitle = searchTitle
            self.searchPlaceholder = searchPlaceholder
            self.exitConfirmationTitle = exitConfirmationTitle
            self.exitConfirmationMessage = exitConfirmationMessage
            self.exitConfirmationDiscard = exitConfirmationDiscard
            self.exitConfirmationKeepEditing = exitConfirmationKeepEditing
            self.publishedToastTitle = publishedToastTitle
        }
    }

    // MARK: - Configuration

    public struct Config {
        public let fileTitle: String
        public let pageID: Int
        public let languageCode: String
        public let imageThumbnailURL: URL?

        public init(fileTitle: String, pageID: Int, languageCode: String, imageThumbnailURL: URL?) {
            self.fileTitle = fileTitle
            self.pageID = pageID
            self.languageCode = languageCode
            self.imageThumbnailURL = imageThumbnailURL
        }
    }

    // MARK: - Properties

    let config: Config
    let localizedStrings: LocalizedStrings

    /// The tags the user has selected to publish.
    private(set) var selectedTags: [WMFDepictsTag] = []

    private let dataController: WMFCommonsMediaInfoDataController
    private let searchDataController: WMFWikidataItemSearchDataController

    /// Called on the main thread when the selected-tags set changes so the view can rerender chips.
    public var onSelectedTagsChanged: (() -> Void)?
    /// Called on the main thread once a publish succeeds, passing the new revision id (if any).
    public var onPublishSucceeded: ((_ newRevisionID: Int?) -> Void)?
    /// Called on the main thread when a publish fails.
    public var onPublishFailed: ((Error) -> Void)?

    public init(config: Config, localizedStrings: LocalizedStrings, dataController: WMFCommonsMediaInfoDataController = WMFCommonsMediaInfoDataController(), searchDataController: WMFWikidataItemSearchDataController = WMFWikidataItemSearchDataController()) {
        self.config = config
        self.localizedStrings = localizedStrings
        self.dataController = dataController
        self.searchDataController = searchDataController
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

    var subtitle: String {
        return String.localizedStringWithFormat(localizedStrings.subtitleFormat, displayFileTitle)
    }

    /// Publish is only possible once at least one tag is selected (Android parity).
    var canPublish: Bool {
        return !selectedTags.isEmpty
    }

    /// Whether there are unpublished selected tags, driving the exit-guard confirmation
    /// (Android `onBackPressed` dialog, commit `4cb33204e3`).
    var hasUnpublishedTags: Bool {
        return !selectedTags.isEmpty
    }

    // MARK: - Selection

    /// Adds a tag to the selection unless it is already present. Returns true if the set changed.
    @discardableResult
    func addTag(_ tag: WMFDepictsTag) -> Bool {
        guard !selectedTags.contains(where: { $0.wikidataID == tag.wikidataID }) else {
            return false
        }
        var newTag = tag
        newTag.isSelected = true
        selectedTags.append(newTag)
        onSelectedTagsChanged?()
        return true
    }

    func removeTag(_ tag: WMFDepictsTag) {
        selectedTags.removeAll { $0.wikidataID == tag.wikidataID }
        onSelectedTagsChanged?()
    }

    func isSelected(_ tag: WMFDepictsTag) -> Bool {
        return selectedTags.contains { $0.wikidataID == tag.wikidataID }
    }

    // MARK: - Networking

    func search(term: String) async -> [WMFDepictsTag] {
        do {
            return try await searchDataController.search(term: term, languageCode: config.languageCode)
        } catch {
            return []
        }
    }

    func publish() {
        guard canPublish else { return }
        dataController.publishDepicts(pageID: config.pageID, tags: selectedTags) { [weak self] result in
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
