# Module Development API - Детальный Разбор Вопросов

**Дата**: 2025-11-02

---

## Вопрос 1: Merge Strategies для Наследования

### Проблема: Как комбинировать значения parent и child?

Когда child setting наследует значение от parent, возникает вопрос: **что делать если у child есть свое значение?**

---

### Кейс 1: Simple Replace (текущее поведение)

**Сценарий**: Policy-based authorization (Pundit, ActionPolicy)

```ruby
setting :billing,
        authorize_with: :manage_billing? do

  # Child ПЕРЕОПРЕДЕЛЯЕТ значение родителя
  setting :invoices,
          authorize_with: :view_invoices?

  # Результат: :view_invoices? (НЕ :manage_billing?)
end
```

**Почему `:replace`?**
- Для `authorize_with` нельзя "объединить" два метода policy
- Либо используется родительский, либо дочерний
- Нет смысла в "merge"

**Стратегия**: `:replace` (default)
```ruby
child_value = :view_invoices?
parent_value = :manage_billing?
result = child_value  # Просто заменяем
```

---

### Кейс 2: Array Append (новое поведение для Roles)

**Сценарий**: RBAC с несколькими ролями

```ruby
# ПРОБЛЕМА: Как это должно работать?
setting :admin_panel,
        viewable_by: [:admin, :super_admin] do

  # Вопрос: Что должно получиться?
  setting :users_management,
          viewable_by: [:hr_manager]

  # Вариант A (Replace): viewable_by = [:hr_manager]
  #   ❌ Потеряли :admin и :super_admin!
  #   ❌ Теперь admin не может видеть users_management!

  # Вариант B (Append): viewable_by = [:admin, :super_admin, :hr_manager]
  #   ✅ Сохранили родительские права
  #   ✅ Добавили новые права
  #   ✅ Admin по-прежнему может видеть
end
```

**Реальный кейс использования**:

```ruby
class Organization < ApplicationRecord
  include ModelSettings::DSL
  include ModelSettings::Modules::Roles

  # Уровень 1: Базовые настройки (только admin)
  setting :settings,
          viewable_by: [:admin],
          editable_by: [:admin] do

    # Уровень 2: Биллинг (admin + finance)
    setting :billing,
            viewable_by: [:finance_manager],  # Добавляем finance
            editable_by: [:finance_manager] do

      # Уровень 3: Инвойсы (admin + finance + accountant)
      setting :invoices,
              viewable_by: [:accountant]  # Добавляем accountant

      # ОЖИДАНИЕ:
      # invoices.viewable_by = [:admin, :finance_manager, :accountant]
      #
      # НЕ [:accountant] !!!
    end
  end
end
```

**Почему это важно?**

Представь иерархию прав доступа:
```
Organization Settings (admin only)
  └─ Billing (admin + finance)
      └─ Invoices (admin + finance + accountant)
          └─ Tax Reports (admin + finance + accountant + auditor)
```

Если использовать `:replace`, то на каждом уровне придется **явно перечислять ВСЕ роли выше**:

```ruby
# ❌ С :replace стратегией (УЖАСНО!)
setting :tax_reports,
        viewable_by: [:admin, :finance_manager, :accountant, :auditor],
        #            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
        #            Приходится вручную копировать все роли родителей!
        editable_by: [:admin, :finance_manager, :accountant, :auditor]
```

```ruby
# ✅ С :append стратегией (ОТЛИЧНО!)
setting :tax_reports,
        viewable_by: [:auditor],  # Просто добавляем новую роль
        editable_by: [:auditor]   # Родительские роли наследуются автоматически
```

**Стратегия**: `:append`
```ruby
child_value = [:accountant]
parent_value = [:admin, :finance_manager]
result = parent_value + child_value  # => [:admin, :finance_manager, :accountant]
```

---

### Кейс 3: Hash Merge (гипотетический кейс)

**Сценарий**: Модуль с конфигурацией в Hash

Представь гипотетический модуль "Versioning":

```ruby
module Versioning
  included do
    register_option(
      :version_config,
      type: Hash,
      inheritable: true,
      merge_strategy: :merge
    )
  end
end
```

**Использование**:

```ruby
setting :documents,
        version_config: {
          max_versions: 10,
          retention_days: 365,
          track_changes: true
        } do

  # Child хочет переопределить ТОЛЬКО max_versions
  setting :contracts,
          version_config: {
            max_versions: 50  # Только это изменяем
          }

  # С :merge стратегией:
  # contracts.version_config = {
  #   max_versions: 50,         # Переопределено
  #   retention_days: 365,      # Унаследовано
  #   track_changes: true       # Унаследовано
  # }

  # С :replace стратегией:
  # contracts.version_config = {
  #   max_versions: 50          # Только это
  #   # retention_days: ПОТЕРЯНО!
  #   # track_changes: ПОТЕРЯНО!
  # }
end
```

**Реальный кейс** (потенциальный модуль для API settings):

```ruby
module ApiConfiguration
  included do
    register_option(
      :api_config,
      type: Hash,
      merge_strategy: :deep_merge  # Глубокое слияние
    )
  end
end

# Использование:
setting :api,
        api_config: {
          rate_limit: { requests: 100, window: 60 },
          timeout: 30,
          retries: 3
        } do

  setting :admin_api,
          api_config: {
            rate_limit: { requests: 1000 }  # Только requests переопределяем
          }

  # Результат с :deep_merge:
  # {
  #   rate_limit: { requests: 1000, window: 60 },  # Merged!
  #   timeout: 30,                                  # Inherited
  #   retries: 3                                    # Inherited
  # }
end
```

**Стратегия**: `:merge` или `:deep_merge`
```ruby
child_value = { max_versions: 50 }
parent_value = { max_versions: 10, retention_days: 365 }
result = parent_value.merge(child_value)
# => { max_versions: 50, retention_days: 365 }
```

---

### Кейс 4: Set Union (редкий кейс)

**Сценарий**: Модуль для тегов или категорий

```ruby
module Tagging
  included do
    register_option(
      :tags,
      type: Set,
      merge_strategy: :union
    )
  end
end

setting :content,
        tags: Set[:public, :searchable] do

  setting :articles,
          tags: Set[:archived]

  # С :union:
  # articles.tags = Set[:public, :searchable, :archived]

  # Автоматически убирает дубликаты
  setting :news,
          tags: Set[:public, :featured]  # :public уже есть
  # news.tags = Set[:public, :searchable, :featured]
end
```

**Стратегия**: `:union`
```ruby
child_value = Set[:archived]
parent_value = Set[:public, :searchable]
result = parent_value | child_value  # Set union
# => Set[:public, :searchable, :archived]
```

---

### Сводная таблица стратегий:

| Стратегия | Тип данных | Когда использовать | Пример модуля |
|-----------|------------|-------------------|---------------|
| `:replace` | Any | Child полностью переопределяет parent | Pundit (`authorize_with`) |
| `:append` | Array | Child добавляет к parent (список прав) | Roles (`viewable_by`) |
| `:merge` | Hash | Child переопределяет только часть ключей | Versioning, ApiConfig |
| `:deep_merge` | Hash (nested) | Глубокое слияние вложенных хешей | Complex configs |
| `:union` | Set | Объединение без дубликатов | Tagging, Categories |

---

### Мой вывод:

**Нужны минимум 3 стратегии**:
1. `:replace` (default) - для простых значений
2. `:append` - для Array (критично для Roles!)
3. `:merge` - для Hash (будущие модули)

`:union` для Set - можно добавить позже если появится кейс.

---

## Вопрос 2: Validation Timing

### Проблема: Когда валидировать DSL опции?

---

### Вариант A: Валидация при `setting` definition (текущее)

**Как работает сейчас**:

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL
  include ModelSettings::Modules::Pundit

  # ❌ ОШИБКА СРАЗУ при определении класса
  setting :premium,
          authorize_with: "admin"  # String вместо Symbol
  # => ArgumentError: authorize_with must be a Symbol...

  # Дальше этого кода execution не идет
  setting :billing  # Никогда не выполнится
end
```

**Плюсы**:
- ✅ **Fast feedback**: Ошибка видна сразу при загрузке файла
- ✅ **Clear error location**: Stack trace указывает на точную строку в модели
- ✅ **Prevents bad state**: Невалидные настройки не попадают в систему

**Минусы**:
- ❌ **Fails fast, stops loading**: Первая ошибка останавливает загрузку класса
- ❌ **Can't collect all errors**: Видим только первую ошибку, остальные скрыты
- ❌ **Hard to show multiple issues**: Нельзя показать "у вас 5 ошибок в настройках"

---

### Вариант B: Валидация при `compile_settings!` (отложенная)

**Как могло бы работать**:

```ruby
class User < ApplicationRecord
  include ModelSettings::DSL
  include ModelSettings::Modules::Pundit

  # При определении - просто сохраняем, НЕ валидируем
  setting :premium,
          authorize_with: "admin"  # Невалидно, но загружается

  setting :billing,
          authorize_with: [:manage]  # Тоже невалидно

  setting :api_access,
          authorize_with: :admin?  # Валидно
end

# Валидация происходит здесь:
User.compile_settings!
# => ModelSettings::ValidationError: Found 2 validation errors:
#    - Setting 'premium': authorize_with must be a Symbol (got String)
#    - Setting 'billing': authorize_with must be a Symbol (got Array)
```

**Плюсы**:
- ✅ **Collects all errors**: Показывает ВСЕ проблемы сразу
- ✅ **Better DX for fixing**: Разработчик видит все что нужно исправить
- ✅ **Allows partial loading**: Класс загружается даже с ошибками

**Минусы**:
- ❌ **Delayed feedback**: Ошибка видна не сразу
- ❌ **Unclear error location**: Stack trace указывает на `compile_settings!`, не на `setting`
- ❌ **Bad state possible**: Невалидные настройки могут временно существовать

---

### Реальный кейс: Rails environment

**Development**:
```ruby
# В development хочется видеть ВСЕ ошибки сразу
User.compile_settings!
# => Found 5 validation errors:
#    - Setting 'premium': ...
#    - Setting 'billing': ...
#    - Setting 'api_access': ...
#    (и т.д.)

# Разработчик исправляет все 5 за раз, а не по одной
```

**Production**:
```ruby
# В production хочется fail fast
# Лучше не запускать приложение вообще, чем запустить с ошибкой

# При загрузке класса:
setting :premium, authorize_with: "admin"
# => ArgumentError (приложение не запустится)
```

---

### Гибридный подход (рекомендую):

**Идея**: Валидация при `setting`, но с режимом "collect errors"

```ruby
# Конфигурация:
ModelSettings.configure do |config|
  config.validation_mode = :strict      # Default: fail fast
  # config.validation_mode = :collect   # Development: collect all errors
end

# В strict mode (production):
setting :premium, authorize_with: "admin"
# => ArgumentError (сразу)

# В collect mode (development):
setting :premium, authorize_with: "admin"  # Сохраняет ошибку
setting :billing, authorize_with: [:admin]  # Сохраняет ошибку

User.compile_settings!
# => Показывает все накопленные ошибки
```

**Преимущества**:
- ✅ Production: fast fail, clear stack traces
- ✅ Development: видны все ошибки сразу
- ✅ Конфигурируемо под разные окружения

---

### Мой вывод:

**Рекомендую гибридный подход**:
1. По умолчанию: валидация при `setting` (strict mode)
2. Опциональный режим: collect errors (для development)
3. Настраивается через `config.validation_mode`

Это best of both worlds.

---

## Вопрос 3: Hook Priority

### Проблема: Порядок выполнения когда несколько модулей подписаны на один hook

---

### Кейс: Несколько модулей хотят отреагировать на событие

```ruby
# Модуль A: Audit logging
module AuditLog
  included do
    ModuleRegistry.register_hook(
      :on_setting_defined,
      callback: ->(setting, model_class) {
        puts "AUDIT: Setting #{setting.name} defined"
      }
    )
  end
end

# Модуль B: Validation
module CustomValidation
  included do
    ModuleRegistry.register_hook(
      :on_setting_defined,
      callback: ->(setting, model_class) {
        puts "VALIDATION: Checking #{setting.name}"
      }
    )
  end
end

# Модуль C: Documentation generator
module AutoDoc
  included do
    ModuleRegistry.register_hook(
      :on_setting_defined,
      callback: ->(setting, model_class) {
        puts "DOC: Generating docs for #{setting.name}"
      }
    )
  end
end

# Когда срабатывает hook - в каком порядке?
class User < ApplicationRecord
  include ModelSettings::DSL
  include AuditLog
  include CustomValidation
  include AutoDoc

  setting :premium  # Какой hook выполнится первым?
end
```

---

### Вариант 1: FIFO - First In, First Out (порядок регистрации)

**Как работает**:
Hooks выполняются в порядке регистрации (include)

```ruby
class User
  include AuditLog          # 1. Регистрирует hook первым
  include CustomValidation  # 2. Регистрирует hook вторым
  include AutoDoc           # 3. Регистрирует hook третьим

  setting :premium
  # Output:
  # AUDIT: Setting premium defined      (1)
  # VALIDATION: Checking premium        (2)
  # DOC: Generating docs for premium    (3)
end
```

**Плюсы**:
- ✅ Предсказуемо
- ✅ Просто реализовать
- ✅ Понятно разработчику (порядок include = порядок выполнения)

**Минусы**:
- ❌ Сложно контролировать если нужен другой порядок
- ❌ Порядок include может быть не очевиден

---

### Вариант 2: LIFO - Last In, First Out (стек)

**Как работает**:
Последний зарегистрированный hook выполняется первым (как middleware)

```ruby
class User
  include AuditLog          # 3. Выполнится третьим
  include CustomValidation  # 2. Выполнится вторым
  include AutoDoc           # 1. Выполнится первым (последний include)

  setting :premium
  # Output:
  # DOC: Generating docs for premium    (1)
  # VALIDATION: Checking premium        (2)
  # AUDIT: Setting premium defined      (3)
end
```

**Плюсы**:
- ✅ Похоже на Rails middleware/concerns (знакомая семантика)
- ✅ "Обертывающее" поведение

**Минусы**:
- ❌ Менее интуитивно для hooks
- ❌ Противоположно ожидаемому поведению

---

### Вариант 3: Explicit Priority (с приоритетами)

**Как работает**:
Модули могут явно указать приоритет

```ruby
module AuditLog
  included do
    ModuleRegistry.register_hook(
      :on_setting_defined,
      priority: 100,  # Низкий приоритет - выполняется последним
      callback: ->(setting, model_class) {
        puts "AUDIT: Setting #{setting.name} defined"
      }
    )
  end
end

module CustomValidation
  included do
    ModuleRegistry.register_hook(
      :on_setting_defined,
      priority: 0,    # Высокий приоритет - выполняется первым
      callback: ->(setting, model_class) {
        puts "VALIDATION: Checking #{setting.name}"
      }
    )
  end
end

module AutoDoc
  included do
    ModuleRegistry.register_hook(
      :on_setting_defined,
      priority: 50,   # Средний приоритет
      callback: ->(setting, model_class) {
        puts "DOC: Generating docs for #{setting.name}"
      }
    )
  end
end

class User
  include AuditLog          # Не важен порядок include!
  include AutoDoc
  include CustomValidation

  setting :premium
  # Output (отсортировано по priority):
  # VALIDATION: Checking premium        (priority: 0)
  # DOC: Generating docs for premium    (priority: 50)
  # AUDIT: Setting premium defined      (priority: 100)
end
```

**Плюсы**:
- ✅ Максимальный контроль
- ✅ Не зависит от порядка include
- ✅ Четкая семантика важности

**Минусы**:
- ❌ Более сложная реализация
- ❌ Нужно документировать "стандартные" приоритеты
- ❌ Можно создать конфликты приоритетов

---

### Реальный кейс: Validation должен быть первым

```ruby
# ПРОБЛЕМА: Validation должен выполниться ДО документации

module CustomValidation
  included do
    register_hook(:on_setting_defined) do |setting|
      raise "Invalid!" if setting.options[:bad]
    end
  end
end

module AutoDoc
  included do
    register_hook(:on_setting_defined) do |setting|
      generate_docs_for(setting)  # Не должно выполниться для невалидных!
    end
  end
end

# Если порядок wrong:
setting :premium, bad: true
# 1. AutoDoc генерирует документацию
# 2. CustomValidation raises error
# ❌ Документация сгенерирована для невалидного setting!

# Если порядок correct:
# 1. CustomValidation raises error
# 2. AutoDoc не выполняется
# ✅ Документация не генерируется для невалидного
```

---

### Вариант 4: Named Phases (семантические фазы)

**Идея**: Hooks группируются по фазам с явной семантикой

```ruby
ModuleRegistry.register_hook(
  :on_setting_defined,
  phase: :validate,  # Фаза валидации (выполняется первой)
  callback: ...
)

ModuleRegistry.register_hook(
  :on_setting_defined,
  phase: :transform,  # Фаза трансформации (после валидации)
  callback: ...
)

ModuleRegistry.register_hook(
  :on_setting_defined,
  phase: :document,  # Фаза документирования (последняя)
  callback: ...
)

# Фазы выполняются в фиксированном порядке:
# 1. :validate
# 2. :transform
# 3. :document
# 4. :audit

# Внутри фазы - FIFO (порядок регистрации)
```

**Плюсы**:
- ✅ Семантически ясно
- ✅ Трудно сделать ошибку
- ✅ Стандартизированные фазы

**Минусы**:
- ❌ Ограничен фиксированным набором фаз
- ❌ Нужно предусмотреть все возможные фазы заранее

---

### Сравнительная таблица:

| Подход | Простота | Контроль | Семантика | Рекомендация |
|--------|----------|----------|-----------|--------------|
| FIFO | ⭐⭐⭐ | ⭐ | ⭐⭐ | Для простых случаев |
| LIFO | ⭐⭐ | ⭐ | ⭐ | Не рекомендую (counter-intuitive) |
| Explicit Priority | ⭐ | ⭐⭐⭐ | ⭐⭐ | Для сложных систем |
| Named Phases | ⭐⭐ | ⭐⭐ | ⭐⭐⭐ | Золотая середина |

---

### Мой вывод:

**Рекомендую гибридный подход**: Named Phases + Priority внутри фазы

```ruby
ModuleRegistry.register_hook(
  :on_setting_defined,
  phase: :validate,   # Семантическая фаза
  priority: 10,       # Приоритет внутри фазы (опционально)
  callback: ...
)

# Стандартные фазы:
# 1. :validate   - Валидация (должна быть первой)
# 2. :transform  - Трансформация данных
# 3. :enhance    - Добавление метаданных
# 4. :document   - Генерация документации
# 5. :audit      - Аудит и логирование (должен быть последним)

# Default priority = 50 (середина)
# Внутри фазы сортировка: priority ASC, затем FIFO
```

**Преимущества**:
- ✅ Ясная семантика (validation всегда перед documentation)
- ✅ Гибкость внутри фазы (можно указать priority)
- ✅ Простой API (phase обязательна, priority опциональна)
- ✅ Расширяемо (можно добавить новые фазы в будущем)

---

## Итоговые Рекомендации

### 1. Merge Strategies

**Реализовать 3 стратегии**:
- ✅ `:replace` (default)
- ✅ `:append` (критично для Roles!)
- ✅ `:merge` (для будущих Hash-based модулей)

`:deep_merge` и `:union` - можно добавить позже при необходимости.

---

### 2. Validation Timing

**Гибридный подход**:
```ruby
ModelSettings.configure do |config|
  config.validation_mode = :strict    # Production (default)
  # config.validation_mode = :collect # Development
end
```

- `:strict` - валидация при `setting`, fail fast
- `:collect` - накапливает ошибки, показывает все при `compile_settings!`

---

### 3. Hook Priority

**Named Phases + Optional Priority**:
```ruby
register_hook(
  :on_setting_defined,
  phase: :validate,     # Required
  priority: 10,         # Optional (default: 50)
  callback: ...
)
```

Стандартные фазы: `:validate` → `:transform` → `:enhance` → `:document` → `:audit`

---

## Вопросы для финального согласования

1. **Merge strategies**: Согласен с тремя (replace, append, merge)?
2. **Validation timing**: Нужен ли collect mode или достаточно strict?
3. **Hook phases**: Согласен с 5 стандартными фазами? Нужны другие?
4. **Default behaviors**: Какие defaults для каждого механизма?

После согласования - можем начинать реализацию!
