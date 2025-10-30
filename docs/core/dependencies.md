# Dependency Management

ModelSettings provides powerful dependency management through **cascades** and **syncs**, allowing settings to automatically update related settings while preventing circular dependencies.

## Overview

| Feature | Purpose | Example Use Case |
|---------|---------|------------------|
| **Cascades** | Enable/disable children when parent changes | Premium plan enables all premium features |
| **Syncs** | Keep two settings synchronized | "Do Not Track" is inverse of "Analytics Enabled" |
| **Cycle Detection** | Prevent infinite loops | Catches circular sync chains at boot time |

---

## Cascades

Cascades automatically propagate enable/disable actions from parent settings to their children.

### Enable Cascade

When parent is enabled, all children are automatically enabled:

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  setting :premium_mode, type: :column, default: false, cascade: {enable: true} do
    setting :advanced_analytics, type: :column, default: false
    setting :priority_support, type: :column, default: false
    setting :custom_branding, type: :column, default: false
  end
end

# When premium_mode is enabled, all children are automatically enabled
user = User.create!
user.premium_mode = true
user.save!

user.advanced_analytics  # => true (auto-enabled)
user.priority_support    # => true (auto-enabled)
user.custom_branding     # => true (auto-enabled)
```

### Disable Cascade

When parent is disabled, all children are automatically disabled:

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  setting :account_active, type: :column, default: true, cascade: {disable: true} do
    setting :api_access, type: :column, default: true
    setting :email_notifications, type: :column, default: true
    setting :data_export, type: :column, default: true
  end
end

# When account is deactivated, all children are automatically disabled
user = User.create!
user.account_active = false
user.save!

user.api_access           # => false (auto-disabled)
user.email_notifications  # => false (auto-disabled)
user.data_export          # => false (auto-disabled)
```

### Both Cascades

Enable and disable both ways:

```ruby
class Organization < ApplicationRecord
  include ModelSettings::DSL

  setting :billing_enabled,
          type: :column,
          default: false,
          cascade: {enable: true, disable: true} do
    setting :invoices, type: :column, default: false
    setting :payments, type: :column, default: false
  end
end

# Enable cascade
org = Organization.create!
org.billing_enabled = true
org.save!
org.invoices  # => true
org.payments  # => true

# Disable cascade
org.billing_enabled = false
org.save!
org.invoices  # => false
org.payments  # => false
```

### Cascade Execution

Cascades execute **during save**, after validations pass:

```ruby
user = User.create!
user.premium_mode = true

# Children NOT yet cascaded (in-memory only)
user.advanced_analytics  # => false (not cascaded yet)

user.save!  # Cascade happens here

# Now children are cascaded
user.advanced_analytics  # => true
```

---

## Syncs

Syncs keep two settings synchronized with three modes: **forward**, **inverse**, and **backward**.

### Forward Sync

Target setting mirrors source setting (target = source):

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  setting :marketing_emails,
          type: :column,
          default: true,
          sync: {target: :newsletter_subscription, mode: :forward}

  setting :newsletter_subscription, type: :column, default: true
end

user = User.create!
user.marketing_emails = false
user.save!

user.newsletter_subscription  # => false (synced)
```

**Use case**: When one setting should always match another.

### Inverse Sync

Target setting is opposite of source (target = !source):

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  setting :do_not_track,
          type: :column,
          default: false,
          sync: {target: :analytics_enabled, mode: :inverse}

  setting :analytics_enabled, type: :column, default: true
end

user = User.create!
user.do_not_track = true
user.save!

user.analytics_enabled  # => false (inverse of true)
```

**Use case**: Opt-out/opt-in relationships.

### Backward Sync

Source setting follows target (source = target):

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  setting :auto_renew,
          type: :column,
          default: true,
          sync: {target: :subscription_active, mode: :backward}

  setting :subscription_active, type: :column, default: false
end

user = User.create!(subscription_active: true)
user.auto_renew = false  # Try to disable
user.save!

user.auto_renew  # => true (reverted to match subscription_active)
```

**Use case**: Derived settings that must follow their source.

### Chained Syncs

Syncs can be chained to propagate changes through multiple settings:

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  setting :gdpr_mode,
          type: :column,
          default: false,
          sync: {target: :privacy_enhanced, mode: :forward}

  setting :privacy_enhanced,
          type: :column,
          default: false,
          sync: {target: :tracking_disabled, mode: :forward}

  setting :tracking_disabled, type: :column, default: false
end

user = User.create!
user.gdpr_mode = true
user.save!

user.privacy_enhanced    # => true (synced from gdpr_mode)
user.tracking_disabled   # => true (synced from privacy_enhanced)
```

---

## Cycle Detection

The DependencyEngine automatically detects circular sync dependencies **at definition time** (boot):

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  setting :feature_a, sync: {target: :feature_b, mode: :forward}
  setting :feature_b, sync: {target: :feature_c, mode: :forward}
  setting :feature_c, sync: {target: :feature_a, mode: :forward}  # Cycle!
end

# Raises at boot time:
# ModelSettings::CyclicSyncError: Cyclic sync detected: feature_a -> feature_b -> feature_c -> feature_a
# Settings cannot have circular sync dependencies.
```

This prevents infinite loops and ensures predictable behavior.

**Why fail at boot?** Catching cycles early prevents runtime errors and data corruption.

---

## Mixed Storage with Dependencies

Cascades and syncs work **across storage types**. Parent and children can use different adapters.

### Column Parent with JSON Children

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  # Column parent with JSON children using explicit storage
  setting :premium, type: :column, default: false, cascade: {enable: true} do
    setting :theme,
            type: :json,
            storage: {column: :premium_features},
            default: "light"

    setting :advanced_filters,
            type: :json,
            storage: {column: :premium_features},
            default: false
  end
end

# Migration:
# add_column :users, :premium, :boolean, default: false
# add_column :users, :premium_features, :jsonb, default: {}

user = User.create!
user.premium = true
user.save!

# Cascade works across storage types
user.advanced_filters  # => true (cascaded from column parent)
user.theme            # => "light" (stored in JSON column)
```

### JSON Parent with Column Children

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  setting :notifications,
          type: :json,
          storage: {column: :settings},
          default: true do
    # Child uses its own column even though parent is JSON
    setting :email_enabled, type: :column, default: false
    setting :sms_enabled, type: :column, default: false
  end
end

# Each setting uses its own storage
user = User.create!
user.notifications = false
user.email_enabled = true
user.save!

user.settings          # => {"notifications" => false}
user.email_enabled     # => true (separate column)
```

---

## Combining Cascades and Syncs

Cascades and syncs work together seamlessly in the same save:

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  # Parent with cascade
  setting :enterprise_mode,
          type: :column,
          default: false,
          cascade: {enable: true} do
    setting :advanced_reporting, type: :column, default: false
  end

  # Independent sync
  setting :analytics_enabled,
          type: :column,
          default: true,
          sync: {target: :tracking_enabled, mode: :forward}

  setting :tracking_enabled, type: :column, default: true
end

user = User.create!
user.enterprise_mode = true
user.analytics_enabled = false
user.save!

# Both cascade and sync applied in same save
user.advanced_reporting  # => true (cascaded)
user.tracking_enabled    # => false (synced)
```

---

## Execution Order

When you save a record, dependencies execute in this order:

1. **Validations** run first
2. **before_save** callbacks
3. **Cascades** execute (parent → children)
4. **Syncs** execute (source → target)
5. **ActiveRecord save**
6. **after_save** callbacks
7. **after_commit** callbacks

This ensures:
- Cascades happen before syncs
- All dependencies resolved before database commit
- Callbacks see final cascaded/synced values

---

## Best Practices

### 1. Use Cascades for Hierarchical Features

```ruby
# ✅ Good - Premium plan with dependent features
setting :premium_plan, cascade: {enable: true} do
  setting :advanced_analytics
  setting :priority_support
  setting :custom_branding
end
```

### 2. Use Forward Sync for Mirroring

```ruby
# ✅ Good - Marketing consent mirrors newsletter
setting :marketing_consent,
        sync: {target: :newsletter_subscription, mode: :forward}
```

### 3. Use Inverse Sync for Opt-Out Relationships

```ruby
# ✅ Good - Do Not Track is opposite of Analytics
setting :do_not_track,
        sync: {target: :analytics_enabled, mode: :inverse}
```

### 4. Use Backward Sync for Computed Settings

```ruby
# ✅ Good - Auto-renew follows subscription status
setting :auto_renew,
        sync: {target: :subscription_active, mode: :backward}
```

### 5. Avoid Deep Cascade Chains

```ruby
# ❌ Avoid - Too many levels
setting :level1, cascade: {enable: true} do
  setting :level2, cascade: {enable: true} do
    setting :level3, cascade: {enable: true} do
      setting :level4  # Too deep!
    end
  end
end

# ✅ Better - Flatter structure
setting :premium, cascade: {enable: true} do
  setting :feature_a
  setting :feature_b
  setting :feature_c
end
```

### 6. Design to Avoid Cycles

```ruby
# ❌ Bad - Circular dependency
setting :feature_a, sync: {target: :feature_b, mode: :forward}
setting :feature_b, sync: {target: :feature_a, mode: :forward}
# Raises CyclicSyncError!

# ✅ Good - Linear dependency chain
setting :feature_a, sync: {target: :feature_b, mode: :forward}
setting :feature_b, sync: {target: :feature_c, mode: :forward}
setting :feature_c  # End of chain
```

---

## Troubleshooting

### Cascades Not Working

**Problem**: Children not cascading when parent changes

**Solutions**:
1. Check if you called `save!` - cascades only apply on save
2. Verify cascade direction matches your intent (enable vs disable)
3. Check if children have conflicting validations preventing change

### Syncs Not Working

**Problem**: Target not syncing with source

**Solutions**:
1. Verify sync mode (forward/inverse/backward)
2. Check if target setting exists
3. Ensure no typos in target name

### Unexpected Values After Cascade/Sync

**Problem**: Settings have unexpected values after save

**Debug**:
```ruby
# Enable dependency engine debugging
user.premium = true
puts "Before save: #{user.advanced_analytics}"
user.save!
puts "After save: #{user.advanced_analytics}"
```

---

## Related Documentation

- [Storage Adapters](adapters.md) - Cascades/syncs work across all storage types
- [Callbacks](callbacks.md) - Hook into cascade/sync execution
- [Validation](validation.md) - Validations run before cascades
- [Settings Inheritance](inheritance.md) - Cascades/syncs are inherited

---

## Summary

| Feature | When to Use | Example |
|---------|-------------|---------|
| **Enable Cascade** | Parent enables all children | Premium plan → premium features |
| **Disable Cascade** | Parent disables all children | Deactivated account → disable all access |
| **Forward Sync** | Mirror one setting to another | Marketing consent → newsletter |
| **Inverse Sync** | Opposite relationships | Do Not Track ↔ Analytics |
| **Backward Sync** | Derived/computed settings | Auto-renew follows subscription |
| **Cycle Detection** | Always active | Catches circular syncs at boot |
