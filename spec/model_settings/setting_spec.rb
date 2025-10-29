# frozen_string_literal: true

require "spec_helper"

RSpec.describe ModelSettings::Setting do
  describe ".new" do
    subject(:setting) { described_class.new(:feature_flag, options) }

    context "with minimal options" do
      let(:options) { {} }

      it "creates a setting with given name" do
        expect(setting.name).to eq(:feature_flag)
      end

      it "has no parent" do
        expect(setting.parent).to be_nil
      end

      it "has no children" do
        expect(setting.children).to be_empty
      end

      it "defaults to column type" do
        expect(setting.type).to eq(:column)
      end
    end

    context "with full options" do
      let(:options) do
        {
          type: :json,
          storage: {column: :features},
          default: false,
          description: "Feature flag for new UI"
        }
      end

      it "stores type" do
        expect(setting.type).to eq(:json)
      end

      it "stores storage configuration" do
        expect(setting.storage).to eq({column: :features})
      end

      it "stores default value" do
        expect(setting.default).to be false
      end

      it "stores description" do
        expect(setting.description).to eq("Feature flag for new UI")
      end
    end

    context "with parent setting" do
      subject(:child_setting) { described_class.new(:child_feature, options, parent: parent_arg) }

      let(:parent_setting) { described_class.new(:parent_feature, {}) }
      let(:options) { {} }
      let(:parent_arg) { parent_setting }

      it "sets the parent" do
        expect(child_setting.parent).to eq(parent_setting)
      end
    end
  end

  # rubocop:disable RSpecGuide/CharacteristicsAndContexts
  describe "#add_child" do
    subject(:add_action) { parent.add_child(child) }

    let(:parent) { described_class.new(:parent, {}) }
    let(:child) { described_class.new(:child, {}, parent: parent) }

    it "adds child to children collection" do
      add_action
      expect(parent.children).to include(child)
    end

    it "returns the child" do
      expect(add_action).to eq(child)
    end

    context "but child is already in collection" do
      before { parent.add_child(child) }

      it "does NOT add duplicate" do
        expect { add_action }.not_to change { parent.children.count }
      end

      it "still returns the child" do
        expect(add_action).to eq(child)
      end
    end

    context "but child is NOT a Setting" do
      let(:child) { {} }

      it "raises ArgumentError" do
        expect { add_action }.to raise_error(ArgumentError, "Child must be a Setting")
      end
    end
  end
  # rubocop:enable RSpecGuide/CharacteristicsAndContexts

  describe "#type" do
    subject(:setting) { described_class.new(:flag, options) }

    context "when type is specified" do
      let(:options) { {type: :json} }

      it "returns the specified type" do
        expect(setting.type).to eq(:json)
      end
    end

    context "when type is NOT specified" do
      let(:options) { {} }

      it "defaults to :column" do
        expect(setting.type).to eq(:column)
      end
    end
  end

  describe "#storage" do
    subject(:setting) { described_class.new(:flag, options) }

    context "when storage is specified" do
      let(:options) { {storage: {column: :features, key: :flag}} }

      it "returns the storage configuration" do
        expect(setting.storage).to eq({column: :features, key: :flag})
      end
    end

    context "when storage is NOT specified" do
      let(:options) { {} }

      it "returns empty hash" do
        expect(setting.storage).to eq({})
      end
    end
  end

  describe "#cascade" do
    subject(:setting) { described_class.new(:flag, options) }

    context "when cascade is specified" do
      let(:options) { {cascade: {enable: false, disable: true}} }

      it "returns the cascade configuration" do
        expect(setting.cascade).to eq({enable: false, disable: true})
      end
    end

    context "when cascade is NOT specified" do
      let(:options) { {} }

      it "defaults to enable and disable both true" do
        expect(setting.cascade).to eq({enable: true, disable: true})
      end
    end
  end

  describe "#deprecated?" do
    subject(:setting) { described_class.new(:flag, options) }

    context "when deprecated is true" do
      let(:options) { {deprecated: true} }

      it "returns true" do
        expect(setting.deprecated?).to be true
      end
    end

    context "when deprecated is a string" do
      let(:options) { {deprecated: "Use new_flag instead"} }

      it "returns true" do
        expect(setting.deprecated?).to be true
      end
    end

    context "when deprecated is NOT set" do
      let(:options) { {} }

      it "returns false" do
        expect(setting.deprecated?).to be false
      end
    end
  end

  describe "#deprecation_reason" do
    subject(:setting) { described_class.new(:flag, options) }

    context "when deprecated with reason" do
      let(:options) { {deprecated: "Use new_flag instead"} }

      it "returns the reason" do
        expect(setting.deprecation_reason).to eq("Use new_flag instead")
      end
    end

    context "when deprecated without reason" do
      let(:options) { {deprecated: true} }

      it "returns default message" do
        expect(setting.deprecation_reason).to eq("Setting is deprecated")
      end
    end

    context "when NOT deprecated" do
      let(:options) { {} }

      it "returns nil" do
        expect(setting.deprecation_reason).to be_nil
      end
    end
  end

  describe "#metadata" do
    subject(:setting) { described_class.new(:flag, options) }

    context "when metadata is provided" do
      let(:options) do
        {metadata: {tracking_id: "FEAT-123", owner: "platform"}}
      end

      it "returns the metadata hash" do
        expect(setting.metadata).to eq({tracking_id: "FEAT-123", owner: "platform"})
      end
    end

    context "when metadata is NOT provided" do
      let(:options) { {} }

      it "returns empty hash" do
        expect(setting.metadata).to eq({})
      end
    end
  end

  describe "#path" do
    subject(:path) { setting.path }

    context "when setting is root" do
      let(:setting) { described_class.new(:root, {}) }

      it "returns array with only own name" do
        expect(path).to eq([:root])
      end
    end

    context "when setting has parent" do
      let(:setting) { described_class.new(:child, {}, parent: parent) }
      let(:parent) { described_class.new(:parent, {}) }

      before { parent.add_child(setting) }

      it "returns path including parent" do
        expect(path).to eq([:parent, :child])
      end
    end

    context "when setting has grandparent" do
      let(:setting) { described_class.new(:grandchild, {}, parent: child) }
      let(:grandparent) { described_class.new(:grandparent, {}) }
      let(:child) { described_class.new(:child, {}, parent: grandparent) }

      before do
        grandparent.add_child(child)
        child.add_child(setting)
      end

      it "returns full path" do
        expect(path).to eq([:grandparent, :child, :grandchild])
      end
    end
  end

  describe "#root" do
    subject(:root) { setting.root }

    context "when setting is root" do
      let(:setting) { described_class.new(:root, {}) }

      it "returns itself" do
        expect(root).to eq(setting)
      end
    end

    context "when setting has parent" do
      let(:setting) { described_class.new(:child, {}, parent: parent) }
      let(:parent) { described_class.new(:parent, {}) }

      it "returns the parent" do
        expect(root).to eq(parent)
      end
    end

    context "when setting has grandparent" do
      let(:setting) { described_class.new(:grandchild, {}, parent: child) }
      let(:grandparent) { described_class.new(:grandparent, {}) }
      let(:child) { described_class.new(:child, {}, parent: grandparent) }

      it "returns the grandparent" do
        expect(root).to eq(grandparent)
      end
    end
  end

  describe "#root?" do
    subject(:is_root) { setting.root? }

    context "when setting has no parent" do
      let(:setting) { described_class.new(:root, {}) }

      it "returns true" do
        expect(is_root).to be true
      end
    end

    context "when setting has parent" do
      let(:setting) { described_class.new(:child, {}, parent: parent) }
      let(:parent) { described_class.new(:parent, {}) }

      it "returns false" do
        expect(is_root).to be false
      end
    end
  end

  # rubocop:disable RSpecGuide/CharacteristicsAndContexts
  describe "#leaf?" do
    subject(:is_leaf) { setting.leaf? }

    let(:setting) { described_class.new(:parent, {}) }

    it "returns true" do
      expect(is_leaf).to be true
    end

    context "but setting has children" do
      let(:child) { described_class.new(:child, {}, parent: setting) }

      before { setting.add_child(child) }

      it "returns false" do
        expect(is_leaf).to be false
      end
    end
  end
  # rubocop:enable RSpecGuide/CharacteristicsAndContexts

  describe "#find_child" do
    subject(:found_child) { parent.find_child(child_name) }

    let(:parent) { described_class.new(:parent, {}) }
    let(:child1) { described_class.new(:child1, {}, parent: parent) }
    let(:child2) { described_class.new(:child2, {}, parent: parent) }

    before do
      parent.add_child(child1)
      parent.add_child(child2)
    end

    # rubocop:disable RSpecGuide/ContextSetup
    context "when child exists" do
      context "when searching by symbol" do
        let(:child_name) { :child1 }

        it "finds child" do
          expect(found_child).to eq(child1)
        end
      end

      context "when searching by string" do
        let(:child_name) { "child2" }

        it "finds child" do
          expect(found_child).to eq(child2)
        end
      end
    end
    # rubocop:enable RSpecGuide/ContextSetup

    context "when child does NOT exist" do
      let(:child_name) { :nonexistent }

      it "returns nil" do
        expect(found_child).to be_nil
      end
    end
  end

  describe "#descendants" do
    subject(:descendants) { setting.descendants }

    let(:setting) { described_class.new(:root, {}) }

    context "when setting has no children" do
      let(:no_children) {}

      it "returns empty array" do
        expect(descendants).to be_empty
      end
    end

    context "when setting has direct children only" do
      let(:child1) { described_class.new(:child1, {}, parent: setting) }
      let(:child2) { described_class.new(:child2, {}, parent: setting) }

      before do
        setting.add_child(child1)
        setting.add_child(child2)
      end

      it "returns all children" do
        expect(descendants).to match_array([child1, child2])
      end
    end

    context "when setting has nested children" do
      let(:child) { described_class.new(:child, {}, parent: setting) }
      let(:grandchild) { described_class.new(:grandchild, {}, parent: child) }

      before do
        setting.add_child(child)
        child.add_child(grandchild)
      end

      it "returns all descendants recursively" do
        expect(descendants).to match_array([child, grandchild])
      end
    end
  end

  describe "#inherited_option" do
    subject(:inherited_value) { child.inherited_option(option_name) }

    let(:child) { described_class.new(:child, child_options, parent: parent) }
    let(:parent) { described_class.new(:parent, parent_options) }
    let(:parent_options) { {type: :json, default: false} }

    context "when child has the option" do
      let(:child_options) { {type: :column} }
      let(:option_name) { :type }

      it "returns child's value" do
        expect(inherited_value).to eq(:column)
      end
    end

    context "when child does NOT have the option" do
      let(:child_options) { {} }

      context "when inheriting type" do
        let(:option_name) { :type }

        it "inherits type from parent" do
          expect(inherited_value).to eq(:json)
        end
      end

      context "when inheriting default" do
        let(:option_name) { :default }

        it "inherits default from parent" do
          expect(inherited_value).to be false
        end
      end
    end

    context "when neither child nor parent has the option" do
      let(:child_options) { {} }
      let(:parent_options) { {} }
      let(:option_name) { :nonexistent }

      it "returns nil" do
        expect(inherited_value).to be_nil
      end
    end
  end

  describe "#callbacks" do
    subject(:setting) { described_class.new(:flag, options) }

    context "when callbacks are defined" do
      let(:options) do
        {
          before_enable: :check_requirements,
          after_enable: :notify_service,
          before_disable: :confirm_disable
        }
      end

      it "returns all callback options" do
        callbacks = setting.callbacks
        expect(callbacks).to include(
          before_enable: :check_requirements,
          after_enable: :notify_service,
          before_disable: :confirm_disable
        )
      end
    end

    context "when no callbacks defined" do
      let(:options) { {} }

      it "returns empty hash" do
        expect(setting.callbacks).to be_empty
      end
    end
  end

  describe "#has_option?" do
    subject(:setting) { described_class.new(:flag, options) }

    context "when option is present" do
      let(:options) { {custom_option: "value"} }

      it "returns true" do
        expect(setting.has_option?(:custom_option)).to be true
      end
    end

    context "when option is NOT present" do
      let(:options) { {} }

      it "returns false" do
        expect(setting.has_option?(:custom_option)).to be false
      end
    end
  end

  describe "#get_option" do
    subject(:setting) { described_class.new(:flag, options) }

    context "when option exists" do
      let(:options) { {custom_option: "value"} }

      it "returns option value" do
        expect(setting.get_option(:custom_option)).to eq("value")
      end
    end

    context "when option does NOT exist" do
      let(:options) { {} }
      let(:default_value) { "default" }

      it "returns nil without default" do
        expect(setting.get_option(:custom_option)).to be_nil
      end

      it "returns default value with default" do
        expect(setting.get_option(:custom_option, default_value)).to eq("default")
      end
    end
  end

  describe "#custom_options" do
    subject(:setting) { described_class.new(:flag, options) }

    context "when only built-in options present" do
      let(:options) { {type: :column, default: false, description: "Test"} }

      it "returns empty hash" do
        expect(setting.custom_options).to be_empty
      end
    end

    context "when custom options present" do
      let(:options) do
        {
          type: :column,
          viewable_by: [:admin],
          ui_group: :advanced,
          custom_meta: "data"
        }
      end

      it "returns only custom options" do
        expect(setting.custom_options).to eq({
          viewable_by: [:admin],
          ui_group: :advanced,
          custom_meta: "data"
        })
      end
    end
  end

  describe ".merge_inherited_options" do
    subject(:merged) do
      described_class.merge_inherited_options(parent_options, child_options)
    end

    let(:parent_options) { {type: :json, default: false, metadata: {tier: "basic"}} }

    context "when child overrides simple option" do
      let(:child_options) { {default: true} }

      it "uses child value" do
        expect(merged[:default]).to be true
      end

      it "keeps parent value for non-overridden options" do
        expect(merged[:type]).to eq(:json)
      end
    end

    context "when child adds metadata" do
      let(:child_options) { {metadata: {owner: "team"}} }

      it "deep merges metadata" do
        expect(merged[:metadata]).to eq({tier: "basic", owner: "team"})
      end
    end

    context "when child overrides metadata key" do
      let(:child_options) { {metadata: {tier: "premium"}} }

      it "uses child metadata value" do
        expect(merged[:metadata]).to eq({tier: "premium"})
      end
    end

    context "when child adds cascade configuration" do
      let(:parent_options) { {cascade: {enable: true}} }
      let(:child_options) { {cascade: {disable: false}} }

      it "deep merges cascade" do
        expect(merged[:cascade]).to eq({enable: true, disable: false})
      end
    end
  end

  describe "#all_inherited_options" do
    subject(:all_options) { child.all_inherited_options }

    context "when setting has no parent" do
      let(:child) { described_class.new(:root, {type: :column, default: false}) }

      it "returns own options" do
        expect(all_options).to eq({type: :column, default: false})
      end
    end

    context "when setting has parent" do
      let(:parent) { described_class.new(:parent, {type: :json, metadata: {tier: "basic"}}) }
      let(:child) { described_class.new(:child, {default: true, metadata: {owner: "team"}}, parent: parent) }

      it "merges parent and child options" do
        expect(all_options).to include(
          type: :json,
          default: true,
          metadata: {tier: "basic", owner: "team"}
        )
      end
    end

    context "when setting has grandparent" do
      let(:grandparent) { described_class.new(:gp, {type: :json, metadata: {tier: "basic"}}) }
      let(:parent) { described_class.new(:parent, {default: false, metadata: {category: "feature"}}, parent: grandparent) }
      let(:child) { described_class.new(:child, {metadata: {owner: "team"}}, parent: parent) }

      it "merges all ancestor options" do
        expect(all_options).to include(
          type: :json,
          default: false,
          metadata: {tier: "basic", category: "feature", owner: "team"}
        )
      end
    end
  end
end
