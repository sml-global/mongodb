# Task 4 Workload Identity Preflight Rubric

Date: 2026-07-25
Scope: Phase 2 EKS Platform Task 4 only
Plan source: docs/superpowers/plans/2026-07-22-phase2-eks-platform.md

## Objective

Gate Task 4 readiness before implementation so the generic workload-identity root stays deterministic, map-driven, and isolated from foundation and data-package ownership.

## Required Inputs

- Approved Task 4 block in the EKS platform implementation plan.
- Current Task 3 platform_contract output shape in the EKS platform root.
- Current repository state in worktree branch feat/uat-access-foundation.

## PASS/FAIL Matrix

| Dimension | Check | PASS Criteria | FAIL Trigger |
|---|---|---|---|
| Safety | Foundation boundary | No edits to foundation-owned parser/orchestrator/registry/public entrypoint files | Any edit proposed outside Task 4 scope |
| Safety | Scope isolation | Mutations limited to Task 4 file list only | Task 5+ files or unrelated package files included |
| Contract | Identity map schema | identities variable is exactly map(object({ namespace, service_account, policy_json, description })) with default {} and no optional/additional fields | Any extra field, optional field, alternate type, or default non-empty map |
| Contract | Role naming | IAM role names derived only from validated environment and identity map key | Any user-provided role-name input or hard-coded role names |
| Contract | Remote-state usage | Root consumes eks-platform platform_contract via remote state and verifies account/region/environment/cluster identity match | No identity check, live-discovered substitute, or ad-hoc contract parsing |
| Operability | Deterministic resource fan-out | Exactly one IAM role, inline policy, Pod Identity association, and output-map entry per identities map entry | Conditional fixture-only resources or non-map-driven resources |
| Operability | Zero committed identities | dev and uat workload-identity tfvars both commit identities = {} | Any committed non-empty identity map |
| Portability | Provider and backend posture | Static validation works with backend=false; no backend keys in tfvars | Backend settings in tfvars or mutation-only assumptions |
| Recoverability | No hidden ownership coupling | Data package can only provide collector entries in map, not root/scope/registry ownership | Any ownership leakage to data package |
| Testability | Exact-once fixture assertion | One test method introduces one synthetic map entry and asserts exactly one role, policy, association, and output map entry | Duplicate exact-once tests or fixture constants hard-coded into implementation |

## Task 4 Mutation File List

- tests/eks_platform/test_terraform_contract.py
- platform-prerequisites/terraform/workload-identity/versions.tf
- platform-prerequisites/terraform/workload-identity/variables.tf
- platform-prerequisites/terraform/workload-identity/main.tf
- platform-prerequisites/terraform/workload-identity/outputs.tf
- platform-prerequisites/terraform/environments/dev/workload-identity.tfvars
- platform-prerequisites/terraform/environments/uat/workload-identity.tfvars

## Verification Gate

Run only static checks unless explicitly authorized otherwise:

- terraform -chdir=platform-prerequisites/terraform/workload-identity fmt -check -recursive
- terraform -chdir=platform-prerequisites/terraform/workload-identity init -backend=false
- terraform -chdir=platform-prerequisites/terraform/workload-identity validate
- python3 -m unittest tests.eks_platform.test_terraform_contract.TerraformContractTests.test_workload_identity_root -v

Expected: all pass with identities = {} in committed tfvars.

## Decision Template

- Decision: PASS or FAIL
- Blocking findings:
  - <finding 1>
  - <finding 2>
- Required remediations:
  - <action 1>
  - <action 2>
- Approved mutation scope:
  - <verified list above>

## Dispatch Guardrails

- Keep implementation generic and map-driven; no component-specific identity roots.
- No Kubernetes/Helm/Flux providers in this root.
- No live AWS mutation commands.
- Preserve ownership boundary: data package contributes only identities map entries.
- Reviewer sequence is mandatory: spec compliance review first, then code quality review.
