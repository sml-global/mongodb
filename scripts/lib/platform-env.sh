#!/usr/bin/env bash
#
# Closed, manifest-driven dev/uat environment parser.
#
# `load_platform_env <dev|uat>` composes the declarative schema in
# config/environment-schema/ (base.manifest plus fragments/*.manifest, in
# bytewise lexical order), then reads config/environments/<env>.env as pure
# data with a line-by-line reader -- never `source`, `eval`, or any construct
# that could execute file content as shell code. Every value is validated
# against the composed schema's built-in validators, immutable-bound values
# are compared against scripts/lib/environment-contracts.sh, and cross-key
# constraints are evaluated, all before anything is exported. This file
# contains no list of downstream keys: the set of required/known keys comes
# entirely from the composed manifest.

_PLATFORM_ENV_LIBRARY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -r "${_PLATFORM_ENV_LIBRARY_DIR}/environment-contracts.sh" ]]; then
  printf 'ERROR: %s\n' "environment contracts library is not readable: ${_PLATFORM_ENV_LIBRARY_DIR}/environment-contracts.sh" >&2
  return 1 2>/dev/null || exit 1
fi
# shellcheck disable=SC1091
source "${_PLATFORM_ENV_LIBRARY_DIR}/environment-contracts.sh"

_platform_env_error() {
  printf 'ERROR: %s\n' "$*" >&2
}

_platform_env_contains() {
  local needle="$1"
  shift
  local candidate
  for candidate in "$@"; do
    if [[ "$candidate" == "$needle" ]]; then
      return 0
    fi
  done
  return 1
}

_platform_env_trim() {
  printf '%s' "$1" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

# ---------------------------------------------------------------------------
# Manifest composition
# ---------------------------------------------------------------------------

_platform_env_validate_validator_spec() {
  local validator_spec="$1"
  local validator_name="${validator_spec%%:*}"
  local validator_argument="-"
  local range_min
  local range_max

  if [[ "$validator_spec" == *:* ]]; then
    validator_argument="${validator_spec#*:}"
  fi

  case "$validator_name" in
    environment|account-id|region|dns-label|s3-bucket|state-prefix|state-key|promotion-mode|nonempty|ipv4-cidr)
      if [[ "$validator_argument" != "-" ]]; then
        _platform_env_error "validator ${validator_name} does not accept an argument"
        return 1
      fi
      ;;
    enum)
      if [[ "$validator_argument" == "-" || ! "$validator_argument" =~ ^[A-Za-z0-9_.-]+(,[A-Za-z0-9_.-]+)*$ ]]; then
        _platform_env_error "invalid enum validator argument: ${validator_argument}"
        return 1
      fi
      ;;
    fixed)
      if [[ "$validator_argument" == "-" || ! "$validator_argument" =~ ^[A-Za-z0-9_.-]+$ ]]; then
        _platform_env_error "invalid fixed validator argument: ${validator_argument}"
        return 1
      fi
      ;;
    integer)
      if [[ ! "$validator_argument" =~ ^[0-9]+:[0-9]+$ ]]; then
        _platform_env_error "invalid integer validator argument: ${validator_argument}"
        return 1
      fi
      range_min="${validator_argument%%:*}"
      range_max="${validator_argument#*:}"
      if ! (( range_min <= range_max )); then
        _platform_env_error "integer validator min must be <= max: ${validator_argument}"
        return 1
      fi
      ;;
    *)
      _platform_env_error "unknown validator: ${validator_name}"
      return 1
      ;;
  esac
}

_platform_env_load_manifest() {
  local manifest_file="$1"
  local line
  local line_number=0
  local trimmed
  local field_a
  local field_b
  local field_c
  local field_d

  if [[ -L "$manifest_file" ]]; then
    _platform_env_error "environment schema manifest must not be a symlink: ${manifest_file}"
    return 1
  fi

  if [[ ! -f "$manifest_file" ]]; then
    _platform_env_error "environment schema manifest must be a regular file: ${manifest_file}"
    return 1
  fi

  if [[ ! -r "$manifest_file" ]]; then
    _platform_env_error "environment schema manifest is not readable: ${manifest_file}"
    return 1
  fi

  while IFS= read -r line || [[ -n "$line" ]]; do
    line_number=$((line_number + 1))
    line="${line%$'\r'}"
    trimmed="$(_platform_env_trim "$line")"

    [[ -n "$trimmed" ]] || continue
    case "$trimmed" in
      '#'*) continue ;;
    esac

    if [[ ! "$trimmed" =~ ^([^\|]*)\|([^\|]*)\|([^\|]*)\|([^\|]*)$ ]]; then
      _platform_env_error "malformed manifest row at ${manifest_file}:${line_number}"
      return 1
    fi

    field_a="${BASH_REMATCH[1]}"
    field_b="${BASH_REMATCH[2]}"
    field_c="${BASH_REMATCH[3]}"
    field_d="${BASH_REMATCH[4]}"

    if [[ "$field_a" == "@constraint" ]]; then
      case "$field_b" in
        integer-order|cidr-contained-by|cidr-nonoverlap) ;;
        *)
          _platform_env_error "unknown constraint predicate at ${manifest_file}:${line_number}: ${field_b}"
          return 1
          ;;
      esac

      if [[ -z "$field_c" ]]; then
        _platform_env_error "constraint row missing key list at ${manifest_file}:${line_number}"
        return 1
      fi

      _platform_env_schema_constraint_predicate+=("$field_b")
      _platform_env_schema_constraint_keys+=("$field_c")
      _platform_env_schema_constraint_argument+=("$field_d")
      continue
    fi

    if [[ ! "$field_a" =~ ^[A-Z][A-Z0-9_]*$ ]]; then
      _platform_env_error "malformed manifest key name at ${manifest_file}:${line_number}: ${field_a}"
      return 1
    fi

    case "$field_b" in
      required|optional) ;;
      *)
        _platform_env_error "unknown required flag at ${manifest_file}:${line_number}: ${field_b}"
        return 1
        ;;
    esac

    _platform_env_validate_validator_spec "$field_c" || return 1

    if [[ "$field_d" != "-" && ! "$field_d" =~ ^[A-Z][A-Z0-9_]*$ ]]; then
      _platform_env_error "malformed immutable binding at ${manifest_file}:${line_number}: ${field_d}"
      return 1
    fi

    if _platform_env_contains "$field_a" "${_platform_env_schema_keys[@]}"; then
      _platform_env_error "duplicate manifest key declaration: ${field_a}"
      return 1
    fi

    _platform_env_schema_keys+=("$field_a")
    _platform_env_schema_required+=("$field_b")
    _platform_env_schema_validator+=("$field_c")
    _platform_env_schema_immutable+=("$field_d")
  done < "$manifest_file"
}

_platform_env_validate_composed_schema() {
  local index
  local keys_csv
  local key_name
  local referenced_keys
  local old_ifs="$IFS"

  for ((index = 0; index < ${#_platform_env_schema_constraint_keys[@]}; index++)); do
    keys_csv="${_platform_env_schema_constraint_keys[$index]}"
    IFS=',' read -r -a referenced_keys <<< "$keys_csv"
    IFS="$old_ifs"
    for key_name in "${referenced_keys[@]}"; do
      if ! _platform_env_contains "$key_name" "${_platform_env_schema_keys[@]}"; then
        _platform_env_error "constraint references unknown key: ${key_name}"
        return 1
      fi
    done
  done
}

_platform_env_schema_field_index() {
  local key_name="$1"
  local index
  for ((index = 0; index < ${#_platform_env_schema_keys[@]}; index++)); do
    if [[ "${_platform_env_schema_keys[$index]}" == "$key_name" ]]; then
      printf '%s' "$index"
      return 0
    fi
  done
  return 1
}

# ---------------------------------------------------------------------------
# Closed dotenv reader (data, never shell)
# ---------------------------------------------------------------------------

_platform_env_parse_environment_file() {
  local environment_file="$1"
  local line
  local line_number=0
  local trimmed
  local key_name
  local value

  if [[ -L "$environment_file" ]]; then
    _platform_env_error "environment config must not be a symlink: ${environment_file}"
    return 1
  fi

  if [[ ! -f "$environment_file" ]]; then
    _platform_env_error "environment config must be a regular file: ${environment_file}"
    return 1
  fi

  if [[ ! -r "$environment_file" ]]; then
    _platform_env_error "environment config is not readable: ${environment_file}"
    return 1
  fi

  if [[ -n "$(find "$environment_file" -maxdepth 0 -perm -020 2>/dev/null)" ]]; then
    _platform_env_error "environment config must not be group-writable: ${environment_file}"
    return 1
  fi

  if [[ -n "$(find "$environment_file" -maxdepth 0 -perm -002 2>/dev/null)" ]]; then
    _platform_env_error "environment config must not be world-writable: ${environment_file}"
    return 1
  fi

  while IFS= read -r line || [[ -n "$line" ]]; do
    line_number=$((line_number + 1))
    line="${line%$'\r'}"
    trimmed="$(_platform_env_trim "$line")"

    [[ -n "$trimmed" ]] || continue
    case "$trimmed" in
      '#'*) continue ;;
    esac

    if [[ ! "$trimmed" =~ ^([A-Z][A-Z0-9_]*)=([^\"\'\`\\\;\&\|\<\>\(\)\{\}\#]*)$ ]]; then
      _platform_env_error "invalid dotenv assignment at ${environment_file}:${line_number}"
      return 1
    fi

    key_name="${BASH_REMATCH[1]}"
    value="${BASH_REMATCH[2]}"
    value="$(_platform_env_trim "$value")"

    if [[ -z "$value" ]]; then
      _platform_env_error "empty value for ${key_name} at ${environment_file}:${line_number}"
      return 1
    fi

    # Note: command substitution ($( ), ${ }), backticks, and <placeholder>
    # values are already rejected above as "invalid dotenv assignment" --
    # the assignment regex's value character class excludes every one of
    # '(', ')', '{', '}', '<', '>', '`', and '#', so no value containing
    # those constructs can ever reach this point. There is deliberately no
    # second "unresolved or executable value" check here: that classification
    # would be dead code.

    if _platform_env_contains "$key_name" "${_platform_env_loaded_keys[@]}"; then
      _platform_env_error "duplicate dotenv key ${key_name} at ${environment_file}:${line_number}"
      return 1
    fi

    _platform_env_loaded_keys+=("$key_name")
    _platform_env_loaded_values+=("$value")
  done < "$environment_file"
}

_platform_env_loaded_value_of() {
  local key_name="$1"
  local index
  for ((index = 0; index < ${#_platform_env_loaded_keys[@]}; index++)); do
    if [[ "${_platform_env_loaded_keys[$index]}" == "$key_name" ]]; then
      printf '%s' "${_platform_env_loaded_values[$index]}"
      return 0
    fi
  done
  return 1
}

# ---------------------------------------------------------------------------
# Built-in validators
# ---------------------------------------------------------------------------

_platform_env_value_in_csv() {
  local value="$1"
  local csv="$2"
  local old_ifs="$IFS"
  local candidate
  local candidates

  IFS=',' read -r -a candidates <<< "$csv"
  IFS="$old_ifs"
  for candidate in "${candidates[@]}"; do
    if [[ "$candidate" == "$value" ]]; then
      return 0
    fi
  done
  return 1
}

_platform_env_validate_value() {
  local validator_spec="$1"
  local key_name="$2"
  local value="$3"
  local validator_name="${validator_spec%%:*}"
  local validator_argument="-"
  local range_min
  local range_max

  if [[ "$validator_spec" == *:* ]]; then
    validator_argument="${validator_spec#*:}"
  fi

  case "$validator_name" in
    environment)
      case "$value" in
        dev|uat) ;;
        *)
          _platform_env_error "invalid value for ${key_name}: ${value}"
          return 1
          ;;
      esac
      ;;
    account-id)
      if [[ ! "$value" =~ ^[0-9]{12}$ ]]; then
        _platform_env_error "invalid AWS account id for ${key_name}: ${value}"
        return 1
      fi
      ;;
    region)
      if [[ ! "$value" =~ ^[a-z]{2}-[a-z]+-[0-9]$ ]]; then
        _platform_env_error "invalid AWS region for ${key_name}: ${value}"
        return 1
      fi
      ;;
    s3-bucket)
      if [[ ! "$value" =~ ^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$ ]]; then
        _platform_env_error "invalid S3 bucket name for ${key_name}: ${value}"
        return 1
      fi
      ;;
    state-prefix)
      if [[ ! "$value" =~ ^[a-z0-9]+(/[a-z0-9-]+)*$ ]]; then
        _platform_env_error "invalid Terraform state prefix for ${key_name}: ${value}"
        return 1
      fi
      ;;
    state-key)
      if [[ ! "$value" =~ ^[a-z0-9]+(/[a-z0-9-]+)*\.tfstate$ ]]; then
        _platform_env_error "invalid Terraform state key for ${key_name}: ${value}"
        return 1
      fi
      ;;
    dns-label)
      if [[ ! "$value" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$ ]]; then
        _platform_env_error "invalid label for ${key_name}: ${value}"
        return 1
      fi
      ;;
    promotion-mode)
      case "$value" in
        modeled|uat-build) ;;
        *)
          _platform_env_error "invalid promotion mode for ${key_name}: ${value}"
          return 1
          ;;
      esac
      ;;
    nonempty)
      if [[ -z "$value" ]]; then
        _platform_env_error "empty value for ${key_name}"
        return 1
      fi
      ;;
    enum)
      if ! _platform_env_value_in_csv "$value" "$validator_argument"; then
        _platform_env_error "invalid enumerated value for ${key_name}: ${value}"
        return 1
      fi
      ;;
    fixed)
      if [[ "$value" != "$validator_argument" ]]; then
        _platform_env_error "invalid fixed value for ${key_name}: ${value}"
        return 1
      fi
      ;;
    integer)
      range_min="${validator_argument%%:*}"
      range_max="${validator_argument#*:}"
      if [[ ! "$value" =~ ^[0-9]+$ ]]; then
        _platform_env_error "invalid integer value for ${key_name}: ${value}"
        return 1
      fi
      if ! (( value >= range_min && value <= range_max )); then
        _platform_env_error "integer value for ${key_name} out of range [${range_min}, ${range_max}]: ${value}"
        return 1
      fi
      ;;
    ipv4-cidr)
      if [[ ! "$value" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        _platform_env_error "invalid IPv4 CIDR for ${key_name}: ${value}"
        return 1
      fi
      ;;
    *)
      _platform_env_error "unknown validator for ${key_name}: ${validator_name}"
      return 1
      ;;
  esac
}

# ---------------------------------------------------------------------------
# Cross-key constraint predicates
# ---------------------------------------------------------------------------

_platform_env_ipv4_to_int() {
  local address="$1"
  local a
  local b
  local c
  local d
  local old_ifs="$IFS"
  IFS='.' read -r a b c d <<< "$address"
  IFS="$old_ifs"
  printf '%s' "$(( (a * 16777216) + (b * 65536) + (c * 256) + d ))"
}

_platform_env_cidr_network_and_mask() {
  local cidr="$1"
  local address="${cidr%/*}"
  local prefix_length="${cidr#*/}"
  local network_int
  local mask_int

  network_int="$(_platform_env_ipv4_to_int "$address")"
  if [[ "$prefix_length" -eq 0 ]]; then
    mask_int=0
  else
    mask_int=$(( (0xFFFFFFFF << (32 - prefix_length)) & 0xFFFFFFFF ))
  fi
  network_int=$(( network_int & mask_int ))
  printf '%s %s\n' "$network_int" "$mask_int"
}

_platform_env_check_integer_order() {
  local keys_csv="$1"
  local old_ifs="$IFS"
  local keys_array
  local key_name
  local current_value
  local previous_value=""

  IFS=',' read -r -a keys_array <<< "$keys_csv"
  IFS="$old_ifs"

  for key_name in "${keys_array[@]}"; do
    current_value="$(_platform_env_loaded_value_of "$key_name")" || {
      _platform_env_error "integer-order references unknown key: ${key_name}"
      return 1
    }
    if [[ -n "$previous_value" ]] && (( current_value < previous_value )); then
      _platform_env_error "integer-order violated at ${key_name}: ${current_value} is less than the previous key's value"
      return 1
    fi
    previous_value="$current_value"
  done
}

_platform_env_check_cidr_contained_by() {
  local keys_csv="$1"
  local child_key="${keys_csv%%,*}"
  local parent_key="${keys_csv#*,}"
  local child_value
  local parent_value
  local child_net
  local child_mask
  local parent_net
  local parent_mask

  child_value="$(_platform_env_loaded_value_of "$child_key")" || {
    _platform_env_error "cidr-contained-by references unknown key: ${child_key}"
    return 1
  }
  parent_value="$(_platform_env_loaded_value_of "$parent_key")" || {
    _platform_env_error "cidr-contained-by references unknown key: ${parent_key}"
    return 1
  }

  read -r child_net child_mask <<< "$(_platform_env_cidr_network_and_mask "$child_value")"
  read -r parent_net parent_mask <<< "$(_platform_env_cidr_network_and_mask "$parent_value")"

  if (( (child_net & parent_mask) != parent_net )); then
    _platform_env_error "${child_key} (${child_value}) is not contained by ${parent_key} (${parent_value})"
    return 1
  fi
}

_platform_env_check_cidr_nonoverlap() {
  local keys_csv="$1"
  local old_ifs="$IFS"
  local keys_array
  local i
  local j
  local value_i
  local value_j
  local net_i
  local mask_i
  local net_j
  local mask_j
  local min_mask

  IFS=',' read -r -a keys_array <<< "$keys_csv"
  IFS="$old_ifs"

  for ((i = 0; i < ${#keys_array[@]}; i++)); do
    for ((j = i + 1; j < ${#keys_array[@]}; j++)); do
      value_i="$(_platform_env_loaded_value_of "${keys_array[$i]}")" || {
        _platform_env_error "cidr-nonoverlap references unknown key: ${keys_array[$i]}"
        return 1
      }
      value_j="$(_platform_env_loaded_value_of "${keys_array[$j]}")" || {
        _platform_env_error "cidr-nonoverlap references unknown key: ${keys_array[$j]}"
        return 1
      }
      read -r net_i mask_i <<< "$(_platform_env_cidr_network_and_mask "$value_i")"
      read -r net_j mask_j <<< "$(_platform_env_cidr_network_and_mask "$value_j")"
      min_mask=$(( mask_i < mask_j ? mask_i : mask_j ))
      if (( (net_i & min_mask) == (net_j & min_mask) )); then
        _platform_env_error "${keys_array[$i]} (${value_i}) overlaps ${keys_array[$j]} (${value_j})"
        return 1
      fi
    done
  done
}

_platform_env_evaluate_constraints() {
  local index
  local predicate
  local keys_csv
  for ((index = 0; index < ${#_platform_env_schema_constraint_predicate[@]}; index++)); do
    predicate="${_platform_env_schema_constraint_predicate[$index]}"
    keys_csv="${_platform_env_schema_constraint_keys[$index]}"
    case "$predicate" in
      integer-order)
        _platform_env_check_integer_order "$keys_csv" || return 1
        ;;
      cidr-contained-by)
        _platform_env_check_cidr_contained_by "$keys_csv" || return 1
        ;;
      cidr-nonoverlap)
        _platform_env_check_cidr_nonoverlap "$keys_csv" || return 1
        ;;
      *)
        _platform_env_error "unknown constraint predicate: ${predicate}"
        return 1
        ;;
    esac
  done
}

# ---------------------------------------------------------------------------
# Legacy required-variable check and UAT contract. verify_aws_identity,
# verify_kubernetes_context, and verify_eks_authentication_mode below are
# intentionally left UAT-specific and unchanged here: generalizing them to
# also cover dev is the explicit scope of "Task 5: Supply Reviewed UAT
# Access Symbols To Unified Provisioning" in
# docs/superpowers/plans/2026-07-22-phase2-environment-orchestration-foundation.md,
# not this task.
# ---------------------------------------------------------------------------

_validate_required_platform_env() {
  local variable_name
  local required_variables=(
    ENVIRONMENT
    EXPECTED_AWS_ACCOUNT_ID
    AWS_REGION
    EKS_CLUSTER_NAME
    BOOMI_NAMESPACE
    TF_STATE_BUCKET
    TF_STATE_REGION
    ACCESS_GOVERNANCE_STATE_KEY
    EKS_ACCESS_STATE_KEY
  )

  for variable_name in "${required_variables[@]}"; do
    if [[ -z "${!variable_name:-}" ]]; then
      _platform_env_error "required platform environment variable is missing: ${variable_name}"
      return 1
    fi
  done
}

_validate_uat_contract() {
  local expected_account_id

  if [[ "$ENVIRONMENT" != "uat" ]]; then
    _platform_env_error "environment config must declare ENVIRONMENT=uat"
    return 1
  fi

  expected_account_id="$(immutable_environment_value uat EXPECTED_AWS_ACCOUNT_ID)" || {
    _platform_env_error "unable to resolve the UAT immutable account id contract"
    return 1
  }

  if [[ "$EXPECTED_AWS_ACCOUNT_ID" != "$expected_account_id" ]]; then
    _platform_env_error "UAT config account is ${EXPECTED_AWS_ACCOUNT_ID}; expected ${expected_account_id}"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# Public entry point
# ---------------------------------------------------------------------------

load_platform_env() {
  local requested_environment="${1:-}"
  local repository_root
  local schema_dir
  local fragments_dir
  local environment_file
  local fragment_file
  local fragment_list
  local old_ifs
  local index
  local key_name
  local value
  local schema_index
  local validator_spec
  local immutable_key
  local expected_value
  local requested_env_value

  case "$requested_environment" in
    dev|uat) ;;
    *)
      _platform_env_error "load_platform_env accepts only dev or uat"
      return 1
      ;;
  esac

  repository_root="$(cd "${_PLATFORM_ENV_LIBRARY_DIR}/../.." && pwd)" || return 1
  schema_dir="$repository_root/config/environment-schema"
  fragments_dir="$schema_dir/fragments"
  environment_file="$repository_root/config/environments/${requested_environment}.env"

  _platform_env_schema_keys=()
  _platform_env_schema_required=()
  _platform_env_schema_validator=()
  _platform_env_schema_immutable=()
  _platform_env_schema_constraint_predicate=()
  _platform_env_schema_constraint_keys=()
  _platform_env_schema_constraint_argument=()
  _platform_env_loaded_keys=()
  _platform_env_loaded_values=()

  if [[ ! -f "$schema_dir/base.manifest" ]]; then
    _platform_env_error "environment schema manifest is missing: ${schema_dir}/base.manifest"
    return 1
  fi

  _platform_env_load_manifest "$schema_dir/base.manifest" || return 1

  if [[ -d "$fragments_dir" ]]; then
    fragment_list="$(find "$fragments_dir" -maxdepth 1 -type f -name '*.manifest' 2>/dev/null | LC_ALL=C sort)"
    if [[ -n "$fragment_list" ]]; then
      old_ifs="$IFS"
      IFS=$'\n'
      for fragment_file in $fragment_list; do
        IFS="$old_ifs"
        _platform_env_load_manifest "$fragment_file" || return 1
        IFS=$'\n'
      done
      IFS="$old_ifs"
    fi
  fi

  _platform_env_validate_composed_schema || return 1

  if [[ ! -e "$environment_file" ]]; then
    _platform_env_error "environment config for ${requested_environment} is missing: ${environment_file}"
    return 1
  fi

  _platform_env_parse_environment_file "$environment_file" || return 1

  for ((index = 0; index < ${#_platform_env_loaded_keys[@]}; index++)); do
    key_name="${_platform_env_loaded_keys[$index]}"
    if ! _platform_env_contains "$key_name" "${_platform_env_schema_keys[@]}"; then
      _platform_env_error "unknown dotenv key: ${key_name}"
      return 1
    fi
  done

  for ((index = 0; index < ${#_platform_env_schema_keys[@]}; index++)); do
    if [[ "${_platform_env_schema_required[$index]}" == "required" ]] && \
       ! _platform_env_contains "${_platform_env_schema_keys[$index]}" "${_platform_env_loaded_keys[@]}"; then
      _platform_env_error "missing required key: ${_platform_env_schema_keys[$index]}"
      return 1
    fi
  done

  for ((index = 0; index < ${#_platform_env_loaded_keys[@]}; index++)); do
    key_name="${_platform_env_loaded_keys[$index]}"
    value="${_platform_env_loaded_values[$index]}"
    schema_index="$(_platform_env_schema_field_index "$key_name")" || {
      _platform_env_error "unknown dotenv key: ${key_name}"
      return 1
    }
    validator_spec="${_platform_env_schema_validator[$schema_index]}"
    _platform_env_validate_value "$validator_spec" "$key_name" "$value" || return 1
  done

  requested_env_value="$(_platform_env_loaded_value_of ENVIRONMENT)" || {
    _platform_env_error "missing required key: ENVIRONMENT"
    return 1
  }
  if [[ "$requested_env_value" != "$requested_environment" ]]; then
    _platform_env_error "environment config declares ENVIRONMENT=${requested_env_value} but ${requested_environment} was requested"
    return 1
  fi

  for ((index = 0; index < ${#_platform_env_schema_keys[@]}; index++)); do
    immutable_key="${_platform_env_schema_immutable[$index]}"
    [[ "$immutable_key" != "-" ]] || continue
    key_name="${_platform_env_schema_keys[$index]}"
    value="$(_platform_env_loaded_value_of "$key_name")" || continue
    expected_value="$(immutable_environment_value "$requested_environment" "$immutable_key")" || {
      _platform_env_error "no immutable contract for ${requested_environment}:${immutable_key}"
      return 1
    }
    if [[ "$value" != "$expected_value" ]]; then
      _platform_env_error "config ${key_name} for ${requested_environment} is ${value}; expected ${expected_value}"
      return 1
    fi
  done

  _platform_env_evaluate_constraints || return 1

  for ((index = 0; index < ${#_platform_env_loaded_keys[@]}; index++)); do
    export "${_platform_env_loaded_keys[$index]}=${_platform_env_loaded_values[$index]}"
  done
}

verify_aws_identity() {
  local actual_account_id

  _validate_required_platform_env || return 1
  _validate_uat_contract || return 1

  if ! actual_account_id="$(aws sts get-caller-identity --query Account --output text)"; then
    _platform_env_error "unable to read the active AWS account with sts get-caller-identity"
    return 1
  fi

  if [[ "$actual_account_id" != "$EXPECTED_AWS_ACCOUNT_ID" ]]; then
    _platform_env_error "active AWS account is ${actual_account_id}; expected 672172129937 for UAT"
    return 1
  fi
}

verify_kubernetes_context() {
  local current_context
  local active_cluster_reference
  local expected_cluster_reference

  _validate_required_platform_env || return 1
  _validate_uat_contract || return 1

  if ! current_context="$(kubectl config current-context)"; then
    _platform_env_error "unable to read the current Kubernetes context"
    return 1
  fi

  if ! active_cluster_reference="$(kubectl config view --minify -o 'jsonpath={.contexts[0].context.cluster}')"; then
    _platform_env_error "unable to resolve the active cluster reference for Kubernetes context '${current_context}'"
    return 1
  fi

  expected_cluster_reference="arn:aws:eks:${AWS_REGION}:${EXPECTED_AWS_ACCOUNT_ID}:cluster/${EKS_CLUSTER_NAME}"
  if [[ "$active_cluster_reference" != "$expected_cluster_reference" ]]; then
    _platform_env_error "current Kubernetes context '${current_context}' does not target UAT; resolves to '${active_cluster_reference}'; expected '${expected_cluster_reference}'"
    return 1
  fi
}

verify_eks_authentication_mode() {
  local authentication_mode

  _validate_required_platform_env || return 1
  _validate_uat_contract || return 1

  if ! authentication_mode="$(aws eks describe-cluster \
    --name "$EKS_CLUSTER_NAME" \
    --region "$AWS_REGION" \
    --query 'cluster.accessConfig.authenticationMode' \
    --output text)"; then
    _platform_env_error "unable to read EKS authentication mode for cluster '${EKS_CLUSTER_NAME}'"
    return 1
  fi

  case "$authentication_mode" in
    API|API_AND_CONFIG_MAP) ;;
    *)
      _platform_env_error "EKS cluster '${EKS_CLUSTER_NAME}' authentication mode is '${authentication_mode:-empty}'; expected API or API_AND_CONFIG_MAP"
      return 1
      ;;
  esac
}