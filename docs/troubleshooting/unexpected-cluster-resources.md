# Investigating Unexpected Cluster Resources

Companion to the [Operator Runbook](../guides/operator-runbook.md) and [Verification Commands](../references/verification-commands.md).

Use this guide when a preflight/health check, a routine `kubectl get namespaces` (or similar listing), or a certification pass (e.g. [issue #28](https://github.com/sml-global/mongodb/issues/28)) turns up a namespace, workload, or other cluster resource that doesn't obviously match this repo's known scope catalog (`mongodb`, `postgresql-core`/`postgresql-brand`, `signoz`, `signoz-observability`, `argocd`, plus shared platform services `cert-manager`, `kyverno`, `flux-system`). This is a read-only triage process — it does not modify or delete anything.

**Do not assume an unrecognized resource is unauthorized or hostile.** Shared UAT/Production clusters accumulate ad-hoc test artifacts, in-flight migrations, and documented-but-not-yet-cleaned-up technical debt. Confirm what it is before deciding whether it matters.

---

## Unexpected Namespace

| Step | Command | What It Tells You |
|---|---|---|
| 1. Full metadata | `kubectl get namespace <name> -o yaml` | Labels/annotations often name the owning tool directly — `app.kubernetes.io/managed-by: Helm`, a `kustomize.toolkit.fluxcd.io/name` label (Flux-managed), or an `argocd.argoproj.io/instance` label (ArgoCD-managed). Age (`metadata.creationTimestamp`) tells you how long it's been there. |
| 2. What's running inside it | `kubectl get all -n <name>` | Distinguishes a live workload (pods actually running — treat with more care) from an empty/stale namespace shell (created but nothing deployed — lower risk either way). |
| 3. Helm/Flux ownership | `kubectl get helmrelease -n <name> 2>/dev/null` and `kubectl get kustomization -A 2>/dev/null \| grep -i <name>` | This repo's provisioning always goes through Helm/Flux (see `docs/index.md` § Architecture), never raw `kubectl apply`/`kubectl create namespace`. No Helm release and no Flux Kustomization owning it is strong evidence it was created manually (ad-hoc testing), not by this repo's automation. |
| 4. Cross-check the scope catalog | Compare the name against `_SCOPE_REGISTRY_CATALOG` in `scripts/lib/scope-registry.sh`, and against the naming convention in `docs/references/component-catalog.md` § "Naming Convention" (`{component}-{env}` for application workloads, no suffix for platform services) | If the name doesn't match any known scope *and* doesn't follow the naming convention, it's very likely ad-hoc/manual, not a provisioning bug. |
| 5. Check known documented exceptions | Search `docs/` for the namespace name (`grep -rl "<name>" docs/`) before treating it as a new finding | Some ad-hoc artifacts are already tracked technical debt. Example: `test-audit` in UAT is a known, already-documented ad-hoc test-pod namespace from manual audit-log/telemetry testing (`scripts/write-auditlog-and-telemetry.sh`), flagged as a naming-convention violation with a planned remediation in `docs/UAT-ARCHITECTURE-ISSUES-NAMESPACE-LOGGING.md` § Issue 1 — not a live incident. |

### Decision guide

- **Matches a known scope, follows naming convention, Helm/Flux-owned** → expected, no action needed.
- **Doesn't match a scope, no Helm/Flux ownership, but already documented elsewhere (e.g. this doc, an open issue, an architecture doc)** → known technical debt; note it in your certification/verification evidence and move on, don't re-investigate from scratch each time.
- **Doesn't match a scope, no Helm/Flux ownership, and not documented anywhere** → new finding. Do not delete it yourself if you're bound by the DEV/SIT/UAT/Production safety rules in `CLAUDE.md` for the account in question — capture the evidence (metadata, workload contents, absence of Helm/Flux ownership) and open an issue or raise it with the team before taking any destructive action.
- **Live workload with active pods, of unknown origin, in UAT/Production** → treat as higher priority; loop in the team before assuming it's safe to ignore, even though this guide's steps are read-only.

---

## Unexpected Workload / Pod

Same triage shape as above, scoped down:

| Step | Command |
|---|---|
| Full pod detail (labels, owner references, image) | `kubectl get pod <name> -n <namespace> -o yaml` |
| Recent logs | `kubectl logs <name> -n <namespace> --tail=200` |
| What created it (Deployment/StatefulSet/Job/bare pod?) | Check `metadata.ownerReferences` in the YAML output — a bare pod with no owner reference is more likely to be a manual `kubectl run`/test artifact than something provisioned by this repo (Helm charts create pods via Deployments/StatefulSets, not bare pods). |

---

## See Also

- [Operator Runbook](../guides/operator-runbook.md) — standard provisioning/destroy procedures this repo's automation follows
- [Component Catalog § Naming Convention](../references/component-catalog.md#naming-convention) — the naming rules an expected resource should follow
- [Recovery Procedures](../references/recovery-procedures.md) — what to do once you've confirmed something needs to change, not just be understood
- [Issue #28](https://github.com/sml-global/mongodb/issues/28) — the live UAT certification pass this guide's example (`test-audit`) was found during
