# Callbacks

ModelSettings provides a comprehensive callback system for hooking into setting lifecycle events.

## Available Callbacks

### Setting Change Callbacks

| Callback | When It Runs | Use Case |
|----------|--------------|----------|
| `before_enable` | Before setting changes to `true` | Prepare resources |
| `around_enable` | **Wraps** setting change to `true` | Measure time, transactions |
| `after_enable` | After setting changes to `true` | Send notifications |
| `before_disable` | Before setting changes to `false` | Check dependencies |
| `around_disable` | **Wraps** setting change to `false` | Measure time, transactions |
| `after_disable` | After setting changes to `false` | Cleanup resources |
| `before_change` | Before any value change | Audit logging |
| `around_change` | **Wraps** any value change | Measure time, transactions |
| `after_change` | After any value change | Sync to external services |
| `after_change_commit` | After database commit | Send emails, queue jobs |

### Lifecycle Callbacks

| Callback | When It Runs | Use Case |
|----------|--------------|----------|
| `before_validation` | Before model validation | Check prerequisites |
| `after_validation` | After model validation | Log validation results |
| `before_destroy` | Before model destruction | Check dependencies, cleanup |
| `after_destroy` | After model destruction | Cascade deletions, notifications |
| `after_change_rollback` | After transaction rollback | Cleanup temporary resources |

**Note**: Lifecycle callbacks integrate with Rails model lifecycle. See [Lifecycle Callbacks](#lifecycle-callbacks) below.

## Basic Usage

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  setting :premium_mode,
          type: :column,
          before_enable: :prepare_premium_features,
          after_enable: :notify_premium_activation,
          after_disable: :cleanup_premium_features,
          after_change_commit: :sync_to_external_service

  private

  def prepare_premium_features
    logger.info "Preparing premium features..."
  end

  def notify_premium_activation
    PremiumActivationMailer.notify(self).deliver_later
  end

  def cleanup_premium_features
    PremiumFeature.cleanup_for_user(self)
  end

  def sync_to_external_service
    ExternalApiJob.perform_later(self.id)
  end
end

# Usage
user.premium_mode_enable!
# Executes: prepare_premium_features → set value → notify_premium_activation
# After commit: sync_to_external_service
```

## Callback Execution Order

When you change a setting and save:

```
1. before_change           # If value changed
2. before_enable/disable   # If changing to true/false
3. Set new value
4. after_enable/disable    # If changed to true/false
5. after_change            # If value changed
6. Database save
7. after_change_commit     # After transaction commits
```

### Example Flow

```ruby
setting :premium, before_change: :log_change, after_change_commit: :notify

user.premium = true
user.save!

# Flow:
# 1. log_change runs (before_change)
# 2. premium = true (value set)
# 3. Database save
# 4. notify runs (after_change_commit)
```

## Multiple Callbacks

Specify multiple callbacks as an array:

```ruby
setting :api_access,
        type: :column,
        before_enable: [:check_quota, :verify_permissions],
        after_enable: [:log_access, :notify_admin]

private

def check_quota
  raise "Quota exceeded" if api_calls >= api_quota
end

def verify_permissions
  raise "No API permissions" unless has_api_role?
end

def log_access
  ApiAccessLog.create(user: self, enabled_at: Time.current)
end

def notify_admin
  AdminMailer.api_access_enabled(self).deliver_later
end
```

## Around Callbacks

**Around callbacks wrap the setting operation** and must call `yield` to execute it. This allows you to measure timing, wrap in transactions, or abort operations.

### Basic Usage

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  setting :expensive_feature,
          type: :column,
          around_enable: :measure_enable_time

  private

  def measure_enable_time
    start_time = Time.current
    yield  # Must yield to actually enable the setting
    duration = Time.current - start_time
    Rails.logger.info("Feature enabled in #{duration}s")
  end
end

user.expensive_feature_enable!
# Log output: "Feature enabled in 0.023s"
```

### Aborting Operations

Around callbacks can **abort the operation by not yielding**:

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  setting :premium_feature,
          type: :column,
          around_enable: :check_subscription

  private

  def check_subscription
    unless has_active_subscription?
      Rails.logger.warn("Cannot enable premium feature: no active subscription")
      return  # Don't yield - operation aborted
    end

    yield  # Proceed with enabling
  end
end

user.premium_feature_enable!
user.premium_feature  # => false (not enabled because no subscription)
```

### Transaction Wrapping

```ruby
class Organization < ApplicationRecord
  include ModelSettings::DSL

  setting :enterprise_mode,
          type: :column,
          around_enable: :wrap_in_transaction

  private

  def wrap_in_transaction
    ActiveRecord::Base.transaction do
      # Enable additional features
      update!(plan: "enterprise", seats: 100)

      yield  # Enable the setting

      # Log the change
      AuditLog.create!(organization: self, action: "enterprise_enabled")
    end
  end
end
```

### Timing and Logging

```ruby
class Callcenter < ApplicationRecord
  include ModelSettings::DSL

  setting :ai_transcription,
          type: :store_model,
          storage: {column: :ai_settings},
          around_enable: :log_with_timing

  private

  def log_with_timing
    Rails.logger.info("[#{id}] Enabling AI transcription...")
    start = Time.current

    yield  # Enable the feature

    elapsed = ((Time.current - start) * 1000).round(2)
    Rails.logger.info("[#{id}] AI transcription enabled (#{elapsed}ms)")
  end
end
```

### Error Handling in Around Callbacks

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  setting :api_access,
          type: :column,
          around_enable: :safe_enable

  private

  def safe_enable
    begin
      verify_api_quota!
      yield  # Enable if quota check passed
      notify_success
    rescue QuotaExceededError => e
      Rails.logger.error("API enable failed: #{e.message}")
      # Don't yield - operation aborted
    end
  end
end
```

### Multiple Around Callbacks

**Note:** Only the **first** around callback is executed. Around callbacks don't chain like before/after callbacks.

```ruby
# ❌ Only measure_time will run
setting :feature,
        around_enable: [:measure_time, :wrap_transaction]

# ✅ Use nested logic instead
def measure_and_wrap
  measure_time do
    wrap_transaction do
      yield
    end
  end
end
```

### Execution Order with Around Callbacks

```
1. before_change           # If value changed
2. before_enable/disable   # If changing to true/false
3. around_enable/disable   # ← Wraps steps 4-6
   ├─ 4. Set new value
   ├─ 5. after_enable/disable
   └─ 6. after_change
7. Database save
8. after_change_commit
```

**Example:**

```ruby
setting :premium,
        before_enable: :prepare,
        around_enable: :wrap,
        after_enable: :notify

# Execution order:
# 1. prepare() runs
# 2. wrap() starts
# 3. yield in wrap() → premium = true
# 4. notify() runs
# 5. wrap() ends
```

## after_change_commit

**Special callback that runs after the database transaction commits.** Perfect for side effects that should only happen after successful save.

### Use Cases

- Sending emails
- Queuing background jobs
- Syncing to external APIs
- Triggering webhooks

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  setting :newsletter_subscription,
          type: :column,
          after_change_commit: :sync_to_mailchimp

  private

  def sync_to_mailchimp
    return unless newsletter_subscription_previously_changed?

    if newsletter_subscription
      MailchimpSyncJob.perform_later(email, :subscribe)
    else
      MailchimpSyncJob.perform_later(email, :unsubscribe)
    end
  end
end
```

### Why after_change_commit?

Without `after_change_commit`, external services might be notified before the database commit completes. If the transaction rolls back, you've already triggered side effects.

```ruby
# ❌ Bad - after_change runs before commit
setting :premium, after_change: :charge_credit_card

user.premium = true
user.save!  # Charges card, then transaction might rollback!

# ✅ Good - after_change_commit runs after commit
setting :premium, after_change_commit: :charge_credit_card

user.premium = true
user.save!  # Transaction commits, THEN card is charged
```

## Lifecycle Callbacks

ModelSettings integrates with Rails model lifecycle, providing callbacks that run during validation, destruction, and transaction rollback.

### Validation Callbacks

Run callbacks during model validation:

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  setting :api_access,
          type: :column,
          before_validation: :check_api_quota,
          after_validation: :log_validation_result

  private

  def check_api_quota
    return unless api_access_changed?

    if api_access && api_calls_today >= daily_quota
      errors.add(:api_access, "daily quota exceeded")
    end
  end

  def log_validation_result
    return unless api_access_changed?

    Rails.logger.info "API access validation: #{errors[:api_access].empty? ? 'passed' : 'failed'}"
  end
end
```

### Destroy Callbacks

Run callbacks when the model is destroyed:

```ruby
class Organization < ApplicationRecord
  include ModelSettings::DSL

  setting :active,
          type: :column,
          before_destroy: :check_active_users,
          after_destroy: :notify_deactivation

  private

  def check_active_users
    if active && users.active.any?
      errors.add(:base, "Cannot delete organization with active users")
      throw :abort  # Prevent destruction
    end
  end

  def notify_deactivation
    AdminMailer.organization_deleted(self).deliver_later
  end
end
```

#### Prepending Destroy Callbacks

Use `:prepend` to run callbacks before others:

```ruby
setting :critical_data,
        type: :column,
        before_destroy: :backup_critical_data,
        prepend: true  # Runs FIRST, before other callbacks

setting :other_data,
        type: :column,
        before_destroy: :cleanup_other  # Runs after
```

### Rollback Callbacks

Run callbacks when a transaction rolls back:

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  setting :trial_mode,
          type: :column,
          after_change: :reserve_trial_resources,
          after_change_rollback: :release_trial_resources

  private

  def reserve_trial_resources
    @trial_resources = TrialResourcePool.reserve_for(self)
  end

  def release_trial_resources
    # Transaction rolled back - release reserved resources
    @trial_resources&.release!
  end
end

# Usage
ActiveRecord::Base.transaction do
  user.trial_mode = true
  user.save!

  raise "Some error"  # Transaction rolls back
end
# release_trial_resources is called automatically
```

### Lifecycle Phase Filtering

Use `:on` option to run callbacks only during specific phases:

```ruby
setting :status,
        type: :column,
        after_change: :send_notification,
        on: :create  # Only on record creation

setting :active,
        type: :column,
        before_validation: :check_dependencies,
        on: [:create, :update]  # Not on destroy
```

## Callback Arguments

Callbacks receive no arguments. Access the instance via `self`:

```ruby
def notify_premium_activation
  # self = the User instance
  PremiumMailer.activated(self).deliver_later
end
```

## Callback Options

Callbacks support Rails-style options for conditional execution and ordering.

### :if Option

Run callback only if condition is true:

```ruby
setting :premium,
        type: :column,
        after_enable: :send_welcome_email,
        if: :email_notifications_enabled?

private

def email_notifications_enabled?
  email_verified? && !unsubscribed?
end
```

### :unless Option

Run callback only if condition is false:

```ruby
setting :api_access,
        type: :column,
        after_enable: :notify_admin,
        unless: :internal_user?

private

def internal_user?
  email.ends_with?('@company.com')
end
```

### :on Option

Run callback only during specific lifecycle phases:

```ruby
setting :feature,
        type: :column,
        after_enable: :send_notification,
        on: :create  # Only on record creation

# Options: :create, :update, :destroy
```

Multiple phases:

```ruby
setting :status,
        type: :column,
        after_change: :log_change,
        on: [:create, :update]  # Not on destroy
```

### :prepend Option

Run callback before others (only for `before_destroy`):

```ruby
setting :important,
        type: :column,
        before_destroy: :critical_cleanup,
        prepend: true  # Runs first

setting :other,
        type: :column,
        before_destroy: :normal_cleanup  # Runs after
```

### Combining Options

Multiple options can be combined:

```ruby
setting :premium,
        type: :column,
        after_enable: :notify_sales_team,
        if: :high_value_customer?,
        on: :update  # Only notify on updates, not creation

private

def high_value_customer?
  total_purchases > 10_000
end
```

## Conditional Callbacks (Manual)

For more complex conditions, use conditional logic inside the callback method:

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  setting :beta_access,
          type: :column,
          after_enable: :notify_if_first_time

  private

  def notify_if_first_time
    return if beta_access_was  # Was already enabled before

    BetaWelcomeMailer.welcome(self).deliver_later
  end
end
```

## Callbacks with Cascades/Syncs

Callbacks run **after** cascades and syncs are applied:

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  setting :premium,
          type: :column,
          cascade: {enable: true},
          after_enable: :log_premium_enabled do
    setting :advanced_analytics, type: :column
  end

  private

  def log_premium_enabled
    # Cascade has already run - children are enabled
    Rails.logger.info "Premium enabled. Analytics: #{advanced_analytics}"
  end
end

user.premium = true
user.save!
# Log output: "Premium enabled. Analytics: true"
```

## Error Handling in Callbacks

Exceptions in callbacks will **roll back the transaction**:

```ruby
setting :api_access,
        after_enable: :verify_api_quota

private

def verify_api_quota
  raise "API quota exceeded" if api_calls >= 1000
end

user.api_access = true
user.save!  # Raises exception, transaction rolled back
user.reload
user.api_access  # => false (not saved)
```

For non-critical callbacks, rescue exceptions:

```ruby
def notify_external_service
  ExternalApi.notify(self)
rescue StandardError => e
  Rails.logger.error("Failed to notify external service: #{e.message}")
  # Don't re-raise - allow save to complete
end
```

## Testing Callbacks

```ruby
RSpec.describe User do
  describe "premium_mode callbacks" do
    let(:user) { User.create! }

    it "calls prepare_premium_features before enabling" do
      expect(user).to receive(:prepare_premium_features)
      user.premium_mode_enable!
    end

    it "calls notify_premium_activation after enabling" do
      expect(user).to receive(:notify_premium_activation)
      user.premium_mode_enable!
    end

    it "calls cleanup_premium_features after disabling" do
      user.premium_mode_enable!
      expect(user).to receive(:cleanup_premium_features)
      user.premium_mode_disable!
    end

    it "syncs to external service after commit" do
      expect(ExternalApiJob).to receive(:perform_later).with(user.id)
      user.premium_mode = true
      user.save!
    end
  end
end
```

## Best Practices

### 1. Use after_change_commit for Side Effects

```ruby
# ✅ Good - external API called after commit
setting :premium, after_change_commit: :sync_to_stripe

# ❌ Risky - external API called before commit
setting :premium, after_change: :sync_to_stripe
```

### 2. Keep Callbacks Fast

```ruby
# ❌ Bad - slow operation in callback
def notify_all_users
  User.find_each { |u| u.send_notification }  # Slow!
end

# ✅ Good - queue background job
def notify_all_users
  NotifyUsersJob.perform_later
end
```

### 3. Avoid Circular Changes

```ruby
# ❌ Bad - can cause infinite loop
setting :feature_a, after_change: :update_feature_b
setting :feature_b, after_change: :update_feature_a

# ✅ Good - use syncs instead
setting :feature_a, sync: {target: :feature_b, mode: :forward}
```

### 4. Use Conditional Logic

```ruby
# ✅ Good - only run when relevant
def notify_upgrade
  return unless premium_mode && premium_mode_previously_changed?
  PremiumMailer.upgraded(self).deliver_later
end
```

## Related Documentation

- [Validation](validation.md) - Validations run before callbacks
- [Dependencies](dependencies.md) - Cascades/syncs run before callbacks
- [DSL Reference](dsl.md) - Complete callback options

## Summary

| Callback | Runs | Best For |
|----------|------|----------|
| `before_enable` | Before `true` | Preparation, validation |
| `around_enable` | **Wraps** `true` | Timing, transactions, aborting |
| `after_enable` | After `true` | Notifications, logging |
| `before_disable` | Before `false` | Dependency checks |
| `around_disable` | **Wraps** `false` | Timing, transactions, aborting |
| `after_disable` | After `false` | Cleanup |
| `before_change` | Before any change | Audit logging |
| `around_change` | **Wraps** any change | Timing, transactions, aborting |
| `after_change` | After any change | Internal state updates |
| `after_change_commit` | After DB commit | External APIs, emails, jobs |

**Key Points**:
- Callbacks run in predictable order
- **Around callbacks must `yield`** to execute the operation
- Around callbacks can abort by not yielding
- Use `after_change_commit` for side effects
- Exceptions roll back the transaction
- Keep callbacks fast - queue jobs for slow work
