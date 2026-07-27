import Foundation

/// A structured caption (MediaInfo label) for a Commons file, in a specific language.
/// Parity: Android reads this from `entityterms.label.first` and stores it on `PageTitle.description`.
public struct WMFMediaInfoCaption: Sendable, Equatable {
    public let languageCode: String
    public let value: String

    public init(languageCode: String, value: String) {
        self.languageCode = languageCode
        self.value = value
    }
}

/// A single "depicts" (P180) image tag resolved to a Wikidata label.
/// Parity: Android `ImageTag` (wikidataId + label), plus a UI-side selection flag used by the tags editor.
public struct WMFDepictsTag: Sendable, Equatable, Identifiable {
    public let wikidataID: String
    public let label: String
    public let description: String?
    public var isSelected: Bool

    public var id: String { wikidataID }

    public init(wikidataID: String, label: String, description: String? = nil, isSelected: Bool = false) {
        self.wikidataID = wikidataID
        self.label = label
        self.description = description
        self.isSelected = isSelected
    }
}

/// Author/date/source/license metadata parsed from the imageinfo `extmetadata` block.
/// Parity: Android renders these fields in `FilePageView` (author, date, source, license short name + link).
public struct WMFCommonsMediaMetadata: Sendable, Equatable {
    public let author: String?
    public let dateTime: String?
    public let credit: String?
    public let licenseShortName: String?
    public let licenseURL: String?

    public init(author: String?, dateTime: String?, credit: String?, licenseShortName: String?, licenseURL: String?) {
        self.author = author
        self.dateTime = dateTime
        self.credit = credit
        self.licenseShortName = licenseShortName
        self.licenseURL = licenseURL
    }
}

/// The full media-info model backing the File Media Info screen.
/// Parity: Android `FilePage` (`commons/FilePage.kt`) plus the fields resolved in `FilePageViewModel.loadImageInfo()`.
public struct WMFCommonsMediaInfo: Sendable, Equatable {

    public let pageID: Int
    /// Fully-prefixed title, e.g. "File:Example.jpg".
    public let title: String
    /// True when the file is natively hosted on Commons (Android: `!isImageShared`).
    public let isFromCommons: Bool
    public let thumbURL: URL?
    public let fullURL: URL?
    public let filePageURL: URL?
    public let mimeType: String?
    public let width: Int?
    public let height: Int?
    public let metadata: WMFCommonsMediaMetadata
    /// The structured MediaInfo caption in the requested language, if present.
    public let caption: WMFMediaInfoCaption?
    /// Any caption in a language other than the requested one (drives the "translate" affordance).
    public let captionInOtherLanguage: WMFMediaInfoCaption?
    public let isEditProtected: Bool
    public let depicts: [WMFDepictsTag]
    /// The requested caption / tag language ("proper language code" in Android terms).
    public let properLanguageCode: String
    /// Whether the entry point allows editing at all (Android `allowEdit`, defaults true).
    public let allowEdit: Bool

    public init(
        pageID: Int,
        title: String,
        isFromCommons: Bool,
        thumbURL: URL?,
        fullURL: URL?,
        filePageURL: URL?,
        mimeType: String?,
        width: Int?,
        height: Int?,
        metadata: WMFCommonsMediaMetadata,
        caption: WMFMediaInfoCaption?,
        captionInOtherLanguage: WMFMediaInfoCaption?,
        isEditProtected: Bool,
        depicts: [WMFDepictsTag],
        properLanguageCode: String,
        allowEdit: Bool
    ) {
        self.pageID = pageID
        self.title = title
        self.isFromCommons = isFromCommons
        self.thumbURL = thumbURL
        self.fullURL = fullURL
        self.filePageURL = filePageURL
        self.mimeType = mimeType
        self.width = width
        self.height = height
        self.metadata = metadata
        self.caption = caption
        self.captionInOtherLanguage = captionInOtherLanguage
        self.isEditProtected = isEditProtected
        self.depicts = depicts
        self.properLanguageCode = properLanguageCode
        self.allowEdit = allowEdit
    }

    // MARK: - Derived eligibility (must match Android exactly)

    /// Parity: Android `FilePage.showEditButton = allowEdit && isFromCommons && !isEditProtected`.
    public var canEdit: Bool {
        return allowEdit && isFromCommons && !isEditProtected
    }

    /// Parity: `FilePageView` shows the "Add caption" CTA when the caption for the proper language
    /// is empty AND the file is editable.
    public var shouldShowAddCaption: Bool {
        return canEdit && (caption?.value.isEmpty ?? true)
    }

    /// A caption exists in another language but not the user's proper language and the file is editable.
    /// Parity: Android offers a "translate" action in this case.
    public var shouldShowTranslateCaption: Bool {
        return canEdit && (caption?.value.isEmpty ?? true) && (captionInOtherLanguage != nil)
    }

    /// Parity: `FilePageView` shows the "Add image tags" CTA when depicts has no entry for the proper
    /// language AND the file is editable.
    public var shouldShowAddTags: Bool {
        return canEdit && depicts.isEmpty
    }
}
