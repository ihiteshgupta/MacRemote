import Foundation

enum MouseButton: UInt8 {
    case none = 0
    case left = 1
    case middle = 2
    case right = 4
    case scrollUp = 8
    case scrollDown = 16
}

struct MouseEvent {
    let x: UInt16
    let y: UInt16
    let buttonMask: UInt8

    init(x: Int, y: Int, buttons: [MouseButton] = []) {
        self.x = UInt16(max(0, x))
        self.y = UInt16(max(0, y))
        self.buttonMask = buttons.reduce(0) { $0 | $1.rawValue }
    }
}

struct KeyEvent {
    let key: UInt32
    let isPressed: Bool

    // Common key codes (X11 keysyms)
    static let escape: UInt32 = 0xff1b
    static let tab: UInt32 = 0xff09
    static let returnKey: UInt32 = 0xff0d
    static let backspace: UInt32 = 0xff08
    static let delete: UInt32 = 0xffff

    // Modifiers
    static let shift: UInt32 = 0xffe1
    static let control: UInt32 = 0xffe3
    static let alt: UInt32 = 0xffe9      // Option on Mac
    static let command: UInt32 = 0xffe7  // Super/Meta

    // Arrow keys
    static let leftArrow: UInt32 = 0xff51
    static let upArrow: UInt32 = 0xff52
    static let rightArrow: UInt32 = 0xff53
    static let downArrow: UInt32 = 0xff54
}

enum InputMode: String, CaseIterable {
    case touch = "Touch"
    case trackpad = "Trackpad"
}

enum DisplayMode: String, CaseIterable {
    case primary = "Primary"    // Left half (main display)
    case secondary = "Secondary" // Right half (second display)
    case all = "All"            // Full desktop (both displays)
}
