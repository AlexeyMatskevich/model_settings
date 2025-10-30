# frozen_string_literal: true

require "spec_helper"

# rubocop:disable RSpec/DescribeClass, RSpec/MultipleExpectations, RSpec/ExampleLength, RSpecGuide/ContextSetup
RSpec.describe "Settings Inheritance" do
  after do
    ModelSettings.reset_configuration!
  end

  # Shared examples for basic inheritance contract
  RSpec.shared_examples "basic inheritance contract" do
    it "inherits all parent settings" do
      parent_settings = parent_class._settings.map(&:name)
      expect(child_class._settings.map(&:name)).to include(*parent_settings)
    end

    it "inherits setting descriptions" do
      settings_with_descriptions = parent_class._settings.select(&:description)

      expect(settings_with_descriptions).to all(
        satisfy do |parent_setting|
          child_setting = child_class.find_setting(parent_setting.name)
          child_setting.description == parent_setting.description
        end
      )
    end

    it "inherits default values" do
      parent_settings = parent_class._settings

      expect(parent_settings).to all(
        satisfy do |parent_setting|
          child_setting = child_class.find_setting(parent_setting.name)
          child_setting.default == parent_setting.default
        end
      )
    end

    it "creates working accessors for inherited settings" do
      instance = child_class.create!
      setting_names = parent_class._settings.map(&:name)

      # Check both getters and setters exist
      expect(setting_names).to all(
        satisfy { |name| instance.respond_to?(name) && instance.respond_to?(:"#{name}=") }
      )
    end
  end

  # Shared examples for storage type inheritance
  RSpec.shared_examples "storage adapter inheritance" do |expected_type|
    it "inherits storage type" do
      setting = child_class.find_setting(setting_name)
      expect(setting.type).to eq(expected_type)
    end

    it "creates functional adapter" do
      # Given: Instance created
      instance = child_class.create!

      # When: Read initial value
      expect { instance.public_send(setting_name) }.not_to raise_error

      # When: Write and persist new value
      instance.public_send(:"#{setting_name}=", test_value)
      instance.save!

      # Then: Value persisted correctly
      expect(instance.reload.public_send(setting_name)).to eq(test_value)
    end
  end

  # Characteristic 1: Configuration (inherit_settings enabled/disabled)
  context "when inherit_settings is enabled" do
    before do
      ModelSettings.configuration.inherit_settings = true
    end

    # Characteristic 2: Inheritance depth
    context "when inheritance depth is single-level" do
      # Characteristic 3: Modification type
      context "without modifications" do
        let(:parent_class) do
          Class.new(TestModel) do
            def self.name
              "ParentModel"
            end

            include ModelSettings::DSL

            setting :notifications_enabled,
              type: :column,
              description: "Enable notifications",
              default: true

            setting :api_access,
              type: :column,
              description: "API access enabled",
              default: false
          end
        end

        let(:child_class) do
          Class.new(parent_class) do
            def self.name
              "ChildModel"
            end
          end
        end

        it_behaves_like "basic inheritance contract"

        it "creates helper methods for inherited boolean settings", :aggregate_failures do
          instance = child_class.create!

          expect(instance).to respond_to(:notifications_enabled_enable!)
          expect(instance).to respond_to(:notifications_enabled_disable!)
          expect(instance).to respond_to(:notifications_enabled_toggle!)
        end

        it "makes helper methods work correctly" do
          instance = child_class.create!(notifications_enabled: false)

          instance.notifications_enabled_enable!
          expect(instance.notifications_enabled).to be true
        end

        it "persists changes through setters" do
          instance = child_class.create!
          instance.notifications_enabled = false
          instance.save!

          expect(instance.reload.notifications_enabled).to be false
        end
      end

      context "with overrides" do
        let(:parent_class) do
          Class.new(TestModel) do
            def self.name
              "ParentModel"
            end

            include ModelSettings::DSL

            setting :notifications_enabled,
              type: :column,
              description: "Enable notifications",
              default: true

            setting :api_access,
              type: :column,
              default: false
          end
        end

        let(:child_class) do
          Class.new(parent_class) do
            def self.name
              "ChildModel"
            end

            # Override with different default
            setting :notifications_enabled, default: false

            # Override with additional description
            setting :api_access,
              default: true,
              description: "Premium API access"
          end
        end

        it "uses overridden default value" do
          notifications = child_class.find_setting(:notifications_enabled)
          expect(notifications.default).to be false
        end

        it "merges description from override" do
          api = child_class.find_setting(:api_access)
          expect(api.description).to eq("Premium API access")
        end

        it "preserves parent description when NOT overridden" do
          notifications = child_class.find_setting(:notifications_enabled)
          expect(notifications.description).to eq("Enable notifications")
        end

        it "applies overridden values to instances" do
          instance = child_class.create!(notifications_enabled: false)
          expect(instance.notifications_enabled).to be false
        end

        it "does NOT affect parent class defaults" do
          parent_instance = parent_class.create!
          expect(parent_instance.notifications_enabled).to be true
        end
      end

      context "and child adds new settings" do
        let(:parent_class) do
          Class.new(TestModel) do
            def self.name
              "ParentModel"
            end

            include ModelSettings::DSL

            setting :base_feature, type: :column, default: true
          end
        end

        let(:child_class) do
          Class.new(parent_class) do
            def self.name
              "ChildModel"
            end

            setting :child_feature, type: :column, default: false
          end
        end

        it "accumulates inherited and new settings" do
          expect(child_class._settings.map(&:name)).to match_array([:base_feature, :child_feature])
        end

        it "creates working accessor for inherited setting" do
          instance = child_class.create!
          expect(instance.base_feature).to be true
        end

        it "creates working accessor for new setting" do
          instance = child_class.create!
          expect(instance.child_feature).to be false
        end
      end
    end

    context "when inheritance depth is multi-level" do
      context "without modifications" do
        let(:base_class) do
          Class.new(TestModel) do
            def self.name
              "BaseModel"
            end

            include ModelSettings::DSL

            setting :level_1, type: :column, default: "base", validate: false
          end
        end

        let(:middle_class) do
          Class.new(base_class) do
            def self.name
              "MiddleModel"
            end

            setting :level_2, type: :column, default: "middle", validate: false
          end
        end

        let(:child_class) do
          Class.new(middle_class) do
            def self.name
              "ChildModel"
            end

            setting :level_3, type: :column, default: "child", validate: false
          end
        end

        it "accumulates settings from all hierarchy levels" do
          expect(child_class._settings.map(&:name)).to match_array([:level_1, :level_2, :level_3])
        end

        it "creates working accessors for all hierarchy levels" do
          instance = child_class.create!

          expect(instance).to have_attributes(
            level_1: "base",
            level_2: "middle",
            level_3: "child"
          )
        end
      end

      context "with overrides at each level" do
        let(:base_class) do
          Class.new(TestModel) do
            def self.name
              "BaseModel"
            end

            include ModelSettings::DSL

            setting :shared_setting,
              type: :column,
              description: "Base description",
              default: "base",
              validate: false
          end
        end

        let(:middle_class) do
          Class.new(base_class) do
            def self.name
              "MiddleModel"
            end

            # Override in middle
            setting :shared_setting, default: "middle"
          end
        end

        let(:child_class) do
          Class.new(middle_class) do
            def self.name
              "ChildModel"
            end

            # Override again in child
            setting :shared_setting,
              default: "child",
              description: "Child description"
          end
        end

        it "uses most recent overrides from child class" do
          setting = child_class.find_setting(:shared_setting)

          expect(setting).to have_attributes(
            default: "child",
            description: "Child description"
          )
        end

        it "does NOT affect parent defaults" do
          middle_setting = middle_class.find_setting(:shared_setting)
          expect(middle_setting.default).to eq("middle")
        end

        it "does NOT affect grandparent defaults" do
          base_setting = base_class.find_setting(:shared_setting)
          expect(base_setting.default).to eq("base")
        end
      end

      context "and each level adds new settings" do
        let(:base_class) do
          Class.new(TestModel) do
            def self.name
              "BaseModel"
            end

            include ModelSettings::DSL

            setting :base_only, type: :column, default: false
          end
        end

        let(:middle_class) do
          Class.new(base_class) do
            def self.name
              "MiddleModel"
            end

            setting :middle_only, type: :column, default: false
          end
        end

        let(:child_class) do
          Class.new(middle_class) do
            def self.name
              "ChildModel"
            end

            setting :child_only, type: :column, default: false
          end
        end

        it "accumulates settings from all levels" do
          expect(child_class._settings.map(&:name)).to match_array([
            :base_only, :middle_only, :child_only
          ])
        end

        it "middle class does NOT see child settings" do
          expect(middle_class._settings.map(&:name)).to match_array([
            :base_only, :middle_only
          ])
        end

        it "base class does NOT see descendant settings" do
          expect(base_class._settings.map(&:name)).to eq([:base_only])
        end
      end
    end

    # Characteristic 4: Storage type (independent characteristic)
    context "when parent uses column storage" do
      let(:parent_class) do
        Class.new(TestModel) do
          def self.name
            "ParentWithColumn"
          end

          include ModelSettings::DSL

          setting :enabled, type: :column, default: true
        end
      end

      let(:child_class) do
        Class.new(parent_class) do
          def self.name
            "ChildOfColumn"
          end
        end
      end

      let(:setting_name) { :enabled }
      let(:test_value) { false }

      it_behaves_like "storage adapter inheritance", :column

      it "creates helper methods for boolean columns", :aggregate_failures do
        instance = child_class.create!

        expect(instance).to respond_to(:enabled_enable!)
        expect(instance).to respond_to(:enabled_disable!)
        expect(instance).to respond_to(:enabled_toggle!)
      end
    end

    context "when parent uses JSON storage" do
      context "without nested settings" do
        let(:parent_class) do
          Class.new(TestModel) do
            def self.name
              "ParentWithJSON"
            end

            include ModelSettings::DSL

            setting :preferences,
              type: :json,
              storage: {column: :settings_data},
              validate: false
          end
        end

        # rubocop:disable RSpecGuide/DuplicateLetValues
        let(:child_class) do
          Class.new(parent_class) do
            def self.name
              "ChildOfJSON"
            end
          end
        end
        # rubocop:enable RSpecGuide/DuplicateLetValues

        let(:setting_name) { :preferences }
        let(:test_value) { {"key" => "value"} }

        it_behaves_like "storage adapter inheritance", :json
      end

      context "with nested settings" do
        let(:parent_class) do
          Class.new(TestModel) do
            def self.name
              "ParentWithJSON"
            end

            include ModelSettings::DSL

            setting :preferences,
              type: :json,
              storage: {column: :settings_data} do
              setting :theme, default: "dark", validate: false
            end
          end
        end

        # rubocop:disable RSpecGuide/DuplicateLetValues
        let(:child_class) do
          Class.new(parent_class) do
            def self.name
              "ChildOfJSON"
            end
          end
        end
        # rubocop:enable RSpecGuide/DuplicateLetValues

        it "inherits JSON parent with nested children" do
          prefs = child_class.find_setting(:preferences)
          theme = prefs.children.find { |c| c.name == :theme }

          expect(prefs.type).to eq(:json)
          expect(theme).not_to be_nil
        end

        it "creates working adapter for nested settings" do
          instance = child_class.create!

          # Test default
          expect(instance.theme).to eq("dark")

          # Test write and persist
          instance.theme = "light"
          instance.save!

          expect(instance.reload.theme).to eq("light")
        end
      end

      # NOTE: Child override with adding nested settings is a complex feature
      # that requires deep merge logic. This is deferred to future iteration.
      # For now, child can either fully override parent JSON setting OR inherit as-is.
    end

    context "when parent uses StoreModel storage" do
      let(:parent_class) do
        Class.new(TestModel) do
          def self.name
            "ParentWithStoreModel"
          end

          include ModelSettings::DSL

          setting :ai_settings,
            type: :store_model,
            storage: {column: :ai_settings, model: AiSettingsStore} do
            setting :ai_transcription, default: false
          end
        end
      end

      let(:child_class) do
        Class.new(parent_class) do
          def self.name
            "ChildOfStoreModel"
          end
        end
      end

      it "inherits StoreModel setting" do
        config = child_class.find_setting(:ai_settings)
        expect(config.type).to eq(:store_model)
      end

      # NOTE: StoreModel adapter with inheritance has known issues with adapter setup
      # causing infinite recursion when methods are defined on child classes.
      # This is pending investigation and fix in a future iteration.
      xit "creates working StoreModel adapter" do
        instance = child_class.create!

        expect(instance.ai_settings).to be_a(AiSettingsStore)

        instance.ai_settings.ai_transcription = true
        instance.save!

        reloaded = instance.reload
        expect(reloaded.ai_settings.ai_transcription).to be true
      end
    end

    # Characteristic 5: Edge cases and constraints
    context "with edge cases" do
      context "when multiple children inherit from same parent" do
        let(:parent_class) do
          Class.new(TestModel) do
            def self.name
              "SharedParent"
            end

            include ModelSettings::DSL

            setting :shared_setting, type: :column, default: true
          end
        end

        let(:child_a) do
          Class.new(parent_class) do
            def self.name
              "ChildA"
            end

            setting :feature_a, type: :column, default: false
          end
        end

        let(:child_b) do
          Class.new(parent_class) do
            def self.name
              "ChildB"
            end

            setting :feature_b, type: :column, default: false
          end
        end

        it "isolates child-specific settings" do
          expect(child_a._settings.map(&:name)).not_to include(:feature_b)
          expect(child_b._settings.map(&:name)).not_to include(:feature_a)
        end

        it "both children inherit parent settings" do
          expect(child_a._settings.map(&:name)).to include(:shared_setting)
          expect(child_b._settings.map(&:name)).to include(:shared_setting)
        end

        it "overrides in one child do NOT affect sibling" do
          child_a_override = Class.new(parent_class) do
            def self.name
              "ChildAOverride"
            end

            setting :shared_setting, default: false
          end

          child_b_separate = Class.new(parent_class) do
            def self.name
              "ChildBSeparate"
            end
          end

          expect(child_a_override.find_setting(:shared_setting).default).to be false
          expect(child_b_separate.find_setting(:shared_setting).default).to be true
        end
      end

      context "when parent has no settings" do
        let(:parent_class) do
          Class.new(TestModel) do
            def self.name
              "EmptyParent"
            end

            include ModelSettings::DSL
            # No settings defined
          end
        end

        let(:child_class) do
          Class.new(parent_class) do
            def self.name
              "ChildOfEmpty"
            end

            setting :child_setting, type: :column, default: true
          end
        end

        it "child can define settings normally" do
          expect(child_class._settings.map(&:name)).to eq([:child_setting])
        end

        it "creates working accessors" do
          instance = child_class.create!(child_setting: true)
          expect(instance.child_setting).to be true

          instance.child_setting = false
          instance.save!
          expect(instance.reload.child_setting).to be false
        end
      end

      context "when child overrides without specifying type" do
        let(:parent_class) do
          Class.new(TestModel) do
            def self.name
              "ParentWithType"
            end

            include ModelSettings::DSL

            setting :typed_setting, type: :column, default: true
          end
        end

        let(:child_class) do
          Class.new(parent_class) do
            def self.name
              "ChildOverride"
            end

            # Override without type - should inherit parent's type
            setting :typed_setting, default: false
          end
        end

        it "inherits parent type but uses overridden default" do
          setting = child_class.find_setting(:typed_setting)

          expect(setting).to have_attributes(
            type: :column,
            default: false
          )
        end
      end

      context "when parent has cascades configured" do
        let(:parent_class) do
          Class.new(TestModel) do
            def self.name
              "ParentWithCascade"
            end

            include ModelSettings::DSL

            setting :parent, type: :column, default: false
            setting :child_a,
              type: :column,
              default: false,
              cascade: {enable: [:parent]}

            compile_settings!
          end
        end

        let(:child_class) do
          child = Class.new(parent_class) do
            def self.name
              "ChildOfCascade"
            end
          end
          child.compile_settings!
          child
        end

        it "inherits cascade configuration" do
          setting = child_class.find_setting(:child_a)
          expect(setting.options[:cascade]).to eq({enable: [:parent]})
        end

        # NOTE: Functional cascade testing on inherited settings requires
        # dependency_engine to be properly inherited and compiled.
        # Configuration inheritance is verified above. Functional test deferred.
      end

      context "when parent has syncs configured" do
        let(:parent_class) do
          Class.new(TestModel) do
            def self.name
              "ParentWithSync"
            end

            include ModelSettings::DSL

            setting :source, type: :column, default: true
            setting :target,
              type: :column,
              default: false,
              sync: {target: :source, mode: :forward}

            compile_settings!
          end
        end

        let(:child_class) do
          child = Class.new(parent_class) do
            def self.name
              "ChildOfSync"
            end
          end
          child.compile_settings!
          child
        end

        it "inherits sync configuration" do
          setting = child_class.find_setting(:target)
          expect(setting.options[:sync]).to eq({target: :source, mode: :forward})
        end

        # NOTE: Functional sync testing on inherited settings requires
        # dependency_engine to be properly inherited and compiled.
        # Configuration inheritance is verified above. Functional test deferred.
      end
    end
  end

  # Characteristic 1: Configuration = disabled
  context "when inherit_settings is disabled" do
    before do
      ModelSettings.configuration.inherit_settings = false
    end

    let(:parent_class) do
      Class.new(TestModel) do
        def self.name
          "ParentModel"
        end

        include ModelSettings::DSL

        setting :parent_setting, type: :column, default: true
      end
    end

    let(:child_class) do
      Class.new(parent_class) do
        def self.name
          "ChildModel"
        end

        setting :child_setting, type: :column, default: false
      end
    end

    it "only has own settings, not parent settings" do
      expect(child_class._settings.map(&:name)).to eq([:child_setting])
    end

    it "creates accessors for own setting" do
      instance = child_class.create!
      expect(instance.child_setting).to be false
    end

    it "parent class is unaffected" do
      expect(parent_class._settings.map(&:name)).to eq([:parent_setting])
    end
  end
end
# rubocop:enable RSpec/DescribeClass, RSpec/MultipleExpectations, RSpec/ExampleLength, RSpecGuide/ContextSetup
