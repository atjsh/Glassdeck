# Native Cutover Closure Context Ledger

Last updated: 2026-03-24

## Integration State
- Primary integration worktree: `/Users/jeonseonghun/git-atjsh/Glassdeck`
- Primary branch: `codex/fill-native-cutover-gaps`
- Primary HEAD: `5be0f1a97bcba4ddd6cd0b377528585537f90c51`
- Landed base commits:
  - `e01c2e5060a07578d22f19526ec28d22a8159a30` `Create native cutover baseline snapshot`
  - `5be0f1a97bcba4ddd6cd0b377528585537f90c51` `Implement runner artifact export cleanup`

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
  - Branch: `codex/runner-artifact-aliases`
  - Worktree: `/Users/jeonseonghun/git-atjsh/.worktrees/glassdeck-runner-artifacts`
  - Ownership: `Tools/GlassdeckBuild/Sources/GlassdeckBuildCore/Artifacts/`, minimal `XcodeInvoker`, matching runner tests
  - Simulator: `iPhone 17 Pro` `8647FB0C-AD1D-4A0D-81E1-814D1877FC15`
- Worker 2:
  - Model: `gpt-5.3-codex-spark`
  - Branch: `codex/ui-harness-split`
  - Worktree: `/Users/jeonseonghun/git-atjsh/.worktrees/glassdeck-ui-harness`
  - Ownership: `Glassdeck/App/`, `Tests/GlassdeckAppUITests/`, plus only the artifact-name mapping touchpoint required by probe export
  - Simulator: `iPhone 17 Pro Max` `8BA84984-26FB-41EC-A0E3-748C658FBCD4`
- Worker 3:
  - Model: `gpt-5.3-codex-spark`
  - Branch: `codex/session-state-tests`
  - Worktree: `/Users/jeonseonghun/git-atjsh/.worktrees/glassdeck-session-state`
  - Ownership: `Glassdeck/Models/SessionManager.swift`, `Tests/GlassdeckAppTests/`
  - Simulator: `iPhone Air` `48B92811-6D0D-4E23-A157-2B201386D6A0`
- Team rule:
  - Keep exactly one researcher and three writing workers.
  - Do not spawn additional sub-agents.
  - Reuse the same agents for the rest of the project.
  - Do not share or overlap simulator instances across workers.

## Execution Order
1. Finish stale-worktree salvage review and remove the remaining stale worktrees/branches.
2. Create the three fresh worker worktrees from `codex/fill-native-cutover-gaps`.
3. Main integrator converts `Vendor/swift-ssh-client` into a pinned submodule and updates diagnostics/tests.
4. Main integrator lands shared CLI executor and bounded or disk-backed long-log capture.
5. Worker 1 lands probe artifact alias export and stable inspection path coverage.
6. Worker 2 lands UI harness split, seeded-vs-live marker separation, and lighter non-failure checkpoint capture.
7. Worker 3 lands `SessionManager` helper extraction and persistence/routing/preview invariant tests.
8. Integrate green worker commits non-interactively in the primary worktree only.

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
- `Vendor/swift-ssh-client` is still a standalone nested checkout rather than a pinned submodule.
- Stable probe aliases `screen.png`, `terminal.png`, and `ui-tree.txt` are defined but not yet fully produced end-to-end.
- The UI harness still mixes seeded preview and live-success evidence in a way that can go false-green.
- The nested `Vendor/swift-ssh-client` checkout contains uncommitted local changes, so submodule conversion needs a preserved fork or explicit salvage path before replacement.

## Integrated Progress
- Main integrator:
  - Added `XcodeCommandExecutor` as the shared thin wrapper above `CommandExecutionContext`.
  - Added disk-backed process capture with bounded in-memory retention for long-running `xcodebuild` logs.
  - Updated `build` and `test` to resolve simulator names and UDIDs through `SimulatorLocator`, matching `run`.
  - Hardened simulator resolution so duplicate exact names fail loudly instead of selecting an arbitrary device.
  - Preserved the dirty `swift-ssh-client` PTY work on fork branch `atjsh/swift-ssh-client:glassdeck-submodule` at `0e50d6dba9d6d4aa082412796d233f96195768c2`.
  - Converted `Vendor/swift-ssh-client` from a tracked vendored directory into a real git submodule pointing at `https://github.com/atjsh/swift-ssh-client.git` on branch `glassdeck-submodule`.
  - Normalized the new submodule with `git submodule absorbgitdirs` so repo checks see standard gitfile-based submodule layout.
  - Added diagnostics coverage proving that gitfile-based submodule layout no longer triggers the standalone nested-checkout warning.
- Validation:
  - `swift test --package-path /Users/jeonseonghun/git-atjsh/Glassdeck/Tools/GlassdeckBuild`
  - Status: passing on 2026-03-24 after the executor, bounded-capture, and simulator-resolution changes.
  - `swift test --filter SSHClientTests.SSHShellPTYTests` in `/Users/jeonseonghun/git-atjsh/Glassdeck/Vendor/swift-ssh-client`
  - Status: passing on 2026-03-24 for the preserved PTY fork branch.
  - `swift run --package-path /Users/jeonseonghun/git-atjsh/Glassdeck/Tools/GlassdeckBuild glassdeck-build build --scheme app --simulator 48B92811-6D0D-4E23-A157-2B201386D6A0 --dry-run`
  - Status: dry-run prints an `xcodebuild` destination using the exact assigned UDID.

## Next Pending Step
- Stage and land the dependency-closure commit cleanly, then continue integrating worker slices while the saved runner changes stay green.
