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
