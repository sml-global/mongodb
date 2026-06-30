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

- Current operator runbook lives in [platform-prerequisites/terraform/README.md](../../platform-prerequisites/terraform/README.md).
- Overview and onboarding summary lives in [README.md](../../README.md).
- Configuration inventory lives in [docs/operations/dev-configuration-catalog.md](dev-configuration-catalog.md).
- Historical context lives in [docs/history/](../history/).

## Which Doc To Read

| If You Need | Read |
|---|---|
| Quick orientation and onboarding | [README.md](../../README.md) |
| Full operator steps and troubleshooting | [platform-prerequisites/terraform/README.md](../../platform-prerequisites/terraform/README.md) |
| Unified Terraform root context | [platform-prerequisites/terraform/dev/README.md](../../platform-prerequisites/terraform/dev/README.md) |
| MongoDB-only Terraform root context | [platform-prerequisites/terraform/mongodb/README.md](../../platform-prerequisites/terraform/mongodb/README.md) |
| PostgreSQL-only Terraform root context | [platform-prerequisites/terraform/postgresql/README.md](../../platform-prerequisites/terraform/postgresql/README.md) |
| Exact defaults and embedded constants | [docs/operations/dev-configuration-catalog.md](dev-configuration-catalog.md) |
| Historical records (not current runbook) | [docs/history/](../history/) |

## Update Order
When run behavior changes:
1. Update [platform-prerequisites/terraform/README.md](../../platform-prerequisites/terraform/README.md) first.
2. Update [README.md](../../README.md) summary wording only.
3. Update [docs/operations/dev-configuration-catalog.md](dev-configuration-catalog.md) only if defaults/constants changed.
4. Keep [docs/history/](../history/) unchanged unless you are adding a new historical snapshot.
