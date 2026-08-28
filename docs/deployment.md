# Deployment Guide

## Purpose

This document defines the supported deployment order for the AWS Control Tower landing zone, project-owned IAM Identity Center administration, the AFT prerequisites, AFT human access, and the AFT platform.

The dependency sequence is:

```text
terraform/bootstrap
  → terraform/workloads/org_units
  → terraform/identity_center
  → terraform/aft/org_unit
  → terraform/aft/account
  → terraform/identity_center/aft_access
  → terraform/aft/platform
  → GitHub CodeConnections authorization
```

Do not run later roots until the preceding root has completed and its asynchronous AWS service operations are healthy.

## Safety Rules

Before every apply:

1. run formatting or a formatting check;
2. run Terraform validation;
3. produce and inspect a plan;
4. stop if the plan contains unexplained replacement or deletion;
5. verify the active AWS identity and target account;
6. ensure no credentials, plans, state, or sensitive output will be committed.

Never approve a plan that unexpectedly proposes replacement or deletion of:

- The AWS Organization;.
- The Control Tower landing zone;.
- Control Tower shared accounts;.
- A governed OU baseline;.
- The AFT management account;.
- Control Tower-created IAM Identity Center resources.

Do not use `-auto-approve` for these foundational roots.

## Environment Configuration

`tf.sh` loads its environment from:

```text
$TF_ENV_FILE
```

or, when that variable is not set:

```text
$HOME/.env/aws-security/terraform/.env
```

If neither file exists, it falls back to a repository-root `.env` file.

The example configuration is:

```text
terraform/.env.example
```

Do not place real credentials or sensitive production values in the example file.

### State backend

The shared backend requires:

```bash
export TF_STATE_BUCKET="your-terraform-state-bucket"
export TF_STATE_REGION="your-state-bucket-region"
```

Every Terraform root has a distinct state key even when it uses the same S3 bucket:

```text
control-tower/terraform.tfstate
workloads/org_units/terraform.tfstate
identity-center/terraform.tfstate
identity-center/workload-access/terraform.tfstate
aft/org_unit/terraform.tfstate
aft/account/terraform.tfstate
identity-center/aft-access/terraform.tfstate
aft/platform/terraform.tfstate
exercises/week2/baseline/terraform.tfstate
lab/week2/exercise2/terraform.tfstate
```

Optional root-specific backend variables are documented in `terraform/.env.example`.

### Required architecture invariants

The current Control Tower landing-zone version requires:

```bash
export TF_VAR_control_tower_baseline_version="5.0"
```

The AFT VPC is intentionally disabled:

```bash
export TF_VAR_aft_enable_vpc=false
```

The baseline variable is validated at `5.0`. The AFT OU baseline and all workload OU baselines use `prevent_destroy` to prevent an accidental version change from unregistering governance.

### AFT repositories

Before deploying the AFT platform, configure the four repositories:

```bash
export TF_VAR_account_request_repo_name="example-organization/aws-security-aft-account-request"
export TF_VAR_global_customizations_repo_name="example-organization/aws-security-aft-global-customizations"
export TF_VAR_account_customizations_repo_name="example-organization/aws-security-aft-account-customizations"
export TF_VAR_account_provisioning_customizations_repo_name="example-organization/aws-security-aft-account-provisioning-customizations"
```

All repositories must exist and contain the configured branch, currently `main`, before the platform root runs.

See [`aft-setup.md`](aft-setup.md) for repository responsibilities and network tradeoffs.

## Phase 1 — Control Tower Bootstrap

The bootstrap root owns:

- AWS Organizations foundation;.
- Foundational non-AFT OUs;.
- Control Tower shared accounts;.
- Control Tower landing zone and prerequisites.

It does not own the AFT OU or AFT management account.

### Plan

```bash
./tf.sh --phase bootstrap --fmt
./tf.sh --phase bootstrap --dry-run
```

Review the plan carefully. It must not propose:

- Replacing the AWS Organization;.
- Disabling `SERVICE_CONTROL_POLICY`;.
- Removing trusted service access;.
- Replacing an existing Control Tower landing zone;.
- Replacing Control Tower shared accounts.

### Apply

```bash
./tf.sh --phase bootstrap --apply
```

Wait until the landing zone reports:

```text
Status: ACTIVE
Drift status: IN_SYNC
```

Control Tower operations are asynchronous. Do not start Identity Center administration or AFT prerequisites while the landing zone is updating or drifted.

### Convergence check

```bash
./tf.sh --phase bootstrap --chk
./tf.sh --phase bootstrap --dry-run
```

A converged root should produce no changes, except for reviewed computed-state refreshes.

## Workload OU Hierarchy

After bootstrap is healthy, create and govern the workload account targets:

```text
Workloads
├── Dev
├── Test
└── Prod
```

Plan the independent root:

```bash
./tf.sh --phase workloads --fmt
./tf.sh --phase workloads --dry-run
```

The plan must create only the four OUs and four `AWSControlTowerBaseline` version `5.0` instances. It must not create accounts. Apply and verify convergence with:

```bash
./tf.sh --phase workloads --apply
./tf.sh --phase workloads --chk
./tf.sh --phase workloads --dry-run
```

Do not submit AFT account requests targeting an environment OU until its baseline has completed successfully. The workload root can otherwise evolve independently of AFT platform deployment.

## Phase 2 — Project-Owned Identity Center Administration

The Identity Center phase first creates the project-owned administrative personas:

```text
AWSIdentityStoreAdmins
AWSPermissionSetAdmins
AWSAccessAssignmentAdmins
```

It also creates their named users, permission sets, memberships, and management-account assignments.

The administrative root discovers the existing Control Tower-enabled organization Identity Center instance. It does not create the instance or adopt Control Tower-created users, groups, permission sets, or assignments.

The parent Identity Center root creates the three central administrative users plus the distinct named `sso_lab_admin` identity. The phase then runs `terraform/identity_center/workload_access`, which looks up that lab user, creates two manually operated test-user records, and creates the project-owned workload groups and reusable permission sets. The test users have no Terraform-managed memberships or direct assignments. The account-assignment map is empty initially, so no workload account assignments are created before AFT account IDs exist. Test and Production operator permission sets have no write actions by default. `WorkloadLabAdministrator` is restricted to the explicit Dev Lab and Test Lab account allowlist and requires a baseline-managed `WorkloadLabRoleBoundary` in both accounts before it is used.

### Plan

On the first deployment of the lab baseline persona, plan and apply the parent
root before running the complete phase because the workload-access root looks
up the user created by that parent state:

```bash
terraform -chdir=terraform/identity_center plan
terraform -chdir=terraform/identity_center apply
```

Then run the complete phase plan:

```bash
./tf.sh --phase identity-center --fmt
./tf.sh --phase identity-center --dry-run
```

Verify that the plan creates only project-owned resources. The parent plan should add the distinct lab baseline user without granting it management-account access. The workload access plan should create two distinct test users, seven groups, seven permission sets, five managed-policy attachments, the lab-baseline membership, and the elevated inline policies. When both `lab_account_ids` values are configured, it also creates the two protected lab-baseline account assignments and both lab inline policies; the ordinary assignment map may remain empty. Before adding a lab assignment, verify that the approved boundary policy exists at `/week2/WorkloadLabRoleBoundary` in both allowlisted lab accounts. Stop if the plan proposes modifying a standard Control Tower group, permission set, assignment, or user.

### Apply

```bash
./tf.sh --phase identity-center --apply
```

After apply:

- Verify the workload groups are initially empty;.
- Verify both test users have no memberships or account assignments;.
- Manually activate the test users, register MFA, and keep any temporary test access documented and time-bounded;.
- Verify Test and Production operator access has no write actions;.
- Activate the named human identities as required;.
- Register strong MFA;.
- Verify the one-hour privileged sessions;.
- Test expected allowed and denied operations;.
- Document the accountable owner of each persona.

### Convergence check

```bash
./tf.sh --phase identity-center --chk
./tf.sh --phase identity-center --dry-run
```

See [`identity_center_security.md`](identity_center_security.md) for the implemented separation, remaining escalation paths, and future mitigation recommendations.

## Phase 3 — AFT Prerequisites and Platform

The AFT phase runs these roots sequentially:

```text
1. terraform/aft/org_unit
2. terraform/aft/account
3. terraform/identity_center/aft_access
4. terraform/aft/platform
```

### Initial deployment limitation

In a new environment, a complete AFT dry run cannot necessarily reach the access and platform roots. The AFT management account ID does not exist in Terraform state until `terraform/aft/account` has been applied.

The initial AFT deployment therefore uses one sequential apply command. Terraform displays an interactive plan for each root; review each plan before approving it.

### Initial AFT apply

```bash
./tf.sh --phase aft --fmt
./tf.sh --phase aft --apply
```

### Root 1 — AFT OU

`terraform/aft/org_unit` creates:

- The dedicated AFT OU;.
- `AWSControlTowerBaseline` version `5.0` for that OU.

The plan must not show:

```text
baseline_version = "5.0" -> "4.0"
```

or replacement of an existing enabled baseline. Version `4.0` is incompatible with the current landing-zone version, and replacement would temporarily remove Control Tower governance from the AFT OU.

### Root 2 — AFT management account

`terraform/aft/account` provisions the account through the built-in Control Tower Account Factory Service Catalog product.

It must not create the account directly with:

```text
aws_organizations_account
```

Wait for the Service Catalog provisioned product to become `AVAILABLE` and verify the resulting account is enrolled in Control Tower. OU membership alone is not proof of enrollment.

### Root 3 — AFT human access

`terraform/identity_center/aft_access` creates:

```text
AFTPlatformAdministrators
AFTPlatformAdministration
```

It then:

- Looks up the existing Account Factory human user using `TF_VAR_sso_aft_user_email`;.
- Adds that user to `AFTPlatformAdministrators`;.
- Assigns `AFTPlatformAdministration` only to the AFT management account.

The root must not create, modify, import, or delete the existing Account Factory user.

The permission set provides:

- Read-only AFT troubleshooting access;.
- The AWS-documented CodeConnections console handshake permissions, including `StartOAuthHandshake` and `UpdateConnectionInstallation`;.
- Limited start, stop, and retry operations for pipelines in the AFT account.

It explicitly denies IAM mutation, Identity Store mutation, permission-set and account-assignment mutation, and Organizations mutation.

### Root 4 — AFT platform

`terraform/aft/platform` deploys the AFT service infrastructure and source integrations.

The AWS AFT module release `1.20.1` is pinned to immutable commit `2ba0f21627e90f86115031bc9f6ea1eb50cd411f`. Any module update requires verification against the upstream release, review of release notes, and a complete platform plan; do not replace the SHA with a mutable branch or tag.

Verify that the plan uses:

```text
aft_enable_vpc = false
```

It must not create:

- An AFT VPC;.
- NAT gateways;.
- AFT interface VPC endpoints.

The four GitHub repositories and their `main` branches must exist before this root runs.

### Week 2 lab baseline and workload assignments

After AFT provisions the Dev Lab and Test Lab accounts, verify that both are enrolled, reside in their intended governed environment OUs, and have healthy Control Tower baselines. Configure `TF_VAR_lab_account_ids` and apply the parent and workload-access Identity Center roots first. This creates the dedicated `sso_lab_admin` user, its protected `WorkloadLabBaselineAdmin` access, and direct assignments to both lab accounts.

Activate that named user with MFA and configure `lab-admin-dev` and `lab-admin-test` for the two accounts, deliberately sharing one `lab-admin` SSO session. Then run `terraform/lab/week2/baseline` with its own state key. The providers use those Identity Center profiles directly and do not call `sts:AssumeRole`. The root creates the persistent `/week2/WorkloadLabRoleBoundary` policy in both accounts and protects it with `prevent_destroy`. Review the baseline plan and verify that it creates only the two expected customer-managed boundary policies.

After the boundary converges, add any approved exercise group/permission-set combinations to `TF_VAR_account_assignments` for `terraform/identity_center/workload_access`, and review:

```bash
./tf.sh --phase identity-center --chk
./tf.sh --phase identity-center --dry-run
```

Apply only the reviewed central account assignments. AFT customizations must not create organization-wide Identity Center groups, permission sets, or assignments. Review and remove unnecessary Account Factory bootstrap-owner access separately.

## Phase 4 — GitHub CodeConnections Authorization

The AFT module creates the CodeConnections resource during platform deployment. For GitHub, the new connection normally begins in:

```text
PENDING
```

Authorization cannot be completed before the connection exists.

After platform apply:

1. sign in through the IAM Identity Center access portal;
2. select the AFT management account;
3. select `AFTPlatformAdministration`;
4. switch to the Control Tower home Region, currently `us-east-2`;
5. open **Developer Tools → Settings → Connections**;
6. select `ct-aft-github-connection`;
7. authorize the GitHub App installation for the four AFT repositories;
8. verify the connection becomes `AVAILABLE`;
9. verify or retry the AFT source pipelines as necessary.

Restrict the GitHub App installation to the required repositories where practical. GitHub repository write access and AFT platform administration should be independently reviewed because their combination can influence account-vending workflows.

AWS references:

- [Create a connection to GitHub](https://docs.aws.amazon.com/dtconsole/latest/userguide/connections-create-github.html).
- [Update a pending connection](https://docs.aws.amazon.com/dtconsole/latest/userguide/connections-update.html).
- [AWS CodeConnections concepts](https://docs.aws.amazon.com/dtconsole/latest/userguide/connections.html).

## Final Convergence Checks

After CodeConnections authorization, run:

```bash
./tf.sh --phase aft --chk
./tf.sh --phase aft --dry-run
```

Expected results:

- The Workloads, Dev, Test, and Prod OU baselines remain version `5.0` and `SUCCEEDED`;.
- The AFT OU baseline remains version `5.0` and `SUCCEEDED`;.
- The AFT management account remains enrolled;.
- The Account Factory provisioned product remains `AVAILABLE`;.
- The existing Account Factory user is unchanged;.
- Workload groups contain only approved named humans;.
- Workload permission sets and assignments match the approved environment matrix;.
- `AFTPlatformAdministration` is assigned only to the AFT account;
- The CodeConnections connection is `AVAILABLE`;.
- AFT pipelines reference the expected repositories and branches;.
- No AFT NAT gateways or interface endpoints exist;.
- All Terraform roots are converged.

If a plan proposes an unexplained replacement or deletion, stop and investigate rather than applying it.

## Complete Command Sequence

Run these commands in order for a new environment.

### Bootstrap

```bash
./tf.sh --phase bootstrap --fmt
./tf.sh --phase bootstrap --dry-run
```

```bash
./tf.sh --phase bootstrap --apply
```

```bash
./tf.sh --phase bootstrap --chk
./tf.sh --phase bootstrap --dry-run
```

### Workload OU hierarchy

```bash
./tf.sh --phase workloads --fmt
./tf.sh --phase workloads --dry-run
```

```bash
./tf.sh --phase workloads --apply
```

```bash
./tf.sh --phase workloads --chk
./tf.sh --phase workloads --dry-run
```

### Identity Center administration

```bash
./tf.sh --phase identity-center --fmt
./tf.sh --phase identity-center --dry-run
```

```bash
./tf.sh --phase identity-center --apply
```

```bash
./tf.sh --phase identity-center --chk
./tf.sh --phase identity-center --dry-run
```

### AFT

Ensure the four repositories and their branches exist, then run:

```bash
./tf.sh --phase aft --fmt
./tf.sh --phase aft --apply
```

Complete GitHub CodeConnections authorization, then run:

```bash
./tf.sh --phase aft --chk
./tf.sh --phase aft --dry-run
```

## Existing or Partially Deployed Environments

Do not recreate or blindly reapply foundational resources merely because this sequence begins with bootstrap.

For an existing environment:

1. run the relevant phase with `--dry-run`;
2. compare the plan with the root's documented ownership;
3. apply only expected project-owned additions or updates;
4. stop if Terraform attempts to adopt, replace, or delete an existing Control Tower resource;
5. import an existing resource only after explicitly deciding that Terraform should own it.

A normal rerun after successful convergence should produce no changes unless configuration or managed AWS state has changed.

## AWS Documentation

- [Getting started with AWS Control Tower](https://docs.aws.amazon.com/controltower/latest/userguide/getting-started-with-control-tower.html).
- [AWS Control Tower baselines](https://docs.aws.amazon.com/controltower/latest/userguide/baselines.html).
- [Control Tower Account Factory](https://docs.aws.amazon.com/controltower/latest/userguide/account-factory.html).
- [AFT prerequisites](https://docs.aws.amazon.com/controltower/latest/userguide/aft-getting-started.html).
- [AFT account provisioning](https://docs.aws.amazon.com/controltower/latest/userguide/aft-provision-account.html).
- [Assign IAM Identity Center access to AWS accounts](https://docs.aws.amazon.com/singlesignon/latest/userguide/useraccess.html).
- [IAM Identity Center permission sets](https://docs.aws.amazon.com/singlesignon/latest/userguide/permissionsetsconcept.html).
