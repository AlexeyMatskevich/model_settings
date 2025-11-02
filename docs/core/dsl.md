# DSL Reference

Complete reference for ModelSettings DSL and setting options.

## Basic Setting Definition

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  setting :name, **options, &block
end
```

## Setting Options

### type (required)

Storage adapter type:

```ruby
setting :premium, type: :column          # Column storage
setting :prefs, type: :json              # JSON storage
setting :ai, type: :store_model          # StoreModel storage
```

### default

Default value when setting is nil:

```ruby
setting :enabled, type: :column, default: false
setting :count, type: :column, default: 0
setting :tags, type: :json, array: true, default: []
```

### storage

Specify storage location (required for JSON and StoreModel):

```ruby
setting :prefs, type: :json, storage: {column: :preferences_data}
setting :ai, type: :store_model, storage: {column: :ai_settings}
```

### array

For JSON array storage:

```ruby
setting :tags,
        type: :json,
        storage: {column: :metadata},
        array: true,
        default: []
```

### description

Human-readable description (used in documentation generation):

```ruby
setting :api_access,
        type: :column,
        description: "Enables API access for third-party integrations"
```

### deprecated

Mark setting as deprecated:

```ruby
setting :old_feature,
        type: :column,
        deprecated: "Use :new_feature instead"
```

### metadata

Custom metadata for querying/organization:

```ruby
setting :billing,
        type: :column,
        metadata: {
          category: "billing",
          tier: "premium",
          requires_verification: true
        }
```

## Callback Options

```ruby
setting :premium,
        before_enable: :prepare,
        after_enable: :notify,
        before_disable: :check,
        after_disable: :cleanup,
        before_change: :log,
        after_change: :sync,
        after_change_commit: :queue_job
```

See [Callbacks](callbacks.md) for details.

## Validation Options

```ruby
setting :api_access,
        type: :column,
        validate_with: [:check_quota, :check_permissions]
```

See [Validation](validation.md) for details.

## Dependency Options

### cascade

```ruby
setting :premium, cascade: {enable: true, disable: true} do
  setting :feature_a
  setting :feature_b
end
```

### sync

```ruby
setting :marketing,
        sync: {target: :newsletter, mode: :forward}

setting :do_not_track,
        sync: {target: :analytics, mode: :inverse}
```

See [Dependencies](dependencies.md) for details.

## Authorization Options

### With Roles Module

```ruby
include ModelSettings::Modules::Roles

setting :billing,
        viewable_by: [:admin, :finance],
        editable_by: [:admin]
```

### With Pundit/ActionPolicy

```ruby
include ModelSettings::Modules::Pundit

setting :billing, authorize_with: :manage_billing?
```

See [Roles](../modules/roles.md), [Pundit](../modules/policy_based/pundit.md), [ActionPolicy](../modules/policy_based/action_policy.md), or [Policy-Based Authorization Overview](../modules/policy_based/README.md).

## I18n Options

```ruby
include ModelSettings::Modules::I18n

setting :notifications,
        i18n: {
          label_key: "settings.notifications.label",
          description_key: "settings.notifications.description"
        }
```

See [I18n Module](../modules/i18n.md).

## Nested Settings

```ruby
setting :features, type: :json, storage: {column: :data} do
  setting :analytics, default: false do
    setting :basic, default: true
    setting :advanced, default: false
  end
end
```

**Important**: Nested settings are compiled in waves by depth level. See [Settings Compilation](#settings-compilation) below for details.

## Settings Compilation

ModelSettings uses **wave-based compilation** to process settings by nesting level (depth), ensuring parent settings are fully set up before their children are processed.

### Why Wave-Based Compilation?

Wave-based compilation enables:
- **Proper inheritance**: Child settings can access parent configuration during validation
- **Dependency resolution**: Parent adapters are set up before children need them
- **Authorization inheritance**: Children can inherit authorization from parents (Phase 4)
- **Predictable order**: Settings are always processed in a deterministic order

### How It Works

Settings are grouped by depth and processed in waves:

```ruby
setting :billing do              # Level 0 (Wave 0)
  setting :invoices do           # Level 1 (Wave 1)
    setting :tax_reports         # Level 2 (Wave 2)
  end
  setting :payments              # Level 1 (Wave 1)
end
setting :api_access              # Level 0 (Wave 0)

# Compilation order:
# Wave 0: :billing, :api_access     (in definition order)
# Wave 1: :invoices, :payments      (in definition order)
# Wave 2: :tax_reports              (in definition order)
```

**Within each wave**, settings are processed in definition order, ensuring predictable behavior.

### When Compilation Happens

Compilation is **lazy** and **idempotent**:
- Triggered automatically on first access (`User.settings`, `User.find_setting(:name)`)
- Triggered automatically when creating an instance (`User.new`)
- Can be manually triggered with `User.compile_settings!`
- Safe to call multiple times (subsequent calls are no-ops)

### Implementation Details

During compilation, for each wave:
1. Settings at the current depth level are identified
2. For each setting in definition order:
   - Storage adapter is set up (`adapter.setup!`)
   - Helper methods are defined (`enable!`, `disable!`, etc.)
   - Validations are registered
3. After all waves complete:
   - Compilation hooks are executed
   - Dependency engine is compiled

### Storage Configuration Validation

Storage configuration (`:type`, `:storage` options) is validated **early** during setting definition, not during compilation. This ensures configuration errors are caught immediately when the class is loaded.

```ruby
# This raises ArgumentError immediately, not during compilation:
setting :invalid, type: :json  # Missing required :storage option
```

### Example: Parent-Child Access

Wave-based compilation enables children to access parent settings:

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  setting :billing, type: :column, default: false do
    setting :invoices,
            type: :column,
            validate_with: -> {
              # Parent setting is already compiled and accessible
              errors.add(:invoices, "requires billing") unless billing?
            }
  end
end
```

### Testing

Wave compilation behavior is tested in `spec/model_settings/wave_compilation_spec.rb`:
- Compilation order by depth
- Settings processed in definition order
- Adapter setup timing
- Dependency engine integration

## Module Extension System

Create custom modules to extend functionality:

```ruby
module MyCustomModule
  extend ActiveSupport::Concern

  included do
    ModelSettings::ModuleRegistry.register_module(:my_module, self)
  end

  module ClassMethods
    def custom_behavior
      # Your code
    end
  end
end

# Use in models
class User < ApplicationRecord
  include ModelSettings::DSL
  include MyCustomModule

  # Your settings
end
```

## Setting Hierarchy Navigation

```ruby
# Get setting object
setting = User.find_setting(:billing)

# Navigate
setting.children    # Child settings
setting.parent      # Parent setting
setting.root        # Root parent
setting.path        # [:parent, :child]
setting.leaf?       # Has no children?

# Access options
setting.name        # => :billing
setting.type        # => :column
setting.default     # => false
setting.options     # => {type: :column, default: false, ...}
```

## Related Documentation

- [Settings Compilation](#settings-compilation) - Wave-based compilation for nested settings
- [Storage Adapters](adapters.md) - `type` and `storage` options
- [Callbacks](callbacks.md) - Callback options
- [Validation](validation.md) - `validate_with` option
- [Dependencies](dependencies.md) - `cascade` and `sync` options
- [Authorization Modules](../modules/roles.md) - Authorization options

## Summary

**Required Options**:
- `type` - Always required

**Storage-Specific**:
- `storage` - Required for JSON and StoreModel
- `array` - Optional for JSON arrays

**Common Options**:
- `default` - Default value
- `description` - Human-readable description
- `metadata` - Custom metadata
- `deprecated` - Deprecation message

**Behavior**:
- Callbacks - `before_*`, `after_*`
- Validation - `validate_with`
- Dependencies - `cascade`, `sync`
- Authorization - `viewable_by`, `editable_by`, `authorize_with`
