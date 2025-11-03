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

### inheritable_options

Configure which setting options should be automatically inherited by nested settings (Sprint 11 Phase 4).

```ruby
ModelSettings.configure do |config|
  # Explicitly set which options are inherited
  config.inheritable_options = [:authorize_with, :viewable_by, :custom_metadata]
end
```

**How It Works:**

Inheritable options are automatically copied from parent settings to child settings unless explicitly overridden. This provides three levels of configuration:

1. **Global Configuration** - Set via `config.inheritable_options` (highest priority when explicit)
2. **Module Registration** - Modules auto-register their options (via `register_inheritable_option`)
3. **Model-Specific** - Override per-model via `settings_config` (highest priority)

**Automatic Registration:**

Built-in modules automatically register their options as inheritable:
- `Roles` module: `:viewable_by`, `:editable_by`
- `Pundit` module: `:authorize_with`
- `ActionPolicy` module: `:authorize_with`

**Global Configuration - Two Approaches:**

```ruby
# Approach 1: Auto-population (recommended for most cases)
ModelSettings.configure do |config|
  # Don't set inheritable_options explicitly
  # Modules will auto-register their options as they're loaded
end
# Result: [:authorize_with, :viewable_by, :editable_by] + any custom module options

# Approach 2: Explicit control (COMPLETE override)
ModelSettings.configure do |config|
  config.inheritable_options = [:authorize_with, :custom_option]
  # ⚠️ WARNING: This COMPLETELY REPLACES the auto-populated list!
  # Modules CANNOT add their options when this is explicitly set.
end
# Result: Only [:authorize_with, :custom_option]
# Module-registered options (viewable_by, editable_by, etc.) are IGNORED
```

**Adding Custom Inheritable Options:**

```ruby
ModelSettings.configure do |config|
  # Add without explicit set (allows modules to continue registering)
  config.add_inheritable_option(:audit_user)
  config.add_inheritable_option(:feature_flag)
end
```

**Per-Model Override:**

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  # This model only inherits authorization options
  settings_config inheritable_options: [:viewable_by, :editable_by]
end
```

**Checking Configuration:**

```ruby
# Global level
ModelSettings.configuration.inheritable_options
# => [:authorize_with, :viewable_by, :editable_by]

ModelSettings.configuration.inheritable_options_explicitly_set?
# => false (if using auto-population)

# Model level
User.inheritable_options
# => [:viewable_by, :editable_by, :custom_option]
```

**When to Use Each Approach:**

| Approach | Use Case |
|----------|----------|
| **Auto-population** (don't set explicitly) | You want modules to automatically register their options. Recommended for most applications. |
| **Explicit global list** (`inheritable_options = [...]`) | You need strict control over exactly which options are inherited across all models. |
| **Per-model override** (`settings_config inheritable_options: [...]`) | Different models need different inheritance behavior. |
| **Add to auto-populated** (`add_inheritable_option`) | You have custom options to add but want modules to keep working. |

**Important Notes:**

- ⚠️ **Setting `inheritable_options` explicitly COMPLETELY REPLACES the list** - modules cannot add their options
- Use `add_inheritable_option` if you want to add custom options while preserving module auto-registration
- Per-model configuration always takes precedence over global configuration
- Check `inheritable_options_explicitly_set?` to see if explicit control is active
- Explicit setting at any level (global or per-model) disables auto-population at that level

**See Also:**
- [Module Development - Registering Inheritable Options](../guides/module_development.md#registering-inheritable-options)
- [Option Inheritance in Nested Settings](inheritance.md#option-inheritance-in-nested-settings) - How options are inherited by child settings

### module_callback

Configure when a module's logic runs in the Rails lifecycle (Sprint 11 Phase 3).

**Important**: This option is only relevant for modules with **runtime logic** that execute during model lifecycle events (save, validation, commit). Most built-in modules (Roles, Pundit, ActionPolicy, I18n) work at compile-time only and do NOT use callbacks.

```ruby
ModelSettings.configure do |config|
  # Configure runtime modules
  config.module_callback(:simple_audit, :after_commit)
  config.module_callback(:workflow, :before_save)
end
```

**Parameters:**
- `module_name` (Symbol) - Module identifier (e.g., `:simple_audit`, `:workflow`)
- `callback_name` (Symbol) - Rails callback (e.g., `:before_validation`, `:before_save`, `:after_commit`)

**Which Modules Use This?**

✅ **Module types that benefit from callback configuration** (runtime logic):
- Audit logging modules - Log changes during save/commit
- Workflow modules - State machine transitions
- Notification modules - Send alerts after changes
- Custom modules that need to run code when settings change

**Example**: `SimpleAudit` module (included as demonstration)

❌ **Built-in modules that DON'T use this** (compile-time only):
- `Roles` - Only stores metadata at definition time
- `Pundit` - Only stores authorization rules at definition time
- `ActionPolicy` - Only stores policy references at definition time
- `I18n` - Only stores translation keys at definition time

**Why the distinction?**

Authorization modules (Roles, Pundit, ActionPolicy) only intercept the `setting()` DSL method to capture metadata. The actual authorization happens in the **controller**, not the model.

**Example - Pundit:**
```ruby
class UsersController < ApplicationController
  def update
    @user = User.find(params[:id])
    authorize @user
    @user.update(permitted_attributes(@user))  # Standard Pundit
  end
end
```

**Example - ActionPolicy:**
```ruby
class UsersController < ApplicationController
  def update
    @user = User.find(params[:id])
    authorize! @user
    filtered_params = authorized(params.require(:user))  # Standard ActionPolicy
    @user.update(filtered_params)
  end
end
```

Runtime modules like SimpleAudit need to execute code when the model saves, so they benefit from configurable callback timing.

**See Also:** [Policy-Based Authorization](../modules/policy_based/README.md), [Pundit Module](../modules/policy_based/pundit.md), [ActionPolicy Module](../modules/policy_based/action_policy.md)

**Default Callbacks** (per module):
- Check module documentation for default callback timing
- Not all modules support callback configuration

**When to change:**
- Performance optimization (run logic later in lifecycle)
- Integration requirements (coordinate with other gems)
- Testing strategies (control execution timing)

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
- [Pundit Module](../modules/policy_based/pundit.md) - Uses `inherit_authorization`
- [ActionPolicy Module](../modules/policy_based/action_policy.md) - Uses `inherit_authorization`

## Summary

| Option | Default | Purpose |
|--------|---------|---------|
| `default_modules` | `[]` | Auto-include optional modules when including DSL |
| `inherit_settings` | `true` | Child classes inherit parent settings |
| `inherit_authorization` | `true` | Child settings inherit parent auth rules |
| `inheritable_options` | Auto-populated | Which options nested settings inherit from parents |
| `add_inheritable_option(name)` | N/A | Add option to inherited list (if not explicitly set) |
| `module_callback(name, callback)` | Per-module | Configure when module's logic runs in Rails lifecycle |
