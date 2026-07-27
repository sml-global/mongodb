# Task 6 Canonical Handlers Preflight Rubric

Date: 2026-07-25
Scope: Phase 2 EKS Platform Task 6 only
Plan source: docs/superpowers/plans/2026-07-22-phase2-eks-platform.md

## Objective

Gate Task 6 implementation before code mutation so canonical handler wrappers remain mode-safe, foundation-compatible, and strictly confined to the approved two-file handler boundary plus tests.

## Required Inputs

- Approved Task 6 section from the EKS platform implementation plan.
- Current foundation registry and orchestration tests for baseline snapshots.
- Current worktree state on branch feat/uat-access-foundation.

## PASS/FAIL Matrix

| Dimension | Check | PASS Criteria | FAIL Trigger |
|---|---|---|---|
| Safety | Foundation boundary | No edits to foundation-owned parser/orchestrator/registry/public scripts listed in the plan contract | Any mutation to prohibited foundation files |
| Safety | Task 6 scope isolation | Changes are limited to Task 6 file list only | Any Task 7+ or unrelated file mutation |
| Contract | Fragment source boundary | scripts/lib/scope-handlers.d/20-eks-platform.sh sources only scripts/lib/packages/20-eks-platform/internal/lifecycle-handlers.sh after foundation validation | Any alternate source path, path escape, substitution, or source of verifier/guard internals |
| Contract | Canonical wrapper ownership | Handler fragment alone defines exact pre-mapped canonical wrapper symbols for eks-platform, workload-identity, and platform-controllers | Wrapper symbols missing, renamed, or defined in internal file |
| Contract | Internal symbol discipline | lifecycle-handlers.sh exports only distinct eks_internal_* handler/lifecycle helpers | Any canonical wrapper symbol, verifier symbol, or pre-destroy-guard symbol in internal file |
| Correctness | No recursion or symbol leakage | Each canonical wrapper delegates to mapped internal helper without recursion or naming collisions | Circular wrapper calls, self-call recursion, or helper/canonical symbol collision |
| Correctness | Immutable registry/graph | Registry mappings, catalog, dependencies, order, state keys, and public entrypoints remain unchanged after fragment load | Any mutation API call, array write, mapping change, or graph/order drift |
| Mode safety | Promotion gate integrity | PROMOTION_MODE=modeled is rejected before any EKS handler mutation path executes | Any modeled-mode path reaching backend/AWS/init/lock/mutation |
| Mode safety | UAT guard continuity | PROMOTION_MODE=uat-build still requires foundation account/region/backend/context/saved-plan/approval guards | Any bypass or reinterpretation of foundation checks |
| Destroy safety | Last-moment drift recheck | Destroy wrappers re-read and match live account, region, environment, cluster identity, deletion protection, EFS protection, backup retention, and vault-lock state immediately before first mutation | Missing recheck, stale-state-only check, or mutation before recheck |
| Destroy safety | Protection drift abort | Any drift between validated contract/state identity and live control-plane protection flags causes immediate refusal | Destroy continues after drift or unknown observation |
| Portability | Bash compatibility | Wrapper and internal implementation remain Bash 3.2 compatible and rely on foundation APIs for paths/state/guards | Bash 4+ features, ad-hoc path parsing, lock/path orchestration logic in package code |
| Testability | Contract-focused tests | tests/eks_platform/test_handlers.py plus registry test updates assert source-path validation, wrapper mapping, mode gates, no-mutation registry invariants, and destroy recheck order | Missing assertions, weak/non-deterministic checks, or no regression on leakage/recursion |

## Task 6 Mutation File List

- scripts/lib/scope-handlers.d/20-eks-platform.sh
- scripts/lib/packages/20-eks-platform/internal/lifecycle-handlers.sh
- tests/eks_platform/test_handlers.py
- tests/environment_orchestration/test_scope_registry.py

## Verification Gate

Run only static/local verification unless separately authorized otherwise:

- bash -n scripts/lib/packages/20-eks-platform/internal/lifecycle-handlers.sh scripts/lib/scope-handlers.d/20-eks-platform.sh
- python3 -m unittest tests.eks_platform.test_handlers tests.environment_orchestration.test_scope_registry -v

Expected:
- PASS with unchanged foundation graph/mappings and exact canonical wrapper resolution.
- PASS with explicit modeled-mode refusal before mutation path entry.
- PASS with destroy wrapper recheck assertions proving drift-triggered refusal.

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

- No edits to foundation-owned files listed in the plan contract.
- Do not add scopes, aliases, dependencies, state-key mappings, public entrypoints, or promotion semantics.
- Keep canonical wrappers in fragment only; keep implementation helpers in lifecycle-handlers.sh only.
- Use only foundation APIs for state lookup, backend validation, paths, cleanup, saved-plan, guard checks, and approval flow.
- Preserve deletion-protection, EFS prevent_destroy, backup retention, and vault-lock constraints in destroy paths.
- Mandatory review order after implementation: spec-compliance review first, code-quality review second.