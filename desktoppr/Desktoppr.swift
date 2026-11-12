//
//  Desktoppr.swift
//  desktoppr
//

import ArgumentParser
import Foundation

let version = "0.5"

struct RuntimeError: Error, CustomStringConvertible {
  let description: String
  init(_ description: String) { self.description = description }
}

/// Warns when running as root, since the picture is set for the current user.
func warnIfRoot() {
  guard ProcessInfo.processInfo.userName == "root" else { return }
  errprint(
    "desktoppr is running as root. This is probably not what you are intending. To set the desktop picture for a user, desktoppr needs to run as that user."
  )
}

@main
struct Desktoppr: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "desktoppr",
    abstract: "Print or set the desktop picture, scaling, and background color.",
    discussion: "Source and documentation: https://github.com/scriptingosx/desktoppr",
    version: version,
    subcommands: [Picture.self, Color.self, Scale.self, Manage.self, Clip.self])

  /// Only reached when no subcommand was given.
  func run() throws {
    throw ValidationError("Missing expected subcommand.")
  }
}
