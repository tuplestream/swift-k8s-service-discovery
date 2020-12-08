import AsyncHTTPClient
import Dispatch
import Foundation
import ServiceDiscovery

fileprivate extension Dictionary where Key == String, Value == String {

    var queryParameters: String {
        var parts: [String] = []
        for (key, value) in self {
            let part = String(format: "%@=%@",
                              String(describing: key).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!,
                              String(describing: value).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)
            parts.append(part as String)
        }
        return parts.joined(separator: "&")
    }

    var urlEncoded: String {
        if let encoded = queryParameters.addingPercentEncoding(withAllowedCharacters: .alphanumerics) {
            return encoded
        }
        return ""
    }
}

public struct K8sObject: Hashable {
    public var labels: [String:String] = Dictionary()
    public var namespace: String = "default"

    var url: String {
        return "/api/v1/namespaces/\(namespace)/pods?labelSelector=\(labels.urlEncoded)"
    }
}

public struct K8sPod: CustomStringConvertible, Hashable {

    public var name: String
    public var address: String

    public var description: String {
        get {
            return "\(name) | \(address)"
        }
    }
}

struct PodMeta: Decodable {
    var name: String
}

struct PodStatus: Decodable {
    var podIP: String
}

struct InternalPod: Decodable {
    var metadata: PodMeta
    var status: PodStatus
}

struct PodList: Decodable {
    var items: [InternalPod]

    var publicItems: [K8sPod] {
        return items.map { pod in
            K8sPod(name: pod.metadata.name, address: pod.status.podIP)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case items
    }
}

public final class K8sServiceDiscovery: ServiceDiscovery {
    public typealias Service = K8sObject
    public typealias Instance = K8sPod

    public let defaultLookupTimeout: DispatchTimeInterval = .seconds(1)

    private let httpClient = HTTPClient(eventLoopGroupProvider: .createNew)
    private let jsonDecoder = JSONDecoder()
    private let apiHost: String

    public init(apiHost: String) {
        self.apiHost = apiHost
    }

    public func lookup(_ service: K8sObject, deadline: DispatchTime?, callback: @escaping (Result<[K8sPod], Error>) -> Void) {
        httpClient.get(url: apiHost + service.url).whenComplete { result in
            let lookupResult: Result<[Instance], Error>!
            switch result {
            case .failure:
                lookupResult = .failure(LookupError.timedOut)
            case .success(let response):
                if let bytes = response.body {
                    let decoded = try! self.jsonDecoder.decode(PodList.self, from: bytes)
                    lookupResult = .success(decoded.publicItems)
                } else {
                    lookupResult = .success([])
                }
            }
            callback(lookupResult)
        }
    }

    public func subscribe(to service: K8sObject, onNext nextResultHandler: @escaping (Result<[K8sPod], Error>) -> Void, onComplete completionHandler: @escaping (CompletionReason) -> Void) -> CancellationToken {
        // TODO
        return CancellationToken()
    }

    public func shutdown() {
        try! httpClient.syncShutdown()
    }
}
