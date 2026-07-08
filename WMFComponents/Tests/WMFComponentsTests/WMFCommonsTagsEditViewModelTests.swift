import XCTest
@testable import WMFComponents
@testable import WMFData
@testable import WMFDataMocks

@MainActor
final class WMFCommonsTagsEditViewModelTests: XCTestCase {

    override func setUp() async throws {
        WMFDataEnvironment.current.mediaWikiService = WMFMockCommonsMediaInfoService()
    }

    private func makeViewModel() -> WMFCommonsTagsEditViewModel {
        let config = WMFCommonsTagsEditViewModel.Config(fileTitle: "File:Example cat.jpg", pageID: 12345, languageCode: "en", imageThumbnailURL: nil)
        let strings = WMFCommonsTagsEditViewModel.LocalizedStrings(title: "Add image tags", subtitleFormat: "What is depicted in %1$@?", addTagButtonTitle: "Add a tag", publishButtonTitle: "Publish tags", cc0NoticeText: "CC0", searchTitle: "Add a tag", searchPlaceholder: "Search", exitConfirmationTitle: "Discard?", exitConfirmationMessage: "msg", exitConfirmationDiscard: "Discard", exitConfirmationKeepEditing: "Keep editing", publishedToastTitle: "Tags published")
        return WMFCommonsTagsEditViewModel(config: config, localizedStrings: strings)
    }

    func testSubtitleFormatting() {
        let vm = makeViewModel()
        XCTAssertEqual(vm.subtitle, "What is depicted in Example cat.jpg?")
        XCTAssertEqual(vm.displayFileTitle, "Example cat.jpg")
    }

    func testAddTagDeduplicatesByWikidataID() {
        let vm = makeViewModel()
        XCTAssertTrue(vm.addTag(WMFDepictsTag(wikidataID: "Q146", label: "cat")))
        // Adding the same id again should be a no-op.
        XCTAssertFalse(vm.addTag(WMFDepictsTag(wikidataID: "Q146", label: "cat (dup)")))
        XCTAssertEqual(vm.selectedTags.count, 1)
        XCTAssertTrue(vm.isSelected(WMFDepictsTag(wikidataID: "Q146", label: "cat")))
    }

    func testCanPublishAndUnpublishedGuard() {
        let vm = makeViewModel()
        XCTAssertFalse(vm.canPublish)
        XCTAssertFalse(vm.hasUnpublishedTags)
        vm.addTag(WMFDepictsTag(wikidataID: "Q146", label: "cat"))
        XCTAssertTrue(vm.canPublish)
        XCTAssertTrue(vm.hasUnpublishedTags)
        vm.removeTag(WMFDepictsTag(wikidataID: "Q146", label: "cat"))
        XCTAssertFalse(vm.canPublish)
    }

    func testSearchReturnsResults() async {
        let vm = makeViewModel()
        let results = await vm.search(term: "cat")
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results.first?.wikidataID, "Q146")
    }

    func testPublishInvokesSuccessCallback() {
        let vm = makeViewModel()
        vm.addTag(WMFDepictsTag(wikidataID: "Q146", label: "cat"))
        let expectation = XCTestExpectation(description: "publish success")
        vm.onPublishSucceeded = { revID in
            XCTAssertEqual(revID, 987700)
            expectation.fulfill()
        }
        vm.publish()
        wait(for: [expectation], timeout: 5.0)
    }
}
