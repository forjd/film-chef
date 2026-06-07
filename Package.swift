// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FilmChef",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "FilmChef", targets: ["FilmChef"]),
        .executable(name: "FilmChefCoreTests", targets: ["FilmChefCoreTests"])
    ],
    targets: [
        .target(
            name: "FilmChefCore",
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "FilmChef",
            dependencies: ["FilmChefCore"]
        ),
        .executableTarget(
            name: "FilmChefCoreTests",
            dependencies: ["FilmChefCore"],
            path: "Tests/FilmChefCoreTests"
        )
    ]
)
