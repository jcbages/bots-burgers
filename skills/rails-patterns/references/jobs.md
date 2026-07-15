# Background Jobs

## Minimal Job Classes

Jobs are one-liners that delegate to a model or service:

```ruby
class Room::PushMessageJob < ApplicationJob
  def perform(room, message)
    Room::MessagePusher.new(room:, message:).push
  end
end

class Bot::WebhookJob < ApplicationJob
  def perform(bot, message)
    bot.deliver_webhook(message)
  end
end

class RemoveBannedContentJob < ApplicationJob
  def perform(user)
    user.remove_banned_content
  end
end
```

## Complex Job Logic in Dedicated Classes

When a job needs complex logic, it lives in a separate class (not in the job):

```ruby
class Room::MessagePusher
  attr_reader :room, :message

  def initialize(room:, message:)
    @room, @message = room, message
  end

  def push
    build_payload.tap do |payload|
      push_to_users_involved_in_everything(payload)
      push_to_users_involved_in_mentions(payload)
    end
  end

  private
    def build_payload
      if room.direct?
        { title: message.creator.name, body: message.plain_text_body, path: room_path(room) }
      else
        { title: room.name, body: "#{message.creator.name}: #{message.plain_text_body}", path: room_path(room) }
      end
    end
end
```

Pattern: `Job#perform` is always a one-liner. Complex logic goes in a dedicated class.
