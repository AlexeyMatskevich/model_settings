# frozen_string_literal: true

module ModelSettings
  # Documentation generation for settings
  #
  # Generates documentation from settings metadata without requiring
  # additional documentation-specific DSL options.
  #
  # @example Generate markdown documentation
  #   docs = User.settings_documentation(format: :markdown)
  #   File.write('docs/user_settings.md', docs)
  #
  # @example Generate JSON documentation
  #   docs = User.settings_documentation(format: :json)
  #
  # @example Generate documentation for all models
  #   ModelSettings::Documentation.generate_all(
  #     output_dir: 'docs/settings',
  #     format: :markdown
  #   )
  #
  module Documentation
    class << self
      # Generate documentation for all models with settings
      #
      # @param output_dir [String] Directory to write documentation files
      # @param format [Symbol] Output format (:markdown, :json, :yaml)
      # @return [Array<String>] List of generated files
      #
      def generate_all(output_dir:, format: :markdown)
        require "fileutils"
        FileUtils.mkdir_p(output_dir)

        models = find_models_with_settings
        generated_files = []

        models.each do |model_class|
          filename = "#{model_class.name.underscore}.#{extension_for(format)}"
          filepath = File.join(output_dir, filename)

          docs = model_class.settings_documentation(format: format)
          File.write(filepath, docs)

          generated_files << filepath
        end

        # Generate index file
        index_file = generate_index(models, output_dir, format)
        generated_files << index_file if index_file

        generated_files
      end

      private

      # Find all models that include ModelSettings::DSL
      def find_models_with_settings
        return [] unless defined?(Rails)

        Rails.application.eager_load! if Rails.env.development?

        ActiveRecord::Base.descendants.select do |model|
          model.respond_to?(:_settings) && model._settings.any?
        end
      end

      # Get file extension for format
      def extension_for(format)
        case format
        when :markdown then "md"
        when :json then "json"
        when :yaml then "yml"
        else format.to_s
        end
      end

      # Generate index file listing all models
      def generate_index(models, output_dir, format)
        return nil unless format == :markdown

        index_path = File.join(output_dir, "index.md")
        content = build_index_markdown(models)
        File.write(index_path, content)

        index_path
      end

      # Build markdown index content
      def build_index_markdown(models)
        lines = []
        lines << "# Settings Documentation"
        lines << ""
        lines << "Generated: #{Time.now.strftime("%Y-%m-%d %H:%M:%S")}"
        lines << ""
        lines << "## Models"
        lines << ""

        models.sort_by(&:name).each do |model|
          settings_count = model._settings.size
          lines << "- [#{model.name}](#{model.name.underscore}.md) (#{settings_count} settings)"
        end

        lines.join("\n")
      end
    end
  end
end
