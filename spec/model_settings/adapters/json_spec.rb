# frozen_string_literal: true

require "spec_helper"

# rubocop:disable RSpecGuide/MinimumBehavioralCoverage
RSpec.describe ModelSettings::Adapters::Json do
  before do
    # Define the model class (table already exists from active_record.rb)
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

      it "creates all helper methods", :aggregate_failures do
        expect(instance).to respond_to(:notifications_enabled_enable!)
        expect(instance).to respond_to(:notifications_enabled_disable!)
        expect(instance).to respond_to(:notifications_enabled_toggle!)
        expect(instance).to respond_to(:notifications_enabled_enabled?)
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

      it "creates parent setting accessors", :aggregate_failures do
        expect(instance).to respond_to(:features)
        expect(instance).to respond_to(:features=)
      end

      it "creates nested settings interface", :aggregate_failures do
        expect(instance).to respond_to(:billing_enabled)
        expect(instance).to respond_to(:billing_enabled=)
        expect(instance).to respond_to(:billing_enabled_enable!)
        expect(instance).to respond_to(:billing_enabled_disable!)
        expect(instance).to respond_to(:billing_enabled_toggle!)
        expect(instance).to respond_to(:speech_recognition)
        expect(instance).to respond_to(:speech_recognition=)
        expect(instance).to respond_to(:speech_recognition_enable!)
      end
    end

    context "when storage configuration is missing" do
      let(:storage_config) { nil }

      it "raises ArgumentError" do
        expect {
          JsonTestModel.setting :invalid_setting, type: :json, storage: storage_config
        }.to raise_error(ArgumentError, /JSON adapter requires a storage column/m)
      end
    end

    context "when storage column is NOT specified" do
      let(:storage_config) { {} }

      it "raises ArgumentError" do
        expect {
          JsonTestModel.setting :invalid_setting, type: :json, storage: storage_config
        }.to raise_error(ArgumentError, /JSON adapter requires a storage column/m)
      end
    end
  end

  # rubocop:disable RSpecGuide/MinimumBehavioralCoverage
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
      context "when setting is disabled" do
        before { instance.update!(notifications_enabled: false) }

        it "enables the setting" do
          instance.notifications_enabled_toggle!
          expect(instance.notifications_enabled).to be true
        end
      end

      context "when setting is enabled" do
        before { instance.update!(notifications_enabled: true) }

        it "disables the setting" do
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
  # rubocop:enable RSpecGuide/MinimumBehavioralCoverage

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

    # rubocop:disable RSpecGuide/ContextSetup
    context "but when value has NOT changed" do  # No changes - testing default state
      it "returns false" do
        expect(adapter.changed?(instance)).to be false
      end
    end
    # rubocop:enable RSpecGuide/ContextSetup
  end

  describe "#was" do
    before do
      JsonTestModel.setting :api_enabled,
        type: :json,
        storage: {column: :settings}
    end

    let(:adapter) { described_class.new(JsonTestModel, JsonTestModel.find_setting(:api_enabled)) }

    context "when value has changed" do
      let(:instance) { JsonTestModel.create!(api_enabled: false) }

      before { instance.api_enabled = true }

      it "returns previous value" do
        expect(adapter.was(instance)).to be false
      end
    end

    context "when value has NOT changed" do
      let(:instance) { JsonTestModel.create!(api_enabled: true) }

      it "returns current value" do
        expect(adapter.was(instance)).to be true
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

    # rubocop:disable RSpecGuide/ContextSetup
    context "but when value has NOT changed" do  # No changes - testing default state
      it "returns nil" do
        expect(adapter.change(instance)).to be_nil
      end
    end
    # rubocop:enable RSpecGuide/ContextSetup
  end

  describe "integration with ActiveRecord dirty tracking" do
    before do
      JsonTestModel.setting :feature_flags, type: :json, storage: {column: :features} do
        setting :analytics_enabled, default: false
        setting :reporting_enabled, default: false
      end
    end

    let(:instance) { JsonTestModel.create! }

    context "when single nested setting changes" do
      before { instance.analytics_enabled = true }

      it "marks setting as changed" do
        expect(instance.analytics_enabled_changed?).to be true
      end

      it "tracks previous value" do
        instance.update!(analytics_enabled: true)
        instance.analytics_enabled = false
        expect(instance.analytics_enabled_was).to be true
      end

      it "returns change array" do
        instance.update!(analytics_enabled: false)
        instance.analytics_enabled = true
        expect(instance.analytics_enabled_change).to eq([false, true])
      end

      context "and saved" do
        before { instance.save! }

        it "persists and clears dirty tracking", :aggregate_failures do
          expect(instance.reload.analytics_enabled).to be true
          expect(instance.analytics_enabled_changed?).to be false
        end
      end
    end

    context "when multiple nested settings change" do
      before do
        instance.analytics_enabled = true
        instance.reporting_enabled = true
      end

      it "tracks all changed nested settings" do
        expect(instance.features_changed?).to be true
      end
    end
  end

  describe "default values" do
    before do
      # Table already exists from active_record.rb
      stub_const("JsonDefaultTestModel", Class.new(ActiveRecord::Base) do
        include ModelSettings::DSL

        serialize :settings, coder: JSON

        setting :notifications_enabled,
          type: :json,
          storage: {column: :settings},
          default: true
      end)
    end

    context "when value is set to falsy value" do
      let(:instance) do
        model = JsonDefaultTestModel.new
        model.notifications_enabled = false
        model
      end

      it "returns the falsy value for boolean" do
        expect(instance.notifications_enabled).to be false
      end
    end

    context "when value is NOT set" do
      let(:instance) { JsonDefaultTestModel.new }

      it "returns default for boolean setting" do
        expect(instance.notifications_enabled).to be true
      end
    end
  end

  # rubocop:disable RSpecGuide/MinimumBehavioralCoverage, RSpecGuide/InvariantExamples
  describe "boolean validation" do
    let(:model_class) do
      Class.new(ActiveRecord::Base) do
        self.table_name = "test_models"
        include ModelSettings::DSL

        # Simple boolean JSON setting for validation tests
        setting :simple_feature, type: :json, storage: {column: :settings_data}, default: false

        # Parent setting with nested settings
        setting :features, type: :json, storage: {column: :settings_data} do
          setting :analytics_enabled, default: false
        end

        compile_settings!
      end
    end

    let(:instance) { model_class.create! }
    let(:adapter) { described_class.new(model_class, model_class.find_setting(:simple_feature)) }

    # Characteristic: Value type
    it "accepts true", :aggregate_failures do
      expect { instance.simple_feature = true }.not_to raise_error
      expect(instance.simple_feature).to be true
    end

    it "accepts false", :aggregate_failures do
      expect { instance.simple_feature = false }.not_to raise_error
      expect(instance.simple_feature).to be false
    end

    it "accepts nil", :aggregate_failures do
      instance.simple_feature = nil
      expect(instance).to be_valid
      expect(instance.simple_feature).to be_nil
    end

    context "but with string value" do
      before { instance.simple_feature = "enabled" }

      it "marks record as invalid" do
        expect(instance).not_to be_valid
      end
    end

    context "but with array value" do
      before { instance.simple_feature = [] }

      it "marks record as invalid" do
        expect(instance).not_to be_valid
      end
    end

    # rubocop:disable RSpecGuide/MinimumBehavioralCoverage
    describe "nested setting validation" do
      it "accepts true", :aggregate_failures do
        expect { instance.analytics_enabled = true }.not_to raise_error
        expect(instance.analytics_enabled).to be true
      end

      it "accepts false", :aggregate_failures do
        expect { instance.analytics_enabled = false }.not_to raise_error
        expect(instance.analytics_enabled).to be false
      end

      it "accepts nil", :aggregate_failures do
        instance.analytics_enabled = nil
        expect(instance).to be_valid
        expect(instance.analytics_enabled).to be_nil
      end

      context "but with NOT valid boolean" do
        before { instance.analytics_enabled = "yes" }

        it "marks record as invalid" do
          expect(instance).not_to be_valid
        end
      end
    end
    # rubocop:enable RSpecGuide/MinimumBehavioralCoverage

    # rubocop:disable RSpecGuide/MinimumBehavioralCoverage
    describe "adapter write validation" do
      it "accepts true value", :aggregate_failures do
        expect { adapter.write(instance, true) }.not_to raise_error
        expect(instance.simple_feature).to be true
      end

      it "accepts false value", :aggregate_failures do
        expect { adapter.write(instance, false) }.not_to raise_error
        expect(instance.simple_feature).to be false
      end

      context "but with NOT valid values" do
        before { adapter.write(instance, "value") }

        it "marks record as invalid" do
          expect(instance).not_to be_valid
        end
      end
    end
    # rubocop:enable RSpecGuide/MinimumBehavioralCoverage
  end

  # rubocop:disable RSpecGuide/MinimumBehavioralCoverage
  describe "array membership pattern" do
    let(:model_class) do
      Class.new(ActiveRecord::Base) do
        def self.name
          "TestArrayModel"
        end

        self.table_name = "test_models"
        include ModelSettings::DSL

        setting :feature_a,
          type: :json,
          storage: {column: :preferences, array: true}
      end
    end

    # rubocop:disable RSpecGuide/MinimumBehavioralCoverage
    describe "getter" do
      it "returns false when value not in array" do
        instance = model_class.new(preferences: [])
        expect(instance.feature_a).to be false
      end

      it "returns true when value in array" do
        instance = model_class.new(preferences: ["feature_a"])
        expect(instance.feature_a).to be true
      end

      it "returns false when column is nil" do
        instance = model_class.new(preferences: nil)
        expect(instance.feature_a).to be false
      end

      it "returns false when other values in array" do
        instance = model_class.new(preferences: ["other_feature"])
        expect(instance.feature_a).to be false
      end
    end

    # rubocop:disable RSpecGuide/MinimumBehavioralCoverage
    describe "setter" do
      it "adds value to array when set to true" do
        instance = model_class.new(preferences: [])
        instance.feature_a = true
        expect(instance.preferences).to eq(["feature_a"])
      end

      it "removes value from array when set to false" do
        instance = model_class.new(preferences: ["feature_a"])
        instance.feature_a = false
        expect(instance.preferences).to eq([])
      end

      it "does not add duplicate when already present" do
        instance = model_class.new(preferences: ["feature_a"])
        instance.feature_a = true
        expect(instance.preferences).to eq(["feature_a"])
      end

      it "initializes array when nil" do
        instance = model_class.new(preferences: nil)
        instance.feature_a = true
        expect(instance.preferences).to eq(["feature_a"])
      end

      it "preserves other values in array" do
        instance = model_class.new(preferences: ["other_feature"])
        instance.feature_a = true
        expect(instance.preferences).to include("other_feature", "feature_a")
      end
    end

    # rubocop:disable RSpecGuide/MinimumBehavioralCoverage
    describe "enable!/disable! helpers" do
      it "enable! adds value to array" do
        instance = model_class.new(preferences: [])
        instance.feature_a_enable!
        expect(instance.preferences).to eq(["feature_a"])
      end

      it "disable! removes value from array" do
        instance = model_class.new(preferences: ["feature_a"])
        instance.feature_a_disable!
        expect(instance.preferences).to eq([])
      end
    end

    # rubocop:disable RSpecGuide/MinimumBehavioralCoverage
    describe "dirty tracking" do
      it "tracks changes from false to true" do  # rubocop:disable RSpec/MultipleExpectations
        instance = model_class.create!(preferences: [])

        expect(instance.feature_a_changed?).to be false

        instance.feature_a = true

        expect(instance.feature_a_changed?).to be true
        expect(instance.feature_a_was).to be false
        expect(instance.feature_a_change).to eq([false, true])
      end

      it "tracks changes from true to false" do  # rubocop:disable RSpec/MultipleExpectations
        instance = model_class.create!(preferences: ["feature_a"])

        instance.feature_a = false

        expect(instance.feature_a_changed?).to be true
        expect(instance.feature_a_was).to be true
        expect(instance.feature_a_change).to eq([true, false])
      end

      it "does not track changes when value unchanged" do
        instance = model_class.create!(preferences: ["feature_a"])

        instance.feature_a = true

        expect(instance.feature_a_changed?).to be false
      end

      it "does not report change when other array values change" do
        instance = model_class.create!(preferences: ["feature_a"])

        instance.preferences << "other_feature"

        expect(instance.feature_a_changed?).to be false
      end
    end

    # rubocop:disable RSpecGuide/MinimumBehavioralCoverage
    describe "custom array_value" do
      let(:model_class) do
        Class.new(ActiveRecord::Base) do
          def self.name
            "TestArrayCustomModel"
          end

          self.table_name = "test_models"
          include ModelSettings::DSL

          setting :feature_b,
            type: :json,
            storage: {column: :preferences, array: true, array_value: "legacy_feature"}
        end
      end

      it "uses custom value in array" do
        instance = model_class.new(preferences: [])
        instance.feature_b = true
        expect(instance.preferences).to eq(["legacy_feature"])
      end

      it "checks custom value for getter" do
        instance = model_class.new(preferences: ["legacy_feature"])
        expect(instance.feature_b).to be true
      end

      it "does not match setting name" do
        instance = model_class.new(preferences: ["feature_b"])
        expect(instance.feature_b).to be false
      end
    end

    # rubocop:disable RSpecGuide/MinimumBehavioralCoverage
    describe "validation" do
      it "validates column is array type" do  # rubocop:disable RSpec/MultipleExpectations
        instance = model_class.new(preferences: "not_array")

        expect(instance.valid?).to be false
        expect(instance.errors[:preferences]).to include("must be an array")
      end

      it "allows nil" do
        instance = model_class.new(preferences: nil)
        expect(instance.valid?).to be true
      end

      it "allows empty array" do
        instance = model_class.new(preferences: [])
        expect(instance.valid?).to be true
      end
    end

    # rubocop:disable RSpecGuide/MinimumBehavioralCoverage
    describe "multiple settings, same column" do
      let(:model_class) do
        Class.new(ActiveRecord::Base) do
          def self.name
            "TestMultiArrayModel"
          end

          self.table_name = "test_models"
          include ModelSettings::DSL

          setting :feature_a,
            type: :json,
            storage: {column: :preferences, array: true}

          setting :feature_b,
            type: :json,
            storage: {column: :preferences, array: true}
        end
      end

      it "works independently" do  # rubocop:disable RSpec/MultipleExpectations
        instance = model_class.new(preferences: [])

        instance.feature_a = true
        expect(instance.preferences).to eq(["feature_a"])
        expect(instance.feature_a).to be true
        expect(instance.feature_b).to be false

        instance.feature_b = true
        expect(instance.preferences).to include("feature_a", "feature_b")
        expect(instance.feature_a).to be true
        expect(instance.feature_b).to be true
      end

      it "tracks changes independently" do  # rubocop:disable RSpec/MultipleExpectations
        instance = model_class.create!(preferences: [])

        instance.feature_a = true

        expect(instance.feature_a_changed?).to be true
        expect(instance.feature_b_changed?).to be false
      end
    end

    # rubocop:disable RSpecGuide/MinimumBehavioralCoverage
    describe "persistence" do
      it "persists array changes" do  # rubocop:disable RSpec/MultipleExpectations
        instance = model_class.create!(preferences: [])

        instance.feature_a = true
        instance.save!

        instance.reload
        expect(instance.feature_a).to be true
        expect(instance.preferences).to eq(["feature_a"])
      end
    end
  end

  describe "BooleanValueValidator integration" do
    let(:validated_model_class) do
      Class.new(TestModel) do
        def self.name
          "ValidatedJsonModel"
        end

        include ModelSettings::DSL

        setting :features, type: :json, storage: {column: :settings} do
          setting :strict_mode
        end

        validates :strict_mode, boolean_value: true
      end
    end

    # rubocop:disable RSpec/MultipleExpectations
    it "accepts valid boolean values" do
      instance = validated_model_class.new
      instance.strict_mode = true
      expect(instance).to be_valid

      instance.strict_mode = false
      expect(instance).to be_valid
    end
    # rubocop:enable RSpec/MultipleExpectations

    it "rejects string '1'" do
      instance = validated_model_class.new
      instance.strict_mode = "1"
      expect(instance).not_to be_valid
      expect(instance.errors[:strict_mode]).to be_present
    end

    it "rejects string 'true'" do
      instance = validated_model_class.new
      instance.strict_mode = "true"
      expect(instance).not_to be_valid
      expect(instance.errors[:strict_mode]).to be_present
    end

    it "rejects integer 0" do
      instance = validated_model_class.new
      instance.strict_mode = 0
      expect(instance).not_to be_valid
      expect(instance.errors[:strict_mode]).to be_present
    end

    it "rejects integer 1" do
      instance = validated_model_class.new
      instance.strict_mode = 1
      expect(instance).not_to be_valid
      expect(instance.errors[:strict_mode]).to be_present
    end
  end
  # rubocop:enable RSpecGuide/MinimumBehavioralCoverage, RSpecGuide/InvariantExamples
end
