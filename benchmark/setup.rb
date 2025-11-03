# frozen_string_literal: true

require "bundler/setup"
require "benchmark/ips"
require_relative "../lib/model_settings"

# Setup test database for benchmarks
require "active_record"

ActiveRecord::Base.establish_connection(
  adapter: "sqlite3",
  database: ":memory:"
)

# Silence ActiveRecord logs
ActiveRecord::Base.logger = Logger.new(nil)

# Helper to create a test model class
def create_test_model(model_name, &block)
  Class.new(ActiveRecord::Base) do
    self.table_name = "benchmark_models"

    define_singleton_method(:name) do
      "BenchmarkModel_#{model_name}"
    end

    include ModelSettings::DSL

    class_eval(&block) if block_given?
  end
end

# Setup benchmark table
ActiveRecord::Base.connection.create_table :benchmark_models, force: true do |t|
  t.boolean :feature_1
  t.boolean :feature_2
  t.boolean :feature_3
  t.boolean :feature_4
  t.boolean :feature_5
  t.text :settings_json  # SQLite uses text for JSON
  t.text :prefs_json

  # Columns for cascade benchmark
  t.boolean :level_0
  t.boolean :level_1
  t.boolean :level_2
  t.boolean :level_3
  t.boolean :level_4
  t.boolean :level_5

  # Columns for sync benchmark
  t.boolean :source
  t.boolean :target_1
  t.boolean :target_2
  t.boolean :target_3
  t.boolean :target_4
  t.boolean :target_5
end

puts "Benchmark setup complete"
puts "Ruby version: #{RUBY_VERSION}"
puts "ActiveRecord version: #{ActiveRecord::VERSION::STRING}"
puts "ModelSettings version: #{ModelSettings::VERSION}"
puts ""
