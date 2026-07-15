# View Patterns

## Fragment Caching

```erb
<% cache message do %>
  <%= message_tag message do %>
    ...
  <% end %>
<% end %>
```

## Helper-Generated HTML with Data Attributes

Complex data-attribute wiring lives in helpers, not views:

```ruby
module MessagesHelper
  def message_area_tag(room, &)
    tag.div id: "message-area", class: "message-area", data: {
      controller: "messages presence drop-target",
      action: [ messages_actions, drop_target_actions, presence_actions ].join(" "),
      messages_page_url_value: room_messages_url(room)
    }, &
  end

  def message_tag(message, &)
    tag.div id: dom_id(message),
      class: "message #{"message--emoji" if message.plain_text_body.all_emoji?}",
      data: {
        controller: "reply",
        user_id: message.creator_id,
        message_id: message.id,
        messages_target: "message"
      }, &
  end
end
```

This keeps views clean — complex data attributes are composed in Ruby, not scattered across ERB.

## Layout with Named Yields

```erb
<nav id="nav"><%= yield :nav %></nav>
<main id="main-content">
  <%= yield %>
  <footer id="footer"><%= yield :footer %></footer>
</main>
<aside id="sidebar"><%= yield :sidebar %></aside>
```

Views provide content for named sections via `content_for`.
