# frozen_string_literal: true

require "spec_helper"

# rubocop:disable RSpecGuide/MinimumBehavioralCoverage
RSpec.describe ModelSettings::Modules::ActionPolicy do
  describe "authorization inheritance" do
    let(:model_class) do
      Class.new(TestModel) do
        def self.name
          "ActionPolicyInheritanceTestModel"
        end

        include ModelSettings::DSL
        include ModelSettings::Modules::ActionPolicy
      end
    end

    describe "explicit :inherit keyword" do
      context "when child uses :inherit for authorize_with" do
        before do
          model_class.class_eval do
            setting :parent, authorize_with: :manage_billing? do
              setting :child, authorize_with: :inherit
            end
          end
        end

        it "inherits authorize_with from parent" do
          expect(model_class.authorization_for_setting(:child)).to eq(:manage_billing?)
        end
      end

      context "but when parent has no authorization" do
        before do
          model_class.class_eval do
            setting :parent do
              setting :child, authorize_with: :inherit
            end
          end
        end

        it "returns nil (no restriction)" do
          expect(model_class.authorization_for_setting(:child)).to be_nil
        end
      end
    end

    describe "setting-level inherit_authorization option" do
      context "when inherit_authorization: true" do
        before do
          model_class.class_eval do
            setting :parent, authorize_with: :manage_billing? do
              setting :child, inherit_authorization: true
            end
          end
        end

        it "inherits authorize_with from parent" do
          expect(model_class.authorization_for_setting(:child)).to eq(:manage_billing?)
        end
      end

      context "when inherit_authorization: false" do
        before do
          model_class.class_eval do
            setting :parent, authorize_with: :admin? do
              setting :child, inherit_authorization: false
            end
          end
        end

        it "does not inherit authorization" do
          expect(model_class.authorization_for_setting(:child)).to be_nil
        end
      end
    end

    describe "model-level settings_config" do
      context "when settings_config inherit_authorization: true" do
        before do
          model_class.class_eval do
            settings_config inherit_authorization: true

            setting :parent, authorize_with: :manage_billing? do
              setting :child1
              setting :child2
            end
          end
        end

        it "child1 inherits from parent" do
          expect(model_class.authorization_for_setting(:child1)).to eq(:manage_billing?)
        end

        it "child2 inherits from parent" do
          expect(model_class.authorization_for_setting(:child2)).to eq(:manage_billing?)
        end
      end

      context "when settings_config inherit_authorization: :view_only" do
        before do
          model_class.class_eval do
            settings_config inherit_authorization: :view_only

            setting :parent, authorize_with: :admin? do
              setting :child
            end
          end
        end

        it "nested setting inherits (policy-based treats view_only same as true)" do
          expect(model_class.authorization_for_setting(:child)).to eq(:admin?)
        end
      end

      context "when settings_config inherit_authorization: :edit_only" do
        before do
          model_class.class_eval do
            settings_config inherit_authorization: :edit_only

            setting :parent, authorize_with: :admin? do
              setting :child
            end
          end
        end

        it "nested setting inherits (policy-based treats edit_only same as true)" do
          expect(model_class.authorization_for_setting(:child)).to eq(:admin?)
        end
      end
    end

    describe "priority levels" do
      context "when explicit value overrides inherit_authorization option" do
        before do
          model_class.class_eval do
            setting :parent, authorize_with: :admin? do
              setting :child,
                authorize_with: :manage_billing?,
                inherit_authorization: true
            end
          end
        end

        it "uses explicit value" do
          expect(model_class.authorization_for_setting(:child)).to eq(:manage_billing?)
        end
      end

      context "when explicit :inherit overrides inherit_authorization: false" do
        before do
          model_class.class_eval do
            setting :parent, authorize_with: :admin? do
              setting :child,
                authorize_with: :inherit,
                inherit_authorization: false
            end
          end
        end

        it "inherits despite inherit_authorization: false" do
          expect(model_class.authorization_for_setting(:child)).to eq(:admin?)
        end
      end

      context "when setting option overrides model config" do
        before do
          model_class.class_eval do
            settings_config inherit_authorization: true

            setting :parent, authorize_with: :admin? do
              setting :child, inherit_authorization: false
            end
          end
        end

        it "uses setting option" do
          expect(model_class.authorization_for_setting(:child)).to be_nil
        end
      end
    end

    describe "deep nesting" do
      before do
        model_class.class_eval do
          settings_config inherit_authorization: true

          setting :level1, authorize_with: :admin? do
            setting :level2 do
              setting :level3 do
                setting :level4
              end
            end
          end
        end
      end

      it "inherits through multiple levels" do
        expect(model_class.authorization_for_setting(:level4)).to eq(:admin?)
      end
    end

    describe "query methods" do
      before do
        model_class.class_eval do
          settings_config inherit_authorization: true

          setting :parent1, authorize_with: :admin? do
            setting :child1
          end

          setting :parent2, authorize_with: :manage_billing? do
            setting :child2
          end

          setting :unrestricted
        end
      end

      describe ".settings_requiring" do
        it "returns parent1 and child1 for :admin?" do
          expect(model_class.settings_requiring(:admin?)).to match_array([:parent1, :child1])
        end

        it "returns parent2 and child2 for :manage_billing?" do
          expect(model_class.settings_requiring(:manage_billing?)).to match_array([:parent2, :child2])
        end
      end

      describe ".authorized_settings" do
        it "returns all settings with authorization (including inherited)" do
          expect(model_class.authorized_settings).to match_array([:parent1, :child1, :parent2, :child2])
        end
      end
    end

    describe "validation" do
      it "accepts true" do
        expect {
          model_class.class_eval do
            setting :test1, inherit_authorization: true
          end
        }.not_to raise_error
      end

      it "accepts false" do
        expect {
          model_class.class_eval do
            setting :test2, inherit_authorization: false
          end
        }.not_to raise_error
      end

      it "accepts :view_only" do
        expect {
          model_class.class_eval do
            setting :test3, inherit_authorization: :view_only
          end
        }.not_to raise_error
      end

      it "accepts :edit_only" do
        expect {
          model_class.class_eval do
            setting :test4, inherit_authorization: :edit_only
          end
        }.not_to raise_error
      end

      it "raises ArgumentError for invalid value" do
        expect {
          model_class.class_eval do
            setting :test, inherit_authorization: :invalid_value
          end
        }.to raise_error(ArgumentError, /inherit_authorization must be one of/)
      end
    end
  end
end
# rubocop:enable RSpecGuide/MinimumBehavioralCoverage
