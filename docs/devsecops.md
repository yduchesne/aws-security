# DevSecOps Tooling

## Purpose

This document describes the repository's local pre-commit controls, the Checkov integration used to scan Terraform, and the expected relationship between developer checks and CI enforcement.

The controls provide early feedback before a change is committed. They complement, but do not replace:

- Terraform formatting and validation;
- Terraform plan review;
- peer review;
- protected branches;
- CI security checks;
- AWS runtime controls and monitoring.

A developer can bypass a local hook with `git commit --no-verify`. CI must therefore run the same checks before a change can merge.

## Toolchain

The repository uses:

| Tool | Responsibility |
|---|---|
| `uv` | Python environment, dependency, and lock-file management |
| `pre-commit` | Git hook orchestration |
| Checkov | Static security analysis of project-owned Terraform |
| `pre-commit-hooks` | Repository hygiene checks such as whitespace, line endings, merge markers, and private-key detection |

The pinned tooling versions created by `install.sh` are currently:

```text
uv:         0.12.5
pre-commit: 4.6.2
Checkov:    3.3.13
```

Tool updates require a reviewed change to `pyproject.toml`, `uv.lock`, and any affected hook configuration.

## Environment Setup

Run the repository installer from the project root:

```bash
./install.sh
```

The installer is idempotent. It:

1. installs missing native prerequisites;
2. installs uv when absent;
3. creates the standard `pyproject.toml` when absent;
4. installs the pinned pre-commit and Checkov packages into `.venv`;
5. generates or synchronizes `uv.lock`;
6. creates `.pre-commit-config.yaml` when absent;
7. installs `.git/hooks/pre-commit` when absent;
8. validates the resulting environment.

The installer places a user-local uv installation under:

```text
$HOME/.local/bin
```

A child process cannot update the parent shell's environment. If uv is not immediately found after the first installation, run:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

or restart the login shell:

```bash
exec "$SHELL" -l
```

The installer also adds an idempotent PATH entry to the applicable Bash, Zsh, or Fish startup configuration.

## Version-Controlled Files

Commit:

```text
pyproject.toml
uv.lock
.pre-commit-config.yaml
```

Do not commit:

```text
.venv/
.pre-commit hook environments or caches
Checkov output containing sensitive paths or values
Terraform plans or state
```

The `.venv/` directory is excluded by `.gitignore`.

## Pre-commit Hooks

The generated `.pre-commit-config.yaml` includes standard hygiene checks:

```text
trailing-whitespace
end-of-file-fixer
mixed-line-ending
check-yaml
check-merge-conflict
check-added-large-files
detect-private-key
```

These checks reduce accidental formatting defects, unresolved merge markers, oversized commits, and obvious private-key exposure.

`detect-private-key` is a useful guard but is not a complete secret scanner. Credentials, Terraform state, environment files, plans, account email addresses, and access tokens must still be reviewed before commit.

## Checkov Integration

Checkov is installed in the uv-managed project environment and invoked by a local pre-commit hook:

```text
Git commit
  → pre-commit
  → uv run --frozen checkov
  → Terraform security scan
```

The hook uses:

```yaml
- repo: local
  hooks:
    - id: checkov
      name: Checkov Terraform security scan
      entry: uv run --frozen checkov
      language: system
      pass_filenames: false
      files: ^(terraform/.*\.tf|\.checkov\.ya?ml|pyproject\.toml|uv\.lock)$
      args:
        - --directory
        - terraform
        - --framework
        - terraform
        - --quiet
        - --compact
        - --download-external-modules
        - "false"
        - --skip-path
        - '(^|/)\.terraform(/|$)|(^|/)\.bak(/|$)'
```

### Why Checkov is invoked through uv

Using:

```text
uv run --frozen checkov
```

ensures that:

- the Checkov version comes from `uv.lock`;
- local and CI scans use the same dependency graph;
- Checkov is not installed into the operating system Python environment;
- an unreviewed dependency resolution cannot silently occur during CI;
- developers do not need a separate global Checkov installation.

### Why `pass_filenames` is disabled

Terraform resources are commonly distributed across:

```text
main.tf
variables.tf
providers.tf
outputs.tf
```

Scanning only a staged filename can omit context from related files. The hook therefore scans the complete project-owned `terraform/` tree whenever a relevant Terraform or tooling file changes.

The tradeoff is a slower commit than a single-file scan. The increased context is preferable for security analysis.

### Scan scope

Checkov scans these project roots:

```text
terraform/bootstrap
terraform/identity_center
terraform/identity_center/aft_access
terraform/aft/org_unit
terraform/aft/account
terraform/aft/platform
```

It excludes:

```text
.terraform/
.bak/
```

External module downloading is disabled. This prevents locally downloaded upstream modules from being evaluated as if they were project-owned source and avoids network-dependent module retrieval during every commit.

The AFT module source itself is still checked for supply-chain properties. It is pinned to the immutable commit corresponding to the reviewed AFT release rather than a mutable branch or tag.

## Running Checks

Run every hook against all tracked files:

```bash
uv run --frozen pre-commit run --all-files
```

Run only Checkov through pre-commit:

```bash
uv run --frozen pre-commit run checkov --all-files
```

Run hooks against staged files as Git would during a commit:

```bash
uv run --frozen pre-commit run
```

Validate the hook configuration:

```bash
uv run --frozen pre-commit validate-config .pre-commit-config.yaml
```

A hook may modify files, for example by removing trailing whitespace or adding a final newline. Review and stage those modifications before committing again.

## Checkov Finding Review

A failed Checkov check is design feedback, not merely lint noise. Classify every finding as one of:

```text
True security defect
Intentional architecture with compensating controls
AWS API resource-scoping limitation
Control Tower-owned resource
Upstream module issue
Checkov false positive
Not applicable
```

The preferred resolution order is:

1. fix the security defect;
2. scope permissions or resources more narrowly;
3. separate broad statements into scoped and genuinely unscopable operations;
4. add conditions or explicit denies where AWS supports them;
5. document compensating controls and residual risk;
6. suppress only the specific remaining finding when no safer representation is available.

Do not use permanent global `--soft-fail` behavior.

## Checkov Suppressions

A suppression must be adjacent to the affected Terraform resource and include a meaningful rationale:

```hcl
# checkov:skip=CKV_AWS_XXX: Explain the required capability, implemented constraints, compensating controls, and documentation reference.
```

A suppression should identify:

- why the capability is required;
- why AWS does not permit narrower enforcement, or why the rule is intentionally triggered;
- resource and condition constraints already applied;
- explicit denies or separation of duties;
- monitoring and review controls;
- the relevant architecture or security document.

Do not use:

- unexplained suppressions;
- repository-wide suppression of IAM checks;
- suppressions added only to make CI green;
- broad skip lists without individual review;
- suppression of a real privilege-escalation path without mitigation.

The permission-set administrator currently carries a narrow `CKV_AWS_289` suppression because permissions management is that persona's explicit responsibility. Before the suppression, the implementation scopes resources, prohibits account assignments, and protects administrative permission sets by tag. The remaining risk is documented in [`identity_center_security.md`](identity_center_security.md).

## IAM Findings and AWS Limitations

Checkov evaluates policy structure and may not know every AWS authorization nuance. For example:

- some list or browser-handshake actions do not support resource ARNs;
- Identity Store actions use a mixture of Identity Store, group, user, and membership resource types;
- IAM Identity Center account assignments authorize instance, permission-set, and account resources;
- a role whose purpose is permission administration necessarily contains permissions-management actions.

Do not immediately suppress a wildcard finding. Consult the AWS service authorization table and separate:

```text
Actions supporting resource-level permissions
  → explicit ARN scope

Actions without a resource type
  → Resource = "*" plus supported conditions and documented exception
```

Relevant project controls include:

```text
SecurityBoundary = Protected
AssignmentDelegation = Allowed
```

These tags protect administrative permission sets and establish the catalog of permission sets that an access-assignment administrator may assign.

## CI Enforcement

CI should run the same committed environment and hook configuration:

```bash
uv sync --frozen
```

```bash
uv run --frozen pre-commit run --all-files --show-diff-on-failure
```

The static-analysis job should:

- run without AWS credentials;
- use the committed `uv.lock`;
- fail when hooks fail;
- pin any CI actions to reviewed immutable commit SHAs;
- avoid uploading source or findings to external services unless approved;
- protect workflow files and the default branch;
- require review before changing Checkov suppressions or hook configuration.

Local success is not sufficient because local hooks can be bypassed.

## Updating Tools

Update a dependency through uv, for example:

```bash
uv lock --upgrade-package checkov
```

After an update:

1. review `pyproject.toml` and `uv.lock`;
2. review upstream release notes;
3. run all hooks;
4. investigate new or changed findings;
5. verify no suppression became obsolete;
6. commit the dependency and lock-file changes together.

The installer preserves an existing `pyproject.toml` and `.pre-commit-config.yaml`. If the existing pre-commit configuration lacks the required Checkov hook, it stops rather than overwriting the file.

## Troubleshooting

### `uv: command not found`

Run:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

Then rerun `./install.sh` or restart the shell.

### Hook is not installed

Run:

```bash
uv run --frozen pre-commit install --install-hooks
```

### Environment differs from the lock file

Run:

```bash
uv sync --frozen
```

If this reports that the lock is stale, do not update it implicitly in CI. Review the project dependency change and regenerate the lock deliberately.

### Checkov reports upstream `.terraform` resources

Verify that the hook uses the configured skip path and that Checkov is invoked through pre-commit rather than an unrelated global command with different arguments.

## References

- [pre-commit framework](https://pre-commit.com/)
- [Supported pre-commit hooks](https://pre-commit.com/hooks.html)
- [uv documentation](https://docs.astral.sh/uv/)
- [uv project environments](https://docs.astral.sh/uv/concepts/projects/)
- [Checkov pre-commit integration](https://www.checkov.io/4.Integrations/pre-commit.html)
- [Checkov Terraform scanning](https://www.checkov.io/7.Scan%20Examples/Terraform.html)
- [Suppressing and skipping Checkov policies](https://www.checkov.io/2.Basics/Suppressing%20and%20Skipping%20Policies.html)
- [AWS Identity Store actions, resources, and condition keys](https://docs.aws.amazon.com/service-authorization/latest/reference/list_identitystore.html)
- [AWS IAM Identity Center actions, resources, and condition keys](https://docs.aws.amazon.com/service-authorization/latest/reference/list_iam-identity-center.html)
- [AWS CodeConnections actions, resources, and condition keys](https://docs.aws.amazon.com/service-authorization/latest/reference/list_codeconnections.html)
