# JSON Adapter

Store multiple settings in a single JSONB column. Best for related settings that are read and written together.

## Basic Usage

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

## Migration

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

**Important:** Use JSONB (not JSON) for better performance and indexing support in PostgreSQL.

## JSON-Specific Features

### Nested Settings

Access nested settings directly without dealing with JSON hashes:

```ruby
user = User.create!

# Access nested settings directly
user.email_notifications = false
user.dark_mode = true
user.save!

# All stored in one JSONB column
user.prefs_data
# => {"email_notifications" => false, "sms_notifications" => false, "dark_mode" => true}
```

### Multiple JSON Columns

You can use multiple JSON columns in one model for logical grouping:

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

**Benefit:** Separate concerns and optimize queries per feature group.

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

## JSON Array Membership Pattern

Store settings as string values in a JSON array. The getter returns `true` if the value is in the array, `false` otherwise. Perfect for feature flags and permission lists.

### Basic Array Membership

```ruby
class Organization < ApplicationRecord
  include ModelSettings::DSL

  # Setting stored as array membership
  setting :omnichannel_startup,
          type: :json,
          storage: {column: :allowed_preferences, array: true}

  setting :voice_recording,
          type: :json,
          storage: {column: :allowed_preferences, array: true}
end
```

### Migration

```ruby
class AddAllowedPreferencesToOrganizations < ActiveRecord::Migration[7.0]
  def change
    add_column :organizations, :allowed_preferences, :jsonb, default: [], null: false
  end
end
```

### Usage

```ruby
org = Organization.create!(allowed_preferences: [])

# Getter: returns true if value in array
org.omnichannel_startup  # => false (not in array)

# Setter: adds/removes from array
org.omnichannel_startup = true
org.allowed_preferences  # => ["omnichannel_startup"]
org.omnichannel_startup  # => true

# Helper methods
org.voice_recording_enable!   # Adds "voice_recording" to array
org.allowed_preferences  # => ["omnichannel_startup", "voice_recording"]

org.omnichannel_startup_disable!  # Removes from array
org.allowed_preferences  # => ["voice_recording"]

# Dirty tracking works
org.voice_recording = false
org.voice_recording_changed?  # => true
org.voice_recording_was       # => true
org.voice_recording_change    # => [true, false]
```

### Custom Array Values

Use custom values for legacy compatibility or renaming settings without data migration:

```ruby
class Organization < ApplicationRecord
  include ModelSettings::DSL

  # Old data has "recording_v1" in array
  # New setting uses "recording_v2" value
  setting :voice_recording,
          type: :json,
          storage: {
            column: :allowed_preferences,
            array: true,
            array_value: "recording_v2"  # Custom value instead of "voice_recording"
          }
end

org.voice_recording = true
org.allowed_preferences  # => ["recording_v2"]  (uses custom value!)
```

### Migration Example

Renaming a setting without breaking existing data:

```ruby
# Old code
setting :old_feature,
        type: :json,
        storage: {column: :preferences, array: true}
# Database contains: ["old_feature"]

# Step 1: Add new setting with array_value pointing to old name
setting :new_feature_name,
        type: :json,
        storage: {
          column: :preferences,
          array: true,
          array_value: "old_feature"  # Points to old value
        }

# Works immediately with existing data!
org.new_feature_name  # => true (checks for "old_feature" in array)

# Step 2 (optional): Migrate array values in database later
# Organization.find_each do |org|
#   if org.preferences.include?("old_feature")
#     org.preferences = org.preferences - ["old_feature"] + ["new_feature_name"]
#     org.save!
#   end
# end
```

### Multiple Settings, Same Array

Multiple settings can share the same array column:

```ruby
setting :feature_a, type: :json, storage: {column: :features, array: true}
setting :feature_b, type: :json, storage: {column: :features, array: true}
setting :feature_c, type: :json, storage: {column: :features, array: true}

org.feature_a = true
org.feature_b = true
org.features  # => ["feature_a", "feature_b"]
```

### Validation

Arrays are automatically validated:

```ruby
org.allowed_preferences = "not_an_array"
org.valid?  # => false
org.errors[:allowed_preferences]  # => ["must be an array"]

org.allowed_preferences = nil  # Allowed (treated as empty array)
org.valid?  # => true
```

### When to Use Array Membership

✅ **Use when:**
- Managing feature flags or permissions
- Multiple boolean settings that logically belong together
- Need compact storage (one array for many settings)
- Settings are independent (no nested structure needed)

❌ **Avoid when:**
- Settings need complex values (not just boolean)
- Need nested configuration structures
- Settings have dependencies between them

## When to Use JSON Adapter

✅ **Use when:**
- Settings are related and read/written together
- You want flexible schema (easy to add/remove settings)
- You have many settings (avoids column bloat)
- You're using PostgreSQL with JSONB

❌ **Avoid when:**
- You need to query individual settings in SQL frequently
- You need indexes on specific settings
- You're using databases without good JSON support

## Common Features

JSON adapter supports all common features:
- **Helper Methods** - `_enable!`, `_disable!`, `_toggle!`, `_enabled?`, `_disabled?`
- **Dirty Tracking** - Custom dirty tracking (tracks JSON column changes)
- **Validation** - Boolean validation

See [Common Features](../adapters.md#common-features) in the Adapters Overview.

## Related Documentation

- [Adapters Overview](../adapters.md) - Compare all adapter types
- [Column Adapter](column.md) - One setting per column
- [StoreModel Adapter](store_model.md) - Complex nested settings
