# frozen_string_literal: true

require "spec_helper"

# rubocop:disable RSpecGuide/MinimumBehavioralCoverage
RSpec.describe ModelSettings::ModuleRegistry do
  # Ensure clean slate for each test
  after do
    described_class.reset!
  end

  # rubocop:disable RSpecGuide/MinimumBehavioralCoverage
  describe ".register_module" do
    it "stores module by name" do
      test_module = Module.new
      described_class.register_module(:test_mod, test_module)

      expect(described_class.modules[:test_mod]).to eq(test_module)
    end
  end
  # rubocop:enable RSpecGuide/MinimumBehavioralCoverage

  # rubocop:disable RSpecGuide/MinimumBehavioralCoverage
  describe ".register_exclusive_group" do
    it "creates new group with module" do
      described_class.register_exclusive_group(:authorization, :pundit)

      expect(described_class.exclusive_groups[:authorization]).to eq([:pundit])
    end

    context "when group already exists" do
      before do
        described_class.register_exclusive_group(:authorization, :pundit)
      end

      it "adds module to existing group" do
        described_class.register_exclusive_group(:authorization, :action_policy)

        expect(described_class.exclusive_groups[:authorization]).to match_array([:pundit, :action_policy])
      end

      context "and module already in group" do
        before do
          described_class.register_exclusive_group(:authorization, :pundit)
        end

        it "does NOT add duplicate" do
          expect(described_class.exclusive_groups[:authorization]).to eq([:pundit])
        end
      end
    end
  end
  # rubocop:enable RSpecGuide/MinimumBehavioralCoverage

  describe ".register_option" do
    context "without validator" do
      before do
        described_class.register_option(:custom_option)
      end

      it "registers option with nil validator", :aggregate_failures do
        expect(described_class.registered_options).to have_key(:custom_option)
        expect(described_class.registered_options[:custom_option]).to be_nil
      end
    end

    context "with validator proc" do
      let(:validator) { ->(setting, value) { raise ArgumentError if value.nil? } }

      before do
        described_class.register_option(:viewable_by, validator)
      end

      it "stores validator" do
        expect(described_class.registered_options[:viewable_by]).to eq(validator)
      end
    end

    context "with validator block" do
      before do
        described_class.register_option(:ui_group) do |setting, value|
          raise ArgumentError unless value.is_a?(Symbol)
        end
      end

      it "stores block as validator" do
        expect(described_class.registered_options[:ui_group]).to be_a(Proc)
      end
    end
  end

  # rubocop:disable RSpecGuide/MinimumBehavioralCoverage
  describe ".extend_setting" do
    it "includes module in Setting class" do
      extension_module = Module.new do
        def custom_method
          "extended"
        end
      end

      described_class.extend_setting(extension_module)
      setting = ModelSettings::Setting.new(:test)

      expect(setting.custom_method).to eq("extended")
    end
  end
  # rubocop:enable RSpecGuide/MinimumBehavioralCoverage

  describe ".module_included?" do
    let(:test_module) { Module.new }
    let(:model_class) do
      Class.new(ActiveRecord::Base) do
        self.table_name = "test_models"
        include ModelSettings::DSL
      end
    end

    context "when module is registered" do
      before do
        described_class.register_module(:test_mod, test_module)
      end

      context "and included in model" do
        before do
          model_class.include(test_module)
        end

        it "returns true" do
          expect(described_class.module_included?(:test_mod, model_class)).to be true
        end
      end

      context "but NOT included in model" do
        let(:model_class) do
          Class.new(ActiveRecord::Base) do
            self.table_name = "test_models"
            include ModelSettings::DSL
          end
        end

        it "returns false" do
          expect(described_class.module_included?(:test_mod, model_class)).to be false
        end
      end
    end

    context "when module is NOT registered" do
      let(:model_class) do
        Class.new(ActiveRecord::Base) do
          self.table_name = "test_models"
          include ModelSettings::DSL
        end
      end

      it "returns false" do
        expect(described_class.module_included?(:nonexistent, model_class)).to be false
      end
    end
  end

  # rubocop:disable RSpecGuide/MinimumBehavioralCoverage
  describe ".on_setting_defined" do
    it "registers definition hook" do
      hook_called = false
      described_class.on_setting_defined { |_setting, _model| hook_called = true }

      expect(described_class.definition_hooks.size).to eq(1)
    end
  end
  # rubocop:enable RSpecGuide/MinimumBehavioralCoverage

  # rubocop:disable RSpecGuide/MinimumBehavioralCoverage
  describe ".on_settings_compiled" do
    it "registers compilation hook" do
      hook_called = false
      described_class.on_settings_compiled { |_settings, _model| hook_called = true }

      expect(described_class.compilation_hooks.size).to eq(1)
    end
  end
  # rubocop:enable RSpecGuide/MinimumBehavioralCoverage

  describe ".validate_setting_options!" do
    let(:setting) { ModelSettings::Setting.new(:test, {viewable_by: [:admin]}) }

    context "when option has validator" do
      before do
        described_class.register_option(:viewable_by) do |_setting, value|
          raise ArgumentError, "Must be array" unless value.is_a?(Array)
        end
      end

      context "and value is valid" do
        let(:setting) { ModelSettings::Setting.new(:test, {viewable_by: [:admin]}) }

        it "does NOT raise error" do
          expect { described_class.validate_setting_options!(setting) }.not_to raise_error
        end
      end

      context "and value is invalid" do
        let(:setting) { ModelSettings::Setting.new(:test, {viewable_by: "admin"}) }

        it "raises ArgumentError" do
          expect { described_class.validate_setting_options!(setting) }.to raise_error(ArgumentError, "Must be array")
        end
      end
    end

    context "when option has no validator" do
      let(:setting) { ModelSettings::Setting.new(:test, {unregistered_option: "value"}) }

      it "does NOT validate" do
        expect { described_class.validate_setting_options!(setting) }.not_to raise_error
      end
    end
  end

  # rubocop:disable RSpecGuide/MinimumBehavioralCoverage
  describe ".execute_definition_hooks" do
    subject(:execute) { described_class.execute_definition_hooks(setting, model_class) }

    let(:setting) { ModelSettings::Setting.new(:test) }
    let(:model_class) { Class.new }

    # rubocop:disable RSpec/ExampleLength
    it "calls hooks and passes correct arguments", :aggregate_failures do
      call_count = 0
      received_setting = nil
      received_model = nil
      described_class.on_setting_defined { |_setting, _model| call_count += 1 }
      described_class.on_setting_defined { |s, m|
        call_count += 1
        received_setting = s
        received_model = m
      }
      execute
      expect(call_count).to eq(2)
      expect(received_setting).to eq(setting)
      expect(received_model).to eq(model_class)
    end
    # rubocop:enable RSpec/ExampleLength
  end
  # rubocop:enable RSpecGuide/MinimumBehavioralCoverage

  # rubocop:disable RSpecGuide/MinimumBehavioralCoverage
  describe ".execute_compilation_hooks" do
    subject(:execute) { described_class.execute_compilation_hooks(settings, model_class) }

    let(:settings) { [ModelSettings::Setting.new(:test)] }
    let(:model_class) { Class.new }

    # rubocop:disable RSpec/ExampleLength
    it "calls hooks and passes correct arguments", :aggregate_failures do
      call_count = 0
      received_settings = nil
      received_model = nil
      described_class.on_settings_compiled { |_settings, _model| call_count += 1 }
      described_class.on_settings_compiled { |s, m|
        call_count += 1
        received_settings = s
        received_model = m
      }
      execute
      expect(call_count).to eq(2)
      expect(received_settings).to eq(settings)
      expect(received_model).to eq(model_class)
    end
    # rubocop:enable RSpec/ExampleLength
  end
  # rubocop:enable RSpecGuide/MinimumBehavioralCoverage

  describe ".check_exclusive_conflict!" do
    let(:pundit_module) { Module.new }
    let(:roles_module) { Module.new }
    let(:model_class) do
      Class.new(ActiveRecord::Base) do
        self.table_name = "test_models"
        include ModelSettings::DSL
      end
    end

    before do
      described_class.register_module(:pundit, pundit_module)
      described_class.register_module(:roles, roles_module)
      described_class.register_exclusive_group(:authorization, :pundit)
      described_class.register_exclusive_group(:authorization, :roles)
    end

    # rubocop:disable RSpecGuide/ContextSetup
    context "when no conflicting modules are included" do  # Organizational/characteristic context
      # rubocop:enable RSpecGuide/ContextSetup
      it "does NOT raise error" do
        expect {
          described_class.check_exclusive_conflict!(model_class, :pundit)
        }.not_to raise_error
      end
    end

    context "when conflicting module is already included" do
      before do
        model_class.include(roles_module)
      end

      it "raises ExclusiveGroupConflictError" do
        expect {
          described_class.check_exclusive_conflict!(model_class, :pundit)
        }.to raise_error(ModelSettings::ModuleRegistry::ExclusiveGroupConflictError, /conflicts with :roles/)
      end
    end

    context "when same module is being checked again" do
      before do
        model_class.include(pundit_module)
      end

      it "does NOT raise error" do
        expect {
          described_class.check_exclusive_conflict!(model_class, :pundit)
        }.not_to raise_error
      end
    end

    context "when module is NOT in any exclusive group" do
      let(:other_module) { Module.new }

      before do
        described_class.register_module(:other, other_module)
      end

      it "does NOT raise error" do
        expect {
          described_class.check_exclusive_conflict!(model_class, :other)
        }.not_to raise_error
      end
    end
  end

  describe ".validate_exclusive_groups!" do
    before do
      described_class.register_exclusive_group(:authorization, :pundit)
      described_class.register_exclusive_group(:authorization, :action_policy)
    end

    context "when no conflicts" do
      let(:active_modules) { [:pundit] }

      it "returns true" do
        result = described_class.validate_exclusive_groups!(active_modules)

        expect(result).to be true
      end
    end

    context "when multiple modules from same group active" do
      let(:active_modules) { [:pundit, :action_policy] }

      it "raises ArgumentError" do
        expect {
          described_class.validate_exclusive_groups!(active_modules)
        }.to raise_error(ArgumentError, /Cannot use multiple modules from exclusive group/)
      end
    end
  end

  # rubocop:disable RSpecGuide/MinimumBehavioralCoverage
  describe ".reset!" do
    subject(:reset) { described_class.reset! }

    before do
      described_class.register_module(:test, Module.new)
      described_class.register_exclusive_group(:auth, :test)
      described_class.register_option(:custom)
      described_class.on_setting_defined { |_s, _m| }
      described_class.on_settings_compiled { |_s, _m| }
      described_class.before_setting_change { |_i, _s, _v| }
      described_class.after_setting_change { |_i, _s, _o, _n| }
    end

    it "clears all registered data", :aggregate_failures do
      reset

      expect(described_class.modules).to be_empty
      expect(described_class.exclusive_groups).to be_empty
      expect(described_class.registered_options).to be_empty
      expect(described_class.definition_hooks).to be_empty
      expect(described_class.compilation_hooks).to be_empty
      expect(described_class.before_change_hooks).to be_empty
      expect(described_class.after_change_hooks).to be_empty
    end
  end
  # rubocop:enable RSpecGuide/MinimumBehavioralCoverage
end
