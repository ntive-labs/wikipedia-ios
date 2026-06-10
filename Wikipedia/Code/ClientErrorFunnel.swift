import Foundation
import WMF
import WMFData

@objc(WMFClientErrorFunnel) public final class ClientErrorFunnel: NSObject {

    @objc public static let shared = ClientErrorFunnel()

    private struct Event: EventInterface {
        static let schema: EventPlatformClient.Schema = .clientError
        let message: String?
        let errorClass: String?
        let errorContext: String?
        let stackTrace: String?
        let http: Http?
        let url: String?

        enum CodingKeys: String, CodingKey {
            case message = "message"
            case errorClass = "error_class"
            case errorContext = "error_context"
            case stackTrace = "stack_trace"
            case http = "http"
            case url = "url"
        }
    }

    private struct Http: Codable {
        let method: String?
        let `protocol`: String?
        let statusCode: Int?

        enum CodingKeys: String, CodingKey {
            case method = "method"
            case `protocol` = "protocol"
            case statusCode = "status_code"
        }
    }

    func logEvent(message: String?) {
        let event: ClientErrorFunnel.Event = ClientErrorFunnel.Event(message: message, errorClass: nil, errorContext: nil, stackTrace: nil, http: nil, url: nil)
        EventPlatformClient.shared.submit(stream: .clientError, event: event, needsMinimal: true)
    }

    /// Logs a caught error to the mediawiki.client.error logging-intake stream
    /// (parity with Android `ClientErrorEvent.logError(throwable)`).
    ///
    /// Note: Swift `Error`s do not carry a throw-site stack trace, so the first
    /// two frames of the *reporting* call stack are sent instead.
    public func logError(_ error: Error) {
        let stackTrace = Thread.callStackSymbols.dropFirst().prefix(2).joined(separator: ",")
        let event = Event(
            message: (error as NSError).localizedDescription,
            errorClass: String(describing: type(of: error)),
            errorContext: nil,
            stackTrace: stackTrace,
            http: nil,
            url: nil)
        EventPlatformClient.shared.submit(stream: .clientError, event: event, needsMinimal: true)
    }

    /// Logs an unsuccessful (>= 400) HTTP response to the mediawiki.client.error
    /// logging-intake stream (parity with Android `ClientErrorEvent.logHttpResponse(response)`).
    ///
    /// Note: unlike OkHttp, URLSession does not surface the negotiated HTTP
    /// protocol or the raw reason phrase at this layer, so `http.protocol` is
    /// omitted and `message` uses the localized status-code description.
    public func logHttpResponse(url: URL?, method: String?, statusCode: Int) {
        // Log this error, but only if it's not a request for a 320px thumbnail, which is a known
        // rate-limiting issue in old saved articles that were saved prior to Commons switching to
        // 330px thumbnails.
        if url?.absoluteString.contains("/320px-") == true {
            return
        }

        let message = HTTPURLResponse.localizedString(forStatusCode: statusCode)
        let event = Event(
            message: message.isEmpty ? String(describing: Self.self) : message,
            errorClass: String(describing: Self.self),
            errorContext: nil,
            stackTrace: nil,
            http: Http(method: method, protocol: nil, statusCode: statusCode),
            url: url?.absoluteString)
        EventPlatformClient.shared.submit(stream: .clientError, event: event, needsMinimal: true)
    }
}
