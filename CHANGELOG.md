# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Repository scaffolding for public hosting:
  - MIT license
  - Contributing guide
  - GitHub issue and PR templates
  - GitHub Actions CI workflow for macOS tests
- Release packaging pipeline:
  - `scripts/package_release.sh` to build `Zoontag-macOS.zip`
  - GitHub Actions release workflow that uploads package assets on `v*` tags

### Changed
- Expanded `.gitignore` for Xcode/macOS and test artifacts.
- Stopped tracking user-specific Xcode workspace files (`xcuserdata` and breakpoints).
- Refactored README for end-user and developer onboarding.
- Clarified README "Get Zoontag" instructions so source build is the default path, release ZIP install is optional when assets are published, and unsigned-app launch guidance matches the current macOS `Open Anyway` flow.
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
