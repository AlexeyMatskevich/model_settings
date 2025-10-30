# Multi-Tenancy Configuration

Manage organization/tenant-level settings with ModelSettings.

## Organization Settings

```ruby
class Organization < ApplicationRecord
  include ModelSettings::DSL

  setting :billing, type: :json, storage: {column: :config_data} do
    setting :plan, default: "free"
    setting :invoicing_enabled, default: false
    setting :auto_payment, default: false
  end

  setting :features, type: :json, storage: {column: :config_data} do
    setting :sso, default: false
    setting :audit_logs, default: false
    setting :api_access, default: false
  end
end

# Migration
add_column :organizations, :config_data, :jsonb, default: {}, null: false
```

## Cascading Features to Users

```ruby
# Users inherit from organization
class User < ApplicationRecord
  belongs_to :organization

  def sso_enabled?
    organization.sso_enabled?
  end

  def api_access?
    organization.api_access_enabled?
  end
end

# Controller check
if current_user.sso_enabled?
  redirect_to sso_login_path
end
```

## Plan-Based Features

```ruby
class Organization < ApplicationRecord
  setting :enterprise_plan, type: :column, cascade: {enable: true} do
    setting :priority_support, type: :column, default: false
    setting :custom_branding, type: :column, default: false
    setting :advanced_analytics, type: :column, default: false
  end
end

# Upgrade to enterprise
org.enterprise_plan_enable!  # Enables all enterprise features
```
