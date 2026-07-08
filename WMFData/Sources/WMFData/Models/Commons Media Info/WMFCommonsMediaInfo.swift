import Foundation

/// A structured MediaInfo caption (label) on a Commons file, in a single language.
///
/// A caption is distinct from the file page's wikitext description (`extmetadata.ImageDescription`);
/// it is a Wikibase `label` on the `M<pageid>` MediaInfo entity.
public struct WMFMediaInfoCaption: Equatable, Sendable {
    public let languageCode: String
    public let value: String

    public init(languageCode: String, value: String) {
        self.languageCode = languageCode
        self.value = value
    }
}

/// A single "depicts" (Wikidata property P180) structured tag on a Commons file, resolved to a
/// human-readable label. Mirrors Android's `ImageTag`.
public struct WMFDepictsTag: Equatable, Sendable, Identifiable {
    /// The Wikidata item id, e.g. "Q146".
    public let wikidataID: String
    public var label: String
    public var description: String?
    /// UI-side selection flag used by the tags editor.
    public var isSelected: Bool

    public var id: String { wikidataID }

    public init(wikidataID: String, label: String, description: String? = nil, isSelected: Bool = false) {
        self.wikidataID = wikidataID
        self.label = label
        self.description = description
        self.isSelected = isSelected
    }
}

/// Author / date / source / licence details drawn from a Commons file's `extmetadata`.
public struct WMFCommonsMediaMetadata: Equatable, Sendable {
    public let imageDescription: String?
    public let artist: String?
    public let dateTime: String?
    public let credit: String?
    public let licenseShortName: String?
    public let licenseURL: String?

    public init(imageDescription: String?, artist: String?, dateTime: String?, credit: String?, licenseShortName: String?, licenseURL: String?) {
        self.imageDescription = imageDescription
        self.artist = artist
        self.dateTime = dateTime
        self.credit = credit
        self.licenseShortName = licenseShortName
        self.licenseURL = licenseURL
    }
}

/// The full media-info payload backing the file/media detail contribution surface, mirroring
/// Android's `FilePage` + `FilePageViewModel` state.
///
/// The `showAddCaption` / `showAddTags` properties encapsulate the eligibility + CTA rules so they
/// cannot silently drift from Android (`FilePageView.setup()`):
/// - Add caption when the caption for the proper language is empty **and** the file is editable.
/// - Add image tags when there are no depicts tags **and** the file is editable.
public struct WMFCommonsMediaInfo: Equatable, Sendable {

    /// The MediaInfo entity page id (the numeric part of `M<pageID>`).
    public let pageID: Int
    /// The prefixed file title, e.g. "File:Example.jpg".
    public let title: String
    /// Whether the file is natively hosted on Commons (Android `!isImageShared`). Only Commons-native
    /// files are editable from the app.
    public let isFromCommons: Bool
    public let thumbURL: URL?
    public let fullURL: URL?
    public let mimeType: String?
    public let thumbnailWidth: Int?
    public let thumbnailHeight: Int?
    public let metadata: WMFCommonsMediaMetadata?
    /// The structured caption in the user's proper language, if one exists.
    public let caption: WMFMediaInfoCaption?
    public let isEditProtected: Bool
    public let depicts: [WMFDepictsTag]
    /// Whether the launching context permits editing (Android's `allowEdit`; the Image Recommendations
    /// file page opens with `allowEdit == false`).
    public let allowEdit: Bool
    /// The user's proper content language for this file, used for caption / tag CTAs.
    public let languageCode: String

    public init(pageID: Int, title: String, isFromCommons: Bool, thumbURL: URL?, fullURL: URL?, mimeType: String?, thumbnailWidth: Int?, thumbnailHeight: Int?, metadata: WMFCommonsMediaMetadata?, caption: WMFMediaInfoCaption?, isEditProtected: Bool, depicts: [WMFDepictsTag], allowEdit: Bool, languageCode: String) {
        self.pageID = pageID
        self.title = title
        self.isFromCommons = isFromCommons
        self.thumbURL = thumbURL
        self.fullURL = fullURL
        self.mimeType = mimeType
        self.thumbnailWidth = thumbnailWidth
        self.thumbnailHeight = thumbnailHeight
        self.metadata = metadata
        self.caption = caption
        self.isEditProtected = isEditProtected
        self.depicts = depicts
        self.allowEdit = allowEdit
        self.languageCode = languageCode
    }

    /// The MediaInfo entity id, e.g. "M12345".
    public var mediaInfoEntityID: String {
        return "M\(pageID)"
    }

    /// Android parity: `showEditButton = allowEdit && isFromCommons && !isEditProtected`.
    public var canEdit: Bool {
        return allowEdit && isFromCommons && !isEditProtected
    }

    /// Whether the caption in the user's proper language is missing.
    public var hasCaptionInLanguage: Bool {
        guard let caption else { return false }
        return caption.languageCode == languageCode && !caption.value.isEmpty
    }

    /// Android parity: show the "Add caption" CTA when the caption is empty and the file is editable.
    public var showAddCaption: Bool {
        return canEdit && !hasCaptionInLanguage
    }

    /// Android parity: show the "Add image tags" CTA when depicts are empty and the file is editable.
    public var showAddTags: Bool {
        return canEdit && depicts.isEmpty
    }
}
