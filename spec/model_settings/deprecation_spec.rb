# frozen_string_literal: true

require "spec_helper"

RSpec.describe ModelSettings::Deprecation do
  let(:model_class) do
    Class.new(TestModel) do
      def self.name
        "DeprecationTestModel"
      end

      include ModelSettings::DSL

      setting :enabled, type: :column, default: false

      setting :feature, # Use existing column
        type: :column,
        default: false,
        deprecated: "Use enabled instead",
        metadata: {
          deprecated_since: "2.0.0",
          replacement: :enabled
        }

      setting :premium_mode, # Use existing column
        type: :column,
        default: false,
        deprecated: true

      setting :notifications, # Use existing column
        type: :column,
        default: false
    end
  end

  let(:instance) { model_class.create! }

  # Shared context for model without deprecated settings
  let(:simple_model) do
    Class.new(TestModel) do
      def self.name
        "SimpleModel"
      end

      include ModelSettings::DSL
      setting :enabled, type: :column
    end
  end

  let(:simple_instance) { simple_model.create! }

  describe "ClassMethods" do
    describe ".deprecated_settings" do
      it "returns array of deprecated settings" do
        results = model_class.deprecated_settings
        expect(results.map(&:name)).to include(:feature, :premium_mode)
      end

      context "but when no deprecated settings" do
        it "returns empty array" do
          expect(simple_model.deprecated_settings).to be_empty
        end
      end
    end

    describe ".settings_deprecated_since" do
      context "when version matches" do
        it "returns settings deprecated since that version" do
          results = model_class.settings_deprecated_since("2.0.0")
          expect(results.map(&:name)).to eq([:feature])
        end
      end

      context "when version does NOT match" do
        it "returns empty array" do
          results = model_class.settings_deprecated_since("3.0.0")
          expect(results).to be_empty
        end
      end

      context "when deprecated_since NOT specified" do
        it "excludes those settings" do
          results = model_class.settings_deprecated_since("1.0.0")
          expect(results.map(&:name)).not_to include(:premium_mode)
        end
      end
    end

    describe ".setting_deprecated?" do
      context "when setting is deprecated" do
        it "returns true" do
          expect(model_class.setting_deprecated?(:feature)).to be true
        end
      end

      context "when setting is NOT deprecated" do
        it "returns false" do
          expect(model_class.setting_deprecated?(:enabled)).to be false
        end
      end

      context "when setting does NOT exist" do
        it "returns false" do
          expect(model_class.setting_deprecated?(:nonexistent)).to be false
        end
      end
    end

    describe ".deprecation_reason_for" do
      context "when setting has reason" do
        it "returns reason string" do
          reason = model_class.deprecation_reason_for(:feature)
          expect(reason).to eq("Use enabled instead")
        end
      end

      context "when setting deprecated without reason" do
        it "returns default message" do
          reason = model_class.deprecation_reason_for(:premium_mode)
          expect(reason).to eq("Setting is deprecated")
        end
      end

      context "when setting NOT deprecated" do
        it "returns nil" do
          reason = model_class.deprecation_reason_for(:enabled)
          expect(reason).to be_nil
        end
      end
    end

    describe ".deprecation_report" do
      it "returns comprehensive deprecation report" do
        report = model_class.deprecation_report
        first_setting = report[:settings].find { |s| s[:name] == :feature }

        aggregate_failures "report structure" do
          expect(report[:total_count]).to eq(2)
          expect(report[:settings]).to be_an(Array)
          expect(report[:settings].size).to eq(2)
          expect(report[:by_version]).to be_a(Hash)
          expect(report[:by_version].keys).to include("2.0.0", "unknown")
        end

        aggregate_failures "setting details" do
          expect(first_setting).to include(
            name: :feature,
            reason: "Use enabled instead",
            since: "2.0.0",
            replacement: :enabled
          )
        end
      end
    end
  end

  describe "#warn_about_deprecated_settings" do
    let(:feature_enabled) { true }  # Happy path по умолчанию

    before { instance.feature = feature_enabled }

    it "warns about the setting when enabled" do
      expect(instance).to receive(:warn_deprecated_setting)
      instance.warn_about_deprecated_settings
    end

    context "but when deprecated setting is disabled" do
      let(:feature_enabled) { false }  # Null object - переопределение

      it "does NOT warn" do
        expect(instance).not_to receive(:warn_deprecated_setting)
        instance.warn_about_deprecated_settings
      end
    end

    context "but when no deprecated settings" do
      it "does nothing" do
        expect { simple_instance.warn_about_deprecated_settings }.not_to raise_error
      end
    end
  end

  describe "#warn_deprecated_setting" do
    let(:setting) { model_class.find_setting(:feature) }

    it "logs deprecation warning and calls track_deprecated_setting_usage" do
      expect(instance).to receive(:track_deprecated_setting_usage).with(setting)

      aggregate_failures do
        expect { instance.warn_deprecated_setting(setting) }.not_to raise_error
      end
    end
  end

  describe "#track_deprecated_setting_usage" do
    let(:setting) { model_class.find_setting(:feature) }

    it "can be overridden for custom metrics tracking" do
      model_class.class_eval do
        attr_accessor :tracked_settings

        def track_deprecated_setting_usage(setting)
          @tracked_settings ||= []
          @tracked_settings << setting.name
        end
      end

      instance.warn_deprecated_setting(setting)
      expect(instance.tracked_settings).to eq([:feature])
    end
  end

  describe "#using_deprecated_settings?" do
    let(:feature_enabled) { true }  # Happy path по умолчанию
    let(:premium_enabled) { false }

    before do
      instance.feature = feature_enabled
      instance.premium_mode = premium_enabled
    end

    it "returns true when any deprecated setting is enabled" do
      expect(instance.using_deprecated_settings?).to be true
    end

    context "but when all deprecated settings are disabled" do
      let(:feature_enabled) { false }  # Null object - переопределение

      it "returns false" do
        expect(instance.using_deprecated_settings?).to be false
      end
    end

    context "but when no deprecated settings" do
      it "returns false" do
        expect(simple_instance.using_deprecated_settings?).to be false
      end
    end
  end

  describe "#active_deprecated_settings" do
    let(:feature_enabled) { true }  # Happy path - some enabled
    let(:premium_enabled) { false }

    before do
      instance.feature = feature_enabled
      instance.premium_mode = premium_enabled
    end

    it "returns array of enabled setting names when some enabled" do
      expect(instance.active_deprecated_settings).to eq([:feature])
    end

    context "but when all deprecated settings disabled" do
      let(:feature_enabled) { false }  # Null object - переопределение

      it "returns empty array" do
        expect(instance.active_deprecated_settings).to be_empty
      end
    end

    context "but when no deprecated settings" do
      it "returns empty array" do
        expect(simple_instance.active_deprecated_settings).to be_empty
      end
    end
  end

end
