# MacRemote (Screen Control)

iPad app to control Mac using VNC protocol - connects to Mac's built-in Screen Sharing.

## Project Structure

```
MacRemote/
├── App/
│   ├── MacRemoteApp.swift      # App entry point
│   └── ContentView.swift       # Root view
├── Core/
│   ├── Discovery/
│   │   ├── BonjourBrowser.swift    # mDNS service discovery
│   │   └── DiscoveredMac.swift     # Discovered Mac model
│   ├── Network/
│   │   ├── AdaptiveQuality.swift   # Network quality adaptation
│   │   └── ConnectionManager.swift # Connection handling
│   └── VNC/
│       ├── RFBProtocol.swift       # VNC/RFB protocol definitions
│       ├── RFBAuth.swift           # VNC authentication (DES)
│       ├── FrameBuffer.swift       # Screen buffer management
│       ├── VNCClient.swift         # Main VNC client
│       └── ZlibDecompressor.swift  # ZRLE decoder (not yet working)
├── Features/
│   ├── Home/
│   │   └── HomeView.swift          # Main screen with Bonjour discovery
│   ├── Session/
│   │   ├── SessionView.swift       # Active connection view
│   │   └── ScreenCanvasView.swift  # Screen display & input handling
│   ├── Connect/
│   │   └── AddConnectionView.swift # Manual connection entry
│   └── Settings/
│       └── SettingsView.swift      # App settings
├── Models/
│   ├── SavedConnection.swift       # SwiftData model for saved connections
│   └── InputEvent.swift            # Mouse/keyboard event models
├── Utilities/
│   └── Constants.swift             # App constants
└── Resources/
    └── Assets.xcassets             # App icons and assets
```

## Build & Run

```bash
# Build for iPad
xcodebuild -project MacRemote.xcodeproj -scheme MacRemote -destination 'platform=iOS,name=Hitesh\'s iPad' build

# Install on device
xcrun devicectl device install app --device <DEVICE_ID> <PATH_TO_APP>

# Launch
xcrun devicectl device process launch --device <DEVICE_ID> com.macremote.app
```

## Requirements

- iOS/iPadOS 17.0+
- Mac with Screen Sharing enabled
- VNC password must be enabled on Mac:
  - System Settings → General → Sharing
  - Click (i) next to Screen Sharing
  - Enable "VNC viewers may control screen with password"
  - Set a password

## Known Issues

### Critical
1. ~~**Keyboard input not working**~~ **FIXED** - Now uses UIKit-based `KeyboardInputView` that properly handles both software and hardware keyboard input via UIKeyInput protocol and `pressesBegan/pressesEnded` responder methods. SwiftUI's `.onKeyPress()` has known bugs with iPad hardware keyboards.

2. **Touch/Mouse input unreliable** - Gestures sometimes don't register. May need to verify coordinate conversion between iPad touch and Mac screen coordinates.

### High Priority
3. **ZRLE encoding not working** - Decoder implemented but produces black screen. Currently disabled, using Raw encoding only (less efficient but works).

4. **Multi-monitor display offset** - When using "Primary" or "Secondary" display mode, mouse coordinates may not map correctly to the selected display.

### Medium Priority
5. **No clipboard sync** - ServerCutText messages are received but ignored. No client-to-server clipboard support.

6. **No Apple Remote Desktop authentication** - Only VNC Auth (type 2) is supported. ARD auth (type 30) and macOS auth (type 35) require complex Diffie-Hellman implementation.

7. **Connection drops not handled gracefully** - Network interruptions may leave app in inconsistent state.

### Low Priority
8. **No Tight encoding** - Would improve performance on slow networks.

9. **No cursor shape updates** - Remote cursor not shown, using local cursor indicator instead.

10. **Trackpad mode cursor position** - Cursor can drift outside visible area.

## VNC Protocol Notes

- Uses RFB 3.8 protocol (Apple uses 3.889 variant)
- Security types: None (1), VNC Auth (2), Apple ARD (30), macOS Auth (35)
- Encodings supported: Raw (0), CopyRect (1)
- Encodings planned: ZRLE (16), Tight (7)

## Testing Checklist

- [ ] Bonjour discovery finds Mac
- [ ] Manual IP connection works
- [ ] VNC password authentication works
- [ ] Screen displays correctly
- [ ] Single tap = click
- [ ] Double tap = double click
- [ ] Drag gesture works
- [ ] Pinch to zoom works
- [ ] Keyboard input works
- [ ] Modifier keys (Cmd, Opt, Ctrl, Shift) work
- [ ] Multi-monitor display selection works
- [ ] Disconnect/reconnect works
