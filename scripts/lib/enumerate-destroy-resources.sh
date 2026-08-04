#!/usr/bin/env bash
#
# Resource enumeration for destroy confirmation preview.
#
# This library provides a dry-run preview of resources that will be deleted
# during a destroy operation, improving the infra admin's ability to review
# what's about to be removed before confirming.
#
# Source path: source "$ROOT_DIR/scripts/lib/enumerate-destroy-resources.sh"
#
# Exported functions:
#   enumerate_destroy_resources_for_scope <scope> <environment>
#
# Returns 0 if enumeration succeeded and printed resources; 1 if enumeration
# is not supported for this scope or failed (caller should handle gracefully).

enumerate_destroy_resources_for_scope() {
  local scope="$1"
  local environment="$2"

  case "$scope" in
    platform-controllers)
      _enumerate_platform_controllers_resources "$environment"
      ;;
    workload-identity)
      _enumerate_workload_identity_resources "$environment"
      ;;
    mongodb)
      _enumerate_mongodb_resources "$environment"
      ;;
    eks-platform)
      _enumerate_eks_platform_resources "$environment"
      ;;
    *)
      # Scope doesn't have enumeration support yet
      return 1
      ;;
  esac
}

_enumerate_platform_controllers_resources() {
  local environment="$1"
  local overlay_dir

  # Determine overlay directory based on environment
  case "$environment" in
    uat)
      overlay_dir="gitops/platform-controllers/overlays/uat"
      ;;
    dev)
      overlay_dir="gitops/platform-controllers/overlays/dev"
      ;;
    *)
      return 1
      ;;
  esac

  [[ -d "$overlay_dir" ]] || return 1

  _enumerate_kustomize_resources "$overlay_dir"
}

_enumerate_mongodb_resources() {
  local environment="$1"
  local overlay_dir

  case "$environment" in
    uat)
      overlay_dir="k8s/overlays/uat"
      ;;
    dev)
      overlay_dir="k8s/overlays/dev"
      ;;
    *)
      return 1
      ;;
  esac

  [[ -d "$overlay_dir" ]] || {
    # Might be gitops path
    overlay_dir="gitops/mongodb/overlays/$environment"
    [[ -d "$overlay_dir" ]] || return 1
  }

  _enumerate_kustomize_resources "$overlay_dir"
}

_enumerate_workload_identity_resources() {
  local environment="$1"

  printf "Terraform-managed resources:\n"
  printf "  - EKS Pod Identity Associations (count varies based on configuration)\n"
  printf "  - IAM Roles for workload identities\n"
  printf "\n"
  printf "Note: This scope provisions identity mappings. Run 'terraform plan -destroy'\n"
  printf "      in platform-prerequisites/terraform/workload-identity for exact list.\n"
  return 0
}

_enumerate_eks_platform_resources() {
  local environment="$1"

  printf "Terraform-managed resources:\n"
  printf "  - EKS Cluster (oms-${environment}-eks-cluster)\n"
  printf "  - VPC and subnets\n"
  printf "  - NAT Gateway and Internet Gateway\n"
  printf "  - EKS Node Group\n"
  printf "  - IAM Roles (cluster, node, addon, autoscaler, LBC)\n"
  printf "  - EFS File System\n"
  printf "  - AWS Backup Vault (with vault lock)\n"
  printf "  - KMS Keys (cluster encryption, backup encryption)\n"
  printf "  - EKS Managed Addons (VPC-CNI, CoreDNS, kube-proxy, EBS CSI, EFS CSI, Pod Identity Agent)\n"
  printf "\n"
  printf "⚠️  WARNING: This is a large-scale destruction that removes the entire cluster!\n"
  printf "⚠️  All workloads, data, and configurations will be permanently deleted.\n"
  return 0
}

_enumerate_kustomize_resources() {
  local overlay_dir="$1"

  # Try to enumerate resources using kubectl dry-run
  local resources
  resources=$(kubectl get -k "$overlay_dir" \
    -o custom-columns=KIND:.kind,NAME:.metadata.name,NAMESPACE:.metadata.namespace \
    --no-headers 2>/dev/null) || {
    printf "  (Unable to enumerate Kubernetes resources - kubectl may not be configured)\n"
    printf "  Resources defined in: %s\n" "$overlay_dir"
    return 1
  }

  # Group resources by kind
  echo "$resources" | awk '
    BEGIN {
      delete kinds;
      kindCount = 0;
    }
    {
      kind = $1;
      name = $2;
      ns = $3;

      if (!(kind in kinds)) {
        kinds[kind] = "";
        kindsOrder[++kindCount] = kind;
        kindCounts[kind] = 0;
      }

      kindCounts[kind]++;

      if (ns != "" && ns != "<none>") {
        kinds[kind] = kinds[kind] "\n  - " ns "/" name;
      } else {
        kinds[kind] = kinds[kind] "\n  - " name;
      }
    }
    END {
      for (i = 1; i <= kindCount; i++) {
        key = kindsOrder[i];
        count = kindCounts[key];

        # Pluralize kind names
        plural = key;
        if (key !~ /s$/) {
          plural = key "s";
        }

        printf "%s (%d):%s\n\n", plural, count, kinds[key];
      }
    }
  '

  return 0
}

# Helper to format destruction summary header
format_destroy_preview_header() {
  local scope="$1"
  local environment="$2"

  printf '\n'
  printf '═══════════════════════════════════════════════════════════════════════════\n'
  printf 'DESTROY PREVIEW: %s (environment: %s)\n' "$scope" "$environment"
  printf '═══════════════════════════════════════════════════════════════════════════\n'
  printf '\nThe following resources will be destroyed:\n\n'
}

format_destroy_preview_footer() {
  printf '═══════════════════════════════════════════════════════════════════════════\n'
  printf '\n'
}
