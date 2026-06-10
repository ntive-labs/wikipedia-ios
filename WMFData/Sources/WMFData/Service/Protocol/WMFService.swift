import Foundation

public protocol WMFService {
    func perform<R: WMFServiceRequest>(request: R, completion: @escaping (Result<Data, Error>) -> Void)
    func perform<R: WMFServiceRequest>(request: R, completion: @escaping (Result<[String: Any]?, Error>) -> Void)
    func performDecodableGET<R: WMFServiceRequest, T: Decodable>(request: R, completion: @escaping (Result<T, Error>) -> Void)
    /// Like `performDecodableGET`, but also surfaces the `HTTPURLResponse` so callers can read
    /// response headers (e.g. the `x-search-id` header on semantic search responses). A default
    /// implementation exists so conformers without header access (mocks) need not implement it.
    func performDecodableGET<R: WMFServiceRequest, T: Decodable>(request: R, completion: @escaping (Result<(T, HTTPURLResponse?), Error>) -> Void)
    func performDecodablePOST<R: WMFServiceRequest, T: Decodable>(request: R, completion: @escaping (Result<T, Error>) -> Void)
    func clearCachedData()
}

public extension WMFService {
    func performDecodableGET<R: WMFServiceRequest, T: Decodable>(request: R, completion: @escaping (Result<(T, HTTPURLResponse?), Error>) -> Void) {
        performDecodableGET(request: request) { (result: Result<T, Error>) in
            completion(result.map { ($0, nil) })
        }
    }
}
