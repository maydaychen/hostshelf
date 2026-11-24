import Foundation

public struct HotKeyShortcut: Codable, Equatable, Hashable, Sendable {
    public static let controlModifier: UInt32 = 4_096
    public static let optionModifier: UInt32 = 2_048
    public static let shiftModifier: UInt32 = 512
    public static let commandModifier: UInt32 = 256
    public static let supportedModifiersMask: UInt32 =
        controlModifier | optionModifier | shiftModifier | commandModifier

    public static let recommendedDefault = HotKeyShortcut(
        keyCode: 4,
        carbonModifiers: controlModifier | optionModifier
    )

    public let keyCode: UInt32
    public let carbonModifiers: UInt32

    public init(keyCode: UInt32, carbonModifiers: UInt32) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers & Self.supportedModifiersMask
    }

    public var isValidForGlobalRegistration: Bool {
        let required = Self.commandModifier | Self.controlModifier | Self.optionModifier
        guard (carbonModifiers & required) != 0 else { return false }
        return Self.keyLabels[keyCode] != nil
    }

    public var displayString: String {
        var prefix = ""
        if (carbonModifiers & Self.controlModifier) != 0 { prefix += "⌃" }
        if (carbonModifiers & Self.optionModifier) != 0 { prefix += "⌥" }
        if (carbonModifiers & Self.shiftModifier) != 0 { prefix += "⇧" }
        if (carbonModifiers & Self.commandModifier) != 0 { prefix += "⌘" }
        let label = Self.keyLabels[keyCode] ?? "Key(\(keyCode))"
        return prefix + label
    }

    public static func carbonModifiers(
        control: Bool,
        option: Bool,
        shift: Bool,
        command: Bool
    ) -> UInt32 {
        var mask: UInt32 = 0
        if control { mask |= controlModifier }
        if option { mask |= optionModifier }
        if shift { mask |= shiftModifier }
        if command { mask |= commandModifier }
        return mask
    }

    public static func keyDisplayName(for keyCode: UInt32) -> String? {
        keyLabels[keyCode]
    }

    private static let keyLabels: [UInt32: String] = [
        0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H", 34: "I",
        38: "J", 40: "K", 37: "L", 46: "M", 45: "N", 31: "O", 35: "P", 12: "Q",
        15: "R", 1: "S", 17: "T", 32: "U", 9: "V", 13: "W", 7: "X", 16: "Y", 6: "Z",
        29: "0", 18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9",
        27: "-", 24: "=", 33: "[", 30: "]", 41: ";", 39: "'", 43: ",", 47: ".", 44: "/",
        42: "\\", 50: "`",
        49: "Space", 36: "Return", 48: "Tab", 51: "Delete",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]
}
