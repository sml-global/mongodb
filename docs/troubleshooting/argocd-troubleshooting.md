# ArgoCD Troubleshooting

Companion to the [ArgoCD section of the Operator Runbook](../guides/operator-runbook.md#argocd-status-design-complete-deployment-pending--issue-82) and [Verification Commands § ArgoCD](../references/verification-commands.md#argocd).

**Status:** ArgoCD is not yet deployed (Issue #82, blocked on Production EKS cluster). This guide targets the deployment once Phases 1-3 are complete.

---

## Pods Not Starting

| Symptom | How To Check | Likely Cause | Fix |
|---|---|---|---|
| `argocd-server` CrashLoopBackOff | `kubectl -n argocd logs deploy/argocd-server` | Redis unreachable | Verify `argocd-redis` pod is Running; check `argocd-redis` Service DNS resolves |
| `argocd-repo-server` stuck Pending | `kubectl -n argocd describe pod <pod>` | Insufficient node resources | Check node capacity: `kubectl top nodes`; scale node group if needed |
| `argocd-application-controller` restarting | `kubectl -n argocd logs statefulset/argocd-application-controller` | OOMKilled from too many watched Applications | Increase controller memory limits, or shard with `ARGOCD_CONTROLLER_REPLICAS` |
| `argocd-dex-server` not starting | `kubectl -n argocd logs deploy/argocd-dex-server` | Invalid OIDC config in `argocd-cm` | Validate `argocd-cm` YAML syntax, especially `oidc.config` block |

---

## SSO Fails

| Symptom | How To Check | Likely Cause | Fix |
|---|---|---|---|
| Login redirects but never completes | Browser dev tools → Network tab for `/api/dex/callback` errors | OIDC redirect URI mismatch | Confirm the URI registered in AWS Identity Center matches `https://<argocd-host>/api/dex/callback` exactly |
| "User not found in any group" | `kubectl -n argocd logs deploy/argocd-dex-server \| grep group` | User not assigned to an `ArgoCD-*` SSO group | Verify assignment in AWS Identity Center per `docs/design/argocd-user-assignments.md` |
| Login succeeds but no permissions | `argocd account get-user-info` (after login) | `argocd-rbac-cm` policy doesn't map the group | Check `policy.csv` in `argocd-rbac-cm` maps the SSO group claim to a role |
| SSO works for some users, not others | Compare group membership in Identity Center | Permission set not assigned to that group | Re-check Phase 2 permission set assignment |

---

## AssumeRole Fails

| Symptom | How To Check | Likely Cause | Fix |
|---|---|---|---|
| `AccessDenied` on `sts:AssumeRole` | `kubectl -n argocd exec deploy/argocd-application-controller -- aws sts get-caller-identity` | ServiceAccount not annotated for IRSA/Pod Identity | Confirm ServiceAccount annotation `eks.amazonaws.com/role-arn` matches the IAM role created by `argocd-iam` Terraform |
| Cross-account trust denied | Check target role's trust policy | `argocd-target-{env}` role doesn't trust the Production account/role | Verify trust policy `Principal` includes the Production `argocd-cluster-manager-prod` role ARN |
| Works for UAT, fails for Dev/SIT | Compare `argocd-target-<env>` roles across accounts | That environment's IAM role not yet deployed | Run Terraform apply for the missing environment (Runbook Step 1) |
| Credentials expire mid-sync | ArgoCD Application shows `Unknown` health intermittently | Session duration too short for long-running syncs | Increase `DurationSeconds` in the AssumeRole call or role's max session duration |

---

## Cluster Registration Fails

| Symptom | How To Check | Likely Cause | Fix |
|---|---|---|---|
| `argocd cluster add` hangs | Check kubeconfig context used matches target cluster | Local kubeconfig context misconfigured, or no network path to target API server | Confirm `kubectl --context <target> get ns` works standalone first |
| `argocd cluster list` shows cluster as `Unknown` | `argocd cluster get <cluster-name>` | ArgoCD's in-cluster ServiceAccount can't reach the target API server | Verify security groups / VPC peering allow Production ArgoCD to reach target cluster's EKS endpoint |
| Registered cluster shows `Invalid` | `argocd cluster get <cluster-name> -o yaml` | Bearer token or cert stored during registration has expired/rotated | Re-run `argocd cluster add` to refresh credentials |
| New cluster (SIT) can't be registered | N/A | SIT does not exist yet per project safety rules | Do not attempt — SIT registration is blocked until the environment is provisioned |

---

## Sync Failures

| Symptom | How To Check | Likely Cause | Fix |
|---|---|---|---|
| Application stuck `OutOfSync` | `argocd app diff <app-name>` | Live state drifted from git (manual kubectl edit) | Either sync to overwrite drift, or update git to match intentional live changes |
| Application `Degraded` after sync | `argocd app get <app-name>` health details | Underlying resource (e.g. MongoDB CR) failed reconciliation | Check the resource's own controller logs (e.g. Percona Operator), not just ArgoCD |
| Sync blocked, "waiting for manual approval" | `argocd app get <app-name>` | Expected — Production project requires manual sync per RBAC design | Have an `ArgoCD-Admin` or `ArgoCD-Operator` (non-Prod) trigger sync via UI/CLI |
| Operator can't sync Production | `argocd app get <app-name> --show-operation` | RBAC correctly denies Operator role Production sync (by design) | Escalate to an `ArgoCD-Admin` — this is expected behavior, not a bug |
| Sync succeeds but resource unchanged | `argocd app diff <app-name>` after sync | Kyverno policy silently mutated/blocked the applied manifest | Check `kubectl get policyreports -n <target-ns>` for admission-time changes |

---

## Related

- [Operator Runbook § ArgoCD](../guides/operator-runbook.md#argocd-status-design-complete-deployment-pending--issue-82)
- [Verification Commands § ArgoCD](../references/verification-commands.md#argocd)
- [Component Catalog § ArgoCD](../references/component-catalog.md)
- [ArgoCD Multi-Env Architecture](../../ARGOCD-MULTI-ENV-ARCHITECTURE.md)
- [User Access Design](../design/argocd-user-access-design.md)
- Issue #82
