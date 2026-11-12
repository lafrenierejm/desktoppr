import ArgumentParser
import Testing

@testable import desktoppr

/// Parses `arguments` as the whole command line and expects the given subcommand.
private func parse<Command: ParsableCommand>(
  _ type: Command.Type, _ arguments: [String]
) throws -> Command {
  let parsed = try Desktoppr.parseAsRoot(arguments)
  return try #require(parsed as? Command, "parsed \(Swift.type(of: parsed))")
}

/// The message ArgumentParser would print for a command line that fails to parse.
private func parseFailure(_ arguments: [String]) -> String {
  do {
    _ = try Desktoppr.parseAsRoot(arguments)
    return "parsed without an error"
  } catch {
    return Desktoppr.message(for: error)
  }
}

@Suite struct CommandParsingTests {
  // MARK: Root

  @Test func requiresASubcommand() throws {
    var command = try Desktoppr.parseAsRoot([])
    #expect(command is Desktoppr)
    #expect(throws: ValidationError.self) { try command.run() }
  }

  @Test(arguments: [["bogus"], ["--screen", "0"], ["/some/picture.png"], ["--bogus"]])
  func rejectsUnknownArguments(arguments: [String]) {
    #expect(throws: (any Error).self) { try Desktoppr.parseAsRoot(arguments) }
  }

  @Test(arguments: [["get"], ["set", "/a.png"], ["set", "--screen", "0", "/a.png"]])
  func rejectsRemovedSubcommands(arguments: [String]) {
    #expect(throws: (any Error).self) { try Desktoppr.parseAsRoot(arguments) }
  }

  @Test func reportsTheVersion() {
    // The error is an internal wrapper, which `message(for:)` and `exitCode(for:)` unwrap.
    do {
      _ = try Desktoppr.parseAsRoot(["--version"])
      Issue.record("expected --version to stop parsing")
    } catch {
      #expect(Desktoppr.message(for: error) == version)
      #expect(Desktoppr.exitCode(for: error) == .success)
    }
  }

  @Test(arguments: ["--help", "-h"])
  func helpIsNotOneOfTheCommands(flag: String) throws {
    // ArgumentParser parses a help flag to its own internal command, which prints
    // the help when run. `listsTheSubcommandsInHelp` covers the text.
    let parsed = try Desktoppr.parseAsRoot([flag])
    #expect(!(parsed is Desktoppr))
    #expect(!(parsed is Picture))
  }

  @Test func listsTheSubcommandsInHelp() {
    let help = Desktoppr.helpMessage()
    for name in ["picture", "color", "scale", "manage"] {
      #expect(help.contains(name), "help is missing \(name)")
    }
    #expect(!help.contains("clip"), "clip is hidden")
  }

  // MARK: picture

  @Test func pictureWithoutArgumentsPrints() throws {
    let command = try parse(Picture.self, ["picture"])
    #expect(command.picture == nil)
    #expect(command.screens.screen == .all)
  }

  @Test(arguments: ["/a.png", "relative/b.jpg", "https://example.com/c.png", "has space.png"])
  func pictureTakesAPathOrURL(path: String) throws {
    let command = try parse(Picture.self, ["picture", path])
    #expect(command.picture == path)
    #expect(command.screens.screen == .all)
  }

  @Test(arguments: [
    (["--screen", "main"], ScreenSelection.main),
    (["--screen", "all"], ScreenSelection.all),
    (["--screen", "2"], ScreenSelection.index(2)),
    (["--screen=1"], ScreenSelection.index(1)),
    (["-s", "0"], ScreenSelection.index(0)),
  ])
  func pictureTakesAScreen(options: [String], expected: ScreenSelection) throws {
    let command = try parse(Picture.self, ["picture"] + options + ["/a.png"])
    #expect(command.screens.screen == expected)
    #expect(command.picture == "/a.png")
  }

  @Test func pictureAcceptsTheScreenAfterThePath() throws {
    let command = try parse(Picture.self, ["picture", "/a.png", "--screen", "1"])
    #expect(command.screens.screen == .index(1))
    #expect(command.picture == "/a.png")
  }

  @Test func pictureCanSelectAScreenWithoutAPicture() throws {
    let command = try parse(Picture.self, ["picture", "--screen", "main"])
    #expect(command.screens.screen == .main)
    #expect(command.picture == nil)
  }

  @Test(arguments: [
    ["picture", "--screen"],
    ["picture", "--screen", "x"],
    ["picture", "--screen", "-1"],
    ["picture", "--screen", "+1"],
    ["picture", "/a.png", "/b.png"],
    ["picture", "--bogus"],
  ])
  func pictureRejectsInvalidArguments(arguments: [String]) {
    #expect(throws: (any Error).self) { try Desktoppr.parseAsRoot(arguments) }
  }

  // MARK: picture --all-spaces

  @Test func allSpacesIsOffByDefault() throws {
    #expect(try parse(Picture.self, ["picture", "/a.png"]).allSpaces == false)
  }

  @Test(arguments: [
    ["picture", "--all-spaces", "/a.png"],
    ["picture", "/a.png", "--all-spaces"],
    ["picture", "--all-spaces", "--screen", "all", "/a.png"],
    ["picture", "--screen=all", "/a.png", "--all-spaces"],
  ])
  func allSpacesAcceptsAPictureOnAllScreens(arguments: [String]) throws {
    let command = try parse(Picture.self, arguments)
    #expect(command.allSpaces)
    #expect(command.picture == "/a.png")
    #expect(command.screens.screen == .all)
  }

  @Test func allSpacesRequiresAPicture() {
    let invalid = [
      ["picture", "--all-spaces"],
      ["picture", "--all-spaces", "--screen", "all"],
    ]
    for arguments in invalid {
      let message = parseFailure(arguments)
      #expect(message.contains("--all-spaces requires a picture"), "\(arguments): \(message)")
    }
  }

  @Test(arguments: [
    ["picture", "--all-spaces", "--screen", "main", "/a.png"],
    ["picture", "--all-spaces", "-s", "0", "/a.png"],
    ["picture", "/a.png", "--screen", "2", "--all-spaces"],
  ])
  func allSpacesRejectsASpecificScreen(arguments: [String]) {
    let message = parseFailure(arguments)
    #expect(message.contains("--all-spaces sets the picture for all screens"), "\(message)")
  }

  @Test(arguments: [
    ["--all-spaces"],
    ["--all-spaces", "picture", "/a.png"],
    ["color", "--all-spaces"],
    ["color", "000000", "--all-spaces"],
    ["scale", "--all-spaces", "fit"],
    ["manage", "--all-spaces"],
  ])
  func allSpacesOnlyBelongsToPicture(arguments: [String]) {
    #expect(throws: (any Error).self) { try Desktoppr.parseAsRoot(arguments) }
  }

  @Test func pictureHelpDocumentsAllSpaces() {
    #expect(Picture.helpMessage().contains("--all-spaces"))
  }

  // MARK: color

  @Test func colorWithoutArgumentsPrints() throws {
    #expect(try parse(Color.self, ["color"]).color == nil)
  }

  @Test(arguments: ["000000", "FFFFFF", "ff0000", "#3333FF"])
  func colorTakesHexDigits(argument: String) throws {
    #expect(try parse(Color.self, ["color", argument]).color != nil)
  }

  @Test(arguments: ["zzz", "FFF", "FFFFFFF", "-FFFFF", ""])
  func colorRejectsInvalidColors(argument: String) {
    #expect(throws: (any Error).self) { try Desktoppr.parseAsRoot(["color", argument]) }
  }

  @Test func colorRejectsExtraArguments() {
    #expect(throws: (any Error).self) { try Desktoppr.parseAsRoot(["color", "000000", "FFFFFF"]) }
  }

  // MARK: scale

  @Test func scaleWithoutArgumentsPrints() throws {
    #expect(try parse(Scale.self, ["scale"]).mode == nil)
  }

  @Test(arguments: ScaleOption.allCases)
  func scaleTakesEveryMode(mode: ScaleOption) throws {
    #expect(try parse(Scale.self, ["scale", mode.rawValue]).mode == mode)
  }

  @Test(arguments: ["sideways", "Fill", "", "fit fill"])
  func scaleRejectsUnknownModes(argument: String) {
    #expect(throws: (any Error).self) { try Desktoppr.parseAsRoot(["scale", argument]) }
  }

  @Test func scaleRejectsExtraArguments() {
    #expect(throws: (any Error).self) { try Desktoppr.parseAsRoot(["scale", "fit", "fill"]) }
  }

  // MARK: manage and clip

  @Test func manageTakesNoArguments() throws {
    _ = try parse(Manage.self, ["manage"])
    #expect(throws: (any Error).self) { try Desktoppr.parseAsRoot(["manage", "extra"]) }
  }

  @Test func clipParsesEvenThoughItIsHidden() throws {
    _ = try parse(Clip.self, ["clip"])
  }
}
