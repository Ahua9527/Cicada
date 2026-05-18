// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "notification-agent",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "cicada-notifier", targets: ["NotificationAgent"])
    ],
    dependencies: [
        .package(url: "https://github.com/Lakr233/NotchNotification.git", from: "1.1.0")
    ],
    targets: [
        .executableTarget(
            name: "NotificationAgent",
            dependencies: [
                .product(name: "NotchNotification", package: "NotchNotification")
            ],
            path: "Sources/NotificationAgent"
        )
    ]
)
