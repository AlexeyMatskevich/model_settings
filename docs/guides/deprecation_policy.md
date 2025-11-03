# Deprecation Policy

This document describes how ModelSettings handles deprecations and breaking changes.

## Policy Overview

### Pre-1.0 Releases (Current: 0.9.x)

**Status**: Alpha/Beta development

We are currently in **pre-1.0** status with **NO production users**. This allows us maximum flexibility:

- ✅ **Breaking changes allowed** in any release (major, minor, or patch)
- ✅ **No deprecation period required** - features can be removed immediately
- ✅ **API changes encouraged** if they improve developer experience
- ✅ **Aggressive refactoring** to find the best API design
- ❌ **No long-term support** for old versions
- ❌ **No migration paths required** (but nice to have)

**Rationale**: We have zero production users, so we can break freely without affecting anyone. This is the time to perfect the API before 1.0.

**Example**:
```ruby
# Version 0.8.0
setting :premium, deprecated: true

# Version 0.9.0 - REMOVED (no deprecation period)
# Feature completely removed, no backward compatibility
```

### Post-1.0 Releases (Future)

**Status**: Stable production releases

Once we reach 1.0.0, we will follow **strict SemVer** with formal deprecation policy:

- **Major versions** (1.x → 2.x): Breaking changes allowed with migration guide
- **Minor versions** (1.1 → 1.2): New features only, no breaking changes
- **Patch versions** (1.2.1 → 1.2.2): Bug fixes only

**Deprecation timeline**:
- Deprecation announced at least **1 major version** in advance
- Deprecated features trigger **warnings** in logs
- **Migration guide** provided for all breaking changes
- **6 months minimum** before actual removal

**Example**:
```ruby
# Version 1.5.0 - Deprecation announced
setting :premium, old_api: true  # Triggers deprecation warning

# Version 1.6.0 - Still supported with warnings
setting :premium, old_api: true  # Warning: old_api is deprecated

# Version 2.0.0 - Removed
setting :premium, old_api: true  # Error: old_api no longer supported
```

## Current Deprecations (0.9.x)

### Active Deprecations

**None** - No features are currently deprecated.

### Recently Removed

**None** - No features have been removed yet (pre-1.0 status).

## Deprecation Process (Post-1.0)

### 1. Announcement

Deprecations will be announced via:
- **CHANGELOG.md** entry
- **GitHub release notes**
- **Deprecation guide** in docs
- **Runtime warnings** in code

### 2. Deprecation Period

Minimum timeline:
- **Announcement**: Version X.Y.0
- **Warning period**: At least 1 major version
- **Removal**: Version (X+1).0.0

Example:
```
v1.5.0 - Feature deprecated, warnings added
v1.6.0 - Still works, warnings continue
v1.7.0 - Still works, warnings continue
v2.0.0 - Feature removed
```

### 3. Migration Guide

Every deprecation will include:
- **Why** it's being deprecated
- **What** to use instead
- **How** to migrate (with code examples)
- **When** it will be removed

Example:
```markdown
## Deprecated: `setting_name_changed?` → Use `setting_name.changed?`

**Deprecated in**: 1.5.0
**Removed in**: 2.0.0

**Reason**: Inconsistent with Rails conventions

**Migration**:
# Old (deprecated)
if user.premium_changed?
  # ...
end

# New (recommended)
if user.premium.changed?
  # ...
end
```

### 4. Removal

Features will be removed in:
- **Next major version** (1.x → 2.0)
- **At least 6 months** after deprecation
- **With clear upgrade guide**

## Deprecation Warnings

### Enabling Warnings

```ruby
# config/environments/development.rb
config.active_support.deprecation = :log

# config/environments/test.rb
config.active_support.deprecation = :stderr

# config/environments/production.rb
config.active_support.deprecation = :notify
```

### Warning Format

```ruby
# Example deprecation warning
DEPRECATION WARNING: `setting_name_changed?` is deprecated and will be removed in ModelSettings 2.0.
Use `setting_name.changed?` instead.
(called from update at app/controllers/users_controller.rb:42)
```

### Suppressing Warnings

```ruby
# Temporarily suppress (not recommended)
ActiveSupport::Deprecation.silenced = true
user.premium_changed?  # No warning
ActiveSupport::Deprecation.silenced = false
```

## Breaking Change Guidelines

### What Constitutes a Breaking Change?

**Breaking changes** (require major version bump after 1.0):
- Removing a public API method
- Changing method signature
- Changing return type
- Renaming classes/modules
- Changing default behavior
- Removing configuration options

**Non-breaking changes** (allowed in minor versions):
- Adding new features
- Adding new optional parameters
- Deprecating features (with warnings)
- Bug fixes
- Performance improvements
- Internal refactoring

### Avoiding Breaking Changes

When possible, we will:
- Use **opt-in** for new behavior
- Provide **shims** for old API
- Add **aliases** for renamed methods
- Keep **defaults** stable

Example:
```ruby
# ✅ GOOD: Opt-in new behavior
setting :premium, new_feature: true  # Optional

# ❌ BAD: Force new behavior
# All settings now use new behavior by default
```

## Semantic Versioning

### Version Format: MAJOR.MINOR.PATCH

- **MAJOR** (1.x → 2.x): Breaking changes
- **MINOR** (1.1 → 1.2): New features, deprecations
- **PATCH** (1.2.1 → 1.2.2): Bug fixes

### Pre-1.0 Versions (Current)

- **MINOR** (0.8 → 0.9): Can include breaking changes
- **PATCH** (0.9.1 → 0.9.2): Bug fixes only

### Post-1.0 Versions (Future)

Strict SemVer:
- **2.0.0**: Breaking changes from 1.x
- **1.5.0**: New features, no breaking changes
- **1.4.3**: Bug fixes only

## Upgrade Strategy

### For Pre-1.0 Users

**Recommendation**: Stay on latest version

```ruby
# Gemfile
gem 'model_settings', '~> 0.9.0'
```

Update frequently:
```bash
bundle update model_settings
bundle exec rspec  # Run tests
git commit -m "Update model_settings to 0.9.0"
```

### For Post-1.0 Users

**Recommendation**: Pin to minor version

```ruby
# Gemfile - Pin to minor version
gem 'model_settings', '~> 1.5.0'  # Allows 1.5.x, not 1.6.0
```

Update strategy:
1. **Patch updates**: Apply immediately (bug fixes)
2. **Minor updates**: Review changelog, test in staging
3. **Major updates**: Plan migration, allocate time

## Deprecation Detection

### Automated Checks

```bash
# Run deprecation audit
bundle exec rake settings:audit:deprecated

# Check for deprecated settings in database
bundle exec rake settings:audit:deprecated
# Exit code 0: No deprecated settings
# Exit code 1: Deprecated settings found
```

### CI Integration

```yaml
# .github/workflows/test.yml
- name: Check for deprecated settings
  run: bundle exec rake settings:audit:deprecated
```

### Manual Review

```ruby
# Check for deprecation warnings in logs
grep -i "DEPRECATION" log/development.log

# List all deprecated settings
User.settings.select(&:deprecated?)
```

## Communication Channels

Deprecation announcements will be published via:

1. **CHANGELOG.md** - Detailed changes
2. **GitHub Releases** - Version announcements
3. **GitHub Discussions** - Community discussion
4. **Documentation** - Migration guides
5. **Runtime Warnings** - In-app notifications

## Exception Policy

### Emergency Breaking Changes

In rare cases, we may need to make breaking changes immediately:

**Reasons**:
- **Security vulnerabilities** requiring immediate fix
- **Critical bugs** affecting data integrity
- **Legal/compliance** requirements

**Process**:
1. Announce immediately via GitHub Security Advisory
2. Release patch version with fix
3. Provide migration guide
4. Extend support for affected versions if needed

### Experimental Features

Features marked as **experimental** can change without deprecation:

```ruby
# Experimental API (can change anytime)
setting :premium, experimental_feature: true  # ⚠️ Subject to change
```

Experimental features will be clearly marked in documentation.

## Version Support Matrix

### Pre-1.0 (Current)

| Version | Status | Support |
|---------|--------|---------|
| 0.9.x | ✅ Current | Full support |
| 0.8.x | ⚠️ Maintenance | Security fixes only |
| 0.7.x | ❌ Unsupported | Upgrade to 0.9+ |
| < 0.7 | ❌ Unsupported | Upgrade to 0.9+ |

### Post-1.0 (Future)

| Version | Status | Support |
|---------|--------|---------|
| 2.x | ✅ Current | Full support |
| 1.x | ✅ LTS | 6 months after 2.0 |
| < 1.0 | ❌ Unsupported | Upgrade to 2.x |

## Questions and Feedback

- **Policy questions**: Open [GitHub Discussion](https://github.com/your-org/model_settings/discussions)
- **Deprecation requests**: Open [GitHub Issue](https://github.com/your-org/model_settings/issues)
- **Migration help**: See [Upgrading Guide](upgrading.md)

## Policy Updates

This policy may be updated as the project evolves. Major changes will be announced via:
- CHANGELOG.md entry
- GitHub Discussion
- Updated documentation

**Last Updated**: 2025-11-04 (v0.9.0)
