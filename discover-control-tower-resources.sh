#!/usr/bin/env bash
#
# discover-control-tower-resources.sh
#
# Purpose
# -------
# Produce an inventory of the AWS Control Tower landing-zone/governance
# resources visible from the AWS Organizations management account.
#
# The script intentionally uses several AWS APIs instead of relying on a
# single Control Tower call. That is a design decision:
#
#   * Control Tower tells us what landing zone, baselines, and controls it
#     believes are enabled.
#   * AWS Organizations tells us the account/OU hierarchy and SCP attachments.
#   * CloudFormation StackSets expose many of the concrete baseline resources
#     Control Tower deploys into governed accounts.
#
# This mirrors the architectural lesson behind the portfolio exercise:
# Control Tower is an orchestration/governance layer over other AWS services,
# not a self-contained security product.
#
# Documentation used / useful references
# ---------------------------------------
# AWS Control Tower landing-zone APIs:
#   https://docs.aws.amazon.com/controltower/latest/APIReference/API_ListLandingZones.html
#   https://docs.aws.amazon.com/controltower/latest/APIReference/API_GetLandingZone.html
#
# AWS Control Tower enabled controls and catalog metadata:
#   https://docs.aws.amazon.com/controltower/latest/APIReference/API_ListEnabledControls.html
#   https://docs.aws.amazon.com/controlcatalog/latest/APIReference/API_GetControl.html
#
# AWS Control Tower baselines:
#   https://docs.aws.amazon.com/controltower/latest/APIReference/API_ListEnabledBaselines.html
#
# Control Tower resources in shared accounts:
#   https://docs.aws.amazon.com/controltower/latest/userguide/shared-account-resources.html
#
# Control Tower governance drift:
#   https://docs.aws.amazon.com/controltower/latest/userguide/governance-drift.html
#
# AWS Organizations:
#   https://docs.aws.amazon.com/organizations/latest/APIReference/API_DescribeOrganization.html
#   https://docs.aws.amazon.com/organizations/latest/APIReference/API_ListRoots.html
#   https://docs.aws.amazon.com/organizations/latest/APIReference/API_ListAccounts.html
#   https://docs.aws.amazon.com/organizations/latest/APIReference/API_ListOrganizationalUnitsForParent.html
#   https://docs.aws.amazon.com/organizations/latest/APIReference/API_ListPolicies.html
#   https://docs.aws.amazon.com/organizations/latest/APIReference/API_ListPoliciesForTarget.html
#
# CloudFormation StackSets:
#   https://docs.aws.amazon.com/AWSCloudFormation/latest/APIReference/API_ListStackSets.html
#   https://docs.aws.amazon.com/AWSCloudFormation/latest/APIReference/API_ListStackInstances.html
#
# Assumptions
# -----------
# 1. Run this from the Organizations management account, or with credentials
#    that have equivalent read visibility. Control Tower administration and
#    Organizations topology are management-account concerns.
#
# 2. The Control Tower home Region is supplied explicitly with --region, via
#    AWS_REGION/AWS_DEFAULT_REGION, or via the selected AWS CLI profile.
#
# 3. AWS CLI v2 and jq are installed.
#
# 4. The caller has read-only permissions for:
#      sts:GetCallerIdentity
#      controltower:ListLandingZones
#      controltower:GetLandingZone
#      controltower:ListEnabledControls
#      controltower:ListEnabledBaselines
#      controlcatalog:GetControl
#      organizations:DescribeOrganization
#      organizations:ListRoots
#      organizations:ListAccounts
#      organizations:ListOrganizationalUnitsForParent
#      organizations:ListPolicies
#      organizations:ListPoliciesForTarget
#      organizations:DescribePolicy
#      organizations:ListParents
#      organizations:ListAWSServiceAccessForOrganization
#      organizations:ListDelegatedAdministrators
#      organizations:ListDelegatedServicesForAccount
#      cloudformation:ListStackSets
#      cloudformation:ListStackInstances
#      cloudformation:ListStacks
#      iam:ListRoles
#      cloudtrail:DescribeTrails
#      config:DescribeConfigurationRecorders
#      config:DescribeDeliveryChannels
#      s3:ListAllMyBuckets
#      servicecatalog:SearchProductsAsAdmin
#
# 5. Control Tower/CloudFormation resource names can evolve between landing-zone
#    releases. Therefore StackSets are discovered by matching names/descriptions
#    containing "ControlTower" / "Control Tower" rather than by hard-coding a
#    fixed list of StackSet names.
#
# Output
# ------
# Default:
#   Human-readable report for interactive exploration.
#
# --json:
#   A single JSON document suitable for:
#
#     ./discover-control-tower-resources.sh --json > control-tower-inventory.json
#     jq '.organizations.organizationalUnits' control-tower-inventory.json
#
# JSON mode deliberately preserves individual API errors as JSON objects
# instead of terminating the whole run. This allows partial discovery when,
# for example, the caller can read Organizations but lacks permission for
# ListEnabledBaselines.
#
set -uo pipefail

PROGRAM="$(basename "$0")"
JSON_MODE=false
PROFILE=""
REGION=""

usage() {
  cat <<EOF
Usage: $PROGRAM [OPTIONS]

Discover AWS Control Tower governance and deployment resources.

Options:
  --json               Emit a single JSON document.
  --profile PROFILE    AWS CLI profile to use.
  --region REGION      AWS Control Tower home Region.
  -h, --help           Show this help.

Environment:
  AWS_PROFILE
  AWS_REGION
  AWS_DEFAULT_REGION

Examples:
  $PROGRAM
  $PROGRAM --json
  $PROGRAM --profile ct-bootstrap --region us-east-2
  $PROGRAM --profile ct-bootstrap --region us-east-2 --json > inventory.json
EOF
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

while (($#)); do
  case "$1" in
    --json)
      JSON_MODE=true
      shift
      ;;
    --profile)
      [[ $# -ge 2 ]] || die "--profile requires a value"
      PROFILE="$2"
      shift 2
      ;;
    --region)
      [[ $# -ge 2 ]] || die "--region requires a value"
      REGION="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown option: $1 (use --help)"
      ;;
  esac
done

require_command aws
require_command jq

# Common AWS CLI arguments are stored in an array so profiles containing
# unusual characters remain safely quoted.
AWS_ARGS=(--no-cli-pager)

if [[ -n "$PROFILE" ]]; then
  AWS_ARGS+=(--profile "$PROFILE")
elif [[ -n "${AWS_PROFILE:-}" ]]; then
  PROFILE="$AWS_PROFILE"
fi

# Resolve the Region in the same order a human would expect:
# explicit option -> environment -> selected AWS CLI profile.
if [[ -z "$REGION" ]]; then
  REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-}}"
fi

if [[ -z "$REGION" ]]; then
  PROFILE_REGION="$(aws "${AWS_ARGS[@]}" configure get region 2>/dev/null || true)"
  REGION="${PROFILE_REGION:-}"
fi

[[ -n "$REGION" ]] || die \
  "No AWS Region found. Supply --region or configure AWS_REGION/AWS_DEFAULT_REGION."

aws_json() {
  aws "${AWS_ARGS[@]}" --region "$REGION" "$@" --output json
}

# A discovery utility should return as much inventory as possible. For optional
# calls we therefore convert AWS CLI failures into JSON instead of exiting.
# This is especially useful when testing least-privilege discovery roles.
aws_json_safe() {
  local tmp rc out err
  tmp="$(mktemp)"
  out="$(aws_json "$@" 2>"$tmp")"
  rc=$?

  if (( rc == 0 )); then
    rm -f "$tmp"
    printf '%s\n' "$out"
    return 0
  fi

  err="$(tr '\n' ' ' <"$tmp" | sed 's/[[:space:]]\+/ /g')"
  rm -f "$tmp"

  jq -cn \
    --arg error "$err" \
    --argjson exitCode "$rc" \
    '{error:$error, exitCode:$exitCode}'
}

# -----------------------------------------------------------------------------
# Identity
# -----------------------------------------------------------------------------
# GetCallerIdentity is intentionally a hard requirement. Without a known
# identity/account, the rest of the inventory is potentially misleading.

IDENTITY="$(aws_json sts get-caller-identity)" ||
  die "Unable to call STS GetCallerIdentity."

ACCOUNT_ID="$(jq -r '.Account' <<<"$IDENTITY")"
CALLER_ARN="$(jq -r '.Arn' <<<"$IDENTITY")"

# -----------------------------------------------------------------------------
# Control Tower landing zone
# -----------------------------------------------------------------------------

LANDING_ZONES_RAW="$(aws_json_safe controltower list-landing-zones)"
LANDING_ZONE_ARN=""
LANDING_ZONE_DETAILS='null'

if ! jq -e '.error?' >/dev/null 2>&1 <<<"$LANDING_ZONES_RAW"; then
  # A management account normally has one Control Tower landing zone. We still
  # retain the complete list in JSON and use the first entry for the detailed
  # human-readable summary.
  LANDING_ZONE_ARN="$(jq -r '.landingZones[0].arn // empty' <<<"$LANDING_ZONES_RAW")"

  if [[ -n "$LANDING_ZONE_ARN" ]]; then
    LANDING_ZONE_DETAILS="$(
      aws_json_safe controltower get-landing-zone \
        --landing-zone-identifier "$LANDING_ZONE_ARN"
    )"
  fi
fi

# -----------------------------------------------------------------------------
# AWS Organizations topology
# -----------------------------------------------------------------------------

ORGANIZATION="$(aws_json_safe organizations describe-organization)"
if jq -e '.Organization?' >/dev/null 2>&1 <<<"$ORGANIZATION"; then
  MANAGEMENT_ACCOUNT_ID="$(jq -r '.Organization.MasterAccountId // empty' <<<"$ORGANIZATION")"
  if [[ -n "$MANAGEMENT_ACCOUNT_ID" && "$ACCOUNT_ID" != "$MANAGEMENT_ACCOUNT_ID" ]]; then
    die "Caller account '${ACCOUNT_ID}' is not the Organizations management account '${MANAGEMENT_ACCOUNT_ID}'. Run this inventory with management-account read credentials."
  fi
fi
ROOTS="$(aws_json_safe organizations list-roots)"
ACCOUNTS="$(aws_json_safe organizations list-accounts)"
SERVICE_ACCESS="$(aws_json_safe organizations list-aws-service-access-for-organization)"
DELEGATED_ADMINISTRATORS="$(aws_json_safe organizations list-delegated-administrators)"
DELEGATED_SERVICES='[]'

if jq -e '.DelegatedAdministrators?' >/dev/null 2>&1 <<<"$DELEGATED_ADMINISTRATORS"; then
  while IFS= read -r delegated_account_id; do
    [[ -n "$delegated_account_id" ]] || continue
    response="$(
      aws_json_safe organizations list-delegated-services-for-account \
        --account-id "$delegated_account_id"
    )"
    DELEGATED_SERVICES="$(
      jq -cn \
        --argjson existing "$DELEGATED_SERVICES" \
        --arg accountId "$delegated_account_id" \
        --argjson response "$response" \
        '$existing + [{
          accountId:$accountId,
          services:($response.DelegatedServices // []),
          error:($response.error // null)
        }]'
    )"
  done < <(jq -r '.DelegatedAdministrators[].Id // empty' <<<"$DELEGATED_ADMINISTRATORS")
fi

# Control Tower governance is OU-oriented. Organizations does not provide one
# recursive "list the OU tree" API, so recurse through
# ListOrganizationalUnitsForParent and keep ParentId on every discovered OU.
OU_FILE="$(mktemp)"
printf '[]' >"$OU_FILE"

discover_ous() {
  local parent_id response count i ou id current
  parent_id="$1"

  response="$(
    aws_json_safe organizations list-organizational-units-for-parent \
      --parent-id "$parent_id"
  )"

  if jq -e '.error?' >/dev/null 2>&1 <<<"$response"; then
    return
  fi

  count="$(jq '.OrganizationalUnits | length' <<<"$response")"

  for ((i=0; i<count; i++)); do
    ou="$(jq ".OrganizationalUnits[$i]" <<<"$response")"
    id="$(jq -r '.Id' <<<"$ou")"
    current="$(cat "$OU_FILE")"

    jq \
      --arg parentId "$parent_id" \
      --argjson ou "$ou" \
      '. + [($ou + {ParentId:$parentId})]' \
      <<<"$current" >"${OU_FILE}.tmp"

    mv "${OU_FILE}.tmp" "$OU_FILE"
    discover_ous "$id"
  done
}

if ! jq -e '.error?' >/dev/null 2>&1 <<<"$ROOTS"; then
  while IFS= read -r root_id; do
    [[ -n "$root_id" ]] && discover_ous "$root_id"
  done < <(jq -r '.Roots[].Id' <<<"$ROOTS")
fi

OUS="$(cat "$OU_FILE")"
rm -f "$OU_FILE"

# Record direct account parentage so OU membership and Control Tower enrollment
# are not conflated. Organizations account membership alone does not prove that
# an account is enrolled or governed by Control Tower.
ACCOUNT_PARENTS='[]'
if jq -e '.Accounts?' >/dev/null 2>&1 <<<"$ACCOUNTS"; then
  while IFS=$'\t' read -r account_id account_name; do
    [[ -n "$account_id" ]] || continue
    response="$(aws_json_safe organizations list-parents --child-id "$account_id")"
    ACCOUNT_PARENTS="$(
      jq -cn \
        --argjson existing "$ACCOUNT_PARENTS" \
        --arg accountId "$account_id" \
        --arg accountName "$account_name" \
        --argjson response "$response" \
        '$existing + [{
          accountId:$accountId,
          accountName:$accountName,
          parents:($response.Parents // []),
          error:($response.error // null)
        }]'
    )"
  done < <(jq -r '.Accounts[] | [.Id,.Name] | @tsv' <<<"$ACCOUNTS")
fi

# -----------------------------------------------------------------------------
# Service Control Policies and attachments
# -----------------------------------------------------------------------------
# SCPs are relevant because many Control Tower preventive controls ultimately
# rely on AWS Organizations policy enforcement. We inventory both the policies
# and where they are attached.

SCPS="$(aws_json_safe organizations list-policies --filter SERVICE_CONTROL_POLICY)"
SCP_DOCUMENTS='[]'
SCP_EXPLANATIONS='[]'
POLICY_ATTACHMENTS='[]'

# Include policy content so Control Tower preventive controls can be mapped to
# their underlying Organizations enforcement. Policy names alone are not
# sufficient evidence of what is denied or allowed.
if jq -e '.Policies?' >/dev/null 2>&1 <<<"$SCPS"; then
  while IFS= read -r policy_id; do
    [[ -n "$policy_id" ]] || continue
    response="$(aws_json_safe organizations describe-policy --policy-id "$policy_id")"
    SCP_DOCUMENTS="$(
      jq -cn \
        --argjson existing "$SCP_DOCUMENTS" \
        --arg policyId "$policy_id" \
        --argjson response "$response" \
        '$existing + [{
          policyId:$policyId,
          policy:($response.Policy // null),
          error:($response.error // null)
        }]'
    )"
  done < <(jq -r '.Policies[].Id // empty' <<<"$SCPS")
fi

# Explain SCPs only from authoritative policy metadata and documents returned
# by Organizations. Statement summaries describe the actual Effect/Action/
# Resource fields; they do not infer business intent beyond those fields.
if jq -e '.Policies?' >/dev/null 2>&1 <<<"$SCPS"; then
  SCP_EXPLANATIONS="$(
    jq -cn \
      --argjson summaries "$SCPS" \
      --argjson documents "$SCP_DOCUMENTS" \
      '[$summaries.Policies[] as $summary |
        ($documents[]? | select(.policyId == $summary.Id)) as $document |
        ($document.policy.Content // null) as $rawContent |
        (if ($rawContent | type) == "string" then (try ($rawContent | fromjson) catch null) else $rawContent end) as $content |
        {
          policyId:$summary.Id,
          name:$summary.Name,
          description:($summary.Description // null),
          awsManaged:($summary.AwsManaged // false),
          controlTowerManaged:(($summary.Description // "") | test("managed by AWS Control Tower"; "i")),
          explanation:(
            if $summary.Id == "p-FullAWSAccess" then
              "AWS-managed allow-list SCP that permits all AWS service actions. It does not grant IAM permissions; it establishes the Organizations permissions ceiling when no more restrictive SCP applies."
            elif (($summary.Description // "") | test("managed by AWS Control Tower"; "i")) then
              "AWS Control Tower-managed SCP implementing preventive controls. AWS states that it must be changed through Control Tower rather than Organizations APIs or console."
            elif ($summary.Description // "") != "" then $summary.Description
            else null end
          ),
          statements:(if ($content.Statement? | type) == "array" then [
            $content.Statement[] | {
              sid:(.Sid // null),
              effect:(.Effect // null),
              actions:(if .Action? then (if (.Action|type)=="array" then .Action else [.Action] end) else [] end),
              notActions:(if .NotAction? then (if (.NotAction|type)=="array" then .NotAction else [.NotAction] end) else [] end),
              resources:(if .Resource? then (if (.Resource|type)=="array" then .Resource else [.Resource] end) else [] end),
              hasCondition:(.Condition? != null)
            }
          ] else [] end),
          references:[
            {title:"Service control policies (SCPs)",url:"https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_scps.html"},
            {title:"SCP effects on permissions",url:"https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_scps_evaluation.html"}
          ]
        }
      ]'
  )"
fi

collect_policies_for_target() {
  local target_id target_name target_type response

  target_id="$1"
  target_name="$2"
  target_type="$3"

  response="$(
    aws_json_safe organizations list-policies-for-target \
      --target-id "$target_id" \
      --filter SERVICE_CONTROL_POLICY
  )"

  POLICY_ATTACHMENTS="$(
    jq -cn \
      --argjson existing "$POLICY_ATTACHMENTS" \
      --arg targetId "$target_id" \
      --arg targetName "$target_name" \
      --arg targetType "$target_type" \
      --argjson response "$response" \
      '$existing + [{
        targetId:$targetId,
        targetName:$targetName,
        targetType:$targetType,
        policies:($response.Policies // []),
        error:($response.error // null)
      }]'
  )"
}

if ! jq -e '.error?' >/dev/null 2>&1 <<<"$ROOTS"; then
  while IFS=$'\t' read -r id name; do
    [[ -n "$id" ]] && collect_policies_for_target "$id" "$name" "ROOT"
  done < <(jq -r '.Roots[] | [.Id,.Name] | @tsv' <<<"$ROOTS")
fi

while IFS=$'\t' read -r id name; do
  [[ -n "$id" ]] && collect_policies_for_target "$id" "$name" "ORGANIZATIONAL_UNIT"
done < <(jq -r '.[] | [.Id,.Name] | @tsv' <<<"$OUS")

# -----------------------------------------------------------------------------
# Enabled Control Tower controls
# -----------------------------------------------------------------------------
# ListEnabledControls is target-oriented. Query every discovered OU ARN rather
# than assuming the controls enabled on one OU apply identically to descendants.

ENABLED_CONTROLS='[]'
CONTROL_CATALOG_DETAILS='[]'

while IFS=$'\t' read -r ou_id ou_arn ou_name; do
  [[ -n "$ou_arn" ]] || continue

  response="$(
    aws_json_safe controltower list-enabled-controls \
      --target-identifier "$ou_arn"
  )"

  ENABLED_CONTROLS="$(
    jq -cn \
      --argjson existing "$ENABLED_CONTROLS" \
      --arg ouId "$ou_id" \
      --arg ouArn "$ou_arn" \
      --arg ouName "$ou_name" \
      --argjson response "$response" \
      '$existing + [{
        ouId:$ouId,
        ouArn:$ouArn,
        ouName:$ouName,
        controls:($response.enabledControls // []),
        error:($response.error // null)
      }]'
  )"
done < <(jq -r '.[] | [.Id,.Arn,.Name] | @tsv' <<<"$OUS")

# Resolve every distinct enabled control through AWS Control Catalog. This API
# supplies AWS-authored names, descriptions, behavior, severity, implementation,
# and governed-resource metadata for both legacy Control Tower identifiers and
# Control Catalog ARNs. Failed lookups remain explicit and receive no invented
# explanation.
while IFS= read -r control_arn; do
  [[ -n "$control_arn" ]] || continue
  response="$(aws_json_safe controlcatalog get-control --control-arn "$control_arn")"
  CONTROL_CATALOG_DETAILS="$(
    jq -cn \
      --argjson existing "$CONTROL_CATALOG_DETAILS" \
      --arg requestedArn "$control_arn" \
      --argjson response "$response" \
      '$existing + [{
        requestedArn:$requestedArn,
        details:(if $response.error? then null else $response end),
        error:($response.error // null),
        references:[
          {title:"AWS Control Tower controls reference guide",url:"https://docs.aws.amazon.com/controltower/latest/controlreference/introduction.html"},
          {title:"GetControl API",url:"https://docs.aws.amazon.com/controlcatalog/latest/APIReference/API_GetControl.html"}
        ]
      }]'
  )"
done < <(jq -r '[.[].controls[]?.controlIdentifier] | unique[]?' <<<"$ENABLED_CONTROLS")

# -----------------------------------------------------------------------------
# Enabled baselines
# -----------------------------------------------------------------------------
# Baseline APIs are useful for newer Control Tower landing-zone/account
# enrollment workflows. The call is deliberately optional because permissions,
# CLI versions, or landing-zone versions can differ.
BASELINE_DEFINITIONS="$(aws_json_safe controltower list-baselines)"
ENABLED_BASELINES="$(aws_json_safe controltower list-enabled-baselines)"

# -----------------------------------------------------------------------------
# Control Tower-related resources in the management account
# -----------------------------------------------------------------------------
# The following APIs expose underlying service resources. Name matching is a
# discovery heuristic, not proof of ownership; the report labels these results
# as candidates and operators must confirm tags, policies, StackSet lineage, and
# AWS documentation before changing anything.

IAM_ROLES_RAW="$(aws_json_safe iam list-roles)"
if jq -e '.error?' >/dev/null 2>&1 <<<"$IAM_ROLES_RAW"; then
  CONTROL_TOWER_IAM_ROLES="$IAM_ROLES_RAW"
else
  CONTROL_TOWER_IAM_ROLES="$(
    jq '[.Roles[] | select(
      ((.RoleName // "") | test("^(AWSControlTower|ControlTower|AWSAFT|AFT)"; "i"))
      or ((.Path // "") | test("controltower|aft"; "i"))
    )]' <<<"$IAM_ROLES_RAW"
  )"
fi

CLOUDFORMATION_STACKS_RAW="$(aws_json_safe cloudformation list-stacks --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE UPDATE_ROLLBACK_COMPLETE IMPORT_COMPLETE)"
if jq -e '.error?' >/dev/null 2>&1 <<<"$CLOUDFORMATION_STACKS_RAW"; then
  CONTROL_TOWER_STACKS="$CLOUDFORMATION_STACKS_RAW"
else
  CONTROL_TOWER_STACKS="$(
    jq '[.StackSummaries[] | select(
      ((.StackName // "") | test("AWSControlTower|ControlTower|StackSet-AWSControlTower"; "i"))
      or ((.TemplateDescription // "") | test("Control Tower"; "i"))
    )]' <<<"$CLOUDFORMATION_STACKS_RAW"
  )"
fi

CLOUDTRAIL_TRAILS="$(aws_json_safe cloudtrail describe-trails --include-shadow-trails)"
CONFIG_RECORDERS="$(aws_json_safe configservice describe-configuration-recorders)"
CONFIG_DELIVERY_CHANNELS="$(aws_json_safe configservice describe-delivery-channels)"
S3_BUCKETS_RAW="$(aws_json_safe s3api list-buckets)"
if jq -e '.error?' >/dev/null 2>&1 <<<"$S3_BUCKETS_RAW"; then
  CONTROL_TOWER_BUCKET_CANDIDATES="$S3_BUCKETS_RAW"
else
  CONTROL_TOWER_BUCKET_CANDIDATES="$(
    jq '[.Buckets[] | select((.Name // "") | test("aws-controltower|controltower"; "i"))]' <<<"$S3_BUCKETS_RAW"
  )"
fi

ACCOUNT_FACTORY_PRODUCTS_RAW="$(aws_json_safe servicecatalog search-products-as-admin)"
if jq -e '.error?' >/dev/null 2>&1 <<<"$ACCOUNT_FACTORY_PRODUCTS_RAW"; then
  ACCOUNT_FACTORY_PRODUCTS="$ACCOUNT_FACTORY_PRODUCTS_RAW"
else
  ACCOUNT_FACTORY_PRODUCTS="$(
    jq '[.ProductViewDetails[] | select(
      (.ProductViewSummary.Name // "") == "AWS Control Tower Account Factory"
    )]' <<<"$ACCOUNT_FACTORY_PRODUCTS_RAW"
  )"
fi

# -----------------------------------------------------------------------------
# CloudFormation StackSets created/used by Control Tower
# -----------------------------------------------------------------------------
# AWS documents shared-account resources and Control Tower StackSets, but exact
# names can change. Match names/descriptions rather than maintaining a brittle
# fixed allow-list.

STACKSETS_RAW="$(
  aws_json_safe cloudformation list-stack-sets \
    --status ACTIVE \
    --call-as SELF
)"

if jq -e '.error?' >/dev/null 2>&1 <<<"$STACKSETS_RAW"; then
  CONTROL_TOWER_STACKSETS="$STACKSETS_RAW"
else
  CONTROL_TOWER_STACKSETS="$(
    jq '[
      .Summaries[]
      | select(
          ((.StackSetName // "") | test("ControlTower"; "i"))
          or
          ((.Description // "") | test("Control Tower"; "i"))
        )
    ]' <<<"$STACKSETS_RAW"
  )"
fi

STACKSET_INVENTORY='[]'

if ! jq -e '.error?' >/dev/null 2>&1 <<<"$CONTROL_TOWER_STACKSETS"; then
  while IFS= read -r stackset_name; do
    [[ -n "$stackset_name" ]] || continue

    response="$(
      aws_json_safe cloudformation list-stack-instances \
        --stack-set-name "$stackset_name" \
        --call-as SELF
    )"

    STACKSET_INVENTORY="$(
      jq -cn \
        --argjson existing "$STACKSET_INVENTORY" \
        --arg stackSetName "$stackset_name" \
        --argjson response "$response" \
        '$existing + [{
          stackSetName:$stackSetName,
          instances:($response.Summaries // []),
          error:($response.error // null)
        }]'
    )"
  done < <(jq -r '.[].StackSetName // empty' <<<"$CONTROL_TOWER_STACKSETS")
fi

# -----------------------------------------------------------------------------
# Canonical JSON model
# -----------------------------------------------------------------------------
# The human-readable report below is rendered from the same underlying data.
# This avoids the two output modes drifting apart semantically.

GENERATED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

RESULT="$(
  jq -cn \
    --arg generatedAt "$GENERATED_AT" \
    --arg region "$REGION" \
    --arg profile "${PROFILE:-default}" \
    --arg managementAccountId "$ACCOUNT_ID" \
    --arg callerArn "$CALLER_ARN" \
    --argjson identity "$IDENTITY" \
    --argjson landingZones "$LANDING_ZONES_RAW" \
    --argjson landingZone "$LANDING_ZONE_DETAILS" \
    --argjson organization "$ORGANIZATION" \
    --argjson roots "$ROOTS" \
    --argjson accounts "$ACCOUNTS" \
    --argjson accountParents "$ACCOUNT_PARENTS" \
    --argjson organizationalUnits "$OUS" \
    --argjson serviceAccess "$SERVICE_ACCESS" \
    --argjson delegatedAdministrators "$DELEGATED_ADMINISTRATORS" \
    --argjson delegatedServices "$DELEGATED_SERVICES" \
    --argjson scps "$SCPS" \
    --argjson scpDocuments "$SCP_DOCUMENTS" \
    --argjson scpExplanations "$SCP_EXPLANATIONS" \
    --argjson policyAttachments "$POLICY_ATTACHMENTS" \
    --argjson enabledControls "$ENABLED_CONTROLS" \
    --argjson controlCatalogDetails "$CONTROL_CATALOG_DETAILS" \
    --argjson baselineDefinitions "$BASELINE_DEFINITIONS" \
    --argjson enabledBaselines "$ENABLED_BASELINES" \
    --argjson iamRoles "$CONTROL_TOWER_IAM_ROLES" \
    --argjson stacks "$CONTROL_TOWER_STACKS" \
    --argjson trails "$CLOUDTRAIL_TRAILS" \
    --argjson configRecorders "$CONFIG_RECORDERS" \
    --argjson configDeliveryChannels "$CONFIG_DELIVERY_CHANNELS" \
    --argjson bucketCandidates "$CONTROL_TOWER_BUCKET_CANDIDATES" \
    --argjson accountFactoryProducts "$ACCOUNT_FACTORY_PRODUCTS" \
    --argjson stackSets "$CONTROL_TOWER_STACKSETS" \
    --argjson stackSetInstances "$STACKSET_INVENTORY" \
    '{
      metadata:{
        generatedAt:$generatedAt,
        region:$region,
        profile:$profile,
        managementAccountId:$managementAccountId,
        callerArn:$callerArn
      },
      identity:$identity,
      controlTower:{
        landingZones:$landingZones,
        landingZone:$landingZone,
        enabledControlsByOu:$enabledControls,
        enabledControlExplanations:$controlCatalogDetails,
        baselineDefinitions:$baselineDefinitions,
        enabledBaselines:$enabledBaselines
      },
      organizations:{
        organization:$organization,
        roots:$roots,
        accounts:$accounts,
        accountParents:$accountParents,
        organizationalUnits:$organizationalUnits,
        trustedServiceAccess:$serviceAccess,
        delegatedAdministrators:$delegatedAdministrators,
        delegatedServices:$delegatedServices,
        serviceControlPolicies:$scps,
        serviceControlPolicyDocuments:$scpDocuments,
        serviceControlPolicyExplanations:$scpExplanations,
        policyAttachments:$policyAttachments
      },
      controlTowerUnderlyingResources:{
        discoveryNote:"Name-based candidates require ownership verification before modification.",
        iamRoleCandidates:$iamRoles,
        cloudTrail:$trails,
        configRecorders:$configRecorders,
        configDeliveryChannels:$configDeliveryChannels,
        loggingBucketCandidates:$bucketCandidates,
        accountFactoryProducts:$accountFactoryProducts
      },
      cloudFormation:{
        controlTowerStacks:$stacks,
        controlTowerStackSets:$stackSets,
        stackSetInstances:$stackSetInstances
      }
    }'
)"

if $JSON_MODE; then
  jq '.' <<<"$RESULT"
  exit 0
fi

# -----------------------------------------------------------------------------
# Human-readable renderer
# -----------------------------------------------------------------------------

printf '\nCONTROL TOWER DISCOVERY REPORT\n'
printf '==============================\n'
printf 'Generated:          %s\n' "$GENERATED_AT"
printf 'Region:             %s\n' "$REGION"
printf 'Profile:            %s\n' "${PROFILE:-default}"
printf 'Management account: %s\n' "$ACCOUNT_ID"
printf 'Caller:             %s\n' "$CALLER_ARN"

printf '\nLANDING ZONE\n'
printf '============\n'
cat <<'EOF'
Explanation: The landing zone is Control Tower's governed multi-account
foundation. Status reports lifecycle state; drift status reports whether
Control Tower-managed resources match expected configuration.
References:
  - What is AWS Control Tower?: https://docs.aws.amazon.com/controltower/latest/userguide/what-is-control-tower.html
  - Detect and resolve drift in AWS Control Tower: https://docs.aws.amazon.com/controltower/latest/userguide/drift.html

EOF

if [[ -n "$LANDING_ZONE_ARN" ]]; then
  printf 'ARN: %s\n' "$LANDING_ZONE_ARN"

  # API response shapes have evolved. Use optional fields defensively so a
  # missing convenience field does not break discovery.
  jq -r '
    (.landingZone // .) as $lz |
    "Version:                  \($lz.version // "unknown")",
    "Status:                   \($lz.status // "unknown")",
    "Latest available version: \($lz.latestAvailableVersion // "unknown")"
  ' <<<"$LANDING_ZONE_DETAILS" 2>/dev/null || true
else
  printf 'No landing zone returned in region %s.\n' "$REGION"
  if jq -e '.error?' >/dev/null 2>&1 <<<"$LANDING_ZONES_RAW"; then
    printf 'API error: %s\n' "$(jq -r '.error' <<<"$LANDING_ZONES_RAW")"
  fi
fi

printf '\nORGANIZATION\n'
printf '============\n'
cat <<'EOF'
Explanation: AWS Organizations supplies the hierarchy, accounts, and policy
boundaries on which Control Tower builds governance. OU membership alone does
not prove Control Tower enrollment.
References:
  - AWS Organizations terminology and concepts: https://docs.aws.amazon.com/organizations/latest/userguide/orgs_getting-started_concepts.html
  - Enroll an existing AWS account in Control Tower: https://docs.aws.amazon.com/controltower/latest/userguide/enroll-account.html

EOF

if jq -e '.Organization?' >/dev/null 2>&1 <<<"$ORGANIZATION"; then
  printf 'Organization ID: %s\n' \
    "$(jq -r '.Organization.Id // "unknown"' <<<"$ORGANIZATION")"
  printf 'Feature set:     %s\n' \
    "$(jq -r '.Organization.FeatureSet // "unknown"' <<<"$ORGANIZATION")"
else
  printf 'Unable to read organization: %s\n' \
    "$(jq -r '.error // "unknown error"' <<<"$ORGANIZATION")"
fi

printf '\nOrganizational Units:\n'
if (( $(jq 'length' <<<"$OUS") == 0 )); then
  printf '  (none discovered)\n'
else
  jq -r '.[] |
    "  \(.Name) [\(.Id)]",
    "    ARN:    \(.Arn)",
    "    Parent: \(.ParentId)"
  ' <<<"$OUS"
fi

printf '\nAccounts:\n'
if jq -e '.Accounts?' >/dev/null 2>&1 <<<"$ACCOUNTS"; then
  jq -r '.Accounts[] |
    "  \(.Name)  \(.Id)  \(.State // .Status // "unknown")  \(.Email)"
  ' <<<"$ACCOUNTS"
else
  printf '  Unable to list accounts: %s\n' \
    "$(jq -r '.error // "unknown error"' <<<"$ACCOUNTS")"
fi

printf '\nTRUSTED ACCESS AND DELEGATED ADMINISTRATION\n'
printf '===========================================\n'
cat <<'EOF'
Explanation: Trusted access lets listed AWS services perform organization-level
operations. Delegated administration lets supported services be administered
from a designated member account instead of the management account. Discovery
does not imply that every listed integration was created exclusively by Control
Tower.
References:
  - AWS Organizations trusted access: https://docs.aws.amazon.com/organizations/latest/userguide/orgs_integrate_services.html
  - Delegated administrator for AWS services: https://docs.aws.amazon.com/organizations/latest/userguide/orgs_integrate_services_delegate_admin.html

EOF

if jq -e '.EnabledServicePrincipals?' >/dev/null 2>&1 <<<"$SERVICE_ACCESS"; then
  jq -r '.EnabledServicePrincipals[]? | "  Trusted service: \(.ServicePrincipal)  enabled=\(.DateEnabled // "unknown")"' <<<"$SERVICE_ACCESS"
else
  printf 'Unable to list trusted service access: %s\n' "$(jq -r '.error // "unknown error"' <<<"$SERVICE_ACCESS")"
fi

if jq -e '.DelegatedAdministrators?' >/dev/null 2>&1 <<<"$DELEGATED_ADMINISTRATORS"; then
  jq -r '.DelegatedAdministrators[]? | "  Delegated administrator: \(.Name) [\(.Id)]  status=\(.Status // .State // "unknown")"' <<<"$DELEGATED_ADMINISTRATORS"
else
  printf 'Unable to list delegated administrators: %s\n' "$(jq -r '.error // "unknown error"' <<<"$DELEGATED_ADMINISTRATORS")"
fi

jq -r '.[] |
  "  Account services: \(.accountId)",
  (if .error != null then "    ERROR: \(.error)" elif (.services | length) == 0 then "    (none)" else (.services[] | "    - \(.ServicePrincipal)") end)
' <<<"$DELEGATED_SERVICES"

printf '\nACCOUNT PARENTS\n'
printf '===============\n'
cat <<'EOF'
Explanation: A direct parent identifies the root or OU from which an account
inherits Organizations policies. It does not by itself establish Control Tower
enrollment or AFT management.
References:
  - AWS Organizations inheritance for management policies: https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_inheritance_mgmt.html
  - Control Tower enrollment: https://docs.aws.amazon.com/controltower/latest/userguide/enroll-account.html

EOF
jq -r '.[] |
  "  \(.accountName) [\(.accountId)]",
  (if .error != null then "    ERROR: \(.error)" elif (.parents | length) == 0 then "    (no parent returned)" else (.parents[] | "    \(.Type): \(.Id)") end)
' <<<"$ACCOUNT_PARENTS"

printf '\nSERVICE CONTROL POLICIES\n'
printf '========================\n'

if jq -e '.Policies?' >/dev/null 2>&1 <<<"$SCPS"; then
  jq -r '.[] |
    "  \(.name) [\(.policyId)]  AWS-managed=\(.awsManaged)",
    (if .explanation != null then "    Explanation: \(.explanation)" else empty end),
    (if (.statements | length) == 0 then "    Statements: no parsed statement details available" else
      (.statements[] |
        "    Statement: \(.sid // "(no Sid)")  effect=\(.effect // "unknown")",
        (if (.actions | length) > 0 then "      Actions: \(.actions | join(", "))" else empty end),
        (if (.notActions | length) > 0 then "      NotActions: all actions except \(.notActions | join(", "))" else empty end),
        (if (.resources | length) > 0 then "      Resources: \(.resources | join(", "))" else empty end),
        (if .hasCondition then "      Conditions: present in the policy document; inspect JSON for exact exceptions" else empty end)
      )
    end),
    "    References:",
    (.references[] | "      - \(.title): \(.url)"),
    ""
  ' <<<"$SCP_EXPLANATIONS"
else
  printf 'Unable to list SCPs: %s\n' \
    "$(jq -r '.error // "unknown error"' <<<"$SCPS")"
fi

printf '\nSCP attachments by Root/OU:\n'
jq -r '.[] |
  "  \(.targetType): \(.targetName) [\(.targetId)]",
  (
    if .error != null then
      "    ERROR: \(.error)"
    elif (.policies | length) == 0 then
      "    (no SCPs)"
    else
      (.policies[] | "    - \(.Name) [\(.Id)]")
    end
  )
' <<<"$POLICY_ATTACHMENTS"

printf '\nCONTROL TOWER ENABLED CONTROLS\n'
printf '==============================\n'

if (( $(jq 'length' <<<"$ENABLED_CONTROLS") == 0 )); then
  printf '(No OUs discovered, so no OU control queries were made.)\n'
else
  jq -nr \
    --argjson enabled "$ENABLED_CONTROLS" \
    --argjson catalog "$CONTROL_CATALOG_DETAILS" '
      $enabled[] |
      "OU: \(.ouName) [\(.ouId)]",
      (if .error != null then
        "  ERROR: \(.error)"
      elif (.controls | length) == 0 then
        "  (no enabled controls returned)"
      else
        (.controls[] as $enabledControl |
          ($catalog[]? | select(.requestedArn == $enabledControl.controlIdentifier)) as $metadata |
          "  - \($enabledControl.controlIdentifier // "unknown")",
          "    Enabled ARN: \($enabledControl.arn // $enabledControl.enabledControlIdentifier // "unknown")",
          "    Status: \($enabledControl.statusSummary.status // $enabledControl.status // "unknown")",
          (if $metadata.error != null then
            "    Explanation unavailable: \($metadata.error)"
          elif $metadata.details != null then
            "    Name: \($metadata.details.Name // "unknown")",
            "    Explanation: \($metadata.details.Description // "No AWS description returned")",
            "    Behavior: \($metadata.details.Behavior // "unknown")",
            "    Severity: \($metadata.details.Severity // "unknown")",
            "    Implementation: \($metadata.details.Implementation.Type // "unknown") / \($metadata.details.Implementation.Identifier // "not specified")",
            "    Scope: \($metadata.details.RegionConfiguration.Scope // "unknown")",
            (if (($metadata.details.GovernedResources // []) | length) > 0 then
              "    Governed resources: \($metadata.details.GovernedResources | join(", "))"
            else empty end),
            "    References:",
            ($metadata.references[] | "      - \(.title): \(.url)")
          else
            "    Explanation unavailable: AWS Control Catalog returned no metadata"
          end),
          ""
        )
      end)
    '
fi

printf '\nENABLED BASELINES\n'
printf '=================\n'
cat <<'EOF'
Explanation: A baseline is a group of resources and controls applied to a
Control Tower target. An Organizations OU is not governed merely because it
exists; the appropriate Control Tower baseline must be enabled successfully.
References:
  - AWS Control Tower baselines: https://docs.aws.amazon.com/controltower/latest/userguide/baselines.html
  - Register an existing OU with Control Tower: https://docs.aws.amazon.com/controltower/latest/userguide/register-existing-ou.html

EOF

if jq -e '.enabledBaselines?' >/dev/null 2>&1 <<<"$ENABLED_BASELINES"; then
  if (( $(jq '.enabledBaselines | length' <<<"$ENABLED_BASELINES") == 0 )); then
    printf '(No enabled baselines returned.)\n'
  else
    jq -r '.enabledBaselines[] |
      "  Target:   \(.targetIdentifier // "unknown")",
      "  Baseline: \(.baselineIdentifier // "unknown")",
      "  Status:   \(.statusSummary.status // .status // "unknown")",
      "  ARN:      \(.arn // "unknown")",
      ""
    ' <<<"$ENABLED_BASELINES"
  fi
elif jq -e '.error?' >/dev/null 2>&1 <<<"$ENABLED_BASELINES"; then
  printf 'Unable to list enabled baselines: %s\n' \
    "$(jq -r '.error' <<<"$ENABLED_BASELINES")"
else
  printf '(No enabled baselines returned.)\n'
fi

printf '\nUNDERLYING CONTROL TOWER RESOURCE CANDIDATES\n'
printf '============================================\n'
cat <<'EOF'
Explanation: Control Tower orchestrates Organizations, IAM, CloudFormation,
CloudTrail, Config, S3, and Service Catalog resources. Name-based matches are
candidates, not ownership proof. Verify tags, policies, StackSet lineage, and
AWS documentation before modification.
References:
  - Resources created and managed by Control Tower: https://docs.aws.amazon.com/controltower/latest/userguide/shared-account-resources.html
  - Control Tower roles and resources: https://docs.aws.amazon.com/controltower/latest/userguide/roles-how.html

EOF

printf 'IAM roles:\n'
if jq -e '.error?' >/dev/null 2>&1 <<<"$CONTROL_TOWER_IAM_ROLES"; then
  printf '  ERROR: %s\n' "$(jq -r '.error' <<<"$CONTROL_TOWER_IAM_ROLES")"
elif (( $(jq 'length' <<<"$CONTROL_TOWER_IAM_ROLES") == 0 )); then
  printf '  (none matched)\n'
else
  jq -r '.[] | "  \(.RoleName)  \(.Arn)"' <<<"$CONTROL_TOWER_IAM_ROLES"
fi

printf '\nCloudTrail trails:\n'
if jq -e '.trailList?' >/dev/null 2>&1 <<<"$CLOUDTRAIL_TRAILS"; then
  jq -r '.trailList[]? | "  \(.Name)  home=\(.HomeRegion) multi-region=\(.IsMultiRegionTrail) bucket=\(.S3BucketName // "none")"' <<<"$CLOUDTRAIL_TRAILS"
else
  printf '  ERROR: %s\n' "$(jq -r '.error // "unknown error"' <<<"$CLOUDTRAIL_TRAILS")"
fi

printf '\nAWS Config:\n'
if jq -e '.ConfigurationRecorders?' >/dev/null 2>&1 <<<"$CONFIG_RECORDERS"; then
  jq -r '.ConfigurationRecorders[]? | "  Recorder: \(.name) role=\(.roleARN)"' <<<"$CONFIG_RECORDERS"
else
  printf '  Recorder error: %s\n' "$(jq -r '.error // "unknown error"' <<<"$CONFIG_RECORDERS")"
fi
if jq -e '.DeliveryChannels?' >/dev/null 2>&1 <<<"$CONFIG_DELIVERY_CHANNELS"; then
  jq -r '.DeliveryChannels[]? | "  Delivery: \(.name) bucket=\(.s3BucketName // "none") topic=\(.snsTopicARN // "none")"' <<<"$CONFIG_DELIVERY_CHANNELS"
else
  printf '  Delivery error: %s\n' "$(jq -r '.error // "unknown error"' <<<"$CONFIG_DELIVERY_CHANNELS")"
fi

printf '\nLogging bucket candidates visible in the management account:\n'
if jq -e '.error?' >/dev/null 2>&1 <<<"$CONTROL_TOWER_BUCKET_CANDIDATES"; then
  printf '  ERROR: %s\n' "$(jq -r '.error' <<<"$CONTROL_TOWER_BUCKET_CANDIDATES")"
elif (( $(jq 'length' <<<"$CONTROL_TOWER_BUCKET_CANDIDATES") == 0 )); then
  printf '  (none matched; central buckets commonly reside in Log Archive)\n'
else
  jq -r '.[] | "  \(.Name)"' <<<"$CONTROL_TOWER_BUCKET_CANDIDATES"
fi

printf '\nAccount Factory products:\n'
if jq -e '.error?' >/dev/null 2>&1 <<<"$ACCOUNT_FACTORY_PRODUCTS"; then
  printf '  ERROR: %s\n' "$(jq -r '.error' <<<"$ACCOUNT_FACTORY_PRODUCTS")"
elif (( $(jq 'length' <<<"$ACCOUNT_FACTORY_PRODUCTS") == 0 )); then
  printf '  (none matched)\n'
else
  jq -r '.[] | "  \(.ProductViewSummary.Name)  product=\(.ProductViewSummary.ProductId // .ProductViewSummary.Id // "unknown")"' <<<"$ACCOUNT_FACTORY_PRODUCTS"
fi

printf '\nCONTROL TOWER STACKS\n'
printf '====================\n'
cat <<'EOF'
Explanation: CloudFormation stacks and StackSets are implementation mechanisms
used by Control Tower to deploy and maintain resources. Do not modify a matched
stack solely because it appears in this report; first confirm ownership.
References:
  - Control Tower and StackSets: https://docs.aws.amazon.com/controltower/latest/userguide/how-control-tower-works.html
  - AWS CloudFormation StackSets concepts: https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/what-is-cfnstacksets.html

EOF
if jq -e '.error?' >/dev/null 2>&1 <<<"$CONTROL_TOWER_STACKS"; then
  printf 'Unable to list stacks: %s\n' "$(jq -r '.error' <<<"$CONTROL_TOWER_STACKS")"
elif (( $(jq 'length' <<<"$CONTROL_TOWER_STACKS") == 0 )); then
  printf '(No active management-account stacks matching Control Tower were found.)\n'
else
  jq -r '.[] | "  \(.StackName)  status=\(.StackStatus // "unknown")"' <<<"$CONTROL_TOWER_STACKS"
fi

printf '\nCONTROL TOWER STACKSETS\n'
printf '=======================\n'
cat <<'EOF'
Explanation: StackSets deploy stack instances across accounts and Regions.
Control Tower uses them for governed-account resources; instance status helps
identify rollout failures but is not a complete Control Tower drift assessment.
References:
  - AWS CloudFormation StackSets concepts: https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/what-is-cfnstacksets.html
  - Detect and resolve Control Tower drift: https://docs.aws.amazon.com/controltower/latest/userguide/drift.html

EOF

if jq -e '.error?' >/dev/null 2>&1 <<<"$CONTROL_TOWER_STACKSETS"; then
  printf 'Unable to list StackSets: %s\n' \
    "$(jq -r '.error' <<<"$CONTROL_TOWER_STACKSETS")"
elif (( $(jq 'length' <<<"$CONTROL_TOWER_STACKSETS") == 0 )); then
  printf '(No active StackSets matching ControlTower/Control Tower were found.)\n'
else
  jq -r '.[] |
    "  \(.StackSetName)  status=\(.Status // "unknown")"
  ' <<<"$CONTROL_TOWER_STACKSETS"

  printf '\nStackSet instances:\n'
  jq -r '.[] |
    "  \(.stackSetName)",
    (
      if .error != null then
        "    ERROR: \(.error)"
      elif (.instances | length) == 0 then
        "    (no stack instances returned)"
      else
        (.instances[] |
          "    account=\(.Account // "unknown") region=\(.Region // "unknown") status=\(.Status // "unknown")")
      end
    )
  ' <<<"$STACKSET_INVENTORY"
fi

printf '\nNEXT STEPS\n'
printf '==========\n'
cat <<'EOF'
Use this report as the starting inventory for the Week 1 Control Tower exercise:

  1. Compare Control Tower's view with Organizations and StackSets.
  2. Inspect the discovered SCPs and map them to preventive controls.
  3. Inspect StackSet-created resources in one governed member account.
  4. Use CloudTrail to trace Control Tower/CloudFormation activity.
  5. Treat name-based IAM/S3/CloudFormation matches as candidates and verify ownership.
  6. Save redacted --json output as evidence before and after safe tests.

Example:

  ./discover-control-tower-resources.sh --json > artifacts/control-tower-inventory.json

Then diff inventories after an experiment:

  diff -u \
    <(jq -S . inventory-before.json) \
    <(jq -S . inventory-after.json)

A difference is not automatically "drift"; it is evidence to investigate.
Control Tower's own drift/status APIs remain the authoritative source for
whether Control Tower considers a governed resource or baseline drifted.

Do not commit raw inventory: it contains account IDs, account emails, ARNs,
role names, policies, and infrastructure topology. Redact it first.
EOF
