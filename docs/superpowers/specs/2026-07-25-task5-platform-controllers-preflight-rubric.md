# Task 5 Platform Controllers Preflight Rubric

Date: 2026-07-25
Scope: Phase 2 EKS Platform Task 5 only
Plan source: docs/superpowers/plans/2026-07-22-phase2-eks-platform.md

## Objective

Gate Task 5 implementation before code mutation so platform-controller delivery remains GitOps-driven, pinned, and isolated from application/data scopes.

## Required Inputs

- Approved Task 5 section from the EKS platform implementation plan.
- Current Task 3 outputs (platform_contract and IAM identity boundaries).
- Current Task 4 workload-identity contract (generic map-driven ownership only).
- Current worktree state on branch feat/uat-access-foundation.

## PASS/FAIL Matrix

| Dimension | Check | PASS Criteria | FAIL Trigger |
|---|---|---|---|
| Safety | Foundation boundary | No edits to foundation-owned parser/orchestrator/registry/public scripts | Any edit outside Task 5 scope |
| Safety | Scope isolation | Mutations limited to Task 5 file list only | Any Task 6+ or unrelated package file change |
| Contract | Ownership split | Platform controllers scope owned only by EKS package; data/app packages provide no controller scope/release/registry mapping | Any ownership leakage outside EKS package |
| Contract | Pinned release sources | Flux sources/releases are pinned to explicit versions/revisions with bounded remediation/timeouts | Any unpinned latest/tag-only source or floating version |
| Contract | UAT cluster identity integration | UAT overlay binds to approved cluster identity and environment labels from platform contract inputs | Missing or ambiguous UAT identity binding |
| Operability | Controller set boundary | cert-manager, kyverno, cluster-autoscaler present; metrics-server and aws-load-balancer-controller are conditional according to plan | Extra controllers, missing required controllers, or unconditional optional controllers |
| Operability | Metrics-server singular ownership | Exactly one ownership path for metrics-server (managed add-on or helm fallback) | Dual ownership or no ownership path |
| Operability | App-scope isolation | No application-scope resources (MongoDB, Percona workloads, app Deployments/Services) in controller manifests | Any app/data workload object introduced |
| Portability | Private static dev posture | Dev overlay renders private/static; no public render mode, component flag, or executable is introduced | New public render mode/CLI surface |
| Portability | Provider boundary | No Terraform provider additions in this task; this is GitOps manifest-only scope plus tests | Any Terraform root/provider mutations in Task 5 |
| Testability | Render and ownership tests | test_controller_render.py verifies pinned versions, environment labels, autoscaler SA identity wiring, conditional LBC absence/presence, and managed-addon exclusion | Missing contract assertions or weak/non-deterministic checks |

## Task 5 Mutation File List

- tests/eks_platform/test_controller_render.py
- gitops/platform-controllers/base/kustomization.yaml
- gitops/platform-controllers/base/namespaces.yaml
- gitops/platform-controllers/base/sources.yaml
- gitops/platform-controllers/base/releases.yaml
- gitops/platform-controllers/overlays/dev/kustomization.yaml
- gitops/platform-controllers/overlays/dev/platform-settings.yaml
- gitops/platform-controllers/overlays/uat/kustomization.yaml
- gitops/platform-controllers/overlays/uat/platform-settings.yaml

## Verification Gate

Run local/static validation only:

- python3 -m unittest tests.eks_platform.test_controller_render -v

Expected:
- PASS with deterministic local render/test checks.
- No live cluster mutations.

## Decision Template

- Decision: PASS or FAIL
- Blocking findings:
  - <finding 1>
  - <finding 2>
- Required remediations:
  - <action 1>
  - <action 2>
- Approved mutation scope:
  - <file list above>

## Dispatch Guardrails

- No edits to foundation-owned files.
- No direct workload/application resources in platform-controllers manifests.
- Keep optional controllers truly conditional and test both branches.
- Ensure no overlap with managed add-ons already owned in Task 3.
- Mandatory review order after implementation: spec-compliance review first, code-quality review second.
