# frozen_string_literal: true

require "spec_helper"

RSpec.describe ModelSettings::Query do
  let(:model_class) do
    Class.new(TestModel) do
      def self.name
        "QueryTestModel"
      end

      include ModelSettings::DSL

      # Settings with various metadata for testing
      setting :security_enabled,
        type: :column,
        default: false,
        metadata: {category: "security", tier: "premium"}

      setting :analytics_enabled,
        type: :column,
        default: false,
        metadata: {category: "analytics", tier: "free"}

      setting :premium_mode,
        type: :column,
        default: false,
        metadata: {category: "billing", tier: "premium", plan_requirement: "pro"}

      setting :notifications,
        type: :column,
        default: true,
        metadata: {category: "communication"}

      # JSON storage setting
      setting :features,
        type: :json,
        storage: {column: :settings_data},
        metadata: {category: "features"}

      # Setting with callbacks
      setting :email_enabled,
        type: :column,
        default: false,
        before_enable: :check_email,
        after_enable: :notify_enabled,
        metadata: {category: "communication"}

      # Setting with validation
      setting :api_access,
        type: :column,
        default: false,
        validate_with: :check_api_quota,
        metadata: {category: "api", tier: "premium"}

      def check_email; end
      def notify_enabled; end
      def check_api_quota; end
    end
  end

  # Shared context for model without complex settings
  let(:simple_model) do
    Class.new(TestModel) do
      def self.name
        "SimpleModel"
      end

      include ModelSettings::DSL
      setting :enabled, type: :column
    end
  end

  describe ".settings_where" do
    it "returns matching settings with single key-value" do
      results = model_class.settings_where(metadata: {category: "security"})
      expect(results.map(&:name)).to eq([:security_enabled])
    end

    it "returns settings matching all criteria with multiple key-values" do
      results = model_class.settings_where(metadata: {category: "analytics", tier: "free"})
      expect(results.map(&:name)).to eq([:analytics_enabled])
    end

    context "but when metadata does NOT match" do
      it "returns empty array" do
        results = model_class.settings_where(metadata: {category: "nonexistent"})
        expect(results).to be_empty
      end
    end

    context "but when no metadata provided" do
      it "returns all settings" do
        results = model_class.settings_where(metadata: {})
        expect(results.size).to eq(model_class.all_settings_recursive.size)
      end
    end
  end

  describe ".settings_with_metadata_key" do
    it "returns all settings with the key regardless of value" do
      results = model_class.settings_with_metadata_key(:tier)
      tiers = results.map { |s| s.metadata[:tier] }.uniq

      aggregate_failures do
        expect(results.map(&:name)).to include(:security_enabled, :analytics_enabled, :premium_mode, :api_access)
        expect(tiers).to include("premium", "free")
      end
    end

    context "but when key does NOT exist" do
      it "returns empty array" do
        results = model_class.settings_with_metadata_key(:nonexistent_key)
        expect(results).to be_empty
      end
    end
  end

  describe ".settings_by_type" do
    it "returns settings of :column type" do
      results = model_class.settings_by_type(:column)
      expect(results.map(&:name)).to include(:security_enabled, :analytics_enabled, :premium_mode)
    end

    it "returns settings of :json type" do
      results = model_class.settings_by_type(:json)
      expect(results.map(&:name)).to eq([:features])
    end

    context "but when type does NOT exist" do
      it "returns empty array for :store_model type" do
        results = model_class.settings_by_type(:store_model)
        expect(results).to be_empty
      end

      it "returns empty array for invalid type" do
        results = model_class.settings_by_type(:invalid_type)
        expect(results).to be_empty
      end
    end
  end

  describe ".settings_with_callbacks" do
    it "returns settings with specific callback type" do
      results = model_class.settings_with_callbacks(:before_enable)
      expect(results.map(&:name)).to eq([:email_enabled])
    end

    it "returns all settings with any callback when type is nil" do
      results = model_class.settings_with_callbacks
      expect(results.map(&:name)).to eq([:email_enabled])
    end

    context "but when callback type does NOT exist" do
      it "returns empty array" do
        results = model_class.settings_with_callbacks(:nonexistent_callback)
        expect(results).to be_empty
      end
    end
  end

  describe ".settings_with_validation" do
    it "returns settings with validate_with option" do
      results = model_class.settings_with_validation
      expect(results.map(&:name)).to eq([:api_access])
    end

    context "but when no settings have validation" do
      it "returns empty array" do
        expect(simple_model.settings_with_validation).to be_empty
      end
    end
  end

  describe ".settings_with_default" do
    it "returns settings with matching default value" do
      results = model_class.settings_with_default(false)
      expect(results.map(&:name)).to include(:security_enabled, :analytics_enabled, :premium_mode)
    end

    it "correctly handles falsy defaults (false and nil)" do
      aggregate_failures "falsy defaults" do
        false_results = model_class.settings_with_default(false)
        expect(false_results).not_to be_empty

        nil_results = model_class.settings_with_default(nil)
        expect(nil_results.map(&:name)).to eq([:features])
      end
    end

    context "but when default value does NOT match" do
      it "returns empty array" do
        results = model_class.settings_with_default(:nonexistent_default)
        expect(results).to be_empty
      end
    end
  end

  describe ".settings_grouped_by_metadata" do
    it "groups settings by metadata value" do
      results = model_class.settings_grouped_by_metadata(:category)

      aggregate_failures "grouped by category" do
        expect(results["security"].map(&:name)).to eq([:security_enabled])
        expect(results["analytics"].map(&:name)).to eq([:analytics_enabled])
        expect(results["billing"].map(&:name)).to eq([:premium_mode])
        expect(results["communication"].map(&:name)).to include(:notifications, :email_enabled)
      end
    end

    context "but when metadata key does NOT exist" do
      it "places all settings in :ungrouped group" do
        results = model_class.settings_grouped_by_metadata(:nonexistent_key)

        aggregate_failures do
          expect(results.keys).to eq([:ungrouped])
          expect(results[:ungrouped].size).to eq(model_class.all_settings_recursive.size)
        end
      end
    end
  end

  describe ".settings_matching" do
    it "returns matching settings based on block condition" do
      results = model_class.settings_matching { |s| s.name.to_s.include?("enabled") }
      expect(results.map(&:name)).to include(:security_enabled, :analytics_enabled, :email_enabled)
    end

    it "applies block with complex condition to each setting" do
      results = model_class.settings_matching do |s|
        s.type == :column && s.metadata[:tier] == "premium"
      end
      expect(results.map(&:name)).to include(:security_enabled, :premium_mode, :api_access)
    end

    context "but when block returns false for all settings" do
      it "returns empty array" do
        results = model_class.settings_matching { |_s| false }
        expect(results).to be_empty
      end
    end
  end

  describe ".settings_count" do
    it "returns total count with no criteria" do
      count = model_class.settings_count
      expect(count).to eq(model_class.all_settings_recursive.size)
    end

    it "counts settings by type" do
      count = model_class.settings_count(type: :column)
      expect(count).to eq(6) # All column settings: security_enabled, analytics_enabled, premium_mode, notifications, email_enabled, api_access
    end

    it "counts settings by metadata" do
      count = model_class.settings_count(metadata: {tier: "premium"})
      expect(count).to eq(3) # security_enabled, premium_mode, api_access
    end

    it "counts settings by deprecated status" do
      deprecated_model = Class.new(TestModel) do
        def self.name
          "DeprecatedModel"
        end

        include ModelSettings::DSL

        setting :old_feature, type: :column, deprecated: true
        setting :new_feature, type: :column
      end

      count = deprecated_model.settings_count(deprecated: true)
      expect(count).to eq(1)
    end

    it "counts settings with multiple criteria" do
      count = model_class.settings_count(
        type: :column,
        metadata: {tier: "premium"}
      )
      expect(count).to eq(3)
    end
  end
end
