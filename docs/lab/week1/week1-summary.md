# AWS Security Foundations Exercises — Week 1

**Context:** AWS Certified Security — Specialty portfolio, Week 1
**Current stage:** Control Tower, IAM Identity Center, the AFT OU and management account, and the AFT platform are deployed
**Time remaining:** Complete by the end of the current week
**Recommended duration:** 2–3 focused days
**Objective:** Validate the deployed governance and identity foundations, document their trust boundaries, and prepare AFT to provision a disposable account for later control testing.

> Do not perform disruptive tests in the Organizations management, Log Archive, Security Tooling/Audit, or AFT management accounts. Do not intentionally drift Control Tower-managed resources. Preventive, detective, proactive, and destructive recovery tests require a disposable AFT-provisioned account and test OU.

## Current Environment

The exercises assume this deployed state:

```text
AWS Organizations management account
├── AWS Control Tower landing zone 4.0
├── IAM Identity Center
├── Security OU
│   ├── Security Tooling / Audit account
│   └── Log Archive account
└── AFT OU (Control Tower governed)
    └── AFT management account (Control Tower enrolled)
```

AFT uses four GitHub repositories:

```text
example-organization/aws-security-aft-account-request
example-organization/aws-security-aft-global-customizations
example-organization/aws-security-aft-account-customizations
example-organization/aws-security-aft-account-provisioning-customizations
```

The AFT VPC is intentionally disabled with `TF_VAR_aft_enable_vpc=false`. See [`../../aft-setup.md`](../../aft-setup.md) for the design and cost tradeoffs.

Automatic account enrollment is also intentionally disabled. Accounts created through AFT still use the Control Tower Account Factory workflow; an account merely moved into a governed OU must not be assumed to be enrolled.

## Documentation Template

For every exercise, record:

```text
HYPOTHESIS
What should be true?

THREAT / FAILURE MODE
What security problem is being considered?

CONTROL
Which AWS or organizational mechanism addresses it?

PROCEDURE
What read-only inspection or safe test was performed?

EXPECTED RESULT
What should happen?

ACTUAL RESULT AND EVIDENCE
CLI output, CloudTrail event, screenshot, Terraform plan, or resource ARN.
Redact account IDs, email addresses, credentials, and sensitive identifiers.

SECURITY CONCLUSION
What guarantee was demonstrated?

LIMITATIONS / RESIDUAL RISK
What was not demonstrated, and where can the control fail?
```

Suggested evidence structure:

```text
experiments/week1/
├── 01-control-plane-inventory/
├── 02-identity-and-bootstrap-handoff/
├── 03-terraform-ownership-and-state/
├── 04-aft-readiness/
├── 05-enrollment-and-baselines/
├── 06-scp-incident-retrospective/
├── 07-log-archive-boundary/
├── 08-security-service-gap-analysis/
└── 09-disposable-account/       # Conditional
```

Do not commit unredacted CLI output, Terraform state, plans containing sensitive values, credentials, access tokens, or account email addresses.

# Exercise 1 — Build a Control-Plane Inventory

## Objective

Understand which resources exist, which service created them, and which Terraform root or AWS service owns subsequent changes.

## Tasks

Inventory the following without modifying them:

- AWS Organization and Organizations root.
- OUs and account placement.
- Control Tower landing zone version, status, and drift status.
- Enabled Control Tower baselines and their targets.
- Control Tower controls currently enabled on each OU.
- IAM Identity Center instance, permission sets, and account assignments.
- Control Tower shared accounts.
- AFT OU and AFT account enrollment.
- Control Tower and AFT IAM roles.
- CloudFormation StackSets and stack instances.
- CloudTrail, AWS Config, and centralized logging resources.
- AFT pipelines, Step Functions workflows, Lambda functions, DynamoDB tables, and CodeConnections connection.

Create an ownership table:

| Resource | Account | Created by | Ongoing owner | Safe change path | Security purpose |
|---|---|---|---|---|---|
| Organization | Management | Bootstrap | `terraform/bootstrap` and AWS service integrations | Bootstrap plan plus documented service workflow | Governance boundary |
| Landing zone | Management | Bootstrap | Control Tower and `terraform/bootstrap` | Supported Control Tower/Terraform workflow | Multi-account governance |
| AFT OU baseline | Management | AFT OU root | `terraform/aft/org_unit` and Control Tower | AFT OU Terraform root | Governed AFT boundary |
| AFT account | AFT OU | Account Factory | Control Tower/AFT account workflow | Account Factory | AFT operations |
| AFT platform | Multiple | AFT platform root | `terraform/aft/platform` | AFT platform Terraform root | Account vending |

## Evidence

Capture redacted CLI inventory, a current account/OU diagram, and a resource-ownership matrix. Explicitly distinguish:

- Organizations membership.
- OU baseline enablement.
- Control Tower account enrollment.
- Control Tower controls.
- AFT account management.

AWS references:

- [What is AWS Control Tower?](https://docs.aws.amazon.com/controltower/latest/userguide/what-is-control-tower.html).
- [AWS Control Tower baselines](https://docs.aws.amazon.com/controltower/latest/userguide/baselines.html).
- [AWS Organizations concepts](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_getting-started_concepts.html).
- [AFT architecture](https://docs.aws.amazon.com/controltower/latest/userguide/aft-architecture.html).

# Exercise 2 — Validate Identity Center and Plan the Bootstrap Handoff

## Objective

Verify that human administration and machine automation use distinct identity paths.

## Tasks

1. Inventory the IAM Identity Center user or group assignments for the management, Audit, Log Archive, and AFT accounts.
2. Record the permission sets assigned to each account and their intended responsibilities.
3. Sign in through the AWS access portal and verify a temporary role session in the AFT account.
4. Compare the SSO role session with the temporary `ct-bootstrap` IAM user session.
5. Confirm that the Identity Center account owner is not used by AFT pipelines.
6. Identify the AFT service roles used for normal automation.
7. Produce a retirement checklist for `ct-bootstrap`: final dependencies, access-key deletion, user disablement/removal, and recovery ownership.
8. Verify root-user protections and document the break-glass process without exercising root access.

Do not remove `ct-bootstrap` until AFT deployment, GitHub connection authorization, and steady-state administrative access are verified.

## Expected Result

```text
Human administrator
  → IAM Identity Center
  → permission set
  → temporary role session

AFT automation
  → AFT service roles
  → scoped cross-account roles

Temporary bootstrap
  → ct-bootstrap
  → retired after operational handoff
```

Use [`../../identities_and_responsibilities.md`](../../identities_and_responsibilities.md) as the authoritative project identity model.

AWS references:

- [IAM Identity Center permission sets](https://docs.aws.amazon.com/singlesignon/latest/userguide/permissionsetsconcept.html).
- [Assign access to AWS accounts](https://docs.aws.amazon.com/singlesignon/latest/userguide/useraccess.html).
- [IAM security best practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html).

# Exercise 3 — Validate Terraform Ownership and Idempotence

## Objective

Demonstrate that the four Terraform roots have explicit ownership and do not attempt to adopt or remove resources owned by another root or by Control Tower.

## Tasks

Review the dependency chain:

```text
terraform/bootstrap
  → terraform/aft/org_unit
  → terraform/aft/account
  → terraform/aft/platform
```

For each root:

1. identify its backend key;
2. list its outputs consumed by the next root;
3. run formatting and validation;
4. run a plan without applying it;
5. inspect the plan for replacement, deletion, or cross-root ownership;
6. verify a converged root produces no changes, allowing for documented computed-value refreshes;
7. verify plans do not disable Organizations policy types or trusted service integrations;
8. verify the platform plan contains no AFT VPC, NAT gateway, or interface endpoint resources.

Record why Terraform state is sensitive and why an existing AWS resource requires import before Terraform can own it.

## Expected Result

No root proposes replacement or deletion of the Organization, landing zone, shared accounts, AFT account, or another root's resources. The AFT platform remains configured with `aft_enable_vpc=false`.

AWS references:

- [Terraform state security guidance for AWS](https://docs.aws.amazon.com/prescriptive-guidance/latest/secure-sensitive-data-secrets-manager-terraform/using-secrets-manager-and-terraform.html).
- [AFT deployment](https://docs.aws.amazon.com/controltower/latest/userguide/aft-getting-started.html).

# Exercise 4 — Validate AFT Operational Readiness

## Objective

Confirm that AFT is usable as the post-bootstrap account-vending system rather than merely present in Terraform state.

## Tasks

1. Verify the AFT management account is visible as enrolled in Control Tower.
2. Verify the four GitHub repositories exist and each has the configured `main` branch.
3. Verify the AWS CodeConnections connection is `AVAILABLE`, not `PENDING`.
4. Inspect AFT CodePipeline pipelines and their source repository mappings.
5. Inspect the account-request Step Functions workflow without starting it manually.
6. Confirm AFT service roles use temporary credentials and documented cross-account trust.
7. Confirm the AFT VPC and NAT gateways were not created.
8. Review CloudWatch log groups and determine where a failed request would be investigated.
9. Verify no human SSO credentials or bootstrap access keys are stored in pipeline configuration.
10. Create a minimal, reviewed account-request pull request draft, but do not merge it until Exercise 9 prerequisites are met.

Create an operational flow diagram:

```text
GitHub account request
  → CodeConnections
  → CodePipeline
  → AFT workflow
  → Control Tower Account Factory
  → governed account
  → global and selected customizations
```

AWS references:

- [AFT account provisioning](https://docs.aws.amazon.com/controltower/latest/userguide/aft-provision-account.html).
- [AFT troubleshooting](https://docs.aws.amazon.com/controltower/latest/userguide/aft-troubleshooting.html).
- [AWS CodeConnections](https://docs.aws.amazon.com/dtconsole/latest/userguide/connections.html).

# Exercise 5 — Prove the Difference Between Baseline, Enrollment, and Automatic Enrollment

## Objective

Explain the distinct governance states already visible in the deployed environment.

## Tasks

1. Record the AFT OU ARN and its enabled `AWSControlTowerBaseline` ARN.
2. Record the enabled `IdentityCenterBaseline` target and status.
3. Verify the AFT account's Organizations OU placement.
4. verify its Control Tower enrollment independently of OU placement.
5. Record that automatic account enrollment is disabled.
6. Explain why the AFT account is enrolled through Account Factory despite automatic enrollment being disabled.
7. Build a state-transition diagram for an account created through AFT versus an existing account moved into a governed OU.

Produce this comparison:

| Concept | What it establishes | Current evidence |
|---|---|---|
| Organizations membership | Account belongs to the organization | Organizations account record |
| OU placement | Policy inheritance boundary | Parent OU ID |
| OU baseline | Control Tower governance resources for the OU | Enabled baseline ARN/status |
| Account enrollment | Control Tower manages the account | Control Tower account status/resources |
| Automatic enrollment | Behavior for eligible accounts entering governed OUs | Disabled by design |
| AFT management | Account request and customization lifecycle | AFT request metadata/pipeline |

Do not create an unmanaged account merely to test automatic enrollment.

AWS references:

- [Register an existing OU](https://docs.aws.amazon.com/controltower/latest/userguide/register-existing-ou.html).
- [Enroll an existing account](https://docs.aws.amazon.com/controltower/latest/userguide/enroll-account.html).
- [Control Tower Account Factory](https://docs.aws.amazon.com/controltower/latest/userguide/account-factory.html).

# Exercise 6 — SCP and Landing-Zone Drift Incident Retrospective

## Objective

Turn the observed `SERVICE_CONTROL_POLICY` disable and landing-zone drift event into documented security and operational evidence without reproducing it.

## Tasks

Reconstruct the sequence from shell history, Terraform output, CloudTrail, and Control Tower status:

```text
Organization resource omitted enabled_policy_types
  → Terraform attempted to disable SERVICE_CONTROL_POLICY
  → provider timed out waiting for policy-type disable
  → Organizations root showed PolicyTypes: []
  → SCP support was restored
  → Terraform ownership guard was added
  → live landing zone returned ACTIVE / IN_SYNC
  → Terraform state was refreshed
```

Document:

- Why omission in a Terraform-managed collection can imply removal.
- Why the management account is exceptionally sensitive.
- Which CloudTrail events record the policy-type change.
- Whether any controls were temporarily ineffective.
- How live AWS status differed from stale Terraform state.
- The code change that preserves `SERVICE_CONTROL_POLICY`.
- The runbook that prevents recurrence.
- Residual risks associated with `ct-bootstrap` and management-account access.

Do **not** disable SCPs again. The real incident already supplies the failure evidence.

AWS references:

- [Enable and disable policy types](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_enable-disable.html).
- [Service control policies](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_scps.html).
- [Detect and resolve Control Tower drift](https://docs.aws.amazon.com/controltower/latest/userguide/drift.html).

# Exercise 7 — Evaluate Log Archive and Audit Boundaries Safely

## Objective

Verify centralized evidence custody without attempting destructive changes.

## Tasks

Use IAM policy analysis and read-only API calls to determine whether these principals can discover, read, delete, change retention, or administer encryption for centralized logs:

| Principal | Produce | Read | Delete | Change retention | Administer keys |
|---|---:|---:|---:|---:|---:|
| Workload/AFT account administrator | Analyze | Analyze | Analyze | Analyze | Analyze |
| Audit role | Analyze | Test approved read | Analyze | Analyze | Analyze |
| Log Archive administrator | Analyze | Test approved read | Analyze | Analyze | Analyze |
| AWS logging service | Verify delivery | N/A | N/A | N/A | As required |

Prefer IAM Policy Simulator, Access Analyzer, resource-policy review, CloudTrail delivery status, S3 Block Public Access status, versioning, encryption, and object-lock/retention inspection where applicable.

Do not attempt object deletion, bucket-policy changes, KMS changes, retention changes, or delivery interruption in the production Log Archive account.

## Expected Result

A compromised member-account administrator cannot alter authoritative centralized evidence. Clearly document which management, Log Archive, or delegated roles retain destructive authority as residual risk.

AWS references:

- [Log Archive account](https://docs.aws.amazon.com/controltower/latest/userguide/accounts.html).
- [CloudTrail security best practices](https://docs.aws.amazon.com/awscloudtrail/latest/userguide/best-practices-security.html).
- [IAM Access Analyzer policy validation](https://docs.aws.amazon.com/IAM/latest/UserGuide/access-analyzer-policy-validation.html).

# Exercise 8 — Perform a Week 1 Security-Service Gap Analysis

## Objective

Compare the current landing-zone foundation with the Week 1 roadmap without claiming that undeployed services are already operational.

## Tasks

For each capability, classify it as `DEPLOYED`, `PARTIAL`, `PLANNED`, or `DEFERRED`:

| Capability | Status | Evidence | Next implementation step |
|---|---|---|---|
| Organizations and OU model | | | |
| Control Tower landing zone | | | |
| IAM Identity Center | | | |
| AFT account vending | | | |
| Organization-wide CloudTrail | | | |
| AWS Config foundation | | | |
| GuardDuty delegated administration | | | |
| Security Hub delegated administration | | | |
| Inspector delegated administration | | | |
| KMS key strategy | | | |
| SCP catalog | | | |
| Resource Control Policies | | | |
| Tagging policy/governance | | | |
| Budget and cost monitoring | | | |

Do not enable every service merely to complete the table. Record dependencies, delegated-administrator choices, recurring cost, supported Regions, Terraform ownership, and the planned exercise week.

This exercise prevents the landing-zone deployment from being mistaken for a complete security program.

AWS references:

- [AWS Security Reference Architecture](https://docs.aws.amazon.com/prescriptive-guidance/latest/security-reference-architecture/).
- [Delegated administrator for AWS services](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_integrate_services_delegate_admin.html).
- [AWS Well-Architected Security Pillar](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/welcome.html).

# Exercise 9 — Provision a Disposable Sandbox Through AFT (Conditional)

## Objective

Validate the complete account-vending path and create a safe target for future security-control experiments.

## Prerequisites

Proceed only if:

- The AFT deployment is healthy.
- CodeConnections is `AVAILABLE`.
- All four repositories and `main` branches exist.
- A dedicated test/sandbox OU is approved and governed.
- A unique account email is available.
- Expected account and security-service costs are accepted.
- Account closure and teardown responsibilities are documented.
- No production or shared account is used.

If these prerequisites cannot be completed before Sunday, prepare and review the account request but defer merging it. That is an acceptable Week 1 outcome.

## Tasks

1. Create a pull request in the account-request repository.
2. Review account name, email, target OU, tags, change metadata, and owner fields.
3. Merge only after review.
4. Trace the request through CodeConnections, CodePipeline, Step Functions, Account Factory, and Control Tower.
5. Record provisioning duration and failure/retry behavior.
6. Verify Organizations membership, OU placement, Control Tower enrollment, IAM Identity Center access, Config, CloudTrail, and AFT metadata.
7. Verify global customizations are either intentionally empty or applied successfully.
8. Record the new account's recurring baseline costs before enabling additional services.

Do not deploy application infrastructure during this exercise.

AWS references:

- [Provision an account with AFT](https://docs.aws.amazon.com/controltower/latest/userguide/aft-provision-account.html).
- [AFT account request](https://docs.aws.amazon.com/controltower/latest/userguide/aft-account-request.html).

# Deferred Exercises

The following exercises from the original list remain valuable but are premature without a disposable governed account and test OU:

## Preventive control test

Attempt a safely prohibited operation as a disposable member-account administrator and prove that the relevant SCP or preventive control causes `AccessDenied` despite an IAM allow.

## Detective control test

Create a reversible noncompliant resource, observe AWS Config or Control Tower detection latency, and restore compliance.

## Proactive control test

Compare a rejected CloudFormation deployment with an equivalent direct API path and document the enforcement boundary.

## OU inheritance and account movement

Test parent/child OU control inheritance and movement only with disposable OUs/accounts. Because automatic enrollment is disabled, explicitly verify enrollment state after movement.

## Controlled governance drift

Use only an AWS-documented, recoverable scenario in a disposable environment. Never repeat the organization-wide SCP disable or deliberately damage foundational Control Tower resources.

These tests should become the first exercises after Exercise 9 supplies a safe target, or move into Week 2/3 according to the roadmap.

# Recommended Schedule for the Rest of Week 1

## Day 1 — Inventory and identity

### Exercise 1 — Control-plane inventory (~3h)

Produce the current organization diagram, Control Tower/AFT inventory, and ownership matrix.

### Exercise 2 — Identity and bootstrap handoff (~3h)

Validate Identity Center access, map AFT service identities, and draft the `ct-bootstrap` retirement checklist.

### Exercise 3 — Terraform ownership (~2h)

Run non-mutating plans and document state boundaries, idempotence, and the no-VPC AFT setting.

**Outcome:** The deployed foundation and its administrative trust paths are understood and documented.

## Day 2 — AFT and governance semantics

### Exercise 4 — AFT readiness (~3h)

Validate repositories, CodeConnections, pipelines, roles, logs, and absence of NAT gateways.

### Exercise 5 — Baseline and enrollment semantics (~2h)

Prove the distinction between governed OU, enrolled account, automatic enrollment, and AFT management.

### Exercise 6 — SCP incident retrospective (~3h)

Create an incident timeline, evidence set, root-cause analysis, and prevention runbook.

**Outcome:** AFT is ready for controlled use, and a real governance failure has been converted into portfolio evidence.

## Optional Day 3 — Evidence boundary and next account

### Exercise 7 — Log Archive boundary (~2.5h)

Complete a non-destructive evidence-custody analysis.

### Exercise 8 — Security-service gap analysis (~2h)

Identify what remains after landing-zone deployment and prioritize future work.

### Exercise 9 — Disposable AFT account (~3.5h, conditional)

Submit and trace a reviewed sandbox account request, or finish a merge-ready request and defer provisioning.

**Outcome:** Week 1 ends with either a validated disposable account for future testing or a documented, reviewed request ready to create one.

# Week 1 Priority Order

| Priority | Exercise | Reason now |
|---:|---|---|
| 1 | Control-plane inventory | Establish what was actually deployed and who owns it |
| 2 | Identity and bootstrap handoff | Reduce management-account credential risk |
| 3 | AFT operational readiness | Verify the new account-vending platform works safely |
| 4 | Terraform ownership/idempotence | Prevent recurrence of organization-level drift |
| 5 | Baseline and enrollment semantics | Validate current Control Tower/AFT architecture |
| 6 | SCP incident retrospective | Use a real failure rather than manufacture another |
| 7 | Log Archive boundary | Validate evidence custody safely |
| 8 | Security-service gap analysis | Set accurate expectations for the remaining roadmap |
| 9 | Disposable AFT account | Enables later enforcement tests when prerequisites are ready |

# Additional Exercises to Consider

These are optional extensions if time remains:

1. **CloudTrail investigation drill:** Find the actual events for policy-type disable/enable, identify the actor, source IP, user agent, request parameters, and event time.
2. **AFT failure drill without account creation:** Submit a deliberately invalid request only if AWS documents the validation path and it cannot invoke billable account creation; capture pipeline validation and remove the request safely.
3. **CodeConnections trust review:** Document GitHub authorization scope, repository access, connection status, IAM `UseConnection` permissions, and revocation procedure.
4. **State-backend threat model:** Review S3 encryption, versioning, public access block, access logging, lockfile behavior, recovery, and principals permitted to read or change state.
5. **Cost baseline:** Record current Control Tower, Config, CloudTrail, AFT, S3, KMS, and logging costs; verify that disabling the AFT VPC avoids NAT gateway and interface endpoint fixed costs.
6. **Root and break-glass review:** Confirm root MFA and contact data in each account without using root credentials for normal administration.
7. **Documentation redaction test:** Scan the repository for account IDs, email addresses, state files, credentials, plans, and generated artifacts before publishing portfolio evidence.

# Portfolio Outcome

A strong Week 1 portfolio statement is:

> Designed and deployed a Terraform-based AWS Control Tower landing zone with IAM Identity Center and Account Factory for Terraform; mapped Terraform and AWS service ownership, validated identity and enrollment boundaries, verified AFT source-control and pipeline integration, analyzed centralized evidence custody, and documented the root cause and remediation of an Organizations SCP drift incident.

Do not claim preventive, detective, or proactive control validation until those tests have been performed in a disposable governed account.

The Week 1 objective is to explain what has been deployed, which security guarantees are already evidenced, which controls remain untested, and how the environment can be extended safely through AFT.
