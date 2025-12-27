# Zoontag

A tag-first file browser for macOS that behaves like a booru:
- results are a grid
- the sidebar shows the most common tags *within the current result set*
- each tag has quick boolean refinement buttons: include (+) / exclude (–)

The key constraint: **use the filesystem + native Finder tags (Spotlight)**, not a separate imported library/database.

## Current status (minimal spine)
Implemented:
- Choose a root folder (NSOpenPanel)
- Query files via Spotlight (`NSMetadataQuery`) scoped to chosen folders
- Include/exclude tag sets drive the query
- Results displayed as a grid (currently uses NSWorkspace file icons as thumbnails)
- Facet sidebar shows top tags + counts derived from the current results
- Clicking + / – modifies the query state and re-runs search
- Included/excluded tags shown as removable chips

Not implemented yet:
- Real thumbnails (QuickLookThumbnailing)
- Preview pane (QuickLook)
- Multi-folder scopes and persistent bookmarks
- OR groups / parentheses / advanced boolean
- Text search, type filters, date filters
- Batch tagging UI

## Architecture
- `QueryState`: the source of truth (include/exclude tags + search scopes)
- `MetadataSearchController`: runs Spotlight queries and publishes results
- `FacetCounter`: computes tag frequency over current results for the sidebar
- SwiftUI UI binds to `QueryState` and calls search controller on changes

Important note: Spotlight does not provide “facets” natively, so facet counts are computed client-side from the query results.

## How Spotlight query is built
- include tags: AND chain of `kMDItemUserTags == <tag>`
- exclude tags: AND chain of `NOT (kMDItemUserTags == <tag>)`
- scope: user-picked folders

## Next steps (likely Codex iteration plan)
1) Swap icons for real thumbnails via `QuickLookThumbnailing`
2) Incremental / cancelable facet counting (and/or sampling)
3) Preview panel for selected file
4) Batch tag edit for selected results
5) Persist scopes via security-scoped bookmarks (sandbox-friendly)
6) Add OR groups (booru-style “(tagA OR tagB)”)

## Notes for sandboxing
If we sandbox later, we should:
- persist user-selected folders as security-scoped bookmarks
- startAccessingSecurityScopedResource when querying/opening files
- handle Spotlight returning items outside accessible scopes gracefully

## Design north star
The “booru loop” must be frictionless:
- see results
- see top tags in results
- click + / – repeatedly
- never get lost in folder hierarchies
