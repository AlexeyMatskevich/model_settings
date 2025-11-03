# Known Issues and Limitations

This document lists known issues, limitations, and edge cases in ModelSettings v0.9.0.

**Last Updated**: 2025-11-04 (v0.9.0)

---

## Known Limitations

### 1. Authorization is Opt-In (BY DESIGN)

**Status**: NOT A BUG - By Design

**Description**:
Helper methods (`enable!`, `disable!`, `toggle!`) and direct attribute assignment do **NOT** enforce authorization checks automatically. Authorization must be enforced at the controller layer.

**Example**:
```ruby
# ❌ INSECURE: No authorization check
def toggle_billing
  @user = User.find(params[:id])
  @user.billing_enabled_toggle!  # Anyone can call this!
  @user.save!
end

# ✅ SECURE: Authorize first
def toggle_billing
  @user = User.find(params[:id])
  authorize @user, :manage_billing?  # Pundit check

  @user.billing_enabled_toggle!
  @user.save!
end
```

**Rationale**:
Model-level authorization is optional. Primary security boundary is the controller using Strong Parameters and policy checks.

**Reference**: [SECURITY.md](../SECURITY.md#authorization-bypass-via-helper-methods)

---

### 2. Cascades and Syncs Bypass Authorization

**Status**: NOT A BUG - By Design

**Description**:
When a setting change triggers cascades or syncs, child settings are modified **WITHOUT** separate authorization checks.

**Example**:
```ruby
setting :premium,
        authorize_with: :admin?,
        cascade: {enable: true} do
  setting :api_access    # Will be enabled automatically
  setting :priority_support  # Will be enabled automatically
end

# If user can modify premium, they indirectly modify children
user.premium = true
user.save!
# ⚠️ api_access and priority_support are enabled WITHOUT separate authorization
```

**Workaround**:
- Only use cascades within same authorization level
- Check authorization on the **parent** setting
- Don't cascade across security boundaries

**Reference**: [SECURITY.md](../SECURITY.md#cascades-and-syncs-bypass-authorization)

---

### 3. No Field-Level Encryption

**Status**: Feature Not Implemented

**Description**:
ModelSettings does not provide built-in field-level encryption for sensitive settings.

**Workaround**:
Use Rails encrypted attributes:

```ruby
class User < ApplicationRecord
  encrypts :api_key

  setting :api_key, type: :column
end
```

**Reference**: [Rails Encryption Guide](https://edgeguides.rubyonrails.org/active_record_encryption.html)

---

### 4. Deep Nesting Performance

**Status**: Performance Consideration

**Description**:
Settings with very deep nesting (10+ levels) may have slower compilation times.

**Example**:
```ruby
# ❌ BAD: Deep nesting (10 levels)
setting :level_0, cascade: {enable: true} do
  setting :level_1, cascade: {enable: true} do
    setting :level_2, cascade: {enable: true} do
      # ... 7 more levels
    end
  end
end
```

**Recommendation**:
- Keep nesting depth < 5 levels
- Use flat structure where possible
- Profile with `Model.settings_debug` if slow

**Reference**: [docs/guides/performance.md](guides/performance.md#cascade-optimization)

---

### 5. after_commit Callbacks in Tests

**Status**: Rails Limitation

**Description**:
`after_commit` callbacks don't fire in transactional fixtures by default.

**Example**:
```ruby
setting :premium,
        after_change_commit: :send_email

# In test with transactional fixtures:
user.premium = true
user.save!
# ❌ send_email is NOT called (transaction never commits)
```

**Workaround**:
```ruby
# spec/spec_helper.rb
RSpec.configure do |config|
  config.use_transactional_fixtures = false

  config.before(:each) do
    DatabaseCleaner.strategy = :transaction
    DatabaseCleaner.start
  end

  config.after(:each) do
    DatabaseCleaner.clean
  end
end
```

**Reference**: [docs/guides/testing.md](guides/testing.md#callbacks-not-firing-in-tests)

---

### 6. StoreModel Inheritance Edge Case

**Status**: Known Issue - Low Priority

**Description**:
When using StoreModel adapter with model inheritance, the adapter may not be created correctly in some edge cases.

**Status in Tests**: 1 pending test (temporarily skipped with `xit`)

**Location**: `spec/model_settings/inheritance_spec.rb:556`

**Current State**:
```ruby
xit "creates working StoreModel adapter" do
  # Temporarily skipped - edge case with inheritance
end
```

**Impact**: Low - rare edge case, workaround exists

**Workaround**:
Explicitly define settings in child class:

```ruby
class Admin < User
  # Re-declare settings if using StoreModel adapter
  setting :config, type: :store_model, storage: {column: :config_json}
end
```

---

### 7. JSON Column Name Conflicts (ActiveRecord 8.1+)

**Status**: Rails 8.1 Breaking Change - Workaround Available

**Description**:
ActiveRecord 8.1 automatically validates boolean columns. If JSON nested settings have names that match boolean column names, validation fails.

**Example**:
```ruby
# ❌ BAD: 'theme' matches a boolean column
create_table :users do |t|
  t.boolean :theme  # Column exists
  t.jsonb :settings
end

setting :prefs, type: :json, storage: {column: :settings} do
  setting :theme, default: "light"  # ❌ AR validates as boolean!
end
```

**Workaround**:
Rename JSON settings to avoid conflicts:

```ruby
# ✅ GOOD: Unique names
setting :prefs, type: :json, storage: {column: :settings} do
  setting :ui_theme, default: "light"  # ✅ No conflict
  setting :email_notifications, default: true
end
```

**Affected**: Benchmarks (fixed in Sprint 12)

---

## Edge Cases

### 1. Circular Dependencies

**Status**: Handled - Cycle Detection

**Description**:
Circular dependencies in cascades/syncs are detected and raise an error.

**Example**:
```ruby
setting :a, sync: {target: :b, mode: :bidirectional}
setting :b, sync: {target: :c, mode: :bidirectional}
setting :c, sync: {target: :a, mode: :bidirectional}  # ❌ Cycle!
```

**Behavior**: Raises `DependencyEngine::CycleDetectedError` during compilation

**Reference**: [docs/core/dependencies.md](core/dependencies.md#cycle-detection)

---

### 2. Changing Adapter Types

**Status**: Partially Supported

**Description**:
Changing adapter type (e.g., Column → JSON) requires manual data migration.

**Not Supported**:
```ruby
# Version 1
setting :premium, type: :column  # Data in 'premium' column

# Version 2
setting :premium, type: :json, storage: {column: :settings}  # ❌ Data not migrated!
```

**Workaround**:
Create a migration to move data:

```ruby
class MigratePremiumToJson < ActiveRecord::Migration[7.0]
  def up
    User.find_each do |user|
      settings = user.settings || {}
      settings['premium'] = user.premium
      user.update_column(:settings, settings)
    end
  end
end
```

---

### 3. Module Load Order

**Status**: Order Matters

**Description**:
Modules must be included in specific order:
1. `ModelSettings::DSL` first
2. Then module-specific includes

**Example**:
```ruby
# ✅ CORRECT ORDER
class User < ApplicationRecord
  include ModelSettings::DSL         # First
  include ModelSettings::Modules::Roles  # Then modules
end

# ❌ WRONG ORDER
class User < ApplicationRecord
  include ModelSettings::Modules::Roles  # ❌ DSL not included yet!
  include ModelSettings::DSL
end
```

---

### 4. Metadata Query Performance

**Status**: Performance Consideration

**Description**:
Metadata queries (`with_metadata`, `where_metadata`) operate on Ruby objects, not database queries. For large setting counts (100+), this may be slow.

**Impact**: Negligible for typical use (< 50 settings per model)

**Optimization**: Results are computed at compilation time and cached

---

### 5. Boolean Type Coercion

**Status**: Intentionally Strict

**Description**:
BooleanValueValidator rejects type-coerced values to prevent silent bugs.

**Example**:
```ruby
setting :premium, type: :column, default: false

user.premium = "1"  # ❌ Raises ArgumentError
user.premium = 1    # ❌ Raises ArgumentError
user.premium = true # ✅ OK
```

**Rationale**: Prevents unexpected behavior from database/form coercion

**Reference**: [docs/core/validation.md](core/validation.md#boolean-validation)

---

## Pending Features

These features are documented but not yet implemented:

### 1. Real-World Testing (Sprint 14)

**Status**: ⏳ PENDING - Requires Manual Testing

**Description**: Testing in realistic production-like scenarios with:
- Large datasets (1000+ records)
- Complex dependency graphs
- Multiple modules active
- High concurrency

**Tracking**: Sprint 14 Acceptance Criteria #5

---

### 2. API Reference Documentation

**Status**: ⏳ PENDING

**Description**: Complete API method reference with all public methods documented.

**Tracking**: Review Checklist - Documentation section

---

### 3. Contributing Guide

**Status**: ⏳ PENDING

**Description**: Guidelines for external contributors.

**Tracking**: Review Checklist - Developer Documentation

---

### 4. Compatibility Matrix

**Status**: ⏳ PENDING - Needs Testing

**Description**: Verified compatibility with:
- Rails 7.0, 7.1, 7.2, 8.0
- Ruby 3.1, 3.2, 3.3, 3.4
- PostgreSQL, MySQL, SQLite

**Current**: Developed on Ruby 3.4.7 + Rails 8.1.1 (edge versions)

**Tracking**: Review Checklist - Compatibility section

---

## Reporting Issues

If you find a bug or limitation not listed here:

1. **Check documentation**: [docs/README.md](README.md)
2. **Search existing issues**: [GitHub Issues](https://github.com/your-org/model_settings/issues)
3. **Report new issue**: Include:
   - ModelSettings version
   - Rails version
   - Ruby version
   - Steps to reproduce
   - Expected vs actual behavior

---

## Version History

- **v0.9.0** (2025-11-04): Added authorization inheritance, all major features complete
- **v0.8.0** (2025-11-03): Added production tooling, security audit, documentation formatters
- **v0.7.0** (2025-11-02): Module Development API complete
- **v0.6.0** (2025-10-31): Metadata queries, around callbacks
- **v0.5.0** (2025-10-30): JSON array support

---

**Last Updated**: 2025-11-04 (v0.9.0)
