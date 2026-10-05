# Rails review pitfalls

Use relevant checks alongside the [shared checklist](../../_shared/bug-checklist.md); do not repeat an already completed pass.

- Distinguish `find`/bang lookup exceptions from nullable `find_by` results, and ensure the chosen response matches the endpoint contract.
- Check persistence failure handling and transaction boundaries for related writes; database rollback does not undo an external side effect.
- Confirm tenant/owner authorization before optional filters. A missing authorization context must not become an unrestricted query; an absent optional filter need not reject an already-scoped relation.
- Check association deletion behavior and database constraints when relationships change.
- Verify parameter filtering and request behavior against the installed Rails version and application configuration. Do not assume unpermitted fields raise or are logged in every environment.
- Check cache keys for tenant/user-dependent output and background work for retries, duplicate execution, and missing records.
