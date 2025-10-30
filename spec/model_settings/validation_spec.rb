# frozen_string_literal: true

require "spec_helper"

RSpec.describe ModelSettings::Validation do
  let(:model_class) do
    Class.new(TestModel) do
      def self.name
        "ValidationTestModel"
      end

      include ModelSettings::DSL

      setting :enabled, type: :column, default: false
      setting :premium_mode, type: :column, default: false
    end
  end

  let(:instance) { model_class.create! }

  describe "#initialize_setting_errors" do
    it "initializes ActiveModel::Errors collection" do
      expect(instance.setting_errors).to be_a(ActiveModel::Errors)
    end
  end

  describe "#validate_setting" do
    context "with validate_with as Symbol" do
      let(:model_class) do
        Class.new(TestModel) do
          def self.name
            "SymbolValidatorModel"
          end

          include ModelSettings::DSL

          attr_accessor :email_configured

          setting :notifications,
            type: :column,
            default: false,
            validate_with: :check_email_configured

          def check_email_configured
            add_setting_error(:notifications, "requires email configuration") unless email_configured
          end
        end
      end

      let(:instance) { model_class.create! }
      let(:email_configured) { true }  # Happy path по умолчанию

      before { instance.email_configured = email_configured }

      it "returns true when validator passes" do
        expect(instance.validate_setting(:notifications)).to be true
      end

      context "but when validator fails" do
        let(:email_configured) { false }  # Null object - переопределение

        it "returns false and adds error to setting_errors" do
          aggregate_failures do
            expect(instance.validate_setting(:notifications)).to be false
            expect(instance.setting_errors_for(:notifications)).to include(/requires email configuration/)
          end
        end
      end

      context "but when validating multiple times" do
        let(:email_configured) { false }  # Null object - переопределение

        it "clears previous errors before validation" do
          instance.validate_setting(:notifications)
          first_errors = instance.setting_errors_for(:notifications).size

          instance.validate_setting(:notifications)
          second_errors = instance.setting_errors_for(:notifications).size

          expect(first_errors).to eq(second_errors)
        end
      end
    end

    context "with validate_with as Proc" do
      let(:model_class) do
        Class.new(TestModel) do
          def self.name
            "ProcValidatorModel"
          end

          include ModelSettings::DSL

          attr_accessor :subscribed

          setting :premium_mode,
            type: :column,
            default: false,
            validate_with: -> {
              add_setting_error(:premium_mode, "requires subscription") unless respond_to?(:subscribed?) && subscribed?
            }

          def subscribed?
            !!subscribed
          end
        end
      end

      let(:instance) { model_class.create! }

      it "executes proc in instance context and validates correctly" do
        aggregate_failures do
          instance.subscribed = true
          expect(instance.validate_setting(:premium_mode)).to be true

          instance.subscribed = false
          expect(instance.validate_setting(:premium_mode)).to be false
          expect(instance.setting_errors_for(:premium_mode)).to include(/requires subscription/)
        end
      end
    end

    context "with validate_with as Array" do
      let(:model_class) do
        Class.new(TestModel) do
          def self.name
            "ArrayValidatorModel"
          end

          include ModelSettings::DSL

          attr_accessor :has_quota, :has_permissions

          setting :enabled,
            type: :column,
            default: false,
            validate_with: [:check_quota, :check_permissions]

          def check_quota
            add_setting_error(:enabled, "quota exceeded") unless has_quota
          end

          def check_permissions
            add_setting_error(:enabled, "insufficient permissions") unless has_permissions
          end
        end
      end

      let(:instance) { model_class.create! }
      let(:has_quota) { false }  # Fail case по умолчанию для демонстрации errors
      let(:has_permissions) { false }

      before do
        instance.has_quota = has_quota
        instance.has_permissions = has_permissions
      end

      it "calls all validators in order and accumulates errors" do
        aggregate_failures do
          expect(instance.validate_setting(:enabled)).to be false
          errors = instance.setting_errors_for(:enabled)
          expect(errors).to include(/quota exceeded/)
          expect(errors).to include(/insufficient permissions/)
        end
      end

      context "but when all validators pass" do
        let(:has_quota) { true }  # Null object - переопределение
        let(:has_permissions) { true }

        it "returns true" do
          expect(instance.validate_setting(:enabled)).to be true
        end
      end
    end

    context "with value parameter provided" do
      let(:model_class) do
        Class.new(TestModel) do
          def self.name
            "ValueParamModel"
          end

          include ModelSettings::DSL

          setting :enabled,
            type: :column,
            default: false,
            validate_with: :check_value

          def check_value
            add_setting_error(:enabled, "invalid value") if @_validating_value == :invalid
          end
        end
      end

      let(:instance) { model_class.create! }

      it "validates provided value instead of current value" do
        expect(instance.validate_setting(:enabled, :invalid)).to be false
      end
    end

    context "but when setting does NOT exist" do
      it "returns true" do
        expect(instance.validate_setting(:nonexistent_setting)).to be true
      end
    end

    context "but when setting has no validator" do
      it "returns true" do
        expect(instance.validate_setting(:premium_mode)).to be true
      end
    end
  end

  describe "#validate_all_settings" do
    context "when all settings valid" do
      let(:model_class) do
        Class.new(TestModel) do
          def self.name
            "AllValidModel"
          end

          include ModelSettings::DSL

          setting :enabled,
            type: :column,
            default: false,
            validate_with: :always_valid_a

          setting :premium_mode,
            type: :column,
            default: false,
            validate_with: :always_valid_b

          def always_valid_a; end
          def always_valid_b; end
        end
      end

      let(:instance) { model_class.create! }

      it "returns true" do
        expect(instance.validate_all_settings).to be true
      end

      it "validates all settings with validate_with option" do
        expect(instance).to receive(:always_valid_a)
        expect(instance).to receive(:always_valid_b)
        instance.validate_all_settings
      end
    end

    context "but when some settings invalid" do
      let(:model_class) do
        Class.new(TestModel) do
          def self.name
            "SomeInvalidModel"
          end

          include ModelSettings::DSL

          setting :enabled,
            type: :column,
            default: false,
            validate_with: :always_valid

          setting :premium_mode,
            type: :column,
            default: false,
            validate_with: :always_invalid

          def always_valid; end

          def always_invalid
            add_setting_error(:premium_mode, "always fails")
          end
        end
      end

      let(:instance) { model_class.create! }

      it "returns false" do
        expect(instance.validate_all_settings).to be false
      end

      it "accumulates errors for all invalid settings" do
        instance.validate_all_settings
        expect(instance.setting_has_errors?(:premium_mode)).to be true
      end
    end

    context "when no settings have validators" do
      it "returns true" do
        expect(instance.validate_all_settings).to be true
      end
    end
  end

  describe "#add_setting_error" do
    it "adds error to setting_errors and is retrievable via setting_errors_for" do
      instance.add_setting_error(:premium_mode, "custom error message")

      aggregate_failures do
        expect(instance.setting_errors.added?(:premium_mode, "custom error message")).to be true
        expect(instance.setting_errors_for(:premium_mode)).to include(/custom error message/)
      end
    end
  end

  describe "#setting_errors_for" do
    it "returns array of full error messages when setting has errors" do
      instance.add_setting_error(:premium_mode, "error 1")
      instance.add_setting_error(:premium_mode, "error 2")

      errors = instance.setting_errors_for(:premium_mode)
      expect(errors).to match([a_string_matching(/error 1/), a_string_matching(/error 2/)])
    end

    context "but when setting has no errors" do
      it "returns empty array" do
        expect(instance.setting_errors_for(:premium_mode)).to be_empty
      end
    end
  end

  describe "#setting_valid?" do
    let(:has_error) { false }  # Happy path по умолчанию

    before { instance.add_setting_error(:premium_mode, "error") if has_error }

    it "returns true when setting has no errors" do
      expect(instance.setting_valid?(:premium_mode)).to be true
    end

    context "but when setting has errors" do
      let(:has_error) { true }  # Null object - переопределение

      it "returns false" do
        expect(instance.setting_valid?(:premium_mode)).to be false
      end
    end
  end

  describe "#setting_has_errors?" do
    let(:has_error) { false }  # Happy path по умолчанию

    before { instance.add_setting_error(:enabled, "error") if has_error }

    it "returns false when setting has no errors" do
      expect(instance.setting_has_errors?(:enabled)).to be false
    end

    context "but when setting has errors" do
      let(:has_error) { true }  # Null object - переопределение

      it "returns true" do
        expect(instance.setting_has_errors?(:enabled)).to be true
      end
    end
  end

  describe "ClassMethods" do
    describe ".configure_setting_validation and .setting_validation_options" do
      it "sets and returns validation options" do
        model_class.configure_setting_validation(strict: true, on_error: :raise)
        expect(model_class.setting_validation_options).to eq({strict: true, on_error: :raise})
      end

      context "but when NOT configured" do
        it "returns empty hash" do
          expect(model_class.setting_validation_options).to eq({})
        end
      end
    end
  end
end
