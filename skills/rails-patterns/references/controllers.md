# Controllers and authorization

Controllers coordinate HTTP inputs, authorized records, domain operations, and responses. Keep them easy to read; there is no action line-count quota. A direct query can be clearer than a one-use scope, provided authorization and domain rules remain explicit.

For a tenant-owned resource, load through the authorized relation:

```ruby
def show
  @message = Current.account.messages.find(params[:id])
end
```

This assumes request authentication established `Current.account`; ownership alone may not grant permission for every action. Enforce the relevant permission on the server, including direct requests.

Use setup/authorization callbacks for genuinely shared behavior, avoiding hidden ordering dependencies. Filter writable parameters using APIs supported by the installed Rails version. Handle expected validation failures in the response contract rather than relying on bang methods to turn all failures into server errors.

Place broadcasts with domain behavior when every caller needs them; keep response-specific rendering in the controller. Existing project conventions take priority over a blanket rule about where every broadcast must live.
