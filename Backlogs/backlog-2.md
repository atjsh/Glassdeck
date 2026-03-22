# Glassdeck vs Ghostty/Ghostling Comparative Code Review

**Validation date**: 2026-03-22, 16:45–16:56 KST  
**Environment**: Xcode 26.3 (17C529), Swift 6.2.4, Docker 29.2.1  
**Simulator**: iPhone 17, iOS 26.3.1 (`6C596A8C-2746-4F36-B548-498535CEF4EE`)  
**SHAs used**:
- Glassdeck: `1a02ac0` (main)
- Ghostty: `ad5e9679c` (main)
- Ghostling: `8458d1a` (main)

**Commands executed**:
- `xcodebuild build-for-testing` (GlassdeckAppUnit, GlassdeckAppUI)
- `xcodebuild test-without-building` (GlassdeckAppUnit, GlassdeckAppUI)
- `Scripts/test-live-docker-ssh.sh`
- `xcrun simctl create/boot/install/launch/screenshot`

---

## Test Results Summary

| Suite | Total | Passed | Failed | Skipped |
|-------|-------|--------|--------|---------|
| **GlassdeckAppUnit** | 60 | 56 | 3 | 2 |
| **GlassdeckAppUI** | 18 | 11 | 2 | 5 |
| **Live Docker SSH** | pass | — | — | — |

### Unit test failures

1. `testAppSettingsMigratesLegacyTerminalConfigurationIntoDisplayProfiles` — float rounding: expected `24.3`, got `24.0` (ConnectionModelTests.swift:126)
2. `testHomeAnimationNormalizedPayloadPreservesBrandAccentAndGridDimensions` — frame width mismatch (GhosttyHomeAnimationPerformanceTests.swift:36)
3. `testRefreshingExternalMonitorProfileRecreatesPresentedSurface` — XCTAssertFalse failed (RemoteControlStateTests.swift:311)

### UI test failures

1. `testAnimationScenarioAdvancesFramesAndRendersTerminal` — XCTAssertTrue failed on terminal surface existence (GlassdeckAppUITests.swift:92)
2. `testSessionRowTapNavigatesToDetail` — XCTAssertTrue failed on navigation (GlassdeckAppUITests.swift:35)

### Visual validation

App launches, shows Connections list with saved profiles. No crash on launch. Connection list renders correctly.

---

## Part 1: Ghostty/Ghostling Divergence Findings

Findings ordered by severity. Each compared against the canonical Ghostty C API usage in `ghostling/main.c` and `ghostty/macos/Sources/Ghostty/`.

---

### F1. `P0 · confirmed static risk` — SSH host-key verification disabled in both live SSH paths

**Files**: `GlassdeckCore/SSH/SSHConnectionManager.swift:57`, `GlassdeckCore/SSH/SFTPManager.swift:323`

Both SSH and SFTP connection paths use `.acceptAll()` for host key validation:

```swift
// SSHConnectionManager.swift:57
authentication: SSHAuthentication(
    username: profile.username,
    method: authMethod,
    hostKeyValidation: .acceptAll()  // ← ACCEPTS ANY SERVER KEY
)

// SFTPManager.swift:323 — identical pattern
hostKeyValidation: .acceptAll()
```

A complete Trust-On-First-Use (TOFU) implementation exists in `GlassdeckCore/SSH/HostKeyVerifier.swift` with `verify()`, `trustHost()`, `forgetHost()`, and SHA256 fingerprinting — but it is **never called** from any connection code. `grep -r "HostKeyVerifier" --include="*.swift"` shows it is only referenced in its own file and in test files.

**Impact**: Trivial MITM attacks against all SSH and SFTP sessions. This is the highest-severity finding.

**Ghostty reference**: While Ghostty itself doesn't implement SSH, its security discipline (careful state validation, explicit error handling) contrasts directly with accepting all server keys.

**Additional risk**: `HostKeyVerifier` stores known-host fingerprints in `UserDefaults` (unencrypted), which is vulnerable on jailbroken devices. When integrated, this should migrate to Keychain.

---

### F2. `P1 · confirmed static risk` — Terminal state lost on surface recreation

**Files**: `Glassdeck/Models/SessionManager.swift:742`, `GlassdeckCore/SSH/SSHPTYBridge.swift:replaceTerminal()`

`recreateSurface()` allocates a fresh `GhosttySurface` (with a fresh `GhosttyVTTerminalEngine` and `GhosttyTerminal` C handle), then swaps the PTY bridge to it:

```swift
let surface = try GhosttySurface(configuration: configuration)
// copies frame/bounds from previous surface
session.surface = surface
bind(surface: surface, to: session)
await bridge.replaceTerminal(GhosttySurfaceTerminalIO(surface: surface))
// ← NEW BLANK TERMINAL. No scrollback replay. No state migration.
```

**Impact**: Any configuration change (font size, color scheme, device rotation, external display) that triggers `recreateSurface` will blank a live SSH session. User loses all visible terminal output.

**Ghostty reference**: Ghostty's macOS port preserves terminal state across configuration changes. The `ghostty_surface_t` owns the terminal state and persists through reconfigurations. Glassdeck creates a new C terminal handle each time.

**Confirmed by test**: `testRefreshingExternalMonitorProfileRecreatesPresentedSurface` fails with `XCTAssertFalse`, suggesting the surface recreation path has a known regression.

---

### F3. `P1 · confirmed static risk` — Printable keys bypass libghostty key encoding

**Files**: `Glassdeck/Terminal/GhosttyTerminalView.swift:762`

`shouldUseTextInputFallback()` returns `true` for all printable ASCII keys (a-z, 0-9, common symbols) when no modifiers are held. These events are marked `unhandled` and routed to iOS `UIKeyInput` text input instead of the libghostty key encoder:

```swift
case .a, .b, .c, ... .bracketRight:
    return !descriptor.text.isEmpty  // ← TRUE for printable keys
```

When `true`, `handleHardwarePresses()` inserts the press into `unhandled` and calls `super.pressesBegan()`, bypassing `engine.encodeKey()`.

**Impact**: Breaks terminal applications that depend on raw keycode events rather than text input (vim, tmux, Kitty keyboard protocol). The libghostty encoder respects terminal modes; the UIKeyInput path does not.

**Ghostling reference**: `ghostling/main.c:handle_input()` routes **all** keys through `ghostty_key_encoder_encode()`, including printable characters. No fallback text path exists.

---

### F4. `P1 · confirmed static risk` — `consumed_mods` hard-coded to zero

**Files**: `GlassdeckCore/Terminal/GhosttyVTBindings.swift:251`

```swift
ghostty_key_event_set_consumed_mods(keyEvent, 0)  // ← ALWAYS ZERO
```

**Impact**: The libghostty key encoder uses `consumed_mods` to determine which modifier keys were consumed by the text input system (e.g., Shift consumed to produce uppercase). Hard-coding to 0 tells the encoder no modifiers were consumed, which produces incorrect sequences for Kitty keyboard protocol and CSI-u encoded modified keys.

**Ghostling reference** (`main.c:519`):
```c
consumed = (ucp != 0 && shift) ? SHIFT : 0;
ghostty_key_event_set_consumed_mods(event, consumed);
```

**Ghostty macOS reference** (`NSEvent+Extension.swift`): Computes consumed modifiers from `modifierFlags` differences between raw and processed events.

---

### F5. `P1 · confirmed static risk` — Remote scroll hard-codes SGR escape sequences

**Files**: `Glassdeck/Terminal/GhosttyTerminalView.swift:634`

```swift
let button = steps > 0 ? 65 : 64
let sequence = "\u{1B}[<\(button);\(coordinates.column);\(coordinates.row)M"
outputHandler?(Data(sequence.utf8))
```

This manually constructs SGR mouse encoding, bypassing `engine.encodeMouse()`. If the terminal switches mouse protocols (X10, URXVT, SGR-Pixels), the scroll output will be in the wrong format.

**Ghostling reference** (`main.c:handle_mouse()`): All mouse events (including scroll) go through `ghostty_mouse_encoder_encode()`, which respects the terminal's current mouse reporting mode and encoding format.

---

### F6. `P1 · confirmed static risk` — CPU rasterization masquerading as Metal renderer

**Files**: `Glassdeck/Terminal/GhosttyTerminalView.swift:1000-1400`

Despite the class name `GhosttyMetalRenderer`, rendering is done via:

1. **CPU**: `UIGraphicsImageRenderer` rasterizes all text using `NSString.draw(in:withAttributes:)` 
2. **GPU blit only**: Result is converted to `CIImage` → rendered to `CAMetalLayer` drawable via `CIContext.render()`

**Missing VT style attributes** (compared to Ghostty's shader-based renderer):

| Attribute | Glassdeck | Ghostty |
|-----------|-----------|---------|
| Bold | ✅ font weight | ✅ font weight |
| Underline (single) | ✅ | ✅ |
| Strikethrough | ✅ | ✅ |
| Faint/Dim | ✅ alpha 0.6 | ✅ |
| Inverse | ✅ color swap | ✅ |
| **Italic** | ❌ missing | ✅ shader-based |
| **Underline color** | ❌ ignored | ✅ per-cell |
| **Double underline** | ❌ | ✅ |
| **Curly underline** | ❌ | ✅ |
| **Overline** | ❌ | ✅ |
| **Blink** | ❌ | ✅ |
| **Cursor visual style (from VT)** | ❌ uses app config | ✅ terminal-controlled |

**Performance**: No glyph atlas caching; every frame re-rasterizes all visible text on CPU. Ghostty's Metal renderer uses vertex/fragment shaders with glyph atlas texturing, GPU-based color space conversion (sRGB→Display P3), and contrast-aware rendering.

**Ghostty reference** (`src/renderer/shaders/shaders.metal`): Real Metal pipeline with projection matrices, per-cell uniform buffers, gamma correction, minimum contrast enforcement, and linear blending.

---

### F7. `P1 · confirmed static risk` — Theme unconditionally overrides terminal-resolved colors

**Files**: `Glassdeck/Terminal/GhosttyTerminalView.swift:1377`

```swift
private func themedProjection(from projection: GhosttyVTRenderProjection) -> GhosttyVTRenderProjection {
    let theme = configuration.colorScheme.theme
    var projection = projection
    projection.backgroundColor = theme.background
    projection.foregroundColor = theme.foreground
    projection.cursorColor = theme.cursor
    projection.palette = theme.palette
    return projection
}
```

This replaces the terminal's resolved foreground/background/cursor colors and full 256-color palette with the app's configured theme. Any OSC-based color changes from the remote application (e.g., `printf '\033]10;#ff0000\007'` to change foreground) are silently overwritten.

**Ghostty reference**: Ghostty's renderer uses the terminal's color state directly and only applies configuration defaults when no terminal-set values exist.

---

### F8. `P2 · unvalidated due to environment` — IME/preedit composition not implemented

**Files**: `Glassdeck/Terminal/GhosttyTerminalView.swift:329`, `Glassdeck/Input/SessionKeyboardInputHost.swift`

Glassdeck implements only `insertText(_:)` and `deleteBackward()`. There is no:
- `setMarkedText(_:selectedRange:replacementRange:)` 
- `unmarkText()`
- Preedit state propagation to libghostty

**Ghostty reference** (`SurfaceView_AppKit.swift:1171+2025`): Explicitly syncs marked text/preedit state into libghostty via `ghostty_surface_preedit()`, renders composition overlays at cursor position via `ghostty_surface_ime_point()`.

**Impact**: CJK input methods and European accent composition (dead keys) will not work correctly. Cannot validate on simulator; requires hardware testing with non-Latin keyboard.

---

## Part 2: Project-Local Code Quality & Test Coverage

---

### F9. `P1 · confirmed build/test failure` — Three unit tests fail consistently

1. **`testAppSettingsMigratesLegacyTerminalConfigurationIntoDisplayProfiles`**: Migration rounds external-monitor font size to integer (`24.0`) but test expects original float (`24.3`). Either `AppSettings.swift:193` rounding logic or `ConnectionModelTests.swift:126` test oracle is wrong.

2. **`testHomeAnimationNormalizedPayloadPreservesBrandAccentAndGridDimensions`**: Animation normalization does not preserve frame width. Either `GhosttyHomeAnimation.swift:127` or the test is incorrect.

3. **`testRefreshingExternalMonitorProfileRecreatesPresentedSurface`**: Surface recreation assertion fails. This directly relates to **F2** (state loss on surface recreation).

---

### F10. `P1 · confirmed build/test failure` — Two UI tests fail consistently

1. **`testAnimationScenarioAdvancesFramesAndRendersTerminal`**: Waits for terminal surface element but it never appears within timeout.

2. **`testSessionRowTapNavigatesToDetail`**: Navigation from session list to detail view fails.

---

### F11. `P1 · static risk` — External display scene may leak on reconnection

**Files**: `Glassdeck/Scenes/ExternalDisplaySceneDelegate.swift`

If `scene(_:willConnectTo:options:)` is called twice (scene reconnection), the second window replaces the first without cleanup:

```swift
self.window = window  // ← Previous window reference lost without cleanup
```

**Fix**: Check and cleanup existing window before creating a new one.

---

### F12. `P2 · static risk` — Password not securely cleared from memory

**Files**: `GlassdeckCore/SSH/SSHAuthenticator.swift`

```swift
public static func passwordMethod(_ password: String) -> SSHAuthentication.Method {
    .password(.init(password))  // Swift String is not zeroed on deallocation
}
```

Swift `String` values persist in memory after deallocation. Sensitive credentials should use a secure wrapper that overwrites memory on deinit.

---

### F13. `P2 · static risk` — SSHReconnectManager treats all failures equally

**Files**: `GlassdeckCore/SSH/SSHReconnectManager.swift`

Reconnection retries regardless of failure type. Auth failures and invalid hostname errors trigger the same exponential backoff as transient network errors. Should classify permanent failures and stop retrying early.

---

### F14. `P2 · static risk` — Focus events not sent on keyboard responder changes

**Files**: `Glassdeck/Input/SessionKeyboardInputHost.swift`

`becomeFirstResponder()` / `resignFirstResponder()` do not send terminal focus-in/focus-out events (CSI I / CSI O). Terminal applications relying on focus reporting (e.g., vim `FocusGained` autocmd) will not work.

**Ghostling reference**: `ghostling/main.c` checks `GHOSTTY_TERMINAL_MODE_FOCUS_EVENTS` and calls `ghostty_focus_encode()` on window focus changes.

---

### F15. `P2 · static risk` — PointerInputHandler SGR encoding is dead code

**Files**: `Glassdeck/Input/PointerInputHandler.swift`

`sgrMouseEvent()` encodes SGR mouse sequences correctly but is never called from any gesture recognizer. No `UITapGestureRecognizer` or `UIPanGestureRecognizer` is attached for terminal area mouse clicks/drags.

---

### F16. `P2 · code quality` — GlassdeckApp launch routing uses 40-attempt polling loop

**Files**: `Glassdeck/App/GlassdeckApp.swift`

```swift
while attempt < 40 && !appliedLaunchRouting {
    attempt += 1
    try? await Task.sleep(for: .milliseconds(attempt == 1 ? 1 : 250))
}
```

Polling with hard-coded delays is fragile. Should use completion callbacks or `AsyncStream` for launch routing coordination.

---

### F17. `P2 · code quality` — TerminalContainerView is 500+ lines with multiple nested views

**Files**: `Glassdeck/Views/TerminalContainerView.swift`

Contains `SessionDetailView`, `SessionDetailContent`, `TerminalPresentationPlaceholderView`, `SessionRecoveryPanel`, `DisplayRoutingPicker`, `TerminalSettingsView` (600+ lines), and more. Should extract each into separate files.

---

### F18. `P2 · false positive in IDE` — Scripts/patch-local-package-product.py regex match errors

**Files**: `Scripts/patch-local-package-product.py:164,179,187,203,211,212,263,272`

Pylance reports `.group()` called on potentially-`None` match results. These are false positives — each function calls `fail()` (which raises `SystemExit`) on the `if not match:` branch, so the code after the guard is unreachable when `match` is `None`. The type narrowing just isn't recognized by Pylance.

---

### F19. `P2 · code quality` — C handle cleanup is correct

**Files**: `GlassdeckCore/Terminal/GhosttyVTBindings.swift` (init/deinit)

All six C handles (`terminal`, `renderState`, `keyEncoder`, `mouseEncoder`, `rowIterator`, `rowCells`) are properly created with error checking and freed in reverse order in `deinit`. No resource leaks detected. **This is well-implemented.**

---

## Missing Validation Coverage

The following areas lack test coverage for the issues identified:

| Area | Tests Exist | Gap |
|------|-------------|-----|
| Host-key enforcement/mismatch | ❌ | No integration test verifies TOFU flow |
| Surface state preservation across recreation | ❌ | Only tests that surface is non-nil after, not content |
| Consumed modifiers correctness | ❌ | No test sends modified keys and verifies VT output |
| IME/preedit composition | ❌ | Requires device testing |
| VT style fidelity (italic, overline, blink) | ❌ | No render output assertion tests |
| Mouse protocol mode switching | ❌ | No test verifies scroll uses correct encoding format |
| Focus event reporting | ❌ | No test for CSI I/O on responder changes |
| External display lifecycle (leak) | ❌ | No test for scene reconnection cleanup |

---

## Strengths

Despite the divergences, several aspects of the codebase are well-implemented:

1. **Clean architecture**: Clear separation of C FFI bindings → Swift domain types → UI layer
2. **Actor isolation**: `SSHConnectionManager`, `SSHPTYBridge`, `SSHReconnectManager` all use actors correctly for thread safety
3. **Resource lifecycle**: C handle init/deinit is correct with proper reverse-order cleanup
4. **Dirty tracking**: Render state dirty-row optimization is present and functional
5. **Credential storage**: SSH passwords stored in Keychain with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`
6. **Reconnection**: Exponential backoff with configurable parameters
7. **Modern Swift**: Async/await, Observation framework, structured concurrency
8. **Live SSH validation**: Docker-based integration test infrastructure works and passes
