# Background jobs

Jobs define execution boundaries: queue selection, retries, discard policy, and serialization. Delegate domain operations when they are reusable or deserve an independent abstraction; keep small, job-specific logic inline when clearer.

```ruby
class DeliverWebhookJob < ApplicationJob
  def perform(webhook)
    webhook.deliver
  end
end
```

This delegation is an example, not a one-line requirement. Design the actual delivery operation for duplicate execution, missing/deleted records, and partial external failure. Retry only failures that are safe to retry. A database transaction does not make an external delivery atomic.

Check the configured queue adapter and installed Rails version before depending on enqueue/transaction semantics. Test the contract that matters: enqueuing the right work and handling its meaningful failure modes.
