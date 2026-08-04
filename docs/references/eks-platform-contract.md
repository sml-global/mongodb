# EKS Platform Component Contract

**Owned by:** Phase 2 EKS Platform (Tasks 1-8)  
**Documentation Date:** 2026-07-27 (implementation); updated 2026-08-04 (deployment status)  
**Status:** Deployed and live-verified in UAT (`eks-platform`, `workload-identity`, `platform-controllers` all provisioned, verified, and destroy-tested end-to-end)

## Overview

The EKS Platform component provides a production-grade Kubernetes foundation for the OMS platform, including workload identity federation, managed add-on governance, and disaster-recovery controls.

This document is the canonical contract for operators, architects, and reviewers. All authorized work proceeds through the foundation's public entrypoints; the three internal implementation files are owned solely by this package and must not be invoked directly.

---

## Ownership & Scope

### What This Component Manages

| Scope | Resource | State Backend | Operator-facing Interface |
|---|---|---|---|
| `eks-platform` | EKS cluster, networking, add-ons | Terraform (platform-prerequisites) | Foundation scopes: `eks-platform` |
| `workload-identity` | IRSA roles, Pod Identity associations, inline policies | Terraform (workload-identity root module) | Foundation scopes: `workload-identity` |
| `platform-controllers` | Cert-manager, Kyverno, cluster autoscaler, metrics-server | Flux (GitOps kustomization) | Foundation scopes: `platform-controllers` |

### What This Component Does NOT Manage

- MongoDB, PostgreSQL, or application databases
- Boomi runtime, audit log, or message queue infrastructure
- Foundation registry, orchestrator, or authentication/authorization logic
- Break-glass access control or evidence artifact persistence

---

## Promotion Modes & Destroy Gate

### `PROMOTION_MODE=uat-build`

**Intended Use:** UAT and pre-production environments.

- **Authorize Flow:** Foundation prompts for account/region validation, backend state review, saved-plan approval, and resource ownership confirmation.
- **Pre-Destroy Gate:** Before any destroy handler runs, the foundation invokes a read-only pre-destroy guard that:
  1. Checks all registered dependents are absent (workload-identity, platform-controllers absent before eks-platform destroy).
  2. Verifies EKS deletion protection is **enabled**.
  3. Verifies EFS `prevent_destroy` protection is **enabled**.
  4. Verifies Backup Vault Lock is **effective** (not pending, broken, or disabled).
  5. Verifies backup retention is **≥ 35 days**.
  6. Computes a deterministic SHA-256 digest over canonical observations.
  7. Invokes the foundation callback **exactly once**: `record_pre_destroy_guard_result <scope> <PASS|FAIL> <resource-identity> <sha256-digest> <summary-code>`.
  8. Returns 0 for PASS, non-zero for FAIL.
  - **Outcome:** Foundation blocks destroy before handler dispatch if guard records FAIL, or if evidence result is missing/malformed.
  - **Handler Recheck:** Immediately before the first destroy mutation, handlers recheck live identity and protections, but this recheck cannot replace or bypass the pre-destroy guard gate.

### `PROMOTION_MODE=modeled`

**Intended Use:** Development environments only (scoped to `ENVIRONMENT=dev`).

- **No authorization prompts.** Assumes test state.
- **No pre-destroy guard.** Handlers proceed directly to mutation.
- **Failure is fail-fast:** any mutation failure aborts the run immediately.

### Breaking the Pre-Destroy Gate

Under the `uat-build` promotion mode, the pre-destroy guard cannot be overridden by operators, shell scripts, or this package code. The only exception is foundation break-glass, which is entirely owned and controlled by the foundation. This package neither implements nor exposes any escape hatch.

---

## Internal Implementation Files

### Three Private Bash 3.2-Compatible Files

This package owns three internal bash files. Operators and other components MUST NOT invoke these files directly; they export only internal symbols (`eks_internal_*`) and are sourced exclusively through the foundation-validated package-source helper.

#### 1. `scripts/lib/packages/20-eks-platform/internal/lifecycle-handlers.sh`

**Responsibility:** Provision and destroy mutation logic.

- Exports only: `eks_internal_eks_platform_provision_handler`, `eks_internal_eks_platform_destroy_handler`, and related mutation helpers.
- Never exports: canonical wrapper symbols, verifier symbols, or guard symbols.
- Never sources: the verifier or guard implementation files.
- Behavior:
  - **Provision:** Reads foundation state context, applies Terraform for workload-identity root and platform-controllers GitOps, outputs state.
  - **Destroy:** Immediately rechecks live account/region/identity/protection state before the first mutation. If live state drifts from the last-recorded snapshot, refuses to mutate. This recheck is **fail-closed and cannot be bypassed**, but it is **not the sole destroy gate**—the pre-destroy guard (invoked before handler dispatch) is the primary gate.

#### 2. `scripts/lib/packages/20-eks-platform/internal/verifiers.sh`

**Responsibility:** Component verification and readiness checks.

- Exports only: `eks_internal_eks_platform_verifier`, `eks_internal_workload_identity_verifier`, `eks_internal_platform_controllers_verifier`.
- Never exports: canonical wrapper symbols, handler symbols, or guard symbols.
- Never sources: the guard implementation file.
- Behavior:
  - Performs read-only checks on the cluster identity from the validated platform_contract.
  - Returns 0 (success) if identity matches live observations; non-zero otherwise.

#### 3. `scripts/lib/packages/20-eks-platform/internal/pre-destroy-guards.sh`

**Responsibility:** Read-only pre-destroy guard logic.

- Exports only: `eks_internal_eks_platform_pre_destroy_guard`, `eks_internal_workload_identity_pre_destroy_guard`, `eks_internal_platform_controllers_pre_destroy_guard`.
- Never exports: canonical wrapper symbols, handler symbols, or verifier symbols.
- Never sources: the verifier implementation file.
- Behavior:
  - Invoked by the foundation **once per scope** during the pre-destroy guard phase (in `uat-build` mode only).
  - Performs read-only checks from foundation-provided in-memory context and live AWS read-only API calls.
  - Derives the canonical resource identity **directly from the validated platform_contract** environment variables (`EKS_PLATFORM_IDENTITY`, or computed from `EKS_CLUSTER_NAME + AWS_REGION + EXPECTED_AWS_ACCOUNT_ID`); never from live AWS discovery or evidence artifacts.
  - Computes a deterministic SHA-256 digest over the canonical checked observations (dependencies, protections, identity).
  - Selects a closed foundation-defined summary code (e.g., `EKS_PLATFORM_GUARD_PASS`, `DEPENDENT_NOT_ABSENT`, `PROTECTION_ABSENT`).
  - Invokes the foundation callback **exactly once**, in the exact signature: `record_pre_destroy_guard_result <scope> <PASS|FAIL> <resource-identity> <sha256-digest> <summary-code>`.
  - Returns 0 for PASS; non-zero for FAIL.
  - **Creates or reads NO evidence artifact.** The foundation receives the in-memory callback result and alone persists the evidence artifact.

---

## Guard Callback Semantics

### Exact Callback Signature

```bash
# AUTHORIZED-ONLY
record_pre_destroy_guard_result <scope> <PASS|FAIL> <resource-identity> <sha256-digest> <summary-code>
```

### Callback Contract

- **Called exactly once** per guard invocation. A second call triggers `GUARD_DUPLICATE_RESULT` abort.
- **After all checks complete.** Callback must not be invoked before checks and identity/digest/code computation.
- **Field validation (foundation-enforced):**
  - `scope`: Must match the active guard scope for this invocation.
  - `guard_status`: Must be exactly `PASS` or `FAIL` (uppercase only); any other value triggers `GUARD_MALFORMED_RESULT` abort.
  - `resource_identity`: Must match `^[A-Za-z0-9][A-Za-z0-9._/@+=:-]{0,255}$` (ARNs and derived identities conform).
  - `evidence_digest`: Must match `^sha256:[0-9a-f]{64}$` (lowercase hex, exactly 64 characters).
  - `summary_code`: Must match `^[A-Z][A-Z0-9_]{0,63}$` (uppercase + underscores, ≤63 chars).
- **Exit code agreement (foundation-enforced):**
  - If guard records `PASS`, the wrapper must return 0 (exit code 0).
  - If guard records `FAIL`, the wrapper must return non-zero (exit code ≠ 0).
  - Mismatch triggers `GUARD_WRAPPER_STATUS_DISAGREEMENT` abort.
- **Return value:** 0 if callback succeeds; 1 if the foundation aborts (malformed fields, duplicate call, scope mismatch, status/exit-code disagreement, etc.).

### Guard Failure Behavior

When a guard records `FAIL`:
1. The callback returns non-zero to the guard wrapper.
2. The guard wrapper returns non-zero exit code.
3. The foundation aborts the entire destroy operation with a failure code (e.g., `GUARD_FAIL`).
4. Destroy is **refused before the handler is dispatched**.
5. The foundation records all results (including failures) in an ordered result set for later auditing.

---

## Canonical Resource Identities

The canonical identity for each scope is **derived exclusively from the validated platform_contract** (in-memory environment variables set by the foundation during provisioning). These identities are embedded in the evidence digest and callback invocation, ensuring auditability and preventing live-lookup inconsistencies.

### Identity Derivation

| Guard Scope | Canonical Identity | Derived From |
|---|---|---|
| `eks-platform` | Cluster ARN | `EKS_PLATFORM_IDENTITY` or `arn:aws:eks:<region>:<account>:cluster/<cluster-name>` |
| `workload-identity` | Cluster ARN + `/workload-identity` | Same base ARN as eks-platform |
| `platform-controllers` | Cluster ARN + `/platform-controllers` | Same base ARN as eks-platform |

**Example (UAT):**
- Base Cluster ARN: `arn:aws:eks:ap-east-1:672172129937:cluster/oms-uat-eks-cluster`
- `eks-platform` identity: `arn:aws:eks:ap-east-1:672172129937:cluster/oms-uat-eks-cluster`
- `workload-identity` identity: `arn:aws:eks:ap-east-1:672172129937:cluster/oms-uat-eks-cluster/workload-identity`
- `platform-controllers` identity: `arn:aws:eks:ap-east-1:672172129937:cluster/oms-uat-eks-cluster/platform-controllers`

**No Live Lookup.** The guard NEVER discovers or substitutes the identity from live AWS API calls. It ALWAYS uses the validated platform_contract.

---

## Evidence Artifact Ownership

### Foundation-Owned Durable Artifact

The foundation receives the guard's in-memory callback result (`PASS`/`FAIL`, identity, digest, summary code) and alone controls the durable evidence artifact:

- **Creation:** Foundation creates the evidence artifact only after all guard results are received and validated.
- **Format:** Ordered JSON array of guard results: `[{scope, status, resource_identity, evidence_digest, summary_code}, ...]`.
- **All-Pass Path:** If all guards record `PASS`, foundation creates the all-pass evidence artifact and proceeds with authorization.
- **Any-Fail Path:** If any guard records `FAIL` or any result is malformed/missing, foundation creates a failure artifact with the ordered results and failure metadata, and blocks destroy.
- **Reading:** Foundation alone reads the evidence artifact during approval consumption and dispatch decisions.

### Package Code: Zero Artifact Access

**EKS package code:**
- Creates **NO** evidence artifact.
- Reads **NO** evidence artifact.
- Writes **NO** evidence artifact.
- Touches **NO** artifact file or path.
- Validates **NO** artifact contents.

The guard receives the validated platform_contract as an in-memory context; the callback invocation is the **only** interface to the evidence layer. All artifact persistence, validation, and ownership remains with the foundation.

---

## Workload Identity Schema

### Exact `identities` Map Shape

Workload-identity roles are created from a Terraform `identities` map. Each map entry produces exactly one role, one inline policy, one Pod Identity association, and one output.

```hcl
identities = {
  "<key>" = {
    namespace       = "<string>"        # Kubernetes namespace (e.g., "mongodb")
    service_account = "<string>"        # Kubernetes service account (e.g., "mongodb-sidecar")
    policy_json     = "<string>"        # Inline IAM policy JSON (no ARN substitution)
    description     = "<string>"        # Human-readable role description
  }
}
```

**Constraints:**
- Role name is derived **only** from the environment and map key; no operator input to role naming.
- One role per map entry; duplication is not supported.
- Inline policy is embedded as-is; no dynamic substitution or Terraform interpolation.
- All four fields are required; any missing field causes the map entry to be rejected.

**Example:**
```hcl
identities = {
  mongodb = {
    namespace       = "mongodb"
    service_account = "mongodb-sidecar"
    policy_json     = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Effect = "Allow"
        Action = ["dynamodb:Query"]
        Resource = "arn:aws:dynamodb:*:*:table/audit-log"
      }]
    })
    description = "MongoDB sidecar workload identity for DynamoDB audit-log access"
  }
}
```

---

## Authorization & Operator Boundaries

### Strictly Disallowed

- Manual execution of `terraform apply`, `terraform destroy`, or `terraform plan` outside the orchestrator.
- Ad-hoc Terraform commands for workload-identity or platform-controller state.
- Direct manipulation of the workload-identity map without going through the authorized flow.
- Manual execution of handlers, verifiers, or guard wrappers as bash commands or subshells.
- Any attempt to write, read, or validate the foundation evidence artifact.
- Dev-mode mutations, commits, or direct Git operations on this component's code.

### Operators Use Foundation Public Entrypoints Only

```bash
# AUTHORIZED-ONLY
bash scripts/provision.sh all --auto-approve
bash scripts/provision.sh signoz --auto-approve
bash scripts/destroy.sh all --auto-approve
bash scripts/verify-platform-health.sh --smoke-test
```

This is the **only** authorized way to interact with this component. Operators:
- Do **NOT** invoke canonical wrappers (`scope_registry_*`) directly as shell commands.
- Do **NOT** call internal helpers (`eks_internal_*`) under any circumstances.
- Do **NOT** create custom scripts that source internal files.
- Do **NOT** pass component-specific CLI flags or custom modes.

### No Custom Executables or Public Modes

This component exports **no CLI flags, public modes, or standalone executables**. All interaction flows through the foundation's orchestrator, which enforces authorization, sequencing, and gate logic.

---

## Handler Behavior & Recheck Logic

### Provision Handler

1. Validates foundation state (backend, saved plan, approval).
2. Applies Terraform for workload-identity root module.
3. Applies Flux GitOps for platform-controllers.
4. Outputs state keys and resource identities.

### Destroy Handler

1. **Pre-dispatch gate:** Foundation's pre-destroy guard (read-only check) must record PASS before the handler is invoked.
2. **Immediate recheck:** Before the first mutation, the destroy handler:
   - Reads the live account, region, environment, cluster identity, EKS deletion protection, EFS protection state, backup retention, and vault-lock state.
   - Compares against the last-recorded snapshot.
   - Refuses if any value drifts (fail-closed).
3. **Mutate:** If recheck passes, proceeds to delete Terraform and Flux resources.
4. **Outcome:** Handler cannot replace or bypass the pre-destroy guard. If the pre-destroy guard fails, the foundation blocks destroy before the handler is invoked.

---

## Implementation Status

**As of 2026-08-04:**
- Tasks 1-8's static implementation (Terraform modules, gitops manifests, schema fragment, docs, tests) landed 2026-07-27.
- The runtime dispatch wiring the static implementation initially lacked (provision/destroy mutation for `workload-identity`/`platform-controllers`, pre-destroy guard registration, unified `verify` never loading package fragments) was completed and merged across issues #35/#37/#38/#41/#43/#44/#46 (PRs #39, #40, #42, #45, #47, #48).
- **All three scopes — `eks-platform`, `workload-identity`, `platform-controllers` — are live-provisioned, live-verified, and destroy-tested against real UAT** (AWS account 672172129937, cluster `oms-uat-eks-cluster`). `bash scripts/provision.sh --env uat <scope> --auto-approve` and `bash scripts/verify-platform-health.sh --env uat --full` both work end-to-end with no manual intervention. See the [Operator Runbook's Unified UAT Provisioning section](../guides/operator-runbook.md#unified-uat-provisioning---env-uat) for the confirmed working procedure.
- `platform-controllers` brings up cert-manager, Kyverno, cluster-autoscaler, metrics-server, and the AWS Load Balancer Controller — all five confirmed `READY=True` with healthy pods on a fresh provision.
- `workload-identity`'s `identities` map remains `{}` in committed tfvars (no consumer has registered a Pod Identity association yet) — this is expected, not a gap; the root itself is fully wired and provisions/destroys cleanly.

This document describes the architecture and contract; the procedural how-to for provisioning lives in the Operator Runbook.
