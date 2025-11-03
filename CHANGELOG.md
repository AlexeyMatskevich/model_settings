# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **Test Coverage Improvements** (Phase 1 Critical Gaps): Comprehensive tests for previously untested components
  - **BooleanValueValidator**: 19 unit tests for strict boolean validation (rejects type coercion, validates true/false/nil)
  - **BooleanValueValidator Integration**: 17 integration tests across all adapters (Column, JSON, StoreModel)
  - **SimpleAudit Module**: 38 tests covering complete module lifecycle
    - Module registration and option validation (4 tests)
    - Callback configuration and global settings (5 tests)
    - Compilation-time indexing for tracked settings (6 tests)
    - Class methods for querying tracked settings (8 tests)
    - Runtime audit behavior with Rails.logger integration (9 tests)
    - Callback timing integration (:before_save, :after_save, :after_commit) (6 tests)
  - Fixed bug in SimpleAudit: use `get_option(:track_changes)` instead of non-existent accessor
  - Updated ModuleRegistry spec to use RegistryStateHelper for proper test isolation
  - All 1300 tests passing (was 955), 0 failures, 6 pending
  - Coverage: 72 new tests eliminating all critical gaps (HIGH RISK components now covered)

- **Test Coverage Improvements** (Phase 2 High Priority): Integration and cross-adapter consistency tests
  - **Module Callback Integration**: 12 end-to-end tests for callback configuration system
    - Default callback timing verification (:before_save default)
    - Configured callback timing (:after_save, :after_commit)
    - Global configuration persistence across models
    - Independent module configuration
    - Interaction with dependency compilation and metadata availability
  - **Cross-Adapter Validation**: 7 consistency tests across Column and JSON adapters
    - BooleanValueValidator consistency (rejection, error messages, acceptance)
    - Default value consistency
    - Change tracking (dirty tracking) consistency
    - Helper methods consistency (enable!/disable!/toggle!)
    - Query methods consistency (enabled?/disabled?)
  - All 1298 tests passing (added 19 new tests), 0 failures, 6 pending
  - Coverage: Verified module callback system and adapter parity

- **Merge Strategies for Option Inheritance** (Phase 3): Configurable merge behavior for nested settings
  - Three merge strategies with automatic validation:
    - `:replace` (default) - Child value completely replaces parent value
    - `:append` - Arrays concatenated (parent + child), validates both are Arrays
    - `:merge` - Hashes deep merged (child keys override parent), validates both are Hashes
  - `ModuleRegistry.register_inheritable_option(:name, merge_strategy:)`: Register options with merge behavior
  - `ModuleRegistry.merge_strategy_for(:option_name)`: Get registered merge strategy for an option
  - `Setting.merge_inherited_options(parent_options, child_options)`: Apply merge strategies to options
  - Automatic type validation raises ArgumentError if parent/child types don't match strategy requirements
  - Built-in module strategies: Roles (`:viewable_by`, `:editable_by` use `:append`), Pundit/ActionPolicy (`:authorize_with` uses `:replace`)
  - Backwards compatible: defaults to `:replace` for unregistered options
  - 31 new tests in merge_strategies_spec.rb (all strategies, nil handling, type validation, mixed strategies)
  - 12 new tests in metadata_cascade_inheritance_spec.rb (:metadata and :cascade inheritance verification with multi-level nesting)
  - All 1341 tests passing (was 1298, +43 new tests), 0 failures, 6 pending

- **Configurable Inheritable Options** (Phase 4): Automatic option inheritance for nested settings
  - Three-level configuration system: Global → Module → Model
  - `Configuration.inheritable_options = [...]`: Explicitly set which options nested settings inherit
  - `Configuration.add_inheritable_option(:name)`: Add option to auto-populated list (preserves module registration)
  - `Configuration.inheritable_options_explicitly_set?`: Check if user has taken explicit control
  - `ModuleRegistry.register_inheritable_option(:name, merge_strategy:, auto_include:)`: Modules register their options as inheritable with merge behavior (see Phase 3 for merge strategies)
  - `ModuleRegistry.inheritable_option?(:name)`: Check if option is registered as inheritable
  - `DSL.settings_config(inheritable_options: [...])`: Per-model override of inheritable options
  - `DSL.inheritable_options`: Get effective inheritable options for a model (merged from all sources)
  - Built-in modules auto-register: Roles (`:viewable_by`, `:editable_by` with `:append`), Pundit/ActionPolicy (`:authorize_with` with `:replace`)
  - Explicit user configuration **completely replaces** auto-population (by design - user has full control)
  - 51 new tests across 4 files (configuration: 13, module_registry: 9, dsl: 10, integration: 19)
  - All tests passing with merge strategies integration (see Phase 3 for total test count)

- **Module API Centralization** (Phase 3.5): Unified metadata storage and module tracking
  - Centralized `_module_metadata` storage replacing per-module class_attributes
  - `ModuleRegistry.set_module_metadata(model_class, module_name, setting_name, value)`: Store metadata centrally
  - `ModuleRegistry.get_module_metadata(model_class, module_name, setting_name = nil)`: Retrieve metadata
  - `ModuleRegistry.module_metadata?(model_class, module_name, setting_name)`: Check metadata presence
  - Converted all modules (Roles, Pundit, ActionPolicy) to use `on_setting_defined` hooks instead of `setting()` overrides
  - Fixed `module_included?` to use `_active_modules` symbol registry (stable across RSpec module reloads)
  - Updated documentation formatters to use centralized metadata API
  - All 1124 tests passing

- **Module Callback Configuration API**: Global configuration for module Rails callbacks
  - `ModuleRegistry.register_module_callback_config(module_name, default_callback:, configurable:)`: Modules declare callback preferences
  - `ModuleRegistry.get_module_callback(module_name)`: Get active callback (respects global config)
  - `Configuration.module_callback(module_name, callback_name)`: Configure callbacks globally
  - Modules can specify default callback and whether it's user-configurable
  - Example: Configure Pundit to use `:before_save` instead of default `:before_validation`
  - 19 new tests (10 for ModuleRegistry, 9 for Configuration)
  - Documentation in `docs/guides/module_development.md` and `docs/core/configuration.md`

- **Wave-Based Compilation**: Settings compiled by nesting level for proper dependency resolution
  - Settings grouped by depth (0 for root, 1+ for nested) and compiled in waves
  - Parent settings fully set up before children are processed
  - Enables child settings to access parent settings during validation
  - Deferred adapter setup from `setting()` to `compile_settings!`
  - Auto-compile on instance initialization (before attribute assignment)
  - Early validation for storage configuration and type
  - 17 new tests in `spec/model_settings/wave_compilation_spec.rb`
  - Documentation in `docs/core/dsl.md` with compilation order examples

- **Rails Lifecycle Callbacks**: Integration with Rails model lifecycle
  - New callbacks: `before_validation`, `after_validation`, `before_destroy`, `after_destroy`, `after_change_rollback`
  - Callback options: `:if`, `:unless` (conditional execution), `:on` (lifecycle phase), `:prepend` (execution order)
  - Phase parameter in `execute_setting_callbacks` for `:on` option filtering
  - `should_execute_callback?` method for condition evaluation
  - 13 new callback tests covering all features
  - Documentation in `docs/core/callbacks.md`

- **DSL Helpers for Module Development**: Simplified API for accessing module functionality
  - `get_module_metadata(module_name, setting_name = nil)`: Retrieve module metadata (wrapper around ModuleRegistry)
  - `module_metadata?(module_name, setting_name)`: Check if module has metadata for a setting
  - `settings_check_exclusive_conflict!(module_name)`: Check for conflicts with other modules
  - Available in ClassMethods and `included do` blocks where `self` is the model class
  - Reduces boilerplate: `get_module_metadata(:roles)` vs `ModelSettings::ModuleRegistry.get_module_metadata(self, :roles)`
  - Updated all authorization modules (Roles, Pundit, ActionPolicy) to use new helpers
  - Comprehensive documentation in module development guide

- **Query Method Registry**: Introspection API for discovering module methods
  - `register_query_method(module_name, method_name, scope, metadata)`: Register methods provided by modules
  - `query_methods_for(module_name)`: Get all methods a module provides
  - `query_methods`: Get all registered query methods across all modules
  - Similar to ActiveRecord's columns/associations introspection
  - 16 query methods registered across 4 modules (Roles: 4, Pundit: 3, ActionPolicy: 3, I18n: 6)
  - Enables IDE hints, auto-documentation, and debugging tools

- **YAML and HTML Documentation Formats**: Extended documentation generator with new output formats
  - `YamlFormatter`: Generate YAML documentation for configuration management and IaC
  - `HtmlFormatter`: Generate styled HTML documentation for wikis and documentation sites
  - Both formatters support all existing documentation features (authorization, deprecation, cascades, syncs, callbacks)
  - HTML formatter includes XSS protection with proper HTML escaping
  - Updated rake tasks to support FORMAT=yaml and FORMAT=html
  - 10 new comprehensive tests (110 total documentation examples)

- **Validation Timing Configuration** (Phase 6): Configurable error reporting during settings compilation
  - Two validation modes for different development contexts:
    - `:strict` mode (default in production) - Fail fast on first validation error during setting definition
    - `:collect` mode (default in development/test) - Collect all validation errors and report together during compilation
  - `Configuration.validation_mode = :strict | :collect`: Set validation mode globally
  - `Configuration.validation_mode`: Get current validation mode
  - Auto-detection based on `Rails.env` (development/test → :collect, production → :strict)
  - Validation deferred to `compile_settings!` in :collect mode for comprehensive error reporting
  - Immediate validation during `setting()` in :strict mode for fast feedback
  - Only validates settings that need their own adapter (skips nested JSON/StoreModel without storage)
  - Aggregated error messages with setting names and detailed fix suggestions
  - 27 comprehensive tests covering both modes, mode switching, and all adapter types
  - Documentation in `docs/core/configuration.md` with examples and usage recommendations
  - All 1353 tests passing (was 1356, -3 duplicate tests removed during test polishing)

- **Test Quality Improvements**: Comprehensive test polishing across all uncommitted test files
  - Applied Test Polishing Guidelines (3-step process) from implementation roadmap to 13 uncommitted test files
  - **Files Fully Polished** (6 files with structural improvements):
    - boolean_value_validator_spec.rb: Removed 2 duplicate tests, restructured invalid values by type
    - simple_audit_spec.rb (766 lines, 38 tests): Restructured 3 blocks with logical grouping
    - module_callback_integration_spec.rb: Restructured all 3 blocks with nested describes
    - cross_adapter_validation_spec.rb: Fixed happy path ordering (valid before invalid)
    - merge_strategies_spec.rb: Reordered 2 blocks for happy path first
    - validation_timing_spec.rb: Removed 3 duplicate tests, eliminated procedural begin/rescue patterns, applied "but when"/"and when" naming for proper test flow
  - **Files Verified Excellent** (7 files, no changes needed):
    - metadata_cascade_inheritance_spec.rb: Already perfectly structured
    - Phase 3 modified files (column/json/store_model/configuration/module_registry/roles/setting specs): All follow RSpec best practices
  - Applied consistent naming patterns: "but when..." (reverse cases), "and when..." (additional errors)
  - 0 critical RSpec/NestedGroups violations across all 13 files
  - **Final Test Suite**: 1353 examples, 0 failures, 6 pending (was 1341 after Phase 3, +27 from Phase 6, -15 from polishing adjustments)

### Changed
- **Module Reloading Documentation**: Added comprehensive comments explaining symbol-based module tracking
  - Documented why `_active_modules` uses symbols instead of Module objects
  - Explained module reloading problem in RSpec and development mode
  - Added examples showing object identity changes during reload
  - Comments in `ModuleRegistry.module_included?`, `DSL._active_modules`, and `DSL.settings_add_module`

### Documentation
- **Updated `docs/core/configuration.md`**: Added `inheritable_options` section
  - Complete API reference for configuring inheritable options (130+ lines)
  - Two approaches: auto-population (default) vs explicit control
  - Per-model override via `settings_config`
  - Clear warnings about explicit setting **completely replacing** auto-population
  - Examples with all three configuration levels
  - When to use each approach comparison table
  - Cross-references to `inheritance.md` and `module_development.md`

- **Updated `docs/core/inheritance.md`**: Added "Option Inheritance in Nested Settings" section
  - Comprehensive explanation of option inheritance (150+ lines)
  - Distinction between Class Inheritance (STI) vs Option Inheritance (nested settings)
  - Multi-level inheritance examples with authorization options
  - Overriding inherited options in child settings
  - Complete example with Roles module showing all inheritance scenarios
  - Updated Summary to cover both inheritance types
  - Cross-references to Configuration documentation

- **Updated `docs/guides/module_development.md`**: Added inheritable options registration guide
  - `register_inheritable_option` API documentation
  - ⚠️ **Critical warning**: User can completely disable module's inheritance
  - Three user choice scenarios (auto-population, explicit inclusion, disable)
  - When to use inheritable options (authorization, metadata that cascades)
  - Module developer guidance: don't assume inheritance will work
  - Complete Roles module example showing registration
  - Cross-references to Configuration and Inheritance documentation

- **Updated `docs/guides/module_development.md`**: Added DSL Helpers section with usage guidelines
  - New section explaining when to use helpers vs. direct ModuleRegistry calls
  - Examples showing both approaches with recommendations
  - Updated all code examples to use recommended helpers
  - Clear explanation of context (ClassMethods, included blocks, hooks)

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
