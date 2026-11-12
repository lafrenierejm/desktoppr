import Foundation
import Testing

@testable import desktoppr

/// Builds wallpaper stores shaped like macOS's `Index.plist`.
private enum Fixture {
  static func configuration(_ urlString: String) -> Data {
    let configuration: [String: Any] = [
      "type": "imageFile",
      "url": ["relative": urlString],
    ]
    return try! PropertyListSerialization.data(
      fromPropertyList: configuration, format: .binary, options: 0)
  }

  /// Round-trips `plist` the way `WallpaperStore.load` reads the store.
  ///
  /// Every nested container ends up mutable, which Swift dictionary literals are not.
  static func mutable(_ plist: [String: Any]) -> NSMutableDictionary {
    let data = try! PropertyListSerialization.data(
      fromPropertyList: plist, format: .binary, options: 0)
    return try! PropertyListSerialization.propertyList(
      from: data, options: .mutableContainers, format: nil) as! NSMutableDictionary
  }

  static func desktop(_ urlString: String, lastSet: Date) -> NSMutableDictionary {
    mutable([
      "LastSet": lastSet,
      "LastUse": lastSet,
      "Content": [
        "Choices": [
          [
            "Provider": "com.apple.wallpaper.choice.image",
            "Files": [Any](),
            "Configuration": configuration(urlString),
          ]
        ],
        "Shuffle": "$null",
      ],
    ])
  }

  static func holder(_ urlString: String, lastSet: Date) -> NSMutableDictionary {
    mutable(["Type": "individual", "Desktop": desktop(urlString, lastSet: lastSet)])
  }

  static let old = Date(timeIntervalSince1970: 1_700_000_000)
  static let new = Date(timeIntervalSince1970: 1_800_000_000)

  /// A store with an old picture everywhere, and `SystemDefault` freshly set to `current`.
  static func store(current: String) -> NSMutableDictionary {
    mutable([
      "SystemDefault": holder(current, lastSet: new),
      "Displays": ["D1": holder("file:///old/display.png", lastSet: old)],
      "Spaces": [
        "S1": [
          "Default": holder("file:///old/space1.png", lastSet: old),
          "Displays": [
            "D1": holder("file:///old/space1-d1.png", lastSet: old),
            "D2": holder("file:///old/space1-d2.png", lastSet: old),
          ],
        ],
        "S2": [
          "Default": holder("file:///old/space2.png", lastSet: old),
          "Displays": ["D1": holder("file:///old/space2-d1.png", lastSet: old)],
        ],
      ],
      // Not a `Desktop`: macOS keeps idle (screen saver) settings here.
      "AllSpacesAndDisplays": ["Type": "idle", "Idle": ["LastSet": old]],
    ])
  }

  static func write(_ index: NSDictionary, to url: URL) throws {
    let data = try PropertyListSerialization.data(
      fromPropertyList: index, format: .binary, options: 0)
    try data.write(to: url)
  }
}

@Suite final class WallpaperStoreTests {
  private let directory: URL
  private var storeURL: URL { directory.appendingPathComponent("Index.plist") }
  private let image = URL(fileURLWithPath: "/pictures/new.png")
  private let imageURLString = "file:///pictures/new.png"

  init() throws {
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("desktoppr-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  deinit {
    try? FileManager.default.removeItem(at: directory)
  }

  /// The picture URL of every `Desktop` in the store.
  private func pictures(in index: NSDictionary) -> [String] {
    WallpaperStore.desktopHolders(in: index).map { holder in
      let desktop = holder["Desktop"] as! NSDictionary
      let choices = (desktop["Content"] as! NSDictionary)["Choices"] as! [NSDictionary]
      let data = choices[0]["Configuration"] as! Data
      let configuration =
        try! PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        as! [String: Any]
      return (configuration["url"] as! [String: Any])["relative"] as! String
    }
  }

  private func shuffle(of holder: NSDictionary) -> String? {
    let content = (holder["Desktop"] as! NSDictionary)["Content"] as! NSDictionary
    return content["Shuffle"] as? String
  }

  // MARK: desktopHolders

  @Test func desktopHoldersFindsEveryDesktop() {
    let index = Fixture.store(current: imageURLString)
    // SystemDefault, 1 display, and per space: Default + displays (1 + 2, 1 + 1).
    #expect(WallpaperStore.desktopHolders(in: index).count == 1 + 1 + 3 + 2)
  }

  @Test func desktopHoldersExcludesIdleOnlyEntries() {
    let index = Fixture.store(current: imageURLString)
    let idle = index["AllSpacesAndDisplays"] as! NSDictionary
    #expect(!WallpaperStore.desktopHolders(in: index).contains { $0 === idle })
  }

  @Test func desktopHoldersToleratesMissingSections() {
    #expect(WallpaperStore.desktopHolders(in: [:]).isEmpty)
    let onlyDefault: NSMutableDictionary = [
      "SystemDefault": Fixture.holder("file:///a", lastSet: Fixture.old)
    ]
    #expect(WallpaperStore.desktopHolders(in: onlyDefault).count == 1)
  }

  // MARK: references

  @Test func referencesMatchesImage() {
    let desktop = Fixture.desktop(imageURLString, lastSet: Fixture.new)
    #expect(WallpaperStore.references(desktop, image: image))
  }

  @Test func referencesRejectsOtherImage() {
    let desktop = Fixture.desktop("file:///pictures/other.png", lastSet: Fixture.new)
    #expect(!WallpaperStore.references(desktop, image: image))
  }

  @Test func referencesRejectsImageWithMatchingPrefix() {
    let desktop = Fixture.desktop("file:///pictures/new.png.bak", lastSet: Fixture.new)
    #expect(!WallpaperStore.references(desktop, image: image))
  }

  @Test func referencesDecodesPercentEncodedPaths() {
    let spaced = URL(fileURLWithPath: "/pictures/my wallpaper.png")
    let desktop = Fixture.desktop("file:///pictures/my%20wallpaper.png", lastSet: Fixture.new)
    #expect(WallpaperStore.references(desktop, image: spaced))
  }

  @Test func referencesFollowsSymlinks() throws {
    let real = directory.appendingPathComponent("real.png")
    try Data().write(to: real)
    let link = directory.appendingPathComponent("link.png")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
    let desktop = Fixture.desktop(real.absoluteString, lastSet: Fixture.new)
    #expect(WallpaperStore.references(desktop, image: link))
  }

  private static var malformedEntries: [NSDictionary] {
    [
      [:],
      ["Content": [:]],
      ["Content": ["Choices": [["Configuration": Data("not a plist".utf8)]]]],
      ["Content": ["Choices": [["Configuration": Fixture.configuration("")]]]],
    ]
  }

  @Test(arguments: 0..<4)
  func referencesIgnoresMalformedEntries(index: Int) {
    let desktop = Self.malformedEntries[index]
    #expect(!WallpaperStore.references(desktop, image: image))
  }

  // MARK: apply

  @Test func applyCopiesNewestEntryEverywhere() {
    let index = Fixture.store(current: imageURLString)
    #expect(WallpaperStore.apply(image: image, to: index))
    #expect(Set(pictures(in: index)) == [imageURLString])
  }

  @Test func applyCopiesWholeEntryIncludingLastSet() {
    let index = Fixture.store(current: imageURLString)
    #expect(WallpaperStore.apply(image: image, to: index))
    for holder in WallpaperStore.desktopHolders(in: index) {
      #expect(WallpaperStore.lastSet(holder["Desktop"] as! NSDictionary) == Fixture.new)
    }
  }

  @Test func applyPrefersNewestWhenSeveralEntriesReferenceImage() {
    let index = Fixture.store(current: imageURLString)
    // An older entry references the same image but with a different shuffle value.
    let stale = Fixture.holder(imageURLString, lastSet: Fixture.old)
    ((stale["Desktop"] as! NSMutableDictionary)["Content"] as! NSMutableDictionary)["Shuffle"] =
      "stale"
    (index["Displays"] as! NSMutableDictionary)["D1"] = stale

    #expect(WallpaperStore.apply(image: image, to: index))
    for holder in WallpaperStore.desktopHolders(in: index) {
      #expect(shuffle(of: holder) == "$null")
    }
  }

  @Test func applyLeavesStoreUntouchedWhenNothingReferencesImage() {
    let index = Fixture.store(current: "file:///pictures/other.png")
    let before = index.copy() as! NSDictionary
    #expect(!WallpaperStore.apply(image: image, to: index))
    #expect(index == before)
  }

  @Test func applyLeavesIdleSettingsAlone() {
    let index = Fixture.store(current: imageURLString)
    let idle = (index["AllSpacesAndDisplays"] as! NSDictionary).copy() as! NSDictionary
    #expect(WallpaperStore.apply(image: image, to: index))
    #expect(index["AllSpacesAndDisplays"] as? NSDictionary == idle)
  }

  @Test func applyDoesNotAddDesktopToEntriesWithoutOne() {
    let index = Fixture.store(current: imageURLString)
    let space = (index["Spaces"] as! NSMutableDictionary)["S1"] as! NSMutableDictionary
    let bare: NSMutableDictionary = ["Type": "individual"]
    (space["Displays"] as! NSMutableDictionary)["D3"] = bare
    #expect(WallpaperStore.apply(image: image, to: index))
    #expect(bare["Desktop"] == nil)
  }

  @Test func applyGivesEachEntryItsOwnCopy() {
    let index = Fixture.store(current: imageURLString)
    #expect(WallpaperStore.apply(image: image, to: index))
    let holders = WallpaperStore.desktopHolders(in: index)
    ((holders[0]["Desktop"] as! NSMutableDictionary)["Content"] as! NSMutableDictionary)[
      "Shuffle"] = "changed"
    for holder in holders.dropFirst() {
      #expect(shuffle(of: holder) == "$null")
    }
  }

  // MARK: load

  @Test func loadReadsStoreWrittenByFixture() throws {
    try Fixture.write(Fixture.store(current: imageURLString), to: storeURL)
    let index = try #require(WallpaperStore.load(storeURL))
    #expect(WallpaperStore.desktopHolders(in: index).count == 7)
  }

  @Test func loadReturnsNilForMissingOrPartialFiles() throws {
    #expect(WallpaperStore.load(storeURL) == nil)
    try Data("bplist00 truncated".utf8).write(to: storeURL)
    #expect(WallpaperStore.load(storeURL) == nil)
  }

  // MARK: spread

  @Test func spreadRewritesStoreOnDisk() throws {
    try Fixture.write(Fixture.store(current: imageURLString), to: storeURL)
    try WallpaperStore.spread(image: image, store: storeURL, timeout: 2)

    let index = try #require(WallpaperStore.load(storeURL))
    #expect(Set(pictures(in: index)) == [imageURLString])
  }

  @Test func spreadWritesBinaryPlistAndLeavesNoTemporaryFile() throws {
    try Fixture.write(Fixture.store(current: imageURLString), to: storeURL)
    try WallpaperStore.spread(image: image, store: storeURL, timeout: 2)

    let data = try Data(contentsOf: storeURL)
    var format = PropertyListSerialization.PropertyListFormat.xml
    _ = try PropertyListSerialization.propertyList(from: data, options: [], format: &format)
    #expect(format == .binary)
    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["Index.plist"])
  }

  @Test func spreadTimesOutAndLeavesStoreUntouched() throws {
    try Fixture.write(Fixture.store(current: "file:///pictures/other.png"), to: storeURL)
    let before = try Data(contentsOf: storeURL)

    let error = #expect(throws: WallpaperStore.StoreError.self) {
      try WallpaperStore.spread(image: image, store: storeURL, timeout: 0.5)
    }
    #expect(
      "\(try #require(error))"
        == "timed out waiting for \(storeURL.path) to reference \(image.path)")
    #expect(try Data(contentsOf: storeURL) == before)
  }

  @Test func spreadTimesOutWhenStoreIsMissing() {
    #expect(throws: WallpaperStore.StoreError.self) {
      try WallpaperStore.spread(image: image, store: storeURL, timeout: 0.5)
    }
  }

  /// The wallpaper agent records the new picture some time after desktoppr sets it.
  @Test func spreadWaitsForAsynchronousWrite() throws {
    try Fixture.write(Fixture.store(current: "file:///pictures/other.png"), to: storeURL)
    let writer = DispatchQueue(label: "agent")
    let storeURL = self.storeURL
    let imageURLString = self.imageURLString
    writer.asyncAfter(deadline: .now() + 0.6) {
      // Start with a partial write, like an agent that is mid-write.
      try? Data("bplist00".utf8).write(to: storeURL)
      writer.asyncAfter(deadline: .now() + 0.4) {
        try? Fixture.write(Fixture.store(current: imageURLString), to: storeURL)
      }
    }

    try WallpaperStore.spread(image: image, store: storeURL, timeout: 10)
    let index = try #require(WallpaperStore.load(storeURL))
    #expect(Set(pictures(in: index)) == [imageURLString])
  }

  // MARK: replace

  @Test func replaceOverwritesFile() throws {
    try Data("old".utf8).write(to: storeURL)
    try WallpaperStore.replace(storeURL, with: Data("new".utf8))
    #expect(try Data(contentsOf: storeURL) == Data("new".utf8))
  }

  @Test func replaceFailsCleanlyWhenDirectoryIsMissing() {
    let missing = directory.appendingPathComponent("missing/Index.plist")
    #expect(throws: (any Error).self) {
      try WallpaperStore.replace(missing, with: Data())
    }
  }

  /// Renaming a file over a non-empty directory fails.
  @Test func replaceCleansUpWhenRenameFails() throws {
    let target = directory.appendingPathComponent("target")
    try FileManager.default.createDirectory(
      at: target.appendingPathComponent("child"), withIntermediateDirectories: true)
    #expect(throws: (any Error).self) {
      try WallpaperStore.replace(target, with: Data("x".utf8))
    }
    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["target"])
  }
}
