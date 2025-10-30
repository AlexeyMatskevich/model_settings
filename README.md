# ModelSettings

Declarative configuration management DSL for Rails models with support for multiple storage backends, authorization, validation, and extensible module integration.

## 📚 Documentation

- **[Getting Started Guide](docs/guides/getting_started.md)** - Complete beginner guide
- **[Migration Guide](docs/guides/migration.md)** - Migrate from boolean columns, JSON, or feature flags
- **[Complete Documentation](docs/README.md)** - Full documentation index
- **[CHANGELOG](CHANGELOG.md)** - Version history and release notes

### Quick Links

| Topic | Documentation |
|-------|---------------|
| Storage Options | [Adapters Guide](docs/core/adapters.md) (Column, JSON, StoreModel) |
| Cascades & Syncs | [Dependencies Guide](docs/core/dependencies.md) |
| Authorization | [Roles](docs/modules/roles.md), [Pundit](docs/modules/pundit.md), [ActionPolicy](docs/modules/action_policy.md) |
| Settings Inheritance | [Inheritance Guide](docs/core/inheritance.md) |
| Auto-Generate Docs | [Documentation Module](docs/modules/documentation.md) |

## Features

- **Multiple Storage Backends**: Column, JSON/JSONB, and StoreModel support
- **Flexible DSL**: Clean, declarative syntax for defining settings
- **Authorization**: Built-in Roles (RBAC), Pundit, and ActionPolicy modules
- **Dependency Management**: Cascades, syncs, and cycle detection
- **Settings Inheritance**: Automatic inheritance across model hierarchies
- **Documentation Generator**: Auto-generate Markdown/JSON documentation
- **Validation Framework**: Strict boolean validation and custom validators
- **Callback System**: before_enable, after_change, after_commit hooks
- **Dirty Tracking**: Full change tracking across all storage types
- **Query Interface**: Find and filter settings by metadata
- **Deprecation Tracking**: Built-in deprecation warnings and audit
- **I18n Support**: Full internationalization
- **Mixed Storage**: Parent-child relationships across storage types

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'model_settings'
```

And then execute:

```bash
bundle install
```

## Quick Start

### Column Storage

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  setting :premium, type: :column, default: false
end

user.premium_enable!
user.premium_toggle!
user.premium_changed?  # => true
```

### JSON Storage

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  setting :preferences, type: :json, storage: {column: :prefs_data} do
    setting :theme, default: "light"
    setting :notifications, default: true
  end
end

user.theme = "dark"
user.notifications = false
user.save!
```

### Cascades

```ruby
setting :premium, cascade: {enable: true} do
  setting :advanced_analytics
  setting :priority_support
end

user.premium = true
user.save!
# Children automatically enabled!
```

### Authorization

```ruby
include ModelSettings::Modules::Roles

setting :billing,
        viewable_by: [:admin, :finance],
        editable_by: [:admin]

user.can_edit_setting?(:billing, :admin)  # => true
```

### Documentation Generation

```bash
rake settings:docs:generate
rake settings:audit:deprecated
```

## Core Concepts

### Storage Adapters

Choose the right backend for your needs:

- **[Column](docs/core/adapters.md#column-adapter)** - Individual database columns, fast queries
- **[JSON](docs/core/adapters.md#json-adapter)** - Multiple settings in JSONB, flexible schema
- **[StoreModel](docs/core/adapters.md#storemodel-adapter)** - Typed nested objects with validation

See [complete adapter comparison](docs/core/adapters.md).

### Dependencies

- **[Cascades](docs/core/dependencies.md#cascades)** - Auto-enable/disable children
- **[Syncs](docs/core/dependencies.md#syncs)** - Keep settings synchronized (forward/inverse/backward)
- **[Cycle Detection](docs/core/dependencies.md#cycle-detection)** - Prevents circular dependencies at boot

### Authorization

Three modules for different needs:

- **[Roles](docs/modules/roles.md)** - Simple RBAC with `viewable_by`/`editable_by`
- **[Pundit](docs/modules/pundit.md)** - Policy-based authorization
- **[ActionPolicy](docs/modules/action_policy.md)** - Rule-based authorization

**Important**: Authorization modules are mutually exclusive (use only one).

### Settings Inheritance

Child classes automatically inherit parent settings:

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL
  setting :notifications, type: :column
end

class PremiumUser < User
  # Inherits :notifications
  setting :advanced_features, type: :column
end
```

See [complete inheritance guide](docs/core/inheritance.md).

## Validation & Callbacks

- **[Validation](docs/core/validation.md)** - Strict boolean validation + custom validators
- **[Callbacks](docs/core/callbacks.md)** - before_enable, after_change, after_commit

## Usage Examples

See real-world examples:

- [Feature Flags](docs/usage_cases/feature_flags.md) - Boolean toggles with gradual rollout
- [User Preferences](docs/usage_cases/user_preferences.md) - Preference storage with JSON
- [Multi-Tenancy](docs/usage_cases/multi_tenancy.md) - Organization-level configuration
- [API Settings](docs/usage_cases/api_settings.md) - API keys and rate limits with StoreModel
- [Admin Panels](docs/usage_cases/admin_panels.md) - Building settings management UIs

## Best Practices

See [complete best practices guide](docs/guides/best_practices.md):

- Choose storage based on query patterns
- Use cascades for hierarchical features
- Use syncs for related settings
- Avoid circular dependencies
- Add metadata and descriptions
- Use `after_change_commit` for external APIs

## Roadmap

### Completed ✅

- StoreModel adapter
- Dependency Engine (cascades, syncs, cycle detection)
- Mixed Storage Types
- Authorization modules (Roles, Pundit, ActionPolicy)
- Documentation Generator
- Settings Inheritance
- **Feature-complete status achieved**

## Development

### Running Tests

```bash
bundle exec rspec
# 872 examples, 0 failures ✅
```

### Code Quality

```bash
bundle exec standardrb        # Check style
bundle exec standardrb --fix  # Auto-fix
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/AlexeyMatskevich/model_settings.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
