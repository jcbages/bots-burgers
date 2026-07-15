# Bug Checklist — Pre-Done Self-Review & PR Review

One list, two moments: the implementation personas (/bob, /tina, /louise) run it BEFORE declaring done, and /mr-fischoeder runs it again at PR review. Every bug the first pass catches is a review cycle saved.

This is the generic checklist shipped with the shared skills. If the project's `CLAUDE.md` points at its own checklist, read THAT one too — it carries project-specific invariants this generic list can't know about.

## How to run it

- Re-read the FULL diff (`git diff`) top-to-bottom once to understand intent, then **bottom-up** to catch bugs — the second pass catches what familiarity hides.
- For each item, actively try to **produce the failure**. Confirming the happy path is not reviewing.

## Correctness

- Wrong logic, off-by-one, wrong variable used, broken control flow
- Every lookup (`find` / `find_by` / dictionary get / array index) — can it return nil/undefined? Is that handled?
- Missing failure propagation where an error should surface (e.g. a non-bang save whose failure is ignored)
- Every callback/hook — right lifecycle? Could it fail silently?

## Multi-tenant & authorization invariants

- **Tenant scoping**: every user-reachable query is scoped to the current tenant/owner. A scope must never silently fall back to "all records" when its filter is empty — the first unscoped caller becomes a cross-tenant leak.
- **Authorization is server-side**: hiding a button in the UI is NOT authorization. Every state-changing action enforces its guard on the server. Ask: "what happens when a user sends this request directly with someone else's id, or with their own restriction removed?"

## Working with third-party API responses

- **Fields are optional**: any field can be absent from an external response. Never overwrite stored data with a fallback default (e.g. `fetch(..., "unknown")`) — only write fields the API actually returned.
- **Batch loops rescue per item**: one failing record must not abort the whole sync. Rescue inside the loop, record the failure, keep going.

## Security

- SQL injection, XSS, mass assignment (are params/inputs allow-listed?), exposed secrets
- New endpoint without auth — is it covered by the unauthorized-access test sweeps?

## Data & concurrency

- Race conditions: concurrent access to shared state, TOCTOU, missing locks
- Multi-step operations wrapped in a transaction
- New associations/relations: delete strategy? FK constraint? Orphans possible?
- Missing validations / DB constraints

## Edge cases

- Empty collections, nil/undefined values, boundary conditions
- Error paths handled — what does the user actually see when it fails?
- Time comparisons that race the wall clock — pin time in tests, never sleep

## Performance

- N+1: associations loaded in loops without eager-loading (`includes`/`preload` or equivalent)
- New scope/query: does it need an index? Could it scan the whole table?

## Contracts & tests

- API responses match the documented contract (schema/spec); every status code is covered
- Every new behavior has a test AND at least one adversarial sad-path test: absent field, empty collection, unauthorized direct request, mid-batch failure
- Bug fixes started from a failing test that reproduces the bug (red → green)
- A test for a form endpoint should submit the SAME fields the real form posts — including empty file inputs, which browsers always send — so param-handling regressions surface

## The ratchet (MANDATORY)

This file must grow. When a reviewer (human or /mr-fischoeder) finds a bug this checklist missed, whoever fixes it adds the **generalized lesson** here — one bullet under the right section, in the same commit/PR as the fix. If the bug class is mechanically checkable, prefer a lint/CI rule instead. A review finding that doesn't become a guardrail is a wasted lesson.
