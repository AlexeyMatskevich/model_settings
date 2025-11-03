# frozen_string_literal: true

require "spec_helper"

# rubocop:disable RSpec/DescribeClass, RSpecGuide/MinimumBehavioralCoverage
RSpec.describe "Merge Strategies" do
  around do |example|
    # Save current registry state
    saved_state = save_registry_state

    example.run
  ensure
    # Restore original state instead of reset to preserve callbacks
    restore_registry_state(saved_state)
  end

  describe "ModuleRegistry.register_inheritable_option" do
    it "registers option with default :replace strategy" do
      ModelSettings::ModuleRegistry.register_inheritable_option(:custom_option)

      strategy = ModelSettings::ModuleRegistry.merge_strategy_for(:custom_option)
      expect(strategy).to eq(:replace)
    end

    it "registers option with :append strategy" do
      ModelSettings::ModuleRegistry.register_inheritable_option(
        :roles,
        merge_strategy: :append
      )

      strategy = ModelSettings::ModuleRegistry.merge_strategy_for(:roles)
      expect(strategy).to eq(:append)
    end

    it "registers option with :merge strategy" do
      ModelSettings::ModuleRegistry.register_inheritable_option(
        :config,
        merge_strategy: :merge
      )

      strategy = ModelSettings::ModuleRegistry.merge_strategy_for(:config)
      expect(strategy).to eq(:merge)
    end

    it "raises error for invalid merge strategy" do
      expect {
        ModelSettings::ModuleRegistry.register_inheritable_option(
          :option,
          merge_strategy: :invalid
        )
      }.to raise_error(ArgumentError, /Invalid merge strategy: :invalid/)
    end

    # rubocop:disable RSpec/MultipleExpectations
    it "stores option in registered_inheritable_options hash" do
      ModelSettings::ModuleRegistry.register_inheritable_option(
        :test_option,
        merge_strategy: :append
      )

      options = ModelSettings::ModuleRegistry.registered_inheritable_options
      expect(options).to be_a(Hash)
      expect(options[:test_option]).to eq({merge_strategy: :append, auto_include: true})
    end
    # rubocop:enable RSpec/MultipleExpectations
  end

  describe "ModuleRegistry.merge_strategy_for" do
    it "returns registered strategy" do
      ModelSettings::ModuleRegistry.register_inheritable_option(
        :test,
        merge_strategy: :merge
      )

      strategy = ModelSettings::ModuleRegistry.merge_strategy_for(:test)
      expect(strategy).to eq(:merge)
    end

    it "returns nil for unregistered option" do
      strategy = ModelSettings::ModuleRegistry.merge_strategy_for(:nonexistent)
      expect(strategy).to be_nil
    end
  end

  describe "ModuleRegistry.inheritable_option?" do
    context "when option is registered" do
      before do
        ModelSettings::ModuleRegistry.register_inheritable_option(:test)
      end

      it "returns true" do
        result = ModelSettings::ModuleRegistry.inheritable_option?(:test)
        expect(result).to be true
      end
    end

    # rubocop:disable RSpecGuide/ContextSetup
    context "but when option is unregistered" do
      # rubocop:enable RSpecGuide/ContextSetup
      it "returns false" do
        result = ModelSettings::ModuleRegistry.inheritable_option?(:nonexistent)
        expect(result).to be false
      end
    end
  end

  describe "Setting.merge_inherited_options" do
    describe ":replace strategy" do
      before do
        ModelSettings::ModuleRegistry.register_inheritable_option(
          :test_option,
          merge_strategy: :replace
        )
      end

      it "replaces parent value with child value" do
        parent_options = {test_option: "parent_value"}
        child_options = {test_option: "child_value"}

        result = ModelSettings::Setting.merge_inherited_options(
          parent_options,
          child_options
        )

        expect(result[:test_option]).to eq("child_value")
      end

      it "uses child value when parent is nil" do
        parent_options = {test_option: nil}
        child_options = {test_option: "child_value"}

        result = ModelSettings::Setting.merge_inherited_options(
          parent_options,
          child_options
        )

        expect(result[:test_option]).to eq("child_value")
      end

      it "uses nil when child value is nil" do
        parent_options = {test_option: "parent_value"}
        child_options = {test_option: nil}

        result = ModelSettings::Setting.merge_inherited_options(
          parent_options,
          child_options
        )

        expect(result[:test_option]).to be_nil
      end

      it "defaults to :replace for unregistered options" do
        parent_options = {unregistered: "parent"}
        child_options = {unregistered: "child"}

        result = ModelSettings::Setting.merge_inherited_options(
          parent_options,
          child_options
        )

        expect(result[:unregistered]).to eq("child")
      end
    end

    describe ":append strategy" do
      before do
        ModelSettings::ModuleRegistry.register_inheritable_option(
          :roles,
          merge_strategy: :append
        )
      end

      it "concatenates parent and child arrays" do
        parent_options = {roles: [:admin, :finance]}
        child_options = {roles: [:manager]}

        result = ModelSettings::Setting.merge_inherited_options(
          parent_options,
          child_options
        )

        expect(result[:roles]).to eq([:admin, :finance, :manager])
      end

      it "handles nil parent value" do
        parent_options = {roles: nil}
        child_options = {roles: [:manager]}

        result = ModelSettings::Setting.merge_inherited_options(
          parent_options,
          child_options
        )

        expect(result[:roles]).to eq([:manager])
      end

      it "handles nil child value" do
        parent_options = {roles: [:admin]}
        child_options = {roles: nil}

        result = ModelSettings::Setting.merge_inherited_options(
          parent_options,
          child_options
        )

        expect(result[:roles]).to eq([:admin])
      end

      it "handles both nil values" do
        parent_options = {roles: nil}
        child_options = {roles: nil}

        result = ModelSettings::Setting.merge_inherited_options(
          parent_options,
          child_options
        )

        expect(result[:roles]).to eq([])
      end

      it "handles empty arrays" do
        parent_options = {roles: []}
        child_options = {roles: [:manager]}

        result = ModelSettings::Setting.merge_inherited_options(
          parent_options,
          child_options
        )

        expect(result[:roles]).to eq([:manager])
      end

      # rubocop:disable RSpec/ExampleLength
      it "raises error when parent is not an array" do
        parent_options = {roles: :admin}  # Symbol, not Array
        child_options = {roles: [:manager]}

        expect {
          ModelSettings::Setting.merge_inherited_options(
            parent_options,
            child_options
          )
        }.to raise_error(
          ArgumentError,
          /Cannot use :append merge strategy for :roles.*Both must be Arrays/
        )
      end
      # rubocop:enable RSpec/ExampleLength

      # rubocop:disable RSpec/ExampleLength
      it "raises error when child is not an array" do
        parent_options = {roles: [:admin]}
        child_options = {roles: :manager}  # Symbol, not Array

        expect {
          ModelSettings::Setting.merge_inherited_options(
            parent_options,
            child_options
          )
        }.to raise_error(
          ArgumentError,
          /Cannot use :append merge strategy for :roles.*Both must be Arrays/
        )
      end
      # rubocop:enable RSpec/ExampleLength
    end

    describe ":merge strategy" do
      before do
        ModelSettings::ModuleRegistry.register_inheritable_option(
          :config,
          merge_strategy: :merge
        )
      end

      it "merges parent and child hashes" do
        parent_options = {config: {a: 1, b: 2}}
        child_options = {config: {b: 3, c: 4}}

        result = ModelSettings::Setting.merge_inherited_options(
          parent_options,
          child_options
        )

        expect(result[:config]).to eq({a: 1, b: 3, c: 4})
      end

      it "child keys override parent keys" do
        parent_options = {config: {key: "parent_value"}}
        child_options = {config: {key: "child_value"}}

        result = ModelSettings::Setting.merge_inherited_options(
          parent_options,
          child_options
        )

        expect(result[:config]).to eq({key: "child_value"})
      end

      it "handles nil parent value" do
        parent_options = {config: nil}
        child_options = {config: {a: 1}}

        result = ModelSettings::Setting.merge_inherited_options(
          parent_options,
          child_options
        )

        expect(result[:config]).to eq({a: 1})
      end

      it "handles nil child value" do
        parent_options = {config: {a: 1}}
        child_options = {config: nil}

        result = ModelSettings::Setting.merge_inherited_options(
          parent_options,
          child_options
        )

        expect(result[:config]).to eq({a: 1})
      end

      it "handles both nil values" do
        parent_options = {config: nil}
        child_options = {config: nil}

        result = ModelSettings::Setting.merge_inherited_options(
          parent_options,
          child_options
        )

        expect(result[:config]).to eq({})
      end

      it "handles empty hashes" do
        parent_options = {config: {}}
        child_options = {config: {a: 1}}

        result = ModelSettings::Setting.merge_inherited_options(
          parent_options,
          child_options
        )

        expect(result[:config]).to eq({a: 1})
      end

      # rubocop:disable RSpec/ExampleLength
      it "raises error when parent is not a hash" do
        parent_options = {config: "string"}  # String, not Hash
        child_options = {config: {a: 1}}

        expect {
          ModelSettings::Setting.merge_inherited_options(
            parent_options,
            child_options
          )
        }.to raise_error(
          ArgumentError,
          /Cannot use :merge merge strategy for :config.*Both must be Hashes/
        )
      end
      # rubocop:enable RSpec/ExampleLength

      # rubocop:disable RSpec/ExampleLength
      it "raises error when child is not a hash" do
        parent_options = {config: {a: 1}}
        child_options = {config: "string"}  # String, not Hash

        expect {
          ModelSettings::Setting.merge_inherited_options(
            parent_options,
            child_options
          )
        }.to raise_error(
          ArgumentError,
          /Cannot use :merge merge strategy for :config.*Both must be Hashes/
        )
      end
      # rubocop:enable RSpec/ExampleLength
    end

    describe "backwards compatibility" do
      before do
        # Re-register core options (cleared by reset! in outer around hook)
        ModelSettings::ModuleRegistry.register_inheritable_option(:metadata, merge_strategy: :merge, auto_include: false)
        ModelSettings::ModuleRegistry.register_inheritable_option(:cascade, merge_strategy: :merge, auto_include: false)
        # Enable inheritance for these options (since auto_include: false)
        ModelSettings.configuration.inheritable_options = [:metadata, :cascade]
      end

      it "merges :metadata option (registered with :merge strategy)" do
        parent_options = {metadata: {category: "finance"}}
        child_options = {metadata: {audit: true}}

        result = ModelSettings::Setting.merge_inherited_options(
          parent_options,
          child_options
        )

        expect(result[:metadata]).to eq({category: "finance", audit: true})
      end

      it "merges :cascade option (registered with :merge strategy)" do
        parent_options = {cascade: {enable: [:child1]}}
        child_options = {cascade: {disable: [:child2]}}

        result = ModelSettings::Setting.merge_inherited_options(
          parent_options,
          child_options
        )

        expect(result[:cascade]).to eq({enable: [:child1], disable: [:child2]})
      end
    end

    describe "mixed strategies" do
      before do
        ModelSettings::ModuleRegistry.register_inheritable_option(
          :roles,
          merge_strategy: :append
        )
        ModelSettings::ModuleRegistry.register_inheritable_option(
          :config,
          merge_strategy: :merge
        )
        ModelSettings::ModuleRegistry.register_inheritable_option(
          :policy,
          merge_strategy: :replace
        )
        # Explicitly configure these options as inheritable (not relying on auto_include)
        ModelSettings.configuration.inheritable_options = [:roles, :config, :policy]
      end

      it "applies correct strategy to each option" do
        parent_options = {
          roles: [:admin],
          config: {a: 1},
          policy: "ParentPolicy"
        }
        child_options = {
          roles: [:manager],
          config: {b: 2},
          policy: "ChildPolicy"
        }

        result = ModelSettings::Setting.merge_inherited_options(
          parent_options,
          child_options
        )

        expect(result).to eq({
          roles: [:admin, :manager],      # :append
          config: {a: 1, b: 2},            # :merge
          policy: "ChildPolicy"            # :replace
        })
      end
    end
  end
end
# rubocop:enable RSpec/DescribeClass, RSpecGuide/MinimumBehavioralCoverage
