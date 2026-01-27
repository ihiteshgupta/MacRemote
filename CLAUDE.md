# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

MacRemote is an iPad app to remotely control a Mac using the VNC protocol. Connects to Mac's built-in Screen Sharing feature.

## Build & Run

```bash
# Build for iPad Simulator
xcodebuild -project MacRemote.xcodeproj -scheme MacRemote -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' build

# Build for physical iPad
xcodebuild -project MacRemote.xcodeproj -scheme MacRemote -destination 'platform=iOS,name=Hitesh'\''s iPad' build

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

### Key Implementation Details

**VNC Authentication** - Two flows:
1. VNC Auth (type 2): Server sends 16-byte challenge → client encrypts with DES using bit-reversed password key → returns 16-byte response
2. ARD Auth (type 30): Diffie-Hellman exchange → MD5 of shared secret as AES key → encrypt 128-byte username+password block

**Coordinate System** - iPad touch coordinates must be converted to remote screen coordinates accounting for:
- Aspect ratio fitting (letterboxing)
- Current zoom scale and pan offset
- Multi-monitor display offset (displayOffsetX for secondary monitor)

**Keyboard Events** - Uses X11 keysyms (e.g., 0xff0d for Return, 0xffe1 for Shift). Hardware keyboard captured via `pressesBegan/pressesEnded`; software keyboard via `UITextFieldDelegate.shouldChangeCharacters`.

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
- Security types supported: None (1), VNC Auth (2)
- Encodings: Raw (0), CopyRect (1), DesktopSize (-223)
- Pixel format: 32-bit RGBA (RGB888)
