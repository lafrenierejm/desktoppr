//
//  Options.swift
//  desktoppr
//

import AppKit
import ArgumentParser

/// How the picture is scaled to the screen.
enum ScaleOption: String, CaseIterable, ExpressibleByArgument {
  case fill
  case stretch
  case center
  case fit
}

/// Which screen a command applies to.
enum ScreenSelection: ExpressibleByArgument {
  case all
  case main
  case index(Int)

  init?(argument: String) {
    switch argument {
    case "all": self = .all
    case "main": self = .main
    default:
      guard let index = Int(argument), index >= 0 else { return nil }
      self = .index(index)
    }
  }

  var defaultValueDescription: String {
    switch self {
    case .all: return "all"
    case .main: return "main"
    case .index(let index): return String(index)
    }
  }

  static var defaultCompletionKind: CompletionKind {
    .list(["all", "main"])
  }

  /// The screens this selection refers to.
  func screens() throws -> [NSScreen] {
    switch self {
    case .all:
      return NSScreen.screens
    case .main:
      guard let main = NSScreen.main else { throw RuntimeError("no main screen") }
      return [main]
    case .index(let index):
      guard NSScreen.screens.indices.contains(index) else {
        throw RuntimeError("No screen with index \(index)!")
      }
      return [NSScreen.screens[index]]
    }
  }
}

/// A color given as six hex digits, with or without a leading `#`.
struct HexColor: ExpressibleByArgument {
  let color: NSColor

  init?(argument: String) {
    let digits = argument.hasPrefix("#") ? String(argument.dropFirst()) : argument
    guard digits.count == 6, let code = Int(digits, radix: 16) else { return nil }
    color = NSColor(
      calibratedRed: CGFloat((code >> 16) & 0xff) / 0xff,
      green: CGFloat((code >> 8) & 0xff) / 0xff,
      blue: CGFloat(code & 0xff) / 0xff,
      alpha: 1.0)
  }
}
