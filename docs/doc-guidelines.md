# Documentation Guidelines

This document summarizes the documentation rules and principles used throughout
this repository, especially for AWS security labs and technical exercises.

## Structure and consistency

- Provide a clear introduction for each lab or exercise.
- Explain the purpose, learning objectives, threat or failure mode, and expected outcomes.
- Organize procedures into explicit sections with descriptive headings.
- Include a table of contents for substantial documents.
- Keep related documentation consistently structured across exercises.
- Provide a `References` section with authoritative AWS documentation links.
- Keep links relative and accurate when referring to repository files.
- Use consistent terminology for source and target accounts, trusted and trusting accounts, IAM Identity Center users and permission sets, provisioned `AWSReservedSSO_*` roles, IAM role sessions, permissions boundaries, identity policies, and trust policies.

## Authentication and identity handling

- Human access uses IAM Identity Center rather than long-lived IAM user keys.
- Document user enablement, including verification email, password setup or reset, and MFA registration and verification.
- Recommend a password manager for managing separate identity passwords.
- Never place passwords, MFA secrets, access keys, tokens, device codes, or copied temporary credentials in Markdown files, `.env` files, Terraform variables, AWS CLI configuration, shell scripts, Terraform state, or repository evidence.
- Explain browser-session reuse risks when multiple users share a workstation.
- Use `--use-device-code --no-browser` where appropriate.
- Recommend separate browser contexts or browsers for different identities.
- Verify every authenticated session with `aws sts get-caller-identity`.
- Refer to `sso_auth.md` for centralized SSO, MFA, browser, and CLI guidance.
- Refer to the relevant exercise-specific profile instructions when discussing test users and role profiles.

## Environment configuration

- Use `.env.example` as the configuration template.
- Instruct users to copy it to `.env` and replace placeholders or desired values.
- Keep `.env` uncommitted.
- Source the global environment before the exercise-specific environment:

  ```bash
  source ~/.env/aws-security/terraform/.env
  source terraform/<lab-or-exercise-directory>/.env
  ```

- Explain that the global environment must be sourced first when exercise files reference shared environment variables.
- Avoid using removed `terraform.tfvars.example` files as part of the documented workflow.
- Keep environment-variable names consistent with the Terraform variable declarations.

## Terraform and ownership

- Treat each exercise as an independent Terraform root with independent state.
- Use separate backend keys for separate exercises.
- Explain the exact Terraform configuration directory for each exercise.
- Use provider account safeguards such as `allowed_account_ids`.
- Validate account IDs, profiles, and other security-sensitive inputs.
- Avoid managing existing Control Tower or IAM Identity Center resources unless ownership is explicit.
- Read shared resources as data sources when they are owned by another Terraform root.
- Clearly identify persistent versus disposable resources.
- Never instruct an exercise to destroy persistent baselines, shared governance resources, Identity Center-provisioned roles, or resources belonging to another exercise.
- Require users to review plans before applying or destroying resources.
- Stop when plans contain unexplained replacements, deletions, or resource adoption.

## Policy explanations

Include excerpts for important:

- Identity policies.
- Trust policies.
- Resource policies.
- Permissions boundaries.
- Terraform resource definitions.

Explain what each policy answers:

- Identity policy: What may this principal request?
- Trust policy: Who may assume or become this role?
- Resource policy: Which principals may access this resource?
- Permissions boundary: What is the maximum permission ceiling?
- SCP: What maximum permissions are available to member-account principals?

Additional principles:

- Explicitly distinguish an Allow from effective authorization.
- Explain that a permissions boundary does not grant permissions by itself.
- Explain that explicit denies override allows.
- Avoid treating role names, paths, or tags as security controls by themselves.
- Document AWS resource-scoping limitations where relevant.
- Explain residual escalation paths and compensating controls.

## Exercise methodology

Each exercise should follow the same investigative lifecycle:

```text
Understand the scenario
  → Predict the authorization decision
  → Deploy the smallest disposable fixture
  → Run positive and negative tests
  → Capture CloudTrail evidence
  → Explain the effective policy evaluation
  → Apply the smallest correction, if applicable
  → Re-test
  → Clean up only disposable resources
```

Documentation should identify:

- Security objective.
- Threat or failure mode.
- Identities involved.
- Resources involved.
- Relevant identity policies.
- Trust or resource policies.
- SCPs, boundaries, and session policies.
- Expected result.
- Actual result.
- CloudTrail evidence.
- Policy layer responsible for the result.
- Residual risk.
- Production hardening recommendations.

## Exercise writing guidelines

Exercise documentation should be written as a learning path, not merely as a
resource-deployment checklist. Each exercise should force the learner to
predict an authorization result, test both an allowed and a denied operation,
collect evidence, and explain the effective policy evaluation.

### Curriculum classification

- Mark each exercise as either `[Core]` or `[Optional]` in its level-one title when the curriculum uses those classifications.
- Keep the classification in the exercise documentation and Terraform configuration aligned.
- Record the classification in Terraform metadata, such as a `Curriculum` tag and a source comment, when appropriate.
- Maintain a curriculum classification table in the relevant summary document.
- Provide an exercise-links section after the curriculum classification section, with `[Core]` or `[Optional]` included in every link label.
- Use `[Core]` for concepts required by the primary learning path.
- Use `[Optional]` for extensions, overlapping demonstrations, slower operational scenarios, or topics that can be covered inside another exercise.

### Avoiding unnecessary duplication

- Combine closely related exercises when they test the same principle from only slightly different angles.
- Treat a detailed demonstration and its troubleshooting variant as complementary parts of one coherent lab when that is clearer for learners.
- Treat a foundational exercise and its increased-complexity extension as one progression when they share the same setup and learning objective.
- Keep exercises distinct when they teach different identity models, policy layers, or operational responsibilities.
- Prefer a smaller number of complete, coherent labs over many incomplete resource fixtures.

### Exercise implementation alignment

The Terraform root must implement the scenario described by the documentation.
Before considering an exercise complete, verify that:

- The resources, policies, trust relationships, conditions, and boundaries in Terraform are the ones described in the guide.
- Every documented positive and negative test can be performed against the resources Terraform creates.
- Example outputs and profile names correspond to actual Terraform outputs and AWS CLI configuration.
- The Terraform state owns only the disposable resources assigned to that exercise.
- Persistent baselines and shared governance resources remain outside the exercise state.
- A dry-run plan contains no unrelated account, Control Tower, Organizations, or Identity Center changes.
- The exercise can be repeated safely after its disposable resources are destroyed.

### Recommended exercise progression

A focused learning progression is:

```text
Cross-account access
  → Trust hardening
  → Contextual trust conditions and confused-deputy prevention
  → Delegated administration and permissions boundaries
  → ABAC and tag governance
  → Native AWS workload identity
  → OIDC workload federation
  → Policy validation
  → Authorization troubleshooting capstone
```

Optional exercises should extend this path without introducing a new mandatory
prerequisite unless that dependency is explicitly documented.

## Diagrams and evidence

- Use Mermaid diagrams where they clarify identity flows, cross-account role chains, policy evaluation, trust relationships, federation flows, or state transitions.
- Include CLI commands that demonstrate both allowed and denied operations.
- Include `get-caller-identity` examples for relevant profiles.
- Explain the expected account, role, and session result.
- Use CloudTrail to identify the calling principal, requested role or resource, session name, event time and event ID, source IP where relevant, resulting assumed-role ARN, and likely policy layer involved.
- Keep evidence redacted and out of version control when it contains sensitive data.

## Console investigation

- Include an **Investigating in the Console** section for exercises where console inspection is useful.
- Explain which account and permission-set session should be used.
- Verify account IDs before inspecting resources.
- Identify the exact IAM roles, policies, permissions boundaries, tags, and resource policies to inspect.
- Warn that console pages may require broad list permissions not granted to a deliberately narrow exercise role.
- Do not broaden policies merely to make console pages work.
- Use the CLI, CloudTrail, direct resource views, or an approved read-only session where necessary.

## Markdown formatting

- Use descriptive headings and consistent capitalization.
- Include tables where they clarify roles, accounts, expected results, or responsibilities.
- Bullet statements should start with a capital letter and end with a period.
- Leave bullets unchanged when they begin with a variable or when their first word is enclosed in quotes or backticks.
- Keep code blocks unchanged and distinguish commands from explanatory text.
- Avoid stale references to removed files or outdated workflows.
- Run Markdown hygiene checks such as `git diff --check` before finalizing changes.
