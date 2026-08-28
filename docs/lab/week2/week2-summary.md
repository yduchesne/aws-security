# Week 2 --- AWS IAM Security Portfolio Exercises

**Schedule assumption:** 8 hours/day, 5 days/week\
**Focus:** AWS Security Specialty --- identity, authorization,
federation, least privilege, policy evaluation, and troubleshooting\
**Environment:** Multi-account AWS Organization / Control Tower landing
zone established in Week 1

Setup and execution guides:

- [Week 2 shared setup](week2-setup.md)
- [Exercise 1 setup and execution](exercise1.md)

The goal for Week 2 is not merely to create IAM policies. Each exercise
should force you to **predict an authorization decision, test it,
capture evidence, and explain exactly which policy layer produced the
result**.

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
    https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies-cross-account-resource-access.html
-   Cross-account policy evaluation:
    https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_evaluation-logic-cross-account.html
-   AWS cross-account IAM tutorial:
    https://docs.aws.amazon.com/IAM/latest/UserGuide/tutorial_cross-account-with-roles.html
-   AWS CLI role configuration:
    https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-role.html

## Exercise 1 --- Basic cross-account `AssumeRole`

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
-   trust policy permitting only a specific source role;
-   permissions allowing a narrow set of read operations, such as
    listing/describing a test S3 bucket or selected resources.

Create in the **source account**:

-   `CrossAccountCallerRole`;
-   identity policy allowing `sts:AssumeRole` only against the target
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

-   allowed read operation succeeds;
-   write operation fails;
-   unrelated resource access fails;
-   assumption by an untrusted principal fails.

### Investigation

Inspect the `AssumeRole` CloudTrail event and identify:

-   calling principal;
-   target role;
-   session name;
-   source IP;
-   resulting assumed-role ARN.

### Learning outcome

Be able to explain why a target role's trust policy alone is not
necessarily sufficient for cross-account role assumption and how
authorization is evaluated in both accounts.

------------------------------------------------------------------------

## Exercise 2 --- Trust-policy hardening

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

## Exercise 3 --- Third-party role and `ExternalId`

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

## Exercise 4 --- Boundary limits an administrator-looking role

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

## Exercise 5 --- Delegated IAM administration with mandatory boundaries

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
    https://docs.aws.amazon.com/IAM/latest/UserGuide/introduction_attribute-based-access-control.html
-   IAM tags and authorization:
    https://docs.aws.amazon.com/IAM/latest/UserGuide/access_iam-tags.html

ABAC uses attributes such as principal and resource tags rather than
enumerating every resource ARN.

## Exercise 6 --- Project-based ABAC

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

-   change its own authorization-relevant tags;
-   change resource tags;
-   create resources with arbitrary `Project` tags.

This is critical: an ABAC system can be undermined if a principal can
freely manipulate the attributes used for authorization.

### Learning outcome

Explain why **tag governance is part of the authorization boundary**,
not merely resource organization.

------------------------------------------------------------------------

## Exercise 7 --- Environment-sensitive ABAC

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

## Exercise 8 --- EC2 workload role versus static credentials

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

-   allowed resource succeeds;
-   unrelated resource fails;
-   replace/detach the role and observe behavior;
-   inspect CloudTrail to identify the role session;
-   inspect how credentials are automatically rotated.

### Security analysis

Compare:

``` text
Static access key
    versus
Instance role + temporary STS credentials
```

Document exposure, rotation, revocation, and blast-radius differences.

------------------------------------------------------------------------

## Exercise 9 --- CI/CD workload federation with OIDC

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

-   CircleCI OIDC provider;
-   narrowly scoped Terraform plan/deployment role;
-   trust-policy conditions restricting which CircleCI project/context
    may assume it;
-   no stored AWS access key.

### Tests

Verify:

-   authorized project succeeds;
-   another project/claim combination fails;
-   role has only required AWS permissions;
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
    https://docs.aws.amazon.com/IAM/latest/UserGuide/access-analyzer-policy-validation.html
-   Finding remediation:
    https://docs.aws.amazon.com/IAM/latest/UserGuide/access-analyzer-findings-remediate.html

IAM Access Analyzer can identify external/internal access, unused
access, validate policies, perform custom checks, and generate policies
from CloudTrail activity.

External/internal analyzers are Regional; unused-access analysis does
not need to be duplicated per Region.

## Exercise 10 --- Detect unintended external access

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

-   resource;
-   external principal;
-   granted actions;
-   finding status;
-   analyzer's zone of trust.

Then remove the external access and verify the finding resolves.

### Learning outcome

Explain why Access Analyzer is more useful than simply searching
policies for `"Principal": "*"`: it reasons about effective external
reachability for supported resource policies.

------------------------------------------------------------------------

## Exercise 11 --- Validate IAM policies before deployment

### Objective

Add IAM policy validation to your Terraform/security-development
workflow.

Create several intentionally problematic policies:

-   overly broad actions/resources;
-   malformed or invalid elements;
-   questionable condition usage;
-   a clean least-privilege policy.

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

## Exercise 12 --- Unused access and least-privilege refinement

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

## Exercise 13 --- IAM says Allow; SCP says Deny

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

-   identity policy;
-   permissions boundary;
-   role session;
-   resource policy;
-   SCPs inherited from root and parent OUs;
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

## Exercise 14 --- Administrator policy constrained by permissions boundary

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

-   explicit deny;
-   implicit deny;
-   permissions ceiling;
-   permissions grant.

Do not describe a permissions boundary as a policy that simply "denies
everything not listed"; explain it as the maximum identity permissions
the principal may receive.

------------------------------------------------------------------------

# `scenarios/assume-role-failure/`

## Exercise 15 --- Diagnose `AssumeRole` failures systematically

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

-   locate relevant STS/CloudTrail evidence;
-   record the principal ARN;
-   record role ARN;
-   record session name;
-   identify which policy layer you conclude blocked access;
-   explain what evidence supports that conclusion.

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

# Repository Layout After Week 2

``` text
week-2-iam/
├── cross-account/
│   ├── README.md
│   ├── terraform/
│   ├── test.sh
│   └── evidence/
│
├── permission-boundaries/
│   ├── README.md
│   ├── terraform/
│   ├── test.sh
│   └── evidence/
│
├── abac/
│   ├── README.md
│   ├── terraform/
│   ├── test.sh
│   └── evidence/
│
├── workload-identities/
│   ├── README.md
│   ├── terraform/
│   ├── test.sh
│   └── evidence/
│
├── access-analyzer/
│   ├── README.md
│   ├── terraform/
│   ├── validate-policies.sh
│   └── evidence/
│
└── scenarios/
    ├── scp-deny/
    │   ├── README.md
    │   ├── terraform/
    │   └── evidence/
    ├── boundary-deny/
    │   ├── README.md
    │   ├── terraform/
    │   └── evidence/
    └── assume-role-failure/
        ├── README.md
        ├── terraform/
        ├── test.sh
        └── evidence/
```

# Week 2 Completion Criteria

At the end of the week, you should be able to take an AWS authorization
failure and reason through it systematically rather than adding
permissions until it works.

You should be able to explain and demonstrate:

-   cross-account trust versus permissions;
-   STS temporary credentials;
-   role trust policies;
-   `ExternalId` and the confused-deputy problem;
-   permissions boundaries as privilege ceilings;
-   delegated IAM administration without unrestricted privilege
    escalation;
-   RBAC versus ABAC;
-   authorization-sensitive tag governance;
-   workforce identity versus workload identity;
-   native AWS roles versus OIDC federation;
-   IAM Access Analyzer external-access reasoning;
-   IAM policy validation;
-   SCP, boundary, identity-policy, and trust-policy interactions;
-   systematic `AssumeRole` troubleshooting.

The strongest portfolio outcome is not "I created IAM roles." It is:

> **I designed, implemented, attacked, and validated a multi-account AWS
> authorization model, including cross-account delegation, permissions
> boundaries, ABAC, federated workload identity, automated policy
> analysis, and explicit-deny troubleshooting.**
