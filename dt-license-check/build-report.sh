#!/usr/bin/env bash
# Builds the license report: job summary, outputs and warnings.
# Runs as a step in dt-license-check/action.yml.
set -euo pipefail

# shellcheck source=helpers.sh
source "$GITHUB_ACTION_PATH/helpers.sh"

# A command that fails gives a warning instead of failing the job: the
# license check must never stop the pipeline.
trap 'warn_and_exit "Unexpected error while generating license inventory."' ERR

COMPONENTS_FILE="$WORK_DIR/components.json"
LICENSE_INFO_MAP_FILE="$WORK_DIR/license-info-map.json"
TOTAL_COMPONENTS=$(jq 'length' "$COMPONENTS_FILE")
NORMALIZED_FILE="$WORK_DIR/normalized.json"

# Normalize components with DT-sourced license categories.
# The license map goes to jq through a file: as one command-line argument,
# a large license catalogue exceeds the kernel limit ("Argument list too long").
jq -L "$GITHUB_ACTION_PATH" --slurpfile licenseInfoMaps "$LICENSE_INFO_MAP_FILE" '
  include "license-rules";

  ($licenseInfoMaps[0] // {}) as $licenseInfoMap
  | map(
    ((.resolved_license.license_id // .license // "UNKNOWN_LICENSE") | tostring) as $lic
    | ($licenseInfoMap[$lic] // {}) as $info
    | (($info.name // "") | tostring) as $licenseName
    | (if $lic == "UNKNOWN_LICENSE" then "Unknown"
       elif ($info.category // "") != "" then $info.category
       else $lic | guess_category
       end) as $category
    | {
      name: ((.name // "UNKNOWN_COMPONENT") | tostring),
      version: ((.version // "UNKNOWN_VERSION") | tostring),
      license: $lic,
      category: $category,
      explanation: (
        if ($info.explanation // "") != "" then
          "License "
          + (if $licenseName != "" then $licenseName + " (" + $lic + ")" else $lic end)
          + ": "
          + $info.explanation
        elif ($lic == "UNKNOWN_LICENSE" or $category == "Unknown") then
          "No explanation found in Dependency-Track. Classify this license in the catalog."
        elif ($category == "Non-Commercial") then
          "License is marked non-commercial; approval is required before use in production."
        elif ($category == "Copyleft") then
          "Copyleft obligations may apply; review redistribution requirements before release."
        elif ($category == "Weak Copyleft") then
          "Weak copyleft obligations may apply; verify linking and distribution requirements."
        else
          "No additional license explanation available in Dependency-Track."
        end
      ),
      instruction: instruction($category; $lic)
    }
  )
' "$COMPONENTS_FILE" > "$NORMALIZED_FILE"

UNKNOWN_LICENSE_COUNT=$(jq '[.[] | select(.category == "Unknown")] | length' "$NORMALIZED_FILE")
REVIEW_LICENSE_COUNT=$(jq -L "$GITHUB_ACTION_PATH" 'include "license-rules"; [.[] | select(needs_review(.category))] | length' "$NORMALIZED_FILE")

PROJECT_URL="$DT_BASE_URL/projects/$DT_PROJECT_UUID"

{
  echo ""
  echo "### License Check - ${DT_PROJECT_NAME} (${DT_PROJECT_VERSION})"
  echo ""
  echo "- Total components: ${TOTAL_COMPONENTS}"
  echo "- Unknown licenses: ${UNKNOWN_LICENSE_COUNT}"
  echo "- Project: [View in Dependency-Track](${PROJECT_URL})"
  echo ""
  echo "| Category | License | Components | Instruction |"
  echo "|----------|---------|-----------:|-------------|"
  jq -r -L "$GITHUB_ACTION_PATH" '
    include "license-rules";

    sort_by(.category, .license, .name)
    | group_by([.category, .license])
    | map("| " + (.[0].category | clean_md) + " | " + (.[0].license | clean_md) + " | " + (length | tostring) + " | " + .[0].instruction + " |")
    | .[]
  ' "$NORMALIZED_FILE"
  echo ""
  echo "#### Components By License"
} >> "$GITHUB_STEP_SUMMARY"

DETAIL_LIMIT="$MAX_DETAIL_ROWS"
if ! [[ "$DETAIL_LIMIT" =~ ^[0-9]+$ ]]; then
  DETAIL_LIMIT=400
fi

if [[ "$TOTAL_COMPONENTS" -le "$DETAIL_LIMIT" ]]; then
  jq -r -L "$GITHUB_ACTION_PATH" --arg dtBaseUrl "$DT_BASE_URL" '
    include "license-rules";

    sort_by(.category, .license, .name)
    | group_by([.category, .license])
    | .[]
    | "<details>\n<summary>" + (.[0].category | clean_md) + " | " + (.[0].license | clean_md) + " (" + (length | tostring) + ")</summary>\n\n"
      + "License explanation: " + (.[0].explanation | clean_md) + "\n\n"
      + (if .[0].license == "UNKNOWN_LICENSE" then ""
         else "\n\nFull license text: [View in Dependency-Track](" + $dtBaseUrl + "/licenses/" + (.[0].license | @uri) + "/licenseText)\n\n"
         end)
      + (map("- " + (.name | clean_md) + " (" + (.version | clean_md) + ")") | unique | join("\n"))
      + "\n\nInstruction: " + .[0].instruction + "\n\n</details>\n"
  ' "$NORMALIZED_FILE" >> "$GITHUB_STEP_SUMMARY"
else
  {
    echo ""
    echo "> Detailed per-component list omitted because total components (${TOTAL_COMPONENTS}) exceeds max_detail_rows (${DETAIL_LIMIT})."
    echo "> Increase max_detail_rows to include expandable component sections in the summary."
  } >> "$GITHUB_STEP_SUMMARY"
fi

if [[ "$UNKNOWN_LICENSE_COUNT" -gt 0 ]]; then
  SAFE_PROJECT_NAME=$(escape_workflow_value "$DT_PROJECT_NAME")
  echo "::warning::DT license check: ${UNKNOWN_LICENSE_COUNT} component(s) have unknown licenses in ${SAFE_PROJECT_NAME}"
fi

# Non-Commercial, Copyleft and custom DT license groups need approval or review.
if [[ "$REVIEW_LICENSE_COUNT" -gt 0 ]]; then
  SAFE_PROJECT_NAME=$(escape_workflow_value "$DT_PROJECT_NAME")
  echo "::warning::DT license check: ${REVIEW_LICENSE_COUNT} component(s) need license approval or review in ${SAFE_PROJECT_NAME}"
fi

# Written last: if anything above fails, the outputs stay empty and the
# action reports 0 (see outputs in action.yml).
echo "total_components=$TOTAL_COMPONENTS" >> "$GITHUB_OUTPUT"
echo "unknown_license_count=$UNKNOWN_LICENSE_COUNT" >> "$GITHUB_OUTPUT"
