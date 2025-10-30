# Callbacks

ModelSettings provides a comprehensive callback system for hooking into setting lifecycle events.

## Available Callbacks

| Callback | When It Runs | Use Case |
|----------|--------------|----------|
| `before_enable` | Before setting changes to `true` | Prepare resources |
| `after_enable` | After setting changes to `true` | Send notifications |
| `before_disable` | Before setting changes to `false` | Check dependencies |
| `after_disable` | After setting changes to `false` | Cleanup resources |
| `before_change` | Before any value change | Audit logging |
| `after_change` | After any value change | Sync to external services |
| `after_change_commit` | After database commit | Send emails, queue jobs |

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

## Callback Arguments

Callbacks receive no arguments. Access the instance via `self`:

```ruby
def notify_premium_activation
  # self = the User instance
  PremiumMailer.activated(self).deliver_later
end
```

## Conditional Callbacks

Run callbacks only when certain conditions are met:

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
| `after_enable` | After `true` | Notifications, logging |
| `before_disable` | Before `false` | Dependency checks |
| `after_disable` | After `false` | Cleanup |
| `before_change` | Before any change | Audit logging |
| `after_change` | After any change | Internal state updates |
| `after_change_commit` | After DB commit | External APIs, emails, jobs |

**Key Points**:
- Callbacks run in predictable order
- Use `after_change_commit` for side effects
- Exceptions roll back the transaction
- Keep callbacks fast - queue jobs for slow work
