# Account Factory for Terraform Setup

## Purpose

This document describes the source-control repositories required by AWS Control Tower Account Factory for Terraform (AFT), when they must exist, and the responsibility of each repository.

AFT uses source control as its operational interface. The repositories described here are inputs to the AFT platform; they are separate from this landing-zone repository unless the architecture is explicitly changed to combine them in a supported layout.

For an overview of AFT, see [Account Factory for Terraform overview](https://docs.aws.amazon.com/controltower/latest/userguide/aft-overview.html).

## Deployment Sequence

The four AFT repositories are not required when creating the AFT OU or the AFT management account.

The intended sequence is:

```text
1. terraform/aft/org_unit
   └── Create the dedicated AFT OU and enable its Control Tower baseline

2. terraform/aft/account
   └── Provision and enroll the AFT management account through Account Factory

3. Source-control preparation
   ├── Create and initialize the four AFT repositories
   ├── Create their configured default branch
   └── Configure and authorize the VCS connection

4. terraform/aft/platform
   └── Deploy the AFT platform, pipelines, and repository integrations
```

The repositories should exist and be accessible before applying `terraform/aft/platform`. Creating the OU and AFT management account does not depend on them.

AFT deployment prerequisites are documented in [Deploy AWS Control Tower Account Factory for Terraform](https://docs.aws.amazon.com/controltower/latest/userguide/aft-getting-started.html).

## Repository Names

The AFT platform root currently accepts four repository variables:

```text
account_request_repo_name

global_customizations_repo_name

account_customizations_repo_name

account_provisioning_customizations_repo_name
```

When `vcs_provider` is `github`, repository values use the following format:

```text
GitHub-owner/repository-name
```

For example:

```bash
export TF_VAR_account_request_repo_name="example-organization/aft-account-request"
export TF_VAR_global_customizations_repo_name="example-organization/aft-global-customizations"
export TF_VAR_account_customizations_repo_name="example-organization/aft-account-customizations"
export TF_VAR_account_provisioning_customizations_repo_name="example-organization/aft-account-provisioning-customizations"
```

Repository names are project-specific and cannot be discovered safely from AWS. They must be configured explicitly before deploying the AFT platform.

## Account Request Repository

Terraform variable:

```text
account_request_repo_name
```

Suggested repository name:

```text
aft-account-request
```

The account request repository is the normal account-vending interface after AFT becomes operational. Changes committed to this repository initiate requests to create or update AFT-managed AWS accounts.

An account request typically defines:

- Account name;.
- Unique account email address;.
- Target governed OU;.
- IAM Identity Center account-owner information;.
- Account tags;.
- Change-management metadata;.
- Custom fields used by organizational workflows;.
- The optional named account customization to apply.

Conceptually:

```text
Pull request and reviewed account request
  ↓
AFT account-request pipeline
  ↓
Control Tower Account Factory workflow
  ↓
New or updated governed AWS account
```

This repository should be subject to pull-request review, branch protection, and ownership controls because changes can result in AWS account provisioning or updates.

See:

- [AFT account provisioning](https://docs.aws.amazon.com/controltower/latest/userguide/aft-provision-account.html).
- [AFT account request Terraform file](https://docs.aws.amazon.com/controltower/latest/userguide/aft-account-request.html).
- [Update an AFT-provisioned account](https://docs.aws.amazon.com/controltower/latest/userguide/aft-update-account.html).

## Global Customizations Repository

Terraform variable:

```text
global_customizations_repo_name
```

Suggested repository name:

```text
aft-global-customizations
```

The global customizations repository contains configuration applied to every account managed by AFT. It establishes organization-wide settings that are not already owned by Control Tower or another centralized service.

Appropriate examples include:

- Baseline IAM roles required by organizational automation;.
- Organization-wide security integrations;.
- Standard account metadata or tagging support;.
- Common monitoring integrations;.
- Shared automation prerequisites.

Global customizations must not recreate or take ownership of Control Tower-managed resources such as mandatory Control Tower roles, AWS Config resources, or centralized logging resources.

Because every AFT-managed account can receive these customizations, changes require broad impact review and staged validation.

See [Apply global customizations](https://docs.aws.amazon.com/controltower/latest/userguide/aft-global-customizations.html).

## Account Customizations Repository

Terraform variable:

```text
account_customizations_repo_name
```

Suggested repository name:

```text
aft-account-customizations
```

The account customizations repository contains named customization packages. An account request selects a package through its account customization name, allowing configuration to differ by account purpose.

Example customization names include:

```text
network
security
workload
sandbox
```

Appropriate examples include:

- Roles and integrations required only by network accounts;.
- Additional controls for security accounts;.
- Workload-account security configuration;.
- Restrictions or cost controls for sandbox accounts;.
- Account-type-specific integration resources.

These customizations configure accounts; they are not the normal deployment mechanism for application infrastructure. Application resources should remain in application-specific Terraform roots and pipelines.

See:

- [AFT account customization options](https://docs.aws.amazon.com/controltower/latest/userguide/aft-account-customization-options.html).
- [Create account customizations](https://docs.aws.amazon.com/controltower/latest/userguide/aft-account-customizations.html).

## Account Provisioning Customizations Repository

Terraform variable:

```text
account_provisioning_customizations_repo_name
```

Suggested repository name:

```text
aft-account-provisioning-customizations
```

The account provisioning customizations repository extends the account-provisioning workflow. It is intended for logic that must run around account provisioning rather than ordinary Terraform configuration applied inside an account.

AFT supports provisioning-framework stages that can run before and after its account-provisioning API helper. Appropriate examples include:

- Validating account-request metadata;.
- Integrating with an IT service management or approval system;.
- Reserving or retrieving data from an external IP address management system;.
- Enriching requests with organizational metadata;.
- Registering a newly provisioned account with an external system;.
- Invoking approved custom APIs during the provisioning lifecycle.

Provisioning customizations should be deterministic, auditable, and safe to retry. External input must be validated, and credentials must be obtained through roles or managed secret mechanisms rather than committed to source control.

See [AFT provisioning customizations](https://docs.aws.amazon.com/controltower/latest/userguide/aft-provisioning-framework.html).

## Repository Separation

AFT is designed around four repository inputs and separate pipeline responsibilities. Use four distinct repositories unless the deployed AFT module version and selected VCS provider explicitly document support for another arrangement.

Separation provides:

- Independent permissions and branch protections;.
- Clearer ownership between account vending and customization teams;.
- Smaller review scopes;.
- Distinct pipeline triggers;.
- Reduced risk that a customization change accidentally submits an account request;.
- Auditable change histories for each responsibility.

These repositories may initially contain minimal valid AFT structures. They do not need complete production customization content before the AFT OU and account are created.

## VCS Connection and Authorization

Creating repositories is not sufficient by itself. AFT must have an AWS CodeConnections connection, a human must authorize the provider handshake, and the AWS Connector for GitHub App must be installed for the repository owner with access to the required repositories.

User authorization and App installation are separate GitHub operations:

```text
Authorized GitHub App
  → records the human user's authorization of the AWS provider handshake

Installed GitHub App
  → grants the AWS Connector installation access to selected repositories
```

Seeing AWS Connector for GitHub under **Authorized GitHub Apps** does not prove that the App is installed or that repository access is restricted correctly.

### Before platform deployment

Before applying `terraform/aft/platform`, verify that:

- All four repositories exist;.
- Each repository contains the branch specified by `repository_branch`, currently `main` by default;.
- Repository names use `owner/repository` format for GitHub;.
- Repository policies permit the intended AFT access;.
- No credentials or tokens are committed to a repository;.
- `AFTPlatformAdministration` is assigned to the named human administrator in the AFT management account.

The AFT module creates the CodeConnections resource during platform deployment. Therefore, the connection cannot be fully authorized before the platform root creates it.

### Authorize the AWS connection

After platform deployment:

1. Sign in through IAM Identity Center to the AFT management account using `AFTPlatformAdministration`.
2. In the Control Tower home Region, currently `us-east-2`, open **Developer Tools → Settings → Connections**.
3. Select the AFT-created connection, normally `ct-aft-github-connection`.
4. Complete the pending GitHub authorization workflow.
5. Verify that the connection becomes `AVAILABLE` after authorization and installation are complete.

The permission set includes the AWS-documented browser-handshake permissions such as `StartOAuthHandshake`, `GetInstallationUrl`, `ListInstallationTargets`, and `UpdateConnectionInstallation`.

### Install and restrict AWS Connector for GitHub

If AWS Connector for GitHub is not already installed for the GitHub account or organization that owns the AFT repositories, open:

```text
https://github.com/apps/aws-connector-for-github
```

Choose **Install**, select the GitHub account or organization that owns the AFT repositories, and set repository access to **Only select repositories**. Select exactly:

```text
aws-security-aft-account-request
aws-security-aft-global-customizations
aws-security-aft-account-customizations
aws-security-aft-account-provisioning-customizations
```

Complete the installation. Do not select **All repositories** unless another reviewed integration explicitly requires it.

The installation can subsequently be reviewed or modified at:

```text
https://github.com/settings/installations
```

The entry under **Authorized GitHub Apps** records user authorization and does not provide the authoritative repository-selection boundary. Repository selection is managed by the installed GitHub App.

A GitHub App installation can be shared by multiple AWS connections. Before narrowing an existing installation, verify that no other approved connection depends on additional repositories. A dedicated installation limited to the four AFT repositories provides the clearest boundary for this project.

### Post-authorization verification

After installation and authorization:

- Verify `ct-aft-github-connection` remains `AVAILABLE`;.
- Inspect every AFT CodePipeline source stage;.
- Confirm each source references one of the four expected repositories and the `main` branch;.
- Retry source stages that failed while the connection was `PENDING`;.
- Verify no unrelated repository is available to the GitHub App installation;.
- Keep all repositories private unless public access is explicitly required;.
- Protect `main`, require pull requests and review, and enable secret scanning;.
- Do not create manual webhooks, deploy keys, personal access tokens, or stored AWS credentials for this integration.

The effective repository boundary is the intersection of:

```text
GitHub App installation repository selection
  ∩ AFT CodePipeline source configuration
  ∩ AWS IAM permission to use the connection
```

See:

- [AFT source-code version control](https://docs.aws.amazon.com/controltower/latest/userguide/aft-vcs.html).
- [What are AWS CodeConnections?](https://docs.aws.amazon.com/dtconsole/latest/userguide/connections.html).
- [Create a connection to GitHub](https://docs.aws.amazon.com/dtconsole/latest/userguide/connections-create-github.html).
- [Reviewing and modifying installed GitHub Apps](https://docs.github.com/en/apps/using-github-apps/reviewing-and-modifying-installed-github-apps).
- [Installing a GitHub App from a third party](https://docs.github.com/en/apps/using-github-apps/installing-a-github-app-from-a-third-party).

## AFT Network Configuration

This deployment sets:

```bash
export TF_VAR_aft_enable_vpc=false
```

The setting is an intentional cost and complexity decision. AFT does not charge a separate license fee, but its optional default VPC creates billable networking resources. With `aft_enable_vpc = true`, the pinned AFT module can create two NAT gateways, Elastic IP addresses, public and private subnets, and numerous interface VPC endpoints across two Availability Zones. NAT gateways and interface endpoints incur hourly charges even when AFT is idle, in addition to data-processing charges.

With `aft_enable_vpc = false`, AFT does not attach its Lambda and CodeBuild workloads to an AFT VPC and does not create the module's VPC, NAT gateways, subnets, or VPC endpoints. These workloads instead use the AWS-managed networking available to the services. This substantially reduces fixed networking cost and is appropriate for the current design, in which AFT uses GitHub through AWS CodeConnections and does not require access to private organizational services.

### Tradeoffs

Disabling the VPC provides:

- No AFT-created NAT gateway hourly or data-processing charges;.
- No AFT-created interface endpoint hourly or data-processing charges;.
- Fewer networking resources to operate and troubleshoot;.
- Simpler initial AFT deployment.

Disabling the VPC also means AFT customization workloads cannot directly use private VPC connectivity. This configuration is unsuitable if AFT must reach:

- Private APIs or services with no public endpoint;.
- Private package or artifact repositories;.
- On-premises services reachable only through VPN or Direct Connect;.
- Resources reachable only through Transit Gateway;.
- Services restricted to selected VPC endpoints or private networks.

Public network reachability must not be confused with public repository visibility. The GitHub repositories may remain private; AWS CodeConnections provides the authorized source integration. Repository and connection permissions must still follow least privilege.

If private connectivity becomes necessary later, perform an architecture and cost review before enabling the AFT VPC or supplying a supported customer-managed VPC. Changing an existing deployment from `false` to `true` adds networking resources and changes the network placement of AFT compute. Conversely, changing from `true` to `false` proposes removal of existing networking resources and must not be applied until dependencies have been reviewed.

Always inspect the platform plan and confirm that it contains no AFT NAT gateways when this setting is false:

```bash
./tf.sh --phase aft --dry-run
```

Relevant AWS references:

- [AFT deployment options](https://docs.aws.amazon.com/controltower/latest/userguide/aft-getting-started.html).
- [Amazon VPC pricing](https://aws.amazon.com/vpc/pricing/).
- [AWS PrivateLink pricing](https://aws.amazon.com/privatelink/pricing/).
- [AWS CodeConnections concepts](https://docs.aws.amazon.com/dtconsole/latest/userguide/connections.html).

## Operational Handoff Before Platform Deployment

Before running `terraform/aft/platform`, operators should confirm:

1. the Control Tower landing zone is `ACTIVE` and `IN_SYNC`;
2. the AFT OU has `AWSControlTowerBaseline` enabled successfully;
3. the AFT management account has been provisioned and enrolled;
4. the AFT management account ID is available from the account root's Terraform output;
5. `terraform/identity_center/aft_access/` has assigned `AFTPlatformAdministration` to the project-owned `AFTPlatformAdministrators` group in the AFT management account;
6. the Account Factory human user can obtain an AFT-account session through IAM Identity Center;
7. all four repositories and their configured branches exist;
8. repository variables are exported without relying on interactive Terraform prompts;
9. `TF_VAR_aft_enable_vpc` is explicitly set to `false` and the plan contains no AFT NAT gateways;
10. AFT customizations do not require private network connectivity;
11. human administrators use IAM Identity Center, while AFT automation uses its service roles.

The AFT module creates the CodeConnections resource during platform deployment. For GitHub it normally starts in `PENDING`, so provider authorization cannot be completed before the resource exists. After platform apply, sign in to the AFT management account with `AFTPlatformAdministration`, authorize the GitHub installation, and verify the connection becomes `AVAILABLE`. Then verify or retry the AFT source pipelines as necessary.

The following variables should therefore be set before platform deployment:

```bash
export TF_VAR_account_request_repo_name="example-organization/aft-account-request"
export TF_VAR_global_customizations_repo_name="example-organization/aft-global-customizations"
export TF_VAR_account_customizations_repo_name="example-organization/aft-account-customizations"
export TF_VAR_account_provisioning_customizations_repo_name="example-organization/aft-account-provisioning-customizations"
export TF_VAR_aft_enable_vpc=false
```

Do not supply arbitrary placeholder values merely to avoid Terraform prompts. AFT pipelines may fail or remain unusable if the referenced repositories or branches do not exist or cannot be accessed.

## Additional AWS Documentation

- [AFT feature overview](https://docs.aws.amazon.com/controltower/latest/userguide/aft-feature-overview.html).
- [AFT architecture](https://docs.aws.amazon.com/controltower/latest/userguide/aft-architecture.html).
- [AFT account provisioning](https://docs.aws.amazon.com/controltower/latest/userguide/aft-provision-account.html).
- [AFT troubleshooting](https://docs.aws.amazon.com/controltower/latest/userguide/aft-troubleshooting.html).
