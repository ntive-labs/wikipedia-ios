import Foundation

extension URL {
    
    // https://www.mediawiki.org/wiki/API:Main_page
    private static let baseMediaWikiAPIPathComponents = "/w/api.php"
    private static let basePaymentWikiAPIPathComponents = "/api.php"
    
    // https://www.mediawiki.org/wiki/Wikimedia_REST_API
    private static let baseWikimediaRestAPIPathComponents = "/api/rest_v1/"
    
    // https://www.mediawiki.org/wiki/API:REST_API
    private static let baseMediaWikiRestAPIPathComponents = "/w/rest.php/"
    
    /// Dev/test seam: when set (e.g. via the -WMFMediaWikiAPIBaseURLOverride launch argument),
    /// MediaWiki Action API requests are redirected to the given base URL so UI-test flows can
    /// serve canned responses locally. The analog of Android's `mediaWikiBaseUri` dev setting.
    private static let mediaWikiAPIBaseURLOverrideKey = "WMFMediaWikiAPIBaseURLOverride"

    static func mediaWikiAPIURL(project: WMFProject) -> URL? {
        
        guard let siteURL = project.siteURL,
        var components = URLComponents(url: siteURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        
        components.path = baseMediaWikiAPIPathComponents

        if let override = UserDefaults.standard.string(forKey: mediaWikiAPIBaseURLOverrideKey),
           let overrideComponents = URLComponents(string: override) {
            components.scheme = overrideComponents.scheme
            components.host = overrideComponents.host
            components.port = overrideComponents.port
        }

        return components.url
    }
    
    /// Dev/test seam: when set (e.g. via the -WMFWikimediaRestAPIBaseURLOverride launch
    /// argument), Wikimedia REST API requests are redirected to the given base URL so
    /// UI-test flows can serve canned responses locally. See .maestro/MOCKING.md.
    private static let wikimediaRestAPIBaseURLOverrideKey = "WMFWikimediaRestAPIBaseURLOverride"

    static func wikimediaRestAPIURL(project: WMFProject, additionalPathComponents: [String]) -> URL? {
        guard let siteURL = project.siteURL,
        var components = URLComponents(url: siteURL, resolvingAgainstBaseURL: false) else {
            return nil
        }

        components.path = baseWikimediaRestAPIPathComponents + additionalPathComponents.joined(separator: "/")

        if let override = UserDefaults.standard.string(forKey: wikimediaRestAPIBaseURLOverrideKey),
           let overrideComponents = URLComponents(string: override) {
            components.scheme = overrideComponents.scheme
            components.host = overrideComponents.host
            components.port = overrideComponents.port
        }

        return components.url
    }
    
    static func mediaWikiRestAPIURL(project: WMFProject, additionalPathComponents: [String]) -> URL? {
        guard let siteURL = project.siteURL,
        var components = URLComponents(url: siteURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        
        components.path = baseMediaWikiRestAPIPathComponents + additionalPathComponents.joined(separator: "/")
        
        return components.url
    }
    
    static func paymentMethodsAPIURL(environment: WMFServiceEnvironment = WMFDataEnvironment.current.serviceEnvironment) -> URL? {
        
        var components = URLComponents()
        components.scheme = "https"
        components.path = basePaymentWikiAPIPathComponents
        components.host = "payments.wikimedia.org"

        return components.url
    }
    
    static func metricsAPIURL() -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.path = baseWikimediaRestAPIPathComponents + "metrics"
        components.host = "wikimedia.org"

        return components.url
    }
    
    static func donatePaymentSubmissionURL(environment: WMFServiceEnvironment = WMFDataEnvironment.current.serviceEnvironment) -> URL? {
        
        var components = URLComponents()
        components.scheme = "https"
        components.path = basePaymentWikiAPIPathComponents
        components.host = "payments.wikimedia.org"
        
        return components.url
    }
    
    static func donateConfigURL(environment: WMFServiceEnvironment = WMFDataEnvironment.current.serviceEnvironment) -> URL? {
        
        var components = URLComponents()
        components.scheme = "https"
        components.path = "/wiki/MediaWiki:AppsDonationConfig.json"
        
        switch environment {
        case .production:
            components.host = "donate.wikimedia.org"
        case .staging:
            components.host = "test.wikipedia.org"
        }
        return components.url
    }
    
    static func fundraisingCampaignConfigURL(environment: WMFServiceEnvironment = WMFDataEnvironment.current.serviceEnvironment) -> URL? {
        
        var components = URLComponents()
        components.scheme = "https"
        components.path = "/wiki/MediaWiki:AppsCampaignConfig.json"
        
        switch environment {
        case .production:
            components.host = "donate.wikimedia.org"
        case .staging:
            components.host = "test.wikipedia.org"
        }
        return components.url
    }
    
    static func featureConfigURL(environment: WMFServiceEnvironment = WMFDataEnvironment.current.serviceEnvironment, project: WMFProject) -> URL? {
        
        switch environment {
        case .production:
            return wikimediaRestAPIURL(project: project, additionalPathComponents: ["feed","configuration"])
        case .staging:
            var components = URLComponents()
            components.scheme = "https"
            components.path = "/wiki/MediaWiki:AppsFeatureConfig.json"
            components.host = "test.wikipedia.org"
            components.queryItems = [URLQueryItem(name: "action", value: "raw")]
            return components.url
        }
    }
}
