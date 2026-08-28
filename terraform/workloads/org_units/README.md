# Workload organizational units

This Terraform root creates and governs the workload OU hierarchy:

```text
Workloads
├── Dev
├── Test
└── Prod
```

Each OU receives its own `AWSControlTowerBaseline` instance. The parent baseline
is enabled before Terraform creates the child OUs, and all baseline resources
are protected with `prevent_destroy`.

Before running Terraform in this directory, load and validate the bootstrap
prerequisites:

```bash
source ./load-prerequisite-env.sh
```

Use the repository wrapper to initialize, validate, and plan this root with the
shared backend configuration:

```bash
./tf.sh --phase workloads --chk
./tf.sh --phase workloads --dry-run
```

When operating directly from this directory, initialize the S3 backend before
running `terraform fmt -check`, `terraform validate`, and `terraform plan`.

Do not submit AFT account requests targeting these OUs until the corresponding
baseline operation has completed successfully. This root creates no AWS
accounts.
