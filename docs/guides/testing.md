# Testing Guide

Complete guide for testing ModelSettings in your Rails application.

## Table of Contents

- [Testing Basics](#testing-basics)
- [Testing Settings Behavior](#testing-settings-behavior)
- [Testing with Different Adapters](#testing-with-different-adapters)
- [Testing Authorization](#testing-authorization)
- [Testing Callbacks](#testing-callbacks)
- [Testing Dependencies](#testing-dependencies)
- [Testing Inheritance](#testing-inheritance)
- [Testing Custom Modules](#testing-custom-modules)
- [Best Practices](#best-practices)

---

## Testing Basics

### Setup

ModelSettings works seamlessly with RSpec and other testing frameworks. Basic setup:

```ruby
# spec/spec_helper.rb or spec/rails_helper.rb
require 'model_settings'

RSpec.configure do |config|
  # Reset ModelSettings configuration between tests
  config.before(:each) do
    ModelSettings.reset_configuration!
  end
end
```

### Basic Setting Tests

```ruby
# spec/models/user_spec.rb
RSpec.describe User, type: :model do
  describe "settings" do
    it "defines premium setting" do
      expect(User._settings.map(&:name)).to include(:premium)
    end

    it "has default value" do
      user = User.new
      expect(user.premium).to be false
    end

    it "can be changed" do
      user = User.create!(premium: false)
      user.premium = true
      user.save!

      expect(user.reload.premium).to be true
    end
  end
end
```

---

## Testing Settings Behavior

### Testing Helper Methods

```ruby
RSpec.describe User, type: :model do
  let(:user) { User.create!(premium: false) }

  describe "#premium_enable!" do
    it "enables the setting" do
      user.premium_enable!
      expect(user.premium).to be true
    end

    it "marks record as changed" do
      user.premium_enable!
      expect(user.premium_changed?).to be true
    end
  end

  describe "#premium_enabled?" do
    context "when premium is true" do
      before { user.update!(premium: true) }

      it "returns true" do
        expect(user.premium_enabled?).to be true
      end
    end

    context "when premium is false" do
      it "returns false" do
        expect(user.premium_enabled?).to be false
      end
    end
  end

  describe "#premium_toggle!" do
    it "toggles from false to true" do
      user.premium_toggle!
      expect(user.premium).to be true
    end

    it "toggles from true to false" do
      user.update!(premium: true)
      user.premium_toggle!
      expect(user.premium).to be false
    end
  end
end
```

### Testing Dirty Tracking

```ruby
RSpec.describe User, type: :model do
  let(:user) { User.create!(premium: false) }

  it "tracks changes" do
    user.premium = true

    expect(user.premium_changed?).to be true
    expect(user.premium_was).to be false
    expect(user.premium_change).to eq([false, true])
  end

  it "clears changes after save" do
    user.premium = true
    user.save!

    expect(user.premium_changed?).to be false
  end
end
```

---

## Testing with Different Adapters

### Column Adapter Tests

```ruby
RSpec.describe User, type: :model do
  # User model uses Column adapter
  it "stores in database column" do
    user = User.create!(premium: true)

    # Direct database query
    raw = User.connection.execute(
      "SELECT premium FROM users WHERE id = #{user.id}"
    ).first

    expect(raw['premium']).to eq(true)
  end
end
```

### JSON Adapter Tests

```ruby
RSpec.describe User, type: :model do
  # User has JSON settings
  # setting :preferences, type: :json, storage: { column: :settings_json } do
  #   setting :theme, default: "light"
  # end

  it "stores in JSON column" do
    user = User.create!
    user.theme = "dark"
    user.save!

    # Check JSON column
    raw = User.connection.execute(
      "SELECT settings_json FROM users WHERE id = #{user.id}"
    ).first

    json = JSON.parse(raw['settings_json'])
    expect(json.dig('preferences', 'theme')).to eq('dark')
  end

  it "handles nested settings" do
    user = User.create!(theme: "dark")

    expect(user.theme).to eq("dark")
    expect(user.preferences.theme).to eq("dark")
  end
end
```

### StoreModel Adapter Tests

```ruby
RSpec.describe User, type: :model do
  # User has StoreModel settings
  # setting :config, type: :store_model, storage: { column: :config_json } do
  #   setting :api_enabled
  # end

  it "uses StoreModel for validation" do
    user = User.new
    user.api_enabled = "invalid"  # Not a boolean

    expect(user).not_to be_valid
    expect(user.errors[:config]).to be_present
  end
end
```

---

## Testing Authorization

### Testing Roles Module

```ruby
RSpec.describe User, type: :model do
  # setting :billing, viewable_by: [:admin, :manager], editable_by: [:admin]

  describe "authorization" do
    let(:admin) { User.create!(role: :admin) }
    let(:manager) { User.create!(role: :manager) }
    let(:user) { User.create!(role: :user) }

    describe "viewable_by" do
      it "allows admins to view" do
        expect(admin.can_view_billing?).to be true
      end

      it "allows managers to view" do
        expect(manager.can_view_billing?).to be true
      end

      it "denies regular users" do
        expect(user.can_view_billing?).to be false
      end
    end

    describe "editable_by" do
      it "allows admins to edit" do
        expect(admin.can_edit_billing?).to be true
      end

      it "denies managers to edit" do
        expect(manager.can_edit_billing?).to be false
      end
    end
  end
end
```

### Testing Pundit Integration

```ruby
RSpec.describe User, type: :model do
  # setting :billing, authorize_with: :manage_billing?

  describe "Pundit authorization" do
    let(:user) { User.create! }
    let(:current_user) { User.create!(admin: true) }

    it "requires permission via policy" do
      policy = UserPolicy.new(current_user, user)

      expect(policy).to respond_to(:update_billing?)
      expect(policy.update_billing?).to be true
    end

    it "includes in permitted_settings" do
      policy = UserPolicy.new(current_user, user)

      expect(policy.permitted_settings).to include(:billing)
    end
  end
end
```

---

## Testing Callbacks

### Testing Lifecycle Callbacks

```ruby
RSpec.describe User, type: :model do
  # setting :premium,
  #   after_enable: :send_welcome_email,
  #   after_disable: :send_cancellation_email

  describe "callbacks" do
    let(:user) { User.create!(premium: false) }

    it "calls after_enable callback" do
      expect(user).to receive(:send_welcome_email)

      user.premium_enable!
      user.save!
    end

    it "calls after_disable callback" do
      user.update!(premium: true)

      expect(user).to receive(:send_cancellation_email)

      user.premium_disable!
      user.save!
    end
  end
end
```

### Testing Callback Timing

```ruby
RSpec.describe User, type: :model do
  it "executes callbacks at correct time" do
    user = User.create!(premium: false)

    # Track callback execution
    callback_order = []

    allow(user).to receive(:before_premium_enable) { callback_order << :before }
    allow(user).to receive(:after_premium_enable) { callback_order << :after }

    user.premium_enable!
    user.save!

    expect(callback_order).to eq([:before, :after])
  end
end
```

---

## Testing Dependencies

### Testing Cascades

```ruby
RSpec.describe User, type: :model do
  # setting :premium, cascade: { enable: true } do
  #   setting :api_access
  #   setting :priority_support
  # end

  describe "cascades" do
    let(:user) { User.create!(premium: false, api_access: false) }

    it "enables children when parent is enabled" do
      user.premium = true
      user.save!

      expect(user.reload.api_access).to be true
      expect(user.priority_support).to be true
    end

    it "disables children when parent is disabled" do
      user.update!(premium: true, api_access: true)

      user.premium = false
      user.save!

      expect(user.reload.api_access).to be false
    end
  end
end
```

### Testing Syncs

```ruby
RSpec.describe User, type: :model do
  # setting :feature_a, sync: { target: :feature_b, mode: :bidirectional }
  # setting :feature_b

  describe "syncs" do
    let(:user) { User.create! }

    it "syncs forward" do
      user.feature_a = true
      user.save!

      expect(user.reload.feature_b).to be true
    end

    it "syncs backward (bidirectional)" do
      user.feature_b = true
      user.save!

      expect(user.reload.feature_a).to be true
    end
  end
end
```

---

## Testing Inheritance

### Testing Model Inheritance

```ruby
RSpec.describe "settings inheritance", type: :model do
  # class Admin < User; end

  it "inherits parent settings" do
    admin = Admin.create!

    # Should have User settings
    expect(admin).to respond_to(:premium)
    expect(admin).to respond_to(:premium_enable!)
  end

  it "can override parent defaults" do
    # Admin overrides premium default to true
    admin = Admin.new

    expect(admin.premium).to be true
  end
end
```

### Testing Nested Settings Inheritance

```ruby
RSpec.describe User, type: :model do
  # setting :features, inherit_authorization: true do
  #   setting :api_enabled
  # end

  it "inherits authorization from parent" do
    # features has viewable_by: [:admin]
    # api_enabled should inherit this

    user = User.create!(role: :user)
    expect(user.can_view_api_enabled?).to be false

    admin = User.create!(role: :admin)
    expect(admin.can_view_api_enabled?).to be true
  end
end
```

---

## Testing Custom Modules

### Testing Module Registration

```ruby
RSpec.describe "custom module", type: :model do
  before do
    ModelSettings::ModuleRegistry.register_module(:audit_trail, AuditTrailModule)
  end

  it "registers module" do
    expect(ModelSettings::ModuleRegistry.module_registered?(:audit_trail)).to be true
  end

  it "tracks active modules" do
    user_class = Class.new(User) do
      include ModelSettings::Modules::AuditTrail
    end

    expect(user_class._active_modules).to include(:audit_trail)
  end
end
```

### Testing Custom Options

```ruby
RSpec.describe "custom options", type: :model do
  before do
    ModelSettings::ModuleRegistry.register_option(:audit_level) do |value, setting, model_class|
      unless [:minimal, :detailed].include?(value)
        raise ArgumentError, "Invalid audit_level"
      end
    end
  end

  it "validates custom option" do
    expect {
      Class.new(User) do
        setting :test, audit_level: :invalid
      end
    }.to raise_error(ArgumentError, /Invalid audit_level/)
  end

  it "accepts valid values" do
    expect {
      Class.new(User) do
        setting :test, audit_level: :detailed
      end
    }.not_to raise_error
  end
end
```

---

## Best Practices

### Use Factories

```ruby
# spec/factories/users.rb
FactoryBot.define do
  factory :user do
    email { Faker::Internet.email }

    trait :premium do
      premium { true }
    end

    trait :with_api_access do
      api_access { true }
    end
  end
end

# In specs
let(:premium_user) { create(:user, :premium) }
let(:api_user) { create(:user, :with_api_access) }
```

### Test Each Adapter Separately

```ruby
# spec/support/shared_examples/setting_examples.rb
RSpec.shared_examples "a boolean setting" do |setting_name|
  it "has enable! helper" do
    instance.public_send(:"#{setting_name}_enable!")
    expect(instance.public_send(setting_name)).to be true
  end

  it "has disable! helper" do
    instance.public_send(:"#{setting_name}_disable!")
    expect(instance.public_send(setting_name)).to be false
  end

  it "has toggle! helper" do
    original = instance.public_send(setting_name)
    instance.public_send(:"#{setting_name}_toggle!")
    expect(instance.public_send(setting_name)).to eq(!original)
  end
end

# Use in specs
RSpec.describe User do
  let(:user) { User.create! }

  it_behaves_like "a boolean setting", :premium do
    let(:instance) { user }
  end
end
```

### Use Database Cleaner

```ruby
# spec/spec_helper.rb
require 'database_cleaner/active_record'

RSpec.configure do |config|
  config.before(:suite) do
    DatabaseCleaner.clean_with(:truncation)
  end

  config.before(:each) do
    DatabaseCleaner.strategy = :transaction
  end

  config.before(:each, js: true) do
    DatabaseCleaner.strategy = :truncation
  end

  config.before(:each) do
    DatabaseCleaner.start
  end

  config.after(:each) do
    DatabaseCleaner.clean
  end
end
```

### Test Configuration Isolation

```ruby
RSpec.describe "configuration", type: :model do
  around do |example|
    # Reset configuration before and after test
    example.run
  ensure
    ModelSettings.reset_configuration!
  end

  it "configures default modules" do
    ModelSettings.configure do |config|
      config.default_modules = [:roles, :i18n]
    end

    # Test that modules are auto-included
    user_class = Class.new(User) do
      include ModelSettings::DSL
    end

    expect(user_class._active_modules).to include(:roles, :i18n)
  end
end
```

### Test Query Interface

```ruby
RSpec.describe "query interface", type: :model do
  before do
    # Create test data
    User.create!(role: :admin, premium: true)
    User.create!(role: :user, premium: false)
  end

  it "finds users by setting value" do
    premium_users = User.where(premium: true)

    expect(premium_users.count).to eq(1)
    expect(premium_users.first.role).to eq(:admin)
  end

  it "queries metadata" do
    admin_settings = User.settings_viewable_by(:admin)

    expect(admin_settings.map(&:name)).to include(:billing, :api_access)
  end
end
```

---

## Running Tests

### Run All Tests

```bash
bundle exec rspec
```

### Run Specific Tests

```bash
# Run specific file
bundle exec rspec spec/models/user_spec.rb

# Run specific line
bundle exec rspec spec/models/user_spec.rb:42

# Run by pattern
bundle exec rspec --pattern "spec/**/*_spec.rb"
```

### Check Coverage

```bash
# With SimpleCov
COVERAGE=true bundle exec rspec

# View coverage report
open coverage/index.html
```

---

## Troubleshooting

### Settings Not Compiling

**Problem**: `NoMethodError: undefined method 'premium'`

**Solution**: Ensure settings are compiled before use:

```ruby
# In test setup
before do
  User.compile_settings!
end
```

### Configuration Leaking Between Tests

**Problem**: Configuration from one test affects another

**Solution**: Reset configuration:

```ruby
RSpec.configure do |config|
  config.before(:each) do
    ModelSettings.reset_configuration!
  end
end
```

### Callbacks Not Firing in Tests

**Problem**: `after_commit` callbacks don't run in tests

**Solution**: Use transactional fixtures:

```ruby
RSpec.configure do |config|
  config.use_transactional_fixtures = false

  # Use database_cleaner instead
  config.before(:each) do
    DatabaseCleaner.strategy = :transaction
    DatabaseCleaner.start
  end

  config.after(:each) do
    DatabaseCleaner.clean
  end
end
```

---

## Additional Resources

- [RSpec Documentation](https://rspec.info/)
- [FactoryBot Documentation](https://github.com/thoughtbot/factory_bot)
- [Database Cleaner](https://github.com/DatabaseCleaner/database_cleaner)
- [SimpleCov](https://github.com/simplecov-ruby/simplecov)
- [ModelSettings Best Practices](best_practices.md)

---

**Last Updated**: 2025-11-04 (v0.9.0)
