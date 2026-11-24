import XCTest
@testable import HostShelfCore

final class HotKeyShortcutTests: XCTestCase {
    func testRecommendedDefaultAndValidation() {
        let recommended = HotKeyShortcut.recommendedDefault
        XCTAssertTrue(recommended.isValidForGlobalRegistration)
        XCTAssertEqual(recommended.displayString, "⌃⌥H")

        let shiftOnly = HotKeyShortcut(keyCode: 4, carbonModifiers: HotKeyShortcut.shiftModifier)
        XCTAssertFalse(shiftOnly.isValidForGlobalRegistration)

        let noModifiers = HotKeyShortcut(keyCode: 49, carbonModifiers: 0)
        XCTAssertFalse(noModifiers.isValidForGlobalRegistration)

        let unknownKey = HotKeyShortcut(keyCode: 999, carbonModifiers: HotKeyShortcut.commandModifier)
        XCTAssertFalse(unknownKey.isValidForGlobalRegistration)
    }

    func testDisplayOrderingAndCodableRoundTrip() throws {
        let mods = HotKeyShortcut.carbonModifiers(control: true, option: true, shift: true, command: true)
        let shortcut = HotKeyShortcut(keyCode: 49, carbonModifiers: mods)
        XCTAssertTrue(shortcut.isValidForGlobalRegistration)
        XCTAssertEqual(shortcut.displayString, "⌃⌥⇧⌘Space")

        let data = try JSONEncoder().encode(shortcut)
        let decoded = try JSONDecoder().decode(HotKeyShortcut.self, from: data)
        XCTAssertEqual(decoded, shortcut)
    }
}
