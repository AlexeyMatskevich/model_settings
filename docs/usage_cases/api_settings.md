# API Configuration

Manage API settings, keys, and rate limits with StoreModel.

## API Settings with StoreModel

```ruby
class ApiConfig
  include StoreModel::Model

  attribute :enabled, :boolean, default: false
  attribute :rate_limit, :integer, default: 100
  attribute :webhook_url, :string
  attribute :api_key, :string

  validates :rate_limit, numericality: {greater_than: 0}
  validates :webhook_url, format: URI::DEFAULT_PARSER.make_regexp(%w[http https]), allow_blank: true
end

class Organization < ApplicationRecord
  include ModelSettings::DSL

  attribute :api_config, ApiConfig.to_type

  setting :api_enabled,
          type: :store_model,
          storage: {column: :api_config}
end

# Migration
add_column :organizations, :api_config, :jsonb, default: {}, null: false

# Usage
org = Organization.create!(api_config: ApiConfig.new)
org.api_enabled = true
org.api_config.rate_limit = 1000
org.api_config.webhook_url = "https://example.com/webhook"
org.save!
```

## Rate Limiting Middleware

```ruby
class ApiRateLimiter
  def initialize(app)
    @app = app
  end

  def call(env)
    org = find_organization_from_request(env)
    
    if org.api_enabled && within_rate_limit?(org)
      @app.call(env)
    else
      [429, {}, ["Rate limit exceeded"]]
    end
  end
end
```
