# frozen_string_literal: true

# rubocop:disable RSpecGuide/MinimumBehavioralCoverage
RSpec.describe ModelSettings do
  around do |example|
    example.run
  ensure
    described_class.reset_configuration!
  end

  it "has a version number" do
    expect(ModelSettings::VERSION).not_to be_nil
  end

  # rubocop:disable RSpecGuide/MinimumBehavioralCoverage
  describe ".configuration" do
    it "returns Configuration instance" do
      expect(described_class.configuration).to be_a(ModelSettings::Configuration)
    end

    it "returns same instance on multiple calls" do
      config1 = described_class.configuration
      config2 = described_class.configuration
      expect(config1).to equal(config2)
    end
  end
  # rubocop:enable RSpecGuide/MinimumBehavioralCoverage

  describe ".configure" do
    it "yields configuration object" do
      expect { |b| described_class.configure(&b) }.to yield_with_args(ModelSettings::Configuration)
    end

    context "when configuring default_modules" do
      before do
        described_class.configure do |config|
          config.default_modules = [:pundit, :ui, :i18n]
        end
      end

      it "sets the default modules" do
        expect(described_class.configuration.default_modules).to eq([:pundit, :ui, :i18n])
      end
    end

    context "when configuring inherit_authorization" do
      before do
        described_class.configure do |config|
          config.inherit_authorization = false
        end
      end

      it "sets the authorization inheritance" do
        expect(described_class.configuration.inherit_authorization).to be false
      end
    end

    context "when configuring multiple options" do
      before do
        described_class.configure do |config|
          config.default_modules = [:pundit]
          config.inherit_authorization = false
        end
      end

      it "sets default_modules" do
        expect(described_class.configuration.default_modules).to eq([:pundit])
      end

      it "sets inherit_authorization" do
        expect(described_class.configuration.inherit_authorization).to be false
      end
    end
  end

  # rubocop:disable RSpecGuide/MinimumBehavioralCoverage
  describe ".reset_configuration!" do
    subject(:reset_action) { described_class.reset_configuration! }

    before do
      described_class.configure do |config|
        config.default_modules = [:pundit, :roles]
        config.inherit_authorization = false
      end
    end

    it "creates new configuration instance" do
      old_config = described_class.configuration
      reset_action
      new_config = described_class.configuration

      expect(new_config).not_to equal(old_config)
    end

    it "resets default_modules to default" do
      reset_action
      config = described_class.configuration

      expect(config.default_modules).to eq([])
    end

    it "resets inherit_authorization to default" do
      reset_action
      config = described_class.configuration

      expect(config.inherit_authorization).to be true
    end
  end
  # rubocop:enable RSpecGuide/MinimumBehavioralCoverage

  # rubocop:disable RSpecGuide/MinimumBehavioralCoverage
  describe "configuration isolation in tests" do
    it "does not leak configuration between tests", :aggregate_failures do
      # This test should start with clean config due to around hook
      expect(described_class.configuration.default_modules).to eq([])
      expect(described_class.configuration.inherit_authorization).to be true
    end
  end
  # rubocop:enable RSpecGuide/MinimumBehavioralCoverage
end
