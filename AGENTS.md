# Repository Guidelines

## Project Structure & Module Organization
Swift sources live under `Zoontag/`: `ZoontagApp` wires the SwiftUI scene, `ContentView` renders the grid/sidebar loop, `QueryState` tracks include/exclude tags, and `MetadataSearchController` orchestrates Spotlight, mdfind, and filesystem fallbacks. Helper models such as `FinderTag`, `FacetCounter`, and Spotlight utilities sit beside the controller so UI files stay presentation-only. Tests mirror that layout in `ZoontagTests/`, and shared assets (icons, previews) are inside `Zoontag/Assets.xcassets`. When adding a feature, keep files near the layer they extend (UI, controller, models) to preserve the current separation.

## Build, Test, and Development Commands
- `open Zoontag.xcodeproj` — launch the project in Xcode for previews and manual runs.
- `xcodebuild -scheme Zoontag -configuration Debug build` — deterministic CLI build (switch to `Release` for profiling).
- `xcodebuild test -scheme Zoontag -destination 'platform=macOS' -derivedDataPath "$(pwd)/.build/DerivedData"` — runs the XCTest suite and avoids sharing DerivedData with other projects. Prefix with `SCRIPT_ENV=ci` (see scripts) if you add automation. Always re-run tests after touching Spotlight logic or query parsing.

## Coding Style & Naming Conventions
Follow Swift API Design Guidelines: PascalCase types, camelCase members, four-space indentation, and descriptive argument labels. Prefer immutable `let`, keep structs equatable when sensible, and isolate Spotlight-specific helpers (e.g., `SpotlightTagQueryBuilder`) from UI code. User-visible strings should use `LocalizedStringKey` or `Text("…", tableName:)` so localization stays possible. Use Xcode’s “Re-Indent” or `swiftformat` if introduced; don’t mix tabs and spaces.

## Testing Guidelines
Add or update XCTest cases in `ZoontagTests` whenever you change query composition, Finder-tag parsing, or facet math. Name suites `<Thing>Tests` and functions `test_<behavior>_when_<condition>()` so failures describe intent. Tests may stub metadata responses—if a behavior is hard to express (e.g., security-scoped URLs), document the manual verification in the test file comments. CI/automation should run the full `xcodebuild test …` command before merging.

## Commit & Branch Practices
Work off `main` using intent-focused branches such as `fix-tag-colors` or `feat-thumbnail-grid`. Commits follow Conventional Commits (`fix(search): guard security scope failures`) and stay small enough to review quickly. Each commit message body should summarize root cause or rationale, and any user-facing change must update README/docs as needed. Before merging, inspect `git status` / `git diff`, ensure tests pass, and remove dead debugging prints. Merge locally (no PRs) and delete the branch when finished.

## Spotlight & Security Notes
Feature work must respect Finder tags and scopes: request security-scoped bookmarks when sandboxing, release them in `deinit`, and surface permission failures via `SpotlightDiagnostics` errors. Tag colors are encoded as `"name\nN"`; always parse before displaying, and perform facet counts on normalized names to avoid splitting colored variants. When fallback enumeration is active, skip packages unless a feature needs to descend, and consider Task-based cancellation for long scans so the UI stays responsive.
