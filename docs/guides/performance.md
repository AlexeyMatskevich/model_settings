# Performance Guide

This guide covers performance characteristics of ModelSettings and optimization strategies for production deployments.

## Table of Contents

- [Overview](#overview)
- [Benchmark Results](#benchmark-results)
- [Performance Characteristics](#performance-characteristics)
- [Optimization Strategies](#optimization-strategies)
- [Common Performance Issues](#common-performance-issues)
- [Monitoring](#monitoring)

## Overview

ModelSettings is designed for high performance with minimal overhead. Most operations complete in microseconds, making it suitable for high-traffic production applications.

### Key Performance Metrics

| Operation | Performance | Notes |
|-----------|-------------|-------|
| **Read column setting** | ~1-2 μs | Direct database column access |
| **Write column setting** | ~5-10 μs | Includes dirty tracking |
| **Read JSON setting** | ~2-3 μs | JSON deserialization overhead |
| **Write JSON setting** | ~10-15 μs | JSON serialization + dirty tracking |
| **Helper methods** | ~5-10 μs | Minimal overhead over direct access |
| **Dirty tracking** | ~1-2 μs | Efficient change detection |

### Definition Time Performance

| Settings Count | Time | Impact |
|----------------|------|--------|
| 1 setting | ~0.7 ms | Negligible |
| 10 settings | ~1.1 ms | Negligible |
| 100 settings | ~5 ms | Minimal |
| 1000 settings | ~85 ms | Noticeable on boot |

**Recommendation:** Keep settings count per model under 100 for optimal boot time.

## Benchmark Results

Based on benchmarks on Ruby 3.4.7, ActiveRecord 8.1, SQLite:

### Setting Definition (Class Load Time)

```
define 1 setting:     1432.9 i/s  (0.7 ms per model)
define 10 settings:    939.6 i/s  (1.1 ms per model) - 1.52x slower
define 100 settings:   202.0 i/s  (5.0 ms per model) - 7.09x slower
define 1000 settings:   11.7 i/s  (85.3 ms per model) - 122x slower
```

**Impact:** Affects application boot time only. Not a concern for most applications.

### Runtime Operations

```
read column setting:    500,000+ i/s  (~2 μs)
write column setting:   100,000+ i/s  (~10 μs)
enable! helper:          80,000+ i/s  (~12 μs)
toggle! helper:          75,000+ i/s  (~13 μs)
enabled? query:         500,000+ i/s  (~2 μs)

read JSON setting:      300,000+ i/s  (~3 μs)
write JSON setting:      60,000+ i/s  (~16 μs)
```

**Impact:** Negligible overhead in request/response cycle.

### Dependency Operations

```
Enable root (5-level cascade):    1,000+ i/s  (~1 ms)
Enable middle level (2-level):    3,000+ i/s  (~0.3 ms)
Enable leaf (no cascade):        10,000+ i/s  (~0.1 ms)

Change source (5-sync chain):     1,200+ i/s  (~0.8 ms)
Change middle (2-sync chain):     3,500+ i/s  (~0.3 ms)
Change leaf (no sync):           10,000+ i/s  (~0.1 ms)
```

**Impact:** Complex dependencies add overhead. Keep cascade/sync chains shallow (< 5 levels).

## Performance Characteristics

### Storage Adapter Comparison

| Adapter | Read Speed | Write Speed | Best For |
|---------|------------|-------------|----------|
| **Column** | Fastest | Fast | Individual toggles, feature flags |
| **JSON** | Fast | Medium | Related settings, flexible schema |
| **StoreModel** | Fast | Medium | Complex nested configs, type safety |

**Column adapter** is fastest but requires database migrations for schema changes.

**JSON adapter** offers flexibility with minimal performance cost (~20% slower than column).

### Overhead Analysis

ModelSettings adds minimal overhead compared to raw ActiveRecord:

```ruby
# Raw ActiveRecord
user.premium  # ~1 μs

# ModelSettings with Column adapter
user.premium  # ~2 μs (+100% but still negligible)

# ModelSettings with JSON adapter
user.theme    # ~3 μs (+200% but still negligible)
```

Even with "overhead", operations complete in microseconds. Not a bottleneck for 99.9% of applications.

### Dirty Tracking

Dirty tracking adds ~1 μs overhead per operation:

```ruby
user.premium_changed?  # ~1 μs
user.premium_was       # ~1 μs
user.premium_change    # ~2 μs
```

This is comparable to ActiveRecord's built-in dirty tracking.

## Optimization Strategies

### 1. Choose the Right Adapter

**Use Column adapter when:**
- Settings are accessed frequently (hot path)
- You need maximum performance
- Schema changes are infrequent

**Use JSON adapter when:**
- Settings are related/grouped logically
- Schema changes are frequent
- Moderate performance is acceptable

**Use StoreModel adapter when:**
- Complex nested structures are needed
- Type safety is important
- Moderate performance is acceptable

### 2. Minimize Cascade/Sync Depth

**Bad:** Deep cascade chains

```ruby
setting :level_0, cascade: {enable: true} do
  setting :level_1, cascade: {enable: true} do
    setting :level_2, cascade: {enable: true} do
      setting :level_3, cascade: {enable: true} do
        setting :level_4, cascade: {enable: true} do
          setting :level_5  # 5 levels deep - slow!
        end
      end
    end
  end
end
```

**Good:** Flat or shallow structure

```ruby
setting :parent, cascade: {enable: true} do
  setting :child_1
  setting :child_2
  setting :child_3  # Only 2 levels - fast!
end
```

**Impact:** Each cascade level adds ~0.2ms. Keep depth < 3 for optimal performance.

### 3. Batch Updates

**Bad:** Multiple separate saves

```ruby
user.premium_enable!
user.api_access_enable!
user.priority_support_enable!  # 3 DB roundtrips
```

**Good:** Single transaction

```ruby
user.transaction do
  user.premium = true
  user.api_access = true
  user.priority_support = true
  user.save!  # 1 DB roundtrip
end
```

### 4. Avoid N+1 Queries

**Bad:** Loading settings in a loop

```ruby
users.each do |user|
  puts user.premium  # N+1 query if not preloaded
end
```

**Good:** Preload settings columns

```ruby
users = User.select(:id, :premium, :api_access).all
users.each do |user|
  puts user.premium  # No extra query
end
```

Settings are just regular model attributes - normal ActiveRecord optimization techniques apply.

### 5. Cache Expensive Operations

If you have complex logic depending on multiple settings:

```ruby
# Bad: Recompute every time
def feature_available?
  premium? && api_access? && within_quota? && !suspended?
end

# Good: Cache result
def feature_available?
  Rails.cache.fetch("user:#{id}:feature_available", expires_in: 5.minutes) do
    premium? && api_access? && within_quota? && !suspended?
  end
end
```

### 6. Optimize Definition Time

**Bad:** Excessive settings per model

```ruby
class User
  100.times do |i|
    setting :"feature_#{i}", type: :column  # Slow boot time
  end
end
```

**Good:** Group related settings in JSON

```ruby
class User
  setting :features, type: :json, storage: {column: :features_json} do
    100.times do |i|
      setting :"feature_#{i}"  # Fast boot time
    end
  end
end
```

## Common Performance Issues

### Issue 1: Slow Application Boot

**Symptom:** Application takes > 5 seconds to boot

**Causes:**
- Too many settings defined per model (> 100)
- Complex dependency graphs
- Eager loading all models unnecessarily

**Solutions:**
- Group related settings in JSON adapters
- Simplify cascade/sync relationships
- Use lazy loading where possible

### Issue 2: Slow Request Times

**Symptom:** Requests take > 100ms with simple setting access

**Causes:**
- N+1 queries from settings access
- Deep cascade/sync chains triggered on every request
- Complex validation logic

**Solutions:**
- Preload setting columns with `select`
- Move complex cascades to background jobs
- Cache computed results

### Issue 3: High Memory Usage

**Symptom:** Memory grows continuously with setting access

**Causes:**
- Memory leaks in custom callbacks
- Excessive caching
- Large JSON objects stored in settings

**Solutions:**
- Profile callback code for leaks
- Use time-based cache expiration
- Store large objects in separate storage (S3, etc.)

## Monitoring

### Key Metrics to Monitor

1. **Application Boot Time**
   - Target: < 10 seconds
   - Alert if > 30 seconds

2. **Setting Read Latency (p95)**
   - Target: < 10 μs
   - Alert if > 100 μs

3. **Setting Write Latency (p95)**
   - Target: < 50 μs
   - Alert if > 500 μs

4. **Cascade/Sync Execution Time (p95)**
   - Target: < 1 ms
   - Alert if > 10 ms

### Monitoring Tools

**New Relic:**
```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  setting :premium, type: :column do
    after_enable do
      NewRelic::Agent.record_metric("Custom/Settings/Premium/Enable", 1)
    end
  end
end
```

**Datadog:**
```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  setting :premium, type: :column do
    after_enable do
      Datadog::Statsd.increment("settings.premium.enable")
    end
  end
end
```

### Profiling

Use `ruby-prof` to profile setting operations:

```ruby
require "ruby-prof"

RubyProf.start

1000.times do
  user.premium_enable!
end

result = RubyProf.stop
printer = RubyProf::FlatPrinter.new(result)
printer.print(STDOUT)
```

## Related Documentation

- [Benchmark Suite](../../benchmark/README.md) - Run performance benchmarks
- [Storage Adapters](../core/adapters.md) - Adapter comparison
- [Dependencies](../core/dependencies.md) - Cascade/sync performance
- [Best Practices](best_practices.md) - General optimization tips

## Questions?

If you encounter performance issues not covered here:
1. Run benchmarks to measure actual impact
2. Profile your application to identify bottlenecks
3. Open an issue with benchmark results and profiling data
