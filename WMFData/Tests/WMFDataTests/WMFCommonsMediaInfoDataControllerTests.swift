import XCTest
@testable import WMFData

final class WMFCommonsMediaInfoDataControllerTests: XCTestCase {

    private func decode<T: Decodable>(_ type: T.Type, from json: String) throws -> T {
        let data = Data(json.utf8)
        return try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - imageinfo | entityterms decoding

    func testImageInfoResponseDecodingExtractsCaptionAndMetadata() throws {
        let json = """
        {
          "query": {
            "pages": [
              {
                "pageid": 12345,
                "title": "File:Example.jpg",
                "imagerepository": "local",
                "imageinfo": [
                  {
                    "thumburl": "https://upload.wikimedia.org/thumb/Example.jpg",
                    "thumbwidth": 640,
                    "thumbheight": 480,
                    "url": "https://upload.wikimedia.org/Example.jpg",
                    "descriptionurl": "https://commons.wikimedia.org/wiki/File:Example.jpg",
                    "mime": "image/jpeg",
                    "extmetadata": {
                      "Artist": { "value": "Jane Doe" },
                      "DateTime": { "value": "2021-05-01" },
                      "LicenseShortName": { "value": "CC BY-SA 4.0" },
                      "LicenseUrl": { "value": "https://creativecommons.org/licenses/by-sa/4.0" }
                    }
                  }
                ],
                "entityterms": { "label": ["A friendly caption"] }
              }
            ]
          }
        }
        """

        let response = try decode(WMFCommonsImageInfoResponse.self, from: json)
        let page = try XCTUnwrap(response.query?.pages?.first)
        XCTAssertEqual(page.pageid, 12345)
        XCTAssertFalse(page.isImageShared)
        XCTAssertEqual(page.entityterms?.label?.first, "A friendly caption")
        let info = try XCTUnwrap(page.imageinfo?.first)
        XCTAssertEqual(info.mime, "image/jpeg")
        XCTAssertEqual(info.extmetadata?.artist?.value, "Jane Doe")
        XCTAssertEqual(info.extmetadata?.licenseShortName?.value, "CC BY-SA 4.0")
    }

    func testImageInfoResponseDetectsSharedImage() throws {
        let json = """
        { "query": { "pages": [ { "pageid": 1, "title": "File:Shared.jpg", "imagerepository": "shared" } ] } }
        """
        let response = try decode(WMFCommonsImageInfoResponse.self, from: json)
        XCTAssertTrue(try XCTUnwrap(response.query?.pages?.first).isImageShared)
    }

    // MARK: - protection | userinfo decoding (isEditProtected truth table)

    func testProtectionResponseEditProtectedWhenUserNotInLevelGroup() throws {
        let json = """
        {
          "query": {
            "pages": [ { "protection": [ { "type": "edit", "level": "sysop", "expiry": "infinity" } ] } ],
            "userinfo": { "groups": ["user", "autoconfirmed"] }
          }
        }
        """
        let response = try decode(WMFCommonsProtectionResponse.self, from: json)
        XCTAssertTrue(response.isEditProtected)
    }

    func testProtectionResponseNotProtectedWhenUserInLevelGroup() throws {
        let json = """
        {
          "query": {
            "pages": [ { "protection": [ { "type": "edit", "level": "sysop", "expiry": "infinity" } ] } ],
            "userinfo": { "groups": ["user", "sysop"] }
          }
        }
        """
        let response = try decode(WMFCommonsProtectionResponse.self, from: json)
        XCTAssertFalse(response.isEditProtected)
    }

    func testProtectionResponseNotProtectedWhenNoEditProtection() throws {
        let json = """
        {
          "query": {
            "pages": [ { "protection": [ { "type": "move", "level": "sysop", "expiry": "infinity" } ] } ],
            "userinfo": { "groups": ["user"] }
          }
        }
        """
        let response = try decode(WMFCommonsProtectionResponse.self, from: json)
        XCTAssertFalse(response.isEditProtected)
    }

    // MARK: - wbgetclaims (P180) decoding

    func testClaimsResponseExtractsDepictsItemIDs() throws {
        let json = """
        {
          "claims": {
            "P180": [
              { "mainsnak": { "datavalue": { "value": { "id": "Q42" } } } },
              { "mainsnak": { "datavalue": { "value": { "id": "Q7378" } } } }
            ]
          }
        }
        """
        let response = try decode(WMFCommonsClaimsResponse.self, from: json)
        XCTAssertEqual(response.depictsItemIDs, ["Q42", "Q7378"])
    }

    func testClaimsResponseEmptyWhenNoP180() throws {
        let json = "{ \"claims\": {} }"
        let response = try decode(WMFCommonsClaimsResponse.self, from: json)
        XCTAssertTrue(response.depictsItemIDs.isEmpty)
    }

    // MARK: - wbsearchentities decoding

    func testSearchResponseDecoding() throws {
        let json = """
        {
          "search": [
            { "id": "Q42", "label": "Douglas Adams", "description": "English writer" },
            { "id": "Q5", "label": "human" }
          ]
        }
        """
        let response = try decode(WMFWikidataSearchResponse.self, from: json)
        XCTAssertEqual(response.search?.count, 2)
        XCTAssertEqual(response.search?.first?.label, "Douglas Adams")
    }

    // MARK: - Eligibility truth table (parity with Android FilePageView)

    private func makeMediaInfo(
        isFromCommons: Bool,
        caption: WMFMediaInfoCaption?,
        captionInOtherLanguage: WMFMediaInfoCaption? = nil,
        isEditProtected: Bool,
        depicts: [WMFDepictsTag],
        allowEdit: Bool
    ) -> WMFCommonsMediaInfo {
        WMFCommonsMediaInfo(
            pageID: 1,
            title: "File:Example.jpg",
            isFromCommons: isFromCommons,
            thumbURL: nil,
            fullURL: nil,
            filePageURL: nil,
            mimeType: "image/jpeg",
            width: 640,
            height: 480,
            metadata: WMFCommonsMediaMetadata(author: nil, dateTime: nil, credit: nil, licenseShortName: nil, licenseURL: nil),
            caption: caption,
            captionInOtherLanguage: captionInOtherLanguage,
            isEditProtected: isEditProtected,
            depicts: depicts,
            properLanguageCode: "en",
            allowEdit: allowEdit
        )
    }

    func testCanEditRequiresCommonsAllowEditAndNotProtected() {
        XCTAssertTrue(makeMediaInfo(isFromCommons: true, caption: nil, isEditProtected: false, depicts: [], allowEdit: true).canEdit)
        XCTAssertFalse(makeMediaInfo(isFromCommons: false, caption: nil, isEditProtected: false, depicts: [], allowEdit: true).canEdit)
        XCTAssertFalse(makeMediaInfo(isFromCommons: true, caption: nil, isEditProtected: true, depicts: [], allowEdit: true).canEdit)
        XCTAssertFalse(makeMediaInfo(isFromCommons: true, caption: nil, isEditProtected: false, depicts: [], allowEdit: false).canEdit)
    }

    func testShowAddCaptionOnlyWhenEditableAndCaptionEmpty() {
        // Editable + no caption → show CTA
        XCTAssertTrue(makeMediaInfo(isFromCommons: true, caption: nil, isEditProtected: false, depicts: [], allowEdit: true).shouldShowAddCaption)
        // Editable + caption present → no CTA
        XCTAssertFalse(makeMediaInfo(isFromCommons: true, caption: WMFMediaInfoCaption(languageCode: "en", value: "hi"), isEditProtected: false, depicts: [], allowEdit: true).shouldShowAddCaption)
        // Not editable + no caption → no CTA
        XCTAssertFalse(makeMediaInfo(isFromCommons: false, caption: nil, isEditProtected: false, depicts: [], allowEdit: true).shouldShowAddCaption)
    }

    func testShowTranslateCaptionWhenOtherLanguageCaptionExists() {
        let info = makeMediaInfo(
            isFromCommons: true,
            caption: nil,
            captionInOtherLanguage: WMFMediaInfoCaption(languageCode: "de", value: "Hallo"),
            isEditProtected: false,
            depicts: [],
            allowEdit: true
        )
        XCTAssertTrue(info.shouldShowTranslateCaption)
    }

    func testShowAddTagsOnlyWhenEditableAndDepictsEmpty() {
        XCTAssertTrue(makeMediaInfo(isFromCommons: true, caption: nil, isEditProtected: false, depicts: [], allowEdit: true).shouldShowAddTags)
        XCTAssertFalse(makeMediaInfo(isFromCommons: true, caption: nil, isEditProtected: false, depicts: [WMFDepictsTag(wikidataID: "Q42", label: "x")], allowEdit: true).shouldShowAddTags)
        XCTAssertFalse(makeMediaInfo(isFromCommons: false, caption: nil, isEditProtected: false, depicts: [], allowEdit: true).shouldShowAddTags)
    }

    // MARK: - Depicts publish payload construction (parity with Android publishImageTags)

    func testBuildDepictsPayloadMatchesAndroidShape() {
        let tags = [
            WMFDepictsTag(wikidataID: "Q42", label: "Douglas Adams"),
            WMFDepictsTag(wikidataID: "Q7378", label: "elephant, large|animal")
        ]
        let payload = WMFCommonsMediaInfoDataController.buildDepictsPayload(pageID: 999, tags: tags)

        XCTAssertTrue(payload.data.hasPrefix("{\"claims\":["))
        XCTAssertTrue(payload.data.hasSuffix("]}"))
        XCTAssertTrue(payload.data.contains("\"property\":\"P180\""))
        XCTAssertTrue(payload.data.contains("\"id\":\"Q42\""))
        XCTAssertTrue(payload.data.contains("\"id\":\"Q7378\""))
        // Statement id uses the "M<pageID>$<uuid>" convention.
        XCTAssertTrue(payload.data.contains("\"id\":\"M999$"))

        // Summary strips "|" and "," from labels.
        XCTAssertEqual(payload.summary, "/* add-depicts: Q42|Douglas Adams,Q7378|elephant largeanimal */")
    }
}
