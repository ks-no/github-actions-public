# License rules shared by the jq programs in dt-license-check/action.yml.
# Load with: jq -L "$GITHUB_ACTION_PATH" 'include "license-rules"; ...'
# Tests: bash dt-license-check/test/license-rules.test.sh

# Category from a license's DT license groups. The most restrictive group wins:
# Non-Commercial, then Copyleft, then any custom group (these rules do not know
# it, so it must be reviewed), then Weak Copyleft, then Permissive.
# Returns "" when the license is in no group.
def group_category($groups):
  [($groups // [])[]? | objects | .name // empty | tostring | select(. != "")] as $names
  | (["Non-Commercial", "Copyleft"] | map(select(. as $g | $names | any(. == $g))) | first)
    // ($names | map(select(. as $n | ["Non-Commercial", "Copyleft", "Weak Copyleft", "Permissive"] | any(. == $n) | not)) | first)
    // (["Weak Copyleft", "Permissive"] | map(select(. as $g | $names | any(. == $g))) | first)
    // "";

# Fallback for licenses that DT has not grouped: guess the category from the
# license id or name. The most restrictive match comes first:
# - "agpl|(^|[^l])gpl" finds GPL but not the "gpl" inside "lgpl", so
#   "GPL-2.0-or-later AND LGPL-2.1-or-later" stays Copyleft.
# - Other LicenseRef- ids are custom licenses: Unknown, so they get checked.
#   This also holds inside an expression: "MIT AND LicenseRef-X" is Unknown.
# - Permissive names count only as whole words ("Limited" does not contain MIT).
def guess_category:
  ascii_downcase as $v
  | if ($v | test("non-?commercial|by-?nc")) then "Non-Commercial"
    elif ($v | test("agpl|(^|[^l])gpl")) then "Copyleft"
    elif ($v | test("(^|[^a-z0-9])licenseref-")) then "Unknown"
    elif ($v | test("lgpl|epl|mpl|cddl")) then "Weak Copyleft"
    elif ($v | test("(^|[^a-z0-9])(apache|mit|bsd|isc|cc0|unlicense|public.?domain|boost|zlib|wtfpl|0bsd)([^a-z0-9]|$)")) then "Permissive"
    else "Unknown"
    end;

# What the reader must do, in Norwegian. Both summary tables use it. Only
# Permissive needs no action; anything not recognised (including custom DT
# groups) asks for review.
def instruction($category; $license):
  if ($license == "UNKNOWN_LICENSE" or $category == "Unknown") then "Verifiser at det ikke kreves vurdering av lisensen"
  elif $category == "Non-Commercial" then "Krever godkjenning av team sikkerhet"
  elif $category == "Copyleft" then "Krever gjennomgang og godkjenning av lisens før prodsetting"
  elif $category == "Weak Copyleft" then "Gjennomgå lisenser og vurder om tiltak er nødvendig"
  elif $category == "Permissive" then "Ingen tiltak nødvendig"
  else "Ukjent lisensgruppe - krever vurdering"
  end;

# True for the categories that need approval or review before production:
# Non-Commercial, Copyleft and custom DT groups. Unknown licenses have their
# own warning. Weak Copyleft and Permissive are not counted.
def needs_review($category):
  ["Unknown", "Weak Copyleft", "Permissive"] | any(. == $category) | not;
