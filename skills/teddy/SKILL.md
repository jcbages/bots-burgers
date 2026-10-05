---
name: teddy
description: "Address review feedback or rebase specified pull requests; use for PR fixes and conflict resolution."
user-invocable: true
disable-model-invocation: true
---

# Teddy — PR Fixes

A short Teddy-style greeting is optional. Begin the requested work directly; delegate only when useful and available, with no mandatory model override.

Read [project settings](../_shared/project-config.md) for unresolved settings. Work in an isolated worktree; keep the shared primary checkout on `main`.

## Scope and stopping condition

A PR number means that PR only. An explicit request to fix all your pending PRs means one snapshot of your open PRs needing fixes or rebasing. For a bare invocation, use an unambiguous PR from context or ask for a target.

Record the PR number, head SHA, and actionable review IDs. Process each snapshot item once. Re-requesting review does not clear `CHANGES_REQUESTED`; a PR awaiting a reviewer is finished for this run. Report new arrivals or changed heads without entering an unbounded re-query loop.

## Fix or rebase

Read the relevant review threads, diff, and surrounding code. Distinguish actionable defects from suggestions; preserve the requested scope. Create a worktree from the fetched PR head, recording the remote head for the eventual push lease.

Rebase only when requested or needed to integrate the fix. Capture the original merge base and branch tip, then reconcile conflicts using both branches' intent. During rebase, “ours” is the new base and “theirs” the replayed commit; neither is categorically newer or preferred. Preserve upstream fixes and adapt the PR's intended behavior to them. If intent remains ambiguous, report it rather than choosing a side by default.

Stage only resolved worktree paths and complete the rebase before comparing the resulting changes. Compare old and new commit series (for example `git range-diff`) and inspect the final target-base diff for lost behavior; textual differences alone are not evidence that work was lost. Use unique scratch paths for saved patches.

Make the scoped fixes and run checks appropriate to the changed behavior and conflict resolutions. A clean rebase needs no artificial “rebase” commit. Commit actual new fixes, then push within the user's authorization. For rewritten history, use `--force-with-lease=<branch>:<recorded-remote-head>`; if the lease fails, stop publishing and inspect the concurrent changes instead of overwriting them.

## Close the loop

When follow-up posting is authorized, summarize fixes and validation, resolve only threads actually addressed, and re-request the relevant reviewers. Do not resolve every thread blindly or re-request reviews for an unchanged clean rebase of approved work. If listing threads, paginate rather than assuming the first page is complete.

Keep incomplete tickets and unresolved comments open. Preserve a worktree containing uncommitted or unpublished work. Report the updated PR, checks, unresolved items, and “awaiting review” when applicable; do not poll for approval.
