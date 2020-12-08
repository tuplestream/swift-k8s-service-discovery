import XCTest

#if !canImport(ObjectiveC)
public func allTests() -> [XCTestCaseEntry] {
    return [
        testCase(K8sServiceDiscoveryTests.allTests),
    ]
}
#endif
