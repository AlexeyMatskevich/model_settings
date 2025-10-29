# frozen_string_literal: true

require "spec_helper"

RSpec.describe ModelSettings::Adapters::Json do
  before do
    # Create test model with JSON column
    ActiveRecord::Schema.define do
      create_table :json_test_models, force: true do |t|
        t.text :settings
        t.text :features
      end
    end

    # Define the model class after table exists
    klass = Class.new(ActiveRecord::Base) do
      self.table_name = "json_test_models"
      include ModelSettings::DSL

      # Serialize JSON columns for SQLite
      serialize :settings, coder: JSON
      serialize :features, coder: JSON
    end
    stub_const("JsonTestModel", klass)
  end

  describe "#setup!" do
    let(:instance) { JsonTestModel.new }

    context "when setting is defined" do
      before do
        JsonTestModel.setting :notifications_enabled,
          type: :json,
          storage: {column: :settings}
      end

      it "creates enable! helper method" do
        expect(instance).to respond_to(:notifications_enabled_enable!)
      end

      it "creates disable! helper method" do
        expect(instance).to respond_to(:notifications_enabled_disable!)
      end

      it "creates toggle! helper method" do
        expect(instance).to respond_to(:notifications_enabled_toggle!)
      end

      it "creates enabled? helper method" do
        expect(instance).to respond_to(:notifications_enabled_enabled?)
      end

      it "creates disabled? helper method" do
        expect(instance).to respond_to(:notifications_enabled_disabled?)
      end
    end

    context "when setting has nested settings" do
      before do
        JsonTestModel.setting :features, type: :json, storage: {column: :features} do
          setting :billing_enabled, default: false
          setting :speech_recognition, default: false
        end
      end

      it "creates getter for parent setting" do
        expect(instance).to respond_to(:features)
      end

      it "creates setter for parent setting" do
        expect(instance).to respond_to(:features=)
      end

      it "creates getter for billing_enabled" do
        expect(instance).to respond_to(:billing_enabled)
      end

      it "creates setter for billing_enabled" do
        expect(instance).to respond_to(:billing_enabled=)
      end

      it "creates getter for speech_recognition" do
        expect(instance).to respond_to(:speech_recognition)
      end

      it "creates setter for speech_recognition" do
        expect(instance).to respond_to(:speech_recognition=)
      end

      it "creates enable! for billing_enabled" do
        expect(instance).to respond_to(:billing_enabled_enable!)
      end

      it "creates disable! for billing_enabled" do
        expect(instance).to respond_to(:billing_enabled_disable!)
      end

      it "creates toggle! for billing_enabled" do
        expect(instance).to respond_to(:billing_enabled_toggle!)
      end

      it "creates enable! for speech_recognition" do
        expect(instance).to respond_to(:speech_recognition_enable!)
      end
    end

    context "when storage configuration is missing" do
      let(:storage_config) { nil }

      it "raises ArgumentError" do
        expect {
          JsonTestModel.setting :invalid_setting, type: :json, storage: storage_config
        }.to raise_error(ArgumentError, /JSON adapter requires storage/)
      end
    end

    context "when storage column is NOT specified" do
      let(:storage_config) { {} }

      it "raises ArgumentError" do
        expect {
          JsonTestModel.setting :invalid_setting, type: :json, storage: storage_config
        }.to raise_error(ArgumentError, /JSON adapter requires storage/)
      end
    end
  end

  # rubocop:disable RSpecGuide/CharacteristicsAndContexts
  describe "helper methods" do
    before do
      JsonTestModel.setting :notifications_enabled,
        type: :json,
        storage: {column: :settings}
    end

    let(:instance) { JsonTestModel.create! }

    describe "#setting_name_enable!" do
      context "when setting is disabled" do
        before { instance.update!(notifications_enabled: false) }

        it "sets the setting to true" do
          instance.notifications_enabled_enable!
          expect(instance.notifications_enabled).to be true
        end

        it "marks the setting as changed" do
          instance.notifications_enabled_enable!
          expect(instance.notifications_enabled_changed?).to be true
        end
      end

      context "when setting is already enabled" do
        before { instance.update!(notifications_enabled: true) }

        it "keeps the setting as true" do
          instance.notifications_enabled_enable!
          expect(instance.notifications_enabled).to be true
        end

        it "does NOT mark as changed" do
          instance.notifications_enabled_enable!
          expect(instance.notifications_enabled_changed?).to be false
        end
      end
    end

    describe "#setting_name_disable!" do
      context "when setting is enabled" do
        before { instance.update!(notifications_enabled: true) }

        it "sets the setting to false" do
          instance.notifications_enabled_disable!
          expect(instance.notifications_enabled).to be false
        end

        it "marks the setting as changed" do
          instance.notifications_enabled_disable!
          expect(instance.notifications_enabled_changed?).to be true
        end
      end

      context "when setting is already disabled" do
        before { instance.update!(notifications_enabled: false) }

        it "keeps the setting as false" do
          instance.notifications_enabled_disable!
          expect(instance.notifications_enabled).to be false
        end

        it "does NOT mark as changed" do
          instance.notifications_enabled_disable!
          expect(instance.notifications_enabled_changed?).to be false
        end
      end
    end

    describe "#setting_name_toggle!" do
      context "when setting is false" do
        before { instance.update!(notifications_enabled: false) }

        it "changes to true" do
          instance.notifications_enabled_toggle!
          expect(instance.notifications_enabled).to be true
        end
      end

      context "when setting is true" do
        before { instance.update!(notifications_enabled: true) }

        it "changes to false" do
          instance.notifications_enabled_toggle!
          expect(instance.notifications_enabled).to be false
        end
      end
    end

    describe "#setting_name_enabled?" do
      context "when setting is true" do
        before { instance.update!(notifications_enabled: true) }

        it "returns true" do
          expect(instance.notifications_enabled_enabled?).to be true
        end
      end

      context "when setting is false" do
        before { instance.update!(notifications_enabled: false) }

        it "returns false" do
          expect(instance.notifications_enabled_enabled?).to be false
        end
      end
    end

    describe "#setting_name_disabled?" do
      context "when setting is false" do
        before { instance.update!(notifications_enabled: false) }

        it "returns true" do
          expect(instance.notifications_enabled_disabled?).to be true
        end
      end

      context "when setting is true" do
        before { instance.update!(notifications_enabled: true) }

        it "returns false" do
          expect(instance.notifications_enabled_disabled?).to be false
        end
      end
    end
  end
  # rubocop:enable RSpecGuide/CharacteristicsAndContexts

  describe "#read" do
    before do
      JsonTestModel.setting :api_enabled,
        type: :json,
        storage: {column: :settings}
    end

    let(:instance) { JsonTestModel.create!(api_enabled: value) }

    context "when value is true" do
      let(:value) { true }

      it "reads true" do
        adapter = described_class.new(JsonTestModel, JsonTestModel.find_setting(:api_enabled))
        expect(adapter.read(instance)).to be true
      end
    end

    context "when value is false" do
      let(:value) { false }

      it "reads false" do
        adapter = described_class.new(JsonTestModel, JsonTestModel.find_setting(:api_enabled))
        expect(adapter.read(instance)).to be false
      end
    end

    context "when value is nil" do
      let(:value) { nil }

      it "reads nil" do
        adapter = described_class.new(JsonTestModel, JsonTestModel.find_setting(:api_enabled))
        expect(adapter.read(instance)).to be_nil
      end
    end
  end

  describe "#write" do
    before do
      JsonTestModel.setting :api_enabled,
        type: :json,
        storage: {column: :settings}
    end

    let(:instance) { JsonTestModel.create! }
    let(:adapter) { described_class.new(JsonTestModel, JsonTestModel.find_setting(:api_enabled)) }

    context "when writing true" do
      let(:new_value) { true }

      it "sets value to true" do
        adapter.write(instance, new_value)
        expect(instance.api_enabled).to be true
      end

      it "marks as changed" do
        adapter.write(instance, new_value)
        expect(instance.api_enabled_changed?).to be true
      end
    end

    context "when writing false" do
      let(:new_value) { false }

      it "sets value to false" do
        adapter.write(instance, new_value)
        expect(instance.api_enabled).to be false
      end

      it "marks as changed" do
        adapter.write(instance, new_value)
        expect(instance.api_enabled_changed?).to be true
      end
    end
  end

  describe "#changed?" do
    before do
      JsonTestModel.setting :api_enabled,
        type: :json,
        storage: {column: :settings}
    end

    let(:instance) { JsonTestModel.create!(api_enabled: false) }
    let(:adapter) { described_class.new(JsonTestModel, JsonTestModel.find_setting(:api_enabled)) }

    context "when value has changed" do
      before { instance.api_enabled = true }

      it "returns true" do
        expect(adapter.changed?(instance)).to be true
      end
    end

    context "when value has NOT changed" do
      let(:expected_result) { false }

      it "returns false" do
        expect(adapter.changed?(instance)).to be expected_result
      end
    end
  end

  describe "#was" do
    before do
      JsonTestModel.setting :api_enabled,
        type: :json,
        storage: {column: :settings}
    end

    let(:instance) { JsonTestModel.create!(api_enabled: false) }
    let(:adapter) { described_class.new(JsonTestModel, JsonTestModel.find_setting(:api_enabled)) }

    context "when value has changed" do
      before { instance.api_enabled = true }

      it "returns previous value" do
        expect(adapter.was(instance)).to be false
      end
    end

    context "when value has NOT changed" do
      let(:expected_value) { false }

      it "returns current value" do
        expect(adapter.was(instance)).to be expected_value
      end
    end
  end

  describe "#change" do
    before do
      JsonTestModel.setting :api_enabled,
        type: :json,
        storage: {column: :settings}
    end

    let(:instance) { JsonTestModel.create!(api_enabled: false) }
    let(:adapter) { described_class.new(JsonTestModel, JsonTestModel.find_setting(:api_enabled)) }

    context "when value has changed" do
      before { instance.api_enabled = true }

      it "returns [old, new] array" do
        expect(adapter.change(instance)).to eq([false, true])
      end
    end

    context "when value has NOT changed" do
      let(:expected_change) { nil }

      it "returns nil" do
        expect(adapter.change(instance)).to be expected_change
      end
    end
  end

  # rubocop:disable RSpecGuide/CharacteristicsAndContexts
  describe "integration with ActiveRecord dirty tracking" do
    before do
      JsonTestModel.setting :feature_flags, type: :json, storage: {column: :features} do
        setting :analytics_enabled, default: false
        setting :reporting_enabled, default: false
      end
    end

    let(:instance) { JsonTestModel.create! }

    describe "change tracking" do
      it "marks setting as changed" do
        instance.analytics_enabled = true
        expect(instance.analytics_enabled_changed?).to be true
      end

      it "tracks previous value" do
        instance.update!(analytics_enabled: true)
        instance.analytics_enabled = false
        expect(instance.analytics_enabled_was).to be true
      end

      it "tracks change array" do
        instance.update!(analytics_enabled: false)
        instance.analytics_enabled = true
        expect(instance.analytics_enabled_change).to eq([false, true])
      end
    end

    describe "persistence" do
      it "persists changes to database" do
        instance.analytics_enabled = true
        instance.save!
        expect(instance.reload.analytics_enabled).to be true
      end

      it "clears changes after save" do
        instance.analytics_enabled = true
        instance.save!
        expect(instance.analytics_enabled_changed?).to be false
      end
    end

    describe "multiple settings" do
      before do
        instance.analytics_enabled = true
        instance.reporting_enabled = true
      end

      it "tracks analytics_enabled as changed" do
        expect(instance.analytics_enabled_changed?).to be true
      end

      it "tracks reporting_enabled as changed" do
        expect(instance.reporting_enabled_changed?).to be true
      end

      it "includes both settings in features changes" do
        expect(instance.features_changed?).to be true
      end
    end
  end
  # rubocop:enable RSpecGuide/CharacteristicsAndContexts

  describe "default values" do
    before do
      ActiveRecord::Base.connection.create_table :json_default_test_models, force: true do |t|
        t.text :settings, default: "{}", null: false
      end

      stub_const("JsonDefaultTestModel", Class.new(ActiveRecord::Base) do
        include ModelSettings::DSL

        serialize :settings, coder: JSON

        setting :notifications_enabled,
          type: :json,
          storage: {column: :settings},
          default: true

        setting :max_users,
          type: :json,
          storage: {column: :settings},
          default: 10
      end)
    end

    context "when value is set to falsy value" do
      let(:instance) do
        model = JsonDefaultTestModel.new
        model.notifications_enabled = false
        model.max_users = 0
        model
      end

      it "returns the falsy value for boolean" do
        expect(instance.notifications_enabled).to be false
      end

      it "returns the falsy value for numeric" do
        expect(instance.max_users).to eq(0)
      end
    end

    context "when value is NOT set" do
      let(:instance) { JsonDefaultTestModel.new }

      it "returns default for boolean setting" do
        expect(instance.notifications_enabled).to be true
      end

      it "returns default for numeric setting" do
        expect(instance.max_users).to eq(10)
      end
    end

    context "when value is explicitly set to nil" do
      let(:instance) do
        model = JsonDefaultTestModel.new
        model.settings = {notifications_enabled: nil, max_users: nil}
        model
      end

      it "returns nil instead of default" do
        expect(instance.notifications_enabled).to be_nil
      end
    end
  end

  # rubocop:disable RSpecGuide/CharacteristicsAndContexts
  describe "array support" do
    let(:instance) { JsonArrayTestModel.new }

    before do
      ActiveRecord::Base.connection.create_table :json_array_test_models, force: true do |t|
        t.text :settings, default: "{}", null: false
      end

      stub_const("JsonArrayTestModel", Class.new(ActiveRecord::Base) do
        include ModelSettings::DSL

        serialize :settings, coder: JSON

        setting :allowed_ips,
          type: :json,
          storage: {column: :settings},
          array: true,
          default: []

        setting :tags,
          type: :json,
          storage: {column: :settings},
          array: true
      end)
    end

    it "returns default empty array" do
      expect(instance.allowed_ips).to eq([])
    end

    it "allows setting array values" do
      instance.allowed_ips = ["192.168.1.1", "10.0.0.1"]

      expect(instance.allowed_ips).to eq(["192.168.1.1", "10.0.0.1"])
    end

    it "tracks array changes" do
      instance.allowed_ips = ["192.168.1.1"]
      instance.save!
      instance.allowed_ips = ["192.168.1.1", "10.0.0.1"]

      expect(instance.allowed_ips_changed?).to be true
    end

    it "returns previous array value" do
      instance.allowed_ips = ["192.168.1.1"]
      instance.save!
      instance.allowed_ips = ["10.0.0.1"]

      expect(instance.allowed_ips_was).to eq(["192.168.1.1"])
    end

    it "returns nil for unset array" do
      expect(instance.tags).to be_nil
    end
  end
  # rubocop:enable RSpecGuide/CharacteristicsAndContexts

  describe "nested keys" do
    before do
      ActiveRecord::Base.connection.create_table :json_nested_test_models, force: true do |t|
        t.text :config, default: "{}", null: false
      end

      stub_const("JsonNestedTestModel", Class.new(ActiveRecord::Base) do
        include ModelSettings::DSL

        serialize :config, coder: JSON

        setting :api, type: :json, storage: {column: :config} do
          setting :enabled, default: false
          setting :rate_limit, default: 100

          setting :oauth do
            setting :client_id
            setting :client_secret
          end
        end
      end)
    end

    context "when accessing nested values" do
      let(:instance) { JsonNestedTestModel.new }

      it "returns default for first level nested setting" do
        expect(instance.enabled).to be false
      end

      it "allows setting first level nested values" do
        instance.enabled = true

        expect(instance.enabled).to be true
      end

      it "returns default for second level nested setting" do
        expect(instance.rate_limit).to eq(100)
      end

      it "allows setting deeply nested values" do
        instance.client_id = "abc123"

        expect(instance.client_id).to eq("abc123")
      end

      it "creates proper nested structure" do
        instance.client_id = "abc123"
        instance.client_secret = "secret"

        expect(instance.config).to eq({
          "api" => {
            "oauth" => {
              "client_id" => "abc123",
              "client_secret" => "secret"
            }
          }
        })
      end
    end

    context "when tracking changes in nested structure" do
      let(:instance) do
        model = JsonNestedTestModel.new
        model.enabled = true
        model.save!
        model
      end

      it "detects changes in nested values" do
        instance.enabled = false

        expect(instance.enabled_changed?).to be true
      end

      it "returns previous nested value" do
        instance.rate_limit = 200

        expect(instance.rate_limit_was).to eq(100)
      end

      it "tracks change array for nested setting" do
        instance.enabled = false

        expect(instance.enabled_change).to eq([true, false])
      end
    end
  end
end
