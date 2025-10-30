# Migration Guide

This guide shows how to migrate to ModelSettings from various existing solutions.

## Migrating from Boolean Columns

### Before: Plain Boolean Columns

You have many boolean columns scattered across your model:

```ruby
class User < ApplicationRecord
  # Many boolean columns
  # Validations scattered throughout
  # No helper methods
  # Hard to organize
end

# Migration
add_column :users, :premium, :boolean, default: false
add_column :users, :notifications_enabled, :boolean, default: true
add_column :users, :api_access, :boolean, default: false
add_column :users, :dark_mode, :boolean, default: false
```

**Problems**:
- No helper methods (`enable!`, `disable!`, `toggle!`)
- No organization or grouping
- Validation logic scattered
- No authorization control
- Hard to document

### After: ModelSettings with Column Storage

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  setting :premium, type: :column, default: false
  setting :notifications_enabled, type: :column, default: true
  setting :api_access, type: :column, default: false
  setting :dark_mode, type: :column, default: false
end

# Same migrations - columns are unchanged!
# But now you get:
user.premium_enable!
user.premium_toggle!
user.premium_changed?
# Plus: validation, authorization, callbacks, documentation
```

**Benefits**:
- ✅ Keep existing database schema
- ✅ Add helper methods automatically
- ✅ Built-in validation
- ✅ Easy authorization with modules
- ✅ Auto-generated documentation
- ✅ Callback hooks

### Migration Steps

1. **Add ModelSettings to existing model**:

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  # Convert each boolean column to a setting
  setting :premium, type: :column, default: false
  setting :notifications_enabled, type: :column, default: true
  # ... etc
end
```

2. **Update code to use new helpers** (optional but recommended):

```ruby
# Before
user.premium = true
user.save!

# After (cleaner)
user.premium_enable!
```

3. **Add authorization** (optional):

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL
  include ModelSettings::Modules::Roles

  setting :premium,
          type: :column,
          viewable_by: [:admin, :user],
          editable_by: [:admin]
end
```

**No data migration needed!** Your existing data stays intact.

## Migrating from JSON/JSONB Hashes

### Before: Manual JSON Management

```ruby
class User < ApplicationRecord
  store_accessor :settings, :email_notifications, :sms_notifications, :dark_mode
end

# Migration
add_column :users, :settings, :jsonb, default: {}, null: false

# Usage
user.email_notifications = true
user.settings  # => {"email_notifications" => true}
```

**Problems**:
- No type coercion
- No dirty tracking
- No helper methods
- Manual accessor management
- No validation

### After: ModelSettings with JSON Storage

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  setting :preferences, type: :json, storage: {column: :settings} do
    setting :email_notifications, default: true
    setting :sms_notifications, default: false
    setting :dark_mode, default: false
  end
end

# Same column, but now you get:
user.email_notifications_enable!
user.email_notifications_changed?
user.email_notifications_was
# Plus: validation, callbacks, documentation
```

**Benefits**:
- ✅ Keep existing JSONB column
- ✅ Automatic dirty tracking
- ✅ Helper methods for booleans
- ✅ Nested organization
- ✅ Type validation

### Migration Steps

1. **Remove `store_accessor`** and add ModelSettings:

```ruby
# Before
class User < ApplicationRecord
  store_accessor :settings, :email_notifications, :sms_notifications
end

# After
class User < ApplicationRecord
  include ModelSettings::DSL

  setting :preferences, type: :json, storage: {column: :settings} do
    setting :email_notifications, default: true
    setting :sms_notifications, default: false
  end
end
```

2. **Existing data works automatically**:

```ruby
# Your existing JSON data:
# settings: {"email_notifications" => true, "sms_notifications" => false}

user = User.find(1)
user.email_notifications  # => true (reads from existing JSON)
user.email_notifications = false
user.save!
# Updates JSON: {"email_notifications" => false, "sms_notifications" => false}
```

3. **Gradually replace manual access**:

```ruby
# Before
user.settings["email_notifications"] = true

# After
user.email_notifications = true  # Type-safe, validated
```

**No data migration needed!** Existing JSON structure is preserved.

## Migrating from Feature Flag Gems

### From Flipper, Rollout, or similar

These gems provide global feature flags. ModelSettings provides **per-record settings**.

**Before: Flipper**

```ruby
# Global flags
Flipper.enable(:premium_features)
Flipper.enabled?(:premium_features)  # => true

# Per-user flags
Flipper.enable_actor(:premium_features, user)
Flipper.enabled?(:premium_features, user)  # => true
```

**After: ModelSettings**

```ruby
# Per-record settings
class User < ApplicationRecord
  include ModelSettings::DSL

  setting :premium_features, type: :column, default: false
end

user.premium_features  # => false
user.premium_features_enable!
user.premium_features  # => true
```

**Key Differences**:

| Feature | Flipper/Rollout | ModelSettings |
|---------|-----------------|---------------|
| **Scope** | Global + per-actor | Per-record (database-backed) |
| **Storage** | Redis, ActiveRecord | ActiveRecord (columns/JSON) |
| **Gradual rollout** | ✅ Built-in | ❌ Manual implementation |
| **Per-record state** | Through actors | ✅ Native |
| **Relationships** | Manual | ✅ Cascades & syncs |
| **Authorization** | Manual | ✅ Built-in modules |

**When to use each**:

- **Flipper/Rollout**: Global feature flags, A/B testing, gradual rollouts
- **ModelSettings**: Per-user/per-tenant settings, preferences, configuration

**Can I use both?** Yes! Use Flipper for global rollouts and ModelSettings for per-user configuration.

## Migrating from ActiveModel::Attributes

### Before: Custom Attributes

```ruby
class User < ApplicationRecord
  attribute :premium, :boolean, default: false
  attribute :api_access, :boolean, default: false

  def premium_enable!
    update(premium: true)
  end

  def premium_disable!
    update(premium: false)
  end

  # Repeat for every setting...
end
```

**Problems**:
- Boilerplate helper methods
- No authorization
- No validation framework
- No dependency management

### After: ModelSettings

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  setting :premium, type: :column, default: false
  setting :api_access, type: :column, default: false
end

# Helper methods automatically generated!
user.premium_enable!
user.premium_disable!
user.premium_toggle!
user.api_access_enable!
# etc...
```

**Benefits**:
- ✅ No boilerplate
- ✅ Consistent API
- ✅ Authorization modules
- ✅ Cascades and syncs
- ✅ Auto-documentation

## Migrating from Hash Configurations

### Before: Serialized Hash

```ruby
class Organization < ApplicationRecord
  serialize :config, Hash

  def billing_enabled?
    config[:billing][:enabled]
  end

  def enable_billing!
    config[:billing][:enabled] = true
    save!
  end
end

# Migration
add_column :organizations, :config, :text
```

**Problems**:
- No type safety
- Manual accessor methods
- No dirty tracking
- Deep hash navigation
- No validation

### After: ModelSettings with JSON

```ruby
class Organization < ApplicationRecord
  include ModelSettings::DSL

  setting :billing, type: :json, storage: {column: :config_data} do
    setting :enabled, default: false
    setting :invoices, default: false
    setting :auto_payment, default: false
  end
end

# Clean API:
org.billing_enabled
org.billing_enabled = true
org.billing_enabled_enable!
```

**Benefits**:
- ✅ Type safety
- ✅ Clean API
- ✅ Dirty tracking
- ✅ Validation
- ✅ Nested organization

### Migration Steps

1. **Create new JSONB column** (or reuse existing):

```ruby
class ConvertConfigToJsonb < ActiveRecord::Migration[7.0]
  def change
    # Option 1: New column
    add_column :organizations, :config_data, :jsonb, default: {}, null: false

    # Option 2: Convert existing text column to jsonb
    # change_column :organizations, :config, :jsonb, using: 'config::jsonb'
  end
end
```

2. **Migrate existing data** (if needed):

```ruby
class MigrateConfigData < ActiveRecord::Migration[7.0]
  def up
    Organization.find_each do |org|
      # Convert old serialized hash to JSONB
      old_config = org.config || {}
      org.update_column(:config_data, {
        "billing" => {
          "enabled" => old_config.dig(:billing, :enabled) || false,
          "invoices" => old_config.dig(:billing, :invoices) || false
        }
      })
    end
  end
end
```

3. **Update model**:

```ruby
class Organization < ApplicationRecord
  include ModelSettings::DSL

  setting :billing, type: :json, storage: {column: :config_data} do
    setting :enabled, default: false
    setting :invoices, default: false
  end
end
```

4. **Remove old code**:

```ruby
# Remove old methods
# def billing_enabled?; end
# def enable_billing!; end

# Use new API
org.billing_enabled  # Clean!
org.billing_enabled_enable!
```

## Combining Multiple Migrations

You can migrate gradually by mixing approaches:

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  # Keep existing column settings
  setting :premium, type: :column, default: false  # Existing column

  # Migrate hash configs to JSON
  setting :preferences, type: :json, storage: {column: :prefs_data} do
    setting :theme, default: "light"
    setting :language, default: "en"
  end

  # New settings
  setting :beta_features, type: :column, default: false  # New column
end
```

## Migration Checklist

- [ ] Identify current solution (booleans, JSON, hash, feature flags)
- [ ] Add `ModelSettings::DSL` to model
- [ ] Convert settings one by one (or all at once)
- [ ] Run tests to ensure behavior unchanged
- [ ] Gradually replace old API with new helpers
- [ ] Add authorization if needed
- [ ] Add callbacks for side effects
- [ ] Generate documentation
- [ ] Remove old boilerplate code
- [ ] Celebrate! 🎉

## Getting Help

- **Questions?** Open an issue on [GitHub](https://github.com/AlexeyMatskevich/model_settings/issues)
- **Examples?** See [usage cases](../usage_cases/)
- **Need support?** Check the [complete documentation](../README.md)

## Next Steps

After migrating, explore ModelSettings features:

- [Dependencies](../core/dependencies.md) - Add cascades and syncs
- [Authorization](../modules/roles.md) - Control access with Roles module
- [Validation](../core/validation.md) - Add custom validation
- [Callbacks](../core/callbacks.md) - Hook into setting changes
- [Documentation Generator](../modules/documentation.md) - Auto-generate docs
