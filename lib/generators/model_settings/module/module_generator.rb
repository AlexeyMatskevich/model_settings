# frozen_string_literal: true

require "rails/generators"
require "rails/generators/named_base"

module ModelSettings
  module Generators
    # Generator for creating custom ModelSettings modules
    #
    # Usage:
    #   rails generate model_settings:module AuditTrail
    #   rails generate model_settings:module AuditTrail --skip-tests
    #   rails generate model_settings:module AuditTrail --skip-docs
    #
    # This will create:
    #   lib/model_settings/modules/audit_trail.rb
    #   spec/model_settings/modules/audit_trail_spec.rb
    #   docs/modules/audit_trail.md
    #
    class ModuleGenerator < Rails::Generators::NamedBase
      source_root File.expand_path("templates", __dir__)

      class_option :skip_tests, type: :boolean, default: false,
        desc: "Skip generating test file"

      class_option :skip_docs, type: :boolean, default: false,
        desc: "Skip generating documentation file"

      class_option :exclusive_group, type: :string, default: nil,
        desc: "Exclusive group name (e.g., 'authorization' for mutually exclusive modules)"

      class_option :options, type: :array, default: [],
        desc: "Custom options to register (e.g., 'audit_level:symbol' 'notify:boolean')"

      # Main generator action
      def create_module_file
        template "module.rb.tt", module_file_path
      end

      def create_spec_file
        return if options[:skip_tests]

        template "module_spec.rb.tt", spec_file_path
      end

      def create_docs_file
        return if options[:skip_docs]

        template "module_docs.md.tt", docs_file_path
      end

      def show_readme
        say "\n"
        say "Module #{module_class_name} created successfully!", :green
        say "\n"
        say "Created files:"
        say "  #{module_file_path}", :green
        say "  #{spec_file_path}", :green unless options[:skip_tests]
        say "  #{docs_file_path}", :green unless options[:skip_docs]
        say "\n"
        say "Next steps:"
        say "  1. Edit #{module_file_path} to implement your module logic"
        say "  2. Run tests: bundle exec rspec #{spec_file_path}" unless options[:skip_tests]
        say "  3. Update documentation in #{docs_file_path}" unless options[:skip_docs]
        say "  4. Include module in your models:"
        say "     class User < ApplicationRecord"
        say "       include ModelSettings::DSL"
        say "       include ModelSettings::Modules::#{module_class_name}"
        say "     end"
        say "\n"
      end

      private

      # Module class name (e.g., "AuditTrail")
      def module_class_name
        @module_class_name ||= name.camelize
      end

      # Module file name (e.g., "audit_trail")
      def module_file_name
        @module_file_name ||= name.underscore
      end

      # Module symbol name (e.g., ":audit_trail")
      def module_symbol_name
        @module_symbol_name ||= ":#{module_file_name}"
      end

      # Full module path (e.g., "ModelSettings::Modules::AuditTrail")
      def module_full_name
        "ModelSettings::Modules::#{module_class_name}"
      end

      # File paths
      def module_file_path
        "lib/model_settings/modules/#{module_file_name}.rb"
      end

      def spec_file_path
        "spec/model_settings/modules/#{module_file_name}_spec.rb"
      end

      def docs_file_path
        "docs/modules/#{module_file_name}.md"
      end

      # Check if exclusive group option is provided
      def exclusive_group?
        options[:exclusive_group].present?
      end

      # Get exclusive group name
      def exclusive_group_name
        options[:exclusive_group]
      end

      # Get exclusive group symbol
      def exclusive_group_symbol
        ":#{exclusive_group_name}"
      end

      # Parse custom options
      def custom_options
        @custom_options ||= options[:options].map do |opt|
          name, type = opt.split(":")
          {
            name: name,
            symbol: ":#{name}",
            type: type || "any",
            validator_example: validator_example_for(type)
          }
        end
      end

      # Has custom options?
      def has_custom_options?
        custom_options.any?
      end

      # Generate validator example based on type
      def validator_example_for(type)
        case type
        when "symbol"
          "raise ArgumentError unless value.is_a?(Symbol)"
        when "boolean"
          "raise ArgumentError unless [true, false].include?(value)"
        when "string"
          "raise ArgumentError unless value.is_a?(String)"
        when "array"
          "raise ArgumentError unless value.is_a?(Array)"
        when "hash"
          "raise ArgumentError unless value.is_a?(Hash)"
        else
          "# Add your validation logic here"
        end
      end
    end
  end
end
