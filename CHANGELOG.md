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
- Lowered `MACOSX_DEPLOYMENT_TARGET` to `14.0` so GitHub Actions `macos-14` runners can build and test successfully.
