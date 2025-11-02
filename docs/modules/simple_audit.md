# SimpleAudit Module

**Educational Example - NOT for Production Use**

---

## Purpose

This module is a **teaching tool** demonstrating Module Development API patterns, specifically:

1. **Callback Configuration API** - How to register and use configurable Rails callbacks
2. **Runtime Module Pattern** - How modules execute logic during model lifecycle
3. **Module Registration** - Proper module structure and registration
4. **Compile-time Indexing** - Building indexes during settings compilation
5. **Custom Options** - Registering and validating custom DSL options

**This is example code for learning.** Study the implementation in `lib/model_settings/modules/simple_audit.rb` to understand Module Development patterns.

---

## What This Module Demonstrates

### 1. Callback Configuration API (Sprint 11 Phase 3)

Shows how to register callback configuration:

```ruby
# In module
ModelSettings::ModuleRegistry.register_module_callback_config(
  :simple_audit,
  default_callback: :before_save,  # Default timing
  configurable: true               # Users can change this
)

# Get configured callback
callback_name = ModelSettings::ModuleRegistry.get_module_callback(:simple_audit)
send(callback_name, :audit_tracked_settings)  # Register Rails callback
```

**Demonstrates:**
- Registering default callback timing
- Allowing global configuration
- Using configured callback in module

### 2. Runtime Module Pattern

Shows how modules execute during model lifecycle:

```ruby
# Module executes at configured time (default: :before_save)
def audit_tracked_settings
  # Runtime logic runs here during save/validation/commit
  self.class.tracked_settings.each do |setting|
    # Check for changes, log to Rails.logger
  end
end
```

**Demonstrates:**
- Runtime execution (vs compile-time)
- Accessing model instance state
- Using Rails callbacks

### 3. Custom DSL Options

Shows how to register custom options:

```ruby
# Register option with validator
ModelSettings::ModuleRegistry.register_option(:track_changes) do |setting, value|
  unless [true, false].include?(value)
    raise ArgumentError, "track_changes must be true or false"
  end
end
```

**Usage:**
```ruby
setting :premium_mode,
        type: :column,
        track_changes: true  # Custom option
```

### 4. Compile-Time Indexing

Shows how to build indexes during compilation:

```ruby
ModelSettings::ModuleRegistry.on_settings_compiled do |settings, model_class|
  # Build index (idempotent)
  model_class._tracked_settings = settings.select do |s|
    s.track_changes == true
  end.map(&:name)
end
```

**Demonstrates:**
- Idempotent hook (safe for reloading)
- Pre-computing for fast runtime lookups
- Storing index in class attribute

### 5. Class and Instance Methods

Shows how to add methods to model:

```ruby
module ClassMethods
  def tracked_settings
    _tracked_settings.map { |name| find_setting(name) }.compact
  end

  def setting_tracked?(setting_name)
    _tracked_settings.include?(setting_name.to_sym)
  end
end
```

**Demonstrates:**
- Adding class methods via ClassMethods module
- Querying metadata
- Instance helper methods

---

## Example Usage (For Learning)

### Basic Setup

```ruby
class Account < ApplicationRecord
  include ModelSettings::DSL
  include ModelSettings::Modules::SimpleAudit

  setting :premium_mode,
          type: :column,
          track_changes: true  # Will be logged

  setting :display_name,
          type: :column
          # Not tracked by default
end
```

### Global Configuration

```ruby
# config/initializers/model_settings.rb
ModelSettings.configure do |config|
  # Change when audit logging runs
  config.module_callback(:simple_audit, :after_commit)
end
```

**Demonstrates callback configuration:**
- Default: `:before_save`
- Can be changed globally to `:before_validation`, `:after_save`, `:after_commit`

---

## DSL Options

### `track_changes`

Enable change tracking and logging for a setting.

**Type**: Boolean (`true` or `false`)
**Required**: No
**Default**: Not tracked (no logging)

```ruby
setting :premium_mode,
        type: :column,
        track_changes: true  # Enable logging
```

**Validation**: Must be `true` or `false` (raises `ArgumentError` otherwise)

---

## Class Methods

### `.tracked_settings`

Get all settings with change tracking enabled.

```ruby
Account.tracked_settings
# => [#<Setting name=:premium_mode ...>, #<Setting name=:api_access ...>]
```

**Returns**: Array of Setting objects

---

### `.setting_tracked?(setting_name)`

Check if a specific setting has change tracking enabled.

```ruby
Account.setting_tracked?(:premium_mode)  # => true
Account.setting_tracked?(:display_name)  # => false
```

**Parameters:**
- `setting_name` (Symbol) - Setting name to check

**Returns**: Boolean

---

## How It Works

### Architecture

```
┌─────────────────────────────────────────────────┐
│ 1. Class Loading (Compile-Time)                │
│    - Register module                             │
│    - Register :track_changes option              │
│    - Register callback configuration             │
│    - Build index of tracked settings             │
└─────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────┐
│ 2. Configuration (User Initializer)            │
│    - User sets preferred callback timing        │
│    ModelSettings.configure do |config|          │
│      config.module_callback(:simple_audit,      │
│                             :after_commit)       │
│    end                                           │
└─────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────┐
│ 3. Runtime (Model Instance Changes)            │
│    account.premium_mode = true                  │
│    account.save!                                │
│         ↓                                        │
│    [Configured callback fires]                  │
│         ↓                                        │
│    audit_tracked_settings method runs           │
│         ↓                                        │
│    Logs: premium_mode: false → true             │
└─────────────────────────────────────────────────┘
```

### Callback Registration

```ruby
# 1. Register callback configuration
ModelSettings::ModuleRegistry.register_module_callback_config(
  :simple_audit,
  default_callback: :before_save,  # Default timing
  configurable: true               # Allow user override
)

# 2. Get the active callback (checks global config or uses default)
callback_name = ModelSettings::ModuleRegistry.get_module_callback(:simple_audit)
# => :after_commit (if user configured it)
# => :before_save (default, if not configured)

# 3. Register Rails callback
send(callback_name, :audit_tracked_settings)
# Equivalent to: after_commit :audit_tracked_settings
```

### Logging Output

When a tracked setting changes, SimpleAudit logs to Rails logger:

```
[SimpleAudit] Account#42 - premium_mode: false → true
[SimpleAudit] Account#42 - api_access: false → true
```

**Log Format**: `[SimpleAudit] ModelClass#id - setting_name: old_value → new_value`

---

## Example: Complete Integration

```ruby
# config/initializers/model_settings.rb
ModelSettings.configure do |config|
  # Run audit after transaction commits (safe for logging)
  config.module_callback(:simple_audit, :after_commit)
end

# app/models/account.rb
class Account < ApplicationRecord
  include ModelSettings::DSL
  include ModelSettings::Modules::SimpleAudit

  setting :billing_enabled,
          type: :column,
          track_changes: true

  setting :api_quota,
          type: :column,
          track_changes: true

  setting :notes,
          type: :column,
          track_changes: false  # Internal notes, don't track
end

# Usage in controller
class AccountsController < ApplicationController
  def update
    @account = Account.find(params[:id])

    if @account.update(account_params)
      # Audit log automatically created during save
      # Check logs for: [SimpleAudit] Account#... - billing_enabled: false → true
      redirect_to @account, notice: "Account updated"
    else
      render :edit
    end
  end

  private

  def account_params
    params.require(:account).permit(:billing_enabled, :api_quota, :notes)
  end
end

# Query tracked settings
Account.tracked_settings.map(&:name)
# => [:billing_enabled, :api_quota]

Account.setting_tracked?(:billing_enabled)  # => true
Account.setting_tracked?(:notes)            # => false
```

---

## Design Decisions

### Why Separate from AuditTrail Example?

The complete `AuditTrail` example in `docs/guides/module_development.md` is comprehensive (200+ lines) and demonstrates many features. SimpleAudit is intentionally minimal (~120 lines) to focus on **one thing**: demonstrating the Callback Configuration API.

**SimpleAudit focuses on:**
- ✅ Callback configuration registration
- ✅ Using configured callback timing
- ✅ Runtime execution in Rails lifecycle
- ✅ Minimal, clear implementation

**AuditTrail example includes:**
- Advanced features (full state snapshots, detail levels)
- Database persistence (AuditLog model)
- Complex serialization logic
- Error handling strategies
- May be overwhelming for learning the callback API

### What SimpleAudit Intentionally Omits

To keep the example focused on Module Development patterns, SimpleAudit intentionally keeps things simple:

- **No database persistence** - Just logs to Rails.logger
- **No user tracking** - Doesn't track who made changes
- **Minimal error handling** - Just basic rescue
- **No query interface** - Can't retrieve history

**These are intentional** to keep the code short and focused on demonstrating Module Development API, not building a complete audit system.

---

## Comparison: Compile-Time vs Runtime Modules

### Compile-Time Module (Roles, Pundit, ActionPolicy)

```ruby
module ModelSettings::Modules::Roles
  def setting(name, **options, &block)
    # Intercepts setting definition to store metadata
    if options[:viewable_by]
      store_authorization_metadata(name, options[:viewable_by])
    end
    super  # Continue with normal setting definition
  end
end
```

**Characteristics:**
- ❌ No Rails callbacks needed
- ✅ Works at class loading time
- ✅ Stores metadata for later use
- ✅ Authorization happens in controller

### Runtime Module (SimpleAudit)

```ruby
module ModelSettings::Modules::SimpleAudit
  included do
    # Register callback to run during model lifecycle
    callback_name = get_module_callback(:simple_audit)
    send(callback_name, :audit_tracked_settings)
  end

  def audit_tracked_settings
    # Executes during save/validation/commit
    Rails.logger.info("Changes: #{changes}")
  end
end
```

**Characteristics:**
- ✅ Needs Rails callbacks
- ✅ Executes during model lifecycle
- ✅ Performs runtime actions (logging, notifications, etc.)
- ✅ Benefits from configurable callback timing

---

## Related Documentation

- [Module Development API](../guides/module_development.md) - Complete guide
- [Configuration](../core/configuration.md) - Global configuration options
- [Callbacks](../core/callbacks.md) - ModelSettings callback system
- [Roles Module](roles.md) - Example of compile-time module
- [Pundit Module](pundit.md) - Example of compile-time module

---

## Summary

**Educational Example** - Study the code to learn Module Development API

**What You Learn From This Module:**

1. **Callback Configuration API**
   - How to register callback configuration with defaults
   - How to make callback timing user-configurable
   - How to use configured callbacks in your module

2. **Runtime vs Compile-Time Patterns**
   - When modules need Rails callbacks (runtime logic)
   - When modules don't need callbacks (compile-time metadata)
   - How to execute logic during model lifecycle

3. **Module Structure**
   - Module registration with ModuleRegistry
   - Custom DSL options with validation
   - Class and instance methods
   - Compile-time indexing (idempotent hooks)

4. **Module Development Best Practices**
   - Pre-computing indexes for performance
   - Idempotent compilation hooks
   - Custom option validation
   - Clean API design

**Next Steps:**
- Read the implementation: `lib/model_settings/modules/simple_audit.rb`
- Study [Module Development Guide](../guides/module_development.md)
- Create your own runtime module using these patterns
