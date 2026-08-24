#!/usr/bin/env bash
#
# Load values owned by terraform/bootstrap into the current shell for use by
# this Terraform root.
#
# Usage (must be sourced):
#   source ./load-prerequisite-env.sh
#
# Prerequisites:
# - terraform/bootstrap is initialized against its existing remote state.
# - The caller can read that state, list Organizations roots, and call Control
#   Tower ListBaselines and ListEnabledBaselines in the home Region.
# - AWS CLI v2 and jq are installed.

_load_bootstrap_env_error() {
  printf 'ERROR: %s\n' "$*" >&2
}

_load_bootstrap_env_output() {
  local bootstrap_dir="$1"
  local output_name="$2"
  local value
  local error_file
  local status

  error_file="$(mktemp)" || {
    _load_bootstrap_env_error "Unable to create a temporary file while reading bootstrap output '${output_name}'."
    return 1
  }

  value="$(terraform -chdir="$bootstrap_dir" output -raw "$output_name" 2>"$error_file")"
  status=$?

  if ((status != 0)); then
    _load_bootstrap_env_error \
      "Unable to read bootstrap Terraform output '${output_name}' from '${bootstrap_dir}'."
    _load_bootstrap_env_error \
      "Confirm that bootstrap is initialized against its existing backend and that your credentials can read and decrypt its state."
    if [[ -s "$error_file" ]]; then
      printf '%s\n' 'Terraform reported:' >&2
      while IFS= read -r line; do
        printf '  %s\n' "$line" >&2
      done <"$error_file"
    fi
    rm -f "$error_file"
    return "$status"
  fi

  rm -f "$error_file"

  # `terraform output -raw` normally emits an empty string for an empty value;
  # explicitly reject common textual null values as well.
  if [[ -z "${value//[[:space:]]/}" || "$value" == "null" || "$value" == "<nil>" ]]; then
    _load_bootstrap_env_error \
      "Bootstrap Terraform output '${output_name}' is null or empty. The completed bootstrap state must contain a non-empty '${output_name}' output."
    return 1
  fi

  printf '%s' "$value"
}

_load_bootstrap_env_aws_json() {
  local description="$1"
  shift

  local value
  local error_file
  local status

  error_file="$(mktemp)" || {
    _load_bootstrap_env_error "Unable to create a temporary file while ${description}."
    return 1
  }

  value="$(aws --no-cli-pager "$@" --output json 2>"$error_file")"
  status=$?

  if ((status != 0)); then
    _load_bootstrap_env_error "AWS CLI failed while ${description}."
    _load_bootstrap_env_error \
      "Confirm that the active credentials are for the Organizations management account and permit organizations:ListRoots, controltower:ListBaselines, and controltower:ListEnabledBaselines."
    if [[ -s "$error_file" ]]; then
      printf '%s\n' 'AWS CLI reported:' >&2
      while IFS= read -r line; do
        printf '  %s\n' "$line" >&2
      done <"$error_file"
    fi
    rm -f "$error_file"
    return "$status"
  fi

  rm -f "$error_file"

  if [[ -z "${value//[[:space:]]/}" || "$value" == "null" ]]; then
    _load_bootstrap_env_error "AWS CLI returned a null or empty response while ${description}."
    return 1
  fi

  printf '%s' "$value"
}

_load_bootstrap_env_main() {
  local script_dir
  local bootstrap_dir
  local organization_root_id
  local landing_zone_arn
  local landing_zone_drift_status
  local landing_zone_partition
  local landing_zone_region
  local landing_zone_account_id
  local caller_account_id
  local organization_roots_json
  local matching_organization_roots_json
  local matching_organization_root_count
  local organization_root_arn
  local organization_id
  local management_account_arn
  local baselines_json
  local identity_center_baseline_arns_json
  local identity_center_baseline_count
  local identity_center_baseline_arn
  local enabled_baselines_json
  local matching_enabled_baselines_json
  local matching_enabled_baseline_count
  local identity_center_enabled_baseline_arn
  local identity_center_enabled_baseline_status

  if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    _load_bootstrap_env_error \
      "This script must be sourced so its exported variables remain in the current shell."
    _load_bootstrap_env_error \
      "Run: source ./load-prerequisite-env.sh"
    return 2
  fi

  if ! command -v terraform >/dev/null 2>&1; then
    _load_bootstrap_env_error \
      "The 'terraform' executable was not found in PATH. Install Terraform before sourcing this script."
    return 1
  fi

  if ! command -v aws >/dev/null 2>&1; then
    _load_bootstrap_env_error \
      "The 'aws' executable was not found in PATH. Install AWS CLI v2 before sourcing this script."
    return 1
  fi

  if ! aws --version 2>&1 | grep -q '^aws-cli/2\.'; then
    _load_bootstrap_env_error \
      "AWS CLI v2 is required to discover the enabled Identity Center baseline."
    return 1
  fi

  if ! command -v jq >/dev/null 2>&1; then
    _load_bootstrap_env_error \
      "The 'jq' executable was not found in PATH. Install jq before sourcing this script."
    return 1
  fi

  script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)" || {
    _load_bootstrap_env_error "Unable to resolve the org_unit script directory."
    return 1
  }
  bootstrap_dir="${script_dir}/../../bootstrap"

  if [[ ! -d "$bootstrap_dir" ]]; then
    _load_bootstrap_env_error \
      "Expected bootstrap Terraform directory '${bootstrap_dir}' does not exist."
    return 1
  fi

  organization_root_id="$(_load_bootstrap_env_output "$bootstrap_dir" organization_root_id)" || return $?
  landing_zone_arn="$(_load_bootstrap_env_output "$bootstrap_dir" landing_zone_arn)" || return $?
  landing_zone_drift_status="$(_load_bootstrap_env_output "$bootstrap_dir" landing_zone_drift_status)" || return $?

  if [[ ! "$organization_root_id" =~ ^r-[a-z0-9]{4,32}$ ]]; then
    _load_bootstrap_env_error \
      "Bootstrap output 'organization_root_id' has unexpected value '${organization_root_id}'; expected an AWS Organizations root ID such as 'r-abcd'."
    return 1
  fi

  if [[ ! "$landing_zone_arn" =~ ^arn:[^:]+:controltower:[^:]+:[0-9]{12}:landingzone/[A-Za-z0-9-]+$ ]]; then
    _load_bootstrap_env_error \
      "Bootstrap output 'landing_zone_arn' has unexpected value '${landing_zone_arn}'; expected a Control Tower landing-zone ARN."
    return 1
  fi

  if [[ "$landing_zone_drift_status" != "IN_SYNC" ]]; then
    _load_bootstrap_env_error \
      "Bootstrap output 'landing_zone_drift_status' is '${landing_zone_drift_status}', not 'IN_SYNC'. Resolve Control Tower drift before operating the AFT org_unit root."
    return 1
  fi

  IFS=: read -r _ landing_zone_partition _ landing_zone_region landing_zone_account_id _ <<<"$landing_zone_arn"

  caller_account_id="$(_load_bootstrap_env_aws_json \
    "checking the active AWS account" \
    sts get-caller-identity \
    --query Account)" || return $?
  caller_account_id="$(jq -r '.' <<<"$caller_account_id")" || return 1

  if [[ "$caller_account_id" != "$landing_zone_account_id" ]]; then
    _load_bootstrap_env_error \
      "The active AWS credentials belong to account '${caller_account_id}', but the landing zone belongs to management account '${landing_zone_account_id}'."
    return 1
  fi

  organization_roots_json="$(_load_bootstrap_env_aws_json \
    "listing AWS Organizations roots" \
    organizations list-roots)" || return $?

  matching_organization_roots_json="$(
    jq -c \
      --arg root_id "$organization_root_id" \
      '[.Roots[]? | select(.Id == $root_id)]' <<<"$organization_roots_json"
  )" || {
    _load_bootstrap_env_error "Unable to parse the AWS Organizations roots returned by AWS."
    return 1
  }
  matching_organization_root_count="$(jq 'length' <<<"$matching_organization_roots_json")"

  if [[ "$matching_organization_root_count" -ne 1 ]]; then
    _load_bootstrap_env_error \
      "Expected exactly one AWS Organizations root with ID '${organization_root_id}', but found ${matching_organization_root_count}."
    return 1
  fi

  organization_root_arn="$(jq -r '.[0].Arn // empty' <<<"$matching_organization_roots_json")"
  if [[ ! "$organization_root_arn" =~ ^arn:${landing_zone_partition}:organizations::${landing_zone_account_id}:root/(o-[a-z0-9]{10,32})/${organization_root_id}$ ]]; then
    _load_bootstrap_env_error \
      "The discovered Organizations root ARN '${organization_root_arn:-<empty>}' is malformed or does not match root '${organization_root_id}' and management account '${landing_zone_account_id}'."
    return 1
  fi

  organization_id="${BASH_REMATCH[1]}"
  management_account_arn="arn:${landing_zone_partition}:organizations::${landing_zone_account_id}:account/${organization_id}/${landing_zone_account_id}"

  baselines_json="$(_load_bootstrap_env_aws_json \
    "listing Control Tower baseline definitions in Region '${landing_zone_region}'" \
    controltower list-baselines \
    --region "$landing_zone_region")" || return $?

  identity_center_baseline_arns_json="$(
    jq -c '[.baselines[]? | select(.name == "IdentityCenterBaseline") | .arn]' <<<"$baselines_json"
  )" || {
    _load_bootstrap_env_error "Unable to parse the Control Tower baseline definitions returned by AWS."
    return 1
  }
  identity_center_baseline_count="$(jq 'length' <<<"$identity_center_baseline_arns_json")"

  if [[ "$identity_center_baseline_count" -ne 1 ]]; then
    _load_bootstrap_env_error \
      "Expected exactly one IdentityCenterBaseline definition in Region '${landing_zone_region}', but found ${identity_center_baseline_count}."
    _load_bootstrap_env_error \
      "Inspect the response with: aws controltower list-baselines --region '${landing_zone_region}'"
    return 1
  fi

  identity_center_baseline_arn="$(jq -r '.[0]' <<<"$identity_center_baseline_arns_json")"

  enabled_baselines_json="$(_load_bootstrap_env_aws_json \
    "listing enabled Control Tower baselines in Region '${landing_zone_region}'" \
    controltower list-enabled-baselines \
    --region "$landing_zone_region")" || return $?

  matching_enabled_baselines_json="$(
    jq -c \
      --arg baseline "$identity_center_baseline_arn" \
      --arg target "$management_account_arn" \
      '[.enabledBaselines[]? | select(
        .baselineIdentifier == $baseline and .targetIdentifier == $target
      )]' <<<"$enabled_baselines_json"
  )" || {
    _load_bootstrap_env_error "Unable to parse the enabled Control Tower baselines returned by AWS."
    return 1
  }
  matching_enabled_baseline_count="$(jq 'length' <<<"$matching_enabled_baselines_json")"

  if [[ "$matching_enabled_baseline_count" -ne 1 ]]; then
    _load_bootstrap_env_error \
      "Expected exactly one IdentityCenterBaseline enabled for management account '${management_account_arn}', but found ${matching_enabled_baseline_count}."
    _load_bootstrap_env_error \
      "Inspect the response with: aws controltower list-enabled-baselines --region '${landing_zone_region}'"
    return 1
  fi

  identity_center_enabled_baseline_arn="$(jq -r '.[0].arn // empty' <<<"$matching_enabled_baselines_json")"
  identity_center_enabled_baseline_status="$(jq -r '.[0].statusSummary.status // empty' <<<"$matching_enabled_baselines_json")"

  if [[ "$identity_center_enabled_baseline_status" != "SUCCEEDED" ]]; then
    _load_bootstrap_env_error \
      "The enabled IdentityCenterBaseline has status '${identity_center_enabled_baseline_status:-<empty>}', not 'SUCCEEDED'. Wait for or repair baseline enablement before operating the AFT org_unit root."
    return 1
  fi

  if [[ ! "$identity_center_enabled_baseline_arn" =~ ^arn:${landing_zone_partition}:controltower:${landing_zone_region}:${landing_zone_account_id}:enabledbaseline/[A-Za-z0-9-]+$ ]]; then
    _load_bootstrap_env_error \
      "The discovered enabled IdentityCenterBaseline ARN '${identity_center_enabled_baseline_arn:-<empty>}' is malformed or does not belong to the expected partition, Region, and management account."
    return 1
  fi

  export TF_VAR_organization_root_id="$organization_root_id"
  export TF_VAR_landing_zone_arn="$landing_zone_arn"
  export TF_VAR_landing_zone_drift_status="$landing_zone_drift_status"
  export TF_VAR_identity_center_enabled_baseline_arn="$identity_center_enabled_baseline_arn"

  printf 'Loaded and validated bootstrap and Control Tower values:\n'
  printf '  TF_VAR_organization_root_id=%s\n' "$TF_VAR_organization_root_id"
  printf '  TF_VAR_landing_zone_arn=%s\n' "$TF_VAR_landing_zone_arn"
  printf '  TF_VAR_landing_zone_drift_status=%s\n' "$TF_VAR_landing_zone_drift_status"
  printf '  TF_VAR_identity_center_enabled_baseline_arn=%s\n' "$TF_VAR_identity_center_enabled_baseline_arn"
}

_load_bootstrap_env_status=0
_load_bootstrap_env_main || _load_bootstrap_env_status=$?
unset -f _load_bootstrap_env_main _load_bootstrap_env_aws_json _load_bootstrap_env_output _load_bootstrap_env_error
return "$_load_bootstrap_env_status" 2>/dev/null || exit "$_load_bootstrap_env_status"
