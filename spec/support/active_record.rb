# frozen_string_literal: true

require "active_record"

# Setup in-memory SQLite database for testing
ActiveRecord::Base.establish_connection(
  adapter: "sqlite3",
  database: ":memory:"
)

# Setup database schema
ActiveRecord::Schema.define do
  create_table :test_models, force: true do |t|
    t.boolean :enabled, default: false, null: false
    t.boolean :premium_mode, default: false, null: false
    t.boolean :notifications, default: true, null: false
    t.text :settings_data # For JSON storage tests (Sprint 2)

    # Additional columns for DependencyEngine tests (Sprint 3)
    t.boolean :feature, default: false
    t.boolean :parent, default: false
    t.boolean :child_a, default: false
    t.boolean :child_b, default: false
    t.boolean :child, default: false
    t.boolean :source, default: false
    t.boolean :target, default: false
    t.boolean :other, default: false
    t.boolean :a, default: false
    t.boolean :b, default: false
    t.boolean :c, default: false
    t.boolean :d, default: false
    t.text :preferences # For JSON tests

    # Columns for mixed storage tests
    t.boolean :premium, default: false
    t.text :theme_data # JSON storage for nested theme setting
    t.text :notifications_data # JSON storage for nested notifications
    t.boolean :email_enabled, default: false # Column child of JSON parent

    t.timestamps
  end
end

# Test model for ActiveRecord integration tests
class TestModel < ActiveRecord::Base
  # Will be used by tests that include ModelSettings::DSL
end

# Reset test models before each test
RSpec.configure do |config|
  config.before(:each, type: :model) do
    TestModel.delete_all
  end
end
