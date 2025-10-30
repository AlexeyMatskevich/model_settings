# Settings Inheritance

ModelSettings supports automatic settings inheritance across model hierarchies. Child classes automatically inherit all settings from their parent classes.

## Enabling Inheritance

Settings inheritance is **enabled by default**. Configure globally:

```ruby
# config/initializers/model_settings.rb
ModelSettings.configure do |config|
  config.inherit_settings = true  # Default: true
end
```

## Basic Inheritance

Child classes automatically inherit all parent settings:

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  setting :notifications_enabled, type: :column, default: true
  setting :api_access, type: :column, default: false
end

class PremiumUser < User
  # Automatically inherits:
  # - notifications_enabled
  # - api_access
end

premium = PremiumUser.create!
premium.notifications_enabled  # => true (inherited default)
premium.notifications_enabled = false
premium.save!
```

## Overriding Inherited Settings

Child classes can override parent settings:

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  setting :notifications_enabled,
          type: :column,
          description: "Enable notifications",
          default: true

  setting :api_access, type: :column, default: false
end

class PremiumUser < User
  # Override with different default
  setting :notifications_enabled, default: false

  # Override with additional metadata
  setting :api_access,
          default: true,
          description: "Premium API access with higher limits"
end

premium = PremiumUser.create!
premium.notifications_enabled  # => false (overridden default)

# Parent class unaffected
user = User.create!
user.notifications_enabled  # => true (original default)
```

## Adding New Settings

Child classes can add their own settings:

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  setting :base_feature, type: :column, default: true
end

class PremiumUser < User
  # Add premium-specific settings
  setting :advanced_analytics, type: :column, default: false
  setting :priority_support, type: :column, default: true
end

premium = PremiumUser.create!
premium.base_feature          # => true (inherited)
premium.advanced_analytics    # => false (new)
premium.priority_support      # => true (new)
```

## Multi-Level Inheritance

Settings inheritance works across multiple levels:

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL
  setting :level_1, type: :column, default: "base"
end

class PremiumUser < User
  setting :level_2, type: :column, default: "premium"
end

class EnterpriseUser < PremiumUser
  setting :level_3, type: :column, default: "enterprise"
end

enterprise = EnterpriseUser.create!
enterprise.level_1  # => "base" (from grandparent)
enterprise.level_2  # => "premium" (from parent)
enterprise.level_3  # => "enterprise" (own setting)
```

## Storage Type Support

Inheritance works with all storage types:

### Column Settings
```ruby
class User < ApplicationRecord
  include ModelSettings::DSL
  setting :enabled, type: :column, default: true
end

class PremiumUser < User
  # Inherits column setting with full adapter support
end

premium = PremiumUser.create!
premium.enabled_disable!  # Helper methods work
```

### JSON Settings
```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  setting :preferences,
          type: :json,
          storage: {column: :settings_data} do
    setting :theme, default: "dark"
  end
end

class PremiumUser < User
  # Inherits JSON parent and nested settings
end

premium = PremiumUser.create!
premium.theme = "light"
premium.save!
```

## Disabling Inheritance

Disable inheritance globally:

```ruby
ModelSettings.configuration.inherit_settings = false

class Parent < ApplicationRecord
  include ModelSettings::DSL
  setting :parent_setting, type: :column, default: true
end

class Child < Parent
  # Does NOT inherit parent_setting
  setting :child_setting, type: :column, default: false
end

Child._settings.map(&:name)  # => [:child_setting]
```

## Important Considerations

1. **Adapter Creation**: Each child class gets its own adapters for inherited settings
2. **Setting Metadata**: All metadata (descriptions, defaults, validations, cascades) is inherited
3. **Children Preservation**: Nested setting hierarchies are fully preserved
4. **Override Merging**: When overriding, options are merged - you only specify what changes

## Complete Example

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  setting :notifications_enabled,
          type: :column,
          description: "Email notifications",
          default: true

  setting :features,
          type: :json,
          storage: {column: :features_data} do
    setting :basic_analytics, default: true
  end
end

class PremiumUser < User
  # Override notification default
  setting :notifications_enabled, default: false

  # Add premium-specific features
  setting :features do
    setting :advanced_analytics, default: true
    setting :custom_reports, default: false
  end
end

class EnterpriseUser < PremiumUser
  # Add enterprise features
  setting :features do
    setting :api_access, default: true
    setting :white_label, default: true
  end

  # Override premium default
  setting :custom_reports, default: true
end

# Usage
enterprise = EnterpriseUser.create!
enterprise.notifications_enabled  # => false (from PremiumUser)
enterprise.basic_analytics        # => true (from User)
enterprise.advanced_analytics     # => true (from PremiumUser)
enterprise.custom_reports         # => true (overridden in EnterpriseUser)
enterprise.api_access             # => true (from EnterpriseUser)
enterprise.white_label            # => true (from EnterpriseUser)
```

## Related Documentation

- [Storage Adapters](adapters.md) - All adapters support inheritance
- [Dependencies](dependencies.md) - Cascades/syncs are inherited
- [Validation](validation.md) - Validators are inherited
- [Callbacks](callbacks.md) - Callbacks are inherited

## Summary

**Key Points**:
- Inheritance is enabled by default
- Child classes get all parent settings
- Override by redefining with same name
- Add new settings in child classes
- Works with all storage types
- Multi-level inheritance supported
- Metadata and options are inherited
