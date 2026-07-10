import UIKit
import WMF
import WMFData
import XCTest
@testable import Wikipedia

final class InsertLinkViewControllerTests: XCTestCase {

    private var dataStore: MWKDataStore!

    override func setUp(completion: @escaping (Error?) -> Void) {
        MWKDataStore.createTemporaryDataStore { dataStore in
            self.dataStore = dataStore
            completion(nil)
        }
    }

    override func tearDown() {
        super.tearDown()
        dataStore.removeFolderAtBasePath()
        dataStore = nil
    }

    /// Regression guard for commit 83e072604e, which dropped the `siteURL` assignment during the
    /// UISearchController refactor. Insert-link search must be scoped to the caller's article wiki so
    /// results — and the inserted link — resolve on the correct wiki. Mirrors Android's
    /// `SearchIntentTest` intent-scoping coverage.
    @MainActor
    func testSearchResultsControllerIsScopedToCallerSiteURL() throws {
        let frSiteURL = try XCTUnwrap(URL(string: "https://fr.wikipedia.org"))
        let link = try XCTUnwrap(Link(page: "Tour Eiffel", label: nil, exists: false))

        let viewController = InsertLinkViewController(link: link, siteURL: frSiteURL, dataStore: dataStore, theme: .light)
        viewController.loadViewIfNeeded()
        viewController.configureNavigationBar()

        let searchResultsVC = try XCTUnwrap(viewController.navigationItem.searchController?.searchResultsController as? SearchResultsViewController)
        XCTAssertEqual(searchResultsVC.siteURL, frSiteURL, "Insert-link search should be scoped to the caller's article wiki, not the app's default wiki.")
        XCTAssertFalse(searchResultsVC.showsLocalResults, "Insert-link search should stay remote-only, matching Android's InvokeSource.PLACES skip.")
    }
}
