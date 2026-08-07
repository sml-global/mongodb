#!/usr/bin/env bash
# scripts/hooks/validate-naming-convention.sh
#
# Pre-commit hook to validate namespace naming convention.
#
# Convention (approved in docs/UAT-ARCHITECTURE-ISSUES-NAMESPACE-LOGGING.md § Issue 1):
# - Application workloads: {component}-{env} (mongodb-dev, signoz-uat, boomi-prod, test-audit-sit)
# - Platform services: {component} NO suffix (cert-manager, kyverno, flux-system, kube-system)
#
# Usage:
#   ./scripts/hooks/validate-naming-convention.sh
#   # Returns 0 if all namespaces are compliant, 1 if violations found

set -euo pipefail

# Platform services that should NOT have environment suffix
PLATFORM_SERVICES=(
  "cert-manager"
  "kyverno"
  "flux-system"
  "kube-system"
  "kube-public"
  "kube-node-lease"
  "default"
)

# Valid environment suffixes
VALID_ENVS=("dev" "uat" "prod" "sit")

VIOLATIONS=()

# Check all namespace declarations in YAML files (OVERLAY files only)
check_yaml_files() {
  local files
  # Only check overlay files, not base (base gets patched by kustomize)
  files=$(find gitops/*/overlays k8s/overlays -type f \( -name "*.yaml" -o -name "*.yml" \) 2>/dev/null || true)

  if [ -z "$files" ]; then
    return 0
  fi

  while IFS= read -r file; do
    # Extract namespace declarations (both in kustomization.yaml and metadata.namespace)
    local namespaces
    namespaces=$(grep -E "^namespace:|  namespace:" "$file" 2>/dev/null | \
      sed -E 's/^[[:space:]]*namespace:[[:space:]]*//g' | \
      tr -d '"' | tr -d "'" || true)

    if [ -z "$namespaces" ]; then
      continue
    fi

    while IFS= read -r ns; do
      if [ -z "$ns" ]; then
        continue
      fi

      # Skip if it's a platform service (allowed to have no suffix)
      is_platform=false
      for platform in "${PLATFORM_SERVICES[@]}"; do
        if [ "$ns" = "$platform" ]; then
          is_platform=true
          break
        fi
      done

      if $is_platform; then
        continue
      fi

      # Check if namespace has valid environment suffix
      has_valid_suffix=false
      for env in "${VALID_ENVS[@]}"; do
        if [[ "$ns" =~ -${env}$ ]]; then
          has_valid_suffix=true
          break
        fi
      done

      if ! $has_valid_suffix; then
        VIOLATIONS+=("$file: namespace '$ns' should have -{env} suffix (e.g., '$ns-dev', '$ns-uat')")
      fi
    done <<< "$namespaces"
  done <<< "$files"
}

# Check kustomization.yaml namespace field (OVERLAY files only)
check_kustomization_files() {
  local files
  # Only check overlay kustomization.yaml files
  files=$(find gitops/*/overlays k8s/overlays -type f -name "kustomization.yaml" 2>/dev/null || true)

  if [ -z "$files" ]; then
    return 0
  fi

  while IFS= read -r file; do
    local ns
    ns=$(grep "^namespace:" "$file" 2>/dev/null | sed 's/^namespace:[[:space:]]*//g' | tr -d '"' | tr -d "'" || true)

    if [ -z "$ns" ]; then
      continue
    fi

    # Skip platform services
    is_platform=false
    for platform in "${PLATFORM_SERVICES[@]}"; do
      if [ "$ns" = "$platform" ]; then
        is_platform=true
        break
      fi
    done

    if $is_platform; then
      continue
    fi

    # Check suffix
    has_valid_suffix=false
    for env in "${VALID_ENVS[@]}"; do
      if [[ "$ns" =~ -${env}$ ]]; then
        has_valid_suffix=true
        break
      fi
    done

    if ! $has_valid_suffix; then
      VIOLATIONS+=("$file: namespace '$ns' should have -{env} suffix")
    fi
  done <<< "$files"
}

# Main execution
echo "🔍 Validating namespace naming convention..."

check_yaml_files
check_kustomization_files

if [ ${#VIOLATIONS[@]} -eq 0 ]; then
  echo "✅ All namespaces follow naming convention"
  echo ""
  echo "Convention:"
  echo "  • Application workloads: {component}-{env} (mongodb-dev, signoz-uat)"
  echo "  • Platform services: {component} (cert-manager, kyverno, flux-system)"
  exit 0
else
  echo "❌ Namespace naming violations found:"
  echo ""
  for violation in "${VIOLATIONS[@]}"; do
    echo "  • $violation"
  done
  echo ""
  echo "Convention:"
  echo "  • Application workloads MUST have -{env} suffix: mongodb-dev, signoz-uat, boomi-prod"
  echo "  • Platform services have NO suffix: cert-manager, kyverno, flux-system"
  echo ""
  echo "See docs/references/component-catalog.md § 'Naming Convention' for details"
  exit 1
fi
