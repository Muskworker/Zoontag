# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.3.0] - 2026-03-27

### Added
- **Spanish (Latin America / US) localization** (`es-419`): all user-visible strings — tag chip headings, sort options, color names, results counts, error messages, and tag field placeholders — are now translated into Spanish. Surfaces to users whose macOS preferred language is set to Español (Latinoamérica).
- **Include subfolders** checkbox above the results grid. When unchecked, only files directly inside the chosen folder are shown — subdirectory contents are excluded from results and from the tag autocomplete catalog. The setting persists across launches. Default is checked (existing behavior preserved).
- Two new sort options in the results toolbar: **Tag Count (Fewest)** and **Tag Count (Most)**. Sorting by fewest tags first surfaces untagged and undertagged files so you can systematically improve tagging coverage.
- Localization infrastructure: `Localizable.xcstrings` string catalog added to the Zoontag target. Sort option titles, color picker labels, results count text, and `FinderTagEditor` error descriptions now route through `String(localized:)` so the app can be translated without source changes. SwiftUI `Text("…")` literals throughout `ContentView` are auto-extracted into the catalog by the build system.

### Fixed
- Folders now appear consistently in search results regardless of query type. Previously, folders were visible in exclude-only tag queries (via mdfind) but invisible in blank queries and include-tag queries (via the enumeration backend, which filtered to regular files only). Both backends now share a single eligibility predicate that accepts regular files and directories.
- Moved the **Clear Query** button (formerly "Clear Tags") from the toolbar into the Query box in the left sidebar, where it correctly belongs alongside the include/exclude tag controls. Its previous placement in the toolbar's trailing area gave the false impression it would clear tags from the selected file.
- Results count label in the toolbar now has balanced horizontal padding, matching the inset of adjacent toolbar buttons.
- Removed stray `Divider` that added asymmetric left-side spacing to the results count.

## [1.2.0] - 2026-03-22

### Fixed
- Tag edits (add/remove in the inspector) now immediately refresh the left-pane facet counts, the center grid, and the inspector tag list.
  - Result cache is invalidated after every tag edit so the next search always fetches fresh data.
  - Tag hydration now reads from extended attributes first (the authoritative, immediately-updated source) instead of the Spotlight MDItem index, which may lag behind writes.
  - A client-side filter is applied after hydration to drop results whose on-disk tags no longer satisfy the current include/exclude filters, so all facet counts stay consistent when Spotlight hasn't yet re-indexed an edited file.
  - The inspector panel now remains populated with the edited file(s) and their fresh tags even when a tag edit causes those files to drop out of the search results, allowing further edits without re-selecting.

### Added
- Repository scaffolding for public hosting:
  - MIT license
  - Contributing guide
  - GitHub issue and PR templates
  - GitHub Actions CI workflow for macOS tests
- Release packaging pipeline:
  - `scripts/package_release.sh` to build `Zoontag-macOS.zip`
  - GitHub Actions release workflow that uploads package assets on `v*` tags
- Screenshot (`docs/screenshots/zoontag-main.png`) embedded in README

### Changed
- Expanded `.gitignore` for Xcode/macOS and test artifacts.
- Stopped tracking user-specific Xcode workspace files (`xcuserdata` and breakpoints).
- Reworked README: prebuilt release download is now the primary install path, source build moved to the developer section, "How to Use" reorganized into scope/filter/manage-tags workflow stages, "Current Capabilities" replaced with a concise feature summary, repository URL placeholder resolved, and unsigned-app guidance reformatted as a note.
- Lowered `MACOSX_DEPLOYMENT_TARGET` to `14.0` so GitHub Actions `macos-14` runners can build and test successfully.
- Updated GitHub Actions workflows to run on `macos-latest` and select the latest stable Xcode before test/package steps.
- Fixed tag editor autocomplete so exact typed tag names consistently apply known Finder colors.
- Added keyboard autocomplete controls in tag editor (`Up`/`Down` to navigate suggestions, `Tab` to accept).
- Added a left-sidebar query tag input with autosuggestions so users can include, exclude, or remove tags even when they are not present in top facets.
- Fixed a query execution deadlock that could leave searches stuck (spinning throbber) when running broad exclude-only tag filters.
- Added multi-file result selection (`Cmd`-click) so inspector tag add/remove actions can update all selected files at once.
- Added a center-pane sort control for search results with common file ordering options (name, modified date, created date, and size).
- Added explicit result coverage reporting (`N`, `N of M`, or `N+`) and incremental paging with a `Load More` control for large result sets.
- Added a toolbar `Stop` action to cancel in-progress searches.
- Updated `Load More` pagination so each page follows the active sort order (new pages append as the next slice of that ordering).
- Cached sortable search candidates per query so `Load More` and sort changes can reuse the prior scan instead of rescanning the full scope.
- Added progressive result refinement for large first-time scans (quick preview first, then full sorted page).
- Streamed `mdfind` output so preview results can render before full command completion.
- Fixed a crash in streamed `mdfind` parsing when draining buffered paths across multiple partial reads.
- Prevented immediate re-sorting of stale results on sort changes while a refresh is still in progress.
- Persisted workspace session state across launches (security-scoped folder bookmark, include/exclude filters, sort option, and detail-pane visibility).
- Added a background per-scope tag index so sidebar query autocomplete stays global to the selected scope instead of shrinking with the current filtered results.
