# Models and domain behavior

Put persistence-related invariants and cohesive domain actions on the relevant model. Use focused plain Ruby objects when behavior spans domains or has an independent lifecycle. Avoid extracting a class or concern just to shorten another file.

Concerns should name a capability and make their associations/callbacks visible. A model-specific concern can live under `app/models/<model_name>/`; follow the project's layout. There is no minimum method count or mandatory declaration order.

Use scopes for meaningful reusable predicates and association extensions when the operation naturally belongs to an association. Keep authorization scopes distinct from optional filters: an absent search filter may legitimately leave an already-authorized relation unchanged, while a missing tenant must not broaden access.

For related writes that must succeed together, use a transaction and propagate failures:

```ruby
def deactivate!
  transaction do
    memberships.delete_all
    update!(status: :deactivated)
  end
end
```

This illustrates atomic database changes; select deletion behavior for the actual associations. Remote calls cannot be rolled back by the transaction. Enqueue or deliver side effects at the appropriate commit boundary and account for retries.

Callbacks suit invariants that must apply regardless of caller. Explicit domain methods suit workflows whose ordering or optional effects should be visible. Do not turn every side effect into a callback.

STI fits stable subtypes sharing a table and lifecycle. A small conditional, enum, composition, or a separate model can be simpler when that relationship does not hold.

`CurrentAttributes` may carry request context, but tenant selection must come from authenticated context. Never infer a tenant by selecting the first account. Keep background jobs' required context explicit and avoid retaining stale related values in custom setters.
