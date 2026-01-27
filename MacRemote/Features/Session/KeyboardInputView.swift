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
        textField.smartQuotesType = .no
        textField.smartDashesType = .no
        textField.smartInsertDeleteType = .no
        textField.keyboardType = .asciiCapable
        textField.returnKeyType = .default
        textField.isSecureTextEntry = false  // Don't use secure entry - it can interfere
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

    // MARK: - UIKeyInput Override (more reliable than delegate)

    override func insertText(_ text: String) {
        print("KeyboardTextField: insertText called with '\(text)'")
        for char in text {
            print("KeyboardTextField: sending character '\(char)' (ASCII: \(char.asciiValue ?? 0))")
            sendCharacter(char)
        }
        // Don't call super - we don't want text in the field
    }

    override func deleteBackward() {
        print("KeyboardTextField: deleteBackward called")
        keyboardEventHandler?(KeyEvent(key: KeyEvent.backspace, isPressed: true))
        keyboardEventHandler?(KeyEvent(key: KeyEvent.backspace, isPressed: false))
        // Don't call super
    }

    // MARK: - UITextFieldDelegate (backup)

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        // This is now a backup - insertText should handle most cases
        print("KeyboardTextField: shouldChangeCharacters - string='\(string)' (backup)")
        return false  // Prevent text from being added since insertText handles it
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        // Return/Enter key
        print("KeyboardTextField: Return key pressed")
        keyboardEventHandler?(KeyEvent(key: KeyEvent.returnKey, isPressed: true))
        keyboardEventHandler?(KeyEvent(key: KeyEvent.returnKey, isPressed: false))
        return false
    }

    @objc private func textDidChange() {
        // Clear any text that somehow got added
        if (text?.count ?? 0) > 0 {
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
        guard let scalar = char.unicodeScalars.first else { return }
        let charCode = UInt32(scalar.value)

        // Use Unicode keysym format: 0x01000000 + unicode value
        // This is more widely compatible with modern VNC servers
        let keySym = 0x01000000 | charCode

        print("KeyboardTextField: sendCharacter '\(char)' -> keySym=0x\(String(keySym, radix: 16))")

        keyboardEventHandler?(KeyEvent(key: keySym, isPressed: true))

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
            self?.keyboardEventHandler?(KeyEvent(key: keySym, isPressed: false))
        }
    }

    // MARK: - Key Mapping

    private func isModifierKey(_ keySym: UInt32) -> Bool {
        return keySym == KeyEvent.shift ||
               keySym == KeyEvent.control ||
               keySym == KeyEvent.alt ||
               keySym == KeyEvent.command
    }

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

        // Special keys
        switch char {
        case "\n", "\r": return KeyEvent.returnKey
        case "\t": return KeyEvent.tab
        default: break
        }

        // For all printable ASCII characters (0x20-0x7E), send the character code directly
        // VNC/X11 keysyms for Latin-1 match Unicode/ASCII values
        if scalar >= 0x20 && scalar <= 0x7E {
            return scalar
        }

        return nil
    }
}
