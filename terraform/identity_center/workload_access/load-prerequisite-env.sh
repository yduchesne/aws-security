#!/usr/bin/env bash
# Source this script before operating the workload access Terraform root.

_identity_center_error() {
  printf 'ERROR: %s\n' "$*" >&2
}

_identity_center_main() {
  local script_dir
  local bootstrap_dir
  local landing_zone_arn
  local landing_zone_region
  local landing_zone_json
  local landing_zone_status
  local landing_zone_drift_status

  if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    _identity_center_error "This script must be sourced: source ./load-prerequisite-env.sh"
    return 2
  fi

  command -v terraform >/dev/null 2>&1 || {
    _identity_center_error "terraform is not installed or not in PATH."
    return 1
  }
  command -v aws >/dev/null 2>&1 || {
    _identity_center_error "AWS CLI is not installed or not in PATH."
    return 1
  }
  command -v jq >/dev/null 2>&1 || {
    _identity_center_error "jq is not installed or not in PATH."
    return 1
  }

  script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)" || return 1
  bootstrap_dir="${script_dir}/../../bootstrap"

  landing_zone_arn="$(terraform -chdir="$bootstrap_dir" output -raw landing_zone_arn 2>/dev/null)" || {
    _identity_center_error "Unable to read landing_zone_arn from initialized bootstrap state."
    return 1
  }
  if [[ ! "$landing_zone_arn" =~ ^arn:[^:]+:controltower:([^:]+):[0-9]{12}:landingzone/[A-Za-z0-9-]+$ ]]; then
    _identity_center_error "Bootstrap landing_zone_arn is empty or malformed: '${landing_zone_arn:-<empty>}'."
    return 1
  fi
  landing_zone_region="${BASH_REMATCH[1]}"
  landing_zone_json="$(aws --no-cli-pager controltower get-landing-zone --landing-zone-identifier "$landing_zone_arn" --region "$landing_zone_region" --output json)" || {
    _identity_center_error "Unable to retrieve the live Control Tower landing-zone status."
    return 1
  }
  landing_zone_status="$(jq -r '.landingZone.status // empty' <<<"$landing_zone_json")"
  landing_zone_drift_status="$(jq -r '.landingZone.driftStatus.status // empty' <<<"$landing_zone_json")"

  if [[ "$landing_zone_status" != "ACTIVE" || "$landing_zone_drift_status" != "IN_SYNC" ]]; then
    _identity_center_error "Landing zone must be ACTIVE and IN_SYNC; found status='${landing_zone_status}', drift='${landing_zone_drift_status}'."
    return 1
  fi

  printf 'Validated workload access prerequisites: landing zone is ACTIVE and IN_SYNC.\n'
}

_identity_center_status=0
_identity_center_main || _identity_center_status=$?
unset -f _identity_center_main _identity_center_error
return "$_identity_center_status" 2>/dev/null || exit "$_identity_center_status"
