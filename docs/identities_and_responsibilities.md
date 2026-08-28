# Identities and Responsibilities

## Purpose

This document defines the intended identity model for landing-zone bootstrap, AFT administration, AFT internal operation, and external Terraform automation.

The core principle is to separate temporary bootstrap access, human administration, AWS service automation, and CI/CD workload identities. An identity created for one purpose must not be repurposed for another merely because it has sufficient privileges.

## Identity Overview

```text
Temporary management-account bootstrap identity
  ├── Establish landing zone
  ├── Create and govern AFT OU
  ├── Provision AFT management account
  └── Deploy AFT platform
          ↓
Retire temporary bootstrap identity
          ↓
Human administration through IAM Identity Center
          +
AFT operation through AFT-managed IAM service roles
          +
Other CI/CD through federation and scoped target-account roles
```

## Temporary Bootstrap Identity

The current bootstrap identity is `ct-bootstrap`, a temporary IAM user in the AWS Organizations management account.

It is used for the initial control-plane sequence:

```text
terraform/bootstrap
  ↓
terraform/aft/org_unit
  ↓
terraform/aft/account
  ↓
terraform/aft/platform
```

Its responsibilities include:

- establishing and maintaining the initial Organizations and Control Tower configuration;
- creating and governing the dedicated AFT OU;
- submitting the AFT management account request through Control Tower Account Factory;
- launching the AFT platform module from the Control Tower management account;
- verifying successful convergence before handoff to steady-state operations.

Although the AFT platform module is launched with management-account credentials, it installs operational resources into the AFT management account and Control Tower shared accounts as required.

### Lifecycle

`ct-bootstrap` is temporary. After the landing zone and AFT platform have been established and verified:

1. stop using the identity for routine administration;
2. delete any access keys;
3. disable and remove the IAM user when it is no longer required;
4. retain audit evidence necessary to identify the bootstrap actions it performed.

A federated session or an assumed bootstrap role is preferable to a long-lived IAM user. If `ct-bootstrap` is retained temporarily for recovery, its permissions and credentials must be reviewed regularly and it must not become a general-purpose management-account automation identity.

## IAM Identity Center Resources Established by Control Tower

Control Tower integrates the landing zone with IAM Identity Center and establishes standard groups and access patterns for Control Tower administration, Account Factory, security auditing, and shared-account administration.

The exact resources and assignments can vary with landing-zone version, identity-source configuration, and subsequent administrator changes. The IAM Identity Center console and APIs are authoritative for the users, groups, permission sets, and account assignments currently present.

### How effective access is constructed

An Identity Center group does not grant AWS permissions by itself. Effective access requires an account assignment that combines three elements:

```text
User
  ↓ membership
Group
  +
Permission set
  +
Target AWS account
  ↓ provisioning
AWSReservedSSO_* IAM role
  ↓
Temporary role session
```

A permission set defines session permissions and settings. An account assignment determines where a user or group can use that permission set. IAM Identity Center provisions a corresponding `AWSReservedSSO_*` role into the target account.

Do not infer effective permissions from a group name or description alone. Verify:

1. group membership;
2. target-account assignments;
3. assigned permission sets;
4. managed and inline policies in each permission set;
5. permission boundaries and session duration;
6. resulting `AWSReservedSSO_*` roles;
7. cross-account trust and resource policies that further affect access.

### Users

Control Tower does not require one user per group or one user per account. The user information supplied during landing-zone or Account Factory workflows identifies a named human administrator or account owner in the centralized Identity Center directory. Depending on the existing identity source and workflow, AWS may create or reference that user and assign access.

Any users visible in Identity Center must be treated as individual human identities unless explicitly documented otherwise. Control Tower groups must not be populated with shared role-named users such as `security-auditor` or `log-archive-admin`.

### Control Tower groups

The current Identity Center instance contains these Control Tower-established groups:

| Group | Intended responsibility | Access sensitivity |
|---|---|---:|
| `AWSControlTowerAdmins` | Administer the Control Tower landing zone, governed OUs, controls, Account Factory, and related provisioned-account operations | Very high |
| `AWSServiceCatalogAdmins` | Administer the Control Tower Account Factory product, portfolio access, and relevant Service Catalog configuration | High |
| `AWSAccountFactory` | Use or view the Account Factory product as an end user, subject to portfolio access and constraints | Limited account-vending access |
| `AWSAuditAccountAdmins` | Administer the Audit/Security Tooling shared account and approved security operations | High |
| `AWSSecurityAuditPowerUsers` | Perform cross-account security investigations requiring more capability than read-only audit | Medium–high |
| `AWSSecurityAuditors` | Inspect assigned accounts and security posture without making routine changes | Read-only but sensitive |
| `AWSLogArchiveAdmins` | Administer approved resources in the Log Archive evidence-custody account | High |
| `AWSLogArchiveViewers` | Read authorized centralized evidence without administering Log Archive resources | Read-only but sensitive |

#### `AWSControlTowerAdmins`

This group represents landing-zone administrators. Membership can provide access to the highest-trust management and governance operations and must be tightly restricted. It must not become the default group for every AWS operator.

#### `AWSServiceCatalogAdmins` and `AWSAccountFactory`

`AWSServiceCatalogAdmins` is intended for human administration of the Account Factory Service Catalog product. `AWSAccountFactory` represents end-user access to that product. Because this project uses AFT pull requests as the standard post-bootstrap account-vending path, direct human Account Factory access should be limited to documented administrative or recovery needs.

Neither group is an AFT automation identity. AFT pipelines use AWS service and execution roles.

#### `AWSAuditAccountAdmins`, `AWSSecurityAuditPowerUsers`, and `AWSSecurityAuditors`

These groups separate Audit/Security Tooling account administration, privileged security investigation, and read-only auditing. `PowerUsers` must not be interpreted as unrestricted administration without inspecting its permission set. Even read-only security access is sensitive because it can expose IAM policies, findings, logs, network topology, metadata, and resource configuration.

#### `AWSLogArchiveAdmins` and `AWSLogArchiveViewers`

These groups separate administration of the Log Archive account from authorized evidence access. Viewers should not be able to delete logs, change retention, alter encryption, or interfere with delivery. Administrator access is highly sensitive and does not authorize unsupported modification of Control Tower-managed resources.

### Meaning of `Manual`

The `Manual` label shown for these groups describes how the group is managed in the Identity Center identity store. It generally indicates direct management in IAM Identity Center rather than synchronization from an external identity provider through SCIM.

It does not mean the group is inactive, that users manually assume it on every login, or that its permissions are provisioned manually into every account.

### Permission sets and account assignments

Control Tower provisions or uses permission sets and account assignments corresponding to its standard responsibilities. Their effective policy contents—not their display names—determine access.

A typical responsibility mapping is:

| Group | Typical target | Intended permission scope |
|---|---|---|
| `AWSControlTowerAdmins` | Organizations management account and required governed-account administration paths | Control Tower administration |
| `AWSServiceCatalogAdmins` | Management account | Account Factory/Service Catalog administration |
| `AWSAccountFactory` | Management account | Restricted Account Factory product use |
| `AWSAuditAccountAdmins` | Audit/Security Tooling account | Shared-account administration |
| `AWSSecurityAuditPowerUsers` | Approved organization accounts | Security investigation/operations |
| `AWSSecurityAuditors` | Approved organization accounts | Security audit/read-only |
| `AWSLogArchiveAdmins` | Log Archive account | Restricted logging administration |
| `AWSLogArchiveViewers` | Log Archive account | Evidence read access |

This table describes intent, not a guarantee of the current configuration. Administrators must review live account assignments and permission-set policies after initial setup and after every access-model change.

## Human Identity and Group Assignment Practices

### One identity per person

Create one named Identity Center identity per human, not one identity per group or AWS account:

```text
alice@example.com
  ├── AWSSecurityAuditors
  └── AWSLogArchiveViewers
```

Do not create duplicate account-specific identities such as:

```text
alice-management
alice-aft
alice-audit
alice-log-archive
```

Do not create shared group identities such as:

```text
AWSControlTowerAdmins-user
security-auditor
log-archive-admin
```

Named identities preserve individual attribution in Identity Center and CloudTrail, simplify MFA and offboarding, and prevent shared-credential ambiguity.

### Groups represent stable job functions

Grant human access primarily through groups representing responsibilities, such as:

```text
SecurityAuditors
AFTPlatformAdministrators
NetworkAdministrators
ProductionOperators
```

A person may belong to multiple groups when justified. Avoid permanent membership in every administrative group for convenience. Group membership must follow least privilege, require an owner, and be reviewed periodically.

### Permission sets represent privilege levels

Use permission sets to separate capabilities such as:

```text
ReadOnly
SecurityAudit
AFTAdministrator
ControlTowerAdministrator
ProductionOperator
```

Administrators should use read-only sessions for routine inspection and select an elevated permission set only for a task that requires it. Privileged permission sets should have shorter session duration, stronger authentication requirements, and monitoring appropriate to their risk.

### Account assignments define scope

An assignment must grant a group and permission set only to the accounts where that responsibility applies. For example:

| Group | Permission set | Target accounts |
|---|---|---|
| `AWSControlTowerAdmins` | Control Tower administrator | Management account |
| `AWSSecurityAuditors` | Security audit | Approved organization accounts |
| `AWSLogArchiveViewers` | Log Archive read-only | Log Archive account |
| `AFTPlatformAdministrators` | AFT administrator | AFT management account |
| Development team | Developer | Development accounts only |
| Production operators | Restricted operator | Production accounts only |

Do not grant broad management-account administration merely to enable access to member accounts. Users enter through the AWS access portal and choose an assigned account and permission set directly.

### Group assignments over direct assignments

Prefer assigning groups to AWS accounts over assigning individual users. Group-based access gives a stable policy boundary and makes onboarding, role changes, reviews, and offboarding easier. Direct user assignments should be exceptional and documented.

### Privileged administrative personas

A separate privileged identity, such as `alice-admin@example.com`, may be appropriate where organizational policy requires stronger separation between routine and privileged activity. This is a deliberate privileged-access design, not an identity per account or group.

For a small environment, one named identity with separate read-only and elevated permission sets may be sufficient. Elevated access should still be used only when required and management-account sessions should be monitored.

### MFA, lifecycle, and access reviews

Every human identity must:

- belong to one accountable person;
- use MFA appropriate to the identity source;
- avoid shared credentials;
- receive access through reviewed group membership;
- have unnecessary assignments removed promptly;
- be disabled promptly during offboarding;
- be included in periodic group, permission-set, and account-assignment reviews.

### Break-glass access

Emergency access must remain separate from normal SSO administration. Protect account root users with MFA, avoid root for routine work, document credential custody and recovery, and alert on root or emergency-role use.

`ct-bootstrap` is not the permanent break-glass identity. It must be retired after Identity Center access, AFT operation, and recovery procedures are verified.

### Automation is not an SSO user

Do not create Identity Center users for AFT pipelines, Terraform CI/CD, or other unattended automation. Use AFT service roles, AWS service roles, OIDC-federated CI/CD roles, and narrowly scoped cross-account roles instead.

## Project-Owned Identity Center Administrative Personas

After Control Tower and its IAM Identity Center integration are healthy, `terraform/identity_center/` creates three project-owned central administrative groups, their three named human users and permission sets, and a fourth distinct named user for lab-baseline administration. The lab user's group, permission set, membership, and lab-account assignments are owned by `terraform/identity_center/workload_access`.

These resources are distinct from the standard Control Tower-created groups and permission sets. Terraform discovers the existing organization Identity Center instance but does not manage the instance or adopt Control Tower-owned identity resources.

The design separates three capabilities:

```text
Identity lifecycle
  ≠
Permission definition
  ≠
Access assignment
```

### Identity Store administrator

Group:

```text
AWSIdentityStoreAdmins
```

Permission set:

```text
IdentityStoreAdministration
```

User variables:

```text
TF_VAR_sso_identity_store_admin_email
TF_VAR_sso_identity_store_admin_first_name
TF_VAR_sso_identity_store_admin_last_name
```

Responsibilities include:

- creating, reading, updating, and deleting Identity Center users;
- creating, reading, updating, and deleting groups;
- managing group memberships;
- performing identity onboarding, role-change, and offboarding tasks.

This persona does not receive permission-set or account-assignment APIs through its project permission set.

This identity remains highly privileged. Broad Identity Store membership APIs may allow it to add itself or another identity it controls to an existing privileged group. Protected-group membership therefore requires independent review and monitoring until privileged membership changes are moved behind approved automation.

### Permission-set administrator

Group:

```text
AWSPermissionSetAdmins
```

Permission set:

```text
PermissionSetAdministration
```

User variables:

```text
TF_VAR_sso_permission_set_admin_email
TF_VAR_sso_permission_set_admin_first_name
TF_VAR_sso_permission_set_admin_last_name
```

Responsibilities include:

- creating and updating permission-set definitions;
- managing managed-policy attachments and customer-managed-policy references;
- managing inline policies and permission boundaries;
- managing permission-set metadata and session settings.

Its permission set explicitly denies account-assignment creation and deletion. Permission definition is therefore separated from assigning that permission to a principal in an AWS account.

This persona can still create or strengthen powerful permission sets and may be able to modify a permission set already assigned to itself or another accessible group. Administrative permission-set changes require independent review, plan inspection, and monitoring.

### Access-assignment administrator

Group:

```text
AWSAccessAssignmentAdmins
```

Permission set:

```text
AccessAssignmentAdministration
```

User variables:

```text
TF_VAR_sso_access_assignment_admin_email
TF_VAR_sso_access_assignment_admin_first_name
TF_VAR_sso_access_assignment_admin_last_name
```

Responsibilities include:

- discovering approved users, groups, permission sets, and AWS accounts;
- creating and deleting account assignments;
- monitoring assignment creation and deletion status;
- assigning existing, approved permission sets to authorized principals and accounts.

Its permission set explicitly denies permission-set creation and policy mutation. Access assignment is therefore separated from permission definition.

This persona may still be able to assign an existing powerful permission set to itself or to a group it belongs to. Assignments involving privileged permission sets or the Organizations management account require independent approval and monitoring.

### Lab baseline administrator

User variables:

```text
TF_VAR_sso_lab_admin_email
TF_VAR_sso_lab_admin_first_name
TF_VAR_sso_lab_admin_last_name
```

The parent root creates this distinct named human without assigning central
administrative permissions. The workload-access root looks up the existing
user and manages:

```text
WorkloadLabBaselineAdministrators
  + WorkloadLabBaselineAdmin
  + Dev Lab and Test Lab accounts only
```

The protected one-hour permission set can create, inspect, tag, and update
versions only for `/week2/WorkloadLabRoleBoundary`. It cannot create IAM roles,
users, access keys, identity providers, or administer Organizations, Identity
Center, or Control Tower. The user authenticates directly into each lab account
through IAM Identity Center; the baseline providers do not call
`sts:AssumeRole`.

### Assignment model

Each project-owned central group receives its corresponding permission set only in the Organizations management account:

```text
AWSIdentityStoreAdmins
  + IdentityStoreAdministration
  + Management account

AWSPermissionSetAdmins
  + PermissionSetAdministration
  + Management account

AWSAccessAssignmentAdmins
  + AccessAssignmentAdministration
  + Management account
```

The three central users must use distinct email addresses. The lab baseline user must differ from all three central users and both exercise test users. Each central user is added only to its corresponding central group; the lab user's membership is owned by the workload-access root.

### Separation-of-duties interpretation

Three distinct identities improve credential isolation, CloudTrail attribution, and resistance to compromise of a single persona. They provide true human separation of duties only when controlled by different accountable people with independent credentials and MFA.

If one person controls all three identities, they are separate privileged personas rather than a two-person or three-person control. The operator can still combine the capabilities across separate sessions.

The design removes the simplest path in which one assignment administrator both creates an unrestricted permission set and self-assigns it. It does not eliminate all escalation paths:

```text
Identity administrator
  → join an already privileged group

Permission-set administrator
  → strengthen an already assigned permission set

Assignment administrator
  → self-assign an existing privileged permission set

Multiple administrators
  → collude or approve one another's escalation
```

### Operational requirements

For all three administrative personas:

- assign different accountable human owners where possible;
- require strong MFA;
- retain the default one-hour privileged session duration unless a shorter supported duration is adopted;
- prohibit shared credentials and unattended use;
- require independent review for protected-group membership;
- require independent review for administrative permission-set changes;
- require additional approval for management-account assignments;
- alert on user, group, membership, permission-set, and assignment changes;
- periodically reconcile live resources with Terraform and approved access records;
- never use these identities for AFT, CI/CD, or other automation.

The intended future state is a reviewed Terraform workflow using OIDC-federated automation. Humans propose and independently approve changes; a protected deployment role applies them and cannot change its own trust or permissions.

See [`identity_center_security.md`](identity_center_security.md) for the detailed policy design, limitations, residual risks, and future mitigations.

## Workload Access Catalog

`terraform/identity_center/workload_access/` creates reusable project-owned groups and permission sets for workload accounts and two named test-user records from the `TF_VAR_test_user1_*` and `TF_VAR_test_user2_*` inputs. It does not modify Control Tower groups.

| Group | Permission set | Account scope |
|---|---|---|
| `WorkloadViewers` | `WorkloadViewOnly` | Approved Dev, Test, and Prod accounts |
| `WorkloadSecurityAuditors` | `WorkloadSecurityAudit` | Approved Dev, Test, and Prod accounts |
| `WorkloadDevelopers` | `WorkloadDeveloper` | Approved Dev accounts only |
| `WorkloadTestOperators` | `WorkloadTestOperator` | Approved Test accounts only |
| `WorkloadProductionOperators` | `WorkloadProductionOperator` | Approved Prod accounts only |
| `WorkloadLabAdministrators` | `WorkloadLabAdministrator` | Explicitly allowlisted Dev Lab and Test Lab accounts only |

`WorkloadLabAdministrator` permits bounded Week 2 IAM, S3, and STS lab work.
Every role it creates must use the pre-provisioned `WorkloadLabRoleBoundary`;
the persona cannot create, alter, replace, or remove that ceiling. Trusted
baseline automation owns the boundary policy in each lab account.

The test users intentionally have no Terraform-managed memberships or direct assignments. They are manually activated and operated for console testing; temporary access must be documented, must exclude the management and AFT accounts, and must be removed immediately after testing.

The catalog can be created before workload accounts exist because its assignment map defaults to empty. After AFT creates and enrolls an account, a reviewed change adds its account ID and an allowed group, permission set, and environment combination to the central assignment map. AFT in-account customizations do not own these Identity Center resources.

The Test and Production operator permission sets are read-only by default. Add only explicit reviewed actions after workload requirements are known. `WorkloadDeveloper` is based on `PowerUserAccess` with explicit denies for central identity, organization, account, Control Tower, and sensitive governance administration; it must never be assigned to Test or Prod.

Use one named identity per human and reviewed group membership. For multiple application teams, introduce team-specific groups rather than assigning one organization-wide developer group to every Dev account.

## IAM Identity Center User for the AFT Account

The `SSOUserEmail`, `SSOUserFirstName`, and `SSOUserLastName` parameters supplied to Control Tower Account Factory identify a human account owner or administrator.

The user is not an IAM user created locally inside the AFT account. IAM Identity Center manages the identity centrally and assigns a permission set that produces temporary role sessions in the AFT account:

```text
IAM Identity Center user
  ↓
Account assignment and permission set
  ↓
Temporary role session in the AFT management account
```

### Appropriate responsibilities

The Identity Center user may be used for:

- inspecting the AFT deployment;
- reviewing pipeline and operational status;
- troubleshooting failed AFT workflows;
- reviewing logs and configuration;
- performing explicitly authorized administrative work;
- emergency intervention when automated operations cannot recover safely.

### Inappropriate responsibilities

The Identity Center user must not be used for:

- unattended Terraform runs;
- CI/CD pipeline credentials;
- storing SSO session credentials in a pipeline or secret store;
- normal AFT internal processing;
- general organization-wide automation;
- a shared automation or service identity.

Where possible, Account Factory should reference an appropriate named human administrator rather than a shared user named for automation.

### AFT platform administration assignment

After Account Factory completes, `terraform/identity_center/aft_access/` looks up this existing user by `TF_VAR_sso_aft_user_email`; it does not create or own the user. The root creates and owns:

```text
AFTPlatformAdministrators
  + AFTPlatformAdministration
  + AFT management account
```

The user is added to `AFTPlatformAdministrators`. The permission set provides read access for AFT troubleshooting and limited writes to authorize the AFT CodeConnections installation and start, stop, or retry AFT-account pipelines. It explicitly denies IAM mutation, Identity Store mutation, permission-set and account-assignment mutation, and Organizations mutation.

This is a privileged human operations role. It uses a one-hour session by default, requires MFA, and must not be used by AFT pipelines. Authorization of a pending GitHub connection is an interactive human action; subsequent pipeline execution uses AFT service roles rather than the human session.

## AFT Internal Automation

AFT performs steady-state account vending and customization through AWS service roles and cross-account IAM roles created or configured by the AFT platform.

Conceptually:

```text
Git account request
  ↓
AFT pipeline and service roles
  ↓
Control Tower Account Factory
  ↓
AFT execution roles in managed accounts
  ↓
Account provisioning and customization
```

Normal AFT operation does not require credentials from the human IAM Identity Center user or from `ct-bootstrap`.

AFT roles should remain scoped to their documented responsibilities. AFT is responsible for account provisioning and account customization; it is not the general application-infrastructure deployment system.

## External Terraform and CI/CD Automation

Terraform automation outside AFT should use workload identity federation and narrowly scoped IAM roles.

A preferred pattern is:

```text
CI/CD workload identity
  ↓ OIDC or AWS service identity
Automation role
  ↓ sts:AssumeRole
Narrowly scoped target-account role
  ↓
Terraform operation
```

Suitable source identities include:

- GitHub Actions using OIDC;
- GitLab CI using OIDC;
- AWS CodeBuild using its service role;
- another CI platform using OIDC or SAML federation.

The source automation identity should only be able to assume explicitly authorized target roles. The target role defines the permissions available in its account.

Production and non-production privileges should be independently assignable. Network, security, workload, and platform administration should use separate target roles where their responsibilities differ.

### Prohibited patterns

Do not use:

- long-lived IAM user access keys for CI/CD;
- exported IAM Identity Center browser-session credentials in pipelines;
- the human AFT account owner as a service identity;
- `ct-bootstrap` for steady-state automation;
- a single unrestricted organization-wide automation role;
- the Organizations management account as a general CI/CD host.

## Management Account Boundary

The Organizations management account is a high-trust administrative boundary. SCPs do not restrict principals in that account.

Only operations that require management-account authority should run there. Routine infrastructure deployment and application automation should run from an appropriate member account and assume narrowly scoped roles in target accounts.

Management-account roles and temporary bootstrap identities require stronger review, logging, and lifecycle controls than ordinary workload identities.

## Responsibility Matrix

| Identity | Type | Primary responsibilities | Must not be used for |
|---|---|---|---|
| `ct-bootstrap` | Temporary management-account bootstrap identity | Landing zone, AFT OU, AFT account request, initial AFT platform deployment | Routine administration, general CI/CD, long-term automation |
| Named human user | Individual IAM Identity Center identity | Access assigned accounts through job-function groups and permission sets | Shared access, service automation, duplicate account-specific identities |
| Control Tower Identity Center groups | Human job-function groups | Control Tower, audit, logging, and Account Factory access according to live assignments | Automation identities, access inferred only from group names |
| Identity Store administrator | Named human Identity Center persona | User, group, membership, and identity lifecycle | Permission-set definition, account assignment, automation |
| Permission-set administrator | Named human Identity Center persona | Permission-set definitions and policies | Account assignments, identity lifecycle, automation |
| Access-assignment administrator | Named human Identity Center persona | Assign approved existing permission sets to authorized principals and accounts | Permission-set mutation, identity lifecycle, automation |
| AFT account owner | Human IAM Identity Center identity | Inspection, troubleshooting, authorized administration, emergency intervention | Unattended Terraform, pipeline credentials, AFT service execution |
| AFT service and execution roles | AWS service and cross-account roles | Account provisioning, AFT workflows, account customization | Human login, unrelated application deployment |
| External CI/CD identity | Federated workload identity | Assume explicitly authorized automation roles | Human administration, unrestricted organization-wide access |
| Target-account automation role | Narrowly scoped IAM role | Perform approved Terraform or deployment actions in one responsibility boundary | Organization-wide unrestricted administration |

## Operational Handoff

Bootstrap is complete only after:

1. the landing zone is healthy and in sync;
2. the AFT OU is governed by Control Tower;
3. the AFT management account is enrolled successfully;
4. the AFT platform is deployed and operational;
5. human administrative access through IAM Identity Center is verified;
6. project-owned identity, permission-set, and access-assignment personas are activated with MFA and tested for expected allows and denies;
7. privileged group, permission-set, and management-account assignment review procedures are operational;
8. AFT workflows operate without bootstrap-user or human-user credentials;
9. the temporary bootstrap identity is retired or placed under a documented short-term recovery process.

This handoff establishes the steady-state identity model: humans use IAM Identity Center, AFT uses its service roles, and external automation uses federated workload identities with narrowly scoped target roles.

## AWS Documentation References

The following AWS documentation supports the identity and responsibility model in this document.

### IAM Identity Center and human access

- [What is IAM Identity Center?](https://docs.aws.amazon.com/singlesignon/latest/userguide/what-is.html)
- [IAM Identity Center integration with AWS Organizations](https://docs.aws.amazon.com/singlesignon/latest/userguide/organization-instances-identity-center.html)
- [Create and manage permission sets](https://docs.aws.amazon.com/singlesignon/latest/userguide/permissionsetsconcept.html)
- [Assign user or group access to AWS accounts](https://docs.aws.amazon.com/singlesignon/latest/userguide/useraccess.html)
- [AWS access portal and temporary credentials](https://docs.aws.amazon.com/singlesignon/latest/userguide/using-the-portal.html)
- [Provision users and groups](https://docs.aws.amazon.com/singlesignon/latest/userguide/users-groups-provisioning.html)
- [Multi-factor authentication in IAM Identity Center](https://docs.aws.amazon.com/singlesignon/latest/userguide/mfa.html)
- [IAM Identity Center security best practices](https://docs.aws.amazon.com/singlesignon/latest/userguide/security-best-practices.html)
- [IAM Identity Center CloudTrail logging](https://docs.aws.amazon.com/singlesignon/latest/userguide/monitoring-cloudtrail.html)

### IAM roles and temporary credentials

- [IAM identities](https://docs.aws.amazon.com/IAM/latest/UserGuide/id.html)
- [IAM roles](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles.html)
- [Temporary security credentials](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_credentials_temp.html)
- [IAM best practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html)
- [Cross-account resource access in IAM](https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies-cross-account-resource-access.html)
- [`AssumeRole` API](https://docs.aws.amazon.com/STS/latest/APIReference/API_AssumeRole.html)

### Workload identity federation and CI/CD

- [IAM roles for web identity federation](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_oidc.html)
- [Create an OpenID Connect identity provider in IAM](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_create_oidc.html)
- [Configuring OpenID Connect in AWS for GitHub Actions](https://docs.github.com/en/actions/security-for-github-actions/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services)
- [CodeBuild service role](https://docs.aws.amazon.com/codebuild/latest/userguide/setting-up-service-role.html)

### Control Tower, Account Factory, and AFT roles

- [Control Tower users, groups, and roles](https://docs.aws.amazon.com/controltower/latest/userguide/users-groups-roles.html)
- [Provision and manage accounts with Control Tower Account Factory](https://docs.aws.amazon.com/controltower/latest/userguide/account-factory.html)
- [Account Factory for Terraform overview](https://docs.aws.amazon.com/controltower/latest/userguide/aft-overview.html)
- [AFT prerequisites](https://docs.aws.amazon.com/controltower/latest/userguide/aft-getting-started.html)
- [AFT account provisioning](https://docs.aws.amazon.com/controltower/latest/userguide/aft-provision-account.html)
- [AFT account customization options](https://docs.aws.amazon.com/controltower/latest/userguide/aft-account-customization-options.html)

### Management-account security boundary

- [Best practices for the AWS Organizations management account](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_best-practices_mgmt-acct.html)
- [SCP effects on permissions](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_scps.html)
- [Delegated administrator for AWS services](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_integrate_services_delegate_admin.html)
