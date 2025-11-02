# frozen_string_literal: true

module ModelSettings
  module Documentation
    # Markdown formatter for settings documentation
    class MarkdownFormatter
      attr_reader :model_class, :settings

      def initialize(model_class, settings)
        @model_class = model_class
        @settings = settings
      end

      def generate
        lines = []
        lines << "# #{model_class.name} Settings"
        lines << ""
        lines << "Generated: #{Time.now.strftime("%Y-%m-%d %H:%M:%S")}"
        lines << ""

        if settings.empty?
          lines << "*No settings defined*"
          return lines.join("\n")
        end

        lines << "## Settings"
        lines << ""

        settings.each do |setting|
          lines.concat(format_setting(setting))
          lines << ""
        end

        lines.join("\n")
      end

      private

      def format_setting(setting)
        lines = []
        lines << "### `#{setting.name}`"
        lines << ""

        # Description
        if setting.description
          lines << setting.description
          lines << ""
        end

        # Metadata table
        lines << "| Property | Value |"
        lines << "|----------|-------|"
        lines << "| **Type** | #{setting.type} |"
        lines << "| **Storage** | #{format_storage(setting)} |"
        lines << "| **Default** | `#{format_value(setting.default)}` |" if setting.options.key?(:default)

        # Authorization
        if (auth_info = format_authorization(setting))
          lines << "| **Authorization** | #{auth_info} |"
        end

        # Deprecation
        if setting.deprecated?
          dep_msg = setting.options[:deprecated]
          dep_msg = "Yes" if dep_msg == true
          lines << "| **Deprecated** | ⚠️  #{dep_msg} |"
        end

        lines << ""

        # API methods
        lines << "**API Methods:**"
        lines << ""
        lines << "```ruby"
        lines << "# Getter"
        lines << "#{model_class.name.underscore}.#{setting.name}"
        lines << ""
        lines << "# Setter"
        lines << "#{model_class.name.underscore}.#{setting.name} = value"
        lines << ""
        lines << "# Helpers (for boolean settings)"
        lines << "#{model_class.name.underscore}.#{setting.name}_enable!"
        lines << "#{model_class.name.underscore}.#{setting.name}_disable!"
        lines << "#{model_class.name.underscore}.#{setting.name}_toggle!"
        lines << "#{model_class.name.underscore}.#{setting.name}_enabled?"
        lines << "#{model_class.name.underscore}.#{setting.name}_disabled?"
        lines << "```"

        # Cascades/Syncs
        if setting.cascade || setting.sync
          lines << ""
          lines << "**Dependencies:**"
          lines << ""

          if setting.cascade
            lines << "- **Cascade**: #{format_cascade(setting.cascade)}"
          end

          if setting.sync
            lines << "- **Sync**: #{format_sync(setting.sync)}"
          end
        end

        lines << ""
        lines << "---"

        lines
      end

      def format_storage(setting)
        case setting.type
        when :column
          "`#{setting.name}` column"
        when :json
          column = setting.storage[:column]
          if setting.parent
            "`#{column}` → `#{setting.name}`"
          else
            "`#{column}` JSON column"
          end
        when :store_model
          column = setting.storage[:column]
          "`#{column}` StoreModel"
        else
          setting.type.to_s
        end
      end

      def format_authorization(setting)
        # Check Roles module
        roles = ModelSettings::ModuleRegistry.get_module_metadata(model_class, :roles, setting.name)
        if roles
          parts = []
          if roles[:viewable_by] && roles[:viewable_by] != []
            parts << "View: #{format_roles(roles[:viewable_by])}"
          end
          if roles[:editable_by] && roles[:editable_by] != []
            parts << "Edit: #{format_roles(roles[:editable_by])}"
          end
          return parts.join(", ") unless parts.empty?
        end

        # Check Pundit module
        pundit_method = ModelSettings::ModuleRegistry.get_module_metadata(model_class, :pundit, setting.name)
        return "Requires `#{pundit_method}` permission" if pundit_method

        # Check ActionPolicy module
        action_policy_method = ModelSettings::ModuleRegistry.get_module_metadata(model_class, :action_policy, setting.name)
        return "Requires `#{action_policy_method}` permission" if action_policy_method

        nil
      end

      def format_roles(roles)
        return ":all" if roles == :all
        roles.map { |r| ":#{r}" }.join(", ")
      end

      def format_value(value)
        case value
        when String
          "\"#{value}\""
        when Symbol
          ":#{value}"
        when nil
          "nil"
        else
          value.inspect
        end
      end

      def format_cascade(cascade)
        parts = []
        parts << "enable children" if cascade[:enable]
        parts << "disable children" if cascade[:disable]
        parts.join(" and ")
      end

      def format_sync(sync)
        "#{sync[:mode]} with #{sync[:target]}"
      end
    end
  end
end
