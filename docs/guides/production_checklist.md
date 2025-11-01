# Production Checklist

This checklist ensures ModelSettings is properly configured and ready for production deployment.

## Pre-Production Checklist

Use this checklist before deploying ModelSettings to production:

### 1. Database Setup ✅

#### Migrations

- [ ] All migrations have been run successfully
- [ ] Settings columns exist in database
- [ ] JSONB columns created for JSON/StoreModel adapters
- [ ] No pending migrations (`rails db:migrate:status`)

```bash
# Check migration status
rails db:migrate:status

# Run migrations
rails db:migrate
```

#### Indexes

- [ ] Add indexes for frequently queried settings columns
- [ ] Add GIN indexes for JSONB columns (PostgreSQL)
- [ ] Review query patterns and optimize

```ruby
# Example: Add index for frequently queried boolean setting
class AddIndexToUsersNotificationsEnabled < ActiveRecord::Migration[7.0]
  def change
    add_index :users, :notifications_enabled
  end
end

# Example: Add GIN index for JSONB column (PostgreSQL)
class AddGinIndexToSettings < ActiveRecord::Migration[7.0]
  def change
    add_index :users, :settings_json, using: :gin
  end
end
```

#### Data Integrity

- [ ] All existing records have valid default values
- [ ] Boolean settings don't have invalid values
- [ ] No NULL values where defaults are expected
- [ ] Run data validation check

```ruby
# Check for invalid boolean values
User.find_each do |user|
  User._settings.each do |setting|
    value = user.public_send(setting.name)
    unless value.nil? || value == true || value == false
      puts "Invalid value for #{user.id}.#{setting.name}: #{value.inspect}"
    end
  end
end
```

### 2. Configuration ✅

#### Settings Compilation

- [ ] All settings are compiled on Rails boot
- [ ] No cyclic sync errors during compilation
- [ ] Dependency engine validates successfully

```ruby
# Check compilation in Rails console
User.compile_settings!
# Should not raise errors
```

#### Module Configuration

- [ ] Authorization modules configured correctly
- [ ] Only ONE authorization module active per model
- [ ] I18n configured if using internationalization
- [ ] Default modules set in initializer (if needed)

```ruby
# config/initializers/model_settings.rb
ModelSettings.configure do |config|
  # Set default modules for all models
  config.default_modules = [:i18n]

  # Configure authorization inheritance
  config.inherit_authorization = true
end
```

#### Environment Variables

- [ ] No sensitive data in setting defaults
- [ ] Environment-specific settings use ENV vars
- [ ] Credentials configured correctly

### 3. Security ✅

#### Authorization

- [ ] Authorization policies defined for all sensitive settings
- [ ] Pundit/ActionPolicy policies tested
- [ ] Role-based access control configured
- [ ] Admin-only settings protected

```ruby
# Example: Pundit policy
class UserPolicy < ApplicationPolicy
  def update_billing_enabled?
    user.admin?
  end
end
```

#### Input Validation

- [ ] All settings have proper validation
- [ ] Custom validators tested
- [ ] Type checking enabled (boolean_value validator)
- [ ] No possibility of type confusion attacks

#### Audit Trail

- [ ] Sensitive setting changes logged
- [ ] PaperTrail or similar gem configured (optional)
- [ ] Audit log retention policy defined

```ruby
# Example: Track changes with PaperTrail
class User < ApplicationRecord
  include ModelSettings::DSL
  has_paper_trail on: [:update], only: [:billing_enabled, :premium_mode]
end
```

### 4. Performance ✅

#### Query Optimization

- [ ] No N+1 queries when loading settings
- [ ] Proper eager loading configured
- [ ] Indexes added for query patterns
- [ ] Database query performance tested

```ruby
# Good: Settings loaded from attributes (no queries)
user.notifications_enabled  # Just attribute access

# Bad: Would be N+1 (but ModelSettings doesn't do this)
# users.each { |u| u.notifications_enabled }  # Still just attributes
```

#### Caching

- [ ] Consider caching settings if queried frequently
- [ ] Redis configured for session/cache if needed
- [ ] Cache invalidation strategy defined

```ruby
# Example: Cache expensive queries
def user_settings_summary(user)
  Rails.cache.fetch("user_settings/#{user.id}/summary", expires_in: 1.hour) do
    {
      notifications: user.notifications_enabled,
      premium: user.premium_mode,
      features: user.features_summary
    }
  end
end
```

#### Memory Usage

- [ ] Settings don't cause memory bloat
- [ ] JSONB columns not storing excessive data
- [ ] StoreModel objects reasonable size

### 5. Testing ✅

#### Test Coverage

- [ ] All settings have unit tests
- [ ] Integration tests for critical workflows
- [ ] Authorization tests for protected settings
- [ ] Callback tests for side effects
- [ ] Cascade/sync tests for dependencies

```ruby
# Minimum test coverage
RSpec.describe User, type: :model do
  describe "settings" do
    it "defaults to false" do
      user = User.new
      expect(user.notifications_enabled).to eq(false)
    end

    it "can be enabled" do
      user = create(:user)
      user.notifications_enabled_enable!
      expect(user.reload.notifications_enabled).to eq(true)
    end
  end
end
```

#### CI/CD Pipeline

- [ ] Tests run on every commit
- [ ] No flaky tests
- [ ] Test database properly seeded
- [ ] Deprecation warnings checked

```yaml
# Example: GitHub Actions
- name: Run RSpec
  run: bundle exec rspec

- name: Check for deprecation warnings
  run: |
    rails runner "puts ModelSettings::DeprecationAuditor.new.generate_report"
```

### 6. Monitoring & Observability ✅

#### Logging

- [ ] Setting changes logged appropriately
- [ ] Error logging configured
- [ ] Log level appropriate for environment
- [ ] Sensitive data not logged

```ruby
# Example: Log important setting changes
class User < ApplicationRecord
  include ModelSettings::DSL

  setting :billing_enabled,
    type: :column,
    after_enable: -> { Rails.logger.info("Billing enabled for user #{id}") },
    after_disable: -> { Rails.logger.info("Billing disabled for user #{id}") }
end
```

#### Metrics

- [ ] Track setting usage metrics
- [ ] Monitor setting change frequency
- [ ] Alert on unusual patterns
- [ ] Dashboard for key settings

```ruby
# Example: Track metrics with Datadog/NewRelic
setting :premium_mode,
  after_enable: -> { StatsD.increment("user.premium_mode.enabled") },
  after_disable: -> { StatsD.decrement("user.premium_mode.enabled") }
```

#### Error Tracking

- [ ] Sentry/Bugsnag configured
- [ ] Callback errors tracked
- [ ] Validation errors monitored
- [ ] Error rates baselined

### 7. Deployment Strategy ✅

#### Zero-Downtime Deployment

- [ ] Database migrations run before code deploy
- [ ] Backward-compatible changes only
- [ ] No breaking changes to setting APIs
- [ ] Rollback plan documented

```bash
# Safe deployment order
1. Run migrations (add columns)
2. Deploy new code
3. Remove old columns (next release)
```

#### Feature Flags

- [ ] Use settings as feature flags
- [ ] Gradual rollout strategy
- [ ] Rollback capability
- [ ] A/B testing infrastructure (if needed)

```ruby
# Example: Gradual rollout
class User < ApplicationRecord
  setting :new_ui_enabled, type: :column, default: false

  def enable_new_ui_for_cohort!
    return if new_ui_enabled?

    # Enable for 10% of users
    if id % 10 == 0
      update!(new_ui_enabled: true)
    end
  end
end
```

### 8. Documentation ✅

#### Internal Documentation

- [ ] Settings documented with descriptions
- [ ] Authorization rules documented
- [ ] Callback side effects documented
- [ ] Dependency relationships documented

```ruby
# Good: Well-documented setting
setting :billing_enabled,
  type: :column,
  default: false,
  description: "Enables billing features and invoice generation",
  metadata: {
    category: "billing",
    requires: "stripe_subscription",
    affects: "invoice generation, payment processing"
  }
```

#### Generated Documentation

- [ ] Run documentation generator
- [ ] Review generated docs for accuracy
- [ ] Publish to internal wiki/docs site
- [ ] Keep docs updated

```ruby
# Generate documentation
docs = User.settings_documentation(format: :markdown)
File.write("docs/user_settings.md", docs)
```

#### Team Training

- [ ] Team familiar with ModelSettings API
- [ ] Best practices documented
- [ ] Code review guidelines established
- [ ] Onboarding docs updated

### 9. Deprecation Management ✅

#### Deprecation Audit

- [ ] Run deprecation audit on production data
- [ ] No actively used deprecated settings
- [ ] Migration plan for deprecated features
- [ ] Timeline for removal documented

```bash
# Run deprecation audit
rails settings:audit:deprecated

# Should show:
# ✓ No deprecated settings in active use
```

#### Migration Strategy

- [ ] Deprecated settings have clear migration path
- [ ] Users notified of deprecations
- [ ] Grace period defined (e.g., 6 months)
- [ ] Removal scheduled

### 10. Backup & Recovery ✅

#### Backup Strategy

- [ ] Database backups include settings tables
- [ ] Backup frequency appropriate (daily/hourly)
- [ ] Backup restoration tested
- [ ] Point-in-time recovery available

#### Disaster Recovery

- [ ] Recovery procedure documented
- [ ] RTO (Recovery Time Objective) defined
- [ ] RPO (Recovery Point Objective) defined
- [ ] DR drills scheduled

### 11. Performance Benchmarks ✅

#### Baseline Metrics

- [ ] Setting read performance measured
- [ ] Setting write performance measured
- [ ] Cascade/sync performance measured
- [ ] Memory usage baselined

```bash
# Run benchmarks
bundle exec ruby benchmark/run_all.rb

# Results should be acceptable:
# - Definition: < 1ms per setting
# - Read: < 10μs per setting
# - Write: < 1ms per setting
```

#### Load Testing

- [ ] Load tests include setting operations
- [ ] Concurrent write handling tested
- [ ] Database connection pool sized correctly
- [ ] Performance under load acceptable

### 12. Compliance & Legal ✅

#### Data Privacy

- [ ] GDPR compliance checked (if applicable)
- [ ] User consent for data processing
- [ ] Data retention policies enforced
- [ ] Right to deletion implemented

#### Audit Compliance

- [ ] Audit logs for compliance requirements
- [ ] Change tracking for regulated settings
- [ ] Access logs maintained
- [ ] Compliance reports available

## Production Deployment Checklist

Quick checklist for deployment day:

### Pre-Deployment

- [ ] All tests passing in CI
- [ ] Staging environment tested
- [ ] Database migrations reviewed
- [ ] Rollback plan prepared
- [ ] Team notified of deployment
- [ ] Maintenance window scheduled (if needed)

### During Deployment

- [ ] Stop background jobs (if needed)
- [ ] Run database migrations
- [ ] Deploy application code
- [ ] Restart application servers
- [ ] Clear caches (if needed)
- [ ] Resume background jobs

### Post-Deployment

- [ ] Smoke tests pass
- [ ] Settings working correctly
- [ ] No error spikes in logs
- [ ] Metrics show normal behavior
- [ ] User reports monitored
- [ ] Rollback if issues detected

## Monitoring Dashboard

### Key Metrics to Monitor

```ruby
# Example metrics to track
- Setting change rate (changes/hour)
- Setting validation errors
- Callback failures
- Authorization denials
- Query performance (p50, p95, p99)
- Memory usage
- Error rates
```

### Alerts to Configure

```ruby
# Example alerts
- High validation error rate (> 1%)
- Callback failure rate (> 0.1%)
- Query latency spike (p95 > 100ms)
- Unusual setting change patterns
- Authorization denial spike
```

## Common Production Issues

### Issue: Setting Changes Not Persisting

**Symptoms**: Setting changes revert after reload

**Causes**:
- Validation errors (check logs)
- Callback failures (check logs)
- Transaction rollback (check surrounding code)

**Fix**:
```ruby
# Check for validation errors
user.notifications_enabled = true
unless user.valid?
  puts user.errors.full_messages
end

# Check for callback errors
# Enable DEBUG_VALIDATION=1 to see callback errors
```

### Issue: Slow Setting Queries

**Symptoms**: Settings queries taking > 100ms

**Causes**:
- Missing indexes
- N+1 queries in related code
- Large JSONB documents

**Fix**:
```ruby
# Add indexes
add_index :users, :notifications_enabled

# For JSONB (PostgreSQL)
add_index :users, :settings_json, using: :gin
```

### Issue: Memory Usage Growing

**Symptoms**: Application memory usage increases over time

**Causes**:
- Large JSONB documents
- Memory leaks in callbacks
- Caching issues

**Fix**:
```ruby
# Review JSONB document sizes
User.pluck(:settings_json).map(&:to_s).map(&:size).max

# Should be < 10KB typically
```

## Getting Help

### Resources

- **Documentation**: `docs/` directory
- **Security**: `docs/security/SECURITY_AUDIT.md`
- **Performance**: `docs/guides/performance.md`
- **Error Messages**: `docs/guides/error_messages.md`

### Support Channels

- GitHub Issues: Bug reports and feature requests
- GitHub Discussions: Questions and discussions
- Security Issues: Private security advisories

## Version-Specific Notes

### v0.8.0 (Current)

- ✅ Security audit completed
- ✅ Error messages improved
- ✅ Performance benchmarks added
- ✅ Production hardening complete

### Upgrading from v0.7.0

- No breaking changes
- Run `rails settings:audit:deprecated` to check for deprecated settings
- Review new error messages (more detailed)
- Review security audit findings

## Final Checklist

Before marking production-ready:

- [ ] All sections of this checklist completed
- [ ] Security audit passed
- [ ] Performance benchmarks acceptable
- [ ] Team trained and ready
- [ ] Documentation complete
- [ ] Monitoring configured
- [ ] Backup/recovery tested
- [ ] Rollback plan ready

**Status**: ⬜ Not Ready / ✅ Production Ready

---

**Last Updated**: 2025-11-02
**Version**: 0.8.0
**Review Date**: Before v1.0.0 release
