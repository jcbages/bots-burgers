# Focused review checklist

Use the sections relevant to the change. Follow project-specific invariants when supplied; do not load unrelated stack checklists or manufacture a finding for each item.

- **Correctness and boundaries:** empty/missing values, invalid inputs, wrong branches, error propagation, and observable failure behavior.
- **Authorization and security:** tenant/owner scoping, server-side permissions, untrusted inputs, secret exposure, and sensitive output handling.
- **State and concurrency:** atomicity, partial failure, retries/idempotency, shared ownership, and races around reads and writes. A snapshot is not proof of authorship under concurrent writers.
- **Contracts:** affected callers, return shapes, renamed paths/symbols, and dependencies. Follow changed interfaces; avoid sweeping every consumer of unchanged behavior.
- **Data and performance:** destructive effects, constraints, query scope/indexes, and work that grows with input size.
- **Verification:** evidence for intended behavior and meaningful failure cases, scaled to risk. For a regression, reproduce it when practical; for safe/preview modes, verify that prohibited side effects are unreachable.

Investigate a candidate defect before reporting it: look for existing guards, identify a concrete triggering case, and distinguish an observed failure from an unverified risk. Use existing tests and checks when they already cover the contract.

Prefer regression tests or executable checks to new universal instructions. Add a checklist rule only when it generalizes across projects; consolidate or replace existing entries. Stack-specific lessons belong with that stack, and one-off incident detail belongs in the fix's history.
