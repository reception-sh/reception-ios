// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Reception",
    defaultLocalization: "en",
    platforms: [.iOS(.v17)],
    products: [.library(name: "Reception", targets: ["Reception"])],
    targets: [.target(name: "Reception", resources: [.process("Resources")],
                      swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]),
              .testTarget(name: "ReceptionTests", dependencies: ["Reception"])],
    swiftLanguageModes: [.v5]
)
