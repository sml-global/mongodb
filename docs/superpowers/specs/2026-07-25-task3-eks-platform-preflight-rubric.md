# Task 3 EKS Platform Terraform Preflight Rubric

Date: 2026-07-25
Scope: Phase 2 EKS Platform Task 3 only
Plan source: docs/superpowers/plans/2026-07-22-phase2-eks-platform.md

## Objective

Gate Task 3 implementation readiness before code mutation. Ensure the implementer can deliver the Terraform module/root contract without violating foundation boundaries.

## Required Inputs

- Approved plan section for Task 3.
- Current repository state in worktree feat/uat-access-foundation.
- Foundation boundaries from AGENTS.md and the Task 3 contract in the plan.

## PASS/FAIL Matrix

| Dimension | Check | PASS Criteria | FAIL Trigger |
|---|---|---|---|
| Safety | Foundation boundaries | No edits proposed to foundation-owned parser/orchestrator/registry files | Any proposed edit to foundation-owned files |
| Safety | Scope isolation | Only Task 3 files are in mutation scope | Any Task 4+ file or unrelated scope in change list |
| Operability | Terraform root/module shape | Candidate file list matches Task 3 file structure exactly | Missing required root/module files |
| Operability | Identity split | Tests and implementation separate cluster/node/add-on/autoscaler identities and remove node overprivilege | Node role still holds controller/admin/workload privilege |
| Operability | Auth and endpoint posture | Contract enforces API auth mode, private endpoint, deletion protection, and private nodes | Public endpoint dependence or missing deletion protection gate |
| Recoverability | EFS and backup controls | Test contract includes encrypted EFS, NFS restrictions, backup selection, retention, and vault-lock evidence metadata | Missing EFS protection or backup retention assertions |
| Portability | Mode and tfvars posture | Dev tfvars remain static model inputs; no backend keys in tfvars | Backend settings inside tfvars or modeled mode mutation path |
| Portability | Provider/use boundaries | No Kubernetes/Helm/Flux providers or workload resources in Task 3 Terraform roots | Any non-Task-3 provider/workload resource appears |
| Contract | Output object | Single non-secret platform_contract object is defined with required identity/network/cluster/EFS/backup/add-on/Pod Identity fields | Missing platform_contract or secret-bearing outputs |
| Testability | Verification command set | Task 3 command block is runnable as static validation without AWS mutation | Commands require live mutation or unspecified prerequisites |

## Preflight Decision Template

- Decision: PASS or FAIL
- Blocking findings:
  - <finding 1>
  - <finding 2>
- Required remediations before implementation:
  - <action 1>
  - <action 2>
- Approved mutation file list:
  - tests/eks_platform/test_terraform_contract.py
  - platform-prerequisites/terraform/modules/network/variables.tf
  - platform-prerequisites/terraform/modules/network/main.tf
  - platform-prerequisites/terraform/modules/network/outputs.tf
  - platform-prerequisites/terraform/modules/iam/variables.tf
  - platform-prerequisites/terraform/modules/iam/main.tf
  - platform-prerequisites/terraform/modules/iam/outputs.tf
  - platform-prerequisites/terraform/modules/eks/variables.tf
  - platform-prerequisites/terraform/modules/eks/main.tf
  - platform-prerequisites/terraform/modules/eks/outputs.tf
  - platform-prerequisites/terraform/modules/efs/variables.tf
  - platform-prerequisites/terraform/modules/efs/main.tf
  - platform-prerequisites/terraform/modules/efs/outputs.tf
  - platform-prerequisites/terraform/modules/backup/variables.tf
  - platform-prerequisites/terraform/modules/backup/main.tf
  - platform-prerequisites/terraform/modules/backup/outputs.tf
  - platform-prerequisites/terraform/eks-platform/versions.tf
  - platform-prerequisites/terraform/eks-platform/variables.tf
  - platform-prerequisites/terraform/eks-platform/main.tf
  - platform-prerequisites/terraform/eks-platform/checks.tf
  - platform-prerequisites/terraform/eks-platform/outputs.tf
  - platform-prerequisites/terraform/environments/dev/eks-platform.tfvars
  - platform-prerequisites/terraform/environments/uat/eks-platform.tfvars

## Dispatch Guardrails

- Implementer must not edit parser, registry, orchestration, or public entrypoint files.
- Implementer must keep Terraform changes static-validation-friendly and avoid live AWS mutation commands unless explicitly authorized.
- Reviewer sequence is mandatory: spec compliance review first, then code quality review.
