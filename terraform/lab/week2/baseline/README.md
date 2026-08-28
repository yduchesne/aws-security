# Week 2 lab baseline

This independent Terraform root is deployed by trusted baseline automation. It
owns the persistent `WorkloadLabRoleBoundary` customer-managed policy in the
Dev Lab/source and Test Lab/target accounts.

The boundary is separate from disposable exercise state. Exercise roots look
up and attach it to every role created under `/week2/`. The
`WorkloadLabAdministrator` permission set can create bounded lab roles but
cannot create, change, replace, or remove this policy.

## Prerequisites

- Both lab accounts exist, are enrolled, and are governed.
- The operator has two authenticated IAM Identity Center setup profiles, one
  for each lab account, with permission to manage only the boundary policy
  required by this root.
- These trusted setup profiles are not the bounded
  `WorkloadLabAdministrator` exercise-user profiles.
- A distinct remote-state key is configured for this root.
- `TF_VAR_lab_account_ids` is shared with the workload-access root and
  `TF_VAR_lab_baseline_aws_profiles` identifies `lab-admin-dev` and
  `lab-admin-test`. Both account profiles deliberately share one `lab-admin`
  SSO session for the same named administrator.

Terraform does not automatically load `.env` files. Export these variables in
the current shell or provide an uncommitted `.tfvars` file before planning.

Example initialization:

```bash
terraform init \
  -backend-config="bucket=$TF_STATE_BUCKET" \
  -backend-config="region=$TF_STATE_REGION" \
  -backend-config="key=exercises/week2/baseline/terraform.tfstate"
```

Then run formatting, validation, and a reviewed plan before apply. The two
boundary resources use `prevent_destroy`; removing them requires an explicit,
reviewed lifecycle change after all dependent lab roles and assignments have
been removed.

## Order

```text
Dev Lab and Test Lab accounts
  → terraform/identity_center parent and workload-access roots
  → activate sso_lab_admin and configure both baseline profiles
  → terraform/lab/week2/baseline
  → temporary WorkloadLabAdministrators test-user membership
  → terraform/lab/week2/exercise1
```
