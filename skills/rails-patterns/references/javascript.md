# JavaScript Patterns

## Stimulus Controllers

- **Private fields** (`#`) for encapsulation — never expose internal state
- **Static declarations**: `targets`, `values`, `classes`, `outlets`
- **Event-driven**: Actions wired via `data-action` in HTML
- **Outlet pattern**: Controllers communicate via outlets, not global events

```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static classes = ["toolbar"]
  static targets = [ "clientid", "fields", "text" ]
  static values = { roomId: Number }
  static outlets = [ "messages" ]

  #files = []

  connect() {
    if (!this.#usingTouchDevice) {
      onNextEventLoopTick(() => this.textTarget.focus())
    }
  }

  submit(event) {
    event.preventDefault()
    if (!this.fieldsTarget.disabled) {
      this.#submitFiles()
      this.#submitMessage()
    }
  }

  get #usingTouchDevice() {
    return 'ontouchstart' in window || navigator.maxTouchPoints > 0;
  }

  async #submitMessage() {
    if (this.#validInput()) {
      const clientMessageId = this.#generateClientId()
      await this.messagesOutlet.insertPendingMessage(clientMessageId, this.textTarget)
      this.element.requestSubmit()
      this.#reset()
    }
  }

  #generateClientId() {
    return Math.random().toString(36).slice(2)
  }
}
```

## JS Models for Complex Logic

Complex logic is extracted into plain JS classes in `app/javascript/models/`:

```javascript
export default class MessageFormatter {
  #userId
  #classes

  constructor(userId, classes) {
    this.#userId = userId
    this.#classes = classes
  }

  format(message, threadstyle) {
    this.#setMeClass(message)
    this.#highlightMentions(message)
    this.#threadMessage(message)
    this.#setFirstOfDayClass(message)
    this.#makeVisible(message)
  }

  #setMeClass(message) {
    const isMe = message.dataset.userId == this.#userId
    message.classList.toggle(this.#classes.me, isMe)
  }
}
```

Pattern: Stimulus controllers are thin orchestrators. Complex logic lives in JS model classes.
