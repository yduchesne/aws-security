# Workload IAM Identity Center access

This independent Terraform root owns the project-specific workload access
catalog. It does not manage Control Tower groups.

It creates two named test-user records from the `TF_VAR_test_user1_*` and
`TF_VAR_test_user2_*` inputs. Terraform intentionally creates no memberships or
direct account assignments for these users. Their console activation,
credentials, MFA, and temporary test memberships are operated manually.

It also creates these groups and permission sets:

| Group | Permission set | Approved scope |
|---|---|---|
| `WorkloadViewers` | `WorkloadViewOnly` | Dev, Test, Prod |
| `WorkloadSecurityAuditors` | `WorkloadSecurityAudit` | Dev, Test, Prod |
| `WorkloadDevelopers` | `WorkloadDeveloper` | Dev only |
| `WorkloadTestOperators` | `WorkloadTestOperator` | Test only |
| `WorkloadProductionOperators` | `WorkloadProductionOperator` | Prod only |
| `WorkloadLabAdministrators` | `WorkloadLabAdministrator` | Explicitly allowlisted Dev Lab and Test Lab accounts only |
| `WorkloadLabBaselineAdministrators` | `WorkloadLabBaselineAdmin` | Exact Dev Lab and Test Lab allowlist only |

The parent `terraform/identity_center` root owns the named
`sso_lab_admin` user. This root looks it up, adds it to
`WorkloadLabBaselineAdministrators`, and automatically assigns the protected,
one-hour `WorkloadLabBaselineAdmin` permission set to both configured
lab accounts. That permission set can create, read, tag, and version only the
exact `/week2/WorkloadLabRoleBoundary` policy; it cannot create roles, users,
access keys, identity providers, or administer central governance.

`WorkloadLabAdministrator` also has read-only cross-account access to the Dev
Lab and Test Lab prefixes in the dedicated
`aws-security-lab-evidence-<MANAGEMENT_ACCOUNT_ID>` bucket. The bucket is owned
by `terraform/lab/evidence` in the Log Archive account and independently
restricts the expected Identity Center role patterns. This permission grants no
Log Archive account session and no evidence write or delete action. See
[`docs/cloud-trail-logs.md`](../../../docs/cloud-trail-logs.md).

For lab exercises, `WorkloadLabAdministrator` can launch instances in the
explicitly assigned lab accounts, manage resources carrying an `Exercise` tag, create
instance profiles under `/week*/exercise*/`, and pass only bounded
lab-exercise roles to EC2. The policy is reusable across weeks and exercise
numbers. These permissions exist to deploy disposable native-workload-identity
fixtures and do not grant general EC2 or unrestricted `iam:PassRole`
administration.

`WorkloadLabAdministrator` is a one-hour bounded lab persona, not a general
account administrator. It can manage S3 buckets matching
`lab_bucket_name_prefix`, assume roles under `lab_role_path_prefix`, and create
or manage roles under that path only when they carry the approved
`WorkloadLabRoleBoundary`. It cannot create or modify managed policies, remove
the boundary, create users or access keys, pass roles, or administer central
governance services.

The boundary must be provisioned through the dedicated baseline administrator
sessions in both lab accounts before the exercise administrator is used. The expected ARN is:

```text
arn:<partition>:iam::<LAB_ACCOUNT_ID>:policy/week2/WorkloadLabRoleBoundary
```

The independent `terraform/lab/week2/baseline` root owns both boundary
policies and must be run by trusted baseline automation before lab access is
used. The lab administrator is deliberately unable to create or change this
policy; allowing it to define its own ceiling would defeat the
privilege-escalation control. Each Week 2 exercise root must attach this
boundary to every role it creates.

The assignment map defaults to empty. Create the catalog before workload
accounts exist, then add explicit assignments only after AFT has provisioned an
account and Control Tower reports it as enrolled and governed.

Example:

```hcl
account_assignments = {
  payments_dev_developers = {
    account_id         = "111122223333"
    environment        = "dev"
    group_key          = "developers"
    permission_set_key = "developer"
  }

  payments_prod_viewers = {
    account_id         = "444455556666"
    environment        = "prod"
    group_key          = "viewers"
    permission_set_key = "view_only"
  }

  week2_dev_lab_administrators = {
    account_id         = "222233334444"
    environment        = "dev"
    group_key          = "lab_administrators"
    permission_set_key = "lab_administrator"
  }
}

lab_account_ids = {
  dev  = "222233334444"
  test = "555566667777"
}
```

Use one named Identity Center identity per person and manage normal membership
through reviewed group changes. Do not create account-specific duplicate users.
The two test users are exceptions for manual console validation: keep them out
of all groups by default, do not grant management-account or AFT access, record
any temporary manual `WorkloadLabAdministrators` membership, and remove it
immediately after each test. Terraform validates that lab-administrator
assignments target only the exact Dev Lab and Test Lab account IDs supplied in
`lab_account_ids`; an ordinary account labeled `dev` or `test` is not enough.

`WorkloadTestOperator` and `WorkloadProductionOperator` have no write actions by
default. Add only reviewed, explicit actions through their corresponding input
variables after application-specific operational requirements are known.
Wildcard actions and central identity/governance administration are rejected.

From the repository root, plan both Identity Center roots with:

```bash
./tf.sh --phase identity-center --dry-run
```
