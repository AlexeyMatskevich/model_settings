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
    context "when setting is defined" do
      before do
        JsonTestModel.setting :notifications_enabled,
          type: :json,
          storage: {column: :settings}
      end

      let(:instance) { JsonTestModel.new }

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

      it "sets up store_accessor for the setting" do
        expect(instance).to respond_to(:notifications_enabled)
        expect(instance).to respond_to(:notifications_enabled=)
      end
    end

    context "when setting has nested settings" do
      before do
        JsonTestModel.setting :features, type: :json, storage: {column: :features} do
          setting :billing_enabled, default: false
          setting :speech_recognition, default: false
        end
      end

      let(:instance) { JsonTestModel.new }

      it "creates accessors for parent setting" do
        expect(instance).to respond_to(:features)
        expect(instance).to respond_to(:features=)
      end

      it "creates accessors for nested settings" do
        expect(instance).to respond_to(:billing_enabled)
        expect(instance).to respond_to(:billing_enabled=)
        expect(instance).to respond_to(:speech_recognition)
        expect(instance).to respond_to(:speech_recognition=)
      end

      it "creates helper methods for nested settings" do
        expect(instance).to respond_to(:billing_enabled_enable!)
        expect(instance).to respond_to(:billing_enabled_disable!)
        expect(instance).to respond_to(:billing_enabled_toggle!)
        expect(instance).to respond_to(:speech_recognition_enable!)
      end
    end

    context "when storage configuration is missing" do
      it "raises ArgumentError" do
        expect {
          JsonTestModel.setting :invalid_setting, type: :json
        }.to raise_error(ArgumentError, /JSON adapter requires storage/)
      end
    end

    context "when storage column is NOT specified" do
      it "raises ArgumentError" do
        expect {
          JsonTestModel.setting :invalid_setting, type: :json, storage: {}
        }.to raise_error(ArgumentError, /JSON adapter requires storage/)
      end
    end
  end

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
      it "sets value to true" do
        adapter.write(instance, true)
        expect(instance.api_enabled).to be true
      end

      it "marks as changed" do
        adapter.write(instance, true)
        expect(instance.api_enabled_changed?).to be true
      end
    end

    context "when writing false" do
      it "sets value to false" do
        adapter.write(instance, false)
        expect(instance.api_enabled).to be false
      end

      it "marks as changed" do
        adapter.write(instance, false)
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
      it "returns false" do
        expect(adapter.changed?(instance)).to be false
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
      it "returns current value" do
        expect(adapter.was(instance)).to be false
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
      it "returns nil" do
        expect(adapter.change(instance)).to be_nil
      end
    end
  end

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
end
