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

- `EKS_KUBERNETES_VERSION`
- `EKS_AUTHENTICATION_MODE`
- `EKS_ENDPOINT_PUBLIC_ACCESS`
- `EKS_ENDPOINT_PRIVATE_ACCESS`
- `EKS_DELETION_PROTECTION`

### Network and address planning

- `EKS_VPC_CIDR`
- `EKS_CONNECTED_CIDR`
- `EKS_AZ_LAYOUT_MODE`
- `EKS_AZ_COUNT`
- `EKS_PRIVATE_SUBNET_CIDRS`
- `EKS_PUBLIC_SUBNET_CIDRS`
- `EKS_NAT_GATEWAY_COUNT`

### Compute and scaling

- `EKS_NODE_INSTANCE_TYPE`
- `EKS_NODE_MIN_SIZE`
- `EKS_NODE_DESIRED_SIZE`
- `EKS_NODE_MAX_SIZE`
- `EKS_NODE_ROOT_VOLUME_GB`
- `EKS_SPOT_ENABLED`

### Storage and data services

- `EKS_EFS_ENABLED`
- `EKS_EFS_THROUGHPUT_MODE`
- `EKS_EFS_BACKUP_ENABLED`
- `EKS_BACKUP_RETENTION_DAYS`

### Managed add-ons and feature flags

- `EKS_ADDON_DELIVERY_MODE`
- `EKS_ENABLE_VPC_CNI`
- `EKS_ENABLE_COREDNS`
- `EKS_ENABLE_KUBE_PROXY`
- `EKS_ENABLE_EBS_CSI`
- `EKS_ENABLE_EFS_CSI`
- `EKS_ENABLE_POD_IDENTITY_AGENT`
- `EKS_ENABLE_CLUSTER_AUTOSCALER`
- `EKS_ENABLE_METRICS_SERVER`

## Validation Rules

The fragment's validations must be explicit and bounded.

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
- `EKS_AZ_LAYOUT_MODE`: enum; allowed values `single` or `one-per-az`.
- `EKS_AZ_COUNT`: integer; must be at least `1`.
- `EKS_NAT_GATEWAY_COUNT`: integer; must be at least `1` and must not exceed
  `EKS_AZ_COUNT`; `single` requires `1`, while `one-per-az` requires one NAT
  gateway per AZ.
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

- `EKS_PRIVATE_SUBNET_CIDRS`: must be a non-empty list of valid IPv4 CIDRs.
- `EKS_PUBLIC_SUBNET_CIDRS`: must be a non-empty list of valid IPv4 CIDRs.
- The number of private and public subnets must each match `EKS_AZ_COUNT`.
- CIDR blocks must not overlap with each other or with the VPC CIDR.

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