// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FilmChef",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "FilmChef", targets: ["FilmChef"])
    ],
    targets: [
        .executableTarget(
            name: "FilmChef",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
