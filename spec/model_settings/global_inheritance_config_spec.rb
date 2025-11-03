# frozen_string_literal: true

require "spec_helper"

# rubocop:disable RSpecGuide/MinimumBehavioralCoverage, RSpec/DescribeClass
RSpec.describe "Global Authorization Inheritance Configuration" do
  after do
    ModelSettings.reset_configuration!
  end

  describe "global inherit_authorization configuration" do
    context "with Roles module" do
      let(:model_class) do
        Class.new(TestModel) do
          def self.name
            "GlobalConfigRolesModel"
          end

          include ModelSettings::DSL
          include ModelSettings::Modules::Roles
        end
      end

      context "when global config is true" do
        before do
          ModelSettings.configure do |config|
            config.inherit_authorization = true
          end

          model_class.class_eval do
            setting :parent, viewable_by: [:admin], editable_by: [:admin] do
              setting :child
            end
          end
        end

        it "child inherits viewable_by from parent" do
          expect(model_class.settings_viewable_by(:admin)).to include(:child)
        end

        it "child inherits editable_by from parent" do
          expect(model_class.settings_editable_by(:admin)).to include(:child)
        end
      end

      context "when global config is false" do
        before do
          ModelSettings.configure do |config|
            config.inherit_authorization = false
          end

          model_class.class_eval do
            setting :parent, viewable_by: [:admin] do
              setting :child
            end
          end
        end

        it "child does NOT inherit authorization" do
          expect(model_class.settings_viewable_by(:admin)).not_to include(:child)
        end
      end
    end

    context "with Pundit module" do
      let(:model_class) do
        Class.new(TestModel) do
          def self.name
            "GlobalConfigPunditModel"
          end

          include ModelSettings::DSL
          include ModelSettings::Modules::Pundit
        end
      end

      context "when global config is true" do
        before do
          ModelSettings.configure do |config|
            config.inherit_authorization = true
          end

          model_class.class_eval do
            setting :parent, authorize_with: :admin? do
              setting :child
            end
          end
        end

        it "child inherits from parent" do
          expect(model_class.authorization_for_setting(:child)).to eq(:admin?)
        end
      end

      context "when global config is false" do
        before do
          ModelSettings.configure do |config|
            config.inherit_authorization = false
          end

          model_class.class_eval do
            setting :parent, authorize_with: :admin? do
              setting :child
            end
          end
        end

        it "child does NOT inherit" do
          expect(model_class.authorization_for_setting(:child)).to be_nil
        end
      end
    end

    context "with ActionPolicy module" do
      let(:model_class) do
        Class.new(TestModel) do
          def self.name
            "GlobalConfigActionPolicyModel"
          end

          include ModelSettings::DSL
          include ModelSettings::Modules::ActionPolicy
        end
      end

      context "when global config is true" do
        before do
          ModelSettings.configure do |config|
            config.inherit_authorization = true
          end

          model_class.class_eval do
            setting :parent, authorize_with: :admin? do
              setting :child
            end
          end
        end

        it "child inherits from parent" do
          expect(model_class.authorization_for_setting(:child)).to eq(:admin?)
        end
      end

      context "when global config is false" do
        before do
          ModelSettings.configure do |config|
            config.inherit_authorization = false
          end

          model_class.class_eval do
            setting :parent, authorize_with: :admin? do
              setting :child
            end
          end
        end

        it "child does NOT inherit" do
          expect(model_class.authorization_for_setting(:child)).to be_nil
        end
      end
    end

    describe "priority: setting option overrides global config" do
      let(:model_class) do
        Class.new(TestModel) do
          def self.name
            "PriorityTestModel"
          end

          include ModelSettings::DSL
          include ModelSettings::Modules::Roles
        end
      end

      context "when global is true but setting has inherit_authorization: false" do
        before do
          ModelSettings.configure do |config|
            config.inherit_authorization = true
          end

          model_class.class_eval do
            setting :parent, viewable_by: [:admin] do
              setting :child, inherit_authorization: false
            end
          end
        end

        it "child does NOT inherit (setting option has priority)" do
          expect(model_class.settings_viewable_by(:admin)).not_to include(:child)
        end
      end

      context "when global is false but setting has inherit_authorization: true" do
        before do
          ModelSettings.configure do |config|
            config.inherit_authorization = false
          end

          model_class.class_eval do
            setting :parent, viewable_by: [:admin] do
              setting :child, inherit_authorization: true
            end
          end
        end

        it "child DOES inherit (setting option has priority)" do
          expect(model_class.settings_viewable_by(:admin)).to include(:child)
        end
      end
    end
  end
end
# rubocop:enable RSpecGuide/MinimumBehavioralCoverage, RSpec/DescribeClass
