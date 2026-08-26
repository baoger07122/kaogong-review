// swift-tools-version: 5.9

// This package is opened directly by Swift Playgrounds on iPad.

import PackageDescription
import AppleProductTypes

let package = Package(
    name: "考公原生预览",
    platforms: [
        .iOS("26.0")
    ],
    products: [
        .iOSApplication(
            name: "考公原生预览",
            targets: ["AppModule"],
            displayVersion: "8.26.4-preview.1",
            bundleVersion: "1",
            appIcon: .placeholder(icon: .box),
            accentColor: .presetColor(.blue),
            supportedDeviceFamilies: [
                .pad
            ],
            supportedInterfaceOrientations: [
                .landscapeRight,
                .landscapeLeft
            ]
        )
    ],
    targets: [
        .executableTarget(
            name: "AppModule",
            path: ".",
            swiftSettings: [
                .enableUpcomingFeature("BareSlashRegexLiterals")
            ]
        )
    ]
)
