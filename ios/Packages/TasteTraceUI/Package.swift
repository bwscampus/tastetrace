// swift-tools-version: 5.10
import PackageDescription

// Design system: tokens and reusable SwiftUI components matching the mockups.
let package = Package(
    name: "TasteTraceUI",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "TasteTraceUI", targets: ["TasteTraceUI"]),
    ],
    targets: [
        .target(name: "TasteTraceUI"),
        .testTarget(name: "TasteTraceUITests", dependencies: ["TasteTraceUI"]),
    ]
)
