# Roles Module

Role-based access control (RBAC) for settings without requiring Pundit or ActionPolicy.

## Installation

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL
  include ModelSettings::Modules::Roles

  setting :billing_override,
          type: :column,
          viewable_by: [:admin, :finance, :manager],
          editable_by: [:admin, :finance]
end
```

## Options

- `viewable_by: [:role1, :role2]` - Roles that can view this setting
- `editable_by: [:role1, :role2]` - Roles that can edit this setting
- `viewable_by: :all` - Anyone can view

## Class Methods

```ruby
User.settings_viewable_by(:finance)   # Settings finance can view
User.settings_editable_by(:admin)     # Settings admin can edit
```

## Instance Methods

```ruby
user.can_view_setting?(:billing_override, :finance)  # => true
user.can_edit_setting?(:billing_override, :manager)  # => false
```

## Controller Integration

```ruby
class UsersController < ApplicationController
  def update
    @user = User.find(params[:id])
    editable = User.settings_editable_by(current_user.role)
    permitted = params.require(:user).permit(*editable)
    @user.update(permitted)
  end
end
```

See full README for complete examples and nested settings with role inheritance.

## See Also

- [Module Development Guide](../guides/module_development.md) - Learn how to create custom modules like Roles
- [ModuleRegistry API Reference](../api/module_registry.md) - Complete API documentation
- [Custom Module Example](../../examples/custom_module/) - Working example of a custom module
- [Configuration Guide](../core/configuration.md) - Global configuration options
