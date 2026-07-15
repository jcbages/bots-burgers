---
name: patterns
description: "Campfire/Basecamp Rails patterns — MANDATORY reference BEFORE writing ANY Ruby/Rails/JS code in a Rails project. Covers slim controllers (1-5 lines/action), fat models with concerns, scopes, callbacks, association extensions, STI, jobs as one-liners, thin Stimulus controllers + plain-JS model classes, Alpine.js vs Stimulus choice, views, helpers, routing, testing. TRIGGER whenever user asks to add/edit/refactor/review/audit a controller, model, concern, job, serializer, view, helper, scope, migration, Stimulus controller, JS class, or test; edits any .rb, .erb, or .js file under app/ or test/; asks 'how should I structure this', 'where does this go', 'Alpine or Stimulus', 'is this the Rails way', 'what would Basecamp/DHH do', 'is this idiomatic'; writes a new action, method, class, endpoint, or data-controller wiring. Load at the START of the task, not after writing. SKIP only for: non-Rails projects, pure config/infra (Gemfile, config/*, bin/*, .github/), docs-only (*.md), trivial typos, pure CSS/asset edits."
user-invocable: true
metadata:
  version: 2.0.0
---

# Architectural Patterns (Basecamp Once-Campfire)

These patterns are derived from Basecamp's Once-Campfire codebase — the reference implementation for how we write Rails. Every pattern is backed by real Campfire code. When in doubt, this is the standard.

This SKILL.md is a lean index. **Read the specific reference file for the area you're working on.**

---

## The 16 Principles

1. **Controllers are thin orchestrators** — 1-5 lines per action, delegate everything to models
2. **Models own all business logic** — validations, callbacks, scopes, domain methods, API calls
3. **Concerns are small and focused** — one domain concept per concern, in `app/models/model_name/`, 3+ methods each
4. **Scopes compose** — chain scopes instead of building queries in controllers. NEVER inline `.where()` / `.joins()` in actions
5. **Transactions wrap multi-step operations** — always in model methods, never skip for multi-create/update
6. **Callbacks for mandatory side effects** — `after_create_commit` for async work, enqueue jobs from model methods
7. **Jobs are one-liners** — `perform` delegates to a model or dedicated class. Complex logic NEVER lives in the job
8. **Stimulus controllers are thin** — complex JS logic goes in `app/javascript/models/` as plain classes
9. **Views use fragment caching** — `cache model do` for expensive renders
10. **Helpers generate complex HTML** — data attributes composed in Ruby helpers, not scattered across ERB views
11. **Association extensions for domain APIs** — `has_many :items do def grant_to(users)...end end` over flat class methods
12. **STI for type-specific behavior** — subclasses over conditionals when behavior branches by type/kind
13. **`CurrentAttributes` for request-scoped state** — cascading setters, use `Current.user` / `Current.account` (whatever your tenant/owner is)
14. **Test behavior, not implementation** — fixtures, shared helpers, assert outcomes not internals
15. **Scope filtering over inline queries** — all filtering via named scopes composed in class methods, controllers never touch Arel
16. **Semantic CSS classes over utility sprawl** — one CSS file defines component classes, views use semantic names

---

## Detailed References

Open only the file(s) for the area you're editing:

| Working on… | Read |
|---|---|
| Controllers, before_actions, auth, controller concerns, broadcasts | `references/controllers.md` |
| Models, model concerns, associations, STI, callbacks, scopes, `Current` | `references/models.md` |
| Stimulus controllers, JS model classes, outlets, data-actions | `references/javascript.md` |
| ERB views, fragment caching, helpers, layouts | `references/views.md` |
| Background jobs, `ApplicationJob`, dedicated worker classes | `references/jobs.md` |
| Minitest, fixtures, test helpers | `references/testing.md` |
| Pre-done self-review, bug hunting, PR review | `references/bug-checklist.md` |
| `config/routes.rb`, nested resources, scope modules | `references/routing.md` |
| Tailwind component classes, `application.tailwind.css` | `references/css.md` |

**The principles above are the rules. The references are the code proof.** Load a reference when you need the example, not preemptively.
