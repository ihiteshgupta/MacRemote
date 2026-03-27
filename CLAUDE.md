# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

MacRemote is an iPad app to remotely control a Mac using the VNC protocol. Connects to Mac's built-in Screen Sharing feature.

## Tech Stack

- **Language**: Swift 5.9+
- **UI**: SwiftUI (views) + UIKit (keyboard input bridging via `UIViewRepresentable`)
- **Persistence**: SwiftData (`@Model` on `SavedConnection`, `ModelContainer` at app root)
- **Networking**: Network.framework (`NWConnection` for TCP, `NWBrowser` for Bonjour mDNS)
- **Security**: Security.framework (Keychain for per-host VNC passwords)
- **Compression**: Compression.framework (zlib decompression for ZRLE encoding)
- **Reactive**: Combine (`ObservableObject` / `@Published` throughout)
- **Minimum OS**: iPadOS 17.0
- **Bundle ID**: `com.macremote.app`

## Project Structure

```
MacRemote/
├── App/
│   ├── MacRemoteApp.swift      # @main, SwiftData ModelContainer setup
│   └── ContentView.swift       # Root navigation
├── Core/
│   ├── VNC/
│   │   ├── VNCClient.swift     # Connection lifecycle, state machine
│   │   ├── RFBProtocol.swift   # RFB 3.8 types, encoding definitions
│   │   ├── RFBAuth.swift       # VNC DES auth + ARD Diffie-Hellman auth
│   │   ├── FrameBuffer.swift   # RGBA pixel buffer → UIImage
│   │   └── ZlibDecompressor.swift  # Zlib + ZRLE tile decoder
│   ├── Network/
│   │   ├── ConnectionManager.swift  # Facade: VNCClient + SwiftData + quality
│   │   └── AdaptiveQuality.swift    # Latency-based quality level adjustment
│   └── Discovery/
│       ├── BonjourBrowser.swift     # NWBrowser mDNS service discovery
│       └── DiscoveredMac.swift      # Discovered service model
├── Features/
│   ├── Home/HomeView.swift          # Saved connections list
│   ├── Connect/AddConnectionView.swift  # Manual connection form
│   ├── Session/
│   │   ├── SessionView.swift        # Active session, auth prompts, toolbar
│   │   ├── ScreenCanvasView.swift   # Touch → mouse, pinch-zoom, gesture handling
│   │   └── KeyboardInputView.swift  # UIKit keyboard bridge (UITextField wrapper)
│   └── Settings/SettingsView.swift  # AppStorage-backed settings sheet
├── Models/
│   ├── SavedConnection.swift    # SwiftData @Model (host, port, name, lastConnected)
│   └── InputEvent.swift        # MouseEvent, KeyEvent, InputMode, DisplayMode enums
├── Utilities/
│   ├── Constants.swift         # AppConstants (ports, timeouts, thresholds)
│   └── KeychainHelper.swift    # Per-host VNC password CRUD via Keychain
└── Resources/Assets.xcassets

MacRemoteTests/
├── VNC/
│   ├── RFBProtocolTests.swift  # Pixel format, ServerInit, encoding parsing
│   └── FrameBufferTests.swift  # Pixel buffer update regions
├── Network/
│   └── AdaptiveQualityTests.swift  # Quality level adjustment logic
├── Helpers/
│   └── CoordinateConversionTests.swift  # Touch→remote coordinate math
└── Mocks/
    └── MockNetworkConnection.swift

MacRemoteUITests/
├── MacRemoteUITests.swift
└── SessionUITests.swift
```

## Build & Run

```bash
# Build for iPad Simulator
xcodebuild -project MacRemote.xcodeproj -scheme MacRemote -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' build

# Build for physical iPad
xcodebuild -project MacRemote.xcodeproj -scheme MacRemote -destination 'platform=iOS,name=Hitesh'\''s iPad' build

# Run unit tests (simulator)
xcodebuild test -project MacRemote.xcodeproj -scheme MacRemote -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)'

# Run UI tests only
xcodebuild test -project MacRemote.xcodeproj -scheme MacRemote -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' -only-testing MacRemoteUITests

# List connected devices
xcrun devicectl list devices

# Install on device (get DEVICE_ID from above command)
xcrun devicectl device install app --device <DEVICE_ID> build/Build/Products/Debug-iphoneos/MacRemote.app

# Launch on device
xcrun devicectl device process launch --device <DEVICE_ID> com.macremote.app
```

## Architecture

### Data Flow

```
iPad Touch/Keyboard → ScreenCanvasView/KeyboardInputView
                    → MouseEvent/KeyEvent structs
                    → VNCClient.sendMouseEvent/sendKeyEvent
                    → RFB protocol encoding
                    → TCP to Mac Screen Sharing

Mac Screen → VNC framebuffer update
           → VNCClient.receiveFramebufferUpdate
           → FrameBuffer.updateRegion
           → UIImage → ScreenCanvasView
```

### Core Components

**VNC Protocol Stack** (`Core/VNC/`)
- `VNCClient.swift` - Main client orchestrating connection lifecycle, state machine (disconnected → connecting → handshaking → authenticating → connected), NWConnection TCP handling
- `RFBProtocol.swift` - RFB 3.8 protocol definitions: message types, encodings (Raw, CopyRect, DesktopSize), pixel formats (RGB888, RGB565)
- `RFBAuth.swift` - VNC authentication (DES challenge-response with bit-reversed keys) and ARD auth (Diffie-Hellman key exchange, AES-128-ECB credentials)
- `FrameBuffer.swift` - RGBA pixel buffer with region updates and CopyRect support, renders to UIImage via CGContext

**Input Handling** (`Features/Session/`)
- `ScreenCanvasView.swift` - Touch → mouse coordinate conversion (accounts for scale, offset, multi-monitor), gesture recognition (tap, double-tap, drag, pinch)
- `KeyboardInputView.swift` - UIKit-based UITextField wrapper using `UIKeyInput` protocol and `pressesBegan/pressesEnded` for reliable hardware keyboard support (SwiftUI's `.onKeyPress()` has iPad bugs)
- `SessionView.swift` - Session management, auth prompts, floating toolbar with modifier keys

**Network Discovery** (`Core/Discovery/`)
- `BonjourBrowser.swift` - NWBrowser for `_rfb._tcp` mDNS service discovery, resolves endpoints to IP addresses

**Network Layer** (`Core/Network/`)
- `ConnectionManager.swift` - `@MainActor ObservableObject` facade that owns `VNCClient` + `AdaptiveQuality`; exposes `connect/disconnect/authenticate` and SwiftData CRUD for `SavedConnection`
- `AdaptiveQuality.swift` - Tracks rolling 20-sample latency history and frame drop rate; auto-adjusts `QualityLevel` (high/medium/low/minimum) every 2 seconds when in `.auto` mode; supports manual override via `QualityMode`

**Models** (`Models/`)
- `SavedConnection.swift` - SwiftData `@Model` persisting `host`, `port`, `name`, `lastConnected`, `isManual`; default port 5900
- `InputEvent.swift` - `MouseEvent` (x/y/buttonMask), `KeyEvent` (X11 keysym + isPressed), `MouseButton` bitmask enum, `InputMode` (touch/trackpad), `DisplayMode` (primary/secondary/all)

**Utilities** (`Utilities/`)
- `KeychainHelper.swift` - Static helper for per-host VNC password storage under service `com.macremote.vnc` with `kSecAttrAccessibleWhenUnlocked`
- `Constants.swift` - `AppConstants` with default port (5900), Bonjour service type (`_rfb._tcp`), connection/handshake timeouts, quality thresholds

**Feature Views** (`Features/`)
- `HomeView.swift` - Lists saved connections (sorted by `lastConnected`) and Bonjour-discovered Macs; entry point to sessions
- `AddConnectionView.swift` - Manual connection form (host, port, name)
- `SettingsView.swift` - Sheet with `@AppStorage`-persisted settings: quality mode, input mode, scroll speed, trackpad sensitivity, auto-reconnect, keep-awake, quality badge toggle

### Key Implementation Details

**VNC Authentication** - Two flows:
1. VNC Auth (type 2): Server sends 16-byte challenge → client encrypts with DES using bit-reversed password key → returns 16-byte response
2. ARD Auth (type 30): Diffie-Hellman exchange → MD5 of shared secret as AES key → encrypt 128-byte username+password block

**Coordinate System** - iPad touch coordinates must be converted to remote screen coordinates accounting for:
- Aspect ratio fitting (letterboxing)
- Current zoom scale and pan offset
- Multi-monitor display offset (displayOffsetX for secondary monitor)

**Keyboard Events** - Uses X11 keysyms (e.g., 0xff0d for Return, 0xffe1 for Shift). Hardware keyboard captured via `pressesBegan/pressesEnded`; software keyboard via `UITextFieldDelegate.shouldChangeCharacters`.

### Persisted Settings (`@AppStorage` keys)

| Key | Type | Default | Purpose |
|-----|------|---------|---------|
| `qualityMode` | String | `"Auto"` | `QualityMode` raw value |
| `defaultInputMode` | String | `"Touch"` | `InputMode` raw value |
| `scrollSpeed` | Double | 1.0 | Scroll multiplier (0.25–2.0) |
| `trackpadSensitivity` | Double | 1.0 | Trackpad multiplier (0.5–2.0) |
| `autoReconnect` | Bool | true | Reconnect on drop |
| `keepScreenAwake` | Bool | true | Disable iPad idle timer during session |
| `showQualityBadge` | Bool | true | Quality indicator overlay |

## Conventions

- All `ObservableObject` view models are `@MainActor final class`
- Network I/O goes through `NWConnection` (Network.framework) — no URLSession or BSD sockets
- Passwords are never stored in SwiftData; only in Keychain (keyed by host string)
- UI is SwiftUI-first; UIKit used only where SwiftUI has known iPad bugs (keyboard input)
- No third-party dependencies — pure Apple frameworks only

## Requirements

- iOS/iPadOS 17.0+
- Mac with Screen Sharing enabled and VNC password set:
  - System Settings → General → Sharing → Screen Sharing → (i)
  - Enable "VNC viewers may control screen with password"

## Known Issues

1. **Touch/Mouse input unreliable** - Gestures sometimes don't register; coordinate conversion may be off
2. **ZRLE encoding broken** - Decoder produces black screen; using Raw encoding only
3. **Multi-monitor display offset** - Mouse coordinates may not map correctly for non-primary displays
4. **No ARD auth in practice** - Pure Swift bignum too slow for 1024-bit DH; prefer VNC auth
5. **No clipboard sync** - ServerCutText ignored, no client-to-server support

## VNC Protocol Notes

- RFB version: 3.8 (Apple uses 3.889 variant)
- Security types: None (1), VNC Auth (2), Apple DH/ARD (30)
- Encodings: Raw (0), CopyRect (1), ZRLE (16), DesktopSize (-223)
- JPEG quality pseudo-encodings: `-32` (q0) to `-23` (q9) → `RFBEncoding.jpegQuality(_:)`
- Compression level pseudo-encodings: `-256` (level 0) to `-247` (level 9)
- Pixel format: 32-bit RGBA (RGB888); RGB565 defined but not actively used
- ZRLE tile size: 64×64 pixels; subtypes: raw (0), solid (1), packed palette (2–16), plain RLE (128), palette RLE (130–255)
