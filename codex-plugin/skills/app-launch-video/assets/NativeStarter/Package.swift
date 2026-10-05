// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "NativeLaunchFilm",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "launch-film", targets: ["LaunchFilm"])],
    dependencies: [
        // Upstream's CLI reports 0.8.1, but that release has no Git tag.
        // Keep the engine reproducible by pinning the verified commit.
        .package(url: "https://github.com/Anoop-design/swift-render", revision: "a63f3d5f846d17b127faff803a7b9d5c368c16d0")
    ],
    targets: [
        .executableTarget(name: "LaunchFilm", dependencies: [
            .product(name: "SwiftRender", package: "swift-render")
        ])
    ]
)
