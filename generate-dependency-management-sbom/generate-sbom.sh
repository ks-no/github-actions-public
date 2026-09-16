#!/usr/bin/env bash
# Genererer en CycloneDX SBOM som dekker alt som er versjonspinnet i
# konsument-prosjektets <dependencyManagement>, inkludert det som kommer inn
# via importerte BOM-er (spring-boot-dependencies, jackson-bom, kotlin-bom,
# osv).
#
# Maven resolver aldri dependencyManagement-entries på egen hånd - de tas kun
# i bruk når en modul har en reell <dependency> som matcher. Derfor: hent ut
# effective-pom (der BOM-importer allerede er flatet ut), materialiser hver
# managed dependency som en ekte <dependency> i en pom.xml i et scratch-
# katalog, og kjør cyclonedx-maven-plugin direkte (uten lifecycle-binding)
# mot den i en egen mvn-prosess.
set -euo pipefail

MVN="${MVN:-mvn}"
WORKING_DIRECTORY="${WORKING_DIRECTORY:-.}"

cd "$WORKING_DIRECTORY"

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

echo "==> Henter effective POM (flater ut importerte BOM-er)"
$MVN -q -N help:effective-pom -Doutput="$WORKDIR/effective-pom.xml"

echo "==> Materialiserer dependencyManagement som ekte dependencies"
xsltproc \
  --stringparam sbomGroupId "$SBOM_GROUP_ID" \
  --stringparam sbomArtifactId "$SBOM_ARTIFACT_ID" \
  "${GITHUB_ACTION_PATH}/materialize-dependency-management.xsl" \
  "$WORKDIR/effective-pom.xml" > "$WORKDIR/pom.xml"

echo "==> Genererer CycloneDX SBOM (laster ned alle managed artefakter for hashing - kan ta flere minutter på kald cache)"
# outputName/outputFormat har ingen CLI-property-binding i cyclonedx-maven-
# plugin (verifisert mot plugin.xml for 2.9.1) - de kan kun settes via et
# <configuration>-element i en reell pom, ikke som -D på kommandolinjen. Ved
# direkte goal-kall uten en slik konfigurasjon skriver pluginen alltid
# target/bom.json + target/bom.xml; vi kopierer/omdøper resultatet selv i
# stedet for å stole på property-overstyring som blir stille ignorert.
$MVN -T 1C -f "$WORKDIR/pom.xml" \
  "org.cyclonedx:cyclonedx-maven-plugin:${CYCLONEDX_PLUGIN_VERSION}:makeBom"

mkdir -p target
cp "$WORKDIR/target/bom.json" "target/${OUTPUT_BOM_NAME}.json"

# bom_file skal være relativ til repo-roten (steget etterpå leser den derfra),
# ikke relativ til $WORKING_DIRECTORY som vi har cd-et inn i her.
if [[ "$WORKING_DIRECTORY" == "." ]]; then
  BOM_FILE="target/${OUTPUT_BOM_NAME}.json"
else
  BOM_FILE="${WORKING_DIRECTORY}/target/${OUTPUT_BOM_NAME}.json"
fi
echo "bom_file=${BOM_FILE}" >> "$GITHUB_OUTPUT"
echo "==> Skrev ${BOM_FILE}"
