# frozen_string_literal: true

require "spec_helper"

RSpec.describe ModelSettings::Modules::I18n do
  let(:model_class) do
    Class.new(TestModel) do
      def self.name
        "I18nTestModel"
      end

      def self.model_name
        ActiveModel::Name.new(self, nil, "i18n_test_model")
      end

      include ModelSettings::DSL

      setting :notifications, # Use existing column
        type: :column,
        default: false,
        metadata: {
          i18n: {
            label_key: "custom.notifications.label",
            description_key: "custom.notifications.description"
          }
        },
        description: "Enable notifications"

      setting :premium_mode, # Use existing column
        type: :column,
        default: false,
        description: "Premium features"

      setting :enabled, # Use existing column
        type: :column,
        default: false
    end
  end

  let(:instance) { model_class.create! }

  # Helper method to temporarily remove I18n constant for testing
  def without_i18n_constant(&block)
    i18n_backup = Object.const_get(:I18n) if Object.const_defined?(:I18n)
    Object.send(:remove_const, :I18n) if Object.const_defined?(:I18n)

    yield
  ensure
    Object.const_set(:I18n, i18n_backup) if i18n_backup
  end

  describe "ClassMethods" do
    describe ".settings_i18n_scope" do
      it "returns I18n scope based on model_name.i18n_key" do
        expect(model_class.settings_i18n_scope).to eq("model_settings.i18n_test_model")
      end
    end

    describe ".settings_with_i18n" do
      it "returns settings with i18n metadata" do
        results = model_class.settings_with_i18n
        expect(results.map(&:name)).to eq([:notifications])
      end

      context "but when no settings have i18n" do
        let(:simple_model) do
          Class.new(TestModel) do
            def self.name
              "SimpleModel"
            end

            def self.model_name
              ActiveModel::Name.new(self, nil, "simple_model")
            end

            include ModelSettings::DSL
            setting :enabled, type: :column
          end
        end

        it "returns empty array" do
          expect(simple_model.settings_with_i18n).to be_empty
        end
      end
    end
  end

  describe "#t_label_for" do
    before do
      require "i18n" unless defined?(::I18n)
    end

    it "uses default scope pattern and falls back to humanized name" do
      result = instance.t_label_for(:premium_mode)
      expect(result).to eq("Premium mode")
    end

    context "but with custom label_key in metadata" do
      it "uses custom key for translation" do
        allow(::I18n).to receive(:t).with("custom.notifications.label").and_return("Custom Notifications Label")

        expect(instance.t_label_for(:notifications)).to eq("Custom Notifications Label")
      end
    end

    context "but when I18n is NOT defined" do
      it "returns humanized setting name" do
        without_i18n_constant do
          expect(instance.t_label_for(:enabled)).to eq("Enabled")
        end
      end
    end
  end

  describe "#t_description_for" do
    before do
      require "i18n" unless defined?(::I18n)
    end

    it "uses default scope and falls back to setting.description" do
      result = instance.t_description_for(:premium_mode)
      expect(result).to eq("Premium features")
    end

    context "but with custom description_key in metadata" do
      it "uses custom key for translation" do
        allow(::I18n).to receive(:t).with("custom.notifications.description").and_return("Custom description")

        expect(instance.t_description_for(:notifications)).to eq("Custom description")
      end
    end

    context "but when I18n is NOT defined" do
      it "returns setting.description" do
        without_i18n_constant do
          expect(instance.t_description_for(:premium_mode)).to eq("Premium features")
        end
      end
    end
  end

  describe "#t_help_for" do
    before do
      require "i18n" unless defined?(::I18n)
    end

    it "uses default scope and returns nil if no translation" do
      result = instance.t_help_for(:enabled)
      expect(result).to be_nil
    end

    context "but when I18n is NOT defined" do
      it "returns nil" do
        without_i18n_constant do
          expect(instance.t_help_for(:enabled)).to be_nil
        end
      end
    end
  end

  describe "#translations_for" do
    before do
      require "i18n" unless defined?(::I18n)
    end

    it "returns hash with :label, :description, :help keys" do
      result = instance.translations_for(:enabled)
      expect(result.keys).to contain_exactly(:label, :description, :help)
    end

    it "calls t_label_for, t_description_for, and t_help_for" do
      aggregate_failures "delegates to translation methods" do
        expect(instance).to receive(:t_label_for).with(:enabled)
        expect(instance).to receive(:t_description_for).with(:enabled)
        expect(instance).to receive(:t_help_for).with(:enabled)

        instance.translations_for(:enabled)
      end
    end

    it "passes options to translation methods" do
      aggregate_failures "passes options through" do
        expect(instance).to receive(:t_label_for).with(:enabled, locale: :ru)
        expect(instance).to receive(:t_description_for).with(:enabled, locale: :ru)
        expect(instance).to receive(:t_help_for).with(:enabled, locale: :ru)

        instance.translations_for(:enabled, locale: :ru)
      end
    end
  end
end
