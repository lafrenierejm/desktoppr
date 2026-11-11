// swift-tools-version:5.6
import PackageDescription

let package = Package(
  name: "desktoppr",
  platforms: [.macOS(.v10_15)],
  targets: [
    .executableTarget(
      name: "desktoppr",
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
  ]
)
