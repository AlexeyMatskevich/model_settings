# Validation

ModelSettings provides built-in boolean validation and a framework for custom validators.

## Built-in Boolean Validation

**All boolean settings automatically validate** that values are `true`, `false`, or `nil`. This prevents Rails' permissive type coercion.

### Why Strict Validation?

Rails' default boolean type casting converts strings (`"1"`, `"true"`, `"yes"`) and integers (`1`, `0`) to booleans. This permissive behavior can lead to unexpected bugs when settings are manipulated programmatically.

```ruby
# Rails default behavior (WITHOUT ModelSettings):
user.premium = "true"  # Coerced to true
user.premium = 1       # Coerced to true
user.premium = "yes"   # Coerced to true

# ModelSettings strict validation:
user.premium = "true"  # ❌ Validation error
user.premium = 1       # ❌ Validation error
user.premium = "yes"   # ❌ Validation error
```

### Automatic Validation

Validation is applied to all **leaf settings** (settings without children) across all storage adapters:

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  setting :premium, type: :column
  setting :notifications, type: :json, storage: {column: :settings}
end

user = User.new

# ✅ Valid
user.premium = true
user.premium = false
user.premium = nil

# ❌ Invalid
user.premium = "true"
user.valid?  # => false
user.errors[:premium]  # => ["must be true or false (got: \"true\")"]

user.premium = 1
user.valid?  # => false
user.errors[:premium]  # => ["must be true or false (got: 1)"]
```

### What Gets Validated

**Validated**:
- ✅ Leaf settings (settings without nested children)
- ✅ All storage types (Column, JSON, StoreModel)

**Not Validated**:
- ❌ Parent/container settings (settings with `do...end` blocks)
- ❌ Array-type settings (`array: true`)

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  # ✅ Validated (leaf setting)
  setting :premium, type: :column

  # ❌ NOT validated (has children)
  setting :features, type: :json, storage: {column: :data} do
    setting :analytics, default: false  # ✅ Validated (leaf)
  end

  # ❌ NOT validated (array type)
  setting :tags, type: :json, storage: {column: :data}, array: true
end
```

---

## Custom Validators

Add custom validation logic to settings using the `validate_with` option.

### Basic Custom Validator

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  setting :premium_mode,
          type: :column,
          validate_with: :check_subscription_active

  private

  def check_subscription_active
    unless subscription_active?
      add_setting_error(:premium_mode, "requires active subscription")
    end
  end
end

# Usage
user = User.new
user.validate_setting(:premium_mode)  # => false
user.setting_errors_for(:premium_mode)  # => ["Premium mode requires active subscription"]
```

### Multiple Validators

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  setting :api_access,
          type: :column,
          validate_with: [:check_api_quota, :check_api_permissions]

  private

  def check_api_quota
    if api_calls_this_month >= api_quota
      add_setting_error(:api_access, "API quota exceeded")
    end
  end

  def check_api_permissions
    unless has_api_role?
      add_setting_error(:api_access, "requires API role")
    end
  end
end
```

### Validation Methods

**add_setting_error(setting_name, message)**

Add a validation error to a specific setting:

```ruby
add_setting_error(:premium_mode, "requires active subscription")
```

**validate_setting(setting_name)**

Validate a specific setting and return true/false:

```ruby
if user.validate_setting(:premium_mode)
  # Valid
else
  # Invalid
end
```

**setting_errors_for(setting_name)**

Get all errors for a setting:

```ruby
user.setting_errors_for(:premium_mode)
# => ["requires active subscription", "payment method required"]
```

---

## Integration with ActiveModel

ModelSettings validation integrates seamlessly with ActiveRecord validations:

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  setting :premium_mode, type: :column, validate_with: :check_subscription

  validates :email, presence: true

  private

  def check_subscription
    add_setting_error(:premium_mode, "invalid") unless subscription_active?
  end
end

user = User.new
user.valid?  # => false

# Both ActiveRecord and setting errors
user.errors.full_messages
# => ["Email can't be blank", "Premium mode invalid"]
```

---

## Validation Lifecycle

Validations run during ActiveRecord's validation phase:

```
1. user.premium_mode = value
2. user.save!
3. ActiveRecord validations run
4. ModelSettings validations run (including custom validators)
5. If valid: proceed with save
6. If invalid: rollback, return false
```

---

## Advanced Patterns

### Conditional Validation

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  setting :beta_features,
          type: :column,
          validate_with: :check_beta_eligibility

  private

  def check_beta_eligibility
    return unless beta_features  # Only validate when enabling

    unless eligible_for_beta?
      add_setting_error(:beta_features, "not eligible for beta program")
    end
  end
end
```

### Cross-Setting Validation

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  setting :advanced_analytics, type: :column, validate_with: :require_premium
  setting :premium, type: :column

  private

  def require_premium
    if advanced_analytics && !premium
      add_setting_error(:advanced_analytics, "requires premium subscription")
    end
  end
end
```

### Context-Dependent Validation

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  setting :enterprise_features,
          type: :column,
          validate_with: :check_enterprise_plan

  private

  def check_enterprise_plan
    if enterprise_features
      unless organization&.enterprise_plan?
        add_setting_error(:enterprise_features, "requires organization with enterprise plan")
      end
    end
  end
end
```

---

## Testing Validations

```ruby
RSpec.describe User do
  describe "#premium_mode validation" do
    let(:user) { User.new }

    context "with active subscription" do
      before { allow(user).to receive(:subscription_active?).and_return(true) }

      it "allows enabling premium mode" do
        user.premium_mode = true
        expect(user).to be_valid
      end
    end

    context "without active subscription" do
      before { allow(user).to receive(:subscription_active?).and_return(false) }

      it "prevents enabling premium mode" do
        user.premium_mode = true
        expect(user).not_to be_valid
        expect(user.errors[:premium_mode]).to include("requires active subscription")
      end
    end
  end
end
```

---

## Disabling Boolean Validation

Boolean validation is always active and cannot be disabled. This is intentional to ensure data integrity.

If you need to store non-boolean values, use a different type:

```ruby
# ❌ Don't do this
setting :status, type: :column  # Boolean validation will apply

# ✅ Do this instead
# Use a string column and custom validation
add_column :users, :status, :string

class User < ApplicationRecord
  include ModelSettings::DSL

  setting :status,
          type: :column,
          validate: false,  # Disable built-in validation
          validate_with: :check_status_value

  private

  def check_status_value
    valid_statuses = %w[active inactive pending]
    unless valid_statuses.include?(status)
      add_setting_error(:status, "must be one of: #{valid_statuses.join(', ')}")
    end
  end
end
```

---

## Related Documentation

- [Callbacks](callbacks.md) - Run code before/after validation
- [Storage Adapters](adapters.md) - Validation works with all adapters
- [DSL Reference](dsl.md) - Complete setting options reference

---

## Summary

| Validation Type | When | Automatic? |
|----------------|------|-----------|
| **Boolean Validation** | All leaf boolean settings | ✅ Yes |
| **Custom Validators** | When you specify `validate_with` | ❌ No (opt-in) |
| **ActiveRecord Integration** | Always | ✅ Yes |

**Key Points**:
- Boolean validation is strict and always enabled
- Use `validate_with` for custom logic
- Validation runs during ActiveRecord's validation phase
- Errors integrate with `model.errors`
