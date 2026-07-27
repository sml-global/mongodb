# Task 8 Documentation Gate Preflight Rubric

Date: 2026-07-27
Scope: Phase 2 EKS Platform Task 8 only
Plan source: docs/superpowers/plans/2026-07-22-phase2-eks-platform.md

## Objective

Gate Task 8 implementation before code mutation to ensure the component documentation accurately reflects the EKS Platform package's boundaries, read-only guard semantics, foundation artifact ownership, and strict authorization rules, without introducing new public modes or command-line wrappers.

## Required Inputs

- Approved Task 8 section from the EKS platform implementation plan.
- Current worktree state on branch feat/uat-access-foundation.
- Tasks 1-7 complete and committed.

## PASS/FAIL Matrix

| Dimension | Check | PASS Criteria | FAIL Trigger |
|---|---|---|---|
| Safety | Command Authorization | Every shell command block begins exactly with `# AUTHORIZED-ONLY` | Any un-gated command block |
| Safety | Mutation Refusal | Documentation explicitly forbids manual direct execution, ad-hoc wrapper execution, commit commands, and dev mutation examples | Any command demonstrating commit, apply, destroy, or dev-mode mutation |
| Safety | No New Public API | Documentation claims no new public modes, component-specific CLI flags, or executable wrappers | Any documented public mode or component-specific command |
| Contract | Guard Semantics Accuracy | Documentation accurately describes read-only pre-destroy guard behavior: input observations → checks → identity/digest → exactly-once callback → matching exit | Vague or incomplete description of guard mechanics |
| Contract | Artifact Ownership Clarity | Documentation explicitly states foundation ALONE creates, reads, validates, and owns the durable evidence artifact; EKS package code receives callback result only | Any implication that EKS writes, reads, or persists the artifact |
| Contract | Promotion Modes | Documentation accurately distinguishes UAT (`PROMOTION_MODE=uat-build`) from dev (`PROMOTION_MODE=modeled`) and explains guard gate in uat-build only | Missing or incorrect promotion mode description |
| Contract | Workload Identity Shape | Documentation specifies exact `identities` map schema: `namespace`, `service_account`, `policy_json`, `description` | Missing or incorrect schema documentation |
| Contract | Canonical Resource Identity | Documentation explicitly defines exact identity derivations: eks-platform = Cluster ARN; workload-identity = Cluster ARN + `/workload-identity`; platform-controllers = Cluster ARN + `/platform-controllers` | Vague identity derivation or live-lookup implication |
| Contract | Handler Behavior | Documentation states handlers immediately recheck identity and protections before mutation but cannot replace or bypass the pre-destroy guard gate | Misleading claim about handler safety ownership |
| Testability | Documentation Tests | tests/eks_platform/test_documentation.py statically analyzes for `# AUTHORIZED-ONLY` prefix and forbidden patterns (commit, apply, destroy, dev mode) | Missing test suite or weak assertion coverage |
| Testability | No Execution Claims | Documentation makes no claims that UAT is deployed, tested, accepted, or verified beyond static implementation | Any deployment, UAT acceptance, or runtime verification claim |

## Task 8 Mutation File List

- `docs/references/eks-platform-contract.md`
- `tests/eks_platform/test_documentation.py`

## Verification Gate

Run local/static verification only:

```bash
# AUTHORIZED-ONLY
python3 -m unittest tests.eks_platform.test_documentation -v
```

Expected: PASS for all documentation assertions (minimum 5 static contract checks).

## Dispatch Guardrails

- Do not alter `docs/index.md`, `docs/references/*` (other than eks-platform-contract.md), or any foundation-owned reference files.
- Write code only in the two Task 8 mutation files listed above.
- Ensure documentation is clear, precise, and free of marketing language.
- No commands should be executed or reported; all are marked `# AUTHORIZED-ONLY`.

## Review Checklist After Implementation

1. `docs/references/eks-platform-contract.md` is readable by operators as the canonical ownership/boundary document.
2. `tests/eks_platform/test_documentation.py` validates every command block for `# AUTHORIZED-ONLY` prefix and forbidden mutation patterns.
3. No new foundation files are created or modified.
4. No runtime execution is claimed; static implementation only.
5. Guard callback exactly-once semantics are documented.
6. Foundation-only artifact ownership is explicit.
