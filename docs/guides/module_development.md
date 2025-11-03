# Module Development API

This document defines the contract for creating external modules that extend ModelSettings functionality.

## Table of Contents

1. [Overview](#overview)
2. [Quick Start with Generator](#quick-start-with-generator)
3. [Module Structure](#module-structure)
4. [DSL Helpers](#dsl-helpers)
5. [ModuleRegistry API](#moduleregistry-api)
6. [Lifecycle Hooks](#lifecycle-hooks)
7. [Hook Execution Order](#hook-execution-order)
8. [Best Practices](#best-practices)
9. [Complete Example](#complete-example)
10. [Testing Modules](#testing-modules)

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

      # Module-level registrations (executed ONCE when module is loaded)

      # 1. Register module
      ModelSettings::ModuleRegistry.register_module(:my_module, self)

      # 2. Register as part of exclusive authorization group (optional)
      ModelSettings::ModuleRegistry.register_exclusive_group(:authorization, :my_module)

      # 3. Register custom DSL options with validators
      ModelSettings::ModuleRegistry.register_option(:my_option) do |setting, value|
        unless valid?(value)
          raise ArgumentError, "Invalid value for my_option: #{value}"
        end
      end

      # 4. Register lifecycle hooks to capture metadata
      ModelSettings::ModuleRegistry.on_setting_defined do |setting, model_class|
        # Only process settings for models that include THIS module
        next unless ModelSettings::ModuleRegistry.module_included?(:my_module, model_class)

        if setting.options.key?(:my_option)
          # Store metadata centrally using ModuleRegistry
          ModelSettings::ModuleRegistry.set_module_metadata(
            model_class,
            :my_module,
            setting.name,
            setting.options[:my_option]
          )
        end
      end

      included do
        # 5. Add to active modules FIRST (before conflict check)
        settings_add_module(:my_module) if respond_to?(:settings_add_module)

        # 6. Check for conflicts with other modules
        settings_check_exclusive_conflict!(:my_module) if respond_to?(:settings_check_exclusive_conflict!)
      end

      # Class methods added to model
      module ClassMethods
        def my_class_method
          # Retrieve metadata using DSL helper (recommended)
          metadata = get_module_metadata(:my_module)
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

## DSL Helpers

ModelSettings provides convenient DSL helpers that simplify module development. These helpers are available **only when `self` is a model class** (inside `ClassMethods` or `included do` blocks).

### Available Helpers

#### `get_module_metadata(module_name, setting_name = nil)`

Convenience wrapper around `ModuleRegistry.get_module_metadata`. Retrieves module-specific metadata.

```ruby
module ClassMethods
  def settings_with_audit
    # Short form (recommended in ClassMethods)
    all_metadata = get_module_metadata(:audit_trail)
    all_metadata.keys
  end

  def audit_level_for(setting_name)
    # Get metadata for specific setting
    get_module_metadata(:audit_trail, setting_name)
  end
end
```

**Parameters:**
- `module_name` (Symbol) - Name of the module
- `setting_name` (Symbol, optional) - Setting name (nil for all settings)

**Returns:**
- If `setting_name` provided: Metadata value or `nil`
- If `setting_name` omitted: Hash of `setting_name => metadata`

---

#### `module_metadata?(module_name, setting_name)`

Check if module has metadata for a setting.

```ruby
module ClassMethods
  def has_audit?(setting_name)
    module_metadata?(:audit_trail, setting_name)
  end
end
```

**Parameters:**
- `module_name` (Symbol) - Name of the module
- `setting_name` (Symbol) - Setting name

**Returns:** Boolean

---

#### `settings_check_exclusive_conflict!(module_name)`

Check for conflicts with other modules in the same exclusive group.

```ruby
included do
  # Add to active modules
  settings_add_module(:my_module) if respond_to?(:settings_add_module)

  # Check for conflicts (short form, recommended)
  settings_check_exclusive_conflict!(:my_module) if respond_to?(:settings_check_exclusive_conflict!)
end
```

**Parameters:**
- `module_name` (Symbol) - Module being checked

**Raises:** `ExclusiveGroupConflictError` if conflict detected

---

### When to Use Helpers vs. Direct ModuleRegistry Calls

✅ **Use DSL helpers** when:
- Inside `ClassMethods` (where `self` = model class)
- Inside `included do` blocks (where `self` = model class)
- Code is cleaner and easier to read

❌ **Use direct ModuleRegistry calls** when:
- At module level (outside `included do` or `ClassMethods`)
- Inside lifecycle hooks (`on_setting_defined`, `on_settings_compiled`)
- Working with a `model_class` parameter (not `self`)

**Example - When helpers are NOT available:**

```ruby
# Module-level registration - NO helpers available here
ModelSettings::ModuleRegistry.on_setting_defined do |setting, model_class|
  # Inside hook - must use direct calls with model_class parameter
  next unless ModelSettings::ModuleRegistry.module_included?(:my_module, model_class)

  ModelSettings::ModuleRegistry.set_module_metadata(
    model_class,  # Parameter, not self
    :my_module,
    setting.name,
    setting.options[:my_option]
  )
end
```

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
  # Direct API (works, but verbose)
  ModelSettings::ModuleRegistry.check_exclusive_conflict!(self, :my_module)

  # DSL helper (recommended in included do blocks - cleaner)
  settings_check_exclusive_conflict!(:my_module) if respond_to?(:settings_check_exclusive_conflict!)
end
```

**Parameters:**
- `model_class` (Class) - The model class including the module
- `module_name` (Symbol) - Module being included

**Raises:** `ExclusiveGroupConflictError` if a conflicting module is already included

**Note:** In `included do` blocks, prefer using the DSL helper `settings_check_exclusive_conflict!(:module_name)` over the direct ModuleRegistry call. The `respond_to?` check ensures compatibility when the module is included before DSL. See [DSL Helpers](#dsl-helpers) section.

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

#### `register_inheritable_option(option_name)`

Register an option as inheritable, allowing nested settings to automatically inherit it from parent settings.

```ruby
# In your module (at module level, outside included block)
ModelSettings::ModuleRegistry.register_inheritable_option(:viewable_by)
ModelSettings::ModuleRegistry.register_inheritable_option(:editable_by)
```

**Parameters:**
- `option_name` (Symbol) - Option name to register as inheritable

**Behavior:**
- Options registered this way are automatically added to the global inheritable options list
- Nested settings will inherit these options from their parents unless explicitly overridden
- ⚠️ **User can completely disable**: If user explicitly sets `config.inheritable_options = [...]`, your registration is **IGNORED**

**When to Use:**
Register options as inheritable when:
- The option represents authorization/permissions that should cascade to children
- The option represents metadata that logically applies to nested settings
- Users would expect child settings to inherit the option by default

**Example - Roles Module:**
```ruby
module ModelSettings
  module Modules
    module Roles
      # Register options
      ModelSettings::ModuleRegistry.register_option(:viewable_by) do |setting, value|
        unless value == :all || value.is_a?(Array)
          raise ArgumentError, "viewable_by must be :all or Array"
        end
      end

      ModelSettings::ModuleRegistry.register_option(:editable_by) do |setting, value|
        unless value == :all || value.is_a?(Array)
          raise ArgumentError, "editable_by must be :all or Array"
        end
      end

      # Register as inheritable (NEW in Phase 4)
      ModelSettings::ModuleRegistry.register_inheritable_option(:viewable_by)
      ModelSettings::ModuleRegistry.register_inheritable_option(:editable_by)

      # ... rest of module
    end
  end
end
```

**Usage in Models:**
```ruby
class Organization < ApplicationRecord
  include ModelSettings::DSL
  include ModelSettings::Modules::Roles

  setting :billing, viewable_by: [:admin, :finance] do
    setting :invoices  # Automatically inherits viewable_by: [:admin, :finance]
    setting :reports   # Automatically inherits viewable_by: [:admin, :finance]
  end
end
```

**⚠️ IMPORTANT: User Can Disable Your Module's Inheritance**

When user explicitly sets `inheritable_options`, your module's `register_inheritable_option` calls are **COMPLETELY IGNORED**:

```ruby
# In your module: you register your options
ModelSettings::ModuleRegistry.register_inheritable_option(:viewable_by)
ModelSettings::ModuleRegistry.register_inheritable_option(:editable_by)

# User explicitly sets inheritable options (REPLACES your registration)
ModelSettings.configure do |config|
  config.inheritable_options = [:authorize_with]  # ← Your options NOT included!
end

# Result: Option inheritance for your module WILL NOT WORK
# Child settings will NOT inherit :viewable_by or :editable_by
```

**This is by design** - users have full control over which options are inherited. Your module should:
- Document that inheritance is optional
- Work correctly even when inheritance is disabled
- Not assume nested settings will automatically inherit your options

**User has three choices:**

```ruby
# Choice 1: Auto-population (your module works automatically)
ModelSettings.configure do |config|
  # Don't set inheritable_options - modules auto-register
end

# Choice 2: Explicit inclusion (user manually includes your options)
ModelSettings.configure do |config|
  config.inheritable_options = [:viewable_by, :editable_by, :custom]  # ← User includes your options
end

# Choice 3: Disable inheritance (your module inheritance doesn't work)
ModelSettings.configure do |config|
  config.inheritable_options = [:custom]  # ← Your options NOT included
end
```

**Checking Registration:**
```ruby
ModelSettings::ModuleRegistry.inheritable_option?(:viewable_by)  # => true
ModelSettings::ModuleRegistry.registered_inheritable_options     # => Set[:viewable_by, :editable_by, :authorize_with]
```

**See Also:**
- [Configuration - inheritable_options](../core/configuration.md#inheritable_options) - User-facing configuration
- [Settings Inheritance](../core/inheritance.md) - How option inheritance works

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

### Centralized Metadata Storage

#### Why Module Metadata?

**The Problem:** Modules need to store processed data for query methods and runtime operations. But where should this data live?

When you create a module that adds custom DSL options (like `viewable_by: [:admin]`), you often need to:
1. **Process** the raw option value (normalize, validate, transform)
2. **Store** the processed result somewhere
3. **Query** it later (e.g., `User.settings_viewable_by(:admin)`)

Module Metadata provides a centralized, isolated storage solution for this processed data.

---

**❌ Alternative 1: Store in `setting.options` (User Namespace Pollution)**

```ruby
# Problem: Pollutes user's option namespace
setting.options[:viewable_by]              # Raw data: [:admin, :finance] or :all or "admin"
setting.options[:_viewable_by_normalized]  # ❌ Pollutes namespace with internal data!

# What if two modules process the same option differently?
setting.options[:_viewable_by_roles_normalized]    # Module A's version
setting.options[:_viewable_by_pundit_normalized]   # Module B's version
# 🔴 Namespace collision risk!
```

**Why it doesn't work:**
- Pollutes user-defined options with internal module data
- `setting.options` should contain raw DSL options, not processed results
- Risk of namespace collision between modules

---

**❌ Alternative 2: Store in Class Variables (Model Isolation Broken)**

```ruby
module Roles
  @@roles_data = {}  # ❌ Global state!

  def self.store_roles(model_class, setting, data)
    @@roles_data[model_class] ||= {}
    @@roles_data[model_class][setting] = data
  end
end

# Problem: Shared between ALL models
User.setting :billing, viewable_by: [:admin]
Post.setting :billing, viewable_by: [:editor]

Roles.@@roles_data  # => {User => {...}, Post => {...}}
# If you forget to check model_class → can accidentally read wrong model's data!
```

**Why it doesn't work:**
- No isolation between models (User vs Post)
- Memory leaks in development mode (references to reloaded classes)
- Thread-safety concerns

---

**❌ Alternative 3: Store in Instance Variables (Module Namespace Collision)**

```ruby
class User
  @roles_data = {...}         # From Roles module
  @pundit_data = {...}        # From Pundit module
  @i18n_data = {...}          # From I18n module
  @custom_module_data = {...} # From custom module
end

# Problems:
# 1. What if two modules use the same variable name?
# 2. How to cleanup when module is removed?
# 3. No standardized API for accessing data
```

**Why it doesn't work:**
- Risk of variable name collisions between modules
- No centralized cleanup mechanism
- Each module must invent its own storage pattern

---

**✅ Solution: Centralized Metadata Storage with Namespace Isolation**

```ruby
# Each module gets its own namespace in a centralized hash:
User._module_metadata = {
  roles: {                           # ← Namespace for Roles module
    billing: {viewable_by: [:admin, :finance], editable_by: [:admin]},
    profile: {viewable_by: [:user, :admin], editable_by: [:user]}
  },
  pundit: {                          # ← Namespace for Pundit module
    billing: {policy: "BillingPolicy"}
  },
  i18n: {                            # ← Namespace for I18n module
    billing: {locale: :en}
  }
}

# Complete isolation between models via class_attribute:
User._module_metadata   # ← Data only for User model
Post._module_metadata   # ← Data only for Post model (separate hash)

# No namespace collisions:
ModuleRegistry.get_module_metadata(User, :roles)   # Only Roles data
ModuleRegistry.get_module_metadata(User, :pundit)  # Only Pundit data
```

**Why it works:**
- ✅ **Namespace isolation**: Each module has its own key (`:roles`, `:pundit`, `:i18n`)
- ✅ **Model isolation**: Each model class has its own `_module_metadata` hash (via `class_attribute`)
- ✅ **Centralized API**: Standardized `get_module_metadata` / `set_module_metadata` methods
- ✅ **Clean separation**: User options in `setting.options`, processed data in Module Metadata

---

**Real Example: Roles Module Query Method**

Here's how the Roles module uses Module Metadata to power `settings_viewable_by(:admin)`:

```ruby
# STEP 1: User defines settings
class User < ApplicationRecord
  include ModelSettings::Modules::Roles

  setting :billing, viewable_by: [:admin, :finance]
  setting :profile, viewable_by: [:user, :admin]
end

# STEP 2: on_setting_defined hook processes and stores data
ModelSettings::ModuleRegistry.on_setting_defined do |setting, model_class|
  next unless ModelSettings::ModuleRegistry.module_included?(:roles, model_class)

  if setting.options.key?(:viewable_by)
    # Normalize raw data: :all, "admin", [:admin] → normalized array
    normalized = normalize_roles(setting.options[:viewable_by])

    # Store in Module Metadata (NOT in setting.options!)
    ModelSettings::ModuleRegistry.set_module_metadata(
      model_class,
      :roles,              # ← Module namespace
      setting.name,
      {viewable_by: normalized, editable_by: []}
    )
  end
end

# STEP 3: Query method uses Module Metadata
module ClassMethods
  def settings_viewable_by(role)
    # Retrieve ALL stored metadata for this module
    all_roles = get_module_metadata(:roles)
    # => {
    #   billing: {viewable_by: [:admin, :finance], editable_by: []},
    #   profile: {viewable_by: [:user, :admin], editable_by: []}
    # }

    # Filter by role
    all_roles.select do |_name, roles|
      roles[:viewable_by].include?(role.to_sym)
    end.keys
    # => [:billing, :profile]  (both viewable by :admin)
  end
end

# STEP 4: Application uses query method
User.settings_viewable_by(:admin)
# => [:billing, :profile]
```

**Key Distinction: Raw vs Processed Data**

```ruby
# RAW data (in setting.options - user input):
setting.options[:viewable_by]
# => [:admin, :finance]  OR  :all  OR  "admin"  (various formats)

# PROCESSED data (in Module Metadata - normalized by module):
ModuleRegistry.get_module_metadata(User, :roles, :billing)[:viewable_by]
# => [:admin, :finance]  (always Array<Symbol> or :all)
```

Modules cannot store processed data in `setting.options` because:
1. It would pollute the user's option namespace
2. `setting.options` is for raw DSL input, not normalized results
3. Multiple modules might process the same option differently

---

**When to Use Module Metadata**

✅ **Use Module Metadata when you need to:**
- Store processed/normalized option values
- Build indexes for fast runtime queries (e.g., `settings_viewable_by(:admin)`)
- Cache expensive computations done at definition-time
- Provide query methods in `ClassMethods` that filter settings by option values

❌ **Don't use Module Metadata for:**
- Reading raw user input (use `setting.options[:my_option]` instead)
- Temporary runtime state (use instance variables)
- Inter-module communication (modules should be isolated)

---

#### `set_module_metadata(model_class, module_name, setting_name, metadata)`

Store module-specific metadata for a setting in centralized storage.

```ruby
ModelSettings::ModuleRegistry.set_module_metadata(
  User,
  :roles,
  :billing_override,
  { viewable_by: [:admin, :finance], editable_by: [:admin] }
)
```

**Parameters:**
- `model_class` (Class) - The model class
- `module_name` (Symbol) - Module identifier
- `setting_name` (Symbol) - Setting name
- `metadata` (Object) - Metadata value to store (any object)

**Use Case:** Store module-specific data during `on_setting_defined` hooks.

**Best Practice:** Use this in your `on_setting_defined` hook to capture option values:

```ruby
ModelSettings::ModuleRegistry.on_setting_defined do |setting, model_class|
  next unless ModelSettings::ModuleRegistry.module_included?(:my_module, model_class)

  if setting.options.key?(:my_option)
    ModelSettings::ModuleRegistry.set_module_metadata(
      model_class,
      :my_module,
      setting.name,
      setting.options[:my_option]
    )
  end
end
```

---

#### `get_module_metadata(model_class, module_name, setting_name = nil)`

Retrieve module-specific metadata from centralized storage.

```ruby
# Get metadata for specific setting
roles = ModelSettings::ModuleRegistry.get_module_metadata(User, :roles, :billing_override)
# => { viewable_by: [:admin, :finance], editable_by: [:admin] }

# Get all metadata for a module
all_roles = ModelSettings::ModuleRegistry.get_module_metadata(User, :roles)
# => { billing_override: {...}, api_access: {...} }
```

**Parameters:**
- `model_class` (Class) - The model class
- `module_name` (Symbol) - Module identifier
- `setting_name` (Symbol, optional) - Setting name (omit to get all settings)

**Returns:**
- If `setting_name` provided: Metadata value or `nil`
- If `setting_name` omitted: Hash of `setting_name => metadata`

**Use Case:** Query methods in ClassMethods that need to access stored metadata.

**Example - Query Method:**

```ruby
module ClassMethods
  # Get all settings with specific option value
  def settings_with_my_option(value)
    # Direct API (works, but verbose)
    all_metadata = ModelSettings::ModuleRegistry.get_module_metadata(self, :my_module)

    # DSL helper (recommended in ClassMethods - cleaner)
    all_metadata = get_module_metadata(:my_module)

    all_metadata.select { |name, data| data == value }.keys
  end
end
```

**Note:** In `ClassMethods`, prefer using the DSL helper `get_module_metadata(:module_name)` over the direct ModuleRegistry call. See [DSL Helpers](#dsl-helpers) section.

---

#### `module_metadata?(model_class, module_name, setting_name)`

Check if module has metadata for a setting.

```ruby
if ModelSettings::ModuleRegistry.module_metadata?(User, :roles, :billing_override)
  # Module has stored metadata for this setting
end
```

**Parameters:**
- `model_class` (Class) - The model class
- `module_name` (Symbol) - Module identifier
- `setting_name` (Symbol) - Setting name

**Returns:** Boolean

---

### Callback Configuration

#### When to Use Callback Configuration

The Callback Configuration API is designed for modules that need to execute **runtime logic** during the Rails model lifecycle (save, validation, commit, etc.).

**✅ USE Callback Configuration for modules with runtime logic:**

Module types that should use callback configuration:
- **Audit logging** - Log changes during save/commit
- **Workflow** - State machine transitions during lifecycle
- **Notifications** - Send alerts after changes
- **Validation** - Custom validation logic at specific timing
- **Data synchronization** - Synchronize with external systems

These module types need to run code when model instances change, so they benefit from configurable callback timing.

**Example**: The included `SimpleAudit` module demonstrates proper usage.

**❌ DON'T USE Callback Configuration for compile-time only modules:**

- **Authorization modules** (Roles, Pundit, ActionPolicy)
  - These only store metadata at definition time (during `setting` call)
  - Authorization happens in **controller** via policy, NOT in model
  - They intercept the `setting()` DSL method to capture options
  - No runtime validation in model callbacks

- **I18n** - Only stores translation keys at definition time
- **Documentation** - Only generates docs at compilation time

These modules work during class loading and don't need to execute during model lifecycle.

**Key Distinction:**

```ruby
# Compile-time module (no callbacks needed):
module ModelSettings::Modules::Roles
  # Register hook to capture metadata at definition time
  ModelSettings::ModuleRegistry.on_setting_defined do |setting, model_class|
    next unless ModelSettings::ModuleRegistry.module_included?(:roles, model_class)

    if setting.options.key?(:viewable_by) || setting.options.key?(:editable_by)
      # Store metadata centrally
      metadata = {
        viewable_by: Array(setting.options[:viewable_by]),
        editable_by: Array(setting.options[:editable_by])
      }
      ModelSettings::ModuleRegistry.set_module_metadata(
        model_class, :roles, setting.name, metadata
      )
    end
  end
end

# Runtime module (needs callbacks):
module ModelSettings::Modules::AuditTrail
  included do
    # Register callback to run during model lifecycle
    callback_name = get_module_callback(:audit_trail)
    send(callback_name, :log_setting_changes)
  end

  def log_setting_changes
    # Executes during save/validation/commit
    AuditLog.create!(changes: changes)
  end
end
```

**Current Authorization Architecture:**

Authorization happens in the **controller**, not the model. Authorization modules work differently depending on which framework you use:

**Pundit:**
```ruby
class UsersController < ApplicationController
  def update
    @user = User.find(params[:id])
    authorize @user
    @user.update(permitted_attributes(@user))  # Standard Pundit
  end
end
```

**ActionPolicy:**
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

The model itself doesn't validate authorization - it just stores the metadata that the controller/policy uses.

**See Also:** [Policy-Based Authorization](../modules/policy_based/README.md), [Pundit Module](../modules/policy_based/pundit.md), [ActionPolicy Module](../modules/policy_based/action_policy.md)

---

#### `register_module_callback_config(module_name, default_callback:, configurable:)`

Register callback configuration for a module (Sprint 11 Phase 3).

Allows modules to declare which Rails callback they use by default and whether users can change it via global configuration.

```ruby
ModelSettings::ModuleRegistry.register_module_callback_config(
  :pundit,
  default_callback: :before_validation,
  configurable: true
)
```

**Parameters:**
- `module_name` (Symbol) - Module identifier
- `default_callback` (Symbol) - Default Rails callback (e.g., `:before_validation`, `:before_save`)
- `configurable` (Boolean) - Whether callback can be changed via `ModelSettings.configure`

**Use Case:** Modules that need to run during Rails model lifecycle can register their preferred callback timing. Users can then globally configure when the module runs if `configurable: true`.

**Example - Module Registration:**
```ruby
module ModelSettings
  module Modules
    module Pundit
      extend ActiveSupport::Concern

      included do
        # Register module
        ModelSettings::ModuleRegistry.register_module(:pundit, self)

        # Register callback configuration
        ModelSettings::ModuleRegistry.register_module_callback_config(
          :pundit,
          default_callback: :before_validation,  # Run before validation by default
          configurable: true                      # Allow users to change this
        )

        # Use the configured callback
        callback_name = ModelSettings::ModuleRegistry.get_module_callback(:pundit)
        send(callback_name, :validate_authorization_settings)
      end

      def validate_authorization_settings
        # Module logic runs at the configured time
      end
    end
  end
end
```

**Example - User Configuration:**
```ruby
# config/initializers/model_settings.rb
ModelSettings.configure do |config|
  # Change when Pundit module runs (if module allows it)
  config.module_callback(:pundit, :before_save)
end
```

---

#### `get_module_callback_config(module_name)`

Get registered callback configuration for a module.

```ruby
config = ModelSettings::ModuleRegistry.get_module_callback_config(:pundit)
# => { default_callback: :before_validation, configurable: true }
```

**Parameters:**
- `module_name` (Symbol) - Module identifier

**Returns:** Hash with `:default_callback` and `:configurable` keys, or `nil` if not registered

---

#### `get_module_callback(module_name)`

Get the active callback for a module (checks global config first, falls back to default).

```ruby
callback = ModelSettings::ModuleRegistry.get_module_callback(:pundit)
# => :before_save (if configured), or :before_validation (default)
```

**Parameters:**
- `module_name` (Symbol) - Module identifier

**Returns:** Symbol (callback name) or `nil` if module not registered

**Behavior:**
1. Checks if globally configured via `ModelSettings.configure`
2. If configured and module is `configurable: true`, returns configured callback
3. If configured but module is `configurable: false`, raises `ArgumentError`
4. Otherwise returns `default_callback`

**Example:**
```ruby
# Module registered with configurable: false
ModelSettings::ModuleRegistry.register_module_callback_config(
  :strict_module,
  default_callback: :before_validation,
  configurable: false  # Cannot be changed
)

# Attempt to configure it globally
ModelSettings.configure do |config|
  config.module_callback(:strict_module, :before_save)
end

# Raises ArgumentError when accessed
ModelSettings::ModuleRegistry.get_module_callback(:strict_module)
# => ArgumentError: Module :strict_module does not allow callback configuration
```

---

#### `module_callback_configs()`

Get all registered module callback configurations.

```ruby
configs = ModelSettings::ModuleRegistry.module_callback_configs
# => {
#      pundit: { default_callback: :before_validation, configurable: true },
#      roles: { default_callback: :before_save, configurable: false }
#    }
```

**Returns:** Hash of module name => config hash

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

Here's a complete example module demonstrating audit trail functionality.

**Note**: This is example/demonstration code for learning module development. Study `SimpleAudit` (included) and this example to understand Module Development patterns.

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

      # Module-level registrations

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

      # 3. Hook to capture audit_log metadata
      ModelSettings::ModuleRegistry.on_setting_defined do |setting, model_class|
        next unless ModelSettings::ModuleRegistry.module_included?(:audit_trail, model_class)

        if setting.options.key?(:audit_log)
          # Store metadata centrally
          ModelSettings::ModuleRegistry.set_module_metadata(
            model_class,
            :audit_trail,
            setting.name,
            setting.options[:audit_log]
          )

          # Definition-time validation
          if setting.type == :store_model && setting.options[:audit_log] == :full
            Rails.logger.warn(
              "Setting #{setting.name}: :full audit logging for StoreModel may " \
              "produce large logs. Consider using :changes_only."
            )
          end
        end
      end

      # 4. Runtime logging hook
      ModelSettings::ModuleRegistry.after_setting_change do |instance, setting, old_value, new_value|
        audit_level = ModelSettings::ModuleRegistry.get_module_metadata(
          instance.class,
          :audit_trail,
          setting.name
        )

        next unless audit_level && audit_level != :none

        begin
          log_entry = {
            model_class: instance.class.name,
            model_id: instance.id,
            setting_name: setting.name,
            old_value: old_value.to_s,
            new_value: new_value.to_s,
            changed_at: Time.current
          }

          # Include full state for :full audit level
          if audit_level == :full
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

      included do
        # 5. Add to active modules FIRST
        settings_add_module(:audit_trail) if respond_to?(:settings_add_module)
      end

      # Class methods
      module ClassMethods
        # Get all settings with audit logging enabled
        #
        # @return [Array<Setting>] Settings with audit_log != :none
        def audited_settings
          # Use DSL helper (recommended in ClassMethods)
          all_audit_metadata = get_module_metadata(:audit_trail)
          setting_names = all_audit_metadata.select { |_name, level| level && level != :none }.keys
          setting_names.map { |name| find_setting(name) }.compact
        end

        # Check if a setting is audited
        #
        # @param setting_name [Symbol] Setting name
        # @return [Boolean]
        def setting_audited?(setting_name)
          # Use DSL helper (recommended in ClassMethods)
          audit_level = get_module_metadata(:audit_trail, setting_name.to_sym)
          audit_level.present? && audit_level != :none
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

**Example Usage** (if this module were implemented):

```ruby
class Account < ApplicationRecord
  include ModelSettings::DSL
  include ModelSettings::Modules::AuditTrail  # Example only - not included

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
- [Pundit Module](../modules/policy_based/pundit.md) - Reference implementation
- [ActionPolicy Module](../modules/policy_based/action_policy.md) - Reference implementation
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
