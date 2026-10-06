// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SwiftRender",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SwiftRender", targets: ["SwiftRender"]),
        .executable(name: "swift-render", targets: ["SwiftRenderCLI"]),
        .executable(name: "swift-render-studio", targets: ["SwiftRenderStudio"]),
    ],
    targets: [
        .target(name: "StudioCore"),
        .executableTarget(name: "SwiftRenderStudio", dependencies: ["StudioCore"]),
        .testTarget(name: "StudioCoreTests", dependencies: ["StudioCore"]),
        .target(
            name: "SwiftRender",
            dependencies: [],
            exclude: ["Shaders"],
            resources: [
                .process("Resources"),
            ],
            plugins: ["MetalCompilerPlugin"]
        ),
        .executableTarget(
            name: "SwiftRenderCLI",
            dependencies: ["SwiftRender"],
            plugins: ["SceneRegistryPlugin"]
        ),
        .plugin(
            name: "MetalCompilerPlugin",
            capability: .buildTool()
        ),
        .plugin(
            name: "SceneRegistryPlugin",
            capability: .buildTool()
        ),
        .testTarget(
            name: "SwiftRenderTests",
            dependencies: ["SwiftRender"]
        ),
    ]
)
