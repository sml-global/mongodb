# ArgoCD User Guide

For everyday ArgoCD users: `ArgoCD-Viewer` and `ArgoCD-Operator` roles. If you manage IAM, SSO, or cluster registration, see the [ArgoCD Admin Guide](argocd-admin-guide.md) instead.

**Status:** ArgoCD is not yet deployed (Issue #82, blocked on Production EKS cluster). This guide describes the intended workflow once deployment completes.

---

## What Is ArgoCD, In This Repo

A single ArgoCD instance runs in the Production EKS cluster and gives you one UI to see application sync status across all four environments (Production, UAT, Dev, SIT) instead of switching `kubectl` contexts. See [Component Catalog § ArgoCD](../references/component-catalog.md) for what it manages and [ARGOCD-MULTI-ENV-ARCHITECTURE.md](../../ARGOCD-MULTI-ENV-ARCHITECTURE.md) for why it exists alongside Flux.

## Your Role And What It Lets You Do

Check your assigned role in [`docs/design/argocd-user-assignments.md`](../design/argocd-user-assignments.md).

| Action | ArgoCD-Viewer | ArgoCD-Operator |
|---|---|---|
| View applications (all 4 envs) | ✅ | ✅ |
| View logs | ✅ | ✅ |
| Sync (deploy) — UAT/Dev/SIT | ❌ | ✅ |
| Sync (deploy) — Production | ❌ | ❌ (view only) |
| Rollback — UAT/Dev/SIT | ❌ | ✅ |
| Exec into pods | ❌ | ✅ (non-Prod only) |

Only `ArgoCD-Admin` can sync Production or manage clusters/repositories — see the [Admin Guide](argocd-admin-guide.md).

## Logging In

1. Browse to the ArgoCD UI URL (provided by your platform team once deployed).
2. Click "Login via SSO" — you'll be redirected to AWS Identity Center.
3. Authenticate with your `@sml.com` account.
4. Your AWS SSO group (`ArgoCD-Admin` / `ArgoCD-Operator` / `ArgoCD-Viewer`) determines what you can do — there's no separate ArgoCD password to manage.

If login fails or you land in the UI without the permissions you expect, see [ArgoCD Troubleshooting § SSO Fails](../troubleshooting/argocd-troubleshooting.md#sso-fails).

## Viewing Applications

- The Applications dashboard lists every managed app (MongoDB, PostgreSQL config, SigNoz) across all registered clusters.
- Each app shows **Sync Status** (`Synced` / `OutOfSync`) and **Health Status** (`Healthy` / `Degraded` / `Progressing`).
- Click an app to see its resource tree, live manifest, and diff against git.

## Syncing an Application (Operator role, non-Production only)

1. Open the application in the UI.
2. Review the diff — what will change if you sync.
3. Click **Sync**. For UAT/Dev/SIT this applies immediately; there is no separate approval step for these environments.
4. Watch the resource tree until all resources reach `Healthy`.

If an app is `OutOfSync` but you don't intend to change anything, it usually means someone edited the live cluster directly (config drift) — don't sync over it without checking with the platform team first, since syncing will overwrite the manual change.

## Production Deployments

Operators can view Production apps but cannot sync them — sync requires an `ArgoCD-Admin`. If you need a Production change deployed, open a request to an Admin (see `docs/design/argocd-user-assignments.md` for the current Admin list) rather than trying to work around the RBAC restriction.

## Rollback

1. Open the application.
2. Go to **History and Rollback**.
3. Pick a previous sync revision and click **Rollback**.

This only works for environments your role can sync (UAT/Dev/SIT for Operators). It reverts the live cluster state — the git repository is unchanged, so the next sync from git will move the app forward again unless git is also reverted.

## Common Issues

See the full [ArgoCD Troubleshooting Guide](../troubleshooting/argocd-troubleshooting.md). Most common for end users:
- **Can't log in** → [SSO Fails](../troubleshooting/argocd-troubleshooting.md#sso-fails)
- **App stuck `OutOfSync`** → [Sync Failures](../troubleshooting/argocd-troubleshooting.md#sync-failures)
- **No Sync button on Production** → expected behavior for Operators/Viewers, not a bug

## Related

- [ArgoCD Admin Guide](argocd-admin-guide.md)
- [Component Catalog § ArgoCD](../references/component-catalog.md)
- [Verification Commands § ArgoCD](../references/verification-commands.md#argocd)
- `docs/design/argocd-user-assignments.md`
