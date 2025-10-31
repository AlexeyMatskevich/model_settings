# StoreModel Adapter

Use [StoreModel](https://github.com/DmitryTsepelev/store_model) for complex nested settings with type casting and validation.

## Setup

Add StoreModel to your Gemfile:

```ruby
gem 'store_model'
```

## Basic Usage

```ruby
# Define StoreModel class
class NotificationSettings
  include StoreModel::Model

  attribute :email, :boolean, default: true
  attribute :sms, :boolean, default: false
  attribute :push, :boolean, default: false
  attribute :frequency, :string, default: "daily"
end

class User < ApplicationRecord
  include ModelSettings::DSL

  # Register StoreModel attribute
  attribute :notification_prefs, NotificationSettings.to_type

  # Define settings using StoreModel storage
  setting :email_notifications,
          type: :store_model,
          storage: {column: :notification_prefs}

  setting :sms_notifications,
          type: :store_model,
          storage: {column: :notification_prefs}
end
```

## Migration

```ruby
class AddNotificationPrefsToUsers < ActiveRecord::Migration[7.0]
  def change
    add_column :users, :notification_prefs, :jsonb, default: {}, null: false
  end
end
```

## StoreModel-Specific Features

### Type Casting

StoreModel automatically casts values to the correct type:

```ruby
class AiSettings
  include StoreModel::Model

  attribute :transcription, :boolean, default: false
  attribute :rate_limit, :integer, default: 100
  attribute :language, :string, default: "en"
  attribute :enabled_at, :datetime
end

class Callcenter < ApplicationRecord
  include ModelSettings::DSL

  attribute :ai_settings, AiSettings.to_type

  setting :transcription,
          type: :store_model,
          storage: {column: :ai_settings}
end

callcenter = Callcenter.create!(ai_settings: AiSettings.new)

# Type casting works automatically
callcenter.ai_settings.rate_limit = "500"  # String input
callcenter.ai_settings.rate_limit          # => 500 (Integer!)

callcenter.ai_settings.enabled_at = "2024-01-01"  # String input
callcenter.ai_settings.enabled_at                 # => DateTime object!
```

**Supported types:** `:boolean`, `:integer`, `:float`, `:string`, `:datetime`, `:date`, `:decimal`, custom types

### StoreModel Validations

StoreModel provides its own validation framework that runs alongside ModelSettings validation:

```ruby
class AiSettings
  include StoreModel::Model

  attribute :rate_limit, :integer, default: 100
  attribute :language, :string, default: "en"

  # StoreModel validations
  validates :rate_limit, numericality: {
    greater_than: 0,
    less_than_or_equal_to: 1000
  }
  validates :language, inclusion: {in: %w[en es fr de]}
end

class Callcenter < ApplicationRecord
  include ModelSettings::DSL

  attribute :ai_settings, AiSettings.to_type

  setting :transcription,
          type: :store_model,
          storage: {column: :ai_settings}
end

callcenter = Callcenter.create!(ai_settings: AiSettings.new)

# StoreModel validations run automatically
callcenter.ai_settings.rate_limit = 2000
callcenter.valid?  # => false
callcenter.errors[:ai_settings]
# => ["Rate limit must be less than or equal to 1000"]

callcenter.ai_settings.language = "invalid"
callcenter.valid?  # => false
callcenter.errors[:ai_settings]
# => ["Language is not included in the list"]
```

**Benefit:** StoreModel validations are separate from ModelSettings validations, providing layered validation.

### Accessing StoreModel Object

Access the underlying StoreModel object directly:

```ruby
# Access StoreModel object
callcenter.ai_settings
# => #<AiSettings transcription=false rate_limit=100 language="en">

# Set multiple attributes at once
callcenter.ai_settings.assign_attributes(
  transcription: true,
  rate_limit: 500,
  language: "es"
)
callcenter.save!

# Access via ModelSettings DSL
callcenter.transcription  # => true (ModelSettings accessor)
callcenter.ai_settings.transcription  # => true (StoreModel accessor)
```

**Note:** Both accessors point to the same data.

### Complex Example

```ruby
class PremiumFeatures
  include StoreModel::Model

  attribute :analytics_enabled, :boolean, default: false
  attribute :analytics_retention_days, :integer, default: 90
  attribute :support_tier, :string, default: "basic"
  attribute :custom_domain, :string

  validates :analytics_retention_days, numericality: {
    greater_than_or_equal_to: 30,
    less_than_or_equal_to: 365
  }
  validates :support_tier, inclusion: {in: %w[basic priority platinum]}
  validates :custom_domain, format: {
    with: /\A[a-z0-9-]+\.[a-z]{2,}\z/i,
    allow_blank: true
  }
end

class Organization < ApplicationRecord
  include ModelSettings::DSL

  attribute :premium_features, PremiumFeatures.to_type

  setting :analytics_enabled,
          type: :store_model,
          storage: {column: :premium_features}

  # Can combine with cascades
  setting :premium_plan,
          type: :column,
          cascade: {enable: true} do
    setting :analytics_enabled,
            type: :store_model,
            storage: {column: :premium_features}
  end
end

org = Organization.create!(premium_features: PremiumFeatures.new)

# Type casting
org.premium_features.analytics_retention_days = "180"  # String
org.premium_features.analytics_retention_days          # => 180 (Integer)

# StoreModel validations
org.premium_features.analytics_retention_days = 400
org.valid?  # => false (exceeds 365 days)

org.premium_features.custom_domain = "my-company.com"
org.valid?  # => true

org.premium_features.custom_domain = "invalid domain!"
org.valid?  # => false (format validation fails)
```

## When to Use StoreModel Adapter

✅ **Use when:**
- You need type casting (integers, dates, enums)
- You want StoreModel's validation framework
- You have complex nested structures
- You need strong typing

❌ **Avoid when:**
- Simple boolean settings (Column or JSON is simpler)
- You don't need type casting or validations
- Extra dependency is a concern

## Common Features

StoreModel adapter supports all common features:
- **Helper Methods** - `_enable!`, `_disable!`, `_toggle!`, `_enabled?`, `_disabled?`
- **Dirty Tracking** - StoreModel's built-in dirty tracking
- **Validation** - Boolean validation (in addition to StoreModel validations)

See [Common Features](../adapters.md#common-features) in the Adapters Overview.

## Related Documentation

- [Adapters Overview](../adapters.md) - Compare all adapter types
- [Column Adapter](column.md) - One setting per column
- [JSON Adapter](json.md) - Multiple settings in one JSONB column
- [StoreModel Gem Documentation](https://github.com/DmitryTsepelev/store_model) - Official StoreModel docs
