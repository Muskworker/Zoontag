# AGENTS.md

This repository uses a “small change, high confidence” workflow for fixing bugs and adding features. The point is to keep changes understandable, test-backed, and easy to undo.

Unless a project explicitly says otherwise, assume the primary branch is `main`.

## Core workflow (bug fix or feature)

1. Create a new branch
   - Name it after the intent, not the implementation.
   - Examples: `fix-login-timeout`, `feat-tag-browser`, `chore-deps`.

2. Find the real problem (Five Whys)
   - Before coding, write a short root-cause (or “need”) note in a scratchpad, issue, or commit draft:
     - What is the user-visible failure / missing behavior?
     - Why does it happen?
     - Why is *that* true? (repeat until you hit a fixable cause)
   - For features, treat it as “Five Whys for the need” (what problem are we solving, and why now?).

3. Add or update the spec/test first (when practical)
   - Bugs: add a regression test that fails before the fix and passes after.
   - Features: add a brief feature description and at least one test or executable example.
   - If a test is genuinely hard to express, write down why, and add an alternate verification method.

4. Implement the change
   - Prefer the smallest change that makes the new behavior true.
   - Keep unrelated refactors out of the same branch unless required for the fix.

5. Keep code readable as you go
   - Add doc/comments for:
     - Any new public-facing function/class/module
     - Any modified function whose behavior is now non-obvious
   - Comments should explain intent and constraints, not narrate the code.

6. Avoid “magic” and make localization possible
   - Replace unexplained constants with named constants/config.
   - If the project supports i18n/l10n, ensure user-visible strings go through the localization system.

7. Reduce unnecessary coupling (Law of Demeter / “one-dot rule” spirit)
   - Avoid reaching deeply through object graphs (`a.b.c.d`) when it can be replaced by:
     - a method on `a`, or
     - a small adapter/helper, or
     - a clearer boundary.
   - The aim is fewer assumptions about other objects’ internals.

8. Stay DRY, but don’t get clever
   - Remove duplication that causes maintenance risk.
   - Don’t abstract until there’s a clear shared shape (two near-identical blocks might be coincidence).

9. Consider performance and storage impact (when relevant)
   - If the change touches persistence, queries, or large data processing:
     - confirm indexes/queries are sane
     - avoid accidental N+1 patterns
     - prefer set-based operations where appropriate
   - If unsure, add a small benchmark or a note describing expected scale.

## Quality gates (before merging)

10. Run formatting/linting on touched files
   - Use the repo’s standard formatter/linter. If none exists yet, create one.
   - Preferred convention: add project scripts under `./script/` (or `./scripts/`) so they’re easy to find.
     - `./script/lint` (or `./script/format` / `./script/ci`)
   - When a linter supports “only changed files,” that’s a fine fast path, but make sure a full run is possible too.

11. Confirm tests pass
   - Run the full test suite when feasible.
   - If the suite is slow, at minimum run all relevant tests plus a fast “smoke” suite.
   - If there is no standard test runner command yet, add one:
     - `./script/test`

12. Update documentation if behavior or usage changed
   - README, in-repo docs, examples, or inline docs as appropriate.
   - If the change affects a command/API/config, docs should mention it.

13. Update the changelog (if the repo uses one)
   - If the project doesn’t have a changelog yet, create `CHANGELOG.md`.
   - Recommended baseline format: “Keep a Changelog” style, with an “Unreleased” section.
     - Each entry should be concise and user-focused: what changed, not what code moved.
   - If the repo uses releases/tags, add dated version sections as needed.

## Commit style

Use Conventional Commits. Prefer the smallest number of commits that still tell the story.

Format:
- `type(scope): short summary`

Common types:
- `feat:` new user-facing capability
- `fix:` bug fix
- `docs:` documentation only
- `refactor:` behavior-preserving change
- `test:` tests only
- `chore:` tooling/maintenance
- `perf:` performance improvement
- `ci:` CI/config changes

Guidelines:
- Write the summary in imperative mood (“add”, “fix”, “remove”).
- Use a scope when it helps (`feat(parser): …`, `fix(ui): …`).
- Include a brief root-cause note in the body when it’s not obvious from the diff.

## Local git flow (no PRs)

14. Review the diff like an enemy would
   - Skim for:
     - unintended file changes
     - debug prints/log spam
     - secrets/credentials
     - dead code
     - confusing names
   - Helpful commands:
     - `git diff`
     - `git status`
     - `git log -1`

15. Commit with Conventional Commits
   - Keep commits logically grouped.
   - If a change is big, prefer multiple commits over one “mega blob,” but don’t micro-commit noise.

16. Merge into the primary branch locally
   - Example:
     - `git switch main`
     - `git merge --no-ff <your-branch>`
   - If you prefer linear history, rebase the branch before merging instead.

17. Delete the branch after merge
   - `git branch -d <your-branch>`

18. Sync state (optional / project-dependent)
   - If there is a remote, push/pull as appropriate.
   - If this is purely local, ensure the working tree is clean.

## Definition of Done (quick checklist)

- Root cause / need understood (Five Whys note exists somewhere).
- Test/spec or executable verification exists.
- Lint/format passes.
- Tests pass.
- Docs updated if user-facing behavior changed.
- Changelog updated (or created) if user-facing behavior changed.
- Branch merged locally and cleaned up.