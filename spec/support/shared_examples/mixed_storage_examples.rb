# frozen_string_literal: true

RSpec.shared_examples "mixed storage basic operations" do
  # Expected parameters via let:
  # - parent_name (Symbol)
  # - parent_type (Symbol: :column, :json, :store_model)
  # - parent_storage (Hash or nil)
  # - parent_default (any)
  # - child_name (Symbol)
  # - child_type (Symbol: :column, :json, :store_model)
  # - child_storage (Hash or nil)
  # - child_default (any)
  # - child_extra_options (Hash) - optional, for array: true etc
  #
  # Optional (can be overridden):
  # - parent_test_value - value to test parent storage
  # - child_test_value - value to test child storage
  # - child_extra_options - extra options for child setting (e.g., array: true)

  # Default test values with fallback logic (can be overridden in calling specs)
  let(:parent_test_value) do
    case parent_type
    when :column, :store_model
      !parent_default
    when :json
      parent_storage ? "parent_test" : parent_default
    end
  end

  let(:child_test_value) do
    extra_opts = defined?(child_extra_options) ? child_extra_options : {}
    case child_type
    when :column, :store_model
      !child_default
    when :json
      extra_opts[:array] ? ["test", "values"] : !child_default
    end
  end

  let(:instance) do
    # Initialize StoreModel attributes if needed
    attrs = {}
    attrs[:premium_features] = PremiumFeaturesStore.new if defined?(PremiumFeaturesStore)
    attrs[:ai_settings] = AiSettingsStore.new if defined?(AiSettingsStore)
    model_class.create!(**attrs)
  end

  # Phase 1: Preparation - define settings structure
  before do
    parent_options = {type: parent_type, default: parent_default}
    parent_options[:storage] = parent_storage if parent_storage

    # Capture let variables before instance_eval block
    captured_child_name = child_name
    captured_child_type = child_type
    captured_child_storage = child_storage
    captured_child_default = child_default
    captured_child_extra_options = defined?(child_extra_options) ? child_extra_options : {}

    # Phase 2: Action - compile settings
    model_class.setting parent_name, **parent_options do
      child_options = {type: captured_child_type, default: captured_child_default}.merge(captured_child_extra_options)
      child_options[:storage] = captured_child_storage if captured_child_storage

      setting captured_child_name, **child_options
    end

    model_class.compile_settings!
  end

  # Interface contract - invariant tests (always true regardless of characteristics)
  it "creates accessor for parent" do
    expect(instance).to respond_to(parent_name)
  end

  it "creates writer for parent" do
    expect(instance).to respond_to(:"#{parent_name}=")
  end

  it "creates accessor for child" do
    expect(instance).to respond_to(child_name)
  end

  it "creates writer for child" do
    expect(instance).to respond_to(:"#{child_name}=")
  end

  it "reads parent default value" do
    expect(instance.public_send(parent_name)).to eq(parent_default)
  end

  it "reads child default value" do
    expect(instance.public_send(child_name)).to eq(child_default)
  end

  # Persistence behavior - depends on value type characteristic
  context "when child is NOT an array type" do
    before do
      extra_opts = defined?(child_extra_options) ? child_extra_options : {}
      skip "Array types skip this test" if extra_opts[:array]
    end

    # rubocop:disable RSpec/ExampleLength
    it "stores and retrieves child value" do
      instance.public_send(:"#{child_name}=", child_test_value)
      instance.save!
      instance.reload

      expect(instance.public_send(child_name)).to eq(child_test_value)
    end
    # rubocop:enable RSpec/ExampleLength
  end

  # Change tracking behavior - lifecycle characteristic
  describe "change tracking" do
    context "when parent value changes" do
      before do
        instance.public_send(:"#{parent_name}=", parent_test_value)
      end

      it "marks parent as changed" do
        expect(instance.public_send(:"#{parent_name}_changed?")).to be true
      end

      it "does NOT mark child as changed" do
        expect(instance.public_send(:"#{child_name}_changed?")).to be false
      end
    end

    # rubocop:disable RSpec/ExampleLength
    context "when parent is saved and child value changes" do
      before do
        instance.public_send(:"#{parent_name}=", parent_test_value)
        instance.save!
        instance.public_send(:"#{child_name}=", child_test_value)
      end

      it "marks child as changed" do
        expect(instance.public_send(:"#{child_name}_changed?")).to be true
      end
    end
    # rubocop:enable RSpec/ExampleLength
  end
end

RSpec.shared_examples "mixed storage with enable cascade" do
  # Expected parameters: same as basic operations plus:
  # - parent_cascade_value (value to trigger cascade, usually true)
  # - child_enabled_value (expected child value after cascade, usually true)

  let(:parent_cascade_value) { true }
  let(:child_enabled_value) { true }

  let(:instance) do
    # Initialize StoreModel attributes if needed
    attrs = {}
    attrs[:premium_features] = PremiumFeaturesStore.new if defined?(PremiumFeaturesStore)
    attrs[:ai_settings] = AiSettingsStore.new if defined?(AiSettingsStore)
    model_class.create!(**attrs)
  end

  # Phase 1: Preparation - define settings with cascade
  before do
    parent_options = {
      type: parent_type,
      default: parent_default,
      cascade: {enable: true}
    }
    parent_options[:storage] = parent_storage if parent_storage

    # Capture let variables before instance_eval block
    captured_child_name = child_name
    captured_child_type = child_type
    captured_child_storage = child_storage
    captured_child_default = child_default
    captured_child_extra_options = defined?(child_extra_options) ? child_extra_options : {}

    # Phase 2: Action - compile settings
    model_class.setting parent_name, **parent_options do
      child_options = {type: captured_child_type, default: captured_child_default}.merge(captured_child_extra_options)
      child_options[:storage] = captured_child_storage if captured_child_storage

      setting captured_child_name, **child_options
    end

    model_class.compile_settings!
  end

  context "when parent is enabled" do
    before do
      instance.public_send(:"#{parent_name}=", parent_cascade_value)
      instance.save!
      instance.reload
    end

    it "cascades enable to child" do
      expect(instance.public_send(child_name)).to eq(child_enabled_value)
    end
  end

  context "when parent is disabled" do
    before do
      instance.public_send(:"#{parent_name}=", !parent_cascade_value)
      instance.save!
      instance.reload
    end

    it "does NOT cascade to child" do
      expect(instance.public_send(child_name)).to eq(child_default)
    end
  end
end

RSpec.shared_examples "mixed storage with disable cascade" do
  # Expected parameters: same as enable cascade plus:
  # - parent_disable_value (value to trigger disable cascade, usually false)
  # - child_disabled_value (expected child value after disable cascade, usually false)

  let(:parent_disable_value) { false }
  let(:child_disabled_value) { false }

  let(:instance) do
    # Initialize StoreModel attributes if needed
    attrs = {}
    attrs[:premium_features] = PremiumFeaturesStore.new if defined?(PremiumFeaturesStore)
    attrs[:ai_settings] = AiSettingsStore.new if defined?(AiSettingsStore)
    model_class.create!(**attrs)
  end

  # Phase 1: Preparation - define settings with cascade
  before do
    parent_options = {
      type: parent_type,
      default: parent_default,
      cascade: {disable: true}
    }
    parent_options[:storage] = parent_storage if parent_storage

    # Capture let variables before instance_eval block
    captured_child_name = child_name
    captured_child_type = child_type
    captured_child_storage = child_storage
    captured_child_default = child_default
    captured_child_extra_options = defined?(child_extra_options) ? child_extra_options : {}

    # Phase 2: Action - compile settings
    model_class.setting parent_name, **parent_options do
      child_options = {type: captured_child_type, default: captured_child_default}.merge(captured_child_extra_options)
      child_options[:storage] = captured_child_storage if captured_child_storage

      setting captured_child_name, **child_options
    end

    model_class.compile_settings!
  end

  # Happy path first (Rule 7)
  context "when parent is enabled" do
    before do
      instance.public_send(:"#{parent_name}=", !parent_disable_value)
      instance.save!
      instance.reload
    end

    it "does NOT cascade to child" do
      expect(instance.public_send(child_name)).to eq(child_default)
    end
  end

  # Corner case second (Rule 7)
  context "when parent is disabled" do
    before do
      # First enable both
      instance.update!(
        parent_name => !parent_disable_value,
        child_name => !child_disabled_value
      )

      # Then disable parent
      instance.public_send(:"#{parent_name}=", parent_disable_value)
      instance.save!
      instance.reload
    end

    it "cascades disable to child" do
      expect(instance.public_send(child_name)).to eq(child_disabled_value)
    end
  end
end

# Combined contract for all mixed storage tests
RSpec.shared_examples "mixed storage contract" do
  it_behaves_like "mixed storage basic operations"
  it_behaves_like "mixed storage with enable cascade"
  it_behaves_like "mixed storage with disable cascade"
end
