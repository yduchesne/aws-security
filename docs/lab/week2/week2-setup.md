# Week 2 Lab Setup

## Purpose

This guide contains the preparation shared by all Week 2 exercises: IAM
Identity Center access, the persistent permissions-boundary baseline, AWS CLI
profiles, and temporary exercise-user assignments.

Read the general [lab setup](../lab-setup.md) first. Exercise-specific commands
for Exercise 1 are in [`exercise1-instructions.md`](exercise1/exercise1-instructions.md),
and Exercise 2 in [`exercise2-instructions.md`](exercise2/exercise2-instructions.md).
The exercise catalog is in [`week2-summary.md`](week2-summary.md).

## Prerequisites

Before a developer starts a Week 2 exercise, an authorized platform operator must
verify:

1. The Dev Lab/source and Test Lab/target accounts exist, are enrolled, and are
   governed.
2. `terraform/lab/week2/baseline` has created
   `/week2/WorkloadLabRoleBoundary` in both accounts.
3. `terraform/identity_center/workload_access` has assigned
   `WorkloadLabAdministrator` to `WorkloadLabAdministrators` in both allowlisted
   lab accounts.
4. The dedicated `sso_lab_admin` user is activated with MFA and can select
   `WorkloadLabBaselineAdmin` in both lab accounts.
5. The two test users are activated, have MFA, and have temporary membership in
   `WorkloadLabAdministrators`.
6. Organization CloudTrail logging and the required evidence-retention path are
   healthy.

The intended users are:

| Exercise role | IAM Identity Center user | Account |
|---|---|---|
| Source operator | `${TF_VAR_test_user1_email}` | Dev Lab/source |
| Target operator | `${TF_VAR_test_user2_email}` | Test Lab/target |

The current design assigns one `WorkloadLabAdministrators` group to both lab
accounts. Both group members can therefore see both account assignments. Using
test1 for the source profile and test2 for the target profile is an operating
convention, not an exclusive user-to-account authorization boundary.

## Platform preparation

### Configure lab baseline administration

Set `TF_VAR_sso_lab_admin_email`, `TF_VAR_sso_lab_admin_first_name`, and
`TF_VAR_sso_lab_admin_last_name` for a distinct accountable human. Configure
`TF_VAR_lab_account_ids` with both enrolled lab account IDs. On the first
deployment, the parent root must create the user before the workload-access
root can look it up. Plan and apply that root first:

```bash
terraform -chdir=terraform/identity_center plan
terraform -chdir=terraform/identity_center apply
```

Then plan and apply the complete Identity Center phase:

```bash
./tf.sh --phase identity-center --dry-run
./tf.sh --phase identity-center --apply
```

On later converged runs, the normal complete phase is sufficient. The parent
root creates the named user. The workload-access root looks it up,
creates `WorkloadLabBaselineAdministrators` and the protected one-hour
`WorkloadLabBaselineAdmin` permission set, manages the user's group
membership, and assigns that access directly to the allowlisted Dev Lab and
Test Lab accounts. Activate the user and register strong MFA before configuring
the baseline profiles.

### Deploy the Dev Lab network foundation

After AFT provisions and Control Tower enrolls the Dev Lab account, create the
reusable VPC and tagged public subnet used by Exercise 8:

```bash
./tf.sh --phase lab-foundation --dry-run
./tf.sh --phase lab-foundation --apply
```

Review the configured CIDRs for overlap. The plan must create no NAT gateway or
EC2 instance. Exercise 8 discovers the subnet through
`Purpose=LabExercises` and `Network=Public`; test users receive no VPC,
route-table, subnet, or internet-gateway administration.

### Deploy the shared lab evidence trail

After the landing zone and Identity Center phase converge, deploy the separate
customer-managed S3-only organization trail and its dedicated Log Archive
bucket:

```bash
./tf.sh --phase lab-evidence --dry-run
./tf.sh --phase lab-evidence --apply
```

The plan must not modify the Control Tower-managed trail or logging buckets. It
should create only the resources owned by
[`terraform/lab/evidence/`](../../../terraform/lab/evidence/): the dedicated
evidence bucket and controls in Log Archive plus the customer-managed
organization trail in the management account.

The workload-access permission set references the deterministic evidence bucket
and grants `WorkloadLabAdministrator` read-only access to the Dev Lab and Test
Lab log prefixes. If that permission-set change was applied after the current
SSO session began, log out and sign in again before testing evidence access.
Lab users remain in the Dev/Test accounts and receive no Log Archive account
assignment.

See [`cloud-trail-logs.md`](../../cloud-trail-logs.md) for ownership, event
selectors, access controls, retrieval, cost, and destruction behavior.

### Deploy the Week 2 baseline

Regular exercise developers should not deploy the baseline unless they are the
authorized baseline operator. The dedicated named user configured through
`TF_VAR_sso_lab_admin_*` must authenticate two IAM Identity Center profiles
directly into the Dev Lab and Test Lab accounts using
`WorkloadLabBaselineAdmin`. The baseline providers do not call
`sts:AssumeRole`. These setup profiles must not use the bounded
`WorkloadLabAdministrator` exercise permission set.

From the repository root, prepare an uncommitted variable file based on:

```text
terraform/lab/week2/baseline/terraform.tfvars.example
```

Set:

- `lab_account_ids.dev` to the Dev Lab/source account ID;
- `lab_account_ids.test` to the Test Lab/target account ID;
- `lab_baseline_aws_profiles.dev` and `.test` to the authenticated trusted
  setup profile names;
- The state bucket and Region during backend initialization.

The baseline and workload-access roots intentionally share
`TF_VAR_lab_account_ids`; the baseline does not use separate
`TF_VAR_source_account_id` and `TF_VAR_target_account_id` inputs. Exercise 1
still uses source and target IDs because those names describe the direction of
the cross-account test.

Terraform does not load `.env` or `.env.example` automatically. `.env.example`
is only a template. Either copy its required values into an uncommitted
`terraform.tfvars`, pass a `-var-file`, or export the variables in the current
shell. If the project environment file contains shell `export` statements,
load it before direct Terraform commands:

```bash
source "${TF_ENV_FILE:-$HOME/.env/aws-security/terraform/.env}"
```

Do not print, inspect, or commit the environment file. Verify the required
values are exported without displaying their contents:

```bash
test -n "$TF_VAR_lab_account_ids"
test -n "$TF_VAR_lab_baseline_aws_profiles"
```

#### Configure the lab baseline administrator profiles

See [`sso_auth.md`](../../sso_auth.md) for browser-session isolation, private-window
behavior, and the `--use-device-code --no-browser` login flow.

Both profiles use the named human configured by
`TF_VAR_sso_lab_admin_email`, but select different account assignments. They
intentionally share the single `lab-admin` SSO session because the user,
Identity Center instance, Region, permission set, and administrative purpose
are the same; only the selected AWS account differs:

```text
lab-admin-dev
  → Dev Lab account
  → WorkloadLabBaselineAdmin

lab-admin-test
  → Test Lab account
  → WorkloadLabBaselineAdmin
```

The Identity Center phase must have created the user, group membership,
permission set, and both account assignments before these profiles are
configured. Activate the user, register MFA, and obtain the organization's AWS
access-portal URL. The examples assume the Identity Center Region is
`us-east-2`.

Configure the Dev Lab profile:

```bash
aws configure sso --profile lab-admin-dev
```

Use or select:

```text
SSO session name: lab-admin
SSO start URL: https://<identity-center-instance>.awsapps.com/start
SSO region: us-east-2
SSO registration scopes: sso:account:access
AWS account: Dev Lab
Role/permission set: WorkloadLabBaselineAdmin
Default client Region: us-east-2
Output format: json
```

When browser authorization opens, sign in as the user represented by
`TF_VAR_sso_lab_admin_email`.

Configure the Test Lab profile and deliberately reuse the same `lab-admin` SSO
session:

```bash
aws configure sso --profile lab-admin-test
```

Select:

```text
SSO session name: lab-admin
AWS account: Test Lab
Role/permission set: WorkloadLabBaselineAdmin
Default client Region: us-east-2
Output format: json
```

The resulting shared AWS configuration should resemble:

```ini
[sso-session lab-admin]
sso_start_url = https://<identity-center-instance>.awsapps.com/start
sso_region = us-east-2
sso_registration_scopes = sso:account:access

[profile lab-admin-dev]
sso_session = lab-admin
sso_account_id = <TF_LAB_DEV_ACCOUNT_ID>
sso_role_name = WorkloadLabBaselineAdmin
region = us-east-2
output = json

[profile lab-admin-test]
sso_session = lab-admin
sso_account_id = <TF_LAB_TEST_ACCOUNT_ID>
sso_role_name = WorkloadLabBaselineAdmin
region = us-east-2
output = json
```

Do not add access keys or copied temporary credentials. The profile is
associated with the intended human when that user completes `aws sso login`;
the email address is not stored in the profile itself.

Authenticate and verify both account selections. See
[`sso_auth.md`](../../sso_auth.md) for details about device authorization,
private-browser isolation, and the behavior of `--no-browser`:

```bash
aws sso login \
  --profile lab-admin-dev \
  --use-device-code \
  --no-browser

aws sso login \
  --profile lab-admin-test \
  --use-device-code \
  --no-browser

aws sts get-caller-identity --profile lab-admin-dev
aws sts get-caller-identity --profile lab-admin-test
```

The first command must report `TF_LAB_DEV_ACCOUNT_ID`, the second must report
`TF_LAB_TEST_ACCOUNT_ID`, and both assumed-role ARNs must contain
`AWSReservedSSO_WorkloadLabBaselineAdmin_`. Stop if either account or role is
unexpected. If the browser uses the wrong Identity Center user, run
`aws sso logout`, sign out of the access portal, and authenticate again in a
private browser window.

Ensure Terraform references the exact profile names:

```bash
export TF_VAR_lab_baseline_aws_profiles='{"dev":"lab-admin-dev","test":"lab-admin-test"}'
```

The associated permission set can create and maintain only
`/week2/WorkloadLabRoleBoundary`. The baseline providers use the SSO profiles
directly and do not make an additional `sts:AssumeRole` call. Sign out after
the baseline converges and monitor all subsequent use of this privileged
persona.

Initialize the independent remote state:

```bash
terraform -chdir=terraform/lab/week2/baseline init \
  -backend-config="bucket=$TF_STATE_BUCKET" \
  -backend-config="region=$TF_STATE_REGION" \
  -backend-config="key=exercises/week2/baseline/terraform.tfstate"
```

Validate and review the plan:

```bash
terraform -chdir=terraform/lab/week2/baseline validate
terraform -chdir=terraform/lab/week2/baseline plan
```

The plan must create or converge exactly two customer-managed policies named:

```text
/week2/WorkloadLabRoleBoundary
```

It must not replace unrelated IAM policies or modify Control Tower resources.
After review, an authorized operator may apply:

```bash
terraform -chdir=terraform/lab/week2/baseline apply
```

Run another plan after apply and verify that it reports no changes. Do not
remove `prevent_destroy` merely to make an unexplained plan succeed.

### Configure exercise-user lab assignments

This section contains commands that must be run **only when preparing to run
Exercise 1 or another Week 2 exercise**. They configure bounded exercise
access; they are not needed to create the lab-baseline administrator access.

The first command supplies the two lab account IDs. The second tells Terraform
to assign `WorkloadLabAdministrator` to the `WorkloadLabAdministrators` group
in both accounts. Run these commands in the same shell that will run `tf.sh`:

```bash
export TF_VAR_lab_account_ids="{\"dev\":\"$TF_LAB_DEV_ACCOUNT_ID\",\"test\":\"$TF_LAB_TEST_ACCOUNT_ID\"}"
export TF_VAR_account_assignments="{
  \"dev_lab_exercise_administrators\": {
    \"account_id\": \"$TF_LAB_DEV_ACCOUNT_ID\",
    \"environment\": \"dev\",
    \"group_key\": \"lab_administrators\",
    \"permission_set_key\": \"lab_administrator\"
  },
  \"test_lab_exercise_administrators\": {
    \"account_id\": \"$TF_LAB_TEST_ACCOUNT_ID\",
    \"environment\": \"test\",
    \"group_key\": \"lab_administrators\",
    \"permission_set_key\": \"lab_administrator\"
  }
}"
```

These are Terraform input variables; this document does not execute them. If
the values are stored in the project environment file, source that file first.
Otherwise run the exports manually. Do not commit the environment file or a
local `terraform.tfvars`.

Review and apply the assignments with the repository workflow:

```bash
./tf.sh --phase identity-center --dry-run
./tf.sh --phase identity-center --apply
```

Before applying, verify that the plan changes only
project-owned workload-access resources and targets exactly the Dev Lab and
Test Lab account IDs.

The workload-access root creates the group-to-permission-set-to-account
assignments, but intentionally does **not** add either test user to the group.
User membership is a separate temporary operation. After the assignment apply
succeeds:

1. Open the `WorkloadLabAdministrators` group in IAM Identity Center.
2. Add the user represented by `TF_VAR_test_user1_email` for the source-side
   test.
3. Add the user represented by `TF_VAR_test_user2_email` for the target-side
   test.
4. Confirm both users have MFA and can select `WorkloadLabAdministrator` in the
   lab account needed for the test.
5. Record the approver, start time, and expiration time for the temporary grant.
6. Remove both users from the group immediately after testing.

The same group is assigned to both lab accounts, so each member technically
receives the permission set in both accounts. Using test1 with `week2-source`
and test2 with `week2-target` is an operating convention, not strict account
isolation. Separate groups would be required for strict isolation.

## Configure the AWS CLI for the test users

Use the browser-isolation and device-authorization procedure in
[`sso_auth.md`](../../sso_auth.md), especially when switching between the two test
identities.

### Requirements

Install AWS CLI version 2 and obtain the IAM Identity Center access-portal URL.
The examples assume the Identity Center Region is `us-east-2`.

The CLI profiles contain portal, account, and permission-set metadata. They do
not contain access keys. A profile is associated with a particular user only
when that user completes `aws sso login`; the profile name itself does not
cryptographically bind it to an email address.

These test-user profiles must not reuse the `lab-admin` SSO session. Unlike the
two baseline profiles, `week2-source` and `week2-target` represent different
human users and therefore use distinct SSO sessions.

### Configure the source profile as test1

Run:

```bash
aws configure sso --profile week2-source
```

Use:

```text
SSO session name: week2-test1
SSO start URL: https://<identity-center-instance>.awsapps.com/start
SSO region: us-east-2
SSO registration scopes: sso:account:access
Account: Dev Lab/source
Role/permission set: WorkloadLabAdministrator
Default client Region: us-east-2
Output format: json
```

Complete browser authorization as:

```text
${TF_VAR_test_user1_email}
```

### Configure the target profile as test2

Run:

```bash
aws configure sso --profile week2-target
```

Use a different SSO session name:

```text
SSO session name: week2-test2
SSO start URL: https://<identity-center-instance>.awsapps.com/start
SSO region: us-east-2
SSO registration scopes: sso:account:access
Account: Test Lab/target
Role/permission set: WorkloadLabAdministrator
Default client Region: us-east-2
Output format: json
```

Complete browser authorization as:

```text
${TF_VAR_test_user2_email}
```

Use separate browser profiles or private windows. Otherwise the browser may
reuse test1's portal session while authorizing `week2-target`.

The resulting `~/.aws/config` should resemble:

```ini
[sso-session week2-test1]
sso_start_url = https://<identity-center-instance>.awsapps.com/start
sso_region = us-east-2
sso_registration_scopes = sso:account:access

[profile week2-source]
sso_session = week2-test1
sso_account_id = <TF_LAB_DEV_ACCOUNT_ID>
sso_role_name = WorkloadLabAdministrator
region = us-east-2
output = json

[sso-session week2-test2]
sso_start_url = https://<identity-center-instance>.awsapps.com/start
sso_region = us-east-2
sso_registration_scopes = sso:account:access

[profile week2-target]
sso_session = week2-test2
sso_account_id = <TF_LAB_TEST_ACCOUNT_ID>
sso_role_name = WorkloadLabAdministrator
region = us-east-2
output = json
```

Do not add `aws_access_key_id`, `aws_secret_access_key`, or copied session
tokens.

### Log in and verify account selection

Authorize each session with the intended browser identity:

```bash
aws sso login \
  --profile week2-source \
  --use-device-code \
  --no-browser

aws sso login \
  --profile week2-target \
  --use-device-code \
  --no-browser
```

Verify both sessions before running Terraform:

```bash
aws sts get-caller-identity --profile week2-source
aws sts get-caller-identity --profile week2-target
```

The first command must return the Dev Lab/source account ID and the second the
Test Lab/target account ID. Both ARNs should contain an
`AWSReservedSSO_WorkloadLabAdministrator_...` role name. Stop if either account
is unexpected.
