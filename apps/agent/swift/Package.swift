// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CicadaSwift",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "CicadaCore", targets: ["CicadaCore"]),
        .library(name: "CicadaIPC", targets: ["CicadaIPC"]),
        .library(name: "CicadaSystem", targets: ["CicadaSystem"]),
        .library(name: "CicadaRelayClient", targets: ["CicadaRelayClient"]),
        .executable(name: "cicada", targets: ["CicadaCLIApp"]),
        .executable(name: "cicada-agent", targets: ["CicadaDaemonApp"]),
    ],
    targets: [
        .target(name: "CicadaCore"),
        .target(name: "CicadaIPC", dependencies: ["CicadaCore"]),
        .target(name: "CicadaSystem", dependencies: ["CicadaCore"]),
        .target(name: "CicadaRelayClient", dependencies: ["CicadaCore", "CicadaIPC", "CicadaSystem"]),
        .executableTarget(name: "CicadaCLIApp", dependencies: ["CicadaCore", "CicadaIPC", "CicadaSystem"]),
        .executableTarget(name: "CicadaDaemonApp", dependencies: ["CicadaCore", "CicadaIPC", "CicadaSystem", "CicadaRelayClient"]),
        .testTarget(name: "CicadaCoreTests", dependencies: ["CicadaCore"]),
        .testTarget(name: "CicadaRelayClientTests", dependencies: ["CicadaRelayClient", "CicadaCore"]),
    ]
)
