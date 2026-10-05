# Views and helpers

Keep templates readable using the project's partials, components, and helpers. Extract complex reusable markup or data-attribute wiring when it clarifies the template; a simple inline attribute needs no helper.

Use fragment caching when rendering cost justifies it and the key captures every dependency that can change the output. Include tenant/user context when the rendered content varies by it; do not share personalized fragments under a model-only key.

Use layout yields and `content_for` where the project already organizes shared page regions that way. Escape untrusted content and preserve accessible labels and action semantics while refactoring markup.
