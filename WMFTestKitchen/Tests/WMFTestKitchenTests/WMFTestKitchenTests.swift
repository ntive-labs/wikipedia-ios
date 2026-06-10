import XCTest
@testable import WMFTestKitchen

final class WMFTestKitchenTests: XCTestCase {

    func testStreamConfigDecodesNestedProducerConfig() throws {
        let json = """
        {
          "stream": "test.stream",
          "canary_events_enabled": true,
          "schema_title": "analytics/test/1.0.0",
          "producers": {
            "metrics_platform_client": {
              "provide_values": ["agent_app_install_id", "performer_session_id"]
            }
          }
        }
        """.data(using: .utf8)!

        let config = try JSONDecoder().decode(StreamConfig.self, from: json)

        XCTAssertEqual(config.streamName, "test.stream")
        XCTAssertTrue(config.canaryEventsEnabled)
        XCTAssertEqual(config.schemaTitle, "analytics/test/1.0.0")
        XCTAssertEqual(
            config.producerConfig?.metricsPlatformClientConfig?.requestedValues,
            ["agent_app_install_id", "performer_session_id"]
        )
        XCTAssertTrue(config.hasRequestedContextValuesConfig())
    }

    func testStreamConfigReportsNoRequestedValuesWhenProducerMissing() throws {
        let json = """
        {
          "stream": "test.stream",
          "canary_events_enabled": false
        }
        """.data(using: .utf8)!

        let config = try JSONDecoder().decode(StreamConfig.self, from: json)

        XCTAssertEqual(config.streamName, "test.stream")
        XCTAssertFalse(config.canaryEventsEnabled)
        XCTAssertNil(config.producerConfig)
        XCTAssertFalse(config.hasRequestedContextValuesConfig())
    }

    func testEventEncodesExperimentAndPageData() throws {
        let instrument = InstrumentImpl(name: "apps-search")
            .startFunnel(name: "search")
            .setExperiment(ExperimentImpl(
                name: "apps_hybridsearch",
                group: "semanticlexical",
                subjectId: "install-id-123"
            ))

        let pageData = PageData(
            id: 42,
            title: "Pluto",
            namespaceId: 0,
            namespaceName: "MAIN",
            contentLanguage: "en"
        )

        let event = Event(
            schema: TestKitchenClient.schemaAppBase,
            stream: TestKitchenClient.streamAppBase,
            dt: "2026-01-01T00:00:00Z",
            instrument: instrument,
            clientData: ClientData(pageData: pageData),
            interactionData: InteractionData(action: "search_result_click")
        )

        let data = try JSONEncoder().encode(event)
        let jsonObject = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        let experiment = try XCTUnwrap(jsonObject["experiment"] as? [String: Any])
        XCTAssertEqual(experiment["enrolled"] as? String, "apps_hybridsearch")
        XCTAssertEqual(experiment["assigned"] as? String, "semanticlexical")
        XCTAssertEqual(experiment["coordinator"] as? String, "custom")
        XCTAssertEqual(experiment["subject_id"] as? String, "install-id-123")

        let page = try XCTUnwrap(jsonObject["page"] as? [String: Any])
        XCTAssertEqual(page["id"] as? Int, 42)
        XCTAssertEqual(page["title"] as? String, "Pluto")
        XCTAssertEqual(page["namespace_id"] as? Int, 0)
        XCTAssertEqual(page["namespace_name"] as? String, "MAIN")
        XCTAssertEqual(page["content_language"] as? String, "en")
    }

    func testInstrumentDropsInteractionsWhenExperimentNotLoggable() {
        let recorder = EventRecorder()
        let client = TestKitchenClient(clientDataCallback: EmptyClientDataCallback(), eventSender: recorder)
        let instrument = client.getInstrument(name: "apps-search")
            .setExperiment(ExperimentImpl(name: "apps_hybridsearch", group: "control", isLoggable: { false }))

        instrument.submitInteraction(action: "click")

        XCTAssertTrue(recorder.events.isEmpty)
    }

    func testInstrumentSubmitsInteractionsWhenExperimentLoggable() {
        let recorder = EventRecorder()
        let client = TestKitchenClient(clientDataCallback: EmptyClientDataCallback(), eventSender: recorder)
        let instrument = client.getInstrument(name: "apps-search")
            .setExperiment(ExperimentImpl(name: "apps_hybridsearch", group: "control", isLoggable: { true }))

        instrument.submitInteraction(action: "click")

        XCTAssertEqual(recorder.events.count, 1)
        XCTAssertEqual(recorder.events.first?.action, "click")
        XCTAssertEqual(recorder.events.first?.experiment?.enrolled, "apps_hybridsearch")
    }
}

private final class EventRecorder: EventSender {
    var events: [Event] = []

    func sendEvents(_ events: [Event]) {
        self.events.append(contentsOf: events)
    }
}

private struct EmptyClientDataCallback: ClientDataCallback {
    func getAgentData() -> AgentData? { nil }
    func getMediawikiData() -> MediawikiData? { nil }
    func getPerformerData() -> PerformerData? { nil }
}
