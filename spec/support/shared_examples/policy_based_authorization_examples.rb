# frozen_string_literal: true

RSpec.shared_examples "policy-based authorization module" do |module_name, module_class|
  # Ensure module is registered
  before do
    unless ModelSettings::ModuleRegistry.module_registered?(module_name)
      ModelSettings::ModuleRegistry.register_module(module_name, module_class)
      ModelSettings::ModuleRegistry.register_exclusive_group(:authorization, module_name)
    end
  end

  # Only reset configuration, not module registry
  after do
    ModelSettings.reset_configuration!
  end

  let(:model_class) do
    test_module_name = "#{module_name.to_s.camelize}TestModel"
    test_module = module_class

    Class.new(TestModel) do
      define_singleton_method(:name) { test_module_name }

      include ModelSettings::DSL
      include test_module

      setting :billing_override,
        type: :column,
        authorize_with: :manage_billing?

      setting :api_access,
        type: :column,
        authorize_with: :admin?

      setting :system_config,
        type: :column,
        authorize_with: :admin?

      setting :display_name,
        type: :column
      # No authorization = unrestricted
    end
  end

  let(:instance) { model_class.create! }

  describe "module inclusion" do
    it "registers in ModuleRegistry and exclusive group" do
      aggregate_failures "registration" do
        expect(ModelSettings::ModuleRegistry.module_registered?(module_name)).to be true
        expect(ModelSettings::ModuleRegistry.exclusive_groups[:authorization]).to include(module_name)
      end
    end

    # rubocop:disable RSpecGuide/ContextSetup
    context "but when conflicting module is already included" do  # Organizational - setup in example
      # rubocop:enable RSpecGuide/ContextSetup
      it "raises ExclusiveGroupConflictError" do  # rubocop:disable RSpec/ExampleLength
        # Setup mock Roles module
        roles_mod = Module.new do
          extend ActiveSupport::Concern

          included do
            ModelSettings::ModuleRegistry.check_exclusive_conflict!(self, :roles)
          end
        end

        # Register mock Roles
        ModelSettings::ModuleRegistry.register_module(:roles, roles_mod)
        ModelSettings::ModuleRegistry.register_exclusive_group(:authorization, :roles)

        # Create model with Roles included
        conflicting_model_name = "Conflicting#{module_name.to_s.camelize}Model"
        conflicting_model_class = Class.new(TestModel) do
          define_singleton_method(:name) { conflicting_model_name }
          include ModelSettings::DSL
          include roles_mod
        end

        # Try to include the authorization module - should raise error
        expect {
          conflicting_model_class.include(module_class)
        }.to raise_error(ModelSettings::ModuleRegistry::ExclusiveGroupConflictError, /conflicts with :roles/)
      end
    end
  end

  describe ".authorization_for_setting" do
    it "returns authorization method for authorized settings" do
      aggregate_failures "authorization lookup" do
        expect(model_class.authorization_for_setting(:billing_override)).to eq(:manage_billing?)
        expect(model_class.authorization_for_setting(:api_access)).to eq(:admin?)
      end
    end

    # rubocop:disable RSpecGuide/ContextSetup
    context "when setting has no authorization" do  # Characteristic tested via setting name arg
      # rubocop:enable RSpecGuide/ContextSetup
      it "returns nil" do
        expect(model_class.authorization_for_setting(:display_name)).to be_nil
      end
    end

    # rubocop:disable RSpecGuide/ContextSetup
    context "when setting does not exist" do  # Characteristic tested via setting name arg
      # rubocop:enable RSpecGuide/ContextSetup
      it "returns nil" do
        expect(model_class.authorization_for_setting(:nonexistent)).to be_nil
      end
    end
  end

  describe ".settings_requiring" do
    it "returns settings requiring specific permissions" do
      aggregate_failures "permission filtering" do
        expect(model_class.settings_requiring(:admin?)).to match_array([:api_access, :system_config])
        expect(model_class.settings_requiring(:manage_billing?)).to eq([:billing_override])
      end
    end

    # rubocop:disable RSpecGuide/ContextSetup
    context "when no settings require the permission" do  # Characteristic tested via permission arg
      # rubocop:enable RSpecGuide/ContextSetup
      it "returns empty array" do
        result = model_class.settings_requiring(:nonexistent_permission?)

        expect(result).to be_empty
      end
    end
  end

  describe ".authorized_settings" do
    it "returns all settings with authorization" do
      result = model_class.authorized_settings

      expect(result).to match_array([:billing_override, :api_access, :system_config])
    end

    context "when no settings have authorization" do
      let(:unrestricted_model) do
        unrestricted_model_name = "Unrestricted#{module_name.to_s.camelize}Model"
        test_module = module_class

        Class.new(TestModel) do
          define_singleton_method(:name) { unrestricted_model_name }
          include ModelSettings::DSL
          include test_module

          setting :public_setting1, type: :column
          setting :public_setting2, type: :column
        end
      end

      it "returns empty array" do
        expect(unrestricted_model.authorized_settings).to be_empty
      end
    end
  end

  describe "authorize_with validation" do
    # rubocop:disable RSpecGuide/ContextSetup
    context "with valid Symbol" do  # Characteristic defined via setting definition
      # rubocop:enable RSpecGuide/ContextSetup
      it "accepts symbol as authorize_with" do
        valid_model_name = "Valid#{module_name.to_s.camelize}Model"
        test_module = module_class

        expect {
          Class.new(TestModel) do
            define_singleton_method(:name) { valid_model_name }
            include ModelSettings::DSL
            include test_module

            setting :test, type: :column, authorize_with: :admin?
          end
        }.not_to raise_error
      end
    end

    # rubocop:disable RSpecGuide/ContextSetup
    context "with invalid types" do  # Organizational - multiple related edge cases
      # rubocop:enable RSpecGuide/ContextSetup
      it "rejects String" do  # rubocop:disable RSpec/ExampleLength
        test_module = module_class

        expect {
          Class.new(TestModel) do
            def self.name
              "InvalidStringModel"
            end
            include ModelSettings::DSL
            include test_module

            setting :test, type: :column, authorize_with: "admin?"
          end
        }.to raise_error(ArgumentError, /must be a Symbol/)
      end

      it "rejects Array" do  # rubocop:disable RSpec/ExampleLength
        test_module = module_class

        expect {
          Class.new(TestModel) do
            def self.name
              "InvalidArrayModel"
            end
            include ModelSettings::DSL
            include test_module

            setting :test, type: :column, authorize_with: [:admin?, :finance?]
          end
        }.to raise_error(ArgumentError, /must be a Symbol/)
      end

      it "rejects Proc" do  # rubocop:disable RSpec/ExampleLength
        test_module = module_class

        expect {
          Class.new(TestModel) do
            def self.name
              "InvalidProcModel"
            end
            include ModelSettings::DSL
            include test_module

            setting :test, type: :column, authorize_with: -> { true }
          end
        }.to raise_error(ArgumentError, /must be a Symbol/)
      end

      it "provides helpful error message" do  # rubocop:disable RSpec/ExampleLength
        test_module = module_class

        expect {
          Class.new(TestModel) do
            def self.name
              "HelpfulErrorModel"
            end
            include ModelSettings::DSL
            include test_module

            setting :test, type: :column, authorize_with: [:admin]
          end
        }.to raise_error(ArgumentError, /Use Roles Module for simple role-based checks/)
      end
    end
  end

  # rubocop:disable RSpec/MultipleMemoizedHelpers
  describe "integration with mock policy" do
    let(:mock_record) { model_class.new }

    let(:mock_policy) do
      Class.new do
        attr_reader :user, :record

        def initialize(user, record)
          @user = user
          @record = record
        end

        def manage_billing?
          user.admin? || user.finance?
        end

        def admin?
          user.admin?
        end

        def permitted_settings
          record.class._authorized_settings.select do |_name, method|
            public_send(method)
          end.keys
        end
      end
    end

    let(:admin_user) { instance_double("User", admin?: true, finance?: false) }
    let(:finance_user) { instance_double("User", admin?: false, finance?: true) }
    let(:guest_user) { instance_double("User", admin?: false, finance?: false) }

    # rubocop:disable RSpecGuide/ContextSetup
    # rubocop:disable RSpec/MultipleMemoizedHelpers
    context "when user is admin" do  # Characteristic tested via user type
      # rubocop:enable RSpecGuide/ContextSetup
      it "permits all authorized settings" do
        policy = mock_policy.new(admin_user, mock_record)
        permitted = policy.permitted_settings

        expect(permitted).to match_array([:billing_override, :api_access, :system_config])
      end
    end

    # rubocop:disable RSpecGuide/ContextSetup
    # rubocop:disable RSpec/MultipleMemoizedHelpers
    context "when user is finance" do  # Characteristic tested via user type
      # rubocop:enable RSpecGuide/ContextSetup
      it "permits only billing settings" do
        policy = mock_policy.new(finance_user, mock_record)
        permitted = policy.permitted_settings

        expect(permitted).to eq([:billing_override])
      end
    end

    # rubocop:disable RSpecGuide/ContextSetup, RSpec/MultipleMemoizedHelpers
    context "when user is guest" do  # Characteristic tested via user type
      # rubocop:enable RSpecGuide/ContextSetup, RSpec/MultipleMemoizedHelpers
      it "permits no settings" do
        policy = mock_policy.new(guest_user, mock_record)
        permitted = policy.permitted_settings

        expect(permitted).to be_empty
      end
    end
  end

  describe "storage of authorization metadata" do
    it "stores authorize_with in _authorized_settings" do
      expect(model_class._authorized_settings).to include(
        billing_override: :manage_billing?,
        api_access: :admin?,
        system_config: :admin?
      )
    end

    it "does NOT store settings without authorization" do
      expect(model_class._authorized_settings).not_to have_key(:display_name)
    end

    context "when class_attribute isolation" do
      let(:other_model) do
        other_model_name = "Other#{module_name.to_s.camelize}Model"
        test_module = module_class

        Class.new(TestModel) do
          define_singleton_method(:name) { other_model_name }
          include ModelSettings::DSL
          include test_module

          setting :other_setting, type: :column, authorize_with: :other_permission?
        end
      end

      it "does NOT leak authorization between models" do
        aggregate_failures do
          expect(model_class._authorized_settings).not_to have_key(:other_setting)
          expect(other_model._authorized_settings).not_to have_key(:billing_override)
        end
      end
    end
  end

  describe "edge cases" do
    # rubocop:disable RSpecGuide/ContextSetup
    context "with multiple settings sharing same permission" do  # Characteristic defined via setting definitions
      # rubocop:enable RSpecGuide/ContextSetup
      it "groups them correctly" do
        settings_with_admin = model_class.settings_requiring(:admin?)

        expect(settings_with_admin).to contain_exactly(:api_access, :system_config)
      end
    end

    context "with no authorized settings" do
      let(:unrestricted_model) do
        unrestricted_model_name = "Unrestricted#{module_name.to_s.camelize}Model"
        test_module = module_class

        Class.new(TestModel) do
          define_singleton_method(:name) { unrestricted_model_name }
          include ModelSettings::DSL
          include test_module

          setting :public_setting1, type: :column
          setting :public_setting2, type: :column
        end
      end

      it "returns empty array for settings_requiring" do
        expect(unrestricted_model.settings_requiring(:admin?)).to be_empty
      end
    end
  end
end
