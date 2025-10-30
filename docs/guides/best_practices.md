# Best Practices

Design patterns and recommendations for using ModelSettings effectively.

## 1. Choose the Right Storage Type

- **Column storage**: Best for frequently queried boolean flags
- **JSON storage**: Best for related settings read/written together
- **Mixed storage**: Use when you need column parent with JSON children

```ruby
# ✅ Good - Feature hierarchy with cascade
setting :premium_plan, cascade: {enable: true} do
  setting :advanced_analytics
  setting :priority_support
end
```

## 2. Use Cascades for Hierarchical Features

```ruby
# ✅ Good
setting :premium_plan, cascade: {enable: true} do
  setting :advanced_analytics
  setting :priority_support
end

# When premium is enabled, all premium features are automatically enabled
```

## 3. Use Syncs for Related Settings

```ruby
# ✅ Good - Marketing consent syncs with newsletter
setting :marketing_consent,
        sync: {target: :newsletter_subscription, mode: :forward}

# ❌ Less ideal - Manual synchronization
after_save :sync_newsletter
def sync_newsletter
  self.newsletter_subscription = marketing_consent  # Easy to miss edge cases
end
```

## 4. Choose the Right Sync Mode

- **Forward** (target = source): For mirroring settings
- **Inverse** (target = !source): For opt-out/opt-in relationships
- **Backward** (source = target): For computed/derived settings

## 5. Avoid Circular Dependencies

```ruby
# ❌ Bad - Circular dependency
setting :feature_a, sync: {target: :feature_b, mode: :forward}
setting :feature_b, sync: {target: :feature_a, mode: :forward}
# Raises CyclicSyncError at boot!

# ✅ Good - Linear dependency chain
setting :feature_a, sync: {target: :feature_b, mode: :forward}
setting :feature_b, sync: {target: :feature_c, mode: :forward}
setting :feature_c  # End of chain
```

## 6. Use Metadata for Organization

```ruby
setting :feature_name,
        metadata: {
          category: "features",
          tier: "premium",
          documented_at: "https://docs.example.com/feature"
        }
```

## 7. Add Descriptions

```ruby
setting :api_access,
        description: "Enables API access for third-party integrations",
        default: false
```

## 8. Use Callbacks for Side Effects

```ruby
# ✅ Good
setting :premium_mode,
        after_enable: :setup_premium_features

# ❌ Less ideal
user.premium_mode = true
user.save!
user.setup_premium_features # Easy to forget!
```

## 9. Deprecate Gracefully

```ruby
setting :old_setting,
        deprecated: "Use new_setting instead",
        metadata: {deprecated_since: "2.0.0", replacement: :new_setting}
```

## 10. Combine Cascades with Syncs

```ruby
# Enterprise plan enables features AND syncs with billing
setting :enterprise_plan,
        cascade: {enable: true},
        sync: {target: :billing_enabled, mode: :forward} do
  setting :advanced_reporting
  setting :sso_integration
end
```

## Performance Tips

### Use Indexes for Column Settings

```ruby
# Migration
add_column :users, :premium, :boolean, default: false
add_index :users, :premium  # Fast queries
```

### Use GIN Indexes for JSON

```ruby
# Migration
add_column :users, :settings, :jsonb, default: {}
add_index :users, :settings, using: :gin  # Fast JSONB queries
```

### Keep Callbacks Fast

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

## Testing

```ruby
RSpec.describe User do
  describe "settings" do
    it "enables notifications by default" do
      user = User.create!
      expect(user.notifications_enabled).to be true
    end

    it "tracks changes" do
      user = User.create!(notifications_enabled: true)
      user.notifications_enabled = false

      expect(user.notifications_enabled_changed?).to be true
      expect(user.notifications_enabled_was).to be true
    end

    it "calls callbacks on enable" do
      user = User.create!
      expect(user).to receive(:notify_activation)
      user.premium_mode_enable!
    end
  end
end
```

## Summary

- Choose storage based on query patterns
- Use cascades for parent-child relationships
- Use syncs to keep settings synchronized
- Avoid circular dependencies (detected at boot)
- Add metadata and descriptions
- Use callbacks for side effects
- Keep callbacks fast - queue jobs
- Test settings like normal attributes
