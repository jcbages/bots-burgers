---
name: project-domain
description: "Use or maintain an existing project navigation map; bootstrap one for sustained work when it will save exploration."
user-invocable: true
metadata:
  type: reference
---

# Project Domain Map

A domain map is an optional index of stable locations and non-obvious invariants. It is a navigation aid, not a prerequisite for reading source.

Check the known project instructions for a map location, then the repo-root `PROJECT_DOMAIN.md` or `.claude/PROJECT_DOMAIN.md` when useful. Read its index and only the relevant sections. Verify stale or uncertain entries against source; a targeted search is appropriate when the map does not answer the question.

Do not create a map merely to answer a location question, review a small diff, or edit a named file. Bootstrap one when the user asks or sustained exploration makes a reusable index worthwhile. Keep it short: stack and entry points, major module relationships, links to source or authoritative docs, and a few non-obvious invariants. Avoid copying schemas, method catalogs, or all routes into prose.

Use stable section anchors for a larger map; do not index by line-number ranges. Update existing entries when this change invalidates them. A new method or route does not automatically need a map entry. Prefer deleting stale detail to accumulating another source of truth.

Report a new map as part of the task's actual file changes; navigation alone should not silently expand into a documentation project.
