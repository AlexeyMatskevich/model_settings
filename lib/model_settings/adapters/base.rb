# frozen_string_literal: true

module ModelSettings
  module Adapters
    # Base adapter interface for storage backends
    #
    # All storage adapters must implement these methods to provide
    # a consistent interface for reading, writing, and tracking changes
    # to settings values.
    class Base
      attr_reader :model_class, :setting

      def initialize(model_class, setting)
        @model_class = model_class
        @setting = setting
      end

      # Setup the adapter for this setting
      # Called once during setting definition
      # Should define accessors, helper methods, etc.
      #
      # @return [void]
      def setup!
        raise NotImplementedError, "#{self.class} must implement #setup!"
      end

      # Read the setting value from an instance
      #
      # @param instance [ActiveRecord::Base] Model instance
      # @return [Object] The setting value
      def read(instance)
        raise NotImplementedError, "#{self.class} must implement #read"
      end

      # Write the setting value to an instance
      #
      # @param instance [ActiveRecord::Base] Model instance
      # @param value [Object] The value to write
      # @return [Object] The written value
      def write(instance, value)
        raise NotImplementedError, "#{self.class} must implement #write"
      end

      # Check if the setting has changed on this instance
      #
      # @param instance [ActiveRecord::Base] Model instance
      # @return [Boolean] true if changed
      def changed?(instance)
        raise NotImplementedError, "#{self.class} must implement #changed?"
      end

      # Get the previous value before change
      #
      # @param instance [ActiveRecord::Base] Model instance
      # @return [Object, nil] Previous value or nil
      def was(instance)
        raise NotImplementedError, "#{self.class} must implement #was"
      end

      # Get the change as [old_value, new_value]
      #
      # @param instance [ActiveRecord::Base] Model instance
      # @return [Array, nil] [old, new] or nil if not changed
      def change(instance)
        raise NotImplementedError, "#{self.class} must implement #change"
      end
    end
  end
end
