# frozen_string_literal: true

require "spec_helper"
require "store_model"

# rubocop:disable RSpecGuide/MinimumBehavioralCoverage
RSpec.describe ModelSettings::Adapters::StoreModel do
  before do
    # Table already exists from active_record.rb

    # Define StoreModel classes
    stub_const("AiSettings", Class.new do
      include ::StoreModel::Model

      attribute :transcription, :boolean, default: false
      attribute :sentiment, :boolean, default: false
      attribute :rate_limit, :integer, default: 100
    end)

    stub_const("NotificationSettings", Class.new do
      include ::StoreModel::Model

      attribute :email_enabled, :boolean, default: true
      attribute :sms_enabled, :boolean, default: false
    end)

    # Define the model class after table exists
    klass = Class.new(ActiveRecord::Base) do
      self.table_name = "store_model_test_models"
      include ModelSettings::DSL

      attribute :ai_settings, AiSettings.to_type
      attribute :notification_settings, NotificationSettings.to_type
    end
    stub_const("StoreModelTestModel", klass)
  end

  describe "#setup!" do
    context "when setting is defined" do
      before do
        StoreModelTestModel.setting :transcription,
          type: :store_model,
          storage: {column: :ai_settings}
      end

      let(:instance) { StoreModelTestModel.new(ai_settings: AiSettings.new) }

      it "creates all helper methods", :aggregate_failures do
        expect(instance).to respond_to(:transcription_enable!)
        expect(instance).to respond_to(:transcription_disable!)
        expect(instance).to respond_to(:transcription_toggle!)
        expect(instance).to respond_to(:transcription_enabled?)
        expect(instance).to respond_to(:transcription_disabled?)
        expect(instance).to respond_to(:transcription_changed?)
        expect(instance).to respond_to(:transcription_was)
        expect(instance).to respond_to(:transcription_change)
      end
    end

    context "when storage configuration is missing" do
      let(:storage_config) { nil }

      it "raises ArgumentError" do
        expect {
          StoreModelTestModel.setting :invalid_setting, type: :store_model, storage: storage_config
        }.to raise_error(ArgumentError, /StoreModel adapter requires a storage column/m)
      end
    end

    context "when storage column is NOT specified" do
      let(:storage_config) { {} }

      it "raises ArgumentError" do
        expect {
          StoreModelTestModel.setting :invalid_setting, type: :store_model, storage: storage_config
        }.to raise_error(ArgumentError, /StoreModel adapter requires a storage column/m)
      end
    end
  end

  # rubocop:disable RSpecGuide/MinimumBehavioralCoverage
  describe "helper methods" do
    before do
      StoreModelTestModel.setting :email_enabled,
        type: :store_model,
        storage: {column: :notification_settings}
    end

    let(:instance) do
      StoreModelTestModel.create!(notification_settings: NotificationSettings.new)
    end

    describe "#setting_name_enable!" do
      context "when setting is disabled" do
        before { instance.update!(email_enabled: false) }

        it "sets the setting to true" do
          instance.email_enabled_enable!
          expect(instance.email_enabled).to be true
        end

        it "marks the setting as changed" do
          instance.email_enabled_enable!
          expect(instance.email_enabled_changed?).to be true
        end
      end

      context "when setting is already enabled" do
        before { instance.update!(email_enabled: true) }

        it "keeps the setting as true" do
          instance.email_enabled_enable!
          expect(instance.email_enabled).to be true
        end

        it "does NOT mark as changed" do
          instance.email_enabled_enable!
          expect(instance.email_enabled_changed?).to be false
        end
      end
    end

    describe "#setting_name_disable!" do
      context "when setting is enabled" do
        before { instance.update!(email_enabled: true) }

        it "sets the setting to false" do
          instance.email_enabled_disable!
          expect(instance.email_enabled).to be false
        end

        it "marks the setting as changed" do
          instance.email_enabled_disable!
          expect(instance.email_enabled_changed?).to be true
        end
      end

      context "when setting is already disabled" do
        before { instance.update!(email_enabled: false) }

        it "keeps the setting as false" do
          instance.email_enabled_disable!
          expect(instance.email_enabled).to be false
        end

        it "does NOT mark as changed" do
          instance.email_enabled_disable!
          expect(instance.email_enabled_changed?).to be false
        end
      end
    end

    describe "#setting_name_toggle!" do
      context "when setting is disabled" do
        before { instance.update!(email_enabled: false) }

        it "enables the setting" do
          instance.email_enabled_toggle!
          expect(instance.email_enabled).to be true
        end
      end

      context "when setting is enabled" do
        before { instance.update!(email_enabled: true) }

        it "disables the setting" do
          instance.email_enabled_toggle!
          expect(instance.email_enabled).to be false
        end
      end
    end

    describe "#setting_name_enabled?" do
      context "when setting is true" do
        before { instance.update!(email_enabled: true) }

        it "returns true" do
          expect(instance.email_enabled_enabled?).to be true
        end
      end

      context "when setting is false" do
        before { instance.update!(email_enabled: false) }

        it "returns false" do
          expect(instance.email_enabled_enabled?).to be false
        end
      end
    end

    describe "#setting_name_disabled?" do
      context "when setting is false" do
        before { instance.update!(email_enabled: false) }

        it "returns true" do
          expect(instance.email_enabled_disabled?).to be true
        end
      end

      context "when setting is true" do
        before { instance.update!(email_enabled: true) }

        it "returns false" do
          expect(instance.email_enabled_disabled?).to be false
        end
      end
    end
  end
  # rubocop:enable RSpecGuide/MinimumBehavioralCoverage

  describe "#read" do
    before do
      StoreModelTestModel.setting :transcription,
        type: :store_model,
        storage: {column: :ai_settings}
    end

    let(:adapter) { described_class.new(StoreModelTestModel, StoreModelTestModel.find_setting(:transcription)) }

    context "when value is true" do
      let(:instance) do
        StoreModelTestModel.create!(ai_settings: AiSettings.new(transcription: true))
      end

      it "reads true" do
        expect(adapter.read(instance)).to be true
      end
    end

    context "when value is false" do
      let(:instance) do
        StoreModelTestModel.create!(ai_settings: AiSettings.new(transcription: false))
      end

      it "reads false" do
        expect(adapter.read(instance)).to be false
      end
    end

    context "when StoreModel instance is nil" do
      let(:instance) { StoreModelTestModel.create!(ai_settings: nil) }

      it "reads nil" do
        expect(adapter.read(instance)).to be_nil
      end
    end
  end

  describe "#write" do
    before do
      StoreModelTestModel.setting :transcription,
        type: :store_model,
        storage: {column: :ai_settings}
    end

    let(:instance) do
      StoreModelTestModel.create!(ai_settings: AiSettings.new)
    end
    let(:adapter) { described_class.new(StoreModelTestModel, StoreModelTestModel.find_setting(:transcription)) }

    context "when writing true" do
      let(:new_value) { true }

      it "sets value to true" do
        adapter.write(instance, new_value)
        expect(instance.transcription).to be true
      end

      it "marks as changed" do
        adapter.write(instance, new_value)
        expect(instance.transcription_changed?).to be true
      end
    end

    context "when writing false" do
      let(:new_value) { false }

      before { instance.update!(transcription: true) }

      it "sets value to false" do
        adapter.write(instance, new_value)
        expect(instance.transcription).to be false
      end

      it "marks as changed" do
        adapter.write(instance, new_value)
        expect(instance.transcription_changed?).to be true
      end
    end

    context "when StoreModel instance is nil" do
      let(:instance) { StoreModelTestModel.create!(ai_settings: nil) }

      it "does NOT raise error" do
        expect { adapter.write(instance, true) }.not_to raise_error
      end

      it "does NOT set value" do
        adapter.write(instance, true)
        expect(instance.transcription).to be_nil
      end
    end
  end

  describe "#changed?" do
    before do
      StoreModelTestModel.setting :transcription,
        type: :store_model,
        storage: {column: :ai_settings}
    end

    let(:instance) do
      StoreModelTestModel.create!(ai_settings: AiSettings.new(transcription: false))
    end
    let(:adapter) { described_class.new(StoreModelTestModel, StoreModelTestModel.find_setting(:transcription)) }

    context "when value has changed" do
      before { instance.transcription = true }

      it "returns true" do
        expect(adapter.changed?(instance)).to be true
      end
    end

    # rubocop:disable RSpecGuide/ContextSetup
    context "but when value has NOT changed" do  # No changes - testing default state
      it "returns false" do
        expect(adapter.changed?(instance)).to be false
      end
    end
    # rubocop:enable RSpecGuide/ContextSetup

    context "and when StoreModel instance is nil" do
      let(:instance) { StoreModelTestModel.create!(ai_settings: nil) }

      it "returns false" do
        expect(adapter.changed?(instance)).to be false
      end
    end
  end

  describe "#was" do
    before do
      StoreModelTestModel.setting :transcription,
        type: :store_model,
        storage: {column: :ai_settings}
    end

    let(:instance) do
      StoreModelTestModel.create!(ai_settings: AiSettings.new(transcription: false))
    end
    let(:adapter) { described_class.new(StoreModelTestModel, StoreModelTestModel.find_setting(:transcription)) }

    context "when value has changed" do
      before { instance.transcription = true }

      it "returns previous value" do
        expect(adapter.was(instance)).to be false
      end
    end

    # rubocop:disable RSpecGuide/ContextSetup
    context "but when value has NOT changed" do  # No changes - testing default state
      it "returns current value" do
        expect(adapter.was(instance)).to be false
      end
    end
    # rubocop:enable RSpecGuide/ContextSetup

    context "and when StoreModel instance is nil" do
      let(:instance) { StoreModelTestModel.create!(ai_settings: nil) }

      it "returns nil" do
        expect(adapter.was(instance)).to be_nil
      end
    end
  end

  describe "#change" do
    before do
      StoreModelTestModel.setting :transcription,
        type: :store_model,
        storage: {column: :ai_settings}
    end

    let(:instance) do
      StoreModelTestModel.create!(ai_settings: AiSettings.new(transcription: false))
    end
    let(:adapter) { described_class.new(StoreModelTestModel, StoreModelTestModel.find_setting(:transcription)) }

    context "when value has changed" do
      before { instance.transcription = true }

      it "returns [old, new] array" do
        expect(adapter.change(instance)).to eq([false, true])
      end
    end

    # rubocop:disable RSpecGuide/ContextSetup
    context "but when value has NOT changed" do  # No changes - testing default state
      it "returns nil" do
        expect(adapter.change(instance)).to be_nil
      end
    end
    # rubocop:enable RSpecGuide/ContextSetup

    context "and when StoreModel instance is nil" do
      let(:instance) { StoreModelTestModel.create!(ai_settings: nil) }

      it "returns nil" do
        expect(adapter.change(instance)).to be_nil
      end
    end
  end

  describe "integration with StoreModel dirty tracking" do
    before do
      StoreModelTestModel.setting :transcription,
        type: :store_model,
        storage: {column: :ai_settings}
      StoreModelTestModel.setting :sentiment,
        type: :store_model,
        storage: {column: :ai_settings}
    end

    let(:instance) do
      StoreModelTestModel.create!(ai_settings: AiSettings.new)
    end

    context "when single setting changes" do
      before { instance.transcription = true }

      it "marks setting as changed" do
        expect(instance.transcription_changed?).to be true
      end

      it "tracks previous value" do
        instance.update!(transcription: true)
        instance.transcription = false
        expect(instance.transcription_was).to be true
      end

      it "returns change array" do
        instance.update!(transcription: false)
        instance.transcription = true
        expect(instance.transcription_change).to eq([false, true])
      end

      context "and saved" do
        before { instance.save! }

        it "persists to database" do
          expect(instance.reload.transcription).to be true
        end

        it "clears changed flag" do
          expect(instance.transcription_changed?).to be false
        end
      end
    end

    context "when multiple settings change" do
      before do
        instance.transcription = true
        instance.sentiment = true
      end

      it "tracks transcription as changed" do
        expect(instance.transcription_changed?).to be true
      end

      it "tracks sentiment as changed" do
        expect(instance.sentiment_changed?).to be true
      end

      it "tracks parent column as changed" do
        expect(instance.ai_settings_changed?).to be true
      end
    end
  end

  describe "default values" do
    before do
      StoreModelTestModel.setting :transcription,
        type: :store_model,
        storage: {column: :ai_settings}
      StoreModelTestModel.setting :rate_limit,
        type: :store_model,
        storage: {column: :ai_settings}
    end

    context "when value is set to falsy value" do
      let(:instance) do
        model = StoreModelTestModel.new(ai_settings: AiSettings.new)
        model.transcription = false
        model
      end

      it "returns the falsy value for boolean" do
        expect(instance.transcription).to be false
      end
    end

    context "when value is NOT set" do
      let(:instance) { StoreModelTestModel.new(ai_settings: AiSettings.new) }

      it "returns default for boolean setting" do
        expect(instance.transcription).to be false
      end
    end

    context "when StoreModel instance is nil" do
      let(:instance) { StoreModelTestModel.new(ai_settings: nil) }

      it "returns nil for setting access" do
        expect(instance.transcription).to be_nil
      end
    end
  end

  # rubocop:disable RSpecGuide/MinimumBehavioralCoverage
  describe "boolean validation" do
    before do
      # Table already exists from active_record.rb
      klass = Class.new(ActiveRecord::Base) do
        include ModelSettings::DSL

        attribute :ai_settings, AiSettings.to_type

        setting :transcription,
          type: :store_model,
          storage: {column: :ai_settings}

        compile_settings!
      end

      stub_const("StoreModelTestModel", klass)
    end

    let(:instance) { StoreModelTestModel.new(ai_settings: AiSettings.new) }
    let(:adapter) { described_class.new(StoreModelTestModel, StoreModelTestModel.find_setting(:transcription)) }

    # Characteristic: Value type
    it "accepts true", :aggregate_failures do
      expect { instance.transcription = true }.not_to raise_error
      expect(instance.transcription).to be true
    end

    it "accepts false", :aggregate_failures do
      expect { instance.transcription = false }.not_to raise_error
      expect(instance.transcription).to be false
    end

    it "accepts nil", :aggregate_failures do
      instance.transcription = nil
      expect(instance).to be_valid
      expect(instance.transcription).to be_nil
    end

    context "but with string value" do
      before { instance.transcription = "enabled" }

      it "marks record as invalid" do
        expect(instance).not_to be_valid
      end
    end

    context "but with integer value" do
      before { instance.transcription = 1 }

      it "marks record as invalid" do
        expect(instance).not_to be_valid
      end
    end

    context "but with hash value" do
      before { instance.transcription = {enabled: true} }

      it "marks record as invalid" do
        expect(instance).not_to be_valid
      end
    end

    # rubocop:disable RSpecGuide/MinimumBehavioralCoverage
    describe "adapter write validation" do
      it "accepts true value", :aggregate_failures do
        expect { adapter.write(instance, true) }.not_to raise_error
        expect(instance.transcription).to be true
      end

      it "accepts false value", :aggregate_failures do
        expect { adapter.write(instance, false) }.not_to raise_error
        expect(instance.transcription).to be false
      end

      it "rejects string value" do
        adapter.write(instance, "value")
        expect(instance).not_to be_valid
      end

      it "rejects array value" do
        adapter.write(instance, [])
        expect(instance).not_to be_valid
      end
    end
    # rubocop:enable RSpecGuide/MinimumBehavioralCoverage
  end
  # rubocop:enable RSpecGuide/MinimumBehavioralCoverage
end
