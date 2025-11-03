# frozen_string_literal: true

require "spec_helper"

# Cross-adapter validation consistency tests
# Ensure validators work consistently across all storage adapters
RSpec.describe "Cross-Adapter Validation Consistency" do
  describe "BooleanValueValidator consistency" do
    let(:invalid_value) { "invalid" }
    let(:valid_value) { true }

    context "with valid value" do
      it "accepts value across all adapters" do
        # Column adapter
        column_model = Class.new(TestModel) do
          def self.name
            "ColumnValidModel"
          end

          include ModelSettings::DSL

          setting :feature, type: :column
          validates :feature, boolean_value: true
        end

        # JSON adapter
        json_model = Class.new(TestModel) do
          def self.name
            "JsonValidModel"
          end

          include ModelSettings::DSL

          setting :feature, type: :json, storage: {column: :settings_data}
          validates :feature, boolean_value: true
        end

        # Both adapters should accept the same valid value
        column_instance = column_model.new(feature: valid_value)
        expect(column_instance).to be_valid

        json_instance = json_model.new(feature: valid_value)
        expect(json_instance).to be_valid
      end
    end

    context "but with invalid value" do
      it "rejects value across all adapters" do
        # Column adapter
        column_model = Class.new(TestModel) do
          def self.name
            "ColumnValidationModel"
          end

          include ModelSettings::DSL

          setting :feature, type: :column
          validates :feature, boolean_value: true
        end

        # JSON adapter (simple, not nested)
        json_model = Class.new(TestModel) do
          def self.name
            "JsonValidationModel"
          end

          include ModelSettings::DSL

          setting :feature, type: :json, storage: {column: :settings_data}
          validates :feature, boolean_value: true
        end

        # Both adapters should reject the same invalid value
        column_instance = column_model.new(feature: invalid_value)
        expect(column_instance).not_to be_valid

        json_instance = json_model.new(feature: invalid_value)
        expect(json_instance).not_to be_valid
      end

      it "shows same error message across all adapters" do
        # Column adapter
        column_model = Class.new(TestModel) do
          def self.name
            "ColumnErrorModel"
          end

          include ModelSettings::DSL

          setting :feature, type: :column
          validates :feature, boolean_value: true
        end

        # JSON adapter
        json_model = Class.new(TestModel) do
          def self.name
            "JsonErrorModel"
          end

          include ModelSettings::DSL

          setting :feature, type: :json, storage: {column: :settings_data}
          validates :feature, boolean_value: true
        end

        column_instance = column_model.new(feature: invalid_value)
        column_instance.valid?
        column_error = column_instance.errors[:feature].first

        json_instance = json_model.new(feature: invalid_value)
        json_instance.valid?
        json_error = json_instance.errors[:feature].first

        # Error messages should be consistent
        expect(column_error).to match(/must be true or false/)
        expect(json_error).to match(/must be true or false/)
      end
    end
  end

  describe "Default value consistency" do
    it "default values work consistently across adapters" do
      # Column adapter with default
      column_model = Class.new(TestModel) do
        def self.name
          "ColumnDefaultModel"
        end

        include ModelSettings::DSL

        setting :feature, type: :column, default: false
      end

      # JSON adapter with default
      json_model = Class.new(TestModel) do
        def self.name
          "JsonDefaultModel"
        end

        include ModelSettings::DSL

        setting :feature, type: :json, storage: {column: :settings_data}, default: false
      end

      # Both should have same default value
      column_instance = column_model.new
      expect(column_instance.feature).to eq(false)

      json_instance = json_model.new
      expect(json_instance.feature).to eq(false)
    end
  end

  describe "Change tracking consistency" do
    it "dirty tracking works consistently across adapters" do
      # Column adapter
      column_model = Class.new(TestModel) do
        def self.name
          "ColumnChangeModel"
        end

        include ModelSettings::DSL

        setting :feature, type: :column
      end

      # JSON adapter
      json_model = Class.new(TestModel) do
        def self.name
          "JsonChangeModel"
        end

        include ModelSettings::DSL

        setting :feature, type: :json, storage: {column: :settings_data}
      end

      # Both should track changes consistently
      column_instance = column_model.create!(feature: false)
      column_instance.feature = true
      expect(column_instance.feature_changed?).to be true
      expect(column_instance.feature_was).to eq(false)

      json_instance = json_model.create!(feature: false)
      json_instance.feature = true
      expect(json_instance.feature_changed?).to be true
      expect(json_instance.feature_was).to eq(false)
    end
  end

  describe "Helper methods consistency" do
    it "enable/disable/toggle helpers work across adapters" do
      # Column adapter
      column_model = Class.new(TestModel) do
        def self.name
          "ColumnHelperModel"
        end

        include ModelSettings::DSL

        setting :feature, type: :column
      end

      # JSON adapter
      json_model = Class.new(TestModel) do
        def self.name
          "JsonHelperModel"
        end

        include ModelSettings::DSL

        setting :feature, type: :json, storage: {column: :settings_data}
      end

      # Both should have same helper methods
      column_instance = column_model.new
      column_instance.feature_enable!
      expect(column_instance.feature).to be true

      json_instance = json_model.new
      json_instance.feature_enable!
      expect(json_instance.feature).to be true

      # Disable
      column_instance.feature_disable!
      expect(column_instance.feature).to be false

      json_instance.feature_disable!
      expect(json_instance.feature).to be false

      # Toggle
      column_instance.feature_toggle!
      expect(column_instance.feature).to be true

      json_instance.feature_toggle!
      expect(json_instance.feature).to be true
    end
  end

  describe "Query method consistency" do
    it "enabled?/disabled? queries work across adapters" do
      # Column adapter
      column_model = Class.new(TestModel) do
        def self.name
          "ColumnQueryModel"
        end

        include ModelSettings::DSL

        setting :feature, type: :column
      end

      # JSON adapter
      json_model = Class.new(TestModel) do
        def self.name
          "JsonQueryModel"
        end

        include ModelSettings::DSL

        setting :feature, type: :json, storage: {column: :settings_data}
      end

      # Both should have consistent query methods
      column_instance = column_model.new(feature: true)
      expect(column_instance.feature_enabled?).to be true
      expect(column_instance.feature_disabled?).to be false

      json_instance = json_model.new(feature: true)
      expect(json_instance.feature_enabled?).to be true
      expect(json_instance.feature_disabled?).to be false

      # Test false state
      column_instance.feature = false
      expect(column_instance.feature_enabled?).to be false
      expect(column_instance.feature_disabled?).to be true

      json_instance.feature = false
      expect(json_instance.feature_enabled?).to be false
      expect(json_instance.feature_disabled?).to be true
    end
  end
end
