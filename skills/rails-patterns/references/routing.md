# Routing

Prefer resource routes when the operation naturally matches a resource lifecycle. Singular resources fit a singleton in the current context. Use namespaces or `scope module:` to organize controllers while choosing URLs deliberately.

Avoid deeply nested routes when a shallower resource identifies the target clearly. A custom action or endpoint is reasonable when it expresses the domain better than an artificial resource. Preserve authorization and client compatibility when changing route shape; update affected callers and documented public interfaces.
