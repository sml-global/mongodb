# Imported-Code Review Matrix

This document is the repository's only canonical imported-code review matrix.
Source repositories are read-only. Every candidate considered for import has
one stable row, including rejected candidates. Later work packages append rows
or advance `Status`; they do not create domain-specific matrices or change the
seven-column schema.

The `mongodb@29353d6:` prefix identifies the immutable completed Phase 1
access-foundation implementation in this repository. Fragment suffixes identify
individual configuration values, resources, or generated-file behaviors.

| ID | Domain | Source | Target | Disposition | Evidence | Status |
| --- | --- | --- | --- | --- | --- | --- |
| FOUNDATION-0001 | FOUNDATION | mongodb@29353d6:config/environments/uat.env#ENVIRONMENT | config/environments/uat.env#ENVIRONMENT | KEEP | docs/superpowers/plans/2026-07-21-uat-access-foundation.md | REVIEWED |
| FOUNDATION-0002 | FOUNDATION | mongodb@29353d6:config/environments/uat.env#EXPECTED_AWS_ACCOUNT_ID | config/environments/uat.env#EXPECTED_AWS_ACCOUNT_ID | KEEP | docs/superpowers/plans/2026-07-21-uat-access-foundation.md | REVIEWED |
| FOUNDATION-0003 | FOUNDATION | mongodb@29353d6:config/environments/uat.env#AWS_REGION | config/environments/uat.env#AWS_REGION | KEEP | docs/superpowers/plans/2026-07-21-uat-access-foundation.md | REVIEWED |
| FOUNDATION-0004 | FOUNDATION | mongodb@29353d6:config/environments/uat.env#EKS_CLUSTER_NAME | config/environments/uat.env#EKS_CLUSTER_NAME | KEEP | docs/superpowers/plans/2026-07-21-uat-access-foundation.md | REVIEWED |
| FOUNDATION-0005 | FOUNDATION | mongodb@29353d6:config/environments/uat.env#BOOMI_NAMESPACE | config/environments/uat.env#BOOMI_NAMESPACE | KEEP | docs/superpowers/plans/2026-07-21-uat-access-foundation.md | REVIEWED |
| FOUNDATION-0006 | FOUNDATION | mongodb@29353d6:config/environments/uat.env#TF_STATE_BUCKET | config/environments/uat.env#TF_STATE_BUCKET | KEEP | docs/superpowers/plans/2026-07-21-uat-access-foundation.md | REVIEWED |
| FOUNDATION-0007 | FOUNDATION | mongodb@29353d6:config/environments/uat.env#TF_STATE_REGION | config/environments/uat.env#TF_STATE_REGION | KEEP | docs/superpowers/plans/2026-07-21-uat-access-foundation.md | REVIEWED |
| FOUNDATION-0008 | FOUNDATION | mongodb@29353d6:config/environments/uat.env#ACCESS_GOVERNANCE_STATE_KEY | config/environments/uat.env#ACCESS_GOVERNANCE_STATE_KEY | KEEP | docs/superpowers/plans/2026-07-21-uat-access-foundation.md | REVIEWED |
| FOUNDATION-0009 | FOUNDATION | mongodb@29353d6:config/environments/uat.env#EKS_ACCESS_STATE_KEY | config/environments/uat.env#EKS_ACCESS_STATE_KEY | KEEP | docs/superpowers/plans/2026-07-21-uat-access-foundation.md | REVIEWED |
| FOUNDATION-0010 | FOUNDATION | mongodb@29353d6:scripts/lib/platform-env.sh | scripts/lib/platform-env.sh | REWRITE | docs/superpowers/plans/2026-07-21-uat-access-foundation.md | REVIEWED |
| FOUNDATION-0011 | FOUNDATION | mongodb@29353d6:scripts/bootstrap-terraform-s3-backend.sh | scripts/lib/packages/10-foundation-access/internal/access-scopes.sh#backend-bootstrap | REWRITE | docs/superpowers/plans/2026-07-21-uat-access-foundation.md | REVIEWED |
| FOUNDATION-0012 | FOUNDATION | mongodb@29353d6:scripts/validate-uat-workforce-principals.sh | scripts/lib/packages/10-foundation-access/internal/access-scopes.sh#principal-validation | REWRITE | docs/superpowers/plans/2026-07-21-uat-access-foundation.md | REVIEWED |
| FOUNDATION-0013 | FOUNDATION | mongodb@29353d6:scripts/validate-uat-workforce-principals.sh#generated-auto-tfvars | scripts/lib/packages/10-foundation-access/internal/access-scopes.sh#generated-auto-tfvars | REWRITE | docs/superpowers/plans/2026-07-21-uat-access-foundation.md | REVIEWED |
| FOUNDATION-0014 | FOUNDATION | mongodb@29353d6:scripts/provision-uat-access.sh | scripts/provision.sh#foundation-access-scopes | REWRITE | docs/superpowers/plans/2026-07-21-uat-access-foundation.md | REVIEWED |
| FOUNDATION-0015 | FOUNDATION | mongodb@29353d6:.gitignore#uat-local-inputs | .gitignore#environment-local-inputs | REWRITE | docs/superpowers/plans/2026-07-21-uat-access-foundation.md | REVIEWED |
| FOUNDATION-0016 | FOUNDATION | mongodb@29353d6:platform-prerequisites/terraform/access-governance/.terraform.lock.hcl | platform-prerequisites/terraform/access-governance/.terraform.lock.hcl | REPLACE | docs/superpowers/plans/2026-07-21-uat-access-foundation.md | REVIEWED |
| FOUNDATION-0017 | FOUNDATION | mongodb@29353d6:platform-prerequisites/terraform/access-governance/versions.tf | platform-prerequisites/terraform/access-governance/versions.tf | REWRITE | docs/superpowers/plans/2026-07-21-uat-access-foundation.md | REVIEWED |
| FOUNDATION-0018 | FOUNDATION | mongodb@29353d6:platform-prerequisites/terraform/access-governance/variables.tf | platform-prerequisites/terraform/access-governance/variables.tf | REWRITE | docs/superpowers/plans/2026-07-21-uat-access-foundation.md | REVIEWED |
| FOUNDATION-0019 | FOUNDATION | mongodb@29353d6:platform-prerequisites/terraform/access-governance/main.tf | platform-prerequisites/terraform/access-governance/main.tf | REWRITE | docs/superpowers/plans/2026-07-21-uat-access-foundation.md | REVIEWED |
| FOUNDATION-0020 | FOUNDATION | mongodb@29353d6:platform-prerequisites/terraform/access-governance/outputs.tf | platform-prerequisites/terraform/access-governance/outputs.tf | REWRITE | docs/superpowers/plans/2026-07-21-uat-access-foundation.md | REVIEWED |
| FOUNDATION-0021 | FOUNDATION | mongodb@29353d6:platform-prerequisites/terraform/access-governance/uat.tfvars | platform-prerequisites/terraform/access-governance/uat.tfvars | REWRITE | docs/superpowers/plans/2026-07-21-uat-access-foundation.md | REVIEWED |
| FOUNDATION-0022 | FOUNDATION | mongodb@29353d6:platform-prerequisites/terraform/access-governance/main.tf#aws_accessanalyzer_analyzer.uat_account | platform-prerequisites/terraform/access-governance/main.tf#aws_accessanalyzer_analyzer.uat_account | REWRITE | docs/superpowers/plans/2026-07-21-uat-access-foundation.md | REVIEWED |
| FOUNDATION-0023 | FOUNDATION | mongodb@29353d6:platform-prerequisites/terraform/eks-access/.terraform.lock.hcl | platform-prerequisites/terraform/eks-access/.terraform.lock.hcl | REPLACE | docs/superpowers/plans/2026-07-21-uat-access-foundation.md | REVIEWED |
| FOUNDATION-0024 | FOUNDATION | mongodb@29353d6:platform-prerequisites/terraform/eks-access/versions.tf | platform-prerequisites/terraform/eks-access/versions.tf | REWRITE | docs/superpowers/plans/2026-07-21-uat-access-foundation.md | REVIEWED |
| FOUNDATION-0025 | FOUNDATION | mongodb@29353d6:platform-prerequisites/terraform/eks-access/variables.tf | platform-prerequisites/terraform/eks-access/variables.tf | REWRITE | docs/superpowers/plans/2026-07-21-uat-access-foundation.md | REVIEWED |
| FOUNDATION-0026 | FOUNDATION | mongodb@29353d6:platform-prerequisites/terraform/eks-access/main.tf | platform-prerequisites/terraform/eks-access/main.tf | REWRITE | docs/superpowers/plans/2026-07-21-uat-access-foundation.md | REVIEWED |
| FOUNDATION-0027 | FOUNDATION | mongodb@29353d6:platform-prerequisites/terraform/eks-access/outputs.tf | platform-prerequisites/terraform/eks-access/outputs.tf | REWRITE | docs/superpowers/plans/2026-07-21-uat-access-foundation.md | REVIEWED |
| FOUNDATION-0028 | FOUNDATION | mongodb@29353d6:platform-prerequisites/terraform/eks-access/uat.tfvars | platform-prerequisites/terraform/eks-access/uat.tfvars | REWRITE | docs/superpowers/plans/2026-07-21-uat-access-foundation.md | REVIEWED |
| FOUNDATION-0029 | FOUNDATION | mongodb@29353d6:platform-prerequisites/terraform/eks-access/main.tf#local.principals | platform-prerequisites/terraform/eks-access/main.tf#local.principals | REWRITE | docs/superpowers/plans/2026-07-21-uat-access-foundation.md | REVIEWED |
| FOUNDATION-0030 | FOUNDATION | mongodb@29353d6:platform-prerequisites/terraform/eks-access/main.tf#aws_eks_access_entry.workforce | platform-prerequisites/terraform/eks-access/main.tf#aws_eks_access_entry.workforce | REWRITE | docs/superpowers/plans/2026-07-21-uat-access-foundation.md | REVIEWED |
| FOUNDATION-0031 | FOUNDATION | mongodb@29353d6:platform-prerequisites/terraform/eks-access/main.tf#aws_eks_access_policy_association.cluster_admin | platform-prerequisites/terraform/eks-access/main.tf#aws_eks_access_policy_association.cluster_admin | REWRITE | docs/superpowers/plans/2026-07-21-uat-access-foundation.md | REVIEWED |
| FOUNDATION-0032 | FOUNDATION | mongodb@29353d6:platform-prerequisites/terraform/eks-access/main.tf#aws_eks_access_policy_association.boomi_admin | platform-prerequisites/terraform/eks-access/main.tf#aws_eks_access_policy_association.boomi_admin | REWRITE | docs/superpowers/plans/2026-07-21-uat-access-foundation.md | REVIEWED |