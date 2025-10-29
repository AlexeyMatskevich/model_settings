# frozen_string_literal: true

require "spec_helper"
require "store_model"

RSpec.describe ModelSettings::Adapters::StoreModel do
  before do
    # Create test model with JSONB column
    ActiveRecord::Schema.define do
      create_table :store_model_test_models, force: true do |t|
        t.text :ai_settings
        t.text :notification_settings
      end
    end

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

      it "creates enable! helper method" do
        expect(instance).to respond_to(:transcription_enable!)
      end

      it "creates disable! helper method" do
        expect(instance).to respond_to(:transcription_disable!)
      end

      it "creates toggle! helper method" do
        expect(instance).to respond_to(:transcription_toggle!)
      end

      it "creates enabled? helper method" do
        expect(instance).to respond_to(:transcription_enabled?)
      end

      it "creates disabled? helper method" do
        expect(instance).to respond_to(:transcription_disabled?)
      end

      it "creates changed? helper method" do
        expect(instance).to respond_to(:transcription_changed?)
      end

      it "creates _was helper method" do
        expect(instance).to respond_to(:transcription_was)
      end

      it "creates _change helper method" do
        expect(instance).to respond_to(:transcription_change)
      end
    end

    context "when storage configuration is missing" do
      let(:storage_config) { nil }

      it "raises ArgumentError" do
        expect {
          StoreModelTestModel.setting :invalid_setting, type: :store_model, storage: storage_config
        }.to raise_error(ArgumentError, /StoreModel adapter requires storage/)
      end
    end

    context "when storage column is NOT specified" do
      let(:storage_config) { {} }

      it "raises ArgumentError" do
        expect {
          StoreModelTestModel.setting :invalid_setting, type: :store_model, storage: storage_config
        }.to raise_error(ArgumentError, /StoreModel adapter requires storage/)
      end
    end
  end

  # rubocop:disable RSpecGuide/CharacteristicsAndContexts
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
      context "when setting is false" do
        before { instance.update!(email_enabled: false) }

        it "changes to true" do
          instance.email_enabled_toggle!
          expect(instance.email_enabled).to be true
        end
      end

      context "when setting is true" do
        before { instance.update!(email_enabled: true) }

        it "changes to false" do
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
  # rubocop:enable RSpecGuide/CharacteristicsAndContexts

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

    context "when value has NOT changed" do
      let(:changed) { false }

      it "returns false" do
        expect(adapter.changed?(instance)).to be changed
      end
    end

    context "when StoreModel instance is nil" do
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

    context "when value has NOT changed" do
      let(:expected_value) { false }

      it "returns current value" do
        expect(adapter.was(instance)).to be expected_value
      end
    end

    context "when StoreModel instance is nil" do
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

    context "when value has NOT changed" do
      let(:expected_change) { nil }

      it "returns nil" do
        expect(adapter.change(instance)).to be expected_change
      end
    end

    context "when StoreModel instance is nil" do
      let(:instance) { StoreModelTestModel.create!(ai_settings: nil) }

      it "returns nil" do
        expect(adapter.change(instance)).to be_nil
      end
    end
  end

  # rubocop:disable RSpecGuide/CharacteristicsAndContexts
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

    describe "change tracking" do
      it "marks setting as changed" do
        instance.transcription = true
        expect(instance.transcription_changed?).to be true
      end

      it "tracks previous value" do
        instance.update!(transcription: true)
        instance.transcription = false
        expect(instance.transcription_was).to be true
      end

      it "tracks change array" do
        instance.update!(transcription: false)
        instance.transcription = true
        expect(instance.transcription_change).to eq([false, true])
      end
    end

    describe "persistence" do
      it "persists changes to database" do
        instance.transcription = true
        instance.save!
        expect(instance.reload.transcription).to be true
      end

      it "clears changes after save" do
        instance.transcription = true
        instance.save!
        expect(instance.transcription_changed?).to be false
      end
    end

    describe "multiple settings" do
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

      it "includes both settings in ai_settings changes" do
        expect(instance.ai_settings_changed?).to be true
      end
    end
  end
  # rubocop:enable RSpecGuide/CharacteristicsAndContexts

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
        model.rate_limit = 0
        model
      end

      it "returns the falsy value for boolean" do
        expect(instance.transcription).to be false
      end

      it "returns the falsy value for numeric" do
        expect(instance.rate_limit).to eq(0)
      end
    end

    context "when value is NOT set" do
      let(:instance) { StoreModelTestModel.new(ai_settings: AiSettings.new) }

      it "returns default for boolean setting" do
        expect(instance.transcription).to be false
      end

      it "returns default for numeric setting" do
        expect(instance.rate_limit).to eq(100)
      end
    end

    context "when StoreModel instance is nil" do
      let(:instance) { StoreModelTestModel.new(ai_settings: nil) }

      it "returns nil for setting access" do
        expect(instance.transcription).to be_nil
      end
    end
  end
end
