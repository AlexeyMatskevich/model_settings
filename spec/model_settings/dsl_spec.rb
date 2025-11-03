# frozen_string_literal: true

require "spec_helper"

# rubocop:disable RSpecGuide/MinimumBehavioralCoverage
RSpec.describe ModelSettings::DSL do
  # Create a test class that includes the DSL
  let(:test_class) do
    Class.new(ActiveRecord::Base) do
      self.table_name = "test_models"

      def self.name
        "TestModel"
      end

      include ModelSettings::DSL
    end
  end

  describe "ActiveRecord requirement" do
    context "when included in non-ActiveRecord class" do
      let(:plain_class) { Class.new }

      it "raises error" do
        expect {
          plain_class.include(described_class)
        }.to raise_error(ModelSettings::Error, /can only be included in ActiveRecord models/)
      end
    end

    context "when included in ActiveRecord model" do
      let(:ar_class) { test_class }

      it "includes successfully" do
        expect { ar_class }.not_to raise_error
      end
    end
  end

  describe ".setting" do
    # Base case: simple setting without options
    context "without options" do
      before { test_class.setting :enabled }

      let(:setting) { test_class.find_setting(:enabled) }

      it "creates and stores Setting object", :aggregate_failures do
        expect(setting).to be_a(ModelSettings::Setting)
        expect(setting.name).to eq(:enabled)
        expect(test_class.settings).to include(setting)
        expect(test_class.settings.first.name).to eq(:enabled)
      end
    end

    context "with options" do
      before do
        test_class.setting :premium_mode,
          type: :column,
          default: false,
          description: "Premium features"
      end

      let(:setting) { test_class.find_setting(:premium_mode) }

      it "passes type to Setting object" do
        expect(setting.type).to eq(:column)
      end

      it "passes default to Setting object" do
        expect(setting.default).to be false
      end

      it "passes description to Setting object" do
        expect(setting.description).to eq("Premium features")
      end
    end

    context "with single level nested settings" do
      before do
        test_class.setting :features do
          setting :ai_enabled
          setting :analytics_enabled
        end
      end

      let(:parent) { test_class.find_setting(:features) }
      let(:child) { parent.find_child(:ai_enabled) }

      it "creates hierarchical structure", :aggregate_failures do
        expect(parent).to be_a(ModelSettings::Setting)
        expect(parent.children.size).to eq(2)
        expect(child.parent).to eq(parent)
        expect(parent.children).to include(child)
      end
    end

    context "with multiple levels nested settings" do
      before do
        test_class.setting :billing do
          setting :invoices do
            setting :auto_send
          end
        end
      end

      let(:billing) { test_class.find_setting(:billing) }
      let(:invoices) { billing.find_child(:invoices) }
      let(:auto_send) { invoices.find_child(:auto_send) }

      it "supports nested path" do
        expect(auto_send.path).to eq([:billing, :invoices, :auto_send])
      end

      it "traverses to root from deep child" do
        expect(auto_send.root).to eq(billing)
      end

      it "collects all descendants from root" do
        expect(billing.descendants).to match_array([invoices, auto_send])
      end

      it "navigates through hierarchy", :aggregate_failures do
        found = billing.find_child(:invoices)
        expect(found).to eq(invoices)
        expect(found.find_child(:auto_send)).to eq(auto_send)
      end
    end

    context "with multiple settings" do
      before do
        test_class.setting :first
        test_class.setting :second
        test_class.setting :third
      end

      it "maintains all settings" do
        expect(test_class.settings.size).to eq(3)
      end

      it "keeps settings separate" do
        expect(test_class.settings.map(&:name)).to match_array([:first, :second, :third])
      end
    end
  end

  describe ".settings" do
    context "when settings are defined" do
      before do
        test_class.setting :first
        test_class.setting :second
      end

      it "returns all root settings" do
        expect(test_class.settings.size).to eq(2)
      end

      context "with nested settings" do
        before do
          test_class.setting :parent do
            setting :child
          end
        end

        it "includes root settings" do
          expect(test_class.settings.size).to eq(3) # first, second, parent
        end

        it "includes parent setting" do
          expect(test_class.settings.map(&:name)).to include(:first, :second, :parent)
        end

        it "does NOT include nested settings" do
          expect(test_class.settings.map(&:name)).not_to include(:child)
        end
      end
    end

    context "when no settings are defined" do
      before { test_class }

      it "returns empty array" do
        expect(test_class.settings).to be_empty
      end
    end
  end

  describe ".find_setting" do
    before do
      test_class.setting :enabled
      test_class.setting :features do
        setting :ai
        setting :analytics do
          setting :tracking
        end
      end
    end

    it "finds root setting by symbol" do
      setting = test_class.find_setting(:enabled)
      expect(setting.name).to eq(:enabled)
    end

    it "finds root setting by string" do
      setting = test_class.find_setting("enabled")
      expect(setting.name).to eq(:enabled)
    end

    # rubocop:disable RSpecGuide/ContextSetup
    context "but when finding nested setting" do  # Organizational/characteristic context
      # rubocop:enable RSpecGuide/ContextSetup
      # rubocop:disable RSpecGuide/ContextSetup
      context "with single level path" do  # Organizational/characteristic context
        # rubocop:enable RSpecGuide/ContextSetup
        it "finds by path array" do
          setting = test_class.find_setting([:features, :ai])
          expect(setting.name).to eq(:ai)
        end
      end

      # rubocop:disable RSpecGuide/ContextSetup
      context "with deep path" do  # Organizational/characteristic context
        # rubocop:enable RSpecGuide/ContextSetup
        it "finds deeply nested setting" do
          setting = test_class.find_setting([:features, :analytics, :tracking])
          expect(setting.name).to eq(:tracking)
        end
      end
    end

    # rubocop:disable RSpecGuide/ContextSetup
    context "when setting does NOT exist" do  # Organizational/characteristic context
      # rubocop:enable RSpecGuide/ContextSetup
      it "returns nil for nonexistent root setting" do
        expect(test_class.find_setting(:nonexistent)).to be_nil
      end

      it "returns nil for nonexistent nested setting" do
        expect(test_class.find_setting([:features, :nonexistent])).to be_nil
      end

      it "returns nil for invalid path" do
        expect(test_class.find_setting([:nonexistent, :child])).to be_nil
      end
    end
    # rubocop:enable RSpecGuide/ContextSetup
  end

  # rubocop:disable RSpecGuide/MinimumBehavioralCoverage
  describe ".root_settings" do
    before do
      test_class.setting :root1
      test_class.setting :root2 do
        setting :child1
        setting :child2
      end
      test_class.setting :root3
    end

    let(:roots) { test_class.root_settings }

    it "returns only root-level settings", :aggregate_failures do
      expect(roots.size).to eq(3)
      expect(roots.map(&:name)).to match_array([:root1, :root2, :root3])
      expect(roots.map(&:name)).not_to include(:child1, :child2)
    end
  end
  # rubocop:enable RSpecGuide/MinimumBehavioralCoverage

  # rubocop:disable RSpecGuide/MinimumBehavioralCoverage
  describe ".leaf_settings" do
    before do
      test_class.setting :standalone
      test_class.setting :parent do
        setting :child1
        setting :child2 do
          setting :grandchild
        end
      end
    end

    let(:leaves) { test_class.leaf_settings }

    it "returns only leaf settings", :aggregate_failures do
      expect(leaves.map(&:name)).to match_array([:standalone, :child1, :grandchild])
      expect(leaves.map(&:name)).not_to include(:parent, :child2)
    end
  end
  # rubocop:enable RSpecGuide/MinimumBehavioralCoverage

  # rubocop:disable RSpecGuide/MinimumBehavioralCoverage
  describe ".all_settings_recursive" do
    before do
      test_class.setting :root1
      test_class.setting :root2 do
        setting :child1
        setting :child2 do
          setting :grandchild
        end
      end
    end

    let(:all_settings) { test_class.all_settings_recursive }

    it "returns all settings including nested", :aggregate_failures do
      expect(all_settings.size).to eq(5)
      expect(all_settings.map(&:name)).to match_array([:root1, :root2, :child1, :child2, :grandchild])
      expect(all_settings.map(&:name)).to include(:root2, :child2)
      expect(all_settings.map(&:name)).to include(:root1, :child1, :grandchild)
    end
  end
  # rubocop:enable RSpecGuide/MinimumBehavioralCoverage

  describe "class isolation" do
    let(:test_class_a) do
      Class.new(ActiveRecord::Base) do
        self.table_name = "test_models"

        def self.name
          "TestModelA"
        end

        include ModelSettings::DSL
      end
    end

    let(:test_class_b) do
      Class.new(ActiveRecord::Base) do
        self.table_name = "test_models"

        def self.name
          "TestModelB"
        end

        include ModelSettings::DSL
      end
    end

    before do
      test_class_a.setting :setting_a
      test_class_b.setting :setting_b
    end

    context "when checking class A" do
      let(:klass) { test_class_a }

      it "isolates settings from other classes", :aggregate_failures do
        expect(klass.settings.map(&:name)).to eq([:setting_a])
        expect(klass.find_setting(:setting_a)).not_to be_nil
        expect(klass.find_setting(:setting_b)).to be_nil
      end
    end

    context "when checking class B" do
      let(:klass) { test_class_b }

      it "isolates settings from other classes", :aggregate_failures do
        expect(klass.settings.map(&:name)).to eq([:setting_b])
        expect(klass.find_setting(:setting_b)).not_to be_nil
        expect(klass.find_setting(:setting_a)).to be_nil
      end
    end
  end

  # Configuration auto-include functionality
  describe "auto-include default modules" do
    subject(:include_dsl) do
      Class.new(ActiveRecord::Base) do
        self.table_name = "test_models"
        include ModelSettings::DSL
      end
    end

    around do |example|
      example.run
    ensure
      ModelSettings.reset_configuration!
    end

    # Happy path: modules are auto-included
    context "when default_modules is configured" do
      before do
        ModelSettings.configure do |config|
          config.default_modules = [:roles, :i18n]
        end
      end

      it "auto-includes Roles module" do
        expect(include_dsl.included_modules).to include(ModelSettings::Modules::Roles)
      end

      it "auto-includes I18n module" do
        expect(include_dsl.included_modules).to include(ModelSettings::Modules::I18n)
      end

      it "tracks active modules" do
        expect(include_dsl._active_modules).to match_array([:roles, :i18n])
      end
    end

    # Reverse case: empty configuration
    context "but when default_modules is empty" do
      before do
        ModelSettings.configure do |config|
          config.default_modules = []
        end
      end

      it "does not include optional modules" do
        optional_modules = [
          ModelSettings::Modules::Roles,
          ModelSettings::Modules::Pundit,
          ModelSettings::Modules::ActionPolicy
        ]
        expect(include_dsl.included_modules).not_to include(*optional_modules)
      end

      it "only includes I18n module (for backward compatibility)" do
        expect(include_dsl._active_modules).to eq([:i18n])
      end
    end

    context "but when default_modules is nil" do
      before do
        ModelSettings.configure do |config|
          config.default_modules = nil
        end
      end

      it "does not raise error" do
        expect { include_dsl }.not_to raise_error
      end
    end

    # Error handling: unknown module
    context "but when configured module does not exist" do
      before do
        ModelSettings.configure do |config|
          config.default_modules = [:nonexistent_module]
        end
      end

      it "skips unknown module gracefully" do
        expect { include_dsl }.not_to raise_error
      end

      it "does not track unknown module (only I18n)" do
        expect(include_dsl._active_modules).to eq([:i18n])
      end
    end

    # Edge case: module already included manually
    context "when module is already included" do
      subject(:include_dsl) do
        Class.new(ActiveRecord::Base) do
          self.table_name = "test_models"
          include ModelSettings::Modules::Roles # Manual include first
          include ModelSettings::DSL
        end
      end

      before do
        ModelSettings.configure do |config|
          config.default_modules = [:roles]
        end
      end

      it "does not include module twice" do
        roles_count = include_dsl.included_modules.count(ModelSettings::Modules::Roles)
        expect(roles_count).to eq(1)
      end
    end

    # Variant: testing with single module
    context "with single module configured" do
      before do
        ModelSettings.configure do |config|
          config.default_modules = [:i18n]
        end
      end

      it "includes the configured module" do
        expect(include_dsl.included_modules).to include(ModelSettings::Modules::I18n)
      end

      it "tracks the active module" do
        expect(include_dsl._active_modules).to eq([:i18n])
      end
    end

    # Partial list (some modules exist, some don't)
    context "with mixed valid and invalid modules" do
      before do
        ModelSettings.configure do |config|
          config.default_modules = [:roles, :nonexistent, :i18n]
        end
      end

      it "includes only valid modules" do
        expect(include_dsl.included_modules).to include(
          ModelSettings::Modules::Roles,
          ModelSettings::Modules::I18n
        )
      end

      it "tracks only valid modules" do
        expect(include_dsl._active_modules).to match_array([:roles, :i18n])
      end
    end
  end

  describe ".settings_config" do
    around do |example|
      # Save registry state
      saved_state = save_registry_state

      example.run
    ensure
      ModelSettings.reset_configuration!
      # Restore registry state instead of reset to preserve callbacks
      restore_registry_state(saved_state)
    end

    context "when configuring inheritable_options" do
      before do
        test_class.settings_config(inheritable_options: [:authorize_with, :viewable_by])
      end

      it "stores model-specific inheritable options" do
        expect(test_class._model_inheritable_options).to eq([:authorize_with, :viewable_by])
      end
    end

    context "when configuring multiple options" do
      before do
        test_class.settings_config(
          inherit_authorization: true,
          inheritable_options: [:custom_option]
        )
      end

      it "stores inherit_authorization" do
        expect(test_class._settings_inherit_authorization).to be true
      end

      it "stores inheritable_options" do
        expect(test_class._model_inheritable_options).to eq([:custom_option])
      end
    end

    context "when inheritable_options is single value" do
      before do
        test_class.settings_config(inheritable_options: :single_option)
      end

      it "converts to array" do
        expect(test_class._model_inheritable_options).to eq([:single_option])
      end
    end
  end

  describe ".inheritable_options" do
    around do |example|
      # Save registry state
      saved_state = save_registry_state

      example.run
    ensure
      ModelSettings.reset_configuration!
      # Restore registry state instead of reset to preserve callbacks
      restore_registry_state(saved_state)
    end

    # rubocop:disable RSpec/MultipleExpectations
    it "returns empty array by default" do
      # May include core options registered with auto_include: true from loaded modules
      # The important thing is no model-specific options are configured
      result = test_class.inheritable_options
      expect(result).to be_an(Array)
      # Should not include any model-specific options (only potentially core options)
      expect(result).not_to include(:model_option, :global_option, :module_option)
    end
    # rubocop:enable RSpec/MultipleExpectations

    context "when model-specific options are configured" do
      before do
        test_class.settings_config(inheritable_options: [:model_option])
      end

      it "returns model-specific options" do
        expect(test_class.inheritable_options).to eq([:model_option])
      end

      it "ignores global and module-registered options" do
        ModelSettings.configuration.add_inheritable_option(:global_option)
        ModelSettings::ModuleRegistry.register_inheritable_option(:module_option)

        expect(test_class.inheritable_options).to eq([:model_option])
      end
    end

    context "when no model-specific options are configured" do
      before do
        ModelSettings.configuration.add_inheritable_option(:global_option)
        ModelSettings::ModuleRegistry.register_inheritable_option(:module_option)
      end

      # rubocop:disable RSpec/MultipleExpectations
      it "merges global and module-registered options" do
        # May also include core options registered with auto_include: true
        result = test_class.inheritable_options
        expect(result).to be_an(Array)
        expect(result).to include(:global_option, :module_option)
      end
      # rubocop:enable RSpec/MultipleExpectations
    end

    context "but when global and module options overlap" do
      before do
        ModelSettings.configuration.add_inheritable_option(:shared_option)
        ModelSettings::ModuleRegistry.register_inheritable_option(:shared_option)
      end

      # rubocop:disable RSpec/MultipleExpectations
      it "deduplicates options" do
        # May also include core options, but :shared_option should appear only once
        result = test_class.inheritable_options
        expect(result).to be_an(Array)
        expect(result).to include(:shared_option)
        expect(result.count(:shared_option)).to eq(1)
      end
      # rubocop:enable RSpec/MultipleExpectations
    end
  end

  # rubocop:disable RSpecGuide/MinimumBehavioralCoverage
  describe ".resolve_module" do
    # Happy path: built-in modules
    it "resolves :roles to Roles module" do
      expect(described_class.resolve_module(:roles)).to eq(ModelSettings::Modules::Roles)
    end

    it "resolves :pundit to Pundit module" do
      expect(described_class.resolve_module(:pundit)).to eq(ModelSettings::Modules::Pundit)
    end

    it "resolves :action_policy to ActionPolicy module" do
      expect(described_class.resolve_module(:action_policy)).to eq(ModelSettings::Modules::ActionPolicy)
    end

    it "resolves :i18n to I18n module" do
      expect(described_class.resolve_module(:i18n)).to eq(ModelSettings::Modules::I18n)
    end

    # Reverse case: unknown module
    it "returns nil for nonexistent module" do
      expect(described_class.resolve_module(:nonexistent)).to be_nil
    end
  end
  # rubocop:enable RSpecGuide/MinimumBehavioralCoverage

  describe ".module_metadata?" do
    let(:test_class) do
      Class.new(TestModel) do
        def self.name
          "ModuleMetadataTestModel"
        end

        include ModelSettings::DSL
        include ModelSettings::Modules::Roles

        setting :feature, type: :column, viewable_by: :admin
        setting :other, type: :column
      end
    end

    before do
      test_class.compile_settings!
    end

    context "when module has metadata for setting" do
      it "returns true for setting with viewable_by" do
        expect(test_class.module_metadata?(:roles, :feature)).to be true
      end
    end

    context "when module has no metadata for setting" do
      it "returns false for setting without viewable_by" do
        expect(test_class.module_metadata?(:roles, :other)).to be false
      end
    end

    context "when setting does not exist" do
      it "returns false" do
        expect(test_class.module_metadata?(:roles, :nonexistent)).to be false
      end
    end

    context "when module is not active" do
      it "returns false" do
        expect(test_class.module_metadata?(:pundit, :feature)).to be false
      end
    end
  end

  describe ".copy_setting_recursively" do
    let(:parent_class) do
      Class.new(TestModel) do
        def self.name
          "CopyParentModel"
        end

        include ModelSettings::DSL

        setting :root, type: :column do
          setting :level1, type: :column do
            setting :level2, type: :column
          end
          setting :sibling, type: :column
        end
      end
    end

    let(:child_class) do
      Class.new(TestModel) do
        def self.name
          "CopyChildModel"
        end

        include ModelSettings::DSL
      end
    end

    before do
      parent_class.compile_settings!
    end

    context "when copying setting with children" do
      it "copies setting and all descendants" do
        root_setting = parent_class.find_setting(:root)
        copied = child_class.send(:copy_setting_recursively, root_setting)

        expect(copied).to have_attributes(
          name: :root,
          children: have_attributes(size: 2)
        )
        expect(copied.children.map(&:name)).to contain_exactly(:level1, :sibling)
      end

      it "recursively copies nested children" do
        root_setting = parent_class.find_setting(:root)
        copied = child_class.send(:copy_setting_recursively, root_setting)

        level1 = copied.children.find { |c| c.name == :level1 }
        expect(level1.children.size).to eq(1)
        expect(level1.children.first.name).to eq(:level2)
      end

      it "creates new Setting objects (not references)" do
        root_setting = parent_class.find_setting(:root)
        copied = child_class.send(:copy_setting_recursively, root_setting)

        expect(copied).not_to equal(root_setting)
        expect(copied.object_id).not_to eq(root_setting.object_id)
      end
    end

    context "when copying leaf setting without children" do
      it "copies setting without children" do
        leaf_setting = parent_class.find_setting([:root, :sibling])
        copied = child_class.send(:copy_setting_recursively, leaf_setting)

        expect(copied.name).to eq(:sibling)
        expect(copied.children).to be_empty
      end
    end
  end

  describe ".settings_debug" do
    let(:debug_class) do
      Class.new(TestModel) do
        def self.name
          "DebugTestModel"
        end

        include ModelSettings::DSL
        include ModelSettings::Modules::Roles

        setting :active, type: :column, deprecated: "Use new_active instead"
        setting :feature, type: :column, cascade: {enable: true, disable: true}
        setting :sync_setting, type: :column, sync: {target: :active, mode: :forward}
        setting :json_setting, type: :json, storage: {column: :settings_data}
      end
    end

    before do
      debug_class.compile_settings!
    end

    describe "basic behavior" do
      it "outputs without error" do
        expect { debug_class.settings_debug }.not_to raise_error
      end

      it "returns nil" do
        expect(debug_class.settings_debug).to be_nil
      end
    end

    describe "active modules section" do
      context "when modules are active" do
        it "shows active module names" do
          expect { debug_class.settings_debug }.to output(/Active Modules/).to_stdout
          expect { debug_class.settings_debug }.to output(/roles/).to_stdout
        end
      end
    end

    describe "deprecated settings section" do
      context "when deprecated settings exist" do
        it "lists deprecated settings with reasons" do
          expect { debug_class.settings_debug }.to output(/Deprecated Settings: 1/).to_stdout
          expect { debug_class.settings_debug }.to output(/active/).to_stdout
          expect { debug_class.settings_debug }.to output(/Use new_active instead/).to_stdout
        end
      end

      context "but when no deprecated settings exist" do
        let(:clean_class) do
          Class.new(TestModel) do
            def self.name
              "CleanModel"
            end

            include ModelSettings::DSL

            setting :feature, type: :column
          end
        end

        before do
          clean_class.compile_settings!
        end

        it "shows zero count" do
          expect { clean_class.settings_debug }.to output(/Deprecated Settings: 0/).to_stdout
        end
      end
    end

    describe "cascade configuration section" do
      context "when settings have cascades" do
        it "shows cascade directions" do
          expect { debug_class.settings_debug }.to output(/Settings with Cascades/).to_stdout
          expect { debug_class.settings_debug }.to output(/feature.*enable, disable/).to_stdout
        end
      end
    end

    describe "sync relationships section" do
      context "when settings have syncs" do
        it "shows sync targets and modes" do
          expect { debug_class.settings_debug }.to output(/Settings with Syncs/).to_stdout
          expect { debug_class.settings_debug }.to output(/sync_setting → active \(forward\)/).to_stdout
        end
      end

      context "when sync execution order exists" do
        it "shows execution order" do
          expect { debug_class.settings_debug }.to output(/Sync Execution Order/).to_stdout
        end
      end
    end

    describe "settings by type section" do
      context "when model has multiple adapter types" do
        it "groups settings by adapter type" do
          expect { debug_class.settings_debug }.to output(/Settings by Type/).to_stdout
          expect { debug_class.settings_debug }.to output(/column:/).to_stdout
          expect { debug_class.settings_debug }.to output(/json:/).to_stdout
        end
      end
    end
  end

  describe ".create_adapter_for (error handling)" do
    let(:error_class) do
      Class.new(TestModel) do
        def self.name
          "ErrorTestModel"
        end

        include ModelSettings::DSL
      end
    end

    context "when storage type is unknown" do
      it "raises ArgumentError with helpful message" do
        setting = ModelSettings::Setting.new(
          :invalid,
          {type: :invalid_type, model_class: error_class}
        )

        expect {
          error_class.create_adapter_for(setting)
        }.to raise_error(ArgumentError, /Unknown storage type/)
      end
    end
  end

  describe ".settings_modules" do
    let(:array_config_class) do
      Class.new(TestModel) do
        def self.name
          "ArrayConfigModel"
        end

        include ModelSettings::DSL
      end
    end

    before do
      @saved_state = save_registry_state
    end

    after do
      restore_registry_state(@saved_state)
    end

    context "with single module" do
      it "includes module" do
        array_config_class.settings_modules(:roles)

        expect(array_config_class._active_modules).to include(:roles)
      end
    end

    context "with array of modules" do
      it "includes all modules from array" do
        array_config_class.settings_modules([:roles, :i18n])

        expect(array_config_class._active_modules).to include(:roles, :i18n)
      end
    end

    context "with nested arrays" do
      it "flattens and includes all modules" do
        array_config_class.settings_modules([[:roles], [:i18n]])

        expect(array_config_class._active_modules).to include(:roles, :i18n)
      end
    end

    context "with multiple arguments" do
      it "includes all modules" do
        array_config_class.settings_modules(:roles, :i18n, :pundit)

        expect(array_config_class._active_modules).to include(:roles, :i18n, :pundit)
      end
    end

    context "with mixed arrays and symbols" do
      it "handles mixed arguments" do
        array_config_class.settings_modules([:roles], :i18n, [:pundit])

        expect(array_config_class._active_modules).to include(:roles, :i18n, :pundit)
      end
    end
  end
end
