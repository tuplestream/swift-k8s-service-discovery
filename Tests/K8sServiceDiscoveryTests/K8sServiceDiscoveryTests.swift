import XCTest
@testable import K8sServiceDiscovery

final class K8sServiceDiscoveryTests: XCTestCase {
    func testExample() {
        let sd = K8sServiceDiscovery(apiHost: "http://127.0.0.1:8001")
        sd.lookup(K8sObject(labels: ["app":"nginx"], namespace: "default"), deadline: .none) { result in
            
        }
        sleep(1)
        sd.shutdown()
    }

    static var allTests = [
        ("testExample", testExample),
    ]
}
