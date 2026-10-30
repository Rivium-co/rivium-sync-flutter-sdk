// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "rivium_sync",
    platforms: [.iOS("13.0")],
    products: [
        .library(name: "rivium-sync", targets: ["rivium_sync"])
    ],
    dependencies: [
        .package(url: "https://github.com/Rivium-co/rivium-sync-ios-sdk.git", from: "0.3.0")
    ],
    targets: [
        .target(
            name: "rivium_sync",
            dependencies: [.product(name: "RiviumSync", package: "rivium-sync-ios-sdk")]
        )
    ]
)
