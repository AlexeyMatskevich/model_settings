# Module Development API - Rails-Way Architecture (v2)

**Дата**: 2025-11-02
**Статус**: Design Phase (Updated)
**Приоритет**: 🔴 CRITICAL
**Sprint**: 11 (перед Sprint 13)

---

## Ключевое решение: Rails Callbacks вместо Custom Hooks

### ❌ Проблема старого подхода (v1):

Мы пытались создать **собственную систему hooks** параллельную Rails:

```ruby
# ❌ Кастомные hooks - НЕ Rails way
ModuleRegistry.on_setting_defined do |setting|
  validate_setting(setting)
end

ModuleRegistry.on_settings_compiled do |settings|
  # ...
end
```

**Проблемы**:
- Разработчики должны учить новый API
- Дублирование концепций Rails callbacks
- Нет контроля когда hook выполняется
- Нет стандартных фич Rails (prepend, if, unless)

---

### ✅ Решение: Использовать Rails Callbacks

**Принцип**:
> Модули регистрируются в **стандартных Rails callbacks**.
> ModelSettings предоставляет callbacks для settings.
> Модули сами выбирают КОГДА они выполняются.

```ruby
# ✅ Rails way - стандартные callbacks
module PunditModule
  extend ActiveSupport::Concern

  included do
    # Модуль сам выбирает callback
    before_validation :validate_authorization_settings
  end

  def validate_authorization_settings
    # Валидация в стандартном Rails lifecycle
  end
end
```

**Преимущества**:
- ✅ Знакомо Rails разработчикам
- ✅ Модули контролируют КОГДА выполняются
- ✅ Все фичи Rails callbacks (prepend, if, unless, etc.)
- ✅ Консистентно с Rails экосистемой

---

## Архитектура: 3 уровня callbacks

### Level 1: Rails Model Callbacks (стандартные)

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  # Стандартные Rails callbacks работают как обычно:
  before_validation :normalize_email
  before_save :check_permissions
  after_commit :send_notification
end

# Lifecycle:
# before_validation ← Здесь можем валидировать settings
# validations
# after_validation
# before_save
# before_create/update
# SQL INSERT/UPDATE
# after_create/update
# after_save
# after_commit/rollback ← Здесь можем обработать изменения settings
```

---

### Level 2: Settings-Specific Callbacks (добавляем в ModelSettings)

ModelSettings добавляет **callbacks для каждого setting**:

```ruby
# lib/model_settings/callbacks.rb

module Callbacks
  extend ActiveSupport::Concern

  included do
    # Добавляем settings callbacks в Rails lifecycle
    before_validation :run_settings_before_validation_callbacks
    after_validation :run_settings_after_validation_callbacks
    after_rollback :run_settings_after_rollback_callbacks
  end

  private

  def run_settings_before_validation_callbacks
    self.class.all_settings_recursive.each do |setting|
      # Выполнить before_validation для этого setting
      execute_setting_callbacks(setting, :before_validation)
    end
  end

  def run_settings_after_validation_callbacks
    self.class.all_settings_recursive.each do |setting|
      execute_setting_callbacks(setting, :after_validation)
    end
  end

  def run_settings_after_rollback_callbacks
    # После rollback транзакции
    # Консистентно с after_change_commit
    self.class.all_settings_recursive.each do |setting|
      execute_setting_callbacks(setting, :after_change_rollback)
    end
  end
end
```

**Новые callbacks для settings**:
```ruby
setting :premium,
        before_validation: :check_premium_eligibility,
        after_validation: :log_premium_validation,
        after_change_rollback: :handle_rollback
```

---

### Level 3: Module Developer API (модули выбирают callback)

Модули регистрируются в **стандартных Rails callbacks**:

```ruby
module ModelSettings
  module Modules
    module Pundit
      extend ActiveSupport::Concern

      included do
        # Модуль сам выбирает КОГДА выполняться
        before_validation :validate_pundit_authorization_settings

        # Опционально: регистрируем конфигурацию
        ModelSettings::ModuleRegistry.register_module_callback_config(
          :pundit,
          default_callback: :before_validation,  # По умолчанию
          configurable: true                      # Можно изменить глобально
        )
      end

      # Метод который вызовется в before_validation
      def validate_pundit_authorization_settings
        self.class.all_settings_recursive.each do |setting|
          validate_setting_authorization(setting)
        end
      end
    end
  end
end
```

**Глобальная конфигурация** (разумные настройки + гибкость):

```ruby
# config/initializers/model_settings.rb

ModelSettings.configure do |config|
  # Переопределить на каком callback работает Pundit
  config.module_callback(:pundit, :before_save)  # Вместо before_validation

  # Или для всех authorization модулей:
  config.authorization_callback = :before_save
end
```

---

## Волновая регистрация по уровням вложенности

### Проблема: Зависимость child от parent

```ruby
setting :billing, viewable_by: [:admin] do
  setting :invoices, viewable_by: :inherit  # Зависит от parent!
end

# Если :invoices обрабатывается ДО :billing:
# ❌ :billing еще не провалидирован
# ❌ Невозможно унаследовать viewable_by

# Если обрабатывается ПОСЛЕ:
# ✅ :billing уже провалидирован
# ✅ Можно безопасно наследовать
```

---

### Решение: Волновая регистрация

**Алгоритм**:
1. Проходим settings в порядке определения
2. Группируем по уровням вложенности (depth)
3. Обрабатываем волнами: Level 0 → Level 1 → Level 2 → ...

```ruby
# Определение:
setting :billing do              # Level 0, порядок: 1
  setting :invoices do           # Level 1, порядок: 1
    setting :tax_reports         # Level 2, порядок: 1
  end
  setting :payments              # Level 1, порядок: 2
end

setting :api_access              # Level 0, порядок: 2

# Волновая обработка:
# Wave 0: :billing (1), :api_access (2)      ← В порядке определения
# Wave 1: :invoices (1), :payments (2)       ← В порядке определения
# Wave 2: :tax_reports (1)                   ← В порядке определения
```

**Реализация**:

```ruby
module ClassMethods
  def compile_settings!
    return if _settings_compiled

    # 1. Группируем settings по уровням вложенности
    settings_by_level = group_settings_by_depth

    # 2. Обрабатываем волнами (Level 0, 1, 2, ...)
    max_level = settings_by_level.keys.max || 0

    (0..max_level).each do |level|
      settings_at_level = settings_by_level[level] || []

      # В порядке определения внутри уровня
      settings_at_level.each do |setting|
        setup_setting_adapter(setting)
        setup_setting_validations(setting)
        setup_setting_callbacks(setting)
      end
    end

    # 3. Выполняем compilation hooks
    ModelSettings::ModuleRegistry.execute_compilation_hooks(
      all_settings_recursive,
      self
    )

    # 4. Компилируем dependency engine
    self._dependency_engine = DependencyEngine.new(self)
    _dependency_engine.compile!

    self._settings_compiled = true
  end

  private

  def group_settings_by_depth
    settings_by_level = Hash.new { |h, k| h[k] = [] }

    all_settings_recursive.each do |setting|
      level = calculate_depth(setting)
      settings_by_level[level] << setting
    end

    settings_by_level
  end

  def calculate_depth(setting)
    depth = 0
    current = setting.parent
    while current
      depth += 1
      current = current.parent
    end
    depth
  end
end
```

---

## Decisions Made ✅

### 1. Merge Strategies ✅ APPROVED

**Реализуем 3 стратегии**:
- `:replace` (default)
- `:append` (для Array)
- `:merge` (для Hash)

### 2. Validation Timing ✅ APPROVED

**Hybrid approach**: `:strict` (default) и `:collect` (опционально)

### 3. Callbacks Architecture ✅ APPROVED - Rails Way

**Три уровня**:
1. **Rails Model Callbacks** - стандартные (before_validation, after_commit, etc.)
2. **Settings Callbacks** - для каждого setting (before_validation, after_validation, after_change_rollback)
3. **Module Callbacks** - модули сами выбирают когда выполняться

**Ключевые решения**:
- ✅ Callbacks для каждого setting отдельно
- ✅ `after_change_rollback` (консистентно с `after_change_commit`)
- ✅ Rails сам управляет rollback, мы просто регистрируем callback
- ✅ Волновая регистрация: Level 0 → Level 1 → Level 2 (в порядке определения)
- ✅ Модуль сам выбирает callback + глобальная конфигурация для гибкости

---

## Implementation Plan (Updated)

### Phase 1: Rails Callbacks Integration (3 дня)

**Задачи**:

1. **Добавить settings callbacks в ModelSettings::Callbacks**:
   ```ruby
   # lib/model_settings/callbacks.rb

   # Добавить новые callbacks:
   - before_validation callbacks для settings
   - after_validation callbacks для settings
   - before_destroy callbacks для settings (с prepend support)
   - after_destroy callbacks для settings
   - after_change_rollback callbacks для settings (консистентно с after_change_commit)
   ```

2. **Расширить Setting class для хранения callbacks**:
   ```ruby
   # lib/model_settings/setting.rb

   class Setting
     # Callback definitions
     attr_accessor :before_validation_callback
     attr_accessor :after_validation_callback
     attr_accessor :before_destroy_callback
     attr_accessor :after_destroy_callback
     attr_accessor :after_change_rollback_callback

     # Callback options (if, unless, on, prepend)
     attr_accessor :callback_options
   end
   ```

3. **DSL для регистрации callbacks с Rails параметрами**:
   ```ruby
   setting :premium,
           before_validation: :check_eligibility,
           after_validation: :log_validation,
           before_destroy: :cleanup_premium_data,
           after_destroy: :audit_deletion,
           after_change_rollback: :handle_rollback,
           # Rails callback параметры:
           if: :admin?,
           unless: :guest?,
           on: :create,
           prepend: true  # Только для before_destroy
   ```

4. **Парсинг и валидация callback параметров**:
   ```ruby
   def parse_callback_options(options)
     callback_opts = {}

     # Extract Rails callback parameters
     callback_opts[:if] = options.delete(:if) if options.key?(:if)
     callback_opts[:unless] = options.delete(:unless) if options.key?(:unless)
     callback_opts[:on] = options.delete(:on) if options.key?(:on)
     callback_opts[:prepend] = options.delete(:prepend) if options.key?(:prepend)

     # Validate prepend only for before_destroy
     if callback_opts[:prepend] && !options.key?(:before_destroy)
       raise ArgumentError, "prepend option is only available for before_destroy"
     end

     callback_opts
   end
   ```

5. **Выполнение callbacks с учетом параметров**:
   ```ruby
   def execute_setting_callback(setting, callback_name)
     callback = setting.public_send("#{callback_name}_callback")
     return unless callback

     options = setting.callback_options || {}

     # Проверяем условия if/unless
     return false if options[:if] && !evaluate_condition(options[:if])
     return false if options[:unless] && evaluate_condition(options[:unless])

     # Проверяем on: :create/:update
     return false if options[:on] && !matches_action?(options[:on])

     # Выполняем callback
     public_send(callback)
   end
   ```

**Тесты**: ~40 examples (добавлены тесты для всех Rails параметров)

---

### Phase 2: Волновая регистрация (1 день)

**Задачи**:

1. **Группировка settings по depth**:
   ```ruby
   def group_settings_by_depth
     # Группируем по уровням вложенности
   end
   ```

2. **Волновая компиляция**:
   ```ruby
   def compile_settings!
     # Level 0 → Level 1 → Level 2 → ...
   end
   ```

3. **Тесты для порядка обработки**:
   ```ruby
   RSpec.describe "Wave-based compilation" do
     it "processes Level 0 before Level 1"
     it "processes settings in definition order within each level"
     it "allows child to access parent during validation"
   end
   ```

**Тесты**: ~20 examples

---

### Phase 3: Module Callback Configuration API (2 дня)

**Задачи**:

1. **Module Registry: регистрация конфигурации**:
   ```ruby
   # lib/model_settings/module_registry.rb

   def register_module_callback_config(module_name, **config)
     @module_callback_configs ||= {}
     @module_callback_configs[module_name] = config
   end
   ```

2. **Global Configuration API**:
   ```ruby
   # lib/model_settings/configuration.rb

   def module_callback(module_name, callback_name)
     # Переопределить callback для модуля
   end

   attr_accessor :authorization_callback  # Для всех auth модулей
   ```

3. **Refactor Pundit/ActionPolicy/Roles**:
   ```ruby
   module Pundit
     included do
       # Регистрируем конфигурацию
       register_module_callback_config(
         :pundit,
         default_callback: :before_validation,
         configurable: true
       )

       # Используем сконфигурированный callback
       callback = resolve_module_callback(:pundit)
       send(callback, :validate_pundit_authorization)
     end
   end
   ```

**Тесты**: ~25 examples

---

### Phase 4: Configurable Inheritable Options (2 дня) ⭐ NEW

**Задачи**:

1. **Configuration: inheritable_options с auto-population**:
   ```ruby
   # lib/model_settings/configuration.rb

   class Configuration
     def initialize
       @inheritable_options = []
       @inheritable_options_explicitly_set = false
     end

     # Setter - пользователь явно устанавливает список
     def inheritable_options=(options)
       @inheritable_options = options
       @inheritable_options_explicitly_set = true  # Помечаем что явно установлен
     end

     # Getter
     def inheritable_options
       @inheritable_options
     end

     # Модули используют это для добавления своих опций
     def add_inheritable_option(option_name)
       # Если список был явно установлен пользователем - НЕ мутируем
       return if @inheritable_options_explicitly_set

       # Добавляем только если еще нет
       @inheritable_options << option_name unless @inheritable_options.include?(option_name)
     end

     # Проверка: был ли список установлен явно
     def inheritable_options_explicitly_set?
       @inheritable_options_explicitly_set
     end
   end
   ```

2. **Per-model configuration**:
   ```ruby
   # lib/model_settings/dsl.rb

   module ClassMethods
     def settings_config(**options)
       # Поддержка inheritable_options:
       if options.key?(:inheritable_options)
         @_inheritable_options = options[:inheritable_options]
       end
     end

     def inheritable_options
       @_inheritable_options || ModelSettings.configuration.inheritable_options
     end
   end
   ```

3. **InheritanceResolver: проверка inheritable_options**:
   ```ruby
   def resolve(setting, option_name, visited = Set.new)
     # Если опция НЕ в inheritable_options:
     unless inheritable?(option_name, setting)
       # Наследуется только с explicit :inherit
       return setting.options[option_name] unless setting.options[option_name] == :inherit
     end

     # Если опция в inheritable_options:
     # Автоматическое наследование (как сейчас работает)
     # ...
   end

   def inheritable?(option_name, setting)
     model_class = setting.model_class
     model_class.inheritable_options.include?(option_name)
   end
   ```

4. **Модули регистрируют И добавляют свои опции (если не переопределено)**:
   ```ruby
   module Pundit
     included do
       # Регистрируем в реестре (для валидации)
       ModuleRegistry.register_inheritable_option(:authorize_with)

       # Добавляем в inheritable_options (если пользователь НЕ переопределил)
       ModelSettings.configuration.add_inheritable_option(:authorize_with)
     end
   end

   module Roles
     included do
       # Регистрация и добавление
       ModuleRegistry.register_inheritable_option(:viewable_by)
       ModelSettings.configuration.add_inheritable_option(:viewable_by)

       ModuleRegistry.register_inheritable_option(:editable_by)
       ModelSettings.configuration.add_inheritable_option(:editable_by)
     end
   end

   # Результат (если пользователь НЕ переопределил):
   # config.inheritable_options = [:authorize_with, :viewable_by, :editable_by]
   ```

**Сценарий 1: Default поведение (модули добавляют свои опции)**:
   ```ruby
   # Пользователь НЕ устанавливает inheritable_options явно
   ModelSettings.configure do |config|
     # inheritable_options не трогаем
   end

   class User < ApplicationRecord
     include ModelSettings::DSL
     include ModelSettings::Modules::Pundit  # Добавляет :authorize_with
     include ModelSettings::Modules::Roles   # Добавляет :viewable_by, :editable_by
   end

   # Результат:
   # config.inheritable_options = [:authorize_with, :viewable_by, :editable_by]
   # ✅ Все опции модулей наследуются автоматически (разумные defaults)
   ```

**Сценарий 2: Пользователь переопределяет список (контроль)**:
   ```ruby
   # Пользователь ЯВНО устанавливает список
   ModelSettings.configure do |config|
     config.inheritable_options = [:viewable_by]  # Только это!
   end

   class User < ApplicationRecord
     include ModelSettings::DSL
     include ModelSettings::Modules::Pundit  # Пытается добавить :authorize_with
     include ModelSettings::Modules::Roles   # Уже есть :viewable_by, :editable_by не добавляется
   end

   # Результат:
   # config.inheritable_options = [:viewable_by]  # Не изменился!
   # ✅ :authorize_with НЕ наследуется (пользователь контролирует)
   # ✅ :viewable_by наследуется
   # ✅ :editable_by НЕ наследуется (пользователь контролирует)
   ```

5. **ModuleRegistry: register_inheritable_option**:
   ```ruby
   # lib/model_settings/module_registry.rb

   class << self
     # Реестр опций которые МОГУТ наследоваться
     def registered_inheritable_options
       @registered_inheritable_options ||= Set.new
     end

     # Модуль регистрирует что его опция может наследоваться
     def register_inheritable_option(option_name)
       registered_inheritable_options << option_name
     end

     # Проверка: может ли опция наследоваться
     def inheritable_option?(option_name)
       registered_inheritable_options.include?(option_name)
     end
   end
   ```

6. **Опциональная валидация при explicit set**:
   ```ruby
   # lib/model_settings/configuration.rb

   def inheritable_options=(options)
     @inheritable_options = options
     @inheritable_options_explicitly_set = true

     # Опционально: предупреждение если опция не зарегистрирована
     options.each do |option|
       unless ModuleRegistry.inheritable_option?(option)
         warn "[ModelSettings] Warning: Option #{option.inspect} is not registered " \
              "as inheritable. Make sure the module that provides this option is loaded."
       end
     end
   end
   ```

**Тесты**: ~40 examples
- ✅ Default: модули автоматически добавляют свои опции
- ✅ Explicit set: пользователь контролирует список (модули НЕ мутируют)
- ✅ Per-model конфигурация переопределяет глобальную
- ✅ Автоматическое наследование для опций в списке
- ✅ Explicit `:inherit` для опций НЕ в списке
- ✅ Флаг `inheritable_options_explicitly_set?` работает корректно
- ✅ Warning при установке незарегистрированной опции

---

### Phase 5: Merge Strategies Implementation (2 дня)

**Задачи**:

1. **ModuleRegistry: register_option с merge_strategy**:
   ```ruby
   register_option(
     :viewable_by,
     type: Array,
     inheritable: true,
     merge_strategy: :append  # ← Критично!
   )
   ```

2. **InheritanceResolver: применение merge_strategy**:
   ```ruby
   def resolve(setting, option_name)
     parent_value = resolve_from_parent(setting, option_name)
     child_value = setting.options[option_name]

     # Применяем merge_strategy
     merge_values(parent_value, child_value, option_name)
   end

   def merge_values(parent_value, child_value, option_name)
     option_meta = ModuleRegistry.option_metadata(option_name)
     strategy = option_meta[:merge_strategy] || :replace

     case strategy
     when :replace
       child_value
     when :append
       (parent_value || []) + (child_value || [])
     when :merge
       (parent_value || {}).merge(child_value || {})
     end
   end
   ```

3. **Тесты для всех 3 стратегий**:
   - :replace (default)
   - :append (Array)
   - :merge (Hash)

**Тесты**: ~40 examples

---

### Phase 6: Validation Timing (1 день)

**Задачи**:

1. **Configuration: validation_mode**:
   ```ruby
   config.validation_mode = :strict   # или :collect
   ```

2. **Collect mode implementation**:
   ```ruby
   # В :collect mode - накапливать ошибки
   # Показать все при compile_settings!
   ```

**Тесты**: ~15 examples

---

### Phase 7: Documentation (1 день)

**Файлы**:
- `docs/guides/module_development.md` - Guide для разработчиков модулей
- `docs/api/callbacks.md` - Callbacks API reference
- `docs/api/module_registry.md` - Module Registry API
- Примеры в `examples/custom_module/`

---

## Total Estimate: ~12 дней (~2.5 недели)

**Breakdown**:
- Phase 1: Rails Callbacks Integration (3 дня) - добавлены destroy callbacks и Rails параметры
- Phase 2: Волновая регистрация (1 день)
- Phase 3: Module Callback Configuration API (2 дня)
- Phase 4: Configurable Inheritable Options (2 дня) ⭐ NEW - полностью настраиваемое наследование
- Phase 5: Merge Strategies Implementation (2 дня)
- Phase 6: Validation Timing (1 день)
- Phase 7: Documentation (1 день)

---

## Decisions on Open Questions ✅

### Q1: Prepend и все Rails callback параметры ✅ APPROVED

**Решение**:
1. **Добавить `before_destroy` и `after_destroy` callbacks**
2. **Прокидывать ВСЕ параметры Rails callbacks** при регистрации

**Rails callback параметры** (будут доступны):
```ruby
setting :premium,
        before_validation: :check_eligibility,
        if: :admin?,                    # Условие
        unless: :guest?,                # Обратное условие
        on: :create,                    # Только при create
        prepend: true                   # Только для before_destroy

# Полный список параметров Rails:
# - if: условие выполнения
# - unless: обратное условие
# - on: :create / :update / :save
# - prepend: true (только для before_destroy)
```

**Module Developer API** (опционально):
```ruby
module CustomModule
  included do
    # Модуль может использовать prepend если нужно
    before_validation :critical_check, prepend: true
  end
end
```

**Вывод**: Порядок include достаточен для большинства кейсов, но prepend доступен если нужен.

---

### Q2: Class-level callbacks ⏸️ REQUIRES CLARIFICATION

**Вопрос пользователя**:
> "В каких случаях мы действительно захотим делать такую неявную операцию с изменением значений settings?"

**Потенциальные кейсы**:

1. **Documentation generation** (при определении класса):
   ```ruby
   # Class загружается:
   class User
     setting :premium  # ← Генерируем документацию
   end
   ```

2. **Setting enhancement** (добавление метаданных):
   ```ruby
   module EnhancerModule
     on_setting_defined do |setting|
       setting.metadata[:enhanced_at] = Time.current
     end
   end
   ```

3. **Validation setup** (регистрация валидаторов):
   ```ruby
   module AutoValidation
     on_setting_defined do |setting|
       # Автоматически добавляем валидатор на основе типа
     end
   end
   ```

**Вопрос**: Нужны ли такие кейсы? Или модули должны работать только с **runtime** (instance callbacks)?

**Мое предположение**:
- Оставить существующие `on_setting_defined` и `on_settings_compiled` (они уже есть)
- Но не расширять их пока нет явного кейса

**Требует уточнения**: Видишь ли ты реальные кейсы для class-level модификаций?

---

### Q3: Callback Inheritance + Configurable Inheritable Options ✅ APPROVED

**Решение**: Вариант C + Полностью конфигурируемый список наследуемых опций!

#### Часть 1: Explicit `:inherit` для callbacks

```ruby
setting :billing,
        before_validation: :check_billing_rules,
        after_validation: :log_validation do

  # Явное наследование:
  setting :invoices,
          before_validation: :inherit,  # Наследует :check_billing_rules
          after_validation: :inherit    # Наследует :log_validation

  # Можно переопределить:
  setting :payments,
          before_validation: :check_payment_rules  # Не наследует
end
```

#### Часть 2: Глобальная конфигурация дефолтного поведения

```ruby
ModelSettings.configure do |config|
  # Список DSL опций которые наследуются по умолчанию
  config.inheritable_options = [
    :authorize_with,      # Authorization
    :viewable_by,         # RBAC view
    :editable_by,         # RBAC edit
    :before_validation,   # Callbacks
    :after_validation,    # Callbacks
    :default              # Значения по умолчанию
  ]

  # Или расширить существующий список:
  config.inheritable_options << :my_custom_option
end
```

#### Часть 3: Per-model конфигурация

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL

  # Переопределить для этой модели:
  settings_config inheritable_options: [
    :authorize_with,  # Только authorization наследуется
    :viewable_by      # И RBAC
    # Callbacks НЕ наследуются для User
  ]

  setting :billing, before_validation: :check do
    setting :invoices  # НЕ наследует before_validation (отключено)
  end
end
```

#### Часть 4: Поведение наследования

```ruby
# По умолчанию (если опция в inheritable_options):
setting :parent, authorize_with: :manage? do
  setting :child  # Автоматически наследует authorize_with = :manage?
end

# Explicit :inherit всегда работает (даже если опция НЕ в inheritable_options):
setting :parent, custom_option: :value do
  setting :child, custom_option: :inherit  # Наследует даже если не в списке
end

# Переопределение:
setting :parent, authorize_with: :manage? do
  setting :child, authorize_with: :view?  # Переопределяет (НЕ наследует)
end
```

**Преимущества**:
- ✅ Гибкость: можно настроить что наследуется глобально
- ✅ Контроль: можно переопределить per-model
- ✅ Explicit: можно явно указать `:inherit` для любой опции
- ✅ Расширяемость: модули могут добавлять свои опции в список

---

## Next Steps ✅ READY TO START

1. ✅ **Q1 Resolved**: Prepend и Rails callback параметры - добавляем
2. ✅ **Q2 Clarified**: Class-level vs Instance-level - два независимых механизма
3. ✅ **Q3 Resolved**: Configurable inheritable options - модули регистрируют, пользователь выбирает
4. ✅ **План финализирован** - все вопросы решены!
5. 🚀 **Готов начинать Phase 1**: Rails Callbacks Integration
6. **Обновить roadmap** Sprint 11 с финальным планом

---

## Clarification: Class-Level vs Instance-Level Callbacks (Q2) ✅

**Важное уточнение от пользователя**:

### `on_setting_defined` / `on_settings_compiled` - Module Developer API

Это **НЕ** callbacks для конкретных settings, это **class-level hooks для МОДУЛЕЙ**:

```ruby
# Module Developer API (class-level)
module MyModule
  included do
    # Hook для MODULE разработчика
    ModuleRegistry.on_setting_defined do |setting, model_class|
      # Выполняется когда ЛЮБОЙ setting определяется
      # Модуль может обработать setting
      setting.metadata[:processed_by_module] = true
    end

    ModuleRegistry.on_settings_compiled do |settings, model_class|
      # Выполняется после компиляции ВСЕХ settings
      # Модуль может сделать что-то со всеми settings сразу
    end
  end
end
```

### `before_validation` и т.д. - User API для settings

Это **instance-level callbacks для конкретного setting**:

```ruby
# User API (instance-level)
class User < ApplicationRecord
  include ModelSettings::DSL

  # Callback для конкретного setting
  setting :premium,
          before_validation: :check_eligibility,
          after_validation: :log_validation

  def check_eligibility
    # Выполняется для инстанса при валидации ЭТОГО setting
  end
end
```

**Это разные уровни!**
- `on_setting_defined` - для разработчиков МОДУЛЕЙ (class-level)
- `before_validation` - для ПОЛЬЗОВАТЕЛЕЙ библиотеки (instance-level)

**Решение**:
- ✅ Оставить `on_setting_defined` и `on_settings_compiled` как есть (они нужны для Module Developer API)
- ✅ Добавить `before_validation`, `after_validation` и т.д. для User API (instance callbacks)
- ✅ Это два независимых механизма, оба нужны

---

## References

- Current implementation: `lib/model_settings/callbacks.rb`
- Module system: `lib/model_settings/module_registry.rb`
- Sprint 11 roadmap: `llm_docs/implementation_roadmap.md`
- Design questions (v1): `docs/architecture/module_api_design_questions.md`
