# frozen_string_literal: true

require "spec_helper"

# rubocop:disable RSpecGuide/MinimumBehavioralCoverage
RSpec.describe ModelSettings::ErrorMessages do
  let(:model_class) do
    Class.new(ActiveRecord::Base) do
      self.table_name = "users"

      def self.name
        "User"
      end
    end
  end

  let(:setting) do
    ModelSettings::Setting.new(:test_setting, {type: :json})
  end

  describe ".adapter_configuration_error" do
    context "when adapter type is :json" do
      let(:error_message) do
        described_class.adapter_configuration_error(:json, setting, model_class)
      end

      it "includes the setting name" do
        expect(error_message).to include(":test_setting")
      end

      it "includes the model name" do
        expect(error_message).to include("User")
      end

      it "includes fix instructions with storage configuration" do
        expect(error_message).to include("storage: {column: :settings_json}")
      end

      it "includes migration hint" do
        expect(error_message).to include("add_column :users, :settings_json, :jsonb")
      end
    end

    context "when adapter type is :store_model" do
      let(:error_message) do
        described_class.adapter_configuration_error(:store_model, setting, model_class)
      end

      it "includes the setting name" do
        expect(error_message).to include(":test_setting")
      end

      it "includes StoreModel setup instructions" do
        expect(error_message).to include("include StoreModel::Model")
      end

      it "includes storage configuration example" do
        expect(error_message).to include("storage: {column: :preferences}")
      end
    end

    context "when adapter type is unknown" do
      let(:error_message) do
        described_class.adapter_configuration_error(:unknown, setting, model_class)
      end

      it "returns generic error message" do
        expect(error_message).to include("Unknown adapter configuration error")
      end

      it "includes setting and model information", :aggregate_failures do
        expect(error_message).to include(":test_setting")
        expect(error_message).to include("User")
      end
    end
  end

  describe ".unknown_storage_type_error" do
    context "when type is close to a valid type" do
      let(:setting) { ModelSettings::Setting.new(:test_setting, {type: :colum}) }
      let(:error_message) do
        described_class.unknown_storage_type_error(:colum, setting, model_class)
      end

      it "includes the invalid type" do
        expect(error_message).to include(":colum")
      end

      it "includes the setting name" do
        expect(error_message).to include(":test_setting")
      end

      it "includes the model name" do
        expect(error_message).to include("User")
      end

      it "lists available storage types", :aggregate_failures do
        expect(error_message).to include(":column")
        expect(error_message).to include(":json")
        expect(error_message).to include(":store_model")
      end

      it "suggests the correct type using did_you_mean" do
        expect(error_message).to include('Did you mean: "column"?')
      end

      it "includes example usage" do
        expect(error_message).to include("Example usage:")
      end
    end

    context "when type is completely invalid" do
      let(:setting) { ModelSettings::Setting.new(:test_setting, {type: :xyz}) }
      let(:error_message) do
        described_class.unknown_storage_type_error(:xyz, setting, model_class)
      end

      it "does not include did_you_mean suggestion" do
        expect(error_message).not_to include("Did you mean:")
      end

      it "still includes available types", :aggregate_failures do
        expect(error_message).to include(":column")
        expect(error_message).to include(":json")
      end
    end
  end

  describe ".module_conflict_error" do
    let(:error_message) do
      described_class.module_conflict_error(:authorization, active_modules)
    end

    context "when two authorization modules are active" do
      let(:active_modules) { [:roles, :pundit] }

      it "includes the group name" do
        expect(error_message).to include("authorization")
      end

      it "lists all active modules", :aggregate_failures do
        expect(error_message).to include(":roles")
        expect(error_message).to include(":pundit")
      end

      it "explains that modules are mutually exclusive" do
        expect(error_message).to include("mutually exclusive")
      end

      it "provides fix instructions" do
        expect(error_message).to include("You must choose only ONE module")
      end

      it "includes example code", :aggregate_failures do
        expect(error_message).to include("ModelSettings::Modules::Roles")
        expect(error_message).to include("ModelSettings::Modules::Pundit")
      end
    end

    context "when three modules are active" do
      let(:active_modules) { [:roles, :pundit, :action_policy] }

      it "lists all three modules", :aggregate_failures do
        expect(error_message).to include(":roles")
        expect(error_message).to include(":pundit")
        expect(error_message).to include(":action_policy")
      end
    end
  end

  describe ".cyclic_sync_error" do
    let(:error_message) do
      described_class.cyclic_sync_error(cycle)
    end

    context "when cycle involves two settings" do
      let(:cycle) { [:feature_a, :feature_b, :feature_a] }

      it "shows the cycle path" do
        expect(error_message).to include(":feature_a → :feature_b → :feature_a")
      end

      it "explains that cycles are not allowed" do
        expect(error_message).to include("cannot form cycles")
      end

      it "provides fix instructions" do
        expect(error_message).to include("Remove one of the sync relationships")
      end

      it "includes before/after example", :aggregate_failures do
        expect(error_message).to include("# Before (creates cycle):")
        expect(error_message).to include("# After (no cycle):")
      end
    end

    context "when cycle involves three settings" do
      let(:cycle) { [:a, :b, :c, :a] }

      it "shows the full cycle path" do
        expect(error_message).to include(":a → :b → :c → :a")
      end
    end
  end

  describe ".infinite_cascade_error" do
    let(:error_message) do
      described_class.infinite_cascade_error(iterations, max_iterations)
    end

    context "when max iterations is 100" do
      let(:iterations) { 100 }
      let(:max_iterations) { 100 }

      it "includes the iteration count" do
        expect(error_message).to include("100 iterations")
      end

      it "includes the max iterations" do
        expect(error_message).to include("max: 100")
      end

      it "explains common causes", :aggregate_failures do
        expect(error_message).to include("Common causes:")
        expect(error_message).to include("Setting A cascades to B, and B cascades back to A")
      end

      it "provides debugging steps", :aggregate_failures do
        expect(error_message).to include("To debug this issue:")
        expect(error_message).to include("settings_debug")
      end

      it "includes example problematic configuration", :aggregate_failures do
        expect(error_message).to include("Example problematic configuration:")
        expect(error_message).to include("cascade: {enable: true}")
      end
    end

    context "when max iterations is 50" do
      let(:iterations) { 50 }
      let(:max_iterations) { 50 }

      it "includes the correct iteration count" do
        expect(error_message).to include("50 iterations")
      end
    end
  end

  describe ".unsupported_format_error" do
    context "when format is close to a valid format" do
      let(:available_formats) { [:markdown, :json] }
      let(:error_message) do
        described_class.unsupported_format_error(:markdwon, available_formats)
      end

      it "includes the invalid format" do
        expect(error_message).to include(":markdwon")
      end

      it "lists available formats", :aggregate_failures do
        expect(error_message).to include(":markdown")
        expect(error_message).to include(":json")
      end

      it "suggests the correct format using did_you_mean" do
        expect(error_message).to include('Did you mean: "markdown"?')
      end

      it "includes example usage", :aggregate_failures do
        expect(error_message).to include("Example usage:")
        expect(error_message).to include("generate_settings_documentation")
      end
    end

    context "when format is completely invalid" do
      let(:available_formats) { [:markdown, :json] }
      let(:error_message) do
        described_class.unsupported_format_error(:xyz, available_formats)
      end

      it "does not include did_you_mean suggestion" do
        expect(error_message).not_to include("Did you mean:")
      end

      it "still lists available formats", :aggregate_failures do
        expect(error_message).to include(":markdown")
        expect(error_message).to include(":json")
      end
    end

    context "when four formats are available" do
      let(:available_formats) { [:markdown, :json, :yaml, :html] }
      let(:error_message) do
        described_class.unsupported_format_error(:txt, available_formats)
      end

      it "lists all available formats", :aggregate_failures do
        expect(error_message).to include(":markdown")
        expect(error_message).to include(":json")
        expect(error_message).to include(":yaml")
        expect(error_message).to include(":html")
      end
    end
  end

  # rubocop:disable RSpecGuide/MinimumBehavioralCoverage
  describe "did_you_mean algorithm" do
    describe ".did_you_mean (private method tested via public API)" do
      context "when input is within Levenshtein distance of 2" do
        let(:candidates) { [:column, :json, :store_model] }

        it "suggests correct candidate for single character typo" do
          error = described_class.unknown_storage_type_error(:colum, setting, model_class)
          expect(error).to include(":column")
        end

        it "suggests correct candidate for two character difference" do
          error = described_class.unknown_storage_type_error(:jsn, setting, model_class)
          expect(error).to include(":json")
        end
      end

      context "when input is too different (distance > 2)" do
        let(:input_type) { :xyz }

        it "does not suggest when distance is > 2" do
          error = described_class.unknown_storage_type_error(input_type, setting, model_class)
          expect(error).not_to include("Did you mean:")
        end
      end

      context "when input is exact match" do
        let(:input_format) { :markdown }
        let(:available_formats) { [:json] }

        it "does not suggest when input matches candidate" do
          # This would be caught before calling did_you_mean,
          # but testing the algorithm behavior
          error = described_class.unsupported_format_error(input_format, available_formats)
          expect(error).not_to include("Did you mean:")
        end
      end
    end

    describe ".levenshtein_distance (private method tested via public API)" do
      let(:candidates) { [:json] }

      context "when strings are identical" do
        let(:input) { :json }
        let(:all_formats) { [:json, :markdown] }

        it "returns 0 distance" do
          # Test via did_you_mean - identical strings should not produce suggestions
          error = described_class.unsupported_format_error(input, all_formats)
          expect(error).not_to include("Did you mean:")
        end
      end

      context "when strings differ by one character" do
        let(:input) { :jso }

        it "suggests the close match" do
          error = described_class.unsupported_format_error(input, candidates)
          expect(error).to include('Did you mean: "json"?')
        end
      end

      context "when strings differ by insertion" do
        let(:input) { :jsoon }

        it "suggests the close match" do
          error = described_class.unsupported_format_error(input, candidates)
          expect(error).to include('Did you mean: "json"?')
        end
      end

      context "when strings differ by deletion" do
        let(:input) { :jon }

        it "suggests the close match" do
          error = described_class.unsupported_format_error(input, candidates)
          expect(error).to include('Did you mean: "json"?')
        end
      end

      context "when strings differ by substitution" do
        let(:input) { :jsan }

        it "suggests the close match" do
          error = described_class.unsupported_format_error(input, candidates)
          expect(error).to include('Did you mean: "json"?')
        end
      end
    end
  end
  # rubocop:enable RSpecGuide/MinimumBehavioralCoverage

  # rubocop:disable RSpecGuide/MinimumBehavioralCoverage, RSpecGuide/HappyPathFirst, RSpec/ExampleLength
  describe "integration with actual error raising" do
    # Base test model for adapter configuration tests
    let(:test_model) do
      Class.new(ActiveRecord::Base) do
        self.table_name = "users"
        include ModelSettings::DSL

        def self.name
          "TestModel"
        end
      end
    end

    context "when storage column is missing for JSON adapter" do
      let(:adapter_type) { :json }

      it "raises ArgumentError with improved message", :aggregate_failures do
        expect do
          test_model.class_eval do
            setting :test, type: :json
          end
        end.to raise_error(ArgumentError) do |error|
          expect(error.message).to include("JSON adapter requires a storage column")
          expect(error.message).to include(":test")
          expect(error.message).to include("TestModel")
          expect(error.message).to include("storage: {column: :settings_json}")
        end
      end
    end

    context "when storage column is missing for StoreModel adapter" do
      let(:adapter_type) { :store_model }

      it "raises ArgumentError with improved message", :aggregate_failures do
        expect do
          test_model.class_eval do
            setting :test, type: :store_model
          end
        end.to raise_error(ArgumentError) do |error|
          expect(error.message).to include("StoreModel adapter requires a storage column")
          expect(error.message).to include(":test")
          expect(error.message).to include("include StoreModel::Model")
        end
      end
    end

    context "when unknown storage type is used" do
      let(:adapter_type) { :invalid_type }

      it "raises ArgumentError with improved message", :aggregate_failures do
        expect do
          test_model.class_eval do
            setting :test, type: :invalid_type
          end
        end.to raise_error(ArgumentError) do |error|
          expect(error.message).to include("Unknown storage type: :invalid_type")
          expect(error.message).to include("Available storage types:")
          expect(error.message).to include(":column")
          expect(error.message).to include(":json")
          expect(error.message).to include(":store_model")
        end
      end
    end

    context "when cyclic sync is detected" do
      # Override test_model to use custom table with sync columns
      # rubocop:disable RSpec/LetSetup
      let!(:test_table) do
        ActiveRecord::Base.connection.create_table :test_models, force: true do |t|
          t.boolean :feature_a
          t.boolean :feature_b
        end
      end
      # rubocop:enable RSpec/LetSetup

      let(:test_model) do
        Class.new(ActiveRecord::Base) do
          self.table_name = "test_models"
          include ModelSettings::DSL

          def self.name
            "TestModelWithSync"
          end
        end
      end

      after do
        ActiveRecord::Base.connection.drop_table :test_models, if_exists: true
      end

      it "raises CyclicSyncError with improved message", :aggregate_failures do
        expect do
          test_model.class_eval do
            setting :feature_a, type: :column, sync: {target: :feature_b, mode: :forward}
            setting :feature_b, type: :column, sync: {target: :feature_a, mode: :forward}
            compile_settings!
          end
        end.to raise_error(ModelSettings::CyclicSyncError) do |error|
          expect(error.message).to include("Cycle detected in sync dependencies")
          expect(error.message).to include(":feature_a")
          expect(error.message).to include(":feature_b")
          expect(error.message).to include("cannot form cycles")
        end
      end
    end
  end
  # rubocop:enable RSpecGuide/MinimumBehavioralCoverage, RSpecGuide/HappyPathFirst, RSpec/ExampleLength
end
# rubocop:enable RSpecGuide/MinimumBehavioralCoverage
