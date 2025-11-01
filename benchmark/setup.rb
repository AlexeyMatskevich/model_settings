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
def create_test_model(name, &block)
  Class.new(ActiveRecord::Base) do
    self.table_name = "benchmark_models"

    def self.name
      "BenchmarkModel_#{name}"
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
end

puts "Benchmark setup complete"
puts "Ruby version: #{RUBY_VERSION}"
puts "ActiveRecord version: #{ActiveRecord::VERSION::STRING}"
puts "ModelSettings version: #{ModelSettings::VERSION}"
puts ""
