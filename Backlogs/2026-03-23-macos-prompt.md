# macOS Agent Session Prompt — 2026-03-23

Paste this into a fresh coding agent session on your Mac:

---

## Context

I'm migrating my iOS SSH terminal app "Glassdeck" from CGhosttyVT (VT parser only) to full GhosttyKit (GPU Metal rendering). All Swift code changes are done and pushed. I now need to do the macOS/Xcode-dependent work.

### Repositories (both already cloned)
- **Glassdeck**: `~/git/Glassdeck` — iOS app, Swift 6.2, SPM, iOS 26+
- **Ghostty fork**: `~/git/ghostty` — Zig codebase, my fork at github.com/atjsh/ghostty with 2 custom C API additions

### What's already done (DO NOT redo any of this)
All Swift code changes are committed and pushed. See `~/git/Glassdeck/Backlogs/2026-03-23.md` for full details. Key points:
- GhosttyKit migration complete (+1,169 / −3,716 lines across Glassdeck)
- Ghostty fork has 2 new C API functions: `ghostty_surface_process_output()` and `ghostty_surface_set_write_callback()` (+68 lines)
- 50 new tests added
- `Package.swift` expects `GhosttyKit.xcframework` at `Frameworks/GhosttyKit.xcframework`

### What needs to happen now

1. **Build `GhosttyKit.xcframework` from the Ghostty fork for iOS (arm64)**
   - The Ghostty repo has build infrastructure for this — explore `build.zig`, `macos/`, and any xcframework build scripts
   - Target: iOS arm64 (device) + iOS simulator (arm64-sim)
   - The framework must export all symbols from `include/ghostty.h` including our 2 custom additions
   - Place the built framework at `~/git/Glassdeck/Frameworks/GhosttyKit.xcframework`

2. **Build Glassdeck in Xcode and fix any compile errors**
   - Open via SPM or the `.xcodeproj`
   - Fix any type mismatches, missing symbols, or API differences between what we coded and what the actual GhosttyKit header provides
   - Pay special attention to: `ghostty_surface_size()` return struct field names, `ghostty_surface_config_new()` vs `ghostty_surface_config_s()`, any enum naming differences

3. **Run the test suite** — all 50 new tests should pass
   - `GlassdeckCoreTests` target (SSHKeyManager, keyboard, pointer, input coordinator tests)
   - `GlassdeckHostIntegrationTests` target (SSHPTYBridge + E2E pipeline tests)

4. **Smoke test on simulator or device** if possible
   - Verify the GhosttyKit Metal surface initializes and renders
   - If you can connect to an SSH server, test the full pipeline

### My engineering preferences
- DRY, well-tested, handle edge cases
- Explicit over clever
- Fix issues as you find them, don't leave broken code

### Important notes
- Read `~/git/Glassdeck/Backlogs/2026-03-23.md` FIRST for full architecture context
- The Ghostty build system uses Zig — you'll need `zig` installed (check with `zig version`)
- DO NOT modify the Ghostty fork's Zig source code unless absolutely necessary for the build
- If GhosttyKit header symbols don't match what Glassdeck expects, fix the GLASSDECK side
