// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Alarm",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Alarm", targets: ["Alarm"])
    ],
    targets: [
        .executableTarget(
            name: "Alarm",
            path: "Sources/Alarm"
        ),
        .testTarget(
            name: "AlarmTests",
            dependencies: ["Alarm"],
            path: "Tests/AlarmTests"
        ),
    ]
)

