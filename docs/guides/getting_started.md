# Getting Started with ModelSettings

This guide will walk you through installing and using ModelSettings from zero to your first working settings.

## What is ModelSettings?

ModelSettings is a declarative DSL for managing configuration settings and feature flags in Rails models. Instead of scattering boolean columns and validation logic across your codebase, ModelSettings provides a unified, type-safe way to define and manage settings.

## Installation

Add ModelSettings to your Gemfile:

```ruby
gem 'model_settings'
```

Run bundle:

```bash
bundle install
```

That's it! No generators needed, no configuration files required. You're ready to define settings.

## Your First Setting

Let's add a simple feature flag to a User model.

### 1. Create the Migration

```ruby
class AddPremiumToUsers < ActiveRecord::Migration[7.0]
  def change
    add_column :users, :premium, :boolean, default: false, null: false
  end
end
```

Run the migration:

```bash
rails db:migrate
```

### 2. Define the Setting

In your User model:

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  setting :premium, type: :column, default: false
end
```

### 3. Use It

```ruby
# Create a user
user = User.create!(email: "user@example.com")

# Check the setting
user.premium  # => false

# Change it
user.premium = true
user.save!

# Use helper methods
user.premium_enable!
user.premium_disable!
user.premium_toggle!

# Check state
user.premium_enabled?  # => true
user.premium_disabled? # => false

# Track changes
user.premium = false
user.premium_changed? # => true
user.premium_was      # => true
user.premium_change   # => [true, false]
```

**Congratulations! You've created your first setting.** 🎉

## Common Use Cases

### Multiple Related Settings

Instead of many database columns, use JSON storage:

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  # Migration: add_column :users, :preferences, :jsonb, default: {}, null: false

  setting :preferences, type: :json, storage: {column: :preferences} do
    setting :email_notifications, default: true
    setting :sms_notifications, default: false
    setting :dark_mode, default: false
  end
end

# Usage
user = User.create!
user.email_notifications = false
user.dark_mode = true
user.save!

# All stored in one JSONB column
user.preferences
# => {"email_notifications" => false, "sms_notifications" => false, "dark_mode" => true}
```

### Dependent Features

Enable child features when parent is enabled:

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  setting :premium, type: :column, cascade: {enable: true} do
    setting :advanced_analytics, type: :column
    setting :priority_support, type: :column
    setting :custom_branding, type: :column
  end
end

# When you enable premium...
user.premium = true
user.save!

# All premium features are automatically enabled!
user.advanced_analytics  # => true
user.priority_support    # => true
user.custom_branding     # => true
```

### Authorization

Control who can view or edit settings:

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL
  include ModelSettings::Modules::Roles

  setting :billing_override,
          type: :column,
          viewable_by: [:admin, :finance],
          editable_by: [:admin]
end

# Check permissions
user.can_view_setting?(:billing_override, :finance)  # => true
user.can_edit_setting?(:billing_override, :finance)  # => false

# Get settings for a role
User.settings_editable_by(:admin)
# => [:billing_override]
```

## Storage Options

ModelSettings supports three storage backends:

### 1. Column Storage

**Best for**: Individual feature flags, frequently queried settings

```ruby
# Migration
add_column :users, :premium, :boolean, default: false, null: false

# Model
setting :premium, type: :column, default: false
```

**Pros**: Fast queries, indexable, clear schema
**Cons**: One column per setting

### 2. JSON Storage

**Best for**: Related settings read/written together, flexible schemas

```ruby
# Migration
add_column :users, :settings, :jsonb, default: {}, null: false
add_index :users, :settings, using: :gin

# Model
setting :notifications, type: :json, storage: {column: :settings} do
  setting :email, default: true
  setting :sms, default: false
end
```

**Pros**: Many settings in one column, flexible schema
**Cons**: Harder to query individual settings in SQL

### 3. StoreModel Storage

**Best for**: Complex nested objects with type casting and validation

```ruby
# Define StoreModel
class NotificationSettings
  include StoreModel::Model

  attribute :email, :boolean, default: true
  attribute :sms, :boolean, default: false
  attribute :push, :boolean, default: false
end

# Migration
add_column :users, :notification_prefs, :jsonb, default: {}, null: false

# Model
class User < ApplicationRecord
  include ModelSettings::DSL

  attribute :notification_prefs, NotificationSettings.to_type

  setting :email, type: :store_model, storage: {column: :notification_prefs}
  setting :sms, type: :store_model, storage: {column: :notification_prefs}
end
```

**Pros**: Type casting, StoreModel validations, nested objects
**Cons**: Requires StoreModel gem, more complex setup

## Next Steps

Now that you understand the basics, explore:

- **[Storage Adapters](../core/adapters.md)** - Deep dive into Column, JSON, and StoreModel storage
- **[Dependencies](../core/dependencies.md)** - Cascades and syncs for complex relationships
- **[Authorization Modules](../modules/roles.md)** - Control access with Roles, Pundit, or ActionPolicy
- **[Validation](../core/validation.md)** - Built-in boolean validation and custom validators
- **[Usage Cases](../usage_cases/)** - Real-world examples

## Common Questions

### Do I need to include ModelSettings::DSL in every model?

Yes, every model that uses settings must include `ModelSettings::DSL`.

### Can I mix storage types in one model?

Yes! You can have some settings as columns and others in JSON:

```ruby
setting :premium, type: :column  # Column storage
setting :preferences, type: :json, storage: {column: :prefs} do  # JSON storage
  setting :theme, default: "dark"
end
```

### What happens if I forget to save?

Settings follow ActiveRecord semantics. Changes are in-memory until you call `save!`:

```ruby
user.premium = true
user.premium  # => true (in memory)
user.reload
user.premium  # => false (not persisted)

user.premium = true
user.save!
user.reload
user.premium  # => true (persisted)
```

### Can I use this with existing boolean columns?

Absolutely! ModelSettings works with existing columns:

```ruby
# You already have: add_column :users, :active, :boolean

class User < ApplicationRecord
  include ModelSettings::DSL

  setting :active, type: :column  # Uses existing column
end

# Now you get all the helper methods for free!
user.active_enable!
user.active_toggle!
user.active_changed?
```

### How do I test settings?

Test them like normal ActiveRecord attributes:

```ruby
RSpec.describe User do
  it "has premium setting" do
    user = User.create!
    expect(user.premium).to be false

    user.premium_enable!
    expect(user.premium).to be true
  end
end
```

## Troubleshooting

### Error: "column 'setting_name' does not exist"

You forgot to create the migration for column storage. Add the column:

```ruby
add_column :users, :setting_name, :boolean, default: false, null: false
```

### Error: "must be true or false"

ModelSettings enforces strict boolean validation. Don't pass strings or integers:

```ruby
# ❌ Wrong
user.premium = "true"  # Error!
user.premium = 1       # Error!

# ✅ Correct
user.premium = true
user.premium = false
```

### Settings not persisting

Did you forget to call `save!`?

```ruby
user.premium = true  # In memory only
user.save!          # Now it's persisted
```

## Summary

You've learned how to:

- ✅ Install ModelSettings
- ✅ Create your first setting with column storage
- ✅ Use JSON storage for multiple related settings
- ✅ Use cascades for dependent features
- ✅ Add role-based authorization
- ✅ Choose the right storage type

**Ready for more?** Check out the [complete documentation](../README.md) or jump into [real-world usage cases](../usage_cases/).
