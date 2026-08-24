# AWS Multi-Account Landing Zone Architecture

## Purpose

This document describes the high-level architecture for an AWS multi-account environment built with AWS Organizations, AWS Control Tower, Terraform, IAM Identity Center, and AWS Control Tower Account Factory for Terraform (AFT).

The design separates the initial landing-zone bootstrap from ongoing account provisioning.

## Architectural Goals

The architecture is designed to provide:

- strong AWS account-level isolation
- centralized governance through AWS Control Tower
- repeatable infrastructure through Terraform
- least-privilege administrative access
- centralized account vending through AFT
- separation of security, networking, automation, and workload responsibilities
- an idempotent bootstrap process
- a clean transition from bootstrap-time resources to steady-state account provisioning

## High-Level Organization Structure

```text
AWS Organization
│
├── Management Account
│   └── AWS Organizations / Control Tower administration
│
├── Security OU
│   ├── Audit / Security account
│   └── Log Archive account
│
├── AFT OU
│   └── AFT Management account
│
├── Infrastructure OU
│   ├── Network account
│   ├── Shared Services account
│   └── Automation / Tooling account
│
├── Workloads OU
│   ├── Dev OU
│   ├── Test OU
│   └── Prod OU
│
└── Sandbox OU
    └── Sandbox accounts
```

The exact workload OU hierarchy can evolve independently of the bootstrap design.

## Control Plane Layers

The environment has several distinct control-plane layers.

### AWS Organizations

Organizations defines:

- the organization root
- organizational units
- account membership
- service control policies
- resource control policies
- delegated administrator relationships

OUs are governance and policy boundaries, not merely folders.

### AWS Control Tower

Control Tower provides an opinionated governance layer over AWS Organizations and related AWS services.

It manages the landing zone and coordinates capabilities such as:

- governed OUs
- shared accounts
- mandatory controls
- optional controls
- logging and compliance infrastructure
- account enrollment
- Account Factory
- IAM Identity Center integration

Control Tower is not a replacement for Organizations, IAM, Config, CloudTrail, Security Hub, GuardDuty, or other underlying services.

### IAM Identity Center

IAM Identity Center is the default mechanism for human access.

Conceptually:

```text
User
  ↓
IAM Identity Center
  ↓
Permission Set
  ↓
Account Assignment
  ↓
Temporary IAM role session
```

Long-lived IAM users and access keys should be avoided for human administrators.

### Account Factory for Terraform

AFT is the steady-state Terraform-based account vending system.

It runs in a dedicated AFT management account and accepts Git-based Terraform account requests.

AFT is responsible for:

- account creation and update requests
- invoking the Control Tower account-provisioning workflow
- applying global account customizations
- applying targeted account customizations
- recording account-request metadata and history

AFT is not intended to deploy normal application resources such as EC2 instances or application stacks.

## Terraform Architecture

The Terraform implementation separates the landing-zone root from three ordered AFT roots.

```text
terraform/
├── bootstrap/              # Organizations, shared accounts, and Control Tower landing zone
├── identity_center/        # Project-owned administrative identities and permission sets
│   ├── workload_access/    # Workload access catalog and post-AFT account assignments
│   └── aft_access/         # Human AFT account access after Account Factory completes
├── aft/
│   ├── org_unit/           # Dedicated AFT OU and AWSControlTowerBaseline
│   ├── account/            # AFT management account through Control Tower Account Factory
│   └── platform/           # AFT platform module deployment
└── workloads/
    └── org_units/          # Governed Workloads, Dev, Test, and Prod OUs
```

Each directory is an independent Terraform root with a distinct state key. The AFT roots run in this order:

```text
bootstrap → identity_center → aft/org_unit → aft/account → identity_center/aft_access → aft/platform
```

The workload OU root runs after bootstrap and must converge before AFT account requests target its environment OUs:

```text
bootstrap → workloads/org_units → AFT account requests
```

A separate AFT account-request repository or directory is expected after AFT is deployed.

## Bootstrap Responsibilities

`terraform/bootstrap/` owns the foundational control plane that already established Control Tower.

Its responsibilities include:

1. AWS Organizations foundation
2. foundational non-AFT OUs
3. AWS Control Tower landing zone and IAM Identity Center integration
4. Control Tower shared-account configuration as applicable

Bootstrap does not own the AFT OU or AFT management account.

## IAM Identity Center Administration Responsibilities

`terraform/identity_center/` runs after the landing zone is healthy. It discovers the Control Tower-enabled organization Identity Center instance and creates only project-owned administrative users, groups, permission sets, memberships, and management-account assignments. It does not manage or adopt Control Tower-created Identity Center resources.

`terraform/identity_center/workload_access/` is a separate central root. It creates project-owned workload groups and reusable permission sets before workload accounts exist. Its account-assignment map defaults to empty and receives explicit account IDs only after AFT provisioning and Control Tower enrollment complete. It creates two manually operated test-user records without memberships or assignments and does not modify Control Tower groups.

`terraform/identity_center/aft_access/` is a separate post-account root. It looks up—but does not own—the human user created or referenced by Account Factory, then creates `AFTPlatformAdministrators`, `AFTPlatformAdministration`, the group membership, and an assignment scoped to the AFT management account.

The security model and residual escalation risks are documented in [`identity_center_security.md`](identity_center_security.md).

## AFT Deployment Responsibilities

AFT deployment uses three AFT roots with an Identity Center access root between account provisioning and platform deployment:

1. `terraform/aft/org_unit/` creates the dedicated AFT OU and enables `AWSControlTowerBaseline` after the landing zone is complete.
2. `terraform/aft/account/` provisions the AFT management account through the built-in Control Tower Account Factory Service Catalog product. It does not use `aws_organizations_account`.
3. `terraform/identity_center/aft_access/` assigns least-privilege human platform access to the completed AFT management account.
4. `terraform/aft/platform/` deploys AFT after the account is enrolled and its account ID has been verified.

This separation models the asynchronous Control Tower dependencies and prevents AFT changes from involving the existing landing-zone state.

## Workload OU Responsibilities

`terraform/workloads/org_units/` creates the root-level `Workloads` OU and its direct `Dev`, `Test`, and `Prod` child OUs. It enables a separate `AWSControlTowerBaseline` on each OU, governing the parent before creating the child hierarchy. The root creates no accounts and remains separate from both bootstrap and AFT platform state.

The root may run independently after bootstrap, but it must converge before an AFT account request targets `Dev`, `Test`, or `Prod`.

Workload account assignments remain centrally owned by `terraform/identity_center/workload_access/`. AFT and its in-account customizations do not create organization-wide Identity Center groups, permission sets, or assignments.

## Automatic Account Enrollment

Automatic account enrollment is intentionally turned off for this landing zone. This is a normal and deliberate setting for the current operating model; it does not prevent deployment or operation of AFT.

Automatic account enrollment governs what happens to eligible accounts created outside the approved account-vending workflow and subsequently placed in a governed OU. With the setting off, OU placement alone must not be assumed to enroll an unmanaged account in Control Tower. Such an account requires an explicit enrollment or OU re-registration workflow, as applicable.

This setting is distinct from account creation through Control Tower Account Factory:

- the AFT management account is provisioned by the built-in Control Tower Account Factory and is enrolled as part of that workflow;
- after AFT is operational, AFT invokes the Control Tower account-provisioning workflow for ordinary accounts;
- neither workflow depends on general automatic account enrollment being enabled.

Leaving automatic enrollment off supports the following controls:

- AFT remains the standard post-bootstrap account-vending path;
- enrollment of accounts created outside Account Factory remains explicit and reviewable;
- moving an existing account into a governed OU does not trigger unexpected Control Tower changes;
- accounts that may not meet Control Tower enrollment prerequisites are not enrolled automatically;
- governance transitions remain deliberate operations.

Before `terraform/aft/platform/` runs, operators must verify that the AFT management account is enrolled successfully and visible in Control Tower. OU membership by itself is not evidence of enrollment.

Automatic enrollment should be enabled only if the operating model changes to require accounts created outside Account Factory to be enrolled automatically when they enter governed OUs. Such a change requires an architecture review and updates to this document.

## Post-Bootstrap Account Provisioning

After AFT is operational, accounts such as the following should normally be created through AFT account requests:

- Automation / Tooling
- Network
- Shared Services
- application development accounts
- application production accounts
- sandbox accounts
- other specialized member accounts

Conceptually:

```text
Git account request
       ↓
AFT account-request pipeline
       ↓
Control Tower Account Factory workflow
       ↓
New AWS account
       ↓
Target governed OU
       ↓
Global customization
       ↓
Account-specific customization
       ↓
Reviewed central Identity Center account assignments
```

## Control Tower Baselines

An Organizations OU and a Control Tower-governed OU are distinct concepts.

A Control Tower OU-level baseline establishes the Control Tower governance resources and controls required for accounts in the target OU.

`AWSControlTowerBaseline` is the baseline used when registering an OU with Control Tower.

The current landing-zone version requires `AWSControlTowerBaseline` version `5.0`. The Terraform variable is pinned and validated at `5.0` because changing it to `4.0` forces replacement of the enabled baseline and AWS rejects that version as incompatible with the current landing zone. Baseline and landing-zone version numbers are separate version streams and must not be assumed to match.

The AFT OU baseline also uses `prevent_destroy`. Any future compatible baseline migration that requires replacement must therefore be an explicit, reviewed code change. Operators must not remove this protection merely to make an unexplained plan succeed.

An OU intended as an AFT account-provisioning target must have the required Control Tower baseline enabled. The `Workloads`, `Dev`, `Test`, and `Prod` OUs each have an explicitly managed baseline; governance of the parent is not treated as a substitute for baseline enablement on its children.

Conceptually:

```text
Organizations OU
      +
AWSControlTowerBaseline
      ↓
Control Tower-governed OU
```

## Infrastructure OU

The Infrastructure OU contains accounts providing organization-wide technical services.

Typical accounts include:

### Network

Owns or administers shared networking capabilities such as:

- Transit Gateway
- VPC IPAM
- shared VPC/subnet infrastructure where appropriate
- Route 53 Resolver infrastructure
- centralized ingress/egress
- AWS Network Firewall
- hybrid connectivity
- AWS RAM networking shares

### Shared Services

Hosts shared platform services consumed by workloads.

Examples may include:

- internal tooling
- shared directory or identity integrations
- common build/artifact services
- shared operational systems

### Automation / Tooling

Hosts general-purpose infrastructure automation and CI/CD capabilities.

It should not possess a single organization-wide unrestricted role.

Instead, automation should assume narrowly scoped roles in target accounts.

## Security OU

The Security OU provides security-specific isolation.

Typical accounts:

### Log Archive

Designed for centralized preservation and protection of security and audit logs.

### Audit / Security Tooling

Used for centralized security administration, investigation, monitoring, and delegated administration of security services as appropriate.

## Cross-Account Automation Model

Use distributed target roles rather than a single broad automation role.

```text
Automation account
      │
      ├── AssumeRole → NetworkAutomationRole
      │                   Network account
      │
      ├── AssumeRole → SecurityAutomationRole
      │                   Security account
      │
      ├── AssumeRole → DevDeploymentRole
      │                   Dev account
      │
      └── AssumeRole → ProdDeploymentRole
                          Prod account
```

The source automation identity should have only the ability to assume explicitly authorized target roles.

Target-account roles define actual privileges.

Production and non-production privilege should be separable.

## Management Account

The Organizations management account is a high-trust administrative boundary.

It should:

- host as little workload infrastructure as practical
- be used only for operations requiring the management account
- delegate supported services to member accounts
- avoid general-purpose CI/CD and application deployment
- use narrowly scoped automation roles

SCPs do not constrain principals in the management account, which makes management-account permissions especially sensitive.

## Account Provisioning Lifecycle

The intended lifecycle is:

```text
Phase 1 — Bootstrap
Organizations
  ↓
Control Tower and IAM Identity Center

Phase 2 — AFT prerequisites
AFT OU
  ↓
AWSControlTowerBaseline
  ↓
AFT management account through Control Tower Account Factory

Phase 3 — AFT platform
Deploy AFT into AFT management account

Phase 4 — Normal operations
Governed Workloads / Dev / Test / Prod OU hierarchy
  ↓
AFT account requests
  ↓
Infrastructure / Workload / Sandbox accounts
```

## State and Ownership

Terraform state defines ownership.

Existing AWS resources must not be re-declared as managed resources without importing them when required.

A routine rerun of a converged Terraform root should produce no changes unless configuration or managed AWS state has changed.

## Design Principle

The architecture deliberately separates:

- governance-plane bootstrap
- account vending
- infrastructure deployment
- workload deployment

This keeps the Control Tower management account small, makes account boundaries meaningful, and allows AFT to become the standard post-bootstrap account-provisioning mechanism.

## AWS Documentation References

Use the following AWS documentation when implementing or operating the Control Tower design:

### Landing zone and shared accounts

- [What is AWS Control Tower?](https://docs.aws.amazon.com/controltower/latest/userguide/what-is-control-tower.html)
- [Getting started with AWS Control Tower](https://docs.aws.amazon.com/controltower/latest/userguide/getting-started-with-control-tower.html)
- [AWS Control Tower shared accounts](https://docs.aws.amazon.com/controltower/latest/userguide/how-control-tower-works.html)
- [AWS Control Tower landing-zone APIs](https://docs.aws.amazon.com/controltower/latest/APIReference/Welcome.html)
- [`CreateLandingZone` API](https://docs.aws.amazon.com/controltower/latest/APIReference/API_CreateLandingZone.html)

### OU governance, baselines, controls, and drift

- [Register an existing organizational unit](https://docs.aws.amazon.com/controltower/latest/userguide/register-existing-ou.html)
- [AWS Control Tower baselines](https://docs.aws.amazon.com/controltower/latest/userguide/baselines.html)
- [`EnableBaseline` API](https://docs.aws.amazon.com/controltower/latest/APIReference/API_EnableBaseline.html)
- [`ListBaselines` API](https://docs.aws.amazon.com/controltower/latest/APIReference/API_ListBaselines.html)
- [`ListEnabledBaselines` API](https://docs.aws.amazon.com/controltower/latest/APIReference/API_ListEnabledBaselines.html)
- [AWS Control Tower controls](https://docs.aws.amazon.com/controltower/latest/controlreference/controls.html)
- [Detect and resolve drift in AWS Control Tower](https://docs.aws.amazon.com/controltower/latest/userguide/drift.html)

### Account provisioning and AFT

- [Provision and manage accounts with Account Factory](https://docs.aws.amazon.com/controltower/latest/userguide/account-factory.html)
- [Enroll an existing AWS account](https://docs.aws.amazon.com/controltower/latest/userguide/enroll-account.html)
- [Account Factory for Terraform overview](https://docs.aws.amazon.com/controltower/latest/userguide/aft-overview.html)
- [AFT prerequisites](https://docs.aws.amazon.com/controltower/latest/userguide/aft-getting-started.html)
- [AFT account provisioning](https://docs.aws.amazon.com/controltower/latest/userguide/aft-provision-account.html)
- [AFT account customizations](https://docs.aws.amazon.com/controltower/latest/userguide/aft-account-customization-options.html)

### Organizations and IAM Identity Center

- [AWS Organizations concepts](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_getting-started_concepts.html)
- [Best practices for the Organizations management account](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_best-practices_mgmt-acct.html)
- [IAM Identity Center integration with AWS Organizations](https://docs.aws.amazon.com/singlesignon/latest/userguide/organization-instances-identity-center.html)
- [IAM Identity Center permission sets](https://docs.aws.amazon.com/singlesignon/latest/userguide/permissionsetsconcept.html)
