# frozen_string_literal: true

require_relative "setup"

puts "=" * 80
puts "Dependency Engine Performance Benchmark"
puts "=" * 80
puts ""

# Setup cascade model
cascade_model = create_test_model("cascade") do
  setting :level_0, type: :column, cascade: {enable: true} do
    setting :level_1, type: :column, cascade: {enable: true} do
      setting :level_2, type: :column, cascade: {enable: true} do
        setting :level_3, type: :column, cascade: {enable: true} do
          setting :level_4, type: :column, cascade: {enable: true} do
            setting :level_5, type: :column, default: false
          end
        end
      end
    end
  end
end

cascade_model.compile_settings!
cascade_instance = cascade_model.new(
  level_0: false,
  level_1: false,
  level_2: false,
  level_3: false,
  level_4: false,
  level_5: false
)
cascade_instance.save!(validate: false)

puts "Testing cascade with 5 levels deep"
puts ""

Benchmark.ips do |x|
  x.config(time: 5, warmup: 2)

  x.report("enable root (triggers 5-level cascade)") do
    cascade_instance.level_0 = true
    cascade_instance.save!
    cascade_instance.level_0 = false
    cascade_instance.save!
  end

  x.report("enable middle level") do
    cascade_instance.level_2 = true
    cascade_instance.save!
    cascade_instance.level_2 = false
    cascade_instance.save!
  end

  x.report("enable leaf (no cascade)") do
    cascade_instance.level_5 = true
    cascade_instance.save!
    cascade_instance.level_5 = false
    cascade_instance.save!
  end

  x.compare!
end

puts ""
puts "=" * 80
puts "Sync Performance Benchmark"
puts "=" * 80
puts ""

# Setup sync model with chain
sync_model = create_test_model("sync") do
  setting :source, type: :column, default: false
  setting :target_1, type: :column, default: false, sync: {target: :source, mode: :forward}
  setting :target_2, type: :column, default: false, sync: {target: :target_1, mode: :forward}
  setting :target_3, type: :column, default: false, sync: {target: :target_2, mode: :forward}
  setting :target_4, type: :column, default: false, sync: {target: :target_3, mode: :forward}
  setting :target_5, type: :column, default: false, sync: {target: :target_4, mode: :forward}
end

sync_model.compile_settings!
sync_instance = sync_model.new(
  source: false,
  target_1: false,
  target_2: false,
  target_3: false,
  target_4: false,
  target_5: false
)
sync_instance.save!(validate: false)

puts "Testing sync chain with 5 settings"
puts ""

Benchmark.ips do |x|
  x.config(time: 5, warmup: 2)

  x.report("change source (triggers 5-setting sync chain)") do
    sync_instance.source = true
    sync_instance.save!
    sync_instance.source = false
    sync_instance.save!
  end

  x.report("change middle (triggers 2-setting sync)") do
    sync_instance.target_3 = true
    sync_instance.save!
    sync_instance.target_3 = false
    sync_instance.save!
  end

  x.report("change leaf (no sync)") do
    sync_instance.target_5 = true
    sync_instance.save!
    sync_instance.target_5 = false
    sync_instance.save!
  end

  x.compare!
end

puts ""
puts "=" * 80
puts "Dependency Graph Compilation"
puts "=" * 80
puts ""

Benchmark.ips do |x|
  x.config(time: 5, warmup: 2)

  x.report("compile 10 settings (no dependencies)") do
    model = create_test_model("compile_simple") do
      10.times { |i| setting :"feature_#{i}", type: :column, default: false }
    end
    model.compile_settings!
  end

  x.report("compile 10 settings (5 cascades)") do
    model = create_test_model("compile_cascade") do
      5.times do |i|
        setting :"parent_#{i}", type: :column, cascade: {enable: true} do
          setting :"child_#{i}", type: :column, default: false
        end
      end
    end
    model.compile_settings!
  end

  x.report("compile 10 settings (5 syncs)") do
    model = create_test_model("compile_sync") do
      setting :source, type: :column, default: false
      5.times do |i|
        setting :"target_#{i}", type: :column, default: false, sync: {target: :source, mode: :forward}
      end
    end
    model.compile_settings!
  end

  x.compare!
end
