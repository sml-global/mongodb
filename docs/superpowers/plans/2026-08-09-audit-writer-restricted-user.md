# Plan: Restricted-scope MongoDB user for the audit-writer secret

**Status:** Draft — awaiting review. Nothing built yet.

## Problem

`scripts/create-audit-writer-secret.sh` (fixed for namespace-awareness in #101/PR #102) creates the `oms-audit-writer` k8s Secret by reusing the **database-admin** credentials from `psmdb-secrets`. Any Boomi process consuming that secret effectively gets full database-admin access to MongoDB, not just write access to the audit database. That's broader than the audit-writer actually needs.

## Goal

- A dedicated MongoDB user, scoped to write-only access on `oms_audit`, not admin.
- Its password: generated with a strong random value, stored somewhere version-control-safe, reusable across dev/uat/prod, and easy to swap to a real value later without changing any code.
- For now (testing), just auto-generate and move on — no manual value needed today.

## Existing precedent already in this repo

`scripts/create-audit-reader.sh` already does the read-only equivalent:
- Connects to a running `mongod` pod via `kubectl exec ... mongosh`, authenticating with `MONGODB_USER_ADMIN_USER`/`MONGODB_USER_ADMIN_PASSWORD` from `psmdb-secrets` (the `userAdmin` role — narrower than the full database-admin account).
- `createUser`/`updateUser` (idempotent) with a role scoped to one database (`{ role: 'read', db: '$DB_NAME' }`).
- `--password` auto-generates via `openssl rand -base64 24` if not supplied.

This plan proposes a write-role sibling script following the identical pattern, not a new mechanism.

## Proposed design

### 1. New script: `scripts/create-audit-writer-user.sh`

Sibling to `create-audit-reader.sh`, adapted as follows:

- Flags: `--namespace` (default `mongodb`), `--db` (default `oms_audit`), `--username` (default `audit_writer`), `--password` (optional override), `--service-host` (default derived from `--namespace`, same fix as #101).
- Auth: reads `MONGODB_USER_ADMIN_USER`/`MONGODB_USER_ADMIN_PASSWORD` from `psmdb-secrets` in the target namespace (same as the reader script) — not the full database-admin account.
- User role: `{ role: 'readWrite', db: '$DB_NAME' }` only — no other database, no admin/cluster roles.
- Idempotent: if the user exists, `updateUser` (password + role); if not, `createUser`. Matches `create-audit-reader.sh`'s existing branch.
- Password resolution order:
  1. `--password` flag, if given.
  2. Else, read `AUDIT_WRITER_PASSWORD` from the new per-environment secrets file (below); if present and non-empty, use it.
  3. Else, generate with `openssl rand -base64 24`, print it once, and **write it back** into that environment's secrets file so the same value is reused on every subsequent run (idempotent user creation needs a stable password — regenerating a random one on every run would silently rotate the live MongoDB user's password each time the script is re-run).
- After the MongoDB user exists, create/update the `oms-audit-writer` k8s Secret with `mongoUri` built from this new user (not the admin account) — folding in what `create-audit-writer-secret.sh` does today, reusing the same `--service-host` derivation logic from PR #102 rather than duplicating it.

**Open question for review:** should `create-audit-writer-secret.sh` be replaced entirely by this new script, or kept as a separate legacy path? Leaning toward: `create-audit-writer-user.sh` becomes the real one going forward (creates the user AND the k8s Secret), and `create-audit-writer-secret.sh` gets a deprecation note pointing at it, rather than deleting it outright and possibly breaking anything else that calls it directly. Confirm before I build.

### 2. New per-environment secrets file: `config/environments/<env>-secrets.env`

- New file, one per environment (`dev-secrets.env`, `uat-secrets.env`, `prod-secrets.env` when that's real).
- **Not** validated by `load_platform_env`'s schema (`config/environment-schema/base.manifest` + fragments) — that schema is explicitly for non-secret infra config (account IDs, regions, state keys) and has no `secret` validator type. Mixing a password into it would either fail validation or require weakening the schema's intent. This file is read by a small, separate, dedicated loader in the new script only.
- Format: simple `KEY=value` lines, e.g.:
  ```
  AUDIT_WRITER_PASSWORD=<generated-or-manually-set-value>
  ```
- Gitignored. Add `config/environments/*-secrets.env` to `.gitignore` explicitly (today's `.gitignore` only has `config/environments/*.local/`, which wouldn't match this).
- A checked-in sample, `config/environments/audit-writer-secrets.env.sample`, documents the expected key with a placeholder — mirroring the existing `terraform.tfvars.sample` convention used elsewhere (e.g. `postgresql-core/terraform.tfvars.sample`).

### 3. "Universal, swap later" behavior this gives you

- **Today (testing):** run the script with no secrets file present → it generates a strong password, writes it to `<env>-secrets.env`, creates the user + k8s Secret. Nothing to think about.
- **Later (real UAT/Prod):** either hand-edit `AUDIT_WRITER_PASSWORD` in that environment's secrets file to a specific value before first run, or let it auto-generate once and rotate later by editing the file and re-running the script (which will `updateUser` the password to match).
- Same script/mechanism across all environments — only the file's contents differ, never the code.

### 4. Safety / execution boundary

This creates a **real MongoDB user** against a live cluster — a write action, not read-only inspection. Per how #101/#102 were handled: I will write and unit-test the script's logic with a stubbed `kubectl`/`mongosh` (verifying flag parsing, password-generation-and-persist logic, idempotent update-vs-create branching, and the final Secret contents), but the user asked to run any real command against UAT themselves — I will not execute this script against a live cluster.

## Out of scope for this plan

- Rotating the *existing* `oms-audit-writer` secret/admin-based URI already possibly created in dev from prior manual runs — a follow-up cleanup once this lands, not part of this change.
- Anything about `psmdb-secrets`' built-in system users (database admin, cluster admin, backup) — those are Percona-operator-managed via the PSMDB CR and out of scope here; this plan only adds one new, narrowly-scoped **application** user on top of them, the same way `create-audit-reader.sh` already does for reads.

## Questions for sign-off before building

1. Replace `create-audit-writer-secret.sh` outright, or deprecate-in-place alongside the new script? (see "Open question" above)
2. Confirm script name (`create-audit-writer-user.sh`) and MongoDB username (`audit_writer`) are what you want — easy to rename before building, harder after it's referenced in docs/other scripts.
3. Confirm secrets-file naming (`config/environments/<env>-secrets.env`) and key name (`AUDIT_WRITER_PASSWORD`) read correctly, in case you'd rather a different shape (e.g. one shared secrets file with per-environment sections, instead of one file per environment).
