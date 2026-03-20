# Glassdeck

A **Liquid Glass** SSH client for iPhone — powered by GhosttyKit terminal emulation, USB-C external display support, and on-device AI assistance.

> Built for iOS 26 · iPhone 15 Pro · SwiftUI · Sideloading

## Features

### 🔮 Liquid Glass Design
Native iOS 26 Liquid Glass UI with `.glassEffect()` floating toolbars, morphing `GlassEffectContainer` controls, and system-native translucency throughout.

### 🖥️ USB-C External Display
Plug into an external monitor via USB-C and get a dedicated full-screen terminal view. Route different SSH sessions to different displays.

### ⌨️ External Hardware Input
- **Keyboard**: Full hardware keyboard support with Ctrl/Alt/Meta modifiers, arrow keys, function keys
- **Mouse/Trackpad**: Cursor visibility, click-to-position, scroll, SGR mouse reporting
- **Touch**: Software keyboard fallback with tap-to-click

### 🤖 On-Device AI Assistant (Foundation Models)
Entirely private, no cloud — runs on iPhone 15 Pro's neural engine:
- **Explain errors** — Select terminal output, AI explains what went wrong
- **Suggest commands** — Natural language → shell command with risk assessment
- **Summarize output** — Long command output distilled to key points

### 🔐 SSH Core
- **SwiftNIO SSH** — Pure Swift, Apple-backed SSH transport
- **Authentication** — Password + SSH key (Ed25519, RSA)
- **Keychain storage** — Private keys secured in iOS Keychain
- **Multi-session** — Multiple concurrent SSH sessions with tab switching

## Tech Stack

| Component | Technology |
|-----------|-----------|
| UI | SwiftUI (iOS 26) + Liquid Glass |
| Terminal | GhosttyKit (libghostty) + Metal 4 |
| SSH | SwiftNIO SSH + swift-ssh-client |
| AI | Foundation Models framework |
| Persistence | SwiftData |
| Min iOS | 26 |

## Project Structure

```
Glassdeck/
├── App/          # App entry, delegates, Info.plist
├── Scenes/       # Main + external display scene delegates
├── Views/        # SwiftUI views (connection list, terminal, AI overlay)
├── Terminal/     # Terminal engine protocol + configuration
├── SSH/          # Connection manager, auth, key management, PTY bridge
├── AI/           # Foundation Models integration
├── Input/        # Keyboard, mouse/trackpad handlers
├── Models/       # Data models, stores, session management
└── Resources/    # Assets, launch screen
```

## Building

Requires **Xcode 26** with iOS 26 SDK.

```bash
# Clone
git clone https://github.com/atjsh/Glassdeck.git

# Open in Xcode
open Package.swift

# Build for iPhone 15 Pro (arm64)
# Select your device and hit Cmd+R
```

### GhosttyKit Setup
The terminal engine requires building GhosttyKit.xcframework from [Ghostty](https://github.com/ghostty-org/ghostty) source:
1. Install Zig toolchain
2. Build for iOS arm64 target
3. Place `GhosttyKit.xcframework` in `Frameworks/`

## License

MIT
