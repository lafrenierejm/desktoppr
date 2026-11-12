//
//  Commands.swift
//  desktoppr
//

import AppKit
import ArgumentParser
import Foundation

struct ScreenOptions: ParsableArguments {
  @Option(
    name: .shortAndLong,
    help: ArgumentHelp(
      "The screen to use: all, main, or a screen index (starting at zero).",
      valueName: "all|main|index"))
  var screen: ScreenSelection = .all
}

struct Picture: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Print or set the desktop picture.",
    discussion: "Without a picture, prints the path of the current picture of each screen.")

  @OptionGroup var screens: ScreenOptions

  @Argument(
    help: "The picture to set: a file path or an http(s) URL.",
    completion: .file())
  var picture: String?

  @Flag(
    help: """
      Also set the picture for every Space (desktop), including Spaces created later. \
      Requires a picture, and applies to all screens.
      """)
  var allSpaces = false

  func validate() throws {
    guard allSpaces else { return }
    guard picture != nil else {
      throw ValidationError("--all-spaces requires a picture to set.")
    }
    guard screens.screen == .all else {
      throw ValidationError("--all-spaces sets the picture for all screens; remove --screen.")
    }
  }

  func run() throws {
    // Check the screen before downloading anything.
    let targets = try screens.screen.screens()
    guard let picture = picture else {
      for screen in targets {
        print(desktopImagePath(for: screen))
      }
      return
    }

    warnIfRoot()
    let url = try resolvePicture(picture)
    if case .all = screens.screen {
      try setAllDesktopImages(url: url, allSpaces: allSpaces)
    } else {
      for screen in targets {
        try setDesktopImage(url: url, for: screen)
      }
    }
  }
}

struct Color: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Print or set the background color for all screens.",
    discussion: "Without a color, prints the current color of each screen.")

  @Argument(help: ArgumentHelp("The color to set, as six hex digits.", valueName: "RRGGBB"))
  var color: HexColor?

  func run() throws {
    warnIfRoot()
    if let color = color {
      try setFillColor(color: color.color)
    } else {
      for screen in NSScreen.screens {
        print(fillColor(for: screen) ?? "cannot get color")
      }
    }
  }
}

struct Scale: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Print or set how the picture is scaled on all screens.",
    discussion: "Without a mode, prints the current mode of each screen.")

  @Argument(help: "The scaling mode to set.")
  var mode: ScaleOption?

  func run() throws {
    warnIfRoot()
    if let mode = mode {
      try setImageScaling(mode)
    } else {
      for screen in NSScreen.screens {
        print(imageScaling(for: screen)?.rawValue ?? "unknown")
      }
    }
  }
}

struct Clip: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Print whether clipping is allowed for each screen.",
    shouldDisplay: false)

  func run() throws {
    warnIfRoot()
    for screen in NSScreen.screens {
      print(allowClipping(for: screen)?.description ?? "unknown")
    }
  }
}

struct Manage: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Apply the settings in the com.scriptingosx.desktoppr preference domain.",
    discussion: "See the documentation for the supported keys.")

  func run() throws {
    warnIfRoot()
    guard let picturePath = Defaults.picturePath else { return }
    let fileURL = try resolvePicture(picturePath)
    try verifyChecksum(of: fileURL)

    // With `setOnlyOnce`, skip pictures already set, so the user can change the
    // wallpaper without it being overwritten.
    let alreadySet = Defaults.lastURL == picturePath || Defaults.lastPath == picturePath
    if Defaults.setOnlyOnce && alreadySet {
      return
    }

    if let colorString = Defaults.color {
      guard let color = HexColor(argument: colorString) else {
        throw RuntimeError("could not parse color: \(colorString)")
      }
      try setFillColor(color: color.color)
    }
    try setImageScaling(Defaults.scale)
    try setAllDesktopImages(url: fileURL, allSpaces: Defaults.allSpaces)
  }

  /// Compares against the configured checksum, if any. Exits with 9 on a mismatch.
  private func verifyChecksum(of url: URL) throws {
    let checks: [(name: String, expected: String?, actual: (Data) -> String)] = [
      ("sha256", Defaults.sha256, { $0.sha256 }),
      ("sha1", Defaults.sha1, { $0.sha1 }),
      ("md5", Defaults.md5, { $0.md5 }),
    ]
    // Only the strongest configured checksum is used.
    guard let check = checks.first(where: { $0.expected != nil }),
      let expected = check.expected
    else { return }
    guard let data = url.data, check.actual(data).lowercased() == expected.lowercased() else {
      errprint("\(check.name) checksum doesn't match")
      throw ExitCode(9)
    }
  }
}
