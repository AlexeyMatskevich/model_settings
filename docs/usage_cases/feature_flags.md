# Feature Flags

Use ModelSettings to implement feature flags for gradual rollouts and A/B testing.

## Basic Feature Flags

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  setting :beta_features, type: :column, default: false
  setting :new_dashboard, type: :column, default: false
  setting :advanced_search, type: :column, default: false
end

# Controller
if current_user.beta_features_enabled?
  render :beta_version
else
  render :stable_version
end
```

## Hierarchical Features

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  setting :beta_program, type: :column, cascade: {enable: true} do
    setting :new_ui, type: :column, default: false
    setting :experimental_api, type: :column, default: false
  end
end

# Enable all beta features at once
user.beta_program_enable!
```

## Per-Organization Features

```ruby
class Organization < ApplicationRecord
  include ModelSettings::DSL

  setting :features, type: :json, storage: {column: :feature_flags} do
    setting :sso, default: false
    setting :audit_logs, default: false
    setting :api_v2, default: false
  end
end

# Check in code
if current_organization.sso_enabled?
  redirect_to sso_login_path
end
```

## Gradual Rollout Pattern

```ruby
# Roll out to percentage of users
class User < ApplicationRecord
  setting :new_feature, type: :column, default: false

  def enable_for_percentage!(percentage)
    return if new_feature
    self.new_feature = (id % 100) < percentage
    save!
  end
end

# Enable for 10% of users
User.find_each { |u| u.enable_for_percentage!(10) }
```
