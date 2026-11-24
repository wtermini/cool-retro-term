// swift-tools-version:5.9
//
// Part of cool-retro-term, licensed under the GNU General Public License
// version 3 or (at your option) any later version. See gpl-3.0.txt.
//
// Native macOS front end for cool-retro-term.
// Build the app bundle with ./build-app.sh (see README.md).

import PackageDescription

let package = Package(
    name: "CoolRetroTerm",
    platforms: [.macOS(.v13)],
    dependencies: [
        // SwiftTerm 1.20.0, pinned to its commit so a moved tag can't change
        // what gets built. Review the changes before updating.
        .package(url: "https://github.com/migueldeicaza/SwiftTerm",
                 revision: "5d14406844143538cd8f8851d2d8a67c1fe443e5"),
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
