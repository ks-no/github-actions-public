#!/usr/bin/env bash
set -euo pipefail

for var in FIKS_URL FIKS_TEAM FIKS_APP FIKS_ENVIRONMENT FIKS_FILE FIKS_AUDIENCE; do
	[[ -n "${!var:-}" ]] || { echo "::error::$var mangler."; exit 1; }
done
if [[ -z "${ACTIONS_ID_TOKEN_REQUEST_URL:-}" || -z "${ACTIONS_ID_TOKEN_REQUEST_TOKEN:-}" ]]; then
	echo "::error::Fant ikke OIDC-tokenet til GitHub Actions. Jobben trenger permissions: id-token: write."
	exit 1
fi
[[ -r "$FIKS_FILE" ]] || { echo "::error::Fant ikke $FIKS_FILE."; exit 1; }
case "${FIKS_MODE:-submit}" in
	submit) path="/api/v1/fiks-yaml" ;;
	plan) path="/api/v1/fiks-yaml/plan" ;;
	*) echo "::error::mode må være submit eller plan, ikke «${FIKS_MODE}»."; exit 1 ;;
esac
if [[ "${FIKS_MODE:-submit}" == "submit" && -z "${FIKS_NAIS_FILE:-}" ]]; then
	echo "::error::nais_file må være satt i mode submit. Tjenesten sjekker at spec.envFrom har secretene den lager."
	exit 1
fi
nais_args=(--arg naisYaml "")
if [[ -n "${FIKS_NAIS_FILE:-}" ]]; then
	[[ -r "$FIKS_NAIS_FILE" ]] || { echo "::error::Fant ikke $FIKS_NAIS_FILE. Sett nais_file til stien til nais.yaml."; exit 1; }
	nais_args=(--rawfile naisYaml "$FIKS_NAIS_FILE")
fi

token="$(curl -sS --fail --max-time 30 -G -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
	--data-urlencode "audience=$FIKS_AUDIENCE" "$ACTIONS_ID_TOKEN_REQUEST_URL" | jq -r '.value // empty')"
[[ -n "$token" ]] || { echo "::error::Fikk ikke OIDC-token fra GitHub Actions."; exit 1; }
echo "::add-mask::$token"

response="$(mktemp)"
trap 'rm -f "$response"' EXIT
status="$(jq -n --arg team "$FIKS_TEAM" --arg app "$FIKS_APP" --arg environment "$FIKS_ENVIRONMENT" --rawfile fiksYaml "$FIKS_FILE" \
	"${nais_args[@]}" \
	'{team: $team, app: $app, environment: $environment, fiksYaml: $fiksYaml} + (if $naisYaml == "" then {} else {naisYaml: $naisYaml} end)' |
	curl -sS --max-time 60 -o "$response" -w '%{http_code}' -H "Authorization: Bearer $token" -H 'Content-Type: application/json' \
		--data-binary @- "${FIKS_URL%/}$path")"

echo "nais-provisioner svarte HTTP $status"
stop_token="$(openssl rand -hex 16)"
echo "::stop-commands::$stop_token"
jq . "$response" 2>/dev/null || cat "$response"
printf '\n::%s::\n' "$stop_token"

if ((status < 200 || status >= 300)); then
	message="$(jq -r '.detail // ((.errors // []) | join(" ")) // empty' "$response" 2>/dev/null || true)"
	message="${message//%/%25}"
	message="${message//$'\r'/%0D}"
	message="${message//$'\n'/%0A}"
	echo "::error::fiks.yaml ble ikke godtatt (HTTP $status): ${message:-se svaret over}"
	exit 1
fi
