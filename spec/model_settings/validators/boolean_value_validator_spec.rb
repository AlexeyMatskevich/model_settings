# frozen_string_literal: true

require "spec_helper"

RSpec.describe ModelSettings::Validators::BooleanValueValidator do
  # Test model for validator testing
  let(:test_model_class) do
    Class.new(ActiveRecord::Base) do
      self.table_name = "test_models"

      def self.name
        "BooleanValidatorTestModel"
      end

      # Standard ActiveRecord boolean column
      validates :enabled, boolean_value: true
    end
  end

  let(:test_model) { test_model_class.new }

  describe "valid boolean values" do
    context "when value is true" do
      it "accepts true" do
        test_model.enabled = true
        expect(test_model).to be_valid
      end
    end

    context "when value is false" do
      it "accepts false" do
        test_model.enabled = false
        expect(test_model).to be_valid
      end
    end

    context "but when value is nil" do
      it "accepts nil (for optional settings)" do
        test_model.enabled = nil
        expect(test_model).to be_valid
      end
    end
  end

  describe "invalid primitive values" do
    describe "string values" do
      context "when value is string '1'" do
        it "rejects string '1'" do
          test_model.enabled = "1"
          expect(test_model).not_to be_valid
          expect(test_model.errors[:enabled]).to be_present
        end
      end

      context "when value is string 'true'" do
        it "rejects string 'true'" do
          test_model.enabled = "true"
          expect(test_model).not_to be_valid
          expect(test_model.errors[:enabled]).to be_present
        end
      end

      context "when value is string 'false'" do
        it "rejects string 'false'" do
          test_model.enabled = "false"
          expect(test_model).not_to be_valid
          expect(test_model.errors[:enabled]).to be_present
        end
      end

      context "when value is string 'yes'" do
        it "rejects string 'yes'" do
          test_model.enabled = "yes"
          expect(test_model).not_to be_valid
          expect(test_model.errors[:enabled]).to be_present
        end
      end
    end

    describe "integer values" do
      context "when value is integer 0" do
        it "rejects integer 0" do
          test_model.enabled = 0
          expect(test_model).not_to be_valid
          expect(test_model.errors[:enabled]).to be_present
        end
      end

      context "when value is integer 1" do
        it "rejects integer 1" do
          test_model.enabled = 1
          expect(test_model).not_to be_valid
          expect(test_model.errors[:enabled]).to be_present
        end
      end
    end
  end

  describe "invalid complex values" do
    context "when value is empty array" do
      it "rejects empty array []" do
        test_model.enabled = []
        expect(test_model).not_to be_valid
        expect(test_model.errors[:enabled]).to be_present
      end
    end

    context "when value is empty hash" do
      it "rejects empty hash {}" do
        test_model.enabled = {}
        expect(test_model).not_to be_valid
        expect(test_model.errors[:enabled]).to be_present
      end
    end

    # Note: Empty string "" is converted to nil by Rails for boolean columns,
    # so it's not tested here. The validator correctly accepts nil.
  end

  describe "type casting detection" do
    # Rails automatically type-casts certain values to boolean (e.g., "1" → true).
    # BooleanValueValidator must detect this and reject the original value.

    context "when type casting occurs" do
      it "detects type casting from string '1' and rejects" do
        # ActiveRecord will convert "1" to true, but validator should catch the raw value
        test_model.enabled = "1"
        expect(test_model).not_to be_valid
        expect(test_model.errors[:enabled]).to be_present
      end

      it "detects type casting from string 't' and rejects" do
        test_model.enabled = "t"
        expect(test_model).not_to be_valid
        expect(test_model.errors[:enabled]).to be_present
      end

      it "detects type casting from string 'f' and rejects" do
        test_model.enabled = "f"
        expect(test_model).not_to be_valid
        expect(test_model.errors[:enabled]).to be_present
      end
    end
  end

  describe "error messages" do
    context "with default message" do
      it "provides helpful error message" do
        test_model.enabled = "invalid"
        test_model.valid?
        expect(test_model.errors[:enabled].first).to match(/must be true or false/)
      end

      it "shows actual invalid value in error" do
        test_model.enabled = "invalid"
        test_model.valid?
        expect(test_model.errors[:enabled].first).to include('"invalid"')
      end
    end

    context "but with custom message" do
      it "uses custom message if provided" do
        custom_model_class = Class.new(ActiveRecord::Base) do
          self.table_name = "test_models"

          def self.name
            "CustomMessageModel"
          end

          validates :enabled, boolean_value: {message: "Custom error message"}
        end

        model = custom_model_class.new
        model.enabled = "invalid"
        model.valid?
        expect(model.errors[:enabled].first).to eq("Custom error message")
      end
    end
  end
end
