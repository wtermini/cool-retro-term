// swift-tools-version:5.9
//
// Native macOS front end for cool-retro-term.
// Build the app bundle with ./build-app.sh (see README.md).

import PackageDescription

let package = Package(
    name: "CoolRetroTerm",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", exact: "1.20.0"),
    ],
    targets: [
        .executableTarget(
            name: "CoolRetroTerm",
            dependencies: [
                .product(name: "SwiftTerm", package: "SwiftTerm"),
            ],
            path: "Sources/CoolRetroTerm"
        ),
    ]
)
