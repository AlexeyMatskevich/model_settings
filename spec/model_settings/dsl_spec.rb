# frozen_string_literal: true

require "spec_helper"

RSpec.describe ModelSettings::DSL do
  # Create a minimal base class that provides class_attribute
  # (similar to what ActiveRecord::Base provides)
  let(:base_class) do
    Class.new do
      def self.class_attribute(*attrs, **options)
        attrs.each do |attr|
          default = options[:default]

          # Class-level accessor
          define_singleton_method(attr) do
            instance_variable_get("@#{attr}") || default
          end

          define_singleton_method("#{attr}=") do |value|
            instance_variable_set("@#{attr}", value)
          end

          # Ensure subclasses get their own copy
          define_singleton_method(:inherited) do |subclass|
            super(subclass) if defined?(super)
            subclass.send("#{attr}=", send(attr))
          end
        end
      end
    end
  end

  # Create a test class that includes the DSL
  let(:test_class) do
    Class.new(base_class) do
      def self.name
        "TestModel"
      end

      include ModelSettings::DSL
    end
  end

  describe ".setting" do
    # Base case: simple setting without options
    context "without options" do
      before { test_class.setting :enabled }

      let(:setting) { test_class.find_setting(:enabled) }

      it "creates a Setting object" do
        expect(setting).to be_a(ModelSettings::Setting)
      end

      it "stores the setting name" do
        expect(setting.name).to eq(:enabled)
      end

      it "adds setting to settings collection" do
        expect(test_class.settings).to include(setting)
      end

      it "makes setting findable" do
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

    # rubocop:disable RSpecGuide/ContextSetup
    context "with nested settings" do
      context "with single level" do
        before do
          test_class.setting :features do
            setting :ai_enabled
            setting :analytics_enabled
          end
        end

        let(:parent) { test_class.find_setting(:features) }
        let(:child) { parent.find_child(:ai_enabled) }

        it "creates parent setting" do
          expect(parent).to be_a(ModelSettings::Setting)
        end

        it "creates child settings" do
          expect(parent.children.size).to eq(2)
        end

        it "establishes parent reference" do
          expect(child.parent).to eq(parent)
        end

        it "establishes children collection" do
          expect(parent.children).to include(child)
        end
      end

      context "with multiple levels" do
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
    end
    # rubocop:enable RSpecGuide/ContextSetup

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

    # rubocop:disable RSpecGuide/ContextSetup
    context "when finding root setting" do
      it "finds by symbol" do
        setting = test_class.find_setting(:enabled)
        expect(setting.name).to eq(:enabled)
      end

      it "finds by string" do
        setting = test_class.find_setting("enabled")
        expect(setting.name).to eq(:enabled)
      end
    end

    context "when finding nested setting" do
      context "with single level path" do
        it "finds by path array" do
          setting = test_class.find_setting([:features, :ai])
          expect(setting.name).to eq(:ai)
        end
      end

      context "with deep path" do
        it "finds deeply nested setting" do
          setting = test_class.find_setting([:features, :analytics, :tracking])
          expect(setting.name).to eq(:tracking)
        end
      end
    end

    context "when setting does NOT exist" do
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

  # rubocop:disable RSpecGuide/CharacteristicsAndContexts
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

    it "returns only root-level settings" do
      expect(roots.size).to eq(3)
    end

    it "includes all root names" do
      expect(roots.map(&:name)).to match_array([:root1, :root2, :root3])
    end

    it "does NOT include nested settings" do
      expect(roots.map(&:name)).not_to include(:child1, :child2)
    end
  end

  # rubocop:disable RSpecGuide/CharacteristicsAndContexts
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

    it "returns only leaf settings" do
      expect(leaves.map(&:name)).to match_array([:standalone, :child1, :grandchild])
    end

    it "does NOT include parent settings" do
      expect(leaves.map(&:name)).not_to include(:parent, :child2)
    end
  end
  # rubocop:enable RSpecGuide/CharacteristicsAndContexts

  # rubocop:disable RSpecGuide/CharacteristicsAndContexts
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

    it "returns all settings including nested" do
      expect(all_settings.size).to eq(5)
    end

    it "includes all setting names" do
      expect(all_settings.map(&:name)).to match_array([:root1, :root2, :child1, :child2, :grandchild])
    end

    it "includes parent settings" do
      expect(all_settings.map(&:name)).to include(:root2, :child2)
    end

    it "includes leaf settings" do
      expect(all_settings.map(&:name)).to include(:root1, :child1, :grandchild)
    end
  end
  # rubocop:enable RSpecGuide/CharacteristicsAndContexts

  # rubocop:disable RSpecGuide/CharacteristicsAndContexts
  describe "class isolation" do
    let(:test_class_a) do
      Class.new(base_class) do
        def self.name
          "TestModelA"
        end
        # rubocop:enable RSpecGuide/CharacteristicsAndContexts

        include ModelSettings::DSL
      end
    end

    let(:test_class_b) do
      Class.new(base_class) do
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

    it "keeps class A settings separate" do
      expect(test_class_a.settings.map(&:name)).to eq([:setting_a])
    end

    it "keeps class B settings separate" do
      expect(test_class_b.settings.map(&:name)).to eq([:setting_b])
    end

    it "allows class A to find its own setting" do
      expect(test_class_a.find_setting(:setting_a)).not_to be_nil
    end

    it "prevents class A from finding class B setting" do
      expect(test_class_a.find_setting(:setting_b)).to be_nil
    end

    it "allows class B to find its own setting" do
      expect(test_class_b.find_setting(:setting_b)).not_to be_nil
    end

    it "prevents class B from finding class A setting" do
      expect(test_class_b.find_setting(:setting_a)).to be_nil
    end
  end
end
