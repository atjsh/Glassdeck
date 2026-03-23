# Glassdeck

![Glassdeck Terminal Screenshot](.github/media/glassdeck-simulator.png)

An iOS 26 SSH client powered by a real terminal engine.

[한국어](README-ko.md)

## Features

**Terminal & Shell**
*   **SSH terminal sessions**: Full VT100/xterm emulation via libghostty-vt (GhosttyTerminal, GhosttyRenderState, key/mouse encoders).
*   **PTY shell**: Bidirectional async bridge (SSHPTYBridge actor) with runtime resize.
*   **Glassdeck-owned Metal renderer**: Core Image based, does NOT depend on GhosttyKit.
*   **Render coalescing**: `scheduleRender()` with UIKit `layoutSubviews` batching to consolidate rapid state changes.
*   **Local scrollback**: 10,000 lines default, configurable 1K–100K, Metal-accelerated viewport scrolling.

**Connectivity**
*   **Auto-reconnection**: Exponential backoff (5 attempts, 1–30s delay, 2× multiplier), transient vs permanent failure classification.
*   **Session persistence & restore**: JSON snapshots to UserDefaults, auto-restore on foreground, optional Core Location background keep-alive.
*   **Connection profiles**: CRUD with JSON persistence, password or SSH key auth, notes, last-connected date.
*   **TOFU host key verification**: Keychain-backed known_hosts, SHA-256 fingerprints, auto-trust new / reject mismatch.

**Input & Hardware**
*   **Hardware keyboard**: 90+ UIKeyCommands (Ctrl+letter, arrows, function keys, Tab, Escape, PageUp/Down, Home/End).
*   **Touch/pointer input**: UIPointerInteraction with I-beam cursor, full SGR mouse reporting, drag tracking.
*   **IME support** (Experimental): UITextInput with marked text / composing flag.

**Advanced Tools**
*   **SFTP**: Browse, preview (UTF-8, 8KB default), upload, delete, download, iOS share sheet export.
*   **External display routing**: Dedicated scene delegate, remote pointer overlay, display routing picker.
*   **Terminal settings**: Per-display-target profiles (iPhone vs external monitor), 8 color schemes, font size, cursor style, bell.

## Repository Layout

```
Glassdeck/
├── Glassdeck/               iOS app: SwiftUI views, UIKit terminal surface, input handling
│   ├── App/                 App entry, environment, delegates, animation demo
│   ├── Input/               Keyboard, pointer, IME input coordination
│   ├── Models/              Session management, persistence, credentials, background keep-alive
│   ├── Remote/              External display geometry, remote trackpad coordination
│   ├── Scenes/              Main + external display scene delegates
│   ├── SSH/                 SSH session observable model
│   ├── Terminal/            GhosttySurface UIView, Metal renderer, SwiftUI wrapper
│   ├── Views/               All SwiftUI views (connections, terminal, SFTP, settings, etc.)
│   └── Resources/           Assets.xcassets, AppIcon.icon
├── GlassdeckCore/           Shared library — the single source of truth for SSH, terminal, models
│   ├── Models/              ConnectionProfile, ConnectionStore, AppSettings, RemoteControlMode
│   ├── SSH/                 SSHConnectionManager, SFTPManager, SSHPTYBridge, SSHAuthenticator,
│   │                        HostKeyVerifier, SSHReconnectManager, SSHKeyManager, etc.
│   └── Terminal/            GhosttyVTBindings, TerminalConfiguration (8 themes), TerminalIO, types
├── Frameworks/              Vendored CGhosttyVT.xcframework (static library, iOS device + simulator)
├── GlassdeckApp.xcodeproj/  Generated Xcode project (xcodegen from project.yml)
├── Scripts/                 Build, run, test automation
├── Tests/                   Unit, UI, integration, performance tests
├── Vendor/                  Forked swift-ssh-client dependency
├── Backlogs/                Code review findings and backlog tracking
├── Package.swift            SPM manifest (swift-tools-version: 6.2)
├── project.yml              xcodegen project definition
├── LICENSE                  MIT
├── README.md                English documentation
└── README-ko.md             Korean documentation
```

## Architecture

```
SwiftUI Views (ConnectionListView, SessionTabView, TerminalContainerView, SFTPBrowserView)
       │
SessionManager (orchestrator — @MainActor, 1082 lines)
SessionLifecycleCoordinator (lifecycle events, persistence, restore)
       │
  ┌────┼────────────────┐
  │    │                 │
SSH Layer       Terminal UI        Input Layer
SSHConnectionManager  GhosttySurface (UIView)  KeyboardInputHandler
SSHAuthenticator      Metal renderer (CI)      PointerInputHandler
SSHPTYBridge          GhosttyVTBindings        SessionKeyboardInputHost
HostKeyVerifier       TerminalConfiguration    RemoteTrackpadCoordinator
SSHReconnectManager
SFTPManager
       │
GlassdeckCore (shared library — only source of truth)
       │
External: libghostty-vt (C) · swift-ssh-client · SwiftNIO SSH · Swift Crypto
```

**Data flow**: User connects → SSHConnectionManager authenticates (password/key) → HostKeyVerifier checks TOFU → shell opened with PTY → SSHPTYBridge bridges shell↔terminal bidirectionally → GhosttyVTBindings processes VT sequences → GhosttySurface renders via Metal → Input flows back through VT encoding → shell.

## Terminal Engine

*   `GhosttyVTBindings.swift` (1,217 lines) — owns GhosttyTerminal, GhosttyRenderState, key encoder, mouse encoder.
*   `GhosttyVTTypes.swift` — pure Swift render projection and input descriptor types.
*   `GhosttyTerminalView.swift` — UIView + CAMetalLayer, Core Image Metal renderer, UIKit input bridge.
*   The renderer is Glassdeck-owned; this repo does NOT depend on GhosttyKit.
*   The VT C API is upstream WIP — vendored static xcframework must stay in sync.

## Vendored Ghostty Build

`Frameworks/CGhosttyVT.xcframework` — static library, committed in-repo.

Rebuild from local Ghostty checkout:
```bash
./Scripts/build-cghosttyvt.sh
```

**Defaults**:
*   Device: aarch64-ios
*   Simulator ARM64: aarch64-ios-simulator -Dcpu=apple_a17
*   Optional x86_64 simulator: INCLUDE_X86_64_SIMULATOR=true
*   SIMD: disabled (pure-static, device-safe)
*   Requires: Zig 0.15.2+, xcodebuild, Ghostty source

## Development

### Regenerate Xcode project

Generate Xcode project from `project.yml` via xcodegen:

```bash
./Scripts/generate-xcodeproj.sh
```

Also patches generated .pbxproj to wire local SPM packages + resources via `patch-local-package-product.py`.

### Run on simulator

Build & launch on iOS simulator:

```bash
./Scripts/run-ios-sim.sh
```

Launch in animation demo mode with test fixtures:

```bash
./Scripts/run-animation-demo-sim.sh
```

### Run tests

Unit tests on simulator:

```bash
./Scripts/test-ios-sim.sh
```

Live SSH integration tests vs Docker (auto-starts container, runs smoke checks first):

```bash
./Scripts/test-live-docker-ssh.sh
```

Terminal rendering performance tests vs live Docker SSH:

```bash
./Scripts/test-docker-render-perf.sh
```

Animation rendering performance tests (simulator):

```bash
./Scripts/test-animation-render-sim.sh
```

Animation rendering performance tests (device) - requires `DEVICE_ID`:

```bash
./Scripts/test-animation-render-device.sh
```

### Run UI tests

UI tests with screenshot capture + artifact export:

```bash
./Scripts/test-docker-ui-sim.sh
```

Verify animations visually render (screenshot diff):

```bash
./Scripts/test-animation-demo-visible-sim.sh
```

### Test utilities

Local web UI for reviewing screenshot test artifacts:

```bash
./Scripts/view-test-artifacts.py
```

### Common flags

| Flag | Description |
|------|-------------|
| `--clean`, `--rebuild` | Force fresh build graph |
| `--verbose` | Enable raw xcodebuild stream (`GLASSDECK_VERBOSE=1`) |
| `--only-testing TARGET` | Run specific test target |

### Simulator target

Default: `iPhone 17` on latest iOS runtime. Override with `SIMULATOR_ID=<udid>`.

### Build artifacts

*   `.build/TestLogs/` — raw xcodebuild logs
*   `.build/TestResults/` — xcresult bundles
*   `.build/TestArtifacts/docker-ui/` — UI screenshot exports

**Note**: If `project.yml` is newer than the project, scripts auto-regenerate via `generate-xcodeproj.sh`.

## Docker SSH Test Target

Canonical live test endpoint (replaces separate Raspberry Pi).

**Requirements**: Docker Desktop on Mac.

```bash
./Scripts/docker/start-test-ssh.sh
./Scripts/docker/stop-test-ssh.sh
```

*   **Port**: 22222 (default)
*   **User**: glassdeck
*   **Auth**: Password + Key both enabled

**Seeded home directory**:
*   `~/bin/health-check.sh`
*   `~/testdata/preview.txt`
*   `~/testdata/nested/dir/info.txt`
*   `~/testdata/nano-target.txt`
*   `~/upload-target/`

**Note**: For physical iPhone testing, iPhone and Mac must be on the same LAN.

## Manual Smoke Checklist

1.  Start Docker SSH: `./Scripts/docker/start-test-ssh.sh`
2.  Or run full suite: `./Scripts/test-live-docker-ssh.sh`
3.  Launch app on simulator or iPhone
4.  Create profile with printed host/port, connect via password auth
5.  Create second profile or switch to SSH key auth
6.  Run `~/bin/health-check.sh`, `pwd`, `ls ~/testdata`
7.  Verify rendering, typing, paste, special keys, resize, disconnect, reconnect
8.  Open SFTP browser → browse testdata, preview, upload, delete
9.  With external monitor + physical keyboard: route session, test Mouse/Cursor mode, two-finger scroll, View Local Terminal, `nano --mouse ~/testdata/nano-target.txt`

## Dependencies

| Dependency | Source | Purpose |
|-----------|--------|---------|
| libghostty-vt | Vendored xcframework | Terminal VT emulation engine |
| swift-ssh-client | Vendor/ (fork) | High-level SSH client |
| swift-nio-ssh | SPM (≥0.9.0) | Low-level SSH protocol |
| swift-nio | SPM (≥2.65.0) | Async networking |
| Swift Crypto | (via NIO SSH) | Ed25519/P256 keys, SHA-256 |
| Core Location | System | Optional background keep-alive |

## Notes

*   GlassdeckCore is the only source of truth for shared SSH, key, model, and terminal logic.
*   The Metal renderer is Glassdeck-owned; no dependency on GhosttyKit.
*   The VT C API is upstream WIP — vendored xcframework + rebuild script must stay in sync.
*   Docker SSH server is the canonical acceptance target.

## License

MIT — see [LICENSE](LICENSE).
