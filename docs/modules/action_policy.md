# ActionPolicy Module

Integrate ModelSettings with ActionPolicy for rule-based authorization.

## Installation

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL
  include ModelSettings::Modules::ActionPolicy

  setting :billing_override, authorize_with: :manage_billing?
  setting :api_access, authorize_with: :admin?
end
```

## Policy Integration

```ruby
class UserPolicy < ApplicationPolicy
  def manage_billing?
    user.admin? || user.finance?
  end

  def permitted_settings
    record.class._authorized_settings.select { |_, method| public_send(method) }.keys
  end
end
```

## Controller Usage

```ruby
class UsersController < ApplicationController
  def update
    @user = User.find(params[:id])
    authorize! @user
    
    policy = authorized(@user)
    allowed = policy.permitted_settings
    permitted_params = params.require(:user).permit(*allowed)
    @user.update(permitted_params)
  end
end
```

See full README for complete examples and params_filter integration.
