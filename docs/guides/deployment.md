# Deployment Guide

Quick reference for deploying applications using ModelSettings.

## Quick Start

### 1. First-Time Setup

```bash
# 1. Add to Gemfile
gem 'model_settings', '~> 0.8.0'

# 2. Install
bundle install

# 3. Create initializer (optional)
rails generate model_settings:install

# 4. Add settings to your models
# See "Basic Usage" section

# 5. Create migrations for new columns
rails generate migration AddNotificationsEnabledToUsers notifications_enabled:boolean
rails db:migrate

# 6. Test in development
rails console
> user = User.first
> user.notifications_enabled = true
> user.save!
```

## Deployment Process

### Standard Rails Deployment

```bash
# 1. Ensure tests pass
bundle exec rspec

# 2. Run migrations (before deploying code)
rails db:migrate

# 3. Deploy application
# (Heroku, Capistrano, Docker, etc.)

# 4. Verify deployment
rails runner "User.compile_settings!"
```

### Zero-Downtime Deployment

For applications that cannot afford downtime:

```ruby
# Step 1: Add new columns (backward compatible)
class AddNewSettingToUsers < ActiveRecord::Migration[7.0]
  def change
    add_column :users, :new_feature_enabled, :boolean, default: false
  end
end

# Step 2: Deploy code that uses new column
# Old code ignores new column (backward compatible)

# Step 3: Backfill data (if needed)
User.find_each do |user|
  user.update_column(:new_feature_enabled, true) if user.premium?
end

# Step 4: Remove old columns (next deployment)
class RemoveOldSettingFromUsers < ActiveRecord::Migration[7.0]
  def change
    remove_column :users, :old_feature_enabled
  end
end
```

## Environment-Specific Configuration

### Development

```ruby
# config/environments/development.rb
config.after_initialize do
  # Enable debug mode for settings
  ENV['DEBUG_VALIDATION'] = '1'

  # Compile settings on boot
  Rails.application.eager_load!
  ActiveRecord::Base.descendants.each do |model|
    model.compile_settings! if model.respond_to?(:compile_settings!)
  end
end
```

### Staging

```ruby
# config/environments/staging.rb
config.after_initialize do
  # Use production-like settings
  # But enable additional logging
  Rails.logger.level = :info
end
```

### Production

```ruby
# config/environments/production.rb
config.after_initialize do
  # Compile settings once on boot
  Rails.application.eager_load!
  ActiveRecord::Base.descendants.each do |model|
    model.compile_settings! if model.respond_to?(:compile_settings!)
  end

  # Log setting changes
  ActiveSupport::Notifications.subscribe('setting.changed') do |*args|
    event = ActiveSupport::Notifications::Event.new(*args)
    Rails.logger.info("Setting changed: #{event.payload}")
  end
end
```

## Database Migrations

### Adding a New Setting

```ruby
# 1. Generate migration
rails generate migration AddFeatureEnabledToUsers feature_enabled:boolean

# 2. Edit migration to add default
class AddFeatureEnabledToUsers < ActiveRecord::Migration[7.0]
  def change
    add_column :users, :feature_enabled, :boolean, default: false, null: false
  end
end

# 3. Run migration
rails db:migrate

# 4. Add setting to model
class User < ApplicationRecord
  include ModelSettings::DSL

  setting :feature_enabled, type: :column, default: false
end
```

### Adding a JSON/JSONB Setting

```ruby
# 1. Generate migration
rails generate migration AddSettingsJsonToUsers

# 2. Edit migration
class AddSettingsJsonToUsers < ActiveRecord::Migration[7.0]
  def change
    # PostgreSQL: Use jsonb for better performance
    add_column :users, :settings_json, :jsonb, default: {}, null: false

    # MySQL: Use json
    # add_column :users, :settings_json, :json

    # SQLite: Use text
    # add_column :users, :settings_json, :text

    # Add GIN index for PostgreSQL
    add_index :users, :settings_json, using: :gin
  end
end

# 3. Run migration
rails db:migrate

# 4. Add settings to model
class User < ApplicationRecord
  include ModelSettings::DSL

  setting :preferences, type: :json, storage: {column: :settings_json} do
    setting :email_notifications, default: true
    setting :sms_notifications, default: false
  end
end
```

### Removing a Deprecated Setting

```ruby
# 1. Mark as deprecated first (deploy)
setting :old_feature, type: :column, deprecated: "Use new_feature instead"

# 2. Wait for grace period (e.g., 6 months)

# 3. Check for active usage
rails settings:audit:deprecated

# 4. If no usage, remove from code (deploy)

# 5. Remove column (next deployment)
class RemoveOldFeatureFromUsers < ActiveRecord::Migration[7.0]
  def change
    remove_column :users, :old_feature
  end
end
```

## Heroku Deployment

### Setup

```bash
# 1. Add to Gemfile
gem 'model_settings', '~> 0.8.0'

# 2. Commit changes
git add .
git commit -m "Add ModelSettings gem"

# 3. Push to Heroku
git push heroku main

# 4. Run migrations
heroku run rails db:migrate

# 5. Verify
heroku run rails runner "User.compile_settings!"
```

### Configuration

```bash
# Set environment variables
heroku config:set RAILS_ENV=production

# Enable debug mode (temporary)
heroku config:set DEBUG_VALIDATION=1

# Disable after debugging
heroku config:unset DEBUG_VALIDATION
```

## Docker Deployment

### Dockerfile Example

```dockerfile
FROM ruby:3.2

WORKDIR /app

# Install dependencies
COPY Gemfile Gemfile.lock ./
RUN bundle install

# Copy application
COPY . .

# Precompile assets (if using)
RUN RAILS_ENV=production rails assets:precompile

# Compile settings
RUN RAILS_ENV=production rails runner "
  Rails.application.eager_load!
  ActiveRecord::Base.descendants.each do |model|
    model.compile_settings! if model.respond_to?(:compile_settings!)
  end
"

EXPOSE 3000

CMD ["rails", "server", "-b", "0.0.0.0"]
```

### Docker Compose

```yaml
version: '3.8'

services:
  db:
    image: postgres:15
    environment:
      POSTGRES_PASSWORD: password
    volumes:
      - postgres_data:/var/lib/postgresql/data

  app:
    build: .
    command: bash -c "rm -f tmp/pids/server.pid && rails db:migrate && rails server -b 0.0.0.0"
    volumes:
      - .:/app
    ports:
      - "3000:3000"
    depends_on:
      - db
    environment:
      DATABASE_URL: postgres://postgres:password@db:5432/app_production
      RAILS_ENV: production

volumes:
  postgres_data:
```

## Kubernetes Deployment

### Deployment Example

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: rails-app
spec:
  replicas: 3
  selector:
    matchLabels:
      app: rails-app
  template:
    metadata:
      labels:
        app: rails-app
    spec:
      initContainers:
        # Run migrations before starting app
        - name: migrate
          image: myapp:latest
          command: ["rails", "db:migrate"]
          env:
            - name: RAILS_ENV
              value: "production"
            - name: DATABASE_URL
              valueFrom:
                secretKeyRef:
                  name: db-credentials
                  key: url

      containers:
        - name: app
          image: myapp:latest
          ports:
            - containerPort: 3000
          env:
            - name: RAILS_ENV
              value: "production"
            - name: DATABASE_URL
              valueFrom:
                secretKeyRef:
                  name: db-credentials
                  key: url
          livenessProbe:
            httpGet:
              path: /health
              port: 3000
            initialDelaySeconds: 30
            periodSeconds: 10
          readinessProbe:
            httpGet:
              path: /ready
              port: 3000
            initialDelaySeconds: 5
            periodSeconds: 5
```

## Common Deployment Issues

### Issue: "Table doesn't exist" Error

**Cause**: Migrations not run before code deployment

**Fix**:
```bash
# Always run migrations BEFORE deploying code
rails db:migrate
```

### Issue: "CyclicSyncError" on Boot

**Cause**: Sync relationships form a cycle

**Fix**:
```ruby
# Check sync definitions
User.settings_debug

# Remove circular syncs
setting :a, sync: {target: :b}
setting :b # Remove sync to :a
```

### Issue: Settings Not Compiling

**Cause**: Error during compilation

**Fix**:
```bash
# Enable debug mode
DEBUG_VALIDATION=1 rails runner "User.compile_settings!"

# Check error messages
```

### Issue: Slow Application Boot

**Cause**: Too many settings or complex dependency graph

**Fix**:
```ruby
# Profile compilation time
Benchmark.measure do
  Rails.application.eager_load!
  ActiveRecord::Base.descendants.each do |model|
    model.compile_settings! if model.respond_to?(:compile_settings!)
  end
end

# Optimize:
# - Reduce number of settings
# - Simplify sync relationships
# - Split into multiple models
```

## Rollback Procedure

### Standard Rollback

```bash
# 1. Identify issue
# 2. Rollback code deployment
# (Heroku) heroku rollback
# (Capistrano) cap production deploy:rollback

# 3. Rollback migrations if needed
rails db:rollback

# 4. Verify system is stable
rails runner "User.first.notifications_enabled = true"
```

### Emergency Rollback

```bash
# 1. Stop application
heroku maintenance:on

# 2. Rollback to last known good version
heroku releases
heroku rollback v123

# 3. Rollback migrations
heroku run rails db:rollback STEP=2

# 4. Restart application
heroku restart

# 5. Verify and resume
heroku run rails console
> User.first.settings_debug
heroku maintenance:off
```

## Health Checks

### Application Health

```ruby
# config/routes.rb
get '/health', to: 'health#index'

# app/controllers/health_controller.rb
class HealthController < ApplicationController
  def index
    # Check database
    ActiveRecord::Base.connection.execute('SELECT 1')

    # Check settings compilation
    User.compile_settings!

    render json: {status: 'ok', timestamp: Time.current}
  rescue => e
    render json: {status: 'error', error: e.message}, status: 503
  end
end
```

### Settings Health

```ruby
# Check settings are working
def settings_health_check
  user = User.first
  return {status: 'error', message: 'No users'} unless user

  # Test read
  value = user.notifications_enabled

  # Test write
  user.notifications_enabled = !value
  user.save!

  # Test reload
  user.reload
  new_value = user.notifications_enabled

  if new_value == !value
    {status: 'ok'}
  else
    {status: 'error', message: 'Settings not persisting'}
  end
rescue => e
  {status: 'error', message: e.message}
end
```

## Monitoring Setup

### Application Performance Monitoring (APM)

```ruby
# config/initializers/apm.rb
if Rails.env.production?
  # New Relic
  require 'newrelic_rpm'

  # Track setting changes
  ActiveSupport::Notifications.subscribe('setting.changed') do |*args|
    event = ActiveSupport::Notifications::Event.new(*args)
    NewRelic::Agent.record_custom_event('SettingChanged', event.payload)
  end
end
```

### Logging

```ruby
# config/application.rb
config.log_level = :info
config.log_tags = [:request_id]

# Custom logger for settings
config.after_initialize do
  ModelSettings.logger = Rails.logger
end
```

## Best Practices

### 1. Always Run Migrations First

```bash
# ✅ Good
rails db:migrate
git push heroku main

# ❌ Bad
git push heroku main
rails db:migrate  # Too late!
```

### 2. Use Backward-Compatible Changes

```ruby
# ✅ Good (gradual migration)
# 1. Add new column
# 2. Deploy code using new column (reads old if new is nil)
# 3. Backfill data
# 4. Remove old column

# ❌ Bad (breaking change)
# Remove column and deploy code at same time
```

### 3. Test in Staging

```bash
# Deploy to staging first
git push staging main

# Test thoroughly
# - Settings work correctly
# - Migrations applied
# - Performance acceptable

# Then deploy to production
git push production main
```

### 4. Monitor After Deployment

```bash
# Watch logs
heroku logs --tail

# Check error rates
heroku run rails runner "
  User.find_each do |user|
    user.valid?
  end
"

# Monitor metrics
# - Response times
# - Error rates
# - Setting change frequency
```

## Next Steps

After successful deployment:

1. ✅ Monitor application health
2. ✅ Review logs for errors
3. ✅ Check performance metrics
4. ✅ Verify settings working correctly
5. ✅ Document any issues encountered
6. ✅ Update team on deployment status

## Resources

- **Production Checklist**: `docs/guides/production_checklist.md`
- **Security Guide**: `docs/security/SECURITY_AUDIT.md`
- **Performance Guide**: `docs/guides/performance.md`
- **Error Messages**: `docs/guides/error_messages.md`

---

**Version**: 0.8.0
**Last Updated**: 2025-11-02
