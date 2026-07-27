import Foundation
import WMFData

#if DEBUG

fileprivate extension WMFData.WMFServiceRequest {

    var isRecentEditsGetList: Bool {
        guard let action = parameters?["action"] as? String,
              let list = parameters?["list"] as? String else {
            return false
        }
        return method == .GET && action == "query" && list == "recentchanges"
    }

    var isRecentEditsGetUsers: Bool {
        guard let action = parameters?["action"] as? String,
              let list = parameters?["list"] as? String else {
            return false
        }
        return method == .GET && action == "query" && list == "users"
    }

    var isRecentEditsGetUserInfo: Bool {
        guard let action = parameters?["action"] as? String,
              let meta = parameters?["meta"] as? String else {
            return false
        }
        return method == .GET && action == "query" && meta == "userinfo" && parameters?["list"] == nil
    }
}

public final class WMFMockRecentEditsMediaWikiService: WMFService {

    /// When true (default) the eligibility endpoint returns a rollback-capable user;
    /// when false it returns a user with no patrol rights.
    public var returnEligibleUser: Bool = true

    public init() { }

    public func perform<R: WMFServiceRequest>(request: R, completion: @escaping (Result<Data, any Error>) -> Void) {
        guard let jsonData = jsonData(for: request) else {
            completion(.failure(WMFMockError.unableToPullData))
            return
        }
        completion(.success(jsonData))
    }

    public func perform<R: WMFServiceRequest>(request: R, completion: @escaping (Result<[String: Any]?, Error>) -> Void) {
        guard let jsonData = jsonData(for: request) else {
            completion(.failure(WMFMockError.unableToPullData))
            return
        }
        guard let jsonDict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            completion(.failure(WMFMockError.unableToDeserialize))
            return
        }
        completion(.success(jsonDict))
    }

    public func performDecodableGET<R: WMFServiceRequest, T: Decodable>(request: R, completion: @escaping (Result<T, Error>) -> Void) {
        guard let jsonData = jsonData(for: request) else {
            completion(.failure(WMFMockError.unableToPullData))
            return
        }
        let decoder = JSONDecoder()
        guard let response = try? decoder.decode(T.self, from: jsonData) else {
            completion(.failure(WMFMockError.unableToDeserialize))
            return
        }
        completion(.success(response))
    }

    public func performDecodablePOST<R, T>(request: R, completion: @escaping (Result<T, Error>) -> Void) where R: WMFData.WMFServiceRequest, T: Decodable {
    }

    private func jsonData(for request: WMFData.WMFServiceRequest) -> Data? {
        let resourceName: String
        if request.isRecentEditsGetList {
            resourceName = "recent-edits-get-list-en"
        } else if request.isRecentEditsGetUsers {
            resourceName = "recent-edits-get-users-en"
        } else if request.isRecentEditsGetUserInfo {
            resourceName = returnEligibleUser ? "recent-edits-get-userinfo-eligible" : "recent-edits-get-userinfo-ineligible"
        } else {
            return nil
        }

        guard let url = Bundle.module.url(forResource: resourceName, withExtension: "json"),
              let jsonData = try? Data(contentsOf: url) else {
            return nil
        }
        return jsonData
    }

    public func clearCachedData() {
        // no-op
    }
}

#endif
