# Policy-Based Authorization Modules

Common documentation for policy-based authorization modules (Pundit and ActionPolicy).

---

## Overview

Policy-based authorization modules integrate ModelSettings with authorization frameworks by storing authorization metadata at compile-time and using it in policies at runtime.

**Available Modules:**
- **[Pundit](pundit.md)** - Integration with Pundit gem
- **[ActionPolicy](action_policy.md)** - Integration with ActionPolicy gem

**Module Exclusivity:** You can only use ONE policy-based authorization module per model. They are mutually exclusive because they provide different authorization APIs.

---

## How Policy-Based Authorization Works

Policy-based modules follow a three-stage flow:

### 1. Model Stage (Compile-Time)

Settings are defined with `authorize_with` option:

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL
  include ModelSettings::Modules::Pundit  # or ActionPolicy

  setting :billing_override,
          type: :column,
          authorize_with: :manage_billing?

  setting :api_access,
          type: :column,
          authorize_with: :admin?
end
```

**What happens:**
- Module intercepts `setting()` DSL method
- Stores authorization metadata: `{ billing_override: :manage_billing?, api_access: :admin? }`
- Metadata stored in `Model._authorized_settings` class attribute
- No runtime validation - just metadata storage

### 2. Policy Stage (Request Time)

Policy uses stored metadata to determine permitted attributes:

```ruby
class UserPolicy < ApplicationPolicy
  def permitted_attributes
    attrs = [:email, :name]  # Always permitted

    # Dynamically add settings based on metadata
    record.class._authorized_settings.each do |setting_name, auth_method|
      attrs << setting_name if send(auth_method)
    end

    attrs
  end

  # Authorization methods referenced by authorize_with
  def manage_billing?
    user.admin? || user.has_role?(:finance_manager)
  end

  def admin?
    user.admin?
  end
end
```

**What happens:**
- Policy reads `_authorized_settings` metadata
- For each setting, checks if user has required permission (calls `manage_billing?`, etc.)
- Returns list of permitted attribute names
- **Policy is single source of truth** for authorization logic

### 3. Controller Stage (Request Time)

Controller uses policy-permitted attributes to filter parameters:

```ruby
class UsersController < ApplicationController
  def update
    @user = User.find(params[:id])
    authorize @user  # or authorize! for ActionPolicy

    # Framework-specific filtering (see Pundit/ActionPolicy docs)
    @user.update(permitted_attributes(@user))  # Pundit
    # OR
    @user.update(authorized(params.require(:user)))  # ActionPolicy
  end
end
```

**What happens:**
- Controller authorizes the action
- Policy filters parameters based on permissions
- Only permitted settings are saved to database
- **No authorization logic in model** - model just saves

---

## Flow Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ 1. MODEL (Compile-Time) - Metadata Storage                                 │
└─────────────────────────────────────────────────────────────────────────────┘

class User < ApplicationRecord
  include ModelSettings::DSL
  include ModelSettings::Modules::Pundit

  setting :billing_override,
          authorize_with: :manage_billing?
                                              ↓
                        Stores metadata in User._authorized_settings
                                { billing_override: :manage_billing? }

┌─────────────────────────────────────────────────────────────────────────────┐
│ 2. POLICY (Request Time) - Permission Check                                │
└─────────────────────────────────────────────────────────────────────────────┘

class UserPolicy < ApplicationPolicy
  def permitted_attributes
    attrs = [:email, :name]

    # Read metadata
    record.class._authorized_settings.each do |setting_name, auth_method|
      attrs << setting_name if send(auth_method)  # Call manage_billing?
    end
                                              ↓
    attrs  # Returns [:email, :name, :billing_override] if authorized
  end

  def manage_billing?
    user.admin? || user.has_role?(:finance_manager)  # Authorization logic HERE
  end
end

┌─────────────────────────────────────────────────────────────────────────────┐
│ 3. CONTROLLER (Request Time) - Parameter Filtering                         │
└─────────────────────────────────────────────────────────────────────────────┘

class UsersController < ApplicationController
  def update
    @user = User.find(params[:id])
    authorize @user
                                              ↓
    @user.update(permitted_attributes(@user))  # Uses policy's permitted list
                                              ↓
                            Only :billing_override saved (if authorized)
                            Unauthorized params rejected by strong parameters
  end
end
```

---

## Key Principles

### 1. Compile-Time Metadata Storage

Modules store authorization requirements at class loading time:

```ruby
# When class loads:
User._authorized_settings
# => { billing_override: :manage_billing?, api_access: :admin? }
```

**No runtime overhead** - metadata stored once, read many times.

### 2. Policy as Single Source of Truth

Authorization logic lives **only in policy**, not in model:

```ruby
# ✅ GOOD - Logic in policy only
class UserPolicy < ApplicationPolicy
  def manage_billing?
    user.admin? ||
    user.has_role?(:finance_manager) ||
    (user.owner? && record.billing_enabled?)
  end
end

# ❌ BAD - Logic split between model and policy
class User < ApplicationRecord
  setting :billing_override, authorize_with: :manage_billing?

  def can_manage_billing?(user)  # DON'T DO THIS
    # Duplicates policy logic
  end
end
```

### 3. No Runtime Validation in Model

Model does **not** validate authorization during save:

```ruby
# Model just saves - NO authorization checks
@user.billing_override = true
@user.save!  # Saves without checking permissions
```

Authorization happens in **controller** via strong parameters:

```ruby
# Controller filters params BEFORE passing to model
permitted_params = permitted_attributes(@user)  # Policy filters here
@user.update(permitted_params)  # Model receives only allowed params
```

### 4. Standard Framework Patterns

Modules integrate with existing authorization patterns - no new methods needed:

**Pundit:**
- Use `permitted_attributes` (standard Pundit method)
- No new methods like `update_with_authorization`

**ActionPolicy:**
- Use `params_filter` and `authorized()` (standard ActionPolicy methods)
- No new controller methods

---

## Common Metadata API

Both modules provide the same metadata storage:

### `Model._authorized_settings`

Hash mapping setting names to authorization methods:

```ruby
User._authorized_settings
# => { billing_override: :manage_billing?, api_access: :admin? }
```

**Usage in Policy:**
```ruby
def permitted_attributes
  attrs = [:email, :name]

  record.class._authorized_settings.each do |setting_name, auth_method|
    attrs << setting_name if send(auth_method)
  end

  attrs
end
```

---

## Module Options

### `authorize_with`

Specify which policy method to call for authorization:

```ruby
setting :billing_override,
        type: :column,
        authorize_with: :manage_billing?
```

**Type:** Symbol (method name)
**Required:** No (settings without `authorize_with` are always permitted)

**Example:**
```ruby
class User < ApplicationRecord
  include ModelSettings::DSL
  include ModelSettings::Modules::Pundit

  # Requires permission
  setting :billing_override,
          authorize_with: :manage_billing?

  # Always permitted (no authorization)
  setting :display_name,
          type: :column
end
```

---

## Comparison: Pundit vs ActionPolicy

Both modules work the same way conceptually, but differ in implementation details:

| Aspect | Pundit | ActionPolicy |
|--------|--------|--------------|
| **Metadata Storage** | ✅ Same (`_authorized_settings`) | ✅ Same (`_authorized_settings`) |
| **Policy Method** | `permitted_attributes` | `params_filter` block |
| **Controller Filtering** | `permitted_attributes(@record)` | `authorized(params)` |
| **Authorization Check** | `authorize @record` | `authorize! @record` |
| **Philosophy** | Manual `permit()` with policy list | Automatic filtering via `params_filter` |

**See detailed differences:**
- [Pundit Module Documentation](pundit.md)
- [ActionPolicy Module Documentation](action_policy.md)

---

## Installation

### Pundit

```ruby
# Gemfile
gem 'pundit'

# Model
class User < ApplicationRecord
  include ModelSettings::DSL
  include ModelSettings::Modules::Pundit  # Add this

  setting :billing_override, authorize_with: :manage_billing?
end
```

### ActionPolicy

```ruby
# Gemfile
gem 'action_policy'

# Model
class User < ApplicationRecord
  include ModelSettings::DSL
  include ModelSettings::Modules::ActionPolicy  # Add this

  setting :billing_override, authorize_with: :manage_billing?
end
```

**Important:** Only include ONE authorization module per model. They are mutually exclusive.

---

## Complete Example

### Model

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL
  include ModelSettings::Modules::Pundit  # Choose Pundit or ActionPolicy

  setting :billing_override,
          type: :column,
          default: false,
          authorize_with: :manage_billing?

  setting :api_access,
          type: :column,
          default: false,
          authorize_with: :admin?

  setting :display_name,
          type: :column  # No authorization - always editable
end
```

### Policy (Pundit)

```ruby
class UserPolicy < ApplicationPolicy
  def permitted_attributes
    attrs = [:email, :display_name]  # Always permitted

    # Add authorized settings dynamically
    record.class._authorized_settings.each do |setting_name, auth_method|
      attrs << setting_name if send(auth_method)
    end

    attrs
  end

  def manage_billing?
    user.admin? || user.has_role?(:finance_manager)
  end

  def admin?
    user.admin?
  end
end
```

### Controller

```ruby
class UsersController < ApplicationController
  def update
    @user = User.find(params[:id])
    authorize @user

    if @user.update(permitted_attributes(@user))
      redirect_to @user, notice: 'User updated'
    else
      render :edit
    end
  end
end
```

**Result:**
- Admin user: Can edit `billing_override`, `api_access`, `display_name`
- Finance manager: Can edit `billing_override`, `display_name` (not `api_access`)
- Regular user: Can edit `display_name` only

---

## Testing

### Testing Metadata Storage

```ruby
RSpec.describe User do
  it "stores authorization metadata" do
    expect(User._authorized_settings).to include(
      billing_override: :manage_billing?,
      api_access: :admin?
    )
  end
end
```

### Testing Policy

```ruby
RSpec.describe UserPolicy do
  let(:user) { User.new }
  let(:admin) { User.new(admin: true) }

  describe "#permitted_attributes" do
    context "when user is admin" do
      subject { described_class.new(admin, user) }

      it "permits all authorized settings" do
        expect(subject.permitted_attributes).to include(
          :billing_override,
          :api_access
        )
      end
    end

    context "when user is NOT admin" do
      subject { described_class.new(User.new, user) }

      it "does NOT permit admin settings" do
        expect(subject.permitted_attributes).not_to include(
          :billing_override,
          :api_access
        )
      end
    end
  end
end
```

---

## Related Documentation

- **[Pundit Module](pundit.md)** - Pundit-specific implementation details
- **[ActionPolicy Module](action_policy.md)** - ActionPolicy-specific implementation details
- **[Roles Module](../roles.md)** - Alternative: Simple role-based authorization (no policy framework)
- **[Module Development](../../guides/module_development.md)** - Creating custom modules

---

## Summary

**Policy-based authorization modules:**
1. ✅ Store metadata at compile-time (no runtime overhead)
2. ✅ Use policy as single source of truth
3. ✅ Integrate with standard framework patterns
4. ✅ No authorization logic in model
5. ✅ Authorization happens in controller via strong parameters

**Choose your module:**
- Already using **Pundit**? → Use `ModelSettings::Modules::Pundit`
- Already using **ActionPolicy**? → Use `ModelSettings::Modules::ActionPolicy`
- Need simple **role-based** auth? → Use `ModelSettings::Modules::Roles`
