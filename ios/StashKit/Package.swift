// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "StashKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "StashKit", targets: ["StashKit"])],
    dependencies: [
        .package(url: "https://github.com/supabase/supabase-swift.git", from: "2.0.0"),
    ],
    targets: [
        .target(name: "StashKit", dependencies: [.product(name: "Supabase", package: "supabase-swift")]),
        .testTarget(name: "StashKitTests", dependencies: ["StashKit"]),
    ]
)
