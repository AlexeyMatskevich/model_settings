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

  # rubocop:disable RSpecGuide/MinimumBehavioralCoverage
  describe "#reset!" do
    subject(:reset_action) { config.reset! }

    before do
      config.default_modules = [:pundit, :roles]
      config.inherit_authorization = false
    end

    it "resets default_modules to empty array" do
      reset_action
      expect(config.default_modules).to eq([])
    end

    it "resets inherit_authorization to true" do
      reset_action
      expect(config.inherit_authorization).to be true
    end
  end
  # rubocop:enable RSpecGuide/MinimumBehavioralCoverage
end
