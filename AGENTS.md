# AGENTS.md

## Purpose

This repository implements an AWS multi-account landing zone using AWS Organizations, AWS Control Tower, Terraform, and AWS Control Tower Account Factory for Terraform (AFT).

The repository is intended to be reproducible, security-focused, and safe to evolve incrementally.

## Read First

Before making architectural or Terraform changes, read:

1. [Architecture](docs/architecture.md)
2. [Control Tower Design](docs/control-tower-design.md)
3. [Account Factory for Control Tower](docs/aft-setup.md)
4. [Identity Center Security](docs/identity_center_security.md)
5. [Identities and responsibilities](docs/identities_and_responsibilities.md)
6. [Deployment](docs/deployment.md)
7. [Devsecops](docs/devsecops.md)

These documents are authoritative for architecture and Control Tower design decisions.

Do not duplicate architectural documentation in this file.

## Repository Structure

Key areas:

- `terraform/bootstrap/`
  - Establishes the foundational AWS organization and Control Tower environment.
  - Owns the existing landing zone, shared accounts, and foundational non-AFT OUs.
  - Must remain independently runnable and idempotent.

- `terraform/identity_center/`
  - Creates project-owned Identity Center administrative users, groups, permission sets, and management-account assignments.
  - Runs after the Control Tower landing zone and Identity Center integration are healthy.
  - Must not take ownership of Control Tower-created identity resources.

- `terraform/identity_center/aft_access/`
  - Looks up the existing Account Factory human user without taking ownership of it.
  - Creates project-owned AFT platform access and assigns it only to the AFT management account.
  - Runs after `terraform/aft/account/` and before `terraform/aft/platform/`.

- `terraform/aft/org_unit/`
  - Creates the dedicated AFT OU and enables its Control Tower baseline.
  - Runs only after bootstrap and IAM Identity Center baseline enablement complete.

- `terraform/aft/account/`
  - Provisions the AFT management account through Control Tower Account Factory.
  - Does not create the account directly with `aws_organizations_account`.

- `terraform/aft/platform/`
  - Deploys Account Factory for Terraform after the AFT account is enrolled.
  - Does not provision application infrastructure.

- AFT account-request configuration/repository
  - Used after AFT is operational to provision ordinary organization accounts.
  - Examples include Automation, Network, Shared Services, development, production, and other workload accounts.

- `docs/architecture.md`
  - High-level organization, account, OU, trust-boundary, and Terraform-root architecture.

- `docs/control-tower-design.md`
  - Control Tower-specific rationale, bootstrap boundaries, baseline semantics, AFT design, enrollment, and account-vending decisions.

## Architectural Rules

### Bootstrap boundary

The bootstrap layer should create only the resources required to establish:

- AWS Organizations
- the AWS Control Tower landing zone
- foundational non-AFT OUs
- Control Tower shared accounts and prerequisites

The AFT OU, its baseline, and the AFT management account belong to the ordered roots under `terraform/aft/`.

Do not add ordinary workload, network, shared-services, or general automation accounts directly to bootstrap unless the architecture documentation explicitly changes this boundary.

### AFT boundary

After AFT is operational, new ordinary member accounts should normally be provisioned through AFT rather than directly with `aws_organizations_account`.

The AFT management account is provisioned by the built-in Control Tower Account Factory because AFT cannot provision the account in which AFT itself must run.

AFT is for account provisioning and account customization. Do not use AFT as the application-resource deployment system.

### Organizational Units and Control Tower governance

An AWS Organizations OU is not automatically a Control Tower-governed OU.

Where required, explicitly enable the appropriate Control Tower OU baseline before using an OU as an AFT provisioning target.

Do not conflate:

- OU creation
- OU registration with Control Tower
- baseline enablement
- account enrollment
- Control Tower controls
- AFT account provisioning

### Automation and IAM

Avoid long-lived IAM user access keys.

- Humans should use IAM Identity Center.
- AWS workloads and CI/CD systems should use IAM roles and temporary credentials.
- Cross-account automation should use narrowly scoped target-account roles.
- Do not introduce a single organization-wide highly privileged automation role.
- Treat the Organizations management account as a high-trust administrative boundary.

### Terraform ownership

Do not define an existing AWS resource as a Terraform-managed resource unless:

- Terraform already owns it in state, or
- the resource is explicitly imported before apply.

Never assume Terraform will automatically adopt an existing Control Tower, Organizations, IAM, or other AWS resource.

### Idempotency

All Terraform roots must be safe to run repeatedly.

Before applying changes:

1. run `terraform fmt`
2. run `terraform validate`
3. run `terraform plan`
4. inspect the plan for unintended replacements or destructive actions

A normal rerun after successful convergence should result in no changes unless configuration or managed infrastructure has changed.

## Control Tower Constraints

Do not manually recreate Control Tower-managed resources unless the design documents explicitly require it.

Treat the following as separate concepts:

- AWS Organizations hierarchy
- Control Tower landing zone
- Control Tower baselines
- Control Tower controls
- account enrollment
- Account Factory
- Account Factory for Terraform
- AFT account customizations

If an AFT account request targets an OU, verify that the OU is governed appropriately and has `AWSControlTowerBaseline` enabled as required.

## Coding Guidelines

Prefer:

- native resources from the HashiCorp AWS provider where available
- explicit dependencies when AWS service sequencing is asynchronous or not inferable from references
- small Terraform files grouped by architectural responsibility
- reusable modules for repeated constructs
- descriptive resource names
- variables for environment-specific values
- outputs for identifiers required by later Terraform roots
- least-privilege IAM roles

Avoid:

- `local-exec` or shell provisioning when an appropriate Terraform/AWS provider resource exists
- hard-coded AWS account IDs
- hard-coded credentials
- unnecessary `AdministratorAccess`
- hidden or undocumented cross-account trust
- direct `aws_organizations_account` creation for ordinary post-AFT accounts

Before introducing a workaround with the AWS CLI, external scripts, or CloudFormation, verify whether the current AWS provider or AFT already supports the requirement.

## Change Procedure

For any non-trivial change:

1. Read the relevant design documentation.
2. Inspect the existing Terraform and state assumptions.
3. Explain the intended dependency graph.
4. Make the smallest coherent change.
5. Run formatting and validation.
6. Produce a Terraform plan.
7. Review for replacements, deletes, or unexpected Control Tower changes.
8. Update documentation if architecture or operating model changed.

## Safety

- Do not run `terraform apply`, destroy AWS resources, close AWS accounts, modify production credentials, or perform other irreversible actions unless explicitly instructed.
- If a plan proposes replacing or destroying the Control Tower landing zone, AWS Organization, Control Tower shared accounts, AFT management account, or other foundational resources, stop and investigate rather than proceeding.
- When creating a new Terraform config directory, always keep the Terraform state in a remote backend.

## Documentation Maintenance

Update:

- `docs/architecture.md` when account topology, OU structure, trust boundaries, or Terraform-root architecture changes.
- `docs/control-tower-design.md` when Control Tower-specific behavior, baselines, controls, account enrollment, bootstrap boundaries, or AFT behavior changes.

Keep `AGENTS.md` focused on coding-agent instructions and repository invariants.
