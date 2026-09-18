// swift-tools-version: 5.10
import PackageDescription

// Session, persistence and domain logic shared by every feature.
let package = Package(
    name: "TasteTraceCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "TasteTraceCore", targets: ["TasteTraceCore"]),
    ],
    dependencies: [
        .package(path: "../TasteTraceAPI"),
    ],
    targets: [
        .target(name: "TasteTraceCore", dependencies: ["TasteTraceAPI"]),
        .testTarget(name: "TasteTraceCoreTests", dependencies: ["TasteTraceCore"]),
    ]
)
