# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.7.0] - 2025-11-01

### Added
- **Module Development Contract**: Complete API for creating external modules
  - ModuleRegistry API fully documented with lifecycle hooks
  - `register_module`: Register custom modules for tracking
  - `register_option`: Register custom DSL options with validators
  - `register_exclusive_group`: Define mutually exclusive modules
  - `check_exclusive_conflict!`: Prevent conflicting module inclusion
  - `extend_setting`: Add methods to Setting class
  - Lifecycle hooks: `on_setting_defined`, `on_settings_compiled`, `before_setting_change`, `after_setting_change`
  - 12 new comprehensive tests for ModuleRegistry (37 total examples)
  - Integration tests for full module lifecycle

- **Rails Generator for Modules**: Create custom modules with `rails generate`
  - Command: `rails generate model_settings:module ModuleName`
  - Options: `--skip-tests`, `--skip-docs`, `--exclusive-group=NAME`, `--options=name:type`
  - Auto-generates module implementation with TODO comments
  - Auto-generates RSpec tests following project conventions
  - Auto-generates comprehensive markdown documentation
  - Support for custom option types: symbol, boolean, string, array, hash
  - Smart name conversion (CamelCase ↔ snake_case)
  - 180 lines of generator tests

- **Configuration Auto-Include**: New method for default module inclusion
  - `auto_include_default_modules` method for including default modules automatically
  - Configurable list of modules to include by default
  - 13 comprehensive RSpec examples
  - Simplifies common module inclusion patterns

### Documentation
- **Created `docs/guides/module_development.md`**: Comprehensive module development guide
  - Complete API reference for ModuleRegistry (850 lines)
  - Lifecycle hooks documentation with execution order
  - Best practices for module development (8 key guidelines)
  - Complete working example: AuditTrail module
  - Testing guidance and patterns
  - Quick start with generator instructions


### Generator Templates
- **`lib/generators/model_settings/module/templates/module.rb.tt`**: Module implementation template
  - Complete module structure with all lifecycle hooks
  - Support for exclusive groups and custom options
  - ClassMethods and instance methods scaffolding
  - TODO comments guiding implementation

- **`lib/generators/model_settings/module/templates/module_spec.rb.tt`**: RSpec test template
  - Module registration tests
  - Exclusive group conflict tests
  - Custom option registration and validation tests
  - Lifecycle hooks tests
  - 150+ lines of test scaffolding

- **`lib/generators/model_settings/module/templates/module_docs.md.tt`**: Documentation template
  - Installation and usage sections
  - Available options reference
  - Class and instance methods documentation
  - Examples (basic and advanced)
  - Configuration and troubleshooting sections

### Test Coverage
- 985 total examples (up from 955)
- +30 new tests (12 ModuleRegistry + 13 Configuration + 5 generator integration)
- All tests passing with 0 failures
- 0 linter offenses

### Changed
- ModuleRegistry now has comprehensive test coverage for all hook types
- Configuration module enhanced with auto-include functionality
- Sprint roadmap reorganized for clarity (Sprint 13: Authorization, Sprint 14: I18n + Polish)

### Breaking Changes Policy
- **Pre-1.0 Policy Established**: Breaking changes allowed freely before v1.0
- No real users yet, so no compatibility constraints
- Freedom to improve API, refactor architecture, change defaults
- After v1.0: Strict SemVer with deprecation periods

## [0.6.0] - 2025-10-31

### Added
- **Metadata Query API**: Advanced methods for querying settings by metadata
  - `with_metadata(key)`: Spec-compliant alias for `settings_with_metadata_key`
  - `without_metadata(key)`: Find settings WITHOUT a specific metadata key
  - `where_metadata(key, equals:)`: Filter by exact metadata value match
  - `where_metadata(key, includes:)`: Filter by array metadata inclusion
  - `where_metadata { |meta| ... }`: Custom block filters with complex logic
  - `where_metadata`: Returns all settings (no filter)
  - 21 comprehensive RSpec examples
  - Full backward compatibility with existing methods

- **Setting Helper Methods**: New metadata query helpers on Setting class
  - `has_metadata?(key)`: Check if setting has metadata key (supports symbol/string)
  - `metadata_value(key)`: Get metadata value (supports symbol/string keys)
  - `metadata_includes?(key, value)`: Check if array metadata includes value
  - Used internally by query methods for cleaner implementation

- **Around Callbacks**: Wrap setting operations with timing, transactions, or abortion
  - `around_enable`: Wraps enable operation
  - `around_disable`: Wraps disable operation
  - `around_change`: Wraps any value change
  - Must call `yield` to execute the wrapped operation
  - Can abort operations by not yielding
  - Perfect for timing measurements, transaction wrapping, conditional execution
  - Integrated into all adapters (Column, JSON, StoreModel)
  - 8 comprehensive RSpec examples covering Symbol callbacks, abort scenarios, integration tests

- **Callback Execution Order Tests**: Comprehensive test coverage for callback execution flow
  - Test correct execution order: before → around_start → after → around_end
  - Test around callback abort scenarios (not yielding stops execution)
  - Test value assignment happens between around callback wrapping
  - 4 comprehensive RSpec examples validating execution order guarantees

### Documentation
- **Updated `docs/core/queries.md`**:
  - Added `with_metadata`, `without_metadata`, `where_metadata` documentation
  - Detailed examples for `equals:`, `includes:`, and block filters
  - Use cases and best practices
  - Updated Summary table with new methods

- **Updated `docs/core/callbacks.md`**:
  - Added comprehensive "Around Callbacks" section
  - Basic usage with timing example
  - Aborting operations pattern
  - Transaction wrapping examples
  - Error handling in around callbacks
  - Multiple around callbacks limitation (only first executes)
  - Updated execution order diagram with around callbacks
  - Updated Summary table with around callback types

- **Created `docs/architecture/metadata_query_api.md`**:
  - Complete design document for Metadata Query API
  - API completeness matrix
  - Implementation details
  - Performance considerations
  - Migration path for existing code
  - Non-goals and future enhancements

### Changed
- Callback execution order now includes around callbacks wrapping the operation
- Query module enhanced with spec-compliant metadata query methods
- All adapters (Column, JSON, StoreModel) now support around callbacks
- Column adapter: `after_enable`/`after_disable` callbacks moved inside around callback block
  - Ensures after callbacks only execute if around callback yields
  - Enables proper abort behavior when around callback doesn't yield

### Test Coverage
- 955 total examples (up from 916)
- +39 new tests (21 query + 8 around callback + 10 refactored + 4 execution order tests)
- All tests passing with 100% backward compatibility

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
