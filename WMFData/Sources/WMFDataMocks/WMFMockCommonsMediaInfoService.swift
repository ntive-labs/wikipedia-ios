import Foundation
import WMFData

#if DEBUG

fileprivate extension WMFData.WMFServiceRequest {

    var action: String? { parameters?["action"] as? String }

    var isImageInfoGet: Bool {
        action == "query" && (parameters?["prop"] as? String) == "imageinfo|entityterms"
    }

    var isProtectionGet: Bool {
        action == "query" && (parameters?["meta"] as? String) == "userinfo" && (parameters?["inprop"] as? String) == "protection"
    }

    var isClaimsGet: Bool {
        action == "wbgetclaims" && (parameters?["property"] as? String) == "P180"
    }

    var isEntityTermsGet: Bool {
        action == "query" && (parameters?["prop"] as? String) == "entityterms"
    }

    var isSearchEntitiesGet: Bool {
        action == "wbsearchentities"
    }

    var isCaptionsGet: Bool {
        action == "wbgetentities"
    }

    var isSetLabelPost: Bool {
        action == "wbsetlabel"
    }

    var isEditEntityPost: Bool {
        action == "wbeditentity"
    }
}

/// Mock MediaWiki service that returns fixture JSON for the Commons MediaInfo read/write endpoints.
/// Mirrors `WMFMockGrowthTasksService`.
public final class WMFMockCommonsMediaInfoService: WMFService {

    public init() {}

    private func resourceName(for request: WMFData.WMFServiceRequest) -> String? {
        if request.isImageInfoGet { return "commons-imageinfo-get" }
        if request.isProtectionGet { return "commons-protection-get" }
        if request.isClaimsGet { return "commons-claims-p180-get" }
        if request.isEntityTermsGet { return "wikidata-entityterms-get" }
        if request.isSearchEntitiesGet { return "wikidata-wbsearchentities-get" }
        if request.isSetLabelPost { return "commons-wbsetlabel-post" }
        if request.isEditEntityPost { return "commons-wbeditentity-post" }
        return nil
    }

    private func jsonData(for request: WMFData.WMFServiceRequest) -> Data? {
        guard let resourceName = resourceName(for: request),
              let url = Bundle.module.url(forResource: resourceName, withExtension: "json"),
              let jsonData = try? Data(contentsOf: url) else {
            return nil
        }
        return jsonData
    }

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
        guard let response = try? JSONDecoder().decode(T.self, from: jsonData) else {
            completion(.failure(WMFMockError.unableToDeserialize))
            return
        }
        completion(.success(response))
    }

    public func performDecodablePOST<R: WMFServiceRequest, T: Decodable>(request: R, completion: @escaping (Result<T, Error>) -> Void) {
        guard let jsonData = jsonData(for: request) else {
            completion(.failure(WMFMockError.unableToPullData))
            return
        }
        guard let response = try? JSONDecoder().decode(T.self, from: jsonData) else {
            completion(.failure(WMFMockError.unableToDeserialize))
            return
        }
        completion(.success(response))
    }

    public func clearCachedData() {
        // no-op
    }
}

#endif
