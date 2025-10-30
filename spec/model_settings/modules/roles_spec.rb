# frozen_string_literal: true

require "spec_helper"

RSpec.describe ModelSettings::Modules::Roles do
  # Ensure module is registered (in case other tests reset the registry)
  before do
    unless ModelSettings::ModuleRegistry.module_registered?(:roles)
      ModelSettings::ModuleRegistry.register_module(:roles, ModelSettings::Modules::Roles)
      ModelSettings::ModuleRegistry.register_exclusive_group(:authorization, :roles)
    end
  end

  # Only reset configuration, not module registry
  after do
    ModelSettings.reset_configuration!
  end

  let(:model_class) do
    Class.new(TestModel) do
      def self.name
        "RolesTestModel"
      end

      include ModelSettings::DSL
      include ModelSettings::Modules::Roles

      # Use existing columns from TestModel
      setting :premium_mode,  # billing substitute
              type: :column,
              viewable_by: [:admin, :finance, :manager],
              editable_by: [:admin, :finance]

      setting :notifications,  # public_setting substitute
              type: :column,
              viewable_by: :all,
              editable_by: [:admin]

      setting :feature,  # admin_only substitute
              type: :column,
              viewable_by: [:admin],
              editable_by: [:admin]

      setting :enabled,  # unrestricted substitute
              type: :column
    end
  end

  let(:instance) { model_class.create! }

  describe "module inclusion" do
    it "registers in ModuleRegistry and exclusive group" do
      aggregate_failures "registration" do
        expect(ModelSettings::ModuleRegistry.module_registered?(:roles)).to be true
        expect(ModelSettings::ModuleRegistry.exclusive_groups[:authorization]).to include(:roles)
      end
    end

    context "but when conflicting module is already included" do
      it "raises ExclusiveGroupConflictError" do
        # Setup mock Pundit module
        pundit_mod = Module.new do
          extend ActiveSupport::Concern
          included do
            ModelSettings::ModuleRegistry.check_exclusive_conflict!(self, :pundit)
          end
        end

        # Register mock Pundit
        ModelSettings::ModuleRegistry.register_module(:pundit, pundit_mod)
        ModelSettings::ModuleRegistry.register_exclusive_group(:authorization, :pundit)

        # Create model with Pundit included
        conflicting_model_class = Class.new(TestModel) do
          def self.name; "ConflictingModel"; end
          include ModelSettings::DSL
          include pundit_mod
        end

        # Try to include Roles - should raise error
        expect {
          conflicting_model_class.include(ModelSettings::Modules::Roles)
        }.to raise_error(ModelSettings::ModuleRegistry::ExclusiveGroupConflictError, /conflicts with :pundit/)
      end
    end
  end

  describe ".settings_viewable_by" do
    it "returns settings viewable by finance role" do
      result = model_class.settings_viewable_by(:finance)

      expect(result).to match_array([:premium_mode, :notifications])
    end

    it "returns settings viewable by manager role" do
      result = model_class.settings_viewable_by(:manager)

      expect(result).to match_array([:premium_mode, :notifications])
    end

    it "returns settings viewable by admin role" do
      result = model_class.settings_viewable_by(:admin)

      expect(result).to match_array([:premium_mode, :notifications, :feature])
    end

    context "with :all permission" do
      it "includes setting for any role" do
        result = model_class.settings_viewable_by(:user)

        expect(result).to include(:notifications)
      end
    end

    context "when role has no permissions" do
      it "returns only :all settings" do
        result = model_class.settings_viewable_by(:guest)

        expect(result).to eq([:notifications])
      end
    end
  end

  describe ".settings_editable_by" do
    it "returns settings editable by finance role" do
      result = model_class.settings_editable_by(:finance)

      expect(result).to match_array([:premium_mode])
    end

    it "returns settings editable by manager role" do
      result = model_class.settings_editable_by(:manager)

      expect(result).to be_empty
    end

    it "returns settings editable by admin role" do
      result = model_class.settings_editable_by(:admin)

      expect(result).to match_array([:premium_mode, :notifications, :feature])
    end

    context "when role cannot edit any settings" do
      it "returns empty array" do
        result = model_class.settings_editable_by(:guest)

        expect(result).to be_empty
      end
    end
  end

  describe "#can_view_setting?" do
    context "when setting has viewable_by restriction" do
      it "returns true for authorized role" do
        expect(instance.can_view_setting?(:premium_mode, :finance)).to be true
      end

      it "returns false for unauthorized role" do
        expect(instance.can_view_setting?(:premium_mode, :guest)).to be false
      end
    end

    context "with :all permission" do
      it "returns true for any role" do
        aggregate_failures do
          expect(instance.can_view_setting?(:notifications, :guest)).to be true
          expect(instance.can_view_setting?(:notifications, :admin)).to be true
          expect(instance.can_view_setting?(:notifications, :user)).to be true
        end
      end
    end

    context "when setting has no restrictions" do
      it "returns true for any role" do
        expect(instance.can_view_setting?(:enabled, :guest)).to be true
      end
    end
  end

  describe "#can_edit_setting?" do
    context "when setting has editable_by restriction" do
      it "returns true for authorized role" do
        expect(instance.can_edit_setting?(:premium_mode, :finance)).to be true
      end

      it "returns false for unauthorized role" do
        expect(instance.can_edit_setting?(:premium_mode, :manager)).to be false
      end
    end

    context "when setting has viewable_by :all but restricted editable_by" do
      it "returns true only for authorized editors" do
        aggregate_failures do
          expect(instance.can_edit_setting?(:notifications, :admin)).to be true
          expect(instance.can_edit_setting?(:notifications, :guest)).to be false
          expect(instance.can_edit_setting?(:notifications, :user)).to be false
        end
      end
    end

    context "when setting has no restrictions" do
      it "returns true for any role" do
        expect(instance.can_edit_setting?(:enabled, :guest)).to be true
      end
    end
  end

  describe "role normalization" do
    let(:model_class) do
      Class.new(TestModel) do
        def self.name; "NormalizationTestModel"; end

        include ModelSettings::DSL
        include ModelSettings::Modules::Roles

        # Single role as symbol (uses existing columns)
        setting :premium,
                type: :column,
                viewable_by: :admin,
                editable_by: :admin

        # Multiple roles as array
        setting :feature,
                type: :column,
                viewable_by: [:admin, :finance],
                editable_by: [:admin, :finance]

        # :all special value
        setting :enabled,
                type: :column,
                viewable_by: :all,
                editable_by: [:admin]

        # Nil values (unrestricted)
        setting :notifications,
                type: :column
      end
    end

    context "with single symbol" do
      it "normalizes to array for both viewable_by and editable_by" do
        roles = model_class._settings_roles[:premium]

        aggregate_failures do
          expect(roles[:viewable_by]).to eq([:admin])
          expect(roles[:editable_by]).to eq([:admin])
        end
      end
    end

    context "with array of symbols" do
      it "keeps array as is" do
        roles = model_class._settings_roles[:feature]

        aggregate_failures do
          expect(roles[:viewable_by]).to eq([:admin, :finance])
          expect(roles[:editable_by]).to eq([:admin, :finance])
        end
      end
    end

    context "with :all special value" do
      it "preserves :all for viewable_by" do
        roles = model_class._settings_roles[:enabled]

        expect(roles[:viewable_by]).to eq(:all)
      end
    end

    context "with nil values (no restrictions)" do
      it "does NOT store in _settings_roles hash" do
        expect(model_class._settings_roles).not_to have_key(:notifications)
      end
    end
  end

  describe "edge cases" do
    context "with partial permissions (viewable but NOT editable)" do
      it "allows viewing but denies editing for manager role" do
        aggregate_failures do
          expect(instance.can_view_setting?(:premium_mode, :manager)).to be true
          expect(instance.can_edit_setting?(:premium_mode, :manager)).to be false
        end
      end
    end

    context "with string vs symbol role consistency" do
      it "treats string and symbol roles identically" do
        aggregate_failures do
          expect(model_class.settings_viewable_by("finance")).to eq(model_class.settings_viewable_by(:finance))
          expect(model_class.settings_editable_by("admin")).to eq(model_class.settings_editable_by(:admin))
        end
      end
    end

    context "with non-existent setting name" do
      it "returns true for unrestricted access" do
        aggregate_failures do
          expect(instance.can_view_setting?(:nonexistent, :guest)).to be true
          expect(instance.can_edit_setting?(:nonexistent, :guest)).to be true
        end
      end
    end
  end

  describe "integration with controller" do
    context "when filtering params by role" do
      it "returns only editable settings for finance role" do
        editable_settings = model_class.settings_editable_by(:finance)

        expect(editable_settings).to match_array([:premium_mode])
      end

      it "returns all controlled settings for admin role" do
        editable_settings = model_class.settings_editable_by(:admin)

        expect(editable_settings).to match_array([:premium_mode, :notifications, :feature])
      end

      context "but when role has no edit permissions" do
        it "returns empty array for guest role" do
          editable_settings = model_class.settings_editable_by(:guest)

          expect(editable_settings).to be_empty
        end
      end
    end
  end
end
