# IAM Identity Center Administrative Security

## Purpose

This document describes the Terraform-managed IAM Identity Center administrative personas under `terraform/identity_center/`, their ownership boundary, the protections implemented, and the residual privilege-escalation risks.

The root runs after the Control Tower landing zone and its IAM Identity Center integration are `ACTIVE` and `IN_SYNC`:

```text
terraform/bootstrap
  → terraform/identity_center
  → terraform/identity_center/workload_access
  → terraform/aft/org_unit
  → terraform/aft/account
  → terraform/identity_center/aft_access
  → terraform/aft/platform
```

## Control Tower Ownership Boundary

Control Tower creates and operates its standard IAM Identity Center groups, permission sets, assignments, roles, and shared-account access. This root does not declare, import, modify, or delete those resources.

It creates only project-specific resources with distinct names:

| Group | Permission set | Responsibility |
|---|---|---|
| `AWSIdentityStoreAdmins` | `IdentityStoreAdministration` | User, group, membership, and identity lifecycle |
| `AWSPermissionSetAdmins` | `PermissionSetAdministration` | Permission-set definitions and policies |
| `AWSAccessAssignmentAdmins` | `AccessAssignmentAdministration` | Account assignments using existing permission sets |

Terraform discovers the existing organization Identity Center instance and identity store. It does not create or manage the instance itself.

A separate state root, `terraform/identity_center/workload_access/`, creates the project-owned workload access catalog:

| Group | Permission set | Approved assignment scope |
|---|---|---|
| `WorkloadViewers` | `WorkloadViewOnly` | Dev, Test, and Prod workload accounts |
| `WorkloadSecurityAuditors` | `WorkloadSecurityAudit` | Dev, Test, and Prod workload accounts |
| `WorkloadDevelopers` | `WorkloadDeveloper` | Dev workload accounts only |
| `WorkloadTestOperators` | `WorkloadTestOperator` | Test workload accounts only |
| `WorkloadProductionOperators` | `WorkloadProductionOperator` | Prod workload accounts only |

The root creates two named test-user records from `TF_VAR_test_user1_*` and `TF_VAR_test_user2_*`. It intentionally creates no memberships or direct assignments for them; access-portal activation, credentials, MFA, and temporary console-test memberships are manual operations. Its assignment map defaults to empty until AFT-created account IDs are known, and lifecycle preconditions enforce the approved group, permission-set, and environment matrix. Workload assignments cannot target the Organizations management account.

`WorkloadDeveloper` attaches `PowerUserAccess` but uses an explicit deny boundary for IAM, Organizations, Identity Center, Control Tower, account administration, and sensitive governance mutations. Test and Production operator permission sets are read-only by default; operational write actions must be listed explicitly, and wildcard actions are rejected. These permission sets carry `AssignmentDelegation = Allowed`, so changes to their policies and assignments require the independent review controls described below.

A separate state root, `terraform/identity_center/aft_access/`, creates project-owned AFT human access after Account Factory completes:

| Group | Permission set | Target | User ownership |
|---|---|---|---|
| `AFTPlatformAdministrators` | `AFTPlatformAdministration` | AFT management account only | Existing Account Factory user is looked up, not managed |

The permission set attaches AWS `ReadOnlyAccess` for troubleshooting and grants limited writes to authorize CodeConnections and start, stop, or retry pipelines in the AFT account. Explicit denies prevent IAM mutation, Identity Store mutation, permission-set/assignment mutation, and Organizations mutation. A one-hour session is used by default.

AWS documents the following permission-only operations as necessary for the console's browser-based provider handshake: `GetIndividualAccessToken`, `GetInstallationUrl`, `ListInstallationTargets`, `StartOAuthHandshake`, and `UpdateConnectionInstallation`. They are IAM permissions rather than public API operations.

`GetConnection`, `ListConnections`, and the write action `UpdateConnectionInstallation` are scoped to connection ARNs in the AFT account. The remaining browser-only actions do not support a connection resource; they retain `Resource = "*"`, and the OAuth actions that support it are constrained to provider type `GitHub`. Pipeline write actions are scoped to CodePipeline resources owned by the AFT account. Legacy `codestar-connections` compatibility is retained only for the scopeable connection actions.

If any resource with one of these names already exists, Terraform must not be applied until the resource is either imported explicitly or the naming/ownership decision is changed. Terraform does not automatically adopt existing Identity Center resources.

## Administrative Users

The root creates three distinct named human identities and adds each only to its corresponding group:

```text
TF_VAR_sso_identity_store_admin_*
  → AWSIdentityStoreAdmins

TF_VAR_sso_permission_set_admin_*
  → AWSPermissionSetAdmins

TF_VAR_sso_access_assignment_admin_*
  → AWSAccessAssignmentAdmins
```

Terraform requires three distinct email values. This prevents accidental use of one Identity Center record for all responsibilities, but separate user records controlled by the same person are privileged personas rather than true human separation of duties.

User email and profile data are stored in Terraform state. A `sensitive` variable suppresses some CLI display but does not remove or encrypt data in state. Backend access must remain tightly restricted.

Terraform does not manage human passwords, MFA secrets, or access-portal activation. Complete credential activation and strong MFA through the supported Identity Center workflow.

## Implemented Permission Separation

### Identity Store administration

`IdentityStoreAdministration` grants Identity Store lifecycle operations. It does not grant IAM Identity Center permission-set or account-assignment APIs. Its allows use the current Identity Store, group, user, and membership ARN patterns rather than unrestricted `Resource = "*"`.

### Permission-set administration

`PermissionSetAdministration` grants permission-set definition and policy operations. It explicitly denies account-assignment creation and deletion. Its allows are scoped to the organization Identity Center instance and permission sets in that instance.

### Access-assignment administration

`AccessAssignmentAdministration` grants account-assignment operations and read access needed to discover identities, accounts, and permission sets. It explicitly denies permission-set definition and policy mutation. Assignment writes exclude the management account and require the permission set to carry `AssignmentDelegation = Allowed`.

All privileged permission sets default to a one-hour session.

## Protection of Privileged Groups

The implementation separates each administrative user into one group and manages the initial memberships declaratively. This reduces accidental privilege concentration and ensures Terraform detects changes to these three memberships.

The identity policy uses exact group ARNs in explicit denies to prevent membership, update, and deletion operations against:

```text
AWSIdentityStoreAdmins
AWSPermissionSetAdmins
AWSAccessAssignmentAdmins
AWSAccountFactory
AWSAuditAccountAdmins
AWSControlTowerAdmins
AWSLogArchiveAdmins
AWSLogArchiveViewers
AWSSecurityAuditPowerUsers
AWSSecurityAuditors
AWSServiceCatalogAdmins
```

The Control Tower groups are discovered through data sources; Terraform does not take ownership of them.

`AFTPlatformAdministrators` and the workload access groups are created later in separate state roots and are not currently included in the parent root's exact group-ARN deny. Membership changes to those groups still require procedural independent approval, CloudTrail monitoring, and periodic Terraform reconciliation. A future central protected-group registry or reviewed automation workflow should close this remaining gap.

## Protection of Administrative Permission Sets

The implementation separates permission-set mutation from account assignment and adds explicit denies across those two permission sets. This removes the simplest path in which one assignment administrator both creates a powerful permission set and self-assigns it.

Project-owned administrative permission sets carry:

```text
SecurityBoundary = Protected
```

`AWSPermissionSetAdmins` is explicitly denied policy, boundary, tag, update, and deletion operations when this resource tag is present. This protects its own permission set, the other two central administrative permission sets, and `AFTPlatformAdministration` without requiring cross-state ARN references.

The permission-set administrator can still create a powerful unprotected permission set. It cannot assign that permission set, but it can mark it `AssignmentDelegation = Allowed`; collusion with the assignment administrator remains a residual path. The strongest future control is to remove high-risk interactive writes and manage protected or delegated permission sets through a reviewed CI/CD workflow whose role cannot modify itself.

## Workload Access Risks

The delegated workload permission sets are intentionally assignable in member accounts and therefore are not tagged `SecurityBoundary = Protected`; the existing access-assignment administrator would otherwise deny their assignment. The permission-set administrator can modify these definitions, the identity administrator can modify workload group memberships, and the assignment administrator can assign approved delegated permission sets. Independent review, CloudTrail monitoring, and Terraform reconciliation remain required to detect policy, membership, or assignment escalation.

The manually operated test users are intentionally outside Terraform membership management. Temporary membership will therefore not be reconciled automatically. Keep both users out of groups by default, prohibit management-account and AFT assignments, document each temporary grant, remove it immediately after testing, and review their live access regularly.

`PowerUserAccess` is broad even with the explicit governance denies. Use it only in Dev accounts, keep the deny policy under review as AWS managed policies evolve, and replace it with application-specific permissions when workload requirements are known. Test and Production operational writes start empty and must remain explicit. The configured action lists cannot express resource scoping, so actions that require sensitive resource-level restrictions should instead be delivered through application-specific roles and policies.

## AFT Platform Administration Risks

`AFTPlatformAdministration` can authorize or change the installation associated with an AFT CodeConnections connection and can operate AFT pipelines. A compromised administrator could disrupt source retrieval, trigger approved pipeline definitions, or influence AFT operations through repositories to which that human also has write access.

Mitigations include:

- assign the group only in the AFT management account;
- keep the one-hour session and require strong MFA;
- protect all four AFT repositories with branch protection and independent review;
- restrict the GitHub App installation to the required repositories;
- alert on CodeConnections installation changes and AFT pipeline executions;
- do not grant IAM mutation, Identity Center administration, Organizations administration, or unrestricted `sts:AssumeRole`;
- periodically reconcile group membership and the account assignment with Terraform.

The Account Factory user is a data source because this project must not create a duplicate or take ownership of an identity created or referenced by Control Tower. If lookup by `UserName` does not find exactly one user, deployment stops rather than guessing.

## Remaining Escalation Paths

### Identity administrator escalation

The identity administrator cannot modify the explicitly protected central and Control Tower groups. It can still manage unprotected groups, including `AFTPlatformAdministrators`, and can create identities and groups. Collusion with an assignment administrator could grant a delegated member-account permission set to a newly controlled principal.

### Permission-set administrator escalation

The permission-set administrator cannot mutate permission sets tagged `SecurityBoundary = Protected`. It can still create a powerful unprotected permission set and mark it as assignment-delegated. It needs the assignment administrator, Terraform automation, or another privileged principal to make that permission effective in an account.

### Access-assignment administrator escalation

The assignment administrator cannot assign access in the Organizations management account and cannot assign protected permission sets. It can assign only permission sets tagged `AssignmentDelegation = Allowed` to member accounts. IAM Identity Center does not provide a complete principal restriction for this operation, so the administrator may self-assign an allowed delegated permission set. Delegated permission sets must therefore remain bounded and independently reviewed.

### Collusion or shared operator

Different identities do not provide true two-person control if one person controls all credentials. Collusion between administrators can combine identity creation, permission definition, and assignment.

### Management account and root

Compromise of a sufficiently privileged management-account principal or root user can bypass the intended administrative separation. SCPs do not constrain principals in the Organizations management account.

## Required Operational Controls

Until stronger automation is implemented:

1. assign the three personas to different accountable people where possible;
2. require strong MFA and one-hour privileged sessions;
3. prohibit shared credentials and unattended use;
4. require independent review for protected-group membership;
5. require independent review for administrative permission-set changes;
6. require additional approval for every management-account assignment;
7. alert on Identity Store membership, permission-set, and account-assignment changes;
8. periodically compare live membership and assignments with Terraform and approved records;
9. keep root and break-glass access separate;
10. never use these identities for AFT, CI/CD, or other automation.

## Recommended Future Mitigation

Move privileged identity changes to protected, reviewed automation:

```text
Change request
  → pull request
  → independent approval
  → policy checks and Terraform plan
  → OIDC-federated deployment role
  → Identity Center change
  → CloudTrail alert
```

The deployment role should:

- trust only the designated repository and protected environment;
- use short-lived OIDC credentials;
- reject self-assignment and unapproved principal/permission-set/account combinations;
- apply an approved assignment catalog;
- require stronger review for the management account;
- be unable to change its own trust policy or permissions;
- send audit events to a destination administrators cannot alter.

At greater scale, an external identity provider with privileged identity management can add just-in-time membership, approval, expiration, access reviews, and phishing-resistant MFA. If users and groups become SCIM-managed, Terraform ownership of `aws_identitystore_user` and `aws_identitystore_group` must be reconsidered.

## Deployment and Review

Initialize and review this root independently:

```bash
./tf.sh --phase identity-center --dry-run
```

Apply only after verifying:

- the landing zone is `ACTIVE` and `IN_SYNC`;
- none of the proposed users, groups, or permission sets already exists;
- each email belongs to the intended accountable human;
- the plan changes no Control Tower-created identity resource;
- policies contain no unexpected wildcard actions;
- account assignments target only the management account;
- the Terraform state backend meets sensitive-data requirements.

After apply, test each persona through the AWS access portal, verify expected allowed and denied operations, register MFA, and retain redacted evidence.

## AWS Documentation

- [IAM Identity Center users and groups](https://docs.aws.amazon.com/singlesignon/latest/userguide/users-groups-provisioning.html)
- [IAM Identity Center permission sets](https://docs.aws.amazon.com/singlesignon/latest/userguide/permissionsetsconcept.html)
- [Assign access to AWS accounts](https://docs.aws.amazon.com/singlesignon/latest/userguide/useraccess.html)
- [IAM Identity Center security best practices](https://docs.aws.amazon.com/singlesignon/latest/userguide/security-best-practices.html)
- [IAM Identity Center actions and resources](https://docs.aws.amazon.com/service-authorization/latest/reference/list_awsiamidentitycenter.html)
- [Identity Store actions and resources](https://docs.aws.amazon.com/service-authorization/latest/reference/list_awsidentitystore.html)
- [IAM Identity Center CloudTrail logging](https://docs.aws.amazon.com/singlesignon/latest/userguide/monitoring-cloudtrail.html)
- [Organizations management-account best practices](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_best-practices_mgmt-acct.html)
