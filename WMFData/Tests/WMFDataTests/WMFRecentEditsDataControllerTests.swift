import XCTest
@testable import WMFData
@testable import WMFDataMocks

final class WMFRecentEditsDataControllerTests: XCTestCase {

    private let enProject = WMFProject.wikipedia(WMFLanguage(languageCode: "en", languageVariantCode: nil))
    private let igProject = WMFProject.wikipedia(WMFLanguage(languageCode: "ig", languageVariantCode: nil))

    private var mockService: WMFMockRecentEditsMediaWikiService!

    override func setUp() async throws {
        WMFDataEnvironment.current.appData = WMFAppData(appLanguages: [
            WMFLanguage(languageCode: "en", languageVariantCode: nil),
            WMFLanguage(languageCode: "es", languageVariantCode: nil)
        ])
        mockService = WMFMockRecentEditsMediaWikiService()
        WMFDataEnvironment.current.mediaWikiService = mockService
        WMFDataEnvironment.current.userDefaultsStore = WMFMockKeyValueStore()
        WMFDataEnvironment.current.sharedCacheStore = WMFMockKeyValueStore()
    }

    // MARK: - Filter type parity

    func testFilterTypeValuesMatchAndroid() {
        XCTAssertEqual(WMFRecentEditsFilterType.minorEdits.value, "minor")
        XCTAssertEqual(WMFRecentEditsFilterType.nonMinorEdits.value, "!minor")
        XCTAssertEqual(WMFRecentEditsFilterType.bot.value, "bot")
        XCTAssertEqual(WMFRecentEditsFilterType.human.value, "!bot")
        XCTAssertEqual(WMFRecentEditsFilterType.notLatestRevision.value, "1")
        XCTAssertEqual(WMFRecentEditsFilterType.unregistered.value, "anon")
        XCTAssertEqual(WMFRecentEditsFilterType.registered.value, "!anon")
        XCTAssertEqual(WMFRecentEditsFilterType.newcomers.value, "0,10|0,4")
        XCTAssertEqual(WMFRecentEditsFilterType.learners.value, "10,500|4,30")
        XCTAssertEqual(WMFRecentEditsFilterType.experiencedUsers.value, "500,-1|30,-1")
        XCTAssertEqual(WMFRecentEditsFilterType.damagingLikelyProblems.value, "0.629|0.944")
        XCTAssertEqual(WMFRecentEditsFilterType.goodfaithGood.value, "0.75|1")
    }

    func testFilterTypeScoreRangeParsing() {
        let range = WMFRecentEditsFilterType.damagingLikelyProblems.scoreRange
        XCTAssertEqual(range?.min ?? -1, 0.629, accuracy: 0.0001)
        XCTAssertEqual(range?.max ?? -1, 0.944, accuracy: 0.0001)
    }

    func testFilterTypeExperienceRangeParsing() {
        let range = WMFRecentEditsFilterType.newcomers.experienceRange
        XCTAssertEqual(range?.edits.min, 0)
        XCTAssertEqual(range?.edits.max, 10)
        XCTAssertEqual(range?.days.min, 0)
        XCTAssertEqual(range?.days.max, 4)

        let experienced = WMFRecentEditsFilterType.experiencedUsers.experienceRange
        XCTAssertEqual(experienced?.edits.max, -1)
        XCTAssertEqual(experienced?.days.max, -1)
    }

    func testDefaultFilterTypeSetMatchesAndroid() {
        XCTAssertEqual(WMFRecentEditsFilterType.defaultFilterTypeSet, [.unregistered, .newcomers, .allEdits, .latestRevision, .allEditors])
    }

    // MARK: - Persistence + active filter count

    func testSaveAndLoadFilterSettings() {
        let controller = WMFRecentEditsDataController()
        let settings = WMFRecentEditsFilterSettings(includedTypes: [.registered, .experiencedUsers, .minorEdits, .damagingGood])
        controller.saveFilterSettings(settings)
        XCTAssertEqual(controller.loadFilterSettings(), settings)
    }

    func testDefaultActiveFilterCountIsZero() {
        let controller = WMFRecentEditsDataController()
        controller.saveFilterSettings(WMFRecentEditsFilterSettings())
        XCTAssertEqual(controller.activeFilterCount(), 0)
    }

    func testActiveFilterCountWithORESAndDefaultsOnly() {
        // Defaults for other groups + a single damaging bucket, no user status selected.
        let controller = WMFRecentEditsDataController()
        controller.saveFilterSettings(WMFRecentEditsFilterSettings(includedTypes: [.allEdits, .latestRevision, .allEditors, .damagingLikelyProblems]))
        // 2 (both default user-status filters missing) + 0 (others all default) + 1 (ores) = 3
        XCTAssertEqual(controller.activeFilterCount(), 3)
    }

    func testActiveFilterCountWithExperiencedRegistered() {
        let controller = WMFRecentEditsDataController()
        controller.saveFilterSettings(WMFRecentEditsFilterSettings(includedTypes: [.allEdits, .latestRevision, .allEditors, .registered, .experiencedUsers]))
        // symmetric difference of {registered, experiencedUsers} vs {unregistered, newcomers} = 4
        XCTAssertEqual(controller.activeFilterCount(), 4)
    }

    // MARK: - ORES local filtering (cache-independent)

    func testFilterORESDamagingBucket() {
        let controller = WMFRecentEditsDataController()
        controller.saveFilterSettings(WMFRecentEditsFilterSettings(includedTypes: [.damagingLikelyProblems]))

        let items = [
            makeItem(rev: 1, user: "a", damaging: 0.02),
            makeItem(rev: 2, user: "b", damaging: 0.80),
            makeItem(rev: 3, user: "c", damaging: nil) // no ores -> dropped when ores filter active
        ]

        let filtered = controller.filterORESScores(items, isDamagingGroup: true)
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.revisionID, 2)
    }

    func testFilterORESInactivePassesThrough() {
        let controller = WMFRecentEditsDataController()
        controller.saveFilterSettings(WMFRecentEditsFilterSettings()) // no ores selected
        let items = [makeItem(rev: 1, user: "a", damaging: nil)]
        XCTAssertEqual(controller.filterORESScores(items, isDamagingGroup: true).count, 1)
    }

    // MARK: - Fetch + two-stage filtering (integration against mock)

    func testFetchRecentEditsExperiencedRegistered() {
        let controller = WMFRecentEditsDataController()
        controller.saveFilterSettings(WMFRecentEditsFilterSettings(includedTypes: [.allEdits, .latestRevision, .allEditors, .registered, .experiencedUsers]))

        let expectation = XCTestExpectation(description: "Fetch recent edits")
        var result: WMFRecentEdits?
        controller.fetchRecentEdits(project: enProject) { r in
            if case .success(let edits) = r { result = edits } else { XCTFail("fetch failed: \(r)") }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 10.0)

        guard let result else { XCTFail("missing result"); return }
        XCTAssertEqual(result.unfilteredItems.count, 5, "unfiltered list should contain the whole server page")
        XCTAssertEqual(result.items.count, 1, "only the experienced, registered author should remain")
        XCTAssertEqual(result.items.first?.username, "ProfUser")
        XCTAssertEqual(result.items.first?.revisionID, 1003)
        XCTAssertEqual(result.activeFilterCount, 4)
        XCTAssertEqual(result.continueString, "20260726120000|1000")
    }

    func testFetchRecentEditsORESParsing() {
        let controller = WMFRecentEditsDataController()
        controller.saveFilterSettings(WMFRecentEditsFilterSettings(includedTypes: [.allEdits, .latestRevision, .allEditors, .registered, .experiencedUsers]))

        let expectation = XCTestExpectation(description: "Fetch recent edits ores")
        var result: WMFRecentEdits?
        controller.fetchRecentEdits(project: enProject) { r in
            if case .success(let edits) = r { result = edits }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 10.0)

        let prof = result?.unfilteredItems.first(where: { $0.username == "ProfUser" })
        XCTAssertEqual(prof?.oresDamaging ?? -1, 0.80, accuracy: 0.0001)
        XCTAssertEqual(prof?.oresGoodFaith ?? -1, 0.30, accuracy: 0.0001)

        // Anonymous item is parsed with the anon flag and tags.
        let anon = result?.unfilteredItems.first(where: { $0.isAnon })
        XCTAssertEqual(anon?.username, "192.0.2.5")
        XCTAssertEqual(anon?.tags, ["mobile edit", "mobile web edit"])
    }

    func testFetchRecentEditsORESDamagingBucketFilter() {
        let controller = WMFRecentEditsDataController()
        controller.saveFilterSettings(WMFRecentEditsFilterSettings(includedTypes: [.allEdits, .latestRevision, .allEditors, .damagingLikelyProblems]))

        let expectation = XCTestExpectation(description: "Fetch recent edits ores bucket")
        var result: WMFRecentEdits?
        controller.fetchRecentEdits(project: enProject) { r in
            if case .success(let edits) = r { result = edits }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 10.0)

        // Only ProfUser's edit (damaging 0.80) falls into 0.629–0.944.
        XCTAssertEqual(result?.items.count, 1)
        XCTAssertEqual(result?.items.first?.username, "ProfUser")
        XCTAssertEqual(result?.activeFilterCount, 3)
    }

    // MARK: - Eligibility

    func testFetchPatrolEligibilityEligible() {
        mockService.returnEligibleUser = true
        let controller = WMFRecentEditsDataController()

        let expectation = XCTestExpectation(description: "eligibility eligible")
        var eligibility: WMFPatrolEligibility?
        controller.fetchPatrolEligibility(project: enProject) { r in
            if case .success(let e) = r { eligibility = e }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 10.0)

        XCTAssertEqual(eligibility?.isEligible, true)
        XCTAssertEqual(eligibility?.hasRollbackRights, true)
        XCTAssertEqual(eligibility?.isBlocked, false)
    }

    func testFetchPatrolEligibilityIneligible() {
        mockService.returnEligibleUser = false
        let controller = WMFRecentEditsDataController()

        let expectation = XCTestExpectation(description: "eligibility ineligible")
        var eligibility: WMFPatrolEligibility?
        controller.fetchPatrolEligibility(project: enProject) { r in
            if case .success(let e) = r { eligibility = e }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 10.0)

        XCTAssertEqual(eligibility?.isEligible, false)
        XCTAssertEqual(eligibility?.hasRollbackRights, false)
    }

    func testFetchPatrolEligibilityIgboRule() {
        // Igbo: eligible when editCount >= 500 and 30+ days tenure — the "eligible" fixture
        // has 6000 edits and a 2015 registration, satisfying the rule even without rollback.
        mockService.returnEligibleUser = true
        let controller = WMFRecentEditsDataController()

        let expectation = XCTestExpectation(description: "eligibility igbo")
        var eligibility: WMFPatrolEligibility?
        controller.fetchPatrolEligibility(project: igProject) { r in
            if case .success(let e) = r { eligibility = e }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 10.0)

        XCTAssertEqual(eligibility?.isEligible, true)
    }

    // MARK: - Revert-candidate cache

    func testRevertCandidatePopulateAndNext() {
        let controller = WMFRecentEditsDataController()
        let i0 = makeItem(rev: 10, user: "a", damaging: 0.1)
        let i1 = makeItem(rev: 11, user: "b", damaging: 0.1)
        let i2 = makeItem(rev: 12, user: "c", damaging: 0.1)
        controller.populateRevertCandidateCache(project: enProject, items: [i0, i1, i2])

        // populate does addFirst for each, so the last inserted item is served first.
        var served: [UInt] = []
        for _ in 0..<3 {
            let expectation = XCTestExpectation(description: "next candidate")
            controller.nextRevertCandidate(project: enProject) { r in
                if case .success(let item) = r { served.append(item.revisionID) }
                expectation.fulfill()
            }
            wait(for: [expectation], timeout: 10.0)
        }
        XCTAssertEqual(served, [12, 11, 10])
    }

    func testRevertCandidateFetchFromNetworkWhenEmpty() {
        let controller = WMFRecentEditsDataController()
        controller.saveFilterSettings(WMFRecentEditsFilterSettings(includedTypes: [.allEdits, .latestRevision, .allEditors, .registered, .experiencedUsers]))

        let expectation = XCTestExpectation(description: "next candidate from network")
        var served: WMFRecentEdits.Item?
        controller.nextRevertCandidate(project: enProject) { r in
            if case .success(let item) = r { served = item }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 10.0)

        XCTAssertEqual(served?.username, "ProfUser")
        XCTAssertEqual(served?.revisionID, 1003)
    }

    // MARK: - Helpers

    private func makeItem(rev: UInt, user: String, damaging: Float?, goodfaith: Float? = nil, anon: Bool = false) -> WMFRecentEdits.Item {
        WMFRecentEdits.Item(
            title: "Title \(rev)",
            pageID: Int(rev),
            revisionID: rev,
            oldRevisionID: rev - 1,
            rcid: rev + 5000,
            username: user,
            isAnon: anon,
            isBot: false,
            isMinor: false,
            isNew: false,
            timestamp: Date(timeIntervalSince1970: TimeInterval(1_700_000_000 + Int(rev))),
            parsedComment: "comment \(rev)",
            comment: "comment \(rev)",
            tags: [],
            byteLength: 100,
            oldByteLength: 90,
            oresDamaging: damaging,
            oresGoodFaith: goodfaith,
            project: enProject)
    }
}
