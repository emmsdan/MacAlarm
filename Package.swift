// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacAlarm",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MacAlarm", targets: ["Alarm"])
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

