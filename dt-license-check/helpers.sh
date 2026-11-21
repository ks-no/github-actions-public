# shellcheck shell=bash
# Functions shared by the dt-license-check scripts. Sourced by each script;
# defines functions only.

escape_workflow_value() {
  local value="$1"
  value="${value//'%'/'%25'}"
  value="${value//$'\r'/'%0D'}"
  value="${value//$'\n'/'%0A'}"
  printf '%s' "$value"
}

# Gives a warning and ends the script with exit 0, so the job goes on.
warn_and_exit() {
  local message="$1"
  local escaped_message
  escaped_message=$(escape_workflow_value "$message")
  echo "::warning::DT license check: ${escaped_message}"
  exit 0
}
