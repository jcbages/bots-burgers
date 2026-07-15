# Testing

## Fixtures Over Factories

```yaml
# test/fixtures/users.yml
<% password_digest = BCrypt::Password.create("secret123456") %>

david:
  name: David
  email_address: david@37signals.com
  password_digest: <%= password_digest %>
  role: administrator

jason:
  name: Jason
  email_address: jason@37signals.com
  password_digest: <%= password_digest %>
  role: administrator
```

## Test Setup

```ruby
class ActiveSupport::TestCase
  include ActiveJob::TestHelper
  parallelize(workers: :number_of_processors)
  fixtures :all
  include SessionTestHelper, MentionTestHelper, TurboTestHelper
end
```

## Model Tests — Test Behavior, Not Implementation

```ruby
class MessageTest < ActiveSupport::TestCase
  test "creating a message enqueues to push later" do
    assert_enqueued_jobs 1, only: [ Room::PushMessageJob ] do
      create_new_message_in rooms(:designers)
    end
  end

  test "mentionees" do
    message = Message.new room: rooms(:pets), body: mention_body(:david), creator: users(:jason)
    assert_equal [ users(:david) ], message.mentionees
  end

  private
    def create_new_message_in(room)
      room.messages.create!(creator: users(:jason), body: "Hello", client_message_id: "123")
    end
end
```
