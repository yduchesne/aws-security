#!/usr/bin/env bash
# Load the completed Account Factory output required by this Terraform root.
# Usage (must be sourced): source ./load-prerequisite-env.sh

_aft_access_error() {
  printf 'ERROR: %s\n' "$*" >&2
}

_aft_access_main() {
  local script_dir
  local account_root
  local account_status
  local account_id

  if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    _aft_access_error "This script must be sourced: source ./load-prerequisite-env.sh"
    return 2
  fi

  command -v terraform >/dev/null 2>&1 || {
    _aft_access_error "terraform is not installed or not in PATH."
    return 1
  }

  script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)" || {
    _aft_access_error "Unable to resolve the aft_access directory."
    return 1
  }
  account_root="${script_dir}/../../aft/account"

  account_status="$(terraform -chdir="$account_root" output -raw account_factory_status 2>/dev/null)" || {
    _aft_access_error "Unable to read account_factory_status from the initialized aft/account state."
    return 1
  }
  if [[ "$account_status" != "AVAILABLE" ]]; then
    _aft_access_error "Account Factory provisioned product must be AVAILABLE before assigning access; found '${account_status:-<empty>}'."
    return 1
  fi

  account_id="$(terraform -chdir="$account_root" output -raw aft_management_account_id 2>/dev/null)" || {
    _aft_access_error "Unable to read aft_management_account_id from the initialized aft/account state."
    return 1
  }
  if [[ ! "$account_id" =~ ^[0-9]{12}$ ]]; then
    _aft_access_error "aft_management_account_id is '${account_id:-<empty>}', not a 12-digit AWS account ID."
    return 1
  fi

  export TF_VAR_aft_management_account_id="$account_id"
  printf 'Loaded and validated TF_VAR_aft_management_account_id=%s\n' "$TF_VAR_aft_management_account_id"
}

_aft_access_status=0
_aft_access_main || _aft_access_status=$?
unset -f _aft_access_main _aft_access_error
return "$_aft_access_status" 2>/dev/null || exit "$_aft_access_status"
