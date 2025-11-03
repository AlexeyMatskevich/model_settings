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

## Option Inheritance in Nested Settings

In addition to class inheritance, ModelSettings supports **option inheritance** where nested settings automatically inherit options from their parent settings.

### How It Works

When you define nested settings, child settings can automatically inherit specific options from their parent. This is particularly useful for authorization options like `viewable_by`, `editable_by`, and `authorize_with`.

**Configuration**: Which options are inherited is controlled by [`inheritable_options`](configuration.md#inheritable_options) setting.

### Basic Example

```ruby
class Organization < ApplicationRecord
  include ModelSettings::DSL
  include ModelSettings::Modules::Roles

  setting :billing, viewable_by: [:admin, :finance] do
    setting :invoices   # Automatically inherits viewable_by: [:admin, :finance]
    setting :reports    # Automatically inherits viewable_by: [:admin, :finance]
  end
end

# Usage
org = Organization.create!
org.can_view_setting?(:invoices, :finance)  # => true (inherited from :billing)
```

### Multi-Level Option Inheritance

Options inherit through multiple levels of nesting:

```ruby
class Organization < ApplicationRecord
  include ModelSettings::DSL
  include ModelSettings::Modules::Roles

  setting :billing,
    viewable_by: [:admin, :finance],
    editable_by: [:admin] do

    setting :invoices do
      # Inherits both: viewable_by: [:admin, :finance], editable_by: [:admin]

      setting :tax_reports
      # Also inherits from parent: viewable_by: [:admin, :finance], editable_by: [:admin]
    end
  end
end
```

### Overriding Inherited Options

Child settings can override inherited options:

```ruby
class Organization < ApplicationRecord
  include ModelSettings::DSL
  include ModelSettings::Modules::Roles

  setting :billing,
    viewable_by: [:admin, :finance],
    editable_by: [:admin] do

    setting :invoices do
      # Inherits both options
    end

    setting :payments, editable_by: [:finance] do
      # Overrides editable_by, keeps viewable_by: [:admin, :finance]
    end

    setting :tax_reports, viewable_by: [:admin] do
      # Overrides viewable_by, keeps editable_by: [:admin]
    end
  end
end
```

### Which Options Are Inherited?

By default, modules register their authorization options as inheritable:
- **Roles module**: `:viewable_by`, `:editable_by`
- **Pundit module**: `:authorize_with`
- **ActionPolicy module**: `:authorize_with`

You can configure which options are inherited globally or per-model. See [Configuration - inheritable_options](configuration.md#inheritable_options) for details.

### Disabling Option Inheritance

To prevent a nested setting from inheriting options, explicitly set them to `nil` or a different value:

```ruby
setting :billing, viewable_by: [:admin] do
  setting :public_invoices, viewable_by: :all  # Override with :all
  setting :internal_reports, viewable_by: nil  # Explicitly no restriction
end
```

### Complete Example

```ruby
class Organization < ApplicationRecord
  include ModelSettings::DSL
  include ModelSettings::Modules::Roles

  # Root setting with authorization
  setting :billing,
    viewable_by: [:admin, :finance, :manager],
    editable_by: [:admin, :finance] do

    # Level 1: Inherits both options
    setting :invoices do
      setting :summary  # Level 2: Also inherits both options
    end

    # Level 1: Overrides editable_by only
    setting :payments, editable_by: [:admin] do
      setting :history  # Level 2: Inherits overridden editable_by
    end

    # Level 1: Override viewable_by only
    setting :reports, viewable_by: [:admin, :finance] do
      # Manager can't view reports, but keeps editable_by: [:admin, :finance]
    end
  end
end

# Usage
org = Organization.create!

# Invoices: inherited from billing
org.can_view_setting?(:invoices, :manager)   # => true
org.can_edit_setting?(:invoices, :finance)   # => true

# Payments: overridden editable_by
org.can_view_setting?(:payments, :manager)   # => true (inherited)
org.can_edit_setting?(:payments, :finance)   # => false (overridden)

# Reports: overridden viewable_by
org.can_view_setting?(:reports, :manager)    # => false (overridden)
org.can_edit_setting?(:reports, :finance)    # => true (inherited)
```

### Important Notes

1. **Option inheritance is separate from class inheritance** - these are two different mechanisms
2. **Only configured options are inherited** - see `inheritable_options` configuration
3. **Inheritance happens at definition time** - options are copied when settings are defined
4. **Explicit always wins** - explicitly set options always override inherited ones

### See Also

- [Configuration - inheritable_options](configuration.md#inheritable_options) - Configure which options are inherited
- [Roles Module](../modules/roles.md) - Uses option inheritance for authorization
- [Pundit Module](../modules/policy_based/pundit.md) - Uses option inheritance for policies

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

**Class Inheritance** (parent class → child class):
- Inheritance is enabled by default
- Child classes get all parent settings
- Override by redefining with same name
- Add new settings in child classes
- Works with all storage types
- Multi-level inheritance supported
- Metadata and options are inherited

**Option Inheritance** (parent setting → nested setting):
- Nested settings inherit options from parent settings
- Controlled by `inheritable_options` configuration
- Modules auto-register their options (viewable_by, editable_by, authorize_with)
- Override by explicitly setting different value
- Multi-level inheritance through deep nesting
- Separate mechanism from class inheritance
