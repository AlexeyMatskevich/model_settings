# ModelSettings

Declarative configuration management DSL for Rails models with support for multiple storage backends, authorization, validation, and extensible module integration.

## Features

- **Multiple Storage Backends**: Column, JSON/JSONB support
- **Flexible DSL**: Clean, declarative syntax for defining settings
- **Validation Framework**: Custom validators with lifecycle hooks
- **Callback System**: Before/after callbacks for state changes
- **Dirty Tracking**: Full change tracking across all storage types
- **Query Interface**: Powerful methods for finding settings by metadata
- **Deprecation Tracking**: Built-in deprecation warnings and audit trails
- **I18n Support**: Full internationalization for labels and descriptions
- **Module System**: Extensible architecture for custom modules

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'model_settings'
```

And then execute:

```bash
bundle install
```

## Quick Start

### Basic Column Storage

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  # Simple boolean setting stored in a database column
  setting :notifications_enabled, type: :column, default: true
end

# Usage
user = User.create!
user.notifications_enabled # => true
user.notifications_enabled = false
user.save!

# Helper methods
user.notifications_enabled_enable!   # Set to true
user.notifications_enabled_disable!  # Set to false
user.notifications_enabled_toggle!   # Toggle value
user.notifications_enabled_enabled?  # => false
user.notifications_enabled_disabled? # => true

# Dirty tracking
user.notifications_enabled = true
user.notifications_enabled_changed? # => true
user.notifications_enabled_was      # => false
user.notifications_enabled_change   # => [false, true]
```

### JSON Storage

Store multiple settings in a single JSONB column:

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  # Multiple settings in one JSON column
  setting :features, type: :json, storage: {column: :settings} do
    setting :billing_enabled, default: false
    setting :speech_recognition, default: false
    setting :api_access, default: false
  end
end

# Usage
user = User.create!
user.billing_enabled = true
user.speech_recognition = true
user.save!

# All helper methods work with JSON storage too
user.billing_enabled_enable!
user.api_access_toggle!
```

### Migration Example

```ruby
class AddSettingsToUsers < ActiveRecord::Migration[7.0]
  def change
    # For column storage
    add_column :users, :notifications_enabled, :boolean, default: false, null: false
    add_column :users, :premium_mode, :boolean, default: false, null: false

    # For JSON storage
    add_column :users, :settings, :jsonb, default: {}, null: false
    add_index :users, :settings, using: :gin
  end
end
```

## Advanced Features

### Validation

Add custom validators to settings:

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  setting :premium_mode,
          type: :column,
          validate_with: :check_subscription_active

  setting :api_access,
          type: :column,
          validate_with: [:check_api_quota, :check_api_permissions]

  private

  def check_subscription_active
    unless subscription_active?
      add_setting_error(:premium_mode, "requires active subscription")
    end
  end

  def check_api_quota
    if api_calls_this_month >= api_quota
      add_setting_error(:api_access, "API quota exceeded")
    end
  end
end

# Usage
user = User.new
user.validate_setting(:premium_mode) # => false
user.setting_errors_for(:premium_mode) # => ["Premium mode requires active subscription"]
```

### Callbacks

Execute code before/after setting changes:

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  setting :premium_mode,
          type: :column,
          before_enable: :prepare_premium_features,
          after_enable: :notify_premium_activation,
          after_disable: :cleanup_premium_features,
          after_change_commit: :sync_to_external_service

  private

  def prepare_premium_features
    # Run before enabling premium mode
    logger.info "Preparing premium features..."
  end

  def notify_premium_activation
    # Run after enabling premium mode
    PremiumActivationMailer.notify(self).deliver_later
  end

  def cleanup_premium_features
    # Run after disabling premium mode
    PremiumFeature.cleanup_for_user(self)
  end

  def sync_to_external_service
    # Run after database commit
    ExternalApiJob.perform_later(self.id)
  end
end

# Usage
user.premium_mode_enable!
# => Executes: prepare_premium_features → set value → notify_premium_activation
# => After commit: sync_to_external_service
```

### Metadata and Queries

Add metadata to settings for organization and querying:

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  setting :billing_enabled,
          type: :json,
          storage: {column: :settings},
          metadata: {
            category: "billing",
            tier: "premium",
            requires_verification: true
          }

  setting :api_access,
          type: :json,
          storage: {column: :settings},
          metadata: {
            category: "api",
            tier: "enterprise",
            rate_limit: 1000
          }
end

# Query by metadata
User.settings_where(metadata: {category: "billing"})
User.settings_where(metadata: {tier: "premium"})

# Query by metadata key
User.settings_with_metadata_key(:rate_limit)

# Query by type
User.settings_by_type(:json)

# Query with callbacks
User.settings_with_callbacks(:after_enable)

# Group by metadata
User.settings_grouped_by_metadata(:category)
# => {"billing" => [...], "api" => [...]}

# Custom queries
User.settings_matching { |s| s.name.to_s.include?("api") }

# Count settings
User.settings_count(type: :json)
User.settings_count(metadata: {tier: "premium"})
```

### Deprecation Tracking

Mark settings as deprecated with automatic warnings:

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  setting :old_notification_system,
          type: :column,
          deprecated: "Use notifications_enabled instead",
          metadata: {
            deprecated_since: "2.0.0",
            replacement: :notifications_enabled
          }

  setting :notifications_enabled,
          type: :column,
          default: true
end

# Get deprecated settings
User.deprecated_settings

# Check if setting is deprecated
User.setting_deprecated?(:old_notification_system) # => true
User.deprecation_reason_for(:old_notification_system)
# => "Use notifications_enabled instead"

# Generate deprecation report
User.deprecation_report
# => {
#      total_count: 1,
#      settings: [{name: :old_notification_system, reason: "...", since: "2.0.0"}],
#      by_version: {"2.0.0" => [...]}
#    }

# Automatic warnings when deprecated settings are used
user = User.create!(old_notification_system: true)
# => DEPRECATION WARNING: Setting 'old_notification_system' is deprecated since version 2.0.0.
#    Use notifications_enabled instead. Please use 'notifications_enabled' instead.
```

### Internationalization

Support for I18n with automatic key lookup:

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  setting :notifications_enabled,
          type: :column,
          i18n: {
            label_key: "settings.notifications.label",
            description_key: "settings.notifications.description"
          }
end

# In config/locales/en.yml:
# en:
#   model_settings:
#     user:
#       notifications_enabled:
#         label: "Enable Notifications"
#         description: "Receive email notifications for important updates"
#         help: "You can change this setting at any time"

# Usage
user = User.new
user.t_label_for(:notifications_enabled)       # => "Enable Notifications"
user.t_description_for(:notifications_enabled) # => "Receive email notifications..."
user.t_help_for(:notifications_enabled)        # => "You can change this setting..."

# Get all translations at once
user.translations_for(:notifications_enabled)
# => {label: "...", description: "...", help: "..."}
```

## Global Configuration

Configure default behavior globally:

```ruby
# config/initializers/model_settings.rb
ModelSettings.configure do |config|
  # Default modules to include (if implementing custom modules)
  config.default_modules = [:i18n]

  # Authorization inheritance (if using authorization modules)
  config.inherit_authorization = true
end
```

## Module Extension System

Create custom modules to extend functionality:

```ruby
module MyCustomModule
  extend ActiveSupport::Concern

  included do
    # Register your module
    ModelSettings::ModuleRegistry.register_module(:my_module, self)
  end

  module ClassMethods
    def custom_setting_behavior
      # Your custom class methods
    end
  end

  # Your custom instance methods
  def custom_instance_behavior
    # ...
  end
end

# Use in your models
class User < ApplicationRecord
  include ModelSettings::DSL
  include MyCustomModule

  # Your settings...
end

# Register hooks
ModelSettings::ModuleRegistry.on_settings_compiled do |settings|
  # Called when settings are compiled
  puts "Compiled #{settings.size} settings"
end

ModelSettings::ModuleRegistry.before_setting_change do |instance, setting, new_value|
  # Called before any setting changes
  AuditLog.create(user: instance, setting: setting.name, new_value: new_value)
end
```

## Setting Hierarchy

Settings can be nested for better organization:

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  setting :features, type: :json, storage: {column: :settings} do
    setting :billing, description: "Billing features" do
      setting :invoices_enabled, default: false
      setting :auto_payment, default: false
    end

    setting :communication, description: "Communication features" do
      setting :email_enabled, default: true
      setting :sms_enabled, default: false
    end
  end
end

# Navigate hierarchy
features_setting = User.find_setting(:features)
features_setting.children # => [billing, communication]

billing_setting = User.find_setting([:features, :billing])
billing_setting.parent # => features setting
billing_setting.root   # => features setting
billing_setting.path   # => [:features, :billing]

# Query hierarchy
User.root_settings      # => Only top-level settings
User.leaf_settings      # => Only settings without children
User.all_settings_recursive # => All settings including nested
```

## Best Practices

### 1. Choose the Right Storage Type

- **Column storage**: Best for frequently queried boolean flags
- **JSON storage**: Best for related settings that are read/written together

### 2. Use Metadata for Organization

```ruby
setting :feature_name,
        metadata: {
          category: "features",
          tier: "premium",
          documented_at: "https://docs.example.com/feature"
        }
```

### 3. Add Descriptions

```ruby
setting :api_access,
        description: "Enables API access for third-party integrations",
        default: false
```

### 4. Use Callbacks for Side Effects

Instead of manually triggering side effects, use callbacks:

```ruby
# Good
setting :premium_mode,
        after_enable: :setup_premium_features

# Less ideal
user.premium_mode = true
user.save!
user.setup_premium_features # Easy to forget!
```

### 5. Deprecate Gracefully

When replacing settings, use deprecation:

```ruby
setting :old_setting,
        deprecated: "Use new_setting instead",
        metadata: {deprecated_since: "2.0.0", replacement: :new_setting}
```

## Testing

```ruby
RSpec.describe User do
  describe "settings" do
    it "enables notifications by default" do
      user = User.create!
      expect(user.notifications_enabled).to be true
    end

    it "tracks changes" do
      user = User.create!(notifications_enabled: true)
      user.notifications_enabled = false

      expect(user.notifications_enabled_changed?).to be true
      expect(user.notifications_enabled_was).to be true
    end

    it "calls callbacks on enable" do
      user = User.create!
      expect(user).to receive(:notify_activation)

      user.premium_mode_enable!
    end
  end
end
```

## Performance Considerations

1. **N+1 Prevention**: Settings are defined at class level and don't cause N+1 queries
2. **JSON Indexing**: Add GIN indexes for JSONB columns in PostgreSQL
3. **Eager Loading**: Settings metadata is cached per model class
4. **Dirty Tracking**: Uses ActiveRecord's built-in dirty tracking

## Roadmap

- [ ] StoreModel adapter for complex nested settings
- [ ] Pundit/ActionPolicy integration for authorization
- [ ] Plans module for subscription tier management
- [ ] Roles module for role-based access control
- [ ] Sync mechanism with cycle detection
- [ ] Documentation generator rake tasks
- [ ] Settings inheritance across models

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/model_settings.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
