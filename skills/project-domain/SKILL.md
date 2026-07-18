---
name: project-domain
description: "Per-project domain map — READ FIRST to skip blind file exploration. Every project keeps its own PROJECT_DOMAIN.md (a self-indexing map of models, routes, modules, business rules with stable anchor jumps). This skill bootstraps that file the first time and keeps it filled thereafter. TRIGGER whenever the user asks where something lives ('where is X', 'which file handles Y', 'find the code for Z', 'show me the X model/module'), navigates the codebase, or starts any feature/bugfix/refactor. Load BEFORE running Grep/Glob/Read across the source tree — the map tells you where to look so you don't wander. SKIP only for: pure infra/CI/tooling changes, questions about other repos, or docs-only edits."
user-invocable: true
metadata:
  type: reference
---

# Project Domain Map

A generic, project-agnostic navigator. Each repo carries its own `PROJECT_DOMAIN.md`
— a hand-maintained map of what the codebase contains and where it lives, with stable
anchors so you jump straight to the right file instead of Grep/Glob/Read hunting.

This skill is shared across all projects, so it holds **no** project specifics itself.
The map (and its index) lives *inside each project's* `PROJECT_DOMAIN.md`, which is
self-indexing: its own table of contents at the top points at anchors further down.

## Step 1 — Locate the map

Look, in order, for:

1. `PROJECT_DOMAIN.md` at the repo root.
2. `.claude/PROJECT_DOMAIN.md`.
3. Whatever path the project's `CLAUDE.md` names as its domain map (e.g. Kerni uses
   `KERNI_DOMAIN.md` + the `/kerni-domain` skill — honor that instead; don't create a
   second map).

If a map exists → **Step 3**. If none exists → **Step 2**.

## Step 2 — Bootstrap it (first time only)

When no map exists, create `PROJECT_DOMAIN.md` at the repo root (or `.claude/` if the
project forbids new root files). Scan the codebase to fill it — don't guess:

- Detect the stack (language, framework, build/test commands) from the manifest
  (`Gemfile`, `package.json`, `go.mod`, `pyproject.toml`, `Cargo.toml`, …).
- Enumerate the domain objects (models / entities / core modules) and how they relate.
- Enumerate the entry points (routes / endpoints / CLI commands / public API).
- Capture the non-obvious business rules and invariants a newcomer would trip over.

Keep it **navigational, not exhaustive** — a map that says *where* to look and *why it
matters*, linking to files, not a copy of the code. Use the template below. Tell the
user you created it.

## Step 3 — Use the anchor index

Each indexed section carries a stable `<!-- pd:* -->` anchor comment above its heading;
the table of contents at the top of `PROJECT_DOMAIN.md` maps topics to those tokens. To
open one: `Grep` its `pd:*` token in `PROJECT_DOMAIN.md`, then `Read` from that line.
Anchors don't shift when content is added elsewhere, so the index stays valid and
merge-conflict-free across parallel edits. **Never** index by line-number range — those
cause cascading merge conflicts on every edit.

## Keeping it filled (MANDATORY)

The map is only useful if it's current. Whenever you add, remove, or materially change
significant logic, update `PROJECT_DOMAIN.md` in the **same** change:

1. **Add/remove a domain object** → update the relationship map + its section.
2. **Add/modify an entry point** (route, endpoint, command) → update the entry-points section.
3. **Change a schema / data shape** → update the schema reference.
4. **Add or change a business rule / invariant** → update the rules section.
5. **Add/rename/remove a section** → add a `<!-- pd:slug -->` anchor above its heading
   (slug = snake_case of the section name) and add/update its row in the top-of-file index.

Adding content to an existing section needs no index change — anchors are stable.

## PROJECT_DOMAIN.md template

```markdown
# <Project> Domain Map

**<One-line: what this project is.>** Stack: <language / framework / db / notable libs>.

**This file is the navigational index.** For full detail on any item, jump to its
`<!-- pd:* -->` anchor via the index below.

## Index
| Section | Anchor |
|---------|--------|
| <Domain object / topic> | pd:<slug> |
| …       | …      |

<!-- pd:relationships -->
## Relationship Map
```
<ascii or bullet map of how the core objects relate>
```

<!-- pd:entry_points -->
## Entry Points
<routes / endpoints / CLI commands / public API, grouped by surface>

<!-- pd:business_rules -->
## Key Business Rules
- <invariant a newcomer would trip over>

<!-- pd:<object_slug> -->
## <Domain Object>
<what it is, where it lives (file path), key methods/fields, relationships>
```
