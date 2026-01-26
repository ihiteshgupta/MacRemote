# MacRemote - iPad VNC Client Design

## Overview

iPad app to control Mac using VNC protocol. Connects to Mac's built-in Screen Sharing via Bonjour discovery (local) or manual IP (remote).

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        iPad App                                  │
├─────────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐ │
│  │ Discovery   │  │ Connection  │  │ UI Layer                │ │
│  │ Module      │  │ Manager     │  │ - Screen View           │ │
│  │ - Bonjour   │  │ - VNC Client│  │ - Touch Handler         │ │
│  │ - Manual IP │  │ - TLS       │  │ - Input Mode Toggle     │ │
│  └─────────────┘  └─────────────┘  │ - Mini Keyboard         │ │
│                                     └─────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
                              │
                         VNC Protocol
                        (Port 5900)
                              │
┌─────────────────────────────────────────────────────────────────┐
│                    Mac (Built-in Screen Sharing)                │
└─────────────────────────────────────────────────────────────────┘
```

**Key decisions:**
- No Mac companion app needed - uses macOS built-in Screen Sharing
- Standard VNC protocol (RFB 3.8) - compatible with any VNC server
- Single iPad app contains discovery, VNC client, and UI

## Connection Flow

### Local Network (Bonjour)

1. Browse for `_rfb._tcp.local` service
2. Receive response with hostname and port
3. TCP connect to resolved IP:5900
4. VNC handshake + authentication
5. Screen streaming begins

### Remote (Manual IP)

1. User enters IP address or hostname
2. Resolve hostname if needed
3. TCP connect to IP:5900
4. VNC handshake + authentication
5. Stream with adaptive quality

### Saved Connections

- App stores recently connected Macs
- Each entry: Name, IP/hostname, port, last connected
- Quick reconnect from home screen

## Input Handling

### Mode Toggle

Bottom toolbar with [Touch] [Trackpad] toggle buttons.

### Touch Mode (Default)

| Gesture | Action |
|---------|--------|
| Tap | Left click at tap location |
| Two-finger tap | Right click |
| Tap and hold | Click and hold (drag start) |
| Drag | Move mouse + hold button |
| Two-finger drag | Scroll |
| Pinch | Zoom viewport (local only) |
| Double tap | Double click |

### Trackpad Mode

| Gesture | Action |
|---------|--------|
| One finger move | Move cursor (relative) |
| Tap | Left click at cursor position |
| Two-finger tap | Right click |
| Two-finger drag | Scroll |
| Three-finger drag | Drag windows |

### Keyboard (Minimal)

Toolbar: `[Esc] [Tab] [⌘] [⌥] [⌃] [⇧] [←][→][↑][↓] [⏎]`

- Modifier keys hold until next key press
- Tap [Kbd] button for iOS system keyboard

## Adaptive Quality

### Levels

| Level | Resolution | Encoding | Target Latency |
|-------|------------|----------|----------------|
| High | Native | ZRLE + Tight | <50ms |
| Medium | 50% scale | JPEG 80% | 50-150ms |
| Low | 25% scale | JPEG 50% | 150-300ms |
| Minimum | 25% grayscale | JPEG 30% | >300ms |

### Adaptation Logic

Every 2 seconds measure:
- Round-trip latency
- Frame decode time
- Frames dropped/delayed

Rules:
- Latency < 50ms && no drops → increase quality
- Latency > 150ms || drops > 10% → decrease quality
- Else → maintain current

### User Override

Settings allow forcing specific quality level or "Auto" (recommended).

## UI Screens

### Home Screen

- Lists nearby Macs (Bonjour discovery)
- Shows recent connections
- "Add Manual Connection" button
- Settings gear icon

### Session Screen

- Full-screen Mac display
- Bottom toolbar: mode toggle, keyboard, disconnect
- Quality indicator badge
- Pinch to zoom viewport

### Settings Screen

- Quality mode (Auto/High/Medium/Low)
- Default input mode (Touch/Trackpad)
- Scroll speed slider
- Trackpad sensitivity slider
- Auto-reconnect toggle
- Keep screen awake toggle

## Tech Stack

| Component | Technology |
|-----------|------------|
| Language | Swift 5.9+ |
| UI | SwiftUI |
| Networking | Network.framework |
| VNC | Custom RFB 3.8 implementation |
| Image Decoding | CoreGraphics, VideoToolbox |
| Storage | SwiftData |
| Target | iPadOS 16.0+ |

## Project Structure

```
MacRemote/
├── MacRemote.xcodeproj
├── MacRemote/
│   ├── App/
│   │   ├── MacRemoteApp.swift
│   │   └── ContentView.swift
│   ├── Features/
│   │   ├── Home/
│   │   ├── Session/
│   │   ├── Connect/
│   │   └── Settings/
│   ├── Core/
│   │   ├── VNC/
│   │   ├── Discovery/
│   │   └── Network/
│   ├── Models/
│   ├── Utilities/
│   └── Resources/
└── MacRemoteTests/
```

## Implementation Order

1. Project setup + basic UI navigation
2. Bonjour discovery
3. VNC protocol (handshake, auth)
4. Screen rendering (framebuffer)
5. Touch input (mouse events)
6. Trackpad mode
7. Keyboard toolbar
8. Adaptive quality
9. Saved connections (SwiftData)
10. Settings & polish
