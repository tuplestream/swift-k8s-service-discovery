/*
 Copyright 2020 TupleStream OÜ
 See the LICENSE file for license information
 SPDX-License-Identifier: Apache-2.0
*/
import AsyncHTTPClient
import Dispatch
import Foundation
import Logging
import NIO
import NIOHTTP1
import ServiceDiscovery

fileprivate extension Dictionary where Key == String, Value == String {

    var queryParameters: String {
        var parts: [String] = []
        for (key, value) in self {
            let encodedKey = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
            let encodedVal = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
            let part = "\(encodedKey!)=\(encodedVal!)"
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
    public var labelSelector: [String:String] = Dictionary()
    public var namespace: String

    public init(labelSelector: [String:String], namespace: String = "default") {
        self.labelSelector = labelSelector
        self.namespace = namespace
    }

    var url: String {
        return "/api/v1/namespaces/\(namespace)/pods?labelSelector=\(labelSelector.urlEncoded)"
    }
}

public struct K8sPod: CustomStringConvertible, Hashable {

    public var name: String
    public var address: String

    public init(name: String, address: String) {
        self.name = name
        self.address = address
    }

    public var description: String {
        get {
            return "Pod[\(name) | \(address)]"
        }
    }
}

struct PodMeta: Decodable, Hashable {
    var name: String
}

struct PodStatus: Decodable, Hashable {
    var podIP: String?
}

struct InternalPod: Decodable, Hashable {
    var metadata: PodMeta
    var status: PodStatus

    var publicPod: K8sPod? {
        get {
            if let ip = status.podIP {
                return K8sPod(name: metadata.name, address: ip)
            } else {
                return nil
            }
        }
    }

    static func == (lhs: InternalPod, rhs: InternalPod) -> Bool {
        return lhs.metadata == rhs.metadata
    }

    private enum CodingKeys: String, CodingKey {
        case metadata, status
    }
}

struct PodList: Decodable {
    var items: [InternalPod]

    var publicItems: [K8sPod] {
        var converted = Array<K8sPod>()
        for item in items {
            if let p = item.publicPod {
                converted.append(p)
            }
        }
        return converted
    }

    private enum CodingKeys: String, CodingKey {
        case items
    }
}

enum UpdateOperation: String, Decodable {
    case added = "ADDED"
    case modified = "MODIFIED"
    case deleted = "DELETED"
}

struct PodUpdateOperation: Decodable {
    var type: UpdateOperation
    var object: InternalPod
}

fileprivate extension DispatchTime {

    var asNIODeadline: NIODeadline {
        get {
            .uptimeNanoseconds(self.uptimeNanoseconds)
        }
    }
}

public final class K8s {
    public static var defaultServiceEndpoint: String? {
        get {
            guard let host = getEnv("KUBERNETES_SERVICE_HOST"), let port = getEnv("KUBERNETES_SERVICE_PORT") else {
                return nil
            }

            var scheme = "http"
            if port == "443" {
                scheme = "https"
            }
            return "\(scheme)://\(host):\(port)"
        }
    }

    static var bearerToken: String? {
        get {
            let path = "/var/run/secrets/kubernetes.io/serviceaccount/token"
            if !FileManager().fileExists(atPath: path) {
                return nil
            }
            return try! String(contentsOfFile: path)
        }
    }

    static var runningInPod: Bool {
        get {
            return ProcessInfo.processInfo.environment["KUBERNETES_SERVICE_HOST"] != nil
        }
    }

    private static func getEnv(_ key: String) -> String? {
        return ProcessInfo.processInfo.environment[key]
    }
}

public struct K8sDiscoveryConfig {
    let eventLoopGroup: EventLoopGroup
    let apiUrl: String

    public init(eventLoopGroup: EventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1), apiUrl: String? = nil) {
        self.eventLoopGroup = eventLoopGroup
        self.apiUrl = apiUrl ?? K8s.defaultServiceEndpoint!
    }
}

public final class K8sServiceDiscovery: ServiceDiscovery {
    public typealias Service = K8sObject
    public typealias Instance = K8sPod

    public let defaultLookupTimeout: DispatchTimeInterval = .seconds(1)

    private let httpClient: HTTPClient
    private let jsonDecoder = JSONDecoder()
    private let apiHost: String

    public convenience init() {
        self.init(config: K8sDiscoveryConfig())
    }

    public init(config: K8sDiscoveryConfig) {
        self.apiHost = config.apiUrl
        let httpConfig = HTTPClient.Configuration(certificateVerification: .none)
        self.httpClient = HTTPClient(eventLoopGroupProvider: .shared(config.eventLoopGroup), configuration: httpConfig)
    }

    public func lookup(_ service: K8sObject, deadline: DispatchTime?, callback: @escaping (Result<[K8sPod], Error>) -> Void) {
        httpClient.get(url: fullURL(service), deadline: deadline?.asNIODeadline).whenComplete { result in
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

    private func fullURL(_ target: K8sObject, watch: Bool = false) -> String {
        if watch {
            return apiHost + target.url + "&watch=true"
        }
        return apiHost + target.url
    }

    public func subscribe(to service: K8sObject, onNext nextResultHandler: @escaping (Result<[K8sPod], Error>) -> Void, onComplete completionHandler: @escaping (CompletionReason) -> Void) -> CancellationToken {

        let request: HTTPClient.Request
        if K8s.runningInPod {
            let headers: HTTPHeaders
            if let token = K8s.bearerToken {
                headers = HTTPHeaders([("Authorization", "Bearer \(token)")])
            } else {
                headers = HTTPHeaders()
            }
            request = try! HTTPClient.Request(url: self.fullURL(service, watch: true), method: .GET, headers: headers, body: nil)
        } else {
            request = try! HTTPClient.Request(url: self.fullURL(service, watch: true))
        }
        let delegate = K8sStreamDelegate(decoder: self.jsonDecoder, onNext: nextResultHandler, onComplete: completionHandler)
        let future = self.httpClient.execute(request: request, delegate: delegate)

        return CancellationToken(isCancelled: false) { _ in
            future.cancel()
        }
    }

    public func shutdown() {
        try! httpClient.syncShutdown()
    }

    class K8sStreamDelegate: HTTPClientResponseDelegate {
        typealias Response = String

        private let log = Logger(label: "K8sStreamDelegate")
        private let decoder: JSONDecoder
        private let nextResultHandler: (Result<[K8sPod], Error>) -> Void
        private let completionHandler: (CompletionReason) -> Void
        private var interimBuffer: ByteBuffer
        private var alreadySeen: Set<K8sPod> = Set()

        init(decoder: JSONDecoder, onNext nextResultHandler: @escaping (Result<[K8sPod], Error>) -> Void, onComplete completionHandler: @escaping (CompletionReason) -> Void) {
            self.decoder = decoder
            self.interimBuffer = ByteBuffer()
            self.nextResultHandler = nextResultHandler
            self.completionHandler = completionHandler
        }

        func didReceiveHead(task: HTTPClient.Task<String>, _ head: HTTPResponseHead) -> EventLoopFuture<Void> {
            if head.status.code > 399 {
                completionHandler(.serviceDiscoveryUnavailable)
                log.error("Error received from K8s API server: \(head.status.reasonPhrase)")
                return task.eventLoop.makeFailedFuture(ServiceDiscoveryError.unavailable)
            }
            return task.eventLoop.makeSucceededFuture(())
        }

        func didReceiveBodyPart(task: HTTPClient.Task<String>, _ buffer: ByteBuffer) -> EventLoopFuture<Void> {
            // update json objects are newline-delimited, but the contents of a buffer may contain more or less than
            // one exact message; copy to an interim buffer and read up to any occurrences of \n and only decode that,
            // saving any remaining bytes for the next time this is called
            var b = buffer
            interimBuffer.writeBuffer(&b)
            let readable = interimBuffer.withUnsafeReadableBytes { $0.firstIndex(of: UInt8(0x0A)) }
            if let r = readable {
                if let decoded = try! interimBuffer.readJSONDecodable(PodUpdateOperation.self, decoder: decoder, length: r + 1) {
                    switch decoded.type {
                    case .deleted:
                        if let publicPod = decoded.object.publicPod {
                            alreadySeen.remove(publicPod)
                        }
                    case .added:
                        notifyIfNew(decoded.object)
                    case .modified:
                        notifyIfNew(decoded.object)
                    }
                }
            }

            return task.eventLoop.makeSucceededFuture(())
        }

        private func notifyIfNew(_ internalPod: InternalPod) {
            if let publicPod = internalPod.publicPod {
                if !alreadySeen.contains(publicPod) {
                    nextResultHandler(.success([publicPod]))
                    alreadySeen.insert(publicPod)
                }
            }
        }

        func didReceiveError(task: HTTPClient.Task<String>, _ error: Error) {
            log.error("request error from Kubernetes API server: \(error.localizedDescription)")
            completionHandler(.serviceDiscoveryUnavailable)
        }

        func didFinishRequest(task: HTTPClient.Task<String>) throws -> String {
            completionHandler(.serviceDiscoveryUnavailable)
            return ""
        }
    }
}
