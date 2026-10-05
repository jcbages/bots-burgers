---
name: gene
description: "Commit the current session’s work to local main; use for commit requests and the project’s required handoff."
user-invocable: true
---

# Gene — Session Commit

A short Gene-style greeting is optional. Proceed with the pending task; print art only if requested.

Read [project settings](../_shared/project-config.md) only for settings not already established. Stay on `main` unless the user explicitly authorized a branch or PR flow. Commit locally by default; push only when the user expressly requested it.

## Establish ownership

Use recorded session edits and a known starting snapshot to identify the exact changes to commit. If available, inspect `bin/mine --files` and `bin/mine`, but treat the ledger as supporting evidence: before/after snapshots cannot prove who wrote a line while concurrent writers were active. Serialize writers when ownership matters. Do not reconstruct disputed ownership from the final diff or classify an entire mixed file as yours.

Codex's `UserPromptSubmit` context supplies the current session ID. Prefix every `bin/mine` and `bin/commit-mine` command with that exact `LEDGER_SESSION='<id>'` assignment. Claude Code supplies `CLAUDE_CODE_SESSION_ID` to its Bash subprocesses.

Leave contested edits out and report them. A path-scoped `git commit -- <paths>` is a fallback only when each included file's entire change is demonstrably this session's and shared-index access is serialized. For mixed files, use a private index with the independently verified session patch. If safe ownership cannot be established, report the uncommitted work rather than including another session's edits.

Do not discard working-tree changes or rewrite files to remove someone else's lines. Keep the shared index untouched when using `bin/commit-mine`: it builds a private index and moves the ref with compare-and-swap. The shared index can lag behind the new `HEAD`, so `git status` may show staged changes after a commit; refresh only paths you own, and never reset paths with another session's staged work.

## Commit and report

1. Reuse the session's validation and review evidence. Run additional checks only when changes, failures, or unresolved risks warrant them; do not repeat completed gates at handoff.
2. If using `bin/commit-mine`, inspect `--dry-run` against the independently verified session patch before committing. Skipped files and failures belong in the report. A ref race warrants refreshing HEAD and rechecking the patch, not a blind retry loop.
3. Commit one cohesive change with an imperative message. Best-effort commits may contain unfinished work; name that work and any failing checks explicitly.
4. If Linear is opted in and available, use an existing task when identified. Create a lightweight ticket only when that workflow is authorized; no persona filler. Mark it Done only after the commit succeeds and its acceptance criteria are complete. Otherwise preserve its state and report what remains.
5. If pushing was requested, inspect the outgoing commits and remote first: pushing local `main` publishes every unpushed commit, not just this session's. Honor the authorized scope and never force-push shared `main`.

Report the commit, files changed and why, unfinished or excluded work, and checks actually run. Include a ticket only when one was used, and distinguish local commit from successful push.
