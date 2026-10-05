---
name: gene
description: "Commit the current session’s work to local main; use for commit requests and the project’s required handoff."
user-invocable: true
---

# Gene — Session Commit

A short Gene-style greeting is optional; print art only if requested. Stay on `main` unless a branch or PR flow was authorized. Commit locally; push only when the user asked. Read [project settings](../_shared/project-config.md) only for settings not yet established, such as Linear.

The scripts below live in this skill's `scripts/` directory; run them by that full path from the project root. In Codex, prefix them with the `LEDGER_SESSION='<id>'` assignment from the prompt context; Claude Code supplies its session ID automatically.

## Steps

1. **See what is yours.** `scripts/mine --files` lists the Edit/Write changes recorded for this session, and `scripts/mine` shows their diff. Compare it with what you know you changed. Shell edits (sed, heredocs, scripts) are not recorded.
2. **Commit recorded edits.** `scripts/commit-mine --dry-run`, check the landing and skipped lists, then `scripts/commit-mine -m "<message>"`. It commits through a private index and never touches the shared one. If HEAD moved meanwhile, rerun it.
3. **Commit everything else by path.** For files this session changed entirely, including shell edits and new files: `git commit -m "<message>" -- <paths>`. Never sweep the shared index (`git commit` without paths, `-a`, or `git add .`).
4. **Leave out what you cannot attribute.** A file another session also edited, or a contested ledger entry, stays uncommitted and goes in the report. Never discard or rewrite someone else's changes.
5. **Push only on request.** First list `git log origin/main..HEAD`: pushing `main` publishes every unpushed commit, not just this session's. Never force-push `main`.

Write one cohesive commit with an imperative message. A best-effort commit may include unfinished work if the message and report say so. Reuse the session's test and review results; rerun checks only when something changed since. If Linear is opted in, update an identified ticket and mark it Done only when its acceptance criteria are met.

Report the commit hash, files and why, excluded or unfinished work, checks run, and whether it was pushed.
