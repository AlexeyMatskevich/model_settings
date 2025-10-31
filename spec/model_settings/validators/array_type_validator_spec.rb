# frozen_string_literal: true

require "spec_helper"

# rubocop:disable RSpecGuide/MinimumBehavioralCoverage
RSpec.describe ModelSettings::Validators::ArrayTypeValidator do
  let(:model_class) do
    Class.new do
      include ActiveModel::Validations

      attr_accessor :preferences

      validates :preferences, array_type: true

      def self.name
        "TestModel"
      end
    end
  end

  let(:instance) { model_class.new }

  describe "#validate_each" do
    subject(:validation) { instance.valid? }

    # Happy path first: arrays are valid
    # rubocop:disable RSpecGuide/ContextSetup
    context "when value is an array" do
      # rubocop:enable RSpecGuide/ContextSetup
      context "and array is empty" do
        before { instance.preferences = [] }

        it "passes validation" do
          expect(validation).to be true
        end

        it "adds no errors" do
          validation
          expect(instance.errors[:preferences]).to be_empty
        end
      end

      context "and array contains strings" do
        before { instance.preferences = ["feature_a", "feature_b"] }

        it "passes validation" do
          expect(validation).to be true
        end

        it "adds no errors" do
          validation
          expect(instance.errors[:preferences]).to be_empty
        end
      end

      context "and array contains mixed types" do
        before { instance.preferences = ["string", 123, true, nil] }

        it "passes validation" do
          expect(validation).to be true
        end

        it "adds no errors" do
          validation
          expect(instance.errors[:preferences]).to be_empty
        end
      end
    end

    # Special case: nil is allowed
    context "when value is nil" do
      before { instance.preferences = nil }

      it "passes validation" do
        expect(validation).to be true
      end

      it "adds no errors" do
        validation
        expect(instance.errors[:preferences]).to be_empty
      end
    end

    # Negative cases: non-arrays are invalid
    # rubocop:disable RSpecGuide/ContextSetup
    context "when value is NOT an array" do
      # rubocop:enable RSpecGuide/ContextSetup
      context "and value is a string" do
        before { instance.preferences = "not_an_array" }

        it "fails validation" do
          expect(validation).to be false
        end

        it "adds array type error message" do
          validation
          expect(instance.errors[:preferences]).to include("must be an array")
        end
      end

      context "and value is a hash" do
        before { instance.preferences = {key: "value"} }

        it "fails validation" do
          expect(validation).to be false
        end

        it "adds array type error message" do
          validation
          expect(instance.errors[:preferences]).to include("must be an array")
        end
      end

      context "and value is an integer" do
        before { instance.preferences = 123 }

        it "fails validation" do
          expect(validation).to be false
        end

        it "adds array type error message" do
          validation
          expect(instance.errors[:preferences]).to include("must be an array")
        end
      end

      context "and value is a boolean" do
        before { instance.preferences = true }

        it "fails validation" do
          expect(validation).to be false
        end

        it "adds array type error message" do
          validation
          expect(instance.errors[:preferences]).to include("must be an array")
        end
      end

      context "and value is an object" do
        before { instance.preferences = Object.new }

        it "fails validation" do
          expect(validation).to be false
        end

        it "adds array type error message" do
          validation
          expect(instance.errors[:preferences]).to include("must be an array")
        end
      end
    end
  end

  # rubocop:disable RSpecGuide/MinimumBehavioralCoverage
  describe "ActiveModel integration" do
    # rubocop:enable RSpecGuide/MinimumBehavioralCoverage
    it "is registered as ActiveModel validator" do
      expect(ActiveModel::Validations::ArrayTypeValidator).to eq(described_class)
    end

    it "works with validates syntax" do
      expect { model_class.new }.not_to raise_error
    end
  end
end
