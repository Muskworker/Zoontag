# Zoontag

Zoontag is a macOS tag-first file browser. It uses Finder tags and Spotlight to let you drill into files quickly without maintaining a separate media database.

## For End Users

### Requirements
- macOS 14 or later

### Get Zoontag
Current path (always available):

1. Download this repository (or clone it).
2. Open `Zoontag.xcodeproj` in Xcode.
3. Run the `Zoontag` scheme.

Optional prebuilt package (when available on a tagged release):

1. Open the repository's GitHub **Releases** page.
2. Download `Zoontag-macOS.zip`.
3. Unzip and move `Zoontag.app` to `/Applications`.
4. Launch Zoontag.

If macOS blocks launch because the app is unsigned:
1. Try to open `Zoontag.app` once, then dismiss the warning.
2. Open `System Settings > Privacy & Security`.
3. In the Security section, click **Open Anyway** for Zoontag and confirm.

Apple notes that **Open Anyway** is available for about one hour after the blocked launch attempt.

### How to Use
1. Choose a folder to search.
2. Browse matching files in the grid, and use the center-pane **Sort** menu to order by name, date modified, date created, or file size.
3. Use sidebar tag controls to refine:
   - `+` include a tag
   - `-` exclude a tag
   - In **Query > Find tag**, type any tag name (not only top tags), then:
     - `+` include typed tag
     - `-` exclude typed tag
     - `x` remove that tag from current query filters
   - `Up` / `Down` navigate autosuggestions, `Tab` accepts highlighted suggestion
4. Remove active tag chips to widen results.
5. Select one or more files in the grid:
   - Click to select one file
   - `Cmd`-click to add/remove files from the current selection
6. In the inspector "Add Tag" input, use autocomplete:
   - `Up` / `Down` to choose suggestions
   - `Tab` to accept the highlighted suggestion and apply its known Finder color
   - Add/remove actions apply to all currently selected files

### Current Capabilities
- Finder-tag search via Spotlight (`NSMetadataQuery`)
- Include/exclude boolean filtering on tags
- Sidebar facets computed from the current result set
- Sidebar query-tag autosuggest input for include/exclude/remove actions on any tag name
- Tag editor autocomplete with keyboard navigation (`Up`/`Down` + `Tab` complete)
- Multi-file selection (`Cmd`-click) with bulk add/remove Finder tag edits
- Center-pane sort control (name/date modified/date created/size, ascending and descending)
- Fallback to `mdfind` and filesystem enumeration when needed

## For Developers

### Requirements
- macOS 14 or later
- Xcode 15 or later

### Setup
```bash
git clone <repository-url>
cd Zoontag
open Zoontag.xcodeproj
```

### Build and Test
```bash
xcodebuild build -scheme Zoontag -configuration Debug
xcodebuild test -scheme Zoontag -destination 'platform=macOS' -derivedDataPath "$(pwd)/.build/DerivedData"
```

### Build Release Package
```bash
./scripts/package_release.sh
```

To publish a packaged download on GitHub Releases, push a `v*` tag (for example `v1.0.0`).

### More Docs
- Contributor workflow: [CONTRIBUTING.md](CONTRIBUTING.md)
- Agent-specific guidance: [AGENTS.md](AGENTS.md)

## License
This project is licensed under the [MIT License](LICENSE).
