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
      puts e.backtrace.first(5).join("\n") if ENV["DEBUG"]
      exit 1
    end

    desc "List all deprecated settings"
    task list_deprecated: :environment do
      require "model_settings"

      lister = ModelSettings::DeprecatedSettingsLister.new
      lister.print_list
    rescue => e
      puts "ERROR: #{e.message}"
      puts e.backtrace.first(5).join("\n") if ENV["DEBUG"]
      exit 1
    end
  end

  namespace :audit do
    desc "Audit deprecated settings usage in database"
    task deprecated: :environment do
      require "model_settings"

      auditor = ModelSettings::DeprecationAuditor.new
      report = auditor.generate_report

      puts report

      if report.has_active_usage?
        exit 1  # Fail CI if deprecated settings are in use
      else
        exit 0  # Success
      end
    rescue => e
      puts "ERROR: #{e.message}"
      puts e.backtrace.first(5).join("\n") if ENV["DEBUG"]
      exit 1
    end
  end
end
