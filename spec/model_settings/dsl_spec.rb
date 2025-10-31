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
end
