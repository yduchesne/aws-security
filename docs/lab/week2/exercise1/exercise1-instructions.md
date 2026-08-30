# [Core] Week 2 Exercise 1 Setup and Execution

This exercise is classified as **Core** in the Week 2 curriculum.

This guide covers Exercise 1 resources, execution, authorization tests,
evidence, and cleanup. Complete the [Week 2 shared setup](../week2-setup.md)
before using this guide. Browser and device-code authentication behavior is
documented in [AWS CLI IAM Identity Center authentication](../../../sso_auth.md).

## Introduction

### Goals

This exercise demonstrates how AWS evaluates a two-stage, cross-account role
chain. The objective is to prove that cross-account access requires compatible
authorization on both sides of the account boundary:

```text
Source-side identity permission
  +
Target-side role trust
  +
Target role's effective permissions
  =
Successful cross-account access
```

You will observe that:

- IAM Identity Center provides short-lived credentials for the initial human
  sessions.
- A source-account role can call `sts:AssumeRole` only for an explicitly named
  target role.
- The target role trusts one approved source role rather than the entire source
  account.
- The assumed target role can read only a selected S3 resource.
- Write access and unrelated-resource access remain implicitly denied.
- An identity-side `sts:AssumeRole` allow is insufficient when the target trust
  policy excludes the caller.
- CloudTrail records the principals and role sessions involved in the chain.

### High-level tasks

The exercise proceeds as follows:

1. Authenticate separate test users to the Dev Lab/source and Test Lab/target
   accounts.
2. Configure Terraform inputs, including the IAM Identity Center-provisioned
   source role ARN.
3. Use Terraform to create bounded source roles, a bounded target role, and two
   disposable S3 test resources.
4. Configure AWS CLI role profiles that form an approved chain and an
   intentionally untrusted chain.
5. Test successful role assumption and selected S3 reads.
6. Test denied writes, denied unrelated-resource reads, and denied role
   assumption by an untrusted caller.
7. Inspect CloudTrail and explain each result using IAM policy-evaluation logic.
8. Destroy only the disposable Exercise 1 resources.

The persistent `WorkloadLabRoleBoundary` policies are prerequisites owned by
`terraform/lab/week2/baseline`; they are not Exercise 1 resources and must not
be destroyed during exercise cleanup.

## Table of contents

- [Introduction](#introduction).
  - [Goals](#goals).
  - [High-level tasks](#high-level-tasks).
- [Configure Exercise 1 inputs](#configure-exercise-1-inputs).
  - [Prepare the `.env` file](#prepare-the-env-file).
  - [Create the AWS CLI profiles](#create-the-aws-cli-profiles).
  - [Add the role-chain profiles](#add-the-role-chain-profiles-to-awsconfig).
- [Some Useful Background](#some-useful-background).
  - [Provisioned IAM Role](#provisioned-iam-role).
- [Initialize, validate, and plan](#initialize-validate-and-plan).
- [Configure role chaining for tests](#configure-role-chaining-for-tests).
- [Execute the authorization tests](#execute-the-authorization-tests).
  - [Test 1 — Approved role chain reaches the target role](#test-1--approved-role-chain-reaches-the-target-role).
  - [Test 2 — List the approved bucket](#test-2--list-the-approved-bucket).
  - [Test 3 — Read the approved object](#test-3--read-the-approved-object).
  - [Test 4 — Attempt to write to the approved bucket](#test-4--attempt-to-write-to-the-approved-bucket).
  - [Test 5 — Attempt to list the unrelated bucket](#test-5--attempt-to-list-the-unrelated-bucket).
  - [Test 6 — Attempt the untrusted cross-account chain](#test-6--attempt-the-untrusted-cross-account-chain).
- [Evidence and security analysis](#evidence-and-security-analysis).
- [Investigating in the Console](#investigating-in-the-console).
- [Clean up](#clean-up).
- [References](#references).

## Configure Exercise 1 inputs

### Prepare the .env file
Open a terminal and source the global project environment:

```bash
source ~/.env/aws-security/terraform/.env
```

The Exercise 1 Terraform root is:

```text
terraform/lab/week2/exercise1
```

Create its local environment file:

```bash
cp terraform/lab/week2/exercise1/.env.example terraform/lab/week2/exercise1/.env
```

Replace every placeholder in the copied file. Configure:

1. the Dev Lab/source and Test Lab/target account IDs;
2. `week2-source` and `week2-target` as the AWS profiles;
3. two globally unique bucket names beginning with `aws-security-week2-`.

The exercise `.env` is a shell script. Every assignment must use `export` and
must not contain spaces around `=`:

An example of the resulting `.env` file:

```bash
export TF_VAR_source_account_id="${TF_LAB_DEV_ACCOUNT_ID}"
export TF_VAR_target_account_id="${TF_LAB_TEST_ACCOUNT_ID}"
export TF_VAR_source_aws_profile="week2-source"
export TF_VAR_target_aws_profile="week2-target"

export TF_VAR_lab_role_boundary_name="WorkloadLabRoleBoundary"
export TF_VAR_lab_role_boundary_path="/week2/"

export TF_VAR_approved_bucket_name="aws-security-week2-${TF_MANAGEMENT_ACCOUNT_ID}-approved"
export TF_VAR_unrelated_bucket_name="aws-security-week2-${TF_MANAGEMENT_ACCOUNT_ID}-unrelated"
```

In the above, the values for the following interpolated environment variables are expected
to come from the global `.env` file, which you should have create as per
instructions: `~/.env/aws-security/terraform/.env`.

- `TF_LAB_DEV_ACCOUNT_ID`: Correponds to the `Dev Lab` workload account ID.
- `TF_LAB_TEST_ACCOUNT_ID`: Correspond to the `Test Lab` workload account ID.
- `TF_MANAGEMENT_ACCOUNT_ID`: Correspond to the ID of the management account.

Terraform derives a suffix-resilient `WorkloadLabAdministrator` role ARN
pattern from the source account ID and home Region. No generated IAM Identity
Center role suffix is required as an input.

For now, make sure to source the source the completed file, to load the variables into your
shell:

```bash
source terraform/lab/week2/exercise1/.env
```

### Create the AWS CLI profiles

Exercise 1 uses two kinds of AWS CLI profile:

1. **Direct IAM Identity Center profiles** establish the two provisioning and
   evidence sessions. `week2-source` is the session for test user 1 in the Dev
   Lab/source account, and `week2-target` is the session for test user 2 in the
   Test Lab/target account. Terraform uses these profiles through its aliased
   `aws.source` and `aws.target` providers. The target profile is also used to
   inspect CloudTrail and the target account directly.
2. **Role-chain profiles** exercise the authorization model. The caller
   profiles assume the disposable source roles. The final target profiles then
   use those caller sessions to request `CrossAccountReadRole`. These profiles
   contain role metadata only; the AWS CLI obtains short-lived credentials at
   runtime and does not store access keys.

The two direct profiles must use separate SSO sessions because they represent
the separate test users we have created in Identity Center. They are created by
Terraform and correspond to `TF_VAR_test_user1_email` and `TF_VAR_test_user2_email`
in the global `.env` file. You should recognize them in Identity Center through
their email addresses, which should have the format `<base_name>+test1@<domain>`
or `<base_name>+test2@<domain>`.

The accounts for these users must have been "activated": they must have a verified email;
MFA must have been enabled; they should have a password.

See the _Enable an IAM Identity Center user account_ section of
[SSO Auth](../../../sso_auth.md) for the details on this.

#### Configure the source profile as test user 1:

```bash
aws configure sso --profile week2-source
```

Select or enter:

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

Notes:
- You may obtain the value for "SSO start URL" from Identity Center
  (got to Identity Center > Dashboard, that look on the right-hand side. Pick the IPv4 URL).
- For SSO region, pick the region in which you created Identity Center (what is referred to as the "home region" in this project). Your region might not be us-east-2.
- For Account: pick the Dev Lab account in the drop-down.
- For Default client region: pick your "home region", as well.

#### Configure the target profile as test user 2

We are using a different SSO session name and a separate browser context:

```bash
aws configure sso --profile week2-target
```

Select:

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

Authenticate and verify these direct profiles before running Terraform:

```bash
aws sso login --profile week2-source --use-device-code --no-browser
aws sso login --profile week2-target --use-device-code --no-browser

aws sts get-caller-identity --profile week2-source
aws sts get-caller-identity --profile week2-target
```

Expected results are:

```text
week2-source → Dev Lab account + AWSReservedSSO_WorkloadLabAdministrator_<SUFFIX>
week2-target → Test Lab account + AWSReservedSSO_WorkloadLabAdministrator_<SUFFIX>
```

The account IDs must match `TF_VAR_source_account_id` and
`TF_VAR_target_account_id`, respectively. Stop if either account or permission
set is unexpected. See [the SSO authentication guide](../../../sso_auth.md)
for browser-session isolation and device-code behavior.

### Add the role-chain profiles to `~/.aws/config`

After Terraform has been applied, obtain the required role ARNs:

```bash
export EXERCISE_ROOT="terraform/lab/week2/exercise1"
echo "approved_caller_role_arn: $(terraform -chdir=$EXERCISE_ROOT output -raw approved_caller_role_arn)"
echo "untrusted_caller_role_arn: $(terraform -chdir=$EXERCISE_ROOT output -raw untrusted_caller_role_arn)"
echo "target_read_role_arn: $(terraform -chdir=$EXERCISE_ROOT output -raw target_read_role_arn)"
```

Append the following profiles to `~/.aws/config`, replacing the placeholders
with those output values - do not put the values within quotes.

```ini
[profile week2-approved-caller]
source_profile = week2-source
role_arn = <approved_caller_role_arn>
role_session_name = week2-approved-caller
region = us-east-2

[profile week2-target-read]
source_profile = week2-approved-caller
role_arn = <target_read_role_arn>
role_session_name = week2-target-read
region = us-east-2

[profile week2-untrusted-caller]
source_profile = week2-source
role_arn = <untrusted_caller_role_arn>
role_session_name = week2-untrusted-caller
region = us-east-2

[profile week2-untrusted-target]
source_profile = week2-untrusted-caller
role_arn = <target_read_role_arn>
role_session_name = week2-untrusted-target
region = us-east-2
```

__Important__:  Do not add credentials to these entries.

The purpose of each role-chain profile is:

| Profile | Purpose | Expected outcome |
|---|---|---|
| `week2-approved-caller` | Assume `CrossAccountCallerRole` in the source account | Allow |
| `week2-target-read` | Chain through the approved caller into `CrossAccountReadRole` | Allow |
| `week2-untrusted-caller` | Assume the negative-test source role | Allow |
| `week2-untrusted-target` | Try the final hop through the untrusted source role | Deny because the target trust excludes it |

The role profiles do not represent additional human identities. They are CLI
role-chain definitions rooted in the authenticated `week2-source` SSO session.
The `week2-target-read` and `week2-untrusted-target` profiles therefore end in
the target account, while the two caller profiles end in the source account.

Verify every configured profile independently. These commands request caller
identity only; they do not create or modify resources:

```bash
aws sts get-caller-identity --profile week2-approved-caller
aws sts get-caller-identity --profile week2-target-read
aws sts get-caller-identity --profile week2-untrusted-caller
aws sts get-caller-identity --profile week2-untrusted-target
```

Expected results are:

```text
week2-approved-caller  → CrossAccountCallerRole in the Dev Lab/source account
week2-target-read      → CrossAccountReadRole in the Test Lab/target account
week2-untrusted-caller → UntrustedCrossAccountCallerRole in the Dev Lab/source account
week2-untrusted-target → AccessDenied on the final AssumeRole hop
```

The final command is intentionally expected to fail. It proves that the
untrusted source role has source-side permission to request the target role but
is rejected by the target role's trust policy. Treat an unexpected success as
a failed security test and inspect the target trust relationship before
continuing.

## Some Useful Background

Before moving on, with the exercise per se, we are providing some background meant to help graps the environment and the sequence of tasks performed.

### Provisioned IAM Role

IAM Identity Center creates an IAM role (a "provisioned" IAM role, as it is entirely under the control of Identity Center) in an AWS account when a permission set
is provisioned through an account assignment. For the
`WorkloadLabAdministrator` permission set, the generated role name is:

```text
AWSReservedSSO_WorkloadLabAdministrator_<SUFFIX>
```

`<SUFFIX>` is an IAM Identity Center-generated unique value. It distinguishes
the provisioned role and is not selected by this project. IAM Identity Center,
not the exercise Terraform root, creates and maintains this role.

#### What "provisioned IAM role" means

The permission set, provisioned role, and role session are three separate
objects:

1. Permission set
   - Name: `WorkloadLabAdministrator`
   - Central configuration maintained in IAM Identity Center.

2. Provisioned IAM role
   - `AWSReservedSSO_WorkloadLabAdministrator_<SUFFIX>`
   - Account-local IAM role created from the permission set.

3. Assumed-role session
   - Short-lived STS credentials issued to an assigned, authenticated user.

A permission set is a central template describing policies, session duration,
and related access settings. It is not an IAM principal and cannot itself call
AWS APIs. An account assignment combines a user or group, a permission set, and
a target AWS account. IAM Identity Center then **provisions** the permission
set by materializing it as an actual `AWSReservedSSO_*` IAM role inside that
account.

The account-local role receives the effective policies defined by the
permission set and the federation configuration needed for assigned users to
obtain sessions. AWS services authorize requests from the resulting IAM role
session—not directly from the central permission-set object. This account-local
role is therefore the bridge between an Identity Center login and AWS IAM
authorization.

The role connects the human Identity Center login to AWS IAM:

```text
Test user 1
  → IAM Identity Center account assignment
  → WorkloadLabAdministrator permission set
  → AWSReservedSSO_WorkloadLabAdministrator_<SUFFIX>
  → temporary AWS role session in the source account
```

The IAM role and its sessions have different lifecycles:

- **Provisioned IAM role:** persists while IAM Identity Center keeps the
  permission set provisioned in that account. The project keeps the assignment
  available for the Week 2 lab. If all assignments using the permission set are
  removed, Identity Center may delete the role; recreating the assignment can
  produce a new suffix and therefore a new ARN.
- **Assumed role session:** temporary credentials issued when the test user
  signs in. `WorkloadLabAdministrator` is configured for a one-hour session.
- **Test-user group membership:** temporary operational access that should last
  only for the exercise window and be removed after testing.

The provisioned IAM role is therefore not itself a one-hour object. Its STS
sessions are temporary and expire after one hour. Do not delete, import into the
exercise state, or manually modify the `AWSReservedSSO_*` role; IAM Identity
Center owns and reconciles it.

The role ARN identifies the permission-set role, not one specific human. Every
user authorized to obtain that permission-set role in the source account can
produce a session under the same IAM role ARN, subject to group membership,
account assignment, effective policies, and other applicable controls.
CloudTrail records the individual session context needed for human
attribution.

#### Exercise-relevant permissions excerpt

`WorkloadLabAdministrator` has no broad AWS managed policy attached. Its inline
policy grants the operations needed to provision, inspect, test, and remove the
bounded Exercise 1 resources. The authoritative definition is in the
[`terraform/identity_center/workload_access/main.tf` workload-access policy](../../../../terraform/identity_center/workload_access/main.tf).
The following is a condensed excerpt; placeholders represent the two
allowlisted lab accounts and configured lab resource prefixes:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ReadCurrentIdentity",
      "Effect": "Allow",
      "Action": "sts:GetCallerIdentity",
      "Resource": "*"
    },
    {
      "Sid": "CreateBoundedLabRoles",
      "Effect": "Allow",
      "Action": "iam:CreateRole",
      "Resource": [
        "arn:aws:iam::<TF_LAB_DEV_ACCOUNT_ID>:role/week2/*",
        "arn:aws:iam::<TF_LAB_TEST_ACCOUNT_ID>:role/week2/*"
      ],
      "Condition": {
        "ArnEquals": {
          "iam:PermissionsBoundary": [
            "arn:aws:iam::<TF_LAB_DEV_ACCOUNT_ID>:policy/week2/WorkloadLabRoleBoundary",
            "arn:aws:iam::<TF_LAB_TEST_ACCOUNT_ID>:policy/week2/WorkloadLabRoleBoundary"
          ]
        }
      }
    },
    {
      "Sid": "ManageBoundedLabRoles",
      "Effect": "Allow",
      "Action": [
        "iam:DeleteRole",
        "iam:DeleteRolePolicy",
        "iam:GetRole",
        "iam:GetRolePolicy",
        "iam:ListAttachedRolePolicies",
        "iam:ListInstanceProfilesForRole",
        "iam:ListRolePolicies",
        "iam:ListRoleTags",
        "iam:PutRolePolicy",
        "iam:TagRole",
        "iam:UntagRole",
        "iam:UpdateAssumeRolePolicy",
        "iam:UpdateRole",
        "iam:UpdateRoleDescription"
      ],
      "Resource": [
        "arn:aws:iam::<TF_LAB_DEV_ACCOUNT_ID>:role/week2/*",
        "arn:aws:iam::<TF_LAB_TEST_ACCOUNT_ID>:role/week2/*"
      ]
    },
    {
      "Sid": "AttachOnlyApprovedBoundary",
      "Effect": "Allow",
      "Action": "iam:PutRolePermissionsBoundary",
      "Resource": [
        "arn:aws:iam::<TF_LAB_DEV_ACCOUNT_ID>:role/week2/*",
        "arn:aws:iam::<TF_LAB_TEST_ACCOUNT_ID>:role/week2/*"
      ],
      "Condition": {
        "ArnEquals": {
          "iam:PermissionsBoundary": [
            "arn:aws:iam::<TF_LAB_DEV_ACCOUNT_ID>:policy/week2/WorkloadLabRoleBoundary",
            "arn:aws:iam::<TF_LAB_TEST_ACCOUNT_ID>:policy/week2/WorkloadLabRoleBoundary"
          ]
        }
      }
    },
    {
      "Sid": "ReadApprovedBoundary",
      "Effect": "Allow",
      "Action": [
        "iam:GetPolicy",
        "iam:GetPolicyVersion",
        "iam:ListPolicyVersions"
      ],
      "Resource": [
        "arn:aws:iam::<TF_LAB_DEV_ACCOUNT_ID>:policy/week2/WorkloadLabRoleBoundary",
        "arn:aws:iam::<TF_LAB_TEST_ACCOUNT_ID>:policy/week2/WorkloadLabRoleBoundary"
      ]
    },
    {
      "Sid": "AssumeOnlyLabRoles",
      "Effect": "Allow",
      "Action": "sts:AssumeRole",
      "Resource": [
        "arn:aws:iam::<TF_LAB_DEV_ACCOUNT_ID>:role/week2/*",
        "arn:aws:iam::<TF_LAB_TEST_ACCOUNT_ID>:role/week2/*"
      ]
    },
    {
      "Sid": "ManageNamedLabBuckets",
      "Effect": "Allow",
      "Action": [
        "s3:CreateBucket",
        "s3:DeleteBucket",
        "s3:GetBucketLocation",
        "s3:GetBucketTagging",
        "s3:PutBucketTagging",
        "s3:GetBucketVersioning",
        "s3:PutBucketVersioning",
        "s3:GetEncryptionConfiguration",
        "s3:PutEncryptionConfiguration",
        "s3:GetBucketPublicAccessBlock",
        "s3:PutBucketPublicAccessBlock",
        "s3:GetBucketOwnershipControls",
        "s3:PutBucketOwnershipControls",
        "s3:GetLifecycleConfiguration",
        "s3:PutLifecycleConfiguration",
        "s3:ListBucket",
        "s3:ListBucketVersions",
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:DeleteObjectVersion",
        "s3:GetObjectTagging",
        "s3:PutObjectTagging"
      ],
      "Resource": [
        "arn:aws:s3:::aws-security-week2-*",
        "arn:aws:s3:::aws-security-week2-*/*"
      ]
    },
    {
      "Sid": "ReadLabAuditEvidence",
      "Effect": "Allow",
      "Action": "cloudtrail:LookupEvents",
      "Resource": "*"
    }
  ]
}
```

Here is an excerpt of the permission boundary. The policy is created once in
each lab account by `terraform/lab/week2/baseline`; the placeholders below are
rendered with the appropriate account IDs, AWS partition, and configured lab
bucket prefix:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowAssumingBoundedWeekTwoRoles",
      "Effect": "Allow",
      "Action": "sts:AssumeRole",
      "Resource": [
        "arn:aws:iam::<TF_LAB_DEV_ACCOUNT_ID>:role/week2/*",
        "arn:aws:iam::<TF_LAB_TEST_ACCOUNT_ID>:role/week2/*"
      ]
    },
    {
      "Sid": "AllowReadCurrentIdentity",
      "Effect": "Allow",
      "Action": "sts:GetCallerIdentity",
      "Resource": "*"
    },
    {
      "Sid": "AllowWeekTwoLabBucketAccess",
      "Effect": "Allow",
      "Action": [
        "s3:GetBucketLocation",
        "s3:ListBucket",
        "s3:ListBucketVersions",
        "s3:GetObject",
        "s3:GetObjectVersion",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:DeleteObjectVersion"
      ],
      "Resource": [
        "arn:aws:s3:::aws-security-week2-*",
        "arn:aws:s3:::aws-security-week2-*/*"
      ]
    }
  ]
}
```

For the Dev Lab/source account, the first role ARN resolves to:

```text
arn:aws:iam::<TF_LAB_DEV_ACCOUNT_ID>:role/week2/*
```

and the boundary itself is addressed as:

```text
arn:aws:iam::<TF_LAB_DEV_ACCOUNT_ID>:policy/week2/WorkloadLabRoleBoundary
```

The corresponding Test Lab/target boundary uses
`<TF_LAB_TEST_ACCOUNT_ID>`. The `aws` partition and bucket prefix are rendered
from the baseline configuration, so the excerpt should not be copied as a
literal policy without substituting the environment-specific values.

This is a permissions boundary, not an identity policy. It defines the maximum
permissions an attached role can receive; it does not grant any of these
operations by itself. For example, `CrossAccountReadRole` can read only the
approved object because its identity policy grants that specific read, even
though the boundary permits a broader Week 2 bucket ceiling. Conversely, a
source role cannot assume a bounded role unless its identity policy also grants
`sts:AssumeRole` on the requested role ARN.

The boundary deliberately limits role assumption to `/week2/*` roles in the
two allowlisted lab accounts and S3 access to the configured Week 2 bucket
prefix. It does not grant IAM user or access-key administration, managed-policy
creation, `iam:PassRole`, Organizations administration, or unrestricted access
to other resources; those capabilities are outside the boundary's allowlist.
Applicable SCPs, session policies, resource policies, trust policies, and
explicit denies remain additional authorization constraints.

The complete source template is
[`workload-lab-role-boundary.json.tftpl`](../../../../terraform/lab/week2/baseline/policies/workload-lab-role-boundary.json.tftpl).
Exercise 1 reads the already-created policy as a data source. It must not
import, edit, replace, or destroy `WorkloadLabRoleBoundary`; changing it here
would cross the Terraform ownership boundary and weaken the control used by
this exercise.

These permissions prevent common provider-time `AccessDenied` failures:

- Terraform can create roles only when the approved boundary is supplied.
- Role-policy, trust-policy, tag, and read-back APIs allow Terraform to
  reconcile role state.
- `iam:GetPolicyVersion` lets Terraform inspect the pre-existing boundary;
- S3 create, configuration, read-back, object, and cleanup APIs support the two
  disposable buckets.
- `sts:AssumeRole` enables the later approved and intentionally untrusted role
  chains;
- `cloudtrail:LookupEvents` supports evidence collection.
- Following the least privilege and separation of duties principles,
  we ensure that the role is scoped to the account, to the relevant S3 Bucket,
  policy and role. In addition it is bounded by a permission boundary.


The permission set deliberately omits IAM user and access-key administration,
`iam:PassRole`, general managed-policy creation, and access outside the Week 2
role and bucket prefixes. An Allow in this permission set can still be limited
by an SCP, the required role permissions boundary, a resource policy, or an
explicit deny.

### Why a Trust Policy is Required

Exercise 1 creates `CrossAccountCallerRole` and
`UntrustedCrossAccountCallerRole` in the source account. Their authoritative
Terraform definitions are in
[`terraform/lab/week2/exercise1/main.tf`](../../../../terraform/lab/week2/exercise1/main.tf),
specifically the `aws_iam_role.caller`, `aws_iam_role.untrusted_caller`,
`data.aws_iam_policy_document.source_operator_trust`, and associated inline
role-policy blocks.

From the `WorkloadLabAdministrator` Identity Center session, we will assume
either source role with `sts:AssumeRole`. Both roles therefore use a trust
policy that accepts only the Dev Lab account's generated
`AWSReservedSSO_WorkloadLabAdministrator_*` role path.

#### What an IAM role trust policy is

An IAM role has a **trust policy**, also called its assume-role policy. It is a
resource-based policy attached to the role that identifies which principals
may request a session for that role and which role-assumption operation they
may use. For these roles, the relevant operation is `sts:AssumeRole`.

A trust policy answers:

```text
Who is allowed to become this role?
```

It does not answer:

```text
What may a session do after it becomes this role?
```

The latter is controlled by the role's identity policies, permissions boundary,
applicable SCPs, and other authorization layers. Successful role assumption
normally requires the caller to be permitted to request `sts:AssumeRole` and
the destination role's trust policy to accept that caller. An explicit deny in
an applicable policy still wins.

#### Source trust-policy excerpt

Both source roles intentionally use the same trust-policy document:

```hcl
data "aws_iam_policy_document" "source_operator_trust" {
  provider = aws.source

  statement {
    sid     = "AllowSpecificOperator"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${var.source_account_id}:root"]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:PrincipalArn"
      values   = [local.source_operator_role_arn_pattern]
    }
  }
}
```

The resulting trust relationship is:

```text
Dev Lab account principal
  + aws:PrincipalArn = AWSReservedSSO_WorkloadLabAdministrator_*
  → trusted by CrossAccountCallerRole
  → trusted by UntrustedCrossAccountCallerRole
```

Terraform attaches that document through each role's `assume_role_policy` and
also attaches the pre-existing permissions boundary:

```hcl
resource "aws_iam_role" "caller" {
  provider             = aws.source
  name                 = var.caller_role_name
  path                 = local.role_path
  assume_role_policy   = data.aws_iam_policy_document.source_operator_trust.json
  permissions_boundary = data.aws_iam_policy.source_role_boundary.arn
  max_session_duration = 3600
}

resource "aws_iam_role" "untrusted_caller" {
  provider             = aws.source
  name                 = var.untrusted_role_name
  path                 = local.role_path
  assume_role_policy   = data.aws_iam_policy_document.source_operator_trust.json
  permissions_boundary = data.aws_iam_policy.source_role_boundary.arn
  max_session_duration = 3600
}
```

Terraform derives `source_operator_role_arn_pattern` from the source account ID
and Identity Center Region. The account-root principal is constrained by
`aws:PrincipalArn`, so other roles in the account are not trusted. The generated
suffix is wildcarded because IAM Identity Center can replace its role and
change that suffix when assignments are removed and recreated. This avoids an
invalid principal without requiring the learner to discover or configure the
suffix.

#### Permissions after assuming the source roles

The two roles also receive separate inline policies, but both inline policies
use the same `assume_target` document:

```hcl
data "aws_iam_policy_document" "assume_target" {
  provider = aws.source

  statement {
    sid       = "AssumeOnlyExerciseTargetRole"
    effect    = "Allow"
    actions   = ["sts:AssumeRole"]
    resources = [
      "arn:<PARTITION>:iam::<TF_LAB_TEST_ACCOUNT_ID>:role/week2/exercise1/CrossAccountReadRole"
    ]
  }
}

resource "aws_iam_role_policy" "caller_assume_target" {
  name   = "AssumeExerciseTargetRole"
  role   = aws_iam_role.caller.id
  policy = data.aws_iam_policy_document.assume_target.json
}

resource "aws_iam_role_policy" "untrusted_caller_assume_target" {
  name   = "AttemptExerciseTargetRole"
  role   = aws_iam_role.untrusted_caller.id
  policy = data.aws_iam_policy_document.assume_target.json
}
```

This deliberate symmetry means both source roles are allowed on the
identity-policy side to request the target role. The role named "untrusted" is
not untrusted by the initial SSO role: its own source trust policy permits the
same SSO principal. It is untrusted only from the target role's perspective.

The target trust policy names only the approved caller:

```hcl
data "aws_iam_policy_document" "target_trust" {
  provider = aws.target

  statement {
    sid     = "TrustOnlyApprovedSourceRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.caller.arn]
    }
  }
}
```

Consequently:

```text
CrossAccountCallerRole
  identity policy allows target
  + target trust policy names caller
  → target assumption can succeed

UntrustedCrossAccountCallerRole
  identity policy allows target
  + target trust policy does not name caller
  → target assumption fails
```

Keeping the source identity policies equivalent isolates the target trust
policy as the reason for the expected failure. Follow the linked Terraform file
to inspect the complete role descriptions, provider assignments, generated
ARNs, boundaries, and target role definition.

## Initialize, validate, and plan

### Why two SSO logins are required

The Terraform root has two aliased AWS providers:

```text
aws.source → week2-source → Dev Lab/source account
aws.target → week2-target → Test Lab/target account
```

Terraform uses both providers during the same plan. The source provider creates
and reads the two caller roles. The target provider creates and reads the target
role and S3 resources. Each provider therefore needs a current, independently
authorized IAM Identity Center session.

`week2-source` must be authorized by the user configured through
`TF_VAR_test_user1_email`; `week2-target` must be authorized by the user
configured through `TF_VAR_test_user2_email`. They use separate SSO sessions
because they represent different humans. These logins establish the initial
Terraform provisioning sessions; they do not yet execute the exercise's
cross-account role chain.

Authenticate each profile using separate browser contexts:

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

See [the SSO authentication guide](../../../sso_auth.md) for browser-session
reuse and private-window guidance. Verify the account and permission-set role
before running Terraform:

```bash
aws sts get-caller-identity --profile week2-source
aws sts get-caller-identity --profile week2-target
```

Both ARNs must contain `AWSReservedSSO_WorkloadLabAdministrator_`; the first
account must match `TF_LAB_DEV_ACCOUNT_ID` and the second must match
`TF_LAB_TEST_ACCOUNT_ID`.

Initialize the S3 backend. The backend identity is independent from the two
aliased exercise providers:

```bash
terraform -chdir=terraform/lab/week2/exercise1 init \
  -backend-config="bucket=$TF_STATE_BUCKET" \
  -backend-config="region=$TF_STATE_REGION" \
  -backend-config="profile=$TF_STATE_PROFILE"
```

Validate the root:

```bash
terraform -chdir=terraform/lab/week2/exercise1 validate
```

### Resources and trust relationships being created

Before planning, understand the intended account-level changes.

#### Dev Lab/source account

Terraform manages:

- `CrossAccountCallerRole` under `/week2/exercise1/`;
- `UntrustedCrossAccountCallerRole` under `/week2/exercise1/`;
- A permissions boundary on both roles.
- A trust policy on both roles allowing only principals whose
  `aws:PrincipalArn` matches the Dev Lab
  `AWSReservedSSO_WorkloadLabAdministrator_*` role path.
- An inline policy on each role allowing `sts:AssumeRole` only for
  `CrossAccountReadRole` in the target account.

The untrusted role intentionally has the same identity-side `sts:AssumeRole`
permission as the approved caller. This isolates the negative test: its failure
must come from the target trust policy, not from a missing source policy.

#### Test Lab/target account

Terraform manages:

- `CrossAccountReadRole` under `/week2/exercise1/`;
- Its required `WorkloadLabRoleBoundary` attachment.
- A trust policy permitting only `CrossAccountCallerRole` from the source
  account.
- An inline policy allowing `s3:ListBucket` and `s3:GetBucketLocation` on the
  approved bucket and `s3:GetObject` on one approved object.
- An approved S3 bucket and object.
- An unrelated S3 bucket and object for a negative resource-scope test.
- Public-access blocks, bucket-owner-enforced ownership, SSE-S3 encryption,
  versioning, and seven-day lifecycle cleanup on both buckets.

The persistent boundary policies are read as data sources and are not imported
into or owned by the Exercise 1 state.

#### Why both sides of the trust relationship are configured

For the approved cross-account hop:

1. `CrossAccountCallerRole` has an identity policy allowing
   `sts:AssumeRole` on the exact target role ARN.
2. `CrossAccountReadRole` has a trust policy naming the exact approved source
   role ARN.
3. Applicable boundaries permit the requested STS action.
4. No applicable explicit deny blocks the request.

The source policy answers **what may this caller request?** The target trust
policy answers **which external principal may become this role?** Both must
permit the operation. Trusting one role rather than the source-account root
keeps delegation narrow and makes the negative caller test deterministic.

Generate and review the plan:

```bash
terraform -chdir=terraform/lab/week2/exercise1 plan
```

The plan should affect only the resources listed above in the two lab accounts.
It must not create users, access keys, general managed policies, public bucket
policies, or resources outside the lab accounts. It must not replace or destroy
the persistent baseline boundary. Stop on any unexplained replacement or
deletion.

After review, apply:

```bash
terraform -chdir=terraform/lab/week2/exercise1 apply
```

Record the raw output ARNs when configuring profiles; raw output avoids copying
Terraform display quotation marks:

```bash
echo "approved_caller_role_arn: $(terraform -chdir=terraform/lab/week2/exercise1 output -raw approved_caller_role_arn)"
echo "untrusted_caller_role_arn: $(terraform -chdir=terraform/lab/week2/exercise1 output -raw untrusted_caller_role_arn)"
echo "target_read_role_arn: $(terraform -chdir=terraform/lab/week2/exercise1 output -raw target_read_role_arn)"
```

## Configure role chaining for tests

### What the approved chain consists of

A role chain occurs when credentials from one role session are used to assume a
second role. The approved path has two role assumptions after the initial SSO
session:

```mermaid
flowchart LR
    U1[Test user 1] -->|IAM Identity Center login| SSO[WorkloadLabAdministrator session]
    SSO -->|AssumeRole permitted by source-role trust| Caller[CrossAccountCallerRole<br/>source account]
    Caller -->|Identity policy allows target<br/>and target trust allows caller| Target[CrossAccountReadRole<br/>target account]
    Target -->|Target role policy| Approved[Approved S3 bucket/object]
```

The AWS CLI resolves this chain automatically through `source_profile`:

```text
week2-target-read
  → source_profile week2-approved-caller
  → source_profile week2-source
  → IAM Identity Center credentials
```

### What the intentionally failing chain consists of

```mermaid
flowchart LR
    U1[Test user 1] -->|IAM Identity Center login| SSO[WorkloadLabAdministrator session]
    SSO -->|Source-role trust permits| Untrusted[UntrustedCrossAccountCallerRole<br/>source account]
    Untrusted -->|Identity policy allows sts:AssumeRole| STS[AWS STS]
    STS -.->|Denied: target trust does not name this role| Target[CrossAccountReadRole<br/>target account]
```

The untrusted source role has the necessary identity policy and permissions
boundary allowance. What is deliberately missing is an Allow for that role in
`CrossAccountReadRole`'s target trust policy. Because cross-account role
assumption requires both sides, the final hop must fail.

### Configure the role profiles

Read the Terraform outputs without display quotes:

```bash
export EXERCISE_ROOT="terraform/lab/week2/exercise1"
echo "approved_caller_role_arn: $(terraform -chdir=$EXERCISE_ROOT output -raw approved_caller_role_arn)"
echo "untrusted_caller_role_arn: $(terraform -chdir=$EXERCISE_ROOT output -raw untrusted_caller_role_arn)"
echo "target_read_role_arn: $(terraform -chdir=$EXERCISE_ROOT output -raw target_read_role_arn)"
```

Configure these profiles in `~/.aws/config` without quotation marks around the
ARN values:

```ini
[profile week2-approved-caller]
source_profile = week2-source
role_arn = <approved_caller_role_arn>
role_session_name = week2-approved-caller
region = us-east-2

[profile week2-target-read]
source_profile = week2-approved-caller
role_arn = <target_read_role_arn>
role_session_name = week2-target-read
region = us-east-2

[profile week2-untrusted-caller]
source_profile = week2-source
role_arn = <untrusted_caller_role_arn>
role_session_name = week2-untrusted-caller
region = us-east-2

[profile week2-untrusted-target]
source_profile = week2-untrusted-caller
role_arn = <target_read_role_arn>
role_session_name = week2-untrusted-target
region = us-east-2
```

These profiles store role metadata, not credentials. The CLI obtains temporary
credentials at runtime and automatically follows each `source_profile` chain.

## Execute the authorization tests

Run each command, record the actual result, and compare it with the expected
policy-evaluation result below.

### Test 1 — Approved role chain reaches the target role

```bash
aws sts get-caller-identity --profile week2-target-read
```

**Caller and resource:** The initial caller is the `week2-source` SSO session.
It assumes `CrossAccountCallerRole`, which then requests the
`CrossAccountReadRole` resource in the target account.

**Expected: Allow.** The first source role trusts the provisioned
`WorkloadLabAdministrator` role and the lab administrator session may call
`sts:AssumeRole` on the bounded source role. For the cross-account hop, the
approved caller's identity policy permits the exact target ARN and the target
trust policy names the exact approved caller ARN. Both boundaries permit the
STS operation and no explicit deny applies.

The returned identity must be an assumed `CrossAccountReadRole` session in the
target account.

### Test 2 — List the approved bucket

```bash
aws s3api list-objects-v2 \
  --profile week2-target-read \
  --bucket "$TF_VAR_approved_bucket_name"
```

**Caller and resource:** The caller is the assumed `CrossAccountReadRole`
session. The resource is the approved target-account bucket.

**Expected: Allow.** The target role's identity policy grants `s3:ListBucket`
on that exact bucket ARN. The attached permissions boundary includes S3 access
to the authorized Week 2 bucket prefix, so the identity grant remains within
the boundary ceiling.

### Test 3 — Read the approved object

```bash
aws s3 cp \
  "s3://$TF_VAR_approved_bucket_name/exercise-1/allowed.txt" \
  /tmp/week2-allowed.txt \
  --profile week2-target-read
```

**Caller and resource:** The caller is `CrossAccountReadRole`; the resource is
`exercise-1/allowed.txt` in the approved bucket.

**Expected: Allow.** The target role policy grants `s3:GetObject` on that exact
object ARN, and the permissions boundary permits S3 access within the lab
bucket prefix. No bucket policy deny or other explicit deny applies.

### Test 4 — Attempt to write to the approved bucket

```bash
printf 'this write must fail\n' > /tmp/week2-denied.txt
aws s3 cp \
  /tmp/week2-denied.txt \
  "s3://$TF_VAR_approved_bucket_name/exercise-1/denied.txt" \
  --profile week2-target-read
```

**Caller and resource:** The caller is `CrossAccountReadRole`; the resource is
a new object in the approved bucket.

**Expected: Deny.** Writing requires `s3:PutObject`. The target role's identity
policy does not grant `s3:PutObject`. A permissions boundary is only a ceiling
and does not grant the action by itself, even if the boundary permits S3 writes
for another bounded role. The missing identity-policy Allow produces an
implicit deny.

### Test 5 — Attempt to list the unrelated bucket

```bash
aws s3api list-objects-v2 \
  --profile week2-target-read \
  --bucket "$TF_VAR_unrelated_bucket_name"
```

**Caller and resource:** The caller is `CrossAccountReadRole`; the resource is
the unrelated target-account bucket.

**Expected: Deny.** The target role grants `s3:ListBucket` only on the approved
bucket ARN. It has no identity-policy Allow for the unrelated bucket. The
permissions boundary's broader lab-prefix ceiling does not grant access, so the
request is implicitly denied.

### Test 6 — Attempt the untrusted cross-account chain

```bash
aws sts get-caller-identity --profile week2-untrusted-target
```

**Caller and resource:** The CLI first obtains the `week2-source` SSO session
and successfully assumes `UntrustedCrossAccountCallerRole`. That role then
requests `CrossAccountReadRole` in the target account.

**Expected: Deny.** The untrusted caller has an identity policy allowing
`sts:AssumeRole` on the exact target role, and its boundary permits the action.
However, the target role's trust policy names only `CrossAccountCallerRole`.
The missing target-side trust Allow causes STS to deny the final hop. This is
the exercise's proof that an identity-side Allow alone is insufficient for
cross-account role assumption.

Capture expected and actual results without storing credentials, device codes,
or unredacted sensitive data in the repository.

## Evidence and security analysis

First reload the exact role ARNs and retrieve the source and target policies
that governed all six tests:

```bash
export EXERCISE1_APPROVED_ROLE_ARN="$(terraform -chdir=terraform/lab/week2/exercise1 output -raw approved_caller_role_arn)"
export EXERCISE1_UNTRUSTED_ROLE_ARN="$(terraform -chdir=terraform/lab/week2/exercise1 output -raw untrusted_caller_role_arn)"
export EXERCISE1_TARGET_ROLE_ARN="$(terraform -chdir=terraform/lab/week2/exercise1 output -raw target_read_role_arn)"
aws iam get-role-policy --profile week2-source --role-name CrossAccountCallerRole --policy-name AssumeExerciseTargetRole --output json --no-cli-pager
aws iam get-role-policy --profile week2-source --role-name UntrustedCrossAccountCallerRole --policy-name AttemptExerciseTargetRole --output json --no-cli-pager
aws iam get-role --profile week2-target --role-name CrossAccountReadRole --query 'Role.{Arn:Arn,Trust:AssumeRolePolicyDocument,Boundary:PermissionsBoundary.PermissionsBoundaryArn}' --output json --no-cli-pager
aws iam get-role-policy --profile week2-target --role-name CrossAccountReadRole --policy-name ReadOnlyApprovedExerciseResource --output json --no-cli-pager
```

Verify both source policies name the same target-role ARN. In the target trust
policy, confirm only `CrossAccountCallerRole` is trusted; this difference
explains the untrusted-chain denial. In `ReadOnlyApprovedExerciseResource`,
compare the approved bucket/object resources and read actions with the denied
write and unrelated-bucket tests. Confirm all three roles report the
`WorkloadLabRoleBoundary` ARN when retrieved with `get-role`.

Retrieve the approved and unrelated bucket configuration to rule out missing or
insecure resources as the reason for the different outcomes:

```bash
aws s3api get-bucket-versioning --profile week2-target --bucket "$TF_VAR_approved_bucket_name" --no-cli-pager
aws s3api get-public-access-block --profile week2-target --bucket "$TF_VAR_approved_bucket_name" --no-cli-pager
aws s3api head-object --profile week2-target --bucket "$TF_VAR_approved_bucket_name" --key exercise-1/allowed.txt --no-cli-pager
aws s3api head-object --profile week2-target --bucket "$TF_VAR_unrelated_bucket_name" --key exercise-1/unrelated.txt --no-cli-pager
```

Look for enabled versioning, all four public-access-block booleans set to true,
and successful metadata for both objects. The unrelated object exists; its
denial is caused by the target role's resource scope rather than absence.

Use the target user's session to locate STS events in the Region where the
request was recorded:

```bash
aws cloudtrail lookup-events \
  --profile week2-target \
  --region "$TF_HOME_REGION" \
  --lookup-attributes AttributeKey=EventName,AttributeValue=AssumeRole
```

For each approved and denied attempt, record:

- Calling principal ARN.
- Requested target role ARN.
- Session name.
- Source IP and event time.
- Resulting assumed-role ARN for successful requests.
- The policy layer inferred to have allowed or blocked the request.

Consult the centralized organization trail if the event is not present in
regional Event History.

Retrieve the S3 data events for the two object checks from the shared evidence
bucket. The detailed architecture and troubleshooting rationale are in
[`cloud-trail-logs.md`](../../../cloud-trail-logs.md), but run all commands here.
First load the authoritative evidence bucket and account-level CloudTrail
prefix; do not construct a path from the workstation date:

```bash
export EXERCISE1_EVIDENCE_BUCKET="$(terraform -chdir=terraform/lab/evidence output -raw evidence_bucket_name)"
export EXERCISE1_ORGANIZATION_ID="$(terraform -chdir=terraform/lab/evidence output -raw organization_id)"
export EXERCISE1_ACCOUNT_ID="$(aws sts get-caller-identity --profile week2-target --query Account --output text)"
export EXERCISE1_ACCOUNT_EVIDENCE_PREFIX="AWSLogs/$EXERCISE1_ORGANIZATION_ID/$EXERCISE1_ACCOUNT_ID/CloudTrail/"
aws s3api list-objects-v2 \
  --profile week2-target \
  --bucket "$EXERCISE1_EVIDENCE_BUCKET" \
  --prefix "$EXERCISE1_ACCOUNT_EVIDENCE_PREFIX" \
  --query 'Contents[].{Key:Key,LastModified:LastModified,Size:Size}' \
  --output table \
  --no-cli-pager
```

Select the latest delivered directory and download its compressed CloudTrail
objects:

```bash
export EXERCISE1_LATEST_LOG_KEY="$(aws s3api list-objects-v2 \
  --profile week2-target \
  --bucket "$EXERCISE1_EVIDENCE_BUCKET" \
  --prefix "$EXERCISE1_ACCOUNT_EVIDENCE_PREFIX" \
  --query 'sort_by(Contents,&LastModified)[-1].Key' \
  --output text \
  --no-cli-pager)"
test -n "$EXERCISE1_LATEST_LOG_KEY"
test "$EXERCISE1_LATEST_LOG_KEY" != "None"
export EXERCISE1_EVIDENCE_PREFIX="${EXERCISE1_LATEST_LOG_KEY%/*}/"
export EXERCISE1_EVIDENCE_TMP="$(mktemp -d)"
chmod 700 "$EXERCISE1_EVIDENCE_TMP"
aws s3 cp \
  "s3://$EXERCISE1_EVIDENCE_BUCKET/$EXERCISE1_EVIDENCE_PREFIX" \
  "$EXERCISE1_EVIDENCE_TMP/" \
  --profile week2-target \
  --recursive \
  --exclude '*' \
  --include '*.json.gz' \
  --no-cli-pager
```

Filter the downloaded events by both exercise buckets and exact object keys:

```bash
find "$EXERCISE1_EVIDENCE_TMP" -type f -name '*.json.gz' -print0 |
  xargs -0 gzip -cd |
  jq -c --arg approved "$TF_VAR_approved_bucket_name" \
        --arg unrelated "$TF_VAR_unrelated_bucket_name" '
    .Records[]
    | select(.eventSource == "s3.amazonaws.com"
        and (.eventName == "GetObject" or .eventName == "HeadObject")
        and ((.requestParameters.bucketName == $approved
              and .requestParameters.key == "exercise-1/allowed.txt")
          or (.requestParameters.bucketName == $unrelated
              and .requestParameters.key == "exercise-1/unrelated.txt")))
    | {eventTime,eventID,principal:.userIdentity.arn,bucket:.requestParameters.bucketName,key:.requestParameters.key,errorCode,errorMessage}
  '
```

The approved object event should have no `errorCode`. The unrelated object event
should show `AccessDenied` if the test request was recorded as a data event.
Match each event to the correct caller and timestamp; delivery is asynchronous,
so wait and retry the listing if no event follows the test. Remove local copies
after preserving redacted evidence:

```bash
find "$EXERCISE1_EVIDENCE_TMP" -type f -delete
find "$EXERCISE1_EVIDENCE_TMP" -depth -type d -empty -delete
unset EXERCISE1_EVIDENCE_TMP EXERCISE1_EVIDENCE_BUCKET EXERCISE1_ORGANIZATION_ID
unset EXERCISE1_ACCOUNT_ID EXERCISE1_ACCOUNT_EVIDENCE_PREFIX
unset EXERCISE1_LATEST_LOG_KEY EXERCISE1_EVIDENCE_PREFIX
```

## Investigating in the Console

Use the AWS console to visualize the identities, policy layers, trust
relationships, and resources involved in the tests. Console inspection is not a
substitute for the CLI results or CloudTrail evidence; it provides a structured
way to connect those results to the deployed configuration.

### Use the correct account session

Open the IAM Identity Center access portal rather than using an IAM user. The
relevant console sessions are:

| Purpose | Account | Permission set |
|---|---|---|
| Inspect source exercise resources | Dev Lab/source | `WorkloadLabAdministrator` |
| Inspect target exercise resources | Test Lab/target | `WorkloadLabAdministrator` |
| Inspect the persistent boundary | Either lab account | `WorkloadLabBaselineAdmin` or another approved IAM reader |
| Inspect Identity Center assignments | Management account | An approved Identity Center administrative or read session |
| Inspect inherited SCPs | Management account | An approved Organizations administrative or read session |

The two exercise profiles represent different test users. To open both account
consoles without browser-session confusion:

1. Sign in to the access portal as the user configured by
   `TF_VAR_test_user1_email` in one private browser or dedicated browser profile.
2. Select the Dev Lab account and `WorkloadLabAdministrator`.
3. Sign in as the user configured by `TF_VAR_test_user2_email` in a different
   browser, or close every private window before starting a new private session.
4. Select the Test Lab account and `WorkloadLabAdministrator`.
5. In each AWS console, use the account menu in the upper-right corner to verify
   the account ID and permission-set role before inspecting resources.

Do not rely on the console's **Switch Role** feature for the initial access.
Choose the assigned account and permission set in the Identity Center portal so
that the session has the intended human attribution and MFA context. See the
[SSO authentication guide](../../../sso_auth.md) for browser-session isolation.

The lab administrator is one named human with two account assignments. That
user can select Dev Lab or Test Lab from the same access portal session using
`WorkloadLabBaselineAdmin` when boundary inspection is required.

Least-privilege sessions may not support every IAM or S3 list page because AWS
console pages sometimes call broad list APIs. If a page reports
`AccessDenied`, do not add permissions merely to make the console work. Use an
approved read-only administrative session, a direct resource URL, the AWS CLI,
or the retained Terraform and CloudTrail evidence.

### Inspect IAM Identity Center assignments

In an authorized management-account session:

1. Open **IAM Identity Center**.
2. Open **AWS accounts** and select the Dev Lab account.
3. Review the assignments for:
   - `WorkloadLabAdministrators` with `WorkloadLabAdministrator`;
   - `WorkloadLabBaselineAdministrators` with
     `WorkloadLabBaselineAdmin`.
4. Repeat for the Test Lab account.
5. Open **Permission sets** and inspect both permission sets, including their
   one-hour session duration and inline policies.
6. Open **Groups** to confirm the temporary exercise-user membership and the
   dedicated baseline-administrator membership.

This view explains how a human receives the initial `AWSReservedSSO_*` session
in each account. It does not show the trust policies of the exercise roles;
those are inspected in IAM within each workload account.

### Inspect the source-account roles

In the Dev Lab/source console, open **IAM → Access management → Roles**. Search
for roles under the `/week2/exercise1/` path and inspect:

#### `CrossAccountCallerRole`

- **Trust relationships:** the principal should be the exact
  `AWSReservedSSO_WorkloadLabAdministrator_<SUFFIX>` IAM role in the source
  account. This permits the initial SSO session to assume the caller role.
- **Permissions:** the inline `AssumeExerciseTargetRole` policy should allow
  only `sts:AssumeRole` on the target account's `CrossAccountReadRole` ARN.
- **Permissions boundary:** `WorkloadLabRoleBoundary` should be attached. The
  boundary is a ceiling; it does not grant the caller's STS permission by
  itself.
- **Path and session duration:** verify `/week2/exercise1/` and the configured
  one-hour maximum role session.

#### `UntrustedCrossAccountCallerRole`

- **Trust relationships:** the same source Identity Center role can assume it.
- **Permissions:** `AttemptExerciseTargetRole` deliberately allows the same
  target-role ARN as the approved caller.
- **Permissions boundary:** the same `WorkloadLabRoleBoundary` is attached.

The untrusted role is intentionally not missing a source-side permission. Its
failure is caused by its absence from the target role's trust policy.

You may also see the Identity Center-owned role named
`AWSReservedSSO_WorkloadLabAdministrator_<SUFFIX>`. Do not modify it. IAM
Identity Center created it from the permission-set account assignment and owns
its lifecycle.

### Inspect the target-account role

In the Test Lab/target console, open **IAM → Access management → Roles** and
inspect `CrossAccountReadRole` under `/week2/exercise1/`:

- **Trust relationships:** only the source account's
  `CrossAccountCallerRole` ARN should be trusted. The untrusted caller and the
  source account root should not appear.
- **Permissions:** the inline `ReadOnlyApprovedExerciseResource` policy should
  grant:.
  - `s3:GetBucketLocation` and `s3:ListBucket` on the approved bucket;
  - `s3:GetObject` on only `exercise-1/allowed.txt` in that bucket.
- **Permissions boundary:** `WorkloadLabRoleBoundary` should be attached.
- **Missing permissions:** there should be no `s3:PutObject` identity grant and
  no permission for the unrelated bucket.

This view shows why the approved cross-account hop and selected reads succeed,
while writes and unrelated-resource reads fail.

### Inspect the permissions boundaries

A separate `WorkloadLabRoleBoundary` customer-managed policy exists in each lab
account. In each account, open **IAM → Access management → Policies**, select
**Customer managed**, and search for:

```text
WorkloadLabRoleBoundary
```

Inspect:

- The policy path `/week2/`.
- The current default policy version.
- The permitted STS role path and the two lab account IDs.
- The permitted S3 lab bucket-name prefix.
- The roles using the policy as a permissions boundary.

The boundary establishes maximum permissions for exercise-created roles. An
action still requires an identity-policy Allow. This is why the target role
cannot write an object merely because the boundary's ceiling permits some S3
write operations.

The boundary is owned by `terraform/lab/week2/baseline`, not the Exercise 1
state. Do not edit it in the console. A console edit would create Terraform
drift and could weaken the privilege-escalation control.

### Inspect the S3 resources

In the Test Lab/target account, open **Amazon S3 → General purpose buckets** and
locate the bucket names returned by:

```bash
echo "approved_caller_role_arn: $(terraform -chdir=terraform/lab/week2/exercise1 output -raw approved_caller_role_arn)"
echo "untrusted_caller_role_arn: $(terraform -chdir=terraform/lab/week2/exercise1 output -raw untrusted_caller_role_arn)"
echo "target_read_role_arn: $(terraform -chdir=terraform/lab/week2/exercise1 output -raw target_read_role_arn)"
```

Inspect the approved bucket:

- **Objects:** `exercise-1/allowed.txt` should exist.
- **Permissions:** all four Block Public Access settings should be enabled;
  Object Ownership should be **Bucket owner enforced**.
- **Properties:** default encryption should use SSE-S3; versioning should be
  enabled.
- **Management:** the lifecycle rule should expire current and noncurrent lab
  data after seven days and abort incomplete multipart uploads.

Inspect the unrelated bucket and its `exercise-1/unrelated.txt` object. Its
security configuration is intentionally similar to the approved bucket. The
denial occurs because `CrossAccountReadRole` does not name this bucket in its
identity policy, not because the unrelated bucket is public, missing, or
configured with a deny policy.

There is no exercise bucket policy granting the source account direct access.
After successful role assumption, the caller uses credentials for a role in
the target account; the target role's identity policy authorizes the selected
S3 calls.

### Inspect applicable service control policies

Exercise 1 does not create or modify an SCP, but inherited SCPs remain part of
the authorization evaluation. In an authorized Organizations management-account
session:

1. Open **AWS Organizations**.
2. Open **AWS accounts** and select the Dev Lab account.
3. Review the account's parent OU hierarchy and attached or inherited service
   control policies.
4. Repeat for the Test Lab account.
5. Inspect whether any SCP restricts `sts:AssumeRole`, IAM, or the selected S3
   actions.

An SCP does not grant permission. It limits the maximum permissions available
to member-account principals, and an applicable explicit deny overrides the
role policies demonstrated in this exercise. Do not change an SCP merely to
make a test pass; investigate and document any inherited restriction first.
SCPs do not constrain principals in the Organizations management account, which
is another reason not to run the exercise there.

### Inspect CloudTrail role activity

In each lab account, open **CloudTrail → Event history** and filter for:

- **Event source:** `sts.amazonaws.com`.
- **Event name:** `AssumeRole`.
- The approved and untrusted caller role names.
- The target role name.

For successful assumptions, expand the event and inspect
`userIdentity`, `requestParameters.roleArn`, `requestParameters.roleSessionName`,
`sourceIPAddress`, and the resulting assumed-role context. For the failed
untrusted hop, compare the requesting principal with the target trust policy.

Also review S3 events where available. Organization trails do not necessarily
include S3 object-level data events unless those data events are explicitly
configured, so absence of an object event in Event History is not proof that no
request occurred.

## Clean up

After preserving evidence, review a destroy plan and remove only Exercise 1
resources:

```bash
terraform -chdir=terraform/lab/week2/exercise1 plan -destroy
terraform -chdir=terraform/lab/week2/exercise1 destroy
```

Do not destroy the Week 2 baseline. Confirm that `WorkloadLabRoleBoundary`
remains in both accounts for later exercises. Remove the test users' temporary
`WorkloadLabAdministrators` membership when the exercise window ends.

Use `terraform show` to verify that the Exercise 1 state is empty. A normal plan
after destruction will propose recreating the exercise and should be run only
when the exercise is intentionally repeated.

## References

- [AWS cross-account resource access](https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies-cross-account-resource-access.html).
- [AWS cross-account policy evaluation](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_evaluation-logic-cross-account.html).
- [IAM role trust policies](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_manage_modify.html).
- [IAM permissions boundaries](https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies_boundaries.html).
- [IAM Identity Center users and groups](https://docs.aws.amazon.com/singlesignon/latest/userguide/users-groups-provisioning.html).
- [IAM Identity Center permission sets](https://docs.aws.amazon.com/singlesignon/latest/userguide/permissionsetsconcept.html).
- [AWS CLI IAM Identity Center authentication](../../../sso_auth.md).
- [AWS CLI role configuration](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-role.html).
- [AWS STS `AssumeRole`](https://docs.aws.amazon.com/STS/latest/APIReference/API_AssumeRole.html).
- [AWS CloudTrail event history](https://docs.aws.amazon.com/awscloudtrail/latest/userguide/view-cloudtrail-events.html).
- [Amazon S3 policy actions and resources](https://docs.aws.amazon.com/service-authorization/latest/reference/list_amazons3.html).
