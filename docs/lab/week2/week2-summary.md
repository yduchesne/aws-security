# Week 2 --- AWS IAM Security Portfolio Exercises

**Schedule assumption:** 8 hours/day, 5 days/week\
**Focus:** AWS Security Specialty --- identity, authorization,
federation, least privilege, policy evaluation, and troubleshooting\
**Environment:** Multi-account AWS Organization / Control Tower landing
zone established in Week 1

## Table of contents

- [Curriculum classification](#curriculum-classification)
- [Exercise guides](#exercise-guides)
  - [[Core] Exercise 1 — Basic cross-account `AssumeRole`](#core-exercise-1--basic-cross-account-assumerole)
  - [[Core] Exercise 2 — Trust-policy hardening](#core-exercise-2--trust-policy-hardening)
  - [[Core] Exercise 3 — Third-party role and `ExternalId`](#core-exercise-3--third-party-role-and-externalid)
  - [[Optional] Exercise 4 — Boundary limits an administrator-looking role](#optional-exercise-4--boundary-limits-an-administrator-looking-role)
  - [[Core] Exercise 5 — Delegated IAM administration with mandatory boundaries](#core-exercise-5--delegated-iam-administration-with-mandatory-boundaries)
  - [[Core] Exercise 6 — Project-based ABAC](#core-exercise-6--project-based-abac)
  - [[Optional] Exercise 7 — Environment-sensitive ABAC](#optional-exercise-7--environment-sensitive-abac)
  - [[Core] Exercise 8 — EC2 workload role versus static credentials](#core-exercise-8--ec2-workload-role-versus-static-credentials)
  - [[Core] Exercise 9 — CI/CD workload federation with OIDC](#core-exercise-9--ci-cd-workload-federation-with-oidc)
  - [[Optional] Exercise 10 — Detect unintended external access](#optional-exercise-10--detect-unintended-external-access)
  - [[Core] Exercise 11 — Validate IAM policies before deployment](#core-exercise-11--validate-iam-policies-before-deployment)
  - [[Optional] Exercise 12 — Unused access and least-privilege refinement](#optional-exercise-12--unused-access-and-least-privilege-refinement)
  - [[Optional] Exercise 13 — IAM says Allow; SCP says Deny](#optional-exercise-13--iam-says-allow-scp-says-deny)
  - [[Optional] Exercise 14 — Administrator policy constrained by permissions boundary](#optional-exercise-14--administrator-policy-constrained-by-permissions-boundary)
  - [[Core] Exercise 15 — Diagnose `AssumeRole` failures systematically](#core-exercise-15--diagnose-assumerole-failures-systematically)
- [Recommended evidence format](#recommended-evidence-format)
- [Suggested 5-Day Execution Plan](#suggested-5-day-execution-plan)
- [Week 2 Completion Criteria](#week-2-completion-criteria)

Setup and execution guides:

- [Week 2 shared setup](week2-setup.md).
- [Exercise 1 setup and execution](exercise1/exercise1-instructions.md).
- [Exercise 2 setup and execution](exercise2/exercise2-instructions.md).
- [Exercises 3–15 setup and execution](exercise3/exercise3-instructions.md) (each exercise has its own directory and guide).

The goal for Week 2 is not merely to create IAM policies. Each exercise
should force you to **predict an authorization decision, test it,
capture evidence, and explain exactly which policy layer produced the
result**.

## Curriculum classification

The following classification keeps the mandatory path focused while retaining
useful extensions:

| Exercises | Classification | Rationale |
|---|---|---|
| 1, 2, 3, 5, 6, 8, 9, 11, 15 | Core | Required concepts for the primary AWS Security Specialty learning path. |
| 4, 7, 10, 12, 13, 14 | Optional | Extensions, overlapping demonstrations, or slower operational scenarios. |

Exercises 4 and 14 are complementary permissions-boundary demonstrations;
Exercise 7 extends Exercise 6; and Exercise 15 serves as the cross-account
troubleshooting capstone. Each exercise guide and Terraform root carries the
same `Core` or `Optional` classification.

## Exercise guides

- [[Core] Exercise 1 — Basic cross-account `AssumeRole`](exercise1/exercise1-instructions.md).
- [[Core] Exercise 2 — Trust-policy hardening](exercise2/exercise2-instructions.md).
- [[Core] Exercise 3 — Third-party role and `ExternalId`](exercise3/exercise3-instructions.md).
- [[Optional] Exercise 4 — Boundary limits an administrator-looking role](exercise4/exercise4-instructions.md).
- [[Core] Exercise 5 — Delegated IAM administration with mandatory boundaries](exercise5/exercise5-instructions.md).
- [[Core] Exercise 6 — Project-based ABAC](exercise6/exercise6-instructions.md).
- [[Optional] Exercise 7 — Environment-sensitive ABAC](exercise7/exercise7-instructions.md).
- [[Core] Exercise 8 — EC2 workload role versus static credentials](exercise8/exercise8-instructions.md).
- [[Core] Exercise 9 — CI/CD workload federation with OIDC](exercise9/exercise9-instructions.md).
- [[Optional] Exercise 10 — Detect unintended external access](exercise10/exercise10-instructions.md).
- [[Core] Exercise 11 — Validate IAM policies before deployment](exercise11/exercise11-instructions.md).
- [[Optional] Exercise 12 — Unused access and least-privilege refinement](exercise12/exercise12-instructions.md).
- [[Optional] Exercise 13 — IAM says Allow; SCP says Deny](exercise13/exercise13-instructions.md).
- [[Optional] Exercise 14 — Administrator policy constrained by permissions boundary](exercise14/exercise14-instructions.md).
- [[Core] Exercise 15 — Diagnose `AssumeRole` failures systematically](exercise15/exercise15-instructions.md).

Use disposable workload accounts/resources where possible. Avoid
experimental deny policies in the management, Log Archive, or Security
Tooling accounts unless you have explicitly verified the recovery path.

## Recommended evidence format

For every exercise preserve:

``` text
README.md
terraform/
test.sh
expected-results.md
evidence/
```

In each `README.md`, document:

1.  Security objective
2.  Threat/failure mode
3.  Identities and resources involved
4.  Relevant identity policy
5.  Relevant trust/resource policy
6.  SCP / permissions boundary / session policy, if applicable
7.  Expected authorization result
8.  Actual result
9.  CloudTrail evidence
10. Explanation using IAM policy-evaluation logic
11. Residual risk and production hardening

------------------------------------------------------------------------

# `cross-account/`

Cross-account exercises should teach the distinction between the
**trusted account** (where the calling principal originates) and
**trusting account** (where the target role/resource exists). For
cross-account authorization, both sides of the trust relationship
matter.

AWS references:

-   Cross-account resource access:
    https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies-cross-account-resource-access.html.
-   Cross-account policy evaluation:
    https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_evaluation-logic-cross-account.html.
-   AWS cross-account IAM tutorial:
    https://docs.aws.amazon.com/IAM/latest/UserGuide/tutorial_cross-account-with-roles.html.
-   AWS CLI role configuration:
    https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-role.html.

## [Core] Exercise 1 --- Basic cross-account `AssumeRole`

### Objective

Build and test a least-privilege cross-account role from one
workload/automation account into another.

Example:

``` text
Source account                         Target account

Caller role
    │
    │ identity policy:
    │ Allow sts:AssumeRole
    ▼
STS AssumeRole ───────────────────────► DeploymentReadRole
                                       │
                                       │ trust policy permits caller
                                       │
                                       ▼
                                  temporary credentials
                                       │
                                       ▼
                                  read selected resources
```

### Implementation

Create in the **target account**:

-   `CrossAccountReadRole`
-   Trust policy permitting only a specific source role.
-   Permissions allowing a narrow set of read operations, such as
    listing/describing a test S3 bucket or selected resources.

Create in the **source account**:

-   `CrossAccountCallerRole`;
-   Identity policy allowing `sts:AssumeRole` only against the target
    role ARN.

Do **not** trust the entire source account unless the exercise
explicitly compares that design with principal-specific trust.

### Tests

Test:

``` bash
aws sts assume-role \
  --role-arn arn:aws:iam::<TARGET>:role/CrossAccountReadRole \
  --role-session-name week2-test
```

Export/use the returned temporary credentials and verify:

-   Allowed read operation succeeds.
-   Write operation fails.
-   Unrelated resource access fails.
-   Assumption by an untrusted principal fails.

### Investigation

Inspect the `AssumeRole` CloudTrail event and identify:

-   Calling principal.
-   Target role.
-   Session name.
-   Source IP.
-   Resulting assumed-role ARN.

### Learning outcome

Be able to explain why a target role's trust policy alone is not
necessarily sufficient for cross-account role assumption and how
authorization is evaluated in both accounts.

------------------------------------------------------------------------

## [Core] Exercise 2 --- Trust-policy hardening

### Objective

Learn why `"Principal": {"AWS": "<account-root-ARN>"}` can create a
broader delegation boundary than trusting one explicit role.

### Procedure

Create two source roles:

``` text
ApprovedAutomationRole
UnapprovedRole
```

First configure the target trust policy to trust the source **account**.
Determine what additional source-account permissions would permit each
role to assume the target role.

Then replace the trust with the specific approved role ARN.

Retest.

### Tests

Record results for:

  Caller              Account-level trust   Explicit role trust
  ----------------- --------------------- ---------------------
  Approved role                      Test                  Test
  Unapproved role                    Test                  Test

### Learning outcome

Explain the difference between:

``` text
"I trust this AWS account to delegate access"
```

and:

``` text
"I trust this specific principal"
```

------------------------------------------------------------------------

## [Core] Exercise 3 --- Third-party role and `ExternalId`

### Objective

Understand the confused-deputy problem and why `sts:ExternalId` exists.

AWS reference:

https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_common-scenarios_third-party.html

### Procedure

Simulate a SaaS vendor using a role in another account.

Target trust policy should require:

``` json
"Condition": {
  "StringEquals": {
    "sts:ExternalId": "<customer-specific-value>"
  }
}
```

Test role assumption:

1.  without `ExternalId`;
2.  with the wrong value;
3.  with the correct value.

### Important conclusion

Document that an external ID is **not a password or secret**. Its
principal security purpose is preventing confused-deputy scenarios in
multi-tenant third-party integrations.

------------------------------------------------------------------------

# `permission-boundaries/`

AWS reference:

https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies_boundaries.html

A permissions boundary defines the **maximum identity-based
permissions** an IAM user or role can receive. It does not itself grant
permissions.

Conceptually:

``` text
Identity policy allows
        ∩
Permissions boundary allows
        =
Effective identity permissions
```

Explicit denies from applicable policies still win.

## [Optional] Exercise 4 --- Boundary limits an administrator-looking role

### Objective

Prove experimentally that attaching `AdministratorAccess` does not
necessarily produce administrator effective permissions.

### Procedure

Create:

``` text
BoundedDeveloperRole
```

Attach:

``` text
AdministratorAccess
```

but also attach a permissions boundary that allows only a controlled set
of services/actions, for example:

``` text
S3
CloudWatch
selected EC2 read operations
```

### Tests

Verify:

``` text
s3:ListBucket          → ALLOW
ec2:DescribeInstances  → ALLOW
iam:CreateRole         → DENY
organizations:*        → DENY
```

Then remove the `AdministratorAccess` identity policy while retaining
the boundary.

Verify that the boundary **does not grant** S3/EC2 access by itself.

### Learning outcome

Be able to explain:

``` text
Permissions boundary = maximum possible permission
Identity policy       = requested/granted permission set
Effective permission  = intersection
```

------------------------------------------------------------------------

## [Core] Exercise 5 --- Delegated IAM administration with mandatory boundaries

### Objective

Build a practical delegation model in which a developer/platform
administrator can create roles but cannot create roles more privileged
than an approved ceiling.

### Scenario

You want a platform engineer to create application roles without
allowing:

``` text
Developer
   ↓
CreateRole
   ↓
Administrator role
   ↓
privilege escalation
```

### Implementation

Create a boundary such as:

``` text
ApplicationRoleBoundary
```

Then grant the delegated administrator permissions to create/manage
roles **only when the required permissions boundary is attached**.

Use IAM condition keys associated with permissions boundaries to enforce
the requirement.

### Tests

Attempt to:

1.  create a role with the approved boundary;
2.  create the same role without the boundary;
3.  create it with an unapproved boundary;
4.  remove the boundary after creation;
5.  replace it;
6.  attach an overly permissive identity policy to the bounded role.

### Expected result

The delegated administrator can manage application roles within the
allowed ceiling but cannot escape that ceiling.

### Portfolio value

This is one of the most important Week 2 exercises because it
demonstrates **privilege-escalation-resistant IAM delegation**, rather
than simply least-privilege policy authoring.

------------------------------------------------------------------------

# `abac/`

AWS references:

-   ABAC introduction:
    https://docs.aws.amazon.com/IAM/latest/UserGuide/introduction_attribute-based-access-control.html.
-   IAM tags and authorization:
    https://docs.aws.amazon.com/IAM/latest/UserGuide/access_iam-tags.html.

ABAC uses attributes such as principal and resource tags rather than
enumerating every resource ARN.

## [Core] Exercise 6 --- Project-based ABAC

### Objective

Build one authorization policy that works across multiple projects
without creating one role/policy per project.

### Model

Resources:

``` text
Project=Alpha
Project=Beta
```

Principals/sessions:

``` text
Project=Alpha
Project=Beta
```

Authorization rule:

``` text
Principal Project tag == Resource Project tag
```

### Implementation

Create test resources tagged:

``` text
Project = Alpha
Project = Beta
```

Create/tag test principals or pass controlled session tags.

Build a policy using:

``` text
aws:PrincipalTag/Project
aws:ResourceTag/Project
```

### Tests

  Principal   Resource   Expected
  ----------- ---------- ----------
  Alpha       Alpha      Allow
  Alpha       Beta       Deny
  Beta        Beta       Allow
  Beta        Alpha      Deny

### Attack test

Determine whether the principal can:

-   Change its own authorization-relevant tags.
-   Change resource tags.
-   Create resources with arbitrary `Project` tags.

This is critical: an ABAC system can be undermined if a principal can
freely manipulate the attributes used for authorization.

### Learning outcome

Explain why **tag governance is part of the authorization boundary**,
not merely resource organization.

------------------------------------------------------------------------

## [Optional] Exercise 7 --- Environment-sensitive ABAC

### Objective

Extend ABAC so project membership alone does not grant production
access.

Use:

``` text
Project
Environment
```

Require both to match.

Example:

``` text
Principal:
  Project=Alpha
  Environment=Development

Resource:
  Project=Alpha
  Environment=Production
```

Result:

``` text
DENY
```

### Tests

Create a matrix covering Alpha/Beta and Development/Production.

Attempt tag tampering and document which IAM permissions must be
controlled to keep the ABAC model trustworthy.

------------------------------------------------------------------------

# `workload-identities/`

AWS reference:

https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles.html

The core rule is:

> Workloads should normally obtain temporary credentials through
> roles/federation rather than store long-lived IAM-user access keys.

## [Core] Exercise 8 --- EC2 workload role versus static credentials

### Objective

Demonstrate native AWS workload identity.

Create a disposable EC2 instance with an instance profile/role that can
read one test resource.

From the instance:

``` bash
aws sts get-caller-identity
```

Then access the allowed resource.

Verify that no static AWS access key was placed on the host.

### Tests

-   Allowed resource succeeds.
-   Unrelated resource fails.
-   Replace/detach the role and observe behavior.
-   Inspect CloudTrail to identify the role session.
-   Inspect how credentials are automatically rotated.

### Security analysis

Compare:

``` text
Static access key
    versus
Instance role + temporary STS credentials
```

Document exposure, rotation, revocation, and blast-radius differences.

------------------------------------------------------------------------

## [Core] Exercise 9 --- CI/CD workload federation with OIDC

### Objective

Apply the same workload-identity principle to external automation such
as CircleCI.

Architecture:

``` text
CircleCI job
    ↓
OIDC JWT
    ↓
AWS IAM OIDC provider
    ↓
sts:AssumeRoleWithWebIdentity
    ↓
CircleCI deployment role
    ↓
temporary AWS credentials
```

### Tasks

Create:

-   CircleCI OIDC provider.
-   Narrowly scoped Terraform plan/deployment role.
-   Trust-policy conditions restricting which CircleCI project/context
    may assume it.
-   No stored AWS access key.

### Tests

Verify:

-   Authorized project succeeds.
-   Another project/claim combination fails.
-   Role has only required AWS permissions.
-   CloudTrail records `AssumeRoleWithWebIdentity`.

### Extension

Separate:

``` text
TerraformPlanRole
TerraformNonProdApplyRole
TerraformProdApplyRole
```

and compare their permissions and trust conditions.

### Learning outcome

Explain why workforce federation (Identity Center) and workload
federation (OIDC) solve different identity problems.

------------------------------------------------------------------------

# `access-analyzer/`

AWS references:

-   Overview:
    https://docs.aws.amazon.com/IAM/latest/UserGuide/what-is-access-analyzer.html
-   Findings:
    https://docs.aws.amazon.com/IAM/latest/UserGuide/access-analyzer-concepts.html
-   Policy validation:
    https://docs.aws.amazon.com/IAM/latest/UserGuide/access-analyzer-policy-validation.html.
-   Finding remediation:
    https://docs.aws.amazon.com/IAM/latest/UserGuide/access-analyzer-findings-remediate.html.

IAM Access Analyzer can identify external/internal access, unused
access, validate policies, perform custom checks, and generate policies
from CloudTrail activity.

External/internal analyzers are Regional; unused-access analysis does
not need to be duplicated per Region.

## [Optional] Exercise 10 --- Detect unintended external access

### Objective

Create an intentional external-access condition and verify Access
Analyzer detects it.

### Procedure

Create an analyzer with the appropriate account/organization zone of
trust.

In a disposable account/resource, create a supported resource policy
granting access outside that zone of trust---for example, a deliberately
controlled cross-account S3 bucket policy or IAM role trust.

Wait for/find the Access Analyzer finding.

### Evidence

Record:

-   Resource.
-   External principal.
-   Granted actions.
-   Finding status.
-   Analyzer's zone of trust.

Then remove the external access and verify the finding resolves.

### Learning outcome

Explain why Access Analyzer is more useful than simply searching
policies for `"Principal": "*"`: it reasons about effective external
reachability for supported resource policies.

------------------------------------------------------------------------

## [Core] Exercise 11 --- Validate IAM policies before deployment

### Objective

Add IAM policy validation to your Terraform/security-development
workflow.

Create several intentionally problematic policies:

-   Overly broad actions/resources.
-   Malformed or invalid elements.
-   Questionable condition usage.
-   A clean least-privilege policy.

Run:

``` bash
aws accessanalyzer validate-policy \
  --policy-document file://policy.json \
  --policy-type IDENTITY_POLICY
```

Record errors, security warnings, warnings, and suggestions.

### Extension

Create:

``` text
scripts/validate-iam-policies.sh
```

and have it fail CI for validation errors/security findings according to
a policy you define.

### Portfolio value

This turns Access Analyzer from a console feature into a **preventive
policy-as-code quality gate**.

------------------------------------------------------------------------

## [Optional] Exercise 12 --- Unused access and least-privilege refinement

### Objective

Understand how historical access data can support permissions reduction.

Create an unused-access analyzer if appropriate for your lab/cost
constraints. Configure a short lab-appropriate tracking period while
understanding that production periods are normally chosen based on
operational patterns.

Create/use a role with permissions broader than the operations you
actually exercise.

Observe findings when sufficient history exists.

### Important limitation

Unused-access findings are historical evidence:

``` text
"Not used during observation period"
```

does **not** logically imply:

``` text
"Will never be required"
```

Document that distinction.

------------------------------------------------------------------------

# `scenarios/`

These are troubleshooting exercises. Do not begin by reading the policy
and immediately fixing it.

Instead:

1.  execute the failing operation;
2.  capture the error;
3.  inspect CloudTrail;
4.  enumerate every applicable policy layer;
5.  predict the decision;
6.  identify the actual blocking layer;
7.  make the smallest correction;
8.  rerun the test.

Use this authorization model:

``` text
Organizations SCP/RCP
        ↓
Identity policy
        ↓
Permissions boundary
        ↓
Session policy
        ↓
Resource/trust policy
        ↓
Condition keys/context
        ↓
Explicit Deny?
        ↓
Effective authorization decision
```

------------------------------------------------------------------------

# `scenarios/scp-deny/`

## [Optional] Exercise 13 --- IAM says Allow; SCP says Deny

### Objective

Diagnose a request denied by an Organizations SCP despite an identity
policy allowing the action.

### Setup

In a disposable workload OU/account:

1.  give a test role permission to perform a harmless operation;
2.  verify it succeeds;
3.  attach an SCP that explicitly denies that operation;
4.  repeat the request.

### Investigation

Before changing anything, inspect:

-   Identity policy.
-   Permissions boundary.
-   Role session.
-   Resource policy.
-   SCPs inherited from root and parent OUs.
-   CloudTrail event.

### Required explanation

Explain why:

``` text
Identity policy = Allow
SCP             = Deny
----------------------
Result          = Deny
```

Then remove/narrow the SCP and prove access returns.

### Extension

Move the test account between OUs and observe how inherited SCPs alter
effective permissions.

------------------------------------------------------------------------

# `scenarios/boundary-deny/`

## [Optional] Exercise 14 --- Administrator policy constrained by permissions boundary

### Objective

Diagnose an authorization failure where the attached identity policy
appears to allow the operation.

### Setup

Attach:

``` text
AdministratorAccess
```

to a role.

Attach a permissions boundary that does **not** permit:

``` text
iam:CreateRole
```

Attempt:

``` bash
aws iam create-role ...
```

### Investigation

Verify:

``` text
AdministratorAccess → Allow
Boundary            → no applicable Allow / outside maximum
Effective result    → Deny
```

Then add the required permission to the boundary and retest.

### Required explanation

Be able to distinguish:

-   Explicit deny.
-   Implicit deny.
-   Permissions ceiling.
-   Permissions grant.

Do not describe a permissions boundary as a policy that simply "denies
everything not listed"; explain it as the maximum identity permissions
the principal may receive.

------------------------------------------------------------------------

# `scenarios/assume-role-failure/`

## [Core] Exercise 15 --- Diagnose `AssumeRole` failures systematically

### Objective

Learn to troubleshoot one of the most common multi-account IAM failures
without trial-and-error policy editing.

### Build several failure modes

Start from a working cross-account role, then introduce one failure at a
time.

#### Failure A --- Source lacks `sts:AssumeRole`

Remove the caller's permission to call:

``` text
sts:AssumeRole
```

Predict and observe the result.

#### Failure B --- Target trust policy does not trust caller

Restore the source policy but remove/change the target trust
relationship.

Retest.

#### Failure C --- SCP blocks STS

Apply a test SCP that prevents the relevant STS operation.

Retest.

#### Failure D --- Incorrect `ExternalId`

Require:

``` text
sts:ExternalId
```

and supply the wrong value.

Retest with the correct value.

#### Failure E --- Trust-policy condition mismatch

Add a controlled condition---for example one based on organization,
principal ARN, source identity, or another appropriate context key---and
intentionally violate it.

### Diagnostic matrix

Complete:

  --------------------------------------------------------------------------
  Source allows  Target trusts  SCP permits?   Conditions     Result
  AssumeRole?    caller?                       satisfied?
  -------------- -------------- -------------- -------------- --------------
  Yes            Yes            Yes            Yes            Allow

  No             Yes            Yes            Yes            Deny

  Yes            No             Yes            Yes            Deny

  Yes            Yes            No             Yes            Deny

  Yes            Yes            Yes            No             Deny
  --------------------------------------------------------------------------

### CloudTrail exercise

For every failure:

-   Locate relevant STS/CloudTrail evidence.
-   Record the principal ARN.
-   Record role ARN.
-   Record session name.
-   Identify which policy layer you conclude blocked access.
-   Explain what evidence supports that conclusion.

### Advanced extension --- Source identity

Investigate `sts:SourceIdentity` and how it improves attribution for
assumed-role activity, including role chaining.

AWS reference:

https://docs.aws.amazon.com/IAM/latest/UserGuide/id_credentials_temp_control-access_monitor.html

------------------------------------------------------------------------

# Suggested 5-Day Execution Plan

## Day 1 --- Cross-account authorization

**Morning** - Exercise 1 --- Basic cross-account `AssumeRole` - Exercise
2 --- Trust-policy hardening

**Afternoon** - Exercise 3 --- `ExternalId` - Start
`assume-role-failure/`

Primary concepts:

``` text
trust policy
identity policy
STS
temporary credentials
cross-account evaluation
ExternalId
```

## Day 2 --- Permissions boundaries and escalation resistance

**Morning** - Exercise 4 --- Boundary versus AdministratorAccess

**Afternoon** - Exercise 5 --- Delegated IAM administration - Exercise
14 --- `boundary-deny/`

Spend substantial time on Exercise 5. It directly addresses IAM
privilege-escalation prevention.

## Day 3 --- ABAC

**Morning** - Exercise 6 --- Project ABAC

**Afternoon** - Exercise 7 --- Environment-sensitive ABAC - attack your
own tag-governance assumptions

The important lesson is not simply how `${aws:PrincipalTag/...}` works;
it is how to prevent unauthorized manipulation of security-relevant
attributes.

## Day 4 --- Workload identity

**Morning** - Exercise 8 --- Native AWS workload role

**Afternoon** - Exercise 9 --- CircleCI OIDC federation

Compare:

``` text
Human              → IAM Identity Center
AWS workload       → AWS IAM role
External CI/CD     → OIDC federation + IAM role
```

Avoid long-lived IAM-user credentials in all three cases.

## Day 5 --- Access analysis and authorization troubleshooting

**Morning** - Exercise 10 --- External access finding - Exercise 11 ---
Policy validation - begin Exercise 12 if useful/cost-appropriate

**Afternoon** - Exercise 13 --- `scp-deny/` - Exercise 14 ---
`boundary-deny/` - Exercise 15 --- `assume-role-failure/`

Finish by writing a one-page **AWS authorization decision
troubleshooting guide** based on what you observed experimentally.

------------------------------------------------------------------------

# Week 2 Completion Criteria

At the end of the week, you should be able to take an AWS authorization
failure and reason through it systematically rather than adding
permissions until it works.

You should be able to explain and demonstrate:

-   Cross-account trust versus permissions.
-   STS temporary credentials.
-   Role trust policies.
-   `ExternalId` and the confused-deputy problem;
-   Permissions boundaries as privilege ceilings.
-   Delegated IAM administration without unrestricted privilege
    escalation.
-   RBAC versus ABAC.
-   Authorization-sensitive tag governance.
-   Workforce identity versus workload identity.
-   Native AWS roles versus OIDC federation.
-   IAM Access Analyzer external-access reasoning.
-   IAM policy validation.
-   SCP, boundary, identity-policy, and trust-policy interactions.
-   Systematic `AssumeRole` troubleshooting.

The strongest portfolio outcome is not "I created IAM roles." It is:

> **I designed, implemented, attacked, and validated a multi-account AWS
> authorization model, including cross-account delegation, permissions
> boundaries, ABAC, federated workload identity, automated policy
> analysis, and explicit-deny troubleshooting.**
