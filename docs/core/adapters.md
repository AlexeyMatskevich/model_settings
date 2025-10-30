# Storage Adapters

ModelSettings supports three storage backends: Column, JSON/JSONB, and StoreModel. Each adapter has different strengths and use cases.

## Quick Comparison

| Feature | Column | JSON | StoreModel |
|---------|--------|------|------------|
| **Storage** | One column per setting | Multiple settings in one JSONB column | Nested objects with type casting |
| **SQL Queries** | Easy, indexable | Requires JSONB operators | Requires JSONB operators |
| **Schema** | Fixed, explicit | Flexible, schemaless | Typed, validated |
| **Performance** | Fast for individual settings | Fast for bulk read/write | Medium (type casting overhead) |
| **Dirty Tracking** | Native ActiveRecord | Custom implementation | StoreModel integration |
| **Best For** | Feature flags, individual toggles | Related settings, preferences | Complex nested configs |

## Column Adapter

Store each setting as a separate database column. Best for feature flags and settings that are frequently queried individually.

### Basic Usage

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  setting :premium, type: :column, default: false
  setting :notifications_enabled, type: :column, default: true
end
```

### Migration

```ruby
class AddSettingsToUsers < ActiveRecord::Migration[7.0]
  def change
    add_column :users, :premium, :boolean, default: false, null: false
    add_column :users, :notifications_enabled, :boolean, default: true, null: false

    # Add index for frequently queried settings
    add_index :users, :premium
  end
end
```

### Helper Methods

Column adapter automatically generates helper methods for boolean settings:

```ruby
user = User.create!

# Getters/setters
user.premium  # => false
user.premium = true

# Helper methods
user.premium_enable!      # Set to true and save
user.premium_disable!     # Set to false and save
user.premium_toggle!      # Toggle and save

# Query methods
user.premium_enabled?     # => true
user.premium_disabled?    # => false

# Dirty tracking
user.premium = false
user.premium_changed?     # => true
user.premium_was          # => true
user.premium_change       # => [true, false]
```

### When to Use Column Adapter

✅ **Use when:**
- Settings are queried individually in SQL (`WHERE premium = true`)
- You need database indexes on settings
- Settings are independent (not grouped)
- You want explicit schema

❌ **Avoid when:**
- You have many related settings (bloats table with columns)
- Schema changes frequently
- Settings are always read/written together

---

## JSON Adapter

Store multiple settings in a single JSONB column. Best for related settings that are read and written together.

### Basic Usage

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  # Multiple settings in one JSON column
  setting :preferences, type: :json, storage: {column: :prefs_data} do
    setting :email_notifications, default: true
    setting :sms_notifications, default: false
    setting :dark_mode, default: false
  end
end
```

### Migration

```ruby
class AddPreferencesToUsers < ActiveRecord::Migration[7.0]
  def change
    # JSONB column with default empty hash
    add_column :users, :prefs_data, :jsonb, default: {}, null: false

    # GIN index for JSONB queries (PostgreSQL)
    add_index :users, :prefs_data, using: :gin
  end
end
```

### Usage

```ruby
user = User.create!

# Access nested settings directly
user.email_notifications = false
user.dark_mode = true
user.save!

# Helper methods work too
user.sms_notifications_enable!

# All stored in one JSONB column
user.prefs_data
# => {"email_notifications" => false, "sms_notifications" => false, "dark_mode" => true}

# Dirty tracking
user.email_notifications = true
user.email_notifications_changed?  # => true
```

### JSON Arrays

Store array values in JSON columns:

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  setting :allowed_ips,
          type: :json,
          storage: {column: :security_settings},
          array: true,
          default: []

  setting :tags,
          type: :json,
          storage: {column: :metadata},
          array: true
end

# Usage
user = User.create!
user.allowed_ips = ["192.168.1.1", "10.0.0.1"]
user.tags = ["premium", "verified"]
user.save!

# Array operations trigger dirty tracking
user.allowed_ips << "172.16.0.1"
user.allowed_ips_changed?  # => true
```

### Multiple JSON Columns

You can use multiple JSON columns in one model:

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  # Different groups in different columns
  setting :notifications, type: :json, storage: {column: :notification_settings} do
    setting :email, default: true
    setting :sms, default: false
  end

  setting :privacy, type: :json, storage: {column: :privacy_settings} do
    setting :public_profile, default: true
    setting :show_email, default: false
  end
end
```

### When to Use JSON Adapter

✅ **Use when:**
- Settings are related and read/written together
- You want flexible schema (easy to add/remove settings)
- You have many settings (avoids column bloat)
- You're using PostgreSQL with JSONB

❌ **Avoid when:**
- You need to query individual settings in SQL frequently
- You need indexes on specific settings
- You're using databases without good JSON support

---

## StoreModel Adapter

Use [StoreModel](https://github.com/DmitryTsepelev/store_model) for complex nested settings with type casting and validation.

### Setup

Add StoreModel to your Gemfile:

```ruby
gem 'store_model'
```

### Basic Usage

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

### Migration

```ruby
class AddNotificationPrefsToUsers < ActiveRecord::Migration[7.0]
  def change
    add_column :users, :notification_prefs, :jsonb, default: {}, null: false
  end
end
```

### Usage

```ruby
user = User.create!(notification_prefs: NotificationSettings.new)

# Type casting works automatically
user.email_notifications = true
user.email_notifications  # => true (boolean, not string)

# StoreModel's dirty tracking
user.email_notifications = false
user.email_notifications_changed?  # => true

# Access StoreModel object directly
user.notification_prefs
# => #<NotificationSettings email=false sms=false push=false frequency="daily">

# StoreModel validations work
user.notification_prefs.frequency = "invalid"
user.valid?  # StoreModel validations run
```

### Complex Example

```ruby
class AiSettings
  include StoreModel::Model

  attribute :transcription, :boolean, default: false
  attribute :sentiment, :boolean, default: false
  attribute :rate_limit, :integer, default: 100
  attribute :language, :string, default: "en"

  validates :rate_limit, numericality: {greater_than: 0, less_than_or_equal_to: 1000}
  validates :language, inclusion: {in: %w[en es fr de]}
end

class Callcenter < ApplicationRecord
  include ModelSettings::DSL

  attribute :ai_settings, AiSettings.to_type

  setting :transcription,
          type: :store_model,
          storage: {column: :ai_settings}

  setting :sentiment,
          type: :store_model,
          storage: {column: :ai_settings}
end

callcenter = Callcenter.create!(ai_settings: AiSettings.new)
callcenter.transcription = true
callcenter.ai_settings.rate_limit = 500
callcenter.save!

# StoreModel validations
callcenter.ai_settings.rate_limit = 2000
callcenter.valid?  # => false
callcenter.errors[:ai_settings]  # => ["Rate limit must be less than or equal to 1000"]
```

### When to Use StoreModel Adapter

✅ **Use when:**
- You need type casting (integers, dates, enums)
- You want StoreModel's validation framework
- You have complex nested structures
- You need strong typing

❌ **Avoid when:**
- Simple boolean settings (Column or JSON is simpler)
- You don't need type casting or validations
- Extra dependency is a concern

---

## Mixed Storage Types

You can mix storage types in a single model. Settings in parent-child relationships can use different storage backends.

### Column Parent with JSON Children

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  # Column parent
  setting :premium, type: :column, default: false, cascade: {enable: true} do
    # JSON children
    setting :theme,
            type: :json,
            storage: {column: :premium_features},
            default: "light"

    setting :advanced_filters,
            type: :json,
            storage: {column: :premium_features},
            default: false
  end
end

# Migration
add_column :users, :premium, :boolean, default: false
add_column :users, :premium_features, :jsonb, default: {}

# Usage
user = User.create!
user.premium = true
user.save!

# Cascade works across storage types
user.advanced_filters  # => true (cascaded from column parent)
user.theme            # => "light" (stored in JSON column)
```

### JSON Parent with Column Children

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  setting :notifications,
          type: :json,
          storage: {column: :settings},
          default: true do
    # Children use their own columns
    setting :email_enabled, type: :column, default: false
    setting :sms_enabled, type: :column, default: false
  end
end

# Migration
add_column :users, :settings, :jsonb, default: {}
add_column :users, :email_enabled, :boolean, default: false
add_column :users, :sms_enabled, :boolean, default: false

# Each setting uses its own storage
user = User.create!
user.notifications = false
user.email_enabled = true
user.save!

user.settings          # => {"notifications" => false}
user.email_enabled     # => true (separate column)
```

### Column Parent with StoreModel Children

```ruby
class PremiumFeatures
  include StoreModel::Model

  attribute :advanced_analytics, :boolean, default: false
  attribute :priority_support, :boolean, default: false
  attribute :custom_branding, :boolean, default: false
end

class User < ApplicationRecord
  include ModelSettings::DSL

  attribute :premium_features, PremiumFeatures.to_type

  setting :premium,
          type: :column,
          default: false,
          cascade: {enable: true} do
    setting :advanced_analytics,
            type: :store_model,
            storage: {column: :premium_features}

    setting :priority_support,
            type: :store_model,
            storage: {column: :premium_features}
  end
end

# Migration
add_column :users, :premium, :boolean, default: false
add_column :users, :premium_features, :jsonb, default: {}

# Cascades work across storage types
user = User.create!(premium_features: PremiumFeatures.new)
user.premium = true
user.save!

user.advanced_analytics  # => true (cascaded, stored in StoreModel)
user.priority_support    # => true (cascaded, stored in StoreModel)
```

---

## Performance Considerations

### Column Storage
- **Fastest** for individual setting queries
- Use indexes for frequently queried settings
- Table size grows with number of settings

```ruby
# Fast with index
User.where(premium: true)

# Add index
add_index :users, :premium
```

### JSON Storage
- **Fastest** for bulk read/write of related settings
- Use GIN indexes for JSONB queries (PostgreSQL)
- Requires JSONB operators for SQL queries

```ruby
# Requires JSONB operators
User.where("prefs_data @> ?", {dark_mode: true}.to_json)

# Add GIN index
add_index :users, :prefs_data, using: :gin
```

### StoreModel Storage
- **Type casting overhead** on read/write
- Similar to JSON for query performance
- Best when type safety is more important than raw speed

---

## Migration Patterns

### Adding a New Setting

**Column:**
```ruby
add_column :users, :new_feature, :boolean, default: false, null: false
```

**JSON:**
No migration needed! Just add to DSL:
```ruby
setting :preferences, type: :json, storage: {column: :prefs_data} do
  setting :new_feature, default: false  # No migration
end
```

### Renaming a Setting

**Column:**
```ruby
rename_column :users, :old_name, :new_name
```

**JSON:**
```ruby
# Data migration
User.find_each do |user|
  prefs = user.prefs_data
  prefs[:new_name] = prefs.delete(:old_name) if prefs.key?(:old_name)
  user.update_column(:prefs_data, prefs)
end
```

### Migrating Column → JSON

```ruby
class MigrateSettingsToJson < ActiveRecord::Migration[7.0]
  def up
    # Add JSON column
    add_column :users, :settings, :jsonb, default: {}, null: false

    # Migrate data
    User.find_each do |user|
      settings = {}
      settings[:feature_a] = user.feature_a
      settings[:feature_b] = user.feature_b
      user.update_column(:settings, settings)
    end

    # Remove old columns
    remove_column :users, :feature_a
    remove_column :users, :feature_b
  end
end
```

---

## Related Documentation

- [Dependencies](dependencies.md) - Cascades and syncs work across storage types
- [Validation](validation.md) - Built-in boolean validation for all adapters
- [Callbacks](callbacks.md) - Callbacks work with all adapters
- [Settings Inheritance](inheritance.md) - Inheritance works with all storage types

---

## Summary

| Choose Column When | Choose JSON When | Choose StoreModel When |
|--------------------|------------------|------------------------|
| Individual queries | Related settings | Type casting needed |
| Need indexes | Flexible schema | Validations needed |
| Explicit schema | Many settings | Complex nested objects |
| Simple toggles | Bulk read/write | Strong typing required |
