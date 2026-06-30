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

create_encryption_secret() {
  local key="$1"

  printf '%s' "$key" \
    | kubectl create secret generic "$ENCRYPTION_SECRET_NAME" \
      --namespace "$NAMESPACE" \
      --from-file=encryptionKey=/dev/stdin >/dev/null
}

generate_password() {
  openssl rand -base64 24 | tr -d '\r\n'
}

write_users_escrow() {
  local -n pairs=$1
  umask 177
  : > "$USERS_ESCROW_FILE"
  for key in "${PSMDB_USER_KEYS[@]}"; do
    printf '%s=%s\n' "$key" "${pairs[$key]}" >> "$USERS_ESCROW_FILE"
  done
  chmod 600 "$USERS_ESCROW_FILE"
}

read_users_escrow() {
  local -n out=$1
  while IFS='=' read -r k v; do
    [[ -z "$k" || "$k" == \#* ]] && continue
    out["$k"]="$v"
  done < "$USERS_ESCROW_FILE"
}

create_users_secret() {
  local -n creds=$1
  local -a args=()
  for key in "${PSMDB_USER_KEYS[@]}"; do
    args+=("--from-literal=${key}=${creds[$key]}")
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
    echo "Secret '$ENCRYPTION_SECRET_NAME' already exists in namespace '$NAMESPACE'."
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
    declare -A user_creds
    read_users_escrow user_creds
    local missing=0
    for k in "${PSMDB_USER_KEYS[@]}"; do
      if [[ -z "${user_creds[$k]:-}" ]]; then
        echo "ERROR: escrow file '$USERS_ESCROW_FILE' is missing key: $k" >&2
        missing=1
      fi
    done
    if [[ "$missing" -ne 0 ]]; then
      exit 1
    fi
    echo "Using existing local user credentials escrow from '$USERS_ESCROW_FILE'."
    create_users_secret user_creds
    echo "Secret '$USERS_SECRET_NAME' created in namespace '$NAMESPACE'."
  else
    declare -A user_creds
    user_creds[MONGODB_BACKUP_USER]="backup"
    user_creds[MONGODB_BACKUP_PASSWORD]="$(generate_password)"
    user_creds[MONGODB_CLUSTER_ADMIN_USER]="clusterAdmin"
    user_creds[MONGODB_CLUSTER_ADMIN_PASSWORD]="$(generate_password)"
    user_creds[MONGODB_CLUSTER_MONITOR_USER]="clusterMonitor"
    user_creds[MONGODB_CLUSTER_MONITOR_PASSWORD]="$(generate_password)"
    user_creds[MONGODB_USER_ADMIN_USER]="userAdmin"
    user_creds[MONGODB_USER_ADMIN_PASSWORD]="$(generate_password)"
    write_users_escrow user_creds
    echo "Generated all user credentials and stored escrow at '$USERS_ESCROW_FILE' (mode 600)."
    create_users_secret user_creds
    echo "Secret '$USERS_SECRET_NAME' created in namespace '$NAMESPACE'."
  fi

  echo "Dev secret bootstrap complete."
}

main "$@"
