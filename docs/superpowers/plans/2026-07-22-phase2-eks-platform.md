# Phase 2 EKS Platform Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the UAT EKS platform, generic workload-identity root, and platform-controller delivery while preserving every foundation-owned environment, registry, orchestration, and public command contract.

**Architecture:** The environment-orchestration foundation remains the sole owner of parsing, immutable values, promotion, the scope graph, state mapping, dispatch, public entrypoints, paths, cleanup, locking, and durable pre-destroy evidence artifacts. This package contributes one declarative schema fragment, one handler fragment, one verifier fragment, three purpose-specific internal implementation files, Terraform roots/modules, GitOps manifests, focused tests, and component documentation. After foundation validation, the handler fragment may source only the EKS-owned mode-safe lifecycle/handler implementation file, while the verifier fragment uses the foundation-validated package-source helper to source both the EKS-owned mode-safe verifier implementation file and the separate EKS-owned mode-safe pre-destroy-guard implementation file; each fragment alone then defines the exact pre-mapped canonical wrapper symbols for its EKS-owned surface, while registry mappings and the graph remain unchanged. The verifier fragment alone also defines the foundation-pre-mapped `verify_eks_platform_pre_destroy`, `verify_workload_identity_pre_destroy`, and `verify_platform_controllers_pre_destroy` guard wrappers. Each delegates to one distinct read-only `eks_internal_*_pre_destroy_guard` function that performs the scope checks from foundation-provided in-memory context and live read-only platform/state observations, derives canonical resource identity from the validated `platform_contract`, computes the evidence digest and foundation-defined closed summary code, and invokes `record_pre_destroy_guard_result <scope> <PASS|FAIL> <resource-identity> <sha256-digest> <summary-code>` exactly once for the active scope after checks and computation and before returning status and diagnostic output. The EKS package creates or reads no evidence artifact and never writes one; the callback transfers the in-memory result to foundation, which alone writes and owns its durable evidence artifact. UAT mutation uses the foundation's exact `PROMOTION_MODE=uat-build` semantics; dev remains `PROMOTION_MODE=modeled` and supports static modeling only.

**Tech Stack:** Bash 3.2, Python 3 `unittest`, Terraform >= 1.10, AWS provider >= 6.0 and < 7.0, AWS CLI v2, Kubernetes/Kustomize, Helm, Flux, Amazon EKS managed add-ons, EKS Pod Identity, Amazon EFS, AWS Backup

---

## Foundation Contract

- `docs/operations/imported-code-review-matrix.md` is the only imported-code matrix.
- `scripts/validate-imported-code-review-matrix.py` is the only matrix parser and validator.
- The matrix schema is exactly `ID | Domain | Source | Target | Disposition | Evidence | Status`.
- EKS IDs begin at `EKS-0001`, use four digits, remain stable, and increase without reuse.
- `Disposition` is exactly one of `KEEP`, `REWRITE`, `REPLACE`, or `REJECT`.
- `Status` is exactly one of `PROPOSED`, `REVIEWED`, or `VERIFIED`.
- EKS schema integration is only `config/environment-schema/fragments/20-eks-platform.manifest`.
- EKS handler integration is only `scripts/lib/scope-handlers.d/20-eks-platform.sh`.
- EKS component verification integration is only `scripts/lib/scope-verifiers.d/20-eks-platform.sh`.
- The foundation registry already contains all EKS scopes, dependencies, state-key mappings, exact canonical handler/verifier symbol mappings, and `all` ordering.
- The foundation registry already maps EKS ordinary-destroy guards to exact canonical symbols `verify_eks_platform_pre_destroy`, `verify_workload_identity_pre_destroy`, and `verify_platform_controllers_pre_destroy`; the EKS package defines but never registers them.
- Only after foundation validation, the handler fragment may source the EKS-owned mode-safe lifecycle/handler implementation file, and the verifier fragment may use the validated package-source helper to source both the EKS-owned mode-safe verifier implementation file and the separate EKS-owned mode-safe pre-destroy-guard implementation file; each fragment alone defines only its exact pre-mapped canonical wrapper symbols for EKS-owned scopes.
- The foundation supplies the active scope and other immutable guard context in memory, exposes the in-memory `record_pre_destroy_guard_result` callback, and alone serializes, writes, and owns the durable pre-destroy evidence artifact.
- EKS pre-destroy code may perform live read-only platform/state observations and compute the evidence digest and foundation-defined closed summary code, but it never creates, opens, reads, validates, updates, or otherwise accesses the foundation durable evidence artifact directly.
- The validated `platform_contract` is the sole source of canonical EKS guard resource identity. For `eks-platform`, use the contract's canonical EKS cluster ARN. For `workload-identity`, use the contract's canonical EKS cluster ARN followed by `/workload-identity`. For `platform-controllers`, use the contract's canonical EKS cluster ARN followed by `/platform-controllers`. Reject a missing, malformed, unvalidated, or live-discovered substitute; do not include mutable display names, dependent sets, timestamps, digests, or evidence paths in the identity.
- Every guard invokes `record_pre_destroy_guard_result <scope> <PASS|FAIL> <resource-identity> <sha256-digest> <summary-code>` exactly once for the active scope, only after all checks and identity/digest/summary computation and before returning. The callback digest is exactly `sha256:<64 lowercase hex characters>`; raw hex is invalid. A guard never records another scope or invokes the callback from an individual check.
- The fragments do not call registry mutation APIs or mutate registry mappings, the scope graph, ordering, or `all`.
- Tests prove foundation registry loading resolves EKS symbols without changing graph, order, or mappings.
- `PROMOTION_MODE=uat-build` permits the reviewed UAT build flow. `PROMOTION_MODE=modeled` permits static modeling and validation but blocks mutation.
- No component value, handler, verifier, tfvars file, or local input overrides or reinterprets `PROMOTION_MODE`.

This package must not modify:

```text
scripts/lib/platform-env.sh
scripts/lib/environment-contracts.sh
scripts/lib/scope-registry.sh
scripts/lib/orchestrator.sh
scripts/lib/orchestration-paths.sh
scripts/provision.sh
scripts/destroy.sh
scripts/verify-platform-health.sh
```

It must not add a parser, parser aggregator, schema loader, scope, alias, dependency, state-key mapping, dispatcher, public component mode, public component executable, lock, path calculator, promotion gate, or direct mapping edit.

Legacy no-`--env` dev behavior remains unchanged. Unified dev mutation fails under `PROMOTION_MODE=modeled` before backend access, AWS access, Terraform initialization, Kubernetes access, generated files, or lock creation.

## Command Policy

Every future command block begins with `# AUTHORIZED-ONLY`. Tests, validators, formatters, syntax checks, renderers, Terraform initialization, AWS reads, Kubernetes reads, plans, applies, destroys, and commits all require separate authorization. This plan contains no commit commands and reports no execution.

## File Structure

| Path | Responsibility |
|---|---|
| `docs/operations/imported-code-review-matrix.md` | Append stable EKS decisions to the canonical seven-column matrix. |
| `config/environment-schema/fragments/20-eks-platform.manifest` | Sole EKS schema contribution, loaded by the unchanged foundation parser. |
| `scripts/lib/scope-handlers.d/20-eks-platform.sh` | After foundation validation, source only the EKS-owned mode-safe lifecycle/handler implementation file and define exact pre-mapped canonical handler wrappers for EKS-owned scopes; destroy wrappers immediately recheck identity and protection before mutation but are not the sole ordinary-destroy gate. |
| `scripts/lib/scope-verifiers.d/20-eks-platform.sh` | After foundation validation, use the validated package-source helper to source both EKS-owned mode-safe internal files, then alone define exact pre-mapped canonical verifier wrappers plus `verify_eks_platform_pre_destroy`, `verify_workload_identity_pre_destroy`, and `verify_platform_controllers_pre_destroy`; guard wrappers are read-only and preserve the check, digest/closed-summary, exactly-once foundation callback, then return ordering without durable-artifact access. |
| `scripts/lib/packages/20-eks-platform/internal/lifecycle-handlers.sh` | Mode-safe package-owned lifecycle and handler implementation, exposing only distinct handler-side `eks_internal_*` symbols and never verifier, pre-destroy-guard, or canonical registry wrapper symbols. |
| `scripts/lib/packages/20-eks-platform/internal/verifiers.sh` | Mode-safe package-owned verifier implementation, exposing only distinct verifier-side `eks_internal_*` symbols and never lifecycle, handler, pre-destroy-guard, or canonical registry wrapper symbols. |
| `scripts/lib/packages/20-eks-platform/internal/pre-destroy-guards.sh` | Mode-safe package-owned read-only pre-destroy-guard implementation, exposing only distinct guard-side `eks_internal_*` symbols, performing checks from in-memory context and live read-only observations, deriving canonical scope identity from the validated platform contract, computing an evidence digest and closed summary code, reporting once through foundation's in-memory callback, creating/reading no evidence artifact, making no filesystem writes, and never defining lifecycle, handler, verifier, or canonical registry wrapper symbols. |
| `platform-prerequisites/terraform/modules/{network,iam,eks,efs,backup}/` | Focused platform modules. |
| `platform-prerequisites/terraform/eks-platform/` | Guarded EKS platform root and stable output object. |
| `platform-prerequisites/terraform/workload-identity/` | Generic map-driven Pod Identity root. |
| `platform-prerequisites/terraform/environments/{dev,uat}/` | Non-secret tfvars; dev is model input only. |
| `gitops/platform-controllers/` | Pinned controller base and environment overlays. |
| `tests/eks_platform/` | Matrix, schema, Terraform, render, handler, verifier, and documentation tests. |
| `tests/environment_orchestration/test_scope_registry.py` | Assert existing slots resolve without graph changes and foundation persists the EKS callback result in its owned evidence artifact. |
| `docs/references/eks-platform-contract.md` | Component ownership, outputs, lifecycle, and authorization contract. |

## Stable Ownership

| Capability | Owner | Explicit non-owner |
|---|---|---|
| VPC CNI, CoreDNS, kube-proxy | EKS managed add-ons | Helm/Flux overlays |
| EBS CSI, EFS CSI, Pod Identity agent | EKS managed add-ons | Workload roots and overlays |
| metrics-server | Managed add-on in `managed-addon`; Helm in `helm-fallback` | Never both |
| cluster autoscaler | IAM in `eks-platform`; release in `platform-controllers` | Node role policies |
| AWS Load Balancer Controller | Conditional IAM and release | Disabled unless configured |
| cert-manager and Kyverno | `platform-controllers` | Application scopes |
| Percona operator | Existing `mongodb` scope | `platform-controllers` |
| Platform controller identities | `eks-platform` | Generic identity root |
| Platform-controller delivery scope and manifests | EKS package through `platform-controllers` | Data and application scopes |
| Generic cross-component Pod Identity root | EKS package through `workload-identity` | Data and component-specific roots |
| Workload identity instances | Data supplies collector map entries only | Data-owned identity roots, handlers, or registry mappings |

### Task 1: Append Canonical EKS Review Decisions

**Files:**
- Modify: `docs/operations/imported-code-review-matrix.md`
- Create: `tests/eks_platform/__init__.py`
- Create: `tests/eks_platform/test_import_review.py`

- [ ] Inventory approved read-only candidates under `../../../../Boomi/boomi-infra/infra`.
- [ ] Import and reuse `parse_matrix` and `validate_rows` from the foundation validator; add no local Markdown parser or validator.
- [ ] Assert the exact seven-column header and no `Test` column.
- [ ] Assert discovered sources equal EKS rows, IDs are unique and sequential from `EKS-0001`, and enum values are uppercase.
- [ ] Preserve non-EKS rows unchanged.
- [ ] Append one stable row per candidate or independently classified resource with concrete evidence.
- [ ] Use `REWRITE` for reusable intent needing private networking, guards, versions, and least privilege; `REPLACE` for legacy wrappers superseded by foundation; `REJECT` for mixed workload/token state, authentication helpers, current-dev discovery, unresolved examples, public-only API, SSH defaults, node-role controller privileges, and legacy locking.
- [ ] Require `REVIEWED` or `VERIFIED` before any authorized UAT plan; `PROPOSED` blocks the gate.

```bash
# AUTHORIZED-ONLY
python3 scripts/validate-imported-code-review-matrix.py docs/operations/imported-code-review-matrix.md
python3 -m unittest tests.eks_platform.test_import_review -v
```

Expected: PASS with exact columns, uppercase enums, stable IDs, and complete inventory.

### Task 2: Add The Sole EKS Schema Fragment

**Files:**
- Create: `config/environment-schema/fragments/20-eks-platform.manifest`
- Create: `tests/eks_platform/test_environment_contract.py`

- [ ] Test lexical discovery through the existing foundation parser without changing parser or aggregator code.
- [ ] Cover required keys, enum validation, numeric bounds, CIDR syntax/containment/overlap, immutable rejection, duplicate/unknown keys, and command-substitution rejection through foundation validator hooks.
- [ ] Assert UAT loads exact `PROMOTION_MODE=uat-build` and dev loads exact `PROMOTION_MODE=modeled` from foundation.
- [ ] Do not declare promotion, account, Region, state prefix, state keys, paths, or authorization values in the fragment.
- [ ] Declare EKS-owned VPC/AZ/subnet, connected CIDR, NAT, Kubernetes, endpoint, deletion, node, EFS, backup, add-on, controller-version, and feature-flag keys using foundation manifest grammar.
- [ ] Use exact enums `single|one-per-az` and `managed-addon|helm-fallback`.
- [ ] Require private endpoint access, deletion protection, UAT backup retention of at least 35 days, `1 <= min <= desired <= max <= 20`, and root volume at least 20 GiB.

```bash
# AUTHORIZED-ONLY
python3 -m unittest tests.eks_platform.test_environment_contract tests.environment_orchestration.test_environment_contract -v
```

Expected: PASS with lexical discovery and no parser, immutable-contract, or aggregator edits.

### Task 3: Implement Platform Terraform

**Files:**
- Create: `tests/eks_platform/test_terraform_contract.py`
- Create: `platform-prerequisites/terraform/modules/network/{variables,main,outputs}.tf`
- Create: `platform-prerequisites/terraform/modules/iam/{variables,main,outputs}.tf`
- Create: `platform-prerequisites/terraform/modules/eks/{variables,main,outputs}.tf`
- Create: `platform-prerequisites/terraform/modules/efs/{variables,main,outputs}.tf`
- Create: `platform-prerequisites/terraform/modules/backup/{variables,main,outputs}.tf`
- Create: `platform-prerequisites/terraform/eks-platform/{versions,variables,main,checks,outputs}.tf`
- Create: `platform-prerequisites/terraform/environments/{dev,uat}/eks-platform.tfvars`

- [ ] Test AZ-keyed network topology and explicit NAT mode.
- [ ] Test separate cluster, node, add-on, autoscaler, and conditional load-balancer-controller identities; node roles have no controller, SSH, administrator, or workload privileges.
- [ ] Test Pod Identity trust uses `pods.eks.amazonaws.com`, `sts:AssumeRole`, and `sts:TagSession`.
- [ ] Test API authentication, private endpoint, five control-plane logs, deletion protection, private nodes, encrypted GP3, IMDSv2, no key pair, explicit add-on versions, and singular metrics-server ownership.
- [ ] Test encrypted private EFS with restricted NFS and ordinary-destroy protection.
- [ ] Test EFS backup selection, approved KMS input, UAT retention, vault lock, and restore-test metadata without claiming a restore occurred.
- [ ] Compose all modules once behind AWS account and Region guards, S3 native lockfiles, version/AZ/quota checks, and no Kubernetes/Helm/Flux provider or workload resource.
- [ ] Publish one non-secret `platform_contract` object containing environment/platform identity, network, cluster, EFS, backup, add-on, and platform Pod Identity outputs.
- [ ] Keep backend keys out of tfvars. Dev tfvars are static model inputs and cannot initialize state under `PROMOTION_MODE=modeled`.

```bash
# AUTHORIZED-ONLY
terraform fmt -check -recursive platform-prerequisites/terraform/modules platform-prerequisites/terraform/eks-platform
terraform -chdir=platform-prerequisites/terraform/eks-platform init -backend=false
terraform -chdir=platform-prerequisites/terraform/eks-platform validate
python3 -m unittest tests.eks_platform.test_terraform_contract -v
```

Expected: PASS. Provider download authorization does not authorize AWS access.

### Task 4: Implement Generic Workload Identity

**Files:**
- Create: `platform-prerequisites/terraform/workload-identity/{versions,variables,main,outputs}.tf`
- Create: `platform-prerequisites/terraform/environments/{dev,uat}/workload-identity.tfvars`
- Modify: `tests/eks_platform/test_terraform_contract.py`

- [ ] Keep unequivocal ownership of the generic `workload-identity` root in EKS; data may supply only collector entries in the `identities` map and owns no root, handler, verifier, scope, or registry mapping.
- [ ] Define the generic object with this exact shape and no additional or optional field:

```hcl
variable "identities" {
  type = map(object({
    namespace       = string
    service_account = string
    policy_json     = string
    description     = string
  }))
  default = {}
}
```

- [ ] Derive each role name only from validated environment plus identity map key; accept no role-name input.
- [ ] Use the `eks-platform` remote-state contract and require matching account, Region, environment, and cluster identity.
- [ ] Create one role, inline policy, association, and output-map entry per map entry.
- [ ] Start both committed maps with `identities = {}`.
- [ ] In one test only, add one fixture entry and assert exactly one IAM role, one inline policy, one Pod Identity association, and one output-map entry.
- [ ] In that same test, reject hard-coded fixture namespace, service account, policy, description, role name, or conditional fixture resource. Do not duplicate the exact-once assertion elsewhere.

```bash
# AUTHORIZED-ONLY
terraform -chdir=platform-prerequisites/terraform/workload-identity fmt -check -recursive
terraform -chdir=platform-prerequisites/terraform/workload-identity init -backend=false
terraform -chdir=platform-prerequisites/terraform/workload-identity validate
python3 -m unittest tests.eks_platform.test_terraform_contract.TerraformContractTests.test_workload_identity_root -v
```

Expected: PASS and zero committed identity resources.

### Task 5: Define Platform Controllers

**Files:**
- Create: `tests/eks_platform/test_controller_render.py`
- Create: `gitops/platform-controllers/base/{kustomization,namespaces,sources,releases}.yaml`
- Create: `gitops/platform-controllers/overlays/{dev,uat}/{kustomization,platform-settings}.yaml`

- [ ] Keep unequivocal ownership of the `platform-controllers` scope and manifests in EKS; data supplies no controller scope, release, handler, verifier, or registry mapping.
- [ ] Test pinned versions, environment labels, UAT cluster identity, autoscaler Pod Identity service account, conditional load-balancer-controller absence, singular metrics-server ownership, and absence of managed add-on or Percona resources.
- [ ] Define pinned Flux sources/releases for cert-manager, Kyverno, cluster autoscaler, conditional metrics-server fallback, and conditional AWS Load Balancer Controller.
- [ ] Configure bounded timeouts, remediation, resources, and CRD ownership only where required.
- [ ] Keep dev rendering private and static. Add no public render mode, component flag, or executable.

```bash
# AUTHORIZED-ONLY
python3 -m unittest tests.eks_platform.test_controller_render -v
```

Expected: PASS using local rendering or mocks only.

### Task 6: Define Canonical Handler Wrappers

**Files:**
- Create: `scripts/lib/scope-handlers.d/20-eks-platform.sh`
- Create: `scripts/lib/packages/20-eks-platform/internal/lifecycle-handlers.sh`
- Create: `tests/eks_platform/test_handlers.py`
- Modify: `tests/environment_orchestration/test_scope_registry.py`

- [ ] Load the unchanged foundation registry and lexical handler fragments exactly as the orchestrator does.
- [ ] Assert foundation validation completes before the fragment sources only the EKS-owned mode-safe lifecycle/handler implementation file at the validated package path `scripts/lib/packages/20-eks-platform/internal/lifecycle-handlers.sh`; reject path escape, substitution, the verifier/pre-destroy-guard implementation file, or any alternate library path.
- [ ] Assert pre-mapped `eks-platform`, `workload-identity`, and `platform-controllers` canonical handler symbols resolve to exact wrapper functions defined in the fragment.
- [ ] Assert the lifecycle/handler implementation file defines handler helpers only with distinct `eks_internal_*` names, defines no verifier or pre-destroy-guard helper and no canonical registry wrapper symbol, and cannot collide with or recursively call a canonical wrapper; assert each fragment wrapper delegates to its mapped internal helper without recursion.
- [ ] Snapshot catalog, dependencies, provision/reverse-destroy order, state mappings, and public entrypoints; assert they remain unchanged after fragment loading.
- [ ] Fail if the fragment writes registry arrays, calls a registry mutation API, adds or changes a symbol mapping, or changes the graph or `all`.
- [ ] Assert foundation rejects `PROMOTION_MODE=modeled` before an EKS handler runs.
- [ ] Assert `PROMOTION_MODE=uat-build` still requires foundation account, Region, backend, context, saved-plan, approval, and ownership guards.
- [ ] Define only Bash 3.2-compatible exact canonical wrapper functions for the pre-mapped EKS-owned scopes; wrappers delegate to the EKS-owned mode-safe internal library.
- [ ] Implement package-owned lifecycle and handler behavior only in Bash 3.2-compatible `eks_internal_*` functions in `lifecycle-handlers.sh`; it must never define verifier, pre-destroy-guard, or canonical registry wrapper symbols.
- [ ] Use foundation state lookup, backend validation, paths, cleanup, saved-plan, guard, and approval APIs; do not parse arguments, calculate paths, acquire locks, call public scripts, or alter registry data.
- [ ] Preserve EKS deletion protection, EFS `prevent_destroy`, Backup Vault Lock, retained controls, and foundation break-glass rules in canonical destroy wrappers.
- [ ] Immediately before the first destroy mutation, re-read and match account, Region, environment, platform identity, EKS deletion protection, EFS protection, backup retention, and vault-lock state. Refuse on drift or missing observations. This last-moment handler recheck is defense in depth and must not replace or bypass foundation's decision based on the guard result and foundation-owned durable evidence artifact.

```bash
# AUTHORIZED-ONLY
bash -n scripts/lib/packages/20-eks-platform/internal/lifecycle-handlers.sh scripts/lib/scope-handlers.d/20-eks-platform.sh
python3 -m unittest tests.eks_platform.test_handlers tests.environment_orchestration.test_scope_registry -v
```

Expected: PASS with unchanged graph/mappings and resolved foundation symbols.

### Task 7: Define Canonical Component-Verifier Wrappers

**Files:**
- Create: `scripts/lib/scope-verifiers.d/20-eks-platform.sh`
- Create: `scripts/lib/packages/20-eks-platform/internal/verifiers.sh`
- Create: `scripts/lib/packages/20-eks-platform/internal/pre-destroy-guards.sh`
- Create: `tests/eks_platform/test_verifiers.py`
- Modify: `tests/environment_orchestration/test_scope_registry.py`

- [ ] Load the unchanged foundation registry and lexical verifier fragments exactly as the verifier orchestration does.
- [ ] Assert foundation validation completes before the fragment uses the foundation-validated package-source helper to source exactly both EKS-owned mode-safe files at `scripts/lib/packages/20-eks-platform/internal/verifiers.sh` and `scripts/lib/packages/20-eks-platform/internal/pre-destroy-guards.sh`; reject path escape, substitution, the lifecycle/handler implementation file, a missing or duplicate source, direct unvalidated sourcing, or any alternate library path.
- [ ] Assert pre-mapped EKS platform, workload identity, and platform controller canonical verifier symbols resolve to exact wrapper functions defined in the fragment.
- [ ] Assert foundation-pre-mapped ordinary-destroy guard symbols resolve exactly to `verify_eks_platform_pre_destroy`, `verify_workload_identity_pre_destroy`, and `verify_platform_controllers_pre_destroy` in the verifier fragment, with no registration or mapping mutation.
- [ ] Assert `verifiers.sh` defines only verifier helpers with distinct `eks_internal_*` names and defines no lifecycle, handler, pre-destroy-guard, or canonical registry wrapper symbol; assert `pre-destroy-guards.sh` defines only guard helpers with distinct `eks_internal_*_pre_destroy_guard` names and defines no lifecycle, handler, verifier, or canonical registry wrapper symbol. Assert neither file can collide with or recursively call a canonical wrapper and each fragment wrapper delegates to its mapped helper without recursion.
- [ ] Assert the numbered verifier fragment alone defines all canonical verifier and guard wrappers; neither internal file may define or source the other internal file or any canonical wrapper fragment.
- [ ] Assert `verify_eks_platform_pre_destroy`, `verify_workload_identity_pre_destroy`, and `verify_platform_controllers_pre_destroy` delegate only to distinct read-only `eks_internal_eks_platform_pre_destroy_guard`, `eks_internal_workload_identity_pre_destroy_guard`, and `eks_internal_platform_controllers_pre_destroy_guard` functions from `pre-destroy-guards.sh`, respectively, without calling verifier helpers, handlers, mutation APIs, write-capable commands, or any foundation durable-evidence file API.
- [ ] Snapshot the same graph and mapping surfaces as Task 6 and assert no change.
- [ ] Add no verification mode, CLI flag, public executable, scope, dependency, or mapping.
- [ ] Implement package-owned verifier behavior only in Bash 3.2-compatible `eks_internal_*` functions in `verifiers.sh`; it must never define lifecycle, handler, pre-destroy-guard, or canonical registry wrapper symbols.
- [ ] Implement package-owned pre-destroy-guard behavior only in Bash 3.2-compatible `eks_internal_*_pre_destroy_guard` functions in `pre-destroy-guards.sh`; it must never define lifecycle, handler, verifier, or canonical registry wrapper symbols. The numbered verifier fragment alone defines the exact mapped canonical verifier and guard wrappers.
- [ ] Verify read-only platform identity, EKS configuration/readiness, managed add-on ownership/versions, EFS network/protection, backup retention/lock, generic identity associations, and controller ownership/readiness/absence rules.
- [ ] For each pre-destroy guard, consume the foundation-provided active scope, environment, account, Region, validated `platform_contract`, state identity, and canonical dependent set from in-memory context; refuse ordinary destroy unless all registered dependents are absent and the scope-specific identity matches current live read-only AWS and Terraform observations. Derive the canonical resource identity exactly as specified in the Foundation Contract: cluster ARN for `eks-platform`, cluster ARN plus `/workload-identity` for `workload-identity`, and cluster ARN plus `/platform-controllers` for `platform-controllers`. Do not discover or replace contract context through live lookup or an evidence artifact.
- [ ] For `verify_eks_platform_pre_destroy`, check through live read-only observations that workload identity and platform controller dependents are absent, EFS recovery/backup state is present, required backup recovery points satisfy retention, Backup Vault Lock remains effective, EFS `prevent_destroy` and EKS deletion protection remain enabled, and every foundation retention/protection requirement is intact.
- [ ] For `verify_workload_identity_pre_destroy` and `verify_platform_controllers_pre_destroy`, check their registered dependents are absent and check retained platform identity, EFS, backup-retention, vault-lock, and deletion-protection state remains valid; absence of an optional resource is not equivalent to missing protection state.
- [ ] After all scope checks complete, compute a deterministic SHA-256 digest over the canonical checked observations and choose the foundation-defined closed summary code for the result. Invoke `record_pre_destroy_guard_result <scope> <PASS|FAIL> <resource-identity> <sha256-digest> <summary-code>` exactly once, substituting the active scope, uppercase result, validated-contract-derived canonical resource identity, exact `sha256:<64 lowercase hex characters>` digest, and closed summary code, then return matching success or failure plus diagnostic output. Record failed as well as successful checks; do not invoke before checks complete, before identity/digest/code computation, from an individual check, more than once, or for any non-active scope.
- [ ] EKS guard code must create or read no evidence artifact and must not validate, write, persist, cache, touch, truncate, append, redirect output into, or otherwise access the foundation-owned durable evidence artifact. Foundation receives only the in-memory callback result and alone serializes, writes, validates, and owns the artifact; ordinary destroy refuses before handler dispatch when foundation evaluates a failed or missing recorded result, while break-glass remains foundation-owned and cannot be inferred or implemented by this package.
- [ ] Test each guard's success path with read-only command fakes, a callback spy, and a write-detecting sandbox. Assert checks occur before canonical identity, digest, and closed-summary computation; computation occurs before exactly one `record_pre_destroy_guard_result <scope> <PASS|FAIL> <resource-identity> <sha256-digest> <summary-code>` invocation containing the active scope, `PASS`, expected validated-contract-derived identity, expected lowercase 64-hex digest, and success summary code; return success occurs afterward. Assert no callback for another scope and no evidence artifact is created, read, or written.
- [ ] Test each guard's failure path with the same fakes, spy, sandbox, ordering, identity derivation, and artifact assertions as success. Assert exactly one `record_pre_destroy_guard_result <scope> <PASS|FAIL> <resource-identity> <sha256-digest> <summary-code>` invocation containing the active scope, `FAIL`, the same expected validated-contract-derived identity, the digest of the canonical failed observations, and the matching closed failure summary code; return failure occurs afterward. Fail either path if `pre-destroy-guards.sh` or a guard wrapper changes filesystem contents or metadata, accesses an evidence-artifact path, emits a mutation request, initializes state, or invokes any write-capable helper other than the in-memory callback; diagnostic stdout/stderr and process status remain permitted effects.
- [ ] Extend foundation-owned tests in `tests/environment_orchestration/test_scope_registry.py` to invoke EKS canonical guards through the existing mappings and capture each guard's single `record_pre_destroy_guard_result <scope> <PASS|FAIL> <resource-identity> <sha256-digest> <summary-code>` invocation. Assert foundation serializes a complete all-`PASS` ordered result set into the all-pass evidence artifact. Assert any `FAIL`, missing, duplicate, or invalid result writes only `destroy-guard-failure.<operation-id>.json` with the ordered results received and failure metadata, never writes the all-pass artifact, and blocks approval, confirmation consumption, and dispatch. Only foundation integration tests read either record; EKS package code reads neither. Apply the same identity and digest validation rules to both result paths.
- [ ] Do not reconcile, mutate, generate or write files, initialize state, call handlers, or expose component-specific public modes. Foundation preflight/full/smoke flow decides when canonical verifier wrappers run.

```bash
# AUTHORIZED-ONLY
bash -n scripts/lib/packages/20-eks-platform/internal/verifiers.sh scripts/lib/packages/20-eks-platform/internal/pre-destroy-guards.sh scripts/lib/scope-verifiers.d/20-eks-platform.sh
python3 -m unittest tests.eks_platform.test_verifiers tests.environment_orchestration.test_scope_registry -v
```

Expected: PASS with read-only pre-destroy guards reporting exactly once in memory, foundation-owned durable evidence integration enforced through existing mappings, no EKS filesystem writes, and no public verification surface change.

### Task 8: Document And Gate The Component

**Files:**
- Create: `docs/references/eks-platform-contract.md`
- Create: `tests/eks_platform/test_documentation.py`

- [ ] Document ownership, state, output, exact workload-identity shape, lifecycle protection, promotion semantics, the three distinct private lifecycle/handler, verifier, and pre-destroy-guard implementation files, read-only guard check/digest/closed-summary/exactly-once-callback semantics, foundation-only durable-artifact ownership, and authorization boundaries.
- [ ] Document that operators use only foundation public entrypoints; component handler and verifier wrappers are exact pre-mapped canonical symbols, not commands, and do not mutate registry mappings or the graph.
- [ ] Document that ordinary destroy is refused before handler dispatch when the foundation-invoked read-only guard fails its dependent-absence, EFS recovery/backup, retention, vault-lock, or deletion-protection checks. Document each scope's validated-platform-contract canonical resource identity. The guard computes the SHA-256 evidence digest and foundation-defined closed summary code, invokes `record_pre_destroy_guard_result <scope> <PASS|FAIL> <resource-identity> <sha256-digest> <summary-code>` exactly once, and then returns matching status/output; package code creates or reads no evidence artifact and never writes one, foundation alone persists and owns its artifact, and the destroy handler immediately rechecks identity and protection before mutation but never owns the sole gate.
- [ ] Require every documentation command block to begin `# AUTHORIZED-ONLY`.
- [ ] Reject commit commands, direct handler/verifier invocation, component executables/modes, dev mutation examples, and claims that UAT is deployed, tested, verified, or accepted.

```bash
# AUTHORIZED-ONLY
python3 -m unittest tests.eks_platform.test_documentation -v
python3 scripts/validate-imported-code-review-matrix.py docs/operations/imported-code-review-matrix.md
python3 -m unittest discover -s tests/eks_platform -p 'test_*.py' -v
python3 -m unittest tests.environment_orchestration.test_environment_contract tests.environment_orchestration.test_scope_registry -v
bash -n scripts/lib/packages/20-eks-platform/internal/lifecycle-handlers.sh scripts/lib/packages/20-eks-platform/internal/verifiers.sh scripts/lib/packages/20-eks-platform/internal/pre-destroy-guards.sh scripts/lib/scope-handlers.d/20-eks-platform.sh scripts/lib/scope-verifiers.d/20-eks-platform.sh
git diff --check
```

Expected: PASS in a separately authorized future session. This plan records no such execution.

## Review Checklist

1. Canonical matrix only, exact seven columns, foundation validator reused, and IDs start at `EKS-0001`.
2. No test column, local matrix parser, local validator, or malformed Python.
3. Schema integration only through `config/environment-schema/fragments/20-eks-platform.manifest`.
4. Handler integration only through `scripts/lib/scope-handlers.d/20-eks-platform.sh`.
5. Verifier integration only through `scripts/lib/scope-verifiers.d/20-eks-platform.sh`.
6. No registry graph, ordering, state mapping, orchestrator, parser, immutable-contract, or public-script edit.
7. UAT is `PROMOTION_MODE=uat-build`; dev is `PROMOTION_MODE=modeled`.
8. Generic identity fields are exactly `namespace`, `service_account`, `policy_json`, and `description`.
9. Role names derive from environment plus map key, and one test asserts exact-once resources.
10. Component verification defines exact pre-mapped canonical wrappers without registry mapping or graph changes, public modes, or executables.
11. Lifecycle/handler, verifier, and pre-destroy-guard internals are three distinct files, all distinct from canonical wrapper fragments; after foundation validation, the handler fragment sources only its internal implementation and the numbered verifier fragment uses the validated package-source helper to source exactly both of its corresponding internal implementations.
12. The numbered verifier fragment alone defines exact foundation-pre-mapped EKS verifier and pre-destroy guard wrappers; guard wrappers delegate to distinct read-only `eks_internal_*_pre_destroy_guard` helpers from `pre-destroy-guards.sh`, perform checks from foundation-provided in-memory context and live read-only observations, derive the scope-specific canonical resource identity from the validated platform contract, compute the SHA-256 evidence digest and closed summary code, invoke `record_pre_destroy_guard_result <scope> <PASS|FAIL> <resource-identity> <sha256-digest> <summary-code>` exactly once in the required order on both success and failure, create/read no evidence artifact, make no filesystem writes, and cause ordinary destroy to refuse before handler dispatch on failure.
13. Destroy handlers immediately recheck identity and protections before mutation, but cannot replace or bypass the pre-destroy gate.
14. Every command is authorized-only, and no execution or commit is reported.

## Completion Gate

Implementation is complete only after separately authorized checks pass, all EKS candidates have canonical reviewed decisions, foundation tests prove exact pre-mapped EKS wrapper and pre-destroy guard symbols resolve without graph or mapping changes, lifecycle/handler, verifier, and pre-destroy-guard internals remain three distinct files separate from canonical wrappers, the numbered verifier fragment proves it uses the validated package-source helper to source exactly both verifier-side internal files and alone defines canonical verifier/guard wrappers, ordinary destroy refuses before handler dispatch when a read-only guard fails its dependent-absence or protection checks, each guard proves checks precede validated-contract canonical resource-identity, deterministic SHA-256 evidence-digest, and closed-summary computation, computation precedes exactly one in-memory `record_pre_destroy_guard_result <scope> <PASS|FAIL> <resource-identity> <sha256-digest> <summary-code>` invocation on success or failure, and matching return follows the callback, EKS tests prove package code creates or reads no evidence artifact and makes no filesystem writes, foundation tests alone prove callback-to-foundation-owned-evidence-artifact integration with aligned `PASS`/`FAIL` identity and digest validation plus dispatch refusal for failed or missing results, destroy handlers prove their immediate identity/protection recheck, Terraform and GitOps ownership tests pass, canonical verifier wrappers report expected state, UAT acceptance evidence is attached, and dev remains modeled. This plan itself authorizes and reports no execution or commit.
