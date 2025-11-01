# ModelSettings Performance Benchmarks

This directory contains performance benchmarks for ModelSettings gem using `benchmark-ips`.

## Running Benchmarks

### Run All Benchmarks

```bash
ruby benchmark/run_all.rb
```

This will run all benchmark suites and take approximately 5-10 minutes.

### Run Individual Benchmarks

```bash
# Setting definition performance
ruby benchmark/definition_benchmark.rb

# Runtime operations performance
ruby benchmark/runtime_benchmark.rb

# Dependency engine (cascades & syncs) performance
ruby benchmark/dependency_benchmark.rb
```

## Benchmark Suites

### 1. Definition Benchmark (`definition_benchmark.rb`)

Measures the performance of defining settings at class load time.

**Tests:**
- Define 1, 10, 100, and 1000 settings
- Nested settings at different depth levels (1-3 levels)

**Why it matters:** Affects application boot time. Critical for apps with many models.

### 2. Runtime Benchmark (`runtime_benchmark.rb`)

Measures the performance of reading/writing settings at runtime.

**Tests:**
- Read/write column settings
- Read/write JSON settings
- Helper methods (`enable!`, `toggle!`, `enabled?`)
- Dirty tracking operations (`changed?`, `was`, `change`)

**Why it matters:** Affects request/response time in production.

### 3. Dependency Benchmark (`dependency_benchmark.rb`)

Measures the performance of cascade and sync operations.

**Tests:**
- Cascade execution at different depths (5 levels)
- Sync chain execution
- Dependency graph compilation

**Why it matters:** Affects complex setting updates with dependencies.

## Performance Characteristics

See [docs/guides/performance.md](../docs/guides/performance.md) for detailed performance characteristics and optimization tips.

## Interpreting Results

Benchmark results show:
- **i/s**: Iterations per second (higher is better)
- **Comparison**: Relative performance between operations

Example output:
```
Comparison:
    define 1 setting:     1432.9 i/s
  define 10 settings:      939.6 i/s - 1.52x  slower
 define 100 settings:      202.0 i/s - 7.09x  slower
define 1000 settings:       11.7 i/s - 122.26x  slower
```

## CI Integration

Benchmarks can be run in CI to detect performance regressions:

```yaml
# .github/workflows/benchmark.yml
name: Benchmark

on: [pull_request]

jobs:
  benchmark:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Set up Ruby
        uses: ruby/setup-ruby@v1
        with:
          bundler-cache: true
      - name: Run benchmarks
        run: ruby benchmark/run_all.rb
```

## Contributing

When adding new features:
1. Add relevant benchmarks to measure performance impact
2. Run benchmarks before and after changes
3. Document any significant performance changes in PR

## Requirements

- Ruby >= 3.1
- benchmark-ips gem (included in development dependencies)
