# Repository Guidelines

## Project Structure & Module Organization
The SwiftUI app lives in `Zoontag/` with lightweight modules: `QueryState` provides the tag/filter model, `MetadataSearchController` drives Spotlight queries, `FacetCounter` summarizes tags for the sidebar, and `ZoontagApp` plus `ContentView` compose the UI. Shared data structures live in `Models.swift`, while Finder assets sit in `Assets.xcassets`. Tests reside in `ZoontagTests/ZoontagTests.swift`. Keep new code close to the existing file that owns the same layer (state, controller, or UI) so component boundaries stay clear.

## Build, Test, and Development Commands
- `open Zoontag.xcodeproj` — launch the project in Xcode for interactive SwiftUI previews.
- `xcodebuild -scheme Zoontag -configuration Debug build` — CI-friendly build; use the `Release` configuration before distribution.
- `xcodebuild test -scheme Zoontag -destination 'platform=macOS'` — run the XCTest suite; add `-only-testing:ZoontagTests/Name` for focused runs.

## Coding Style & Naming Conventions
Follow Swift API Design Guidelines: types in PascalCase, methods/properties in camelCase, and prefer immutable `let` over `var`. Indent with four spaces, match the concise initializer patterns already in `QueryState.swift`, and keep files Swift-format clean (Xcode’s `Editor > Structure > Re-Indent` is the canonical formatter). Localized strings funnel through SwiftUI’s `LocalizedStringKey` so user-facing text can be translated later.

## Testing Guidelines
Use XCTest inside `ZoontagTests`. Name test cases `<Feature>Tests` (e.g., `MetadataSearchControllerTests`) and individual tests `test_<behavior>`. Cover every new user-visible behavior with at least one deterministic test; network or filesystem interactions should be wrapped so they can be mocked. Run `xcodebuild test …` before merging and include negative cases when changing Spotlight query construction or facet math.

## Commit & Branch Flow
Create intent-focused branches (`feat-preview-pane`, `fix-tag-filter`) from `main`. Commits follow Conventional Commits (`fix(search): clamp scoped queries`) and should mention the root cause or motivation in the body. Keep diffs small, review them locally (`git status`, `git diff`), and merge back into `main` once tests pass. Include doc or changelog updates whenever behavior changes the UX; remove branches after merging to keep the tree clean.

## Finder & Security Notes
The app depends on Finder tags and Spotlight scopes. When adding code that touches user-selected folders, ensure you request bookmarks/security-scoped URLs when sandboxing, and never cache file metadata outside the user’s chosen scope. Handle permission failures gracefully so the query UI never blocks.
