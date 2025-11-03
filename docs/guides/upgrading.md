# Upgrading Guide

This guide covers how to upgrade ModelSettings between versions.

## Table of Contents

- [General Upgrade Process](#general-upgrade-process)
- [Version-Specific Upgrades](#version-specific-upgrades)
  - [Upgrading to 0.9.0](#upgrading-to-090)
  - [Upgrading to 0.8.0](#upgrading-to-080)
  - [Upgrading to 0.7.0](#upgrading-to-070)
- [Breaking Changes Policy](#breaking-changes-policy)
- [Deprecation Timeline](#deprecation-timeline)

## General Upgrade Process

### 1. Review CHANGELOG

Always read the [CHANGELOG.md](../../CHANGELOG.md) for the target version to understand:
- New features
- Breaking changes
- Deprecations
- Bug fixes

### 2. Update Gemfile

```ruby
# Gemfile
gem 'model_settings', '~> 0.9.0'
```

Then run:
```bash
bundle update model_settings
```

### 3. Run Tests

```bash
# Run full test suite
bundle exec rspec

# Check for deprecation warnings
VERBOSE=1 bundle exec rspec 2>&1 | grep -i deprecat
```

### 4. Audit Deprecated Settings

```bash
bundle exec rake settings:audit:deprecated
```

### 5. Review Code Changes

Check for:
- API changes in your code
- New required parameters
- Renamed methods
- Changed defaults

### 6. Deploy to Staging

Test the upgrade in staging environment before production.

### 7. Monitor After Deploy

Watch for:
- Error rates
- Performance changes
- Unexpected behavior

## Version-Specific Upgrades

## Upgrading to 0.9.0

**Release Date**: 2025-11-04
**Status**: Current stable release

### Breaking Changes

#### 1. Validator Signature Unified

**Old signature** (0.8.0 and earlier):
```ruby
ModelSettings::ModuleRegistry.register_option(:my_option) do |setting, value|
  # ...
end
```

**New signature** (0.9.0+):
```ruby
ModelSettings::ModuleRegistry.register_option(:my_option) do |value, setting, model_class|
  # ...
end
```

**Migration**:
```ruby
# Before (0.8.0)
ModelSettings::ModuleRegistry.register_option(:audit_level) do |setting, value|
  unless [:minimal, :detailed].include?(value)
    raise ArgumentError, "Invalid audit_level"
  end
end

# After (0.9.0)
ModelSettings::ModuleRegistry.register_option(:audit_level) do |value, setting, model_class|
  unless [:minimal, :detailed].include?(value)
    raise ArgumentError, "Invalid audit_level"
  end
end
```

**Impact**: Only affects custom modules that register options. Built-in modules (Roles, Pundit, ActionPolicy, I18n) are already updated.

**Who is affected**: Applications with custom modules only.

### New Features

- **Module Registry API Compliance**: Full support for all Module Registry APIs
- **Documentation Modules**: Enhanced I18n, Pundit, ActionPolicy, Roles documentation
- **PolicyBasedAuthorization**: Shared base class for Pundit and ActionPolicy
- **Improved Error Messages**: Better diagnostics with `did_you_mean` suggestions

### Deprecations

None in this release.

### Upgrade Steps

1. Update Gemfile: `gem 'model_settings', '~> 0.9.0'`
2. Run `bundle update model_settings`
3. **If you have custom modules**: Update validator signatures (see breaking change #1)
4. Run tests: `bundle exec rspec`
5. Deploy

---

## Upgrading to 0.8.0

**Release Date**: 2025-11-02

### Breaking Changes

None. This is a feature-add release with full backward compatibility.

### New Features

- **Production Tooling**: Rake tasks for deprecation audit
- **Performance Benchmarks**: Benchmark suite added
- **Error Messages**: Comprehensive error messages with suggestions
- **Debug Helper**: `Model.settings_debug` for troubleshooting
- **YAML/HTML Formats**: Documentation generation in multiple formats

### Deprecations

None in this release.

### Upgrade Steps

1. Update Gemfile: `gem 'model_settings', '~> 0.8.0'`
2. Run `bundle update model_settings`
3. Run tests: `bundle exec rspec`
4. Optional: Try new rake tasks:
   ```bash
   bundle exec rake settings:audit:deprecated
   bundle exec rake settings:docs:generate
   ```
5. Deploy

---

## Upgrading to 0.7.0

**Release Date**: 2025-11-01

### Breaking Changes

None. This is the first stable alpha release.

### New Features

- **Module Development Contract**: Full Module Registry API
- **Lifecycle Callbacks**: `on_setting_defined`, `on_settings_compiled`, etc.
- **Configuration Auto-Include**: `config.default_modules` support
- **Wave-Based Compilation**: Improved dependency resolution
- **Validation Timing**: Configurable validation execution

### Upgrade Steps

1. Update Gemfile: `gem 'model_settings', '~> 0.7.0'`
2. Run `bundle update model_settings`
3. Run tests: `bundle exec rspec`
4. Deploy

---

## Breaking Changes Policy

### Pre-1.0 (Current)

**Status**: Alpha/Beta - Breaking changes allowed

ModelSettings is currently in **pre-1.0** development (versions 0.x.x). We reserve the right to make breaking changes between minor versions.

**Why**: We have no production users yet, so we can improve the API without backwards compatibility concerns.

**What this means**:
- ✅ Breaking changes CAN occur in minor versions (0.8 → 0.9)
- ✅ API refactoring for better clarity
- ✅ Immediate deprecation removal (no deprecation period)
- ❌ No long-term support for old versions

**Upgrade recommendation**: Stay on latest version for best features and bug fixes.

### Post-1.0 (Future)

**Status**: Not yet released

Once we reach 1.0.0, we will follow **strict SemVer**:

- **Major versions** (1.x → 2.x): Breaking changes allowed
- **Minor versions** (1.1 → 1.2): New features, no breaking changes
- **Patch versions** (1.2.1 → 1.2.2): Bug fixes only

**Deprecation policy**:
- Deprecations announced at least 1 major version in advance
- Migration guides provided for all breaking changes
- Long-term support for previous major version (6 months minimum)

## Deprecation Timeline

### Current Deprecations

**None** - No features are currently deprecated in 0.9.0.

### Removed Features

**None** - No features have been removed yet.

### Future Deprecations

To be announced in future releases.

## Common Upgrade Issues

### Issue 1: Tests Failing After Upgrade

**Symptom**: RSpec tests fail with `NoMethodError` or similar

**Cause**: API changes between versions

**Solution**:
1. Read CHANGELOG for breaking changes
2. Search codebase for affected methods: `grep -r "old_method_name" app/`
3. Update method calls according to new API
4. Run tests incrementally to verify fixes

### Issue 2: Validator Signature Errors (0.9.0)

**Symptom**: `ArgumentError` when registering custom options

**Cause**: Validator signature changed in 0.9.0

**Solution**:
```ruby
# Update validator parameter order
# OLD: |setting, value|
# NEW: |value, setting, model_class|

ModelSettings::ModuleRegistry.register_option(:my_option) do |value, setting, model_class|
  # Swap the order of first two parameters
end
```

### Issue 3: Performance Regression

**Symptom**: Slower boot time after upgrade

**Cause**: Additional validations or features

**Solution**:
1. Run benchmarks: `ruby benchmark/run_all.rb`
2. Profile boot time: `time bundle exec rails runner "puts 'ready'"`
3. Check `Model.settings_debug` for complexity
4. Review cascade/sync chains for optimization

### Issue 4: Deprecation Warnings

**Symptom**: Warnings in logs about deprecated features

**Cause**: Using deprecated APIs

**Solution**:
```bash
# Find deprecated usage
bundle exec rake settings:audit:deprecated

# Review warnings
VERBOSE=1 bundle exec rspec 2>&1 | grep -i deprecat

# Update code according to deprecation messages
```

## Rollback Procedure

If upgrade causes issues:

### 1. Rollback Gem Version

```ruby
# Gemfile
gem 'model_settings', '~> 0.8.0'  # Previous version
```

```bash
bundle update model_settings
```

### 2. Rollback Database Migrations

```bash
# If new migrations were added
bundle exec rake db:rollback STEP=N
```

### 3. Rollback Code Changes

```bash
git revert <upgrade-commit>
```

### 4. Deploy Rollback

Follow normal deployment process with rolled-back version.

### 5. Report Issue

Open GitHub issue with:
- Version you upgraded from/to
- Error messages
- Steps to reproduce
- Environment details

## Testing Upgrades

### 1. Test in Isolation

```bash
# Create clean gemset
rvm gemset create model_settings_upgrade
rvm gemset use model_settings_upgrade

# Install new version
bundle install

# Run tests
bundle exec rspec
```

### 2. Test with Real Data

```bash
# Clone production database to staging
pg_dump production_db | psql staging_db

# Run upgrade in staging
bundle update model_settings
bundle exec rake db:migrate

# Verify functionality
bundle exec rails console
> User.first.settings_debug
```

### 3. Automated Testing

```ruby
# spec/upgrade_spec.rb
RSpec.describe 'ModelSettings upgrade' do
  it 'maintains backward compatibility' do
    # Test that old API still works (if not breaking change)
    user = create(:user)
    expect(user).to respond_to(:premium_enable!)
  end

  it 'supports new features' do
    # Test new API
    expect(User).to respond_to(:settings_debug)
  end
end
```

## Version Support

| Version | Status | Support Until | Notes |
|---------|--------|---------------|-------|
| 0.9.x | ✅ Current | Ongoing | Latest features |
| 0.8.x | ⚠️ Maintenance | Until 1.0 | Security fixes only |
| 0.7.x | ❌ Unsupported | 2025-11-04 | Upgrade to 0.8+ |
| < 0.7 | ❌ Unsupported | - | Upgrade to 0.9+ |

## Getting Help

- **Documentation**: [docs/](../)
- **CHANGELOG**: [CHANGELOG.md](../../CHANGELOG.md)
- **Issues**: [GitHub Issues](https://github.com/your-org/model_settings/issues)
- **Discussions**: [GitHub Discussions](https://github.com/your-org/model_settings/discussions)

## Migration Checklist

Use this checklist when upgrading:

- [ ] Review CHANGELOG for target version
- [ ] Update Gemfile
- [ ] Run `bundle update model_settings`
- [ ] Review breaking changes
- [ ] Update code for API changes
- [ ] Run full test suite locally
- [ ] Audit deprecated settings
- [ ] Test in staging environment
- [ ] Verify performance (benchmarks)
- [ ] Create database backup
- [ ] Deploy to production
- [ ] Monitor error rates
- [ ] Verify key functionality
- [ ] Update documentation (if needed)
