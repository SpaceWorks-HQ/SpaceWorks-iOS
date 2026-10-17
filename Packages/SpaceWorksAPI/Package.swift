// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SpaceWorksAPI",
    defaultLocalization: "en",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "SpaceWorksAPI", type: .dynamic, targets: ["SpaceWorksAPI"])],
    dependencies: [
        .package(url: "https://github.com/apple/swift-openapi-generator", exact: "1.10.0"),
        .package(url: "https://github.com/apple/swift-openapi-runtime", exact: "1.8.2"),
        .package(url: "https://github.com/apple/swift-openapi-urlsession", exact: "1.1.0"),
        .package(url: "https://github.com/apple/swift-http-types", exact: "1.3.1")
    ],
    targets: [.target(
        name: "SpaceWorksAPI",
        dependencies: [
            .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
            .product(name: "OpenAPIURLSession", package: "swift-openapi-urlsession"),
            .product(name: "HTTPTypes", package: "swift-http-types")
        ],
        resources: [.process("Resources")],
        plugins: [.plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator")]
    )]
)
