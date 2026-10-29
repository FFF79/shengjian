// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ShengJian",
    platforms: [.macOS("26.0")],
    products: [.library(name: "ShengJianCore", targets: ["ShengJianCore"]), .executable(name: "ShengJian", targets: ["ShengJian"])],
    targets: [
        .target(name: "ShengJianCore", path: "Sources/ShengJianCore"),
        .executableTarget(name: "ShengJian", dependencies: ["ShengJianCore"], path: "Sources/ShengJian",
                          linkerSettings: [.linkedFramework("AVFoundation"), .linkedFramework("Security")]),
        .testTarget(name: "ShengJianCoreTests", dependencies: ["ShengJianCore"], path: "Tests/ShengJianCoreTests")
    ]
)
