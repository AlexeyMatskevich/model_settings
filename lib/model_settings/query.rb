# frozen_string_literal: true

module ModelSettings
  # Query methods for finding settings by metadata
  #
  # Provides powerful query interface for finding settings based on
  # metadata keys, values, and other criteria.
  #
  # Usage:
  #   User.settings_where(metadata: {category: "security"})
  #   User.settings_with_metadata_key(:plan_requirement)
  #   User.settings_by_type(:json)
  #
  module Query
    extend ActiveSupport::Concern

    module ClassMethods
      # Find settings by metadata key/value pairs
      #
      # @param metadata [Hash] Metadata key/value pairs to match
      # @return [Array<Setting>] Matching settings
      #
      # @example
      #   User.settings_where(metadata: {category: "security", tier: "premium"})
      #
      def settings_where(metadata: {})
        all_settings_recursive.select do |setting|
          metadata.all? do |key, value|
            setting.metadata[key] == value
          end
        end
      end

      # Find settings that have a specific metadata key
      #
      # @param key [Symbol] Metadata key
      # @return [Array<Setting>] Settings with the key
      #
      # @example
      #   User.settings_with_metadata_key(:plan_requirement)
      #
      def settings_with_metadata_key(key)
        all_settings_recursive.select do |setting|
          setting.metadata.key?(key)
        end
      end

      # Find settings by storage type
      #
      # @param type [Symbol] Storage type (:column, :json, :store_model)
      # @return [Array<Setting>] Settings of the type
      #
      # @example
      #   User.settings_by_type(:json)
      #
      def settings_by_type(type)
        all_settings_recursive.select do |setting|
          setting.type == type
        end
      end

      # Find settings with callbacks defined
      #
      # @param callback_type [Symbol, nil] Specific callback type or nil for any
      # @return [Array<Setting>] Settings with callbacks
      #
      # @example
      #   User.settings_with_callbacks(:after_enable)
      #   User.settings_with_callbacks # Any callback
      #
      def settings_with_callbacks(callback_type = nil)
        all_settings_recursive.select do |setting|
          if callback_type
            setting.options.key?(callback_type)
          else
            setting.callbacks.any?
          end
        end
      end

      # Find settings with validation
      #
      # @return [Array<Setting>] Settings with validators
      def settings_with_validation
        all_settings_recursive.select do |setting|
          setting.options.key?(:validate_with)
        end
      end

      # Find settings with a specific default value
      #
      # @param value [Object] Default value to match
      # @return [Array<Setting>] Settings with matching default
      def settings_with_default(value)
        all_settings_recursive.select do |setting|
          setting.default == value
        end
      end

      # Group settings by a metadata key
      #
      # @param key [Symbol] Metadata key to group by
      # @return [Hash] Hash of metadata value => array of settings
      #
      # @example
      #   User.settings_grouped_by_metadata(:category)
      #   # => {"security" => [...], "billing" => [...]}
      #
      def settings_grouped_by_metadata(key)
        all_settings_recursive.group_by do |setting|
          setting.metadata[key] || :ungrouped
        end
      end

      # Find settings matching a condition block
      #
      # @yield [setting] Block that receives each setting
      # @return [Array<Setting>] Settings where block returns true
      #
      # @example
      #   User.settings_matching { |s| s.name.to_s.include?("api") }
      #
      def settings_matching(&block)
        all_settings_recursive.select(&block)
      end

      # Count settings by criteria
      #
      # @param criteria [Hash] Criteria to count by
      # @return [Integer] Count of matching settings
      #
      # @example
      #   User.settings_count(type: :json)
      #   User.settings_count(metadata: {tier: "premium"})
      #
      def settings_count(**criteria)
        settings = all_settings_recursive

        if criteria[:type]
          settings = settings.select { |s| s.type == criteria[:type] }
        end

        if criteria[:metadata]
          settings = settings.select do |s|
            criteria[:metadata].all? { |k, v| s.metadata[k] == v }
          end
        end

        if criteria[:deprecated]
          settings = settings.select(&:deprecated?)
        end

        settings.size
      end
    end
  end
end
