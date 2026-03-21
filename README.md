# Glassdeck

English | [한국어](README-ko.md)

Glassdeck is an experimental SSH client for iOS 26 built with SwiftUI. The repository is aimed at an iPhone-first terminal experience with session management, external display routing, hardware input support, and hooks for on-device AI features.

## Overview

- SwiftUI app structure for connection management and multi-session terminal workflows
- SSH connection and session scaffolding built on `swift-nio-ssh` and `swift-ssh-client`
- External display scene support, keyboard and pointer input handlers, and terminal configuration models
- AI assistant UI and service placeholders intended for Foundation Models integration

## Highlights

### In the Repository Today

- Saved connection profiles with search, create/edit flows, and local persistence via `UserDefaults`
- Session management for connect, open shell, disconnect, and multi-session routing
- External display scene support with a dedicated routing picker and separate terminal view
- Terminal configuration models for themes, font size, cursor style, and scrollback settings
- SSH key storage helpers backed by Keychain, plus password and key-based auth models
- Built-in help browser and AI assistant sheet wired into the main app shell

### Gated or Partial

- `GhosttyKit` integration is scaffolded in `Glassdeck/Terminal/GhosttyTerminalView.swift`, but the framework is not vendored in this repo and the bridging code is still commented out
- Foundation Models-backed AI is not active yet; `AIAssistant` currently returns placeholder responses until framework integration is completed
- Some SSH and terminal behaviors are still TODO-backed, including PTY resize plumbing, host key verification wiring, and parts of the SSH key import/export experience
- Persistence currently uses `UserDefaults`; code comments indicate a later move to SwiftData

## Current Status

- Public work in progress, not a finished production client
- Requires Xcode 26 and the iOS 26 SDK to work on the current codebase
- The supported developer workflow is opening the package in Xcode and running it against an iOS target from there
- `swift build` is not currently a supported default path; the package still hits a platform compatibility issue against its SSH dependencies when built from the CLI
- Optional integrations such as GhosttyKit and Foundation Models require additional setup or unfinished implementation work

## Requirements

- macOS with Xcode 26 beta and the iOS 26 SDK
- iPhone 15 Pro is the intended device target for the current product direction
- Apple Intelligence-capable hardware if you want to finish and test the on-device AI path
- Optional `GhosttyKit.xcframework` if you want to work on the Ghostty-backed terminal integration

## Build and Run

Use Xcode as the primary workflow for this repository.

```bash
git clone git@github-atjsh:atjsh/Glassdeck
cd Glassdeck
swift package resolve
open Package.swift
```

Then:

1. Open the package in Xcode 26.
2. Select an iOS 26 target device.
3. Build and run from Xcode.

Do not treat `swift build` as the primary verification step until the package platform metadata is corrected for CLI builds.

### Optional GhosttyKit Setup

If you want to continue the Ghostty-backed terminal path:

1. Build `GhosttyKit.xcframework` from [Ghostty](https://github.com/ghostty-org/ghostty) using `./macos/build.nu --scheme Ghostty-iOS --configuration Release --action build`.
2. Place the framework in `Frameworks/`.
3. Uncomment `import GhosttyKit` and the related bridge code in `Glassdeck/Terminal/GhosttyTerminalView.swift`.
4. Verify the terminal surface lifecycle and rendering paths against the vendored framework.

## Architecture Snapshot

```text
Glassdeck/
├── App/        App entry point, app delegate, Info.plist
├── Scenes/     Main and external display scene delegates
├── Views/      SwiftUI flows for connections, terminal UI, settings, and help
├── Models/     Connection profiles, app settings, and session state
├── SSH/        Connection lifecycle, auth, PTY bridge, and key storage
├── Terminal/   Terminal surface wrappers, configuration, and protocols
├── Input/      Keyboard and pointer input handling
└── AI/         AI assistant actor and overlay UI scaffolding
```

## Roadmap / Known Gaps

- Finish the GhosttyKit rendering bridge and remove placeholder terminal behavior
- Replace AI placeholder responses with real Foundation Models availability checks and generation flows
- Complete SSH ergonomics such as host key verification wiring, terminal resize requests, and richer key import/export UX
- Revisit package metadata so CLI builds can become a documented and supported path
- Evaluate the planned move from `UserDefaults` persistence to SwiftData

## License

MIT. See [LICENSE](LICENSE).
