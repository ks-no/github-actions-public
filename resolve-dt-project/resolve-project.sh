#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${DT_BASE_URL_INPUT%/}"
WARNING_PREFIX=$(echo "${DT_WARNING_PREFIX:-DT resolver}" | tr -cd '[:alnum:][:space:]:._-')
if [[ -z "$WARNING_PREFIX" ]]; then
  WARNING_PREFIX="DT resolver"
fi

escape_workflow_value() {
  local value="$1"
  value="${value//'%'/'%25'}"
  value="${value//$'\r'/'%0D'}"
  value="${value//$'\n'/'%0A'}"
  printf '%s' "$value"
}

warn_and_exit() {
  local message="$1"
  local escaped_prefix
  local escaped_message
  escaped_prefix=$(escape_workflow_value "$WARNING_PREFIX")
  escaped_message=$(escape_workflow_value "$message")
  echo "project_uuid=" >> "$GITHUB_OUTPUT"
  echo "resolved=false" >> "$GITHUB_OUTPUT"
  echo "base_url=${BASE_URL}" >> "$GITHUB_OUTPUT"
  echo "::warning::${escaped_prefix}: ${escaped_message}"
  exit 0
}

trap 'warn_and_exit "Unexpected error while resolving project."' ERR

if [[ -z "${DT_API_KEY:-}" ]]; then
  warn_and_exit "No DT API key provided; skipping project resolution."
fi

if [[ "$BASE_URL" != https://* ]]; then
  warn_and_exit "DT base URL must use HTTPS."
fi

PROJECT_UUID=""

if [[ -n "${DT_PROJECT_UUID_INPUT:-}" ]] && [[ "$DT_PROJECT_UUID_INPUT" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
  PROJECT_UUID="$DT_PROJECT_UUID_INPUT"
  echo "::debug::Using pre-resolved project UUID: $PROJECT_UUID"
else
  ENCODED_NAME=$(jq -rn --arg v "$DT_PROJECT_NAME" '$v | @uri')
  ENCODED_VERSION=$(jq -rn --arg v "$DT_PROJECT_VERSION" '$v | @uri')

  RETRY_COUNT="${DT_RETRY_COUNT:-3}"
  if ! [[ "$RETRY_COUNT" =~ ^[0-9]+$ ]]; then
    RETRY_COUNT=3
  fi

  RETRY_DELAY="${DT_RETRY_DELAY_SECONDS:-2}"
  if ! [[ "$RETRY_DELAY" =~ ^[0-9]+$ ]]; then
    RETRY_DELAY=2
  fi

  for attempt in $(seq 1 "$RETRY_COUNT"); do
    PROJECT_JSON=$(curl -fsS \
      --connect-timeout 10 --max-time 30 \
      -H "X-Api-Key: $DT_API_KEY" \
      "$BASE_URL/api/v1/project/lookup?name=$ENCODED_NAME&version=$ENCODED_VERSION" 2>/dev/null) || true

    PROJECT_UUID=$(echo "$PROJECT_JSON" | jq -r '.uuid // empty' 2>/dev/null || true)

    if [[ -n "$PROJECT_UUID" ]]; then
      break
    fi

    if [[ "$attempt" -lt "$RETRY_COUNT" ]]; then
      echo "::debug::Project lookup attempt $attempt returned empty, retrying in ${RETRY_DELAY}s..."
      sleep "$RETRY_DELAY"
    fi
  done
fi

if [[ -z "$PROJECT_UUID" ]]; then
  warn_and_exit "Could not find DT project '$DT_PROJECT_NAME' version '$DT_PROJECT_VERSION'."
fi

if ! [[ "$PROJECT_UUID" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
  warn_and_exit "Unexpected project UUID format: $PROJECT_UUID"
fi

echo "project_uuid=$PROJECT_UUID" >> "$GITHUB_OUTPUT"
echo "resolved=true" >> "$GITHUB_OUTPUT"
echo "base_url=$BASE_URL" >> "$GITHUB_OUTPUT"
echo "::debug::Resolved DT project UUID: $PROJECT_UUID"
