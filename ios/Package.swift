// swift-tools-version:5.9
// JarvisKit: the app's talking-to-Jarvis code (events, wording, the HTTP
// client), kept out of the UI so `swift test` can check it on any Mac
// without a simulator. The app target (project.yml) links it.
import PackageDescription

let package = Package(
    name: "JarvisKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "JarvisKit", targets: ["JarvisKit"]),
    ],
    targets: [
        .target(name: "JarvisKit"),
        .testTarget(name: "JarvisKitTests", dependencies: ["JarvisKit"]),
    ]
)
