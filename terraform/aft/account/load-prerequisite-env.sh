#!/usr/bin/env bash
#
# Load the AFT OU outputs and discover the Control Tower Account Factory
# Service Catalog product and current provisioning artifact.
#
# Usage (must be sourced):
#   source ./load-prerequisite-env.sh
#
# Prerequisites:
# - terraform/aft/org_unit is initialized against its existing remote state.
# - The active credentials belong to the Organizations management account.
# - The caller can search Service Catalog products and list their artifacts.
# - Terraform, AWS CLI v2, and jq are installed.

_load_aft_account_error() {
  printf 'ERROR: %s\n' "$*" >&2
}

_load_aft_account_tf_output() {
  local root_dir="$1"
  local output_name="$2"
  local value
  local error_file
  local status

  error_file="$(mktemp)" || {
    _load_aft_account_error "Unable to create a temporary file while reading Terraform output '${output_name}'."
    return 1
  }

  value="$(terraform -chdir="$root_dir" output -raw "$output_name" 2>"$error_file")"
  status=$?

  if ((status != 0)); then
    _load_aft_account_error \
      "Unable to read Terraform output '${output_name}' from '${root_dir}'."
    _load_aft_account_error \
      "Confirm that the org_unit root is initialized against its existing backend and that your credentials can read and decrypt its state."
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

  if [[ -z "${value//[[:space:]]/}" || "$value" == "null" || "$value" == "<nil>" ]]; then
    _load_aft_account_error \
      "Terraform output '${output_name}' is null or empty. The completed org_unit state must contain a non-empty '${output_name}' output."
    return 1
  fi

  printf '%s' "$value"
}

_load_aft_account_aws_json() {
  local description="$1"
  shift

  local value
  local error_file
  local status

  error_file="$(mktemp)" || {
    _load_aft_account_error "Unable to create a temporary file while ${description}."
    return 1
  }

  value="$(aws --no-cli-pager "$@" --output json 2>"$error_file")"
  status=$?

  if ((status != 0)); then
    _load_aft_account_error "AWS CLI failed while ${description}."
    _load_aft_account_error \
      "Confirm that the active management-account credentials permit servicecatalog:SearchProductsAsAdmin and servicecatalog:ListProvisioningArtifacts."
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
    _load_aft_account_error "AWS CLI returned a null or empty response while ${description}."
    return 1
  fi

  printf '%s' "$value"
}

_load_aft_account_main() {
  local script_dir
  local org_unit_dir
  local aft_ou_id
  local aft_ou_name
  local aft_control_tower_baseline_arn
  local landing_zone_arn
  local landing_zone_region
  local management_account_id
  local caller_identity_json
  local caller_account_id
  local products_json
  local matching_products_json
  local matching_product_count
  local account_factory_product_id
  local artifacts_json
  local eligible_artifacts_json
  local eligible_artifact_count
  local latest_created_time
  local latest_artifacts_json
  local latest_artifact_count
  local account_factory_provisioning_artifact_id
  local account_factory_provisioning_artifact_name

  if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    _load_aft_account_error \
      "This script must be sourced so its exported variables remain in the current shell."
    _load_aft_account_error "Run: source ./load-prerequisite-env.sh"
    return 2
  fi

  if ! command -v terraform >/dev/null 2>&1; then
    _load_aft_account_error "The 'terraform' executable was not found in PATH."
    return 1
  fi

  if ! command -v aws >/dev/null 2>&1; then
    _load_aft_account_error "The 'aws' executable was not found in PATH. Install AWS CLI v2."
    return 1
  fi

  if ! aws --version 2>&1 | grep -q '^aws-cli/2\.'; then
    _load_aft_account_error "AWS CLI v2 is required to discover Account Factory."
    return 1
  fi

  if ! command -v jq >/dev/null 2>&1; then
    _load_aft_account_error "The 'jq' executable was not found in PATH."
    return 1
  fi

  script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)" || {
    _load_aft_account_error "Unable to resolve the account script directory."
    return 1
  }
  org_unit_dir="${script_dir}/../org_unit"

  if [[ ! -d "$org_unit_dir" ]]; then
    _load_aft_account_error "Expected org_unit Terraform directory '${org_unit_dir}' does not exist."
    return 1
  fi

  aft_ou_id="$(_load_aft_account_tf_output "$org_unit_dir" aft_ou_id)" || return $?
  aft_ou_name="$(_load_aft_account_tf_output "$org_unit_dir" aft_ou_name)" || return $?
  aft_control_tower_baseline_arn="$(_load_aft_account_tf_output "$org_unit_dir" aft_control_tower_baseline_arn)" || return $?
  landing_zone_arn="$(_load_aft_account_tf_output "$org_unit_dir" landing_zone_arn)" || return $?

  if [[ ! "$aft_ou_id" =~ ^ou-[a-z0-9]{4,32}-[a-z0-9]{8,32}$ ]]; then
    _load_aft_account_error \
      "Terraform output 'aft_ou_id' has unexpected value '${aft_ou_id}'; expected an AWS Organizations OU ID."
    return 1
  fi

  if [[ -z "${aft_ou_name//[[:space:]]/}" ]]; then
    _load_aft_account_error "Terraform output 'aft_ou_name' is empty or whitespace-only."
    return 1
  fi

  if [[ ! "$aft_control_tower_baseline_arn" =~ ^arn:[^:]+:controltower:[^:]+:[0-9]{12}:enabledbaseline/[A-Za-z0-9-]+$ ]]; then
    _load_aft_account_error \
      "Terraform output 'aft_control_tower_baseline_arn' has unexpected value '${aft_control_tower_baseline_arn}'."
    return 1
  fi

  if [[ ! "$landing_zone_arn" =~ ^arn:[^:]+:controltower:[^:]+:[0-9]{12}:landingzone/[A-Za-z0-9-]+$ ]]; then
    _load_aft_account_error \
      "Terraform output 'landing_zone_arn' has unexpected value '${landing_zone_arn}'."
    return 1
  fi

  IFS=: read -r _ _ _ landing_zone_region management_account_id _ <<<"$landing_zone_arn"

  caller_identity_json="$(_load_aft_account_aws_json \
    "checking the active AWS account" \
    sts get-caller-identity)" || return $?
  caller_account_id="$(jq -r '.Account // empty' <<<"$caller_identity_json")" || return 1

  if [[ "$caller_account_id" != "$management_account_id" ]]; then
    _load_aft_account_error \
      "The active AWS credentials belong to account '${caller_account_id:-<empty>}', but the landing zone belongs to management account '${management_account_id}'."
    return 1
  fi

  products_json="$(_load_aft_account_aws_json \
    "searching for the Control Tower Account Factory product in Region '${landing_zone_region}'" \
    servicecatalog search-products-as-admin \
    --region "$landing_zone_region")" || return $?

  matching_products_json="$(
    jq -c \
      '[.ProductViewDetails[]?.ProductViewSummary
        | select(.Name == "AWS Control Tower Account Factory")
        | {id: (.ProductId // .Id // ""), name: .Name}]' \
      <<<"$products_json"
  )" || {
    _load_aft_account_error "Unable to parse the Service Catalog product search response."
    return 1
  }
  matching_product_count="$(jq 'length' <<<"$matching_products_json")"

  if [[ "$matching_product_count" -ne 1 ]]; then
    _load_aft_account_error \
      "Expected exactly one Service Catalog product named 'AWS Control Tower Account Factory' in Region '${landing_zone_region}', but found ${matching_product_count}."
    _load_aft_account_error \
      "Inspect the response with: aws servicecatalog search-products-as-admin --region '${landing_zone_region}'"
    return 1
  fi

  account_factory_product_id="$(jq -r '.[0].id // empty' <<<"$matching_products_json")"
  if [[ ! "$account_factory_product_id" =~ ^prod-[A-Za-z0-9]+$ ]]; then
    _load_aft_account_error \
      "Discovered Account Factory product ID '${account_factory_product_id:-<empty>}' is malformed."
    return 1
  fi

  artifacts_json="$(_load_aft_account_aws_json \
    "listing provisioning artifacts for Account Factory product '${account_factory_product_id}'" \
    servicecatalog list-provisioning-artifacts \
    --region "$landing_zone_region" \
    --product-id "$account_factory_product_id")" || return $?

  eligible_artifacts_json="$(
    jq -c \
      '[.ProvisioningArtifactDetails[]?
        | select(.Active == true and (.Guidance // "DEFAULT") != "DEPRECATED")
        | {id: (.Id // ""), name: (.Name // ""), createdTime: (.CreatedTime // "")}]' \
      <<<"$artifacts_json"
  )" || {
    _load_aft_account_error "Unable to parse the Account Factory provisioning artifacts response."
    return 1
  }
  eligible_artifact_count="$(jq 'length' <<<"$eligible_artifacts_json")"

  if [[ "$eligible_artifact_count" -eq 0 ]]; then
    _load_aft_account_error \
      "No active, non-deprecated provisioning artifact was found for Account Factory product '${account_factory_product_id}'."
    return 1
  fi

  if jq -e 'any(.[]; .createdTime == "")' >/dev/null <<<"$eligible_artifacts_json"; then
    _load_aft_account_error \
      "At least one eligible Account Factory artifact has no creation timestamp, so the newest artifact cannot be selected safely."
    return 1
  fi

  latest_created_time="$(jq -r 'map(.createdTime) | max' <<<"$eligible_artifacts_json")"
  latest_artifacts_json="$(
    jq -c --arg created "$latest_created_time" '[.[] | select(.createdTime == $created)]' \
      <<<"$eligible_artifacts_json"
  )"
  latest_artifact_count="$(jq 'length' <<<"$latest_artifacts_json")"

  if [[ "$latest_artifact_count" -ne 1 ]]; then
    _load_aft_account_error \
      "Found ${latest_artifact_count} eligible Account Factory artifacts with the newest creation timestamp '${latest_created_time}'; refusing to choose ambiguously."
    return 1
  fi

  account_factory_provisioning_artifact_id="$(jq -r '.[0].id // empty' <<<"$latest_artifacts_json")"
  account_factory_provisioning_artifact_name="$(jq -r '.[0].name // empty' <<<"$latest_artifacts_json")"

  if [[ ! "$account_factory_provisioning_artifact_id" =~ ^pa-[A-Za-z0-9]+$ ]]; then
    _load_aft_account_error \
      "Discovered provisioning artifact ID '${account_factory_provisioning_artifact_id:-<empty>}' is malformed."
    return 1
  fi

  export TF_VAR_aft_ou_id="$aft_ou_id"
  export TF_VAR_aft_ou_name="$aft_ou_name"
  export TF_VAR_aft_control_tower_baseline_arn="$aft_control_tower_baseline_arn"
  export TF_VAR_account_factory_product_id="$account_factory_product_id"
  export TF_VAR_account_factory_provisioning_artifact_id="$account_factory_provisioning_artifact_id"

  printf 'Loaded and validated AFT account prerequisites:\n'
  printf '  TF_VAR_aft_ou_id=%s\n' "$TF_VAR_aft_ou_id"
  printf '  TF_VAR_aft_ou_name=%s\n' "$TF_VAR_aft_ou_name"
  printf '  TF_VAR_aft_control_tower_baseline_arn=%s\n' "$TF_VAR_aft_control_tower_baseline_arn"
  printf '  TF_VAR_account_factory_product_id=%s\n' "$TF_VAR_account_factory_product_id"
  printf '  TF_VAR_account_factory_provisioning_artifact_id=%s\n' "$TF_VAR_account_factory_provisioning_artifact_id"
  printf '  Selected artifact name=%s created=%s\n' \
    "$account_factory_provisioning_artifact_name" "$latest_created_time"
}

_load_aft_account_status=0
_load_aft_account_main || _load_aft_account_status=$?
unset -f _load_aft_account_main _load_aft_account_aws_json _load_aft_account_tf_output _load_aft_account_error
return "$_load_aft_account_status" 2>/dev/null || exit "$_load_aft_account_status"
