# Column Adapter

Store each setting as a separate database column. Best for feature flags and settings that are frequently queried individually.

## Basic Usage

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  setting :premium, type: :column, default: false
  setting :notifications_enabled, type: :column, default: true
end
```

## Migration

```ruby
class AddSettingsToUsers < ActiveRecord::Migration[7.0]
  def change
    add_column :users, :premium, :boolean, default: false, null: false
    add_column :users, :notifications_enabled, :boolean, default: true, null: false

    # Add index for frequently queried settings
    add_index :users, :premium
  end
end
```

**Important:** Always specify `default:` and `null: false` to ensure data integrity.

## Column-Specific Features

### SQL Queries and Indexes

Column storage makes settings easily queryable with standard SQL:

```ruby
# Direct WHERE clauses
User.where(premium: true)
User.where(notifications_enabled: false)

# Combine with other conditions
User.where(premium: true, active: true)

# Use indexes for fast queries
add_index :users, :premium
add_index :users, [:premium, :active]  # Composite index
```

**Performance:** With proper indexes, column queries are the fastest option.

### Schema Management

Each setting requires its own column:

```ruby
# Adding a setting = adding a column
add_column :users, :new_feature, :boolean, default: false

# Removing a setting = removing a column
remove_column :users, :old_feature

# Renaming a setting = renaming a column
rename_column :users, :old_name, :new_name
```

**Trade-off:** Explicit schema (good for clarity) vs. table bloat with many settings.

## When to Use Column Adapter

✅ **Use when:**
- Settings are queried individually in SQL (`WHERE premium = true`)
- You need database indexes on settings
- Settings are independent (not grouped)
- You want explicit schema

❌ **Avoid when:**
- You have many related settings (bloats table with columns)
- Schema changes frequently
- Settings are always read/written together

## Common Features

Column adapter supports all common features:
- **Helper Methods** - `_enable!`, `_disable!`, `_toggle!`, `_enabled?`, `_disabled?`
- **Dirty Tracking** - Native ActiveRecord dirty tracking
- **Validation** - Boolean validation

See [Common Features](../adapters.md#common-features) in the Adapters Overview.

## Related Documentation

- [Adapters Overview](../adapters.md) - Compare all adapter types
- [JSON Adapter](json.md) - Multiple settings in one column
- [StoreModel Adapter](store_model.md) - Complex nested settings
