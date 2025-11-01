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
  describe ".before_setting_change" do
    it "registers before_change hook" do
      hook_called = false
      described_class.before_setting_change { |_instance, _setting, _new_value| hook_called = true }

      expect(described_class.before_change_hooks.size).to eq(1)
    end
  end
  # rubocop:enable RSpecGuide/MinimumBehavioralCoverage

  # rubocop:disable RSpecGuide/MinimumBehavioralCoverage
  describe ".after_setting_change" do
    it "registers after_change hook" do
      hook_called = false
      described_class.after_setting_change { |_instance, _setting, _old, _new| hook_called = true }

      expect(described_class.after_change_hooks.size).to eq(1)
    end
  end
  # rubocop:enable RSpecGuide/MinimumBehavioralCoverage

  # rubocop:disable RSpecGuide/MinimumBehavioralCoverage
  describe ".execute_before_change_hooks" do
    subject(:execute) { described_class.execute_before_change_hooks(instance, setting, new_value) }

    let(:instance) { instance_double(ActiveRecord::Base) }
    let(:setting) { ModelSettings::Setting.new(:test) }
    let(:new_value) { true }

    # rubocop:disable RSpec/ExampleLength
    it "calls hooks and passes correct arguments", :aggregate_failures do
      call_count = 0
      received_instance = nil
      received_setting = nil
      received_new_value = nil
      described_class.before_setting_change { |_i, _s, _v| call_count += 1 }
      described_class.before_setting_change { |i, s, v|
        call_count += 1
        received_instance = i
        received_setting = s
        received_new_value = v
      }
      execute
      expect(call_count).to eq(2)
      expect(received_instance).to eq(instance)
      expect(received_setting).to eq(setting)
      expect(received_new_value).to eq(new_value)
    end
    # rubocop:enable RSpec/ExampleLength
  end
  # rubocop:enable RSpecGuide/MinimumBehavioralCoverage

  # rubocop:disable RSpecGuide/MinimumBehavioralCoverage
  describe ".execute_after_change_hooks" do
    subject(:execute) { described_class.execute_after_change_hooks(instance, setting, old_value, new_value) }

    let(:instance) { instance_double(ActiveRecord::Base) }
    let(:setting) { ModelSettings::Setting.new(:test) }
    let(:old_value) { false }
    let(:new_value) { true }

    # rubocop:disable RSpec/ExampleLength
    it "calls hooks and passes correct arguments", :aggregate_failures do
      call_count = 0
      received_instance = nil
      received_setting = nil
      received_old_value = nil
      received_new_value = nil
      described_class.after_setting_change { |_i, _s, _o, _n| call_count += 1 }
      described_class.after_setting_change { |i, s, o, n|
        call_count += 1
        received_instance = i
        received_setting = s
        received_old_value = o
        received_new_value = n
      }
      execute
      expect(call_count).to eq(2)
      expect(received_instance).to eq(instance)
      expect(received_setting).to eq(setting)
      expect(received_old_value).to eq(old_value)
      expect(received_new_value).to eq(new_value)
    end
    # rubocop:enable RSpec/ExampleLength
  end
  # rubocop:enable RSpecGuide/MinimumBehavioralCoverage

  # rubocop:disable RSpecGuide/MinimumBehavioralCoverage
  describe ".module_registered?" do
    before do
      described_class.register_module(:test_mod, Module.new)
    end

    it "returns true when module is registered" do
      expect(described_class.module_registered?(:test_mod)).to be true
    end

    it "returns false when module is NOT registered" do
      expect(described_class.module_registered?(:nonexistent)).to be false
    end
  end
  # rubocop:enable RSpecGuide/MinimumBehavioralCoverage

  # rubocop:disable RSpecGuide/MinimumBehavioralCoverage
  describe ".get_module" do
    let(:test_module) { Module.new }

    before do
      described_class.register_module(:test_mod, test_module)
    end

    it "returns the module when registered" do
      expect(described_class.get_module(:test_mod)).to eq(test_module)
    end

    it "returns nil when module is NOT registered" do
      expect(described_class.get_module(:nonexistent)).to be_nil
    end
  end
  # rubocop:enable RSpecGuide/MinimumBehavioralCoverage

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

  # rubocop:disable RSpec/MultipleMemoizedHelpers, RSpecGuide/MinimumBehavioralCoverage
  describe "integration: full module lifecycle" do
    let(:model_class) do
      Class.new(ActiveRecord::Base) do
        self.table_name = "test_models"

        def self.name
          "IntegrationTestModel"
        end

        include ModelSettings::DSL
      end
    end

    let(:instance) { model_class.create! }
    let(:definition_hook_calls) { [] }
    let(:compilation_hook_calls) { [] }
    let(:before_change_calls) { [] }
    let(:after_change_calls) { [] }

    before do
      # Register option with validator
      described_class.register_option(:audit_level) do |setting, value|
        valid_levels = [:none, :basic, :full]
        unless valid_levels.include?(value)
          raise ArgumentError, "audit_level must be one of #{valid_levels.inspect}"
        end
      end

      # Register definition hook
      described_class.on_setting_defined do |setting, model|
        audit_level = setting.options[:audit_level]
        if audit_level
          definition_hook_calls << {setting: setting.name, model: model.name, level: audit_level}
        end
      end

      # Register compilation hook
      described_class.on_settings_compiled do |settings, model|
        audited = settings.select { |s| s.options[:audit_level] && s.options[:audit_level] != :none }
        compilation_hook_calls << {model: model.name, count: audited.size}
      end

      # Register before_change hook
      described_class.before_setting_change do |inst, setting, new_value|
        audit_level = setting.options[:audit_level]
        if audit_level && audit_level != :none
          before_change_calls << {instance_id: inst.id, setting: setting.name, new_value: new_value}
        end
      end

      # Register after_change hook
      described_class.after_setting_change do |inst, setting, old_val, new_val|
        audit_level = setting.options[:audit_level]
        if audit_level && audit_level != :none
          after_change_calls << {
            instance_id: inst.id,
            setting: setting.name,
            old_value: old_val,
            new_value: new_val,
            level: audit_level
          }
        end
      end
    end

    context "when defining settings with custom options" do
      before do
        model_class.setting :tracked_setting,
          type: :column,
          audit_level: :full

        model_class.setting :normal_setting,
          type: :column

        model_class.compile_settings!
      end

      it "executes definition hooks for each setting" do
        expect(definition_hook_calls).to contain_exactly(
          {setting: :tracked_setting, model: "IntegrationTestModel", level: :full}
        )
      end

      it "executes compilation hook once with all settings" do
        expect(compilation_hook_calls).to contain_exactly(
          {model: "IntegrationTestModel", count: 1}
        )
      end

      # rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations
      it "hooks are registered and ready for runtime execution" do
        # Verify hooks are registered
        expect(described_class.before_change_hooks).not_to be_empty
        expect(described_class.after_change_hooks).not_to be_empty

        # Simulate runtime execution
        tracked_setting_obj = model_class.find_setting(:tracked_setting)
        normal_setting_obj = model_class.find_setting(:normal_setting)
        mock_instance = instance_double(ActiveRecord::Base, id: 1)

        # Execute hooks for tracked setting
        described_class.execute_before_change_hooks(mock_instance, tracked_setting_obj, true)
        described_class.execute_after_change_hooks(mock_instance, tracked_setting_obj, false, true)

        # Execute hooks for normal setting
        described_class.execute_before_change_hooks(mock_instance, normal_setting_obj, true)
        described_class.execute_after_change_hooks(mock_instance, normal_setting_obj, false, true)

        # Verify tracked setting triggered hooks
        expect(before_change_calls).to contain_exactly(
          {instance_id: 1, setting: :tracked_setting, new_value: true}
        )
        expect(after_change_calls).to contain_exactly(
          hash_including(
            instance_id: 1,
            setting: :tracked_setting,
            old_value: false,
            new_value: true,
            level: :full
          )
        )
      end
      # rubocop:enable RSpec/ExampleLength, RSpec/MultipleExpectations
    end

    it "raises ArgumentError when option validation fails" do
      expect {
        model_class.setting :invalid_setting,
          type: :column,
          audit_level: :invalid_level
      }.to raise_error(ArgumentError, /audit_level must be one of/)
    end
  end
  # rubocop:enable RSpec/MultipleMemoizedHelpers, RSpecGuide/MinimumBehavioralCoverage
end
