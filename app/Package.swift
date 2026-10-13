// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Cheesecloth",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Cheesecloth", targets: ["Cheesecloth"]),
    ],
    targets: [
        // The local API client and the app's state, without UI, so tests
        // can use them.
        .target(name: "CheeseclothKit"),
        .executableTarget(
            name: "Cheesecloth", dependencies: ["CheeseclothKit"],
            // The menu-bar icon, from mockups/menubar_template.svg.
            resources: [.copy("Resources/menubar_template.svg")]),
        .testTarget(name: "CheeseclothKitTests", dependencies: ["CheeseclothKit"]),
    ]
)
