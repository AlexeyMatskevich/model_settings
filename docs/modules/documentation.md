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
```

## Rake Tasks

```bash
# Generate Markdown (default)
rake settings:docs:generate

# Generate JSON
rake settings:docs:generate FORMAT=json

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
