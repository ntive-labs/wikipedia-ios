import XCTest
@testable import WMFData
@testable import WMFDataMocks

final class WMFCommonsMediaInfoDataControllerTests: XCTestCase {

    override func setUp() async throws {
        WMFDataEnvironment.current.mediaWikiService = WMFMockCommonsMediaInfoService()
    }

    // MARK: - File title normalization

    func testNormalizedFileTitleAddsPrefixWhenMissing() {
        XCTAssertEqual(WMFCommonsMediaInfoDataController.normalizedFileTitle("Example.jpg"), "File:Example.jpg")
    }

    func testNormalizedFileTitleKeepsExistingPrefix() {
        XCTAssertEqual(WMFCommonsMediaInfoDataController.normalizedFileTitle("File:Example.jpg"), "File:Example.jpg")
        XCTAssertEqual(WMFCommonsMediaInfoDataController.normalizedFileTitle("file:Example.jpg"), "file:Example.jpg")
    }

    func testNormalizedFileTitleTrimsWhitespace() {
        XCTAssertEqual(WMFCommonsMediaInfoDataController.normalizedFileTitle("  Example.jpg  "), "File:Example.jpg")
    }

    // MARK: - Caption edit tags

    func testEditTagsForAdd() {
        XCTAssertEqual(WMFCommonsMediaInfoDataController.editTags(for: .add, additionalTags: []), [.appImageCaptionAdd])
    }

    func testEditTagsForTranslate() {
        XCTAssertEqual(WMFCommonsMediaInfoDataController.editTags(for: .translate, additionalTags: []), [.appImageCaptionTranslate])
    }

    func testEditTagsIncludeAdditionalSuggestedEditTagWithoutDuplication() {
        let tags = WMFCommonsMediaInfoDataController.editTags(for: .add, additionalTags: [.appSuggestedEdit, .appImageCaptionAdd])
        XCTAssertEqual(tags, [.appImageCaptionAdd, .appSuggestedEdit])
    }

    // MARK: - Caption publish contract (action=wbsetlabel)

    func testCaptionPublishParametersMatchWbSetLabelContract() {
        let parameters = WMFCommonsMediaInfoDataController.captionPublishParameters(fileTitle: "Example.jpg", languageCode: "en", caption: "A friendly caption", editType: .add, additionalTags: [], summary: nil)

        XCTAssertEqual(parameters["action"], "wbsetlabel")
        XCTAssertEqual(parameters["language"], "en")
        XCTAssertEqual(parameters["uselang"], "en")
        XCTAssertEqual(parameters["site"], "commonswiki")
        XCTAssertEqual(parameters["title"], "File:Example.jpg")
        XCTAssertEqual(parameters["value"], "A friendly caption")
        XCTAssertEqual(parameters["matags"], "app-image-caption-add")
        XCTAssertEqual(parameters["formatversion"], "2")
        XCTAssertNil(parameters["summary"])
    }

    func testCaptionPublishParametersUseSelectedLanguageDirectly() {
        let parameters = WMFCommonsMediaInfoDataController.captionPublishParameters(fileTitle: "File:Example.jpg", languageCode: "fr", caption: "Une légende", editType: .translate, additionalTags: [.appSuggestedEdit], summary: "Adding French caption")

        XCTAssertEqual(parameters["language"], "fr")
        XCTAssertEqual(parameters["uselang"], "fr")
        XCTAssertEqual(parameters["matags"], "app-image-caption-translate,app-suggestededit")
        XCTAssertEqual(parameters["summary"], "Adding French caption")
    }

    // MARK: - Read parameter contracts

    func testImageInfoParametersMatchAndroidContract() {
        let parameters = WMFCommonsMediaInfoDataController.imageInfoParameters(fileTitle: "Example.jpg", metadataLanguage: "en", entityLanguage: "en")
        XCTAssertEqual(parameters["action"] as? String, "query")
        XCTAssertEqual(parameters["prop"] as? String, "imageinfo|entityterms")
        XCTAssertEqual(parameters["iiprop"] as? String, "timestamp|user|url|mime|extmetadata")
        XCTAssertEqual(parameters["iiurlwidth"] as? String, "330")
        XCTAssertEqual(parameters["wbetlanguage"] as? String, "en")
        XCTAssertEqual(parameters["titles"] as? String, "File:Example.jpg")
    }

    func testProtectionParametersMatchAndroidContract() {
        let parameters = WMFCommonsMediaInfoDataController.protectionParameters(fileTitle: "Example.jpg")
        XCTAssertEqual(parameters["action"] as? String, "query")
        XCTAssertEqual(parameters["meta"] as? String, "userinfo")
        XCTAssertEqual(parameters["inprop"] as? String, "protection")
        XCTAssertEqual(parameters["uiprop"] as? String, "groups")
    }

    func testClaimsParametersMatchWbGetClaimsContract() {
        let parameters = WMFCommonsMediaInfoDataController.claimsParameters(pageID: 12345)
        XCTAssertEqual(parameters["action"] as? String, "wbgetclaims")
        XCTAssertEqual(parameters["entity"] as? String, "M12345")
        XCTAssertEqual(parameters["property"] as? String, "P180")
    }

    func testEntityTermsParametersJoinIdsWithPipe() {
        let parameters = WMFCommonsMediaInfoDataController.entityTermsParameters(ids: ["Q146", "Q42320"], language: "en")
        XCTAssertEqual(parameters["action"] as? String, "query")
        XCTAssertEqual(parameters["prop"] as? String, "entityterms")
        XCTAssertEqual(parameters["titles"] as? String, "Q146|Q42320")
        XCTAssertEqual(parameters["wbetlanguage"] as? String, "en")
    }

    // MARK: - Depicts publish contract (action=wbeditentity, P180)

    func testDepictsPublishParametersMatchWbEditEntityContract() {
        let tags = [WMFDepictsTag(wikidataID: "Q146", label: "domestic cat")]
        let parameters = WMFCommonsMediaInfoDataController.depictsPublishParameters(pageID: 12345, tags: tags)
        XCTAssertEqual(parameters["action"], "wbeditentity")
        XCTAssertEqual(parameters["id"], "M12345")
        XCTAssertEqual(parameters["matags"], "app-image-tag-add")
        XCTAssertNotNil(parameters["data"])
        XCTAssertNotNil(parameters["summary"])
    }

    func testDepictsClaimJSONShapeMatchesAndroid() throws {
        let tags = [WMFDepictsTag(wikidataID: "Q146", label: "domestic cat")]
        let json = WMFCommonsMediaInfoDataController.depictsClaimJSON(pageID: 12345, tags: tags)

        // Must be valid JSON with the exact Wikibase statement shape.
        let object = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        let claims = object?["claims"] as? [[String: Any]]
        XCTAssertEqual(claims?.count, 1)
        let mainsnak = claims?.first?["mainsnak"] as? [String: Any]
        XCTAssertEqual(mainsnak?["property"] as? String, "P180")
        XCTAssertEqual(mainsnak?["datatype"] as? String, "wikibase-item")
        let datavalue = mainsnak?["datavalue"] as? [String: Any]
        XCTAssertEqual(datavalue?["type"] as? String, "wikibase-entityid")
        let value = datavalue?["value"] as? [String: Any]
        XCTAssertEqual(value?["entity-type"] as? String, "item")
        XCTAssertEqual(value?["id"] as? String, "Q146")
        let statementID = claims?.first?["id"] as? String
        XCTAssertTrue(statementID?.hasPrefix("M12345$") ?? false)
    }

    func testDepictsSummarySanitizesLabelsAndMatchesAndroid() {
        let tags = [
            WMFDepictsTag(wikidataID: "Q146", label: "domestic, cat|feline"),
            WMFDepictsTag(wikidataID: "Q42320", label: "wall")
        ]
        let summary = WMFCommonsMediaInfoDataController.depictsSummary(tags: tags)
        XCTAssertEqual(summary, "/* add-depicts: Q146|domestic catfeline,Q42320|wall */")
    }

    // MARK: - Wikidata item search contract

    func testSearchParametersMatchWbSearchEntitiesContract() {
        let parameters = WMFWikidataItemSearchDataController.searchParameters(term: "cat", languageCode: "en")
        XCTAssertEqual(parameters["action"] as? String, "wbsearchentities")
        XCTAssertEqual(parameters["type"] as? String, "item")
        XCTAssertEqual(parameters["limit"] as? String, "20")
        XCTAssertEqual(parameters["search"] as? String, "cat")
        XCTAssertEqual(parameters["language"] as? String, "en")
        XCTAssertEqual(parameters["uselang"] as? String, "en")
    }

    // MARK: - Response decoding

    func testLabelsDecodingFromEntitiesResponse() throws {
        let json = """
        { "entities": { "M12345": { "type": "mediainfo", "id": "M12345",
          "labels": { "en": { "language": "en", "value": "A cat sitting on a wall" },
                      "fr": { "language": "fr", "value": "Un chat" } } } } }
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(WMFCommonsMediaInfoDataController.EntitiesResponse.self, from: json)
        let labels = WMFCommonsMediaInfoDataController.labels(from: response)
        XCTAssertEqual(labels["en"], "A cat sitting on a wall")
        XCTAssertEqual(labels["fr"], "Un chat")
    }

    func testDepictsItemIDsExtraction() throws {
        let json = """
        { "claims": { "P180": [
          { "mainsnak": { "datavalue": { "value": { "entity-type": "item", "id": "Q146" }, "type": "wikibase-entityid" } } },
          { "mainsnak": { "datavalue": { "value": { "entity-type": "item", "id": "Q42320" }, "type": "wikibase-entityid" } } }
        ] } }
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(WMFCommonsMediaInfoDataController.ClaimsResponse.self, from: json)
        XCTAssertEqual(WMFCommonsMediaInfoDataController.depictsItemIDs(from: response), ["Q146", "Q42320"])
    }

    func testDepictsTagsResolvedFromEntityTerms() throws {
        let json = """
        { "query": { "pages": [
          { "title": "Q146", "entityterms": { "label": ["domestic cat"] } },
          { "title": "Q42320", "entityterms": { "label": ["wall"] } }
        ] } }
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(WMFCommonsMediaInfoDataController.EntityTermsResponse.self, from: json)
        let tags = WMFCommonsMediaInfoDataController.depictsTags(ids: ["Q146", "Q42320"], from: response)
        XCTAssertEqual(tags.map { $0.wikidataID }, ["Q146", "Q42320"])
        XCTAssertEqual(tags.map { $0.label }, ["domestic cat", "wall"])
    }

    func testEditProtectedTrueWhenLevelNotInUserGroups() throws {
        let json = """
        { "query": { "userinfo": { "groups": ["*", "user"] },
          "pages": [ { "protection": [ { "type": "edit", "level": "sysop", "expiry": "infinity" } ] } ] } }
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(WMFCommonsMediaInfoDataController.ProtectionResponse.self, from: json)
        XCTAssertTrue(WMFCommonsMediaInfoDataController.isEditProtected(from: response))
    }

    func testEditProtectedFalseWhenUserHasRequiredGroup() throws {
        let json = """
        { "query": { "userinfo": { "groups": ["*", "user", "sysop"] },
          "pages": [ { "protection": [ { "type": "edit", "level": "sysop", "expiry": "infinity" } ] } ] } }
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(WMFCommonsMediaInfoDataController.ProtectionResponse.self, from: json)
        XCTAssertFalse(WMFCommonsMediaInfoDataController.isEditProtected(from: response))
    }

    func testEditProtectedFalseWhenNoProtection() throws {
        let json = """
        { "query": { "userinfo": { "groups": ["*", "user"] }, "pages": [ { "protection": [] } ] } }
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(WMFCommonsMediaInfoDataController.ProtectionResponse.self, from: json)
        XCTAssertFalse(WMFCommonsMediaInfoDataController.isEditProtected(from: response))
    }

    // MARK: - Integration (mock service)

    func testFetchMediaInfoHappyPath() async throws {
        let controller = WMFCommonsMediaInfoDataController()
        let info = try await controller.fetchMediaInfo(fileTitle: "Example cat.jpg", pageLanguageCode: "en", allowEdit: true)

        XCTAssertEqual(info.pageID, 12345)
        XCTAssertEqual(info.title, "File:Example cat.jpg")
        XCTAssertTrue(info.isFromCommons)
        XCTAssertFalse(info.isEditProtected)
        XCTAssertEqual(info.caption?.value, "A domestic cat on a garden wall")
        XCTAssertEqual(info.metadata?.licenseShortName, "CC BY-SA 4.0")
        XCTAssertEqual(info.depicts.map { $0.wikidataID }, ["Q146", "Q42320"])
        XCTAssertEqual(info.depicts.map { $0.label }, ["domestic cat", "wall"])
        // Caption present -> no add-caption CTA; depicts present -> no add-tags CTA.
        XCTAssertTrue(info.canEdit)
        XCTAssertFalse(info.showAddCaption)
        XCTAssertFalse(info.showAddTags)
    }

    func testFetchDepictsResolvesLabels() async throws {
        let controller = WMFCommonsMediaInfoDataController()
        let tags = try await controller.fetchDepicts(pageID: 12345, wikidataLanguageCode: "en")
        XCTAssertEqual(tags.map { $0.label }, ["domestic cat", "wall"])
    }

    func testPublishCaptionSucceeds() async throws {
        let controller = WMFCommonsMediaInfoDataController()
        let result: WMFCommonsMediaInfoDataController.CaptionPublishResult = try await withCheckedThrowingContinuation { continuation in
            controller.publishCaption(fileTitle: "Example cat.jpg", languageCode: "en", caption: "A cat", editType: .add) { result in
                continuation.resume(with: result)
            }
        }
        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.newRevisionID, 987654)
    }

    func testPublishDepictsSucceeds() async throws {
        let controller = WMFCommonsMediaInfoDataController()
        let result = try await controller.publishDepicts(pageID: 12345, tags: [WMFDepictsTag(wikidataID: "Q146", label: "cat")])
        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.newRevisionID, 987700)
    }

    func testSearchReturnsTags() async throws {
        let controller = WMFWikidataItemSearchDataController()
        let tags = try await controller.search(term: "cat", languageCode: "en")
        XCTAssertEqual(tags.count, 2)
        XCTAssertEqual(tags.first?.wikidataID, "Q146")
        XCTAssertEqual(tags.first?.label, "house cat")
        XCTAssertEqual(tags.first?.description, "domesticated species of feline")
    }

    // MARK: - Eligibility truth table (WMFCommonsMediaInfo)

    private func makeInfo(isFromCommons: Bool = true, isEditProtected: Bool = false, allowEdit: Bool = true, caption: WMFMediaInfoCaption? = nil, depicts: [WMFDepictsTag] = [], languageCode: String = "en") -> WMFCommonsMediaInfo {
        WMFCommonsMediaInfo(pageID: 1, title: "File:X.jpg", isFromCommons: isFromCommons, thumbURL: nil, fullURL: nil, mimeType: nil, thumbnailWidth: nil, thumbnailHeight: nil, metadata: nil, caption: caption, isEditProtected: isEditProtected, depicts: depicts, allowEdit: allowEdit, languageCode: languageCode)
    }

    func testCanEditRequiresCommonsUnprotectedAndAllowed() {
        XCTAssertTrue(makeInfo().canEdit)
        XCTAssertFalse(makeInfo(isFromCommons: false).canEdit)
        XCTAssertFalse(makeInfo(isEditProtected: true).canEdit)
        XCTAssertFalse(makeInfo(allowEdit: false).canEdit)
    }

    func testShowAddCaptionWhenMissingAndEditable() {
        XCTAssertTrue(makeInfo(caption: nil).showAddCaption)
        XCTAssertFalse(makeInfo(caption: WMFMediaInfoCaption(languageCode: "en", value: "hello")).showAddCaption)
        // Caption in another language still shows the CTA in the user's language.
        XCTAssertTrue(makeInfo(caption: WMFMediaInfoCaption(languageCode: "fr", value: "bonjour")).showAddCaption)
        // Not editable -> never show the CTA.
        XCTAssertFalse(makeInfo(isFromCommons: false, caption: nil).showAddCaption)
    }

    func testShowAddTagsWhenEmptyAndEditable() {
        XCTAssertTrue(makeInfo(depicts: []).showAddTags)
        XCTAssertFalse(makeInfo(depicts: [WMFDepictsTag(wikidataID: "Q1", label: "x")]).showAddTags)
        XCTAssertFalse(makeInfo(allowEdit: false, depicts: []).showAddTags)
    }
}
