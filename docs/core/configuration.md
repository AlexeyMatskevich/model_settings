# Global Configuration

Configure ModelSettings behavior globally for your application.

## Configuration File

Create an initializer:

```ruby
# config/initializers/model_settings.rb
ModelSettings.configure do |config|
  # Configure options here
end
```

## Available Options

### default_modules

Configure which optional modules to auto-include when a model includes `ModelSettings::DSL`.

```ruby
ModelSettings.configure do |config|
  config.default_modules = [:roles, :i18n]  # Default: []
end
```

Available built-in modules:
- `:roles` - Role-based authorization
- `:pundit` - Pundit integration
- `:action_policy` - ActionPolicy integration
- `:i18n` - Internationalization (auto-included for backward compatibility)

**Note**: Authorization modules (`:roles`, `:pundit`, `:action_policy`) are mutually exclusive - you can only use one per model.

**Example with auto-include**:

```ruby
# config/initializers/model_settings.rb
ModelSettings.configure do |config|
  config.default_modules = [:roles, :i18n]
end

# app/models/user.rb
class User < ApplicationRecord
  include ModelSettings::DSL  # Automatically includes Roles and I18n modules

  setting :premium_mode,
    viewable_by: :all,      # From Roles module
    editable_by: :admin     # From Roles module
end
```

**Without auto-include** (manual approach):

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL
  include ModelSettings::Modules::Roles  # Manual include
  include ModelSettings::Modules::I18n   # Manual include

  setting :premium_mode,
    viewable_by: :all,
    editable_by: :admin
end
```

### inherit_settings

Control whether child classes inherit parent settings.

```ruby
ModelSettings.configure do |config|
  config.inherit_settings = true  # Default: true
end
```

**When to disable**: If you have STI models but don't want automatic inheritance.

### inherit_authorization

Control authorization inheritance (when using auth modules).

```ruby
ModelSettings.configure do |config|
  config.inherit_authorization = true  # Default: true
end
```

Used by Roles, Pundit, and ActionPolicy modules for inheriting `viewable_by`, `editable_by`, and `authorize_with` options.

### module_callback

Configure when a module's logic runs in the Rails lifecycle (Sprint 11 Phase 3).

```ruby
ModelSettings.configure do |config|
  # Change when Pundit module runs
  config.module_callback(:pundit, :before_save)
end
```

**Parameters:**
- `module_name` (Symbol) - Module identifier (e.g., `:pundit`, `:roles`)
- `callback_name` (Symbol) - Rails callback (e.g., `:before_validation`, `:before_save`, `:after_commit`)

**Default Callbacks** (per module):
- Most authorization modules default to `:before_validation`
- Check module documentation for specifics

**When to change:**
- Performance optimization (run validation later in lifecycle)
- Integration requirements (coordinate with other gems)
- Testing strategies (control callback timing)

**Example - Multiple Modules:**
```ruby
ModelSettings.configure do |config|
  # Authorization runs before validation (default for most)
  config.module_callback(:pundit, :before_validation)

  # Audit logging runs after commit (recommended)
  config.module_callback(:audit_trail, :after_commit)
end
```

**Restrictions:**
- Only works if module registered with `configurable: true`
- Some modules may not allow configuration for correctness reasons
- Raises `ArgumentError` if attempting to configure non-configurable module

**Example - Non-Configurable Module:**
```ruby
# Module registered with configurable: false
ModelSettings.configure do |config|
  config.module_callback(:strict_module, :before_save)
end

# Later, when module is loaded:
# => ArgumentError: Module :strict_module does not allow callback configuration
#    (configurable: false in registration)
```

**See Also:** [Module Development API](../guides/module_development.md#callback-configuration) for module developers

## Per-Model Configuration

Override global config per model:

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  # This model doesn't inherit settings even if globally enabled
  self.inherit_settings = false

  setting :premium, type: :column
end
```

## Environment-Specific Configuration

```ruby
ModelSettings.configure do |config|
  if Rails.env.production?
    config.inherit_authorization = true
  else
    config.inherit_authorization = false  # More permissive in dev
  end
end
```

## Accessing Configuration

```ruby
# Check current configuration
ModelSettings.configuration.inherit_settings  # => true

# Check per-model
User.inherit_settings  # => true
```

## Related Documentation

- [Settings Inheritance](inheritance.md) - How `inherit_settings` works
- [Roles Module](../modules/roles.md) - Uses `inherit_authorization`
- [Pundit Module](../modules/pundit.md) - Uses `inherit_authorization`
- [ActionPolicy Module](../modules/action_policy.md) - Uses `inherit_authorization`

## Summary

| Option | Default | Purpose |
|--------|---------|---------|
| `default_modules` | `[]` | Auto-include optional modules when including DSL |
| `inherit_settings` | `true` | Child classes inherit parent settings |
| `inherit_authorization` | `true` | Child settings inherit parent auth rules |
| `module_callback(name, callback)` | Per-module | Configure when module's logic runs in Rails lifecycle |
