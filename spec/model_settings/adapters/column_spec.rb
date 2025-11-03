# frozen_string_literal: true

require "spec_helper"

# rubocop:disable RSpecGuide/MinimumBehavioralCoverage
RSpec.describe ModelSettings::Adapters::Column, type: :model do
  # Create a fresh test model class for each test
  let(:model_class) do
    Class.new(TestModel) do
      def self.name
        "TestModelWithSettings"
      end

      include ModelSettings::DSL

      setting :enabled, type: :column
      setting :premium_mode, type: :column, default: false
    end
  end

  describe "#setup!" do
    context "when setting is defined" do
      let(:instance) { model_class.new }

      it "creates all helper methods", :aggregate_failures do
        expect(instance).to respond_to(:enabled_enable!)
        expect(instance).to respond_to(:enabled_disable!)
        expect(instance).to respond_to(:enabled_toggle!)
        expect(instance).to respond_to(:enabled_enabled?)
        expect(instance).to respond_to(:enabled_disabled?)
      end
    end

    context "when setting is NOT defined" do
      let(:model_without_setting) do
        Class.new(ActiveRecord::Base) do
          self.table_name = "test_models"
        end
      end

      it "does NOT create helper methods" do
        instance = model_without_setting.new
        expect(instance).not_to respond_to(:enabled_enable!)
      end
    end
  end

  # rubocop:disable RSpecGuide/MinimumBehavioralCoverage
  describe "helper methods" do
    let(:instance) { model_class.create! }

    describe "#setting_name_enable!" do
      subject(:enable_action) { instance.enabled_enable! }

      context "when setting is disabled" do
        before { instance.update!(enabled: false) }

        it "sets the setting to true" do
          enable_action
          expect(instance.enabled).to be true
        end

        it "marks the setting as changed" do
          enable_action
          expect(instance.enabled_changed?).to be true
        end
      end

      context "when setting is already enabled" do
        before { instance.update!(enabled: true) }

        it "keeps the setting as true" do
          enable_action
          expect(instance.enabled).to be true
        end

        it "does NOT mark as changed" do
          enable_action
          expect(instance.enabled_changed?).to be false
        end
      end
    end

    describe "#setting_name_disable!" do
      subject(:disable_action) { instance.enabled_disable! }

      context "when setting is enabled" do
        before { instance.update!(enabled: true) }

        it "sets the setting to false" do
          disable_action
          expect(instance.enabled).to be false
        end

        it "marks the setting as changed" do
          disable_action
          expect(instance.enabled_changed?).to be true
        end
      end

      context "when setting is already disabled" do
        before { instance.update!(enabled: false) }

        it "keeps the setting as false" do
          disable_action
          expect(instance.enabled).to be false
        end

        it "does NOT mark as changed" do
          disable_action
          expect(instance.enabled_changed?).to be false
        end
      end
    end

    describe "#setting_name_toggle!" do
      subject(:toggle_action) { instance.enabled_toggle! }

      context "when setting is disabled" do
        before { instance.update!(enabled: false) }

        it "enables the setting" do
          toggle_action
          expect(instance.enabled).to be true
        end
      end

      context "when setting is enabled" do
        before { instance.update!(enabled: true) }

        it "disables the setting" do
          toggle_action
          expect(instance.enabled).to be false
        end
      end
    end

    describe "#setting_name_enabled?" do
      subject(:enabled_query) { instance.enabled_enabled? }

      context "when setting is true" do
        before { instance.update!(enabled: true) }

        it "returns true" do
          expect(enabled_query).to be true
        end
      end

      context "when setting is false" do
        before { instance.update!(enabled: false) }

        it "returns false" do
          expect(enabled_query).to be false
        end
      end
    end

    describe "#setting_name_disabled?" do
      subject(:disabled_query) { instance.enabled_disabled? }

      context "when setting is false" do
        before { instance.update!(enabled: false) }

        it "returns true" do
          expect(disabled_query).to be true
        end
      end

      context "when setting is true" do
        before { instance.update!(enabled: true) }

        it "returns false" do
          expect(disabled_query).to be false
        end
      end
    end
  end
  # rubocop:enable RSpecGuide/MinimumBehavioralCoverage

  describe "#read" do
    subject(:read_value) { adapter.read(instance) }

    let(:adapter) { described_class.new(model_class, model_class.find_setting(:enabled)) }

    context "when value is true" do
      let(:instance) { model_class.new(enabled: true) }

      it "reads true" do
        expect(read_value).to be true
      end
    end

    context "when value is false" do
      let(:instance) { model_class.new(enabled: false) }

      it "reads false" do
        expect(read_value).to be false
      end
    end
  end

  describe "#write" do
    let(:adapter) { described_class.new(model_class, model_class.find_setting(:enabled)) }

    context "when writing true" do
      subject(:write_action) { adapter.write(instance, true) }

      let(:instance) { model_class.new }

      it "sets value to true" do
        write_action
        expect(instance.enabled).to be true
      end

      it "marks as changed" do
        write_action
        expect(instance.enabled_changed?).to be true
      end
    end

    context "when writing false" do
      subject(:write_action) { adapter.write(instance, false) }

      let(:instance) { model_class.create!(enabled: true) }

      it "sets value to false" do
        write_action
        expect(instance.enabled).to be false
      end

      it "marks as changed" do
        write_action
        expect(instance.enabled_changed?).to be true
      end
    end
  end

  describe "#changed?" do
    let(:instance) { model_class.new }
    let(:adapter) { described_class.new(model_class, model_class.find_setting(:enabled)) }

    context "when value has changed" do
      before { instance.enabled = true }

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
  end

  describe "#was" do
    subject(:previous_value) { adapter.was(instance) }

    let(:adapter) { described_class.new(model_class, model_class.find_setting(:enabled)) }

    context "when value has changed" do
      let(:instance) { model_class.create!(enabled: false) }

      before { instance.enabled = true } # value changed

      it "returns previous value" do
        expect(previous_value).to be false
      end
    end

    context "when value has NOT changed" do
      let(:instance) { model_class.create!(enabled: true) } # create different instance to avoid the same expectation

      it "returns current value" do
        expect(previous_value).to be true
      end
    end
  end

  describe "#change" do
    subject(:change) { adapter.change(instance) }

    let(:instance) { model_class.create!(enabled: false) }
    let(:adapter) { described_class.new(model_class, model_class.find_setting(:enabled)) }

    context "when value has changed" do
      before { instance.enabled = true }

      it "returns [old, new] array" do
        expect(change).to eq([false, true])
      end
    end

    # rubocop:disable RSpecGuide/ContextSetup
    context "but when value has NOT changed" do  # No changes - testing default state
      it "returns nil" do
        expect(change).to be_nil
      end
    end
    # rubocop:enable RSpecGuide/ContextSetup
  end

  describe "integration with ActiveRecord dirty tracking" do
    let(:instance) { model_class.create!(enabled: false, premium_mode: false) }

    context "when single setting changes" do
      before { instance.enabled = true }

      it "marks setting as changed" do
        expect(instance.enabled_changed?).to be true
      end

      it "tracks previous value" do
        expect(instance.enabled_was).to be false
      end

      it "returns change array" do
        expect(instance.enabled_change).to eq([false, true])
      end

      context "and saved" do
        before { instance.save! }

        it "persists to database" do
          reloaded = model_class.find(instance.id)
          expect(reloaded.enabled).to be true
        end

        it "clears changed flag" do
          expect(instance.enabled_changed?).to be false
        end
      end
    end

    context "when multiple settings change" do
      before do
        instance.enabled = true
        instance.premium_mode = true
      end

      it "tracks all changed settings" do
        expect(instance.changed).to match_array(["enabled", "premium_mode"])
      end
    end
  end

  # rubocop:disable RSpecGuide/MinimumBehavioralCoverage
  describe "boolean validation" do
    let(:instance) { model_class.new }
    let(:adapter) { described_class.new(model_class, model_class.find_setting(:enabled)) }

    # Characteristic 1: Value type
    it "accepts true", :aggregate_failures do
      adapter.write(instance, true)
      expect(instance).to be_valid
      expect(instance.enabled).to be true
    end

    it "accepts false", :aggregate_failures do
      adapter.write(instance, false)
      expect(instance).to be_valid
      expect(instance.enabled).to be false
    end

    it "accepts nil", :aggregate_failures do
      adapter.write(instance, nil)
      expect(instance).to be_valid
      expect(instance.enabled).to be_nil
    end

    context "but with NOT valid boolean" do
      let(:invalid_value_scenarios) { [:string, :integer, :array, :hash] }

      context "with string value" do
        before { adapter.write(instance, "true") }

        it "marks record as invalid" do
          expect(instance).not_to be_valid
        end

        it "includes error message" do
          instance.valid?
          expect(instance.errors[:enabled]).to include(match(/must be true or false.*got: "true"/))
        end
      end

      context "with integer value" do
        before { adapter.write(instance, 1) }

        it "marks record as invalid" do
          expect(instance).not_to be_valid
        end

        it "includes error message" do
          instance.valid?
          expect(instance.errors[:enabled]).to include(match(/must be true or false.*got: 1/))
        end
      end

      context "with array value" do
        before { adapter.write(instance, []) }

        it "marks record as invalid" do
          expect(instance).not_to be_valid
        end

        it "includes error message" do
          instance.valid?
          expect(instance.errors[:enabled]).to include(match(/must be true or false.*got: \[\]/))
        end
      end

      context "with hash value" do
        before { adapter.write(instance, {}) }

        it "marks record as invalid" do
          expect(instance).not_to be_valid
        end

        it "includes error message" do
          instance.valid?
          expect(instance.errors[:enabled]).to include(match(/must be true or false.*got: \{\}/))
        end
      end
    end

    # Characteristic 2: Assignment method
    describe "validation through Rails methods" do
      context "with valid value" do
        let(:valid_value) { true }

        it "accepts update() with boolean", :aggregate_failures do
          result = instance.update(enabled: valid_value)
          expect(result).to be true
          expect(instance.enabled).to eq(valid_value)
        end
      end

      context "with invalid value" do
        let(:invalid_value) { "invalid" }

        it "rejects direct assignment" do
          instance.enabled = invalid_value
          expect(instance).not_to be_valid
        end

        it "rejects update() and returns false" do
          result = instance.update(enabled: invalid_value)
          expect(result).to be false
        end

        it "rejects update!() with exception" do
          expect {
            instance.update!(enabled: invalid_value)
          }.to raise_error(ActiveRecord::RecordInvalid)
        end
      end
    end
  end

  describe "BooleanValueValidator integration" do
    let(:validated_model_class) do
      Class.new(TestModel) do
        def self.name
          "ValidatedColumnModel"
        end

        include ModelSettings::DSL

        setting :enabled, type: :column
        validates :enabled, boolean_value: true
      end
    end

    context "with valid boolean values" do
      it "accepts true" do
        instance = validated_model_class.new(enabled: true)
        expect(instance).to be_valid
      end

      it "accepts false" do
        instance = validated_model_class.new(enabled: false)
        expect(instance).to be_valid
      end
    end

    context "with invalid string values" do
      it "rejects string '1'" do
        instance = validated_model_class.new(enabled: "1")
        expect(instance).not_to be_valid
        expect(instance.errors[:enabled]).to be_present
      end

      it "rejects string 'true'" do
        instance = validated_model_class.new(enabled: "true")
        expect(instance).not_to be_valid
        expect(instance.errors[:enabled]).to be_present
      end

      it "rejects string 'yes'" do
        instance = validated_model_class.new(enabled: "yes")
        expect(instance).not_to be_valid
        expect(instance.errors[:enabled]).to be_present
      end
    end

    context "with invalid integer values" do
      it "rejects integer 0" do
        instance = validated_model_class.new(enabled: 0)
        expect(instance).not_to be_valid
        expect(instance.errors[:enabled]).to be_present
      end

      it "rejects integer 1" do
        instance = validated_model_class.new(enabled: 1)
        expect(instance).not_to be_valid
        expect(instance.errors[:enabled]).to be_present
      end
    end
  end
  # rubocop:enable RSpecGuide/MinimumBehavioralCoverage
end
