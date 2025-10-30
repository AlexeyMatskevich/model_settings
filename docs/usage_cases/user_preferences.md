# User Preferences

Store user preferences and settings using JSON storage.

## Basic Preferences

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  setting :preferences, type: :json, storage: {column: :prefs_data} do
    setting :theme, default: "light"
    setting :language, default: "en"
    setting :timezone, default: "UTC"
    setting :email_notifications, default: true
    setting :sms_notifications, default: false
  end
end

# Migration
add_column :users, :prefs_data, :jsonb, default: {}, null: false
add_index :users, :prefs_data, using: :gin

# Usage
user.theme = "dark"
user.language = "es"
user.save!
```

## Settings Form

```erb
<%= form_for current_user do |f| %>
  <div class="field">
    <%= f.label :theme %>
    <%= f.select :theme, ["light", "dark", "auto"] %>
  </div>

  <div class="field">
    <%= f.label :language %>
    <%= f.select :language, ["en", "es", "fr", "de"] %>
  </div>

  <div class="field">
    <%= f.check_box :email_notifications %>
    <%= f.label :email_notifications %>
  </div>

  <%= f.submit "Save Preferences" %>
<% end %>
```

## Controller

```ruby
class PreferencesController < ApplicationController
  def update
    if current_user.update(preferences_params)
      redirect_to preferences_path, notice: "Preferences saved"
    else
      render :edit
    end
  end

  private

  def preferences_params
    params.require(:user).permit(:theme, :language, :timezone,
                                   :email_notifications, :sms_notifications)
  end
end
```
