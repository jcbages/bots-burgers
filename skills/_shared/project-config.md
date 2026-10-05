# Project settings

Reuse settings already established in the session. Otherwise consult the project's instructions (including `AGENTS.md` and `CLAUDE.md` when present), then infer only what this task needs:

- Repository: `gh repo view --json nameWithOwner`; pass the resolved repository when GitHub commands might otherwise be ambiguous.
- Validation: the documented runner or CI configuration; run checks proportional to the change rather than guessing a command.
- Worktree: a unique temporary directory for an explicitly authorized branch/PR workflow.
- Patterns and templates: project conventions first; [Rails patterns](../rails-patterns/SKILL.md) and [PR template](../mr-frond/assets/pr-body.md) are defaults when relevant.

Linear is opt-in: automated ticket steps require the project to name a team and the integration to be available, plus authorization for those writes. An explicit ticket request can establish that authorization. Use plain commit and PR descriptions when Linear is unavailable. Mark tickets Done only when their acceptance criteria are complete.

Resolve resource links relative to this file or the skill that names them, never through a hardcoded user directory. Ask only when a setting is essential and cannot be inferred safely.
