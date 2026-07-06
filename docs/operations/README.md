# Operations Docs Guide

## Purpose
This file is a docs index and ownership map.

It intentionally does not duplicate runbook steps.

## Table Of Contents
- [Purpose](#purpose)
- [Single Source Of Truth](#single-source-of-truth)
- [Which Doc To Read](#which-doc-to-read)
- [Update Order](#update-order)

## Single Source Of Truth

- Central documentation hub: [docs/index.md](../index.md)
- Environment setup: [docs/guides/environment-setup.md](../guides/environment-setup.md)
- Operator runbook: [docs/guides/operator-runbook.md](../guides/operator-runbook.md)
- Architecture reference: [docs/guides/architect-reference.md](../guides/architect-reference.md)
- Boomi integration: [docs/guides/boomi-integration-guide.md](../guides/boomi-integration-guide.md)
- Enterprise architecture: [docs/guides/enterprise-architecture.md](../guides/enterprise-architecture.md)
- Component catalog: [docs/references/component-catalog.md](../references/component-catalog.md)
- Verification commands: [docs/references/verification-commands.md](../references/verification-commands.md)
- Recovery procedures: [docs/references/recovery-procedures.md](../references/recovery-procedures.md)
- Configuration inventory: [docs/operations/dev-configuration-catalog.md](dev-configuration-catalog.md)
- Overview and onboarding: [README.md](../../README.md)
- Historical context: [docs/history/](../history/)

## Which Doc To Read

| If You Need | Read |
|---|---|
| Find anything quickly | [docs/index.md](../index.md) |
| Set up your workstation | [docs/guides/environment-setup.md](../guides/environment-setup.md) |
| Provision infrastructure | [docs/guides/operator-runbook.md](../guides/operator-runbook.md) |
| Understand architecture | [docs/guides/architect-reference.md](../guides/architect-reference.md) |
| Write audit logs from Boomi | [docs/guides/boomi-integration-guide.md](../guides/boomi-integration-guide.md) |
| Review design/security/compliance | [docs/guides/enterprise-architecture.md](../guides/enterprise-architecture.md) |
| Check component health | [docs/references/verification-commands.md](../references/verification-commands.md) |
| Recover from failures | [docs/references/recovery-procedures.md](../references/recovery-procedures.md) |
| Find exact defaults | [docs/operations/dev-configuration-catalog.md](dev-configuration-catalog.md) |
| Historical records (not current) | [docs/history/](../history/) |

## Update Order
When behavior changes:
1. Update the relevant guide(s) in `docs/guides/`
2. Update [docs/references/component-catalog.md](../references/component-catalog.md) if a component was added/removed
3. Update [docs/operations/dev-configuration-catalog.md](dev-configuration-catalog.md) only if defaults/constants changed
4. Update [docs/index.md](../index.md) if navigation paths changed
5. Keep [docs/history/](../history/) unchanged unless adding a new historical snapshot
