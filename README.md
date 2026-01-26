# MacRemote (Screen Control)

An iPad app to remotely control your Mac using the VNC protocol. Works with Mac's built-in Screen Sharing feature.

![Platform](https://img.shields.io/badge/platform-iPadOS%2017%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![License](https://img.shields.io/badge/license-MIT-green)

## Features

- **Bonjour Discovery** - Automatically finds Macs on your local network with Screen Sharing enabled
- **Manual Connection** - Connect to any Mac via IP address (supports remote connections)
- **Touch Input** - Tap to click, drag to move, pinch to zoom
- **Trackpad Mode** - Relative cursor movement like a trackpad
- **Keyboard Support** - On-screen and hardware keyboard input
- **Modifier Keys** - Command, Option, Control, Shift buttons
- **Multi-Monitor** - Select primary, secondary, or all displays

## Screenshots

*Coming soon*

## Requirements

### iPad
- iPadOS 17.0 or later
- iPad (any model supporting iPadOS 17)

### Mac (Remote)
- macOS with Screen Sharing enabled
- **Important**: VNC password must be enabled:
  1. Open **System Settings** → **General** → **Sharing**
  2. Click the **(i)** button next to **Screen Sharing**
  3. Enable **"VNC viewers may control screen with password"**
  4. Set a password

## Installation

### From Source

1. Clone the repository:
   ```bash
   git clone https://github.com/anthropics/mac-remote.git
   cd mac-remote
   ```

2. Open in Xcode:
   ```bash
   open MacRemote.xcodeproj
   ```

3. Select your iPad as the run destination

4. Build and run (⌘R)

## Usage

1. **Launch the app** on your iPad
2. **Find your Mac** in the discovered devices list, or tap **+** to enter an IP manually
3. **Enter the VNC password** you set on your Mac
4. **Control your Mac!**
   - **Tap** = Click
   - **Double tap** = Double click
   - **Drag** = Click and drag
   - **Pinch** = Zoom in/out
   - **Triple tap** = Toggle toolbar

### Toolbar

- **Display** - Switch between primary/secondary/all monitors
- **Touch/Trackpad** - Toggle input mode
- **⌘ ⌥ ⌃ ⇧** - Modifier keys (sticky)
- **Keyboard** - Show/hide keyboard
- **X** - Disconnect

## Technical Details

- **Protocol**: VNC/RFB 3.8
- **Authentication**: VNC Auth (DES challenge-response)
- **Encodings**: Raw, CopyRect
- **Framework**: SwiftUI, Network.framework, SwiftData

## Known Issues

See [CLAUDE.md](CLAUDE.md) for detailed known issues and development notes.

Key issues:
- Keyboard input may not work reliably with hardware keyboards
- ZRLE encoding disabled (using Raw encoding for now)
- Only VNC password authentication supported (not Apple Remote Desktop auth)

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

MIT License - see [LICENSE](LICENSE) for details.

## Acknowledgments

- Built with SwiftUI for iPadOS
- Uses Apple's Network.framework for TCP connections
- VNC protocol implementation based on [RFB Protocol Specification](https://github.com/rfbproto/rfbproto)
