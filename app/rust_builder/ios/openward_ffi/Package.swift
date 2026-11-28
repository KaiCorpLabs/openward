// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "openward_ffi",
    platforms: [
        .iOS("15.0")
    ],
    products: [
        .library(name: "openward-ffi", targets: ["openward_ffi"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "openward_ffi",
            dependencies: [],
            cSettings: [
                .headerSearchPath("include")
            ]
        )
    ]
)
