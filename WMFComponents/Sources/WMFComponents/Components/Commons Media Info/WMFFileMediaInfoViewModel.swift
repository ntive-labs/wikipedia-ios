import Foundation
import UIKit
import WMFData

/// Logging delegate for the File Media Info screen (impressions + CTA taps).
/// Parity: Android logs edit-attempt / image-recommendation events on this surface.
@MainActor
public protocol WMFFileMediaInfoLoggingDelegate: AnyObject {
    func logFileMediaInfoDidAppear()
    func logFileMediaInfoDidTapAddCaption()
    func logFileMediaInfoDidTapAddTags()
    func logFileMediaInfoDidTapViewOnCommons()
}

/// View model for the File Media Info screen — the iOS analogue of Android's `FilePageViewModel`
/// + `FilePageView` state. Loads metadata, computes Android-parity eligibility, and drives the CTAs.
@MainActor
public final class WMFFileMediaInfoViewModel: ObservableObject {

    // MARK: - Nested Types

    public enum State: Equatable {
        case loading
        case loaded
        case error
    }

    public struct LocalizedStrings: Sendable {
        public let title: String
        public let captionHeader: String
        public let addCaptionButtonTitle: String
        public let translateCaptionButtonTitle: String
        public let tagsHeader: String
        public let addTagsButtonTitle: String
        public let authorHeader: String
        public let dateHeader: String
        public let licenseHeader: String
        public let viewOnCommonsButtonTitle: String
        public let errorTitle: String
        public let errorRetryButtonTitle: String
        public let noCaptionPlaceholder: String
        public let noTagsPlaceholder: String

        public init(
            title: String,
            captionHeader: String,
            addCaptionButtonTitle: String,
            translateCaptionButtonTitle: String,
            tagsHeader: String,
            addTagsButtonTitle: String,
            authorHeader: String,
            dateHeader: String,
            licenseHeader: String,
            viewOnCommonsButtonTitle: String,
            errorTitle: String,
            errorRetryButtonTitle: String,
            noCaptionPlaceholder: String,
            noTagsPlaceholder: String
        ) {
            self.title = title
            self.captionHeader = captionHeader
            self.addCaptionButtonTitle = addCaptionButtonTitle
            self.translateCaptionButtonTitle = translateCaptionButtonTitle
            self.tagsHeader = tagsHeader
            self.addTagsButtonTitle = addTagsButtonTitle
            self.authorHeader = authorHeader
            self.dateHeader = dateHeader
            self.licenseHeader = licenseHeader
            self.viewOnCommonsButtonTitle = viewOnCommonsButtonTitle
            self.errorTitle = errorTitle
            self.errorRetryButtonTitle = errorRetryButtonTitle
            self.noCaptionPlaceholder = noCaptionPlaceholder
            self.noTagsPlaceholder = noTagsPlaceholder
        }
    }

    // MARK: - Inputs

    public let localizedStrings: LocalizedStrings
    /// Fully-prefixed Commons title, e.g. "File:Example.jpg".
    public let commonsTitle: String
    public let metadataLanguageCode: String
    public let captionLanguageCode: String
    public let allowEdit: Bool
    public let articleProject: WMFProject?

    /// Coordinator hooks — launched from the CTAs (set by the app-side coordinator).
    public var didTapAddCaption: ((WMFCommonsMediaInfo, _ isTranslation: Bool) -> Void)?
    public var didTapAddTags: ((WMFCommonsMediaInfo) -> Void)?
    public var didTapViewOnCommons: ((URL) -> Void)?

    public weak var loggingDelegate: WMFFileMediaInfoLoggingDelegate?

    // MARK: - Published state

    @Published public private(set) var state: State = .loading
    @Published public private(set) var mediaInfo: WMFCommonsMediaInfo?
    @Published public private(set) var thumbnail: UIImage?

    // MARK: - Private

    private let dataController: WMFCommonsMediaInfoDataController
    private var loadTask: Task<Void, Never>?

    // MARK: - Lifecycle

    public init(
        localizedStrings: LocalizedStrings,
        commonsTitle: String,
        metadataLanguageCode: String,
        captionLanguageCode: String,
        allowEdit: Bool,
        articleProject: WMFProject? = nil,
        dataController: WMFCommonsMediaInfoDataController = WMFCommonsMediaInfoDataController()
    ) {
        self.localizedStrings = localizedStrings
        self.commonsTitle = commonsTitle
        self.metadataLanguageCode = metadataLanguageCode
        self.captionLanguageCode = captionLanguageCode
        self.allowEdit = allowEdit
        self.articleProject = articleProject
        self.dataController = dataController
    }

    deinit {
        loadTask?.cancel()
    }

    // MARK: - Derived, RTL

    public var semanticContentAttribute: UISemanticContentAttribute {
        let language = WMFLanguage(languageCode: captionLanguageCode, languageVariantCode: nil)
        return WMFProject.wikipedia(language).isRTL ? .forceRightToLeft : .forceLeftToRight
    }

    // MARK: - Loading

    public func loadMediaInfo() {
        loadTask?.cancel()
        state = .loading
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let info = try await self.dataController.loadMediaInfo(
                    commonsTitle: self.commonsTitle,
                    metadataLanguage: self.metadataLanguageCode,
                    captionLanguage: self.captionLanguageCode,
                    articleProject: self.articleProject,
                    allowEdit: self.allowEdit
                )
                if Task.isCancelled { return }
                self.mediaInfo = info
                self.state = .loaded
                self.loadThumbnail(url: info.thumbURL)
            } catch {
                if Task.isCancelled { return }
                self.state = .error
            }
        }
    }

    private func loadThumbnail(url: URL?) {
        guard let url else { return }
        Task { [weak self] in
            guard let self else { return }
            if let data = try? await WMFImageDataController.shared.fetchImageData(url: url) {
                self.thumbnail = UIImage(data: data)
            }
        }
    }

    // MARK: - CTA actions

    func tappedAddCaption(isTranslation: Bool) {
        guard let mediaInfo else { return }
        loggingDelegate?.logFileMediaInfoDidTapAddCaption()
        didTapAddCaption?(mediaInfo, isTranslation)
    }

    func tappedAddTags() {
        guard let mediaInfo else { return }
        loggingDelegate?.logFileMediaInfoDidTapAddTags()
        didTapAddTags?(mediaInfo)
    }

    func tappedViewOnCommons() {
        guard let url = mediaInfo?.filePageURL else { return }
        loggingDelegate?.logFileMediaInfoDidTapViewOnCommons()
        didTapViewOnCommons?(url)
    }
}
