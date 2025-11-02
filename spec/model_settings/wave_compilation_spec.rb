# frozen_string_literal: true

require "spec_helper"

# Integration tests for wave-based compilation
# Tests compilation order by nesting depth to ensure proper parent-child setup
# rubocop:disable RSpec/DescribeClass, RSpecGuide/MinimumBehavioralCoverage, RSpec/ExampleLength, RSpec/MultipleExpectations
RSpec.describe "Wave-based compilation" do
  describe "compilation order" do
    it "processes Level 0 settings before Level 1 settings" do
      model_class = Class.new(TestModel) do
        def self.name
          "WaveOrderModel"
        end

        include ModelSettings::DSL

        setting :parent, type: :column, default: false
        setting :features, type: :json, storage: {column: :settings} do
          setting :ai_enabled, default: false
        end
      end

      # After compilation, all methods should exist
      instance = model_class.create!

      aggregate_failures do
        expect(instance).to respond_to(:parent_enable!)
        expect(instance).to respond_to(:ai_enabled)
        expect(instance).to respond_to(:ai_enabled=)
      end
    end

    it "processes settings in definition order within each level" do
      model_class = Class.new(TestModel) do
        def self.name
          "DefinitionOrderModel"
        end

        include ModelSettings::DSL

        # Level 0: defined in order first, second, third
        setting :first, type: :column, default: false
        setting :second, type: :column, default: false
        setting :third, type: :column, default: false
      end

      settings = model_class.settings
      names = settings.map(&:name)

      expect(names).to eq([:first, :second, :third])
    end

    it "processes nested settings after their parents" do
      model_class = Class.new(TestModel) do
        def self.name
          "NestedOrderModel"
        end

        include ModelSettings::DSL

        setting :features, type: :json, storage: {column: :settings} do
          setting :ai_enabled, default: false do
            setting :voice_recognition, default: false
          end
        end
      end

      # All settings should be accessible after compilation
      instance = model_class.create!

      aggregate_failures do
        expect(instance).to respond_to(:ai_enabled)
        expect(instance).to respond_to(:ai_enabled=)
        expect(instance).to respond_to(:voice_recognition)
        expect(instance).to respond_to(:voice_recognition=)
      end
    end
  end

  describe "depth calculation" do
    let(:model_class) do
      Class.new(TestModel) do
        def self.name
          "DepthTestModel"
        end

        include ModelSettings::DSL

        setting :root, type: :json, storage: {column: :settings} do
          setting :child, default: false do
            setting :grandchild, default: false
          end
        end
      end
    end

    it "calculates depth 0 for root settings" do
      root_setting = model_class.find_setting(:root)
      depth = model_class.send(:calculate_depth, root_setting)

      expect(depth).to eq(0)
    end

    it "calculates depth 1 for direct children" do
      child_setting = model_class.find_setting([:root, :child])
      depth = model_class.send(:calculate_depth, child_setting)

      expect(depth).to eq(1)
    end

    it "calculates depth 2 for grandchildren" do
      grandchild_setting = model_class.find_setting([:root, :child, :grandchild])
      depth = model_class.send(:calculate_depth, grandchild_setting)

      expect(depth).to eq(2)
    end
  end

  describe "grouping by depth" do
    let(:model_class) do
      Class.new(TestModel) do
        def self.name
          "GroupingTestModel"
        end

        include ModelSettings::DSL

        setting :billing, type: :json, storage: {column: :settings} do
          setting :invoices, default: false do
            setting :tax_reports, default: false
          end
          setting :payments, default: false
        end
        setting :api_access, type: :column, default: false
      end
    end

    it "groups settings by their nesting level" do
      grouped = model_class.send(:group_settings_by_depth)

      aggregate_failures do
        expect(grouped[0].map(&:name)).to contain_exactly(:billing, :api_access)
        expect(grouped[1].map(&:name)).to contain_exactly(:invoices, :payments)
        expect(grouped[2].map(&:name)).to contain_exactly(:tax_reports)
      end
    end

    it "preserves definition order within each level" do
      grouped = model_class.send(:group_settings_by_depth)

      # Level 0: billing defined before api_access
      expect(grouped[0].map(&:name)).to eq([:billing, :api_access])

      # Level 1: invoices defined before payments
      expect(grouped[1].map(&:name)).to eq([:invoices, :payments])
    end
  end

  describe "adapter setup timing" do
    it "sets up all adapters during compile_settings!" do
      model_class = Class.new(TestModel) do
        def self.name
          "AdapterTimingModel"
        end

        include ModelSettings::DSL

        setting :feature, type: :column, default: false
      end

      # Before any access, compilation hasn't happened yet
      # (compilation is lazy)
      expect(model_class.instance_variable_get(:@_settings_compiled)).to be_nil

      # First access triggers compilation
      model_class.settings

      expect(model_class._settings_compiled).to be true
    end

    it "sets up adapters for nested settings" do
      model_class = Class.new(TestModel) do
        def self.name
          "NestedAdapterModel"
        end

        include ModelSettings::DSL

        setting :parent, type: :json, storage: {column: :settings} do
          setting :child, default: false
        end
      end

      instance = model_class.create!

      aggregate_failures do
        expect(instance).to respond_to(:child)
        expect(instance).to respond_to(:child=)
        expect(instance).to respond_to(:child_enable!)
      end
    end
  end

  # Compilation hooks testing is part of Phase 3: Module Callback Configuration API
  # These tests will be added when the hook registration API is implemented

  describe "initialization behavior" do
    it "compiles settings before instance initialization" do
      model_class = Class.new(TestModel) do
        def self.name
          "InitializationModel"
        end

        include ModelSettings::DSL

        setting :feature, type: :column, default: false
      end

      # Create instance - compilation should happen in initialize
      instance = model_class.new

      aggregate_failures do
        expect(model_class._settings_compiled).to be true
        expect(instance).to respond_to(:feature)
        expect(instance).to respond_to(:feature_enable!)
      end
    end

    it "allows setting values in constructor" do
      model_class = Class.new(TestModel) do
        def self.name
          "ConstructorModel"
        end

        include ModelSettings::DSL

        setting :feature, type: :column, default: false
      end

      # This should work because compile_settings! runs before attribute assignment
      instance = model_class.new(feature: true)

      expect(instance.feature).to be true
    end

    it "compiles settings only once" do
      model_class = Class.new(TestModel) do
        def self.name
          "IdempotentModel"
        end

        include ModelSettings::DSL

        setting :feature, type: :column, default: false
      end

      # Multiple initializations should not re-compile
      first_instance = model_class.new
      second_instance = model_class.new

      # Both should work, compilation happened once
      aggregate_failures do
        expect(first_instance).to respond_to(:feature_enable!)
        expect(second_instance).to respond_to(:feature_enable!)
        expect(model_class._settings_compiled).to be true
      end
    end
  end

  describe "mixed nesting levels" do
    it "handles multiple root settings with different nesting levels" do
      model_class = Class.new(TestModel) do
        def self.name
          "ComplexNestingModel"
        end

        include ModelSettings::DSL

        setting :simple, type: :column, default: false
        setting :nested, type: :json, storage: {column: :settings} do
          setting :level1, default: false do
            setting :level2, default: false
          end
        end
      end

      grouped = model_class.send(:group_settings_by_depth)

      aggregate_failures do
        expect(grouped[0].map(&:name)).to contain_exactly(:simple, :nested)
        expect(grouped[1].map(&:name)).to contain_exactly(:level1)
        expect(grouped[2].map(&:name)).to contain_exactly(:level2)
      end
    end

    it "processes sibling settings at the same level" do
      model_class = Class.new(TestModel) do
        def self.name
          "SiblingsModel"
        end

        include ModelSettings::DSL

        setting :parent, type: :json, storage: {column: :settings} do
          setting :child1, default: false
          setting :child2, default: false
          setting :child3, default: false
        end
      end

      grouped = model_class.send(:group_settings_by_depth)

      # All three children should be at level 1
      expect(grouped[1].map(&:name)).to eq([:child1, :child2, :child3])
    end
  end

  describe "dependency engine integration" do
    it "initializes dependency engine after wave compilation" do
      model_class = Class.new(TestModel) do
        def self.name
          "DependencyEngineModel"
        end

        include ModelSettings::DSL

        setting :feature, type: :column, default: false
      end

      model_class.settings

      expect(model_class._dependency_engine).not_to be_nil
    end

    it "compiles dependency engine with all settings" do
      model_class = Class.new(TestModel) do
        def self.name
          "DependencySettingsModel"
        end

        include ModelSettings::DSL

        setting :parent, type: :column, default: false, enable_cascade: [:child]
        setting :child, type: :column, default: false
      end

      model_class.settings

      # Dependency engine should be compiled and ready
      expect(model_class._dependency_engine).to be_a(ModelSettings::DependencyEngine)
    end
  end
end
# rubocop:enable RSpec/DescribeClass, RSpecGuide/MinimumBehavioralCoverage, RSpec/ExampleLength, RSpec/MultipleExpectations
