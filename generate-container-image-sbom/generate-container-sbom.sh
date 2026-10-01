#!/usr/bin/env bash
# Skanner ett eller flere container-images med Syft og slår BOM-ene sammen
# til ett enkelt CycloneDX-dokument med cyclonedx-cli.
#
# Hvorfor sammenslåing før opplasting i stedet for flere opplastinger til
# samme DT-prosjekt: Dependency-Track reconciler komponentlisten til et
# prosjekt+versjon ved hver BOM-opplasting - den andre opplastingen ville
# overskrevet komponentene fra den første, ikke supplert dem.
set -euo pipefail

IMAGE_REFS="${IMAGE_REFS:?IMAGE_REFS må være satt}"
OUTPUT_BOM_NAME="${OUTPUT_BOM_NAME:-container-images-bom}"
SYFT_VERSION="${SYFT_VERSION:?SYFT_VERSION må være satt}"
CYCLONEDX_CLI_VERSION="${CYCLONEDX_CLI_VERSION:?CYCLONEDX_CLI_VERSION må være satt}"

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT
mkdir -p "$WORKDIR/bin"
export PATH="$WORKDIR/bin:$PATH"

echo "==> Installerer syft ${SYFT_VERSION}"
curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh \
  | sh -s -- -b "$WORKDIR/bin" "$SYFT_VERSION"

echo "==> Installerer cyclonedx-cli ${CYCLONEDX_CLI_VERSION}"
curl -sSfL -o "$WORKDIR/bin/cyclonedx" \
  "https://github.com/CycloneDX/cyclonedx-cli/releases/download/${CYCLONEDX_CLI_VERSION}/cyclonedx-linux-x64"
chmod +x "$WORKDIR/bin/cyclonedx"

# Dedupliser og fjern tomme linjer
mapfile -t REFS < <(printf '%s\n' "$IMAGE_REFS" | sed '/^[[:space:]]*$/d' | sort -u)

if [[ ${#REFS[@]} -eq 0 ]]; then
  echo "::error::Ingen image-referanser i IMAGE_REFS - ingenting å skanne"
  exit 1
fi

echo "==> Skanner ${#REFS[@]} unike image(r):"
printf '    - %s\n' "${REFS[@]}"

PARTIAL_FILES=()
i=0
for ref in "${REFS[@]}"; do
  i=$((i + 1))
  partial="$WORKDIR/partial-${i}.cdx.json"
  echo "==> [$i/${#REFS[@]}] syft scan ${ref}"
  syft scan "registry:${ref}" -o "cyclonedx-json=${partial}"
  PARTIAL_FILES+=("$partial")
done

mkdir -p "$WORKDIR/out"
MERGED_FILE="$WORKDIR/out/${OUTPUT_BOM_NAME}.json"

if [[ ${#PARTIAL_FILES[@]} -eq 1 ]]; then
  echo "==> Kun ett image - ingen sammenslåing nødvendig"
  cp "${PARTIAL_FILES[0]}" "$MERGED_FILE"
else
  echo "==> Slår sammen ${#PARTIAL_FILES[@]} BOM-er med cyclonedx-cli"
  cyclonedx merge \
    --input-files "${PARTIAL_FILES[@]}" \
    --output-file "$MERGED_FILE" \
    --output-format json
fi

# Flytt resultatet ut av $WORKDIR (som slettes av trap) til RUNNER_TEMP
FINAL_FILE="${RUNNER_TEMP:-/tmp}/${OUTPUT_BOM_NAME}.json"
cp "$MERGED_FILE" "$FINAL_FILE"

echo "bom_file=${FINAL_FILE}" >> "$GITHUB_OUTPUT"
echo "==> Skrev ${FINAL_FILE}"
