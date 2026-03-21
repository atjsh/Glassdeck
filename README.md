# Glassdeck

Glassdeck is an iOS 26 SSH client with a shared Swift core and a generated Xcode app target. The current revision uses a real `libghostty-vt` backend for terminal state, a Glassdeck-owned Metal renderer, PTY-aware SSH shells, and an expanding SFTP workflow.

## Current Scope

- SSH terminal sessions backed by `libghostty-vt`
- PTY shell startup and runtime resize through the vendored `swift-ssh-client`
- External display routing
- Hardware keyboard, touch, focus, paste, and local scrollback handling
- SFTP directory browsing, text preview, upload, delete, and export

## Repository Layout

```text
Glassdeck/
├── Glassdeck/            iOS app shell, SwiftUI views, UIKit terminal surface
├── GlassdeckCore/        Shared models, SSH, terminal engine bindings, SFTP
├── Frameworks/           Vendored CGhosttyVT xcframework
├── GlassdeckApp.xcodeproj Generated iOS app project for simulator/device runs
├── Scripts/              Ghostty packaging, simulator scripts, Docker SSH target
├── Tests/                iOS simulator XCTest sources
└── Vendor/               Forked swift-ssh-client dependency
```

## Terminal Architecture

- `GlassdeckCore/Terminal/GhosttyVTBindings.swift` owns the live `GhosttyTerminal`, `GhosttyRenderState`, key encoder, and mouse encoder.
- `GlassdeckCore/Terminal/GhosttyVTTypes.swift` defines the pure Swift render projection and input descriptor types.
- `Glassdeck/Terminal/GhosttyTerminalView.swift` contains the iOS surface: a `UIView` backed by `CAMetalLayer`, a Core Image based Metal renderer, and the UIKit input bridge.
- `GlassdeckCore/SSH/SSHPTYBridge.swift` remains the UI-agnostic PTY bridge. Shell output writes into the terminal engine, and VT-encoded local input goes back to the shell.

## Vendored Ghostty Build

`Frameworks/CGhosttyVT.xcframework` is committed in-repo as a static-library Apple-platform artifact. To rebuild it from a local Ghostty checkout:

```bash
./Scripts/build-cghosttyvt.sh
```

Defaults:

- device target: `aarch64-ios`
- simulator target: `aarch64-ios-simulator -Dcpu=apple_a17`
- optional Intel simulator slice: `INCLUDE_X86_64_SIMULATOR=true`
- VT packaging mode: static xcframework, no runtime framework embedding
- SIMD: disabled by default for the vendored iOS build so the archive remains pure-static and device-safe

## Development

### Regenerate the Xcode project

```bash
./Scripts/generate-xcodeproj.sh
```

### Run on the canonical iOS simulator

```bash
./Scripts/run-ios-sim.sh
```

### Run simulator XCTest

```bash
./Scripts/test-ios-sim.sh
```

Run a single test target without hand-writing `xcodebuild` flags:

```bash
./Scripts/test-ios-sim.sh --only-testing GlassdeckAppTests/RemoteControlStateTests
```

### Run the live Docker SSH integration tests

```bash
./Scripts/test-live-docker-ssh.sh
```

### Run the Docker UI screenshot tests

```bash
./Scripts/test-docker-ui-sim.sh
```

### Start the canonical live SSH test target

```bash
./Scripts/docker/start-test-ssh.sh
```

Optional host-side smoke validation:

```bash
./Scripts/docker/smoke-test-ssh.sh
```

Stop the Docker target:

```bash
./Scripts/docker/stop-test-ssh.sh
```

Optional live log tail:

```bash
./Scripts/run-ios-sim.sh --logs
```

The XCTest runner scripts default to quiet output. Each run saves the raw `xcodebuild` log under `.build/TestLogs/` and the `xcresult` bundle under `.build/TestResults/`.

If you want the raw `xcodebuild` stream back, use `--verbose` or `GLASSDECK_VERBOSE=1`:

```bash
./Scripts/test-ios-sim.sh --verbose
GLASSDECK_VERBOSE=1 ./Scripts/test-live-docker-ssh.sh
```

The expected local simulator target is `iPhone 17` on the latest installed iOS runtime.

The simulator run path uses the generated `GlassdeckApp.xcodeproj` and scheme `GlassdeckApp`. Set `SIMULATOR_ID` to target a specific booted or available simulator directly; otherwise the scripts resolve the latest available `iPhone 17`. If `project.yml` is newer than the project, the repo scripts regenerate it with `./Scripts/generate-xcodeproj.sh`.

Glassdeck is currently supported on iOS only. The canonical local workflow is the generated Xcode project plus the simulator scripts above.

## Docker SSH Test Target

Glassdeck now treats the repo-owned Docker SSH server as the canonical live test endpoint instead of a separate Raspberry Pi host.

- Requires Docker Desktop on the Mac that is running the repo.
- Publishes OpenSSH on port `22222` by default.
- Supports both password auth and SSH-key auth for the same `glassdeck` user.
- Seeds a deterministic home directory with:
  - `~/bin/health-check.sh`
  - `~/testdata/preview.txt`
  - `~/testdata/nested/dir/info.txt`
  - `~/testdata/nano-target.txt`
  - `~/upload-target/`

`./Scripts/docker/start-test-ssh.sh` prints the exact host, port, username, password, SSH private-key path, and current host-key fingerprint to use in Glassdeck. For physical-iPhone testing, the iPhone and the Mac running Docker must be on the same LAN so the published SSH port is reachable over the Mac’s LAN IP.

## Manual Smoke Checklist

- Start the Docker SSH target with `./Scripts/docker/start-test-ssh.sh`
- Or run `./Scripts/test-live-docker-ssh.sh` to boot the Docker target, verify it with the host-side smoke checks, and run the opt-in live `SSHConnectionManager` XCTest cases on `iPhone 17`
- Launch the app on the simulator or physical iPhone
- Create a connection profile using the printed host/port and connect over password auth
- Open a second profile or switch auth to the printed SSH key and connect over SSH-key auth
- In the terminal, run `~/bin/health-check.sh`, `pwd`, and `ls ~/testdata` to confirm login and command execution
- Verify terminal rendering, typing, paste, special keys, resize, disconnect, and reconnect
- Open the SFTP browser from the terminal toolbar and browse `~/testdata`, preview `preview.txt`, upload into `~/upload-target`, and delete the uploaded file
- With an external monitor and physical keyboard attached, route the active session to the external display and validate `Mouse` mode, `Cursor` mode, two-finger scroll, `View Local Terminal`, and `nano --mouse ~/testdata/nano-target.txt`

## Notes

- `GlassdeckCore` is the only supported source of truth for shared SSH, key, model, and terminal logic.
- The Metal renderer is Glassdeck-owned; this repo does not depend on `GhosttyKit`.
- The VT C API is upstream work in progress, so keeping the vendored static xcframework and rebuild script in sync matters.
- The Docker SSH server is the canonical live acceptance target for password auth, SSH-key auth, SFTP, and external-display testing.
