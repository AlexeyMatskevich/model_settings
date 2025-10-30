# frozen_string_literal: true

require "spec_helper"
require "store_model"

# Integration tests that verify all adapters implement the same contract
# using shared examples
# rubocop:disable RSpec/DescribeClass
RSpec.describe "Adapter shared behavior" do
  # Common setting name used across all adapters
  let(:setting_name) { :enabled }

  # Group all adapter contract checks into a single shared example
  shared_examples "adapter contract" do
    it_behaves_like "an adapter with helper methods"
    it_behaves_like "an adapter with dirty tracking"
    it_behaves_like "an adapter with read/write operations"
    it_behaves_like "an adapter with persistence"
  end

  # rubocop:disable RSpecGuide/CharacteristicsAndContexts
  describe ModelSettings::Adapters::Column do
    let(:model_class) do
      Class.new(TestModel) do
        def self.name
          "ColumnAdapterTestModel"
        end

        include ModelSettings::DSL

        setting :enabled, type: :column, default: false
      end
    end

    let(:instance) { model_class.create! }
    let(:adapter) do
      described_class.new(model_class, model_class.find_setting(:enabled))
    end

    it_behaves_like "adapter contract"
  end
  # rubocop:enable RSpecGuide/CharacteristicsAndContexts

  # rubocop:disable RSpecGuide/CharacteristicsAndContexts
  describe ModelSettings::Adapters::Json do
    before do
      # Table already exists from active_record.rb
      klass = Class.new(ActiveRecord::Base) do
        self.table_name = "json_adapter_test_models"
        include ModelSettings::DSL

        serialize :settings, coder: JSON

        setting :enabled,
          type: :json,
          storage: {column: :settings},
          default: false
      end
      stub_const("JsonAdapterTestModel", klass)
    end

    let(:instance) { JsonAdapterTestModel.create! }
    let(:adapter) do
      described_class.new(JsonAdapterTestModel, JsonAdapterTestModel.find_setting(:enabled))
    end

    it_behaves_like "adapter contract"
  end
  # rubocop:enable RSpecGuide/CharacteristicsAndContexts

  # rubocop:disable RSpecGuide/CharacteristicsAndContexts
  describe ModelSettings::Adapters::StoreModel do
    before do
      # Table already exists from active_record.rb
      stub_const("TestSettings", Class.new do
        include ::StoreModel::Model

        attribute :enabled, :boolean, default: false
      end)

      klass = Class.new(ActiveRecord::Base) do
        self.table_name = "store_model_adapter_test_models"
        include ModelSettings::DSL

        attribute :settings, TestSettings.to_type

        setting :enabled,
          type: :store_model,
          storage: {column: :settings}
      end
      stub_const("StoreModelAdapterTestModel", klass)
    end

    let(:instance) do
      StoreModelAdapterTestModel.create!(settings: TestSettings.new)
    end
    let(:adapter) do
      described_class.new(StoreModelAdapterTestModel, StoreModelAdapterTestModel.find_setting(:enabled))
    end

    it_behaves_like "adapter contract"
  end
  # rubocop:enable RSpecGuide/CharacteristicsAndContexts
end
# rubocop:enable RSpec/DescribeClass
