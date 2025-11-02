# Using Roles Module with Pundit/ActionPolicy

**Use Case:** You want simple role-based metadata (`viewable_by`, `editable_by`) in your settings, but prefer to use Pundit or ActionPolicy for parameter filtering instead of the built-in authorization modules.

**Key Benefit:** Combine simple role declarations with your existing Pundit/ActionPolicy infrastructure without using `authorize_with`.

---

## Overview

This guide shows how to:
1. Use **Roles Module** for role-based metadata in settings
2. **NOT use** Pundit/ActionPolicy ModelSettings modules (no `authorize_with`)
3. Read role metadata in your Pundit/ActionPolicy policies
4. Filter permitted attributes based on roles

### When to Use This Approach

**✅ Use this when:**
- You want simple role-based settings (`viewable_by: [:admin]`)
- You already use Pundit or ActionPolicy in your app
- You want policies to handle ALL authorization logic
- You don't need complex authorization methods per setting

**❌ Don't use this when:**
- Each setting needs different authorization logic → Use policy-based modules with `authorize_with`
- You don't use Pundit/ActionPolicy → Use Roles module alone

---

## Quick Comparison

### Approach 1: Roles Module + Policy (This Guide)

```ruby
# Model - Simple role metadata
class User < ApplicationRecord
  include ModelSettings::DSL
  include ModelSettings::Modules::Roles  # Only Roles module

  setting :billing_override,
          viewable_by: :all,
          editable_by: [:admin, :finance_manager]
end

# Policy - Reads role metadata using Roles API
class UserPolicy < ApplicationPolicy
  def permitted_attributes
    attrs = [:email, :name]

    # Simple - use Roles module API
    user.roles.each do |role|
      attrs.concat(record.class.settings_editable_by(role))
    end

    attrs.uniq
  end
end
```

### Approach 2: Policy-Based Module (Alternative)

```ruby
# Model - Policy method per setting
class User < ApplicationRecord
  include ModelSettings::DSL
  include ModelSettings::Modules::Pundit  # Pundit module

  setting :billing_override,
          authorize_with: :manage_billing?  # Custom logic per setting
end

# Policy - Custom authorization methods
class UserPolicy < ApplicationPolicy
  def manage_billing?
    user.admin? || (user.finance_manager? && record.billing_enabled?)
  end
end
```

**Choose Approach 1 (this guide)** when roles are sufficient. **Choose Approach 2** when you need custom authorization logic per setting.

---

## Implementation: Roles + Pundit

### 1. Model Setup

Use **only** the Roles module (do NOT include Pundit module):

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL
  include ModelSettings::Modules::Roles  # Only Roles - NO Pundit module

  # Settings with role-based metadata
  setting :billing_override,
          type: :column,
          viewable_by: :all,           # Anyone can view
          editable_by: [:admin, :finance_manager]  # Only these roles can edit

  setting :api_access,
          type: :column,
          viewable_by: [:admin, :developer],
          editable_by: [:admin]

  setting :display_name,
          type: :column,
          viewable_by: :all,
          editable_by: :all  # Anyone can edit
end
```

**What this does:**
- Stores role metadata in `User._settings_roles`
- Provides API: `settings_editable_by(role)`, `settings_viewable_by(role)`
- Does NOT create authorization checks in model
- Just metadata for policies to use

### 2. Policy Implementation

Read role metadata and filter attributes:

```ruby
class UserPolicy < ApplicationPolicy
  # Standard Pundit method
  def permitted_attributes
    attrs = [:email]  # Always permitted base attributes

    # Simple way - use Roles module API
    user.roles.each do |role|
      attrs.concat(record.class.settings_editable_by(role))
    end

    attrs.uniq
  end

  # Alternative: Even simpler with helper method
  def permitted_attributes
    [:email] + editable_settings_for_user
  end

  private

  def editable_settings_for_user
    setting_names = []

    user.roles.each do |role|
      setting_names.concat(record.class.settings_editable_by(role))
    end

    setting_names.uniq
  end
end
```

**Key Roles Module API:**
- `Model.settings_editable_by(role)` - Returns array of setting names editable by role
- `Model.settings_viewable_by(role)` - Returns array of setting names viewable by role


### 3. Controller Usage

Standard Pundit pattern:

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

## Implementation: Roles + ActionPolicy

### 1. Model Setup

Same as Pundit - use **only** Roles module:

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL
  include ModelSettings::Modules::Roles  # Only Roles - NO ActionPolicy module

  setting :billing_override,
          viewable_by: :all,
          editable_by: [:admin, :finance_manager]

  setting :api_access,
          viewable_by: [:admin, :developer],
          editable_by: [:admin]
end
```

### 2. Policy Implementation

Use `params_filter` to read role metadata:

```ruby
class UserPolicy < ActionPolicy::Base
  # Standard ActionPolicy params_filter
  params_filter do |params|
    allowed = [:email]  # Always permitted base attributes

    # Simple way - use Roles module API
    user.roles.each do |role|
      allowed.concat(record.class.settings_editable_by(role))
    end

    params.permit(*allowed.uniq)
  end

  # Alternative: Even simpler with helper method
  params_filter do |params|
    allowed = [:email] + editable_settings_for_user
    params.permit(*allowed)
  end

  private

  def editable_settings_for_user
    setting_names = []

    user.roles.each do |role|
      setting_names.concat(record.class.settings_editable_by(role))
    end

    setting_names.uniq
  end
end
```

**Key Roles Module API:**
- `Model.settings_editable_by(role)` - Returns array of setting names editable by role
- `Model.settings_viewable_by(role)` - Returns array of setting names viewable by role


### 3. Controller Usage

Standard ActionPolicy pattern:

```ruby
class UsersController < ApplicationController
  def update
    @user = User.find(params[:id])
    authorize! @user

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

## Accessing Role Metadata

The Roles module provides convenient class methods for querying settings by role:

### High-Level API (Recommended)

**`Model.settings_editable_by(role)`** - Get settings editable by a specific role:

```ruby
User.settings_editable_by(:admin)
# => [:billing_override, :api_access, :display_name]

User.settings_editable_by(:finance_manager)
# => [:billing_override, :display_name]
```

**`Model.settings_viewable_by(role)`** - Get settings viewable by a specific role:

```ruby
User.settings_viewable_by(:developer)
# => [:api_access, :display_name]
```

**Usage in Policy:**

```ruby
class UserPolicy < ApplicationPolicy
  def permitted_attributes
    attrs = [:email]

    # Simple - use the API
    user.roles.each do |role|
      attrs.concat(record.class.settings_editable_by(role))
    end

    attrs.uniq
  end
end
```

### Low-Level API (Advanced)

For advanced use cases, you can access the raw metadata hashes:

**`Model._settings_roles`** - Hash mapping setting names to role configuration:

```ruby
User._settings_roles
# => {
#      billing_override: { viewable_by: :all, editable_by: [:admin, :finance_manager] },
#      api_access: { viewable_by: [:admin, :developer], editable_by: [:admin] },
#      display_name: { viewable_by: :all, editable_by: :all }
#    }
```

---

## Complete Example

### Model

```ruby
class Account < ApplicationRecord
  include ModelSettings::DSL
  include ModelSettings::Modules::Roles

  # Admin-only settings
  setting :billing_enabled,
          type: :column,
          default: false,
          viewable_by: :all,
          editable_by: [:admin]

  setting :max_users,
          type: :column,
          default: 10,
          viewable_by: [:admin, :owner],
          editable_by: [:admin]

  # Finance settings
  setting :invoice_frequency,
          type: :column,
          default: 'monthly',
          viewable_by: [:admin, :finance, :owner],
          editable_by: [:admin, :finance]

  # Public settings
  setting :company_name,
          type: :column,
          viewable_by: :all,
          editable_by: [:admin, :owner]

  setting :timezone,
          type: :column,
          default: 'UTC',
          viewable_by: :all,
          editable_by: :all
end
```

### User Model (with roles)

```ruby
class User < ApplicationRecord
  # Simple roles array
  def roles
    @roles ||= (self[:roles] || []).map(&:to_sym)
  end

  def has_role?(role)
    roles.include?(role.to_sym)
  end
end
```

### Pundit Policy

```ruby
class AccountPolicy < ApplicationPolicy
  def permitted_attributes
    # Start with base attributes
    attrs = [:name, :description]

    # Add settings using Roles module API
    user.roles.each do |role|
      attrs.concat(Account.settings_editable_by(role))
    end

    attrs.uniq
  end

  # Optional: Get visible settings for form
  def visible_settings
    setting_names = []

    user.roles.each do |role|
      setting_names.concat(Account.settings_viewable_by(role))
    end

    # Return Setting objects
    setting_names.uniq.map { |name| Account.find_setting(name) }.compact
  end

  # Helper: Check if setting is editable by current user
  def can_edit_setting?(setting_name)
    user.roles.any? do |role|
      record.class.settings_editable_by(role).include?(setting_name.to_sym)
    end
  end
end
```

### Controller

```ruby
class AccountsController < ApplicationController
  def edit
    @account = Account.find(params[:id])
    authorize @account

    # Get visible settings for form
    @visible_settings = policy(@account).visible_settings
  end

  def update
    @account = Account.find(params[:id])
    authorize @account

    if @account.update(permitted_attributes(@account))
      redirect_to @account, notice: 'Account updated'
    else
      render :edit
    end
  end
end
```

### View (ERB)

```erb
<%= form_with model: @account do |f| %>
  <%= f.text_field :name %>
  <%= f.text_area :description %>

  <h3>Settings</h3>

  <% @visible_settings.each do |setting| %>
    <div class="field">
      <%= f.label setting.name %>

      <% if policy(@account).can_edit_setting?(setting.name) %>
        <%= f.check_box setting.name %>
      <% else %>
        <%= @account.public_send(setting.name) %> (read-only)
      <% end>
    </div>
  <% end %>

  <%= f.submit %>
<% end %>
```

---

## Testing

### Policy Specs (Pundit)

```ruby
RSpec.describe AccountPolicy do
  let(:account) { Account.create! }

  describe "#permitted_attributes" do
    context "when user is admin" do
      let(:admin) { User.create!(roles: [:admin]) }
      subject(:policy) { described_class.new(admin, account) }

      it "permits all admin-editable settings" do
        permitted = policy.permitted_attributes

        expect(permitted).to include(
          :billing_enabled,
          :max_users,
          :invoice_frequency,
          :company_name,
          :timezone
        )
      end
    end

    context "when user is finance" do
      let(:finance) { User.create!(roles: [:finance]) }
      subject(:policy) { described_class.new(finance, account) }

      it "permits finance settings" do
        permitted = policy.permitted_attributes

        expect(permitted).to include(:invoice_frequency)
      end

      it "does NOT permit admin-only settings" do
        permitted = policy.permitted_attributes

        expect(permitted).not_to include(:billing_enabled, :max_users)
      end
    end

    context "when user has no special roles" do
      let(:regular_user) { User.create!(roles: []) }
      subject(:policy) { described_class.new(regular_user, account) }

      it "only permits :all editable settings" do
        permitted = policy.permitted_attributes

        expect(permitted).to include(:timezone)
        expect(permitted).not_to include(:billing_enabled, :invoice_frequency)
      end
    end
  end

  describe "#visible_settings" do
    context "when user is owner" do
      let(:owner) { User.create!(roles: [:owner]) }
      subject(:policy) { described_class.new(owner, account) }

      it "includes settings visible to owner" do
        visible = policy.visible_settings.map(&:name)

        expect(visible).to include(
          :max_users,
          :invoice_frequency,
          :company_name,
          :timezone
        )
      end
    end
  end
end
```

### Controller Request Specs

```ruby
RSpec.describe "Accounts", type: :request do
  let(:account) { Account.create!(company_name: "Test Corp") }

  describe "PATCH /accounts/:id" do
    context "when user is admin" do
      let(:admin) { User.create!(roles: [:admin]) }
      before { sign_in admin }

      it "allows updating billing_enabled" do
        patch account_path(account), params: {
          account: { billing_enabled: true }
        }

        expect(account.reload.billing_enabled).to be true
      end
    end

    context "when user is finance" do
      let(:finance) { User.create!(roles: [:finance]) }
      before { sign_in finance }

      it "allows updating invoice_frequency" do
        patch account_path(account), params: {
          account: { invoice_frequency: 'quarterly' }
        }

        expect(account.reload.invoice_frequency).to eq('quarterly')
      end

      it "does NOT allow updating billing_enabled" do
        patch account_path(account), params: {
          account: { billing_enabled: true }
        }

        # Unpermitted parameter rejected by strong parameters
        expect(account.reload.billing_enabled).to be false
      end
    end
  end
end
```

---

## Advanced: Helper Methods

Extract common role-checking logic into a helper module:

```ruby
# app/policies/concerns/settings_role_filter.rb
module SettingsRoleFilter
  def permitted_settings_for_roles(model_class, user_roles)
    setting_names = []

    user_roles.each do |role|
      setting_names.concat(model_class.settings_editable_by(role))
    end

    setting_names.uniq
  end

  def visible_settings_for_roles(model_class, user_roles)
    setting_names = []

    user_roles.each do |role|
      setting_names.concat(model_class.settings_viewable_by(role))
    end

    # Return Setting objects
    setting_names.uniq.map { |name| model_class.find_setting(name) }.compact
  end
end
```

### Using the Helper

```ruby
class AccountPolicy < ApplicationPolicy
  include SettingsRoleFilter

  def permitted_attributes
    attrs = [:name, :description]
    attrs.concat(permitted_settings_for_roles(Account, user.roles))
    attrs
  end

  def visible_settings
    visible_settings_for_roles(Account, user.roles)
  end
end
```

**Note:** This helper is optional - the inline approach is already simple enough with the Roles module API.

---

## Comparison: Roles vs Policy-Based Modules

| Aspect | Roles Module + Policy (This Guide) | Policy-Based Module (`authorize_with`) |
|--------|-----------------------------------|----------------------------------------|
| **Setup Complexity** | ✅ Simple - just roles | ⚠️ More complex - methods per setting |
| **Authorization Logic** | ✅ In policy only | ⚠️ Split between model and policy |
| **Flexibility** | ⚠️ Role-based only | ✅ Custom logic per setting |
| **Metadata** | `viewable_by`, `editable_by` | `authorize_with: :method_name` |
| **Use Case** | Simple role-based access | Complex authorization rules |
| **Policy Code** | Reads role metadata | Calls authorization methods |

**Rule of Thumb:**
- **Use Roles + Policy (this guide)** when: Role names are sufficient (`[:admin, :finance]`)
- **Use Policy-Based Module** when: Need custom logic (`user.admin? && record.enabled?`)

---

## Related Documentation

- **[Roles Module](../modules/roles.md)** - Full Roles module documentation
- **[Policy-Based Authorization](../modules/policy_based/README.md)** - Alternative approach with `authorize_with`
- **[Pundit Module](../modules/policy_based/pundit.md)** - Using Pundit module with `authorize_with`
- **[ActionPolicy Module](../modules/policy_based/action_policy.md)** - Using ActionPolicy module with `authorize_with`

---

## Summary

**This approach combines:**
- ✅ Simple role metadata from Roles module (`viewable_by`, `editable_by`)
- ✅ Powerful policy filtering from Pundit/ActionPolicy
- ✅ No module conflicts (only Roles module included)
- ✅ Authorization logic in ONE place (policy)

**Perfect for:**
- Apps already using Pundit or ActionPolicy
- Simple role-based authorization
- Avoiding `authorize_with` complexity
- Centralized authorization in policies
