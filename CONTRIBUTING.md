# Contributing to Zoontag

Thanks for contributing. This project uses a small-change, high-confidence workflow.

## Development Setup

1. Open `Zoontag.xcodeproj` in Xcode, or use CLI commands from the README.
2. Work from a short-lived branch named for intent (for example, `fix-tag-query`).
3. Add/adjust tests for behavior changes before implementing when practical.

## Required Checks

Run these before merging:

```bash
xcodebuild build -scheme Zoontag -configuration Debug
xcodebuild test -scheme Zoontag -destination 'platform=macOS' -derivedDataPath "$(pwd)/.build/DerivedData"
```

At minimum, run the `xcodebuild test ...` command if your change touches query parsing, Spotlight integration, or facet counting.

## Commit Style

Use Conventional Commits:

- `feat: ...`
- `fix: ...`
- `docs: ...`
- `refactor: ...`
- `test: ...`
- `chore: ...`

Prefer small commits that are easy to review and revert.

## Merge Flow

This repository currently uses local merge flow (no PR requirement):

1. `git switch main`
2. `git merge --no-ff <branch>`
3. `git branch -d <branch>`

If a remote is configured, push `main` after local validation.

## Creating a Release

Tagging with `v*` triggers the GitHub release workflow, which attaches:

- `Zoontag-macOS.zip`
- `Zoontag-macOS.zip.sha256`

Example:

```bash
git tag v1.0.0
git push origin v1.0.0
```
