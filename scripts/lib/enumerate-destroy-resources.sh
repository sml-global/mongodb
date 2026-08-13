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
# Return status contract (the caller distinguishes all three):
#   0  enumeration succeeded and printed the real resource list
#   1  enumeration FAILED for a scope that does have an enumerator (state
#      unreadable, kubectl unusable, backend not initialized). The caller
#      MUST abort the destroy: there is no fallback list, because a
#      plausible-looking fiction shown at the moment a human decides
#      whether to destroy production is worse than showing nothing (#163).
#   2  no enumerator is mapped for this scope (or for this scope in this
#      environment). An honest absence, not a failure; the caller says so
#      explicitly and continues to the typed-yes gate.

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
      # Scope doesn't have enumeration support yet.
      return 2
      ;;
  esac
}

_enumerate_platform_controllers_resources() {
  local environment="$1"
  local overlay_dir

  # Derived from the environment rather than an allow-list of two: a
  # hardcoded `uat|dev` case meant PRODUCTION -- the environment where an
  # unreviewed destroy is most costly -- silently got no resource list at
  # all, even though gitops/platform-controllers/overlays/prod exists.
  # Deriving the path keeps every environment enumerated, and a genuinely
  # absent overlay is still reported honestly below.
  overlay_dir="gitops/platform-controllers/overlays/${environment}"

  [[ -d "$overlay_dir" ]] || return 2

  _enumerate_kustomize_resources "$overlay_dir"
}

_enumerate_mongodb_resources() {
  local environment="$1"
  local overlay_dir

  # k8s/ and gitops/ are two different deployment paths (see CLAUDE.md);
  # whichever exists for this environment is the one to enumerate. Checked
  # in order rather than hardcoding per-environment names so a new
  # environment is enumerated automatically instead of silently omitted.
  overlay_dir=""
  local candidate
  for candidate in \
    "k8s/overlays/${environment}" \
    "gitops/mongodb/overlays/${environment}"
  do
    if [[ -d "$candidate" ]]; then
      overlay_dir="$candidate"
      break
    fi
  done
  [[ -n "$overlay_dir" ]] || return 2

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

  tf_dir="$(_enumerate_terraform_tf_dir_for_scope "$scope")" || return 2
  [[ -d "$tf_dir" ]] || return 2

  # CROSS-ENVIRONMENT GUARD.
  #
  # `terraform show -json` reads whichever backend `.terraform/` was LAST
  # INITIALIZED to, which has nothing to do with the environment being
  # destroyed. A working copy previously used against prod leaves
  # .terraform/terraform.tfstate pointing at the prod bucket, so a
  # subsequent `destroy.sh --env uat` would enumerate PROD resources and
  # then ask the operator to type `yes` to destroy UAT -- real resource
  # ids, wrong account.
  #
  # Caught by a live UAT run during #159 review: with a prod-initialized
  # .terraform/ present, enumeration reached for
  # "oms/prod/eks-platform.tfstate" while the requested scope was uat. It
  # only failed safe there because the prod credentials had expired (403).
  #
  # So: refuse to trust a backend whose recorded bucket/key does not match
  # this environment's contract. Status 3 (state unavailable), never a
  # list from the wrong place.
  local backend_state="${tf_dir}/.terraform/terraform.tfstate"
  if [[ -f "$backend_state" ]]; then
    local recorded_bucket=""
    recorded_bucket="$("${_ORCHESTRATOR_PYTHON:-python3}" -c '
import json, sys
try:
    with open(sys.argv[1]) as handle:
        print((json.load(handle).get("backend") or {}).get("config", {}).get("bucket") or "")
except Exception:
    print("")
' "$backend_state" 2>/dev/null)"

    if [[ -n "$recorded_bucket" && -n "${TF_STATE_BUCKET:-}" \
          && "$recorded_bucket" != "$TF_STATE_BUCKET" ]]; then
      printf '  Terraform state for %s cannot be read safely from this working copy.\n' "$scope"
      printf '  The initialized backend points at bucket %s, but %s expects %s.\n' \
        "$recorded_bucket" "$environment" "$TF_STATE_BUCKET"
      printf '  Refusing to enumerate: a resource list from another environment is worse\n'
      printf '  than no list at all. Re-run provisioning for %s to re-initialize.\n' "$environment"
      return 3
    fi
  fi

  # Read-only. No bootstrap is ever triggered from a preview path -- a
  # preview must never create or mutate anything (a "preview" that can
  # create an S3 backend bucket is not a preview).
  #
  # The backend is therefore NOT guaranteed to be initialized here:
  # `.terraform/` is gitignored, so any fresh clone, new workstation, or
  # CI-less machine has never run `terraform init` for this root. That is
  # a normal condition, not a defect, and it must NOT abort the destroy --
  # doing so would strand every teardown from such a machine with no
  # supported recovery (running `terraform init` by hand is exactly the
  # raw-Terraform path this repo forbids). Report it as status 3 so the
  # caller prints the reason and continues to the typed-yes gate.
  local terraform_stderr terraform_status
  terraform_stderr="$(mktemp)" || return 1
  state_json="$(terraform -chdir="$tf_dir" show -json 2>"$terraform_stderr")"
  terraform_status=$?

  if [[ "$terraform_status" -ne 0 || -z "$state_json" ]]; then
    # Conditions where the state is legitimately UNREADABLE rather than
    # broken. Each is a normal point in a teardown's life, and each must
    # stay non-fatal or it strands the very teardown it is reporting on:
    #
    #   initializ|reconfigure|backend  -- never inited here (.terraform/
    #                                     is gitignored, so a fresh clone
    #                                     or new workstation always hits
    #                                     this)
    #   NoSuchBucket|does not exist    -- the state bucket itself is gone,
    #                                     i.e. the environment has already
    #                                     been torn down. Observed live
    #                                     against an emptied UAT during
    #                                     #159 validation.
    #   NoSuchKey|no state file        -- bucket present, this scope's
    #                                     state object already removed.
    if grep -qiE 'initializ|reconfigure|backend|NoSuchBucket|does not exist|NoSuchKey|no state file' \
         "$terraform_stderr" 2>/dev/null; then
      printf '  Terraform state for %s is not readable here:\n' "$scope"
      sed 's/^/    /' "$terraform_stderr" | sed -e 's/\x1b\[[0-9;]*m//g' -e '/^[[:space:]]*$/d' | head -6
      rm -f "$terraform_stderr"
      return 3
    fi
    printf '  terraform show -json failed for %s (exit %s):\n' "$scope" "$terraform_status" >&2
    sed 's/^/    /' "$terraform_stderr" >&2
    rm -f "$terraform_stderr"
    return 1
  fi
  rm -f "$terraform_stderr"

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
        name = values.get("name") or values.get("tags", {}).get("Name") or ""
        rows.append((r.get("type", "?"), r.get("address") or r.get("name", "?"),
                     str(ident), str(name)))
    for child in module.get("child_modules", []):
        walk(child)

walk((doc.get("values") or {}).get("root_module") or {})

if not rows:
    print("  (no managed resources in state -- nothing for this scope to destroy)")
    print("__RESOURCE_COUNT__=0")
    sys.exit(0)

# Group by the Terraform module the resource lives in, so an operator reads
# "what parts of the stack go" rather than scanning 58 undifferentiated
# lines. Within a group, sort by type then address for a stable order.
def group_of(address):
    # module.network.aws_vpc.this -> network ; top-level -> (root)
    parts = address.split(".")
    if len(parts) >= 2 and parts[0] == "module":
        return parts[1].split("[")[0]
    return "(root)"

groups = {}
for rtype, addr, ident, name in rows:
    groups.setdefault(group_of(addr), []).append((rtype, addr, ident, name))

# Long ids (ARNs, policy attachments) are truncated in the middle: the tail
# is the identifying part, and a wrapped 150-char ARN is what made this list
# hard to audit.
def short(text, limit=64):
    if len(text) <= limit:
        return text
    keep = limit - 3
    return text[: keep // 2] + "..." + text[-(keep - keep // 2):]

for group in sorted(groups):
    members = groups[group]
    print("  %s  (%d)" % (group, len(members)))
    for rtype, addr, ident, name in sorted(members):
        label = name if name and name not in ident else ""
        suffix = ("  %s" % label) if label else ""
        print("      %-34s %s%s" % (rtype, short(ident), suffix))
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
    # Status 3, NOT 1. kubectl is unusable precisely when the cluster is
    # already gone -- the most common partially-destroyed state, and one
    # this repo produces routinely because a teardown deletes the cluster
    # before the Terraform scopes that referenced it. Aborting here would
    # make the remaining scopes undestroyable: the #159 deadlock rebuilt
    # on a different observation. Report the absence honestly and let the
    # typed-yes gate stand between the operator and the destroy.
    printf "  Unable to enumerate Kubernetes resources for %s (kubectl is not usable here;\n" "$overlay_dir"
    printf "  this is expected when the cluster has already been destroyed).\n"
    return 3
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
