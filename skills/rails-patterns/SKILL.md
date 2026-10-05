---
name: rails-patterns
description: "Basecamp-inspired Rails design guidance for architectural decisions in Rails code; consult the relevant reference when needed."
user-invocable: true
metadata:
  version: 3.0.0
---

# Rails patterns

Prefer the project's established architecture. These Basecamp-inspired defaults guide judgment; they do not require rewriting existing patterns or optimizing for line counts.

Keep controllers focused on HTTP coordination and put domain behavior with the relevant models or focused Ruby objects. Extract a concern when it expresses a coherent reusable capability, not to meet a method quota. Jobs own scheduling/retry concerns and can delegate reusable domain behavior; they do not need a one-line `perform`.

Use named scopes for meaningful reusable queries. A straightforward controller query is acceptable when it does not hide authorization or domain policy. Use transactions for changes that must succeed atomically, and design external side effects separately because database rollback cannot undo them.

Choose callbacks for lifecycle invariants that apply to every caller; use explicit methods when ordering and intent need to be visible. Choose STI only when shared storage and a stable subtype relationship fit the domain. Keep request state explicit enough to trace tenant and authorization boundaries.

Load only a reference that helps the current decision:

| Area | Reference |
|---|---|
| HTTP coordination and authorization | [Controllers](references/controllers.md) |
| Domain objects, concerns, queries, transactions | [Models](references/models.md) |
| Stimulus and JavaScript responsibilities | [JavaScript](references/javascript.md) |
| Templates, caching, helpers | [Views](references/views.md) |
| Retries and background work | [Jobs](references/jobs.md) |
| Test design | [Testing](references/testing.md) |
| Rails-specific review pitfalls | [Bug checklist](references/bug-checklist.md) |
| Resource routes and namespaces | [Routing](references/routing.md) |
| Existing styles and reusable components | [CSS](references/css.md) |

For version-sensitive behavior, check the installed versions and current official documentation when needed; examples here are not a substitute for that check.
