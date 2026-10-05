---
name: mr-frond
description: "Package this session’s verified changes into a pull request when the user asks for a PR."
user-invocable: true
disable-model-invocation: true
---

# Mr. Frond — Pull Request

Proceed with the supplied PR request. A short character greeting is optional; no art, waiting, or routine confirmation rounds.

Read [project settings](../_shared/project-config.md) for unresolved repository, worktree, validation, or Linear settings. A PR request authorizes its branch/worktree and normal push/create steps. Keep the primary checkout on `main`.

## Capture the change

Identify an independently verified session patch and its exact base before creating the worktree. Use the session's edit record and starting snapshot; ledger output alone does not establish authorship when writers overlapped. Include session-owned untracked files and intended mode/deletion changes. Leave disputed changes out and report them; ask only when ambiguity prevents the requested result.

Use existing validation/review evidence; do not automatically repeat completed gates. Find or create a Linear ticket only when the project opts in and that ticket workflow is authorized. A ticket is not required for a PR.

## Build the PR

Fetch the intended target and create an isolated worktree/branch from its current base. Replay the session patch onto that base, using a three-way application when the base blobs are available. For binary changes use a binary-capable patch. Never copy whole files from local `main`: they can contain earlier unpushed work absent from the PR base.

Inspect the resulting diff for missing hunks, unrelated content, and dependencies on unpublished local commits. Reconcile conflicts using both intents. If the session depends on another unpublished change, report that dependency and choose a base or scope authorized by the user; do not smuggle it into the PR.

Commit cohesive changes in the worktree. Run checks warranted by the resulting change and any integration differences; reuse earlier evidence only when it still applies. Resolve failures within scope and report blockers honestly. Do not imply a failed check passed or publish a ready-for-review PR with known failures without explaining them; use a draft when appropriate to the authorized task.

Push the PR branch and create the PR with an outcome-focused title and the project's template, or [the minimal template](assets/pr-body.md). Use a body file or structured argument for multiline content. Include actual validation results and material limitations. Remove the worktree only after its changes are safely committed and the requested publication succeeded; preserve it if unfinished work remains.

Report the PR link, changed areas, checks, and any excluded or unfinished work.
