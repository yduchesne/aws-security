#!/usr/bin/env bash
# Source this script before operating the persistent lab evidence Terraform root.

_lab_evidence_error() {
  printf 'ERROR: %s\n' "$*" >&2
}

_lab_evidence_main() {
  local script_dir
  local bootstrap_dir
  local landing_zone_arn
  local landing_zone_region
  local landing_zone_json
  local landing_zone_status
  local landing_zone_drift_status

  if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    _lab_evidence_error "This script must be sourced: source ./load-prerequisite-env.sh"
    return 2
  fi

  command -v terraform >/dev/null 2>&1 || {
    _lab_evidence_error "terraform is not installed or not in PATH."
    return 1
  }
  command -v aws >/dev/null 2>&1 || {
    _lab_evidence_error "AWS CLI is not installed or not in PATH."
    return 1
  }
  command -v jq >/dev/null 2>&1 || {
    _lab_evidence_error "jq is not installed or not in PATH."
    return 1
  }

  script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)" || return 1
  bootstrap_dir="${script_dir}/../../bootstrap"

  landing_zone_arn="$(terraform -chdir="$bootstrap_dir" output -raw landing_zone_arn 2>/dev/null)" || {
    _lab_evidence_error "Unable to read landing_zone_arn from initialized bootstrap state."
    return 1
  }
  if [[ ! "$landing_zone_arn" =~ ^arn:[^:]+:controltower:([^:]+):[0-9]{12}:landingzone/[A-Za-z0-9-]+$ ]]; then
    _lab_evidence_error "Bootstrap landing_zone_arn is empty or malformed: '${landing_zone_arn:-<empty>}'."
    return 1
  fi

  landing_zone_region="${BASH_REMATCH[1]}"
  landing_zone_json="$(aws --no-cli-pager controltower get-landing-zone --landing-zone-identifier "$landing_zone_arn" --region "$landing_zone_region" --output json)" || {
    _lab_evidence_error "Unable to retrieve the live Control Tower landing-zone status."
    return 1
  }
  landing_zone_status="$(jq -r '.landingZone.status // empty' <<<"$landing_zone_json")"
  landing_zone_drift_status="$(jq -r '.landingZone.driftStatus.status // empty' <<<"$landing_zone_json")"

  if [[ "$landing_zone_status" != "ACTIVE" || "$landing_zone_drift_status" != "IN_SYNC" ]]; then
    _lab_evidence_error "Landing zone must be ACTIVE and IN_SYNC; found status='${landing_zone_status}', drift='${landing_zone_drift_status}'."
    return 1
  fi

  [[ "${TF_VAR_lab_account_ids:-}" == *'"dev"'* && "${TF_VAR_lab_account_ids:-}" == *'"test"'* ]] || {
    _lab_evidence_error "TF_VAR_lab_account_ids must contain the Dev Lab and Test Lab account IDs."
    return 1
  }

  printf 'Validated lab evidence prerequisites: landing zone is ACTIVE and IN_SYNC.\n'
}

_lab_evidence_status=0
_lab_evidence_main || _lab_evidence_status=$?
unset -f _lab_evidence_main _lab_evidence_error
return "$_lab_evidence_status" 2>/dev/null || exit "$_lab_evidence_status"
