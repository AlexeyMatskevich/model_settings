# frozen_string_literal: true

module ModelSettings
  module Validators
    # Validates that an attribute value is an Array type
    #
    # Used for JSON array membership pattern to ensure the column
    # storing the array is actually an array and not a different type.
    #
    # @example
    #   validates :preferences, array_type: true
    #
    #   model.preferences = []           # Valid
    #   model.preferences = ["a", "b"]   # Valid
    #   model.preferences = nil          # Valid (allows nil)
    #   model.preferences = "not_array"  # Invalid
    #   model.preferences = {}           # Invalid
    class ArrayTypeValidator < ActiveModel::EachValidator
      # Validates that the attribute value is an Array
      #
      # @param record [ActiveRecord::Base] The model instance being validated
      # @param attribute [Symbol] The attribute name being validated
      # @param value [Object] The attribute value
      def validate_each(record, attribute, value)
        return if value.nil?  # Allow nil values
        return if value.is_a?(Array)

        record.errors.add(attribute, :array_type, message: "must be an array")
      end
    end
  end
end

# Register with ActiveModel for validates :attr, array_type: true syntax
ActiveModel::Validations::ArrayTypeValidator = ModelSettings::Validators::ArrayTypeValidator
