# Module Development API

This document defines the contract for creating external modules that extend ModelSettings functionality.

## Table of Contents

1. [Overview](#overview)
2. [Quick Start with Generator](#quick-start-with-generator)
3. [Module Structure](#module-structure)
4. [ModuleRegistry API](#moduleregistry-api)
4. [Lifecycle Hooks](#lifecycle-hooks)
5. [Hook Execution Order](#hook-execution-order)
6. [Best Practices](#best-practices)
7. [Complete Example](#complete-example)
8. [Testing Modules](#testing-modules)

---

## Overview

ModelSettings provides a comprehensive Module Development API that allows developers to create custom modules extending the DSL with new options, behaviors, and lifecycle hooks.

**Key Features:**
- Register custom DSL options
- Hook into setting lifecycle (definition, compilation, runtime changes)
- Extend Setting class with custom methods
- Define mutually exclusive module groups
- Validate options at definition-time

**Built-in Modules** (reference implementations):
- `ModelSettings::Modules::Roles` - Simple RBAC authorization
- `ModelSettings::Modules::Pundit` - Pundit integration
- `ModelSettings::Modules::ActionPolicy` - ActionPolicy integration
- `ModelSettings::Modules::I18n` - Internationalization support

---

## Quick Start with Generator

The easiest way to create a new module is using the Rails generator:

```bash
rails generate model_settings:module AuditTrail
```

This will create:
- `lib/model_settings/modules/audit_trail.rb` - Module implementation
- `spec/model_settings/modules/audit_trail_spec.rb` - RSpec tests
- `docs/modules/audit_trail.md` - Documentation

### Generator Options

**Basic usage:**
```bash
rails generate model_settings:module NAME [options]
```

**Options:**

| Option | Description | Example |
|--------|-------------|---------|
| `--skip-tests` | Don't generate test file | `--skip-tests` |
| `--skip-docs` | Don't generate documentation | `--skip-docs` |
| `--exclusive-group=GROUP` | Add to exclusive group | `--exclusive-group=authorization` |
| `--options=OPTS` | Register custom options | `--options=audit_level:symbol notify:boolean` |

**Examples:**

```bash
# Basic module
rails generate model_settings:module AuditTrail

# Module with exclusive group (e.g., authorization)
rails generate model_settings:module CustomAuth --exclusive-group=authorization

# Module with custom options
rails generate model_settings:module Workflow --options=state:symbol notify:boolean

# Module without tests and docs
rails generate model_settings:module SimpleModule --skip-tests --skip-docs
```

**Custom option types:**
- `symbol` - Validates value is a Symbol
- `boolean` - Validates value is true or false
- `string` - Validates value is a String
- `array` - Validates value is an Array
- `hash` - Validates value is a Hash

### After Generation

1. Edit the generated module file to implement your logic
2. Update the TODO comments with your implementation
3. Run tests: `bundle exec rspec spec/model_settings/modules/your_module_spec.rb`
4. Update documentation in `docs/modules/your_module.md`

---

## Module Structure

Custom modules must follow this structure:

```ruby
module ModelSettings
  module Modules
    module MyModule
      extend ActiveSupport::Concern

      included do
        # 1. Register module (for tracking and conflict detection)
        ModelSettings::ModuleRegistry.register_module(:my_module, self)

        # 2. Register exclusive group (optional, for mutually exclusive modules)
        ModelSettings::ModuleRegistry.register_exclusive_group(:authorization, :my_module)

        # 3. Check for conflicts with other modules
        ModelSettings::ModuleRegistry.check_exclusive_conflict!(self, :my_module)

        # 4. Register custom DSL options
        ModelSettings::ModuleRegistry.register_option(:my_option) do |setting, value|
          # Optional validator
          raise ArgumentError, "Invalid value" unless valid?(value)
        end

        # 5. Register lifecycle hooks
        ModelSettings::ModuleRegistry.on_setting_defined do |setting, model_class|
          # Process setting when defined
        end

        # 6. Add module to active modules list
        settings_add_module(:my_module)
      end

      # Class methods added to model
      module ClassMethods
        def my_class_method
          # ...
        end
      end

      # Instance methods added to model
      def my_instance_method
        # ...
      end
    end
  end
end
```

**Namespace Convention:**
- All modules must be under `ModelSettings::Modules::*`
- Module name should be PascalCase (e.g., `ActionPolicy`)
- Symbol name should be snake_case (e.g., `:action_policy`)

---

## ModuleRegistry API

The `ModelSettings::ModuleRegistry` provides the following methods:

### Module Registration

#### `register_module(name, mod)`

Register a module for tracking and conflict detection.

```ruby
ModelSettings::ModuleRegistry.register_module(:my_module, MyModule)
```

**Parameters:**
- `name` (Symbol) - Module identifier (snake_case)
- `mod` (Module) - The module constant

**Returns:** None

---

#### `register_exclusive_group(group_name, module_name)`

Register a module as part of a mutually exclusive group.

```ruby
ModelSettings::ModuleRegistry.register_exclusive_group(:authorization, :my_auth_module)
```

**Parameters:**
- `group_name` (Symbol) - Group identifier (e.g., `:authorization`)
- `module_name` (Symbol) - Module identifier

**Use Case:** Authorization modules (only one can be active at a time)

**Behavior:** When a model tries to include two modules from the same exclusive group, `check_exclusive_conflict!` will raise an error.

---

#### `check_exclusive_conflict!(model_class, module_name)`

Check for conflicts when including a module.

```ruby
included do
  ModelSettings::ModuleRegistry.check_exclusive_conflict!(self, :my_module)
end
```

**Parameters:**
- `model_class` (Class) - The model class including the module
- `module_name` (Symbol) - Module being included

**Raises:** `ExclusiveGroupConflictError` if a conflicting module is already included

**Example Error:**
```
Cannot include :pundit module: conflicts with :roles module
(both are in :authorization exclusive group).
Use only ONE authorization module at a time.
```

---

### Option Registration

#### `register_option(option_name, validator = nil, &block)`

Register a custom DSL option that can be used in setting definitions.

```ruby
ModelSettings::ModuleRegistry.register_option(:viewable_by) do |setting, value|
  unless value == :all || value.is_a?(Array)
    raise ArgumentError, "viewable_by must be :all or Array of roles"
  end
end
```

**Parameters:**
- `option_name` (Symbol) - Option name (snake_case)
- `validator` (Proc, optional) - Validation block receiving `(setting, value)`
- `&block` - Alternative way to pass validator

**Validator Behavior:**
- Called during setting definition (`setting` method call)
- Should raise `ArgumentError` if value is invalid
- Receives the `Setting` object and the option value
- Can access other setting attributes: `setting.name`, `setting.type`, etc.

**Example with Named Validator:**
```ruby
validator = ->(setting, value) { raise ArgumentError unless value.positive? }
ModelSettings::ModuleRegistry.register_option(:min_value, validator)
```

---

#### `validate_setting_options!(setting)`

Validate all registered options for a setting.

```ruby
ModelSettings::ModuleRegistry.validate_setting_options!(setting_obj)
```

**Parameters:**
- `setting` (Setting) - The setting object to validate

**Behavior:**
- Automatically called by DSL during setting definition
- Runs all validators for options present on the setting
- Raises `ArgumentError` if any validator fails

**Internal Use:** You typically don't call this directly - it's called by the DSL framework.

---

### Setting Extension

#### `extend_setting(methods_module)`

Add methods to the `Setting` class.

```ruby
module SettingExtensions
  def my_custom_method
    "Setting: #{name}, Type: #{type}"
  end
end

ModelSettings::ModuleRegistry.extend_setting(SettingExtensions)
```

**Parameters:**
- `methods_module` (Module) - Module containing methods to add

**Use Case:** Add custom methods to Setting objects that can be called like:
```ruby
setting = User.find_setting(:premium_mode)
setting.my_custom_method  # => "Setting: premium_mode, Type: column"
```

---

### Module Queries

#### `module_included?(module_name, model_class)`

Check if a module is included in a model class.

```ruby
if ModelSettings::ModuleRegistry.module_included?(:pundit, User)
  # Pundit module is active
end
```

**Parameters:**
- `module_name` (Symbol) - Module identifier
- `model_class` (Class) - Model class to check

**Returns:** Boolean

---

#### `module_registered?(name)`

Check if a module is registered.

```ruby
ModelSettings::ModuleRegistry.module_registered?(:my_module)  # => true/false
```

---

#### `get_module(name)`

Get a registered module constant.

```ruby
mod = ModelSettings::ModuleRegistry.get_module(:roles)
# => ModelSettings::Modules::Roles
```

---

## Lifecycle Hooks

Modules can hook into four lifecycle events:

### 1. `on_setting_defined`

Called immediately after a setting is defined.

```ruby
ModelSettings::ModuleRegistry.on_setting_defined do |setting, model_class|
  # setting: Setting object just created
  # model_class: The model class defining the setting

  if setting.my_option
    # Validate, compute metadata, etc.
  end
end
```

**When:** Definition-time (during `setting` method call)
**Idempotency:** ✅ **MUST be idempotent** (may run multiple times in development due to code reloading)
**Use Cases:**
- Validate custom options
- Compute derived metadata
- Store option values for later use
- Raise errors for invalid configurations

**Example:**
```ruby
on_setting_defined do |setting, model_class|
  if setting.viewable_by && !valid_roles?(setting.viewable_by)
    raise ArgumentError, "Invalid roles: #{setting.viewable_by}"
  end
end
```

---

### 2. `on_settings_compiled`

Called after all settings are defined and adapters are set up.

```ruby
ModelSettings::ModuleRegistry.on_settings_compiled do |settings, model_class|
  # settings: Array of all Setting objects (including nested)
  # model_class: The model class

  # Build indexes, validate relationships across settings
end
```

**When:** Definition-time (after class loading completes, before first use)
**Idempotency:** ✅ **MUST be idempotent** (may run multiple times in development)
**Use Cases:**
- Build indexes for fast runtime lookups
- Validate relationships across settings
- Pre-compute expensive operations
- Set up cross-setting dependencies

**Example:**
```ruby
on_settings_compiled do |settings, model_class|
  # Build index for fast lookup (MUST clear previous index for idempotency)
  model_class._auth_index = {}
  settings.each do |s|
    if s.viewable_by
      model_class._auth_index[s.name] = s.viewable_by
    end
  end
end
```

---

### 3. `before_setting_change`

Called before a setting value changes.

```ruby
ModelSettings::ModuleRegistry.before_setting_change do |instance, setting, new_value|
  # instance: Model instance (e.g., user)
  # setting: Setting object
  # new_value: The new value being set

  # Authorization checks, pre-validation, etc.
end
```

**When:** Runtime (before value assignment)
**Idempotency:** ❌ Not required (but should handle multiple calls gracefully)
**Can Raise:** ✅ Yes - raising an exception aborts the change
**Use Cases:**
- Authorization checks
- Pre-change validation
- Conditional logic before changes
- Rate limiting

**Example:**
```ruby
before_setting_change do |instance, setting, new_value|
  unless authorized_to_edit?(instance, setting, new_value)
    raise UnauthorizedError, "Cannot change #{setting.name}"
  end
end
```

---

### 4. `after_setting_change`

Called after a setting value changes.

```ruby
ModelSettings::ModuleRegistry.after_setting_change do |instance, setting, old_value, new_value|
  # instance: Model instance
  # setting: Setting object
  # old_value: Previous value
  # new_value: New value

  # Audit logging, notifications, side effects
end
```

**When:** Runtime (after value assignment)
**Idempotency:** ⚠️ **RECOMMENDED** (should handle duplicate calls gracefully)
**Cannot Raise:** ⚠️ Exceptions should be caught and logged (change already happened)
**Use Cases:**
- Audit logging
- Notifications
- Webhooks
- Analytics tracking

**Example:**
```ruby
after_setting_change do |instance, setting, old_value, new_value|
  AuditLog.create!(
    model: instance.class.name,
    model_id: instance.id,
    setting_name: setting.name,
    old_value: old_value,
    new_value: new_value,
    changed_at: Time.current
  )
end
```

---

## Hook Execution Order

### Definition-Time (Class Loading)

```
1. Model includes ModelSettings::DSL
   ↓
2. Model includes custom module(s)
   ↓
3. For each `setting` call:
   a. Create Setting object
   b. Validate registered options (ModuleRegistry.validate_setting_options!)
   c. Execute ALL on_setting_defined hooks (order: registration order)
   d. Setup storage adapter
   ↓
4. After class loading completes:
   ModelSettings::DSL.compile_settings! is called
   a. Execute ALL on_settings_compiled hooks (order: registration order)
   b. Mark settings as compiled
```

**Idempotency Note:** Steps 3-4 may repeat in development due to Rails code reloading.

---

### Runtime (Setting Value Changes)

```
1. User calls setter: instance.premium_mode = true
   ↓
2. Adapter's write method called
   ↓
3. Execute ALL before_setting_change hooks (order: registration order)
   - If any hook raises exception → change aborted
   ↓
4. Assign new value to database column/JSON
   ↓
5. Execute ALL after_setting_change hooks (order: registration order)
   - Exceptions should be caught and logged
   ↓
6. Return new value
```

**Hook Order:** Hooks execute in the order they were registered (first registered = first executed).

---

## Best Practices

### 1. Namespace Your Options

Use prefixed names to avoid conflicts with other modules.

```ruby
# ✅ Good - clear namespace
register_option(:audit_log_level)
register_option(:workflow_state)

# ❌ Bad - too generic, may conflict
register_option(:level)
register_option(:state)
```

---

### 2. Validate Early (Definition-Time)

Catch configuration errors when the class loads, not at runtime.

```ruby
on_setting_defined do |setting, model_class|
  if setting.my_option && !valid_value?(setting.my_option)
    raise ArgumentError,
          "Invalid my_option for #{setting.name}: #{setting.my_option}. " \
          "Expected: #{valid_values.join(', ')}"
  end
end
```

---

### 3. Make Definition Hooks Idempotent

Development mode reloads code frequently. Your hooks must handle repeated calls.

```ruby
# ✅ CORRECT - Idempotent (clears before building)
on_settings_compiled do |settings, model_class|
  model_class._my_index = {}  # Clear previous index
  settings.each { |s| model_class._my_index[s.name] = s.my_option }
end

# ❌ WRONG - Not idempotent (accumulates duplicates)
on_settings_compiled do |settings, model_class|
  model_class._my_index ||= {}  # WRONG! Keeps old data
  settings.each { |s| model_class._my_index[s.name] = s.my_option }
end
```

---

### 4. Pre-Compute at Compilation Time

Build indexes during compilation for fast runtime lookups.

```ruby
on_settings_compiled do |settings, model_class|
  # Build reverse index: option_value => [setting_names]
  model_class._option_index = Hash.new { |h, k| h[k] = [] }

  settings.each do |setting|
    if setting.my_option
      model_class._option_index[setting.my_option] << setting.name
    end
  end
end

# Fast runtime lookup
def settings_with_option(value)
  self.class._option_index[value].map { |name| find_setting(name) }
end
```

---

### 5. Provide Clear Error Messages

Help developers debug configuration issues.

```ruby
before_setting_change do |instance, setting, new_value|
  unless authorized?(instance, setting)
    raise UnauthorizedError,
          "User #{instance.id} cannot change '#{setting.name}' setting. " \
          "Required role: #{setting.editable_by.inspect}, " \
          "User roles: #{instance.roles.inspect}"
  end
end
```

---

### 6. Document Dependencies

If your module requires external gems, check and document them.

```ruby
module ModelSettings
  module Modules
    module MyModule
      extend ActiveSupport::Concern

      included do
        unless defined?(SomeGem)
          raise LoadError,
                "MyModule requires 'some_gem' gem. " \
                "Add 'gem \"some_gem\"' to your Gemfile."
        end
      end
    end
  end
end
```

---

### 7. Handle Nil Values Gracefully

Users may not provide your option - handle nil appropriately.

```ruby
on_setting_defined do |setting, model_class|
  # ✅ Good - checks for presence
  if setting.my_option.present?
    validate_my_option(setting.my_option)
  end

  # ❌ Bad - crashes on nil
  validate_my_option(setting.my_option)
end
```

---

### 8. Test Module Isolation

Ensure your module works independently of other modules.

```ruby
RSpec.describe "MyModule" do
  it "works without other modules" do
    model = Class.new(ApplicationRecord) do
      include ModelSettings::DSL
      include ModelSettings::Modules::MyModule

      setting :test, my_option: :value
    end

    expect(model.settings.first.my_option).to eq(:value)
  end
end
```

---

## Complete Example

Here's a complete module implementing audit trail functionality:

```ruby
# frozen_string_literal: true

module ModelSettings
  module Modules
    # Audit Trail module for automatic change logging
    #
    # Provides automatic audit logging for setting changes with configurable detail levels.
    #
    # @example Basic usage
    #   class Account < ApplicationRecord
    #     include ModelSettings::DSL
    #     include ModelSettings::Modules::AuditTrail
    #
    #     setting :billing_enabled,
    #             type: :column,
    #             audit_log: :full
    #   end
    #
    module AuditTrail
      extend ActiveSupport::Concern

      included do
        # 1. Register module
        ModelSettings::ModuleRegistry.register_module(:audit_trail, self)

        # 2. Register DSL option with validator
        ModelSettings::ModuleRegistry.register_option(:audit_log) do |setting, value|
          valid_levels = [:none, :changes_only, :full]
          unless valid_levels.include?(value)
            raise ArgumentError,
                  "audit_log must be one of #{valid_levels.inspect}, got #{value.inspect}"
          end
        end

        # 3. Definition-time validation
        ModelSettings::ModuleRegistry.on_setting_defined do |setting, model_class|
          next unless setting.audit_log

          # Validate audit_log is compatible with setting type
          if setting.type == :store_model && setting.audit_log == :full
            Rails.logger.warn(
              "Setting #{setting.name}: :full audit logging for StoreModel may " \
              "produce large logs. Consider using :changes_only."
            )
          end
        end

        # 4. Compilation-time indexing
        ModelSettings::ModuleRegistry.on_settings_compiled do |settings, model_class|
          # Build index of audited settings (idempotent)
          model_class._audited_settings = settings.select do |s|
            s.audit_log && s.audit_log != :none
          end.map(&:name)
        end

        # 5. Runtime logging
        ModelSettings::ModuleRegistry.after_setting_change do |instance, setting, old_value, new_value|
          next unless setting.audit_log && setting.audit_log != :none

          begin
            log_entry = {
              model_class: instance.class.name,
              model_id: instance.id,
              setting_name: setting.name,
              old_value: serialize_value(old_value),
              new_value: serialize_value(new_value),
              changed_at: Time.current
            }

            # Include full state for :full audit level
            if setting.audit_log == :full
              log_entry[:full_state] = instance.settings.map { |s|
                [s.name, instance.public_send(s.name)]
              }.to_h
            end

            AuditLog.create!(log_entry)
          rescue => e
            # Don't crash the application if audit logging fails
            Rails.logger.error("Failed to create audit log: #{e.message}")
            Rails.logger.error(e.backtrace.join("\n"))
          end
        end

        # 6. Add to active modules
        settings_add_module(:audit_trail)

        # 7. Storage for audited settings list
        class_attribute :_audited_settings, default: []
      end

      # Class methods
      module ClassMethods
        # Get all settings with audit logging enabled
        #
        # @return [Array<Setting>] Settings with audit_log != :none
        def audited_settings
          _audited_settings.map { |name| find_setting(name) }.compact
        end

        # Check if a setting is audited
        #
        # @param setting_name [Symbol] Setting name
        # @return [Boolean]
        def setting_audited?(setting_name)
          _audited_settings.include?(setting_name.to_sym)
        end
      end

      # Instance methods

      # Get audit history for a specific setting
      #
      # @param setting_name [Symbol] Setting name
      # @return [ActiveRecord::Relation] Audit log entries
      #
      # @example
      #   account.audit_history(:billing_enabled)
      #   # => [#<AuditLog old: false, new: true, changed_at: ...>, ...]
      #
      def audit_history(setting_name)
        AuditLog.where(
          model_class: self.class.name,
          model_id: id,
          setting_name: setting_name
        ).order(changed_at: :desc)
      end

      # Get all audited settings for this instance
      #
      # @return [Array<Setting>] Audited settings
      def audited_settings
        self.class.audited_settings
      end

      private

      # Serialize value for audit log storage
      #
      # @param value [Object] Value to serialize
      # @return [String, Hash] Serialized value
      def serialize_value(value)
        case value
        when Hash, Array
          value.to_json
        else
          value.to_s
        end
      end
    end
  end
end
```

**Usage:**

```ruby
class Account < ApplicationRecord
  include ModelSettings::DSL
  include ModelSettings::Modules::AuditTrail

  setting :billing_enabled,
          type: :column,
          audit_log: :full

  setting :api_access,
          type: :column,
          audit_log: :changes_only

  setting :display_name,
          type: :column,
          audit_log: :none  # Not audited
end

account = Account.create!
account.billing_enabled = true
account.save!

# Audit log automatically created
AuditLog.last
# => #<AuditLog
#      model_class: "Account",
#      model_id: 1,
#      setting_name: "billing_enabled",
#      old_value: "false",
#      new_value: "true",
#      full_state: {"billing_enabled" => true, "api_access" => false, ...},
#      changed_at: 2025-11-01 10:30:00>

account.audit_history(:billing_enabled)
# => [#<AuditLog ...>]
```

---

## Testing Modules

### Test Structure

```ruby
# frozen_string_literal: true

require "spec_helper"

RSpec.describe ModelSettings::Modules::MyModule do
  let(:model_class) do
    Class.new(ActiveRecord::Base) do
      self.table_name = "test_models"

      include ModelSettings::DSL
      include ModelSettings::Modules::MyModule

      def self.name
        "TestModel"
      end
    end
  end

  describe "module registration" do
    it "registers module in registry" do
      expect(ModelSettings::ModuleRegistry.module_registered?(:my_module)).to be true
    end
  end

  describe "option registration" do
    it "registers my_option" do
      expect(ModelSettings::ModuleRegistry.registered_options).to have_key(:my_option)
    end

    context "when my_option has invalid value" do
      it "raises ArgumentError" do
        expect {
          model_class.setting :test, my_option: :invalid_value
        }.to raise_error(ArgumentError, /Invalid my_option/)
      end
    end
  end

  describe "lifecycle hooks" do
    before do
      model_class.setting :test_setting, my_option: :valid_value
      model_class.compile_settings!
    end

    it "executes on_setting_defined hook" do
      # Verify hook was executed
    end

    it "executes on_settings_compiled hook" do
      # Verify compilation hook was executed
    end
  end

  describe "runtime behavior" do
    let(:instance) { model_class.create! }

    before do
      model_class.setting :test_setting, my_option: :value
    end

    it "executes before_setting_change hook" do
      # Test before-change behavior
    end

    it "executes after_setting_change hook" do
      # Test after-change behavior
    end
  end
end
```

---

## Related Documentation

- [Configuration](../core/configuration.md) - Global configuration options
- [Roles Module](../modules/roles.md) - Reference implementation
- [Pundit Module](../modules/pundit.md) - Reference implementation
- [ActionPolicy Module](../modules/action_policy.md) - Reference implementation
- [I18n Module](../modules/i18n.md) - Reference implementation

---

## Summary

**Key Points:**
1. Use `ModelSettings::ModuleRegistry` for all module functionality
2. Make definition-time hooks idempotent (required!)
3. Validate options early (at definition-time)
4. Pre-compute indexes during compilation
5. Handle errors gracefully in runtime hooks
6. Provide clear error messages
7. Test module in isolation

**Module Checklist:**
- [ ] Extends `ActiveSupport::Concern`
- [ ] Registers module with `register_module`
- [ ] Registers options with `register_option`
- [ ] Validates options in hooks
- [ ] Makes definition hooks idempotent
- [ ] Handles nil values gracefully
- [ ] Provides clear error messages
- [ ] Includes comprehensive tests
- [ ] Documents usage examples
- [ ] Checks for gem dependencies

**For Questions:** See source code of built-in modules in `lib/model_settings/modules/` for additional examples.
