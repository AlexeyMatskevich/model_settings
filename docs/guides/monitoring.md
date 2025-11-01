# Monitoring Guide

Guide for monitoring ModelSettings in production.

## Overview

Effective monitoring helps you:
- Detect issues early
- Track setting usage patterns
- Optimize performance
- Ensure system health

## Key Metrics to Monitor

### 1. Setting Change Rate

Track how frequently settings are changed.

```ruby
# Track with StatsD/Datadog
class User < ApplicationRecord
  include ModelSettings::DSL

  setting :notifications_enabled,
    type: :column,
    after_enable: -> { StatsD.increment('settings.notifications.enabled') },
    after_disable: -> { StatsD.increment('settings.notifications.disabled') }
end

# Alert if rate changes dramatically
# Example: > 100 changes/minute (may indicate issue)
```

### 2. Validation Errors

Monitor validation failures.

```ruby
# Track validation errors
class User < ApplicationRecord
  after_validation :track_validation_errors

  private

  def track_validation_errors
    if errors.any?
      errors.details.each do |attribute, details|
        details.each do |error|
          StatsD.increment("validation.error.#{attribute}.#{error[:error]}")
        end
      end
    end
  end
end

# Alert if error rate > 1%
```

### 3. Callback Failures

Track callback execution failures.

```ruby
# Enable callback error tracking
# Add to config/initializers/model_settings.rb

Rails.application.config.after_initialize do
  ActiveSupport::Notifications.subscribe('callback.failed') do |*args|
    event = ActiveSupport::Notifications::Event.new(*args)

    # Log to error tracking service
    Sentry.capture_message("Setting callback failed", extra: {
      setting: event.payload[:setting],
      callback: event.payload[:callback],
      error: event.payload[:error]
    })

    # Track metric
    StatsD.increment('settings.callback.failed',
      tags: ["setting:#{event.payload[:setting]}"]
    )
  end
end
```

### 4. Query Performance

Monitor database query times.

```ruby
# Track slow queries with Scout/NewRelic
# Automatic with APM tools

# Or manually track
ActiveSupport::Notifications.subscribe('sql.active_record') do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)

  if event.duration > 100 # ms
    Rails.logger.warn("Slow query: #{event.payload[:sql]} (#{event.duration}ms)")
    StatsD.timing('database.query.slow', event.duration)
  end
end

# Alert if p95 > 100ms
```

### 5. Memory Usage

Track memory consumption.

```ruby
# Monitor with system tools
# - Heroku metrics
# - NewRelic
# - Scout

# Alert if memory > 512MB per process
```

## Monitoring Tools

### Application Performance Monitoring (APM)

#### New Relic

```ruby
# config/initializers/newrelic.rb
if Rails.env.production?
  require 'newrelic_rpm'

  # Track custom events
  ActiveSupport::Notifications.subscribe('setting.changed') do |*args|
    event = ActiveSupport::Notifications::Event.new(*args)

    NewRelic::Agent.record_custom_event('SettingChanged', {
      user_id: event.payload[:user_id],
      setting: event.payload[:setting],
      old_value: event.payload[:old_value],
      new_value: event.payload[:new_value]
    })
  end

  # Track setting operations
  NewRelic::Agent.add_method_tracer('User#notifications_enabled=', 'Custom/Settings/Write')
end
```

#### Scout APM

```ruby
# config/initializers/scout.rb
if Rails.env.production?
  # Automatically tracks queries and performance
  # No additional configuration needed for basic monitoring
end
```

### Error Tracking

#### Sentry

```ruby
# config/initializers/sentry.rb
if Rails.env.production?
  Sentry.init do |config|
    config.dsn = ENV['SENTRY_DSN']
    config.breadcrumbs_logger = [:active_support_logger, :http_logger]

    # Track setting changes as breadcrumbs
    config.before_breadcrumb = lambda do |breadcrumb, hint|
      if breadcrumb.category == 'setting.changed'
        breadcrumb.data = hint[:data]
      end
      breadcrumb
    end
  end

  # Track callback errors
  ActiveSupport::Notifications.subscribe('callback.failed') do |*args|
    event = ActiveSupport::Notifications::Event.new(*args)
    Sentry.capture_exception(event.payload[:error])
  end
end
```

### Metrics (StatsD/Datadog)

```ruby
# config/initializers/statsd.rb
if Rails.env.production?
  require 'statsd-instrument'

  StatsD.backend = StatsD::Instrument::Backends::DatadogBackend.new(
    ENV['STATSD_HOST'] || 'localhost',
    8125
  )

  # Track setting metrics
  module ModelSettings::Metrics
    extend ActiveSupport::Concern

    included do
      after_save :track_setting_changes
    end

    private

    def track_setting_changes
      self.class._settings.each do |setting|
        if saved_change_to_attribute?(setting.name)
          old_val, new_val = saved_change_to_attribute(setting.name)

          StatsD.increment('settings.changed', tags: [
            "model:#{self.class.name.underscore}",
            "setting:#{setting.name}",
            "from:#{old_val}",
            "to:#{new_val}"
          ])
        end
      end
    end
  end

  # Include in models
  ActiveSupport.on_load(:active_record) do
    include ModelSettings::Metrics
  end
end
```

### Logging

#### Structured Logging

```ruby
# config/initializers/logging.rb
if Rails.env.production?
  # Use Lograge for structured logs
  Rails.application.configure do
    config.lograge.enabled = true
    config.lograge.formatter = Lograge::Formatters::Json.new

    config.lograge.custom_options = lambda do |event|
      {
        time: Time.current,
        host: Socket.gethostname,
        process_id: Process.pid
      }
    end
  end

  # Log setting changes
  ActiveSupport::Notifications.subscribe('setting.changed') do |*args|
    event = ActiveSupport::Notifications::Event.new(*args)

    Rails.logger.info({
      event: 'setting_changed',
      user_id: event.payload[:user_id],
      setting: event.payload[:setting],
      old_value: event.payload[:old_value],
      new_value: event.payload[:new_value],
      timestamp: Time.current.iso8601
    }.to_json)
  end
end
```

## Dashboards

### Grafana Dashboard Example

```yaml
# grafana_dashboard.json
{
  "dashboard": {
    "title": "ModelSettings Monitoring",
    "panels": [
      {
        "title": "Setting Changes Rate",
        "targets": [
          {
            "expr": "rate(settings_changed_total[5m])"
          }
        ]
      },
      {
        "title": "Validation Error Rate",
        "targets": [
          {
            "expr": "rate(validation_error_total[5m])"
          }
        ]
      },
      {
        "title": "Callback Failures",
        "targets": [
          {
            "expr": "increase(callback_failed_total[1h])"
          }
        ]
      },
      {
        "title": "Query Performance (p95)",
        "targets": [
          {
            "expr": "histogram_quantile(0.95, database_query_duration_ms)"
          }
        ]
      }
    ]
  }
}
```

### Datadog Dashboard

```ruby
# Create dashboard via API
require 'dogapi'

dog = Dogapi::Client.new(ENV['DATADOG_API_KEY'])

dashboard = {
  title: 'ModelSettings Monitoring',
  description: 'Monitor setting changes and performance',
  widgets: [
    {
      definition: {
        title: 'Setting Changes',
        type: 'timeseries',
        requests: [{
          q: 'sum:settings.changed{*}.as_rate()'
        }]
      }
    },
    {
      definition: {
        title: 'Top Changed Settings',
        type: 'toplist',
        requests: [{
          q: 'top(sum:settings.changed{*} by {setting}, 10, "sum", "desc")'
        }]
      }
    }
  ]
}

dog.create_dashboard(dashboard)
```

## Alerts

### Critical Alerts

#### 1. High Validation Error Rate

```yaml
# Alert: Validation errors > 1%
name: "High Settings Validation Error Rate"
condition: |
  (validation_error_count / setting_change_count) > 0.01
severity: critical
notification: pagerduty, slack
```

#### 2. Callback Failures

```yaml
# Alert: Any callback failure
name: "Setting Callback Failed"
condition: |
  callback_failed_count > 0
severity: warning
notification: slack
```

#### 3. Slow Queries

```yaml
# Alert: Query p95 > 100ms
name: "Slow Settings Query"
condition: |
  database_query_p95 > 100
severity: warning
notification: slack
```

### Warning Alerts

#### 1. Unusual Change Rate

```yaml
# Alert: Change rate 2x higher than normal
name: "Unusual Setting Change Rate"
condition: |
  setting_change_rate > (avg(setting_change_rate[1d]) * 2)
severity: warning
notification: slack
```

#### 2. Memory Usage

```yaml
# Alert: Memory > 512MB
name: "High Memory Usage"
condition: |
  process_memory_mb > 512
severity: warning
notification: slack
```

## Health Checks

### Application Health Endpoint

```ruby
# config/routes.rb
get '/health', to: 'health#index'
get '/health/settings', to: 'health#settings'

# app/controllers/health_controller.rb
class HealthController < ApplicationController
  skip_before_action :verify_authenticity_token

  def index
    render json: {
      status: 'ok',
      timestamp: Time.current,
      version: ModelSettings::VERSION
    }
  rescue => e
    render json: {
      status: 'error',
      error: e.message
    }, status: 503
  end

  def settings
    checks = {
      compilation: check_compilation,
      validation: check_validation,
      persistence: check_persistence
    }

    all_ok = checks.values.all? { |c| c[:status] == 'ok' }

    render json: {
      status: all_ok ? 'ok' : 'degraded',
      checks: checks,
      timestamp: Time.current
    }, status: all_ok ? 200 : 503
  end

  private

  def check_compilation
    User.compile_settings!
    {status: 'ok'}
  rescue => e
    {status: 'error', error: e.message}
  end

  def check_validation
    user = User.new
    user.notifications_enabled = "invalid"
    user.valid?

    if user.errors.any?
      {status: 'ok', message: 'Validation working'}
    else
      {status: 'error', message: 'Validation not catching errors'}
    end
  rescue => e
    {status: 'error', error: e.message}
  end

  def check_persistence
    user = User.first || User.create!
    original = user.notifications_enabled
    user.update!(notifications_enabled: !original)
    user.reload

    if user.notifications_enabled == !original
      {status: 'ok'}
    else
      {status: 'error', message: 'Settings not persisting'}
    end
  rescue => e
    {status: 'error', error: e.message}
  end
end
```

### Kubernetes Probes

```yaml
# kubernetes/deployment.yaml
apiVersion: apps/v1
kind: Deployment
spec:
  template:
    spec:
      containers:
        - name: app
          livenessProbe:
            httpGet:
              path: /health
              port: 3000
            initialDelaySeconds: 30
            periodSeconds: 10
            timeoutSeconds: 5
            failureThreshold: 3

          readinessProbe:
            httpGet:
              path: /health/settings
              port: 3000
            initialDelaySeconds: 10
            periodSeconds: 5
            timeoutSeconds: 3
            failureThreshold: 2
```

## Audit Trail

### Track All Setting Changes

```ruby
# app/models/concerns/setting_audit_trail.rb
module SettingAuditTrail
  extend ActiveSupport::Concern

  included do
    after_save :log_setting_changes
  end

  private

  def log_setting_changes
    self.class._settings.each do |setting|
      if saved_change_to_attribute?(setting.name)
        old_val, new_val = saved_change_to_attribute(setting.name)

        SettingChangeLog.create!(
          model_type: self.class.name,
          model_id: id,
          setting_name: setting.name,
          old_value: old_val,
          new_value: new_val,
          changed_at: Time.current,
          changed_by: Current.user&.id # If using Current attributes
        )
      end
    end
  end
end

# app/models/setting_change_log.rb
class SettingChangeLog < ApplicationRecord
  # t.string :model_type
  # t.integer :model_id
  # t.string :setting_name
  # t.string :old_value
  # t.string :new_value
  # t.integer :changed_by
  # t.datetime :changed_at

  belongs_to :changed_by_user, class_name: 'User', foreign_key: :changed_by, optional: true

  scope :recent, -> { order(changed_at: :desc).limit(100) }
  scope :for_setting, ->(name) { where(setting_name: name) }
  scope :for_model, ->(model) { where(model_type: model.class.name, model_id: model.id) }
end
```

## Troubleshooting

### High Memory Usage

```ruby
# Check JSONB document sizes
result = User.connection.execute(<<~SQL)
  SELECT
    id,
    pg_column_size(settings_json) as size_bytes
  FROM users
  ORDER BY size_bytes DESC
  LIMIT 10
SQL

result.each do |row|
  puts "User #{row['id']}: #{row['size_bytes']} bytes"
end

# Alert if any document > 10KB
```

### Slow Queries

```ruby
# Enable query logging
ActiveRecord::Base.logger = Logger.new(STDOUT)

# Check query plans
explain = User.where(notifications_enabled: true).explain
puts explain

# Add indexes if needed
```

### Missing Indexes

```ruby
# Check for missing indexes
# Use gem 'lol_dba' or 'bullet'

# Or manually check
User.connection.execute(<<~SQL)
  SELECT
    schemaname,
    tablename,
    attname,
    n_distinct,
    correlation
  FROM pg_stats
  WHERE tablename = 'users'
    AND attname IN ('notifications_enabled', 'premium_mode')
SQL
```

## Best Practices

1. **Monitor Proactively**: Set up alerts before issues occur
2. **Track Trends**: Look at metrics over time, not just current values
3. **Set Baselines**: Know what "normal" looks like for your application
4. **Regular Reviews**: Review dashboards and alerts weekly
5. **Document Incidents**: Keep record of issues and resolutions

## Resources

- **Production Checklist**: `docs/guides/production_checklist.md`
- **Deployment Guide**: `docs/guides/deployment.md`
- **Performance Guide**: `docs/guides/performance.md`

---

**Version**: 0.8.0
**Last Updated**: 2025-11-02
