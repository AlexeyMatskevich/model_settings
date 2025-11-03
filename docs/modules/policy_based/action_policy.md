# ActionPolicy Module

Integration with ActionPolicy authorization framework.

**For common policy-based concepts, see [Policy-Based Authorization Overview](README.md).**

---

## ActionPolicy-Specific Implementation

### Policy Method: `params_filter`

ActionPolicy uses `params_filter` block for automatic parameter filtering:

```ruby
class UserPolicy < ActionPolicy::Base
  # params_filter automatically filters parameters
  params_filter do |params|
    allowed = [:email, :name]  # Always permitted base attributes

    # Add authorized settings using metadata
    record.class._authorized_settings.each do |setting_name, auth_method|
      allowed << setting_name if public_send(auth_method)
    end

    params.permit(*allowed)
  end

  # Manual alternative (less DRY)
  params_filter do |params|
    allowed = [:email, :name]

    allowed << :billing_override if manage_billing?
    allowed << :api_access if admin?

    params.permit(*allowed)
  end
end
```

**Key points:**
- Returns filtered params object (not array)
- Automatically applied via `authorized()` helper
- Uses `public_send` (not `send`) for authorization methods
- Standard ActionPolicy pattern

---

## Controller Usage

Use ActionPolicy's `authorized()` helper to apply params_filter:

```ruby
class UsersController < ApplicationController
  def update
    @user = User.find(params[:id])
    authorize! @user  # Standard ActionPolicy authorization

    # ActionPolicy's way - authorized() applies params_filter automatically
    filtered_params = authorized(params.require(:user))

    if @user.update(filtered_params)
      redirect_to @user, notice: 'Settings updated'
    else
      render :edit
    end
  end
end
```

**What `authorized(params)` does:**
1. Finds policy class (`UserPolicy`)
2. Calls `policy.params_filter` block with params
3. Returns filtered params object
4. **Automatic** - no manual `permit()` call needed

**Key difference from Pundit:** `authorized()` returns filtered params directly, not an array of permitted keys.

---

## Complete Example

### 1. Model

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL
  include ModelSettings::Modules::ActionPolicy

  setting :billing_override,
          type: :column,
          authorize_with: :manage_billing?

  setting :api_access,
          type: :column,
          authorize_with: :admin?

  setting :display_name,
          type: :column  # No authorization
end
```

### 2. Policy

```ruby
class UserPolicy < ActionPolicy::Base
  # Standard ActionPolicy params_filter
  params_filter do |params|
    allowed = [:email, :display_name]

    # Dynamic approach using metadata
    record.class._authorized_settings.each do |setting_name, auth_method|
      allowed << setting_name if public_send(auth_method)
    end

    params.permit(*allowed)
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

### 3. Controller

```ruby
class UsersController < ApplicationController
  def update
    @user = User.find(params[:id])
    authorize! @user

    # authorized() automatically applies params_filter
    filtered_params = authorized(params.require(:user))

    if @user.update(filtered_params)
      redirect_to @user, notice: 'User updated'
    else
      render :edit
    end
  end
end
```

---

## Named Filters

ActionPolicy supports named filters for different actions:

```ruby
class UserPolicy < ActionPolicy::Base
  # Default filter
  params_filter do |params|
    allowed = [:email, :display_name]
    record.class._authorized_settings.each do |name, method|
      allowed << name if public_send(method)
    end
    params.permit(*allowed)
  end

  # Named filter for admin updates
  params_filter :admin_update do |params|
    # Admins can update everything
    all_settings = record.class._authorized_settings.keys
    params.permit(:email, :display_name, *all_settings)
  end
end
```

**Usage in controller:**
```ruby
def update
  authorize! @user

  # Use named filter
  if current_user.admin?
    filtered = authorized(params.require(:user), as: :admin_update)
  else
    filtered = authorized(params.require(:user))
  end

  @user.update(filtered)
end
```

---

## Testing

### Policy Specs

```ruby
RSpec.describe UserPolicy do
  let(:user) { User.create! }
  let(:admin) { User.create!(admin: true) }
  let(:finance_manager) { User.create!(roles: [:finance_manager]) }

  describe "#params_filter" do
    let(:params) do
      ActionController::Parameters.new(
        user: {
          email: "new@example.com",
          billing_override: true,
          api_access: true,
          display_name: "New Name"
        }
      )
    end

    context "when user is admin" do
      subject(:policy) { described_class.new(user, user: admin) }

      it "permits all authorized settings" do
        filtered = policy.params_filter.call(params[:user])

        expect(filtered.permitted?).to be true
        expect(filtered.keys).to include(
          "billing_override",
          "api_access",
          "display_name"
        )
      end
    end

    context "when user is finance manager" do
      subject(:policy) { described_class.new(user, user: finance_manager) }

      it "permits billing settings" do
        filtered = policy.params_filter.call(params[:user])

        expect(filtered.keys).to include("billing_override")
      end

      it "does NOT permit admin settings" do
        filtered = policy.params_filter.call(params[:user])

        expect(filtered.keys).not_to include("api_access")
      end
    end

    context "when user is regular user" do
      subject(:policy) { described_class.new(user, user: User.new) }

      it "only permits display_name" do
        filtered = policy.params_filter.call(params[:user])

        expect(filtered.keys).to include("display_name")
        expect(filtered.keys).not_to include("billing_override", "api_access")
      end
    end
  end

  describe "#manage_billing?" do
    it "returns true for admin" do
      policy = described_class.new(user, user: admin)
      expect(policy.manage_billing?).to be true
    end

    it "returns true for finance manager" do
      policy = described_class.new(user, user: finance_manager)
      expect(policy.manage_billing?).to be true
    end

    it "returns false for regular user" do
      policy = described_class.new(user, user: User.new)
      expect(policy.manage_billing?).to be false
    end
  end
end
```

### Controller Request Specs

```ruby
RSpec.describe "Users", type: :request do
  let(:user) { User.create!(email: "user@example.com") }
  let(:admin) { User.create!(email: "admin@example.com", admin: true) }

  describe "PATCH /users/:id" do
    context "when user is admin" do
      before { sign_in admin }

      it "allows updating billing_override" do
        patch user_path(user), params: {
          user: { billing_override: true }
        }

        expect(user.reload.billing_override).to be true
      end
    end

    context "when user is NOT admin" do
      before { sign_in User.create! }

      it "does NOT allow updating billing_override" do
        patch user_path(user), params: {
          user: { billing_override: true }
        }

        expect(user.reload.billing_override).to be false
      end
    end
  end
end
```

---

## Pundit vs ActionPolicy

| Feature | Pundit | ActionPolicy |
|---------|--------|--------------|
| **Policy Method** | `permitted_attributes` | `params_filter` block |
| **Returns** | Array of symbols | Filtered params object |
| **Controller** | `permitted_attributes(@record)` | `authorized(params)` |
| **Authorization** | `authorize @record` | `authorize! @record` |
| **Philosophy** | Manual `permit()` in controller | Automatic via `params_filter` |
| **Named Filters** | Not built-in | ✅ `params_filter :name` |

**See:** [Pundit Module](pundit.md) for Pundit-specific details.

---

## Common Issues

### Issue: `public_send` not found

**Problem:**
```ruby
params_filter do |params|
  record.class._authorized_settings.each do |name, method|
    allowed << name if send(method)  # May not work
  end
end
```

**Cause:** ActionPolicy policies use `public_send` for security

**Solution:** Use `public_send` instead of `send`:
```ruby
params_filter do |params|
  record.class._authorized_settings.each do |name, method|
    allowed << name if public_send(method)  # ✅ GOOD
  end
end
```

### Issue: `authorized()` returns unpermitted params

**Problem:** Params marked as unpermitted

**Cause:** `params_filter` not calling `permit()`

**Solution:**
```ruby
# ❌ BAD - Forgot to call permit()
params_filter do |params|
  allowed = [:email, :name]
  # Missing: params.permit(*allowed)
end

# ✅ GOOD - Call permit()
params_filter do |params|
  allowed = [:email, :name]
  params.permit(*allowed)  # Must call this!
end
```

### Issue: Settings not filtered

**Problem:** Unauthorized settings being saved

**Cause:** Not using `authorized()` helper

**Solution:**
```ruby
# ❌ BAD - No filtering
@user.update(params.require(:user))

# ✅ GOOD - Use authorized()
@user.update(authorized(params.require(:user)))
```

---

## Related Documentation

- **[Policy-Based Authorization Overview](README.md)** - Common concepts for all policy-based modules
- **[Pundit Module](pundit.md)** - Alternative policy framework
- **[Roles Module](../roles.md)** - Simple role-based alternative
- **[ActionPolicy Gem Documentation](https://actionpolicy.evilmartians.io)** - Official ActionPolicy docs

---

## Summary

**ActionPolicy Module provides:**
- ✅ Standard `params_filter` integration
- ✅ Automatic parameter filtering via `authorized()`
- ✅ Named filters for different actions
- ✅ Dynamic permission checking via metadata
- ✅ Clean separation: metadata in model, logic in policy

**Use when:**
- You already use ActionPolicy in your application
- You prefer automatic parameter filtering
- You want named filters for different contexts
- You follow ActionPolicy patterns

## See Also

- [Module Development Guide](../../guides/module_development.md) - Learn how to create custom modules like ActionPolicy
- [ModuleRegistry API Reference](../../api/module_registry.md) - Complete API documentation
- [Custom Module Example](../../../examples/custom_module/) - Working example of a custom module
- [Policy-Based Authorization](README.md) - Overview of policy-based modules
- [Configuration Guide](../../core/configuration.md) - Global configuration options
