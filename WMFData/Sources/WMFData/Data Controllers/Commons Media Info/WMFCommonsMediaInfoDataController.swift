import Foundation

/// Reads and writes structured metadata (caption + depicts tags) for a Commons-hosted media file.
///
/// Parity: this is the iOS analogue of Android's `FilePageViewModel.loadImageInfo()` +
/// `ImageTagsProvider` (reads) and `DescriptionEditViewModel.postLabelEdit` +
/// `SuggestedEditsImageTagsViewModel.publishImageTags` (writes).
public actor WMFCommonsMediaInfoDataController {

    // MARK: - Constants

    /// Parity: Android `Service.PREFERRED_THUMB_SIZE`.
    private static let preferredThumbWidth = 640

    // MARK: - Errors

    public enum CommonsMediaInfoError: Error {
        case noImageInfoFound
        case invalidPageID
    }

    // MARK: - Properties

    private let service: WMFService?

    // MARK: - Lifecycle

    public init(service: WMFService? = WMFDataEnvironment.current.mediaWikiService) {
        self.service = service
    }

    // MARK: - Combined load (parity: FilePageViewModel.loadImageInfo)

    /// Loads the full media-info model for a Commons file, mirroring Android's
    /// `FilePageViewModel.loadImageInfo()`: imageinfo/entityterms first, then protection + depicts
    /// concurrently, folded into eligibility flags.
    ///
    /// - Parameters:
    ///   - commonsTitle: fully-prefixed title, e.g. "File:Example.jpg".
    ///   - metadataLanguage: language for `extmetadata` (Android: the article wiki language).
    ///   - captionLanguage: language for the MediaInfo caption / tags ("proper language code").
    ///   - articleProject: the wiki the file surfaced from, used for the non-Commons fallback.
    ///   - allowEdit: whether the entry point permits editing (Android `allowEdit`, default true).
    public func loadMediaInfo(
        commonsTitle: String,
        metadataLanguage: String,
        captionLanguage: String,
        articleProject: WMFProject? = nil,
        allowEdit: Bool = true
    ) async throws -> WMFCommonsMediaInfo {

        var isFromCommons = false
        var response = try await fetchImageInfoResponse(
            project: .commons,
            title: commonsTitle,
            metadataLanguage: metadataLanguage,
            captionLanguage: captionLanguage
        )
        var page = response.query?.pages?.first

        // Structured caption (Android: pageTitle.description = entityTerms.label.first).
        let captionValue = page?.entityterms?.label?.first

        if page?.imageinfo?.first == nil {
            // Non-Commons file page (e.g. movie posters on *.wikipedia.org). Fall back to the file's
            // own wiki and treat as non-Commons — parity with Android's fallback branch.
            if let articleProject {
                response = try await fetchImageInfoResponse(
                    project: articleProject,
                    title: commonsTitle,
                    metadataLanguage: metadataLanguage,
                    captionLanguage: captionLanguage
                )
                page = response.query?.pages?.first
            }
        } else {
            isFromCommons = !(page?.isImageShared ?? false)
        }

        guard let page, let imageInfo = page.imageinfo?.first, let pageID = page.pageid else {
            throw CommonsMediaInfoError.noImageInfoFound
        }

        // Concurrently resolve protection and depicts (Android uses two async {} blocks).
        let fromCommons = isFromCommons
        let protectionProject: WMFProject = fromCommons ? .commons : (articleProject ?? .commons)
        async let isEditProtected = fetchProtection(project: protectionProject, title: commonsTitle)
        async let depicts = fetchDepicts(pageID: pageID, wikidataLanguage: captionLanguage)

        let caption: WMFMediaInfoCaption?
        if let captionValue, !captionValue.isEmpty {
            caption = WMFMediaInfoCaption(languageCode: captionLanguage, value: captionValue)
        } else {
            caption = nil
        }

        let metadata = WMFCommonsMediaMetadata(
            author: imageInfo.extmetadata?.artist?.value,
            dateTime: imageInfo.extmetadata?.dateTime?.value,
            credit: imageInfo.extmetadata?.credit?.value,
            licenseShortName: imageInfo.extmetadata?.licenseShortName?.value,
            licenseURL: imageInfo.extmetadata?.licenseUrl?.value
        )

        return WMFCommonsMediaInfo(
            pageID: pageID,
            title: page.title ?? commonsTitle,
            isFromCommons: fromCommons,
            thumbURL: imageInfo.thumburl.flatMap { URL(string: $0) },
            fullURL: imageInfo.url.flatMap { URL(string: $0) },
            filePageURL: imageInfo.descriptionurl.flatMap { URL(string: $0) },
            mimeType: imageInfo.mime,
            width: imageInfo.thumbwidth,
            height: imageInfo.thumbheight,
            metadata: metadata,
            caption: caption,
            captionInOtherLanguage: nil,
            isEditProtected: try await isEditProtected,
            depicts: try await depicts,
            properLanguageCode: captionLanguage,
            allowEdit: allowEdit
        )
    }

    // MARK: - Reads

    /// Parity: Android `getImageInfoWithEntityTerms`.
    func fetchImageInfoResponse(
        project: WMFProject,
        title: String,
        metadataLanguage: String,
        captionLanguage: String
    ) async throws -> WMFCommonsImageInfoResponse {

        let parameters: [String: Any] = [
            "action": "query",
            "prop": "imageinfo|entityterms",
            "iiprop": "timestamp|user|url|mime|extmetadata",
            "iiurlwidth": Self.preferredThumbWidth,
            "iiextmetadatalanguage": metadataLanguage,
            "wbetlanguage": captionLanguage,
            "titles": title,
            "format": "json",
            "formatversion": "2"
        ]

        return try await performDecodableGET(project: project, parameters: parameters)
    }

    /// Parity: Android `getProtectionWithUserInfo(...).query.isEditProtected`.
    public func fetchProtection(project: WMFProject, title: String) async throws -> Bool {
        let parameters: [String: Any] = [
            "action": "query",
            "meta": "userinfo",
            "prop": "info",
            "inprop": "protection",
            "uiprop": "groups",
            "titles": title,
            "format": "json",
            "formatversion": "2"
        ]

        let response: WMFCommonsProtectionResponse = try await performDecodableGET(project: project, parameters: parameters)
        return response.isEditProtected
    }

    /// Parity: Android `ImageTagsProvider.getImageTags` — read P180 claims on Commons, then resolve the
    /// referenced Wikidata Q-ids to labels. Swallows failures to an empty array, like Android.
    public func fetchDepicts(pageID: Int, wikidataLanguage: String) async throws -> [WMFDepictsTag] {
        do {
            let claimsParams: [String: Any] = [
                "action": "wbgetclaims",
                "entity": "M\(pageID)",
                "property": "P180",
                "format": "json"
            ]
            let claims: WMFCommonsClaimsResponse = try await performDecodableGET(project: .commons, parameters: claimsParams)
            let ids = claims.depictsItemIDs
            guard !ids.isEmpty else {
                return []
            }

            let termsParams: [String: Any] = [
                "action": "query",
                "prop": "entityterms",
                "titles": ids.joined(separator: "|"),
                "wbetlanguage": wikidataLanguage,
                "format": "json",
                "formatversion": "2"
            ]
            let terms: WMFWikidataEntityTermsResponse = try await performDecodableGET(project: .wikidata, parameters: termsParams)

            var tags: [WMFDepictsTag] = []
            for page in terms.query?.pages ?? [] {
                guard let qid = page.title, let label = page.entityterms?.label?.first else {
                    continue
                }
                tags.append(WMFDepictsTag(wikidataID: qid, label: label, description: page.entityterms?.description?.first))
            }
            return tags
        } catch {
            return []
        }
    }

    // MARK: - Writes

    /// Publishes a Commons MediaInfo caption via `wbsetlabel`.
    /// Parity: Android `DescriptionEditViewModel` → `postLabelEdit`.
    public func publishCaption(
        title: String,
        languageCode: String,
        value: String,
        isTranslation: Bool,
        summary: String? = nil
    ) async throws {

        let editTag: WMFEditTag = isTranslation ? .appImageCaptionTranslate : .appImageCaptionAdd

        let parameters: [String: Any] = [
            "action": "wbsetlabel",
            "errorlang": "uselang",
            "language": languageCode,
            "uselang": languageCode,
            "site": "commonswiki",
            "title": title,
            "value": value,
            "summary": summary as Any,
            "assert": "user",
            "matags": editTag.rawValue,
            "format": "json",
            "formatversion": "2",
            "errorformat": "html",
            "errorsuselocal": "1"
        ].compactMapValues { $0 }

        try await performPOST(project: .commons, parameters: parameters)
    }

    /// Publishes P180 "depicts" statements to a Commons MediaInfo entity via `wbeditentity`.
    /// Parity: Android `SuggestedEditsImageTagsViewModel.publishImageTags` — builds an identical
    /// `data` JSON of P180 statements and a `/* add-depicts: … */` summary.
    public func publishDepicts(pageID: Int, tags: [WMFDepictsTag]) async throws {

        guard pageID > 0 else {
            throw CommonsMediaInfoError.invalidPageID
        }

        let mID = "M\(pageID)"
        let payload = Self.buildDepictsPayload(pageID: pageID, tags: tags)

        let parameters: [String: Any] = [
            "action": "wbeditentity",
            "errorlang": "uselang",
            "id": mID,
            "data": payload.data,
            "summary": payload.summary,
            "assert": "user",
            "matags": WMFEditTag.appImageTagAdd.rawValue,
            "format": "json",
            "formatversion": "2",
            "errorformat": "html",
            "errorsuselocal": "1"
        ]

        try await performPOST(project: .commons, parameters: parameters)
    }

    /// Builds the `data` JSON and `summary` for a depicts `wbeditentity` edit.
    /// Extracted for unit testing. Parity: Android `SuggestedEditsImageTagsViewModel.publishImageTags`.
    nonisolated static func buildDepictsPayload(pageID: Int, tags: [WMFDepictsTag]) -> (data: String, summary: String) {
        let mID = "M\(pageID)"
        var claimStr = "{\"claims\":["
        var commentStr = "/* add-depicts: "
        var first = true
        for tag in tags {
            if !first {
                claimStr += ","
                commentStr += ","
            }
            first = false
            claimStr += "{\"mainsnak\":" +
                "{\"snaktype\":\"value\",\"property\":\"P180\"," +
                "\"datavalue\":{\"value\":" +
                "{\"entity-type\":\"item\",\"id\":\"\(tag.wikidataID)\"}," +
                "\"type\":\"wikibase-entityid\"},\"datatype\":\"wikibase-item\"}," +
                "\"type\":\"statement\"," +
                "\"id\":\"\(mID)$\(UUID().uuidString)\"," +
                "\"rank\":\"normal\"}"
            let sanitizedLabel = tag.label.replacingOccurrences(of: "|", with: "").replacingOccurrences(of: ",", with: "")
            commentStr += tag.wikidataID + "|" + sanitizedLabel
        }
        claimStr += "]}"
        commentStr += " */"
        return (claimStr, commentStr)
    }

    // MARK: - Request helpers

    func performDecodableGET<T: Decodable>(project: WMFProject, parameters: [String: Any]) async throws -> T {
        guard let service else {
            throw WMFDataControllerError.mediaWikiServiceUnavailable
        }
        guard let url = URL.mediaWikiAPIURL(project: project) else {
            throw WMFDataControllerError.failureCreatingRequestURL
        }
        let request = WMFMediaWikiServiceRequest(url: url, method: .GET, backend: .mediaWiki, parameters: parameters)
        return try await withCheckedThrowingContinuation { continuation in
            service.performDecodableGET(request: request) { (result: Result<T, Error>) in
                switch result {
                case .success(let value):
                    continuation.resume(returning: value)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    @discardableResult
    func performPOST(project: WMFProject, parameters: [String: Any]) async throws -> [String: Any]? {
        guard let service else {
            throw WMFDataControllerError.mediaWikiServiceUnavailable
        }
        guard let url = URL.mediaWikiAPIURL(project: project) else {
            throw WMFDataControllerError.failureCreatingRequestURL
        }
        let request = WMFMediaWikiServiceRequest(url: url, method: .POST, backend: .mediaWiki, tokenType: .csrf, parameters: parameters)
        return try await withCheckedThrowingContinuation { continuation in
            service.perform(request: request) { (result: Result<[String: Any]?, Error>) in
                switch result {
                case .success(let value):
                    continuation.resume(returning: value)
                case .failure(let error):
                    continuation.resume(throwing: WMFDataControllerError.serviceError(error))
                }
            }
        }
    }
}
