# Rails tests

Follow the project's existing runner, fixtures/factories, and helpers. Do not migrate test infrastructure to match this reference.

Test observable domain behavior and HTTP contracts. Use a failing reproduction for a regression when practical, then verify the fix. Add failure-path coverage when it protects a meaningful risk such as unauthorized access, invalid input, partial persistence, or duplicate delivery. Existing coverage may already establish the contract.

Controller/request tests should send the inputs real clients send, including empty form fields where relevant. Assert both response behavior and important state changes. For tenant boundaries, exercise a record owned by another tenant.

Run focused tests while iterating. Broaden verification when the changed interfaces or shared infrastructure warrant it, and reuse completed evidence until new changes invalidate it. Report the commands and actual results; an unrun suite is not a green suite.
