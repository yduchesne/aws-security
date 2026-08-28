#!/usr/bin/env bash

set -euo pipefail

###############################################################################
# Defaults
###############################################################################

export AWS_PROFILE="${AWS_PROFILE:-ct-bootstrap}"
export AWS_SDK_LOAD_CONFIG=1

PHASE=""
APPLY=false
DRY_RUN=false
RUN_FMT=false
RUN_FMT_CHECK=false
ENVIRONMENT_FILE=""

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
BOOTSTRAP_DIR="${SCRIPT_DIR}/terraform/bootstrap"
IDENTITY_CENTER_DIR="${SCRIPT_DIR}/terraform/identity_center"
WORKLOAD_ACCESS_DIR="${SCRIPT_DIR}/terraform/identity_center/workload_access"
AFT_ACCESS_DIR="${SCRIPT_DIR}/terraform/identity_center/aft_access"
AFT_ORG_UNIT_DIR="${SCRIPT_DIR}/terraform/aft/org_unit"
AFT_ACCOUNT_DIR="${SCRIPT_DIR}/terraform/aft/account"
AFT_PLATFORM_DIR="${SCRIPT_DIR}/terraform/aft/platform"
WORKLOAD_ORG_UNITS_DIR="${SCRIPT_DIR}/terraform/workloads/org_units"

###############################################################################
# Functions
###############################################################################

usage() {
  cat <<EOF
Usage: $(basename "$0") --phase <bootstrap|identity-center|aft|workloads> [OPTIONS]

Run a Terraform phase for the AWS Control Tower landing zone.

Required:
  --phase PHASE  Phase to run: bootstrap, identity-center, aft, or workloads

Operations:
  --apply        Run 'terraform apply' in each selected Terraform root
  --dry-run      Run 'terraform plan' in each selected Terraform root
  --fmt          Run 'terraform fmt -recursive' as a standalone operation
  --chk          Run 'terraform fmt -check -recursive' as a standalone operation
  -h, --help     Display this help message

The identity-center phase runs these independent roots in order:
  1. terraform/identity_center
  2. terraform/identity_center/workload_access

The AFT phase runs these independent roots in order:
  1. terraform/aft/org_unit
  2. terraform/aft/account
  3. terraform/identity_center/aft_access
  4. terraform/aft/platform

The workloads phase runs terraform/workloads/org_units after bootstrap and
before AFT account requests target the workload environment OUs.

Examples:
  $(basename "$0") --phase bootstrap --fmt
  $(basename "$0") --phase bootstrap --dry-run
  $(basename "$0") --phase identity-center --dry-run
  $(basename "$0") --phase aft --chk
  $(basename "$0") --phase aft --dry-run
  $(basename "$0") --phase workloads --dry-run
EOF
}

log() {
  printf '==> %s\n' "$*"
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

require_nonempty() {
  local variable_name="$1"
  local value="${!variable_name:-}"

  if [[ -z "${value//[[:space:]]/}" ]]; then
    die "Required environment variable '${variable_name}' is not set or is empty. Add it to '${ENVIRONMENT_FILE:-the selected environment file}' or export it before running tf.sh."
  fi

  # Ensure values sourced from the environment file are inherited by Terraform
  # even if that file omitted an explicit `export` statement.
  export "$variable_name"
}

require_aft_platform_configuration() {
  require_nonempty TF_VAR_account_request_repo_name
  require_nonempty TF_VAR_global_customizations_repo_name
  require_nonempty TF_VAR_account_customizations_repo_name
  require_nonempty TF_VAR_account_provisioning_customizations_repo_name
}

load_environment() {
  local environment_file="${TF_ENV_FILE:-${HOME}/.env/aws-security/terraform/.env}"

  if [[ ! -f "$environment_file" ]]; then
    environment_file="${SCRIPT_DIR}/.env"
  fi

  if [[ ! -f "$environment_file" ]]; then
    die "Environment file not found. Set TF_ENV_FILE or create '${SCRIPT_DIR}/.env'."
  fi

  ENVIRONMENT_FILE="$environment_file"
  log "Loading environment variables from ${ENVIRONMENT_FILE}"
  set -a
  # shellcheck disable=SC1090
  source "$ENVIRONMENT_FILE"
  set +a
}

backend_bucket_for_root() {
  local root_name="$1"

  case "$root_name" in
    bootstrap)
      printf '%s' "${TF_STATE_BUCKET:-}"
      ;;
    identity-center)
      printf '%s' "${TF_IDENTITY_CENTER_STATE_BUCKET:-${TF_STATE_BUCKET:-}}"
      ;;
    identity-center-aft-access)
      printf '%s' "${TF_IDENTITY_CENTER_AFT_ACCESS_STATE_BUCKET:-${TF_IDENTITY_CENTER_STATE_BUCKET:-${TF_STATE_BUCKET:-}}}"
      ;;
    identity-center-workload-access)
      printf '%s' "${TF_IDENTITY_CENTER_WORKLOAD_ACCESS_STATE_BUCKET:-${TF_IDENTITY_CENTER_STATE_BUCKET:-${TF_STATE_BUCKET:-}}}"
      ;;
    aft-org-unit)
      printf '%s' "${TF_AFT_ORG_UNIT_STATE_BUCKET:-${TF_AFT_STATE_BUCKET:-${TF_STATE_BUCKET:-}}}"
      ;;
    aft-account)
      printf '%s' "${TF_AFT_ACCOUNT_STATE_BUCKET:-${TF_AFT_STATE_BUCKET:-${TF_STATE_BUCKET:-}}}"
      ;;
    aft-platform)
      printf '%s' "${TF_AFT_PLATFORM_STATE_BUCKET:-${TF_AFT_STATE_BUCKET:-${TF_STATE_BUCKET:-}}}"
      ;;
    workload-org-units)
      printf '%s' "${TF_WORKLOAD_ORG_UNITS_STATE_BUCKET:-${TF_STATE_BUCKET:-}}"
      ;;
    *)
      die "Unknown Terraform root name '${root_name}'."
      ;;
  esac
}

backend_region_for_root() {
  local root_name="$1"

  case "$root_name" in
    bootstrap)
      printf '%s' "${TF_STATE_REGION:-}"
      ;;
    identity-center)
      printf '%s' "${TF_IDENTITY_CENTER_STATE_REGION:-${TF_STATE_REGION:-}}"
      ;;
    identity-center-aft-access)
      printf '%s' "${TF_IDENTITY_CENTER_AFT_ACCESS_STATE_REGION:-${TF_IDENTITY_CENTER_STATE_REGION:-${TF_STATE_REGION:-}}}"
      ;;
    identity-center-workload-access)
      printf '%s' "${TF_IDENTITY_CENTER_WORKLOAD_ACCESS_STATE_REGION:-${TF_IDENTITY_CENTER_STATE_REGION:-${TF_STATE_REGION:-}}}"
      ;;
    aft-org-unit)
      printf '%s' "${TF_AFT_ORG_UNIT_STATE_REGION:-${TF_AFT_STATE_REGION:-${TF_STATE_REGION:-}}}"
      ;;
    aft-account)
      printf '%s' "${TF_AFT_ACCOUNT_STATE_REGION:-${TF_AFT_STATE_REGION:-${TF_STATE_REGION:-}}}"
      ;;
    aft-platform)
      printf '%s' "${TF_AFT_PLATFORM_STATE_REGION:-${TF_AFT_STATE_REGION:-${TF_STATE_REGION:-}}}"
      ;;
    workload-org-units)
      printf '%s' "${TF_WORKLOAD_ORG_UNITS_STATE_REGION:-${TF_STATE_REGION:-}}"
      ;;
    *)
      die "Unknown Terraform root name '${root_name}'."
      ;;
  esac
}

run_terraform_root() {
  local root_name="$1"
  local root_dir="$2"
  local backend_bucket
  local backend_region

  [[ -d "$root_dir" ]] || die "Terraform root not found: ${root_dir}"

  backend_bucket="$(backend_bucket_for_root "$root_name")"
  backend_region="$(backend_region_for_root "$root_name")"

  if [[ -z "${backend_bucket//[[:space:]]/}" ]]; then
    die "No backend bucket is configured for '${root_name}'. Set its root-specific backend variable or TF_STATE_BUCKET."
  fi

  if [[ -z "${backend_region//[[:space:]]/}" ]]; then
    die "No backend Region is configured for '${root_name}'. Set its root-specific backend variable or TF_STATE_REGION."
  fi

  log "Running Terraform root: ${root_name} (${root_dir})"

  if [[ "$RUN_FMT" == true ]]; then
    log "Formatting ${root_name}"
    terraform -chdir="$root_dir" fmt -recursive
  fi

  if [[ "$RUN_FMT_CHECK" == true ]]; then
    log "Checking Terraform formatting for ${root_name}"
    terraform -chdir="$root_dir" fmt -check -recursive
  fi

  log "Initializing ${root_name}"
  terraform -chdir="$root_dir" init \
    -reconfigure \
    -backend-config="bucket=${backend_bucket}" \
    -backend-config="region=${backend_region}"

  log "Validating ${root_name}"
  terraform -chdir="$root_dir" validate

  if [[ "$DRY_RUN" == true ]]; then
    log "Planning ${root_name}"
    terraform -chdir="$root_dir" plan
  elif [[ "$APPLY" == true ]]; then
    log "Applying ${root_name}"
    terraform -chdir="$root_dir" apply
  fi
}

load_terraform_account_id_output() {
  local root_dir="$1"
  local output_name="$2"
  local value
  local error_file
  local status

  error_file="$(mktemp)" || die "Unable to create a temporary file while reading Terraform output '${output_name}'."
  value="$(terraform -chdir="$root_dir" output -raw "$output_name" 2>"$error_file")"
  status=$?

  if ((status != 0)); then
    printf "ERROR: Unable to read Terraform output '%s' from '%s'.\n" "$output_name" "$root_dir" >&2
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

  if [[ ! "$value" =~ ^[0-9]{12}$ ]]; then
    printf "ERROR: Terraform output '%s' from '%s' is '%s', not a 12-digit AWS account ID.\n" \
      "$output_name" "$root_dir" "${value:-<empty>}" >&2
    return 1
  fi

  printf '%s' "$value"
}

load_aft_management_account_id() {
  local account_id

  account_id="$(load_terraform_account_id_output "$AFT_ACCOUNT_DIR" aft_management_account_id)" || {
    die "Complete the aft/account phase and verify its Account Factory outputs before running aft/platform."
  }

  export TF_VAR_aft_management_account_id="$account_id"
  log "Loaded TF_VAR_aft_management_account_id from the aft/account state"
}

load_control_tower_shared_account_ids() {
  local audit_account_id
  local log_archive_account_id

  audit_account_id="$(load_terraform_account_id_output "$BOOTSTRAP_DIR" security_tooling_account_id)" || {
    die "Unable to initialize TF_VAR_audit_account_id from the bootstrap state."
  }
  log_archive_account_id="$(load_terraform_account_id_output "$BOOTSTRAP_DIR" log_archive_account_id)" || {
    die "Unable to initialize TF_VAR_log_archive_account_id from the bootstrap state."
  }

  if [[ "$audit_account_id" == "$log_archive_account_id" ]]; then
    die "Bootstrap outputs identify the same account '${audit_account_id}' as both Audit and Log Archive; expected distinct Control Tower shared accounts."
  fi

  export TF_VAR_audit_account_id="$audit_account_id"
  export TF_VAR_log_archive_account_id="$log_archive_account_id"
  log "Loaded TF_VAR_audit_account_id and TF_VAR_log_archive_account_id from the bootstrap state"
}

run_bootstrap_phase() {
  run_terraform_root bootstrap "$BOOTSTRAP_DIR"
}

run_identity_center_phase() {
  local prerequisite_script="${IDENTITY_CENTER_DIR}/load-prerequisite-env.sh"

  [[ -f "$prerequisite_script" ]] || die "Prerequisite script not found: ${prerequisite_script}"
  log "Loading prerequisites for identity_center"
  # shellcheck disable=SC1090
  source "$prerequisite_script"
  run_terraform_root identity-center "$IDENTITY_CENTER_DIR"

  prerequisite_script="${WORKLOAD_ACCESS_DIR}/load-prerequisite-env.sh"
  [[ -f "$prerequisite_script" ]] || die "Prerequisite script not found: ${prerequisite_script}"
  log "Loading prerequisites for identity_center/workload_access"
  # shellcheck disable=SC1090
  source "$prerequisite_script"
  run_terraform_root identity-center-workload-access "$WORKLOAD_ACCESS_DIR"
}

run_workloads_phase() {
  local prerequisite_script="${WORKLOAD_ORG_UNITS_DIR}/load-prerequisite-env.sh"

  [[ -f "$prerequisite_script" ]] || die "Prerequisite script not found: ${prerequisite_script}"
  log "Loading prerequisites for workloads/org_units"
  # shellcheck disable=SC1090
  source "$prerequisite_script"
  run_terraform_root workload-org-units "$WORKLOAD_ORG_UNITS_DIR"
}

run_aft_phase() {
  local prerequisite_script

  prerequisite_script="${AFT_ORG_UNIT_DIR}/load-prerequisite-env.sh"
  [[ -f "$prerequisite_script" ]] || die "Prerequisite script not found: ${prerequisite_script}"
  log "Loading prerequisites for aft/org_unit"
  # shellcheck disable=SC1090
  source "$prerequisite_script"
  run_terraform_root aft-org-unit "$AFT_ORG_UNIT_DIR"

  prerequisite_script="${AFT_ACCOUNT_DIR}/load-prerequisite-env.sh"
  [[ -f "$prerequisite_script" ]] || die "Prerequisite script not found: ${prerequisite_script}"
  log "Loading prerequisites for aft/account"
  # shellcheck disable=SC1090
  source "$prerequisite_script"
  run_terraform_root aft-account "$AFT_ACCOUNT_DIR"

  # A plan cannot produce an account ID for a not-yet-created account. Permit a
  # caller to supply it explicitly for a full AFT dry run; otherwise require the
  # completed aft/account state before planning or applying the platform root.
  if [[ -z "${TF_VAR_aft_management_account_id:-}" ]]; then
    load_aft_management_account_id
  elif [[ ! "$TF_VAR_aft_management_account_id" =~ ^[0-9]{12}$ ]]; then
    die "TF_VAR_aft_management_account_id must be a 12-digit AWS account ID."
  fi

  prerequisite_script="${AFT_ACCESS_DIR}/load-prerequisite-env.sh"
  [[ -f "$prerequisite_script" ]] || die "Prerequisite script not found: ${prerequisite_script}"
  log "Loading prerequisites for identity_center/aft_access"
  # shellcheck disable=SC1090
  source "$prerequisite_script"
  run_terraform_root identity-center-aft-access "$AFT_ACCESS_DIR"

  load_control_tower_shared_account_ids
  if [[ "$DRY_RUN" == true || "$APPLY" == true ]]; then
    require_aft_platform_configuration
    log "Validated required AFT repository TF_VAR environment variables"
  fi
  run_terraform_root aft-platform "$AFT_PLATFORM_DIR"
}

###############################################################################
# Parse command-line arguments
###############################################################################

while (($#)); do
  case "$1" in
    --phase)
      (($# >= 2)) || die "--phase requires a value: bootstrap, identity-center, aft, or workloads."
      PHASE="$2"
      shift 2
      ;;
    --phase=*)
      PHASE="${1#*=}"
      shift
      ;;
    --apply)
      APPLY=true
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --fmt)
      RUN_FMT=true
      shift
      ;;
    --chk)
      RUN_FMT_CHECK=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown argument: $1"
      ;;
  esac
done

[[ "$PHASE" == "bootstrap" || "$PHASE" == "identity-center" || "$PHASE" == "aft" || "$PHASE" == "workloads" ]] ||
  die "--phase must be set to 'bootstrap', 'identity-center', 'aft', or 'workloads'."

if [[ "$APPLY" == true && "$DRY_RUN" == true ]]; then
  die "--apply and --dry-run are mutually exclusive."
fi

if [[ "$APPLY" == false && "$DRY_RUN" == false && "$RUN_FMT" == false && "$RUN_FMT_CHECK" == false ]]; then
  die "Specify at least one operation: --apply, --dry-run, --fmt, or --chk."
fi

###############################################################################
# Verify prerequisites and identity
###############################################################################

command -v terraform >/dev/null 2>&1 || die "terraform is not installed or not in PATH."
command -v aws >/dev/null 2>&1 || die "AWS CLI is not installed or not in PATH."

load_environment

log "Verifying AWS identity"
aws sts get-caller-identity

###############################################################################
# Execute selected phase
###############################################################################

case "$PHASE" in
  bootstrap)
    run_bootstrap_phase
    ;;
  identity-center)
    run_identity_center_phase
    ;;
  aft)
    run_aft_phase
    ;;
  workloads)
    run_workloads_phase
    ;;
esac
