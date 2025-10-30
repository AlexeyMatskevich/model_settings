# frozen_string_literal: true

require "active_record"
require "store_model"

# Setup in-memory SQLite database for testing
ActiveRecord::Base.establish_connection(
  adapter: "sqlite3",
  database: ":memory:"
)

# Disable migration logs during tests
ActiveRecord::Migration.verbose = false

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

    # Additional columns for comprehensive mixed storage tests
    t.text :features_data # JSON array storage
    t.text :ui_data # JSON parent storage
    t.text :appearance_data # JSON parent storage
    t.text :allowed_ips_data # JSON array storage
    t.text :config_data # JSON parent storage
    t.text :sentiment_data # JSON child storage

    # Additional columns for Settings Inheritance tests
    t.boolean :notifications_enabled, default: true
    t.string :theme, default: "light"
    t.boolean :base_feature, default: true
    t.boolean :child_feature, default: false
    t.string :level_1, default: "base"
    t.string :level_2, default: "middle"
    t.string :level_3, default: "child"
    t.text :config_data_2 # For StoreModel inheritance tests
    t.boolean :api_access, default: false
    t.text :processors_data # JSON array storage
    t.text :premium_features # StoreModel storage
    t.text :ai_settings # StoreModel storage
    t.boolean :parent_setting, default: true
    t.boolean :child_setting, default: false

    # Additional columns for edge case tests
    t.boolean :shared_setting, default: true
    t.boolean :feature_a, default: false
    t.boolean :feature_b, default: false
    t.boolean :typed_setting, default: true
    t.boolean :child_only, default: false
    t.boolean :middle_only, default: false
    t.boolean :base_only, default: false

    t.timestamps
  end

  # JSON adapter test models
  create_table :json_test_models, force: true do |t|
    t.text :settings
    t.text :features
  end

  create_table :json_default_test_models, force: true do |t|
    t.text :settings, default: "{}", null: false
  end

  # StoreModel adapter test models
  create_table :store_model_test_models, force: true do |t|
    t.text :ai_settings # Nullable for main tests, validation tests will set defaults
    t.text :notification_settings
  end

  # Adapter shared behavior test models
  create_table :json_adapter_test_models, force: true do |t|
    t.text :settings
  end

  create_table :store_model_adapter_test_models, force: true do |t|
    t.text :settings
  end
end

# StoreModel classes for mixed storage tests
class PremiumFeaturesStore
  include StoreModel::Model

  attribute :analytics, :boolean, default: false
end

class AiSettingsStore
  include StoreModel::Model

  attribute :ai_transcription, :boolean, default: false
  attribute :ai_sentiment, :boolean, default: false
  attribute :ai_processing, :boolean, default: false
  attribute :ai_features, :boolean, default: false
  attribute :ai_summary, :boolean, default: false
  attribute :ai_enabled, :boolean, default: false
end

# Test model for ActiveRecord integration tests
class TestModel < ActiveRecord::Base
  # StoreModel attribute declarations for mixed storage tests
  attribute :premium_features, PremiumFeaturesStore.to_type
  attribute :ai_settings, AiSettingsStore.to_type

  # Will be used by tests that include ModelSettings::DSL
end

# Configure RSpec to use transactional fixtures for automatic cleanup
RSpec.configure do |config|
  # Wrap each test in a transaction and rollback after completion
  config.around do |example|
    ActiveRecord::Base.transaction do
      example.run
      raise ActiveRecord::Rollback
    end
  end
end
