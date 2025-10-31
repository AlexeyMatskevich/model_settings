# Query Interface

ModelSettings provides powerful methods for finding and filtering settings by metadata, type, and other criteria.

## Basic Queries

### find_setting

Find a setting by name or path:

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  setting :billing, type: :json, storage: {column: :settings_data} do
    setting :invoices, default: false
  end
end

# Find by name
User.find_setting(:billing)

# Find nested setting by path
User.find_setting([:billing, :invoices])
```

### settings_by_type

Get all settings of a specific type:

```ruby
# All column settings
User.settings_by_type(:column)

# All JSON settings
User.settings_by_type(:json)

# All StoreModel settings
User.settings_by_type(:store_model)
```

## Metadata Queries

### settings_where

Query settings by metadata:

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  setting :billing_enabled,
          type: :json,
          storage: {column: :settings},
          metadata: {
            category: "billing",
            tier: "premium",
            requires_verification: true
          }

  setting :api_access,
          type: :json,
          storage: {column: :settings},
          metadata: {
            category: "api",
            tier: "enterprise",
            rate_limit: 1000
          }
end

# Query by metadata
User.settings_where(metadata: {category: "billing"})
# => [billing_enabled setting]

User.settings_where(metadata: {tier: "premium"})
# => [billing_enabled setting]
```

### settings_with_metadata_key / with_metadata

Find settings that have a specific metadata key:

```ruby
User.settings_with_metadata_key(:rate_limit)
# => [api_access setting]

User.settings_with_metadata_key(:category)
# => [billing_enabled, api_access settings]

# Shorter alias
User.with_metadata(:rate_limit)
# => [api_access setting]
```

### without_metadata

Find settings that **don't** have a specific metadata key:

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  setting :documented_feature,
          metadata: {description: "Feature with docs"}

  setting :undocumented_feature
          # No description
end

# Find settings without description
User.without_metadata(:description)
# => [undocumented_feature setting]

# Find settings without tier
User.without_metadata(:tier)
# => Settings that don't have tier metadata
```

**Use case:** Find settings that need documentation or categorization.

### where_metadata

Advanced metadata querying with operators:

#### Exact Match (`equals:`)

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  setting :basic_features,
          metadata: {tier: "basic"}

  setting :premium_features,
          metadata: {tier: "premium"}

  setting :enterprise_features,
          metadata: {tier: "enterprise"}
end

# Find settings with exact tier value
User.where_metadata(:tier, equals: "premium")
# => [premium_features setting]

User.where_metadata(:tier, equals: "basic")
# => [basic_features setting]
```

#### Array Inclusion (`includes:`)

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  setting :analytics,
          metadata: {
            plans: [:professional, :enterprise]
          }

  setting :advanced_reports,
          metadata: {
            plans: [:enterprise]
          }

  setting :basic_dashboard,
          metadata: {
            plans: [:basic, :professional, :enterprise]
          }
end

# Find settings available in professional plan
User.where_metadata(:plans, includes: :professional)
# => [analytics, basic_dashboard settings]

# Find settings available in enterprise plan
User.where_metadata(:plans, includes: :enterprise)
# => [analytics, advanced_reports, basic_dashboard settings]
```

**Note:** The `includes:` operator only works with array metadata values.

#### Block Filter

```ruby
# Complex conditions
User.where_metadata do |meta|
  meta[:tier] == "premium" && !meta[:deprecated]
end

# Multiple criteria
User.where_metadata do |meta|
  meta[:category] == "billing" && meta[:tier] == "enterprise"
end

# Check key presence with condition
User.where_metadata do |meta|
  meta.key?(:rate_limit) && meta[:rate_limit] > 100
end
```

#### No Filter

```ruby
# Returns all settings (same as all_settings_recursive)
User.where_metadata
```

### settings_grouped_by_metadata

Group settings by a metadata key:

```ruby
User.settings_grouped_by_metadata(:category)
# => {
#   "billing" => [billing_enabled],
#   "api" => [api_access]
# }

User.settings_grouped_by_metadata(:tier)
# => {
#   "premium" => [billing_enabled],
#   "enterprise" => [api_access]
# }
```

## Callback Queries

### settings_with_callbacks

Find settings that have specific callbacks:

```ruby
# Settings with after_enable callback
User.settings_with_callbacks(:after_enable)

# Settings with any callback
User.settings_with_callbacks(:before_change, :after_change)
```

## Custom Queries

### settings_matching

Filter settings with a custom block:

```ruby
# Settings with "api" in the name
User.settings_matching { |s| s.name.to_s.include?("api") }

# Settings with defaults
User.settings_matching { |s| s.default.present? }

# Settings with specific metadata value
User.settings_matching { |s| s.metadata[:tier] == "premium" }
```

## Counting

### settings_count

Count settings with optional filters:

```ruby
# Count by type
User.settings_count(type: :json)

# Count by metadata
User.settings_count(metadata: {tier: "premium"})

# Count all settings
User.settings_count
```

## Hierarchy Queries

### root_settings

Get only top-level settings (no parents):

```ruby
User.root_settings
# => [billing, premium, notifications]  # Only parents
```

### leaf_settings

Get only settings without children:

```ruby
User.leaf_settings
# => [invoices, payments, api_access]  # Only leaves
```

### all_settings_recursive

Get all settings including nested:

```ruby
User.all_settings_recursive
# => All settings, including parents and children
```

## Instance Queries

### Setting Navigation

Navigate setting hierarchies:

```ruby
# Find a setting
billing = User.find_setting(:billing)

# Get children
billing.children
# => [invoices, payments, subscriptions]

# Get parent
invoices = User.find_setting([:billing, :invoices])
invoices.parent
# => billing setting

# Get root
invoices.root
# => billing setting

# Get path
invoices.path
# => [:billing, :invoices]

# Check if leaf
invoices.leaf?  # => true
billing.leaf?   # => false
```

## Performance Tips

### Cache Results

Setting metadata is cached at the class level:

```ruby
# First call queries settings (fast)
@premium_settings = User.settings_where(metadata: {tier: "premium"})

# Subsequent calls return cached results (instant)
User.settings_where(metadata: {tier: "premium"})
```

### Use Specific Queries

```ruby
# ✅ Fast - specific query
User.settings_by_type(:json)

# ❌ Slower - filter all settings
User.all_settings_recursive.select { |s| s.type == :json }
```

## Examples

### Get All Deprecated Settings

```ruby
deprecated = User.settings_matching { |s| s.deprecated? }

deprecated.each do |setting|
  puts "#{setting.name}: #{setting.options[:deprecated]}"
end
```

### Group Settings for UI

```ruby
settings_by_category = User.settings_grouped_by_metadata(:category)

settings_by_category.each do |category, settings|
  puts "#{category}:"
  settings.each do |setting|
    puts "  - #{setting.name}"
  end
end
```

### Find Settings Needing Migration

```ruby
# Find column settings (candidates for JSON migration)
column_settings = User.settings_by_type(:column)

if column_settings.count > 10
  puts "Consider migrating #{column_settings.count} column settings to JSON"
end
```

## Related Documentation

- [DSL Reference](dsl.md) - Setting definition with metadata
- [Storage Adapters](adapters.md) - Query by storage type
- [Deprecation](../guides/best_practices.md#deprecation) - Find deprecated settings

## Summary

| Method | Returns | Use Case |
|--------|---------|----------|
| `find_setting` | Single setting | Get specific setting |
| `settings_by_type` | Array of settings | Filter by storage type |
| `settings_where` | Array of settings | Filter by exact metadata values |
| `with_metadata` | Array of settings | Find settings with metadata key |
| `without_metadata` | Array of settings | Find settings without metadata key |
| `where_metadata` | Array of settings | Advanced metadata queries (equals, includes, block) |
| `settings_matching` | Array of settings | Custom filter logic |
| `root_settings` | Array of settings | Top-level only |
| `leaf_settings` | Array of settings | Settings without children |
| `settings_count` | Integer | Count with filters |
