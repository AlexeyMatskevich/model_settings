# frozen_string_literal: true

# Run all benchmarks
#
# Usage:
#   ruby benchmark/run_all.rb
#
# Or individual benchmarks:
#   ruby benchmark/definition_benchmark.rb
#   ruby benchmark/runtime_benchmark.rb
#   ruby benchmark/dependency_benchmark.rb

puts ""
puts "=" * 80
puts "ModelSettings Performance Benchmark Suite"
puts "=" * 80
puts ""
puts "This will run all performance benchmarks."
puts "This may take 5-10 minutes..."
puts ""

benchmarks = [
  "definition_benchmark.rb",
  "runtime_benchmark.rb",
  "dependency_benchmark.rb"
]

benchmarks.each do |benchmark|
  puts ""
  puts "▶ Running #{benchmark}..."
  puts ""

  require_relative benchmark

  puts ""
  puts "✓ #{benchmark} complete"
  puts ""
end

puts ""
puts "=" * 80
puts "All Benchmarks Complete!"
puts "=" * 80
puts ""
