# Glassdeck Agent Workflow

This repository uses a test-first workflow for all non-trivial changes.

## Required order of work

1. Define or update the relevant interfaces, types, and test cases first.
2. Write failing tests before implementation for new behavior.
3. Implement only after the tests and type boundaries make the change explicit.
4. Run the targeted validations for the touched area before asking for integration.

## Worktree policy

- Every writing sub-agent must use a dedicated git worktree.
- Worktree ownership must be explicit and disjoint by file or module.
- Main integration happens in the primary worktree only after the worker branch is green.
- Do not let multiple agents edit the same file concurrently.

## Commit policy

- Keep commit topics small and green.
- Tests and implementation may be developed incrementally in a topic branch, but they should be committed together only after the topic passes.
- Do not inherit the current git index blindly. Stage intentionally for each commit.

## Required validation

- Runner changes: `swift test --package-path Tools/GlassdeckBuild`
- App build/test changes: run the relevant `glassdeck-build` command for the touched scheme or flow
- Script changes: run the shebang-appropriate syntax check before merge

## Canonical artifact inspection

Use the runner as the source of truth for generated artifacts:

```bash
swift run --package-path Tools/GlassdeckBuild glassdeck-build artifacts --command <build|test>
```

## Implementation defaults

- Prefer explicit over clever.
- Flag and remove repetition aggressively.
- Add tests for edge cases rather than relying on manual verification alone.
- Keep abstractions shallow unless duplication or coupling clearly justifies a new layer.
