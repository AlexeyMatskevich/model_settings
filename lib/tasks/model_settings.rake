# frozen_string_literal: true

namespace :settings do
  namespace :docs do
    desc "Generate documentation for all models with settings"
    task generate: :environment do
      require "model_settings"

      output_dir = ENV["OUTPUT_DIR"] || "docs/settings"
      format = (ENV["FORMAT"] || "markdown").to_sym

      puts "Generating #{format} documentation..."
      puts "Output directory: #{output_dir}"
      puts ""

      generated_files = ModelSettings::Documentation.generate_all(
        output_dir: output_dir,
        format: format
      )

      puts "Generated #{generated_files.size} files:"
      generated_files.each do |file|
        puts "  - #{file}"
      end

      puts ""
      puts "✓ Documentation generation complete!"
    rescue => e
      puts "ERROR: #{e.message}"
      puts e.backtrace.first(5).join("\n")
      exit 1
    end
  end

  namespace :audit do
    desc "Audit deprecated settings across all models"
    task deprecated: :environment do
      require "model_settings"

      puts "Auditing deprecated settings..."
      puts ""

      models = find_models_with_settings
      deprecated_count = 0

      models.each do |model_class|
        deprecated_settings = model_class._settings.select(&:deprecated?)

        next if deprecated_settings.empty?

        puts "#{model_class.name}:"
        deprecated_settings.each do |setting|
          deprecated_count += 1
          message = setting.options[:deprecated]
          message = "(no message)" if message == true

          puts "  - #{setting.name}: #{message}"
        end
        puts ""
      end

      if deprecated_count.zero?
        puts "✓ No deprecated settings found"
        exit 0
      else
        puts "Found #{deprecated_count} deprecated setting(s) across #{models.size} model(s)"
        exit 1  # Non-zero exit for CI/CD pipelines
      end
    rescue => e
      puts "ERROR: #{e.message}"
      exit 1
    end
  end

  # Helper method
  def find_models_with_settings
    return [] unless defined?(Rails)

    Rails.application.eager_load! if Rails.env.development?

    ActiveRecord::Base.descendants.select do |model|
      model.respond_to?(:_settings) && model._settings.any?
    end
  end
end
