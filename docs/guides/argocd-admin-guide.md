# ArgoCD Admin Guide

For `ArgoCD-Admin` role holders responsible for deploying, configuring, and maintaining ArgoCD itself — IAM, SSO, cluster registration, and RBAC. For day-to-day application sync as an end user, see the [ArgoCD User Guide](argocd-user-guide.md).

**Status:** ArgoCD is not yet deployed (Issue #82, blocked on Production EKS cluster). This guide describes the deployment and maintenance procedure once implementation begins.

---

## Scope Of This Role

Per [`docs/design/argocd-user-assignments.md`](../design/argocd-user-assignments.md), Admins (currently xavierlee@sml.com, jiaweima@sml.com) have full access across all 4 environments: sync, rollback, delete applications, manage clusters, manage repositories. This is the only role that can:
- Sync Production applications
- Register/deregister remote clusters
- Manage ArgoCD's own configuration (`argocd-cm`, `argocd-rbac-cm`)
- Manage repository connections

## Deployment (First-Time Setup)

Full step-by-step procedure lives in [Operator Runbook § ArgoCD](operator-runbook.md#argocd-status-design-complete-deployment-pending--issue-82) — this section covers admin-specific judgment calls, not the mechanical steps.

**Order matters:**
1. Confirm Production EKS cluster exists and is healthy — everything else is blocked until this is true.
2. Deploy IAM roles (Terraform) for every environment — UAT and Dev can be done ahead of time to validate the modules; SIT is blocked until that environment exists (never provision SIT, per CLAUDE.md § Safety Rules).
3. Deploy ArgoCD into the Production cluster only. Never deploy a second ArgoCD instance into UAT/Dev to "get ahead" — the architecture is intentionally centralized (see [ARGOCD-MULTI-ENV-ARCHITECTURE.md](../../ARGOCD-MULTI-ENV-ARCHITECTURE.md)).
4. Configure SSO/OIDC and verify all three roles can log in before registering any remote clusters — RBAC misconfiguration is much easier to fix before real Applications exist.
5. Register remote clusters (UAT, Dev; SIT once it exists).

## Managing Users And Roles

Source of truth: [`docs/design/argocd-user-assignments.md`](../design/argocd-user-assignments.md). Keep it updated whenever you change group membership — it is the reference the rest of the docs (Runbook, Troubleshooting, User Guide) link to rather than duplicating the user list.

### Adding a user

1. Add the user's email in AWS Identity Center.
2. Add them to the appropriate group (`ArgoCD-Admin` / `ArgoCD-Operator` / `ArgoCD-Viewer`).
3. Update `docs/design/argocd-user-assignments.md`.
4. No ArgoCD-side action needed — RBAC is driven entirely by SSO group claims via `argocd-rbac-cm`.

### Changing a user's role

Move them between AWS Identity Center groups; do not create per-user policy overrides in `argocd-rbac-cm` — the three-tier model (Admin/Operator/Viewer) is deliberately simple. If a use case doesn't fit any of the three, treat that as a design question, not a one-off policy hack.

### Removing a user

Remove from the AWS Identity Center group. Their existing ArgoCD session (if any) remains valid until token expiry — for urgent removal, also revoke the session in AWS Identity Center.

## RBAC Configuration

`argocd-rbac-cm` maps SSO group claims to ArgoCD roles. The three roles are defined once and referenced by group, not by individual user:

```
role:admin       — full access, all projects/clusters
role:operator    — sync/rollback on uat/dev/sit projects, view-only on prod project
role:readonly    — view only, all projects
```

Production sync restriction is enforced at the **AppProject** level (a `prod` ArgoCD Project with `role:operator` excluded from its sync RBAC), not by hiding the Sync button in the UI — don't rely on UI-only restrictions.

Before editing `argocd-rbac-cm`, re-check the permission matrix in `docs/design/argocd-user-assignments.md` — it's the design source; the ConfigMap should implement it exactly, not drift from it.

## Cluster Registration

Only register a cluster once its cross-account IAM role (`argocd-target-{env}`) is deployed and its trust policy includes the Production `argocd-cluster-manager-prod` role. Registering a cluster before IAM is in place will succeed at the `argocd cluster add` step but fail silently on the next sync attempt — verify with `argocd cluster get <name>` immediately after adding.

Never register a cluster that doesn't officially exist yet (SIT) — see CLAUDE.md § Safety Rules.

## Repository Management

Only Admins manage git repository connections (`argocd repo add`). Operators and Viewers have view-only repo access by design (see permission matrix in `docs/design/argocd-user-assignments.md`) — don't grant repo-write to non-Admin roles even temporarily.

## Emergency Procedures

- **Production sync went wrong**: use History and Rollback in the UI, or `argocd app rollback <app> <revision>`. This does not touch git — if the bad state came from a bad commit, also revert that commit so the next sync doesn't reintroduce it.
- **SSO broken, no one can log in**: `argocd-server` still accepts the local `admin` account as a break-glass credential (retrieve initial password per upstream ArgoCD docs, then rotate/disable once SSO is fixed). Do not leave the local admin account enabled long-term.
- **Cross-account AssumeRole broken for one environment**: don't disable RBAC or widen IAM trust policies as a workaround — fix the specific role's trust policy. See [Troubleshooting § AssumeRole Fails](../troubleshooting/argocd-troubleshooting.md#assumerole-fails).

## Related

- [ArgoCD User Guide](argocd-user-guide.md)
- [Operator Runbook § ArgoCD](operator-runbook.md#argocd-status-design-complete-deployment-pending--issue-82)
- [ArgoCD Troubleshooting Guide](../troubleshooting/argocd-troubleshooting.md)
- [ARGOCD-MULTI-ENV-ARCHITECTURE.md](../../ARGOCD-MULTI-ENV-ARCHITECTURE.md)
- [User Access Design](../design/argocd-user-access-design.md)
- `docs/design/argocd-user-assignments.md`
- Issue #82
