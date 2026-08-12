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
  _enumerate_terraform_state_resources "workload-identity" "$1"
}

_enumerate_eks_platform_resources() {
  _enumerate_terraform_state_resources "eks-platform" "$1"
}

# ---------------------------------------------------------------------------
# _enumerate_terraform_tf_dir_for_scope <scope>
# ---------------------------------------------------------------------------
#
# Explicit scope -> Terraform root mapping. Deliberately a hardcoded case
# rather than a derived path: a new scope must be added here consciously,
# and an unmapped scope returns 1 so the caller reports "enumeration
# unavailable" instead of silently previewing the wrong root.
_enumerate_terraform_tf_dir_for_scope() {
  local root="${_ORCHESTRATOR_ROOT_DIR:-.}/platform-prerequisites/terraform"
  case "${1:-}" in
    eks-platform)      printf '%s\n' "${root}/eks-platform" ;;
    workload-identity) printf '%s\n' "${root}/workload-identity" ;;
    access-governance) printf '%s\n' "${root}/access-governance" ;;
    eks-access)        printf '%s\n' "${root}/eks-access" ;;
    mongodb)           printf '%s\n' "${root}/mongodb" ;;
    *) return 1 ;;
  esac
}

# ---------------------------------------------------------------------------
# _enumerate_terraform_state_resources <scope> <environment>
# ---------------------------------------------------------------------------
#
# Enumerates the resources a destroy would actually target, read from real
# Terraform state, and annotates each with whether it still exists live.
#
# This replaces a hardcoded printf list that never read state (#163). That
# list was observed announcing an EFS filesystem, a backup vault, a node
# group and six addons that earlier runs had already destroyed -- i.e. it
# misinformed the operator at precisely the moment they were deciding
# whether to destroy production.
#
# Two deliberate properties:
#
#   1. Fails closed. If state cannot be read, this returns 1 and the caller
#      prints "enumeration not available" -- it never falls back to a
#      plausible-looking static list. Showing a confident fiction is worse
#      than showing nothing.
#
#   2. MISSING is informational, never fatal. State can legitimately
#      disagree with live AWS after a partial destroy, and a partially-
#      destroyed stack must remain destroyable -- that was the #159
#      deadlock and must not be reintroduced here.
_enumerate_terraform_state_resources() {
  local scope="$1"
  local environment="$2"
  local tf_dir state_json

  tf_dir="$(_enumerate_terraform_tf_dir_for_scope "$scope")" || return 1
  [[ -d "$tf_dir" ]] || return 1

  # Read-only. Assumes the backend is already initialized: the destroy flow
  # initializes it before this runs. No bootstrap is triggered from a
  # preview path -- a preview must never create or mutate anything.
  state_json="$(terraform -chdir="$tf_dir" show -json 2>/dev/null)" || return 1
  [[ -n "$state_json" ]] || return 1

  local rendered resource_count
  rendered="$(printf '%s' "$state_json" | "${_ORCHESTRATOR_PYTHON:-python3}" -c '
import json, sys

try:
    doc = json.load(sys.stdin)
except Exception:
    sys.exit(1)

rows = []
def walk(module):
    for r in module.get("resources", []):
        if r.get("mode") != "managed":
            continue
        values = r.get("values") or {}
        ident = values.get("id") or values.get("arn") or values.get("name") or "-"
        rows.append((r.get("type", "?"), r.get("address") or r.get("name", "?"), str(ident)))
    for child in module.get("child_modules", []):
        walk(child)

walk((doc.get("values") or {}).get("root_module") or {})

if not rows:
    print("  (no managed resources in state -- nothing for this scope to destroy)")
    print("__RESOURCE_COUNT__=0")
    sys.exit(0)

rows.sort()
width = max(len(t) for t, _, _ in rows)
for rtype, addr, ident in rows:
    print("  %-*s  %s" % (width, rtype, addr))
    print("  %-*s    id: %s" % (width, "", ident))
print("")
print("  %d managed resource(s) in Terraform state for this scope." % len(rows))
print("__RESOURCE_COUNT__=%d" % len(rows))
')" || return 1

  resource_count="$(printf '%s\n' "$rendered" | sed -n 's/^__RESOURCE_COUNT__=//p')"
  printf '%s\n' "$rendered" | grep -v '^__RESOURCE_COUNT__='

  printf '\n'
  printf 'Source: live Terraform state for %s (%s).\n' "$scope" "$environment"
  printf 'State can lag reality after a partial destroy; Terraform re-checks\n'
  printf 'each resource against AWS during the plan shown before apply.\n'

  # Preserved from the previous static implementation: eks-platform is the
  # whole cluster, so it keeps an explicit blast-radius warning -- but only
  # when there is actually something left to destroy. Warning about a
  # "large-scale destruction" over an empty state is the same kind of
  # misinformation this change exists to remove.
  if [[ "$scope" == "eks-platform" && "${resource_count:-0}" -gt 0 ]]; then
    printf '\n'
    printf '⚠️  WARNING: This is a large-scale destruction that removes the entire cluster!\n'
    printf '⚠️  All workloads, data, and configurations will be permanently deleted.\n'
  fi
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
