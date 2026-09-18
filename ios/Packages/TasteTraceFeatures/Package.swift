// swift-tools-version: 5.10
import PackageDescription

// All screens and view models. Kept UIKit-free so the package compiles on
// macOS with the command-line toolchain; the app target is a thin shell.
let package = Package(
    name: "TasteTraceFeatures",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "TasteTraceFeatures", targets: ["TasteTraceFeatures"]),
    ],
    dependencies: [
        .package(path: "../TasteTraceAPI"),
        .package(path: "../TasteTraceCore"),
        .package(path: "../TasteTraceUI"),
    ],
    targets: [
        .target(name: "TasteTraceFeatures", dependencies: ["TasteTraceAPI", "TasteTraceCore", "TasteTraceUI"]),
        .testTarget(name: "TasteTraceFeaturesTests", dependencies: ["TasteTraceFeatures"]),
    ]
)
