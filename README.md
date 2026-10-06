# bots-burgers
🍔 A Bob's Burgers crew of skills, hooks, and shared instructions for Claude Code and Codex.

## Install

Requires Bash, Git, `jq`, and Python 3.

```bash
./install.sh -y   # links into ~/.claude and ~/.codex (see ./install.sh --help)
```

Rerunning is idempotent and keeps unrelated settings. After moving the checkout,
rerun it from the new location. Then start a new session; Codex asks you to trust
changed hooks under `/hooks`.

## The crew

| Skill | Job |
|---|---|
| `gene` | Commit this session's work |
| `mr-fischoeder` | Review a diff or PR |
| `mr-frond` | Open a pull request |
| `teddy` | Address review feedback, rebase PRs |
| `linda` | Create Linear tickets |
| `bob`, `tina`, `louise` | Work personas, one picked per session |

Use `/gene` in Claude Code and `$gene` in Codex. Hooks guard destructive Git
operations and keep commits scoped to each session's own edits.

## Test

```bash
bash hooks/test/run_all.sh
```
