# Exercise Lab Setup

## Purpose

This is the entry point for developers preparing to run security labs. Lab
infrastructure is isolated from the landing-zone control plane and must use
disposable governed workload accounts.

Use temporary IAM Identity Center sessions. Never run exercise roots against
the Organizations management, Log Archive, Security Tooling, AFT, or production
accounts.

## Scope of `terraform/lab`

`terraform/lab/` contains persistent lab prerequisites and disposable
exercise resources. It does not create AWS accounts or OUs, enroll accounts in
Control Tower, create the Identity Center instance, replace AFT, or deploy
application infrastructure.

Persistent baseline roots and disposable exercise roots use separate Terraform
state and lifecycles. A baseline must converge before dependent exercises.
Destroy disposable exercise resources after collecting evidence; do not destroy
shared baselines as part of exercise cleanup.

Terraform state defines ownership. Do not import an existing resource into an
exercise state without an explicit ownership decision. Never commit Terraform
state, plan files, AWS credentials, SSO cache data, device codes, or sensitive
evidence.

## Documentation

- [Lab roadmap](lab-roadmap.md).
- [AWS CLI IAM Identity Center authentication](../sso_auth.md).
- [Week 1 exercises](week1/exercises-week1.md).
- [Week 2 exercise summary](week2/exercises-summary.md).
- [Week 2 shared setup](week2/week2-setup.md).
- [Week 2 Exercise 1 setup and execution](week2/exercise1.md).
