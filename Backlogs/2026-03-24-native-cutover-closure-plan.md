# Native Cutover Closure Context Ledger

Last updated: 2026-03-24

## Integration State
- Primary integration worktree: `/Users/jeonseonghun/git-atjsh/Glassdeck`
- Primary branch: `codex/fill-native-cutover-gaps`
- Primary validated stack head: `561d969035e41e8b75b3a8dc6d4e1e70d5b3a52a`
- Current green closure baseline:
  - committed primary closure stack entry `85940551a1127673ad3e92fdd904fee22d905c57` `Close native cutover live probe blocker`
  - committed primary follow-on entry `561d969035e41e8b75b3a8dc6d4e1e70d5b3a52a` `Migrate legacy external display routing on restore`
  - live prompt probe: green
  - live command-injection probe: green
  - live render-only probe: green
  - host-backed relaunch acceptance: green
  - full `SessionPersistenceTests` unit slice: green
- Landed base commits:
  - `e01c2e5060a07578d22f19526ec28d22a8159a30` `Create native cutover baseline snapshot`
  - `5be0f1a97bcba4ddd6cd0b377528585537f90c51` `Implement runner artifact export cleanup`
  - `8fbabcf6f00fa1d73c55a1fdf4f198986324f12d` `Convert swift-ssh-client to pinned fork submodule`
  - `8125f4c57b3a4a5f03f3c5afdc84d47a8f2ef54f` `Add shared xcode executor and bounded log capture`
  - `0896d2630d95359500ca57c34ab68f1a07c417ae` `Add runner stable artifact aliases and tests`
  - `c0d362953ed4f8186247622efa82b4378af58037` `Fix runner workspace detection for git worktrees`
  - `6b0b2e0b5d37d9d2c75b0444bdf2a2e12bca2c4d` `Resolve simulator for build/test commands`
  - `3c99bb534ca14ed071f156a17498aeac48dbe732` `Align runner tests with executor preview API`

## Stale Worktree Cleanup
- Completed:
  - Exported stale patch salvage artifacts to `/Users/jeonseonghun/git-atjsh/Glassdeck/temp/stale-worktree-patches/`
  - Removed clean stale worktree `/Users/jeonseonghun/git-atjsh/.worktrees/glassdeck-log-inspect`
  - Deleted clean stale branch `codex/log-inspect`
  - Removed stale worktree `/Users/jeonseonghun/git-atjsh/.worktrees/glassdeck-log-trim`
  - Removed stale worktree `/Users/jeonseonghun/git-atjsh/.worktrees/glassdeck-runner`
  - Removed stale worktree `/Users/jeonseonghun/git-atjsh/.worktrees/glassdeck-ui`
  - Deleted stale branch `codex/log-trim`
  - Deleted stale branch `codex/runner-export-cleanup`
  - Deleted stale branch `codex/ui-probe-harness`
- Remaining stale worktrees requiring diff/patch review before removal:
  - none
- Salvage artifacts:
  - `/Users/jeonseonghun/git-atjsh/Glassdeck/temp/stale-worktree-patches/log-trim.patch`
  - `/Users/jeonseonghun/git-atjsh/Glassdeck/temp/stale-worktree-patches/runner-export-cleanup.patch`
  - `/Users/jeonseonghun/git-atjsh/Glassdeck/temp/stale-worktree-patches/ui-probe-harness.patch`
- File overlap summary:
  - `log-trim` overlaps current primary runner CLI/output files and adds `Tests/GlassdeckBuildCoreTests/TestHelpers.swift`
  - `runner-export-cleanup` overlaps current primary runner files and adds artifact-focused tests plus `TimestampedProcessOutputWriter.swift`
  - `ui-probe-harness` overlaps current primary UI probe files only
- Cleanup rule:
  - Review each patch against the current primary dirty state.
  - Salvage unique hunks into active implementation flow.
  - Remove the stale worktree and delete the stale branch only after salvage is complete.

## Fixed Codex Team
- Researcher:
  - Model: `gpt-5.4`
  - Mode: read-only
  - Responsibilities: ledger upkeep, stale-worktree comparison, commit slicing, cross-cutting review, integration readiness
  - Simulator: none; do not boot or use Simulator
- Worker 1:
  - Model: `gpt-5.3-codex-spark`
  - Branch: retired on 2026-03-24 after accepted runner slices were integrated into `codex/fill-native-cutover-gaps`
  - Worktree: retired on 2026-03-24 after cleanup from the primary worktree
  - Ownership: `Tools/GlassdeckBuild/Sources/GlassdeckBuildCore/Artifacts/`, minimal `XcodeInvoker`, matching runner tests
  - Simulator: `iPhone 17 Pro` `8647FB0C-AD1D-4A0D-81E1-814D1877FC15`
- Worker 2:
  - Model: `gpt-5.3-codex-spark`
  - Branch: retired on 2026-03-24 after the current primary closure diff superseded the older harness split
  - Worktree: retired on 2026-03-24 after cleanup from the primary worktree
  - Ownership: `Glassdeck/App/`, `Tests/GlassdeckAppUITests/`, plus only the artifact-name mapping touchpoint required by probe export
  - Simulator: `iPhone 17 Pro Max` `8BA84984-26FB-41EC-A0E3-748C658FBCD4`
- Worker 3:
  - Model: `gpt-5.3-codex-spark`
  - Branch: retired on 2026-03-24 after the useful persistence slice was recovered directly in the primary worktree
  - Worktree: retired on 2026-03-24 after cleanup from the primary worktree
  - Ownership: `Glassdeck/Models/SessionManager.swift`, `Tests/GlassdeckAppTests/`
  - Simulator: `iPhone Air` `48B92811-6D0D-4E23-A157-2B201386D6A0`
- Team rule:
  - Keep exactly one researcher and three writing workers.
  - Do not spawn additional sub-agents.
  - Reuse the same agents for the rest of the project.
  - Do not share or overlap simulator instances across workers.

## Execution Order
1. Completed: stale-worktree salvage review and cleanup.
2. Completed: three fresh worker worktrees created from `codex/fill-native-cutover-gaps`.
3. Completed: main integrator converted `Vendor/swift-ssh-client` into a pinned submodule and updated diagnostics/tests.
4. Completed: main integrator landed shared CLI executor, simulator name-or-UDID resolution, duplicate-name rejection, and bounded long-log capture.
5. Completed: worker 1 probe artifact alias export integrated in the primary worktree.
6. Completed in the primary worktree: Phase 1 live blocker closure via explicit keyboard-input seam, event-first forwarding, fallback-only text-delta handling, deterministic keyboard/input tests, restored-live-state tests, and failure-path persistence/setup coverage.
7. Completed in the primary worktree: bounded follow-on helper extraction for `UITestLaunchSupport` and `SessionManager` only as far as required to stabilize live resume, host-backed routing, and off-window synthetic presentation metrics.
8. Completed: worker 2 and worker 3 were explicitly superseded from the primary worktree and retired after the accepted runner/live-fix stack was green.
9. Next: compare `main` against `codex/fill-native-cutover-gaps`, decide whether promotion can be a fast-forward or needs a fresh cherry-pick-only promotion branch, then finish final cleanup.

## Validation Commands
- Runner tests:
  - `swift test --package-path /Users/jeonseonghun/git-atjsh/Glassdeck/Tools/GlassdeckBuild`
- Canonical artifact inspection:
  - `swift run --package-path /Users/jeonseonghun/git-atjsh/Glassdeck/Tools/GlassdeckBuild glassdeck-build artifacts --command <build|test>`
- App build path:
  - `swift run --package-path /Users/jeonseonghun/git-atjsh/Glassdeck/Tools/GlassdeckBuild glassdeck-build build --scheme app`
- Follow-up UI validation after integration:
  - focused live Docker probe tests
  - live relaunch acceptance path

## Open Blockers
- No remaining live UI acceptance blocker in the primary worktree. The ordered validation stack is green on the accepted closure diff.
- No remaining worker-branch integration blocker. `codex/ui-harness-split` and `codex/session-state-tests` were superseded explicitly and retired from the primary worktree.
- Remaining closure work is promotion and final cleanup only:
  - compare `main` against `codex/fill-native-cutover-gaps` and choose fast-forward versus a fresh cherry-pick-only promotion branch
  - remove obsolete `temp/stale-worktree-patches/` artifacts once the final promotion stack proves they are fully superseded

## Environment Mitigations
- No active worker worktrees remain. The temporary framework-link and submodule-seeding mitigations were only needed during parallel worker validation and are no longer part of the active stack.
- Runner worktree root detection:
  - `glassdeck-build` now resolves alternate git worktree roots without assuming the checkout directory is literally named `Glassdeck`.
  - Verified earlier via `glassdeck-build doctor --dry-run` from the worker worktrees before they were retired.
- Live UI runner environment:
  - Earlier fallback remains valid: `glassdeck-build sim set-env` can still be used when a shell or CI context does not propagate the live Docker env into the UI test runner.
  - Current primary-worktree closure validation on simulator `B703B3A6-69A3-4B2C-815B-45BC91E16265` passed directly under the inherited live-Docker env in this shell session, so the canonical record for this wave is the exact `glassdeck-build test --scheme ui` commands listed below.

## Integrated Progress
- Main integrator:
  - Added `XcodeCommandExecutor` as the shared thin wrapper above `CommandExecutionContext`.
  - Added disk-backed process capture with bounded in-memory retention for long-running `xcodebuild` logs.
  - Updated `build` and `test` to resolve simulator names and UDIDs through `SimulatorLocator`, matching `run`.
  - Hardened simulator resolution so duplicate exact names fail loudly instead of selecting an arbitrary device.
  - Restored the missing UI-test synthetic terminal backend in source: `GhosttyKitSurfaceIO.emitInput`, synthetic-mode `GhosttySurface` behavior, and a SwiftUI `SyntheticTerminalPreview` so `terminal-surface-view` is visibly non-flat without forcing a real Ghostty surface in simulator UI tests.
  - Changed live-seeded UI-test launch snapshots so they always preserve reconnect intent; prompt-only and render-only probes no longer depend on a preloaded connected command to schedule the real SSH resume path.
  - Cleared synthetic preview transcripts at the live-shell handoff so prompt-only probes stop carrying seeded markers once SSH output begins.
  - Tightened the live probe tests to require live prompt evidence before render-only acceptance or command injection.
  - Added an explicit `SessionKeyboardInputSink` seam between `session-keyboard-host` and the terminal surface, with event-based forwarding as the primary path for typed characters, newline, and delete/backspace.
  - Kept text-delta forwarding only as the UIKit fallback path by handling `replace(_:withText:)`, `.editingChanged`, and `UITextField.textDidChangeNotification` without duplicating already-forwarded input.
  - Split the UI-test keyboard state from the keyboard host itself by adding a separate `session-keyboard-state` accessibility element and updating the live helpers to keep command injection end-to-end through `session-keyboard-host`.
  - Added deterministic keyboard-host bridge coverage proving event-path, replacement-fallback, newline preservation, and text-change fallback delivery into the synthetic terminal bridge.
  - Added deterministic restored-live-state and failure-path coverage for corrupted persistence snapshots, deferred live resume routing, preserved host-backed launch routing, and surfaced credential-persistence warnings.
  - Cleared corrupted persisted session snapshots on decode failure instead of silently retaining invalid data.
  - Added unchanged-snapshot skipping in session persistence without introducing broader write coalescing.
  - Surfaced runtime credential-persistence failures on otherwise-successful password connections via `runtimeWarningMessage` instead of treating them as connection failures.
  - Added explicit synthetic presentation preparation for off-window surfaces so manual live-connect and host-backed relaunch flows publish nonzero presentation metrics before first visible attachment.
  - Preserved the dirty `swift-ssh-client` PTY work on fork branch `atjsh/swift-ssh-client:glassdeck-submodule` at `0e50d6dba9d6d4aa082412796d233f96195768c2`.
  - Converted `Vendor/swift-ssh-client` from a tracked vendored directory into a real git submodule pointing at `https://github.com/atjsh/swift-ssh-client.git` on branch `glassdeck-submodule`.
  - Normalized the new submodule with `git submodule absorbgitdirs` so repo checks see standard gitfile-based submodule layout.
  - Added diagnostics coverage proving that gitfile-based submodule layout no longer triggers the standalone nested-checkout warning.
  - Fixed `WorkspaceContext.current()` so `glassdeck-build` works from alternate git worktree names instead of assuming a root directory named `Glassdeck`.
  - Seeded all active worker worktrees with transient `GhosttyKit.xcframework` framework links and local state markers so direct `xcodebuild` validation can continue without committing framework artifacts.
- Worker integration:
  - Integrated worker 1 commit `a6f503a` as primary commit `0896d26` to export stable alias outputs for `screen.png`, `terminal.png`, and `ui-tree.txt`.
  - Integrated the remaining accepted worker 1 runner slice from `9b815de` by landing primary commits `6b0b2e0` (`Resolve simulator for build/test commands`) and `3c99bb5` (`Align runner tests with executor preview API`) after conflict resolution against the current executor/output-mode API.
  - Removed worker 1 worktree `/Users/jeonseonghun/git-atjsh/.worktrees/glassdeck-runner-artifacts` and deleted local branch `codex/runner-artifact-aliases` once the runner slice was green in the primary worktree.
  - Committed the green primary closure diff as `8594055` (`Close native cutover live probe blocker`) before further worker integration so the accepted live-fix baseline is no longer just dirty worktree state.
  - Explicitly superseded worker 2 branch `codex/ui-harness-split` and retired its worktree because the current primary harness already carried the stricter deferred-live-resume path and the remaining worker diff would weaken the accepted command probe path.
  - Recovered worker 3's only still-useful persistence gap directly in primary commit `561d969` (`Migrate legacy external display routing on restore`), added restored-persistence coverage for idempotent restore and empty-snapshot clearing, then retired branch `codex/session-state-tests` and its worktree as superseded.
- Validation:
  - `swift test --package-path /Users/jeonseonghun/git-atjsh/Glassdeck/Tools/GlassdeckBuild`
  - Status: passing on 2026-03-24 after the executor, bounded-capture, simulator-resolution, alias-export, and worktree-detection changes. Current total: 93 tests.
  - `swift test --filter SSHClientTests.SSHShellPTYTests` in `/Users/jeonseonghun/git-atjsh/Glassdeck/Vendor/swift-ssh-client`
  - Status: passing on 2026-03-24 for the preserved PTY fork branch.
  - `swift run --package-path /Users/jeonseonghun/git-atjsh/Glassdeck/Tools/GlassdeckBuild glassdeck-build build --scheme app --simulator 48B92811-6D0D-4E23-A157-2B201386D6A0 --dry-run`
  - Status: dry-run prints an `xcodebuild` destination using the exact assigned UDID.
  - `swift run --package-path /Users/jeonseonghun/git-atjsh/Glassdeck/Tools/GlassdeckBuild glassdeck-build doctor --dry-run`
  - Status: from each worker worktree, dry-run now resolves the actual worktree root instead of an invalid `.../Glassdeck` path.
  - `swift run --package-path /Users/jeonseonghun/git-atjsh/Glassdeck/Tools/GlassdeckBuild glassdeck-build test --scheme unit --simulator B703B3A6-69A3-4B2C-815B-45BC91E16265 --only-testing GlassdeckAppTests/SessionPersistenceTests/testSessionManagerCanPrimeRestoredSessionWithoutPreparingSurface --only-testing GlassdeckAppTests/SessionPersistenceTests/testPrimeSyntheticPreviewSessionCanFreezeConnectedPresentationWithoutRestore`
  - Status: passing on 2026-03-24 through the native runner.
  - `swift run --package-path /Users/jeonseonghun/git-atjsh/Glassdeck/Tools/GlassdeckBuild glassdeck-build build --scheme ui --simulator A3493C6A-A636-470F-BF4D-72BBDE6720BB`
  - Status: passing on 2026-03-24; the dirty UI harness/project slice compiles cleanly through the runner.
  - `swift run --package-path /Users/jeonseonghun/git-atjsh/Glassdeck/Tools/GlassdeckBuild glassdeck-build test --scheme ui --simulator A3493C6A-A636-470F-BF4D-72BBDE6720BB --only-testing GlassdeckAppUITests/GlassdeckAppUITests/testSessionRowTapNavigatesToDetail`
  - Status: passing on 2026-03-24 through the native runner, which narrows the remaining UI risk to live Docker/probe-specific behavior rather than generic navigation launch failures.
  - `swift run --package-path /Users/jeonseonghun/git-atjsh/Glassdeck/Tools/GlassdeckBuild glassdeck-build sim boot --simulator A3493C6A-A636-470F-BF4D-72BBDE6720BB`
  - `swift run --package-path /Users/jeonseonghun/git-atjsh/Glassdeck/Tools/GlassdeckBuild glassdeck-build sim set-env --simulator A3493C6A-A636-470F-BF4D-72BBDE6720BB --host 192.168.0.45 --port 22222 --user glassdeck --password glassdeck --key-path /Users/jeonseonghun/git-atjsh/Glassdeck/Scripts/docker/fixtures/keys/glassdeck_ed25519`
  - `swift run --package-path /Users/jeonseonghun/git-atjsh/Glassdeck/Tools/GlassdeckBuild glassdeck-build test --scheme ui --simulator A3493C6A-A636-470F-BF4D-72BBDE6720BB --only-testing GlassdeckAppUITests/DockerLiveProbeUITests/testPromptOnlyProbeShowsShellPromptAndCheckpointNaming`
  - `swift run --package-path /Users/jeonseonghun/git-atjsh/Glassdeck/Tools/GlassdeckBuild glassdeck-build sim unset-env --simulator A3493C6A-A636-470F-BF4D-72BBDE6720BB`
  - Status: passing on 2026-03-24 through the native runner when the simulator-side environment is injected with `sim set-env`. The same test skips if only shell env is provided to `glassdeck-build test`.
  - `swift run --package-path /Users/jeonseonghun/git-atjsh/Glassdeck/Tools/GlassdeckBuild glassdeck-build test --scheme unit --simulator B703B3A6-69A3-4B2C-815B-45BC91E16265 --only-testing GlassdeckAppTests/TerminalRenderingConsistencyTests`
  - Status: passing on 2026-03-24 through the native runner after restoring the missing synthetic-terminal source path. Current result: 4 tests executed, 1 skipped, 0 failures.
  - `swift run --package-path /Users/jeonseonghun/git-atjsh/Glassdeck/Tools/GlassdeckBuild glassdeck-build test --scheme ui --simulator B703B3A6-69A3-4B2C-815B-45BC91E16265 --only-testing GlassdeckAppUITests/GlassdeckAppUITests/testEmptyLaunchShowsConnectionsRoot --only-testing GlassdeckAppUITests/GlassdeckAppUITests/testSessionScenarioTerminalScreenshotIsNotBlank --only-testing GlassdeckAppUITests/GlassdeckAppUITests/testSessionScenarioHonorsSeededLightTerminalTheme --only-testing GlassdeckAppUITests/GlassdeckAppUITests/testAnimationScenarioAdvancesFramesAndRendersTerminal`
  - Status: passing on 2026-03-24 through the native runner after reconciling the synthetic backend and SwiftUI preview fallback in source. This revalidated the non-live UI screenshot cluster on the same simulator used for local debugging.
  - `swift run --package-path /Users/jeonseonghun/git-atjsh/Glassdeck/Tools/GlassdeckBuild glassdeck-build sim set-env --simulator B703B3A6-69A3-4B2C-815B-45BC91E16265 --host 192.168.0.45 --port 22222 --user glassdeck --password glassdeck --key-path /Users/jeonseonghun/git-atjsh/Glassdeck/Scripts/docker/fixtures/keys/glassdeck_ed25519`
  - `swift run --package-path /Users/jeonseonghun/git-atjsh/Glassdeck/Tools/GlassdeckBuild glassdeck-build test --scheme ui --simulator B703B3A6-69A3-4B2C-815B-45BC91E16265 --only-testing GlassdeckAppUITests/DockerLiveProbeUITests/testPromptOnlyProbeShowsShellPromptAndCheckpointNaming`
  - `swift run --package-path /Users/jeonseonghun/git-atjsh/Glassdeck/Tools/GlassdeckBuild glassdeck-build sim unset-env --simulator B703B3A6-69A3-4B2C-815B-45BC91E16265`
  - Status: passing on 2026-03-24 in the primary worktree after the live-shell handoff fix. The prompt-only probe now proves live prompt output without seeded preview markers.
  - `swift run --package-path /Users/jeonseonghun/git-atjsh/Glassdeck/Tools/GlassdeckBuild glassdeck-build test --scheme unit --simulator B703B3A6-69A3-4B2C-815B-45BC91E16265 --only-testing GlassdeckAppTests/SessionPersistenceTests`
  - Status: passing on 2026-03-24 through the native runner before the final closure pass. This suite is now supplemented by deterministic live-resume and off-window synthetic-presentation coverage in the current primary closure baseline.
  - `swift run --package-path /Users/jeonseonghun/git-atjsh/Glassdeck/Tools/GlassdeckBuild glassdeck-build test --scheme unit --simulator B703B3A6-69A3-4B2C-815B-45BC91E16265 --only-testing GlassdeckAppTests/SessionPersistenceTests`
  - Status: passing on 2026-03-24 after recovering the legacy external-display routing fallback and restoring the idempotent/empty-snapshot persistence coverage. Result bundle: `/Users/jeonseonghun/git-atjsh/Glassdeck/.build/glassdeck-build/results/test/20260324-061027-unit.xcresult`. Summary: `/Users/jeonseonghun/git-atjsh/Glassdeck/.build/glassdeck-build/artifacts/test/20260324-061027-unit/summary.txt`.
  - `~/Library/Logs/DiagnosticReports/Glassdeck-2026-03-24-014338.ips`
  - `~/Library/Logs/DiagnosticReports/Glassdeck-2026-03-24-014505.ips`
  - Status: historical worker-simulator crash reports showing SIGABRT during `GhosttySurface.createSurface()` → `SessionManager.prepareSurface()` → `UITestLaunchSupport` while forcing preview-surface creation. Keep them as related preview-surface diagnostics, but they were not reproduced in the final primary closure validation stack.
  - `swift run --package-path /Users/jeonseonghun/git-atjsh/Glassdeck/Tools/GlassdeckBuild glassdeck-build test --scheme unit --simulator B703B3A6-69A3-4B2C-815B-45BC91E16265 --only-testing GlassdeckAppTests/SessionKeyboardIMETests --only-testing GlassdeckAppTests/SessionPersistenceTests --only-testing GlassdeckAppTests/TerminalRenderingConsistencyTests --only-testing GlassdeckAppTests/AppLaunchRoutingTests`
  - Status: passing on 2026-03-24 in the current primary closure baseline. Result bundle: `/Users/jeonseonghun/git-atjsh/Glassdeck/.build/glassdeck-build/results/test/20260324-054150-unit.xcresult`. Summary: `/Users/jeonseonghun/git-atjsh/Glassdeck/.build/glassdeck-build/artifacts/test/20260324-054150-unit/summary.txt`.
  - `swift run --package-path /Users/jeonseonghun/git-atjsh/Glassdeck/Tools/GlassdeckBuild glassdeck-build test --scheme ui --simulator B703B3A6-69A3-4B2C-815B-45BC91E16265 --only-testing GlassdeckAppUITests/DockerLiveUITests/testLiveDockerClipboardSeedFailsWhenKeyMaterialIsMissing --only-testing GlassdeckAppUITests/DockerLiveUITests/testLiveDockerClipboardSeedFailsWhenKeyMaterialIsUnreadable --only-testing GlassdeckAppUITests/GlassdeckAppUITests/testEmptyLaunchShowsConnectionsRoot --only-testing GlassdeckAppUITests/GlassdeckAppUITests/testSessionScenarioTerminalScreenshotIsNotBlank --only-testing GlassdeckAppUITests/GlassdeckAppUITests/testSessionScenarioHonorsSeededLightTerminalTheme --only-testing GlassdeckAppUITests/GlassdeckAppUITests/testAnimationScenarioAdvancesFramesAndRendersTerminal --only-testing GlassdeckAppUITests/GlassdeckAppUITests/testSessionScenarioExposesSeparateKeyboardStateElement`
  - Status: passing on 2026-03-24 in the current primary closure baseline. Result bundle: `/Users/jeonseonghun/git-atjsh/Glassdeck/.build/glassdeck-build/results/test/20260324-054235-ui.xcresult`. Summary: `/Users/jeonseonghun/git-atjsh/Glassdeck/.build/glassdeck-build/artifacts/test/20260324-054235-ui/summary.txt`.
  - `swift run --package-path /Users/jeonseonghun/git-atjsh/Glassdeck/Tools/GlassdeckBuild glassdeck-build test --scheme ui --simulator B703B3A6-69A3-4B2C-815B-45BC91E16265 --only-testing GlassdeckAppUITests/DockerLiveProbeUITests/testPromptOnlyProbeShowsShellPromptAndCheckpointNaming`
  - Status: passing on 2026-03-24 in the current primary closure baseline. Result bundle: `/Users/jeonseonghun/git-atjsh/Glassdeck/.build/glassdeck-build/results/test/20260324-054405-ui.xcresult`. Summary: `/Users/jeonseonghun/git-atjsh/Glassdeck/.build/glassdeck-build/artifacts/test/20260324-054405-ui/summary.txt`.
  - `swift run --package-path /Users/jeonseonghun/git-atjsh/Glassdeck/Tools/GlassdeckBuild glassdeck-build test --scheme ui --simulator B703B3A6-69A3-4B2C-815B-45BC91E16265 --only-testing GlassdeckAppUITests/DockerLiveProbeUITests/testCommandInjectionOnlyProbeInjectsFullCommandAndCapturesSummary`
  - Status: passing on 2026-03-24 in the current primary closure baseline. This closes the primary live UI blocker. Result bundle: `/Users/jeonseonghun/git-atjsh/Glassdeck/.build/glassdeck-build/results/test/20260324-054451-ui.xcresult`. Summary: `/Users/jeonseonghun/git-atjsh/Glassdeck/.build/glassdeck-build/artifacts/test/20260324-054451-ui/summary.txt`.
  - `swift run --package-path /Users/jeonseonghun/git-atjsh/Glassdeck/Tools/GlassdeckBuild glassdeck-build test --scheme ui --simulator B703B3A6-69A3-4B2C-815B-45BC91E16265 --only-testing GlassdeckAppUITests/DockerLiveProbeUITests/testRenderOnlyProbeCapturesVisibleTerminalSurface`
  - Status: passing on 2026-03-24 in the current primary closure baseline. Result bundle: `/Users/jeonseonghun/git-atjsh/Glassdeck/.build/glassdeck-build/results/test/20260324-054527-ui.xcresult`. Summary: `/Users/jeonseonghun/git-atjsh/Glassdeck/.build/glassdeck-build/artifacts/test/20260324-054527-ui/summary.txt`.
  - `swift run --package-path /Users/jeonseonghun/git-atjsh/Glassdeck/Tools/GlassdeckBuild glassdeck-build test --scheme ui --simulator B703B3A6-69A3-4B2C-815B-45BC91E16265 --only-testing GlassdeckAppUITests/DockerLiveUITests/testPasswordAuthSessionRelaunchesIntoDetailWithoutBlankTerminal`
  - Status: passing on 2026-03-24 in the current primary closure baseline. This confirms the off-window synthetic-presentation fix keeps the relaunch path out of the blank-terminal placeholder state. Result bundle: `/Users/jeonseonghun/git-atjsh/Glassdeck/.build/glassdeck-build/results/test/20260324-054605-ui.xcresult`. Summary: `/Users/jeonseonghun/git-atjsh/Glassdeck/.build/glassdeck-build/artifacts/test/20260324-054605-ui/summary.txt`.

## Next Pending Step
- Compare `main` against `codex/fill-native-cutover-gaps` and choose the clean promotion path: fast-forward if the branch already matches the desired final stack, otherwise create a fresh promotion branch from `main` and cherry-pick only the accepted final commits in order.
- Re-run the validation required for promotion on the chosen final stack, then fast-forward `main`.
- Remove obsolete `temp/stale-worktree-patches/` artifacts only after the promoted stack proves they are fully superseded.
