import XCTest
@testable import WMFData

final class WMFCommonsMediaInfoDataControllerTests: XCTestCase {

    // MARK: - File title normalization

    func testNormalizedFileTitleAddsPrefixWhenMissing() {
        XCTAssertEqual(WMFCommonsMediaInfoDataController.normalizedFileTitle("Example.jpg"), "File:Example.jpg")
    }

    func testNormalizedFileTitleKeepsExistingPrefix() {
        XCTAssertEqual(WMFCommonsMediaInfoDataController.normalizedFileTitle("File:Example.jpg"), "File:Example.jpg")
        // Namespace prefix match should be case-insensitive.
        XCTAssertEqual(WMFCommonsMediaInfoDataController.normalizedFileTitle("file:Example.jpg"), "file:Example.jpg")
    }

    func testNormalizedFileTitleTrimsWhitespace() {
        XCTAssertEqual(WMFCommonsMediaInfoDataController.normalizedFileTitle("  Example.jpg  "), "File:Example.jpg")
    }

    // MARK: - Edit tags

    func testEditTagsForAdd() {
        let tags = WMFCommonsMediaInfoDataController.editTags(for: .add, additionalTags: [])
        XCTAssertEqual(tags, [.appImageCaptionAdd])
    }

    func testEditTagsForTranslate() {
        let tags = WMFCommonsMediaInfoDataController.editTags(for: .translate, additionalTags: [])
        XCTAssertEqual(tags, [.appImageCaptionTranslate])
    }

    func testEditTagsIncludeAdditionalSuggestedEditTagWithoutDuplication() {
        let tags = WMFCommonsMediaInfoDataController.editTags(for: .add, additionalTags: [.appSuggestedEdit, .appImageCaptionAdd])
        XCTAssertEqual(tags, [.appImageCaptionAdd, .appSuggestedEdit])
    }

    // MARK: - Publish request contract (action=wbsetlabel)

    func testPublishParametersMatchWbSetLabelContract() {
        let parameters = WMFCommonsMediaInfoDataController.publishParameters(
            fileTitle: "Example.jpg",
            languageCode: "en",
            caption: "A friendly caption",
            editType: .add,
            additionalTags: [],
            summary: nil
        )

        XCTAssertEqual(parameters["action"], "wbsetlabel")
        // Language is sent verbatim for both language and uselang (Android bffdf572f2 parity).
        XCTAssertEqual(parameters["language"], "en")
        XCTAssertEqual(parameters["uselang"], "en")
        XCTAssertEqual(parameters["site"], "commonswiki")
        XCTAssertEqual(parameters["title"], "File:Example.jpg")
        XCTAssertEqual(parameters["value"], "A friendly caption")
        XCTAssertEqual(parameters["matags"], "app-image-caption-add")
        XCTAssertEqual(parameters["format"], "json")
        XCTAssertEqual(parameters["formatversion"], "2")
        XCTAssertEqual(parameters["errorformat"], "html")
        XCTAssertEqual(parameters["errorsuselocal"], "1")
        // No summary provided -> key absent.
        XCTAssertNil(parameters["summary"])
    }

    func testPublishParametersUseSelectedLanguageDirectly() {
        // The caption language must be sent as-is, not normalized to the article/site language.
        let parameters = WMFCommonsMediaInfoDataController.publishParameters(
            fileTitle: "File:Example.jpg",
            languageCode: "fr",
            caption: "Une légende",
            editType: .translate,
            additionalTags: [.appSuggestedEdit],
            summary: "Adding French caption"
        )

        XCTAssertEqual(parameters["language"], "fr")
        XCTAssertEqual(parameters["uselang"], "fr")
        XCTAssertEqual(parameters["matags"], "app-image-caption-translate,app-suggestededit")
        XCTAssertEqual(parameters["summary"], "Adding French caption")
    }

    // MARK: - Fetch request contract (action=wbgetentities)

    func testFetchParametersMatchWbGetEntitiesContract() {
        let parameters = WMFCommonsMediaInfoDataController.fetchParameters(fileTitle: "Example.jpg", languageCode: "en")

        XCTAssertEqual(parameters["action"] as? String, "wbgetentities")
        XCTAssertEqual(parameters["sites"] as? String, "commonswiki")
        XCTAssertEqual(parameters["titles"] as? String, "File:Example.jpg")
        XCTAssertEqual(parameters["props"] as? String, "labels")
        XCTAssertEqual(parameters["languages"] as? String, "en")
        XCTAssertEqual(parameters["formatversion"] as? String, "2")
    }

    func testFetchParametersOmitLanguagesWhenNil() {
        let parameters = WMFCommonsMediaInfoDataController.fetchParameters(fileTitle: "Example.jpg", languageCode: nil)
        XCTAssertNil(parameters["languages"])
    }

    // MARK: - Response decoding

    func testLabelsDecodingFromEntitiesResponse() throws {
        let json = """
        {
          "entities": {
            "M12345": {
              "type": "mediainfo",
              "id": "M12345",
              "labels": {
                "en": { "language": "en", "value": "A cat sitting on a wall" },
                "fr": { "language": "fr", "value": "Un chat" }
              }
            }
          }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(WMFCommonsMediaInfoDataController.EntitiesResponse.self, from: json)
        let labels = WMFCommonsMediaInfoDataController.labels(from: response)
        XCTAssertEqual(labels["en"], "A cat sitting on a wall")
        XCTAssertEqual(labels["fr"], "Un chat")
    }

    func testLabelsDecodingForFileWithoutCaption() throws {
        // A file whose MediaInfo entity exists but has no labels yet.
        let json = """
        {
          "entities": {
            "M999": {
              "type": "mediainfo",
              "id": "M999",
              "missing": ""
            }
          }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(WMFCommonsMediaInfoDataController.EntitiesResponse.self, from: json)
        XCTAssertTrue(WMFCommonsMediaInfoDataController.labels(from: response).isEmpty)
    }

    func testPublishResponseDecoding() throws {
        let json = """
        {
          "entity": {
            "type": "mediainfo",
            "id": "M12345",
            "lastrevid": 987654,
            "labels": { "en": { "language": "en", "value": "A caption" } }
          },
          "success": 1
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(WMFCommonsMediaInfoDataController.CaptionPublishResponse.self, from: json)
        XCTAssertEqual(response.success, 1)
        XCTAssertEqual(response.entity?.lastrevid, 987654)
    }
}
