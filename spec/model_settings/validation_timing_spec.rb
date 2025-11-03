# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Validation Timing Configuration" do
  let(:test_class) do
    Class.new(ActiveRecord::Base) do
      self.table_name = "test_models"

      def self.name
        "ValidationTestModel"
      end

      include ModelSettings::DSL
    end
  end

  before do
    ModelSettings.reset_configuration!
  end

  after do
    ModelSettings.reset_configuration!
  end

  describe "Configuration#validation_mode" do
    it "defaults to :strict in production-like environments" do
      expect(ModelSettings.configuration.validation_mode).to eq(:strict)
    end

    it "accepts :strict mode" do
      ModelSettings.configure do |config|
        config.validation_mode = :strict
      end

      expect(ModelSettings.configuration.validation_mode).to eq(:strict)
    end

    it "accepts :collect mode" do
      ModelSettings.configure do |config|
        config.validation_mode = :collect
      end

      expect(ModelSettings.configuration.validation_mode).to eq(:collect)
    end

    it "rejects invalid modes" do
      expect {
        ModelSettings.configure do |config|
          config.validation_mode = :invalid
        end
      }.to raise_error(ArgumentError, /Validation mode must be :strict or :collect/)
    end

    it "rejects nil mode" do
      expect {
        ModelSettings.configure do |config|
          config.validation_mode = nil
        end
      }.to raise_error(ArgumentError, /Validation mode must be :strict or :collect/)
    end

    it "resets to default on reset!" do
      ModelSettings.configure do |config|
        config.validation_mode = :collect
      end

      ModelSettings.configuration.reset!

      expect(ModelSettings.configuration.validation_mode).to eq(:strict)
    end
  end

  describe "validate_settings_configuration! with :strict mode" do
    before do
      ModelSettings.configure do |config|
        config.validation_mode = :strict
      end
    end

    # Happy path: valid settings compile successfully
    it "compiles valid settings without errors" do
      test_class.setting :feature, type: :column, default: false

      expect { test_class.compile_settings! }.not_to raise_error
    end

    it "marks valid settings as compiled" do
      test_class.setting :feature, type: :column, default: false
      test_class.compile_settings!

      expect(test_class._settings_compiled).to be true
    end

    # rubocop:disable RSpecGuide/ContextSetup
    context "but when single setting has invalid configuration" do
      # rubocop:enable RSpecGuide/ContextSetup
      it "raises error immediately during setting definition" do
        expect {
          test_class.setting :broken, type: :invalid_type
        }.to raise_error(ArgumentError, /Unknown storage type/)
      end

      it "stops validation on first error" do
        expect {
          test_class.setting :broken1, type: :invalid
        }.to raise_error(ArgumentError, /Unknown storage type/)

        # Second setting is never reached because first one raises
      end
    end

    # rubocop:disable RSpecGuide/ContextSetup
    context "and when JSON adapter misconfigured" do
      # rubocop:enable RSpecGuide/ContextSetup
      it "raises error for missing column during setting definition" do
        expect {
          test_class.setting :features, type: :json
        }.to raise_error(ArgumentError, /JSON adapter requires/)
      end

      it "raises error for invalid storage during setting definition" do
        expect {
          test_class.setting :features, type: :json, storage: "invalid"
        }.to raise_error(ArgumentError, /JSON adapter requires/)
      end
    end

    # rubocop:disable RSpecGuide/ContextSetup
    context "and when StoreModel adapter misconfigured" do
      # rubocop:enable RSpecGuide/ContextSetup
      it "raises error for missing column during setting definition" do
        expect {
          test_class.setting :config, type: :store_model
        }.to raise_error(ArgumentError, /StoreModel adapter requires/)
      end

      it "raises error for invalid storage during setting definition" do
        expect {
          test_class.setting :config, type: :store_model, storage: []
        }.to raise_error(ArgumentError, /StoreModel adapter requires/)
      end
    end
  end

  describe "validate_settings_configuration! with :collect mode" do
    before do
      ModelSettings.configure do |config|
        config.validation_mode = :collect
      end
    end

    # Happy path: valid settings compile successfully
    it "compiles valid settings without errors" do
      test_class.setting :feature, type: :column, default: false
      test_class.setting :premium, type: :column, default: false

      expect { test_class.compile_settings! }.not_to raise_error
    end

    it "marks valid settings as compiled" do
      test_class.setting :feature, type: :column, default: false
      test_class.compile_settings!

      expect(test_class._settings_compiled).to be true
    end

    # rubocop:disable RSpecGuide/ContextSetup
    context "but when single setting has invalid configuration" do
      # rubocop:enable RSpecGuide/ContextSetup
      it "collects error and raises with setting name in details" do
        test_class.setting :broken, type: :invalid_type

        expect {
          test_class.compile_settings!
        }.to raise_error(ArgumentError) do |error|
          expect(error.message).to match(/Found 1 validation error/)
          expect(error.message).to match(/- broken:/)
        end
      end
    end

    # rubocop:disable RSpecGuide/ContextSetup
    context "and when multiple settings have invalid configuration" do
      # rubocop:enable RSpecGuide/ContextSetup
      it "collects all errors without stopping on first" do
        test_class.setting :broken1, type: :invalid
        test_class.setting :broken2, type: :also_invalid
        test_class.setting :broken3, type: :still_invalid

        expect {
          test_class.compile_settings!
        }.to raise_error(ArgumentError) do |error|
          expect(error.message).to match(/Found 3 validation error/)
          expect(error.message).to match(/- broken1:/)
          expect(error.message).to match(/- broken2:/)
          expect(error.message).to match(/- broken3:/)
        end
      end
    end

    # rubocop:disable RSpecGuide/ContextSetup
    context "and when mixing valid and invalid settings" do
      # rubocop:enable RSpecGuide/ContextSetup
      it "reports only invalid settings, omitting valid ones" do
        test_class.setting :valid1, type: :column, default: true
        test_class.setting :invalid1, type: :bad
        test_class.setting :valid2, type: :column, default: false
        test_class.setting :invalid2, type: :worse

        expect {
          test_class.compile_settings!
        }.to raise_error(ArgumentError) do |error|
          expect(error.message).to match(/Found 2 validation error/)
          expect(error.message).to match(/- invalid1:/)
          expect(error.message).to match(/- invalid2:/)
          expect(error.message).not_to match(/- valid1:/)
          expect(error.message).not_to match(/- valid2:/)
        end
      end
    end

    # rubocop:disable RSpecGuide/ContextSetup
    context "and when JSON adapter misconfigured" do
      # rubocop:enable RSpecGuide/ContextSetup
      it "collects error for missing column" do
        test_class.setting :features, type: :json

        expect {
          test_class.compile_settings!
        }.to raise_error(ArgumentError) do |error|
          expect(error.message).to match(/Found 1 validation error/)
          expect(error.message).to match(/- features:/)
        end
      end

      it "collects multiple JSON adapter errors" do
        test_class.setting :features, type: :json
        test_class.setting :settings, type: :json, storage: "bad"

        expect {
          test_class.compile_settings!
        }.to raise_error(ArgumentError) do |error|
          expect(error.message).to match(/Found 2 validation error/)
          expect(error.message).to match(/- features:/)
          expect(error.message).to match(/- settings:/)
        end
      end
    end

    # rubocop:disable RSpecGuide/ContextSetup
    context "and when StoreModel adapter misconfigured" do
      # rubocop:enable RSpecGuide/ContextSetup
      it "collects error for missing column" do
        test_class.setting :config, type: :store_model

        expect {
          test_class.compile_settings!
        }.to raise_error(ArgumentError) do |error|
          expect(error.message).to match(/Found 1 validation error/)
          expect(error.message).to match(/- config:/)
        end
      end

      it "collects multiple StoreModel adapter errors" do
        test_class.setting :config1, type: :store_model
        test_class.setting :config2, type: :store_model, storage: nil

        expect {
          test_class.compile_settings!
        }.to raise_error(ArgumentError) do |error|
          expect(error.message).to match(/Found 2 validation error/)
          expect(error.message).to match(/- config1:/)
          expect(error.message).to match(/- config2:/)
        end
      end
    end

    # rubocop:disable RSpecGuide/ContextSetup
    context "and when mixing different error types" do
      # rubocop:enable RSpecGuide/ContextSetup
      it "collects all error types together" do
        test_class.setting :unknown_type, type: :bad
        test_class.setting :bad_json, type: :json
        test_class.setting :bad_store_model, type: :store_model

        expect {
          test_class.compile_settings!
        }.to raise_error(ArgumentError) do |error|
          expect(error.message).to match(/Found 3 validation error/)
          expect(error.message).to match(/- unknown_type:/)
          expect(error.message).to match(/- bad_json:/)
          expect(error.message).to match(/- bad_store_model:/)
        end
      end
    end
  end

  describe "mode switching" do
    it "switches from :strict to :collect" do
      ModelSettings.configure { |c| c.validation_mode = :strict }
      expect(ModelSettings.configuration.validation_mode).to eq(:strict)

      ModelSettings.configure { |c| c.validation_mode = :collect }
      expect(ModelSettings.configuration.validation_mode).to eq(:collect)
    end

    it "switches from :collect to :strict" do
      ModelSettings.configure { |c| c.validation_mode = :collect }
      expect(ModelSettings.configuration.validation_mode).to eq(:collect)

      ModelSettings.configure { |c| c.validation_mode = :strict }
      expect(ModelSettings.configuration.validation_mode).to eq(:strict)
    end

    it "applies new mode to subsequent setting definitions" do
      # First class in strict mode - errors immediately on setting definition
      ModelSettings.configure { |c| c.validation_mode = :strict }

      expect {
        Class.new(ActiveRecord::Base) do
          self.table_name = "test_models"

          def self.name
            "StrictModeModel"
          end

          include ModelSettings::DSL

          setting :bad1, type: :invalid
        end
      }.to raise_error(ArgumentError, /Unknown storage type/)

      # Switch to collect mode - errors only on compile_settings!
      ModelSettings.configure { |c| c.validation_mode = :collect }
      class2 = Class.new(ActiveRecord::Base) do
        self.table_name = "test_models"

        def self.name
          "CollectModeModel"
        end

        include ModelSettings::DSL

        setting :bad1, type: :invalid
        setting :bad2, type: :also_invalid
      end

      # No error during setting definition, error happens during compilation
      expect {
        class2.compile_settings!
      }.to raise_error(ArgumentError, /Found 2 validation error/)
    end
  end
end
