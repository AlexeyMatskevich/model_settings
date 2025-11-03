# frozen_string_literal: true

require "spec_helper"

# rubocop:disable RSpecGuide/MinimumBehavioralCoverage
RSpec.describe ModelSettings::Modules::Roles do
  describe "authorization inheritance" do
    let(:model_class) do
      Class.new(TestModel) do
        def self.name
          "RolesInheritanceTestModel"
        end

        include ModelSettings::DSL
        include ModelSettings::Modules::Roles
      end
    end

    describe "explicit :inherit keyword" do
      context "when child uses :inherit for viewable_by" do
        before do
          model_class.class_eval do
            setting :parent, viewable_by: [:admin, :finance] do
              setting :child, viewable_by: :inherit
            end
          end
        end

        it "includes child for admin role" do
          expect(model_class.settings_viewable_by(:admin)).to include(:child)
        end

        it "includes child for finance role" do
          expect(model_class.settings_viewable_by(:finance)).to include(:child)
        end

        it "does NOT include child for guest role" do
          expect(model_class.settings_viewable_by(:guest)).not_to include(:child)
        end
      end

      context "when child uses :inherit for editable_by" do
        before do
          model_class.class_eval do
            setting :parent, editable_by: [:admin] do
              setting :child, editable_by: :inherit
            end
          end
        end

        it "includes child for admin role" do
          expect(model_class.settings_editable_by(:admin)).to include(:child)
        end

        it "does NOT include child for finance role" do
          expect(model_class.settings_editable_by(:finance)).not_to include(:child)
        end
      end

      context "but without parent authorization" do
        before do
          model_class.class_eval do
            setting :parent do
              setting :child, viewable_by: :inherit
            end
          end
        end

        let(:instance) { model_class.new }

        it "does NOT include child in query results" do
          expect(model_class.settings_viewable_by(:guest)).not_to include(:child)
        end

        it "allows viewing by instance method" do
          expect(instance.can_view_setting?(:child, :guest)).to be true
        end
      end
    end

    describe "setting-level inherit_authorization option" do
      let(:instance) { model_class.new }

      context "when inherit_authorization: true" do
        before do
          model_class.class_eval do
            setting :parent, viewable_by: [:admin, :finance], editable_by: [:admin] do
              setting :child, inherit_authorization: true
            end
          end
        end

        it "includes child in viewable_by for admin" do
          expect(model_class.settings_viewable_by(:admin)).to include(:child)
        end

        it "includes child in viewable_by for finance" do
          expect(model_class.settings_viewable_by(:finance)).to include(:child)
        end

        it "does NOT include child in viewable_by for guest" do
          expect(model_class.settings_viewable_by(:guest)).not_to include(:child)
        end

        it "includes child in editable_by for admin" do
          expect(model_class.settings_editable_by(:admin)).to include(:child)
        end

        it "does NOT include child in editable_by for finance" do
          expect(model_class.settings_editable_by(:finance)).not_to include(:child)
        end
      end

      context "when inherit_authorization: :view_only" do
        before do
          model_class.class_eval do
            setting :parent, viewable_by: [:admin, :finance], editable_by: [:admin] do
              setting :child, inherit_authorization: :view_only
            end
          end
        end

        it "includes child in viewable_by for finance" do
          expect(model_class.settings_viewable_by(:finance)).to include(:child)
        end

        it "does NOT include child in editable_by query" do
          expect(model_class.settings_editable_by(:guest)).not_to include(:child)
        end

        it "allows editing by instance method" do
          expect(instance.can_edit_setting?(:child, :guest)).to be true
        end
      end

      context "when inherit_authorization: :edit_only" do
        before do
          model_class.class_eval do
            setting :parent, viewable_by: [:admin, :finance], editable_by: [:admin] do
              setting :child, inherit_authorization: :edit_only
            end
          end
        end

        it "does NOT include child in viewable_by query" do
          expect(model_class.settings_viewable_by(:guest)).not_to include(:child)
        end

        it "allows viewing by instance method" do
          expect(instance.can_view_setting?(:child, :guest)).to be true
        end

        it "includes child in editable_by for admin" do
          expect(model_class.settings_editable_by(:admin)).to include(:child)
        end

        it "does NOT include child in editable_by for finance" do
          expect(model_class.settings_editable_by(:finance)).not_to include(:child)
        end
      end

      context "when inherit_authorization: false" do
        before do
          model_class.class_eval do
            setting :parent, viewable_by: [:admin], editable_by: [:admin] do
              setting :child, inherit_authorization: false
            end
          end
        end

        it "does NOT include child in viewable_by query" do
          expect(model_class.settings_viewable_by(:guest)).not_to include(:child)
        end

        it "does NOT include child in editable_by query" do
          expect(model_class.settings_editable_by(:guest)).not_to include(:child)
        end

        it "allows viewing by instance method" do
          expect(instance.can_view_setting?(:child, :guest)).to be true
        end

        it "allows editing by instance method" do
          expect(instance.can_edit_setting?(:child, :guest)).to be true
        end
      end
    end

    describe "model-level settings_config" do
      let(:instance) { model_class.new }

      context "when settings_config inherit_authorization: true" do
        before do
          model_class.class_eval do
            settings_config inherit_authorization: true

            setting :parent, viewable_by: [:admin, :finance], editable_by: [:admin] do
              setting :child1
              setting :child2
            end
          end
        end

        it "includes both children in viewable_by for finance" do
          expect(model_class.settings_viewable_by(:finance)).to include(:child1, :child2)
        end

        it "includes both children in editable_by for admin" do
          expect(model_class.settings_editable_by(:admin)).to include(:child1, :child2)
        end

        it "does NOT include children in editable_by for finance" do
          expect(model_class.settings_editable_by(:finance)).not_to include(:child1, :child2)
        end
      end

      context "when settings_config inherit_authorization: :view_only" do
        before do
          model_class.class_eval do
            settings_config inherit_authorization: :view_only

            setting :parent, viewable_by: [:admin], editable_by: [:admin] do
              setting :child
            end
          end
        end

        it "includes child in viewable_by for admin" do
          expect(model_class.settings_viewable_by(:admin)).to include(:child)
        end

        it "does NOT include child in viewable_by for guest" do
          expect(model_class.settings_viewable_by(:guest)).not_to include(:child)
        end

        it "does NOT include child in editable_by query" do
          expect(model_class.settings_editable_by(:guest)).not_to include(:child)
        end

        it "allows editing by instance method" do
          expect(instance.can_edit_setting?(:child, :guest)).to be true
        end
      end

      context "when settings_config inherit_authorization: :edit_only" do
        before do
          model_class.class_eval do
            settings_config inherit_authorization: :edit_only

            setting :parent, viewable_by: [:admin], editable_by: [:admin] do
              setting :child
            end
          end
        end

        it "does NOT include child in viewable_by query" do
          expect(model_class.settings_viewable_by(:guest)).not_to include(:child)
        end

        it "allows viewing by instance method" do
          expect(instance.can_view_setting?(:child, :guest)).to be true
        end

        it "includes child in editable_by for admin" do
          expect(model_class.settings_editable_by(:admin)).to include(:child)
        end

        it "does NOT include child in editable_by for guest" do
          expect(model_class.settings_editable_by(:guest)).not_to include(:child)
        end
      end
    end

    describe "priority levels" do
      context "when explicit value overrides inherit_authorization option" do
        before do
          model_class.class_eval do
            setting :parent, viewable_by: [:admin] do
              setting :child,
                viewable_by: [:finance],
                inherit_authorization: true
            end
          end
        end

        it "includes child for finance role" do
          expect(model_class.settings_viewable_by(:finance)).to include(:child)
        end

        it "does NOT include child for admin role" do
          expect(model_class.settings_viewable_by(:admin)).not_to include(:child)
        end
      end

      context "when explicit :inherit overrides inherit_authorization: false" do
        before do
          model_class.class_eval do
            setting :parent, viewable_by: [:admin] do
              setting :child,
                viewable_by: :inherit,
                inherit_authorization: false
            end
          end
        end

        it "includes child for admin role" do
          expect(model_class.settings_viewable_by(:admin)).to include(:child)
        end

        it "does NOT include child for guest role" do
          expect(model_class.settings_viewable_by(:guest)).not_to include(:child)
        end
      end

      context "when setting option overrides model config" do
        before do
          model_class.class_eval do
            settings_config inherit_authorization: true

            setting :parent, viewable_by: [:admin] do
              setting :child, inherit_authorization: false
            end
          end
        end

        let(:instance) { model_class.new }

        it "does NOT include child in query results" do
          expect(model_class.settings_viewable_by(:guest)).not_to include(:child)
        end

        it "allows viewing by instance method" do
          expect(instance.can_view_setting?(:child, :guest)).to be true
        end
      end
    end

    describe "instance methods with inheritance" do
      before do
        model_class.class_eval do
          setting :parent, viewable_by: [:admin, :finance], editable_by: [:admin] do
            setting :child, inherit_authorization: true
          end
        end
      end

      let(:instance) { model_class.new }

      describe "#can_view_setting?" do
        it "returns true for admin" do
          expect(instance.can_view_setting?(:child, :admin)).to be true
        end

        it "returns true for finance" do
          expect(instance.can_view_setting?(:child, :finance)).to be true
        end

        it "returns false for guest" do
          expect(instance.can_view_setting?(:child, :guest)).to be false
        end
      end

      describe "#can_edit_setting?" do
        it "returns true for admin" do
          expect(instance.can_edit_setting?(:child, :admin)).to be true
        end

        it "returns false for finance" do
          expect(instance.can_edit_setting?(:child, :finance)).to be false
        end

        it "returns false for guest" do
          expect(instance.can_edit_setting?(:child, :guest)).to be false
        end
      end
    end

    describe "deep nesting" do
      before do
        model_class.class_eval do
          settings_config inherit_authorization: true

          setting :level1, viewable_by: [:admin] do
            setting :level2 do
              setting :level3 do
                setting :level4
              end
            end
          end
        end
      end

      it "includes deeply nested setting for admin" do
        expect(model_class.settings_viewable_by(:admin)).to include(:level4)
      end

      it "does NOT include deeply nested setting for guest" do
        expect(model_class.settings_viewable_by(:guest)).not_to include(:level4)
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
