# frozen_string_literal: true

require "spec_helper"
require "store_model"

# Integration tests that verify all adapters implement the same contract
# using shared examples
# rubocop:disable RSpec/DescribeClass, RSpecGuide/CharacteristicsAndContexts
RSpec.describe "Adapter shared behavior" do
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
    let(:setting_name) { :enabled }
    let(:adapter) do
      described_class.new(model_class, model_class.find_setting(:enabled))
    end

    it_behaves_like "an adapter with helper methods"
    it_behaves_like "an adapter with dirty tracking"
    it_behaves_like "an adapter with read/write operations"
    it_behaves_like "an adapter with persistence"
  end

  describe ModelSettings::Adapters::Json do
    before do
      ActiveRecord::Schema.define do
        create_table :json_adapter_test_models, force: true do |t|
          t.text :settings
        end
      end

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
    let(:setting_name) { :enabled }
    let(:adapter) do
      described_class.new(JsonAdapterTestModel, JsonAdapterTestModel.find_setting(:enabled))
    end

    it_behaves_like "an adapter with helper methods"
    it_behaves_like "an adapter with dirty tracking"
    it_behaves_like "an adapter with read/write operations"
    it_behaves_like "an adapter with persistence"
  end

  describe ModelSettings::Adapters::StoreModel do
    before do
      ActiveRecord::Schema.define do
        create_table :store_model_adapter_test_models, force: true do |t|
          t.text :settings
        end
      end

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
    let(:setting_name) { :enabled }
    let(:adapter) do
      described_class.new(StoreModelAdapterTestModel, StoreModelAdapterTestModel.find_setting(:enabled))
    end

    it_behaves_like "an adapter with helper methods"
    it_behaves_like "an adapter with dirty tracking"
    it_behaves_like "an adapter with read/write operations"
    it_behaves_like "an adapter with persistence"
  end
end
# rubocop:enable RSpec/DescribeClass, RSpecGuide/CharacteristicsAndContexts
