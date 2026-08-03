// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CicadaSwift",
    defaultLocalization: "zh-Hans",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CicadaCore", targets: ["CicadaCore"]),
        .library(name: "CicadaIPC", targets: ["CicadaIPC"]),
        .library(name: "CicadaSystem", targets: ["CicadaSystem"]),
        .library(name: "CicadaSleepHoldCore", targets: ["CicadaSleepHoldCore"]),
        .library(name: "CicadaRelayClient", targets: ["CicadaRelayClient"]),
        .library(name: "CicadaCLI", targets: ["CicadaCLI"]),
        .library(name: "CicadaUI", targets: ["CicadaUI"]),
        .executable(name: "cicada", targets: ["CicadaCLIApp"]),
        .executable(name: "cicada-agent", targets: ["CicadaDaemonApp"]),
        .executable(name: "cicada-sleephold", targets: ["CicadaSleepHoldServiceApp"]),
    ],
    targets: [
        .target(name: "CicadaCore"),
        .target(name: "CicadaIPC", dependencies: ["CicadaCore"]),
        .target(
            name: "CicadaBluetoothBridge",
            publicHeadersPath: "include",
            linkerSettings: [.linkedFramework("IOBluetooth")]
        ),
        .target(
            name: "CicadaSleepHoldCore",
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        .target(
            name: "CicadaSystem",
            dependencies: ["CicadaCore", "CicadaIPC", "CicadaBluetoothBridge", "CicadaSleepHoldCore"]
        ),
        .target(name: "CicadaRelayClient", dependencies: ["CicadaCore", "CicadaIPC", "CicadaSystem"]),
        .target(
            name: "CicadaUI",
            dependencies: ["CicadaCore", "CicadaIPC", "CicadaSleepHoldCore", "CicadaSystem"],
            resources: [.process("Resources")]
        ),
        .target(
            name: "CicadaCLI",
            dependencies: ["CicadaCore", "CicadaIPC", "CicadaSystem", "CicadaRelayClient", "CicadaSleepHoldCore"]
        ),
        .executableTarget(name: "CicadaSleepHoldServiceApp", dependencies: ["CicadaSleepHoldCore"]),
        .executableTarget(
            name: "CicadaCLIApp",
            dependencies: ["CicadaCLI"],
            exclude: ["Info.plist"],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/CicadaCLIApp/Info.plist",
                ]),
            ]
        ),
        .executableTarget(
            name: "CicadaDaemonApp",
            dependencies: ["CicadaCore", "CicadaIPC", "CicadaSystem", "CicadaRelayClient"],
            exclude: ["Info.plist"],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/CicadaDaemonApp/Info.plist",
                ]),
            ]
        ),
        .testTarget(name: "CicadaCoreTests", dependencies: ["CicadaCore"]),
        .testTarget(name: "CicadaIPCTests", dependencies: ["CicadaIPC", "CicadaCore"]),
        .testTarget(name: "CicadaSystemTests", dependencies: ["CicadaSystem", "CicadaCore"]),
        .testTarget(name: "CicadaSleepHoldCoreTests", dependencies: ["CicadaSleepHoldCore"]),
        .testTarget(
            name: "CicadaCLITests",
            dependencies: ["CicadaCLI", "CicadaCore", "CicadaIPC", "CicadaSystem", "CicadaSleepHoldCore"]
        ),
        .testTarget(name: "CicadaRelayClientTests", dependencies: ["CicadaRelayClient", "CicadaCore"]),
        .testTarget(
            name: "CicadaUITests",
            dependencies: ["CicadaUI", "CicadaCore", "CicadaIPC", "CicadaSleepHoldCore"]
        ),
    ]
)
