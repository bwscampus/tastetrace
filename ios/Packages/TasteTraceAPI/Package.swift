// swift-tools-version: 5.10
import PackageDescription

// API client and Codable models mirroring app/server. macOS is listed so the
// package builds and tests with the command-line toolchain.
let package = Package(
    name: "TasteTraceAPI",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "TasteTraceAPI", targets: ["TasteTraceAPI"]),
        .executable(name: "apismoke", targets: ["APISmoke"]),
    ],
    targets: [
        .target(name: "TasteTraceAPI"),
        // Exercises the client against a running backend: `swift run apismoke http://localhost:5000`
        .executableTarget(name: "APISmoke", dependencies: ["TasteTraceAPI"]),
        .testTarget(
            name: "TasteTraceAPITests",
            dependencies: ["TasteTraceAPI"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
