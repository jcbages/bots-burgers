# Models, Concerns, Scopes & Callbacks

## Fat Models With Modular Concerns

### Model Structure

Campfire models follow a strict order: concerns, associations, enums, callbacks, validations, scopes, public methods, private methods.

```ruby
class User < ApplicationRecord
  include Avatar, Bannable, Bot, Mentionable, Role, Transferable

  has_many :memberships, dependent: :delete_all
  has_many :rooms, through: :memberships
  has_many :messages, dependent: :destroy, foreign_key: :creator_id

  enum :status, %i[ active deactivated banned ], default: :active
  has_secure_password validations: false

  after_create_commit :grant_membership_to_open_rooms

  scope :ordered, -> { order("LOWER(name)") }
  scope :filtered_by, ->(query) { where("name like ?", "%#{query}%") }

  def initials
    name.scan(/\b\w/).join
  end

  def deactivate
    transaction do
      close_remote_connections
      memberships.without_direct_rooms.delete_all
      push_subscriptions.delete_all
      sessions.delete_all
      update! status: :deactivated, email_address: deactived_email_address
    end
  end
end
```

### Concern Organization

Every concern is in `app/models/model_name/`. Each concern is focused, small, and handles one domain concept.

**User::Role** — simple enum + permission check:
```ruby
module User::Role
  extend ActiveSupport::Concern

  included do
    enum :role, %i[ member administrator bot ]
  end

  def can_administer?(record = nil)
    administrator? || self == record&.creator || record&.new_record?
  end
end
```

**User::Bot** — bot creation, authentication, webhook delivery:
```ruby
module User::Bot
  extend ActiveSupport::Concern

  included do
    scope :active_bots, -> { active.where(role: :bot) }
    has_one :webhook, dependent: :delete
  end

  module ClassMethods
    def create_bot!(attributes)
      bot_token = generate_bot_token
      webhook_url = attributes.delete(:webhook_url)
      User.create!(**attributes, bot_token: bot_token, role: :bot).tap do |user|
        user.create_webhook!(url: webhook_url) if webhook_url
      end
    end

    def authenticate_bot(bot_key)
      bot_id, bot_token = bot_key.split("-")
      active_bots.find_by(id: bot_id, bot_token: bot_token)
    end
  end

  def deliver_webhook_later(message)
    Bot::WebhookJob.perform_later(self, message) if webhook
  end
end
```

**Message::Pagination** — cursor-based pagination via scopes:
```ruby
module Message::Pagination
  extend ActiveSupport::Concern

  PAGE_SIZE = 40

  included do
    scope :last_page, -> { ordered.last(PAGE_SIZE) }
    scope :first_page, -> { ordered.first(PAGE_SIZE) }
    scope :before, ->(message) { where("created_at < ?", message.created_at) }
    scope :after, ->(message) { where("created_at > ?", message.created_at) }
    scope :page_before, ->(message) { before(message).last_page }
    scope :page_after, ->(message) { after(message).first_page }
  end

  class_methods do
    def page_around(message)
      page_before(message) + [ message ] + page_after(message)
    end
  end
end
```

**Message::Broadcasts** — thin broadcast methods, no logic:
```ruby
module Message::Broadcasts
  def broadcast_create
    broadcast_append_to room, :messages, target: [ room, :messages ]
    ActionCable.server.broadcast("unread_rooms", { roomId: room.id })
  end

  def broadcast_remove
    broadcast_remove_to room, :messages
  end
end
```

**Message::Searchable** — SQLite FTS5 integration:
```ruby
module Message::Searchable
  extend ActiveSupport::Concern

  included do
    after_create_commit  :create_in_index
    after_update_commit  :update_in_index
    after_destroy_commit :remove_from_index

    scope :search, ->(query) {
      joins("join message_search_index idx on messages.id = idx.rowid")
        .where("idx.body match ?", query).ordered
    }
  end

  private
    def create_in_index
      execute_sql_with_binds "insert into message_search_index(rowid, body) values (?, ?)", id, plain_text_body
    end
end
```

### Key Observations
- **6 concerns for User, 5 for Message** — small, focused modules
- **Scopes compose**: `before(message).last_page` chains scopes naturally
- **Transactions in models**: `deactivate` wraps multiple destructive operations
- **`included` block** for callbacks, scopes, associations that run at include-time
- **`class_methods` or `module ClassMethods`** for class-level methods
- **`default: ->` for belongs_to**: `belongs_to :creator, class_name: "User", default: -> { Current.user }`

---

## Association Extensions

Campfire extends `has_many` associations with custom methods directly on the association proxy:

```ruby
class Room < ApplicationRecord
  has_many :memberships, dependent: :delete_all do
    def grant_to(users)
      room = proxy_association.owner
      Membership.insert_all(Array(users).collect { |user| {
        room_id: room.id, user_id: user.id, involvement: room.default_involvement
      }})
    end

    def revoke_from(users)
      destroy_by user: users
    end

    def revise(granted: [], revoked: [])
      transaction do
        grant_to(granted) if granted.present?
        revoke_from(revoked) if revoked.present?
      end
    end
  end
end
```

This allows `room.memberships.grant_to(users)` — domain-rich, readable API on the association.

---

## STI (Single Table Inheritance) for Type Specialization

```ruby
class Room < ApplicationRecord
  scope :opens,   -> { where(type: "Rooms::Open") }
  scope :closeds, -> { where(type: "Rooms::Closed") }
  scope :directs, -> { where(type: "Rooms::Direct") }
end

class Rooms::Open < Room
  after_save_commit :grant_access_to_all_users

  private
    def grant_access_to_all_users
      memberships.grant_to(User.active) if type_previously_changed?(to: "Rooms::Open")
    end
end

class Rooms::Direct < Room
  class << self
    def find_or_create_for(users)
      find_for(users) || create_for({}, users: users)
    end
  end

  def default_involvement
    "everything"
  end
end
```

Behavior changes by type, not by conditionals. Each subclass owns its specific logic.

---

## CurrentAttributes

```ruby
class Current < ActiveSupport::CurrentAttributes
  attribute :session, :user, :request

  delegate :host, :protocol, to: :request, prefix: true, allow_nil: true

  def session=(value)
    super(value)
    self.user = session.user if value.present?
  end

  def account
    Account.first
  end
end
```

Setting `Current.session` automatically sets `Current.user` — cascading state via setter override.

---

## Callbacks & Lifecycle

Campfire uses callbacks for side effects that MUST happen:

```ruby
class Message < ApplicationRecord
  before_create -> { self.client_message_id ||= Random.uuid }
  after_create_commit -> { room.receive(self) }
end

class Room < ApplicationRecord
  def receive(message)
    unread_memberships(message)
    push_later(message)
  end

  private
    def push_later(message)
      Room::PushMessageJob.perform_later(self, message)
    end
end
```

Pattern: `after_create_commit` triggers async work via model method, which enqueues a job.

---

## Scope Filtering Pattern

When index actions need filtering, build it entirely from scopes — never construct queries in the controller.

### The Anti-Pattern (DON'T)

```ruby
# Controller builds query inline — WRONG
def index
  messages = Message.joins(:channel).merge(@current_account.channels)
  messages = messages.where(status: params[:status]) if params[:status]
  messages = messages.where(channel_id: channel.id) if params[:channel_id]
  render json: messages
end
```

### The Campfire Way (DO)

Scopes on the model, composed in the controller via a class method:

```ruby
# Model — all query logic lives here
class Message < ApplicationRecord
  scope :for_account, ->(account) {
    joins(:channel).merge(account.channels)
  }
  scope :for_channel, ->(channel) { where(channel: channel) }
  scope :with_status, ->(status) { where(status: status) }

  def self.apply_filters(scope, params)
    scope = scope.for_channel(params[:channel]) if params[:channel]
    scope = scope.with_status(params[:status]) if params[:status]
    scope
  end
end

# Controller — thin orchestrator
def index
  messages = Message.for_account(@current_account)
  messages = Message.apply_filters(messages, params)
  render json: messages
end
```

Key: every `.where()`, `.joins()`, `.merge()` is a named scope. The controller never touches Arel directly.
