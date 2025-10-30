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

See [Roles](../modules/roles.md), [Pundit](../modules/pundit.md), [ActionPolicy](../modules/action_policy.md).

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
