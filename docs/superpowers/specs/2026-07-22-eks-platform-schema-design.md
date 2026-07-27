# EKS Platform Schema Design

**Date:** 2026-07-22

**Status:** Draft for review

## Purpose

Define the static environment-schema fragment for the EKS platform package.
This task is intentionally narrow: it declares only the EKS-owned environment
keys that the foundation parser must recognize, and it proves that the composed
schema remains collision-free when `base.manifest` is combined with
`20-eks-platform.manifest`.

This spec does not introduce runtime checks, Terraform logic, access-entry
logic, identity checks, backend checks, or provisioning behavior. Those belong
to later implementation tasks.

The fragment is additive and non-breaking: it may declare new EKS keys as
optional so the current `dev.env` and `uat.env` files continue to load while
later tasks introduce the corresponding values.

## Scope Boundary

### In scope

- A single fragment file at `config/environment-schema/fragments/20-eks-platform.manifest`.
- A contract test at `tests/eks_platform/test_environment_contract.py`.
- Static validation of the fragment's key set, types, bounds, and enum values.
- Static validation that the composed key space has no duplicate keys.

### Out of scope

- Any IAM policy, role, or permission-set logic.
- Any EKS access-entry or `aws-auth` behavior.
- Any backend bootstrap or Terraform remote-state checks.
- Any `umask`, temporary file, or generated tfvars behavior.
- Any cluster-authentication-mode verification.
- Any VPC, NAT, subnet, node-group, EFS, or add-on provisioning logic beyond
  the schema keys themselves.

## Design Principles

1. The fragment is structural, not operational. It describes what the parser
   accepts, not what provisioning should do.
2. The fragment must fail closed. Unknown keys, duplicate keys, or invalid enum
   values must be rejected by the contract test.
3. The fragment must be composable. Its key names must not collide with
   `base.manifest` or any other registered fragment.
4. The fragment must not encode mutation defaults. Every value is either a
   required field or a bounded validation choice.

## Planned Key Set

The fragment is expected to declare the following EKS-owned environment keys.
These are the only keys this task may introduce.

### Platform identity and topology

- `EKS_KUBERNETES_VERSION` (optional)
- `EKS_AUTHENTICATION_MODE` (optional)
- `EKS_ENDPOINT_PUBLIC_ACCESS` (optional)
- `EKS_ENDPOINT_PRIVATE_ACCESS` (optional)
- `EKS_DELETION_PROTECTION` (optional)

### Network and address planning

- `EKS_VPC_CIDR` (optional)
- `EKS_CONNECTED_CIDR` (optional)
- `EKS_AZ_LAYOUT_MODE` (optional)
- `EKS_AZ_COUNT` (optional)
- `EKS_PRIVATE_SUBNET_A_CIDR` (optional)
- `EKS_PRIVATE_SUBNET_B_CIDR` (optional)
- `EKS_PRIVATE_SUBNET_C_CIDR` (optional)
- `EKS_PUBLIC_SUBNET_A_CIDR` (optional)
- `EKS_PUBLIC_SUBNET_B_CIDR` (optional)
- `EKS_PUBLIC_SUBNET_C_CIDR` (optional)
- `EKS_NAT_GATEWAY_COUNT` (optional)

### Compute and scaling

- `EKS_NODE_INSTANCE_TYPE` (optional)
- `EKS_NODE_MIN_SIZE` (optional)
- `EKS_NODE_DESIRED_SIZE` (optional)
- `EKS_NODE_MAX_SIZE` (optional)
- `EKS_NODE_ROOT_VOLUME_GB` (optional)
- `EKS_SPOT_ENABLED` (optional)

### Storage and data services

- `EKS_EFS_ENABLED` (optional)
- `EKS_EFS_THROUGHPUT_MODE` (optional)
- `EKS_EFS_BACKUP_ENABLED` (optional)
- `EKS_BACKUP_RETENTION_DAYS` (optional)

### Managed add-ons and feature flags

- `EKS_ADDON_DELIVERY_MODE` (optional)
- `EKS_ENABLE_VPC_CNI` (optional)
- `EKS_ENABLE_COREDNS` (optional)
- `EKS_ENABLE_KUBE_PROXY` (optional)
- `EKS_ENABLE_EBS_CSI` (optional)
- `EKS_ENABLE_EFS_CSI` (optional)
- `EKS_ENABLE_POD_IDENTITY_AGENT` (optional)
- `EKS_ENABLE_CLUSTER_AUTOSCALER` (optional)
- `EKS_ENABLE_METRICS_SERVER` (optional)

## Validation Rules

The fragment's validations must be explicit and bounded. Optional keys are
still validated when values are later supplied in an environment file.

### Scalar fields

- `EKS_KUBERNETES_VERSION`: enum; allowed values must be the currently supported
  EKS version(s) approved by the phase plan and no others.
- `EKS_AUTHENTICATION_MODE`: enum; allowed values `API` or `API_AND_CONFIG_MAP`.
- `EKS_ENDPOINT_PUBLIC_ACCESS`: boolean.
- `EKS_ENDPOINT_PRIVATE_ACCESS`: boolean.
- `EKS_DELETION_PROTECTION`: boolean.
- `EKS_VPC_CIDR`: CIDR string; must be valid IPv4 CIDR notation.
- `EKS_CONNECTED_CIDR`: CIDR string; must be valid IPv4 CIDR notation and must
  remain contained within the VPC CIDR without overlapping any subnet block.
- `EKS_AZ_LAYOUT_MODE`: fixed value `one-per-az`.
- `EKS_AZ_COUNT`: fixed value `3`.
- `EKS_NAT_GATEWAY_COUNT`: fixed value `3`.
- `EKS_NODE_INSTANCE_TYPE`: enum or validated string; must be one of the
  approved node instance families for the phase plan.
- `EKS_NODE_MIN_SIZE`: integer; `>= 1`.
- `EKS_NODE_DESIRED_SIZE`: integer; `>= EKS_NODE_MIN_SIZE`.
- `EKS_NODE_MAX_SIZE`: integer; `>= EKS_NODE_DESIRED_SIZE`.
- `EKS_NODE_ROOT_VOLUME_GB`: integer; `>= 20`.
- `EKS_SPOT_ENABLED`: boolean.
- `EKS_EFS_ENABLED`: boolean.
- `EKS_EFS_THROUGHPUT_MODE`: enum; allowed values must be the supported EFS
  throughput modes selected by the phase plan.
- `EKS_EFS_BACKUP_ENABLED`: boolean.
- `EKS_BACKUP_RETENTION_DAYS`: integer; must meet the phase plan's minimum
  retention policy.

### Array-like or repeated fields

- `EKS_PRIVATE_SUBNET_A_CIDR`, `EKS_PRIVATE_SUBNET_B_CIDR`,
  `EKS_PRIVATE_SUBNET_C_CIDR`, `EKS_PUBLIC_SUBNET_A_CIDR`,
  `EKS_PUBLIC_SUBNET_B_CIDR`, and `EKS_PUBLIC_SUBNET_C_CIDR` are valid IPv4
  CIDRs.
- All six subnet CIDRs must be pairwise non-overlapping.
- Each subnet CIDR must remain contained within `EKS_VPC_CIDR`.

### Managed add-on flags

- `EKS_ENABLE_VPC_CNI`, `EKS_ENABLE_COREDNS`, `EKS_ENABLE_KUBE_PROXY`,
  `EKS_ENABLE_EBS_CSI`, `EKS_ENABLE_EFS_CSI`, `EKS_ENABLE_POD_IDENTITY_AGENT`,
  `EKS_ENABLE_CLUSTER_AUTOSCALER`, and `EKS_ENABLE_METRICS_SERVER` are boolean.
- `EKS_ADDON_DELIVERY_MODE`: enum; allowed values `managed-addon` or
  `helm-fallback`.
- The fragment must not encode add-on versions, charts, or install mechanics.

## Explicit Exclusions

The fragment must not contain or imply any of the following:

- IAM roles, IAM policies, IAM users, or permission-set ARNs.
- EKS access entries, cluster RBAC bindings, or `aws-auth` entries.
- Workload identity, Pod Identity role ARNs, or service-account annotations.
- Terraform backend keys, S3 bucket names, or state-lock settings.
- Runtime mutation defaults, generate-on-apply behavior, or local file writes.
- Dev-only toggles, fallback paths, or cross-work-package settings.
- Any key that would blur the boundary between static schema and provisioning.

## Collision and Composition Rules

The contract test must verify the composed manifest surface, not just the
fragment in isolation.

1. Load the foundation schema plus `20-eks-platform.manifest` using the same
   composition order the parser uses in production.
2. Assert that every key is unique across the composed set.
3. Assert that no EKS fragment key duplicates any key already defined by the
   base schema.
4. Assert that the fragment contains only keys from the approved EKS key set.
5. Fail closed on any unknown, duplicated, or missing required key.

## Acceptance Criteria

This design is complete when the implementation can prove the following:

- The fragment exists at `config/environment-schema/fragments/20-eks-platform.manifest`.
- The fragment contains only the approved EKS schema keys.
- The parser accepts the composed schema without duplicate-key collisions.
- The contract test fails if any foreign key, duplicate key, or invalid enum is
  introduced.
- The design remains static and does not reach into runtime or provisioning
  concerns.

## Review Notes

This spec intentionally keeps Task 2 narrow. The following concerns are real,
but they belong in later task specs rather than here:

- EKS authentication-mode runtime checks.
- `umask 077` for generated files.
- Backend initialization and remote-state health checks.

Those controls should be written into the task that actually implements the
relevant runtime behavior.