# frozen_string_literal: true

require "spec_helper"

# rubocop:disable RSpec/DescribeClass, RSpecGuide/MinimumBehavioralCoverage, RSpec/ContextWording
RSpec.describe "Metadata and Cascade Inheritance" do
  let(:model_class) do
    Class.new(ActiveRecord::Base) do
      self.table_name = "test_models"

      def self.name
        "TestModel"
      end

      include ModelSettings::DSL
    end
  end

  before do
    # Register core options and enable inheritance
    ModelSettings::ModuleRegistry.register_inheritable_option(:metadata, merge_strategy: :merge, auto_include: false)
    ModelSettings::ModuleRegistry.register_inheritable_option(:cascade, merge_strategy: :merge, auto_include: false)
    ModelSettings.configuration.inheritable_options = [:metadata, :cascade]
  end

  after do
    # Only reset configuration, not registry (to avoid breaking subsequent tests)
    ModelSettings.reset_configuration!
  end

  describe ":metadata inheritance with :merge strategy" do
    context "when parent has metadata and child adds metadata" do
      before do
        model_class.setting :parent,
          type: :column,
          metadata: {category: "finance", deprecated_since: "1.0"} do
          setting :child,
            type: :column,
            metadata: {sensitive: true}
        end

        model_class.compile_settings!
      end

      it "merges parent and child metadata keys" do
        parent_setting = model_class.find_setting(:parent)
        child_setting = parent_setting.children.first

        expect(child_setting.metadata).to eq({
          category: "finance",
          deprecated_since: "1.0",
          sensitive: true
        })
      end

      it "parent metadata remains unchanged" do
        parent_setting = model_class.find_setting(:parent)

        expect(parent_setting.metadata).to eq({
          category: "finance",
          deprecated_since: "1.0"
        })
      end
    end

    context "when child overrides parent metadata key" do
      before do
        model_class.setting :parent,
          type: :column,
          metadata: {category: "finance", tier: "basic"} do
          setting :child,
            type: :column,
            metadata: {tier: "premium"}
        end

        model_class.compile_settings!
      end

      it "child value takes precedence" do
        parent_setting = model_class.find_setting(:parent)
        child_setting = parent_setting.children.first

        expect(child_setting.metadata).to eq({
          category: "finance",
          tier: "premium"
        })
      end
    end

    context "when child has no metadata" do
      before do
        model_class.setting :parent,
          type: :column,
          metadata: {category: "finance"} do
          setting :child, type: :column
        end

        model_class.compile_settings!
      end

      it "inherits parent metadata" do
        parent_setting = model_class.find_setting(:parent)
        child_setting = parent_setting.children.first

        expect(child_setting.metadata).to eq({category: "finance"})
      end
    end

    context "with multi-level nesting" do
      before do
        model_class.setting :grandparent,
          type: :column,
          metadata: {a: 1, b: 2} do
          setting :parent,
            type: :column,
            metadata: {b: 3, c: 4} do
            setting :child,
              type: :column,
              metadata: {c: 5, d: 6}
          end
        end

        model_class.compile_settings!
      end

      it "merges metadata through all levels" do
        grandparent = model_class.find_setting(:grandparent)
        parent = grandparent.children.first
        child = parent.children.first

        expect(child.metadata).to eq({
          a: 1,  # from grandparent
          b: 3,  # from parent (overrode grandparent)
          c: 5,  # from child (overrode parent)
          d: 6   # from child
        })
      end
    end
  end

  describe ":cascade inheritance with :merge strategy" do
    context "when parent has cascade enable and child adds disable" do
      before do
        model_class.setting :parent,
          type: :column,
          default: false,
          cascade: {enable: true} do
          setting :child,
            type: :column,
            default: false,
            cascade: {disable: true} do
            setting :grandchild,
              type: :column,
              default: false
          end
        end

        model_class.compile_settings!
      end

      it "child gets both enable and disable" do
        parent_setting = model_class.find_setting(:parent)
        child_setting = parent_setting.children.first

        expect(child_setting.cascade).to eq({
          enable: true,
          disable: true
        })
      end

      it "grandchild inherits merged cascade from child" do
        parent_setting = model_class.find_setting(:parent)
        child_setting = parent_setting.children.first
        grandchild_setting = child_setting.children.first

        expect(grandchild_setting.cascade).to eq({
          enable: true,
          disable: true
        })
      end
    end

    context "when child overrides parent cascade key" do
      before do
        model_class.setting :parent,
          type: :column,
          default: false,
          cascade: {enable: true, disable: false} do
          setting :child,
            type: :column,
            default: false,
            cascade: {enable: false}
        end

        model_class.compile_settings!
      end

      it "child value takes precedence for enable key" do
        parent_setting = model_class.find_setting(:parent)
        child_setting = parent_setting.children.first

        expect(child_setting.cascade).to eq({
          enable: false,  # overridden by child
          disable: false  # inherited from parent
        })
      end
    end

    context "when child has no cascade" do
      before do
        model_class.setting :parent,
          type: :column,
          default: false,
          cascade: {enable: true} do
          setting :child,
            type: :column,
            default: false
        end

        model_class.compile_settings!
      end

      it "inherits parent cascade" do
        parent_setting = model_class.find_setting(:parent)
        child_setting = parent_setting.children.first

        expect(child_setting.cascade).to eq({enable: true})
      end
    end
  end

  describe "when inheritance is disabled" do
    before do
      # Disable inheritance by not including :metadata/:cascade
      ModelSettings.configuration.inheritable_options = [:viewable_by]
    end

    context "for :metadata" do
      before do
        model_class.setting :parent,
          type: :column,
          metadata: {category: "finance"} do
          setting :child,
            type: :column,
            metadata: {sensitive: true}
        end

        model_class.compile_settings!
      end

      it "does not inherit parent metadata" do
        parent_setting = model_class.find_setting(:parent)
        child_setting = parent_setting.children.first

        expect(child_setting.metadata).to eq({sensitive: true})
      end
    end

    context "for :cascade" do
      before do
        model_class.setting :parent,
          type: :column,
          default: false,
          cascade: {enable: true} do
          setting :child,
            type: :column,
            default: false,
            cascade: {disable: true}
        end

        model_class.compile_settings!
      end

      it "does not inherit parent cascade" do
        parent_setting = model_class.find_setting(:parent)
        child_setting = parent_setting.children.first

        expect(child_setting.cascade).to eq({disable: true})
      end
    end
  end

  describe "integration with deprecation system" do
    before do
      model_class.setting :parent,
        type: :column,
        metadata: {deprecated_since: "1.0", replacement: :new_parent} do
        setting :child, type: :column
      end

      model_class.compile_settings!
    end

    # rubocop:disable RSpec/MultipleExpectations
    it "child inherits deprecation metadata" do
      parent_setting = model_class.find_setting(:parent)
      child_setting = parent_setting.children.first

      expect(child_setting.metadata[:deprecated_since]).to eq("1.0")
      expect(child_setting.metadata[:replacement]).to eq(:new_parent)
    end
    # rubocop:enable RSpec/MultipleExpectations
  end
end
# rubocop:enable RSpec/DescribeClass, RSpecGuide/MinimumBehavioralCoverage, RSpec/ContextWording
