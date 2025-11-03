# Pundit Module

Integration with Pundit authorization framework.

**For common policy-based concepts, see [Policy-Based Authorization Overview](README.md).**

---

## Pundit-Specific Implementation

### Policy Method: `permitted_attributes`

Pundit uses the standard `permitted_attributes` method pattern:

```ruby
class UserPolicy < ApplicationPolicy
  def permitted_attributes
    attrs = [:email, :name]  # Always permitted base attributes

    # Add authorized settings using metadata
    record.class._authorized_settings.each do |setting_name, auth_method|
      attrs << setting_name if send(auth_method)
    end

    attrs
  end

  # Manual alternative (less DRY)
  def permitted_attributes
    attrs = [:email, :name]

    attrs << :billing_override if manage_billing?
    attrs << :api_access if admin?

    attrs
  end
end
```

**Key points:**
- Returns Array of permitted attribute names
- Called by controller via `permitted_attributes(@record)`
- Standard Pundit pattern - no new methods

---

## Controller Usage

Use standard Pundit `permitted_attributes` helper:

```ruby
class UsersController < ApplicationController
  def update
    @user = User.find(params[:id])
    authorize @user  # Standard Pundit authorization

    # Standard Pundit pattern
    if @user.update(permitted_attributes(@user))
      redirect_to @user, notice: 'Settings updated'
    else
      render :edit
    end
  end
end
```

**What `permitted_attributes(@user)` does:**
1. Finds policy class (`UserPolicy`)
2. Calls `policy.permitted_attributes`
3. Returns array of symbols: `[:email, :name, :billing_override]`
4. Controller then does: `params.require(:user).permit(*permitted_attrs)`

---

## Complete Example

### 1. Model

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL
  include ModelSettings::Modules::Pundit

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
class UserPolicy < ApplicationPolicy
  # Standard Pundit method
  def permitted_attributes
    attrs = [:email, :display_name]

    # Dynamic approach using metadata
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

### 3. Controller

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

---

## Authorization Inheritance

Child settings can inherit authorization from their parent settings using a 5-level priority system.

### Explicit `:inherit` Keyword

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL
  include ModelSettings::Modules::Pundit

  setting :billing, authorize_with: :manage_billing? do
    setting :invoices, authorize_with: :inherit  # Inherits :manage_billing?
    setting :reports, authorize_with: :inherit   # Inherits :manage_billing?
  end
end
```

### Setting-Level `inherit_authorization` Option

```ruby
setting :billing, authorize_with: :manage_billing? do
  setting :invoices, inherit_authorization: true   # Inherits :manage_billing?
  setting :archive, inherit_authorization: false   # No inheritance
end
```

### Model-Level Configuration

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL
  include ModelSettings::Modules::Pundit

  settings_config inherit_authorization: true  # All nested settings inherit by default

  setting :billing, authorize_with: :manage_billing? do
    setting :invoices    # Automatically inherits :manage_billing?
    setting :reports     # Automatically inherits :manage_billing?
  end
end
```

### Global Configuration

```ruby
# config/initializers/model_settings.rb
ModelSettings.configure do |config|
  config.inherit_authorization = true  # Enable inheritance globally
end
```

### 5-Level Priority System

Authorization is resolved using this priority (highest to lowest):

1. **Explicit setting value** - `authorize_with: :admin?`
2. **Explicit `:inherit` keyword** - `authorize_with: :inherit`
3. **Setting `inherit_authorization` option** - `inherit_authorization: true`
4. **Model `settings_config`** - `settings_config inherit_authorization: true`
5. **Global configuration** - `ModelSettings.configuration.inherit_authorization`

### Querying Inherited Authorization

```ruby
# Find authorization for a setting (including inherited)
User.authorization_for_setting(:invoices)  # => :manage_billing? (inherited)

# Find all settings requiring a specific permission
User.settings_requiring(:manage_billing?)  # => [:billing, :invoices, :reports]

# Find all settings with any authorization
User.authorized_settings  # => [:billing, :invoices, :reports]
```

**Note:** For policy-based modules like Pundit, `:view_only` and `:edit_only` options behave the same as `true` since Pundit uses a single `authorize_with` for both viewing and editing.

---

## Testing

### Policy Specs

```ruby
RSpec.describe UserPolicy do
  let(:user) { User.create! }
  let(:admin) { User.create!(admin: true) }
  let(:finance_manager) { User.create!(roles: [:finance_manager]) }

  describe "#permitted_attributes" do
    context "when user is admin" do
      subject(:policy) { described_class.new(admin, user) }

      it "permits all authorized settings" do
        expect(policy.permitted_attributes).to include(
          :billing_override,
          :api_access,
          :display_name
        )
      end
    end

    context "when user is finance manager" do
      subject(:policy) { described_class.new(finance_manager, user) }

      it "permits billing settings" do
        expect(policy.permitted_attributes).to include(:billing_override)
      end

      it "does NOT permit admin settings" do
        expect(policy.permitted_attributes).not_to include(:api_access)
      end
    end

    context "when user is regular user" do
      subject(:policy) { described_class.new(User.new, user) }

      it "only permits display_name" do
        permitted = policy.permitted_attributes
        expect(permitted).to include(:display_name)
        expect(permitted).not_to include(:billing_override, :api_access)
      end
    end
  end

  describe "#manage_billing?" do
    it "returns true for admin" do
      policy = described_class.new(admin, user)
      expect(policy.manage_billing?).to be true
    end

    it "returns true for finance manager" do
      policy = described_class.new(finance_manager, user)
      expect(policy.manage_billing?).to be true
    end

    it "returns false for regular user" do
      policy = described_class.new(User.new, user)
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
| **Manual Filtering** | Controller calls `params.permit(...)` | Automatic via `params_filter` |

**See:** [ActionPolicy Module](action_policy.md) for ActionPolicy-specific details.

---

## Common Issues

### Issue: `permitted_attributes` returns empty array

**Problem:**
```ruby
policy.permitted_attributes  # => [:email, :name]
# Missing settings!
```

**Cause:** Authorization methods return `false`

**Solution:** Check authorization method logic:
```ruby
def manage_billing?
  puts "User admin: #{user.admin?}"  # Debug
  user.admin?
end
```

### Issue: Settings not filtered in controller

**Problem:** Unauthorized settings are being saved

**Cause:** Not using `permitted_attributes` helper

**Solution:**
```ruby
# ❌ BAD - No filtering
@user.update(params.require(:user))

# ✅ GOOD - Use permitted_attributes
@user.update(permitted_attributes(@user))
```

---

## Related Documentation

- **[Policy-Based Authorization Overview](README.md)** - Common concepts for all policy-based modules
- **[ActionPolicy Module](action_policy.md)** - Alternative policy framework
- **[Roles Module](../roles.md)** - Simple role-based alternative
- **[Pundit Gem Documentation](https://github.com/varvet/pundit)** - Official Pundit docs

---

## Summary

**Pundit Module provides:**
- ✅ Standard `permitted_attributes` integration
- ✅ No new controller methods needed
- ✅ Dynamic permission checking via metadata
- ✅ Clean separation: metadata in model, logic in policy

**Use when:**
- You already use Pundit in your application
- You prefer explicit `permitted_attributes` method
- You want standard Pundit patterns

## See Also

- [Module Development Guide](../../guides/module_development.md) - Learn how to create custom modules like Pundit
- [ModuleRegistry API Reference](../../core/module_registry.md) - Complete API documentation
- [Custom Module Example](../../../examples/custom_module/) - Working example of a custom module
- [Policy-Based Authorization](README.md) - Overview of policy-based modules
- [Configuration Guide](../../core/configuration.md) - Global configuration options
