#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
NAMESPACE="mongodb"
ENCRYPTION_SECRET_NAME="psmdb-encryption-key"
ENCRYPTION_ESCROW_FILE="$ROOT_DIR/.local-dev-encryption-key.txt"
USERS_SECRET_NAME="psmdb-secrets"
USERS_ESCROW_FILE="$ROOT_DIR/.local-dev-user-passwords.txt"
GITIGNORE_FILE="$ROOT_DIR/.gitignore"

# Percona PSMDB operator expected user keys in the users secret.
PSMDB_USER_KEYS=(
  MONGODB_BACKUP_USER
  MONGODB_BACKUP_PASSWORD
  MONGODB_CLUSTER_ADMIN_USER
  MONGODB_CLUSTER_ADMIN_PASSWORD
  MONGODB_CLUSTER_MONITOR_USER
  MONGODB_CLUSTER_MONITOR_PASSWORD
  MONGODB_USER_ADMIN_USER
  MONGODB_USER_ADMIN_PASSWORD
)

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "ERROR: required command not found: $1" >&2
    exit 1
  fi
}

decode_base64() {
  local encoded="$1"

  if printf '%s' "$encoded" | base64 --decode >/dev/null 2>&1; then
    printf '%s' "$encoded" | base64 --decode
    return 0
  fi

  if printf '%s' "$encoded" | base64 -D >/dev/null 2>&1; then
    printf '%s' "$encoded" | base64 -D
    return 0
  fi

  return 1
}

validate_key() {
  local key="$1"
  local decoded_len

  if ! decoded_len="$(decode_base64 "$key" | wc -c | tr -d '[:space:]')"; then
    return 1
  fi

  [[ "$decoded_len" == "32" ]]
}

ensure_gitignore_entry() {
  local entry="$1"

  if [[ -f "$GITIGNORE_FILE" ]] && grep -Eq "^${entry}$" "$GITIGNORE_FILE"; then
    return 0
  fi

  if [[ ! -f "$GITIGNORE_FILE" ]]; then
    printf '%s\n' "$entry" > "$GITIGNORE_FILE"
  else
    printf '\n%s\n' "$entry" >> "$GITIGNORE_FILE"
  fi
}

read_key_from_escrow() {
  tr -d '\r\n' < "$ENCRYPTION_ESCROW_FILE"
}

write_encryption_escrow_key() {
  local key="$1"
  umask 177
  printf '%s\n' "$key" > "$ENCRYPTION_ESCROW_FILE"
  chmod 600 "$ENCRYPTION_ESCROW_FILE"
}

read_encryption_secret_key() {
  kubectl -n "$NAMESPACE" get secret "$ENCRYPTION_SECRET_NAME" -o go-template='{{index .data "encryption-key"}}'
}

read_legacy_encryption_secret_key() {
  kubectl -n "$NAMESPACE" get secret "$ENCRYPTION_SECRET_NAME" -o go-template='{{index .data "encryptionKey"}}'
}

create_encryption_secret() {
  local key="$1"

  printf '%s' "$key" \
    | kubectl create secret generic "$ENCRYPTION_SECRET_NAME" \
      --namespace "$NAMESPACE" \
      --from-file=encryption-key=/dev/stdin \
      --dry-run=client -o yaml | kubectl apply -f - >/dev/null
}

generate_password() {
  openssl rand -base64 24 | tr -d '\r\n'
}

escrow_value_for_key() {
  local key="$1"
  local file="$2"

  awk -F= -v wanted="$key" '$1 == wanted { print substr($0, index($0, "=") + 1); exit }' "$file"
}

write_generated_users_escrow() {
  local backup_password="$1"
  local cluster_admin_password="$2"
  local cluster_monitor_password="$3"
  local user_admin_password="$4"

  umask 177
  cat > "$USERS_ESCROW_FILE" <<EOF
MONGODB_BACKUP_USER=backup
MONGODB_BACKUP_PASSWORD=$backup_password
MONGODB_CLUSTER_ADMIN_USER=clusterAdmin
MONGODB_CLUSTER_ADMIN_PASSWORD=$cluster_admin_password
MONGODB_CLUSTER_MONITOR_USER=clusterMonitor
MONGODB_CLUSTER_MONITOR_PASSWORD=$cluster_monitor_password
MONGODB_USER_ADMIN_USER=userAdmin
MONGODB_USER_ADMIN_PASSWORD=$user_admin_password
EOF
  chmod 600 "$USERS_ESCROW_FILE"
}

validate_users_escrow() {
  local missing=0

  for key in "${PSMDB_USER_KEYS[@]}"; do
    if [[ -z "$(escrow_value_for_key "$key" "$USERS_ESCROW_FILE")" ]]; then
      echo "ERROR: escrow file '$USERS_ESCROW_FILE' is missing key: $key" >&2
      missing=1
    fi
  done

  return "$missing"
}

create_users_secret_from_escrow() {
  local -a args=()

  for key in "${PSMDB_USER_KEYS[@]}"; do
    args+=("--from-literal=${key}=$(escrow_value_for_key "$key" "$USERS_ESCROW_FILE")")
  done

  kubectl create secret generic "$USERS_SECRET_NAME" \
    --namespace "$NAMESPACE" \
    "${args[@]}" >/dev/null
}

main() {
  local key

  require_cmd kubectl
  require_cmd openssl
  require_cmd base64
  require_cmd grep

  if ! kubectl get serviceaccount default --namespace "$NAMESPACE" >/dev/null 2>&1; then
    echo "ERROR: namespace-scoped preflight failed for '$NAMESPACE'. Ensure platform prerequisites were applied and you have access in this namespace." >&2
    exit 1
  fi

  if [[ "$(kubectl auth can-i get secrets --namespace "$NAMESPACE")" != "yes" ]]; then
    echo "ERROR: RBAC check failed. Current identity cannot get secrets in namespace '$NAMESPACE'." >&2
    exit 1
  fi

  if [[ "$(kubectl auth can-i create secrets --namespace "$NAMESPACE")" != "yes" ]]; then
    echo "ERROR: RBAC check failed. Current identity cannot create secrets in namespace '$NAMESPACE'." >&2
    exit 1
  fi

  # Ensure escrow files are in .gitignore.
  ensure_gitignore_entry ".local-dev-encryption-key.txt"
  ensure_gitignore_entry ".local-dev-user-passwords.txt"

  # --- Encryption key secret ---
  if kubectl -n "$NAMESPACE" get secret "$ENCRYPTION_SECRET_NAME" >/dev/null 2>&1; then
    local current_key=""
    local legacy_key=""

    current_key="$(read_encryption_secret_key || true)"
    if [[ -n "$current_key" ]] && validate_key "$current_key"; then
      echo "Secret '$ENCRYPTION_SECRET_NAME' already exists in namespace '$NAMESPACE' with the expected key name."
    else
      legacy_key="$(read_legacy_encryption_secret_key || true)"
      if [[ -n "$legacy_key" ]] && validate_key "$legacy_key"; then
        echo "Secret '$ENCRYPTION_SECRET_NAME' uses the legacy key name 'encryptionKey'; reconciling it to 'encryption-key'."
        create_encryption_secret "$legacy_key"
      elif [[ -f "$ENCRYPTION_ESCROW_FILE" ]]; then
        key="$(read_key_from_escrow)"
        if ! validate_key "$key"; then
          echo "ERROR: escrow file '$ENCRYPTION_ESCROW_FILE' is invalid. Expected base64 value decoding to exactly 32 bytes." >&2
          exit 1
        fi
        echo "Secret '$ENCRYPTION_SECRET_NAME' exists but is missing a valid 'encryption-key' entry; restoring from '$ENCRYPTION_ESCROW_FILE'."
        create_encryption_secret "$key"
      else
        echo "ERROR: secret '$ENCRYPTION_SECRET_NAME' exists but does not contain a valid 'encryption-key' entry, and no escrow file is available to repair it safely." >&2
        exit 1
      fi
    fi
  elif [[ -f "$ENCRYPTION_ESCROW_FILE" ]]; then
    key="$(read_key_from_escrow)"
    if ! validate_key "$key"; then
      echo "ERROR: escrow file '$ENCRYPTION_ESCROW_FILE' is invalid. Expected base64 value decoding to exactly 32 bytes." >&2
      exit 1
    fi
    echo "Using existing local escrow key from '$ENCRYPTION_ESCROW_FILE'."
    create_encryption_secret "$key"
    echo "Secret '$ENCRYPTION_SECRET_NAME' created in namespace '$NAMESPACE'."
  else
    key="$(openssl rand -base64 32 | tr -d '\r\n')"
    if ! validate_key "$key"; then
      echo "ERROR: generated key failed validation." >&2
      exit 1
    fi
    write_encryption_escrow_key "$key"
    echo "Generated new key and stored local escrow at '$ENCRYPTION_ESCROW_FILE' (mode 600)."
    create_encryption_secret "$key"
    echo "Secret '$ENCRYPTION_SECRET_NAME' created in namespace '$NAMESPACE'."
  fi

  # --- Users secret (all Percona operator credentials) ---
  if kubectl -n "$NAMESPACE" get secret "$USERS_SECRET_NAME" >/dev/null 2>&1; then
    echo "Secret '$USERS_SECRET_NAME' already exists in namespace '$NAMESPACE'."
  elif [[ -f "$USERS_ESCROW_FILE" ]]; then
    if ! validate_users_escrow; then
      exit 1
    fi
    echo "Using existing local user credentials escrow from '$USERS_ESCROW_FILE'."
    create_users_secret_from_escrow
    echo "Secret '$USERS_SECRET_NAME' created in namespace '$NAMESPACE'."
  else
    local backup_password
    local cluster_admin_password
    local cluster_monitor_password
    local user_admin_password

    backup_password="$(generate_password)"
    cluster_admin_password="$(generate_password)"
    cluster_monitor_password="$(generate_password)"
    user_admin_password="$(generate_password)"

    write_generated_users_escrow \
      "$backup_password" \
      "$cluster_admin_password" \
      "$cluster_monitor_password" \
      "$user_admin_password"
    echo "Generated all user credentials and stored escrow at '$USERS_ESCROW_FILE' (mode 600)."
    create_users_secret_from_escrow
    echo "Secret '$USERS_SECRET_NAME' created in namespace '$NAMESPACE'."
  fi

  echo "Dev secret bootstrap complete."
}

main "$@"
