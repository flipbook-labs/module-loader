# Change entries

This folder holds the unreleased changes for the next release. Each file describes one change: how big a version bump it warrants and what to say about it in the changelog. At release time [Changewrite](https://github.com/flipbook-labs/changewrite) combines every entry here into `CHANGELOG.md`, bumps the version, and deletes the entries it consumed.

## Adding an entry

Create a markdown file in this folder. The filename is up to you — it only exists to make entries easy to browse — so name it after the change, e.g. `fix-release-permissions.md`:

```markdown
---
bump: minor
category: Features
---

Add support for Foo values so Bar can be Bazzed.
```

- **`bump`** (required) — how much to move the version: `major`, `minor`, or `patch`.
- **`category`** (optional) — the heading this entry appears under in the changelog, e.g. `Features`, `Fixes`, `Dependencies`. Defaults to `Changes`.
- **Body** — everything below the frontmatter is the changelog text. Aim for one or two sentences; it can span multiple paragraphs if a change needs it.

## How the version is chosen

The next version is the largest bump across all pending entries: a single `major` entry makes the release a major, otherwise a single `minor` makes it a minor, otherwise it's a `patch`. You don't pick the version yourself — you just say how big each change is.

## Notes

- `README.md` (this file) is ignored, so it's safe to keep here.
- Entries are deleted once they're released; they live in this folder only while unreleased.
- The folder location is configurable via `unreleased_changes` in `changewrite.toml` (it defaults to `./.changes/`).
