# JavaScript and Stimulus

Use the project's existing frontend stack. Do not add Alpine or migrate to Stimulus merely to follow this reference.

Stimulus controllers coordinate DOM behavior through targets, values, classes, and actions. Keep local UI behavior local; extract plain JavaScript functions or classes when complex or reusable behavior benefits from independent reasoning and testing. A new class is not required for each controller method.

Use private fields for internal state when appropriate, keeping methods invoked by Stimulus actions accessible. Prefer outlets for explicit controller relationships and dispatched events for loose coupling or integration with non-Stimulus consumers. Neither mechanism is universally preferred.

Account for reconnects: release listeners, observers, and timers in `disconnect` when they outlive the controller, and avoid duplicating subscriptions. For async work, handle rejected operations and results arriving after the relevant DOM or state changed.
