# Architecture Documentation

This directory contains Architecture Decision Records (ADRs) for the ModelSettings project.

---

## Architecture Decision Records (ADRs)

**ADR (Architecture Decision Record)** documents important architectural decisions, including:
- **Context**: Why the question arose
- **Decision**: What we decided to do (or NOT do)
- **Rationale**: Why this choice
- **Alternatives**: What else we considered
- **Consequences**: How this affects the project

### Why ADRs?

1. **Team Memory** - Document "why we did it this way"
2. **Onboarding** - Help new developers understand architectural choices
3. **Avoid Repetition** - "We already discussed this, here's why we chose X"
4. **Transparency** - Open architectural decisions for the community

### ADR Format

All ADRs follow a consistent format (see `adr-template.md`):

```markdown
# ADR-XXX: Decision Title

**Status**: Accepted / In Discussion / Rejected / Superseded by ADR-YYY
**Decision Date**: YYYY-MM-DD

## Context
What's the problem? Why did the question arise?

## Decision
What did we decide to do?

## Rationale
Why this way?

## Alternatives Considered
What else did we consider and why reject?

## Consequences
What does this mean for the project?
```

---

## List of ADRs

| ADR | Title | Status | Date |
|-----|-------|--------|------|
| [ADR-001](adr-001-no-rails-store.md) | Don't use Rails ActiveRecord::Store | ✅ Accepted | 2025-10-31 |

---

## How to Create a New ADR?

1. **Copy template**: `cp adr-template.md adr-00X-title.md`
2. **Fill sections**: Context, decision, rationale, alternatives, consequences
3. **Discuss with team**: Get feedback before final decision
4. **Update README**: Add entry to ADR table above
5. **Commit**: Save to git

---

## When to Create an ADR?

Create ADR for:
- ✅ Choosing fundamental technologies (Rails Store vs custom)
- ✅ Architectural patterns (modular system, plugin architecture)
- ✅ API design (breaking changes, major refactoring)
- ✅ Deviations from specification (conscious decisions)
- ✅ Performance trade-offs (memory vs speed)

Don't create ADR for:
- ❌ Routine bug fixes
- ❌ Minor refactorings
- ❌ Style changes
- ❌ Dependency updates (unless architectural consequences)

---

## Links

- **What is ADR**: https://adr.github.io/
- **Template**: [adr-template.md](adr-template.md)
- **Examples**: [ADR-001](adr-001-no-rails-store.md)
