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
}
```

Use one named Identity Center identity per person and manage normal membership
through reviewed group changes. Do not create account-specific duplicate users.
The two test users are exceptions for manual console validation: keep them out
of all groups by default, do not grant management-account or AFT access, record
any temporary manual membership, and remove it immediately after each test.

`WorkloadTestOperator` and `WorkloadProductionOperator` have no write actions by
default. Add only reviewed, explicit actions through their corresponding input
variables after application-specific operational requirements are known.
Wildcard actions and central identity/governance administration are rejected.

From the repository root, plan both Identity Center roots with:

```bash
./tf.sh --phase identity-center --chk --dry-run
```
