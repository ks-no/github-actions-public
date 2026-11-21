#!/usr/bin/env bash
# Fetches the DT license catalogue and builds $WORK_DIR/license-info-map.json.
# Runs as a step in dt-license-check/action.yml.
set -euo pipefail

# shellcheck source=helpers.sh
source "$GITHUB_ACTION_PATH/helpers.sh"

# A command that fails gives a warning instead of failing the job: the
# license check must never stop the pipeline.
trap 'warn_and_exit "Unexpected error while generating license inventory."' ERR

COMPONENTS_FILE="$WORK_DIR/components.json"

# Keep catalog lookup on v1 until a v2 license listing endpoint is available.
DT_LICENSES_FILE="$WORK_DIR/licenses.json"
DT_LICENSES_HEADERS_FILE="$WORK_DIR/licenses-headers.txt"
LICENSE_PAGE_SIZE=1000
# The catalogue holds every license text, so it can be large: allow 60 s.
# If it times out, DT's license groups are lost and the regex fallback is used.
LICENSES_HTTP=$(curl -sS -D "$DT_LICENSES_HEADERS_FILE" -o "$DT_LICENSES_FILE" -w '%{http_code}' \
  --connect-timeout 10 --max-time 60 \
  -H "X-Api-Key: $DT_API_KEY" \
  "$DT_BASE_URL/api/v1/license?pageSize=$LICENSE_PAGE_SIZE&sortName=licenseId&sortOrder=asc") || true

if [[ "$LICENSES_HTTP" =~ ^2[0-9]{2}$ ]]; then
  LICENSE_COUNT=$(jq 'length' "$DT_LICENSES_FILE" 2>/dev/null || echo "0")
  LICENSE_TOTAL_HEADER=$(awk -F': ' 'tolower($1)=="x-total-count" {gsub("\r", "", $2); print $2}' "$DT_LICENSES_HEADERS_FILE" | tail -n1)
  if [[ "$LICENSE_TOTAL_HEADER" =~ ^[0-9]+$ ]] && [[ "$LICENSE_TOTAL_HEADER" -gt "$LICENSE_PAGE_SIZE" ]]; then
    echo "::warning::DT license check: License catalog appears truncated (X-Total-Count=${LICENSE_TOTAL_HEADER}, pageSize=${LICENSE_PAGE_SIZE})."
  elif [[ "$LICENSE_COUNT" -eq "$LICENSE_PAGE_SIZE" ]]; then
    echo "::warning::DT license check: License catalog may be truncated at pageSize=${LICENSE_PAGE_SIZE}."
  fi
  LICENSE_INFO_MAP=$(jq -L "$GITHUB_ACTION_PATH" '
    include "license-rules";

    map({
      key: (.licenseId // ""),
      value: {
        category: group_category(.licenseGroups),
        name: ((.name // "") | tostring),
        explanation: ((.licenseText // .licenseComments // .standardLicenseHeader // "") | short_license_text)
      }
    })
    | map(select(.key != ""))
    | from_entries
  ' "$DT_LICENSES_FILE" 2>/dev/null || echo '{}')

  # Enrich explanations from per-license detail endpoint for licenses used by this project.
  # This improves summary quality when catalog entries have empty/truncated explanation fields.
  LICENSE_TEXT_FETCH_LIMIT=25
  UNIQUE_LICENSES_FILE="$WORK_DIR/unique-licenses.txt"
  DETAIL_FILE="$WORK_DIR/license-detail.json"
  jq -r '
    map((.resolved_license.license_id // .license // "UNKNOWN_LICENSE") | tostring)
    | unique
    | .[]
    | select(. != "" and . != "UNKNOWN_LICENSE")
  ' "$COMPONENTS_FILE" > "$UNIQUE_LICENSES_FILE"

  UNIQUE_LICENSE_COUNT=$(wc -l < "$UNIQUE_LICENSES_FILE" | tr -d ' ')
  FETCHED_LICENSE_COUNT=0

  if [[ "$UNIQUE_LICENSE_COUNT" -gt "$LICENSE_TEXT_FETCH_LIMIT" ]]; then
    echo "::warning::DT license check: Limiting per-license text enrichment to ${LICENSE_TEXT_FETCH_LIMIT} of ${UNIQUE_LICENSE_COUNT} unique licenses."
  fi

  while IFS= read -r LICENSE_ID; do
    if [[ "$FETCHED_LICENSE_COUNT" -ge "$LICENSE_TEXT_FETCH_LIMIT" ]]; then
      break
    fi
    if [[ -z "$LICENSE_ID" ]]; then
      continue
    fi

    ENCODED_LICENSE_ID=$(jq -rn --arg v "$LICENSE_ID" '$v | @uri')
    # curl writes the file only when data arrives, so clear the previous license first.
    : > "$DETAIL_FILE"
    DETAIL_HTTP=$(curl -sS -o "$DETAIL_FILE" -w '%{http_code}' \
      --connect-timeout 10 --max-time 30 \
      -H "X-Api-Key: $DT_API_KEY" \
      "$DT_BASE_URL/api/v1/license/$ENCODED_LICENSE_ID") || true

    if [[ "$DETAIL_HTTP" =~ ^2[0-9]{2}$ ]]; then
      DETAIL_TEXT=$(jq -r -L "$GITHUB_ACTION_PATH" 'include "license-rules"; (.licenseText // "") | short_license_text' \
        "$DETAIL_FILE" 2>/dev/null || echo "")
      DETAIL_NAME=$(jq -r '(.name // "") | tostring' "$DETAIL_FILE" 2>/dev/null || echo "")

      if [[ -n "$DETAIL_TEXT" ]]; then
        LICENSE_INFO_MAP=$(jq -c --arg k "$LICENSE_ID" --arg nm "$DETAIL_NAME" --arg exp "$DETAIL_TEXT" '
          .[$k] = (
            (.[$k] // {category:"", name:"", explanation:""})
            | .name = (if $nm != "" then $nm else (.name // "") end)
            | .explanation = $exp
          )
        ' <<< "$LICENSE_INFO_MAP" 2>/dev/null || echo "$LICENSE_INFO_MAP")
      fi
    fi

    FETCHED_LICENSE_COUNT=$((FETCHED_LICENSE_COUNT + 1))
  done < "$UNIQUE_LICENSES_FILE"
else
  # curl reports 000 when no HTTP response arrived (connection error or timeout).
  if [[ "$LICENSES_HTTP" =~ ^[1-5][0-9]{2}$ ]]; then
    LICENSES_RESULT="HTTP $LICENSES_HTTP"
  else
    LICENSES_RESULT="no HTTP response"
  fi
  echo "::warning::DT license check: Failed to fetch license catalog (${LICENSES_RESULT}), falling back to regex-based categorization."
  LICENSE_INFO_MAP='{}'
fi

# The report step reads the license map from this file.
LICENSE_INFO_MAP_FILE="$WORK_DIR/license-info-map.json"
printf '%s' "$LICENSE_INFO_MAP" > "$LICENSE_INFO_MAP_FILE"
echo "ok=true" >> "$GITHUB_OUTPUT"
