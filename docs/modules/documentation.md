# Documentation Generator

Automatically generate documentation from your settings definitions.

## Generate for One Model

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  setting :premium, type: :column, description: "Premium subscription"
end

# Generate Markdown
docs = User.settings_documentation(format: :markdown)
File.write('docs/user_settings.md', docs)

# Generate JSON
docs = User.settings_documentation(format: :json)
File.write('docs/user_settings.json', docs)

# Generate YAML
docs = User.settings_documentation(format: :yaml)
File.write('docs/user_settings.yml', docs)

# Generate HTML
docs = User.settings_documentation(format: :html)
File.write('docs/user_settings.html', docs)
```

## Rake Tasks

```bash
# Generate Markdown (default)
rake settings:docs:generate

# Generate JSON
rake settings:docs:generate FORMAT=json

# Generate YAML
rake settings:docs:generate FORMAT=yaml

# Generate HTML
rake settings:docs:generate FORMAT=html

# Output directory
rake settings:docs:generate OUTPUT_DIR=docs/api

# Audit deprecated settings
rake settings:audit:deprecated
```

## Filter Documentation

```ruby
# Only active settings
User.settings_documentation(format: :markdown, filter: :active)

# Only deprecated
User.settings_documentation(format: :markdown, filter: :deprecated)

# Custom filter
User.settings_documentation(
  format: :markdown,
  filter: ->(s) { s.description&.include?("API") }
)
```

## What's Included

Generated documentation includes:
- Setting names and types
- Storage details
- Default values
- Descriptions
- Authorization rules
- Deprecation status
- API methods
- Dependencies (cascades/syncs)

See full README for example output.

## See Also

- [Module Development Guide](../guides/module_development.md) - Learn how to create custom modules like Documentation
- [ModuleRegistry API Reference](../core/module_registry.md) - Complete API documentation
- [Custom Module Example](../../examples/custom_module/) - Working example of a custom module
- [Configuration Guide](../core/configuration.md) - Global configuration options
