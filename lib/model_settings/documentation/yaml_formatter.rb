# frozen_string_literal: true

require "yaml"

module ModelSettings
  module Documentation
    # YAML formatter for settings documentation
    #
    # Generates YAML documentation suitable for:
    # - Configuration management
    # - Infrastructure as code
    # - Automated processing
    # - Version control friendly format
    #
    # @example
    #   formatter = YamlFormatter.new(User, User._settings)
    #   yaml = formatter.generate
    #   File.write("docs/user_settings.yml", yaml)
    #
    class YamlFormatter
      attr_reader :model_class, :settings

      def initialize(model_class, settings)
        @model_class = model_class
        @settings = settings
      end

      # Generate YAML documentation
      #
      # @return [String] YAML documentation
      def generate
        data = {
          "model" => model_class.name,
          "generated_at" => Time.current.iso8601,
          "version" => ModelSettings::VERSION,
          "settings_count" => settings.size,
          "settings" => settings.map { |setting| format_setting(setting) }
        }

        data.to_yaml
      end

      private

      # Format a single setting as a hash
      #
      # @param setting [Setting] The setting to format
      # @return [Hash] Setting data
      def format_setting(setting)
        data = {
          "name" => setting.name.to_s,
          "type" => setting.type.to_s,
          "storage" => format_storage(setting),
          "default" => format_value(setting.default)
        }

        # Description
        data["description"] = setting.description if setting.description

        # Authorization
        if (auth_info = format_authorization(setting))
          data["authorization"] = auth_info
        end

        # Deprecation
        if setting.deprecated?
          dep_msg = setting.options[:deprecated]
          data["deprecated"] = (dep_msg == true) ? true : dep_msg.to_s
          data["deprecated_since"] = setting.options[:deprecated_since] if setting.options[:deprecated_since]
        end

        # Metadata
        if setting.metadata.any?
          data["metadata"] = setting.metadata.transform_keys(&:to_s)
        end

        # Cascades
        if setting.cascade
          data["cascade"] = setting.cascade.transform_keys(&:to_s)
        end

        # Syncs
        if setting.options[:sync]
          sync_config = setting.options[:sync]
          data["sync"] = {
            "target" => (sync_config[:target] || sync_config["target"]).to_s,
            "mode" => (sync_config[:mode] || sync_config["mode"] || :forward).to_s
          }
        end

        # Callbacks
        callbacks = extract_callbacks(setting)
        if callbacks.any?
          data["callbacks"] = callbacks
        end

        # Children (nested settings)
        if setting.children.any?
          data["children"] = setting.children.map { |child| format_setting(child) }
        end

        data
      end

      # Format storage configuration
      #
      # @param setting [Setting] The setting
      # @return [Hash, String] Storage info
      def format_storage(setting)
        case setting.type
        when :column
          setting.storage[:column]&.to_s || setting.name.to_s
        when :json, :store_model
          if setting.storage.is_a?(Hash)
            {"column" => setting.storage[:column].to_s}
          else
            "inherited"
          end
        else
          "unknown"
        end
      end

      # Format value for YAML
      #
      # @param value [Object] The value
      # @return [Object] Formatted value
      def format_value(value)
        case value
        when Symbol
          value.to_s
        when Hash
          value.transform_keys(&:to_s)
        when Array
          value.map { |v| format_value(v) }
        else
          value
        end
      end

      # Extract callbacks from setting
      #
      # @param setting [Setting] The setting
      # @return [Hash] Callbacks hash
      def extract_callbacks(setting)
        callbacks = {}

        %i[
          before_enable after_enable around_enable
          before_disable after_disable around_disable
          before_toggle after_toggle
          before_change after_change around_change
          after_change_commit
          validate_with
        ].each do |callback_name|
          next unless setting.options.key?(callback_name)

          callback = setting.options[callback_name]
          callbacks[callback_name.to_s] = format_callback(callback)
        end

        callbacks
      end

      # Format callback for YAML
      #
      # @param callback [Symbol, Proc, Array] The callback
      # @return [String, Array] Formatted callback
      def format_callback(callback)
        case callback
        when Symbol
          callback.to_s
        when Proc
          "Proc"
        when Array
          callback.map { |cb| format_callback(cb) }
        else
          callback.to_s
        end
      end

      # Format authorization info
      #
      # @param setting [Setting] The setting
      # @return [Hash, nil] Authorization info
      def format_authorization(setting)
        if setting.options[:policy]
          {
            "policy" => setting.options[:policy].to_s,
            "action" => "update_#{setting.name}?"
          }
        elsif setting.options[:roles]
          roles = Array(setting.options[:roles]).map(&:to_s)
          {
            "type" => "roles",
            "required" => roles
          }
        end
      end
    end
  end
end
