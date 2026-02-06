## Summary

Describe what changed and why.

## Root Cause / Need

Briefly state the user-visible problem or need this addresses.

## Verification

- [ ] `xcodebuild build -scheme Zoontag -configuration Debug`
- [ ] `xcodebuild test -scheme Zoontag -destination 'platform=macOS' -derivedDataPath "$(pwd)/.build/DerivedData"`
- [ ] Manual check completed (if needed)

## Checklist

- [ ] Tests added or updated (or rationale provided)
- [ ] Docs updated (README/docs/changelog if user-facing)
- [ ] No debug logs, secrets, or unrelated changes
