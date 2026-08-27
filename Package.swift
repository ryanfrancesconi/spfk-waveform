// swift-tools-version: 6.2
// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi

import PackageDescription

let package = Package(
    name: "spfk-waveform",
    defaultLocalization: "en",
    platforms: [.macOS(.v13), .iOS(.v16),],
    products: [
        .library(
            name: "SPFKWaveform",
            targets: ["SPFKWaveform"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/ryanfrancesconi/spfk-audio-base", from: "1.10.1"),
        .package(url: "https://github.com/ryanfrancesconi/spfk-base", from: "1.6.0"),
        .package(url: "https://github.com/ryanfrancesconi/spfk-testing", from: "1.1.0"),
        .package(url: "https://github.com/ryanfrancesconi/spfk-utils", from: "1.14.0"),
    ],
    targets: [
        .target(
            name: "SPFKWaveform",
            dependencies: [
                .product(name: "SPFKAudioBase", package: "spfk-audio-base"),
                .product(name: "SPFKBase", package: "spfk-base"),
                .product(name: "SPFKUtils", package: "spfk-utils"),
            ]
        ),
        .testTarget(
            name: "SPFKWaveformTests",
            dependencies: [
                .targetItem(name: "SPFKWaveform", condition: nil),
                .product(name: "SPFKAudioBase", package: "spfk-audio-base"),
                .product(name: "SPFKTesting", package: "spfk-testing"),
            ]
        ),
    ]
)
