// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "TeeCircleKit",
    platforms: [
        .iOS("16.4"),
        .macOS(.v13),
    ],
    products: [
        .library(name: "TeeCircleDomain", targets: ["TeeCircleDomain"]),
        .library(name: "TeeCircleScoring", targets: ["TeeCircleScoring"]),
        .library(name: "TeeCircleAPI", targets: ["TeeCircleAPI"]),
        .library(name: "TeeCircleDesign", targets: ["TeeCircleDesign"]),
        .library(name: "TeeCircleActivities", targets: ["TeeCircleActivities"]),
    ],
    targets: [
        .target(name: "TeeCircleDomain"),
        .target(
            name: "TeeCircleScoring",
            dependencies: ["TeeCircleDomain"]
        ),
        .target(
            name: "TeeCircleAPI",
            dependencies: ["TeeCircleDomain"]
        ),
        .target(
            name: "TeeCircleDesign",
            dependencies: ["TeeCircleDomain"]
        ),
        .target(
            name: "TeeCircleActivities",
            dependencies: ["TeeCircleDomain"]
        ),
        .testTarget(
            name: "TeeCircleDomainTests",
            dependencies: ["TeeCircleDomain", "TeeCircleAPI"]
        ),
        .testTarget(
            name: "TeeCircleScoringTests",
            dependencies: ["TeeCircleDomain", "TeeCircleScoring"]
        ),
        .testTarget(
            name: "TeeCircleAPITests",
            dependencies: ["TeeCircleDomain", "TeeCircleAPI"]
        ),
        .testTarget(
            name: "TeeCircleDesignTests",
            dependencies: ["TeeCircleDomain", "TeeCircleDesign"]
        ),
        .testTarget(
            name: "TeeCircleActivitiesTests",
            dependencies: ["TeeCircleDomain", "TeeCircleActivities"]
        ),
    ]
)
