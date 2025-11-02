# frozen_string_literal: true

require "spec_helper"

# rubocop:disable RSpecGuide/MinimumBehavioralCoverage
RSpec.describe ModelSettings::Configuration do
  subject(:config) { described_class.new }

  around do |example|
    example.run
  ensure
    ModelSettings.reset_configuration!
  end

  # rubocop:disable RSpecGuide/MinimumBehavioralCoverage
  describe "#initialize" do
    it "sets default_modules to empty array" do
      expect(config.default_modules).to eq([])
    end

    it "sets inherit_authorization to true by default" do
      expect(config.inherit_authorization).to be true
    end

    it "initializes module_callbacks to empty hash" do
      expect(config.module_callbacks).to eq({})
    end
  end
  # rubocop:enable RSpecGuide/MinimumBehavioralCoverage

  describe "#default_modules=" do
    context "when setting to array of modules" do
      before { config.default_modules = [:pundit, :roles, :i18n] }

      it "stores the modules" do
        expect(config.default_modules).to eq([:pundit, :roles, :i18n])
      end
    end

    context "when setting to empty array" do
      before { config.default_modules = [] }

      it "stores empty array" do
        expect(config.default_modules).to eq([])
      end
    end
  end

  describe "#inherit_authorization=" do
    context "when setting to false" do
      before { config.inherit_authorization = false }

      it "stores false" do
        expect(config.inherit_authorization).to be false
      end
    end

    context "when setting to true" do
      before { config.inherit_authorization = true }

      it "stores true" do
        expect(config.inherit_authorization).to be true
      end
    end
  end

  describe "#module_callback" do
    context "when configuring callback for a module" do
      before do
        config.module_callback(:pundit, :before_save)
      end

      it "stores the callback" do
        expect(config.get_module_callback(:pundit)).to eq(:before_save)
      end
    end

    context "when configuring multiple modules" do
      before do
        config.module_callback(:pundit, :before_save)
        config.module_callback(:roles, :before_validation)
      end

      it "stores all callbacks" do
        aggregate_failures do
          expect(config.get_module_callback(:pundit)).to eq(:before_save)
          expect(config.get_module_callback(:roles)).to eq(:before_validation)
        end
      end
    end

    context "when overwriting existing callback" do
      before do
        config.module_callback(:pundit, :before_save)
        config.module_callback(:pundit, :before_validation)
      end

      it "updates to new callback" do
        expect(config.get_module_callback(:pundit)).to eq(:before_validation)
      end
    end
  end

  describe "#get_module_callback" do
    context "when callback is configured" do
      before do
        config.module_callback(:pundit, :before_save)
      end

      it "returns the callback" do
        expect(config.get_module_callback(:pundit)).to eq(:before_save)
      end
    end

    # rubocop:disable RSpecGuide/ContextSetup
    context "when callback is NOT configured" do  # No setup - testing nil return
      # rubocop:enable RSpecGuide/ContextSetup
      it "returns nil" do
        expect(config.get_module_callback(:nonexistent)).to be_nil
      end
    end
  end

  describe "#module_callbacks" do
    # rubocop:disable RSpecGuide/ContextSetup
    context "when no callbacks configured" do  # No setup - testing empty hash return
      # rubocop:enable RSpecGuide/ContextSetup
      it "returns empty hash" do
        expect(config.module_callbacks).to eq({})
      end
    end

    context "when callbacks are configured" do
      before do
        config.module_callback(:pundit, :before_save)
        config.module_callback(:roles, :before_validation)
      end

      it "returns all configured callbacks" do
        expect(config.module_callbacks).to eq({
          pundit: :before_save,
          roles: :before_validation
        })
      end
    end
  end

  # rubocop:disable RSpecGuide/MinimumBehavioralCoverage
  describe "#reset!" do
    subject(:reset_action) { config.reset! }

    before do
      config.default_modules = [:pundit, :roles]
      config.inherit_authorization = false
      config.module_callback(:pundit, :before_save)
    end

    it "resets default_modules to empty array" do
      reset_action
      expect(config.default_modules).to eq([])
    end

    it "resets inherit_authorization to true" do
      reset_action
      expect(config.inherit_authorization).to be true
    end

    it "resets module_callbacks to empty hash" do
      reset_action
      expect(config.module_callbacks).to eq({})
    end
  end
  # rubocop:enable RSpecGuide/MinimumBehavioralCoverage
end
