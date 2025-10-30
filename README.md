# ModelSettings

Declarative configuration management DSL for Rails models with support for multiple storage backends, authorization, validation, and extensible module integration.

## Features

- **Multiple Storage Backends**: Column, JSON/JSONB, and StoreModel support
- **Flexible DSL**: Clean, declarative syntax for defining settings
- **Authorization**: Built-in Roles (RBAC), Pundit, and ActionPolicy modules for flexible authorization
- **Dependency Management**: Cascades, syncs, and automatic propagation with cycle detection
- **Validation Framework**: Custom validators with lifecycle hooks
- **Callback System**: Before/after callbacks for state changes
- **Dirty Tracking**: Full change tracking across all storage types
- **Query Interface**: Powerful methods for finding settings by metadata
- **Deprecation Tracking**: Built-in deprecation warnings and audit trails
- **I18n Support**: Full internationalization for labels and descriptions
- **Module System**: Extensible architecture for custom modules with exclusive groups
- **Mixed Storage**: Support for complex parent-child relationships across storage types

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'model_settings'
```

And then execute:

```bash
bundle install
```

## Quick Start

### Basic Column Storage

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  # Simple boolean setting stored in a database column
  setting :notifications_enabled, type: :column, default: true
end

# Usage
user = User.create!
user.notifications_enabled # => true
user.notifications_enabled = false
user.save!

# Helper methods
user.notifications_enabled_enable!   # Set to true
user.notifications_enabled_disable!  # Set to false
user.notifications_enabled_toggle!   # Toggle value
user.notifications_enabled_enabled?  # => false
user.notifications_enabled_disabled? # => true

# Dirty tracking
user.notifications_enabled = true
user.notifications_enabled_changed? # => true
user.notifications_enabled_was      # => false
user.notifications_enabled_change   # => [false, true]
```

### JSON Storage

Store multiple settings in a single JSONB column:

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  # Multiple settings in one JSON column
  setting :features, type: :json, storage: {column: :settings} do
    setting :billing_enabled, default: false
    setting :speech_recognition, default: false
    setting :api_access, default: false
  end
end

# Usage
user = User.create!
user.billing_enabled = true
user.speech_recognition = true
user.save!

# All helper methods work with JSON storage too
user.billing_enabled_enable!
user.api_access_toggle!
```

### JSON Arrays

Store array values in JSON columns:

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  setting :allowed_ips,
          type: :json,
          storage: {column: :security_settings},
          array: true,
          default: []

  setting :tags,
          type: :json,
          storage: {column: :metadata},
          array: true
end

# Usage
user = User.create!
user.allowed_ips = ["192.168.1.1", "10.0.0.1"]
user.tags = ["premium", "verified"]
user.save!

# Array operations
user.allowed_ips << "172.16.0.1"
user.allowed_ips_changed? # => true
```

### StoreModel Storage

Use StoreModel for complex nested settings with type casting and validation:

```ruby
# Define StoreModel class
class AiSettings
  include StoreModel::Model

  attribute :transcription, :boolean, default: false
  attribute :sentiment, :boolean, default: false
  attribute :rate_limit, :integer, default: 100
end

class Callcenter < ApplicationRecord
  include ModelSettings::DSL

  # Register StoreModel attribute
  attribute :ai_settings, AiSettings.to_type

  setting :transcription,
          type: :store_model,
          storage: {column: :ai_settings}

  setting :sentiment,
          type: :store_model,
          storage: {column: :ai_settings}
end

# Usage
callcenter = Callcenter.create!(ai_settings: AiSettings.new)
callcenter.transcription = true
callcenter.transcription_changed? # => true (via StoreModel)
callcenter.save!
```

### Migration Example

```ruby
class AddSettingsToUsers < ActiveRecord::Migration[7.0]
  def change
    # For column storage
    add_column :users, :notifications_enabled, :boolean, default: false, null: false
    add_column :users, :premium_mode, :boolean, default: false, null: false

    # For JSON hash storage
    add_column :users, :settings, :jsonb, default: {}, null: false
    add_index :users, :settings, using: :gin

    # For JSON array storage
    add_column :users, :security_settings, :jsonb, default: {}, null: false
    add_column :users, :metadata, :jsonb, default: {}, null: false

    # For StoreModel storage
    add_column :users, :ai_settings, :jsonb, default: {}, null: false
    add_column :users, :premium_features, :jsonb, default: {}, null: false
  end
end
```

## Advanced Features

### Validation

#### Built-in Boolean Validation

ModelSettings automatically validates that all boolean settings receive only `true` or `false` values. This strict validation prevents common bugs from Rails' permissive type coercion:

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  setting :premium_mode, type: :column
  setting :notifications, type: :json, storage: {column: :settings_data}
end

user = User.new

# Valid: true/false values
user.premium_mode = true   # ✓ Valid
user.premium_mode = false  # ✓ Valid
user.premium_mode = nil    # ✓ Valid (settings are optional by default)

# Invalid: non-boolean values are rejected
user.premium_mode = "true"      # ✗ Invalid - strings not allowed
user.premium_mode = 1           # ✗ Invalid - integers not allowed
user.premium_mode = "yes"       # ✗ Invalid - no type coercion
user.valid? # => false
user.errors[:premium_mode] # => ["must be true or false (got: \"true\")"]
```

**Why Strict Validation?**

Rails' default boolean type casting converts strings (`"1"`, `"true"`, `"yes"`) and integers (`1`, `0`) to booleans. This permissive behavior can lead to unexpected bugs when settings are manipulated programmatically. ModelSettings enforces strict boolean values across all storage adapters (Column, JSON, StoreModel) to ensure data integrity.

**Note:** Validation is automatically applied to all leaf settings (settings without nested children). Parent container settings and array-type settings are excluded from boolean validation.

#### Custom Validators

Add custom validators to settings:

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  setting :premium_mode,
          type: :column,
          validate_with: :check_subscription_active

  setting :api_access,
          type: :column,
          validate_with: [:check_api_quota, :check_api_permissions]

  private

  def check_subscription_active
    unless subscription_active?
      add_setting_error(:premium_mode, "requires active subscription")
    end
  end

  def check_api_quota
    if api_calls_this_month >= api_quota
      add_setting_error(:api_access, "API quota exceeded")
    end
  end
end

# Usage
user = User.new
user.validate_setting(:premium_mode) # => false
user.setting_errors_for(:premium_mode) # => ["Premium mode requires active subscription"]
```

### Callbacks

Execute code before/after setting changes:

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  setting :premium_mode,
          type: :column,
          before_enable: :prepare_premium_features,
          after_enable: :notify_premium_activation,
          after_disable: :cleanup_premium_features,
          after_change_commit: :sync_to_external_service

  private

  def prepare_premium_features
    # Run before enabling premium mode
    logger.info "Preparing premium features..."
  end

  def notify_premium_activation
    # Run after enabling premium mode
    PremiumActivationMailer.notify(self).deliver_later
  end

  def cleanup_premium_features
    # Run after disabling premium mode
    PremiumFeature.cleanup_for_user(self)
  end

  def sync_to_external_service
    # Run after database commit
    ExternalApiJob.perform_later(self.id)
  end
end

# Usage
user.premium_mode_enable!
# => Executes: prepare_premium_features → set value → notify_premium_activation
# => After commit: sync_to_external_service
```

### Metadata and Queries

Add metadata to settings for organization and querying:

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  setting :billing_enabled,
          type: :json,
          storage: {column: :settings},
          metadata: {
            category: "billing",
            tier: "premium",
            requires_verification: true
          }

  setting :api_access,
          type: :json,
          storage: {column: :settings},
          metadata: {
            category: "api",
            tier: "enterprise",
            rate_limit: 1000
          }
end

# Query by metadata
User.settings_where(metadata: {category: "billing"})
User.settings_where(metadata: {tier: "premium"})

# Query by metadata key
User.settings_with_metadata_key(:rate_limit)

# Query by type
User.settings_by_type(:json)

# Query with callbacks
User.settings_with_callbacks(:after_enable)

# Group by metadata
User.settings_grouped_by_metadata(:category)
# => {"billing" => [...], "api" => [...]}

# Custom queries
User.settings_matching { |s| s.name.to_s.include?("api") }

# Count settings
User.settings_count(type: :json)
User.settings_count(metadata: {tier: "premium"})
```

### Deprecation Tracking

Mark settings as deprecated with automatic warnings:

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  setting :old_notification_system,
          type: :column,
          deprecated: "Use notifications_enabled instead",
          metadata: {
            deprecated_since: "2.0.0",
            replacement: :notifications_enabled
          }

  setting :notifications_enabled,
          type: :column,
          default: true
end

# Get deprecated settings
User.deprecated_settings

# Check if setting is deprecated
User.setting_deprecated?(:old_notification_system) # => true
User.deprecation_reason_for(:old_notification_system)
# => "Use notifications_enabled instead"

# Generate deprecation report
User.deprecation_report
# => {
#      total_count: 1,
#      settings: [{name: :old_notification_system, reason: "...", since: "2.0.0"}],
#      by_version: {"2.0.0" => [...]}
#    }

# Automatic warnings when deprecated settings are used
user = User.create!(old_notification_system: true)
# => DEPRECATION WARNING: Setting 'old_notification_system' is deprecated since version 2.0.0.
#    Use notifications_enabled instead. Please use 'notifications_enabled' instead.
```

### Internationalization

Support for I18n with automatic key lookup:

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  setting :notifications_enabled,
          type: :column,
          i18n: {
            label_key: "settings.notifications.label",
            description_key: "settings.notifications.description"
          }
end

# In config/locales/en.yml:
# en:
#   model_settings:
#     user:
#       notifications_enabled:
#         label: "Enable Notifications"
#         description: "Receive email notifications for important updates"
#         help: "You can change this setting at any time"

# Usage
user = User.new
user.t_label_for(:notifications_enabled)       # => "Enable Notifications"
user.t_description_for(:notifications_enabled) # => "Receive email notifications..."
user.t_help_for(:notifications_enabled)        # => "You can change this setting..."

# Get all translations at once
user.translations_for(:notifications_enabled)
# => {label: "...", description: "...", help: "..."}
```

### Authorization with Roles Module

ModelSettings provides simple role-based access control (RBAC) through the built-in Roles Module. This allows you to control who can view or edit specific settings without requiring a full authorization framework like Pundit or ActionPolicy.

**Important:** Authorization modules (Roles, Pundit, ActionPolicy) are mutually exclusive. You can only use ONE authorization module at a time per model.

#### Basic Role-Based Authorization

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL
  include ModelSettings::Modules::Roles

  # Define settings with role restrictions
  setting :billing_override,
          type: :column,
          viewable_by: [:admin, :finance, :manager],
          editable_by: [:admin, :finance]

  setting :api_access,
          type: :column,
          viewable_by: [:admin],
          editable_by: [:admin]

  setting :display_name,
          type: :column,
          viewable_by: :all,              # Anyone can view
          editable_by: [:admin, :user]    # Only admin and user can edit

  setting :notifications,
          type: :column
          # No restrictions = anyone can view/edit
end

# Check permissions
user = User.create!
user.can_view_setting?(:billing_override, :finance)  # => true
user.can_view_setting?(:billing_override, :guest)    # => false
user.can_edit_setting?(:billing_override, :admin)    # => true
user.can_edit_setting?(:billing_override, :manager)  # => false

# Get all settings viewable/editable by a role
User.settings_viewable_by(:finance)
# => [:billing_override, :display_name]

User.settings_editable_by(:finance)
# => [:billing_override]
```

#### Controller Integration

Use role-based filtering to protect settings in your controllers:

```ruby
class UsersController < ApplicationController
  def update
    @user = User.find(params[:id])

    # Get editable settings for current user's role
    editable_settings = User.settings_editable_by(current_user.role)

    # Filter params to only allow editable settings
    permitted_params = params.require(:user).permit(*editable_settings)

    if @user.update(permitted_params)
      redirect_to @user
    else
      render :edit
    end
  end
end
```

#### Role Inheritance with Nested Settings

Roles are inherited by child settings:

```ruby
class Organization < ApplicationRecord
  include ModelSettings::DSL
  include ModelSettings::Modules::Roles

  setting :billing,
          type: :json,
          storage: {column: :settings},
          viewable_by: [:admin, :finance],
          editable_by: [:admin] do
    # Children inherit parent's roles automatically
    setting :invoices, default: false
    setting :payments, default: false
    setting :subscriptions, default: false
  end
end

# All children inherit parent's role restrictions
org = Organization.create!
org.can_view_setting?(:invoices, :finance)  # => true (inherited)
org.can_edit_setting?(:invoices, :finance)  # => false (inherited)
```

#### Special Values

- **`:all`** - Setting is viewable by anyone (use for public settings)
- **`nil` or omitted** - No restrictions (anyone can view/edit)
- **Array of symbols** - Specific roles allowed (e.g., `[:admin, :finance]`)

#### Authorization Options

```ruby
setting :setting_name,
        viewable_by: :all,              # Symbol - anyone can view
        editable_by: [:admin, :finance] # Array - only these roles can edit

setting :other_setting,
        viewable_by: [:admin, :manager], # Array - only these roles
        editable_by: :admin              # Symbol - single role (converted to array)
```

#### View Layer Integration

```erb
<!-- In your views -->
<% if @user.can_view_setting?(:billing_override, current_user.role) %>
  <div class="setting">
    <%= @user.billing_override %>

    <% if @user.can_edit_setting?(:billing_override, current_user.role) %>
      <%= link_to "Edit", edit_setting_path(:billing_override) %>
    <% end %>
  </div>
<% end %>

<!-- Generate settings form with role-based filtering -->
<%= form_for @user do |f| %>
  <% User.settings_editable_by(current_user.role).each do |setting_name| %>
    <%= f.check_box setting_name %>
    <%= f.label setting_name %>
  <% end %>
<% end %>
```

#### Exclusive Authorization Groups

You cannot mix authorization modules:

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL
  include ModelSettings::Modules::Roles
  include PunditModule  # ❌ Raises ExclusiveGroupConflictError!
end
# => Cannot include pundit module: conflicts with :roles module
#    (both are in :authorization exclusive group)
```

This prevents conflicting authorization strategies and ensures consistent behavior.

### Authorization with Pundit Module

For applications using [Pundit](https://github.com/varvet/pundit) for authorization, ModelSettings provides seamless integration through the Pundit Module. This allows you to leverage your existing Pundit policies to control access to settings.

**Important:** Authorization modules (Roles, Pundit, ActionPolicy) are mutually exclusive. You can only use ONE authorization module at a time per model.

#### Basic Pundit Integration

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL
  include ModelSettings::Modules::Pundit

  # Use policy methods for authorization
  setting :billing_override,
          type: :column,
          authorize_with: :manage_billing?

  setting :api_access,
          type: :column,
          authorize_with: :admin?

  setting :system_config,
          type: :column,
          authorize_with: :admin?

  setting :display_name,
          type: :column
          # No authorization = unrestricted
end

# In your UserPolicy
class UserPolicy < ApplicationPolicy
  def manage_billing?
    user.admin? || user.finance?
  end

  def admin?
    user.admin?
  end

  # Helper method to get permitted settings
  def permitted_settings
    record.class._authorized_settings.select do |_name, method|
      send(method)
    end.keys
  end
end
```

#### Controller Integration with Pundit

```ruby
class UsersController < ApplicationController
  def update
    @user = User.find(params[:id])
    authorize @user

    # Get settings allowed by policy
    policy = policy(@user)
    allowed_settings = policy.permitted_settings

    # Filter params to only include allowed settings
    permitted_params = params.require(:user).permit(*allowed_settings)

    if @user.update(permitted_params)
      redirect_to @user
    else
      render :edit
    end
  end
end
```

#### Querying Authorization Metadata

```ruby
# Get the policy method for a setting
User.authorization_for_setting(:billing_override)
# => :manage_billing?

# Get all settings requiring a specific permission
User.settings_requiring(:admin?)
# => [:api_access, :system_config]

# Get all settings with authorization
User.authorized_settings
# => [:billing_override, :api_access, :system_config]
```

#### View Layer with Pundit

```erb
<!-- In your views -->
<% policy = policy(@user) %>
<% policy.permitted_settings.each do |setting_name| %>
  <div class="setting">
    <%= f.check_box setting_name %>
    <%= f.label setting_name %>
  </div>
<% end %>

<!-- Check specific permission -->
<% if policy.manage_billing? %>
  <%= f.check_box :billing_override %>
  <%= f.label :billing_override %>
<% end %>
```

#### Validation Rules

The Pundit Module enforces strict validation:

```ruby
# ✓ Valid - Symbol pointing to policy method
setting :feature, authorize_with: :manage_feature?

# ✗ Invalid - String not allowed
setting :feature, authorize_with: "manage_feature?"
# => ArgumentError: authorize_with must be a Symbol

# ✗ Invalid - Array not allowed (use Roles Module for this)
setting :feature, authorize_with: [:admin?, :finance?]
# => ArgumentError: authorize_with must be a Symbol

# ✗ Invalid - Proc not allowed
setting :feature, authorize_with: -> { true }
# => ArgumentError: authorize_with must be a Symbol
```

**Why only Symbols?** Pundit policies are method-based. For simple role arrays or custom logic, use the Roles Module instead.

#### Advanced Policy Pattern

```ruby
# In your UserPolicy
class UserPolicy < ApplicationPolicy
  # Group permissions by category
  def billing_permissions
    User.settings_requiring(:manage_billing?)
  end

  def admin_permissions
    User.settings_requiring(:admin?)
  end

  # Combine with scopes
  def permitted_settings_for_form
    return [] unless can_edit_user?

    permitted_settings
  end

  # Check if user can edit any settings
  def can_edit_settings?
    permitted_settings.any?
  end

  private

  def can_edit_user?
    user.admin? || record == user
  end
end
```

#### Testing with Pundit

```ruby
RSpec.describe UserPolicy do
  subject { described_class.new(user, record) }

  let(:record) { User.new }

  context "when user is admin" do
    let(:user) { User.new(role: :admin) }

    it "permits all settings" do
      expect(subject.permitted_settings).to include(
        :billing_override,
        :api_access,
        :system_config
      )
    end
  end

  context "when user is finance" do
    let(:user) { User.new(role: :finance) }

    it "permits only billing settings" do
      expect(subject.permitted_settings).to eq([:billing_override])
    end
  end
end
```

### Authorization with ActionPolicy Module

For applications using [ActionPolicy](https://actionpolicy.evilmartians.io/) for authorization, ModelSettings provides seamless integration through the ActionPolicy Module. This allows you to leverage your existing ActionPolicy rules to control access to settings.

**Important:** Authorization modules (Roles, Pundit, ActionPolicy) are mutually exclusive. You can only use ONE authorization module at a time per model.

#### Basic ActionPolicy Integration

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL
  include ModelSettings::Modules::ActionPolicy

  # Use policy rules for authorization
  setting :billing_override,
          type: :column,
          authorize_with: :manage_billing?

  setting :api_access,
          type: :column,
          authorize_with: :admin?

  setting :system_config,
          type: :column,
          authorize_with: :admin?

  setting :display_name,
          type: :column
          # No authorization = unrestricted
end

# In your UserPolicy
class UserPolicy < ApplicationPolicy
  def manage_billing?
    user.admin? || user.finance?
  end

  def admin?
    user.admin?
  end

  # Helper method to get permitted settings
  def permitted_settings
    record.class._authorized_settings.select do |_name, method|
      public_send(method)
    end.keys
  end
end
```

#### Controller Integration with ActionPolicy

```ruby
class UsersController < ApplicationController
  def update
    @user = User.find(params[:id])
    authorize! @user

    # Get settings allowed by policy
    policy = authorized(@user)
    allowed_settings = policy.permitted_settings

    # Filter params to only include allowed settings
    permitted_params = params.require(:user).permit(*allowed_settings)

    if @user.update(permitted_params)
      redirect_to @user
    else
      render :edit
    end
  end
end
```

#### Querying Authorization Metadata

```ruby
# Get the policy rule for a setting
User.authorization_for_setting(:billing_override)
# => :manage_billing?

# Get all settings requiring a specific permission
User.settings_requiring(:admin?)
# => [:api_access, :system_config]

# Get all settings with authorization
User.authorized_settings
# => [:billing_override, :api_access, :system_config]
```

#### View Layer with ActionPolicy

```erb
<!-- In your views -->
<% policy = authorized(@user) %>
<% policy.permitted_settings.each do |setting_name| %>
  <div class="setting">
    <%= f.check_box setting_name %>
    <%= f.label setting_name %>
  </div>
<% end %>

<!-- Check specific permission -->
<% if allowed_to?(:manage_billing?, @user) %>
  <%= f.check_box :billing_override %>
  <%= f.label :billing_override %>
<% end %>
```

#### Validation Rules

The ActionPolicy Module enforces strict validation:

```ruby
# ✓ Valid - Symbol pointing to policy rule
setting :feature, authorize_with: :manage_feature?

# ✗ Invalid - String not allowed
setting :feature, authorize_with: "manage_feature?"
# => ArgumentError: authorize_with must be a Symbol

# ✗ Invalid - Array not allowed (use Roles Module for this)
setting :feature, authorize_with: [:admin?, :finance?]
# => ArgumentError: authorize_with must be a Symbol

# ✗ Invalid - Proc not allowed
setting :feature, authorize_with: -> { true }
# => ArgumentError: authorize_with must be a Symbol
```

**Why only Symbols?** ActionPolicy policies are rule-based methods. For simple role arrays or custom logic, use the Roles Module instead.

#### Advanced Policy Pattern

```ruby
# In your UserPolicy
class UserPolicy < ApplicationPolicy
  # Scope-based filtering
  relation_scope do |relation|
    next relation if user.admin?
    relation.where(organization_id: user.organization_id)
  end

  # Group permissions by category
  def billing_permissions
    User.settings_requiring(:manage_billing?)
  end

  def admin_permissions
    User.settings_requiring(:admin?)
  end

  # Dynamic permission checking
  def permitted_settings_for_form
    return [] unless can_edit_user?

    permitted_settings
  end

  # Check if user can edit any settings
  def can_edit_settings?
    permitted_settings.any?
  end

  private

  def can_edit_user?
    user.admin? || record.id == user.id
  end
end
```

#### Testing with ActionPolicy

```ruby
RSpec.describe UserPolicy do
  let(:policy) { described_class.new(user: user, record: record) }
  let(:record) { User.new }

  context "when user is admin" do
    let(:user) { User.new(role: :admin) }

    it "permits all settings" do
      expect(policy.permitted_settings).to include(
        :billing_override,
        :api_access,
        :system_config
      )
    end

    it "allows managing billing" do
      expect(policy.manage_billing?).to be true
    end
  end

  context "when user is finance" do
    let(:user) { User.new(role: :finance) }

    it "permits only billing settings" do
      expect(policy.permitted_settings).to eq([:billing_override])
    end

    it "allows managing billing" do
      expect(policy.manage_billing?).to be true
    end

    it "denies admin access" do
      expect(policy.admin?).to be false
    end
  end
end
```

#### Integration with params_filter

ActionPolicy's `params_filter` feature works seamlessly:

```ruby
class UserPolicy < ApplicationPolicy
  # Define allowed attributes based on permissions
  def allowed_attributes
    base = [:display_name]  # Always allowed
    base += permitted_settings  # Add authorized settings
    base
  end
end

# In controller
class UsersController < ApplicationController
  def update
    @user = User.find(params[:id])
    authorize! @user

    # Use params_filter with authorized settings
    filtered_params = params_filter(
      @user,
      :user,
      with: UserPolicy
    )

    @user.update(filtered_params)
  end
end
```

## Dependency Management

ModelSettings provides powerful dependency management through cascades and syncs, allowing settings to automatically update related settings while preventing circular dependencies.

### Cascades

Cascades automatically propagate enable/disable actions to child settings:

#### Enable Cascade

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  setting :premium_mode, type: :column, default: false, cascade: {enable: true} do
    setting :advanced_analytics, type: :column, default: false
    setting :priority_support, type: :column, default: false
    setting :custom_branding, type: :column, default: false
  end
end

# When premium_mode is enabled, all children are automatically enabled
user = User.create!
user.premium_mode = true
user.save!

user.advanced_analytics  # => true (auto-enabled)
user.priority_support    # => true (auto-enabled)
user.custom_branding     # => true (auto-enabled)
```

#### Disable Cascade

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  setting :account_active, type: :column, default: true, cascade: {disable: true} do
    setting :api_access, type: :column, default: true
    setting :email_notifications, type: :column, default: true
    setting :data_export, type: :column, default: true
  end
end

# When account is deactivated, all children are automatically disabled
user = User.create!
user.account_active = false
user.save!

user.api_access           # => false (auto-disabled)
user.email_notifications  # => false (auto-disabled)
user.data_export          # => false (auto-disabled)
```

#### Both Cascades

```ruby
class Organization < ApplicationRecord
  include ModelSettings::DSL

  setting :billing_enabled,
          type: :column,
          default: false,
          cascade: {enable: true, disable: true} do
    setting :invoices, type: :column, default: false
    setting :payments, type: :column, default: false
  end
end

# Enable cascade
org = Organization.create!
org.billing_enabled = true
org.save!
org.invoices  # => true
org.payments  # => true

# Disable cascade
org.billing_enabled = false
org.save!
org.invoices  # => false
org.payments  # => false
```

### Syncs

Syncs keep two settings synchronized with three modes: forward, inverse, and backward:

#### Forward Sync

Target setting mirrors source setting:

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  setting :marketing_emails,
          type: :column,
          default: true,
          sync: {target: :newsletter_subscription, mode: :forward}

  setting :newsletter_subscription, type: :column, default: true
end

user = User.create!
user.marketing_emails = false
user.save!

user.newsletter_subscription  # => false (synced)
```

#### Inverse Sync

Target setting is opposite of source setting:

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  setting :do_not_track,
          type: :column,
          default: false,
          sync: {target: :analytics_enabled, mode: :inverse}

  setting :analytics_enabled, type: :column, default: true
end

user = User.create!
user.do_not_track = true
user.save!

user.analytics_enabled  # => false (inverse of true)
```

#### Backward Sync

Source setting is updated to match target (useful for derived settings):

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  setting :auto_renew,
          type: :column,
          default: true,
          sync: {target: :subscription_active, mode: :backward}

  setting :subscription_active, type: :column, default: false
end

user = User.create!(subscription_active: true)
user.auto_renew = false  # Try to disable
user.save!

user.auto_renew  # => true (reverted to match subscription_active)
```

#### Chained Syncs

Syncs can be chained to propagate changes through multiple settings:

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  setting :gdpr_mode,
          type: :column,
          default: false,
          sync: {target: :privacy_enhanced, mode: :forward}

  setting :privacy_enhanced,
          type: :column,
          default: false,
          sync: {target: :tracking_disabled, mode: :forward}

  setting :tracking_disabled, type: :column, default: false
end

user = User.create!
user.gdpr_mode = true
user.save!

user.privacy_enhanced    # => true (synced from gdpr_mode)
user.tracking_disabled   # => true (synced from privacy_enhanced)
```

### Cycle Detection

The DependencyEngine automatically detects circular sync dependencies at definition time:

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  setting :feature_a, sync: {target: :feature_b, mode: :forward}
  setting :feature_b, sync: {target: :feature_c, mode: :forward}
  setting :feature_c, sync: {target: :feature_a, mode: :forward}  # Cycle!
end

# Raises at boot time:
# ModelSettings::CyclicSyncError: Cyclic sync detected: feature_a -> feature_b -> feature_c -> feature_a
# Settings cannot have circular sync dependencies.
```

This prevents infinite loops and ensures predictable behavior.

### Mixed Storage Types

Settings can have parent-child relationships across different storage backends:

#### Column Parent with JSON Children

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  # Column parent with JSON children using explicit storage
  setting :premium, type: :column, default: false, cascade: {enable: true} do
    setting :theme,
            type: :json,
            storage: {column: :premium_features},
            default: "light"

    setting :advanced_filters,
            type: :json,
            storage: {column: :premium_features},
            default: false
  end
end

# Migration:
# add_column :users, :premium, :boolean, default: false
# add_column :users, :premium_features, :jsonb, default: {}

user = User.create!
user.premium = true
user.save!

user.advanced_filters  # => true (cascaded from column parent)
user.theme            # => "light" (stored in JSON column)
```

#### JSON Parent with Column Children

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  setting :notifications,
          type: :json,
          storage: {column: :settings},
          default: true do
    # Child uses its own column even though parent is JSON
    setting :email_enabled, type: :column, default: false
    setting :sms_enabled, type: :column, default: false
  end
end

# Migration:
# add_column :users, :settings, :jsonb, default: {}
# add_column :users, :email_enabled, :boolean, default: false
# add_column :users, :sms_enabled, :boolean, default: false

user = User.create!
user.notifications = false
user.email_enabled = true

user.save!

# Each setting uses its own storage
user.settings          # => {"notifications" => false}
user.email_enabled     # => true (separate column)
```

#### Column Parent with StoreModel Children

```ruby
# Define StoreModel class
class PremiumFeatures
  include StoreModel::Model

  attribute :advanced_analytics, :boolean, default: false
  attribute :priority_support, :boolean, default: false
  attribute :custom_branding, :boolean, default: false
end

class User < ApplicationRecord
  include ModelSettings::DSL

  # Register StoreModel attribute
  attribute :premium_features, PremiumFeatures.to_type

  # Column parent with StoreModel children
  setting :premium,
          type: :column,
          default: false,
          cascade: {enable: true} do
    setting :advanced_analytics,
            type: :store_model,
            storage: {column: :premium_features}

    setting :priority_support,
            type: :store_model,
            storage: {column: :premium_features}

    setting :custom_branding,
            type: :store_model,
            storage: {column: :premium_features}
  end
end

# Migration:
# add_column :users, :premium, :boolean, default: false
# add_column :users, :premium_features, :jsonb, default: {}

user = User.create!(premium_features: PremiumFeatures.new)
user.premium = true
user.save!

# Cascade works across storage types
user.advanced_analytics  # => true (auto-enabled by cascade)
user.priority_support    # => true (auto-enabled by cascade)

# StoreModel benefits: type casting and validation
user.premium_features    # => #<PremiumFeatures advanced_analytics=true...>
```

### Combining Cascades and Syncs

Cascades and syncs work together seamlessly:

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  # Parent with cascade
  setting :enterprise_mode,
          type: :column,
          default: false,
          cascade: {enable: true} do
    setting :advanced_reporting, type: :column, default: false
  end

  # Independent sync
  setting :analytics_enabled,
          type: :column,
          default: true,
          sync: {target: :tracking_enabled, mode: :forward}

  setting :tracking_enabled, type: :column, default: true
end

user = User.create!
user.enterprise_mode = true
user.analytics_enabled = false
user.save!

# Both cascade and sync applied in same save
user.advanced_reporting  # => true (cascaded)
user.tracking_enabled    # => false (synced)
```

## Global Configuration

Configure default behavior globally:

```ruby
# config/initializers/model_settings.rb
ModelSettings.configure do |config|
  # Default modules to include (if implementing custom modules)
  config.default_modules = [:i18n]

  # Authorization inheritance (if using authorization modules)
  config.inherit_authorization = true
end
```

## Module Extension System

Create custom modules to extend functionality:

```ruby
module MyCustomModule
  extend ActiveSupport::Concern

  included do
    # Register your module
    ModelSettings::ModuleRegistry.register_module(:my_module, self)
  end

  module ClassMethods
    def custom_setting_behavior
      # Your custom class methods
    end
  end

  # Your custom instance methods
  def custom_instance_behavior
    # ...
  end
end

# Use in your models
class User < ApplicationRecord
  include ModelSettings::DSL
  include MyCustomModule

  # Your settings...
end

# Register hooks
ModelSettings::ModuleRegistry.on_settings_compiled do |settings|
  # Called when settings are compiled
  puts "Compiled #{settings.size} settings"
end

ModelSettings::ModuleRegistry.before_setting_change do |instance, setting, new_value|
  # Called before any setting changes
  AuditLog.create(user: instance, setting: setting.name, new_value: new_value)
end
```

## Setting Hierarchy

Settings can be nested for better organization:

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  setting :features, type: :json, storage: {column: :settings} do
    setting :billing, description: "Billing features" do
      setting :invoices_enabled, default: false
      setting :auto_payment, default: false
    end

    setting :communication, description: "Communication features" do
      setting :email_enabled, default: true
      setting :sms_enabled, default: false
    end
  end
end

# Navigate hierarchy
features_setting = User.find_setting(:features)
features_setting.children # => [billing, communication]

billing_setting = User.find_setting([:features, :billing])
billing_setting.parent # => features setting
billing_setting.root   # => features setting
billing_setting.path   # => [:features, :billing]

# Query hierarchy
User.root_settings      # => Only top-level settings
User.leaf_settings      # => Only settings without children
User.all_settings_recursive # => All settings including nested
```

## Best Practices

### 1. Choose the Right Storage Type

- **Column storage**: Best for frequently queried boolean flags
- **JSON storage**: Best for related settings that are read/written together
- **Mixed storage**: Use when you need column parent with JSON children or vice versa

### 2. Use Cascades for Hierarchical Features

Cascades are perfect for parent-child feature relationships:

```ruby
# Good - Feature hierarchy with cascade
setting :premium_plan, cascade: {enable: true} do
  setting :advanced_analytics
  setting :priority_support
  setting :custom_branding
end

# When premium is enabled, all premium features are automatically enabled
```

### 3. Use Syncs for Related Settings

Syncs keep related settings in sync automatically:

```ruby
# Good - Marketing consent syncs with newsletter
setting :marketing_consent,
        sync: {target: :newsletter_subscription, mode: :forward}

# Less ideal - Manual synchronization
after_save :sync_newsletter
def sync_newsletter
  self.newsletter_subscription = marketing_consent  # Easy to miss edge cases
end
```

### 4. Choose the Right Sync Mode

- **Forward** (target = source): For mirroring settings
- **Inverse** (target = !source): For opt-out/opt-in relationships
- **Backward** (source = target): For computed/derived settings

### 5. Avoid Circular Dependencies

The system will catch cycles at boot time, but design carefully:

```ruby
# Bad - Circular dependency
setting :feature_a, sync: {target: :feature_b, mode: :forward}
setting :feature_b, sync: {target: :feature_a, mode: :forward}
# Raises CyclicSyncError at boot!

# Good - Linear dependency chain
setting :feature_a, sync: {target: :feature_b, mode: :forward}
setting :feature_b, sync: {target: :feature_c, mode: :forward}
setting :feature_c  # End of chain
```

### 6. Use Metadata for Organization

```ruby
setting :feature_name,
        metadata: {
          category: "features",
          tier: "premium",
          documented_at: "https://docs.example.com/feature"
        }
```

### 7. Add Descriptions

```ruby
setting :api_access,
        description: "Enables API access for third-party integrations",
        default: false
```

### 8. Use Callbacks for Side Effects

Instead of manually triggering side effects, use callbacks:

```ruby
# Good
setting :premium_mode,
        after_enable: :setup_premium_features

# Less ideal
user.premium_mode = true
user.save!
user.setup_premium_features # Easy to forget!
```

### 9. Deprecate Gracefully

When replacing settings, use deprecation:

```ruby
setting :old_setting,
        deprecated: "Use new_setting instead",
        metadata: {deprecated_since: "2.0.0", replacement: :new_setting}
```

### 10. Combine Cascades with Syncs

Cascades and syncs work together for complex workflows:

```ruby
# Enterprise plan enables features AND syncs with billing
setting :enterprise_plan,
        cascade: {enable: true},
        sync: {target: :billing_enabled, mode: :forward} do
  setting :advanced_reporting
  setting :sso_integration
end
```

## Testing

```ruby
RSpec.describe User do
  describe "settings" do
    it "enables notifications by default" do
      user = User.create!
      expect(user.notifications_enabled).to be true
    end

    it "tracks changes" do
      user = User.create!(notifications_enabled: true)
      user.notifications_enabled = false

      expect(user.notifications_enabled_changed?).to be true
      expect(user.notifications_enabled_was).to be true
    end

    it "calls callbacks on enable" do
      user = User.create!
      expect(user).to receive(:notify_activation)

      user.premium_mode_enable!
    end
  end
end
```

## Performance Considerations

1. **N+1 Prevention**: Settings are defined at class level and don't cause N+1 queries
2. **JSON Indexing**: Add GIN indexes for JSONB columns in PostgreSQL
3. **Eager Loading**: Settings metadata is cached per model class
4. **Dirty Tracking**: Uses ActiveRecord's built-in dirty tracking

## Roadmap

### Completed ✅

- [x] **StoreModel adapter** - Full support for complex nested settings with StoreModel
- [x] **Dependency Engine** - Cascades, syncs (forward/inverse/backward), and cycle detection
- [x] **Mixed Storage Types** - Column parents with JSON children and vice versa
- [x] **Roles Module** - Role-based access control for settings with viewable_by/editable_by
- [x] **Pundit Module** - Seamless Pundit integration with authorize_with for policy-based authorization
- [x] **ActionPolicy Module** - ActionPolicy integration with authorize_with for rule-based authorization

### Planned

- [ ] **Plans Module** - Subscription tier management with automatic feature gating
- [ ] **Documentation Generator** - Rake tasks to generate settings documentation
- [ ] **Settings Inheritance** - Inherit settings across model hierarchies

## Development

### Running Tests

The gem uses RSpec for testing with comprehensive coverage across all adapters and features:

```bash
# Run all tests
bundle exec rspec

# Run specific test file
bundle exec rspec spec/model_settings/adapters/json_spec.rb

# Run with documentation format
bundle exec rspec --format documentation
```

### Code Quality

The project uses [StandardRB](https://github.com/standardrb/standard) for Ruby style and linting:

```bash
# Check code style
bundle exec standardrb

# Auto-fix issues
bundle exec standardrb --fix
```

### Test Architecture

- **In-memory SQLite**: Tests run against `:memory:` database for speed
- **Transactional fixtures**: Each test runs in a transaction that rolls back automatically
- **No migration logs**: `ActiveRecord::Migration.verbose = false` keeps test output clean
- **Shared examples**: Common adapter behavior tested via shared examples for consistency
- **Test isolation**: Full isolation between tests without manual cleanup

### Test Coverage

The test suite includes:

- **736 examples** with 100% passing rate
- Unit tests for all adapters (Column, JSON, StoreModel)
- Integration tests for dependency engine (cascades, syncs, mixed storage)
- Authorization tests for all three modules: Roles (RBAC), Pundit, and ActionPolicy
- Validation tests for boolean type checking and authorization options
- Edge case coverage (nil values, empty arrays, circular dependencies)
- Shared behavior verification across all adapters
- Module registry tests for exclusive groups and conflict detection
- RSpec Skill compliance: aggregate_failures, proper symmetry, Pattern 1

### Development Setup

```bash
# Clone the repository
git clone https://github.com/AlexeyMatskevich/model_settings.git
cd model_settings

# Install dependencies
bundle install

# Run tests
bundle exec rspec

# Check code style
bundle exec standardrb
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/AlexeyMatskevich/model_settings.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
