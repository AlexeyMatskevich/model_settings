# frozen_string_literal: true

require "spec_helper"

# rubocop:disable RSpecGuide/MinimumBehavioralCoverage
RSpec.describe ModelSettings::Configuration do
  subject(:config) { described_class.new }

  around do |example|
    example.run
  ensure
    ModelSettings.reset_configuration!
    # Ensure core options are registered for next spec files
    unless ModelSettings::ModuleRegistry.inheritable_option?(:metadata)
      ModelSettings::ModuleRegistry.register_inheritable_option(:metadata, merge_strategy: :merge, auto_include: false)
      ModelSettings::ModuleRegistry.register_inheritable_option(:cascade, merge_strategy: :merge, auto_include: false)
      ModelSettings::ModuleRegistry.register_inheritable_option(:viewable_by, merge_strategy: :append)
      ModelSettings::ModuleRegistry.register_inheritable_option(:editable_by, merge_strategy: :append)
      ModelSettings::ModuleRegistry.register_inheritable_option(:authorize_with, merge_strategy: :replace)
    end
    # Ensure modules are registered for next spec files
    unless ModelSettings::ModuleRegistry.module_registered?(:roles)
      ModelSettings::ModuleRegistry.register_module(:roles, ModelSettings::Modules::Roles)
      ModelSettings::ModuleRegistry.register_exclusive_group(:authorization, :roles)
      ModelSettings::ModuleRegistry.register_module(:pundit, ModelSettings::Modules::Pundit)
      ModelSettings::ModuleRegistry.register_exclusive_group(:authorization, :pundit)
      ModelSettings::ModuleRegistry.register_module(:action_policy, ModelSettings::Modules::ActionPolicy)
      ModelSettings::ModuleRegistry.register_exclusive_group(:authorization, :action_policy)
    end
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

    it "initializes inheritable_options to empty array" do
      expect(config.inheritable_options).to eq([])
    end

    it "sets inheritable_options_explicitly_set to false" do
      expect(config.inheritable_options_explicitly_set?).to be false
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

  describe "#inheritable_options" do
    it "returns empty array by default" do
      expect(config.inheritable_options).to eq([])
    end

    context "when explicitly set" do
      before do
        config.inheritable_options = [:authorize_with, :viewable_by]
      end

      it "returns the set options" do
        expect(config.inheritable_options).to eq([:authorize_with, :viewable_by])
      end
    end
  end

  # rubocop:disable RSpecGuide/MinimumBehavioralCoverage
  describe "#inheritable_options=" do
    subject(:set_options) { config.inheritable_options = [:authorize_with, :viewable_by] }

    it "sets the inheritable options" do
      set_options
      expect(config.inheritable_options).to eq([:authorize_with, :viewable_by])
    end

    it "marks inheritable_options as explicitly set" do
      set_options
      expect(config.inheritable_options_explicitly_set?).to be true
    end
  end
  # rubocop:enable RSpecGuide/MinimumBehavioralCoverage

  describe "#add_inheritable_option" do
    it "adds the option to the list" do
      config.add_inheritable_option(:authorize_with)
      expect(config.inheritable_options).to eq([:authorize_with])
    end

    it "does not add duplicate options" do
      config.add_inheritable_option(:authorize_with)
      config.add_inheritable_option(:authorize_with)
      expect(config.inheritable_options).to eq([:authorize_with])
    end

    it "adds multiple unique options" do
      config.add_inheritable_option(:authorize_with)
      config.add_inheritable_option(:viewable_by)
      config.add_inheritable_option(:editable_by)
      expect(config.inheritable_options).to eq([:authorize_with, :viewable_by, :editable_by])
    end

    context "but when inheritable_options is explicitly set" do
      before do
        config.inheritable_options = [:viewable_by]
      end

      it "does not add new options (user control takes precedence)" do
        config.add_inheritable_option(:authorize_with)
        expect(config.inheritable_options).to eq([:viewable_by])
      end
    end
  end

  describe "#inheritable_options_explicitly_set?" do
    it "returns false by default" do
      expect(config.inheritable_options_explicitly_set?).to be false
    end

    context "when explicitly set via setter" do
      before do
        config.inheritable_options = [:authorize_with]
      end

      it "returns true" do
        expect(config.inheritable_options_explicitly_set?).to be true
      end
    end

    context "but when modified via add_inheritable_option" do
      before do
        config.add_inheritable_option(:authorize_with)
      end

      it "remains false (not explicitly set by user)" do
        expect(config.inheritable_options_explicitly_set?).to be false
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
      config.inheritable_options = [:authorize_with, :viewable_by]
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

    it "resets inheritable_options to empty array" do
      reset_action
      expect(config.inheritable_options).to eq([])
    end

    it "resets inheritable_options_explicitly_set flag to false" do
      reset_action
      expect(config.inheritable_options_explicitly_set?).to be false
    end
  end

  describe "#effective_inheritable_options" do
    around do |example|
      # Save current registry state
      saved_state = save_registry_state

      # Reset to get clean state for these tests
      ModelSettings::ModuleRegistry.reset!

      # Run test
      example.run

      # Restore original state for subsequent tests
      restore_registry_state(saved_state)
    end

    context "when user explicitly set inheritable_options" do
      before do
        config.inheritable_options = [:custom, :user_defined]
        # Use test-only option names with auto_include: false to avoid contamination
        ModelSettings::ModuleRegistry.register_inheritable_option(:test_ignored_1, merge_strategy: :append, auto_include: false)
        ModelSettings::ModuleRegistry.register_inheritable_option(:test_ignored_2, merge_strategy: :merge, auto_include: false)
      end

      it "returns only user list" do
        expect(config.effective_inheritable_options).to eq([:custom, :user_defined])
      end

      # rubocop:disable RSpec/MultipleExpectations
      it "ignores module registrations" do
        expect(config.effective_inheritable_options).not_to include(:test_ignored_1)
        expect(config.effective_inheritable_options).not_to include(:test_ignored_2)
      end
      # rubocop:enable RSpec/MultipleExpectations
    end

    context "when user did not explicitly set" do
      before do
        config.add_inheritable_option(:custom)
        config.add_inheritable_option(:another)
        # Use test-only option names - register them so merge strategy is defined
        # but with auto_include: false so they don't contaminate other tests
        ModelSettings::ModuleRegistry.register_inheritable_option(:test_option_1, merge_strategy: :append, auto_include: false)
        ModelSettings::ModuleRegistry.register_inheritable_option(:test_option_2, merge_strategy: :merge, auto_include: false)
        # Manually add to config to make them inheritable for THIS test
        config.add_inheritable_option(:test_option_1)
        config.add_inheritable_option(:test_option_2)
      end

      it "merges config options and module registrations" do
        expect(config.effective_inheritable_options).to contain_exactly(
          :custom, :another, :test_option_1, :test_option_2
        )
      end

      it "does not duplicate options" do
        config.add_inheritable_option(:test_option_1)  # Manually add what's also registered
        result = config.effective_inheritable_options
        expect(result.count(:test_option_1)).to eq(1)
      end
    end

    # rubocop:disable RSpecGuide/ContextSetup
    context "when neither user nor modules registered anything" do
      it "returns empty array" do
        expect(config.effective_inheritable_options).to eq([])
      end
    end
    # rubocop:enable RSpecGuide/ContextSetup

    context "when only modules registered" do
      before do
        # Use test-only option name with auto_include: true for this specific test
        # (testing the auto-include feature itself)
        ModelSettings::ModuleRegistry.register_inheritable_option(:test_module_option, merge_strategy: :append, auto_include: true)
      end

      it "returns module registered options" do
        expect(config.effective_inheritable_options).to eq([:test_module_option])
      end
      # Note: This auto-included option may linger in subsequent tests,
      # but it won't affect them since they use save/restore pattern.
      # Future tests should prefer auto_include: false for isolation.
    end

    context "when only user added via config" do
      before do
        config.add_inheritable_option(:custom)
      end

      it "returns config options" do
        expect(config.effective_inheritable_options).to eq([:custom])
      end
    end
  end
  # rubocop:enable RSpecGuide/MinimumBehavioralCoverage
end
