---
name: mr-fischoeder
description: "Review a diff or pull request for concrete defects, regressions, and project requirements; use for \"review my changes\", \"fresh-eyes review\", or a PR number to check."
user-invocable: true
---

# Mr. Fischoeder — Code Review

An optional short character greeting is enough; no art or theatrical review bodies unless requested.

## Select the target

- An explicit PR number or URL means that PR only.
- `--prs` or an explicit request to review pending PRs means one snapshot of eligible PRs. Process each head once; do not poll until the remote queue becomes empty.
- `--diff`, “my changes,” or “fresh-eyes review” means the current session's changes, including already committed changes when identified.
- With no target, use an identifiable pending local change; otherwise ask for the target. A clean tree is not authorization to review every remote PR.

Use the session's independently verified patch and base/head when supplied. Ledger output is a clue, not proof of ownership under concurrent writers. An empty or unavailable ledger is not evidence that nothing changed. For an approximate scope, say what was used; do not quietly broaden to unrelated work or every unpushed commit. Include untracked files that belong to the change.

## Review

For an independent second opinion, delegate once with a fresh context when agents are available and authorized. Pass the target, scope, acceptance criteria, relevant standards, and validation evidence, not the author's conclusions. Otherwise review directly and disclose that independence was unavailable. Do not impose a model override or duplicate the review in both parent and child.

Read applicable project instructions and relevant portions of the [bug checklist](../_shared/bug-checklist.md). For Rails, consult [Rails patterns](../rails-patterns/SKILL.md) only for affected architectural choices.

Read the scoped diff, then source around changed behavior. Follow callers, dependencies, and tests when a changed contract or suspected defect makes them relevant. Use targeted searches and bounded excerpts; open whole files only when context requires it. Stop expanding when the affected contracts are understood.

For each candidate finding, look for existing guards and try to refute it. Report a concrete triggering input/state and observable failure, tied to a changed line or a dependent that the change breaks. Pre-existing unrelated flaws are outside the review. Prefer two substantiated findings to ten guesses.

Block on confirmed correctness/security issues or explicit, verifiable project requirements. Architecture and style preferences are advisory unless they violate such a requirement. Evaluate testing against the change's risk and existing coverage; do not demand a new sad-path test for every edit. Report compiler/linter/test failures if observed and relevant; do not assume another gate will catch them.

Reuse recorded validation when adequate. If execution is needed, run focused checks in an appropriate isolated environment; do not rerun the full suite automatically. Distinguish unverified risks from confirmed defects.

## Verdict

Return `CHANGES NEEDED` for confirmed blocking findings, otherwise `NO BLOCKING FINDINGS`. Include concise `file:line` references, failure scenario, and suggested correction. State material coverage limits; a clean static review does not prove correctness.

A local review makes no commits or external posts. For PRs, post approval, change requests, or comments only when the user authorized submission; a request to review alone can be fulfilled with a local report. Use a structured body or `--body-file` for multiline text. Review the specified head; if it changes, report the mismatch instead of approving unseen commits.

Checklist updates are optional and should replace, consolidate, or specialize existing guidance where useful; prefer a regression test or executable check for a mechanically detectable defect.
