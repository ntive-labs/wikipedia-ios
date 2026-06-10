import XCTest
@testable import WMFData
@testable import WMFDataMocks

final class WMFGamesDataControllerTests: XCTestCase {

    // MARK: - Properties

    var store: WMFCoreDataStore?
    var dataController: WMFGamesDataController?

    lazy var enProject: WMFProject = {
        let language = WMFLanguage(languageCode: "en", languageVariantCode: nil)
        return .wikipedia(language)
    }()

    /// Date string with enough On This Day events in the May 7 fixture (55 events).
    let dateWithEnoughEvents = "2026-05-07"

    /// Date string for the Feb 21 fixture that only has 3 events (fewer than 5 pairs).
    /// Since Android commit 4824d3a9f7, days like this recycle events from a copy of
    /// the pool and still produce a full set of questions.
    let dateWithFewEvents = "2026-02-21"

    /// Date string for the Jun 9 fixture with 9 events: 4 real pairs plus one leftover
    /// event whose partner is recycled from the pool copy (Android commit 4824d3a9f7;
    /// previously a synthesized blank year+10 event, e17bbd4e49).
    let dateWithNineEvents = "2026-06-09"

    /// Date string for the Mar 15 fixture whose 3 events all share one year, so no
    /// question can ever be formed and the day must stay unavailable.
    let dateWithSameYearEvents = "2026-03-15"

    // MARK: - Setup

    override func setUp() async throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try await WMFCoreDataStore(appContainerURL: temporaryDirectory)
        self.store = store

        WMFDataEnvironment.current.appData = WMFAppData(appLanguages: [
            WMFLanguage(languageCode: "en", languageVariantCode: nil)
        ])

        self.dataController = WMFGamesDataController(coreDataStore: store)

        try await super.setUp()
    }

    // MARK: - Helper Factories

    private func makeOnThisDayController(fixture: String) -> WMFOnThisDayDataController {
        let mockService = WMFMockBasicService(jsonResourceName: fixture)
        return WMFOnThisDayDataController(basicService: mockService)
    }

    private func onThisDayControllerWithEnoughEvents() -> WMFOnThisDayDataController {
        makeOnThisDayController(fixture: "onthisday-events-05-07-get")
    }

    private func onThisDayControllerWithFewEvents() -> WMFOnThisDayDataController {
        makeOnThisDayController(fixture: "onthisday-events-02-21-get")
    }

    private func onThisDayControllerWithNineEvents() -> WMFOnThisDayDataController {
        makeOnThisDayController(fixture: "onthisday-events-06-09-get")
    }

    private func onThisDayControllerWithSameYearEvents() -> WMFOnThisDayDataController {
        makeOnThisDayController(fixture: "onthisday-events-03-15-get")
    }

    // MARK: - fetchOrStartWhichCameFirstDailySession Tests

    func testFetchOrStartCreatesNewSessionWithFiveQuestions() async throws {
        guard let dataController else { throw TestsError.missingDataController }

        let (gameState, _) = try await dataController.fetchOrStartWhichCameFirstDailySession(
            date: dateWithEnoughEvents,
            project: enProject,
            onThisDayDataController: onThisDayControllerWithEnoughEvents()
        )

        XCTAssertEqual(gameState.questions.count, 5)
        XCTAssertTrue(gameState.answers.isEmpty)
    }

    func testFetchOrStartResumesExistingSessionWithoutNewAPICall() async throws {
        guard let dataController else { throw TestsError.missingDataController }

        let otdController = onThisDayControllerWithEnoughEvents()

        let (firstState, _) = try await dataController.fetchOrStartWhichCameFirstDailySession(
            date: dateWithEnoughEvents,
            project: enProject,
            onThisDayDataController: otdController
        )

        guard let firstQuestion = firstState.questions.first else {
            XCTFail("Expected at least one question")
            return
        }

        _ = try await dataController.submitWhichCameFirstAnswer(
            sessionIdentifier: try await sessionIdentifier(for: dateWithEnoughEvents),
            questionIdentifier: firstQuestion.id,
            pickedOption: firstQuestion.correctAnswer
        )

        let (resumedState, _) = try await dataController.fetchOrStartWhichCameFirstDailySession(
            date: dateWithEnoughEvents,
            project: enProject,
            onThisDayDataController: makeOnThisDayController(fixture: "onthisday-events-05-07-get")
        )

        XCTAssertEqual(resumedState.questions.count, 5)
        XCTAssertEqual(resumedState.answers.count, 1)
        XCTAssertEqual(resumedState.answers[firstQuestion.id.uuidString], firstQuestion.correctAnswer)
    }

    func testFetchOrStartQuestionsHaveDistinctYears() async throws {
        guard let dataController else { throw TestsError.missingDataController }

        let (gameState, _) = try await dataController.fetchOrStartWhichCameFirstDailySession(
            date: dateWithEnoughEvents,
            project: enProject,
            onThisDayDataController: onThisDayControllerWithEnoughEvents()
        )

        for question in gameState.questions {
            XCTAssertNotEqual(
                question.optionA.date,
                question.optionB.date,
                "Each question's two options should have different dates"
            )
        }
    }

    func testFetchOrStartCorrectAnswerIsValidOption() async throws {
        guard let dataController else { throw TestsError.missingDataController }

        let (gameState, _) = try await dataController.fetchOrStartWhichCameFirstDailySession(
            date: dateWithEnoughEvents,
            project: enProject,
            onThisDayDataController: onThisDayControllerWithEnoughEvents()
        )

        for question in gameState.questions {
            XCTAssertTrue(
                question.correctAnswer == "A" || question.correctAnswer == "B",
                "correctAnswer must be 'A' or 'B', got '\(question.correctAnswer)'"
            )
        }
    }

    // MARK: - submitWhichCameFirstAnswer Tests

    func testSubmitCorrectAnswerIncrementsScore() async throws {
        guard let dataController else { throw TestsError.missingDataController }

        let (gameState, _) = try await dataController.fetchOrStartWhichCameFirstDailySession(
            date: dateWithEnoughEvents,
            project: enProject,
            onThisDayDataController: onThisDayControllerWithEnoughEvents()
        )

        guard let firstQuestion = gameState.questions.first else {
            XCTFail("Expected at least one question")
            return
        }

        let sessionID = try await sessionIdentifier(for: dateWithEnoughEvents)
        let result = try await dataController.submitWhichCameFirstAnswer(
            sessionIdentifier: sessionID,
            questionIdentifier: firstQuestion.id,
            pickedOption: firstQuestion.correctAnswer
        )

        XCTAssertTrue(result.isCorrect)
        XCTAssertEqual(result.correctAnswer, firstQuestion.correctAnswer)

        let sessions = try await dataController.fetchWhichCameFirstSessions(project: enProject)
        XCTAssertEqual(sessions.first?.score, 1)
    }

    func testSubmitWrongAnswerDoesNotIncrementScore() async throws {
        guard let dataController else { throw TestsError.missingDataController }

        let (gameState, _) = try await dataController.fetchOrStartWhichCameFirstDailySession(
            date: dateWithEnoughEvents,
            project: enProject,
            onThisDayDataController: onThisDayControllerWithEnoughEvents()
        )

        guard let firstQuestion = gameState.questions.first else {
            XCTFail("Expected at least one question")
            return
        }

        let wrongAnswer = firstQuestion.correctAnswer == "A" ? "B" : "A"
        let sessionID = try await sessionIdentifier(for: dateWithEnoughEvents)
        let result = try await dataController.submitWhichCameFirstAnswer(
            sessionIdentifier: sessionID,
            questionIdentifier: firstQuestion.id,
            pickedOption: wrongAnswer
        )

        XCTAssertFalse(result.isCorrect)
        XCTAssertEqual(result.correctAnswer, firstQuestion.correctAnswer)

        let sessions = try await dataController.fetchWhichCameFirstSessions(project: enProject)
        XCTAssertEqual(sessions.first?.score, 0)
    }

    func testSubmitInvalidOptionThrows() async throws {
        guard let dataController else { throw TestsError.missingDataController }

        let (gameState, _) = try await dataController.fetchOrStartWhichCameFirstDailySession(
            date: dateWithEnoughEvents,
            project: enProject,
            onThisDayDataController: onThisDayControllerWithEnoughEvents()
        )

        guard let firstQuestion = gameState.questions.first else {
            XCTFail("Expected at least one question")
            return
        }

        let sessionID = try await sessionIdentifier(for: dateWithEnoughEvents)
        do {
            _ = try await dataController.submitWhichCameFirstAnswer(
                sessionIdentifier: sessionID,
                questionIdentifier: firstQuestion.id,
                pickedOption: "C"
            )
            XCTFail("Expected invalidPickedOption error")
        } catch WMFGamesDataController.CustomError.invalidPickedOption {
            // expected
        }
    }

    func testAnsweringAllQuestionsCompletesSession() async throws {
        guard let dataController else { throw TestsError.missingDataController }

        let (gameState, _) = try await dataController.fetchOrStartWhichCameFirstDailySession(
            date: dateWithEnoughEvents,
            project: enProject,
            onThisDayDataController: onThisDayControllerWithEnoughEvents()
        )

        XCTAssertEqual(gameState.questions.count, 5)
        let sessionID = try await sessionIdentifier(for: dateWithEnoughEvents)

        for question in gameState.questions {
            _ = try await dataController.submitWhichCameFirstAnswer(
                sessionIdentifier: sessionID,
                questionIdentifier: question.id,
                pickedOption: question.correctAnswer
            )
        }

        let sessions = try await dataController.fetchWhichCameFirstSessions(project: enProject)
        guard let session = sessions.first else {
            XCTFail("Expected at least one session")
            return
        }

        XCTAssertEqual(session.status, .completed)
        XCTAssertNotNil(session.completedDate)
        XCTAssertEqual(session.score, 5)
        XCTAssertEqual(session.currentQuestionIndex, 5)
    }

    func testSubmitAnswerUpdatesCurrentQuestionIndex() async throws {
        guard let dataController else { throw TestsError.missingDataController }

        let (gameState, _) = try await dataController.fetchOrStartWhichCameFirstDailySession(
            date: dateWithEnoughEvents,
            project: enProject,
            onThisDayDataController: onThisDayControllerWithEnoughEvents()
        )

        guard let firstQuestion = gameState.questions.first else {
            XCTFail("Expected at least one question")
            return
        }

        let sessionID = try await sessionIdentifier(for: dateWithEnoughEvents)
        _ = try await dataController.submitWhichCameFirstAnswer(
            sessionIdentifier: sessionID,
            questionIdentifier: firstQuestion.id,
            pickedOption: firstQuestion.correctAnswer
        )

        let sessions = try await dataController.fetchWhichCameFirstSessions(project: enProject)
        XCTAssertEqual(sessions.first?.currentQuestionIndex, 1)
    }

    // MARK: - fetchWhichCameFirstSessions Tests

    func testFetchSessionsReturnsSortedByDateDescending() async throws {
        guard let dataController else { throw TestsError.missingDataController }

        let earlierDate = "2026-05-06"
        let laterDate = "2026-05-07"

        _ = try await dataController.fetchOrStartWhichCameFirstDailySession(
            date: earlierDate,
            project: enProject,
            onThisDayDataController: onThisDayControllerWithEnoughEvents()
        )

        _ = try await dataController.fetchOrStartWhichCameFirstDailySession(
            date: laterDate,
            project: enProject,
            onThisDayDataController: onThisDayControllerWithEnoughEvents()
        )

        let sessions = try await dataController.fetchWhichCameFirstSessions(project: enProject)
        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(sessions[0].dailyGameDate, laterDate)
        XCTAssertEqual(sessions[1].dailyGameDate, earlierDate)
    }

    func testFetchSessionsReturnsEmptyForNewStore() async throws {
        guard let dataController else { throw TestsError.missingDataController }

        let sessions = try await dataController.fetchWhichCameFirstSessions(project: enProject)
        XCTAssertTrue(sessions.isEmpty)
    }

    // MARK: - isWhichCameFirstDailySessionAvailable Tests

    func testIsAvailableReturnsTrueForExistingSession() async throws {
        guard let dataController else { throw TestsError.missingDataController }

        _ = try await dataController.fetchOrStartWhichCameFirstDailySession(
            date: dateWithEnoughEvents,
            project: enProject,
            onThisDayDataController: onThisDayControllerWithEnoughEvents()
        )

        let isAvailable = try await dataController.isWhichCameFirstDailySessionAvailable(
            date: dateWithEnoughEvents,
            project: enProject,
            onThisDayDataController: onThisDayControllerWithEnoughEvents()
        )

        XCTAssertTrue(isAvailable)
    }

    func testIsAvailableReturnsTrueWhenAPIHasEnoughEvents() async throws {
        guard let dataController else { throw TestsError.missingDataController }

        let isAvailable = try await dataController.isWhichCameFirstDailySessionAvailable(
            date: dateWithEnoughEvents,
            project: enProject,
            onThisDayDataController: onThisDayControllerWithEnoughEvents()
        )

        XCTAssertTrue(isAvailable)
    }

    func testIsAvailableReturnsTrueWhenEventsAreRecycled() async throws {
        guard let dataController else { throw TestsError.missingDataController }

        // 3 distinct-year events used to be insufficient for 5 questions; since
        // Android commit 4824d3a9f7 the pairing loop recycles events from a copy
        // of the pool, so the day is now playable.
        let isAvailable = try await dataController.isWhichCameFirstDailySessionAvailable(
            date: dateWithFewEvents,
            project: enProject,
            onThisDayDataController: onThisDayControllerWithFewEvents()
        )

        XCTAssertTrue(isAvailable)
    }

    func testIsAvailableReturnsFalseWhenAllEventsShareOneYear() async throws {
        guard let dataController else { throw TestsError.missingDataController }

        // Same-year events can never form a question, even with recycling.
        let isAvailable = try await dataController.isWhichCameFirstDailySessionAvailable(
            date: dateWithSameYearEvents,
            project: enProject,
            onThisDayDataController: onThisDayControllerWithSameYearEvents()
        )

        XCTAssertFalse(isAvailable)
    }

    func testIsAvailableReturnsTrueWhenFallbackPairingFillsQuestions() async throws {
        guard let dataController else { throw TestsError.missingDataController }

        let isAvailable = try await dataController.isWhichCameFirstDailySessionAvailable(
            date: dateWithNineEvents,
            project: enProject,
            onThisDayDataController: onThisDayControllerWithNineEvents()
        )

        XCTAssertTrue(isAvailable)
    }

    func testWhichCameFirstSessionWithInsufficientEvents() async throws {
        guard let dataController else { throw TestsError.missingDataController }

        // 9 events pair into 4 real questions; the leftover event's partner is
        // recycled from the pool copy (Android parity: 4824d3a9f7) — a real,
        // already-used event, not the former synthesized blank year+10 card.
        let (gameState, _) = try await dataController.fetchOrStartWhichCameFirstDailySession(
            date: dateWithNineEvents,
            project: enProject,
            onThisDayDataController: onThisDayControllerWithNineEvents()
        )

        XCTAssertEqual(gameState.questions.count, 5)

        // No blank synthesized options anywhere.
        for question in gameState.questions {
            XCTAssertFalse(question.optionA.title.isEmpty)
            XCTAssertFalse(question.optionB.title.isEmpty)
        }

        // With 9 events and 5 questions, exactly one event must appear twice.
        let titles = gameState.questions.flatMap { [$0.optionA.title, $0.optionB.title] }
        XCTAssertEqual(titles.count, 10)
        XCTAssertEqual(Set(titles).count, 9)

        // The recycled partner can predate its event1, so every correct answer
        // must match the earlier option date.
        for question in gameState.questions {
            let earlier = question.optionA.date < question.optionB.date ? "A" : "B"
            XCTAssertEqual(question.correctAnswer, earlier)
        }
    }

    func testWhichCameFirstSessionRecyclesEventsWhenPoolRunsOut() async throws {
        guard let dataController else { throw TestsError.missingDataController }

        // Only 3 events: the pool is exhausted after question 1, so event1 itself
        // is recycled via poolCopy[index % poolCopy.count] and partners come from
        // the pool copy (Android parity: 4824d3a9f7). Previously this day threw
        // CustomError.insufficientQuestions.
        let (gameState, _) = try await dataController.fetchOrStartWhichCameFirstDailySession(
            date: dateWithFewEvents,
            project: enProject,
            onThisDayDataController: onThisDayControllerWithFewEvents()
        )

        XCTAssertEqual(gameState.questions.count, 5)

        for question in gameState.questions {
            XCTAssertFalse(question.optionA.title.isEmpty)
            XCTAssertFalse(question.optionB.title.isEmpty)
            // Options within a question always have distinct years.
            XCTAssertNotEqual(question.optionA.date, question.optionB.date)
            let earlier = question.optionA.date < question.optionB.date ? "A" : "B"
            XCTAssertEqual(question.correctAnswer, earlier)
        }
    }

    // MARK: - fetchWhichCameFirstStats Tests

    func testStatsGamesPlayedCountsOnlyCompletedSessions() async throws {
        guard let dataController else { throw TestsError.missingDataController }

        // Start but do not complete a session
        _ = try await dataController.fetchOrStartWhichCameFirstDailySession(
            date: dateWithEnoughEvents,
            project: enProject,
            onThisDayDataController: onThisDayControllerWithEnoughEvents()
        )

        let stats = try await dataController.fetchWhichCameFirstStats(project: enProject)
        XCTAssertEqual(stats.gamesPlayed, 0)
    }

    func testStatsGamesPlayedIncrementsAfterCompletion() async throws {
        guard let dataController else { throw TestsError.missingDataController }

        try await completeAllQuestions(for: dateWithEnoughEvents)

        let stats = try await dataController.fetchWhichCameFirstStats(project: enProject)
        XCTAssertEqual(stats.gamesPlayed, 1)
    }

    func testStatsAverageScoreAfterPerfectGame() async throws {
        guard let dataController else { throw TestsError.missingDataController }

        try await completeAllQuestions(for: dateWithEnoughEvents)

        let stats = try await dataController.fetchWhichCameFirstStats(project: enProject)
        XCTAssertEqual(stats.averageScore, 5)
    }

    func testStatsBestStreakAfterOneGame() async throws {
        guard let dataController else { throw TestsError.missingDataController }

        try await completeAllQuestions(for: dateWithEnoughEvents)

        let stats = try await dataController.fetchWhichCameFirstStats(project: enProject)
        XCTAssertEqual(stats.bestStreak, 1)
    }

    func testStatsAreZeroWithNoSessions() async throws {
        guard let dataController else { throw TestsError.missingDataController }

        let stats = try await dataController.fetchWhichCameFirstStats(project: enProject)
        XCTAssertEqual(stats.gamesPlayed, 0)
        XCTAssertEqual(stats.currentStreak, 0)
        XCTAssertEqual(stats.bestStreak, 0)
        XCTAssertEqual(stats.averageScore, 0)
    }

    // MARK: - fetchWhichCameFirstDailyPreviewEvents Tests

    func testPreviewEventsReturnsTwoDistinctOptions() async throws {
        guard let dataController else { throw TestsError.missingDataController }

        let preview = try await dataController.fetchWhichCameFirstDailyPreviewEvents(
            date: dateWithEnoughEvents,
            project: enProject,
            onThisDayDataController: onThisDayControllerWithEnoughEvents()
        )

        XCTAssertNotNil(preview)
        XCTAssertNotEqual(preview?.optionA.date, preview?.optionB.date)
    }

    func testPreviewEventsReusesExistingSessionWithoutAPICall() async throws {
        guard let dataController else { throw TestsError.missingDataController }

        // Create a session first
        let (gameState, _) = try await dataController.fetchOrStartWhichCameFirstDailySession(
            date: dateWithEnoughEvents,
            project: enProject,
            onThisDayDataController: onThisDayControllerWithEnoughEvents()
        )

        guard let firstQuestion = gameState.questions.first else {
            XCTFail("Expected at least one question")
            return
        }

        // Preview should match the already-persisted first question
        let preview = try await dataController.fetchWhichCameFirstDailyPreviewEvents(
            date: dateWithEnoughEvents,
            project: enProject,
            onThisDayDataController: onThisDayControllerWithEnoughEvents()
        )

        XCTAssertEqual(preview?.optionA.title, firstQuestion.optionA.title)
        XCTAssertEqual(preview?.optionB.title, firstQuestion.optionB.title)
    }

    // MARK: - Helpers

    /// Fetches the identifier of the persisted session for a given date from Core Data.
    private func sessionIdentifier(for date: String) async throws -> UUID {
        guard let dataController else { throw TestsError.missingDataController }
        let sessions = try await dataController.fetchWhichCameFirstSessions(project: enProject)
        guard let session = sessions.first(where: { $0.dailyGameDate == date }) else {
            throw TestsError.sessionNotFound
        }
        return session.identifier
    }

    /// Starts a session for the given date and answers all questions correctly.
    @discardableResult
    private func completeAllQuestions(for date: String) async throws -> [WMFWhichCameFirstQuestion] {
        guard let dataController else { throw TestsError.missingDataController }

        let (gameState, _) = try await dataController.fetchOrStartWhichCameFirstDailySession(
            date: date,
            project: enProject,
            onThisDayDataController: onThisDayControllerWithEnoughEvents()
        )

        let sessionID = try await sessionIdentifier(for: date)
        for question in gameState.questions {
            _ = try await dataController.submitWhichCameFirstAnswer(
                sessionIdentifier: sessionID,
                questionIdentifier: question.id,
                pickedOption: question.correctAnswer
            )
        }

        return gameState.questions
    }

    // MARK: - Error

    enum TestsError: Error {
        case missingDataController
        case sessionNotFound
    }
}
