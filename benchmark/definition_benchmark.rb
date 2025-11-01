# frozen_string_literal: true

require_relative "setup"

puts "=" * 80
puts "Setting Definition Performance Benchmark"
puts "=" * 80
puts ""

Benchmark.ips do |x|
  x.config(time: 5, warmup: 2)

  x.report("define 1 setting") do
    create_test_model("single") do
      setting :feature, type: :column, default: false
    end
  end

  x.report("define 10 settings") do
    create_test_model("ten") do
      10.times do |i|
        setting :"feature_#{i}", type: :column, default: false
      end
    end
  end

  x.report("define 100 settings") do
    create_test_model("hundred") do
      100.times do |i|
        setting :"feature_#{i}", type: :column, default: false
      end
    end
  end

  x.report("define 1000 settings") do
    create_test_model("thousand") do
      1000.times do |i|
        setting :"feature_#{i}", type: :column, default: false
      end
    end
  end

  x.compare!
end

puts ""
puts "=" * 80
puts "Nested Settings Performance"
puts "=" * 80
puts ""

Benchmark.ips do |x|
  x.config(time: 5, warmup: 2)

  x.report("1 level (10 settings)") do
    create_test_model("flat") do
      10.times do |i|
        setting :"feature_#{i}", type: :column, default: false
      end
    end
  end

  x.report("2 levels (5x2 = 10 settings)") do
    create_test_model("nested_2") do
      5.times do |i|
        setting :"parent_#{i}", type: :json, storage: {column: :settings_json} do
          2.times do |j|
            setting :"child_#{j}", default: false
          end
        end
      end
    end
  end

  x.report("3 levels (3x3x3 = 27 settings)") do
    create_test_model("nested_3") do
      3.times do |i|
        setting :"parent_#{i}", type: :json, storage: {column: :settings_json} do
          3.times do |j|
            setting :"child_#{j}", default: false do
              3.times do |k|
                setting :"grandchild_#{k}", default: false
              end
            end
          end
        end
      end
    end
  end

  x.compare!
end
