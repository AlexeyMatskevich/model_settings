# frozen_string_literal: true

require "spec_helper"

# rubocop:disable RSpecGuide/MinimumBehavioralCoverage
RSpec.describe ModelSettings::DeprecationAuditor do
  let(:auditor) { described_class.new }
  # rubocop:enable RSpecGuide/MinimumBehavioralCoverage

  describe "#generate_report" do
    let(:model_class) do
      Class.new(ActiveRecord::Base) do
        self.table_name = "test_models"

        def self.name
          "DeprecationTestModel"
        end

        include ModelSettings::DSL

        setting :active_feature, type: :column, default: false
        setting :deprecated_feature,
          type: :column,
          default: false,
          deprecated: "Use active_feature instead"
      end
    end

    before do
      # Setup test database
      ActiveRecord::Base.connection.create_table :test_models, force: true do |t|
        t.boolean :active_feature
        t.boolean :deprecated_feature
      end

      model_class.compile_settings!
      allow(auditor).to receive(:find_models_with_settings).and_return([model_class])
    end

    after do
      ActiveRecord::Base.connection.drop_table :test_models, if_exists: true
    end

    # Happy path first - when deprecated settings are actively used
    context "when deprecated settings are in use" do
      before do
        # Create records with deprecated setting enabled
        3.times { model_class.create!(deprecated_feature: true) }
        2.times { model_class.create!(deprecated_feature: false) }
      end

      it "reports active usage with counts" do
        report = auditor.generate_report

        expect(report).to have_attributes(
          has_active_usage?: true,
          model_reports: contain_exactly(
            hash_including(
              model_class: model_class,
              settings: contain_exactly(
                hash_including(
                  usage_count: 3,
                  total_count: 5
                )
              )
            )
          )
        )
      end

      it "formats report with details" do
        report = auditor.generate_report
        output = report.to_s

        expect(output).to include("⚠️  Found deprecated settings in use")
          .and include("DeprecationTestModel (1 deprecated settings)")
          .and include("✗ deprecated_feature")
          .and include("Reason: Use active_feature instead")
          .and include("Used in: 3 records (out of 5 total)")
      end
    end

    # Edge case - deprecated settings exist but not used
    # rubocop:disable RSpecGuide/ContextSetup
    context "when deprecated settings exist but are not used" do
      # rubocop:enable RSpecGuide/ContextSetup
      # No records created - testing zero usage scenario

      it "returns report with zero usage" do
        report = auditor.generate_report

        expect(report).to have_attributes(
          has_active_usage?: false
        )
      end

      it "formats success message" do
        report = auditor.generate_report

        expect(report.to_s).to eq("✓ No deprecated settings found in use")
      end
    end

    # Edge case - no deprecated settings at all
    context "when no deprecated settings exist" do
      let(:model_without_deprecated) do
        Class.new(ActiveRecord::Base) do
          self.table_name = "test_models"

          def self.name
            "CleanModel"
          end

          include ModelSettings::DSL

          setting :normal_setting, type: :column, default: false
        end
      end

      before do
        allow(auditor).to receive(:find_models_with_settings).and_return([model_without_deprecated])
      end

      it "returns empty report" do
        report = auditor.generate_report

        expect(report.model_reports).to be_empty
      end
    end
  end

  describe "Report#has_active_usage?" do
    let(:report) { described_class::Report.new }
    let(:test_setting) { instance_double(ModelSettings::Setting, name: :test) }

    # Happy path first - usage detected
    context "when at least one setting has usage" do
      before do
        report.add_model_report(
          Class,
          [{setting: test_setting, usage_count: 5, total_count: 10}]
        )
      end

      it "returns true" do
        expect(report.has_active_usage?).to be true
      end
    end

    # Edge case - no usage
    context "when no models have usage" do
      before do
        report.add_model_report(
          Class,
          [{setting: test_setting, usage_count: 0, total_count: 10}]
        )
      end

      it "returns false" do
        expect(report.has_active_usage?).to be false
      end
    end
  end

  describe "Report#to_s" do
    let(:report) { described_class::Report.new }
    let(:model_class) { instance_double(Class, name: "User") }

    # Happy path - deprecated settings with usage
    context "when deprecated settings are in use" do
      let(:setting) { instance_double(ModelSettings::Setting, name: :old_feature, options: {deprecated: "Use new_feature"}) }

      before do
        report.add_model_report(
          model_class,
          [{setting: setting, usage_count: 10, total_count: 100}]
        )
      end

      it "includes warning header and details" do
        output = report.to_s

        expect(output).to include("⚠️  Found deprecated settings in use")
          .and include("User (1 deprecated settings)")
          .and include("✗ old_feature")
          .and include("Reason: Use new_feature")
          .and include("Used in: 10 records (out of 100 total)")
      end
    end

    # Edge case - deprecation without message
    context "when deprecation message is boolean true" do
      let(:setting) { instance_double(ModelSettings::Setting, name: :old_feature, options: {deprecated: true}) }

      before do
        report.add_model_report(
          model_class,
          [{setting: setting, usage_count: 5, total_count: 50}]
        )
      end

      it "does not show 'Reason' line" do
        output = report.to_s

        expect(output).not_to include("Reason:")
      end
    end

    # Edge case - no deprecated settings in use
    # rubocop:disable RSpecGuide/ContextSetup
    context "when no deprecated settings in use" do
      # rubocop:enable RSpecGuide/ContextSetup
      # No model reports added - testing empty state

      it "returns success message" do
        expect(report.to_s).to eq("✓ No deprecated settings found in use")
      end
    end
  end

  describe "#count_usage (private)" do
    let(:model_class) do
      Class.new(ActiveRecord::Base) do
        self.table_name = "test_models"

        def self.name
          "UsageTestModel"
        end

        include ModelSettings::DSL

        setting :deprecated_bool, type: :column, deprecated: true, default: false
        setting :deprecated_string, type: :column, deprecated: true, default: ""
      end
    end

    before do
      ActiveRecord::Base.connection.create_table :test_models, force: true do |t|
        t.boolean :deprecated_bool
        t.string :deprecated_string, null: true
      end

      model_class.compile_settings!
    end

    after do
      ActiveRecord::Base.connection.drop_table :test_models, if_exists: true
    end

    # Happy path - Column adapter with real data
    context "with Column adapter" do
      let(:adapter_type) { :column }  # Characteristic marker

      context "with boolean column" do
        before do
          model_class.create!(deprecated_bool: true)
          model_class.create!(deprecated_bool: false)
        end

        it "counts only true values" do
          setting = model_class.find_setting(:deprecated_bool)
          count = auditor.send(:count_usage, model_class, setting)

          expect(count).to eq(1)
        end
      end

      context "with non-boolean column" do
        before do
          ActiveRecord::Base.connection.execute("INSERT INTO test_models (deprecated_string) VALUES ('value')")
          ActiveRecord::Base.connection.execute("INSERT INTO test_models (deprecated_string) VALUES (NULL)")
        end

        it "counts only non-NULL values" do
          setting = model_class.find_setting(:deprecated_string)
          count = auditor.send(:count_usage, model_class, setting)

          expect(count).to eq(1)
        end
      end
    end

    # Error case - unknown adapter type
    context "when type is unknown" do
      let(:setting) do
        instance_double(
          ModelSettings::Setting,
          name: :unknown,
          storage: {},
          type: :unknown_type
        )
      end

      it "returns 0" do
        count = auditor.send(:count_usage, model_class, setting)

        expect(count).to eq(0)
      end
    end

    # Error case - count operation fails
    context "when count_usage raises error" do
      let(:setting) do
        instance_double(
          ModelSettings::Setting,
          name: :nonexistent_column,
          storage: {},
          type: :column
        )
      end

      it "returns 0 without raising" do
        count = auditor.send(:count_usage, model_class, setting)

        expect(count).to eq(0)
      end
    end
  end

  describe "#find_models_with_settings (private)" do
    # rubocop:disable RSpecGuide/ContextSetup
    context "when Rails is defined" do
      # rubocop:enable RSpecGuide/ContextSetup
      # Rails constant is defined by default in test environment

      it "returns models that include ModelSettings::DSL" do
        models = auditor.send(:find_models_with_settings)

        expect(models).to all(respond_to(:settings))
      end
    end

    # rubocop:disable RSpecGuide/ContextSetup
    context "but when Rails is not defined" do
      # rubocop:enable RSpecGuide/ContextSetup
      around do |example|
        # Temporarily remove Rails constant
        rails_const = Object.send(:remove_const, :Rails) if defined?(Rails)

        example.run

        # Restore Rails constant
        Object.const_set(:Rails, rails_const) if rails_const
      end

      it "returns empty array" do
        models = auditor.send(:find_models_with_settings)

        expect(models).to eq([])
      end
    end
  end

  describe "#count_json_usage (private)" do
    let(:json_model_class) do
      Class.new(ActiveRecord::Base) do
        self.table_name = "json_test_models"

        def self.name
          "JsonUsageModel"
        end

        include ModelSettings::DSL

        setting :deprecated_json, type: :json, storage: {column: :settings_data}, deprecated: true
      end
    end

    before do
      ActiveRecord::Base.connection.create_table :json_test_models, force: true do |t|
        t.json :settings_data
      end

      json_model_class.compile_settings!
    end

    after do
      ActiveRecord::Base.connection.drop_table :json_test_models, if_exists: true
    end

    context "when column exists with JSON data" do
      before do
        # Create records with JSON data using raw SQL to bypass validations
        ActiveRecord::Base.connection.execute(
          "INSERT INTO json_test_models (settings_data) VALUES ('{\"deprecated_json\": \"value1\"}')"
        )
        ActiveRecord::Base.connection.execute(
          "INSERT INTO json_test_models (settings_data) VALUES ('{\"deprecated_json\": \"value2\"}')"
        )
        ActiveRecord::Base.connection.execute(
          "INSERT INTO json_test_models (settings_data) VALUES ('{}')"
        )
      end

      it "counts records with the JSON key" do
        setting = json_model_class.find_setting(:deprecated_json)
        count = auditor.send(:count_json_usage, json_model_class, setting)

        expect(count).to eq(2)
      end
    end

    context "but when column does not exist" do
      let(:invalid_setting) do
        instance_double(
          ModelSettings::Setting,
          name: :test,
          storage: {column: :nonexistent_column},
          type: :json
        )
      end

      it "returns 0" do
        count = auditor.send(:count_json_usage, json_model_class, invalid_setting)

        expect(count).to eq(0)
      end
    end

    context "and when query fails" do
      let(:failing_setting) do
        setting = json_model_class.find_setting(:deprecated_json)
        allow(json_model_class).to receive(:where).and_raise(StandardError.new("DB error"))
        setting
      end

      it "returns 0 without raising" do
        count = auditor.send(:count_json_usage, json_model_class, failing_setting)

        expect(count).to eq(0)
      end
    end
  end

  describe "#count_store_model_usage (private)" do
    let(:store_model_class) do
      Class.new(ActiveRecord::Base) do
        self.table_name = "store_test_models"

        def self.name
          "StoreUsageModel"
        end

        include ModelSettings::DSL

        setting :deprecated_store, type: :store_model, storage: {column: :config_data}, deprecated: true
      end
    end

    before do
      ActiveRecord::Base.connection.create_table :store_test_models, force: true do |t|
        t.json :config_data
      end

      store_model_class.compile_settings!
    end

    after do
      ActiveRecord::Base.connection.drop_table :store_test_models, if_exists: true
    end

    context "when column has data" do
      before do
        # Create records with data in the column
        ActiveRecord::Base.connection.execute(
          "INSERT INTO store_test_models (config_data) VALUES ('{\"key\": \"value\"}')"
        )
        ActiveRecord::Base.connection.execute(
          "INSERT INTO store_test_models (config_data) VALUES (NULL)"
        )
      end

      it "counts records where column is not null" do
        setting = store_model_class.find_setting(:deprecated_store)
        count = auditor.send(:count_store_model_usage, store_model_class, setting)

        expect(count).to eq(1)
      end
    end

    context "but when query fails" do
      let(:failing_setting) do
        setting = store_model_class.find_setting(:deprecated_store)
        allow(store_model_class).to receive(:where).and_raise(StandardError.new("DB error"))
        setting
      end

      it "returns 0 without raising" do
        count = auditor.send(:count_store_model_usage, store_model_class, failing_setting)

        expect(count).to eq(0)
      end
    end
  end
end
