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

## Adapter Types

### Column Adapter

Store each setting as a separate database column. Best for feature flags and settings that are frequently queried individually.

**Quick Example:**
```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  setting :premium, type: :column, default: false
  setting :notifications_enabled, type: :column, default: true
end
```

✅ **Use when:** Settings are queried individually, need indexes, want explicit schema

📖 **[Full Column Adapter Documentation →](adapters/column.md)**

---

### JSON Adapter

Store multiple settings in a single JSONB column. Best for related settings that are read and written together.

**Quick Example:**
```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  setting :preferences, type: :json, storage: {column: :prefs_data} do
    setting :email_notifications, default: true
    setting :dark_mode, default: false
  end
end
```

✅ **Use when:** Related settings, flexible schema, many settings, using PostgreSQL JSONB

**Special Feature: JSON Array Membership** - Store settings as string values in a JSON array for compact feature flags:

```ruby
setting :feature_a, type: :json, storage: {column: :features, array: true}
setting :feature_b, type: :json, storage: {column: :features, array: true}

org.feature_a = true
org.features  # => ["feature_a"]
```

📖 **[Full JSON Adapter Documentation →](adapters/json.md)**

---

### StoreModel Adapter

Use [StoreModel](https://github.com/DmitryTsepelev/store_model) for complex nested settings with type casting and validation.

**Quick Example:**
```ruby
class NotificationSettings
  include StoreModel::Model

  attribute :email, :boolean, default: true
  attribute :frequency, :string, default: "daily"
end

class User < ApplicationRecord
  include ModelSettings::DSL

  attribute :notification_prefs, NotificationSettings.to_type

  setting :email_notifications,
          type: :store_model,
          storage: {column: :notification_prefs}
end
```

✅ **Use when:** Need type casting, StoreModel validations, complex nested structures

📖 **[Full StoreModel Adapter Documentation →](adapters/store_model.md)**

---

## Common Features

All adapters share these core features regardless of storage backend.

### Helper Methods

ModelSettings automatically generates helper methods for boolean settings:

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL
  setting :premium, type: :column, default: false
end

user = User.create!

# Getters/setters
user.premium          # => false
user.premium = true

# Action methods (change + save)
user.premium_enable!   # Set to true and save!
user.premium_disable!  # Set to false and save!
user.premium_toggle!   # Toggle and save!

# Query methods
user.premium_enabled?  # => true
user.premium_disabled? # => false
```

**Available for:** Column, JSON, StoreModel (all adapters)

**Note:** Helper methods work the same regardless of storage backend. A JSON-stored setting has the same `_enable!`, `_disable!`, `_toggle!` methods as a column-stored setting.

### Dirty Tracking

All adapters provide full dirty tracking support:

```ruby
user = User.create!(premium: false)

# Make a change
user.premium = true

# Check if changed
user.premium_changed?       # => true
user.premium_was            # => false (previous value)
user.premium_change         # => [false, true] (from → to)
user.changes                # => {"premium" => [false, true]}

# Reset changes
user.restore_premium!       # Restore to original value
user.premium                # => false

# After save
user.save!
user.premium_changed?       # => false (no pending changes)
```

**Available for:** Column, JSON, StoreModel (all adapters)

**Implementation:**
- **Column**: Native ActiveRecord dirty tracking
- **JSON**: Custom dirty tracking (tracks JSON column changes)
- **StoreModel**: StoreModel's built-in dirty tracking

### Validation

All boolean settings are validated by default:

```ruby
user.premium = "not_a_boolean"
user.valid?  # => false
user.errors[:premium]  # => ["must be a boolean"]

# Only true, false, or nil allowed
user.premium = true   # ✅ Valid
user.premium = false  # ✅ Valid
user.premium = nil    # ✅ Valid
user.premium = "yes"  # ❌ Invalid
user.premium = 1      # ❌ Invalid
```

**Available for:** Column, JSON, StoreModel (all adapters)

**Custom validation:** Add your own validators using `validate_with`:

```ruby
setting :premium,
        type: :column,
        validate_with: :check_premium_eligibility

def check_premium_eligibility
  errors.add(:premium, "requires verified email") unless email_verified?
end
```

See [Validation Guide](validation.md) for more details.

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

**JSON Array with array_value:**
```ruby
# No data migration needed! Use array_value to point to old name
setting :new_feature_name,
        type: :json,
        storage: {
          column: :preferences,
          array: true,
          array_value: "old_feature"  # Points to old value in array
        }
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

- **[Column Adapter](adapters/column.md)** - Detailed column adapter documentation
- **[JSON Adapter](adapters/json.md)** - Detailed JSON adapter documentation with JSON Array Membership
- **[StoreModel Adapter](adapters/store_model.md)** - Detailed StoreModel adapter documentation
- **[Dependencies](dependencies.md)** - Cascades and syncs work across storage types
- **[Validation](validation.md)** - Built-in boolean validation for all adapters
- **[Callbacks](callbacks.md)** - Callbacks work with all adapters
- **[Settings Inheritance](inheritance.md)** - Inheritance works with all storage types

---

## Summary

| Choose Column When | Choose JSON When | Choose StoreModel When |
|--------------------|------------------|------------------------|
| Individual queries | Related settings | Type casting needed |
| Need indexes | Flexible schema | Validations needed |
| Explicit schema | Many settings | Complex nested objects |
| Independent settings | Bulk read/write | Strong typing required |
