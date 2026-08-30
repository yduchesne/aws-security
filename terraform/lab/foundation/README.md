# Dev Lab foundation

This independent root creates the reusable network prerequisite for disposable
Dev Lab exercises. It runs after Control Tower and after AFT has provisioned the
Dev Lab account; it is not part of the landing-zone bootstrap state.

Resources:

- `DevLabExerciseVpc` using `dev_lab_vpc_cidr`.
- `DevLabExercisePublicSubnet` tagged `Purpose=LabExercises` and
  `Network=Public`.
- An internet gateway and public route table.
- A deny-all default security group.

The root creates no NAT gateway and no application instance. Individual
exercise roots own their security groups and compute resources. Exercise 8
discovers the subnet by its stable tags and launches a no-ingress, IMDSv2-only
instance with temporary instance-profile credentials.

The initial deployment uses `ct-bootstrap` in the management account and
assumes `AWSControlTowerExecution` in Dev Lab. Exercise users receive no VPC,
subnet, route-table, or internet-gateway administration.

Operate through the dedicated phase:

```bash
./tf.sh --phase lab-foundation --dry-run
./tf.sh --phase lab-foundation --apply
./tf.sh --phase lab-foundation --dry-run
```

Review CIDR overlap before applying. The defaults are:

```text
VPC:    10.80.0.0/16
Subnet: 10.80.0.0/24
```

The root uses remote state at `lab/foundation/terraform.tfstate` and can be
destroyed independently after all dependent exercise resources have been
removed.
