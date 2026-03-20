# Glassdeck

**A native iOS 26 SSH client for iPhone 15 Pro** — powered by GhosttyKit terminal emulation, USB-C external display support, hardware input, and on-device AI assistance.

> Built for iOS 26 · iPhone 15 Pro · SwiftUI · Liquid Glass · Sideloading

---

## Features

### 🖥️ Terminal
- **GhosttyKit** — GPU-accelerated terminal rendering via Metal 4
- Full **xterm-256color** support with scrollback buffer
- 8 built-in color schemes (Solarized, Dracula, Tokyo Night, etc.)
- Configurable fonts and cursor styles
- Swappable backend: GhosttyKit ↔ SwiftTerm via `TerminalEngine` protocol

### 🔐 SSH
- **Password & SSH key** authentication (Ed25519, P256/ECDSA)
- Key generation, import, and Keychain-secure storage
- OpenSSH PEM key parsing
- Powered by **SwiftNIO SSH** + **swift-ssh-client** + **swift-crypto**
- Actor-isolated connection manager with async/await

### 📺 External Display (USB-C)
- Dedicated full-screen terminal on external monitors
- Route any session to the external display
- Independent resolution scaling per display
- Minimal glass-effect HUD overlay on external screen

### ⌨️ Hardware Input
- **External keyboard**: Full `UIKeyCommand` mapping — Ctrl+a-z, arrows with modifiers, function keys, escape sequences
- **Mouse/trackpad**: `UIPointerInteraction` with SGR mouse encoding for terminal apps (vim, tmux, etc.)
- **Touch**: Software keyboard fallback with tap-to-click

### 🤖 AI Assistant (Foundation Models)
- **Explain errors** — select terminal output, get AI explanation with severity
- **Suggest commands** — natural language → shell command with risk assessment
- **Summarize output** — condense long command output to key points
- Fully on-device via `SystemLanguageModel.default` — no cloud, fully private
- `@Generable` structs for structured AI responses

### 🪟 iOS 26 Liquid Glass Design
- Floating `GlassEffectContainer` toolbar with tinted action buttons
- Glass-effect connection status pill overlays
- Enhanced `TabView` with minimize-on-scroll session tabs
- Section-indexed connection list with alphabetical jump-bar
- Native SwiftUI `WebView` for in-app SSH documentation

---

## Architecture

```
SwiftUI App (iOS 26 Liquid Glass)
├── ConnectionListView — saved hosts with section indexes
├── TerminalContainerView — GhosttySurface + floating glass toolbar
├── SessionTabView — multi-session tabs (minimize-on-scroll)
├── ExternalTerminalView — USB-C external monitor scene
└── AIOverlayView — Foundation Models AI assistant sheet

SSH Layer (Swift 6 actors)
├── SSHConnectionManager — connection lifecycle (actor-isolated)
├── SSHAuthenticator — password + key auth (NIOSSHPrivateKey, CryptoKit)
├── SSHPTYBridge — SSH shell ↔ terminal I/O bridge (AsyncThrowingStream)
├── SSHKeyManager — Keychain CRUD for SSH keys
└── SSHSessionModel — per-session state tracking

Terminal Engine
├── GhosttyTerminalView — UIViewRepresentable wrapping CAMetalLayer surface
├── GhosttyApp — ghostty_app_t lifecycle + runtime callbacks
├── TerminalEngine protocol — swappable backend (GhosttyKit ↔ SwiftTerm)
└── TerminalConfiguration — color schemes, fonts, cursor settings

Input Handling
├── KeyboardInputHandler — UIKeyCommand responder chain
├── PointerInputHandler — UIPointerInteraction + SGR mouse encoding
└── InputCoordinator — unified input dispatch to terminal
```

---

## Tech Stack

| Component | Technology |
|-----------|-----------|
| UI | SwiftUI (iOS 26) + Liquid Glass |
| Terminal | GhosttyKit (libghostty) + Metal 4 |
| SSH | SwiftNIO SSH + swift-ssh-client |
| Crypto | swift-crypto (Ed25519, P256) |
| AI | Foundation Models framework |
| Persistence | UserDefaults (SwiftData planned) |
| Min iOS | 26 |
| Min Device | iPhone 15 Pro (A17 Pro) |

---

## Building

Requires **Xcode 26** beta with iOS 26 SDK.

```bash
# Clone
git clone https://github.com/atjsh/Glassdeck.git
cd Glassdeck

# Resolve SPM dependencies
swift package resolve

# Open in Xcode 26
open Package.swift

# Build for iPhone 15 Pro (arm64) — Cmd+R
```

### GhosttyKit Setup (Optional)
The terminal engine uses GhosttyKit for GPU-accelerated rendering. Without it, the app falls back gracefully (placeholder terminal view).

To build GhosttyKit.xcframework from [Ghostty](https://github.com/ghostty-org/ghostty):
1. Install Zig toolchain
2. `./macos/build.nu --scheme Ghostty-iOS --configuration Release --action build`
3. Place `GhosttyKit.xcframework` in `Frameworks/`
4. Uncomment `import GhosttyKit` in `GhosttyTerminalView.swift`

### SPM Dependencies
- [swift-nio-ssh](https://github.com/apple/swift-nio-ssh) — SSH transport
- [swift-ssh-client](https://github.com/gaetanzanella/swift-ssh-client) — high-level SSH API
- [swift-crypto](https://github.com/apple/swift-crypto) — Ed25519/P256 key operations

---

## Project Structure

```
Glassdeck/
├── App/          — @main entry, AppDelegate, Info.plist
├── Scenes/       — Main + external display scene delegates
├── Views/        — SwiftUI views (connections, terminal, settings, AI)
├── Terminal/     — GhosttyKit integration, terminal protocol
├── SSH/          — Connection manager, auth, PTY bridge, key manager
├── AI/           — Foundation Models assistant, overlay UI
├── Input/        — Keyboard, mouse/trackpad handlers
├── Models/       — ConnectionProfile, AppSettings, SessionManager
└── Resources/    — Assets, launch screen
```

---

## License

MIT
