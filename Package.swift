// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "swift-k8s-service-discovery",
    products: [
        .library(
            name: "K8sServiceDiscovery",
            targets: ["K8sServiceDiscovery"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-service-discovery.git", from: "1.0.0"),
        .package(url: "https://github.com/swift-server/async-http-client.git", from: "1.2.0"),
        .package(url: "https://github.com/NozeIO/MicroExpress.git", from: "0.5.3"),
    ],
    targets: [
        .target(
            name: "K8sServiceDiscovery",
            dependencies: [
                .product(name: "ServiceDiscovery", package: "swift-service-discovery"),
                .product(name: "AsyncHTTPClient", package: "async-http-client"),
            ]),
        .testTarget(
            name: "K8sServiceDiscoveryTests",
            dependencies: [
                "K8sServiceDiscovery",
                .product(name: "MicroExpress", package: "MicroExpress"),
            ],
            resources: [
                .process("listresponse.json"),
                .process("integration.yml"),
            ]),
    ]
)
