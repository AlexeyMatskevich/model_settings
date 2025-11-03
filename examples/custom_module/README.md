# Custom Module Example: AuditTrail

This directory contains a complete, working example of a custom ModelSettings module that demonstrates all major features of the Module Development API.

## What This Module Does

The `AuditTrail` module adds audit logging capabilities to settings:

- Logs all changes to settings in an audit log
- Supports different audit levels (`:minimal`, `:detailed`)
- Allows capturing the current user making changes
- Inherits audit configuration to nested settings
- Configurable Rails callback timing

## Files

- `audit_trail.rb` - Complete module implementation
- `audit_trail_spec.rb` - Comprehensive RSpec tests
- `README.md` - This file

## Features Demonstrated

### 1. Module Registration
```ruby
ModuleRegistry.register_module(:audit_trail, self)
```

### 2. Custom DSL Options
```ruby
setting :premium,
  audit_level: :detailed,           # Custom option
  audit_user: ->(user) { Current.user }  # Callable option
```

### 3. Lifecycle Hooks
- `on_setting_defined` - Capture audit configuration
- `after_setting_change` - Log changes to audit table

### 4. Inheritable Options
- `audit_level` inherits to nested settings

### 5. Callback Configuration
- Default: `:after_save`
- User-configurable via global settings

### 6. Metadata Storage
- Centralized storage of audit configuration per setting

### 7. Query Methods
- `Model.audited_settings` - Find all audited settings

## Usage Example

### 1. Include the Module

```ruby
# lib/model_settings/modules/audit_trail.rb
# Copy audit_trail.rb to your application

class User < ApplicationRecord
  include ModelSettings::DSL
  include ModelSettings::Modules::AuditTrail

  setting :premium,
    type: :column,
    audit_level: :detailed,
    audit_user: ->(user) { Current.user }

  setting :billing do
    setting :auto_renew,
      type: :column
      # Inherits audit_level from parent
  end
end
```

### 2. Database Migration

```ruby
class CreateAuditLogs < ActiveRecord::Migration[7.0]
  def change
    create_table :audit_logs do |t|
      t.references :model, polymorphic: true, null: false
      t.string :setting, null: false
      t.text :old_value
      t.text :new_value
      t.string :level, null: false
      t.references :user, null: true
      t.timestamps
    end

    add_index :audit_logs, [:model_type, :model_id, :setting]
  end
end
```

### 3. Configure Callback Timing (Optional)

```ruby
# config/initializers/model_settings.rb
ModelSettings.configure do |config|
  # Change when audit logs are created
  config.module_callback(:audit_trail, :after_commit)  # Default: :after_save
end
```

### 4. Use It

```ruby
user = User.find(1)
user.premium = true
user.save!

# Audit log automatically created
AuditLog.last
# => #<AuditLog
#      model: #<User id: 1>,
#      setting: "premium",
#      old_value: "false",
#      new_value: "true",
#      level: "detailed",
#      user: #<User id: 2>,
#      created_at: ...>

# Query audited settings
User.audited_settings
# => [#<Setting name=:premium>, #<Setting name=:auto_renew>]
```

## Testing

See `audit_trail_spec.rb` for comprehensive test examples covering:

- Option validation
- Metadata storage
- Lifecycle hook execution
- Inheritance behavior
- Query methods
- Edge cases

Run tests:
```bash
rspec examples/custom_module/audit_trail_spec.rb
```

## Key Concepts Explained

### Option Validators

```ruby
ModuleRegistry.register_option(:audit_level) do |value, setting, model_class|
  unless [:minimal, :detailed].include?(value)
    raise ArgumentError, "audit_level must be :minimal or :detailed"
  end
end
```

- Validates options at setting definition time
- Raises `ArgumentError` if invalid
- Receives value, setting, and model class

### Metadata Storage

```ruby
ModuleRegistry.on_setting_defined do |setting, model_class|
  if setting.options[:audit_level]
    ModuleRegistry.set_module_metadata(
      model_class,
      :audit_trail,
      setting.name,
      {level: setting.options[:audit_level]}
    )
  end
end
```

- Store configuration during setting definition
- Retrieve later during runtime
- Centralized per model/module/setting

### Lifecycle Hooks

```ruby
ModuleRegistry.after_setting_change do |instance, setting, old_value, new_value|
  # Only process settings with audit_level
  meta = ModuleRegistry.get_module_metadata(
    instance.class,
    :audit_trail,
    setting.name
  )

  if meta
    # Create audit log
    AuditLog.create!(...)
  end
end
```

- Execute custom logic at specific points
- Access instance, setting, and values
- Check metadata to determine behavior

### Inheritable Options

```ruby
ModuleRegistry.register_inheritable_option(
  :audit_level,
  merge_strategy: :replace,
  auto_include: true
)
```

- Makes option automatically inherit to nested settings
- Merge strategy controls how parent/child values combine
- `auto_include: true` adds to global inheritable list

## Advanced Patterns

### Conditional Auditing

```ruby
setting :premium,
  audit_level: :detailed,
  audit_if: ->(instance) { instance.account_type == 'enterprise' }
```

### Custom Audit Formats

```ruby
setting :api_key,
  audit_level: :detailed,
  audit_format: ->(value) { value ? '[REDACTED]' : nil }
```

### Bulk Audit Queries

```ruby
class User
  def audit_history(setting_name)
    AuditLog.where(
      model: self,
      setting: setting_name
    ).order(created_at: :desc)
  end
end
```

## Extending the Example

Ideas for enhancement:

1. **Filtering**: Add `audit_exclude` option to skip certain changes
2. **Batching**: Batch multiple changes into single audit record
3. **Compression**: Compress large values before storage
4. **Retention**: Auto-delete old audit logs
5. **Analysis**: Add methods to analyze change patterns
6. **Notifications**: Send alerts on critical changes

## Resources

- [Module Development Guide](../../docs/guides/module_development.md)
- [ModuleRegistry API Reference](../../docs/api/module_registry.md)
- [Built-in Modules](../../docs/modules/) - More examples

## License

This example code is in the public domain. Use it however you want.
