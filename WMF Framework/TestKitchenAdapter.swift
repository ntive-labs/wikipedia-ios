import UIKit
import WMFTestKitchen
import WMFData
import CocoaLumberjackSwift

@objc public class TestKitchenAdapter: NSObject, ClientDataCallback, EventSender {

    @objc public static let shared = TestKitchenAdapter()

    public lazy var client: TestKitchenClient = {
        TestKitchenClient(
            clientDataCallback: self,
            eventSender: self
        )
    }()

    private override init() {
        super.init()
    }

    // MARK: - ClientDataCallback

    public func getAgentData() -> AgentData? {
        let appInstallID: String? = try? WMFDataEnvironment.current.crossProcessUserDefaultsStore?.load(key: WMFUserDefaultsKey.appInstallID.rawValue)
        let versionName = WikipediaAppUtils.versionName()
        let buildNumber = Int(Bundle.main.wmf_bundleVersion() ?? "0")
        let deviceFamily = WikipediaAppUtils.formFactor()

        let deviceLanguage = Locale.preferredLanguages.first ?? "en"

        // Release status must be 1 of 3 values: debug, dev or prod
        
        #if DEBUG
        let releaseStatus = "debug"
        #elseif WMF_STAGING
        let releaseStatus = "dev"
        #elseif WMF_EXPERIMENTAL
        let releaseStatus = "dev"
        #elseif UITESTS
        let releaseStatus = "dev"
        #elseif TEST
        let releaseStatus = "dev"
        #elseif WMF_LOCAL
        let releaseStatus = "dev"
        #else
        let releaseStatus = "prod"
        #endif
        
        var appFlavor: String?
        #if NDEBUG
        if Bundle.main.isTestFlight() {
            appFlavor = "TestFlight"
        } else {
            appFlavor = "AppStore"
        }
        #endif

        return AgentData(
            appFlavor: appFlavor,
            appInstallId: appInstallID,
            appTheme: UserDefaults.standard.themeAnalyticsName,
            appVersion: buildNumber,
            appVersionName: versionName,
            clientPlatform: "ios",
            clientPlatformFamily: "app",
            deviceFamily: deviceFamily,
            deviceLanguage: deviceLanguage,
            releaseStatus: releaseStatus
        )
    }

    public func getMediawikiData() -> MediawikiData? {
        
        guard let primarySiteURL = MWKDataStore.shared().primarySiteURL,
              let project = WikimediaProject(siteURL: primarySiteURL) else {
            return nil
        }
        
        let databaseIdentifier = project.notificationsApiWikiIdentifier
        
        return MediawikiData(database: databaseIdentifier)
    }

    public func getPerformerData() -> PerformerData? {
        
        let dataStore = MWKDataStore.shared()
        let isLoggedIn = dataStore.authenticationManager.authStateIsPermanent
        let isTemp = dataStore.authenticationManager.authStateIsTemporary
        let sessionId = EventPlatformClient.shared.sessionID

        var languageGroups: String? = nil
        var languagePrimary: String? = nil
        
        // If in widget, don't lean on MMKDataStore for preferred languages
        if Bundle.main.isAppExtension {
            let cachedContent = WidgetController.shared.widgetCache
            languageGroups = cachedContent.settings.preferredLanguageCodes.joined(separator: ",")
            languagePrimary = cachedContent.settings.languageCode
        } else {
            let languageCodes = dataStore.languageLinkController.preferredLanguages.compactMap { $0.languageCode }
            languageGroups = languageCodes.joined(separator: ",")
            languagePrimary = EventPlatformClient.shared.primaryLanguage
        }


        return PerformerData(
            isLoggedIn: isLoggedIn,
            isTemp: isTemp,
            sessionId: sessionId,
            languageGroups: languageGroups,
            languagePrimary: languagePrimary
        )
    }

    // MARK: - Hybrid Search

    public func getHybridSearchExperiment() -> ExperimentImpl {
        let dataController = WMFHybridSearchDataController.shared

        let group: String
        switch WMFHybridSearchDataController.GroupName(rawValue: dataController.assignedGroupName) ?? .control {
        case .control:
            group = "control"
        case .lexicalSemantic:
            group = "lexicalsemantic"
        case .semanticLexical:
            group = "semanticlexical"
        }

        let appInstallID: String? = try? WMFDataEnvironment.current.crossProcessUserDefaultsStore?.load(key: WMFUserDefaultsKey.appInstallID.rawValue)

        return ExperimentImpl(name: "apps_hybridsearch", group: group, subjectId: appInstallID, isLoggable: {
            let languageCode = MWKDataStore.shared().languageLinkController.appLanguage?.languageCode
            return dataController.shouldInstrument(languageCode: languageCode)
        })
    }

    public func getPageData(articleTitle: String, languageCode: String?) -> PageData {
        return PageData(
            title: articleTitle.denormalizedPageTitle ?? articleTitle,
            namespaceId: 0,
            namespaceName: "MAIN",
            contentLanguage: languageCode
        )
    }

    // MARK: - EventSender

    public func sendEvents(_ events: [Event]) {
        guard let storageManager = EventPlatformClient.shared.storageManager else {
            DDLogError("TestKitchenAdapter: StorageManager unavailable")
            return
        }
        
        let encoder = JSONEncoder()
        for event in events {
            
#if DEBUG
            encoder.outputFormatting = .prettyPrinted
#endif
            
            guard let data = try? encoder.encode(event) else {
                DDLogError("TestKitchenAdapter: Failed to encode event")
                continue
            }
            
#if DEBUG
            // Convert to loose dictionary so we can sort keys and print that way.
            if let dict = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                let printablePayload = PrintableEventPayload(payload: dict)
                print("\n\n🧑‍🍳TestKitchen: Scheduling event to be sent to \(event.schema):")
                print("\(printablePayload)")
            }

            // Single-line event log, for test assertions. Appended to a file in
            // the app container (the unified log truncates long messages).
            if let lineData = try? JSONEncoder().encode(event),
               let line = String(data: lineData, encoding: .utf8) {
                NSLog("TKEV %@", line)
                let logURL = FileManager.default.temporaryDirectory.appendingPathComponent("tkev.log")
                if let lineData = (line + "\n").data(using: .utf8) {
                    if let handle = try? FileHandle(forWritingTo: logURL) {
                        defer { try? handle.close() }
                        _ = try? handle.seekToEnd()
                        try? handle.write(contentsOf: lineData)
                    } else {
                        try? lineData.write(to: logURL)
                    }
                }
            }
#endif
            
            storageManager.push(data: data, stream: .productMetricsAppBase)
        }
    }
}
