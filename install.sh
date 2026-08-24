#!/usr/bin/env bash
# Install and configure local tooling for this repository.
#
# The Python packaging standard requires the filename `pyproject.toml` (not
# `project.toml`). This script creates it when absent, manages pre-commit and
# Checkov with uv, and installs the Git pre-commit hook.
#
# Supported Linux families:
# - Debian/Ubuntu (apt-get)
# - Fedora/RHEL/CentOS/Amazon Linux (dnf or yum)
# - openSUSE/SLES (zypper)
# - Arch Linux (pacman)
# - Alpine Linux (apk)

set -euo pipefail

readonly UV_VERSION="0.12.5"
readonly PRE_COMMIT_VERSION="4.6.2"
readonly CHECKOV_VERSION="3.3.13"
readonly GITLEAKS_VERSION="8.24.2"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
PYPROJECT_FILE="${SCRIPT_DIR}/pyproject.toml"
PRE_COMMIT_CONFIG="${SCRIPT_DIR}/.pre-commit-config.yaml"
UV_SHELL_RESTART_REQUIRED=false

log() {
  printf '==> %s\n' "$*"
}

warn() {
  printf 'WARNING: %s\n' "$*" >&2
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<EOF
Usage: $(basename "$0")

Idempotently configure this repository's local tooling:
  - install jq and AWS CLI v2 when missing;
  - install uv ${UV_VERSION} when uv is missing;
  - create pyproject.toml when missing;
  - install pre-commit ${PRE_COMMIT_VERSION}, Checkov ${CHECKOV_VERSION}, and Gitleaks ${GITLEAKS_VERSION};
  - create the repository pre-commit configuration when missing;
  - install the Git pre-commit hook when missing;
  - run every configured pre-commit check against all tracked files.

Gitleaks is installed idempotently into ${HOME}/.local/bin and is also
configured as a pinned pre-commit hook.

The script supports Linux and may request sudo only for missing system packages.
EOF
}

if (($#)); then
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown argument: $1"
      ;;
  esac
fi

[[ "$(uname -s)" == "Linux" ]] || die "This installer supports Linux only."
[[ -d "${SCRIPT_DIR}/.git" ]] || die "Expected a Git repository at '${SCRIPT_DIR}'."

cd "$SCRIPT_DIR"

DISTRO_NAME="unknown Linux distribution"
if [[ -r /etc/os-release ]]; then
  # shellcheck disable=SC1091
  source /etc/os-release
  DISTRO_NAME="${PRETTY_NAME:-${NAME:-unknown Linux distribution}}"
fi

SUDO=()
configure_sudo() {
  if [[ "${EUID}" -eq 0 ]]; then
    SUDO=()
  elif command -v sudo >/dev/null 2>&1; then
    SUDO=(sudo)
  else
    die "Missing system packages require root privileges, but sudo is unavailable."
  fi
}

install_missing_native_tools() {
  local missing=()
  local command_name
  local package_name
  local aws_native=false

  for command_name in jq curl unzip; do
    if command -v "$command_name" >/dev/null 2>&1; then
      log "System prerequisite already installed: ${command_name}"
    else
      log "System prerequisite is missing: ${command_name}"
      missing+=("$command_name")
    fi
  done

  # Alpine uses its native AWS CLI package because the official AWS bundle
  # requires glibc. Other distributions use AWS's official CLI v2 bundle.
  if command -v apk >/dev/null 2>&1; then
    if ! command -v aws >/dev/null 2>&1 || [[ ! "$(aws --version 2>&1)" =~ ^aws-cli/2\. ]]; then
      missing+=("aws-cli")
      aws_native=true
      log "AWS CLI v2 is missing; Alpine will install its native aws-cli package"
    else
      log "AWS CLI v2 already installed: $(aws --version 2>&1)"
    fi
  fi

  if ((${#missing[@]} == 0)); then
    log "No native prerequisite packages need installation"
    return
  fi

  configure_sudo
  log "Detected ${DISTRO_NAME}; installing missing packages: ${missing[*]}"

  if command -v apt-get >/dev/null 2>&1; then
    "${SUDO[@]}" apt-get update
    "${SUDO[@]}" env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${missing[@]}" ca-certificates
  elif command -v dnf >/dev/null 2>&1; then
    "${SUDO[@]}" dnf install -y "${missing[@]}" ca-certificates
  elif command -v yum >/dev/null 2>&1; then
    "${SUDO[@]}" yum install -y "${missing[@]}" ca-certificates
  elif command -v zypper >/dev/null 2>&1; then
    "${SUDO[@]}" zypper --non-interactive install "${missing[@]}" ca-certificates
  elif command -v pacman >/dev/null 2>&1; then
    "${SUDO[@]}" pacman -Sy --needed --noconfirm "${missing[@]}" ca-certificates
  elif command -v apk >/dev/null 2>&1; then
    "${SUDO[@]}" apk add --no-cache "${missing[@]}" ca-certificates
  else
    die "No supported package manager was found. Install these packages manually: ${missing[*]}"
  fi

  if $aws_native; then
    hash -r
  fi
}

install_aws_cli_v2_if_needed() {
  local machine_arch
  local aws_arch
  local temporary_dir
  local installer_args

  if command -v aws >/dev/null 2>&1 && [[ "$(aws --version 2>&1)" =~ ^aws-cli/2\. ]]; then
    log "AWS CLI v2 already installed; leaving it unchanged: $(aws --version 2>&1)"
    return
  fi

  if command -v apk >/dev/null 2>&1; then
    die "The Alpine aws-cli package did not provide AWS CLI v2."
  fi

  machine_arch="$(uname -m)"
  case "$machine_arch" in
    x86_64|amd64)
      aws_arch="x86_64"
      ;;
    aarch64|arm64)
      aws_arch="aarch64"
      ;;
    *)
      die "AWS CLI v2's official Linux installer is unsupported on architecture '${machine_arch}'."
      ;;
  esac

  configure_sudo
  temporary_dir="$(mktemp -d)" || die "Unable to create a temporary directory for AWS CLI installation."

  cleanup_aws_installer() {
    if [[ -n "${temporary_dir:-}" && -d "$temporary_dir" && "$temporary_dir" == /tmp/* ]]; then
      rm -r -- "$temporary_dir"
    fi
  }
  trap cleanup_aws_installer EXIT

  log "AWS CLI v2 is missing; downloading the official installer for ${aws_arch}"
  curl --fail --silent --show-error --location \
    "https://awscli.amazonaws.com/awscli-exe-linux-${aws_arch}.zip" \
    --output "${temporary_dir}/awscliv2.zip"
  unzip -q "${temporary_dir}/awscliv2.zip" -d "$temporary_dir"
  [[ -x "${temporary_dir}/aws/install" ]] || die "The AWS CLI archive did not contain the expected installer."

  installer_args=(--install-dir /usr/local/aws-cli --bin-dir /usr/local/bin)
  if [[ -d /usr/local/aws-cli/v2/current ]]; then
    log "An existing official AWS CLI installation was found; updating it to v2"
    installer_args+=(--update)
  else
    log "Installing AWS CLI v2 under /usr/local"
  fi

  "${SUDO[@]}" "${temporary_dir}/aws/install" "${installer_args[@]}"
  cleanup_aws_installer
  trap - EXIT
  hash -r
}

persist_uv_path() {
  local marker="# Added by aws-security install.sh for uv"
  local shell_name
  local profile
  local profiles=()

  shell_name="$(basename "${SHELL:-bash}")"
  case "$shell_name" in
    bash)
      profiles=("${HOME}/.bashrc" "${HOME}/.profile")
      ;;
    zsh)
      profiles=("${HOME}/.zshrc" "${HOME}/.zprofile")
      ;;
    fish)
      profile="${HOME}/.config/fish/config.fish"
      mkdir -p -- "$(dirname "$profile")"
      if grep -Fq "$marker" "$profile" 2>/dev/null; then
        log "uv PATH configuration already present in ${profile}"
      else
        printf '\n%s\nfish_add_path "$HOME/.local/bin"\n' "$marker" >>"$profile"
        log "Added the uv installation directory to ${profile}"
      fi
      return
      ;;
    *)
      profiles=("${HOME}/.profile")
      ;;
  esac

  for profile in "${profiles[@]}"; do
    if grep -Fq "$marker" "$profile" 2>/dev/null; then
      log "uv PATH configuration already present in ${profile}"
    else
      printf '\n%s\nexport PATH="$HOME/.local/bin:$PATH"\n' "$marker" >>"$profile"
      log "Added the uv installation directory to ${profile}"
    fi
  done
}

ensure_uv_path() {
  local uv_bin_dir="${HOME}/.local/bin"

  case ":${PATH}:" in
    *":${uv_bin_dir}:"*)
      log "uv installation directory is already present in PATH: ${uv_bin_dir}"
      ;;
    *)
      export PATH="${uv_bin_dir}:${PATH}"
      UV_SHELL_RESTART_REQUIRED=true
      log "Added ${uv_bin_dir} to PATH for this installer process"
      ;;
  esac

  # A child process cannot change its parent's PATH. Persist the user-local
  # directory in shell startup files and print an immediate command at the end.
  if $UV_SHELL_RESTART_REQUIRED && command -v uv >/dev/null 2>&1; then
    persist_uv_path
  fi
}

install_gitleaks_if_needed() {
  local machine_arch
  local gitleaks_arch
  local temporary_dir
  local archive_name
  local archive_path
  local checksums_path
  local expected_checksum
  local actual_checksum
  local installed_version=""
  local gitleaks_bin="${HOME}/.local/bin/gitleaks"

  ensure_uv_path

  if command -v gitleaks >/dev/null 2>&1; then
    installed_version="$(gitleaks version 2>/dev/null || true)"
  elif [[ -x "$gitleaks_bin" ]]; then
    installed_version="$($gitleaks_bin version 2>/dev/null || true)"
  fi

  if [[ "$installed_version" == "$GITLEAKS_VERSION" ]]; then
    log "Gitleaks ${GITLEAKS_VERSION} already installed; leaving it unchanged"
    return
  fi

  machine_arch="$(uname -m)"
  case "$machine_arch" in
    x86_64|amd64)
      gitleaks_arch="x64"
      ;;
    aarch64|arm64)
      gitleaks_arch="arm64"
      ;;
    *)
      die "Gitleaks official Linux releases are unsupported on architecture '${machine_arch}'."
      ;;
  esac

  temporary_dir="$(mktemp -d)" || die "Unable to create a temporary directory for Gitleaks installation."
  cleanup_gitleaks_installer() {
    if [[ -n "${temporary_dir:-}" && -d "$temporary_dir" && "$temporary_dir" == /tmp/* ]]; then
      rm -r -- "$temporary_dir"
    fi
  }
  trap cleanup_gitleaks_installer EXIT

  archive_name="gitleaks_${GITLEAKS_VERSION}_linux_${gitleaks_arch}.tar.gz"
  archive_path="${temporary_dir}/${archive_name}"
  checksums_path="${temporary_dir}/checksums.txt"

  log "Gitleaks is missing or differs from ${GITLEAKS_VERSION}; downloading the official release"
  curl --proto '=https' --tlsv1.2 --fail --silent --show-error --location \
    "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/${archive_name}" \
    --output "$archive_path"
  curl --proto '=https' --tlsv1.2 --fail --silent --show-error --location \
    "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_checksums.txt" \
    --output "$checksums_path"

  expected_checksum="$(awk -v name="$archive_name" '$2 == name { print $1; exit }' "$checksums_path")"
  [[ "$expected_checksum" =~ ^[[:xdigit:]]{64}$ ]] || die "The Gitleaks checksum file did not contain a valid checksum for ${archive_name}."
  actual_checksum="$(sha256sum "$archive_path" | awk '{print $1}')"
  [[ "$actual_checksum" == "$expected_checksum" ]] || die "Gitleaks archive checksum verification failed."

  tar -xzf "$archive_path" -C "$temporary_dir" gitleaks
  [[ -x "${temporary_dir}/gitleaks" ]] || die "The Gitleaks archive did not contain the expected executable."
  install -Dm755 "${temporary_dir}/gitleaks" "$gitleaks_bin"
  cleanup_gitleaks_installer
  trap - EXIT
  hash -r

  [[ -x "$gitleaks_bin" ]] || die "Gitleaks installation did not create ${gitleaks_bin}."
  [[ "$($gitleaks_bin version)" == "$GITLEAKS_VERSION" ]] || die "Unexpected Gitleaks version after installation: $($gitleaks_bin version)"
  log "Gitleaks installation completed: ${GITLEAKS_VERSION}"
}

install_uv_if_needed() {
  local temporary_dir
  local installer

  if command -v uv >/dev/null 2>&1; then
    log "uv already installed; leaving it unchanged: $(uv --version)"
    return
  fi

  # An existing user-local installation may not yet be visible to this shell.
  ensure_uv_path
  if command -v uv >/dev/null 2>&1; then
    log "Found an existing user-local uv installation: $(uv --version)"
    return
  fi

  temporary_dir="$(mktemp -d)" || die "Unable to create a temporary directory for uv installation."
  installer="${temporary_dir}/uv-installer.sh"

  cleanup_uv_installer() {
    if [[ -n "${temporary_dir:-}" && -d "$temporary_dir" && "$temporary_dir" == /tmp/* ]]; then
      rm -r -- "$temporary_dir"
    fi
  }
  trap cleanup_uv_installer EXIT

  log "uv is not installed; downloading the pinned official uv ${UV_VERSION} installer"
  curl --proto '=https' --tlsv1.2 --fail --silent --show-error --location \
    "https://astral.sh/uv/${UV_VERSION}/install.sh" \
    --output "$installer"

  log "Installing uv ${UV_VERSION} into ${HOME}/.local/bin"
  UV_INSTALL_DIR="${HOME}/.local/bin" sh "$installer"
  cleanup_uv_installer
  trap - EXIT
  hash -r

  command -v uv >/dev/null 2>&1 || die "uv installation completed, but uv is not available in PATH. Add '${HOME}/.local/bin' to PATH."
  log "uv installation completed: $(uv --version)"
  ensure_uv_path
}

create_pyproject_if_needed() {
  if [[ -f "$PYPROJECT_FILE" ]]; then
    log "Python project configuration already exists; preserving ${PYPROJECT_FILE}"
    return
  fi

  log "Creating the standard Python project configuration: ${PYPROJECT_FILE}"
  cat >"$PYPROJECT_FILE" <<EOF
[project]
name = "aws-security-tooling"
version = "0.1.0"
description = "Local development and security-analysis tooling for the AWS security repository."
requires-python = ">=3.12,<3.13"
dependencies = []

[dependency-groups]
dev = [
  "checkov==${CHECKOV_VERSION}",
  "pre-commit==${PRE_COMMIT_VERSION}",
]

[tool.uv]
package = false
EOF
}

ensure_python_tools() {
  local pre_commit_output=""
  local checkov_output=""
  local tools_current=false

  if [[ -f uv.lock ]]; then
    pre_commit_output="$(uv run --frozen pre-commit --version 2>/dev/null || true)"
    checkov_output="$(uv run --frozen checkov --version 2>/dev/null | head -n 1 || true)"

    if [[ "$pre_commit_output" == "pre-commit ${PRE_COMMIT_VERSION}" && "$checkov_output" == "${CHECKOV_VERSION}" ]]; then
      tools_current=true
    fi
  fi

  if $tools_current; then
    log "pre-commit already installed at the required version: ${PRE_COMMIT_VERSION}"
    log "Checkov already installed at the required version: ${CHECKOV_VERSION}"
    log "Synchronizing the existing locked uv environment"
    uv sync --frozen
  else
    if [[ -z "$pre_commit_output" ]]; then
      log "pre-commit is not installed in the project environment"
    else
      log "pre-commit version differs from the required ${PRE_COMMIT_VERSION}: ${pre_commit_output}"
    fi

    if [[ -z "$checkov_output" ]]; then
      log "Checkov is not installed in the project environment"
    else
      log "Checkov version differs from the required ${CHECKOV_VERSION}: ${checkov_output}"
    fi

    log "Ensuring exact development-tool requirements in pyproject.toml"
    uv add --dev "pre-commit==${PRE_COMMIT_VERSION}" "checkov==${CHECKOV_VERSION}"
    log "Synchronizing the uv environment from the generated lock file"
    uv sync --frozen
  fi

  pre_commit_output="$(uv run --frozen pre-commit --version)"
  checkov_output="$(uv run --frozen checkov --version | head -n 1)"
  [[ "$pre_commit_output" == "pre-commit ${PRE_COMMIT_VERSION}" ]] || die "Unexpected pre-commit version after installation: ${pre_commit_output}"
  [[ "$checkov_output" == "${CHECKOV_VERSION}" ]] || die "Unexpected Checkov version after installation: ${checkov_output}"
}

create_pre_commit_config_if_needed() {
  if [[ -f "$PRE_COMMIT_CONFIG" ]]; then
    log "Pre-commit configuration already exists; preserving ${PRE_COMMIT_CONFIG}"
    if ! grep -Eq '^[[:space:]]*-[[:space:]]+id:[[:space:]]+checkov[[:space:]]*$' "$PRE_COMMIT_CONFIG"; then
      die "Existing ${PRE_COMMIT_CONFIG} does not define the required Checkov hook; refusing to overwrite it."
    fi
    if ! grep -Eq '^[[:space:]]*-[[:space:]]+id:[[:space:]]+gitleaks[[:space:]]*$' "$PRE_COMMIT_CONFIG"; then
      die "Existing ${PRE_COMMIT_CONFIG} does not define the required Gitleaks hook; refusing to overwrite it."
    fi
    return
  fi

  log "Creating ${PRE_COMMIT_CONFIG} with repository hygiene and uv-managed Checkov hooks"
  cat >"$PRE_COMMIT_CONFIG" <<'EOF'
repos:
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v6.0.0
    hooks:
      - id: trailing-whitespace
      - id: end-of-file-fixer
      - id: mixed-line-ending
        args:
          - --fix=lf
      - id: check-yaml
      - id: check-merge-conflict
      - id: check-added-large-files
      - id: detect-private-key

  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.24.2
    hooks:
      - id: gitleaks
        name: Gitleaks secret scan

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
EOF
}

install_pre_commit_hook_if_needed() {
  local hook_file="${SCRIPT_DIR}/.git/hooks/pre-commit"

  uv run --frozen pre-commit validate-config "$PRE_COMMIT_CONFIG"

  if [[ -f "$hook_file" ]] && grep -q 'pre_commit' "$hook_file"; then
    log "Git pre-commit hook is already installed; preserving ${hook_file}"
    log "Ensuring remote hook environments are available"
    uv run --frozen pre-commit install-hooks
  else
    if [[ -e "$hook_file" ]]; then
      die "A non-pre-commit hook already exists at '${hook_file}'. Preserve or migrate it before rerunning this installer."
    fi
    log "Git pre-commit hook is not installed; installing it now"
    uv run --frozen pre-commit install --install-hooks
  fi
}

run_pre_commit_checks() {
  log "Running all pre-commit checks against tracked files"
  uv run --frozen pre-commit run --all-files
}

verify_installation() {
  command -v jq >/dev/null 2>&1 || die "jq is not available after installation."
  command -v aws >/dev/null 2>&1 || die "AWS CLI is not available after installation."
  command -v uv >/dev/null 2>&1 || die "uv is not available after installation."
  command -v gitleaks >/dev/null 2>&1 || die "Gitleaks is not available after installation."
  [[ "$(gitleaks version)" == "$GITLEAKS_VERSION" ]] || die "Unexpected Gitleaks version: $(gitleaks version)"
  [[ "$(aws --version 2>&1)" =~ ^aws-cli/2\. ]] || die "AWS CLI v2 is required; found: $(aws --version 2>&1)"
  [[ -f "$PYPROJECT_FILE" ]] || die "Missing ${PYPROJECT_FILE}."
  [[ -f "${SCRIPT_DIR}/uv.lock" ]] || die "Missing ${SCRIPT_DIR}/uv.lock."
  [[ -f "$PRE_COMMIT_CONFIG" ]] || die "Missing ${PRE_COMMIT_CONFIG}."
  [[ -x "${SCRIPT_DIR}/.git/hooks/pre-commit" ]] || die "The Git pre-commit hook is not executable."

  log "Environment setup completed successfully"
  printf 'jq:         %s\n' "$(jq --version)"
  printf 'aws:        %s\n' "$(aws --version 2>&1)"
  printf 'uv:         %s\n' "$(uv --version)"
  printf 'pre-commit: %s\n' "$(uv run --frozen pre-commit --version)"
  printf 'checkov:    %s\n' "$(uv run --frozen checkov --version | head -n 1)"
  printf 'gitleaks:   %s\n' "$(gitleaks version)"
  printf 'config:     %s\n' "$PRE_COMMIT_CONFIG"
  printf 'hook:       %s\n' "${SCRIPT_DIR}/.git/hooks/pre-commit"

  if $UV_SHELL_RESTART_REQUIRED; then
    warn "The parent shell cannot inherit PATH changes made by install.sh."
    warn "For immediate access, run: export PATH=\"${HOME}/.local/bin:\$PATH\""
    warn "Then restart the shell later to verify the persisted startup configuration."
  fi
}

install_missing_native_tools
install_aws_cli_v2_if_needed
install_uv_if_needed
install_gitleaks_if_needed
create_pyproject_if_needed
ensure_python_tools
create_pre_commit_config_if_needed
install_pre_commit_hook_if_needed
verify_installation
run_pre_commit_checks

log "All installation checks completed successfully."
log "Run all checks with: uv run --frozen pre-commit run --all-files"
