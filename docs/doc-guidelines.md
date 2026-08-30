# Documentation Guidelines

This document summarizes the documentation rules and principles used throughout
this repository, especially for AWS security labs and technical exercises.

## Structure and consistency

- Provide a clear introduction for each lab or exercise.
- Explain the purpose, learning objectives, threat or failure mode, and expected outcomes.
- Organize procedures into explicit sections with descriptive headings.
- Include a table of contents in every exercise instruction document, with links to the document's major sections and relevant subsections.
- Keep the table of contents synchronized with the headings and section order.
- Keep related documentation consistently structured across exercises.
- Provide a `References` section with authoritative AWS documentation links.
- Keep links relative and accurate when referring to repository files.
- Whenever the reader is directed to inspect, read, or use a repository file or directory, provide a direct Markdown link to that file or directory.
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

## Bash and Terraform command generation

- Write command snippets as valid Bash that can be copied and executed without manual repair.
- Use one backslash at the end of a Bash line only when continuing one command onto the next line.
- Never generate two consecutive backslash characters for shell line continuation; they escape each other and can cause the command to be parsed incorrectly.
- Keep short commands on one line when line continuation does not improve readability.
- Prefer a single-line copy command for simple source-and-destination operations, such as `cp path/.env.example path/.env`.
- Keep each continued option on its own line and place the continuation backslash immediately after the preceding command text, with no trailing characters after it.
- Ensure shell variable expansion is intentional: quote values when paths or values may contain whitespace, and document any project convention that requires an unquoted expansion.
- Use consistent variable names between command snippets and the documented environment configuration.
- When displaying Terraform outputs, prefer a labeled `echo` with `terraform output -raw` rather than assigning values solely for display or using `printf`.
- Use command substitution carefully and verify that nested quoting remains valid Bash, for example: `echo "role_arn: $(terraform -chdir=$EXERCISE_ROOT output -raw role_arn)"`.
- Do not include passwords, access keys, MFA secrets, tokens, or other credentials in command examples.
- Validate generated command blocks syntactically when practical and search for accidental duplicate continuation characters before finalizing documentation.
- Do not include redundant Terraform formatting commands in exercise execution instructions when formatting is already handled by the repository workflow; omit standalone `terraform ... fmt` and `terraform ... fmt -check` commands from those procedural snippets.

Example of valid multiline Bash:

```bash
terraform -chdir=$EXERCISE_ROOT init \
  -backend-config="bucket=$TF_STATE_BUCKET" \
  -backend-config="region=$TF_STATE_REGION" \
  -backend-config="profile=$TF_STATE_PROFILE"
```

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
- For every policy excerpt, explain the intended principal or role association, the operations it is intended to allow, the operations or principals it is intended to deny or exclude, the resources or conditions it is intended to limit, and its weak points or residual escalation paths.
- For every trust-policy excerpt, explicitly identify the principals it trusts, the principals it intentionally distrusts or excludes, the assume-role action being authorized, and the consequences of broad versus specific trust.
- For every permissions-boundary excerpt, explain which identity permissions it caps, which actions or resources are outside the ceiling, and why the boundary does not grant access by itself.

### Permissions-boundary excerpts

- Include a permissions-boundary excerpt whenever the documentation mentions or relies on a permissions boundary.
- Take the excerpt from the authoritative policy JSON file or JSON template that declares the boundary; do not reconstruct it from memory or paraphrase the policy as if it were authoritative.
- Link directly to the source policy declaration next to the excerpt.
- Preserve the original JSON statement identifiers, effects, actions, resources, and conditions in the excerpt.
- If the source is a template, retain its interpolation variables and explain how they are rendered; do not silently replace template expressions with example values.
- Label shortened content explicitly as an excerpt and link readers to the complete policy.
- Explain the boundary's role as a maximum-permissions ceiling rather than a permission grant.
- Explain which identity policy, trust policy, resource policy, SCP, session policy, or explicit deny must also be considered.
- Identify the Terraform root or system that owns the boundary and distinguish read-only references from managed ownership.
- Do not instruct readers to edit, import, replace, or destroy a boundary owned by another configuration.

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

### Happy- and unhappy-path tests

Every exercise must provide executable tests for both positive and negative
outcomes. An exercise is not complete unless it includes both:

- A **happy-path (positive) test** in which the intended principal, request
  context, resource, configuration, and policy conditions are correct and the
  operation is expected to succeed.
- An **unhappy-path (negative) test** in which an unauthorized principal,
  missing or incorrect context value, out-of-scope resource, invalid
  configuration, or other deliberately incorrect condition causes the
  operation to be denied or rejected as designed.

This requirement applies to every exercise, not only exercises whose primary
topic is IAM authorization. For detection, validation, governance, and other
security exercises, define the equivalent positive and negative outcomes—for
example, an intended finding is detected while an in-scope configuration does
not produce that finding, or a valid policy passes validation while an invalid
policy is rejected.

Label these tests explicitly, state the expected result before each command,
and provide copyable commands whenever the operation can be tested safely. The
happy path must verify the specific protected operation rather than an
unrelated health check. The unhappy path should change one authorization factor
at a time while keeping the caller, target, and operation constant where
practical, so the denial can be attributed to the control under study.

Denied or rejected tests must distinguish the expected security-control outcome
from an expired login, wrong account or Region, malformed resource identifier,
missing resource, network failure, tool failure, or other unrelated error. A
command that fails for the wrong reason is not a successful negative test.
Negative-test snippets should report an unexpected success clearly and must not
print or persist temporary credentials if the operation unexpectedly succeeds.

For every test, document:

- The principal and account used.
- The operation and target resource.
- The policy or request-context difference being tested.
- The predicted result.
- The actual result and command exit status where relevant.
- The expected AWS error code, validation result, finding state, or equivalent
  negative outcome.
- The CloudTrail event ID or other evidence when available.
- The policy layer that explains the result.

If a realistic happy-path operation would be destructive, costly, or unsafe,
use the narrowest safe equivalent and explain the limitation. Do not weaken a
security control merely to make a test pass.

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

## Required exercise documentation sections

Every exercise instruction document must include the following sections.

### Evidence and security analysis

The **Evidence and security analysis** section is primarily a synthesis of the
exercise's learnings and the observations relevant to the topics it covers. It
must go beyond listing commands or attaching raw evidence. It should:

- Summarize the security objective and the authorization behavior demonstrated.
- Compare the predicted and actual results for the important positive and negative tests.
- Identify the principals, resources, policies, conditions, and policy layers that determined each result.
- Explain the relevant authorization decision using AWS policy-evaluation concepts.
- Correlate CloudTrail or other retained evidence with the observed behavior.
- Describe what an attacker, misconfigured identity, or incorrectly trusted principal could do if the tested control were absent or weakened.
- Identify assumptions, environmental dependencies, and limitations of the exercise.
- Document residual risk and practical production hardening recommendations.
- Distinguish an exercise observation, such as unused access during a short observation window, from a conclusion that access is never required.

#### AWS CLI evidence collection

Every **Evidence and security analysis** section must provide contextual AWS CLI
commands that let the reader independently retrieve the configuration and logs
that explain every positive and negative test. Do not provide one generic
command set unrelated to the exercise's actual API calls and resources.

For each conducted test, include commands that retrieve:

- The exact principal, role, resource, policy, trust relationship, permissions
  boundary, session policy, SCP, resource policy, tags, condition values, and
  other configuration that influenced the decision, as applicable.
- The active policy document and policy version rather than only a policy name.
- The principal and resource attributes evaluated by ABAC or other contextual
  conditions, including each value that matched or differed.
- CloudTrail management events, data events, service logs, validation findings,
  analyzer findings, configuration history, or other telemetry that records the
  operation and its outcome.
- Stable identifiers needed to correlate evidence, including event ID, request
  ID, query ID, timestamp, account ID, Region, principal ARN, session name,
  resource ARN, action, error code, and error message when available.

For every command:

- Give the command its own descriptive subsection under **Evidence and security
  analysis**. Do not group unrelated commands into one undifferentiated code
  block.
- Put the command and its explanation in the same subsection. The explanation
  must immediately follow the command and identify the fields, values, and
  security conclusion the reader should inspect.
- State its purpose before the command.
- Explain which output fields and expected values the reader must examine after
  the command.
- Tie those fields to a specific happy or unhappy path and explain how they
  support the authorization or security conclusion.
- Use exact exercise role names, policy names, statement IDs, tag keys, object
  keys, resource paths, ARN suffixes, API event names, and Terraform outputs.
- Explain how to distinguish the intended event or resource from unrelated
  activity with a similar name.
- Use a profile authorized only for the required evidence operation. If the
  exercise persona cannot query centralized evidence, name a separate approved
  evidence profile variable instead of silently assuming broader permissions.
- Avoid printing or persisting access keys, secret keys, session tokens, OIDC
  tokens, passwords, or other credentials.

Evidence procedures should begin by loading exact resource identifiers from
Terraform outputs or service APIs. Do not rely on copied example account IDs,
manually reconstructed ARNs, or stale resource names when an authoritative
command can retrieve them.

When an exercise uses the shared evidence bucket, its instructions must include
every command required to retrieve the evidence: load the bucket and
organization identifiers, determine the account-level prefix, list or select
the delivered Region/date directory, download the relevant log objects, filter
records for the exact principal, action, resource, and test outcome, and remove
local copies afterward. A reference to
[`cloud-trail-logs.md`](cloud-trail-logs.md) may provide architecture and
troubleshooting context, but it must not replace executable, exercise-specific
commands.

Apply this command-by-command structure consistently to every exercise that has
resource or log evidence, including later exercises. If a later exercise is
only a scaffold and has no implemented fixture or authoritative resource
identifiers, say so explicitly rather than inventing commands or claiming that
generic evidence is exercise-specific.

When retrieving IAM configuration:

- Use commands such as `get-role`, `get-role-policy`, `get-policy`, and
  `get-policy-version` as appropriate.
- Retrieve role tags, trust-policy principals and conditions, boundary ARNs,
  inline policy statements, managed-policy versions, and relevant identity or
  resource-policy conditions.
- Explain which policy is a grant, which is a maximum ceiling, which establishes
  trust, and which condition caused the positive or negative outcome.

When retrieving resource configuration:

- Query the exact authorization-relevant settings, such as object or resource
  tags, encryption state, public-access controls, network rules, ownership,
  versioning, or logging configuration.
- Provide separate commands or clearly separated output for each resource used
  by the positive and negative tests.
- State the expected differences between those resources and hold unrelated
  request factors constant where practical.

When retrieving logs and findings:

- Query the exact API event names generated by the tests and filter by the
  exercise principal, role session, resource, account, Region, and test time
  window.
- Explain the expected successful outcome, such as an absent `errorCode` and an
  expected response resource, and the expected negative outcome, such as
  `AccessDenied`, a validation error, or a security finding.
- Distinguish CloudTrail management events from data events. Do not use
  `lookup-events` for S3 object access, Lambda invocation, or other data events
  that require configured data-event collection.
- Verify a trail's event selectors, an event data store's advanced selectors,
  analyzer scope, log-group retention, or equivalent evidence coverage before
  claiming that a missing event proves anything.
- Account for asynchronous evidence systems. Provide bounded polling or status
  commands for CloudTrail Lake queries, Access Analyzer findings, Config
  evaluations, or similar operations instead of assuming immediate completion.
- Retrieve final query or finding results and identify the fields that prove
  which test succeeded or failed.
- Document a telemetry gap when the required collection was not enabled before
  the test. Do not retroactively claim evidence, and do not change organization
  trails, centralized stores, or retention settings without approval.

Conclude with a correlation table or equivalent structured analysis containing
one row per test. It should compare principal attributes, resource attributes,
request context, predicted CLI outcome, actual CLI outcome, log or finding
outcome, stable evidence ID, and the determining policy or control layer.
Commands that fail because of expired authentication, wrong account or Region,
missing resources, malformed input, insufficient evidence-query permission, or
network errors are not valid proof of the intended security-control outcome.

The section should provide enough context for a reader to understand not only
what happened, but why it happened and what the result means for a production
security design.

### References

Every exercise instruction document must include a **References** section. It
should contain links to relevant online documentation for the concepts,
services, commands, and security controls used by the exercise. AWS
documentation should be included where applicable, but references are not
limited to AWS. Appropriate sources may include:

- AWS service documentation and service-authorization references.
- AWS API, CLI, IAM policy-evaluation, and security-best-practice documentation.
- Official documentation for external identity providers, CI/CD systems, or other integrated services.
- Official Terraform provider or module documentation when Terraform behavior is relevant.
- Maintainer documentation for security tools used by the exercise.
- Repository documentation that defines local architecture, ownership, authentication, or operational procedures.

References should be specific to the exercise rather than a generic list. Link
to the authoritative source for each significant service or security concept,
and ensure that repository links remain valid when files or directories move.

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

Include an **Investigating in the Console** section whenever console inspection
can help explain the exercise. The section must be exercise-specific and
procedural; do not use vague directions such as "inspect the relevant policy"
or "look in CloudTrail."

### Session and navigation

- State the exact AWS account and IAM Identity Center permission set or other
  approved session to use.
- Require the reader to verify the account ID and Region before inspecting
  resources.
- Provide the complete console navigation path, such as **IAM → Access
  management → Roles**, **S3 → Buckets**, or **CloudTrail → Event history**.
- Explain how to locate dynamically named resources. Prefer an exact Terraform
  output command, ARN suffix, resource path, tag, or deterministic name rather
  than asking the reader to browse an unfiltered list.
- Use an approved inspection or read-only session when the deliberately narrow
  exercise role lacks console list permissions. Warn about that limitation and
  do not broaden the exercise policy merely to make console navigation work.

### Resource and policy inspection

- Name every exercise resource, role, inline policy, managed policy, permission
  set, boundary, tag key, condition key, and policy statement that the reader
  must inspect.
- Provide the most significant identifying portion of each ARN, such as the
  account, path, policy name, role name, or resource-name prefix. Explain how
  the reader can distinguish it from similarly named or AWS-managed resources.
- Identify the exact console tab, field, or JSON element to examine—for example,
  **Permissions**, **Trust relationships**, **Permissions boundary**,
  `Principal.AWS`, `Action`, `Resource`, `Condition`, or a statement `Sid`.
- State the expected value and explain its security purpose. For tags used by
  ABAC, identify the principal and resource tag keys, their expected values,
  the condition comparing them, and which happy- and unhappy-path combinations
  should allow or deny access.
- Distinguish identity policies, trust policies, resource policies, permissions
  boundaries, session policies, and SCPs. Explain what decision each inspected
  policy contributes and what it does not grant by itself.
- If encryption, public-access controls, versioning, logging, network controls,
  or other resource settings matter to the exercise, identify the exact console
  section and expected state rather than saying only to inspect security
  settings.

### SCP inspection

When SCP inspection is relevant:

- State whether the exercise creates an SCP or only inherits existing
  organization and Control Tower policies.
- Name each known exercise-owned SCP exactly. For pre-existing or generated
  SCPs whose names vary by environment, direct the reader to the target
  account's **Service control policies** view and identify the exact account,
  OU, parent OU, and organization-root inheritance levels to inspect. Do not
  invent a stable SCP name when AWS or Control Tower generates it dynamically.
- Tell the reader which displayed policies matter, such as `FullAWSAccess`, an
  exercise-specific SCP, or Control Tower preventive-control SCPs. Explain the
  purpose of each known policy.
- Identify the actions, effects, resources, and conditions to search for. For
  example, instruct the reader to find `Effect: "Deny"` with `s3:GetObject`,
  `s3:*`, or `Action: "*"`, and explain how that statement would affect the
  tested request.
- Require the reader to record the actual policy name and attachment or
  inheritance source. Do not instruct them to modify organization or Control
  Tower policies merely to complete an exercise unless that mutation is the
  explicitly approved scenario.

### CloudTrail investigation

CloudTrail steps must correspond to the API calls made by the exercise's
positive and negative tests:

- Give the exact console path to **CloudTrail → Event history**, **CloudTrail →
  Lake → Query**, a trail's S3 log destination, or another approved evidence
  view.
- Name every API event to search for, such as `AssumeRole`, `CreateRole`, or
  `PutObject`, and provide the appropriate lookup attribute or query filter.
- Explain how to select the exercise event using concrete fields such as
  `eventSource`, `eventName`, `eventTime`, `userIdentity.arn`,
  `requestParameters.roleArn`, `requestParameters.roleSessionName`, resource
  ARN, bucket name, object key, `errorCode`, and `errorMessage`.
- State the expected evidence for each happy and unhappy path. A successful
  event should have the expected response identity or resource and no error
  code; an expected denial should identify the same intended caller and target
  while showing the relevant authorization error.
- Distinguish CloudTrail management events from data events. Do not claim that
  S3 object, Lambda invocation, or other data events appear in standard Event
  history when they require an enabled data-event selector or event data store.
- Tell the reader how to verify that the required trail selector or CloudTrail
  Lake event data store covered the resource before the test. If collection was
  not enabled, require the reader to document the telemetry gap rather than
  infer an event or change an organization trail without approval.
- Correlate console evidence with the CLI result and policy evaluation. A
  missing event or an unrelated authentication, configuration, Region, or
  network failure is not proof that the tested control denied the request.
- Keep evidence redacted and do not copy credentials, session tokens, or other
  sensitive response fields into exercise documentation.

## Markdown formatting

- Use descriptive headings and consistent capitalization.
- Include tables where they clarify roles, accounts, expected results, or responsibilities.
- Bullet statements should start with a capital letter and end with a period.
- Leave bullets unchanged when they begin with a variable or when their first word is enclosed in quotes or backticks.
- Keep code blocks unchanged and distinguish commands from explanatory text.
- Avoid stale references to removed files or outdated workflows.
- Run Markdown hygiene checks such as `git diff --check` before finalizing changes.
