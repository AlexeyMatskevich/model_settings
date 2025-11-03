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

## Authorization Inheritance

Child settings can inherit authorization from their parent settings using a 5-level priority system.

### Explicit `:inherit` Keyword

```ruby
setting :billing, viewable_by: [:admin, :finance], editable_by: [:admin] do
  setting :invoices, viewable_by: :inherit, editable_by: :inherit
end

# invoices inherits: viewable_by [:admin, :finance], editable_by [:admin]
```

### Setting-Level `inherit_authorization` Option

```ruby
setting :billing, viewable_by: [:admin, :finance], editable_by: [:admin] do
  setting :invoices, inherit_authorization: true  # Inherits both viewable_by and editable_by
  setting :reports, inherit_authorization: :view_only  # Inherits only viewable_by
  setting :exports, inherit_authorization: :edit_only  # Inherits only editable_by
  setting :archive, inherit_authorization: false  # No inheritance
end
```

### Model-Level Configuration

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL
  include ModelSettings::Modules::Roles

  settings_config inherit_authorization: true  # All nested settings inherit by default

  setting :billing, viewable_by: [:admin] do
    setting :invoices    # Automatically inherits viewable_by: [:admin]
    setting :reports     # Automatically inherits viewable_by: [:admin]
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

1. **Explicit setting value** - `viewable_by: [:admin]`
2. **Explicit `:inherit` keyword** - `viewable_by: :inherit`
3. **Setting `inherit_authorization` option** - `inherit_authorization: true`
4. **Model `settings_config`** - `settings_config inherit_authorization: true`
5. **Global configuration** - `ModelSettings.configuration.inherit_authorization`

### Partial Inheritance Examples

**Inherit view permissions only:**
```ruby
setting :billing, viewable_by: [:admin, :finance], editable_by: [:admin] do
  setting :reports, inherit_authorization: :view_only
  # Result: viewable_by [:admin, :finance], editable_by nil (unrestricted)
end
```

**Inherit edit permissions only:**
```ruby
setting :billing, viewable_by: [:admin], editable_by: [:admin, :finance] do
  setting :exports, inherit_authorization: :edit_only
  # Result: viewable_by nil (unrestricted), editable_by [:admin, :finance]
end
```

### Query Method Semantics

Query methods return settings with **explicit authorization** (not unrestricted settings):

```ruby
setting :parent, viewable_by: [:admin] do
  setting :child, inherit_authorization: false  # No authorization (nil)
end

User.settings_viewable_by(:guest)  # => [] (child not included, has nil authorization)
user.can_view_setting?(:child, :guest)  # => true (nil = unrestricted access)
```

- `nil` authorization = unrestricted (accessible by all) but NOT in query results
- `:all` authorization = explicitly viewable/editable by all AND in query results

## See Also

- [Module Development Guide](../guides/module_development.md) - Learn how to create custom modules like Roles
- [ModuleRegistry API Reference](../core/module_registry.md) - Complete API documentation
- [Custom Module Example](../../examples/custom_module/) - Working example of a custom module
- [Configuration Guide](../core/configuration.md) - Global configuration options
