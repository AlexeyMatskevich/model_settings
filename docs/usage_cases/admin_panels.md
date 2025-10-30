# Admin Panels

Build admin UIs for managing settings with authorization.

## Admin Settings Controller

```ruby
class Admin::SettingsController < Admin::BaseController
  before_action :require_admin

  def index
    @user = User.find(params[:user_id])
    @settings = User.all_settings_recursive
  end

  def update
    @user = User.find(params[:user_id])
    
    # Get editable settings for admin
    editable = User.settings_editable_by(:admin)
    
    if @user.update(setting_params(editable))
      redirect_to admin_user_settings_path(@user), notice: "Settings updated"
    else
      render :index
    end
  end

  private

  def setting_params(allowed_settings)
    params.require(:user).permit(*allowed_settings)
  end
end
```

## Settings List View

```erb
<h2>User Settings for <%= @user.email %></h2>

<%= form_for @user, url: admin_user_settings_path(@user) do |f| %>
  <% @settings.each do |setting| %>
    <% if current_admin.can_edit_setting?(setting.name, :admin) %>
      <div class="setting-row">
        <%= f.check_box setting.name %>
        <%= f.label setting.name %>
        
        <% if setting.deprecated? %>
          <span class="badge badge-warning">Deprecated</span>
        <% end %>
      </div>
    <% end %>
  <% end %>

  <%= f.submit "Update Settings" %>
<% end %>
```

## Bulk Operations

```ruby
class Admin::BulkSettingsController < Admin::BaseController
  def enable_for_all
    setting_name = params[:setting]
    
    User.find_each do |user|
      user.public_send("#{setting_name}_enable!")
    end
    
    redirect_to admin_settings_path, notice: "Enabled #{setting_name} for all users"
  end
end
```
