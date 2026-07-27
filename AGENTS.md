# MongoDB Repo Rules

This is the active implementation repository in this workspace.

## Scope And Safety

- Make edits in this repository only.
- Treat sibling repositories as read-only references:
  - `../boomi-infra/`
  - `../oms-backend/`
  - `../oms-frontend/`
- Do not modify files outside `mongodb/` unless the user gives explicit approval in the current conversation.

## Canonical Entry Points (Read First)

- Documentation hub: [docs/index.md](docs/index.md)
- Operator setup and run flow: [docs/guides/environment-setup.md](docs/guides/environment-setup.md), [docs/guides/operator-runbook.md](docs/guides/operator-runbook.md)
- Verification commands: [docs/references/verification-commands.md](docs/references/verification-commands.md)
- Audit contract: [docs/references/audit-log-contract.md](docs/references/audit-log-contract.md)
- SigNoz dashboards/alerts as code: [docs/references/signoz-dashboard-import-pack.md](docs/references/signoz-dashboard-import-pack.md)

Use links to canonical docs instead of duplicating long procedural content in responses or instruction files.

## Preferred Command Workflow

When asked to provision or validate, use this default sequence unless the user asks for a narrower scope:

1. `scripts/verify-platform-health.sh --preflight`
2. `bash scripts/provision.sh all --auto-approve`
3. `bash scripts/provision.sh signoz --auto-approve`
4. `bash scripts/provision.sh signoz-observability --auto-approve`
5. `scripts/verify-platform-health.sh --smoke-test`

Prefer repository scripts over ad-hoc raw Terraform/Kubernetes command chains.

## Project Conventions For Agents

- Respect intentional scope split:
  - `all` = MongoDB + PostgreSQL core data layer
  - `signoz` = telemetry platform
  - `signoz-observability` = dashboards + alert rules
- Before declaring success, run relevant verification commands and report concrete outcomes.
- For docs updates, preserve cross-links and keep [docs/index.md](docs/index.md) navigation accurate.
- For Boomi-related changes, keep behavior aligned with [docs/references/audit-log-contract.md](docs/references/audit-log-contract.md).

## High-Value Pitfalls To Check Early

- Missing local prerequisites can break automation: confirm `python3` and Playwright availability before SigNoz observability bootstrap paths.
- SigNoz API-driven observability steps depend on a healthy SigNoz platform first; verify readiness before applying observability resources.
- MongoDB health is not pod-status-only; use replica set and smoke-test validation paths when troubleshooting.

## Current Documentation Focus

- Audit log contract for Boomi producers.
- SigNoz correlation and observability guidance.
