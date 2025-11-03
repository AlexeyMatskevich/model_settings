# Production Deployment Guide

This guide covers best practices for deploying ModelSettings to production environments.

## Table of Contents

- [Pre-Deployment Checklist](#pre-deployment-checklist)
- [Database Migrations](#database-migrations)
- [Performance Optimization](#performance-optimization)
- [Monitoring and Observability](#monitoring-and-observability)
- [Security Hardening](#security-hardening)
- [Rollback Strategy](#rollback-strategy)
- [Common Issues](#common-issues)

## Pre-Deployment Checklist

### Code Quality

- [ ] All tests passing: `bundle exec rspec` (should show 1400+ examples, 0 failures)
- [ ] Linter clean: `bundle exec standardrb` (0 offenses)
- [ ] No deprecated settings in use: `bundle exec rake settings:audit:deprecated`
- [ ] Code review completed
- [ ] Security audit passed (see [SECURITY.md](../../SECURITY.md))

### Documentation

- [ ] CHANGELOG.md updated with all changes
- [ ] Breaking changes documented
- [ ] Migration guide prepared (if needed)
- [ ] API documentation updated

### Database

- [ ] All migrations tested in staging
- [ ] Rollback migrations prepared
- [ ] Database backups verified
- [ ] Column types match setting definitions
- [ ] Indexes added for frequently queried columns

### Performance

- [ ] Benchmark tests run: `ruby benchmark/run_all.rb`
- [ ] No N+1 queries in setting access
- [ ] Settings compilation time acceptable (< 100ms per model)
- [ ] Cache strategy implemented (if needed)

### Security

- [ ] Strong Parameters configured in all controllers
- [ ] Authorization modules included (Pundit/ActionPolicy/Roles)
- [ ] Cascade security boundaries validated
- [ ] HTTPS enforced
- [ ] Secrets management configured

## Database Migrations

### Column Adapter Migrations

```ruby
class AddSettingsToUsers < ActiveRecord::Migration[7.0]
  def change
    # Boolean settings
    add_column :users, :notifications_enabled, :boolean, default: false, null: false
    add_column :users, :dark_mode, :boolean, default: false, null: false

    # Add index for frequently queried settings
    add_index :users, :notifications_enabled
  end
end
```

### JSON Adapter Migrations

```ruby
class AddSettingsJsonToUsers < ActiveRecord::Migration[7.0]
  def change
    # PostgreSQL JSONB (recommended)
    add_column :users, :preferences, :jsonb, default: {}, null: false

    # MySQL JSON
    # add_column :users, :preferences, :json

    # Add GIN index for PostgreSQL JSONB queries
    add_index :users, :preferences, using: :gin
  end
end
```

### StoreModel Adapter Migrations

```ruby
class AddConfigToUsers < ActiveRecord::Migration[7.0]
  def change
    add_column :users, :settings_config, :jsonb, default: {}, null: false
    add_index :users, :settings_config, using: :gin
  end
end
```

### Migration Best Practices

1. **Always provide defaults**: Prevents NULL values
2. **Add indexes**: For frequently queried boolean settings
3. **Use JSONB over JSON**: Better performance in PostgreSQL
4. **Test rollbacks**: Ensure `down` migrations work
5. **Batch operations**: For large tables, use batching:

```ruby
class AddSettingsToUsers < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!  # Required for concurrent index

  def up
    add_column :users, :premium, :boolean, default: false
    add_index :users, :premium, algorithm: :concurrently
  end

  def down
    remove_index :users, :premium
    remove_column :users, :premium
  end
end
```

## Performance Optimization

### 1. Eager Load Settings Compilation

```ruby
# config/application.rb
config.after_initialize do
  # Compile settings for all models at boot time
  Rails.application.eager_load! if Rails.env.production?

  # Force settings compilation
  ActiveRecord::Base.descendants.each do |model|
    model.compile_settings! if model.respond_to?(:compile_settings!)
  end
end
```

### 2. Cache Settings Metadata

```ruby
# If you're reading setting metadata frequently
class User < ApplicationRecord
  include ModelSettings::DSL

  # Cache the settings list
  def self.available_settings
    @available_settings ||= settings.keys.freeze
  end
end
```

### 3. Optimize Cascade Chains

```ruby
# ❌ BAD: Deep cascade (10+ levels)
setting :level_0, cascade: {enable: true} do
  setting :level_1, cascade: {enable: true} do
    setting :level_2, cascade: {enable: true} do
      # ... 7 more levels
    end
  end
end

# ✅ GOOD: Shallow cascade (< 5 levels)
setting :premium, cascade: {enable: true} do
  setting :api_access
  setting :priority_support
end
```

### 4. Use Column Adapter for High-Traffic Settings

```ruby
# ✅ BEST: Column adapter for frequently read settings
setting :notifications_enabled, type: :column

# ⚠️ OK: JSON for less frequently accessed settings
setting :preferences, type: :json, storage: {column: :prefs_json} do
  setting :theme
  setting :language
end
```

### 5. Batch Updates

```ruby
# ❌ BAD: N updates
users.each do |user|
  user.update(premium: true)
end

# ✅ GOOD: Single query
User.where(id: user_ids).update_all(premium: true)
```

## Monitoring and Observability

### 1. Add Instrumentation

```ruby
# config/initializers/model_settings_instrumentation.rb
ActiveSupport::Notifications.subscribe('model_settings.compilation') do |name, start, finish, id, payload|
  duration = (finish - start) * 1000
  Rails.logger.info "[ModelSettings] Compiled #{payload[:model]} in #{duration.round(2)}ms"

  # Send to monitoring service
  StatsD.increment('model_settings.compilation', tags: ["model:#{payload[:model]}"])
  StatsD.histogram('model_settings.compilation_time', duration, tags: ["model:#{payload[:model]}"])
end
```

### 2. Monitor Deprecated Settings Usage

```ruby
# In CI/CD pipeline
bundle exec rake settings:audit:deprecated
if [ $? -ne 0 ]; then
  echo "ERROR: Deprecated settings in use!"
  exit 1
fi
```

### 3. Track Setting Changes

```ruby
# Use callbacks for audit logging
class User < ApplicationRecord
  include ModelSettings::DSL

  setting :billing_enabled,
          type: :column,
          after_change: -> (user, old_value, new_value) {
            AuditLog.create!(
              user: user,
              action: "billing_enabled_changed",
              old_value: old_value,
              new_value: new_value
            )
          }
end
```

### 4. Error Tracking

```ruby
# config/initializers/model_settings_errors.rb
module ModelSettings
  class Error < StandardError
    def initialize(message)
      super(message)
      # Report to error tracking service
      Sentry.capture_exception(self) if defined?(Sentry)
    end
  end
end
```

## Security Hardening

### 1. Enforce Authorization

```ruby
# app/controllers/users_controller.rb
class UsersController < ApplicationController
  before_action :authenticate_user!

  def update
    @user = User.find(params[:id])
    authorize @user  # Pundit/ActionPolicy check

    # Get allowed settings from policy
    policy = policy(@user)
    allowed = policy.permitted_settings

    # Filter with Strong Parameters
    permitted = params.require(:user).permit(*allowed)

    if @user.update(permitted)
      redirect_to @user, notice: 'Settings updated'
    else
      render :edit
    end
  end
end
```

### 2. Validate Cascade Security

```ruby
# Ensure cascades don't cross security boundaries
class User < ApplicationRecord
  include ModelSettings::DSL
  include ModelSettings::Modules::Pundit

  # ✅ SAFE: Same authorization level
  setting :premium,
          authorize_with: :admin?,
          cascade: {enable: true} do
    setting :api_access, authorize_with: :admin?
    setting :priority_support, authorize_with: :admin?
  end

  # ❌ UNSAFE: Mixed authorization
  # setting :user_pref,
  #         authorize_with: :user?,
  #         cascade: {enable: true} do
  #   setting :admin_panel, authorize_with: :admin?  # NEVER DO THIS
  # end
end
```

### 3. Sanitize Callbacks

```ruby
# Ensure callbacks don't expose sensitive data
setting :notifications_enabled,
        after_enable: -> (user) {
          # ✅ SAFE: Only notify
          NotificationMailer.welcome(user).deliver_later

          # ❌ UNSAFE: Exposes sensitive data
          # Rails.logger.info "User #{user.email} password: #{user.encrypted_password}"
        }
```

### 4. Use HTTPS Only

```ruby
# config/environments/production.rb
config.force_ssl = true
config.ssl_options = {
  hsts: {
    expires: 1.year,
    subdomains: true,
    preload: true
  }
}
```

## Rollback Strategy

### 1. Prepare Rollback Migrations

```ruby
# Always test the `down` migration
class AddPremiumToUsers < ActiveRecord::Migration[7.0]
  def up
    add_column :users, :premium, :boolean, default: false
  end

  def down
    remove_column :users, :premium
  end
end

# Test rollback in staging
# bundle exec rake db:migrate
# bundle exec rake db:rollback
```

### 2. Feature Flags

```ruby
# Use feature flags for gradual rollout
class User < ApplicationRecord
  include ModelSettings::DSL

  if FeatureFlag.enabled?(:new_premium_features)
    setting :premium_v2, type: :column, default: false
  else
    setting :premium, type: :column, default: false
  end
end
```

### 3. Database Backup Before Deploy

```bash
# Production deployment script
#!/bin/bash
set -e

# 1. Backup database
pg_dump $DATABASE_URL > backups/pre_deploy_$(date +%Y%m%d_%H%M%S).sql

# 2. Run migrations
bundle exec rake db:migrate

# 3. Restart application
sudo systemctl restart app

# 4. Verify deployment
curl -f https://app.example.com/health || (
  echo "Health check failed! Rolling back..."
  bundle exec rake db:rollback
  sudo systemctl restart app
  exit 1
)
```

### 4. Canary Deployments

```ruby
# Deploy to subset of servers first
# config/deploy/production.rb (Capistrano example)
set :stages, %w[canary production]
set :default_stage, 'canary'

# Monitor canary for issues before full rollout
```

## Common Issues

### Issue 1: Settings Not Compiling

**Symptom**: `NoMethodError: undefined method 'setting_name'`

**Cause**: Settings not compiled before use

**Solution**:
```ruby
# Ensure compilation in production
config.after_initialize do
  Rails.application.eager_load!
  ActiveRecord::Base.descendants.each do |model|
    model.compile_settings! if model.respond_to?(:compile_settings!)
  end
end
```

### Issue 2: Slow Boot Time

**Symptom**: Application takes > 10 seconds to boot

**Cause**: Too many settings or complex dependency graphs

**Solution**:
```ruby
# Profile settings compilation
User.settings_debug  # Shows compilation statistics

# Optimize:
# - Reduce number of settings
# - Simplify cascade chains
# - Remove unnecessary syncs
```

### Issue 3: Authorization Not Working

**Symptom**: Users can modify settings they shouldn't

**Cause**: Missing authorization checks in controller

**Solution**:
```ruby
# Always authorize before update
def update
  @user = User.find(params[:id])
  authorize @user  # ADD THIS

  # ... rest of update logic
end
```

### Issue 4: Migration Fails in Production

**Symptom**: `PG::UndefinedColumn: column does not exist`

**Cause**: Migration order issue or missing migration

**Solution**:
```bash
# Check pending migrations
bundle exec rake db:migrate:status

# Run migrations
bundle exec rake db:migrate

# Verify database schema matches
bundle exec rake db:schema:dump
git diff db/schema.rb
```

### Issue 5: JSON Column Performance

**Symptom**: Slow queries on JSON columns

**Cause**: Missing GIN index

**Solution**:
```ruby
# Add GIN index for JSONB
add_index :users, :preferences, using: :gin

# Or for specific keys
add_index :users, "(preferences -> 'theme')", using: :btree, name: 'index_users_on_theme'
```

## Health Checks

```ruby
# app/controllers/health_controller.rb
class HealthController < ApplicationController
  skip_before_action :authenticate_user!

  def show
    checks = {
      database: check_database,
      settings: check_settings_compilation,
      deprecated: check_deprecated_settings
    }

    if checks.values.all?
      render json: {status: 'ok', checks: checks}, status: :ok
    else
      render json: {status: 'error', checks: checks}, status: :service_unavailable
    end
  end

  private

  def check_database
    ActiveRecord::Base.connection.execute('SELECT 1')
    true
  rescue
    false
  end

  def check_settings_compilation
    User.respond_to?(:settings) && User.settings.any?
  rescue
    false
  end

  def check_deprecated_settings
    auditor = ModelSettings::DeprecationAuditor.new
    !auditor.generate_report.has_active_usage?
  rescue
    true  # Don't fail health check on audit errors
  end
end
```

## Production Configuration

```ruby
# config/environments/production.rb
Rails.application.configure do
  # Force SSL
  config.force_ssl = true

  # Eager load (compiles settings at boot)
  config.eager_load = true

  # Log level
  config.log_level = :info

  # Asset compilation
  config.assets.compile = false
  config.assets.digest = true

  # Cache
  config.cache_store = :redis_cache_store, {
    url: ENV['REDIS_URL'],
    expires_in: 1.hour
  }
end
```

## Deployment Checklist

### Pre-Deployment
- [ ] Run full test suite locally
- [ ] Run benchmarks to verify performance
- [ ] Audit deprecated settings
- [ ] Review security checklist
- [ ] Create database backup
- [ ] Review rollback plan

### Deployment
- [ ] Deploy to staging first
- [ ] Run migrations in staging
- [ ] Verify staging works correctly
- [ ] Deploy to canary (if available)
- [ ] Monitor canary for 30 minutes
- [ ] Deploy to production
- [ ] Run migrations in production
- [ ] Verify health checks

### Post-Deployment
- [ ] Monitor error rates
- [ ] Check application logs
- [ ] Verify key features work
- [ ] Monitor performance metrics
- [ ] Update documentation
- [ ] Notify team of deployment

## Support

For production issues:
1. Check logs: `tail -f log/production.log`
2. Check health endpoint: `curl https://app.example.com/health`
3. Review error tracking: Sentry/Honeybadger
4. Consult [troubleshooting guide](../guides/troubleshooting.md)
5. Report issues: [GitHub Issues](https://github.com/your-org/model_settings/issues)
