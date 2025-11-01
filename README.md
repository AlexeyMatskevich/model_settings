# ModelSettings

Declarative configuration management DSL for Rails models with support for multiple storage backends, authorization, validation, and extensible module integration.

## 📚 Documentation

**[Complete Documentation →](docs/README.md)** | **[Getting Started Guide →](docs/guides/getting_started.md)** | **[CHANGELOG →](CHANGELOG.md)**

### Quick Links

| Topic | Documentation |
|-------|---------------|
| Storage Options | [Adapters Guide](docs/core/adapters.md) - Column, JSON, StoreModel |
| Cascades & Syncs | [Dependencies Guide](docs/core/dependencies.md) |
| Authorization | [Roles](docs/modules/roles.md), [Pundit](docs/modules/pundit.md), [ActionPolicy](docs/modules/action_policy.md) |
| Settings Inheritance | [Inheritance Guide](docs/core/inheritance.md) |
| Validation & Callbacks | [Validation](docs/core/validation.md), [Callbacks](docs/core/callbacks.md) |
| Deprecation Management | [Deprecation Guide](docs/guides/deprecation.md) - Audit & migrate deprecated settings |
| Performance | [Performance Guide](docs/guides/performance.md) - Benchmarks & optimization |
| **Module Development** | [Module Development Guide](docs/guides/module_development.md) - Create custom modules |
| Real-World Examples | [Usage Cases](docs/usage_cases/) |

## Features

- **Multiple Storage Backends** - Column, JSON/JSONB, and StoreModel adapters
- **Dependency Management** - Cascades, syncs, and cycle detection
- **Authorization** - Built-in Roles (RBAC), Pundit, and ActionPolicy modules
- **Settings Inheritance** - Automatic inheritance across model hierarchies
- **Validation Framework** - Strict boolean validation and custom validators
- **Callback System** - before_enable, after_change, after_commit hooks
- **Dirty Tracking** - Full change tracking across all storage types
- **Documentation Generator** - Auto-generate Markdown/JSON documentation
- **Deprecation Management** - Mark settings as deprecated and audit real usage
- **Query Interface** - Find and filter settings by metadata
- **I18n Support** - Full internationalization
- **Module Development API** - Create custom modules with Rails generator

## Installation

Add to your Gemfile:

```ruby
gem 'model_settings'
```

Then run:

```bash
bundle install
```

## Quick Start

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  # Column storage - one setting per column
  setting :premium, type: :column, default: false

  # JSON storage - multiple settings in one JSONB column
  setting :preferences, type: :json, storage: {column: :prefs_data} do
    setting :theme, default: "light"
    setting :notifications, default: true
  end

  # Cascades - enable children automatically
  setting :enterprise, type: :column, cascade: {enable: true} do
    setting :advanced_analytics, type: :column, default: false
    setting :priority_support, type: :column, default: false
  end
end

# Usage
user = User.create!

# Helper methods
user.premium_enable!
user.premium_toggle!
user.premium_changed?  # => true

# JSON settings
user.theme = "dark"
user.notifications = false
user.save!

# Cascades
user.enterprise = true
user.save!
user.advanced_analytics  # => true (auto-enabled!)
```

**[→ See more examples in Getting Started Guide](docs/guides/getting_started.md)**

## Storage Adapters

Choose the right backend for your needs:

| Adapter | Best For | Documentation |
|---------|----------|---------------|
| **Column** | Feature flags, individual toggles | [Column Adapter →](docs/core/adapters/column.md) |
| **JSON** | Related settings, flexible schema | [JSON Adapter →](docs/core/adapters/json.md) |
| **StoreModel** | Complex nested configs, type safety | [StoreModel Adapter →](docs/core/adapters/store_model.md) |

**[→ See complete adapter comparison](docs/core/adapters.md)**

## Authorization

Three modules for different needs (mutually exclusive):

```ruby
# Simple RBAC
include ModelSettings::Modules::Roles
setting :billing, viewable_by: [:admin, :finance], editable_by: [:admin]

# Pundit integration
include ModelSettings::Modules::Pundit
setting :api_access, authorize_with: :manage?

# ActionPolicy integration
include ModelSettings::Modules::ActionPolicy
setting :admin_panel, authorize_with: :admin_access?
```

**[→ See authorization guides](docs/modules/)**

## Documentation & Deprecation Management

Auto-generate documentation and manage deprecated settings:

```bash
# Generate Markdown documentation
rake settings:docs:generate

# List all deprecated settings
rake settings:docs:list_deprecated

# Audit deprecated settings usage in database
rake settings:audit:deprecated
```

**[→ See Documentation Module guide](docs/modules/documentation.md)**
**[→ See Deprecation Management guide](docs/guides/deprecation.md)**

## Module Development

Create custom modules with Rails generator:

```bash
rails generate model_settings:module AuditTrail
```

**[→ See Module Development Guide](docs/guides/module_development.md)**

## Roadmap

### Completed ✅

- ✅ Sprint 1-10: Core features (adapters, dependencies, validation, callbacks, inheritance)
- ✅ Sprint 9: JSON Array Membership implementation
- ✅ Sprint 10: Metadata Query API & Around Callbacks
- ✅ Sprint 11: Module Development API & Rails Generator (v0.7.0)
- ✅ Authorization modules (Roles, Pundit, ActionPolicy)
- ✅ Documentation Generator module
- ✅ I18n module
- ✅ Comprehensive documentation structure

**Current Status**: v0.7.0 - 985 tests passing, ~75% spec compliance

### Next Up

- 🔄 Sprint 12: Tooling & Production Hardening (v0.8.0)
- 🔄 Sprint 13: Authorization Inheritance System (v0.9.0)
- 🔄 Sprint 14: I18n Dual API & Final Polish (v0.9.x)
- ⏳ v1.0: Manual review and release decision

**Note**: Pre-1.0 versions allow breaking changes for API improvements.

## Development

### Running Tests

```bash
bundle exec rspec
```

### Code Quality

```bash
bundle exec standardrb
```

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/my-feature`)
3. Write tests for your changes
4. Ensure all tests pass and code style is correct
5. Commit your changes (`git commit -am 'Add new feature'`)
6. Push to the branch (`git push origin feature/my-feature`)
7. Create a Pull Request

## License

The gem is available as open source under the terms of the [MIT License](LICENSE.txt).
