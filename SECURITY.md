# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 0.9.x   | :white_check_mark: |
| 0.8.x   | :white_check_mark: |
| 0.7.x   | :x: (use 0.8+)     |
| < 0.7   | :x:                |

## Security Model

ModelSettings follows a **defense-in-depth** approach with multiple security layers:

1. **Controller Layer** - Primary authorization point (Strong Parameters)
2. **Model Layer** - Optional authorization via Pundit/ActionPolicy/Roles modules
3. **Database Layer** - SQL injection protection via Arel/ActiveRecord

## Reported Security Findings

### ✅ PASS: SQL Injection Protection

**Status**: No vulnerabilities found

**Analysis**:
- All database queries use safe ActiveRecord/Arel APIs
- Metadata queries operate on Ruby objects, not SQL
- JSON adapter uses `Arel::Nodes::Quoted` for parameter binding
- No dynamic SQL construction detected

**Example of safe query** (`lib/model_settings/deprecation_auditor.rb:160`):
```ruby
# PostgreSQL JSONB query - safely parameterized
model_class.where(
  Arel::Nodes::InfixOperation.new("?", column, Arel::Nodes::Quoted.new(json_key.to_s))
).count
```

### ✅ PASS: Mass Assignment Protection

**Status**: Correctly delegates to Strong Parameters

**Analysis**:
- ModelSettings does NOT handle parameter filtering directly
- Applications MUST use Strong Parameters in controllers
- `permitted_settings` helper documented for Pundit/ActionPolicy

**Secure controller pattern**:
```ruby
class UsersController < ApplicationController
  def update
    @user = User.find(params[:id])
    authorize @user

    # Get allowed settings from policy
    allowed_settings = policy(@user).permitted_settings

    # Filter params using Strong Parameters
    permitted_params = params.require(:user).permit(*allowed_settings)
    @user.update(permitted_params)
  end
end
```

### ⚠️ IMPORTANT: Authorization Bypass via Helper Methods

**Status**: BY DESIGN - Requires controller-level protection

**Finding**:
Helper methods (`enable!`, `disable!`, `toggle!`) and direct attribute assignment **DO NOT** enforce authorization checks. Authorization must be enforced at the controller layer.

**Example of vulnerability**:
```ruby
# In controller WITHOUT authorization
def toggle_billing
  @user = User.find(params[:id])
  @user.billing_enabled_toggle!  # ❌ NO authorization check!
  @user.save!
end
```

**Secure pattern**:
```ruby
# ✅ CORRECT: Authorize before action
def toggle_billing
  @user = User.find(params[:id])
  authorize @user, :manage_billing?  # Pundit check

  @user.billing_enabled_toggle!
  @user.save!
end
```

**Rationale**: Model-level authorization is optional. Primary security boundary is the controller using Strong Parameters and policy checks.

### ⚠️ IMPORTANT: Cascades and Syncs Bypass Authorization

**Status**: BY DESIGN - Internal operations

**Finding**:
When a setting change triggers cascades or syncs, child settings are modified **WITHOUT** authorization checks.

**Example**:
```ruby
setting :premium, cascade: {enable: true} do
  setting :api_access    # Will be enabled automatically
  setting :priority_support  # Will be enabled automatically
end

# User changes premium
user.premium = true
user.save!
# ⚠️ api_access and priority_support are enabled WITHOUT separate authorization
```

**Security implications**:
- If user can modify parent setting, they can indirectly modify children
- Cascades should NOT cross security boundaries
- Authorization should be checked on the **parent** setting only

**Best practice**:
```ruby
# ✅ GOOD: Cascade within same security domain
setting :notifications, authorize_with: :manage_notifications? do
  setting :email_notifications
  setting :sms_notifications
  setting :push_notifications
end

# ❌ BAD: Cascade across security domains
setting :user_preferences do  # Any user can edit
  setting :billing_enabled, cascade: {enable: true} do  # ❌ Allows privilege escalation!
    setting :admin_features  # Admin-only setting!
  end
end
```

### ✅ PASS: No Direct Column Access Bypass

**Status**: Column accessors follow Rails conventions

**Analysis**:
- Setting accessors use `public_send` which respects `attr_accessible` (Rails 3) or Strong Parameters (Rails 4+)
- No backdoor methods that bypass ActiveRecord
- Dirty tracking uses native Rails mechanisms

## Security Best Practices

### 1. Always Use Authorization at Controller Level

```ruby
class UsersController < ApplicationController
  before_action :authenticate_user!

  def update
    @user = User.find(params[:id])

    # ✅ REQUIRED: Authorize the action
    authorize @user

    # ✅ REQUIRED: Filter parameters
    allowed = policy(@user).permitted_settings
    permitted = params.require(:user).permit(*allowed)

    @user.update(permitted)
  end
end
```

### 2. Never Trust User Input

```ruby
# ❌ INSECURE: Direct mass assignment
def update
  @user = User.find(params[:id])
  @user.update(params[:user])  # ❌ Mass assignment vulnerability!
end

# ✅ SECURE: Use Strong Parameters
def update
  @user = User.find(params[:id])
  @user.update(user_params)
end

private

def user_params
  params.require(:user).permit(:notifications_enabled, :theme)
end
```

### 3. Validate Cascade Security Boundaries

Before using cascades, ensure all cascaded settings share the same authorization requirements:

```ruby
# ✅ SAFE: All settings have same authorization
setting :premium,
        authorize_with: :admin?,
        cascade: {enable: true} do
  setting :api_access, authorize_with: :admin?
  setting :priority_support, authorize_with: :admin?
end

# ❌ UNSAFE: Mixed authorization levels
setting :premium,
        authorize_with: :user?,  # Any user can modify
        cascade: {enable: true} do
  setting :admin_panel, authorize_with: :admin?  # ❌ Privilege escalation!
end
```

### 4. Use Authorization Modules

Include one of the authorization modules:

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL
  include ModelSettings::Modules::Pundit  # or ActionPolicy or Roles

  setting :billing_enabled, authorize_with: :manage_billing?
end
```

Then enforce in controller:
```ruby
class UsersController < ApplicationController
  def update
    authorize @user
    # ... Strong Parameters ...
  end
end
```

### 5. Audit Deprecated Settings

Regularly audit deprecated settings to prevent security issues from stale code:

```bash
# In CI pipeline
bundle exec rake settings:audit:deprecated
# Exit code 1 if deprecated settings are in use
```

### 6. Review Callback Security

Callbacks can execute arbitrary code. Ensure callbacks don't:
- Bypass authorization
- Expose sensitive data
- Modify unrelated settings

```ruby
# ⚠️ REVIEW CAREFULLY
setting :premium,
        after_enable: -> { user.grant_admin_access! } do  # ❌ Potential privilege escalation
  # ...
end
```

## Reporting a Vulnerability

**DO NOT** open a public issue for security vulnerabilities.

Please report security vulnerabilities by email to the project maintainers.

Include:
1. Description of the vulnerability
2. Steps to reproduce
3. Potential impact
4. Suggested fix (if any)

We will respond within 48 hours and provide a fix timeline.

## Security Checklist for Applications

- [ ] Strong Parameters used in all controllers
- [ ] Authorization checks before setting modifications
- [ ] Cascades reviewed for security boundary violations
- [ ] Callbacks reviewed for privilege escalation
- [ ] Deprecated settings audited in CI
- [ ] HTTPS enforced in production
- [ ] Database credentials secured
- [ ] Regular dependency updates

## Known Limitations

1. **No model-level authorization enforcement** - Authorization is opt-in via modules
2. **Cascades/syncs bypass authorization** - By design for internal consistency
3. **Helper methods don't check permissions** - Controller must authorize first
4. **No field-level encryption** - Use Rails encrypted attributes if needed

## Security Updates

Security patches will be released as:
- **Patch versions** for security fixes (e.g., 0.9.1)
- **Minor versions** for security features (e.g., 0.10.0)

Subscribe to releases on GitHub to receive security notifications.

## License

This security policy is part of the ModelSettings project and follows the same MIT license.
