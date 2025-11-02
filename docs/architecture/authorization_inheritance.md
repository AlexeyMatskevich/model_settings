# Authorization Inheritance Design

**Status**: 🔴 In Progress
**Version**: v0.9.0
**Created**: 2025-11-02
**Sprint**: Sprint 13

---

## Table of Contents

1. [Overview](#overview)
2. [5-Level Priority System](#5-level-priority-system)
3. [Priority Resolution Algorithm](#priority-resolution-algorithm)
4. [Module-Specific Implementations](#module-specific-implementations)
5. [Edge Cases](#edge-cases)
6. [Implementation Plan](#implementation-plan)
7. [Testing Strategy](#testing-strategy)
8. [Open Questions](#open-questions)

---

## Overview

### Problem Statement

Currently, nested settings require explicit authorization configuration on every setting, leading to:
- **Code duplication**: Repeating `authorize_with`/`viewable_by`/`editable_by` for every nested setting
- **Security risks**: Easy to forget authorization on a nested setting
- **Poor DX**: Verbose DSL when defining deeply nested structures

### Solution

Implement a **5-level priority system** for authorization inheritance that allows:
- Automatic inheritance from parent settings (secure by default)
- Flexible override at multiple configuration levels
- Clear, predictable resolution algorithm
- Support for all three authorization modules (Roles, Pundit, ActionPolicy)

### Scope

**In Scope**:
- 5-level priority resolution for authorization options
- Common base implementation for policy-based modules (Pundit, ActionPolicy)
- Separate implementation for Roles module (array-based authorization)
- Global, model-level, and setting-level configuration
- Comprehensive tests (>105 new examples)

**Out of Scope**:
- Authorization runtime checks (already implemented)
- New authorization modules
- Breaking changes to existing authorization APIs

---

## 5-Level Priority System

Authorization inheritance follows a **5-level priority system** from highest to lowest:

### Level 1: Explicit Setting Value (Highest Priority)

The most explicit form - directly specified authorization on the setting.

**Syntax**:
```ruby
# Pundit/ActionPolicy
setting :nested, authorize_with: :manage_feature?

# Roles
setting :nested, viewable_by: [:admin], editable_by: [:admin, :manager]
```

**Behavior**: Always takes precedence over all other levels. No inheritance occurs.

**Use case**: Override any inherited authorization for a specific setting.

---

### Level 2: Explicit `:inherit` Keyword

Explicitly request inheritance from parent, regardless of other configuration.

**Syntax**:
```ruby
# Pundit/ActionPolicy
setting :nested, authorize_with: :inherit

# Roles
setting :nested, viewable_by: :inherit, editable_by: :inherit
```

**Behavior**:
- Always inherits from parent setting
- If parent has no authorization, walks up the tree
- If no parent found, results in `nil` (no authorization)
- Overrides model and global configuration

**Use case**: Explicitly inherit in contexts where inheritance is disabled by default.

---

### Level 3: Setting-Level `inherit_authorization` Option

Controls inheritance for all children within a setting block.

**Syntax**:
```ruby
setting :parent,
        authorize_with: :manage_feature?,
        inherit_authorization: true do

  setting :child  # Inherits :manage_feature?
end
```

**Options**:
- `true`: All children inherit (unless explicitly overridden)
- `false`: Children do NOT inherit (must specify explicitly or use `:inherit`)
- `nil` or not specified: Falls through to Level 4

**Behavior**: Only affects direct children of this setting, not grandchildren (unless they also specify it).

**Use case**: Create authorization boundaries at specific nesting levels.

---

### Level 4: Model-Level Configuration

Controls inheritance for all settings in the model.

**Syntax**:
```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  settings_config inherit_authorization: true  # or false, or :view_only, or :edit_only
end
```

**Options**:
- `true`: All settings inherit authorization
- `false`: No automatic inheritance (require explicit)
- `:view_only`: Inherit only `viewable_by`/view authorization
- `:edit_only`: Inherit only `editable_by`/edit authorization
- `nil` or not specified: Falls through to Level 5

**Behavior**: Applies to all settings in the model unless overridden by Level 1-3.

**Use case**: Set model-wide inheritance policy based on security requirements.

---

### Level 5: Global Configuration (Lowest Priority)

Application-wide default for authorization inheritance.

**Syntax**:
```ruby
# config/initializers/model_settings.rb
ModelSettings.configure do |config|
  config.default_authorization_inheritance = true  # Default: true (secure by default)
end
```

**Options**:
- `true`: All models inherit authorization by default (secure by default)
- `false`: No automatic inheritance (explicit authorization required)
- `nil`: Same as `false`

**Behavior**: Fallback when no other configuration is specified.

**Use case**: Set application-wide security policy.

**Default**: `true` (secure by default)

---

## Priority Resolution Algorithm

### Algorithm Overview

For each authorization aspect (`viewable_by`, `editable_by`, `authorize_with`):

```
1. Check explicit setting value → use if present (not nil, not :inherit)
2. Check if :inherit keyword → resolve from parent recursively
3. Check inherit_authorization option on parent → resolve from parent if true
4. Check model settings_config → apply model defaults
5. Check global config → apply global defaults
6. No inheritance → return nil (no authorization)
```

### Pseudocode

```ruby
def resolve_authorization(setting, aspect)
  # aspect = :viewable_by, :editable_by, or :authorize_with

  # Level 1: Explicit setting value
  explicit = setting.options[aspect]
  return explicit if explicit.present? && explicit != :inherit

  # Level 2: Explicit :inherit keyword
  if explicit == :inherit
    return resolve_from_parent(setting, aspect)
  end

  # Level 3: Parent setting configuration
  if setting.parent&.options[:inherit_authorization]
    case setting.parent.options[:inherit_authorization]
    when true
      return resolve_from_parent(setting, aspect)
    when :view_only
      return resolve_from_parent(setting, aspect) if aspect == :viewable_by || aspect == :authorize_with
    when :edit_only
      return resolve_from_parent(setting, aspect) if aspect == :editable_by
    when false
      # Explicitly disabled at parent level, skip to Level 4
    end
  end

  # Level 4: Model-level configuration
  model_config = setting.model_class.settings_config_value(:inherit_authorization)
  if model_config
    case model_config
    when true
      return resolve_from_parent(setting, aspect)
    when :view_only
      return resolve_from_parent(setting, aspect) if aspect == :viewable_by || aspect == :authorize_with
    when :edit_only
      return resolve_from_parent(setting, aspect) if aspect == :editable_by
    when false
      # Explicitly disabled at model level, skip to Level 5
    end
  end

  # Level 5: Global configuration
  global_config = ModelSettings.configuration.default_authorization_inheritance
  if global_config == true
    return resolve_from_parent(setting, aspect)
  end

  # No inheritance - return nil (no authorization)
  nil
end

def resolve_from_parent(setting, aspect)
  parent = setting.parent
  return nil unless parent  # No parent = no authorization

  # Recursively resolve parent's authorization
  resolve_authorization(parent, aspect)
end
```

### Resolution Examples

#### Example 1: Default Behavior (Global: true)

```ruby
# Global config: inherit_authorization = true (default)

setting :billing, authorize_with: :manage_billing? do
  setting :invoices  # Resolves to :manage_billing? (via Level 5 → Level 1 of parent)
end
```

**Resolution for `:invoices`**:
1. Level 1: No explicit `authorize_with` → continue
2. Level 2: Not `:inherit` → continue
3. Level 3: Parent has no `inherit_authorization` → continue
4. Level 4: Model has no `settings_config` → continue
5. Level 5: Global = true → resolve from parent
6. Parent's Level 1: `:manage_billing?` → **return `:manage_billing?`**

---

#### Example 2: Explicit Override

```ruby
setting :billing, authorize_with: :manage_billing? do
  setting :reports, authorize_with: :view_billing?  # Override
end
```

**Resolution for `:reports`**:
1. Level 1: Explicit `:view_billing?` → **return `:view_billing?`**

---

#### Example 3: Explicit `:inherit` with Global Disabled

```ruby
# Global config: inherit_authorization = false

setting :billing, authorize_with: :manage_billing? do
  setting :invoices, authorize_with: :inherit  # Explicit
end
```

**Resolution for `:invoices`**:
1. Level 1: Value is `:inherit` → continue to Level 2
2. Level 2: Explicit `:inherit` → resolve from parent
3. Parent's Level 1: `:manage_billing?` → **return `:manage_billing?`**

---

#### Example 4: Parent-Level Configuration

```ruby
setting :billing,
        authorize_with: :manage_billing?,
        inherit_authorization: false do  # Disable for children

  setting :invoices  # No authorization (parent disabled inheritance)
  setting :reports, authorize_with: :inherit  # Explicit :inherit overrides
end
```

**Resolution for `:invoices`**:
1. Level 1: No explicit → continue
2. Level 2: Not `:inherit` → continue
3. Level 3: Parent has `inherit_authorization: false` → **return nil**

**Resolution for `:reports`**:
1. Level 1: Value is `:inherit` → continue
2. Level 2: Explicit `:inherit` → resolve from parent
3. Parent's Level 1: `:manage_billing?` → **return `:manage_billing?`**

---

## Module-Specific Implementations

### Common Policy Base (Pundit + ActionPolicy)

Both Pundit and ActionPolicy use policy-based authorization, so they share 95%+ of inheritance logic.

**Approach**: Create `PolicyBasedAuthorization` module that both extend.

**Location**: `lib/model_settings/modules/policy_based_authorization.rb`

**Implementation**:
```ruby
module ModelSettings
  module Modules
    module PolicyBasedAuthorization
      extend ActiveSupport::Concern

      # Common 5-level priority resolution
      def resolve_authorization_for_setting(setting_name, action:)
        setting = find_setting(setting_name)
        authorization = resolve_authorization_with_priority(setting, :authorize_with)

        return true if authorization.nil?  # No authorization = allowed

        # Call policy (abstract method)
        check_policy(authorization, action: action)
      end

      private

      def resolve_authorization_with_priority(setting, aspect)
        # Implementation of 5-level algorithm (see above)
      end

      # Abstract method - implemented by Pundit/ActionPolicy
      def check_policy(authorization, action:)
        raise NotImplementedError, "#{self.class} must implement #check_policy"
      end
    end
  end
end
```

**Pundit Extension**:
```ruby
module ModelSettings
  module Modules
    module Pundit
      include PolicyBasedAuthorization

      private

      def check_policy(authorization, action:)
        policy_class = authorization.is_a?(Class) ? authorization : "#{authorization.to_s.camelize}Policy".constantize
        policy_class.new(current_user, self).public_send(action)
      end
    end
  end
end
```

**ActionPolicy Extension**:
```ruby
module ModelSettings
  module Modules
    module ActionPolicy
      include PolicyBasedAuthorization

      private

      def check_policy(authorization, action:)
        authorize! self, to: action, with: authorization
      end
    end
  end
end
```

---

### Roles Module (Array-Based)

Roles module uses array-based authorization (`viewable_by`, `editable_by`), so it needs separate implementation.

**Key Differences**:
- Two separate aspects: `viewable_by` and `editable_by`
- Authorization value is array of roles, not policy method
- Partial inheritance supported (inherit view but not edit, or vice versa)

**Implementation**:
```ruby
module ModelSettings
  module Modules
    module Roles
      def authorized_to_view?(setting_name, role:)
        setting = find_setting(setting_name)
        roles = resolve_authorization_with_priority(setting, :viewable_by)

        return true if roles.nil? || roles.empty?  # No authorization = allowed

        Array(roles).include?(role)
      end

      def authorized_to_edit?(setting_name, role:)
        setting = find_setting(setting_name)
        roles = resolve_authorization_with_priority(setting, :editable_by)

        return true if roles.nil? || roles.empty?

        Array(roles).include?(role)
      end

      private

      def resolve_authorization_with_priority(setting, aspect)
        # Same 5-level algorithm as PolicyBasedAuthorization
        # But returns array of roles instead of policy method
      end
    end
  end
end
```

**Partial Inheritance Support**:

Roles module supports inheriting only view or edit:

```ruby
# Model-level: inherit only view
settings_config inherit_authorization: :view_only

# Setting-level: inherit only edit
setting :parent,
        viewable_by: [:admin],
        editable_by: [:admin, :manager],
        inherit_authorization: :edit_only do

  setting :child
  # Inherits editable_by: [:admin, :manager]
  # Does NOT inherit viewable_by (must specify explicitly)
end
```

---

## Edge Cases

### 1. Circular References (Should Not Happen)

**Scenario**: Setting somehow references itself in parent chain.

**Detection**: Track visited settings during resolution, raise error if cycle detected.

**Resolution**:
```ruby
def resolve_from_parent(setting, aspect, visited = Set.new)
  if visited.include?(setting)
    raise CyclicInheritanceError, "Circular inheritance detected for #{setting.name}"
  end

  visited << setting
  parent = setting.parent
  return nil unless parent

  resolve_authorization_with_priority(parent, aspect, visited)
end
```

**Test**: Ensure this error never happens in normal usage (test error handling only).

---

### 2. Parent Has No Authorization

**Scenario**: Child tries to inherit, but parent has no authorization defined.

**Expected Behavior**: Walk up the tree until authorization found, or return `nil`.

**Example**:
```ruby
setting :level1, authorize_with: :manage? do
  setting :level2 do  # No authorization
    setting :level3, authorize_with: :inherit
  end
end
```

**Resolution for `:level3`**:
- Level 2: `:inherit` → resolve from parent (`:level2`)
- `:level2` has no explicit → resolve from its parent (`:level1`)
- `:level1` has `:manage?` → **return `:manage?`**

---

### 3. Root Setting with `:inherit`

**Scenario**: Top-level setting uses `authorize_with: :inherit`.

**Expected Behavior**: No parent exists, so return `nil` (no authorization).

**Example**:
```ruby
setting :root, authorize_with: :inherit
```

**Resolution**:
- Level 2: `:inherit` → resolve from parent
- No parent → **return nil**

**Warning**: This is likely a user error. Should we log a warning?

---

### 4. Mixed Authorization Types

**Scenario**: Parent uses Pundit, child uses Roles.

**Expected Behavior**: **NOT SUPPORTED**. Each model can only use ONE authorization module.

**Enforcement**: Module exclusivity already enforced by `register_exclusive_group(:authorization)`.

**Test**: Verify exclusivity error is raised when attempting to include multiple authorization modules.

---

### 5. `nil` vs Empty Array for Roles

**Scenario**: Roles module with `viewable_by: []` vs `viewable_by: nil`.

**Expected Behavior**:
- `viewable_by: nil` → No authorization (anyone can view)
- `viewable_by: []` → No authorization (anyone can view)
- Both treated the same

**Rationale**: Empty array means "no roles required" = anyone can access.

---

### 6. Partial Inheritance with `:inherit`

**Scenario**: Model configured with `:view_only`, but child explicitly uses `editable_by: :inherit`.

**Expected Behavior**: Explicit `:inherit` (Level 2) overrides model configuration (Level 4).

**Example**:
```ruby
settings_config inherit_authorization: :view_only

setting :parent, viewable_by: [:admin], editable_by: [:admin] do
  setting :child, editable_by: :inherit  # Explicit :inherit overrides :view_only
end
```

**Resolution for `:child.editable_by`**:
- Level 2: Explicit `:inherit` → resolve from parent → **return [:admin]**

---

### 7. Deep Nesting (5+ Levels)

**Scenario**: Setting nested 5+ levels deep, each inheriting from parent.

**Expected Behavior**: Recursively walk up the tree until authorization found.

**Performance**: Memoize resolution results to avoid repeated traversal.

**Test**: Create 10-level deep nesting, verify correct resolution and acceptable performance (<1ms per resolution).

---

### 8. Dynamic Setting Definition Order

**Scenario**: Settings defined dynamically, authorization may not be set yet when child is defined.

**Expected Behavior**: Resolution happens at **access time**, not definition time, so it's safe.

**Example**:
```ruby
setting :parent do
  setting :child, authorize_with: :inherit  # Parent auth not set yet
end

# Later...
parent_setting = model.class._settings.find { |s| s.name == :parent }
parent_setting.options[:authorize_with] = :manage?  # Set after child defined
```

**Resolution**: At access time, parent already has authorization → works correctly.

---

### 9. Changing Configuration at Runtime

**Scenario**: User changes `ModelSettings.configuration.default_authorization_inheritance` at runtime.

**Expected Behavior**: New resolution uses new configuration (no caching).

**Caution**: Changing configuration at runtime is NOT recommended (should be set once at initialization).

**Test**: Verify that configuration changes affect new resolutions (but document as anti-pattern).

---

### 10. `settings_config` vs `setting` Option Conflict

**Scenario**: Model has `settings_config inherit_authorization: true`, but parent setting has `inherit_authorization: false`.

**Expected Behavior**: Setting-level (Level 3) takes priority over model-level (Level 4).

**Example**:
```ruby
settings_config inherit_authorization: true  # Model level

setting :parent,
        authorize_with: :manage?,
        inherit_authorization: false do  # Override model level

  setting :child  # Does NOT inherit (setting-level wins)
end
```

**Resolution for `:child`**:
- Level 3: Parent has `inherit_authorization: false` → **return nil**

---

## Implementation Plan

### Phase 1: Foundation (Task 13.1) - **CURRENT**

**Deliverable**: Design document ✅

**Tasks**:
- [x] Study specification for authorization inheritance
- [x] Document 5-level priority system
- [x] Document priority resolution algorithm
- [x] Identify edge cases
- [x] Create implementation plan

---

### Phase 2: Common Policy Base (Task 13.2)

**Deliverable**: `PolicyBasedAuthorization` module

**Tasks**:
1. Create `lib/model_settings/modules/policy_based_authorization.rb`
2. Implement 5-level priority resolution algorithm
3. Implement `resolve_from_parent` with cycle detection
4. Add abstract `check_policy` method
5. Refactor Pundit module to extend `PolicyBasedAuthorization`
6. Refactor ActionPolicy module to extend `PolicyBasedAuthorization`
7. Update tests to use `PolicyBasedAuthorization` (eliminate duplication)
8. Create shared examples for policy-based authorization contract
9. **Test Polishing**: Apply all 28 rules

**Estimated**: 2 days

---

### Phase 3: Roles Module Inheritance (Task 13.3)

**Deliverable**: Authorization inheritance for Roles module

**Tasks**:
1. Implement `resolve_authorization_with_priority` in Roles module
2. Implement `resolve_from_parent` with cycle detection
3. Support partial inheritance (`:view_only`, `:edit_only`)
4. Add `authorized_to_view?` and `authorized_to_edit?` methods
5. Update existing Roles tests to cover inheritance
6. Add new tests for partial inheritance
7. **Test Polishing**: Apply all 28 rules

**Estimated**: 3 days

---

### Phase 4: Configuration Support (Task 13.4)

**Deliverable**: Configuration options for authorization inheritance

**Tasks**:
1. Add `default_authorization_inheritance` to `Configuration` class
2. Add `settings_config` class method to DSL
3. Add `settings_config_value` helper method
4. Update resolution algorithm to use configuration
5. Create `docs/core/configuration.md` documentation
6. Add tests for configuration at all levels
7. Test interaction between different configuration levels
8. **Test Polishing**: Apply all 28 rules

**Estimated**: 2 days

---

### Phase 5: Comprehensive Tests (Task 13.5)

**Deliverable**: >105 new tests for authorization inheritance

**Tasks**:
1. **5-level priority resolution** (30 examples)
   - Test each level individually
   - Test level combinations
   - Test override behavior
2. **Partial inheritance** (20 examples)
   - `:view_only` configuration
   - `:edit_only` configuration
   - Mixed scenarios
3. **Deep nesting** (15 examples)
   - 5+ levels of nesting
   - Inheritance chain resolution
   - Performance tests
4. **Edge cases** (20 examples)
   - Circular reference detection
   - Parent with no authorization
   - Root setting with `:inherit`
   - Empty array vs nil
5. **Integration tests** (20 examples)
   - Roles + Pundit together (verify exclusivity)
   - All modules tested with inheritance
   - Real-world scenarios
6. **Test Polishing**: Apply all 28 rules to all new tests

**Estimated**: 3 days

---

### Phase 6: Documentation Update (Task 13.6)

**Deliverable**: Comprehensive documentation with examples

**Tasks**:
1. Update `docs/modules/roles.md` with inheritance section
2. Update `docs/modules/pundit.md` with inheritance section
3. Update `docs/modules/action_policy.md` with inheritance section
4. Update `docs/core/configuration.md` with authorization config
5. Update `README.md` with inheritance examples
6. Add migration guide for upgrading from no inheritance
7. Verify all examples are tested and working

**Estimated**: 2 days

---

## Testing Strategy

### Unit Tests (per module)

**PolicyBasedAuthorization**: ~40 examples
- 5-level priority resolution
- `resolve_from_parent` recursive behavior
- Cycle detection
- Edge cases

**Roles Module**: ~50 examples
- View authorization resolution
- Edit authorization resolution
- Partial inheritance (`:view_only`, `:edit_only`)
- Array handling (`nil` vs empty)

**Configuration**: ~20 examples
- Global configuration
- Model configuration
- Setting-level configuration
- Priority between levels

---

### Integration Tests: ~20 examples

**Cross-Module**:
- Verify Pundit and Roles are mutually exclusive
- Verify ActionPolicy and Roles are mutually exclusive
- Test real-world scenarios (multi-level nesting with mixed configuration)

**Performance**:
- Benchmark resolution for 10-level deep nesting
- Verify resolution time <1ms per setting
- Test with 100+ settings in model

---

### Shared Examples

**Authorization Inheritance Contract**:
```ruby
RSpec.shared_examples "authorization inheritance" do |module_name|
  describe "5-level priority resolution" do
    it "Level 1: uses explicit setting value"
    it "Level 2: inherits with :inherit keyword"
    it "Level 3: respects parent setting configuration"
    it "Level 4: respects model configuration"
    it "Level 5: respects global configuration"
  end

  describe "edge cases" do
    it "handles parent with no authorization"
    it "handles root setting with :inherit"
    it "detects circular references"
  end
end
```

---

## Open Questions

### Q1: Should `:inherit` be allowed for root settings?

**Current Behavior**: Returns `nil` (no authorization).

**Options**:
- A: Allow (current) - return nil silently
- B: Log warning - return nil but log warning
- C: Raise error - fail loudly for user error

**Recommendation**: **A** - Allow silently. User might be using dynamic parent assignment.

---

### Q2: Should configuration changes at runtime be supported?

**Current Behavior**: New resolutions use new configuration.

**Options**:
- A: Support (current) - configuration is read on each resolution
- B: Cache + invalidate - cache resolution results, clear on config change
- C: Disallow - raise error if config changed after initialization

**Recommendation**: **A** - Support but document as anti-pattern. No caching for v0.9.0.

---

### Q3: Should we add memoization for resolution results?

**Pros**: Faster repeated access to same setting
**Cons**: Memory overhead, cache invalidation complexity

**Recommendation**: **NO** for v0.9.0. Add in v1.0 if performance issues identified.

---

### Q4: Should partial inheritance (`:view_only`, `:edit_only`) be supported for policy-based modules?

**Current Design**: Only for Roles module.

**Reasoning**: Pundit/ActionPolicy use single `authorize_with` option, not separate view/edit.

**Recommendation**: **NO** - Only support for Roles module in v0.9.0.

---

### Q5: How to handle StoreModel nested settings with authorization?

**Current Behavior**: StoreModel settings are separate classes, not part of inheritance chain.

**Recommendation**: StoreModel settings inherit authorization same as JSON settings. Test this explicitly.

---

## Success Criteria

**Sprint 13 is successful if**:

1. ✅ All 5 levels of priority resolution work correctly
2. ✅ `PolicyBasedAuthorization` eliminates duplication between Pundit and ActionPolicy
3. ✅ Roles module supports authorization inheritance with partial inheritance
4. ✅ Configuration works at global, model, and setting levels
5. ✅ >105 new tests pass with 0 failures
6. ✅ All edge cases are handled correctly
7. ✅ Documentation is comprehensive and examples are verified
8. ✅ Spec compliance increases from ~70% to ~90%
9. ✅ All tests pass (1175+ examples expected)

---

## References

- **Specification**: `llm_docs/settings_gem_spec.md` (Section 13: Authorization Inheritance)
- **Roadmap**: `llm_docs/implementation_roadmap.md` (Sprint 13)
- **Existing Modules**:
  - `lib/model_settings/modules/roles.rb`
  - `lib/model_settings/modules/pundit.rb`
  - `lib/model_settings/modules/action_policy.rb`

---

## Changelog

- **2025-11-02**: Initial design document created (Task 13.1)
