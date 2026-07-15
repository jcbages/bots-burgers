# Controllers & Authentication

## Slim Controllers

**Golden Rule**: Controllers orchestrate (1-5 lines/action). ALL business logic lives in models.

### What Campfire Controllers Look Like

```ruby
class MessagesController < ApplicationController
  include ActiveStorage::SetCurrent, RoomScoped

  before_action :set_message, only: %i[ show edit update destroy ]
  before_action :ensure_can_administer, only: %i[ edit update destroy ]

  def index
    @messages = find_paged_messages
    fresh_when @messages if @messages.any?
  end

  def create
    set_room
    @message = @room.messages.create_with_attachment!(message_params)
    @message.broadcast_create
  end

  def update
    @message.update!(message_params)
    @message.broadcast_replace_to @room, :messages, target: [ @message, :presentation ],
      partial: "messages/presentation", attributes: { maintain_scroll: true }
    redirect_to room_message_url(@room, @message)
  end

  private
    def message_params
      params.require(:message).permit(:body, :attachment, :client_message_id)
    end
end
```

### Key Observations
- **Concerns-first**: Controllers include cross-cutting concerns (`RoomScoped`, `ActiveStorage::SetCurrent`)
- **No fat controllers**: `create` calls `create_with_attachment!` on the model, then `broadcast_create` — zero business logic
- **`before_action` for setup**: `set_room`, `set_message`, `ensure_can_administer` — all via before_action
- **Rate limiting**: Built-in Rails rate limiting on sensitive actions
  ```ruby
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { render_rejection :too_many_requests }
  ```
- **Nested controllers** with module namespacing:
  ```ruby
  class Accounts::UsersController < ApplicationController
    def index
      set_page_and_extract_portion_from User.active.ordered.without_bots, per_page: 500
    end
  end
  ```

### Controller Concerns

Authorization is a one-liner concern:
```ruby
module Authorization
  private
    def ensure_can_administer
      head :forbidden unless Current.user.can_administer?
    end
end
```

Scoping is a before_action concern:
```ruby
module RoomScoped
  extend ActiveSupport::Concern

  included do
    before_action :set_room
  end

  private
    def set_room
      @membership = Current.user.memberships.find_by!(room_id: params[:room_id])
      @room = @membership.room
    end
end
```

---

## Authentication

Authentication concern uses `class_methods` for opt-out:

```ruby
module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :require_authentication
    helper_method :signed_in?
  end

  class_methods do
    def allow_unauthenticated_access(**options)
      skip_before_action :require_authentication, **options
    end
  end
end
```

Broadcasts happen via model methods (not controllers or channels):

```ruby
broadcast_append_to room, :messages, target: [ room, :messages ]
broadcast_replace_to @room, :messages, target: [ @message, :presentation ], partial: "messages/presentation"
```
