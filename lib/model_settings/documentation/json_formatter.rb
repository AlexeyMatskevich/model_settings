# frozen_string_literal: true

require "json"

module ModelSettings
  module Documentation
    # JSON formatter for settings documentation
    class JsonFormatter
      attr_reader :model_class, :settings

      def initialize(model_class, settings)
        @model_class = model_class
        @settings = settings
      end

      def generate
        JSON.pretty_generate(build_documentation_hash)
      end

      private

      def build_documentation_hash
        {
          model: model_class.name,
          generated_at: Time.now.iso8601,
          settings: settings.map { |setting| format_setting(setting) }
        }
      end

      def format_setting(setting)
        hash = {
          name: setting.name.to_s,
          type: setting.type.to_s,
          storage: format_storage(setting),
          default: setting.default
        }

        hash[:description] = setting.description if setting.description

        # Authorization
        if (auth = format_authorization(setting))
          hash[:authorization] = auth
        end

        # Deprecation
        if setting.deprecated?
          dep_msg = setting.options[:deprecated]
          hash[:deprecated] = (dep_msg == true) ? true : dep_msg.to_s
        else
          hash[:deprecated] = false
        end

        # API methods
        instance_name = model_class.name.underscore
        hash[:api] = {
          getter: "#{instance_name}.#{setting.name}",
          setter: "#{instance_name}.#{setting.name} = value",
          enable: "#{instance_name}.#{setting.name}_enable!",
          disable: "#{instance_name}.#{setting.name}_disable!",
          toggle: "#{instance_name}.#{setting.name}_toggle!",
          enabled?: "#{instance_name}.#{setting.name}_enabled?",
          disabled?: "#{instance_name}.#{setting.name}_disabled?"
        }

        # Dependencies
        if setting.cascade || setting.sync
          hash[:dependencies] = {}
          hash[:dependencies][:cascade] = format_cascade_json(setting.cascade) if setting.cascade
          hash[:dependencies][:sync] = format_sync_json(setting.sync) if setting.sync
        end

        hash
      end

      def format_storage(setting)
        case setting.type
        when :column
          {
            type: "column",
            column: setting.name.to_s
          }
        when :json
          column = setting.storage[:column].to_s
          result = {
            type: "json",
            column: column
          }
          result[:path] = setting.name.to_s if setting.parent
          result
        when :store_model
          {
            type: "store_model",
            column: setting.storage[:column].to_s
          }
        else
          {type: setting.type.to_s}
        end
      end

      def format_authorization(setting)
        # Check Roles module
        if model_class.respond_to?(:_settings_roles)
          roles = model_class._settings_roles[setting.name]
          if roles
            auth = {}
            auth[:module] = "Roles"
            auth[:viewable_by] = format_roles_json(roles[:viewable_by]) if roles[:viewable_by]
            auth[:editable_by] = format_roles_json(roles[:editable_by]) if roles[:editable_by]
            return auth unless auth.keys == [:module]
          end
        end

        # Check Pundit/ActionPolicy modules
        if model_class.respond_to?(:_authorized_settings)
          method = model_class._authorized_settings[setting.name]
          if method
            auth_module = detect_authorization_module
            return {
              module: auth_module,
              method: method.to_s
            }
          end
        end

        nil
      end

      def detect_authorization_module
        if model_class.ancestors.include?(ModelSettings::Modules::Pundit)
          "Pundit"
        elsif model_class.ancestors.include?(ModelSettings::Modules::ActionPolicy)
          "ActionPolicy"
        else
          "Unknown"
        end
      end

      def format_roles_json(roles)
        return "all" if roles == :all
        return [] if roles.nil? || roles.empty?
        roles.map(&:to_s)
      end

      def format_cascade_json(cascade)
        {
          enable: cascade[:enable] || false,
          disable: cascade[:disable] || false
        }
      end

      def format_sync_json(sync)
        {
          mode: sync[:mode].to_s,
          target: sync[:target].to_s
        }
      end
    end
  end
end
