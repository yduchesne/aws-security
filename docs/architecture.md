# AWS Multi-Account Landing Zone Architecture

## Purpose

This document describes the high-level architecture for an AWS multi-account environment built with AWS Organizations, AWS Control Tower, Terraform, IAM Identity Center, and AWS Control Tower Account Factory for Terraform (AFT).

The design separates the initial landing-zone bootstrap from ongoing account provisioning.

## Architectural Goals

The architecture is designed to provide:

- Strong AWS account-level isolation.
- Centralized governance through AWS Control Tower.
- Repeatable infrastructure through Terraform.
- Least-privilege administrative access.
- Centralized account vending through AFT.
- Separation of security, networking, automation, and workload responsibilities.
- An idempotent bootstrap process.
- A clean transition from bootstrap-time resources to steady-state account provisioning.

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

- The organization root.
- Organizational units.
- Account membership.
- Service control policies.
- Resource control policies.
- Delegated administrator relationships.

OUs are governance and policy boundaries, not merely folders.

### AWS Control Tower

Control Tower provides an opinionated governance layer over AWS Organizations and related AWS services.

It manages the landing zone and coordinates capabilities such as:

- Governed OUs.
- Shared accounts.
- Mandatory controls.
- Optional controls.
- Logging and compliance infrastructure.
- Account enrollment.
- Account Factory.
- IAM Identity Center integration.

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

- Account creation and update requests.
- Invoking the Control Tower account-provisioning workflow.
- Applying global account customizations.
- Applying targeted account customizations.
- Recording account-request metadata and history.

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
├── workloads/
│   └── org_units/          # Governed Workloads, Dev, Test, and Prod OUs
└── lab/
    ├── foundation/          # Reusable tagged Dev Lab VPC and public exercise subnet
    ├── evidence/            # Separate S3-only organization trail and Log Archive evidence bucket
    └── week2/
        ├── baseline/       # Persistent lab-role boundaries in Dev Lab and Test Lab
        ├── exercise1/     # Disposable cross-account AssumeRole exercise resources
        └── exercise2/     # Disposable trust-policy hardening exercise resources
```

Each directory is an independent Terraform root with a distinct state key. The AFT roots run in this order:

```text
bootstrap → identity_center → aft/org_unit → aft/account → identity_center/aft_access → aft/platform
```

The workload OU root runs after bootstrap and must converge before AFT account requests target its environment OUs:

```text
bootstrap → workloads/org_units → AFT account requests
```

The project-owned lab evidence root runs after bootstrap and Identity Center,
before exercises generate S3 data events:

```text
bootstrap → identity_center → AFT platform and lab accounts → lab/foundation → identity_center/workload_access → lab/evidence → Week 2 baseline → exercises
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

`terraform/identity_center/workload_access/` is a separate central root. The parent Identity Center root creates a distinct named lab-baseline user; workload access looks up that user and owns its protected boundary-management group, membership, permission set, and direct assignments to the two lab accounts. It also creates project-owned workload groups and reusable permission sets before ordinary workload accounts exist. Its account-assignment map defaults to empty and receives explicit account IDs only after AFT provisioning and Control Tower enrollment complete. It creates two manually operated test-user records without memberships or assignments and does not modify Control Tower groups. Its bounded `WorkloadLabAdministrator` is assignable only to explicitly allowlisted Dev Lab and Test Lab accounts; every lab-created role must carry a trusted-baseline-managed `WorkloadLabRoleBoundary`.

Exercise 8 adds a narrow native-workload-identity deployment capability to this
persona. It may create instance profiles only under a `/week*/exercise*/` path, pass
only bounded lab-exercise roles to EC2, launch instances in the explicitly
assigned lab accounts, and manage EC2 resources carrying an `Exercise` tag. The fixture uses a
no-ingress security group, IMDSv2, an EC2 service trust policy, and a one-object
S3 grant. This exception is not general EC2 administration or unrestricted
`iam:PassRole`.

`terraform/identity_center/aft_access/` is a separate post-account root. It looks up—but does not own—the human user created or referenced by Account Factory, then creates `AFTPlatformAdministrators`, `AFTPlatformAdministration`, the group membership, and an assignment scoped to the AFT management account.

The security model and residual escalation risks are documented in [`identity_center_security.md`](identity_center_security.md).

`WorkloadLabAdministrator` also receives read-only identity permissions for the
dedicated lab evidence bucket. Those permissions cover only the Dev Lab and Test
Lab organization-trail prefixes. The Log Archive bucket policy independently
requires the expected Identity Center-provisioned role ARN pattern. Lab users
remain in their workload-account sessions and receive no Log Archive account
assignment or evidence write/delete permission.

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

## Dev Lab Network Foundation

`terraform/lab/foundation/` owns the reusable network prerequisite for
EC2-based exercises. It runs only after AFT has provisioned and Control Tower
has enrolled the Dev Lab account; it is not part of the landing-zone bootstrap
state. The temporary `ct-bootstrap` identity assumes `AWSControlTowerExecution`
in Dev Lab to create a dedicated VPC, internet gateway, public route table, and
one public subnet tagged `Purpose=LabExercises` and `Network=Public`.

The foundation creates no NAT gateway, workload instance, or inbound security
rule. Individual exercises own their compute resources and security groups.
Exercise 8 discovers the subnet by tags, requires IMDSv2, and uses a no-ingress
security group. Lab users may describe the network and deploy narrowly scoped
Exercise 8 resources but cannot create or mutate VPCs, subnets, route tables, or
internet gateways.

## Lab S3 Data-Event Evidence

`terraform/lab/evidence/` owns a customer-managed organization trail dedicated
to S3 object data events for the approved lab bucket-name prefix. The trail is
multi-Region, excludes management events, enables log-file validation, and has
no CloudWatch Logs destination. It is separate from—and does not modify—the
Control Tower-managed organization trail.

The root is launched initially with the temporary `ct-bootstrap` profile after
the landing zone is `ACTIVE` and `IN_SYNC`. It creates the trail in the
management account and assumes the existing `AWSControlTowerExecution` role to
create a dedicated bucket in the Log Archive account. That highly privileged
role is used only for initial Terraform operation; exercise users never receive
it.

The evidence bucket has a distinct name outside the mutable exercise-bucket
prefix. It uses public-access blocking, bucket-owner-enforced ownership,
versioning, SSE-S3, finite lifecycle retention, TLS enforcement, and exact
CloudTrail delivery conditions. The bucket and trail are intentionally
independently destructible and are not foundational Control Tower resources.
Destroying their state removes retained lab evidence but leaves Control Tower
logging unchanged.

See [`cloud-trail-logs.md`](cloud-trail-logs.md) for selectors, object layout,
reader access, costs, evidence retrieval, and destruction behavior.

## Post-Bootstrap Account Provisioning

After AFT is operational, accounts such as the following should normally be created through AFT account requests:

- Automation / Tooling.
- Network.
- Shared Services.
- Application development accounts.
- Application production accounts.
- Sandbox accounts.
- Other specialized member accounts.

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

- Transit Gateway.
- VPC IPAM.
- Shared VPC/subnet infrastructure where appropriate.
- Route 53 Resolver infrastructure.
- Centralized ingress/egress.
- AWS Network Firewall.
- Hybrid connectivity.
- AWS RAM networking shares.

### Shared Services

Hosts shared platform services consumed by workloads.

Examples may include:

- Internal tooling.
- Shared directory or identity integrations.
- Common build/artifact services.
- Shared operational systems.

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

- Host as little workload infrastructure as practical.
- Be used only for operations requiring the management account.
- Delegate supported services to member accounts.
- Avoid general-purpose CI/CD and application deployment.
- Use narrowly scoped automation roles.

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

- Governance-plane bootstrap.
- Account vending.
- Infrastructure deployment.
- Workload deployment.

This keeps the Control Tower management account small, makes account boundaries meaningful, and allows AFT to become the standard post-bootstrap account-provisioning mechanism.

## AWS Documentation References

The following AWS documentation is authoritative for the AWS service behavior described in this architecture:

### AWS Organizations and account boundaries

- [What is AWS Organizations?](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_introduction.html).
- [AWS Organizations terminology and concepts](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_getting-started_concepts.html).
- [Best practices for the management account](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_best-practices_mgmt-acct.html).
- [Service control policies](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_scps.html).
- [Delegated administrator for AWS services](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_integrate_services_delegate_admin.html).

### AWS Control Tower and Account Factory

- [What is AWS Control Tower?](https://docs.aws.amazon.com/controltower/latest/userguide/what-is-control-tower.html).
- [AWS Control Tower shared accounts](https://docs.aws.amazon.com/controltower/latest/userguide/how-control-tower-works.html).
- [Register an existing organizational unit with AWS Control Tower](https://docs.aws.amazon.com/controltower/latest/userguide/register-existing-ou.html).
- [AWS Control Tower baselines](https://docs.aws.amazon.com/controltower/latest/userguide/baselines.html).
- [Provision and manage accounts with Account Factory](https://docs.aws.amazon.com/controltower/latest/userguide/account-factory.html).
- [Account Factory for Terraform overview](https://docs.aws.amazon.com/controltower/latest/userguide/aft-overview.html).
- [AFT prerequisites](https://docs.aws.amazon.com/controltower/latest/userguide/aft-getting-started.html).

### Identity and cross-account access

- [What is IAM Identity Center?](https://docs.aws.amazon.com/singlesignon/latest/userguide/what-is.html).
- [IAM roles and temporary credentials](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles.html).
- [Cross-account resource access in IAM](https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies-cross-account-resource-access.html).
- [IAM best practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html).

### Central security and networking services

- [AWS CloudTrail concepts](https://docs.aws.amazon.com/awscloudtrail/latest/userguide/cloudtrail-concepts.html).
- [AWS Config concepts](https://docs.aws.amazon.com/config/latest/developerguide/config-concepts.html).
- [AWS Transit Gateway](https://docs.aws.amazon.com/vpc/latest/tgw/what-is-transit-gateway.html).
- [VPC IP Address Manager](https://docs.aws.amazon.com/vpc/latest/ipam/what-it-is-ipam.html).
- [Sharing AWS resources with AWS RAM](https://docs.aws.amazon.com/ram/latest/userguide/what-is.html).
