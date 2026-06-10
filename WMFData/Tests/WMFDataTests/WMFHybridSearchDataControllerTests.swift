import XCTest
@testable import WMFData
@testable import WMFDataMocks

final class WMFHybridSearchDataControllerTests: XCTestCase {

    private var controller: WMFHybridSearchDataController!

    override func setUp() async throws {
        WMFDataEnvironment.current.userDefaultsStore = WMFMockKeyValueStore()
        WMFDataEnvironment.current.sharedCacheStore = WMFMockKeyValueStore()
        removeStandardUserDefaultsOverrides()
        controller = WMFHybridSearchDataController(service: nil, experimentStore: WMFMockKeyValueStore())
    }

    override func tearDown() async throws {
        removeStandardUserDefaultsOverrides()
    }

    private func removeStandardUserDefaultsOverrides() {
        UserDefaults.standard.removeObject(forKey: WMFHybridSearchDataController.bucketOverrideUserDefaultsKey)
        UserDefaults.standard.removeObject(forKey: WMFHybridSearchDataController.supportedLanguagesOverrideUserDefaultsKey)
    }

    private func setBucketOverride(_ value: String) {
        UserDefaults.standard.set(value, forKey: WMFHybridSearchDataController.bucketOverrideUserDefaultsKey)
    }

    // MARK: - Snippet post-processing

    func testPostProcessSectionTextConvertsBoldAndItalic() {
        let processed = WMFHybridSearchDataController.postProcessSectionText("The '''capital''' of ''Greece''.")
        XCTAssertEqual(processed, "The <b>capital</b> of <i>Greece</i>.")
    }

    func testPostProcessSectionTextMatchesAcrossNewlines() {
        let processed = WMFHybridSearchDataController.postProcessSectionText("'''bold\ntext''' and ''italic\ntext''")
        XCTAssertEqual(processed, "<b>bold\ntext</b> and <i>italic\ntext</i>")
    }

    func testPostProcessSectionTextRemovesEmptyParentheses() {
        let processed = WMFHybridSearchDataController.postProcessSectionText("Athens ( , .; ) is a city (founded 3000 BC).")
        XCTAssertEqual(processed, "Athens  is a city (founded 3000 BC).")
    }

    // MARK: - Bucket override

    func testBucketOverrideControl() {
        setBucketOverride("control")
        XCTAssertEqual(controller.assignedGroupName, "control")
        XCTAssertFalse(controller.isTestGroupUser())
    }

    func testBucketOverrideLexicalSemantic() {
        setBucketOverride("lexicalSemantic")
        XCTAssertEqual(controller.assignedGroupName, "lexicalSemantic")
        XCTAssertTrue(controller.isTestGroupUser())
    }

    func testBucketOverrideSemanticLexical() {
        setBucketOverride("semanticLexical")
        XCTAssertEqual(controller.assignedGroupName, "semanticLexical")
        XCTAssertTrue(controller.isTestGroupUser())
    }

    func testAssignedGroupNameWithoutOverrideIsValidGroup() {
        let validGroupNames = ["control", "lexicalSemantic", "semanticLexical"]
        let assignedGroupName = controller.assignedGroupName
        XCTAssertTrue(validGroupNames.contains(assignedGroupName))

        // Assignment is sticky.
        XCTAssertEqual(controller.assignedGroupName, assignedGroupName)
    }

    // MARK: - Language support

    func testIsLanguageSupportedDefaults() {
        XCTAssertTrue(controller.isLanguageSupported("el"))
        XCTAssertTrue(controller.isLanguageSupported("EL"))
        XCTAssertTrue(controller.isLanguageSupported("fr"))
        XCTAssertFalse(controller.isLanguageSupported("en"))
        XCTAssertFalse(controller.isLanguageSupported(nil))
    }

    func testIsLanguageSupportedWithOverride() {
        controller.supportedLanguagesOverride = ["en", "de"]
        XCTAssertTrue(controller.isLanguageSupported("en"))
        XCTAssertTrue(controller.isLanguageSupported("de"))
        XCTAssertFalse(controller.isLanguageSupported("el"))
    }

    // MARK: - Gating

    func testShouldShowOnboarding() {
        setBucketOverride("lexicalSemantic")
        XCTAssertTrue(controller.shouldShowOnboarding(languageCode: "el"))
        XCTAssertFalse(controller.shouldShowOnboarding(languageCode: "en"))

        controller.isHybridSearchOnboardingShown = true
        XCTAssertFalse(controller.shouldShowOnboarding(languageCode: "el"))
    }

    func testShouldShowOnboardingControlGroup() {
        setBucketOverride("control")
        XCTAssertFalse(controller.shouldShowOnboarding(languageCode: "el"))
    }

    func testIsHybridSearchActive() {
        setBucketOverride("semanticLexical")
        XCTAssertFalse(controller.isHybridSearchActive(languageCode: "el"))

        controller.isHybridSearchEnabled = true
        XCTAssertTrue(controller.isHybridSearchActive(languageCode: "el"))
        XCTAssertFalse(controller.isHybridSearchActive(languageCode: "en"))
    }

    func testIsHybridSearchActiveControlGroup() {
        setBucketOverride("control")
        controller.isHybridSearchEnabled = true
        XCTAssertFalse(controller.isHybridSearchActive(languageCode: "el"))
    }

    // MARK: - Response model

    func testSemanticSearchResponseDecoding() throws {
        let json = """
        {
            "language_code": "el",
            "query": "test",
            "semantic_search_results": [
                {
                    "page_title": "Greek_mythology",
                    "section_header": "Origins",
                    "section_index": 2,
                    "section_text": "The '''gods''' of ''Olympus'' ( )",
                    "url": "https://el.wikipedia.org/wiki/Greek_mythology"
                }
            ]
        }
        """

        let response = try JSONDecoder().decode(WMFSemanticSearchResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.languageCode, "el")
        XCTAssertEqual(response.query, "test")
        XCTAssertEqual(response.results.count, 1)

        let result = try XCTUnwrap(response.results.first)
        XCTAssertEqual(result.rawTitle, "Greek_mythology")
        XCTAssertEqual(result.title, "Greek mythology")
        XCTAssertEqual(result.sectionHeader, "Origins")
        XCTAssertEqual(result.sectionIndex, 2)
        XCTAssertEqual(result.url, "https://el.wikipedia.org/wiki/Greek_mythology")
        XCTAssertEqual(result.processedSnippetHTML, "The <b>gods</b> of <i>Olympus</i> ")
    }

    // MARK: - MediaWiki full-text semantic response (6240fa0d02)

    func testMediaWikiFullTextSearchResponseDecoding() throws {
        let json = """
        {
            "batchcomplete": true,
            "query": {
                "pages": [
                    {
                        "pageid": 2,
                        "ns": 0,
                        "title": "Dwarf planet",
                        "index": 2,
                        "description": "Small planetary-mass object",
                        "snippet": "A <b>dwarf planet</b> orbits the Sun."
                    },
                    {
                        "pageid": 1,
                        "ns": 0,
                        "title": "Pluto",
                        "index": 1,
                        "description": "Dwarf planet",
                        "snippet": "Pluto was reclassified as a <i>dwarf planet</i>.",
                        "sectiontitle": "IAU classification",
                        "thumbnail": {
                            "source": "https://upload.wikimedia.org/pluto.jpg",
                            "width": 320,
                            "height": 320
                        }
                    }
                ]
            }
        }
        """

        let response = try JSONDecoder().decode(WMFMediaWikiFullTextSearchResponse.self, from: Data(json.utf8))
        let pages = try XCTUnwrap(response.query?.pages)
        XCTAssertEqual(pages.count, 2)
        XCTAssertEqual(pages[1].title, "Pluto")
        XCTAssertEqual(pages[1].sectiontitle, "IAU classification")
        XCTAssertEqual(pages[1].thumbnail?.source, "https://upload.wikimedia.org/pluto.jpg")
        XCTAssertNil(pages[0].sectiontitle)
    }

    func testFullTextSearchResultFragmentAddsUnderscores() {
        let result = WMFSemanticFullTextSearchResults.Result(title: "Pluto", snippetHTML: "", sectionTitle: "IAU classification", description: nil, thumbnailURL: nil)
        XCTAssertEqual(result.fragment, "IAU_classification")

        let noSection = WMFSemanticFullTextSearchResults.Result(title: "Pluto", snippetHTML: "", sectionTitle: nil, description: nil, thumbnailURL: nil)
        XCTAssertNil(noSection.fragment)

        let emptySection = WMFSemanticFullTextSearchResults.Result(title: "Pluto", snippetHTML: "", sectionTitle: "", description: nil, thumbnailURL: nil)
        XCTAssertNil(emptySection.fragment)
    }
}
