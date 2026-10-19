#!/usr/bin/env bash
# Tests for dt-license-check/license-rules.jq.
# Run: bash dt-license-check/test/license-rules.test.sh   (exit 0 only if every check passes)
set -uo pipefail
dir="$(cd "$(dirname "$0")/.." && pwd)"
[[ -f "$dir/license-rules.jq" ]] || { echo "FAIL: $dir/license-rules.jq not found"; exit 1; }
failures=0

check() { # $1 = name, $2 = expected output, $3 = jq expression that uses the rules
  local got
  got=$(jq -nr -L "$dir" "include \"license-rules\"; $3" 2>&1)
  if [[ "$got" == "$2" ]]; then
    echo "ok   $1"
  else
    echo "FAIL $1: expected '$2', got '$got'"
    failures=$((failures + 1))
  fi
}

# guess_category: fallback for licenses without a DT license group
check "LGPL-2.1 is weak copyleft"            "Weak Copyleft"  '"LGPL-2.1-only" | guess_category'
check "LGPL-3.0+ is weak copyleft"           "Weak Copyleft"  '"LGPL-3.0-or-later" | guess_category'
check "GPL is copyleft"                      "Copyleft"       '"GPL-3.0-only" | guess_category'
check "AGPL is copyleft"                     "Copyleft"       '"AGPL-3.0-only" | guess_category'
check "GPL AND LGPL stays copyleft"          "Copyleft"       '"GPL-2.0-or-later AND LGPL-2.1-or-later" | guess_category'
check "MPL is weak copyleft"                 "Weak Copyleft"  '"MPL-2.0" | guess_category'
check "MIT is permissive"                    "Permissive"     '"MIT" | guess_category'
check "Apache license name is permissive"    "Permissive"     '"The Apache Software License, Version 2.0" | guess_category'
check "0BSD is permissive"                   "Permissive"     '"0BSD" | guess_category'
check "CC-BY-NC is non-commercial"           "Non-Commercial" '"CC-BY-NC-4.0" | guess_category'
check "LicenseRef id is unknown"             "Unknown"        '"LicenseRef-Proprietary-Limited" | guess_category'
check "LicenseRef naming MIT is unknown"     "Unknown"        '"LicenseRef-MIT-Modified" | guess_category'
check "LicenseRef naming GPL stays copyleft" "Copyleft"       '"LicenseRef-GPL-2.0-custom" | guess_category'
check "LicenseRef in an expression is unknown" "Unknown"      '"MIT AND LicenseRef-Proprietary-1.0" | guess_category'
check "GPL with a LicenseRef stays copyleft" "Copyleft"       '"GPL-2.0-only AND LicenseRef-Custom" | guess_category'
check "mit inside a word is not MIT"         "Unknown"        '"Proprietary-Limited-1.0" | guess_category'
check "isc inside a word is not ISC"         "Unknown"        '"Discretionary-Use-1.0" | guess_category'
check "unknown id"                           "Unknown"        '"Foo-1.0" | guess_category'

# group_category: the most restrictive DT license group wins
check "no groups"                            ""               'group_category([])'
check "null groups"                          ""               'group_category(null)'
check "single group"                         "Permissive"     'group_category([{name: "Permissive"}])'
check "copyleft beats permissive"            "Copyleft"       'group_category([{name: "Permissive"}, {name: "Copyleft"}])'
check "custom group beats permissive"        "Forbidden"      'group_category([{name: "Permissive"}, {name: "Forbidden"}])'
check "custom group beats weak copyleft"     "Forbidden"      'group_category([{name: "Weak Copyleft"}, {name: "Forbidden"}])'
check "copyleft beats custom group"          "Copyleft"       'group_category([{name: "Copyleft"}, {name: "Forbidden"}])'
check "non-commercial beats copyleft"        "Non-Commercial" 'group_category([{name: "Copyleft"}, {name: "Non-Commercial"}])'

# instruction: one Norwegian text per category, used by both tables
check "permissive needs nothing"             "Ingen tiltak nødvendig"                 'instruction("Permissive"; "MIT")'
check "custom group needs review"            "Ukjent lisensgruppe - krever vurdering" 'instruction("Forbidden"; "X-1.0")'
check "unknown license needs check"          "Verifiser at det ikke kreves vurdering av lisensen" 'instruction("Permissive"; "UNKNOWN_LICENSE")'

# needs_review: the categories that the approval/review warning counts
check "copyleft is counted"                  "true"           'needs_review("Copyleft")'
check "non-commercial is counted"            "true"           'needs_review("Non-Commercial")'
check "custom group is counted"              "true"           'needs_review("Forbidden")'
check "weak copyleft is not counted"         "false"          'needs_review("Weak Copyleft")'
check "permissive is not counted"            "false"          'needs_review("Permissive")'
check "unknown is not counted (own warning)" "false"          'needs_review("Unknown")'

echo "$failures failure(s)"
[[ "$failures" -eq 0 ]]
