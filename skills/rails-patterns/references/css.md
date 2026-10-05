# CSS

Follow the project's existing styling system. Reuse established components, tokens, or utility conventions before introducing another abstraction.

Extract a semantic component class when repeated styling or a stable design role benefits from a shared definition. Utilities can be appropriate for local layout; do not require every view to move styles into one global stylesheet. Use `@apply` only when it fits the installed Tailwind version and project conventions.

When changing a shared token, inspect affected consumers and verify representative rendered states. Inheritance, component defaults, and local overrides can make a theme edit ineffective. Keep surface-specific colors separate from reusable translucent tokens when their backgrounds differ.
