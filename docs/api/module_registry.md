# ModuleRegistry API Reference

Complete API reference for `ModelSettings::ModuleRegistry` - the centralized registry for managing modules, options, lifecycle hooks, and metadata.

## Table of Contents

1. [Overview](#overview)
2. [Module Registration](#module-registration)
3. [Option Registration](#option-registration)
4. [Lifecycle Hooks](#lifecycle-hooks)
5. [Metadata Management](#metadata-management)
6. [Query Methods Registry](#query-methods-registry)
7. [Inheritable Options](#inheritable-options)
8. [Callback Configuration](#callback-configuration)
9. [Helper Methods](#helper-methods)
10. [Internal Methods](#internal-methods)

---

## Overview

`ModuleRegistry` is the central hub for the module system in ModelSettings. It provides:

- **Module Registration**: Register modules and manage exclusive groups
- **Option Registration**: Define custom DSL options with validators
- **Lifecycle Hooks**: Hook into setting lifecycle events
- **Metadata Storage**: Centralized metadata for all modules
- **Query Methods**: Introspection API for module-provided methods
- **Inheritable Options**: Configure which options cascade to nested settings
- **Callback Configuration**: Manage Rails lifecycle callback timing

**Access Pattern**:
```ruby
# In your module
module ModelSettings
  module Modules
    module YourModule
      extend ActiveSupport::Concern

      included do
        ModelSettings::ModuleRegistry.register_module(:your_module, self)
        # ... other registration calls
      end
    end
  end
end
```

---

## Module Registration

### `register_module(name, mod)`

Register a module with ModelSettings.

**Parameters**:
- `name` (Symbol) - Unique identifier for the module
- `mod` (Module) - The module object

**Returns**: `void`

**Example**:
```ruby
ModuleRegistry.register_module(:audit_trail, ModelSettings::Modules::AuditTrail)
```

**Notes**:
- Module name must be unique
- Usually called in `included` hook
- Required before using any other registry features

---

### `register_exclusive_group(group_name, module_name)`

Add module to an exclusive group (only one module from group can be active).

**Parameters**:
- `group_name` (Symbol) - Name of the exclusive group
- `module_name` (Symbol) - Module to add to group

**Returns**: `void`

**Example**:
```ruby
# Authorization modules are mutually exclusive
ModuleRegistry.register_exclusive_group(:authorization, :pundit)
ModuleRegistry.register_exclusive_group(:authorization, :action_policy)
ModuleRegistry.register_exclusive_group(:authorization, :roles)

# In model - raises error if multiple authorization modules included
class User < ApplicationRecord
  include ModelSettings::DSL
  include ModelSettings::Modules::Pundit
  include ModelSettings::Modules::Roles  # ❌ ArgumentError!
end
```

**Built-in Groups**:
- `:authorization` - Roles, Pundit, ActionPolicy

---

### `module_registered?(name)`

Check if a module is registered.

**Parameters**:
- `name` (Symbol) - Module name

**Returns**: `Boolean`

**Example**:
```ruby
ModuleRegistry.module_registered?(:pundit)  # => true
ModuleRegistry.module_registered?(:unknown)  # => false
```

---

### `get_module(name)`

Get registered module by name.

**Parameters**:
- `name` (Symbol) - Module name

**Returns**: `Module` or `nil`

**Example**:
```ruby
mod = ModuleRegistry.get_module(:pundit)
# => ModelSettings::Modules::Pundit
```

---

### `modules`

Get all registered modules.

**Returns**: `Hash` - `{name => module}`

**Example**:
```ruby
ModuleRegistry.modules
# => {:roles => ModelSettings::Modules::Roles, :pundit => ..., ...}
```

---

### `exclusive_groups`

Get all exclusive groups and their members.

**Returns**: `Hash` - `{group_name => [module_names]}`

**Example**:
```ruby
ModuleRegistry.exclusive_groups
# => {:authorization => [:roles, :pundit, :action_policy]}
```

---

## Option Registration

### `register_option(option_name, validator = nil, &block)`

Register a custom DSL option that modules can use.

**Parameters**:
- `option_name` (Symbol) - Name of the option
- `validator` (Proc, optional) - Validation logic
- `&block` (optional) - Alternative way to provide validator

**Returns**: `void`

**Validator Signature**:
```ruby
->(value, setting, model_class) { ... }
# Should raise ArgumentError if invalid
```

**Example**:
```ruby
# Simple validator
ModuleRegistry.register_option(:audit_level) do |value, setting, model_class|
  unless [:minimal, :standard, :detailed].include?(value)
    raise ArgumentError, "audit_level must be :minimal, :standard, or :detailed"
  end
end

# Usage in model
setting :premium, audit_level: :detailed
```

**Built-in Options**:
- `:viewable_by`, `:editable_by` (Roles)
- `:authorize_with` (Pundit, ActionPolicy)

---

### `registered_options`

Get all registered options.

**Returns**: `Hash` - `{option_name => validator}`

**Example**:
```ruby
ModuleRegistry.registered_options
# => {:audit_level => #<Proc>, :viewable_by => #<Proc>, ...}
```

---

### `validate_setting_options!(setting)`

Validate all options on a setting.

**Parameters**:
- `setting` (Setting) - Setting to validate

**Returns**: `void`

**Raises**: `ArgumentError` if any option is invalid

**Example**:
```ruby
# Called automatically during setting definition
# You rarely call this manually
ModuleRegistry.validate_setting_options!(setting)
```

---

## Lifecycle Hooks

### `on_setting_defined(&block)`

Hook that runs when a setting is defined in the DSL.

**Block Parameters**:
- `setting` (Setting) - The setting being defined
- `model_class` (Class) - The model class

**Returns**: `void`

**Example**:
```ruby
ModuleRegistry.on_setting_defined do |setting, model_class|
  if setting.options[:audit_level]
    # Store audit configuration
    AuditConfig.store(model_class, setting.name, setting.options[:audit_level])
  end
end
```

**When It Runs**: Immediately when `setting :name, ...` is called

**Use Cases**:
- Capturing metadata from options
- Validating option combinations
- Setting up data structures

---

### `on_settings_compiled(&block)`

Hook that runs after all settings are compiled.

**Block Parameters**:
- `settings` (Array<Setting>) - All settings for the model
- `model_class` (Class) - The model class

**Returns**: `void`

**Example**:
```ruby
ModuleRegistry.on_settings_compiled do |settings, model_class|
  # Build authorization index
  auth_settings = settings.select { |s| s.options[:viewable_by] }
  AuthIndex.build(model_class, auth_settings)
end
```

**When It Runs**: After `compile_settings!` processes all settings

**Use Cases**:
- Building indexes
- Validating relationships between settings
- Setting up cross-setting dependencies

---

### `before_setting_change(&block)`

Hook that runs before a setting value changes.

**Block Parameters**:
- `instance` (ActiveRecord) - Model instance
- `setting` (Setting) - Setting being changed
- `new_value` (Any) - New value about to be set

**Returns**: `void`

**Example**:
```ruby
ModuleRegistry.before_setting_change do |instance, setting, new_value|
  if setting.options[:audit_level]
    AuditLog.log_before(instance, setting.name, new_value)
  end
end
```

**When It Runs**: Before `instance.setting_name = value`

**Use Cases**:
- Logging old values
- Pre-validation
- Triggering side effects

---

### `after_setting_change(&block)`

Hook that runs after a setting value changes.

**Block Parameters**:
- `instance` (ActiveRecord) - Model instance
- `setting` (Setting) - Setting that changed
- `old_value` (Any) - Previous value
- `new_value` (Any) - New value

**Returns**: `void`

**Example**:
```ruby
ModuleRegistry.after_setting_change do |instance, setting, old_value, new_value|
  if setting.options[:notify]
    NotificationService.notify_change(instance, setting, old_value, new_value)
  end
end
```

**When It Runs**: After `instance.setting_name = value` completes

**Use Cases**:
- Audit logging
- Notifications
- Cache invalidation

---

### Hook Execution Methods

#### `execute_definition_hooks(setting, model_class)`

Execute all `on_setting_defined` hooks.

**Internal**: Called by DSL automatically

---

#### `execute_compilation_hooks(settings, model_class)`

Execute all `on_settings_compiled` hooks.

**Internal**: Called by DSL automatically

---

#### `execute_before_change_hooks(instance, setting, new_value)`

Execute all `before_setting_change` hooks.

**Internal**: Called by DSL automatically

---

#### `execute_after_change_hooks(instance, setting, old_value, new_value)`

Execute all `after_setting_change` hooks.

**Internal**: Called by DSL automatically

---

## Metadata Management

### `set_module_metadata(model_class, module_name, setting_name, metadata)`

Store metadata for a module about a setting.

**Parameters**:
- `model_class` (Class) - Model class
- `module_name` (Symbol) - Module identifier
- `setting_name` (Symbol) - Setting name
- `metadata` (Any) - Metadata to store

**Returns**: `void`

**Example**:
```ruby
# Store authorization rules
ModuleRegistry.set_module_metadata(
  User,
  :roles,
  :premium,
  {viewable_by: :all, editable_by: :admin}
)
```

**Storage Structure**:
```ruby
{
  User => {
    :roles => {
      :premium => {viewable_by: :all, editable_by: :admin},
      :billing => {viewable_by: :owner, editable_by: :owner}
    },
    :i18n => {
      :premium => {translation_key: "user.settings.premium"}
    }
  }
}
```

---

### `get_module_metadata(model_class, module_name, setting_name = nil)`

Retrieve metadata for a module.

**Parameters**:
- `model_class` (Class) - Model class
- `module_name` (Symbol) - Module identifier
- `setting_name` (Symbol, optional) - Specific setting or all settings

**Returns**: `Hash` or `nil`

**Example**:
```ruby
# Get metadata for specific setting
meta = ModuleRegistry.get_module_metadata(User, :roles, :premium)
# => {viewable_by: :all, editable_by: :admin}

# Get metadata for all settings
all_meta = ModuleRegistry.get_module_metadata(User, :roles)
# => {:premium => {...}, :billing => {...}}
```

---

### `module_metadata?(model_class, module_name, setting_name)`

Check if module has metadata for a setting.

**Parameters**:
- `model_class` (Class) - Model class
- `module_name` (Symbol) - Module identifier
- `setting_name` (Symbol) - Setting name

**Returns**: `Boolean`

**Example**:
```ruby
ModuleRegistry.module_metadata?(User, :roles, :premium)  # => true
ModuleRegistry.module_metadata?(User, :roles, :unknown)  # => false
```

---

## Query Methods Registry

### `register_query_method(module_name, method_name, scope, metadata = {})`

Register a method that a module provides for introspection.

**Parameters**:
- `module_name` (Symbol) - Module providing the method
- `method_name` (Symbol) - Method name
- `scope` (Symbol) - `:class` or `:instance`
- `metadata` (Hash) - Additional metadata (description, parameters, etc.)

**Returns**: `void`

**Example**:
```ruby
ModuleRegistry.register_query_method(
  :roles,
  :viewable_settings,
  :instance,
  description: "Returns settings viewable by current user",
  parameters: [{name: :role, type: :symbol}],
  returns: "Array<Setting>"
)
```

**Use Cases**:
- IDE autocomplete hints
- Documentation generation
- Debugging tools

---

### `query_methods_for(module_name)`

Get all query methods registered by a module.

**Parameters**:
- `module_name` (Symbol) - Module name

**Returns**: `Array<Hash>` - Array of method metadata

**Example**:
```ruby
methods = ModuleRegistry.query_methods_for(:roles)
# => [
#   {method_name: :viewable_settings, scope: :instance, ...},
#   {method_name: :editable_settings, scope: :instance, ...}
# ]
```

---

### `query_methods`

Get all registered query methods across all modules.

**Returns**: `Hash` - `{module_name => [methods]}`

**Example**:
```ruby
all_methods = ModuleRegistry.query_methods
# => {
#   :roles => [{...}, {...}],
#   :i18n => [{...}, {...}]
# }
```

---

## Inheritable Options

### `register_inheritable_option(option_name, merge_strategy: :replace, auto_include: true)`

Register an option as inheritable by nested settings.

**Parameters**:
- `option_name` (Symbol) - Option name
- `merge_strategy` (Symbol) - How to merge parent/child values (`:replace`, `:append`, `:merge`)
- `auto_include` (Boolean) - Auto-add to global inheritable_options list

**Returns**: `void`

**Merge Strategies**:
- `:replace` - Child value completely replaces parent
- `:append` - Arrays concatenated (parent + child)
- `:merge` - Hashes deep merged (child overrides parent keys)

**Example**:
```ruby
# Roles module registers viewable_by with append strategy
ModuleRegistry.register_inheritable_option(
  :viewable_by,
  merge_strategy: :append,
  auto_include: true
)

# Usage in model
setting :billing, viewable_by: [:admin] do
  setting :invoices  # Inherits viewable_by: [:admin]
  setting :reports, viewable_by: [:accountant]  # Merged: [:admin, :accountant]
end
```

**See**: [Configuration Guide](../core/configuration.md#inheritable_options) for user-facing docs

---

### `inheritable_option?(option_name)`

Check if an option is registered as inheritable.

**Parameters**:
- `option_name` (Symbol) - Option name

**Returns**: `Boolean`

**Example**:
```ruby
ModuleRegistry.inheritable_option?(:viewable_by)  # => true
ModuleRegistry.inheritable_option?(:unknown)       # => false
```

---

### `merge_strategy_for(option_name)`

Get the merge strategy for an inheritable option.

**Parameters**:
- `option_name` (Symbol) - Option name

**Returns**: `Symbol` - `:replace`, `:append`, or `:merge`

**Example**:
```ruby
ModuleRegistry.merge_strategy_for(:viewable_by)     # => :append
ModuleRegistry.merge_strategy_for(:authorize_with)  # => :replace
```

---

### `registered_inheritable_options`

Get all registered inheritable options.

**Returns**: `Hash` - `{option_name => {merge_strategy:, auto_include:}}`

**Example**:
```ruby
ModuleRegistry.registered_inheritable_options
# => {
#   :viewable_by => {merge_strategy: :append, auto_include: true},
#   :editable_by => {merge_strategy: :append, auto_include: true},
#   :authorize_with => {merge_strategy: :replace, auto_include: true}
# }
```

---

## Callback Configuration

### `register_module_callback_config(module_name, default_callback:, configurable: true)`

Register callback configuration for a module.

**Parameters**:
- `module_name` (Symbol) - Module identifier
- `default_callback` (Symbol) - Default Rails callback (`:before_validation`, `:after_save`, etc.)
- `configurable` (Boolean) - Whether users can change the callback

**Returns**: `void`

**Example**:
```ruby
# Register audit module with configurable callback
ModuleRegistry.register_module_callback_config(
  :audit_trail,
  default_callback: :after_save,
  configurable: true
)
```

**Built-in Callbacks**:
- `:before_validation`
- `:after_validation`
- `:before_save`
- `:after_save`
- `:after_commit`
- `:before_destroy`
- `:after_destroy`

---

### `get_module_callback_config(module_name)`

Get callback configuration for a module.

**Parameters**:
- `module_name` (Symbol) - Module name

**Returns**: `Hash` - `{default_callback:, configurable:}` or `nil`

**Example**:
```ruby
config = ModuleRegistry.get_module_callback_config(:audit_trail)
# => {default_callback: :after_save, configurable: true}
```

---

### `get_module_callback(module_name)`

Get effective callback for a module (respects global configuration).

**Parameters**:
- `module_name` (Symbol) - Module name

**Returns**: `Symbol` - Rails callback name

**Example**:
```ruby
# Default callback
callback = ModuleRegistry.get_module_callback(:audit_trail)
# => :after_save

# After user configures it differently
ModelSettings.configure do |config|
  config.module_callback(:audit_trail, :after_commit)
end

callback = ModuleRegistry.get_module_callback(:audit_trail)
# => :after_commit
```

---

### `module_callback_configs`

Get all module callback configurations.

**Returns**: `Hash` - `{module_name => {default_callback:, configurable:}}`

**Example**:
```ruby
configs = ModuleRegistry.module_callback_configs
# => {
#   :audit_trail => {default_callback: :after_save, configurable: true},
#   :workflow => {default_callback: :before_save, configurable: false}
# }
```

---

## Helper Methods

### `module_included?(module_name, model_class)`

Check if a module is included in a model.

**Parameters**:
- `module_name` (Symbol) - Module to check
- `model_class` (Class) - Model class

**Returns**: `Boolean`

**Example**:
```ruby
ModuleRegistry.module_included?(:roles, User)    # => true
ModuleRegistry.module_included?(:pundit, User)   # => false
```

**Notes**:
- Uses symbol-based tracking (stable across module reloads)
- See DSL `_active_modules` for implementation details

---

### `check_exclusive_conflict!(model_class, module_name)`

Check if including a module would violate exclusive group constraints.

**Parameters**:
- `model_class` (Class) - Model class
- `module_name` (Symbol) - Module being included

**Returns**: `void`

**Raises**: `ArgumentError` if conflict exists

**Example**:
```ruby
# Check before including
ModuleRegistry.check_exclusive_conflict!(User, :action_policy)
# => ArgumentError if Pundit or Roles already included

# Called automatically by DSL
```

---

### `validate_exclusive_groups!(active_modules)`

Validate that no exclusive group has multiple active modules.

**Parameters**:
- `active_modules` (Array<Symbol>) - List of active module names

**Returns**: `void`

**Raises**: `ArgumentError` if violation found

**Internal**: Called by DSL during compilation

---

### `extend_setting(methods_module)`

Extend the Setting class with additional methods.

**Parameters**:
- `methods_module` (Module) - Module containing methods to add

**Returns**: `void`

**Example**:
```ruby
module CustomSettingMethods
  def custom_helper
    "Setting: #{name}"
  end
end

ModuleRegistry.extend_setting(CustomSettingMethods)

# Now all settings have the method
setting = User.settings.find(:premium)
setting.custom_helper  # => "Setting: premium"
```

**Use Cases**:
- Adding helper methods to settings
- Extending setting behavior without modifying core

---

## Internal Methods

The following methods are primarily for internal use by ModelSettings core:

### Lifecycle Hook Getters

- `definition_hooks` - Get all on_setting_defined hooks
- `compilation_hooks` - Get all on_settings_compiled hooks
- `before_change_hooks` - Get all before_setting_change hooks
- `after_change_hooks` - Get all after_setting_change hooks

These return arrays of registered Proc objects.

---

## Complete Example

Here's a complete example showing how to use ModuleRegistry to create a full-featured module:

```ruby
module ModelSettings
  module Modules
    module AuditTrail
      extend ActiveSupport::Concern

      included do
        # 1. Register the module
        ModuleRegistry.register_module(:audit_trail, self)

        # 2. Register options
        ModuleRegistry.register_option(:audit_level) do |value, setting, model_class|
          unless [:minimal, :detailed].include?(value)
            raise ArgumentError, "audit_level must be :minimal or :detailed"
          end
        end

        ModuleRegistry.register_option(:audit_user, ->(value, _, _) {
          unless value.respond_to?(:call)
            raise ArgumentError, "audit_user must be a callable"
          end
        })

        # 3. Register as inheritable (optional)
        ModuleRegistry.register_inheritable_option(
          :audit_level,
          merge_strategy: :replace,
          auto_include: true
        )

        # 4. Register callback configuration
        ModuleRegistry.register_module_callback_config(
          :audit_trail,
          default_callback: :after_save,
          configurable: true
        )

        # 5. Register lifecycle hooks
        ModuleRegistry.on_setting_defined do |setting, model_class|
          if setting.options[:audit_level]
            # Store which settings to audit
            ModuleRegistry.set_module_metadata(
              model_class,
              :audit_trail,
              setting.name,
              {level: setting.options[:audit_level]}
            )
          end
        end

        ModuleRegistry.after_setting_change do |instance, setting, old_value, new_value|
          meta = ModuleRegistry.get_module_metadata(
            instance.class,
            :audit_trail,
            setting.name
          )

          if meta
            level = meta[:level]
            user = setting.options[:audit_user]&.call(instance)

            AuditLog.create!(
              model: instance,
              setting: setting.name,
              old_value: old_value,
              new_value: new_value,
              level: level,
              user: user
            )
          end
        end

        # 6. Register query methods
        ModuleRegistry.register_query_method(
          :audit_trail,
          :audited_settings,
          :class,
          description: "Returns all settings being audited",
          returns: "Array<Setting>"
        )
      end

      # 7. Add model class methods
      class_methods do
        def audited_settings
          settings.select do |setting|
            ModuleRegistry.module_metadata?(self, :audit_trail, setting.name)
          end
        end
      end
    end
  end
end
```

**Usage**:
```ruby
class User < ApplicationRecord
  include ModelSettings::DSL
  include ModelSettings::Modules::AuditTrail

  setting :premium,
    type: :column,
    audit_level: :detailed,
    audit_user: ->(user) { Current.user }

  setting :billing do
    setting :auto_renew,
      type: :column,
      audit_level: :minimal
  end
end

# Query audited settings
User.audited_settings  # => [premium, auto_renew settings]

# Changes are automatically logged
user = User.find(1)
user.premium = true  # => Creates AuditLog record
```

---

## See Also

- [Module Development Guide](../guides/module_development.md) - Comprehensive guide
- [Configuration Reference](../core/configuration.md) - Global configuration
- [DSL Reference](../core/dsl.md) - DSL methods
- [Built-in Modules](../modules/) - Reference implementations
