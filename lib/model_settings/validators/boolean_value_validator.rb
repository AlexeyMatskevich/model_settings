# frozen_string_literal: true

module ModelSettings
  module Validators
    # Custom validator to ensure setting values are strictly boolean (true or false)
    #
    # Rails' default boolean type casting is too permissive - it converts
    # strings like "1", "true", "yes" to true. ModelSettings requires
    # strict boolean values only.
    #
    # Usage:
    #   validates :setting_name, boolean_value: true
    #
    # This validator ensures that:
    # - Value must be exactly true or false
    # - No type coercion (strings, integers are rejected)
    # - nil values are allowed (settings don't have to be required)
    # - Works with all storage adapters (column, json, store_model)
    class BooleanValueValidator < ActiveModel::EachValidator
      def validate_each(record, attribute, value)
        # Allow nil values (settings are not required by default)
        return if value.nil?

        raw_value = nil

        # Try to get value before type casting
        # 1. Try attribute-specific method first (for StoreModel delegated attributes)
        if record.respond_to?("#{attribute}_before_type_cast")
          raw_value = record.public_send("#{attribute}_before_type_cast")
        end

        # 2. Fall back to ActiveRecord's read_attribute_before_type_cast if we didn't get a value
        if raw_value.nil? && record.respond_to?(:read_attribute_before_type_cast)
          raw_value = record.read_attribute_before_type_cast(attribute)
        end

        # If we got a raw value and it's different from processed value,
        # validate the raw value (type casting happened)
        if raw_value && raw_value != value
          # Check if raw value is valid boolean
          unless raw_value == true || raw_value == false
            record.errors.add(
              attribute,
              :invalid_boolean,
              message: options[:message] || "must be true or false (got: #{raw_value.inspect})"
            )
            return
          end
        end

        # Validate the processed value (no type casting occurred, or for JSON adapter)
        return if value == true || value == false

        record.errors.add(
          attribute,
          :invalid_boolean,
          message: options[:message] || "must be true or false (got: #{value.inspect})"
        )
      end
    end
  end
end

# Register the validator so it can be used as `validates :attr, boolean_value: true`
ActiveModel::Validations::BooleanValueValidator = ModelSettings::Validators::BooleanValueValidator
