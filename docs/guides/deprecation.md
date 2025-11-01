# Deprecation Management

ModelSettings provides comprehensive tools for managing deprecated settings, including marking settings as deprecated, auditing their usage in your database, and ensuring smooth migrations.

## Table of Contents

- [Marking Settings as Deprecated](#marking-settings-as-deprecated)
- [Listing Deprecated Settings](#listing-deprecated-settings)
- [Auditing Database Usage](#auditing-database-usage)
- [CI Integration](#ci-integration)
- [Migration Strategies](#migration-strategies)

## Marking Settings as Deprecated

You can mark any setting as deprecated using the `deprecated` option:

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  # Simple deprecation flag
  setting :old_feature, type: :column, deprecated: true

  # With custom message
  setting :legacy_api_enabled,
    type: :column,
    deprecated: "Use new_api_enabled instead",
    deprecated_since: "2.0.0"
end
```

### Deprecation Options

- **`deprecated: true`** - Marks setting as deprecated without a specific reason
- **`deprecated: "message"`** - Provides a custom deprecation message explaining what to use instead
- **`deprecated_since: "version"`** - Optional version indicator for tracking when deprecation started

## Listing Deprecated Settings

To get a quick overview of all deprecated settings in your application:

```bash
rake settings:docs:list_deprecated
```

**Example Output:**

```
Deprecated Settings Report
==================================================

User:
  - old_feature
    Message: (no message)
  - legacy_api_enabled
    Message: Use new_api_enabled instead
    Since: 2.0.0

Organization:
  - beta_feature
    Message: Feature is now stable, use stable_feature
    Since: 1.5.0

Found 3 deprecated setting(s) across 2 model(s)
```

This command:
- Scans all models in your application
- Lists deprecated settings grouped by model
- Shows deprecation messages and version information
- Useful for documentation and planning migrations

## Auditing Database Usage

Before removing deprecated settings, you need to know if they're actually being used. The audit task checks your database for real usage:

```bash
rake settings:audit:deprecated
```

### Understanding Audit Results

**When no deprecated settings are in use:**

```
✓ No deprecated settings found in use
```

Exit code: `0` (success)

**When deprecated settings are found:**

```
⚠️  Found deprecated settings in use:

User (1 deprecated settings):
  ✗ legacy_api_enabled
    Reason: Use new_api_enabled instead
    Used in: 127 records (out of 5000 total)

Organization (1 deprecated settings):
  ✗ beta_feature
    Reason: Feature is now stable, use stable_feature
    Used in: 3 records (out of 50 total)
```

Exit code: `1` (failure - useful for CI)

### How Auditing Works

The auditor intelligently checks usage based on storage type:

#### Column Adapter
```ruby
setting :old_feature, type: :column, deprecated: true
```

- **Boolean columns**: Counts records where value is explicitly `true`
- **Other types**: Counts records where value is NOT NULL

#### JSON Adapter
```ruby
setting :old_feature,
  type: :json,
  storage: { column: :settings_json },
  deprecated: true
```

- **PostgreSQL**: Uses native JSONB operators (`?`) to check key existence
- **Other databases**: Falls back to Ruby-based checking

#### StoreModel Adapter
```ruby
setting :old_feature,
  type: :store_model,
  storage: { column: :preferences },
  deprecated: true
```

- Checks if parent StoreModel column has data (conservative approach)

## CI Integration

Integrate deprecation auditing into your CI pipeline to prevent accidental use of deprecated settings:

### GitHub Actions

```yaml
# .github/workflows/test.yml
name: Test

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Set up Ruby
        uses: ruby/setup-ruby@v1
        with:
          bundler-cache: true

      # ... other test steps ...

      - name: Audit deprecated settings
        run: bundle exec rake settings:audit:deprecated
```

### GitLab CI

```yaml
# .gitlab-ci.yml
test:
  script:
    - bundle install
    - bundle exec rspec
    - bundle exec rake settings:audit:deprecated
```

### Exit Codes

- **Exit 0**: No deprecated settings in use (CI passes)
- **Exit 1**: Deprecated settings found in use (CI fails)

This ensures your team is notified immediately when deprecated settings are used.

## Migration Strategies

### Strategy 1: Gradual Migration (Recommended)

1. **Mark setting as deprecated:**

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  setting :old_feature, type: :column, deprecated: "Use new_feature instead"
  setting :new_feature, type: :column, default: false
end
```

2. **Run audit to find usage:**

```bash
rake settings:audit:deprecated
# Found 50 records using old_feature
```

3. **Create data migration:**

```ruby
# db/migrate/20250101000000_migrate_old_feature_to_new_feature.rb
class MigrateOldFeatureToNewFeature < ActiveRecord::Migration[7.0]
  def up
    User.where(old_feature: true).update_all(new_feature: true)
  end

  def down
    User.where(new_feature: true).update_all(old_feature: true)
  end
end
```

4. **Deploy and monitor:**

```bash
# After deployment, verify migration
rake settings:audit:deprecated
# ✓ No deprecated settings found in use
```

5. **Remove deprecated setting:**

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  # Remove old_feature completely
  setting :new_feature, type: :column, default: false
end
```

6. **Create database migration to drop column:**

```ruby
# db/migrate/20250115000000_remove_old_feature_from_users.rb
class RemoveOldFeatureFromUsers < ActiveRecord::Migration[7.0]
  def change
    remove_column :users, :old_feature, :boolean
  end
end
```

### Strategy 2: Breaking Change (Pre-1.0 or Major Version)

For breaking changes in pre-1.0 or major version releases:

1. **Announce deprecation in changelog and documentation**
2. **Mark settings as deprecated with clear migration path**
3. **Run audit in staging environment**
4. **If usage is minimal, proceed with removal**
5. **Update all affected records in migration**
6. **Remove deprecated settings in same release**

### Strategy 3: Backward-Compatible Wrapper

For complex migrations, create a wrapper that supports both old and new interfaces:

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  setting :new_feature, type: :column, default: false

  # Deprecated wrapper that delegates to new_feature
  def old_feature
    Rails.logger.warn("DEPRECATED: old_feature is deprecated, use new_feature")
    new_feature
  end

  def old_feature=(value)
    Rails.logger.warn("DEPRECATED: old_feature= is deprecated, use new_feature=")
    self.new_feature = value
  end
end
```

## Best Practices

1. **Always provide deprecation messages** explaining what to use instead
2. **Use version tracking** with `deprecated_since` for better planning
3. **Run audits regularly** to catch usage early
4. **Integrate auditing into CI** to prevent new usage
5. **Document migration paths** in changelog and guides
6. **Give ample warning** before removing deprecated settings (at least one major version)
7. **Verify zero usage** before removal using audit task

## Troubleshooting

### Audit shows zero usage but I know it's used

**Possible causes:**

1. **Test/development database**: Audit checks current database. Make sure to run in production (or production dump).
2. **Cached results**: Try reloading Rails: `bundle exec rails runner 'Rails.application.eager_load!'`
3. **Boolean false values**: For booleans, only `true` is counted as usage, not `false`.

### Audit fails with error

**Common errors:**

- **Table doesn't exist**: Run migrations first
- **Column not found**: Ensure setting name matches database column
- **JSON parse error**: Check JSON column data integrity

**Debug mode:**

```bash
DEBUG=1 rake settings:audit:deprecated
```

## Related Documentation

- [Settings Documentation](../modules/documentation.md) - Generate documentation for all settings
- [Module Development](module_development.md) - Create custom modules
- [Validation](../core/validation.md) - Validate setting values
