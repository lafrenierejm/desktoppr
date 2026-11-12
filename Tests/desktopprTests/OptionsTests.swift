import AppKit
import Testing

@testable import desktoppr

@Suite struct HexColorTests {
  private func components(of color: NSColor) -> [Double] {
    [color.redComponent, color.greenComponent, color.blueComponent, color.alphaComponent]
      .map(Double.init)
  }

  @Test(arguments: ["FF8000", "ff8000", "#FF8000", "#ff8000"])
  func parsesSixDigits(argument: String) throws {
    let hex = try #require(HexColor(argument: argument))
    let expected = [1.0, 128.0 / 255.0, 0.0, 1.0]
    for (actual, wanted) in zip(components(of: hex.color), expected) {
      #expect(abs(actual - wanted) < 0.001)
    }
  }

  @Test func parsesBlackAndWhite() throws {
    let black = try #require(HexColor(argument: "000000"))
    let white = try #require(HexColor(argument: "FFFFFF"))
    #expect(components(of: black.color).prefix(3).allSatisfy { $0 == 0 })
    #expect(components(of: white.color).prefix(3).allSatisfy { abs($0 - 1) == 0 })
  }

  @Test(arguments: [
    "", "#", "FFF", "FFFFF", "FFFFFFF", "GGGGGG", "##FFFFFF", " FFFFFF", "FFFFFF ",
    "-FFFFF", "+FFFFF", "0xFFFFF",
  ])
  func rejectsInvalidColors(argument: String) {
    #expect(HexColor(argument: argument) == nil)
  }
}

@Suite struct ScreenSelectionTests {
  @Test func parsesKeywords() {
    #expect(ScreenSelection(argument: "all") == .all)
    #expect(ScreenSelection(argument: "main") == .main)
  }

  @Test(arguments: [0, 1, 2, 10])
  func parsesIndexes(index: Int) {
    #expect(ScreenSelection(argument: String(index)) == .index(index))
  }

  @Test(arguments: ["", "ALL", "Main", "x", "-1", "+1", "1.5", "1 ", "99999999999999999999"])
  func rejectsInvalidSelections(argument: String) {
    #expect(ScreenSelection(argument: argument) == nil)
  }

  @Test func describesItsDefault() {
    #expect(ScreenSelection.all.defaultValueDescription == "all")
    #expect(ScreenSelection.main.defaultValueDescription == "main")
    #expect(ScreenSelection.index(3).defaultValueDescription == "3")
  }
}

@Suite struct ScaleOptionTests {
  @Test(arguments: ScaleOption.allCases)
  func parsesEveryCase(scale: ScaleOption) {
    #expect(ScaleOption(argument: scale.rawValue) == scale)
  }

  @Test func hasTheDocumentedCases() {
    #expect(ScaleOption.allCases.map(\.rawValue) == ["fill", "stretch", "center", "fit"])
  }

  @Test(arguments: ["", "Fill", "FIT", "sideways", "tile"])
  func rejectsUnknownModes(argument: String) {
    #expect(ScaleOption(argument: argument) == nil)
  }
}
