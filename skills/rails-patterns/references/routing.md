# Routing

Resource-based, nested, with scoped modules:

```ruby
Rails.application.routes.draw do
  root "welcome#show"

  resource :session
  resource :account do
    scope module: "accounts" do
      resources :users
      resources :bots do
        scope module: "bots" do
          resource :key, only: :update
        end
      end
    end
  end

  resources :rooms do
    resources :messages
    post ":bot_key/messages", to: "messages/by_bots#create", as: :bot_messages

    scope module: "rooms" do
      resource :refresh, only: :show
      resource :involvement, only: %i[ show update ]
    end

    get "@:message_id", to: "rooms#show", as: :at_message
  end
end
```

Key patterns: `scope module:` for nested controllers without deeply nested URLs, `resource` (singular) for singleton resources, custom routes only when RESTful routes don't fit.
