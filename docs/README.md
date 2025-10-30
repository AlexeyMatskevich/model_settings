# ModelSettings Documentation

Complete documentation for ModelSettings gem - declarative configuration management DSL for Rails models.

## 📚 Documentation Structure

### Getting Started

- **[Getting Started Guide](guides/getting_started.md)** - Complete beginner guide from installation to first settings
- **[Migration Guide](guides/migration.md)** - Migrating from boolean columns, feature flags, or other solutions
- **[Quick Reference](../README.md#quick-start)** - Fast syntax reference (in main README)

### Core Functionality

Everything you need to know about ModelSettings core features:

- **[DSL Basics](core/dsl.md)** - Defining settings, options, and the settings DSL
- **[Storage Adapters](core/adapters.md)** - Column, JSON/JSONB, and StoreModel adapters
- **[Dependencies](core/dependencies.md)** - Cascades, syncs, and the dependency engine
- **[Settings Inheritance](core/inheritance.md)** - Automatic inheritance across model hierarchies
- **[Validation](core/validation.md)** - Built-in and custom validation framework
- **[Callbacks](core/callbacks.md)** - before_enable, after_change, around hooks, etc.
- **[Query Interface](core/queries.md)** - Finding and filtering settings by metadata
- **[Configuration](core/configuration.md)** - Global configuration and defaults

### Modules

Extend ModelSettings with powerful modules:

- **[Roles Module](modules/roles.md)** - Role-based access control (RBAC) with `viewable_by`/`editable_by`
- **[Pundit Module](modules/pundit.md)** - Pundit policy integration for authorization
- **[ActionPolicy Module](modules/action_policy.md)** - ActionPolicy integration for authorization
- **[I18n Module](modules/i18n.md)** - Internationalization for labels and descriptions
- **[Documentation Generator](modules/documentation.md)** - Auto-generate Markdown/JSON docs

### Real-World Usage Cases

See how to solve specific problems with ModelSettings:

- **[Feature Flags](usage_cases/feature_flags.md)** - Boolean feature toggles with gradual rollout
- **[User Preferences](usage_cases/user_preferences.md)** - User-specific settings and preferences
- **[Multi-Tenancy](usage_cases/multi_tenancy.md)** - Organization/tenant-level configurations
- **[API Settings](usage_cases/api_settings.md)** - API keys, rate limits, and integrations
- **[Admin Panels](usage_cases/admin_panels.md)** - Building settings management UIs

### Guides & Best Practices

Learn how to use ModelSettings effectively:

- **[Testing Guide](guides/testing.md)** - Testing strategies and patterns
- **[Performance Guide](guides/performance.md)** - Optimization and N+1 prevention
- **[Best Practices](guides/best_practices.md)** - Design patterns and recommendations

## 🔍 Finding What You Need

### I want to...

**Learn the basics**
→ Start with [Getting Started Guide](guides/getting_started.md)

**Store settings in database columns**
→ See [Storage Adapters](core/adapters.md#column-adapter)

**Store multiple settings in one JSON column**
→ See [Storage Adapters](core/adapters.md#json-adapter)

**Use StoreModel for complex nested settings**
→ See [Storage Adapters](core/adapters.md#storemodel-adapter)

**Enable child settings when parent is enabled**
→ See [Dependencies - Cascades](core/dependencies.md#cascades)

**Keep two settings synchronized**
→ See [Dependencies - Syncs](core/dependencies.md#syncs)

**Control who can view/edit settings**
→ See [Roles Module](modules/roles.md), [Pundit Module](modules/pundit.md), or [ActionPolicy Module](modules/action_policy.md)

**Inherit settings from parent model**
→ See [Settings Inheritance](core/inheritance.md)

**Generate documentation from code**
→ See [Documentation Generator](modules/documentation.md)

**Validate setting values**
→ See [Validation](core/validation.md)

**Run code when settings change**
→ See [Callbacks](core/callbacks.md)

**Migrate from boolean columns**
→ See [Migration Guide](guides/migration.md#from-boolean-columns)

**Test my settings**
→ See [Testing Guide](guides/testing.md)

### By Feature

| Feature | Documentation | Quick Example |
|---------|--------------|---------------|
| Boolean feature flags | [Feature Flags](usage_cases/feature_flags.md) | `setting :premium, type: :column` |
| JSON storage | [JSON Adapter](core/adapters.md#json-adapter) | `setting :prefs, type: :json, storage: {column: :data}` |
| StoreModel | [StoreModel Adapter](core/adapters.md#storemodel-adapter) | `setting :ai, type: :store_model, storage: {column: :ai_settings}` |
| Cascades | [Cascades](core/dependencies.md#cascades) | `cascade: {enable: true}` |
| Syncs | [Syncs](core/dependencies.md#syncs) | `sync: {target: :other, mode: :forward}` |
| Authorization | [Roles](modules/roles.md) | `viewable_by: [:admin]` |
| I18n | [I18n Module](modules/i18n.md) | `t_label_for(:setting_name)` |
| Inheritance | [Settings Inheritance](core/inheritance.md) | Automatic in `class Child < Parent` |
| Documentation | [Doc Generator](modules/documentation.md) | `rake settings:docs:generate` |

## 📖 Additional Resources

- **[Main README](../README.md)** - Quick overview and installation
- **[CHANGELOG](../CHANGELOG.md)** - Version history and changes
- **[GitHub Repository](https://github.com/AlexeyMatskevich/model_settings)** - Source code
- **[Issue Tracker](https://github.com/AlexeyMatskevich/model_settings/issues)** - Bug reports and feature requests

## 💡 Documentation Philosophy

This documentation follows a clear philosophy:

1. **Start Simple, Go Deep**: Beginner guides first, then comprehensive reference
2. **Show, Don't Tell**: Every concept has working code examples
3. **Real-World Focus**: Usage cases show actual problems and solutions
4. **Complete Examples**: All code examples are runnable and tested
5. **Cross-References**: Generous linking between related concepts

## 🤝 Contributing to Documentation

Found a typo? Have a suggestion? Want to add an example?

- Documentation lives alongside code in the [GitHub repository](https://github.com/AlexeyMatskevich/model_settings)
- All contributions welcome via Pull Requests
- See [Documentation Plan](PLAN.md) for structure and guidelines
- Questions? Open an issue!

---

**Note**: This documentation is actively developed. Some sections may be placeholders marked with "Coming soon". Check [Documentation Plan](PLAN.md) for current status and priorities.
