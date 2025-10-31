# Metadata Query API Design

**Sprint**: 10
**Task**: 10.1
**Status**: Design Phase
**Date**: 2025-10-31

---

## Overview

Design API for querying settings by metadata, extending existing Query module with spec-compliant methods.

---

## Current State

### Existing Methods (Already Implemented)

```ruby
# Find by exact metadata key-value pairs
User.settings_where(metadata: {category: "security", tier: "premium"})

# Find by metadata key presence
User.settings_with_metadata_key(:plan_requirement)

# Find by type
User.settings_by_type(:json)

# Group by metadata
User.settings_grouped_by_metadata(:category)

# Custom filter
User.settings_matching { |s| s.name.to_s.include?("api") }

# Count settings
User.settings_count(metadata: {tier: "premium"})
```

**Location**: `lib/model_settings/query.rb` (lines 1-157)

---

## Required Additions (Spec Compliance)

### From Specification (Section 7, lines 1013-1280)

```ruby
# Find by metadata key (shorthand)
Model.with_metadata(:description)
Model.without_metadata(:description)

# Find by metadata value with operators
Model.where_metadata(:tier, includes: :premium)  # Array includes
Model.where_metadata(:tier, equals: :basic)      # Exact match

# Block-based filter
Model.where_metadata { |meta| !meta[:deprecated] }

# Chainable
Model.settings
  .active
  .with_metadata(:tier)
  .where_metadata(:tier, includes: :premium)
```

---

## API Design

### 1. Alias Existing Methods (Spec Names)

```ruby
module ModelSettings
  module Query
    module ClassMethods
      # Existing: settings_with_metadata_key(:key)
      # Spec name: with_metadata(:key)
      alias_method :with_metadata, :settings_with_metadata_key

      # Existing: settings_where(metadata: {})
      # Keep both - settings_where is more flexible
    end
  end
end
```

**Rationale**: Maintain backward compatibility while adding spec-compliant names.

### 2. Add New Methods

#### 2.1 `without_metadata(key)`

Opposite of `with_metadata` - find settings WITHOUT a metadata key.

```ruby
# Find settings without metadata key
#
# @param key [Symbol] Metadata key
# @return [Array<Setting>] Settings without the key
#
# @example
#   User.without_metadata(:description)
#
def without_metadata(key)
  all_settings_recursive.reject do |setting|
    setting.metadata.key?(key)
  end
end
```

#### 2.2 `where_metadata(key, includes:, equals:, &block)`

Advanced metadata querying with operators.

```ruby
# Query settings by metadata value with operators
#
# @param key [Symbol, nil] Metadata key (nil when using block)
# @param includes [Object] Value that array should include
# @param equals [Object] Value that must match exactly
# @yield [metadata] Block for custom filter
# @return [Array<Setting>] Matching settings
#
# @example Exact match
#   User.where_metadata(:tier, equals: :premium)
#
# @example Array includes
#   User.where_metadata(:plans, includes: :professional)
#
# @example Block filter
#   User.where_metadata { |meta| meta[:tier] == :premium && !meta[:deprecated] }
#
def where_metadata(key = nil, includes: nil, equals: nil, &block)
  settings = all_settings_recursive

  if block_given?
    # Custom filter with block
    settings.select { |s| block.call(s.metadata) }
  elsif equals
    # Exact match
    settings.select { |s| s.metadata[key] == equals }
  elsif includes
    # Array includes
    settings.select { |s|
      value = s.metadata[key]
      value.is_a?(Array) && value.include?(includes)
    }
  else
    # No filter specified - return all
    settings
  end
end
```

---

## API Completeness Matrix

| Feature | Existing Method | Spec Method | Status |
|---------|----------------|-------------|--------|
| Find by key presence | `settings_with_metadata_key` | `with_metadata` | ✅ Alias |
| Find by key absence | ❌ None | `without_metadata` | ⏳ **NEW** |
| Find by exact key-value | `settings_where(metadata: {})` | - | ✅ Exists |
| Find by exact match | ❌ None | `where_metadata(:key, equals:)` | ⏳ **NEW** |
| Find by array includes | ❌ None | `where_metadata(:key, includes:)` | ⏳ **NEW** |
| Custom block filter | `settings_matching` | `where_metadata { }` | ⏳ **NEW** |
| Group by metadata | `settings_grouped_by_metadata` | - | ✅ Exists |
| Count by criteria | `settings_count` | - | ✅ Exists |

**Summary**:
- ✅ **3 features already exist** (but may need aliases)
- ⏳ **4 new features required**

---

## Implementation Plan

### Phase 1: Add Missing Methods (Task 10.2)

1. Add `without_metadata(key)` method
2. Add `where_metadata(key, includes:, equals:, &block)` method
3. Add alias `with_metadata` → `settings_with_metadata_key`

### Phase 2: Enhance Setting Class

Add helper methods to Setting class for cleaner implementation:

```ruby
# In lib/model_settings/setting.rb
class Setting
  # Check if setting has a metadata key
  def has_metadata?(key)
    metadata.key?(key) || metadata.key?(key.to_s)
  end

  # Get metadata value for a key
  def metadata_value(key)
    metadata[key] || metadata[key.to_s]
  end

  # Check if array metadata includes a value
  def metadata_includes?(key, value)
    meta_value = metadata_value(key)
    meta_value.is_a?(Array) && meta_value.include?(value)
  end
end
```

### Phase 3: Tests (Task 10.2)

Add comprehensive RSpec tests:

```ruby
RSpec.describe ModelSettings::Query do
  describe ".with_metadata" do
    it "returns settings with specified metadata key"
    it "works with symbol keys"
    it "works with string keys"
  end

  describe ".without_metadata" do
    it "returns settings without specified metadata key"
    it "excludes settings with the key"
  end

  describe ".where_metadata" do
    context "with equals: parameter" do
      it "filters by exact value match"
      it "handles nil values"
    end

    context "with includes: parameter" do
      it "filters by array inclusion"
      it "handles non-array values gracefully"
    end

    context "with block" do
      it "filters using custom block logic"
      it "passes metadata hash to block"
    end

    context "without parameters" do
      it "returns all settings"
    end
  end
end
```

---

## Backward Compatibility

### ✅ All Existing Methods Preserved

- `settings_where(metadata: {})` - kept for flexibility
- `settings_with_metadata_key` - kept as primary implementation
- `settings_matching` - kept for general use
- All other existing methods - unchanged

### ✅ New Aliases

- `with_metadata` → alias of `settings_with_metadata_key`

**Result**: 100% backward compatible, new spec-compliant names added.

---

## Usage Examples

### Basic Queries

```ruby
# Find settings with description
premium_settings = User.with_metadata(:description)

# Find settings without description
undocumented = User.without_metadata(:description)

# Find by exact tier value
premium = User.where_metadata(:tier, equals: :premium)

# Find by array inclusion
enterprise_features = User.where_metadata(:plans, includes: :enterprise)
```

### Advanced Queries

```ruby
# Complex block filter
active_premium = User.where_metadata do |meta|
  meta[:tier] == :premium && !meta[:deprecated] && meta[:stable]
end

# Chaining (if we make them chainable in future)
# User.with_metadata(:tier).where_metadata(:tier, equals: :premium)
```

### Migration Path

```ruby
# Old style (still works)
User.settings_with_metadata_key(:description)
User.settings_where(metadata: {tier: "premium"})

# New style (spec-compliant)
User.with_metadata(:description)
User.where_metadata(:tier, equals: :premium)
```

---

## Non-Goals (Out of Scope for Sprint 10)

### ❌ Not Implementing (Yet)

1. **Chainable query builder** - Would require major refactoring
   ```ruby
   # This is NOT in Sprint 10 scope:
   User.settings.with_metadata(:tier).where_metadata(:tier, equals: :premium)
   ```

2. **SQL-based queries** - All queries are in-memory
   ```ruby
   # This is NOT in Sprint 10 scope:
   User.where("settings_metadata @> ?", {tier: "premium"}.to_json)
   ```

3. **Query caching** - No caching layer
4. **Lazy evaluation** - All queries eager

**Rationale**: Keep Sprint 10 focused on core query API. Chainable queries can be added in future sprint if needed.

---

## Performance Considerations

### Current Approach: In-Memory Filtering

All queries use `all_settings_recursive.select { }` - this is **O(n)** where n = number of settings.

**Impact**:
- ✅ **Fine for typical usage** (10-50 settings per model)
- ⚠️ **May be slow for 500+ settings**
- ✅ **Simple implementation**
- ✅ **No database dependencies**

**Future Optimization** (not Sprint 10):
- Build index of settings by metadata
- Lazy evaluation with chainable queries
- Memoization of query results

---

## API Surface

### New Public Methods (3)

1. `Model.with_metadata(key)` - alias
2. `Model.without_metadata(key)` - new
3. `Model.where_metadata(key, includes:, equals:, &block)` - new

### New Setting Methods (3)

1. `setting.has_metadata?(key)` - new
2. `setting.metadata_value(key)` - new
3. `setting.metadata_includes?(key, value)` - new

**Total**: 6 new public methods

---

## Success Criteria

### Functional

- ✅ `with_metadata(key)` works as alias
- ✅ `without_metadata(key)` returns correct results
- ✅ `where_metadata(:key, equals:)` filters correctly
- ✅ `where_metadata(:key, includes:)` handles arrays
- ✅ `where_metadata { |meta| ... }` supports custom logic
- ✅ All existing methods still work

### Quality

- ✅ 100% test coverage for new methods
- ✅ RSpec tests comprehensive (>20 examples)
- ✅ Documentation updated
- ✅ Examples in docs
- ✅ Backward compatible

---

## Timeline

**Task 10.1** (Design): 0.5 day ✅ (this document)
**Task 10.2** (Implementation): 2 days
- Day 1: Implement methods + Setting helpers
- Day 2: Write comprehensive tests

**Total**: 2.5 days

---

## Next Steps

1. ✅ Review this design with team
2. ⏳ Implement `without_metadata` method
3. ⏳ Implement `where_metadata` method
4. ⏳ Add Setting helper methods
5. ⏳ Write comprehensive RSpec tests
6. ⏳ Update docs/core/queries.md

---

## Related Documentation

- `lib/model_settings/query.rb` - Current implementation
- `lib/model_settings/setting.rb` - Setting class
- `docs/core/queries.md` - Query documentation
- Spec Section 7 (lines 1013-1280) - Metadata query requirements

---

## Questions & Decisions

### Q: Should we make queries chainable?

**A**: No, not in Sprint 10. Current implementation returns Array, making methods chainable would require query builder pattern. Out of scope.

### Q: Should we support SQL-based queries?

**A**: No. In-memory queries keep implementation simple and adapter-agnostic.

### Q: What about performance with 1000+ settings?

**A**: Out of scope. If needed, can optimize in future sprint with metadata indexing.

### Q: Support both symbol and string keys?

**A**: Yes. Setting helper methods (`has_metadata?`, `metadata_value`) handle both.

---

**Status**: ✅ Design Complete
**Ready for**: Task 10.2 Implementation
