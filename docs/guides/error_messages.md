# Error Messages Guide

This guide describes the principles and patterns for writing helpful error messages in ModelSettings.

## Philosophy

Error messages should be **developer-friendly** and **actionable**. When a developer encounters an error, they should:

1. **Understand what went wrong** - Clear description of the problem
2. **Know where it happened** - File, class, setting name
3. **Know how to fix it** - Concrete examples and suggestions
4. **Learn from the error** - Context about why it's a problem

## Structure of Good Error Messages

All error messages in ModelSettings follow this structure:

```ruby
def self.error_name(context_params)
  <<~ERROR
    [WHAT] Brief description of what went wrong

    [WHERE] Location information (setting name, model, etc.)

    [WHY] Explanation of why this is a problem

    [HOW] Step-by-step fix instructions

    [EXAMPLE] Code example showing the fix

    [OPTIONAL] Migration hints or additional context
  ERROR
end
```

### Example: JSON Adapter Configuration Error

```ruby
def self.json_adapter_error(setting, model_class)
  <<~ERROR
    JSON adapter requires a storage column to be specified.

    Setting: #{setting.name.inspect}
    Model: #{model_class.name}

    You must specify which JSONB column to store the setting in.

    Fix by adding storage configuration:
      setting :#{setting.name},
        type: :json,
        storage: {column: :settings_json}  # ← Add this

    Make sure the column exists in your database:
      add_column :#{model_class.table_name}, :settings_json, :jsonb
  ERROR
end
```

## Key Principles

### 1. **Be Specific, Not Generic**

❌ Bad:
```ruby
raise ArgumentError, "Invalid configuration"
```

✅ Good:
```ruby
raise ArgumentError, ErrorMessages.adapter_configuration_error(:json, setting, model_class)
# Produces: "JSON adapter requires a storage column to be specified..."
```

### 2. **Show the Location**

Always include:
- Setting name (`:notifications_enabled`)
- Model class name (`User`)
- File path if relevant

```ruby
Setting: :notifications_enabled
Model: User
```

### 3. **Provide Actionable Fix Instructions**

Use numbered steps or bullet points:

```ruby
To fix this issue:
  1. Decide which module best fits your needs
  2. Remove the include statement for other modules
```

### 4. **Include Code Examples**

Show the exact code needed to fix the problem:

```ruby
Fix by adding storage configuration:
  setting :transcription,
    type: :json,
    storage: {column: :ai_settings}  # ← Add this
```

Use visual markers like `# ←` or `✓` / `❌` to highlight important parts.

### 5. **Add Migration Hints When Needed**

If the fix requires database changes, show the migration:

```ruby
Make sure the column exists in your database:
  add_column :users, :settings_json, :jsonb
```

### 6. **Use "Did You Mean" Suggestions**

For typos or similar names, suggest the correct option:

```ruby
Unknown storage type: :colum

Did you mean: "column"?
```

The `did_you_mean` method uses Levenshtein distance to find close matches:

```ruby
suggestion = did_you_mean(input, candidates)
message += "\nDid you mean: #{suggestion.inspect}?" if suggestion
```

### 7. **Format for Readability**

- Use blank lines to separate sections
- Use indentation for code blocks
- Use bullet points or numbered lists
- Keep line length reasonable (~80 chars)

## ErrorMessages Module

All error messages are centralized in `lib/model_settings/error_messages.rb`:

```ruby
module ModelSettings
  module ErrorMessages
    class << self
      def adapter_configuration_error(adapter_type, setting, model_class)
        # ...
      end

      def unknown_storage_type_error(type, setting, model_class)
        # ...
      end

      # ... more error methods
    end
  end
end
```

### Adding a New Error Message

1. **Add method to ErrorMessages module:**

```ruby
def self.my_new_error(param1, param2)
  <<~ERROR
    [Brief description]

    [Context: param1, param2]

    [Explanation]

    [Fix instructions]

    [Example code]
  ERROR
end
```

2. **Use the error in your code:**

```ruby
raise ArgumentError, ErrorMessages.my_new_error(value1, value2)
```

3. **Write tests:**

```ruby
it "raises ArgumentError with improved message", :aggregate_failures do
  expect do
    # code that triggers error
  end.to raise_error(ArgumentError) do |error|
    expect(error.message).to include("Brief description")
    expect(error.message).to include(value1.to_s)
    expect(error.message).to include("Fix instructions")
  end
end
```

## "Did You Mean" Algorithm

The module includes a Levenshtein distance implementation for suggesting corrections:

```ruby
def self.did_you_mean(input, candidates)
  matches = candidates.select do |candidate|
    distance = levenshtein_distance(input.to_s, candidate.to_s)
    distance <= 2 && distance > 0  # Max distance of 2
  end

  matches.min_by { |c| levenshtein_distance(input.to_s, c.to_s) }
end
```

### When to Use "Did You Mean"

✅ Use when:
- User provides a typo (`:colum` → `:column`)
- There's a small set of valid options
- The difference is <= 2 characters

❌ Don't use when:
- Too many valid options (> 10)
- Options are very different
- Suggestion might be confusing

## Examples by Error Type

### Configuration Errors

For missing or invalid configuration:

```ruby
JSON adapter requires a storage column to be specified.

Setting: :preferences
Model: User

You must specify which JSONB column to store the setting in.

Fix by adding storage configuration:
  setting :preferences,
    type: :json,
    storage: {column: :settings_json}
```

### Type Errors

For invalid types with suggestions:

```ruby
Unknown storage type: :colum for setting :enabled

Location: User

Available storage types:
  - :column      (stores in database column)
  - :json        (stores in JSONB column)
  - :store_model (stores using StoreModel gem)

Did you mean: "column"?

Example usage:
  setting :enabled, type: :column, default: false
```

### Dependency Errors

For graph/cycle problems:

```ruby
Cycle detected in sync dependencies: :a → :b → :a

Sync relationships cannot form cycles. Each setting can only sync in one direction.

To fix this issue:
  1. Remove one of the sync relationships to break the cycle
  2. Choose a clear direction for data flow

Example fix:
  # Before (creates cycle):
  setting :a, sync: {target: :b, mode: :forward}
  setting :b, sync: {target: :a, mode: :forward}  # ❌ Creates cycle

  # After (no cycle):
  setting :a, sync: {target: :b, mode: :forward}  # ✓ Clear direction
  setting :b  # Remove sync
```

### Module Conflict Errors

For exclusive group violations:

```ruby
Cannot use multiple modules from the 'authorization' exclusive group.

Active modules: :roles, :pundit

These modules are mutually exclusive because they provide conflicting
functionality. You must choose only ONE module from this group.

To fix this issue:
  1. Decide which module best fits your needs
  2. Remove the include statement for other modules

Example for authorization modules:
  # Choose ONE of these:
  include ModelSettings::Modules::Roles        # Simple RBAC
  include ModelSettings::Modules::Pundit       # Pundit integration
  include ModelSettings::Modules::ActionPolicy # ActionPolicy integration
```

## Testing Error Messages

### Unit Tests

Test each error message method directly:

```ruby
describe ".adapter_configuration_error" do
  context "when adapter type is :json" do
    let(:error_message) do
      described_class.adapter_configuration_error(:json, setting, model_class)
    end

    it "includes the setting name" do
      expect(error_message).to include(":test_setting")
    end

    it "includes fix instructions with storage configuration" do
      expect(error_message).to include("storage: {column: :settings_json}")
    end

    it "includes migration hint" do
      expect(error_message).to include("add_column :users, :settings_json, :jsonb")
    end
  end
end
```

### Integration Tests

Test that errors are raised correctly in actual usage:

```ruby
context "when storage column is missing for JSON adapter" do
  it "raises ArgumentError with improved message", :aggregate_failures do
    expect do
      TestModel.setting :test, type: :json
    end.to raise_error(ArgumentError) do |error|
      expect(error.message).to include("JSON adapter requires a storage column")
      expect(error.message).to include(":test")
      expect(error.message).to include("TestModel")
      expect(error.message).to include("storage: {column: :settings_json}")
    end
  end
end
```

### Testing "Did You Mean"

Test the suggestion algorithm:

```ruby
context "when type is close to a valid type" do
  it "suggests the correct type using did_you_mean" do
    error = described_class.unknown_storage_type_error(:colum, setting, model_class)
    expect(error).to include('Did you mean: "column"?')
  end
end

context "when type is completely invalid" do
  it "does not include did_you_mean suggestion" do
    error = described_class.unknown_storage_type_error(:xyz, setting, model_class)
    expect(error).not_to include("Did you mean:")
  end
end
```

## Checklist for New Error Messages

When adding a new error message:

- [ ] Error describes **what** went wrong clearly
- [ ] Error shows **where** it happened (setting name, model)
- [ ] Error explains **why** it's a problem
- [ ] Error provides **how** to fix it (step-by-step)
- [ ] Error includes **code example** showing the fix
- [ ] Error includes migration hints if database changes needed
- [ ] Error uses "did you mean" if appropriate
- [ ] Error is added to `ErrorMessages` module
- [ ] Error has unit tests
- [ ] Error has integration tests
- [ ] Existing tests updated if error message changed

## Anti-Patterns to Avoid

### ❌ Generic Messages

```ruby
raise ArgumentError, "Invalid configuration"
raise ArgumentError, "Something went wrong"
```

### ❌ Technical Jargon Only

```ruby
raise ArgumentError, "Adjacency list cycle detected in DAG"
# Better: "Cycle detected in sync dependencies: :a → :b → :a"
```

### ❌ No Context

```ruby
raise ArgumentError, "Column not specified"
# Missing: Which setting? Which model? Which adapter?
```

### ❌ No Fix Instructions

```ruby
raise ArgumentError, "JSON adapter configuration error"
# Missing: How to fix it? What configuration is needed?
```

### ❌ Inline Error Strings

```ruby
# Bad: Error string defined at call site
raise ArgumentError, "JSON adapter requires..."

# Good: Error defined in ErrorMessages module
raise ArgumentError, ErrorMessages.adapter_configuration_error(...)
```

## Maintenance

When updating error messages:

1. **Update the ErrorMessages module** - Single source of truth
2. **Update affected tests** - Change regex patterns if needed
3. **Test manually** - Trigger the error and verify it looks good
4. **Document in CHANGELOG** - Under "Developer Experience" section

## Resources

- **Implementation**: `lib/model_settings/error_messages.rb`
- **Tests**: `spec/model_settings/error_messages_spec.rb`
- **Integration tests**: Check adapter, dependency_engine, documentation, and module_registry specs
- **Examples**: See any error in the ErrorMessages module

## Summary

Good error messages are:
- **Clear** - Easy to understand
- **Specific** - Include context
- **Actionable** - Show how to fix
- **Educational** - Explain why it's wrong
- **Consistent** - Follow the same structure

By following these principles, ModelSettings provides a developer-friendly experience that helps users quickly understand and resolve issues.
