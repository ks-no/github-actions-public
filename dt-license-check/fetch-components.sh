#!/usr/bin/env bash
# Fetches all components of the DT project into $WORK_DIR/components.json.
# Runs as a step in dt-license-check/action.yml.
set -euo pipefail

# shellcheck source=helpers.sh
source "$GITHUB_ACTION_PATH/helpers.sh"

# A command that fails gives a warning instead of failing the job: the
# license check must never stop the pipeline.
trap 'warn_and_exit "Unexpected error while generating license inventory."' ERR

# Work files go in one folder in RUNNER_TEMP. The runner empties RUNNER_TEMP
# when the job ends, so they need no cleanup.
WORK_DIR=$(mktemp -d -p "$RUNNER_TEMP")
COMPONENTS_FILE="$WORK_DIR/components.json"
PAGE_FILE="$WORK_DIR/page.json"
PAGE_SIZE=100
PAGE_TOKEN=""
PAGE_INDEX=1
MAX_PAGES=10000

echo '[]' > "$COMPONENTS_FILE"

while [[ "$PAGE_INDEX" -le "$MAX_PAGES" ]]; do
  COMPONENTS_URL="$DT_BASE_URL/api/v2/projects/$DT_PROJECT_UUID/components?limit=$PAGE_SIZE&sort_by=name&sort_direction=ASC"
  if [[ -n "$PAGE_TOKEN" ]]; then
    ENCODED_PAGE_TOKEN=$(jq -rn --arg v "$PAGE_TOKEN" '$v | @uri')
    COMPONENTS_URL+="&page_token=$ENCODED_PAGE_TOKEN"
  fi

  # curl writes the file only when data arrives, so clear the previous page first.
  : > "$PAGE_FILE"
  HTTP_CODE=$(curl -sS -o "$PAGE_FILE" -w '%{http_code}' \
    --connect-timeout 10 --max-time 30 \
    -H "X-Api-Key: $DT_API_KEY" \
    "$COMPONENTS_URL") || true

  if ! [[ "$HTTP_CODE" =~ ^[0-9]{3}$ ]]; then
    warn_and_exit "Failed to fetch components (no HTTP response)."
  fi

  if [[ "$HTTP_CODE" -lt 200 || "$HTTP_CODE" -ge 300 ]]; then
    warn_and_exit "Failed to fetch components (HTTP $HTTP_CODE)."
  fi

  if ! jq -e '.items and (.items | type == "array")' "$PAGE_FILE" >/dev/null 2>&1; then
    warn_and_exit "Failed to parse component page payload."
  fi

  PAGE_COUNT=$(jq '.items | length' "$PAGE_FILE" 2>/dev/null || echo "0")
  if [[ "$PAGE_COUNT" == "0" ]]; then
    break
  fi

  jq -s '.[0] + .[1].items' "$COMPONENTS_FILE" "$PAGE_FILE" > "${COMPONENTS_FILE}.next"
  mv "${COMPONENTS_FILE}.next" "$COMPONENTS_FILE"

  NEXT_PAGE_TOKEN=$(jq -r '.next_page_token // empty' "$PAGE_FILE" 2>/dev/null || echo "")

  if [[ -z "$NEXT_PAGE_TOKEN" ]]; then
    break
  fi

  PAGE_TOKEN="$NEXT_PAGE_TOKEN"
  PAGE_INDEX=$((PAGE_INDEX + 1))
done

if [[ "$PAGE_INDEX" -gt "$MAX_PAGES" ]]; then
  echo "::warning::DT license check: Stopping pagination after MAX_PAGES=${MAX_PAGES}."
fi

echo "work_dir=$WORK_DIR" >> "$GITHUB_OUTPUT"
echo "ok=true" >> "$GITHUB_OUTPUT"
