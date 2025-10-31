# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.5.0] - 2025-10-31

### Added
- **JSON Array Membership Pattern**: Store settings as string values in JSON arrays
  - New `array: true` storage option for JSON settings
  - Getter returns `true` if value is in array, `false` otherwise
  - Setter adds/removes value from array
  - Custom array values via `array_value` option (for legacy compatibility and renaming)
  - Full dirty tracking support (`_changed?`, `_was`, `_change`)
  - Helper methods (`enable!`, `disable!`) work seamlessly
  - Multiple settings can share the same array column
  - Automatic array type validation
  - 24 comprehensive RSpec examples
  - Perfect for feature flags and permission management

- **Array Type Validator**: New validator for ensuring array types
  - `validates :column, array_type: true` syntax
  - Allows `nil` values
  - Rejects non-array types with "must be an array" error message
  - 13 comprehensive RSpec examples

### Documentation
- Added JSON Array Membership section to README with complete examples
- Added comprehensive Array Membership Pattern section to `docs/core/adapters.md`
  - Basic usage and migration examples
  - Custom array values for legacy compatibility
  - Migration guide for renaming settings
  - Multiple settings sharing same array
  - Validation examples
  - When to use / when to avoid guidance

### Changed
- JSON adapter now detects and handles `array: true` storage option
- JSON adapter validates array columns automatically (no duplicate validations)

## [0.4.0] - 2025-10-31

### Added
- **Settings Inheritance**: Automatic settings inheritance across model hierarchies
  - Child classes inherit all parent settings automatically
  - Override support for defaults, descriptions, and all options
  - Multi-level inheritance (grandparent → parent → child)
  - Works with all storage types (Column, JSON, StoreModel)
  - Preserves nested setting hierarchies
  - Full adapter creation for inherited settings
  - 43 comprehensive RSpec examples with 100% pass rate

- **Documentation Generator Module**: Auto-generate documentation from settings
  - Generate Markdown, JSON, and YAML formats
  - Filter by active/deprecated settings or custom predicates
  - Includes all setting metadata: type, storage, defaults, authorization, cascades
  - Rake tasks: `settings:docs:generate` and `settings:docs:list_deprecated`
  - CI-friendly: deprecation audit exits with code 1 if deprecated settings found
  - 71 comprehensive RSpec examples

### Changed
- Removed UI Module and Plans Module from documentation (not implemented)
- Polished RSpec test coverage across all modules

## [0.3.0] - 2025-10-31

### Added
- **ActionPolicy Module**: Seamless ActionPolicy integration
  - `authorize_with` option for settings to specify policy rules
  - Class methods: `authorization_for_setting`, `settings_requiring`, `authorized_settings`
  - Helper methods for policies: `permitted_settings`
  - Integration with ActionPolicy's `params_filter`
  - Strict validation: only Symbol values allowed (no arrays, procs, or strings)
  - Comprehensive RSpec tests with 63 examples

- **Shared Examples for Authorization**: Reusable test patterns
  - `settings_authorization` shared example for all auth modules
  - Eliminates test duplication across Roles, Pundit, and ActionPolicy modules
  - Tests module inclusion, option validation, query methods, and edge cases

## [0.2.0] - 2025-10-30

### Added
- **Pundit Module**: Seamless Pundit integration for authorization
  - `authorize_with` option for settings to specify policy methods
  - Class methods: `authorization_for_setting`, `settings_requiring`, `authorized_settings`
  - Helper methods for policies: `permitted_settings`
  - Integration with Pundit's `permitted_attributes`
  - Strict validation: only Symbol values allowed (no arrays, procs, or strings)
  - Comprehensive RSpec tests with 63 examples

- **Roles Module**: Role-based access control (RBAC) for settings
  - `viewable_by` and `editable_by` options for settings
  - Support for `:all` role (public access)
  - Role inheritance for nested settings
  - Class methods: `settings_viewable_by`, `settings_editable_by`
  - Instance methods: `can_view_setting?`, `can_edit_setting?`
  - Setting extensions: `viewable_by?`, `editable_by?` on Setting objects
  - Integration with ModuleRegistry for exclusive auth module checking
  - Comprehensive RSpec tests with 112 examples

### Changed
- Polished and refactored specs for Validation, Callbacks, Query, Deprecation, and I18n modules
- All specs follow RSpec best practices: aggregate_failures, proper symmetry, characteristic-based context organization


## [0.1.0] - 2025-10-28

### Added
- **Initial Release**: Core ModelSettings DSL framework
- **Column Adapter**: Support for database column storage
  - Boolean settings with getter/setter methods
  - Helper methods: `enable!`, `disable!`, `toggle!`, `enabled?`, `disabled?`
  - Full dirty tracking integration
- **DSL Basics**:
  - `setting` method for defining settings
  - Support for `type`, `default`, and `storage` options
  - Nested settings with parent-child relationships
  - Setting metadata and options
- **Query Interface**: Find and filter settings
  - `find_setting` by name or path
  - `settings_by_type`, `settings_with_callbacks`
  - `settings_where`, `settings_matching`
  - `settings_grouped_by_metadata`
  - Root/leaf setting queries
- **Validation Framework**:
  - Built-in validations
  - Custom validators with `validate_with` option
  - `add_setting_error` helper method
- **Callback System**:
  - `before_enable`, `after_enable`
  - `before_disable`, `after_disable`
  - `before_change`, `after_change`
  - `after_change_commit` with ActiveRecord integration
- **Deprecation Tracking**:
  - Mark settings as deprecated
  - Automatic warnings when deprecated settings accessed
  - `deprecated_settings`, `deprecation_report` methods
- **I18n Support**:
  - Automatic translation key lookup
  - `t_label_for`, `t_description_for`, `t_help_for` methods
  - Custom translation keys support
- **ModuleRegistry**:
  - Module registration system
  - Exclusive group checking (e.g., authorization modules)
  - Conflict detection
- **Configuration**: Global configuration system
  - `ModelSettings.configure` block
  - `inherit_settings` option (default: true)
- **Test Infrastructure**:
  - In-memory SQLite test database
  - Shared adapter examples
  - Comprehensive RSpec coverage

### Dependencies
- Ruby >= 2.7
- Rails >= 5.2
- ActiveRecord
- ActiveSupport

## Release Notes

### Upgrade Guide for 0.4.0

**Settings Inheritance** is now enabled by default. If you have existing STI models with settings, inheritance works automatically.

**Documentation Generator** provides new rake tasks for generating docs and auditing deprecated settings.

### Compatibility

- Ruby 2.7+ (tested on 2.7, 3.0, 3.1, 3.2, 3.3)
- Rails 5.2+ (tested on 5.2, 6.0, 6.1, 7.0, 7.1)
- ActiveRecord 5.2+
- PostgreSQL (recommended for JSONB), MySQL, SQLite

### Breaking Changes

None in 0.x releases. The gem maintains backward compatibility.

## Future Roadmap

**Current Status**: ~40% complete, alpha stage

### Completed ✅
- Column, JSON, and StoreModel adapters
- Dependency Engine (cascades, syncs, cycle detection)
- Authorization modules (Roles, Pundit, ActionPolicy)
- Settings Inheritance
- Documentation Generator
- Comprehensive test suite (872 examples, 0 failures)

### Planned
- Advanced query capabilities
- Performance optimizations
- Additional modules (Plans, UI helpers)
- More usage examples
- Production hardening
- 1.0 release preparation

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for details on how to contribute.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
