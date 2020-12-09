import XCTest
@testable import K8sServiceDiscovery

final class K8sServiceDiscoveryTests: XCTestCase {
    func testExample() {
        let target = K8sObject(labelSelector: ["app":"nginx"], namespace: "default")
        let sd = K8sServiceDiscovery(apiHost: "http://localhost:8001")
//        sd.lookup(K8sObject(labelSelector: ["app":"nginx"], namespace: "default"), deadline: .now() + .milliseconds(2000)) { result in
//            switch result {
//            case .failure:
//                print("ERR")
//            case .success(let instances):
//                for instance in instances {
//                    print(instance)
//                }
//            }
//        }

        sd.subscribe(to: target) { result in
            switch result {
            case .success(let pods):
                print("\(pods)")
            case .failure:
                print("ERR")
            }
        } onComplete: { reason in
            print("bye")
        }

        Thread.sleep(forTimeInterval: 1000)
        sd.shutdown()
    }

    static var allTests = [
        ("testExample", testExample),
    ]
}
