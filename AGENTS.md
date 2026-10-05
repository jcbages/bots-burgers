# ai-config

This repository installs shared instructions and skills for Claude Code and Codex.
Global preferences live in `instructions/AGENTS.md`; the installer links that file
into each host. Keep this repository's instructions focused on its own implementation.

- `PROJECT_DOMAIN.md` locates the installer, hooks, skills, and test suites.
- Shell code targets macOS Bash 3.2 and Linux Bash; use `jq` for JSON. Declare any
  additional runtime dependency in the installer and README.
- When changing installation, preserve unrelated settings, hooks, and permission
  choices. Repeated installation must be idempotent. Test with temporary config dirs
  before applying changes to the user's real configuration.
- Hook protocols differ between hosts. Validate against the installed host and
  current official documentation; do not silently grant tool permissions.
- Hook and commit changes need adversarial tests for shared-work ownership and
  failure handling. Run the affected `hooks/test/*_test.sh` while iterating, then
  `bash hooks/test/run_all.sh` once before handoff for infrastructure changes.
- Skills use relative references that work from either host's installed directory.
  Keep workflow-specific details out of global instructions.
- Update README and the domain map when installation paths or hook behavior change.
