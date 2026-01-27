import SwiftUI
import UIKit

/// A UIKit-based keyboard input view that reliably captures both software and hardware keyboard input on iPad.
/// Uses UITextField internally to ensure the software keyboard appears.
struct KeyboardInputView: UIViewRepresentable {
    let onKeyEvent: (KeyEvent) -> Void
    @Binding var isActive: Bool

    func makeUIView(context: Context) -> KeyboardTextField {
        let textField = KeyboardTextField()
        textField.keyboardEventHandler = { event in
            print("KeyboardInputView: Sending key event - key=\(event.key) pressed=\(event.isPressed)")
            onKeyEvent(event)
        }
        textField.onResignFirstResponder = {
            DispatchQueue.main.async {
                isActive = false
            }
        }

        // Configure for invisible but functional text field
        textField.autocapitalizationType = .none
        textField.autocorrectionType = .no
        textField.spellCheckingType = .no
        textField.keyboardType = .asciiCapable
        textField.returnKeyType = .default
        textField.backgroundColor = .clear
        textField.textColor = .clear
        textField.tintColor = .clear

        return textField
    }

    func updateUIView(_ textField: KeyboardTextField, context: Context) {
        print("KeyboardInputView: updateUIView called - isActive=\(isActive) isFirstResponder=\(textField.isFirstResponder)")
        if isActive && !textField.isFirstResponder {
            DispatchQueue.main.async {
                let success = textField.becomeFirstResponder()
                print("KeyboardInputView: becomeFirstResponder result=\(success)")
            }
        } else if !isActive && textField.isFirstResponder {
            DispatchQueue.main.async {
                textField.resignFirstResponder()
            }
        }
    }
}

/// Custom UITextField that intercepts all keyboard input and converts to VNC key events
class KeyboardTextField: UITextField, UITextFieldDelegate {
    var keyboardEventHandler: ((KeyEvent) -> Void)?
    var onResignFirstResponder: (() -> Void)?

    // Track currently pressed modifier keys
    private var pressedModifiers: Set<UInt32> = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        delegate = self

        // Add target for text changes as backup
        addTarget(self, action: #selector(textDidChange), for: .editingChanged)
    }

    override var canBecomeFirstResponder: Bool { true }

    @discardableResult
    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        onResignFirstResponder?()
        return result
    }

    // MARK: - UITextFieldDelegate

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        print("KeyboardTextField: shouldChangeCharacters - string='\(string)' isEmpty=\(string.isEmpty)")
        if string.isEmpty {
            // Deletion (backspace)
            keyboardEventHandler?(KeyEvent(key: KeyEvent.backspace, isPressed: true))
            keyboardEventHandler?(KeyEvent(key: KeyEvent.backspace, isPressed: false))
        } else {
            // Character input
            for char in string {
                print("KeyboardTextField: sending character '\(char)'")
                sendCharacter(char)
            }
        }

        // Clear text periodically to prevent overflow
        if (textField.text?.count ?? 0) > 50 {
            textField.text = ""
        }

        return true
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        // Return/Enter key
        keyboardEventHandler?(KeyEvent(key: KeyEvent.returnKey, isPressed: true))
        keyboardEventHandler?(KeyEvent(key: KeyEvent.returnKey, isPressed: false))
        return false
    }

    @objc private func textDidChange() {
        // Backup handler - clear text if it gets too long
        if (text?.count ?? 0) > 100 {
            text = ""
        }
    }

    // MARK: - Hardware Keyboard Support

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var handled = false

        for press in presses {
            if let key = press.key {
                if let keySym = uiKeyToKeySym(key) {
                    // Track modifier keys
                    if isModifierKey(keySym) {
                        pressedModifiers.insert(keySym)
                    }

                    keyboardEventHandler?(KeyEvent(key: keySym, isPressed: true))
                    handled = true
                }
            }
        }

        if !handled {
            super.pressesBegan(presses, with: event)
        }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var handled = false

        for press in presses {
            if let key = press.key {
                if let keySym = uiKeyToKeySym(key) {
                    // Untrack modifier keys
                    if isModifierKey(keySym) {
                        pressedModifiers.remove(keySym)
                    }

                    keyboardEventHandler?(KeyEvent(key: keySym, isPressed: false))
                    handled = true
                }
            }
        }

        if !handled {
            super.pressesEnded(presses, with: event)
        }
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        pressesEnded(presses, with: event)
    }

    // MARK: - Character Handling

    private func sendCharacter(_ char: Character) {
        guard let keySym = charToKeySym(char) else { return }

        // Check if we need shift for uppercase or symbols
        let needsShift = char.isUppercase || shiftRequiredChars.contains(char)

        if needsShift && !pressedModifiers.contains(KeyEvent.shift) {
            keyboardEventHandler?(KeyEvent(key: KeyEvent.shift, isPressed: true))
        }

        keyboardEventHandler?(KeyEvent(key: keySym, isPressed: true))
        keyboardEventHandler?(KeyEvent(key: keySym, isPressed: false))

        if needsShift && !pressedModifiers.contains(KeyEvent.shift) {
            keyboardEventHandler?(KeyEvent(key: KeyEvent.shift, isPressed: false))
        }
    }

    // MARK: - Key Mapping

    private func isModifierKey(_ keySym: UInt32) -> Bool {
        return keySym == KeyEvent.shift ||
               keySym == KeyEvent.control ||
               keySym == KeyEvent.alt ||
               keySym == KeyEvent.command
    }

    private let shiftRequiredChars: Set<Character> = [
        "!", "@", "#", "$", "%", "^", "&", "*", "(", ")",
        "_", "+", "{", "}", "|", ":", "\"", "<", ">", "?", "~"
    ]

    private func uiKeyToKeySym(_ key: UIKey) -> UInt32? {
        switch key.keyCode {
        // Modifiers
        case .keyboardLeftShift, .keyboardRightShift:
            return KeyEvent.shift
        case .keyboardLeftControl, .keyboardRightControl:
            return KeyEvent.control
        case .keyboardLeftAlt, .keyboardRightAlt:
            return KeyEvent.alt
        case .keyboardLeftGUI, .keyboardRightGUI:
            return KeyEvent.command

        // Special keys
        case .keyboardEscape:
            return KeyEvent.escape
        case .keyboardTab:
            return KeyEvent.tab
        case .keyboardReturnOrEnter:
            return KeyEvent.returnKey
        case .keyboardDeleteOrBackspace:
            return KeyEvent.backspace
        case .keyboardDeleteForward:
            return KeyEvent.delete

        // Arrow keys
        case .keyboardLeftArrow:
            return KeyEvent.leftArrow
        case .keyboardRightArrow:
            return KeyEvent.rightArrow
        case .keyboardUpArrow:
            return KeyEvent.upArrow
        case .keyboardDownArrow:
            return KeyEvent.downArrow

        // Function keys
        case .keyboardF1: return 0xffbe
        case .keyboardF2: return 0xffbf
        case .keyboardF3: return 0xffc0
        case .keyboardF4: return 0xffc1
        case .keyboardF5: return 0xffc2
        case .keyboardF6: return 0xffc3
        case .keyboardF7: return 0xffc4
        case .keyboardF8: return 0xffc5
        case .keyboardF9: return 0xffc6
        case .keyboardF10: return 0xffc7
        case .keyboardF11: return 0xffc8
        case .keyboardF12: return 0xffc9

        // Navigation
        case .keyboardHome: return 0xff50
        case .keyboardEnd: return 0xff57
        case .keyboardPageUp: return 0xff55
        case .keyboardPageDown: return 0xff56

        // Space
        case .keyboardSpacebar:
            return 0x20

        default:
            break
        }

        // For character keys, use charactersIgnoringModifiers
        let chars = key.charactersIgnoringModifiers
        if let char = chars.first {
            return charToKeySym(char)
        }

        return nil
    }

    private func charToKeySym(_ char: Character) -> UInt32? {
        let scalar = char.unicodeScalars.first?.value ?? 0

        // Letters - send lowercase, shift handled separately
        if char.isLetter {
            return UInt32(char.lowercased().unicodeScalars.first?.value ?? scalar)
        }

        // Shifted symbols -> send base key
        switch char {
        case "!": return UInt32(Character("1").asciiValue!)
        case "@": return UInt32(Character("2").asciiValue!)
        case "#": return UInt32(Character("3").asciiValue!)
        case "$": return UInt32(Character("4").asciiValue!)
        case "%": return UInt32(Character("5").asciiValue!)
        case "^": return UInt32(Character("6").asciiValue!)
        case "&": return UInt32(Character("7").asciiValue!)
        case "*": return UInt32(Character("8").asciiValue!)
        case "(": return UInt32(Character("9").asciiValue!)
        case ")": return UInt32(Character("0").asciiValue!)
        case "_": return UInt32(Character("-").asciiValue!)
        case "+": return UInt32(Character("=").asciiValue!)
        case "{": return UInt32(Character("[").asciiValue!)
        case "}": return UInt32(Character("]").asciiValue!)
        case "|": return UInt32(Character("\\").asciiValue!)
        case ":": return UInt32(Character(";").asciiValue!)
        case "\"": return UInt32(Character("'").asciiValue!)
        case "<": return UInt32(Character(",").asciiValue!)
        case ">": return UInt32(Character(".").asciiValue!)
        case "?": return UInt32(Character("/").asciiValue!)
        case "~": return UInt32(Character("`").asciiValue!)
        case "\n", "\r": return KeyEvent.returnKey
        case "\t": return KeyEvent.tab
        default:
            // ASCII printable range
            if scalar >= 0x20 && scalar <= 0x7E {
                return scalar
            }
            return nil
        }
    }
}
