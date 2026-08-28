# AWS Certified Security -- Specialty (SCS-C03) + Portfolio Roadmap

**Schedule:** 8 hours/day, 5 days/week\
**Duration:** 8 weeks\
**Total effort:** 320 hours\
**Goal:** Prepare for AWS Certified Security -- Specialty while building
an interview-ready AWS cloud-security engineering portfolio.

## Learning model

Use the same loop throughout the program:

``` text
1. LEARN
   AWS documentation / SRA / Skill Builder
        ↓
2. LAB
   Builder Lab / SimuLearn / Workshop / Jam
        ↓
3. BUILD
   Reimplement and extend with Terraform
        ↓
4. BREAK
   Misconfigure / attack / troubleshoot / validate
        ↓
5. DOCUMENT
   Threat, control, evidence, residual risk
```

Skill Builder is the guided-practice layer. The Terraform portfolio is
the independent engineering layer.

## Overall allocation

  Activity                                 Approx. hours
  -------------------------------------- ---------------
  AWS documentation and theory                        62
  Skill Builder / AWS labs / workshops                96
  Terraform portfolio engineering                    130
  Documentation and diagrams                          20
  Exam-specific assessment and review                 12
  **Total**                                      **320**

## Portfolio structure

``` text
aws-security-reference-architecture/
├── terraform/
│   ├── organization-governance/
│   ├── identity-access/
│   ├── network-security/
│   ├── data-protection/
│   ├── logging-detection/
│   └── incident-response/
├── policies/
├── automation/
├── scenarios/
│   ├── compromised-credentials/
│   ├── public-s3/
│   ├── compromised-ec2/
│   └── privilege-escalation/
├── diagrams/
├── docs/
│   ├── architecture.md
│   ├── threat-model.md
│   ├── security-controls.md
│   ├── incident-response.md
│   ├── deployment.md
│   └── cost-analysis.md
└── README.md
```

------------------------------------------------------------------------

# Week 1 --- Security Foundations, Governance, and Multi-Account Architecture

**40 hours**

## Topics

-   AWS Security Reference Architecture (SRA)
-   AWS Well-Architected Security Pillar
-   AWS Organizations
-   OUs and account structure
-   accounts as security boundaries
-   management-account protection
-   Security Tooling account
-   Log Archive account
-   delegated administration
-   Service Control Policies (SCPs)
-   Resource Control Policies (RCPs)
-   Control Tower concepts
-   organization-wide CloudTrail
-   AWS Config
-   organization-wide GuardDuty
-   Security Hub
-   KMS foundations
-   tagging and resource governance

## Skill Builder / AWS hands-on

Prioritize relevant Builder Labs such as:

-   Introduction to AWS Identity and Access Management (IAM)
-   Introduction to AWS Key Management Service (AWS KMS)
-   Performing a Basic Audit of Your AWS Environment

Where an appropriate fixed lab is unavailable, use Skill Builder Lab
Maker for scenarios such as:

-   multi-account AWS Organizations architecture with Security,
    Infrastructure, and Workloads OUs
-   SCP preventing a workload account from disabling CloudTrail
-   centralized organization CloudTrail delivery to a protected Log
    Archive account
-   delegated security-service administration

## Portfolio

Build:

``` text
AWS Organization
│
├── Security OU
│   ├── Security Tooling
│   └── Log Archive
├── Infrastructure OU
└── Workloads OU
    ├── Development
    └── Production
```

Implement Terraform for the organizational model, baseline guardrails,
centralized logging, security-service administration, encryption, Config
foundations, and tagging.

## Validation

-   Attempt an operation prohibited by an SCP.
-   Attempt to interfere with centralized logging.
-   Verify organization CloudTrail delivery.
-   Verify KMS and S3 policy behavior.
-   Verify security controls apply as intended to member accounts.

## Suggested allocation

-   Reading/theory: 12h
-   Skill Builder/labs: 8h
-   Terraform portfolio: 17h
-   Documentation/testing: 3h

**Milestone:** Multi-Account AWS Security Foundation.

------------------------------------------------------------------------

# Week 2 --- Identity and Access Management

**40 hours**

## Topics

-   IAM policies
-   resource policies
-   roles
-   STS and AssumeRole
-   cross-account access
-   permission boundaries
-   SCP interactions
-   session policies
-   explicit deny
-   ABAC
-   IAM Identity Center
-   Access Analyzer
-   MFA
-   service-linked roles
-   workload identities
-   policy conditions
-   least privilege
-   confused-deputy protections

## Skill Builder / AWS hands-on

Use IAM-focused Skill Builder material, including Authentication and
Authorization with AWS IAM where available.

Use Lab Maker or your own sandbox for authorization scenarios:

``` text
IAM Allow + SCP Deny
IAM Allow + restrictive permission boundary
Cross-account AssumeRole + trust policy + identity policy + SCP
Resource policy + identity policy interactions
ABAC conditions
```

The objective is to become comfortable determining **effective
permissions**, not merely writing IAM JSON.

## Portfolio

``` text
identity-access/
├── cross-account/
├── permission-boundaries/
├── abac/
├── workload-identities/
├── access-analyzer/
└── scenarios/
    ├── scp-deny/
    ├── boundary-deny/
    └── assume-role-failure/
```

Create deliberately broken authorization scenarios and document why each
request succeeds or fails.

## Suggested allocation

-   Study: 8h
-   Skill Builder/labs: 12h
-   Portfolio: 17h
-   Documentation/questions: 3h

**Milestone:** Enterprise AWS IAM Architecture.

------------------------------------------------------------------------

# Week 3 --- Infrastructure Security

**40 hours**

## Topics

-   VPC architecture
-   subnets and routing
-   security groups
-   NACLs
-   VPC endpoints
-   PrivateLink
-   VPC Flow Logs
-   Network Firewall
-   DNS Firewall
-   Route 53 Resolver
-   Transit Gateway concepts
-   Network Access Analyzer
-   CloudFront
-   WAF
-   Shield
-   TLS and ACM
-   API Gateway security
-   EC2 security
-   IMDSv2
-   Systems Manager
-   Inspector
-   Lambda security
-   EKS security concepts

## Skill Builder / AWS hands-on

Use relevant Builder Labs such as:

-   Introduction to Amazon VPC
-   Introduction to Amazon EC2
-   Introduction to Amazon CloudFront

Add deeper labs or Lab Maker exercises involving:

-   private application workloads
-   VPC endpoints
-   Network Firewall
-   WAF
-   Flow Logs
-   restrictive security-group design
-   three-tier VPC isolation
-   S3 access without public Internet traversal

## Portfolio

Build:

``` text
Internet
   │
CloudFront
   │
  WAF
   │
  ALB
   │
┌──────────── VPC ─────────────┐
│ Public subnets               │
│       │                      │
│ Private application subnets │
│       │                      │
│ Isolated data subnets       │
│                              │
│ VPC endpoints               │
└──────────────────────────────┘
```

## Validation

-   Internet → database: denied
-   Internet → unnecessary SSH: denied
-   application → database: allowed only as intended
-   application → S3: intended private path
-   rejected/unexpected flows: observable

## Suggested allocation

-   Study: 8h
-   Skill Builder/labs: 12h
-   Portfolio: 17h
-   Documentation/questions: 3h

**Milestone:** Secure AWS Network and Workload Reference Architecture.

------------------------------------------------------------------------

# Week 4 --- Data Protection

**40 hours**

## Topics

-   KMS key policies
-   IAM/KMS policy interaction
-   grants
-   envelope encryption
-   encryption context
-   rotation
-   multi-Region keys
-   cross-account encryption
-   imported key material concepts
-   S3 security
-   EBS/EFS/RDS encryption
-   AWS Backup
-   Secrets Manager
-   Parameter Store
-   ACM
-   Private CA
-   CloudHSM concepts
-   credential rotation

## Skill Builder / AWS hands-on

Use KMS and S3 Builder Labs plus AWS security workshops/material
covering:

-   Secrets Manager
-   encryption on AWS
-   encryption at rest with KMS
-   key-policy troubleshooting
-   cross-account encryption

Build broken scenarios intentionally:

``` text
Application → S3 → KMS → AccessDenied
```

Determine whether the cause is:

-   IAM policy
-   key policy
-   grant
-   resource policy
-   `kms:ViaService`
-   encryption context
-   cross-account authorization

## Portfolio

Implement a protected data architecture for a fictitious regulated
workload.

Include:

-   S3 Block Public Access
-   TLS enforcement
-   SSE-KMS
-   restrictive bucket policies
-   endpoint restrictions where appropriate
-   organization restrictions
-   versioning
-   logging
-   secrets-management patterns
-   encrypted storage

## Suggested allocation

-   Study: 8h
-   Skill Builder/labs: 12h
-   Portfolio: 17h
-   Review/documentation: 3h

**Milestone:** AWS Data Protection Reference Architecture.

------------------------------------------------------------------------

# Week 5 --- Detection Engineering

**40 hours**

## Topics

-   CloudTrail
-   CloudTrail Lake
-   CloudWatch
-   VPC Flow Logs
-   Route 53 logging
-   WAF logging
-   GuardDuty
-   Inspector
-   Macie
-   AWS Config
-   Security Hub
-   Security Lake
-   Detective
-   EventBridge

## Skill Builder / AWS hands-on

Prioritize available getting-started and hands-on material for:

-   Amazon Inspector
-   Amazon Detective
-   AWS Config
-   AWS Security Hub
-   AWS CloudTrail
-   Amazon Security Lake

Use GuardDuty exercises where available.

## Portfolio

Build:

``` text
CloudTrail ─────┐
Config ─────────┤
GuardDuty ──────┤
Inspector ──────┼──► Security Hub
Macie ──────────┤
                │
                ▼
           EventBridge
             │     │
             ▼     ▼
            SNS  Lambda
```

## Detection scenarios

Generate controlled events such as:

-   unauthorized API activity
-   overly permissive security group
-   public storage
-   suspicious IAM behavior
-   unencrypted resource
-   configuration drift

Trace:

``` text
Action
 ↓
Telemetry
 ↓
Detection
 ↓
Finding
 ↓
Aggregation
 ↓
Alert
```

## Suggested allocation

-   Study: 6h
-   Skill Builder/AWS labs: 16h
-   Portfolio: 15h
-   Documentation/questions: 3h

**Milestone:** AWS Detection Engineering Platform.

------------------------------------------------------------------------

# Week 6 --- Incident Response and Security Automation

**40 hours**

## Topics

-   incident-response plans and runbooks
-   forensic preparation
-   event correlation
-   containment
-   eradication
-   recovery
-   evidence preservation
-   CloudTrail investigation
-   snapshots
-   Detective
-   Athena
-   EventBridge
-   Lambda
-   Step Functions
-   Systems Manager
-   automated remediation

## Skill Builder / AWS hands-on

Use relevant material such as:

-   AWS Security Incident Response Overview
-   AWS threat detection and response workshops
-   incident-response labs
-   Lab Maker scenarios where useful

## Portfolio

Build:

``` text
GuardDuty
    ↓
Security Hub
    ↓
EventBridge
    ↓
Step Functions
    ↓
┌───────────────┐
│               │
Lambda         SSM
│               │
└───────┬───────┘
        ↓
Containment
        ↓
Evidence collection
        ↓
Notification
```

Implement at least three playbooks.

### Compromised EC2

``` text
detect
→ quarantine
→ collect metadata
→ snapshot storage
→ preserve logs
→ notify
```

### Compromised IAM credential

``` text
detect
→ identify principal
→ restrict credential
→ retrieve CloudTrail activity
→ identify affected resources
→ notify
```

### Exposed S3

``` text
detect
→ remove exposure
→ preserve evidence
→ investigate prior access
→ notify
```

## Suggested allocation

-   Study: 6h
-   AWS labs/workshops: 12h
-   Portfolio: 19h
-   Documentation: 3h

**Milestone:** Automated AWS Incident Response Platform.

------------------------------------------------------------------------

# Week 7 --- Integration, Cloud Quest, Jam, and DevSecOps

**40 hours**

## Skill Builder / AWS hands-on

Use less-guided exercises now that the individual technologies are
familiar.

Prioritize selected:

-   AWS Cloud Quest security missions
-   AWS Jam security challenges
-   troubleshooting scenarios
-   incident-response challenges
-   Lab Maker integration exercises

Do not complete missions simply for completion. Prioritize scenarios
relevant to IAM, network security, data protection, detection, and
incident response.

## Integrate the portfolio

``` text
AWS Organization
       │
       ├── Governance
       ├── IAM
       ├── Network Security
       ├── Data Protection
       ├── Logging
       ├── Detection
       └── Incident Response
```

## Add secure CI/CD

``` text
GitHub Actions
      │
      │ OIDC
      ▼
AWS deployment role
      │
      ├── Terraform validation
      ├── IaC security checks
      ├── policy-as-code
      ├── secrets scanning
      └── controlled deployment
```

Cover:

-   OIDC federation
-   least-privilege CI/CD roles
-   Terraform state protection
-   IaC security scanning
-   policy-as-code
-   secrets scanning
-   production separation
-   change control

## Suggested allocation

-   Study: 4h
-   Cloud Quest/Jam/labs: 12h
-   Portfolio integration: 21h
-   Documentation: 3h

**Milestone:** Production-Grade AWS Enterprise Security Reference
Architecture.

------------------------------------------------------------------------

# Week 8 --- SCS-C03 Exam Readiness and Portfolio Validation

**40 hours**

## Skill Builder exam preparation

Use the current SCS-C03 Exam Prep Plan and available:

-   Official Practice Question Set
-   Domain Review material
-   Domain Practice
-   AWS SimuLearn
-   Official Practice Exam

Use SimuLearn selectively based on weaknesses rather than completing
material unnecessarily.

## Days 1--2 --- Domain assessment and attack validation

Run controlled portfolio scenarios such as:

-   attempted CloudTrail disabling
-   cross-account privilege escalation
-   forbidden AssumeRole
-   public S3 exposure
-   Internet-exposed SSH
-   unencrypted S3 upload
-   noncompliant resource creation
-   unauthorized KMS access
-   simulated compromised EC2
-   attempted modification of security controls

For each:

``` text
Threat
 ↓
Preventive control
 ↓
Attack/test
 ↓
Telemetry
 ↓
Detection
 ↓
Containment
 ↓
Remediation
 ↓
Evidence
```

## Day 3 --- SimuLearn / targeted remediation

Use practice results to identify weak domains and spend the day only on
those gaps.

## Day 4 --- Official Practice Exam

For every missed question classify the failure:

``` text
Knowledge gap?
AWS architecture misunderstanding?
Service confusion?
Missed requirement?
Poor answer elimination?
```

Perform targeted remediation.

## Day 5 --- Portfolio polish and final review

Finish:

-   architecture diagrams
-   threat model
-   ADRs
-   security-control catalog
-   incident-response documentation
-   deployment instructions
-   cost analysis
-   README
-   safe teardown procedure

Remove:

-   credentials
-   account IDs where unnecessary
-   secrets
-   Terraform state
-   generated files not appropriate for Git
-   sensitive environment information

**Milestone:** Exam-ready + interview-ready portfolio.

------------------------------------------------------------------------

# Weekly Summary

  -----------------------------------------------------------------------------------
  Week              Focus                    Skill Builder/AWS    Portfolio milestone
                                             practice
  ----------------- ------------------------ -------------------- -------------------
  1                 Governance/foundations   IAM, KMS, audit,     Multi-account
                                             governance labs      foundation

  2                 IAM                      Authorization labs   Enterprise IAM
                                                                  architecture

  3                 Infrastructure           VPC, EC2,            Secure
                                             CloudFront, network  network/workloads
                                             labs

  4                 Data protection          KMS, S3,             Data protection
                                             secrets/encryption
                                             labs

  5                 Detection                Config, CloudTrail,  Detection platform
                                             Inspector,
                                             Detective, Security
                                             Hub, Security Lake

  6                 Incident response        IR and               Automated IR
                                             threat-detection
                                             exercises

  7                 Integration              Cloud Quest / Jam /  Enterprise security
                                             integration labs     platform

  8                 Exam/validation          SCS-C03 SimuLearn +  Validated polished
                                             practice exam        portfolio
  -----------------------------------------------------------------------------------

# Documentation Standard

For every significant control, record:

``` text
CONTROL
Prevent modification of centralized CloudTrail.

THREAT
A compromised administrator in a workload account attempts
to disable or impair security telemetry.

ARCHITECTURE
Organization-wide logging is centrally administered and logs
are delivered to a separate Log Archive account.

PREVENTIVE CONTROL
Organizational guardrails and restrictive resource policies.

DETECTIVE CONTROL
CloudTrail, Config, Security Hub, or other monitoring.

VALIDATION
Attempt the prohibited action.

EVIDENCE
Capture the denial, finding, and relevant telemetry.

RESIDUAL RISK
Explain what the control does not prevent.
```

# Primary Resources

-   AWS Certified Security -- Specialty\
    https://aws.amazon.com/certification/certified-security-specialty/

-   AWS Security training\
    https://aws.amazon.com/training/learn-about/security/

-   AWS Security Reference Architecture\
    https://docs.aws.amazon.com/prescriptive-guidance/latest/security-reference-architecture/

-   AWS Well-Architected Security Pillar\
    https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/

-   AWS Security Ramp-Up Guide information\
    https://aws.amazon.com/blogs/security/updated-aws-ramp-up-guide-available-for-security-identity-and-compliance/

-   AWS Skill Builder\
    https://skillbuilder.aws/

# Expected Outcome

At the end of approximately **320 focused hours**, you should have:

## Certification readiness

-   SCS-C03 domain knowledge
-   practical experience with AWS security services
-   troubleshooting repetitions
-   official practice-assessment experience

## Portfolio evidence

-   multi-account governance
-   enterprise IAM
-   secure AWS networking
-   data protection and KMS
-   centralized logging
-   detection engineering
-   automated incident response
-   Terraform
-   secure CI/CD
-   threat modeling
-   architecture diagrams
-   attack and validation scenarios
-   documented security decisions

The portfolio should demonstrate the complete engineering cycle:

``` text
Security requirement
        ↓
Architecture
        ↓
Terraform implementation
        ↓
AWS control
        ↓
Attack / failure test
        ↓
Telemetry
        ↓
Detection
        ↓
Response
        ↓
Evidence
```

## Recommended résumé framing after completion

> Designed and implemented a Terraform-based multi-account AWS security
> reference architecture covering organizational governance,
> least-privilege IAM, network segmentation, KMS-based data protection,
> centralized security telemetry, GuardDuty/Security Hub detection, and
> event-driven incident-response automation; validated controls through
> documented attack and failure scenarios.

## Timing recommendation

Begin professional networking and recruiter outreach around **Weeks
5--6** rather than waiting until the entire program is finished. By that
point, the governance, IAM, infrastructure, data-protection, and
detection portions of the portfolio should already provide substantial
evidence of hands-on AWS security engineering capability.
