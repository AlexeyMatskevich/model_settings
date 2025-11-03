# Test Coverage Improvement Plan
**Created**: 2025-11-03
**Based on**: coverage_analysis_2025-11-03.md
**Target**: v1.0 Test Readiness

---

## Overview

This plan addresses the 2 critical test coverage gaps identified in the coverage analysis:

1. ❌ **BooleanValueValidator** - NO TESTS (HIGH RISK)
2. ❌ **SimpleAudit Module** - NO TESTS (MEDIUM RISK)

**Total Estimated Time**: 5-7 hours
**Target Confidence Level**: 95%+ for v1.0 release

---

## Phase 1: Critical Gaps (MUST FIX) - 5-7 hours

### Task 1.1: Add BooleanValueValidator Tests (2-3 hours)

**File to create**: `spec/model_settings/validators/boolean_value_validator_spec.rb`

**Test Structure:**

```ruby
RSpec.describe ModelSettings::Validators::BooleanValueValidator do
  # 1. Valid values (3 tests)
  - accepts true
  - accepts false
  - accepts nil (for optional settings)

  # 2. Invalid primitive values (6 tests)
  - rejects string "1"
  - rejects string "true"
  - rejects string "yes"
  - rejects integer 0
  - rejects integer 1
  - rejects string "false"

  # 3. Invalid complex values (3 tests)
  - rejects empty array []
  - rejects empty hash {}
  - rejects empty string ""

  # 4. Type casting detection (3 tests)
  - detects type casting and rejects
  - handles pre-cast values
  - works with StoreModel delegated attributes

  # 5. Error messages (3 tests)
  - provides helpful error message
  - shows actual invalid value in error
  - uses custom message if provided
end

# Integration tests (to add to existing adapter specs)

# spec/model_settings/adapters/column_spec.rb
context "with boolean_value validation" do
  - rejects invalid boolean input (3 tests)
  - accepts valid boolean input (2 tests)
end

# spec/model_settings/adapters/json_spec.rb
context "with boolean_value validation" do
  - rejects invalid boolean input (3 tests)
  - accepts valid boolean input (2 tests)
end

# spec/model_settings/adapters/store_model_spec.rb
context "with boolean_value validation" do
  - rejects invalid boolean input (3 tests)
  - accepts valid boolean input (2 tests)
end
```

**Estimated Tests**: ~33 new tests
**Estimated Time**: 2-3 hours

**Success Criteria:**
- [ ] All valid values accepted
- [ ] All invalid values rejected with clear errors
- [ ] Type casting detected and rejected
- [ ] Works consistently across all 3 adapters
- [ ] Error messages are helpful

---

### Task 1.2: Add SimpleAudit Module Tests (3-4 hours)

**File to create**: `spec/model_settings/modules/simple_audit_spec.rb`

**Test Structure:**

```ruby
RSpec.describe ModelSettings::Modules::SimpleAudit do
  # 1. Module registration (4 tests)
  describe "module registration" do
    - registers :simple_audit module in ModuleRegistry
    - registers :track_changes option
    - validates track_changes is boolean
    - raises ArgumentError for non-boolean track_changes
  end

  # 2. Callback configuration (5 tests)
  describe "callback configuration" do
    - defaults to :before_save
    - accepts :after_save as custom timing
    - accepts :after_commit as custom timing
    - stores configuration in ModuleRegistry
    - configuration is global across models
  end

  # 3. Compilation-time indexing (6 tests)
  describe "compilation-time indexing" do
    context "when model has tracked settings" do
      - indexes settings with track_changes: true
      - ignores settings with track_changes: false
      - stores indexed settings in centralized metadata
    end

    context "when multiple models exist" do
      - indexes are scoped per model class
      - one model's index doesn't affect another
    end

    context "when no tracked settings" do
      - creates empty index
    end
  end

  # 4. Class methods (8 tests)
  describe ".tracked_settings" do
    context "when settings are tracked" do
      - returns array of Setting objects
      - returns settings in definition order
      - only returns tracked settings
    end

    context "when no settings tracked" do
      - returns empty array
    end
  end

  describe ".setting_tracked?" do
    - returns true for tracked setting
    - returns false for untracked setting
    - returns false for nonexistent setting
    - accepts symbol or string
  end

  # 5. Runtime behavior (10 tests)
  describe "#audit_tracked_settings" do
    context "when record is new" do
      - does not audit (only audits persisted records)
    end

    context "when record is persisted" do
      context "when tracked setting changes" do
        - logs change to Rails.logger
        - includes model class and ID
        - includes setting name
        - shows old → new values
        - handles nil → value changes
        - handles value → nil changes
      end

      context "when tracked setting does NOT change" do
        - does not log anything
      end

      context "when untracked setting changes" do
        - does not log
      end
    end
  end

  # 6. Callback timing integration (6 tests)
  describe "callback execution" do
    context "with default timing (:before_save)" do
      - executes before record is saved
      - can access old and new values
    end

    context "with :after_save timing" do
      - executes after record is saved
      - changes are persisted
    end

    context "with :after_commit timing" do
      - executes after transaction commits
      - changes are persisted and committed
    end
  end
end
```

**Estimated Tests**: ~39 new tests
**Estimated Time**: 3-4 hours

**Success Criteria:**
- [ ] Module registration works
- [ ] Option validation works
- [ ] Callback configuration works
- [ ] Metadata indexing works
- [ ] Class methods return correct data
- [ ] Runtime audit logging works
- [ ] Callback timing is configurable and correct

---

## Phase 2: High Priority (SHOULD FIX) - 3 hours

### Task 2.1: Add Module Callback Integration Tests (2 hours)

**Location**: New file `spec/model_settings/module_callback_integration_spec.rb`

**Test Structure:**

```ruby
RSpec.describe "Module Callback Integration" do
  # End-to-end tests for callback configuration system

  # 1. Default callback timing (3 tests)
  - SimpleAudit uses :before_save by default
  - Callback executes at correct time
  - Multiple models use same default

  # 2. Configured callback timing (6 tests)
  - Can configure to :after_save
  - Can configure to :after_commit
  - Configuration applies to all models
  - Configuration persists across compiles
  - Can configure different modules independently
  - Invalid callback raises error

  # 3. Interaction with dependency compilation (4 tests)
  - Callbacks execute after dependency resolution
  - Callbacks execute in wave order
  - Metadata is available during callback execution
  - Multiple modules' callbacks execute in order
end
```

**Estimated Tests**: ~13 new tests
**Estimated Time**: 2 hours

---

### Task 2.2: Add Cross-Adapter Validation Tests (1 hour)

**Location**: New file `spec/model_settings/cross_adapter_validation_spec.rb`

**Test Structure:**

```ruby
RSpec.describe "Cross-Adapter Validation Consistency" do
  # Ensure validators work consistently across all adapters

  # 1. BooleanValueValidator consistency (3 tests)
  - same invalid value rejected by all adapters
  - same error message across all adapters
  - same valid value accepted by all adapters

  # 2. ArrayTypeValidator consistency (3 tests)
  - same array validation across adapters
  - same error messages
  - array membership validation consistent

  # 3. Custom validators (2 tests)
  - custom validators work with all adapters
  - validation timing is consistent
end
```

**Estimated Tests**: ~8 new tests
**Estimated Time**: 1 hour

---

## Execution Order

### Recommended Order:

1. **Task 1.1: BooleanValueValidator Tests** (Day 1)
   - Highest risk, blocks v1.0
   - No dependencies on other tasks
   - Quick win (2-3 hours)

2. **Task 1.2: SimpleAudit Module Tests** (Day 1-2)
   - Medium-high risk
   - No dependencies
   - Longer task (3-4 hours)

3. **Task 2.1: Module Callback Integration** (Day 2)
   - Builds on SimpleAudit tests
   - Validates end-to-end flow
   - 2 hours

4. **Task 2.2: Cross-Adapter Validation** (Day 2)
   - Builds on BooleanValueValidator tests
   - Ensures consistency
   - 1 hour (quick)

---

## Success Metrics

### Before Starting:
- Total Examples: 1,205
- Failures: 0
- Critical Gaps: 2

### After Phase 1 (Target):
- Total Examples: ~1,277 (+72)
- Failures: 0
- Critical Gaps: 0 ✅

### After Phase 2 (Target):
- Total Examples: ~1,298 (+93)
- Failures: 0
- All High Priority Gaps: 0 ✅

### Final Quality Targets:
- [ ] All tests pass (0 failures)
- [ ] BooleanValueValidator fully tested
- [ ] SimpleAudit module fully tested
- [ ] Validation consistency verified
- [ ] Module callback integration verified
- [ ] Execution time < 20 seconds (from ~14s)
- [ ] Confidence level: 95%+ for v1.0

---

## Risk Mitigation

### Risk 1: Tests May Find Bugs
**Likelihood**: MEDIUM
**Impact**: HIGH
**Mitigation**:
- Run tests incrementally
- Fix bugs as found
- May extend timeline by 2-4 hours

### Risk 2: Integration Tests May Fail Due to Shared State
**Likelihood**: LOW
**Impact**: MEDIUM
**Mitigation**:
- Use registry_state_helper (already implemented)
- Follow save/restore pattern
- Isolate test data

### Risk 3: BooleanValueValidator May Need Refactoring
**Likelihood**: LOW
**Impact**: MEDIUM
**Mitigation**:
- Review implementation before writing tests
- Test current behavior, note issues
- Propose refactoring separately if needed

---

## Rollout Plan

### Step 1: Create Test Files (5 minutes)
```bash
touch spec/model_settings/validators/boolean_value_validator_spec.rb
touch spec/model_settings/modules/simple_audit_spec.rb
touch spec/model_settings/module_callback_integration_spec.rb
touch spec/model_settings/cross_adapter_validation_spec.rb
```

### Step 2: Implement Task 1.1 (2-3 hours)
- Write BooleanValueValidator unit tests
- Add integration tests to adapter specs
- Run tests: `bundle exec rspec spec/model_settings/validators/boolean_value_validator_spec.rb`
- Fix any found issues
- Run full suite: `bundle exec rspec`

### Step 3: Implement Task 1.2 (3-4 hours)
- Write SimpleAudit module tests
- Run tests: `bundle exec rspec spec/model_settings/modules/simple_audit_spec.rb`
- Fix any found issues
- Run full suite: `bundle exec rspec`

### Step 4: Implement Task 2.1 (2 hours)
- Write module callback integration tests
- Run tests incrementally
- Verify end-to-end flows

### Step 5: Implement Task 2.2 (1 hour)
- Write cross-adapter validation tests
- Verify consistency
- Run full suite

### Step 6: Final Verification (30 minutes)
- Run full test suite: `bundle exec rspec`
- Verify metrics meet targets
- Run linter: `bundle exec standardrb`
- Update CHANGELOG.md

---

## Deliverables

1. **New Test Files (4 files)**:
   - `spec/model_settings/validators/boolean_value_validator_spec.rb`
   - `spec/model_settings/modules/simple_audit_spec.rb`
   - `spec/model_settings/module_callback_integration_spec.rb`
   - `spec/model_settings/cross_adapter_validation_spec.rb`

2. **Updated Test Files (3 files)**:
   - `spec/model_settings/adapters/column_spec.rb` (add validation tests)
   - `spec/model_settings/adapters/json_spec.rb` (add validation tests)
   - `spec/model_settings/adapters/store_model_spec.rb` (add validation tests)

3. **Updated Documentation**:
   - `CHANGELOG.md` (note improved test coverage)
   - This plan document (mark tasks complete)

4. **Test Metrics Report**:
   - Before/after comparison
   - Coverage improvement percentage
   - Execution time impact

---

## Timeline

**Total Estimated Time**: 8-11 hours (including buffer for bug fixes)

- **Phase 1 (Critical)**: 5-7 hours
  - Task 1.1: 2-3 hours
  - Task 1.2: 3-4 hours

- **Phase 2 (High Priority)**: 3 hours
  - Task 2.1: 2 hours
  - Task 2.2: 1 hour

- **Buffer for Issues**: 2-3 hours

**Target Completion**: 2 working days (assuming 4-6 hours per day)

---

## Next Steps

1. ✅ Review this plan with user
2. ✅ Get approval to proceed
3. ⏸️ Create test file skeletons
4. ⏸️ Implement Task 1.1 (BooleanValueValidator)
5. ⏸️ Implement Task 1.2 (SimpleAudit)
6. ⏸️ Implement Task 2.1 (Module Callback Integration)
7. ⏸️ Implement Task 2.2 (Cross-Adapter Validation)
8. ⏸️ Final verification and commit

---

**Plan End**
