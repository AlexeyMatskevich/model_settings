# Module Development Guide

Learn how to create custom modules that extend ModelSettings with new functionality.

## Table of Contents

1. [Overview](#overview)
2. [Learn by Example: AuditTrail Module](#learn-by-example-audittrail-module)
3. [Lifecycle Hooks](#lifecycle-hooks)
4. [Advanced Topics](#advanced-topics)
5. [Best Practices](#best-practices)
6. [Creating Your Own Module](#creating-your-own-module)
7. [Testing Modules](#testing-modules)
8. [API Reference](#api-reference)

---

## Overview

ModelSettings provides a comprehensive Module Development API that allows you to create custom modules extending the DSL with new options, behaviors, and lifecycle hooks.

**What You Can Do:**
- Add custom DSL options (e.g., `audit_level:`, `notify:`)
- Hook into setting lifecycle (definition, compilation, runtime changes)
- Store module-specific metadata per setting
- Add class and instance methods to models
- Configure inheritable options for nested settings
- Define mutually exclusive module groups (e.g., authorization)

**Built-in Modules** (reference implementations):
- `Roles` - Simple RBAC authorization ([docs](../modules/roles.md))
- `Pundit` - Pundit integration ([docs](../modules/policy_based/pundit.md))
- `ActionPolicy` - ActionPolicy integration ([docs](../modules/policy_based/action_policy.md))
- `I18n` - Internationalization ([docs](../modules/i18n.md))

**Learning Approach:**

This guide uses a **teaching-first approach**: we'll walk through a complete, working example (the AuditTrail module) step-by-step, then dive into the details of each API feature.

---

## Learn by Example: AuditTrail Module

The best way to understand module development is to study a complete example. We'll walk through the **AuditTrail** module, which adds audit logging to settings.

### What the Example Does

The AuditTrail module logs all changes to settings in an audit log:

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL
  include ModelSettings::Modules::AuditTrail

  setting :premium,
    type: :column,
    audit_level: :detailed,              # Custom option
    audit_user: ->(user) { Current.user } # Callable option
end

user.premium = true
# → Creates audit log entry: "premium: false → true" with user info
```

**Example Files:**
- 📄 **Implementation**: [`examples/custom_module/audit_trail.rb`](../../examples/custom_module/audit_trail.rb) (300 lines)
- 📋 **Usage Guide**: [`examples/custom_module/README.md`](../../examples/custom_module/README.md)
- ✅ **Tests**: [`examples/custom_module/audit_trail_spec.rb`](../../examples/custom_module/audit_trail_spec.rb) (200+ tests)

---

### Module Anatomy: 7 Steps

Let's break down how AuditTrail is built, step by step. Each step demonstrates a key aspect of the Module Development API.

---

#### Step 1: Register the Module

```ruby
# From audit_trail.rb:30-33
included do
  ModuleRegistry.register_module(:audit_trail, self)
end
```

**What this does**: Registers the `:audit_trail` identifier with the ModuleRegistry.

**Why it matters**:
- Enables global configuration via `ModelSettings.configure`
- Tracks which modules are active on each model
- Allows introspection (`ModuleRegistry.module_registered?(:audit_trail)`)

**Key method**: [`ModuleRegistry.register_module`](../core/module_registry.md#register_module)

---

#### Step 2: Register Custom DSL Options

```ruby
# From audit_trail.rb:35-42
ModuleRegistry.register_option(:audit_level) do |value, setting, model_class|
  unless [:minimal, :detailed].include?(value)
    raise ArgumentError, "audit_level must be :minimal or :detailed, got #{value.inspect}"
  end
end

ModuleRegistry.register_option(:audit_user) do |value, setting, model_class|
  unless value.nil? || value.respond_to?(:call)
    raise ArgumentError, "audit_user must be a callable (Proc/Lambda), got #{value.class}"
  end
end
```

**What this does**: Adds `audit_level:` and `audit_user:` options to the `setting` DSL.

**Usage:**
```ruby
setting :premium,
  audit_level: :detailed,                    # ✅ Valid
  audit_user: ->(instance) { Current.user }  # ✅ Valid

setting :premium, audit_level: :invalid      # ❌ Raises ArgumentError
setting :premium, audit_user: "not callable" # ❌ Raises ArgumentError
```

**Pattern**: **Validate early** - catch configuration errors at definition-time (class loading), not runtime.

**Key method**: [`ModuleRegistry.register_option`](../core/module_registry.md#register_option)

#### Validator Signature: 3 Parameters

**IMPORTANT**: Validators receive **3 parameters** in this specific order:

```ruby
ModuleRegistry.register_option(:my_option) do |value, setting, model_class|
  # value: The actual value passed (e.g., :detailed, [:admin, :manager], etc.)
  # setting: The Setting object being defined
  # model_class: The model class (e.g., User, Account)
end
```

**Parameter Order: `|value, setting, model_class|`**

**Common Use Cases:**

```ruby
# 1. Validate value only (most common)
ModuleRegistry.register_option(:audit_level) do |value, setting, model_class|
  unless [:minimal, :detailed].include?(value)
    raise ArgumentError, "audit_level must be :minimal or :detailed"
  end
end

# 2. Use setting context in validation
ModuleRegistry.register_option(:sync_from) do |value, setting, model_class|
  unless model_class.find_setting(value)
    raise ArgumentError,
      "sync_from references unknown setting: #{value}. " \
      "Available settings: #{model_class.settings.map(&:name).join(', ')}"
  end
end

# 3. Use model_class for validation
ModuleRegistry.register_option(:authorize_with) do |value, setting, model_class|
  unless value.is_a?(Symbol)
    policy_type = (model_class.name.include?("ActionPolicy")) ? "rule" : "method"
    raise ArgumentError,
      "authorize_with must be a Symbol pointing to a policy #{policy_type}"
  end
end
```

**Why 3 parameters?**
- `value` - What you're validating
- `setting` - Context about the setting being defined (name, parent, options)
- `model_class` - Context about the model (check other settings, config, etc.)

---

#### Step 3: Capture Metadata with Lifecycle Hooks

```ruby
# From audit_trail.rb:80-95
ModuleRegistry.on_setting_defined do |setting, model_class|
  # Only process settings for models that include THIS module
  next unless ModuleRegistry.module_included?(:audit_trail, model_class)

  if setting.options[:audit_level]
    # Store metadata centrally
    ModuleRegistry.set_module_metadata(
      model_class,
      :audit_trail,
      setting.name,
      {
        level: setting.options[:audit_level],
        user_callable: setting.options[:audit_user],
        audit_if: setting.options[:audit_if]
      }
    )
  end
end
```

**What this does**: Captures audit configuration when each setting is defined and stores it centrally.

**When it runs**: Definition-time (during class loading, when `setting :premium, ...` is called)

**Why centralized storage**: The ModuleRegistry provides a single place to store all module-specific metadata, avoiding `class_attribute` pollution.

**Key methods**:
- [`ModuleRegistry.on_setting_defined`](../core/module_registry.md#on_setting_defined)
- [`ModuleRegistry.set_module_metadata`](../core/module_registry.md#set_module_metadata)

---

#### Step 4: Register Inheritable Options

```ruby
# From audit_trail.rb:60-65
ModuleRegistry.register_inheritable_option(
  :audit_level,
  merge_strategy: :replace,
  auto_include: true
)
```

**What this does**: Makes `audit_level` inherit to nested settings.

**Example:**
```ruby
setting :billing, audit_level: :detailed do
  setting :invoices, type: :column   # Inherits audit_level: :detailed
  setting :reports, type: :column    # Inherits audit_level: :detailed
end
```

**Why it matters**: Reduces repetition for deeply nested settings.

**Key method**: [`ModuleRegistry.register_inheritable_option`](../core/module_registry.md#register_inheritable_option)

**See also**: [Advanced Topics: Inheritable Options](#inheritable-options) for merge strategies.

---

#### Step 5: Configure Callback Timing

```ruby
# From audit_trail.rb:67-72
ModuleRegistry.register_module_callback_config(
  :audit_trail,
  default_callback: :after_save,
  configurable: true
)
```

**What this does**: Declares that AuditTrail runs at `:after_save` by default, but users can configure it globally.

**Global configuration:**
```ruby
# config/initializers/model_settings.rb
ModelSettings.configure do |config|
  config.module_callback(:audit_trail, :after_commit)  # Run after transaction
end
```

**Why it matters**: Some modules need to execute during Rails lifecycle (save, validation, commit). This makes timing configurable without code changes.

**Key method**: [`ModuleRegistry.register_module_callback_config`](../core/module_registry.md#register_module_callback_config)

**See also**: [Advanced Topics: Callback Configuration](#callback-configuration)

---

#### Step 6: Add Runtime Behavior

```ruby
# From audit_trail.rb:120-145
ModuleRegistry.after_setting_change do |instance, setting, old_value, new_value|
  # Get audit configuration for this setting
  meta = ModuleRegistry.get_module_metadata(
    instance.class,
    :audit_trail,
    setting.name
  )

  next unless meta  # Skip if not audited

  # Check condition
  if meta[:audit_if]
    next unless meta[:audit_if].call(instance)
  end

  # Create audit log
  AuditLog.create!(
    model: instance,
    setting: setting.name.to_s,
    old_value: meta[:level] == :detailed ? old_value : nil,
    new_value: meta[:level] == :detailed ? new_value : nil,
    level: meta[:level].to_s,
    user: meta[:user_callable]&.call(instance),
    created_at: Time.current
  )
end
```

**What this does**: Logs changes to audited settings after they're saved.

**When it runs**: Runtime (after setting value changes)

**Pattern**:
- Check metadata to see if this setting is audited
- Respect conditional auditing (`audit_if`)
- Handle both `:minimal` (no values) and `:detailed` (with values) levels

**Key method**: [`ModuleRegistry.after_setting_change`](../core/module_registry.md#after_setting_change)

---

#### Step 7: Add Query Methods

```ruby
# From audit_trail.rb:165-200
module ClassMethods
  def audited_settings
    # Get all settings with audit metadata
    all_metadata = get_module_metadata(:audit_trail)
    setting_names = all_metadata.keys
    setting_names.map { |name| find_setting(name) }.compact
  end

  def audit_config_for(setting_name)
    get_module_metadata(:audit_trail, setting_name)
  end
end

# Instance methods
def audited?(setting_name)
  self.class.audit_config_for(setting_name).present?
end

def audit_history(setting_name)
  AuditLog.where(
    model: self,
    setting: setting_name.to_s
  ).order(created_at: :desc)
end
```

**What this does**: Adds convenience methods to query which settings are audited and retrieve history.

**Usage:**
```ruby
User.audited_settings.map(&:name)  # => [:premium, :billing_enabled]
user.audited?(:premium)             # => true
user.audit_history(:premium)        # => [#<AuditLog ...>, ...]
```

**Key method**: [`ModuleRegistry.register_query_method`](../core/module_registry.md#register_query_method) (optional, for introspection API)

---

### Key Takeaways from the Example

The AuditTrail module demonstrates:

✅ **Custom DSL options** with validation (`audit_level:`, `audit_user:`)
✅ **Lifecycle hooks** to capture metadata and implement runtime behavior
✅ **Centralized metadata storage** using ModuleRegistry
✅ **Inheritable options** to reduce repetition in nested settings
✅ **Configurable callbacks** for flexible Rails integration
✅ **Query methods** for introspection and convenience
✅ **Complete example** with tests, docs, and database integration

**Next**: Let's dive into each API feature in detail.

---

## Lifecycle Hooks

Modules can hook into four lifecycle events. Understanding when and how to use each hook is crucial for effective module development.

### Hook Overview

| Hook | When | Idempotent? | Can Raise? | Use Cases |
|------|------|-------------|------------|-----------|
| `on_setting_defined` | Definition-time | ✅ Required | ✅ Yes | Validate options, store metadata |
| `on_settings_compiled` | Definition-time | ✅ Required | ✅ Yes | Build indexes, cross-setting validation |
| `before_setting_change` | Runtime | ⚠️ Recommended | ✅ Yes | Authorization, validation |
| `after_setting_change` | Runtime | ⚠️ Recommended | ⚠️ Catch & log | Audit logging, notifications |

---

### 1. `on_setting_defined`

Called immediately after each setting is defined.

```ruby
ModuleRegistry.on_setting_defined do |setting, model_class|
  # setting: Setting object just created
  # model_class: The model class defining the setting (e.g., User)

  if setting.options[:my_option]
    # Validate, store metadata, compute derived values
  end
end
```

**When**: Definition-time (during `setting` method call)
**Idempotency**: ✅ **REQUIRED** - Hook may run multiple times in development due to Rails code reloading
**Can raise**: ✅ Yes - raising aborts class loading with clear error

**Use Cases:**
- Validate custom options (fail fast at definition-time)
- Store option values in centralized metadata
- Compute derived metadata
- Raise errors for invalid configurations

**Example from AuditTrail:**
```ruby
on_setting_defined do |setting, model_class|
  next unless ModuleRegistry.module_included?(:audit_trail, model_class)

  if setting.options[:audit_level]
    # Store for later use
    ModuleRegistry.set_module_metadata(
      model_class,
      :audit_trail,
      setting.name,
      {level: setting.options[:audit_level]}
    )
  end
end
```

**Best Practice**: Always check `module_included?` to only process settings from models that include your module.

---

### 2. `on_settings_compiled`

Called after all settings are defined and adapters are set up.

```ruby
ModuleRegistry.on_settings_compiled do |settings, model_class|
  # settings: Array of ALL Setting objects (including nested)
  # model_class: The model class

  # Build indexes, validate cross-setting relationships
end
```

**When**: Definition-time (after class loading completes, before first use)
**Idempotency**: ✅ **REQUIRED** - Hook may run multiple times in development
**Can raise**: ✅ Yes - raising aborts class loading with clear error

**Use Cases:**
- Build indexes for fast runtime lookups
- Validate relationships across multiple settings
- Pre-compute expensive operations
- Set up cross-setting dependencies

**Example - Building an index:**
```ruby
on_settings_compiled do |settings, model_class|
  # IMPORTANT: Clear previous data for idempotency
  model_class._audit_index = {}

  settings.each do |setting|
    if ModuleRegistry.module_metadata?(model_class, :audit_trail, setting.name)
      model_class._audit_index[setting.name] = true
    end
  end
end
```

**⚠️ Idempotency Pattern**: Always clear/reset data structures before building them.

```ruby
# ✅ CORRECT - Idempotent
model_class._my_index = {}  # Clear first

# ❌ WRONG - Not idempotent (accumulates duplicates)
model_class._my_index ||= {}  # Keeps old data
```

---

### 3. `before_setting_change`

Called before a setting value changes.

```ruby
ModuleRegistry.before_setting_change do |instance, setting, new_value|
  # instance: Model instance (e.g., user)
  # setting: Setting object
  # new_value: The new value being set

  # Authorization checks, validation, etc.
  # Raising an exception aborts the change
end
```

**When**: Runtime (before value assignment)
**Idempotency**: ⚠️ Recommended (handle multiple calls gracefully)
**Can raise**: ✅ Yes - raising **aborts the change**

**Use Cases:**
- Authorization checks (e.g., Pundit, Roles modules)
- Pre-change validation
- Conditional logic before changes
- Rate limiting

**Example - Authorization:**
```ruby
before_setting_change do |instance, setting, new_value|
  # Get authorization metadata
  required_role = ModuleRegistry.get_module_metadata(
    instance.class,
    :roles,
    setting.name
  )

  if required_role && !instance.has_role?(required_role)
    raise UnauthorizedError,
          "User #{instance.id} cannot change '#{setting.name}'. " \
          "Required role: #{required_role}"
  end
end
```

**Pattern**: Raise descriptive errors with context (user ID, setting name, required role).

---

### 4. `after_setting_change`

Called after a setting value changes.

```ruby
ModuleRegistry.after_setting_change do |instance, setting, old_value, new_value|
  # instance: Model instance
  # setting: Setting object
  # old_value: Previous value
  # new_value: New value

  # Audit logging, notifications, webhooks, analytics
end
```

**When**: Runtime (after value assignment)
**Idempotency**: ⚠️ Recommended (should handle duplicate calls gracefully)
**Cannot raise**: ⚠️ **Catch exceptions** - change already happened, don't crash application

**Use Cases:**
- Audit logging (e.g., AuditTrail module)
- Notifications (email, Slack, webhooks)
- Analytics tracking
- Side effects (update related records)

**Example from AuditTrail:**
```ruby
after_setting_change do |instance, setting, old_value, new_value|
  meta = ModuleRegistry.get_module_metadata(
    instance.class,
    :audit_trail,
    setting.name
  )

  next unless meta

  begin
    AuditLog.create!(
      model: instance,
      setting: setting.name.to_s,
      old_value: old_value,
      new_value: new_value,
      level: meta[:level],
      created_at: Time.current
    )
  rescue => e
    # Don't crash the application if audit logging fails
    Rails.logger.error("Failed to create audit log: #{e.message}")
  end
end
```

**⚠️ Error Handling**: Always wrap in `begin/rescue` to catch and log exceptions. The setting change has already happened - don't let logging failures crash the app.

---

### Hook Execution Order

#### Definition-Time (Class Loading)

```
1. Model includes ModelSettings::DSL
   ↓
2. Model includes custom module(s)
   ↓
3. For each `setting :name, ...` call:
   a. Create Setting object
   b. Validate registered options
   c. Execute ALL on_setting_defined hooks (order: registration order)
   d. Setup storage adapter
   ↓
4. After class loading completes:
   ModelSettings::DSL.compile_settings! is called
   a. Execute ALL on_settings_compiled hooks (order: registration order)
   b. Mark settings as compiled
```

**⚠️ Idempotency Note**: Steps 3-4 repeat in development due to Rails code reloading.

---

#### Runtime (Setting Value Changes)

```
1. User calls setter: instance.premium = true
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

**Hook Order**: Hooks execute in the order they were registered (first registered = first executed).

---

## Advanced Topics

### Inheritable Options

Make options automatically inherit to nested settings.

```ruby
# Register as inheritable
ModuleRegistry.register_inheritable_option(
  :audit_level,
  merge_strategy: :replace,  # or :append, :merge
  auto_include: true
)
```

**Usage:**
```ruby
setting :billing, audit_level: :detailed do
  setting :invoices, type: :column   # Inherits audit_level: :detailed
  setting :reports, type: :column    # Inherits audit_level: :detailed
  setting :exports, type: :column, audit_level: :minimal  # Override
end
```

**Merge Strategies:**

| Strategy | Use For | Behavior | Example |
|----------|---------|----------|---------|
| `:replace` | Scalar values | Child value completely replaces parent | `:detailed` → `:minimal` |
| `:append` | Arrays | Concatenates arrays: `parent + child` | `[:admin]` + `[:manager]` = `[:admin, :manager]` |
| `:merge` | Hashes | Deep merges hashes: `parent.deep_merge(child)` | `{a: 1}` + `{b: 2}` = `{a: 1, b: 2}` |

**Detailed Examples:**

```ruby
# ============================================================================
# Strategy 1: :replace (default) - For scalar values
# ============================================================================
# Use when: Values are simple scalars (symbols, strings, integers) that should
#           completely replace parent values
# Example from: Roles module (:inherit_authorization)

register_inheritable_option(:audit_level, merge_strategy: :replace)

setting :parent, audit_level: :detailed do
  setting :child1                           # audit_level = :detailed (inherited)
  setting :child2, audit_level: :minimal    # audit_level = :minimal (replaced)
end

# ============================================================================
# Strategy 2: :append - For arrays
# ============================================================================
# Use when: Child should ADD to parent's list, not replace it
# Example from: Roles module (:viewable_by, :editable_by)

register_inheritable_option(:viewable_by, merge_strategy: :append)

setting :parent, viewable_by: [:admin] do
  setting :child1                              # viewable_by = [:admin] (inherited)
  setting :child2, viewable_by: [:manager]     # viewable_by = [:admin, :manager] (appended)
  setting :child3, viewable_by: [:guest]       # viewable_by = [:admin, :guest] (appended)
end

# Real-world use case: Progressive authorization
# Parent grants admin access, children ADD manager/guest without losing admin
setting :billing, viewable_by: [:admin] do
  setting :invoices, viewable_by: [:finance]    # [:admin, :finance] can view
  setting :reports, viewable_by: [:manager]     # [:admin, :manager] can view
end

# ============================================================================
# Strategy 3: :merge - For hashes
# ============================================================================
# Use when: Child should ADD keys to parent hash, merging deeply
# Example: Custom metadata, feature flags

register_inheritable_option(:metadata, merge_strategy: :merge)

setting :parent, metadata: {category: "billing", visibility: "public"} do
  setting :child1  # metadata = {category: "billing", visibility: "public"} (inherited)

  setting :child2, metadata: {priority: "high"}
  # metadata = {category: "billing", visibility: "public", priority: "high"} (merged)

  setting :child3, metadata: {category: "reports", author: "system"}
  # metadata = {category: "reports", visibility: "public", author: "system"}
  # Note: "category" was replaced (deep_merge behavior), others merged
end

# Real-world use case: Feature configuration
register_inheritable_option(:feature_config, merge_strategy: :merge)

setting :ai_features, feature_config: {enabled: true, region: "us-east"} do
  setting :chatbot, feature_config: {model: "gpt-4"}
  # Result: {enabled: true, region: "us-east", model: "gpt-4"}

  setting :voice, feature_config: {enabled: false, model: "whisper"}
  # Result: {enabled: false, region: "us-east", model: "whisper"}
  # Note: "enabled" replaced parent's true with false
end
```

**Choosing the Right Strategy:**

| Your Option Type | Choose Strategy | Reason |
|------------------|-----------------|--------|
| Symbol, String, Integer | `:replace` | Scalars should override |
| Boolean | `:replace` | true/false should override |
| Array of roles/permissions | `:append` | Accumulate permissions |
| Array of IDs | `:append` | Build composite list |
| Configuration hash | `:merge` | Combine configs |
| Metadata hash | `:merge` | Extend metadata |

**Implementation Note:**

When registering inheritable options, ModelSettings automatically detects the type and chooses the appropriate default:
- Arrays default to `:append`
- Hashes default to `:merge`
- Everything else defaults to `:replace`

But you should **always specify explicitly** for clarity:

```ruby
# ✅ GOOD - Explicit strategy
register_inheritable_option(:viewable_by, merge_strategy: :append)

# ⚠️ OKAY - Works but implicit (will default to :append for arrays)
register_inheritable_option(:viewable_by)
```

**See**: [`ModuleRegistry.register_inheritable_option`](../core/module_registry.md#register_inheritable_option)

---

### Exclusive Groups

Prevent conflicting modules from being used together.

```ruby
# In your module
ModuleRegistry.register_exclusive_group(:authorization, :my_auth_module)

# In model's included block
included do
  settings_add_module(:my_auth_module)
  settings_check_exclusive_conflict!(:my_auth_module)
end
```

**Example - Authorization group:**
```ruby
# Pundit, Roles, and ActionPolicy are mutually exclusive
ModuleRegistry.register_exclusive_group(:authorization, :pundit)
ModuleRegistry.register_exclusive_group(:authorization, :roles)
ModuleRegistry.register_exclusive_group(:authorization, :action_policy)

# This will raise ExclusiveGroupConflictError:
class User < ApplicationRecord
  include ModelSettings::DSL
  include ModelSettings::Modules::Pundit
  include ModelSettings::Modules::Roles  # ❌ Error: both in :authorization group
end
```

**See**: [`ModuleRegistry.register_exclusive_group`](../core/module_registry.md#register_exclusive_group)

---

### Callback Configuration

For modules that need to execute during Rails lifecycle (save, validation, commit), make callback timing configurable.

```ruby
# In your module
ModuleRegistry.register_module_callback_config(
  :my_module,
  default_callback: :before_save,
  configurable: true
)

# Get the configured callback
included do
  callback_name = ModuleRegistry.get_module_callback(:my_module)
  send(callback_name, :my_callback_method)  # Registers Rails callback
end
```

**Global configuration:**
```ruby
# config/initializers/model_settings.rb
ModelSettings.configure do |config|
  config.module_callback(:audit_trail, :after_commit)  # Change from default :after_save
end
```

**When to use:**
- Audit logging modules (log after commit)
- Workflow modules (state transitions on save)
- Notification modules (send after commit)

**When NOT to use:**
- Compile-time modules (Roles, Pundit, ActionPolicy, I18n) - they only store metadata, no runtime execution needed

**See**: [`ModuleRegistry.register_module_callback_config`](../core/module_registry.md#register_module_callback_config)

---

### DSL Helpers

ModelSettings provides convenient DSL helpers for use inside your module's `ClassMethods` or `included do` blocks.

```ruby
# Available in ClassMethods and included do blocks
module ClassMethods
  def my_method
    # Short form
    metadata = get_module_metadata(:my_module)

    # Long form (equivalent)
    metadata = ModelSettings::ModuleRegistry.get_module_metadata(self, :my_module)
  end
end
```

**Available helpers:**
- `get_module_metadata(module_name, setting_name = nil)` - Retrieve metadata
- `module_metadata?(module_name, setting_name)` - Check if metadata exists
- `settings_check_exclusive_conflict!(module_name)` - Check for conflicts
- `settings_add_module(module_name)` - Track active modules

**When to use helpers vs. direct calls:**

✅ **Use DSL helpers** when:
- Inside `ClassMethods` (where `self` = model class)
- Inside `included do` blocks (where `self` = model class)
- Code is cleaner and easier to read

❌ **Use direct ModuleRegistry calls** when:
- At module level (outside `included do` or `ClassMethods`)
- Inside lifecycle hooks (`on_setting_defined`, etc.) where you have `model_class` parameter
- Working with a `model_class` parameter (not `self`)

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
  if setting.options[:my_option] && !valid_value?(setting.options[:my_option])
    raise ArgumentError,
          "Invalid my_option for #{setting.name}: #{setting.options[:my_option]}. " \
          "Expected one of: #{VALID_VALUES.join(', ')}"
  end
end
```

**Benefits:**
- Fails fast during development
- Clear error messages pointing to exact problem
- No runtime surprises

---

### 3. Make Definition Hooks Idempotent

Development mode reloads code frequently. Your hooks must handle repeated calls.

```ruby
# ✅ CORRECT - Idempotent (clears before building)
on_settings_compiled do |settings, model_class|
  model_class._my_index = {}  # Clear previous index
  settings.each { |s| model_class._my_index[s.name] = s.options[:my_option] }
end

# ❌ WRONG - Not idempotent (accumulates duplicates)
on_settings_compiled do |settings, model_class|
  model_class._my_index ||= {}  # WRONG! Keeps old data on reload
  settings.each { |s| model_class._my_index[s.name] = s.options[:my_option] }
end
```

**Pattern**: Always assign (`=`), never conditionally assign (`||=`) in definition hooks.

---

### 4. Pre-Compute at Compilation Time

Build indexes during compilation for fast runtime lookups.

```ruby
on_settings_compiled do |settings, model_class|
  # Build reverse index: option_value => [setting_names]
  model_class._option_index = Hash.new { |h, k| h[k] = [] }

  settings.each do |setting|
    if setting.options[:my_option]
      model_class._option_index[setting.options[:my_option]] << setting.name
    end
  end
end

# Fast runtime lookup
module ClassMethods
  def settings_with_option(value)
    _option_index[value].map { |name| find_setting(name) }
  end
end
```

**Benefits:**
- Fast runtime performance (O(1) lookup instead of O(n) scan)
- Computed once at class load, not on every request

---

### 5. Provide Clear Error Messages

Help developers debug configuration issues.

```ruby
before_setting_change do |instance, setting, new_value|
  unless authorized?(instance, setting)
    raise UnauthorizedError,
          "User #{instance.id} cannot change '#{setting.name}' setting.\n" \
          "Required role: #{setting.options[:editable_by].inspect}\n" \
          "User roles: #{instance.roles.inspect}"
  end
end
```

**Include in error messages:**
- What failed (setting name, user ID)
- Why it failed (required role, current roles)
- How to fix it (explicit values, not just "invalid")

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
                "MyModule requires the 'some_gem' gem.\n" \
                "Add to your Gemfile: gem 'some_gem', '~> 1.0'"
        end
      end
    end
  end
end
```

**Check early**: Fail fast in `included` block, not when first used.

---

### 7. Handle Nil Values Gracefully

Users may not provide your option - handle nil appropriately.

```ruby
on_setting_defined do |setting, model_class|
  # ✅ Good - checks for presence
  if setting.options[:my_option].present?
    validate_my_option(setting.options[:my_option])
  end

  # ❌ Bad - crashes on nil
  validate_my_option(setting.options[:my_option])
end
```

**Pattern**: Use `.present?`, `.nil?`, or `&.` safe navigation to handle missing options.

---

### 8. Test Module Isolation

Ensure your module works independently of other modules.

```ruby
RSpec.describe "MyModule in isolation" do
  it "works without other modules" do
    model = Class.new(ApplicationRecord) do
      self.table_name = "test_models"
      include ModelSettings::DSL
      include ModelSettings::Modules::MyModule  # ONLY this module

      setting :test, my_option: :value
    end

    expect(model.settings.first.options[:my_option]).to eq(:value)
  end
end
```

**Why**: Ensures your module doesn't accidentally depend on Roles, Pundit, or other modules being present.

---

## Creating Your Own Module

### Using the Generator (Recommended)

The easiest way to create a module:

```bash
rails generate model_settings:module AuditTrail
```

**This creates:**
- `lib/model_settings/modules/audit_trail.rb` - Module implementation
- `spec/model_settings/modules/audit_trail_spec.rb` - RSpec tests
- `docs/modules/audit_trail.md` - Documentation

**Generator options:**

```bash
# Basic module
rails generate model_settings:module MyModule

# Module with exclusive group
rails generate model_settings:module CustomAuth --exclusive-group=authorization

# Module with custom options
rails generate model_settings:module Workflow \
  --options=state:symbol notify:boolean priority:integer

# Skip tests or docs
rails generate model_settings:module SimpleModule --skip-tests --skip-docs
```

**After generation:**
1. Edit generated file to implement your logic
2. Update TODO comments with implementation
3. Run tests: `bundle exec rspec spec/model_settings/modules/your_module_spec.rb`
4. Update documentation in `docs/modules/your_module.md`

---

### Manual Creation

**File structure:**
```
lib/model_settings/modules/my_module.rb
spec/model_settings/modules/my_module_spec.rb
docs/modules/my_module.md
```

**Minimal module template:**

```ruby
# frozen_string_literal: true

module ModelSettings
  module Modules
    module MyModule
      extend ActiveSupport::Concern

      # 1. Register module
      ModelSettings::ModuleRegistry.register_module(:my_module, self)

      # 2. Register custom options
      ModelSettings::ModuleRegistry.register_option(:my_option) do |value, setting, model_class|
        # Validate value
        unless valid?(value)
          raise ArgumentError, "Invalid my_option: #{value}"
        end
      end

      # 3. Register lifecycle hooks
      ModelSettings::ModuleRegistry.on_setting_defined do |setting, model_class|
        next unless ModelSettings::ModuleRegistry.module_included?(:my_module, model_class)

        if setting.options[:my_option]
          ModelSettings::ModuleRegistry.set_module_metadata(
            model_class,
            :my_module,
            setting.name,
            setting.options[:my_option]
          )
        end
      end

      included do
        # 4. Add to active modules
        settings_add_module(:my_module) if respond_to?(:settings_add_module)
      end

      # 5. Add class methods
      module ClassMethods
        def settings_with_my_option
          metadata = get_module_metadata(:my_module)
          metadata.keys.map { |name| find_setting(name) }.compact
        end
      end

      # 6. Add instance methods
      def my_option_for(setting_name)
        self.class.get_module_metadata(:my_module, setting_name)
      end
    end
  end
end
```

**Namespace convention:**
- Module class: `ModelSettings::Modules::MyModule` (PascalCase)
- Symbol name: `:my_module` (snake_case)

---

## Testing Modules

### Test Structure

```ruby
# frozen_string_literal: true

require "spec_helper"

RSpec.describe ModelSettings::Modules::MyModule do
  let(:test_model) do
    Class.new(ActiveRecord::Base) do
      self.table_name = "test_models"

      def self.name
        "TestModel"
      end

      include ModelSettings::DSL
      include ModelSettings::Modules::MyModule
    end
  end

  describe "module registration" do
    it "registers with ModuleRegistry" do
      expect(ModuleRegistry.module_registered?(:my_module)).to be true
    end
  end

  describe "option registration" do
    describe "my_option" do
      it "accepts valid value" do
        expect {
          test_model.setting :test, type: :column, my_option: :valid
        }.not_to raise_error
      end

      it "rejects invalid value" do
        expect {
          test_model.setting :test, type: :column, my_option: :invalid
        }.to raise_error(ArgumentError, /Invalid my_option/)
      end
    end
  end

  describe "metadata storage" do
    before do
      test_model.setting :premium, type: :column, my_option: :value
      test_model.compile_settings!
    end

    it "stores metadata for settings with my_option" do
      meta = ModuleRegistry.get_module_metadata(test_model, :my_module, :premium)
      expect(meta).to eq(:value)
    end
  end

  describe "lifecycle hooks" do
    it "executes on_setting_defined" do
      # Test that hook captured metadata
    end

    it "executes on_settings_compiled" do
      # Test that index was built
    end
  end

  describe "runtime behavior" do
    let(:instance) { test_model.create! }

    before do
      test_model.setting :feature, type: :column, my_option: :value
    end

    it "executes before_setting_change hook" do
      # Test authorization, validation, etc.
    end

    it "executes after_setting_change hook" do
      # Test logging, notifications, etc.
    end
  end
end
```

**What to test:**
1. ✅ Module registration
2. ✅ Option registration and validation
3. ✅ Metadata storage (definition-time hooks)
4. ✅ Index building (compilation-time hooks)
5. ✅ Runtime behavior (change hooks)
6. ✅ Class and instance methods
7. ✅ Error handling

**See example**: [`examples/custom_module/audit_trail_spec.rb`](../../examples/custom_module/audit_trail_spec.rb) for comprehensive test patterns.

---

## API Reference

For complete API documentation of all ModuleRegistry methods, see:
**📚 [ModuleRegistry API Reference](../core/module_registry.md)**

### Quick Reference

**Most commonly used methods:**

**Module Registration:**
- `register_module(name, mod)` - Register your module
- `register_exclusive_group(group, name)` - Add to exclusive group

**Custom Options:**
- `register_option(name, &validator)` - Add custom DSL option
- `register_inheritable_option(name, merge_strategy:)` - Make option inheritable

**Lifecycle Hooks:**
- `on_setting_defined(&block)` - Hook setting definition
- `on_settings_compiled(&block)` - Hook after compilation
- `before_setting_change(&block)` - Hook before value changes
- `after_setting_change(&block)` - Hook after value changes

**Metadata Storage:**
- `set_module_metadata(model, module, setting, value)` - Store metadata
- `get_module_metadata(model, module, setting = nil)` - Retrieve metadata
- `module_metadata?(model, module, setting)` - Check existence

**Query Methods:**
- `register_query_method(module, method, scope, meta)` - Register introspection method

**Callback Configuration:**
- `register_module_callback_config(module, default_callback:, configurable:)` - Configure Rails callbacks
- `get_module_callback(module)` - Get effective callback

**Helper Methods:**
- `module_included?(name, model)` - Check if module is included
- `module_registered?(name)` - Check if module is registered

---

## Related Documentation

**Guides:**
- [Configuration](../core/configuration.md) - Global configuration options
- [Callbacks](../core/callbacks.md) - ModelSettings callback system

**Built-in Modules (Reference Implementations):**
- [Roles Module](../modules/roles.md) - Simple RBAC authorization
- [Pundit Module](../modules/policy_based/pundit.md) - Pundit integration
- [ActionPolicy Module](../modules/policy_based/action_policy.md) - ActionPolicy integration
- [I18n Module](../modules/i18n.md) - Internationalization

**API Reference:**
- [ModuleRegistry API](../core/module_registry.md) - Complete API documentation

**Examples:**
- [AuditTrail Example](../../examples/custom_module/) - Complete working module

---

## Summary

**Key Concepts:**

1. **Custom DSL Options**: Extend the `setting` DSL with your own options
2. **Lifecycle Hooks**: Hook into definition, compilation, and runtime events
3. **Metadata Storage**: Centralized storage for module-specific data
4. **Inheritable Options**: Make options flow to nested settings
5. **Query Methods**: Add introspection methods to models
6. **Idempotency**: Definition hooks MUST be idempotent for Rails reloading

**Development Checklist:**

- [ ] Module extends `ActiveSupport::Concern`
- [ ] Registered with `ModuleRegistry.register_module`
- [ ] Custom options registered with validators
- [ ] Definition hooks are idempotent
- [ ] Metadata stored in centralized location
- [ ] Error messages are clear and helpful
- [ ] Nil values handled gracefully
- [ ] Comprehensive tests included
- [ ] Usage documentation provided
- [ ] Dependencies checked (if any)

**Learning Resources:**

1. **Start here**: Study the [AuditTrail example](../../examples/custom_module/)
2. **Deep dive**: Read the [ModuleRegistry API](../core/module_registry.md)
3. **Reference**: Examine built-in modules in `lib/model_settings/modules/`
4. **Generate**: Use `rails generate model_settings:module` to scaffold your module

**Questions?** See the source code of built-in modules for additional examples:
- `lib/model_settings/modules/roles.rb` - Simple module
- `lib/model_settings/modules/pundit.rb` - Authorization module
- `lib/model_settings/modules/i18n.rb` - Translation module
