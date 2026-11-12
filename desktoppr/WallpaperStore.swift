//
//  WallpaperStore.swift
//  desktoppr
//

import Foundation

/// Spreads a wallpaper across every Space, including Spaces created later.
///
/// `NSWorkspace.setDesktopImageURL(_:for:)` only updates some entries of the
/// system's wallpaper store: always the current Space's, and usually
/// `SystemDefault` and the top-level `Displays`, but not reliably. Every other
/// Space keeps its own `Desktop` entry. `SystemDefault` is what new Spaces
/// start from.
///
/// This copies the freshly set entry over all of those entries. The store is
/// private and undocumented, so its layout may change between macOS releases.
enum WallpaperStore {
  static let defaultIndexURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/com.apple.wallpaper/Store/Index.plist")

  enum StoreError: Error, CustomStringConvertible {
    case timedOut(URL, URL)

    var description: String {
      switch self {
      case .timedOut(let store, let image):
        return "timed out waiting for \(store.path) to reference \(image.path)"
      }
    }
  }

  /// Waits until the store references `image`, then copies the newest such
  /// entry to every Space and to the defaults for new Spaces.
  ///
  /// The wallpaper agent writes the store asynchronously, so the entry may not
  /// exist yet when this is called.
  static func spread(
    image: URL, store: URL = defaultIndexURL, timeout: TimeInterval = 15
  ) throws {
    let deadline = Date().addingTimeInterval(timeout)
    while true {
      // The store can be mid-write; treat any read failure as "not yet".
      if let index = load(store), apply(image: image, to: index) {
        let data = try PropertyListSerialization.data(
          fromPropertyList: index, format: .binary, options: 0)
        try replace(store, with: data)
        return
      }
      if Date() >= deadline {
        throw StoreError.timedOut(store, image)
      }
      Thread.sleep(forTimeInterval: 0.25)
    }
  }

  /// Replaces `url` with `data` by writing a sibling file and renaming it over `url`,
  /// so readers never see a partial store.
  static func replace(_ url: URL, with data: Data) throws {
    let temporary = url.deletingLastPathComponent().appendingPathComponent(
      url.lastPathComponent + ".desktoppr-tmp")
    try data.write(to: temporary)
    if rename(temporary.path, url.path) != 0 {
      let code = errno
      try? FileManager.default.removeItem(at: temporary)
      throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
    }
  }

  static func load(_ url: URL) -> NSMutableDictionary? {
    guard let data = try? Data(contentsOf: url) else { return nil }
    return try? PropertyListSerialization.propertyList(
      from: data, options: .mutableContainers, format: nil) as? NSMutableDictionary
  }

  /// Copies the newest entry referencing `image` over every other entry.
  ///
  /// Returns false, leaving `index` untouched, if no entry references `image`.
  static func apply(image: URL, to index: NSMutableDictionary) -> Bool {
    let holders = desktopHolders(in: index)
    let matches = holders.compactMap { $0["Desktop"] as? NSDictionary }
      .filter { references($0, image: image) }
    guard
      let source = matches.max(by: { lastSet($0) < lastSet($1) })
    else { return false }

    for holder in holders where holder["Desktop"] != nil {
      guard let copy = deepCopy(source) else { return false }
      holder["Desktop"] = copy
    }
    return true
  }

  /// Every dictionary in the store that holds a `Desktop` entry.
  static func desktopHolders(in index: NSDictionary) -> [NSMutableDictionary] {
    func dictionaries(_ value: Any?) -> [NSMutableDictionary] {
      (value as? NSDictionary)?.allValues.compactMap { $0 as? NSMutableDictionary } ?? []
    }

    var holders: [NSMutableDictionary] = []
    if let systemDefault = index["SystemDefault"] as? NSMutableDictionary {
      holders.append(systemDefault)
    }
    holders += dictionaries(index["Displays"])
    for case let space as NSDictionary in (index["Spaces"] as? NSDictionary)?.allValues ?? [] {
      if let spaceDefault = space["Default"] as? NSMutableDictionary {
        holders.append(spaceDefault)
      }
      holders += dictionaries(space["Displays"])
    }
    return holders
  }

  /// Whether any choice of `desktop` is the image file at `image`.
  static func references(_ desktop: NSDictionary, image: URL) -> Bool {
    let target = image.resolvingSymlinksInPath().path
    let choices = (desktop["Content"] as? NSDictionary)?["Choices"] as? [NSDictionary] ?? []
    return choices.contains { choice in
      // `Configuration` is itself a plist: {type: imageFile, url: {relative: "file:///…"}}
      guard
        let data = choice["Configuration"] as? Data,
        let configuration = try? PropertyListSerialization.propertyList(
          from: data, options: [], format: nil) as? [String: Any],
        let url = configuration["url"] as? [String: Any],
        let relative = url["relative"] as? String,
        let fileURL = URL(string: relative)
      else { return false }
      return fileURL.resolvingSymlinksInPath().path == target
    }
  }

  static func lastSet(_ desktop: NSDictionary) -> Date {
    desktop["LastSet"] as? Date ?? .distantPast
  }

  /// An independent mutable copy, so entries don't share nested containers.
  static func deepCopy(_ desktop: NSDictionary) -> NSMutableDictionary? {
    guard
      let data = try? PropertyListSerialization.data(
        fromPropertyList: desktop, format: .binary, options: 0)
    else { return nil }
    return try? PropertyListSerialization.propertyList(
      from: data, options: .mutableContainers, format: nil) as? NSMutableDictionary
  }
}
