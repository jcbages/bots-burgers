# Global Instructions

## Language

- **Respond in English by default.** No French unless I ask for it.
- **Exception — the `/fr` prefix**: when my message starts with `/fr`, respond in French for that one message (prefix the block with the 🇫🇷 flag emoji). If I wrote French, correct my mistakes — show what I wrote, what was wrong, the corrected version, and name the error type (grammar, conjugation, gender, ...). Keep it a quick note, not a lecture. The next message reverts to English.
- **Exception — the `/learn` prefix**: when my message starts with `/learn`, I'm passing a French word or expression I didn't understand. Explain it bilingually (English meaning + 🇫🇷 French example/nuance) so I can learn it. Applies to that one message only.
- **Never correct my English** — corrections are for French only, and only when I wrote French.
- **All external artifacts are always in English**, whatever language the chat is in: code, comments, commit messages, PR titles/descriptions, branch names, file contents, Linear tickets, GitHub comments.
- When using skill-based characters (e.g., /mr-frond, /linda, /bob, /louise, etc.), **stay fully in character** while still following the rules above.

---

# Git Workflow (applies to all projects)

- **Always work directly on `main`** — this is about *which branch*, never about committing unasked: when you do commit it goes to `main`, and when a branch's work is finished, merge it back into `main`.
- **The user triggers every commit, one at a time.** Never commit unprompted, and never treat one "commit this" as standing permission for the rest of the session — consent expires the moment it is used. `hooks/require_commit_request.sh` denies any `git commit` the user has not asked for since the last one. When they do ask, `/gene` is the fast lane (it re-runs the touched tests and splits mixed files before committing).
- Only create, switch to, or stay on a non-`main` branch when I **explicitly** ask for it. Absent an explicit instruction, assume `main`.
- **A commit carries only your own work.** `.git/index` is one file every agent in a working tree shares, so `git add` there is a read-modify-write race with a commit as the payload — and once two sessions have written to a file, no after-the-fact reading of the diff can say which lines are whose. A session hook records that as it happens: for each file you touch it keeps the content when you first touched it and that content plus only your edits, so another agent's lines are in both snapshots and cancel. `bin/mine` shows your diff in a tree full of everyone's; `bin/commit-mine -m "..."` replays it onto HEAD in a private index and moves the ref with a compare-and-swap. Never `git add` + `git commit` in a shared tree — `hooks/require_scoped_commit.sh` denies the unscoped forms, and a commit that names its paths (`git commit -m '...' -- <paths>`) is the fallback when the ledger is unavailable. A worktree has its own index and is exempt, which is why `/mr-frond` and `/teddy` commit inside one.
- **Parallel work is encouraged** — other agents may edit the same files at the same time. Seeing changes in a file you didn't make yourself is expected, not a conflict or a red flag: don't revert them, don't halt, and don't treat unexpected diffs as corruption. Rebase/merge onto the latest state, keep your own change scoped, and carry on.

---

# Code Philosophy (applies to all projects)

These are standing principles for every language and framework — apply them to every feature, bug fix, and refactor. A project's own `CLAUDE.md` may add specifics; this is the baseline.

## DHH's Craftsmanship

Code should not merely work — it should be **exemplary**. Would it be accepted into the framework's core, or into a language style guide?

- **DRY** — Ruthlessly eliminate duplication. If two places do the same thing, extract it.
- **Concise** — Every line earns its place. No dead code, no ceremony, no abstraction that isn't paying for itself.
- **Expressive** — Code reads like prose. Use the language's full expressiveness (`unless` over `if !`, trailing conditionals, guard clauses) instead of verbose mechanics.
- **Convention over Configuration** — Flow WITH the framework, never fight it. If it feels forced, it's probably wrong.
- **Declarative over imperative** — Prefer the framework's DSLs and higher-level constructs over manual step-by-step logic.
- **Self-documenting** — Comments are a code smell. Rename things until you don't need one. A comment is a last resort for a non-obvious *why* — 1-2 sentences, never a paragraph restating what the code does.
- **No archaeology in comments** — Never explain what the code *used to* do, what bug it once had, or why the previous approach was wrong. "Derived here, not in didChangeDependencies, because…", "the store used to…", "this fixes…" — all of it belongs in the commit message, where it is attached to the change that needed it. A comment is read by someone working on the code as it is now; the history is one `git blame` away and does not rot. Only the *currently* non-obvious constraint earns a line: "single-subscription, so this must be the only listener" stays, "the old code subscribed twice" goes.
- **No unnecessary metaprogramming** — Question any dynamic dispatch / reflection / macro that isn't essential.
- **Programmer happiness** — Would you enjoy maintaining this? Does it spark joy or dread?

**Test:** Would this be accepted into the framework's core as an exemplar?

## Rich Hickey's "Simple Made Easy"

**Simple is not the same as easy.** Simple means one concept, one role, one concern — things not braided together. Easy means familiar/close-at-hand. When they conflict, **choose simple.**

- **Compose, don't complect** — Complecting (braiding together) is the enemy; it destroys your ability to reason about, change, or debug either concern independently. Composing (placing together while keeping separable) is the goal.
- **Minimize mutable state** — State complects value and time. When state is necessary, make the transitions explicit.
- **Don't impose order** — Temporal coupling (A must happen before B) complects components. Avoid it unless truly required.
- **Reason about parts independently** — If understanding one piece requires understanding three others, something has been complected.
- **Simplify by disentangling, not by hiding** — A facade that hides complexity is not simple. Actually separate the concerns.
- **More small pieces > fewer large ones** — Focused, independent components over intertwined ones. Simplifying makes MORE things, not fewer.

**Red flags:** a method that knows both *what* to do and *how*; a class holding multiple unrelated responsibilities; the same policy scattered across many conditionals; a "simple" facade that hides complexity instead of eliminating it.

**Test:** Can you reason about each part independently? Or are concerns braided together?

---

# Working Standards (applies to all projects)

These are framework-agnostic. A project's own `CLAUDE.md` may add stack-specific steps on top.

## Definition of Done

No implementation work (feature, bug fix, refactor) is done until every step has run — this is how bugs get caught in the first pass instead of in review. A `Stop` hook (`hooks/require_dod.sh`) enforces steps 3–4 after any source edit; reply `skip dod` to bypass it for a session.

1. **Adversarial self-review of the diff.** Re-read the full `git diff` — top-down for intent, then bottom-up for bugs — against the shared bug checklist (`skills/_shared/bug-checklist.md`, plus any the project's `CLAUDE.md` names). Actively try to break the code; confirming the happy path is not reviewing.
2. **Sad-path tests.** Every new behavior gets at least one adversarial test (absent field, empty collection, unauthorized direct request, mid-batch failure) alongside the happy path. Bug fixes **start red** — reproduce the bug with a failing test first, then fix to green; never adjust a test to make the implementation pass.
3. **Fresh-eyes review.** Run `/mr-fischoeder --diff` on the session diff — it reviews the local working tree (committed *and* uncommitted), not just open PRs — and fix real findings in-loop. (A fresh-context review subagent scoped to the bug checklist also satisfies the gate.) Self-review misses the author's own bugs; a clean context does not.
4. **Green tests with evidence.** Run the touched tests (the stack's runner) while iterating and
   the full suite once at the end (see **Round trips**), and show the output. "It should pass" is not evidence. When there's a runtime surface (UI, endpoint), drive the actual flow — unit tests alone don't prove the feature works.

## Handing off

Finish a piece of work by **reporting it, not committing it**. The handoff is three things,
and it is short:

1. **Files touched, one line each on *why*** — grouped if there are many, and naming the one or
   two that carry the actual change so a reviewer knows where to look first.
2. **What you deliberately left out** — scope you judged out of bounds, a follow-up worth doing,
   a finding you chose not to act on. Silence here reads as "nothing was left", which is a lie
   more often than not.
3. **Verification you actually ran** — the command and its result, not "should pass".

Then stop. The user decides whether that becomes a commit (see the Git Workflow rules above).

## Blast radius

Keep changes small and focused. Evaluate scope before starting — if a task touches more than ~5–6 files, consider splitting it. Small changes are easier to review, test, and ship.

## Screenshots

When the user shares a screenshot of a UI issue or a desired design, treat it as primary context — faster and more precise than a verbal description.

## Codebase navigation

Before exploring an unfamiliar codebase, use `/project-domain` — it reads (or, the first time,
bootstraps) the project's `PROJECT_DOMAIN.md` map so you land on the right file instead of blind
searching. Keep the map current as you change significant logic. A SessionStart hook
(`hooks/session_start_domain_map.sh`) names the map for you, or tells you to bootstrap it — a
skill that merely *describes* when it applies gets skipped in favour of one more grep.

`hooks/require_domain_map.sh` then denies the first Grep/Glob/recursive-grep until the skill has
actually been invoked. Opening the map by hand does not lift it: the map is *where* things live,
the skill is how to reach them through the anchor index and the duty to leave the map current, and
a session that cat's the map goes straight back to one file per call. Falling back to reading
files individually is not a way around the gate either — that is the searching it exists to stop.

## Round trips

Orientation, not typing, is where the time goes. Measured across a dozen sessions of one Flutter
project: **93–98% of tool calls were Bash, and 64–71% of those were `cat`/`grep`/`find`** — one
file per call, ~6s of model latency each, the same file reopened 20+ times in a single session.
Three rules, in order of payoff:

- **Batch reads into one call.** `for f in a.dart b.dart c.dart; do echo "══ $f"; cat "$f"; done`
  is one round trip; three `cat`s are three. Same for surveys — one `grep` across the tree beats
  five scoped ones. And never reopen a file you already read this session; scroll back instead.
- **Delegate the survey, keep the conclusion.** When answering means sweeping many files and you
  only want the answer, spawn a read-only subagent (`Explore`, or `general-purpose`). It reads the
  170 grep hits; you get the paragraph. Raw exploration output is what fills the context window and
  forces the compaction that makes you re-read everything you already knew.
- **Full test suite once, at the end.** Iterate against the touched test file; run the whole suite
  once before declaring done. A full-suite run after every edit was the largest single wall-clock
  item measured — 100 minutes of one session spent re-running tests nothing had touched.
