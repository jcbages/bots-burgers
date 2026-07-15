# CSS — Semantic Classes Over Utility Sprawl

Campfire uses semantic CSS classes (`message`, `message--emoji`, `message__body`). The same principle applies to a Tailwind project via `@apply` component classes in one stylesheet (e.g. `application.tailwind.css`):

```css
/* One file defines the design language */
.btn-primary { @apply inline-flex items-center px-4 py-2 bg-blue-600 text-white ... }
.form-input  { @apply block w-full rounded-lg border border-gray-300 ... }
.badge       { @apply inline-flex items-center px-2 py-0.5 rounded-full text-xs ... }
```

```erb
<%# DO: use component classes %>
<button class="btn-primary">Save</button>

<%# DON'T: raw Tailwind when a component class exists %>
<button class="inline-flex items-center px-4 py-2 bg-blue-600 text-white rounded-lg">Save</button>
```

The principle: **one CSS file controls the design language.** Views use semantic class names. New component classes are added when a raw Tailwind pattern repeats 3+ times. Check `application.tailwind.css` before writing raw utilities.
