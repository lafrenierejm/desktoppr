// swift-tools-version:6.0
import PackageDescription

let package = Package(
  name: "desktoppr",
  // swift-argument-parser links Swift Concurrency, which ships with macOS 12.
  platforms: [.macOS(.v12)],
  dependencies: [
    .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.8.2")
  ],
  targets: [
    .executableTarget(
      name: "desktoppr",
      dependencies: [
        .product(name: "ArgumentParser", package: "swift-argument-parser")
      ],
      path: "desktoppr",
      // Info.plist is embedded via the linker below, not treated as a resource.
      exclude: ["Info.plist", "ToDo.markdown"],
      linkerSettings: [
        // Equivalent of Xcode's CREATE_INFOPLIST_SECTION_IN_BINARY. This gives the
        // tool its bundle identifier, which UserDefaults uses as the preferences domain.
        .unsafeFlags([
          "-Xlinker", "-sectcreate",
          "-Xlinker", "__TEXT",
          "-Xlinker", "__info_plist",
          "-Xlinker", "\(Context.packageDirectory)/desktoppr/Info.plist",
        ])
      ]
    )
  ],
  // The sources predate Swift 6 strict concurrency.
  swiftLanguageModes: [.v5]
)
