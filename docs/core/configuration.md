# Global Configuration

Configure ModelSettings behavior globally for your application.

## Configuration File

Create an initializer:

```ruby
# config/initializers/model_settings.rb
ModelSettings.configure do |config|
  # Configure options here
end
```

## Available Options

### inherit_settings

Control whether child classes inherit parent settings.

```ruby
ModelSettings.configure do |config|
  config.inherit_settings = true  # Default: true
end
```

**When to disable**: If you have STI models but don't want automatic inheritance.

### inherit_authorization

Control authorization inheritance (when using auth modules).

```ruby
ModelSettings.configure do |config|
  config.inherit_authorization = true  # Default: true
end
```

Used by Roles, Pundit, and ActionPolicy modules for inheriting `viewable_by`, `editable_by`, and `authorize_with` options.

## Per-Model Configuration

Override global config per model:

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  # This model doesn't inherit settings even if globally enabled
  self.inherit_settings = false

  setting :premium, type: :column
end
```

## Environment-Specific Configuration

```ruby
ModelSettings.configure do |config|
  if Rails.env.production?
    config.inherit_authorization = true
  else
    config.inherit_authorization = false  # More permissive in dev
  end
end
```

## Accessing Configuration

```ruby
# Check current configuration
ModelSettings.configuration.inherit_settings  # => true

# Check per-model
User.inherit_settings  # => true
```

## Related Documentation

- [Settings Inheritance](inheritance.md) - How `inherit_settings` works
- [Roles Module](../modules/roles.md) - Uses `inherit_authorization`
- [Pundit Module](../modules/pundit.md) - Uses `inherit_authorization`
- [ActionPolicy Module](../modules/action_policy.md) - Uses `inherit_authorization`

## Summary

| Option | Default | Purpose |
|--------|---------|---------|
| `inherit_settings` | `true` | Child classes inherit parent settings |
| `inherit_authorization` | `true` | Child settings inherit parent auth rules |
