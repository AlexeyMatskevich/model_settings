# frozen_string_literal: true

require_relative "setup"

puts "=" * 80
puts "Runtime Performance Benchmark"
puts "=" * 80
puts ""

# Setup test model
model_class = create_test_model("runtime") do
  setting :feature_1, type: :column, default: false
  setting :feature_2, type: :column, default: false
  setting :feature_3, type: :column, default: false

  setting :prefs, type: :json, storage: {column: :prefs_json} do
    setting :ui_theme, default: "light"
    setting :email_notifications, default: true
    setting :ui_language, default: "en"
  end
end

model_class.compile_settings!

# Create test instance
instance = model_class.new
instance.feature_1 = false
instance.feature_2 = false
instance.feature_3 = false
instance.ui_theme = "light"
instance.email_notifications = true
instance.ui_language = "en"
instance.save!(validate: false)

puts "Testing with instance: #{instance.class.name}"
puts ""

Benchmark.ips do |x|
  x.config(time: 5, warmup: 2)

  x.report("read column setting") do
    instance.feature_1
  end

  x.report("write column setting") do
    instance.feature_1 = true
  end

  x.report("enable! helper") do
    instance.feature_1_enable!
  end

  x.report("toggle! helper") do
    instance.feature_1_toggle!
  end

  x.report("enabled? query") do
    instance.feature_1_enabled?
  end

  x.report("read JSON setting") do
    instance.ui_theme
  end

  x.report("write JSON setting") do
    instance.ui_theme = "dark"
  end

  x.compare!
end

puts ""
puts "=" * 80
puts "Dirty Tracking Performance"
puts "=" * 80
puts ""

Benchmark.ips do |x|
  x.config(time: 5, warmup: 2)

  x.report("changed? check") do
    instance.feature_1_changed?
  end

  x.report("was value") do
    instance.feature_1_was
  end

  x.report("change array") do
    instance.feature_1_change
  end

  x.report("changes hash") do
    instance.changes
  end

  x.compare!
end
