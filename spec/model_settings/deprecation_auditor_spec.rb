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
    context "when deprecated settings exist but are not used" do
      let(:records_count) { 0 }  # Explicit "no records" marker

      before { records_count.times { model_class.create! } }

      it "returns report with zero usage", :aggregate_failures do
        report = auditor.generate_report

        expect(report).to have_attributes(
          has_active_usage?: false
        )
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
    context "when no deprecated settings in use" do
      let(:model_reports) { [] }  # Explicit "empty reports" marker

      before { model_reports.each { |mr| report.add_model_report(*mr) } }

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
end
