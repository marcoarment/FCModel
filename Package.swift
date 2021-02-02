// swift-tools-version:5.3
import PackageDescription

let package = Package(
    name: "FCModel",
    platforms: [.macOS(.v10_10), .iOS(.v9)],
    products: [.library(name: "FCModel", targets: ["FCModel"])],
    dependencies: [
      .package(name: "FMDB", url: "https://github.com/ccgus/fmdb.git", from: "2.7.7"),
    ],
    targets: [
        .target(
            name: "FCModel",
            dependencies: ["FMDB"],
            path: "FCModel",
            exclude: ["FCModel+ObservableObject.swift"]
        )
    ]
)
