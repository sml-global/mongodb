# Task 7 Canonical Verifiers Preflight Rubric

Date: 2026-07-27
Scope: Phase 2 EKS Platform Task 7 only
Plan source: docs/superpowers/plans/2026-07-22-phase2-eks-platform.md

## Objective

Gate Task 7 implementation before code mutation so canonical verifier and pre-destroy-guard wrappers remain read-only, rely exclusively on the in-memory foundation callback, and preserve the exact three-file boundary without accessing the foundation-owned durable evidence artifact.

## Required Inputs

- Approved Task 7 section from the EKS platform implementation plan.
- Current foundation orchestrator (record_pre_destroy_guard_result contract) and scope-registry (canonical symbol mappings).
- Current worktree state on branch feat/uat-access-foundation.

## Six Canonical Symbols Defined By This Fragment

The verifier fragment alone must define all six of the following, with no extra definitions:

| Symbol | Kind | Delegates to |
|---|---|---|
| `scope_registry_verify_eks_platform` | verifier wrapper | `eks_internal_eks_platform_verifier` (in verifiers.sh) |
| `scope_registry_verify_workload_identity` | verifier wrapper | `eks_internal_workload_identity_verifier` (in verifiers.sh) |
| `scope_registry_verify_platform_controllers` | verifier wrapper | `eks_internal_platform_controllers_verifier` (in verifiers.sh) |
| `verify_eks_platform_pre_destroy` | guard wrapper | `eks_internal_eks_platform_pre_destroy_guard` (in pre-destroy-guards.sh) |
| `verify_workload_identity_pre_destroy` | guard wrapper | `eks_internal_workload_identity_pre_destroy_guard` (in pre-destroy-guards.sh) |
| `verify_platform_controllers_pre_destroy` | guard wrapper | `eks_internal_platform_controllers_pre_destroy_guard` (in pre-destroy-guards.sh) |

Neither internal file may define any of these six symbols.

## Foundation Callback Contract (Exact)

`record_pre_destroy_guard_result <scope> <PASS|FAIL> <resource-identity> <sha256-digest> <summary-code>`

Foundation enforces:
- `scope` must equal the active guard scope for this invocation.
- `guard_status` must be exactly `PASS` or `FAIL` (uppercase, no other value).
- `resource_identity` must match `^[A-Za-z0-9][A-Za-z0-9._/@+=:-]{0,255}$`.
- `evidence_digest` must match `^sha256:[0-9a-f]{64}$` (lowercase hex, no uppercase).
- `summary_code` must match `^[A-Z][A-Z0-9_]{0,63}$`.
- Callback must be called exactly once; a second call triggers `GUARD_DUPLICATE_RESULT` abort.
- Callback must not be called before all checks and identity/digest/code computation.
- `GUARD_MISSING_RESULT`: if the guard wrapper returns without calling the callback, foundation aborts the destroy run.
- `GUARD_WRAPPER_STATUS_DISAGREEMENT`: if the guard records `PASS` but the wrapper function exits non-zero, or records `FAIL` but exits zero, foundation aborts with `GUARD_WRAPPER_STATUS_DISAGREEMENT`.

Tests must cover every abort path listed above.

## Canonical Resource Identity Derivation

Derived exclusively from the validated `platform_contract` output (no live substitution, no evidence artifact):

| Guard scope | Identity string |
|---|---|
| `eks-platform` | Cluster ARN (e.g., `arn:aws:eks:ap-east-1:672172129937:cluster/oms-uat-eks-cluster`) |
| `workload-identity` | Cluster ARN + `/workload-identity` |
| `platform-controllers` | Cluster ARN + `/platform-controllers` |

Reject a missing, malformed, unvalidated, or live-discovered substitute.

## PASS/FAIL Matrix

| Dimension | Check | PASS Criteria | FAIL Trigger |
|---|---|---|---|
| Safety | Foundation boundary | No edits to foundation-owned orchestrator/registry/evidence scripts | Any mutation to prohibited foundation files |
| Safety | Task 7 scope isolation | Changes limited to Task 7 file list only | Any Task 8+ or unrelated file mutation |
| Contract | Dual-source boundary | Fragment sources exactly verifiers.sh then pre-destroy-guards.sh via validated package-source helper; no other source call | Missing source, extra source, direct unvalidated sourcing, or alternate path |
| Contract | Mutual non-sourcing | verifiers.sh does not source pre-destroy-guards.sh; pre-destroy-guards.sh does not source verifiers.sh | Either file sources the other |
| Contract | Fragment owns all six symbols | All six canonical symbols (three verifier + three guard wrappers) defined only in the fragment | Any canonical symbol defined in an internal file or missing from fragment |
| Contract | Internal symbol discipline | verifiers.sh defines only `eks_internal_*` verifier helpers; pre-destroy-guards.sh defines only `eks_internal_*_pre_destroy_guard` helpers | Cross-surface symbol leakage into either internal file |
| Contract | No lifecycle/handler symbols in internal files | Neither verifiers.sh nor pre-destroy-guards.sh defines a lifecycle or handler symbol | Any `eks_internal_*_provision_handler`, `eks_internal_*_destroy_handler`, or lifecycle symbol in verifier-side files |
| Correctness | Read-only guard semantics | Guards use only live read-only AWS/Terraform observations and in-memory context; no mutation APIs, no write-capable shell commands, no filesystem writes | Any terraform apply, aws create/delete/update, file write, or state init |
| Correctness | Callback mandatory on every path | record_pre_destroy_guard_result is called exactly once on both the success path and the failure path of every guard | Guard returns without calling callback (GUARD_MISSING_RESULT), calls twice (GUARD_DUPLICATE_RESULT), or calls from individual check |
| Correctness | Callback ordering | Checks complete → identity derived → SHA-256 digest computed → summary_code chosen → exactly one callback invocation → return | Callback invoked before checks complete or before identity/digest/code computation |
| Correctness | Callback field format | Digest matches `^sha256:[0-9a-f]{64}$`; identity matches foundation regex; summary_code matches `^[A-Z][A-Z0-9_]{0,63}$` | Any lowercase digest hex missing sha256: prefix, uppercase digest hex, malformed identity, or lowercase summary_code |
| Correctness | Status-exit agreement | Guard recording PASS exits 0; guard recording FAIL exits non-zero (GUARD_WRAPPER_STATUS_DISAGREEMENT abort otherwise) | PASS with non-zero exit or FAIL with zero exit |
| Correctness | Zero artifact access | EKS guard code creates, reads, touches, truncates, appends to, or validates no evidence artifact | Any access to foundation evidence artifact paths |
| Operability | Dependent-absence check | eks_platform guard refuses if workload-identity or platform-controllers dependents are still present | Guard passes when registered dependents are not absent |
| Operability | Protection-state check | Guards verify EKS deletion protection, EFS prevent_destroy, backup retention, and vault-lock remain intact | Guard passes when any protection flag is absent or below threshold |
| Portability | Bash 3.2 compatibility | No associative arrays, no declare -g, no namerefs, no Bash 4+ features in any of the three files | Any Bash 4+ syntax |
| Testability | Success path spy | test_verifiers.py tests success path with callback spy asserting exact scope, PASS, contract-derived identity, lowercase 64-hex digest, and success summary_code, plus exit 0 | Missing spy, wrong field values, or missing exit-code assertion |
| Testability | Failure path spy | Same test structure for failure path asserting FAIL, matching digest of failed observations, failure summary_code, and non-zero exit | Missing failure path test or missing exit-code assertion |
| Testability | Artifact sandbox | Write-detecting sandbox asserts no evidence artifact is created, read, or written on success or failure path | No filesystem write check in tests |
| Testability | GUARD_MISSING_RESULT coverage | Test that a guard returning without calling the callback triggers foundation abort (GUARD_MISSING_RESULT) | Missing test for callback-skip path |
| Testability | GUARD_WRAPPER_STATUS_DISAGREEMENT coverage | Test that PASS-recorded guard returning non-zero and FAIL-recorded guard returning zero both trigger foundation abort | Missing disagreement path test |
| Testability | Registry snapshot | test_scope_registry.py extended assertions confirm six EKS verifier/guard symbols resolve without graph/mapping drift vs. pre-load snapshot | Any new scope, dependency, order change, or mapping mutation after fragment load |

## Task 7 Mutation File List

- `scripts/lib/scope-verifiers.d/20-eks-platform.sh`
- `scripts/lib/packages/20-eks-platform/internal/verifiers.sh`
- `scripts/lib/packages/20-eks-platform/internal/pre-destroy-guards.sh`
- `tests/eks_platform/test_verifiers.py`
- `tests/environment_orchestration/test_scope_registry.py`

## Verification Gate

Run local/static verification only:

```bash
# AUTHORIZED-ONLY
bash -n scripts/lib/packages/20-eks-platform/internal/verifiers.sh \
     scripts/lib/packages/20-eks-platform/internal/pre-destroy-guards.sh \
     scripts/lib/scope-verifiers.d/20-eks-platform.sh
python3 -m unittest tests.eks_platform.test_verifiers tests.environment_orchestration.test_scope_registry -v
```

Expected:
- `bash -n` clean for all three shell files.
- All tests PASS with read-only guards reporting exactly once in memory.
- Foundation durable evidence integration enforced through existing registry mappings.
- No EKS filesystem writes on any test path.
- No public verification surface changes.

## Decision Template

- Decision: PASS or FAIL
- Blocking findings:
  - &lt;finding 1&gt;
  - &lt;finding 2&gt;
- Required remediations:
  - &lt;action 1&gt;
  - &lt;action 2&gt;
- Approved mutation scope:
  - &lt;file list above&gt;

## Dispatch Guardrails

- Do not parse CLI arguments, calculate paths, acquire locks, or register new scopes.
- Do not access, validate, read, write, or touch the foundation-owned durable evidence artifact.
- Guard return code must agree with the recorded PASS/FAIL status (both zero/non-zero pairs must be tested).
- Ensure the failure path of every guard always calls the callback before returning.
- Mandatory review order after implementation: spec-compliance review first, code-quality review second.
