# frozen_string_literal: true

require "spec_helper"
require "stringio"

# rubocop:disable RSpecGuide/MinimumBehavioralCoverage
RSpec.describe ModelSettings::DeprecatedSettingsLister do
  let(:lister) { described_class.new }
  # rubocop:enable RSpecGuide/MinimumBehavioralCoverage

  def capture_stdout
    old_stdout = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = old_stdout
  end

  describe "#print_list" do
    let(:model_class) do
      Class.new(ActiveRecord::Base) do
        self.table_name = "test_models"

        def self.name
          "ListerTestModel"
        end

        include ModelSettings::DSL

        setting :active_feature, type: :column, default: false
        setting :deprecated_feature,
          type: :column,
          default: false,
          deprecated: "Use active_feature instead",
          deprecated_since: "2.0.0"
      end
    end

    before do
      ActiveRecord::Base.connection.create_table :test_models, force: true do |t|
        t.boolean :active_feature
        t.boolean :deprecated_feature
      end

      model_class.compile_settings!
    end

    after do
      ActiveRecord::Base.connection.drop_table :test_models, if_exists: true
    end

    # Happy path - deprecated settings exist with full details
    context "when deprecated settings exist" do
      before do
        allow(lister).to receive(:find_models_with_settings).and_return([model_class])
      end

      it "lists all details" do
        output = capture_stdout { lister.print_list }

        expect(output).to include("Deprecated Settings Report")
          .and include("ListerTestModel:")
          .and include("deprecated_feature")
          .and include("Message: Use active_feature instead")
          .and include("Since: 2.0.0")
          .and include("Found 1 deprecated setting")
      end
    end

    # Edge case - deprecation without message string
    context "when deprecated message is boolean true" do
      let(:model_with_bool_deprecated) do
        Class.new(ActiveRecord::Base) do
          self.table_name = "test_models"

          def self.name
            "BoolDeprecatedModel"
          end

          include ModelSettings::DSL

          setting :old_feature, type: :column, deprecated: true
        end
      end

      before do
        allow(lister).to receive(:find_models_with_settings).and_return([model_with_bool_deprecated])
      end

      it "shows '(no message)' placeholder" do
        expect { lister.print_list }.to output(/Message: \(no message\)/).to_stdout
      end
    end

    # Edge case - no deprecated settings
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
        allow(lister).to receive(:find_models_with_settings).and_return([model_without_deprecated])
      end

      it "prints success message" do
        expect { lister.print_list }.to output(/✓ No deprecated settings found/).to_stdout
      end
    end
  end

  describe "#grouped_deprecated_settings" do
    let(:model_class) do
      Class.new(ActiveRecord::Base) do
        self.table_name = "test_models"

        def self.name
          "GroupTestModel"
        end

        include ModelSettings::DSL

        setting :normal_setting, type: :column, default: false
        setting :deprecated_one, type: :column, deprecated: true
        setting :deprecated_two, type: :column, deprecated: "Old feature"
      end
    end

    before do
      ActiveRecord::Base.connection.create_table :test_models, force: true do |t|
        t.boolean :normal_setting
        t.boolean :deprecated_one
        t.boolean :deprecated_two
      end

      model_class.compile_settings!
    end

    after do
      ActiveRecord::Base.connection.drop_table :test_models, if_exists: true
    end

    # Happy path - model with deprecated settings
    context "when model has deprecated settings" do
      before do
        allow(lister).to receive(:find_models_with_settings).and_return([model_class])
      end

      it "returns hash grouped by model class" do
        result = lister.grouped_deprecated_settings

        expect(result).to match(
          model_class => all(have_attributes(
            name: be_in([:deprecated_one, :deprecated_two])
          ))
        )
      end
    end

    # Edge case - model without deprecated settings
    context "when model has no deprecated settings" do
      let(:clean_model) do
        Class.new(ActiveRecord::Base) do
          self.table_name = "test_models"

          def self.name
            "CleanModel"
          end

          include ModelSettings::DSL

          setting :normal, type: :column
        end
      end

      before do
        allow(lister).to receive(:find_models_with_settings).and_return([clean_model])
      end

      it "does not include model in result" do
        result = lister.grouped_deprecated_settings

        expect(result).to be_empty
      end
    end
  end

  # rubocop:disable RSpecGuide/MinimumBehavioralCoverage
  describe "#find_models_with_settings (private)" do
    # Happy path tested implicitly in #print_list and #grouped_deprecated_settings
    # Edge case - Rails not available
    context "when Rails is not defined" do
      before { hide_const("Rails") }

      it "returns empty array" do
        result = lister.send(:find_models_with_settings)

        expect(result).to eq([])
      end
    end
  end
  # rubocop:enable RSpecGuide/MinimumBehavioralCoverage
end
