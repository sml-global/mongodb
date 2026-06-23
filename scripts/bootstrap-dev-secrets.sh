#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
NAMESPACE="mongodb"
SECRET_NAME="psmdb-encryption-key"
ESCROW_FILE="$ROOT_DIR/.local-dev-encryption-key.txt"
GITIGNORE_FILE="$ROOT_DIR/.gitignore"

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
  local entry=".local-dev-encryption-key.txt"

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
  tr -d '\r\n' < "$ESCROW_FILE"
}

write_escrow_key() {
  local key="$1"
  umask 177
  printf '%s\n' "$key" > "$ESCROW_FILE"
  chmod 600 "$ESCROW_FILE"
}

create_cluster_secret() {
  local key="$1"

  printf '%s' "$key" \
    | kubectl create secret generic "$SECRET_NAME" \
      --namespace "$NAMESPACE" \
      --from-file=encryptionKey=/dev/stdin >/dev/null
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

  if kubectl -n "$NAMESPACE" get secret "$SECRET_NAME" >/dev/null 2>&1; then
    echo "Secret '$SECRET_NAME' already exists in namespace '$NAMESPACE'."
    echo "Cluster is ready."
    exit 0
  fi

  ensure_gitignore_entry

  if [[ -f "$ESCROW_FILE" ]]; then
    key="$(read_key_from_escrow)"
    if ! validate_key "$key"; then
      echo "ERROR: escrow file '$ESCROW_FILE' is invalid. Expected base64 value decoding to exactly 32 bytes." >&2
      exit 1
    fi
    echo "Using existing local escrow key from '$ESCROW_FILE'."
  else
    key="$(openssl rand -base64 32 | tr -d '\r\n')"
    if ! validate_key "$key"; then
      echo "ERROR: generated key failed validation." >&2
      exit 1
    fi
    write_escrow_key "$key"
    echo "Generated new key and stored local escrow at '$ESCROW_FILE' (mode 600)."
  fi

  create_cluster_secret "$key"
  echo "Secret '$SECRET_NAME' created in namespace '$NAMESPACE'."
}

main "$@"
