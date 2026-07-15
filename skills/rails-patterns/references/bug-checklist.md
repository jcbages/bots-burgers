# Bug Checklist (Rails)

The full, stack-agnostic checklist lives at `~/.claudita/skills/_shared/bug-checklist.md` — read it. This file only adds Rails-specific reminders on top.

## Rails-specific reminders

- Every `find` / `find_by` — can it return nil? Is nil handled? (`find` raises, `find_by` returns nil.)
- Missing `!` on `save`/`update`/`create` where failure should raise
- Multi-step model operations wrapped in a `transaction`
- New associations: `dependent:` strategy, FK constraint, orphan risk
- Scopes never fall back to `all` when their filter is empty (cross-tenant leak) — scope through `Current.account`/`@current_account` (or your tenant object)
- API controllers use `find_by_public_id!` and serializers use `prefixed_public_id`, not raw `.id` (if the project uses public ids)
- Under `load_defaults 8.x`, `action_on_unpermitted_parameters` is `:log` — unpermitted params are silently dropped (no 500). A missing `permit` entry does NOT raise; verify the resolved value before assuming a filter will crash.
