#!/usr/bin/env bash
#
# Loads config/environments/dev.env into the current shell's environment,
# read as pure data (never `source`d/`eval`d), so a value already set in the
# calling script's environment is not overwritten but an unset one gets the
# dotenv's value -- letting config/environments/dev.env be the single place
# these values are edited, while the "${VAR:-default}" fallback in each
# legacy script still applies if the dotenv is unreadable or missing a key.
#
# Usage: source this file after ROOT_DIR is set, before reading
# TF_STATE_BUCKET/TF_STATE_REGION/etc.

_load_env_config() {
  local env_file="${ROOT_DIR}/config/environments/dev.env"

  if [[ ! -r "$env_file" ]]; then
    return 0
  fi

  local line key value
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    [[ "$line" != *=* ]] && continue
    key="${line%%=*}"
    value="${line#*=}"
    [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
    if [[ -z "${!key:-}" ]]; then
      export "$key=$value"
    fi
  done < "$env_file"
}

_load_env_config
