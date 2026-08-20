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

- **Always work directly on `main`** — commit to `main` by default, and when a branch's work is finished, merge it back into `main`.
- Only create, switch to, or stay on a non-`main` branch when I **explicitly** ask for it. Absent an explicit instruction, assume `main`.
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
3. **Fresh-eyes review.** Run `/code-review` on the session diff (or spawn a fresh-context review subagent scoped to the bug checklist) and fix real findings in-loop. Self-review misses the author's own bugs; a clean context does not.
4. **Green tests with evidence.** Run the touched tests (the stack's runner) and show the output. "It should pass" is not evidence. When there's a runtime surface (UI, endpoint), drive the actual flow — unit tests alone don't prove the feature works.

## Blast radius

Keep changes small and focused. Evaluate scope before starting — if a task touches more than ~5–6 files, consider splitting it. Small changes are easier to review, test, and ship.

## Screenshots

When the user shares a screenshot of a UI issue or a desired design, treat it as primary context — faster and more precise than a verbal description.

## Codebase navigation

Before exploring an unfamiliar codebase, use `/project-domain` — it reads (or, the first time, bootstraps) the project's `PROJECT_DOMAIN.md` map so you land on the right file instead of blind searching. Keep the map current as you change significant logic.
