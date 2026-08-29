# AWS CLI IAM Identity Center Authentication

## Purpose

This guide explains how AWS CLI IAM Identity Center authentication interacts
with browser sessions, private windows, MFA, and the device-authorization flow.
It is intended for developers who use several named identities or account
profiles on the same Ubuntu workstation.

No AWS password, MFA code, SSO access token, or device code belongs in an AWS
CLI configuration file, environment file, Terraform input, shell script, or
repository evidence.

## Table of contents

- [Purpose](#purpose).
- [Enable an IAM Identity Center user account](#enable-an-iam-identity-center-user-account).
  - [Send the verification email](#1-send-the-verification-email).
  - [Set up MFA for the user](#2-set-up-mfa-for-the-user).
  - [Send a password-reset notification](#3-send-a-password-reset-notification).
  - [Verify account enablement before CLI configuration](#verify-account-enablement-before-cli-configuration).
- [Example: configure and use the AWS CLI after enablement](#example-configure-and-use-the-aws-cli-after-enablement).
- [Authentication state exists in two places](#authentication-state-exists-in-two-places).
- [SSO sessions and AWS CLI profiles](#sso-sessions-and-aws-cli-profiles).
- [Why browser-session reuse causes the wrong identity](#why-browser-session-reuse-causes-the-wrong-identity).
- [Device authorization with `--use-device-code`](#device-authorization-with---use-device-code).
- [What `--no-browser` fixes](#what---no-browser-fixes).
- [Private browser windows on Ubuntu](#private-browser-windows-on-ubuntu).
- [Recommended login sequence for different test users](#recommended-login-sequence-for-different-test-users).
- [Recommended login sequence for the lab administrator](#recommended-login-sequence-for-the-lab-administrator).
- [Troubleshooting checklist](#troubleshooting-checklist).

## Enable an IAM Identity Center user account

Creating an IAM Identity Center user record with Terraform or in the console
does not by itself make the user ready to sign in. An authorized Identity
Center administrator must complete the account-enablement workflow for each
named human. The exact console labels can vary slightly with the Identity
Center identity source and AWS console version, but the sequence is:

```text
Create user record
  → send verification email
  → user sets or resets password
  → enable MFA and register an authenticator
  → user can configure AWS CLI and sign in
```

Perform these steps in the organization management account from an approved
administrative session. Do not send passwords or MFA secrets through email,
chat, tickets, or Terraform variables.

### 1. Send the verification email

The following descibes the email verification flow that would apply to "real"
human users. In the case of this project, all emails are expected to go to
your inbox and you are expected to complete the flow, for each user.
Regardless, the flow applies in both cases.

1. Open **IAM Identity Center** in the home Region.
2. Open **Users** and select the intended named user.
3. Confirm the user's email address and profile details belong to the
   accountable human. Do not continue if the address is incorrect or already
   belongs to another person.
4. From **Actions**, choose **Send verification email** (or the equivalent
   **Send email** action) and confirm the operation.
5. Ask the user to open the message and follow the organization access-portal
   link. They should verify that the displayed name and email are theirs.

The verification message is an activation/recovery step, not an AWS access key.
The administrator should not open the user's message or handle the user's
password. If the email is not received, check the address, spam/quarantine
systems, and the user's status before sending another message.

### 2. Set up MFA for the user

Here, we are diverging a bit from the standard flow, since you are impersonating all users.
We are still providing the standard flow, further below. For now, follow those simplified steps:

1. Open **IAM Identity Center** in the home Region.
2. Open **Users** and select the intended named user.
3. Under **MFA Devices**, click **Register MFA device**.
4. Proceed with the MFA device registration flow, using your authenticator app. Double-check that the email you are registering an MFA device for is indeed that of the user in question.
5. At the end of the flow, you should have a new MFA code in your authenticator app.

You may now go to the last step (#3), involving the password creation for the user.

#### Standard flow

This flow applies when dealing with "real" users.

MFA must be required by the organization's IAM Identity Center
**Settings → Authentication → Multi-factor authentication** configuration.
Review that setting before activating a privileged user. Prefer a phishing-
resistant security key or an organization-approved authenticator method.

Then have the user complete MFA registration through the access portal:

1. Open the verification or access-portal URL as the intended user.
2. Set or confirm the Identity Center password when prompted.
3. Open the account/security settings or follow the MFA registration prompt.
4. Register the approved authenticator or security key.
5. Complete a test sign-in and verify that an MFA challenge is required.

Identity Center administrators configure the MFA policy; they should not collect
or store a user's TOTP seed, recovery codes, or security-key private material.
If the console offers an administrator action to reset or remove a registered
MFA device, use it only under the organization's documented recovery process
and record the approver. A user must not be considered enabled until the user
can complete a fresh MFA-protected portal login.

### 3. Send a password-reset notification

If the user did not complete the initial activation, forgot the password, or
needs a new activation link:

1. Return to **IAM Identity Center → Users** and select the user.
2. From **Actions**, choose **Reset password** or **Send password reset
   notification**.
3. Confirm the reset notification is sent to the verified user email address.
4. Have the user follow the notification and set a new password directly in
   the Identity Center portal.
5. Require MFA at the next sign-in and verify that the user can reach only the
   accounts and permission sets assigned to them.

A password reset notification does not grant an account assignment or change a
permission set. It only restores the user's ability to authenticate to
Identity Center. If the user is disabled, unassigned, or not provisioned to an
account, resolve that separate lifecycle or access-assignment issue rather
than repeatedly resetting the password.

We recommend using a reputable password manager to keep track of the
*different passwords* used for separate named identities and services. Do not
reuse passwords between privileged personas, and do not store passwords in AWS
CLI profiles, `.env` files, Terraform state, shell history, or repository
files. A password manager does not replace MFA or independent ownership of
privileged identities.

### Verify account enablement before CLI configuration

The administrator should verify the user record, MFA policy/status, and
intended group memberships and account assignments. The user should then
complete one interactive access-portal sign-in before configuring the CLI. A
successful portal login alone does not prove AWS account access; the user must
also select the expected account and permission set.

## Example: configure and use the AWS CLI after enablement

The following example assumes an enabled user named `alice@example.com` has
been assigned `WorkloadLabAdministrator` in the Dev Lab account. The email
address is shown for explanatory purposes only; it is not placed in the AWS
CLI configuration. Configuration happens **after** the user has completed
verification, password setup/reset, and MFA registration.

First configure a profile using IAM Identity Center:

```bash
aws configure sso --profile alice-dev
```

Use the following values when prompted:

```text
SSO session name: alice-session
SSO start URL: https://<identity-center-instance>.awsapps.com/start
SSO region: <pick the desired region>
SSO registration scopes: sso:account:access
AWS account: <pick an account>
Role/permission set: WorkloadLabAdministrator
Default client Region: <enter the desired region - i.e. for simplicity the same as the SSO region above>
Output format: json
```
Note: The `WorkloadLabAdministrator` role is picked as an example: you'd pick whatever makes sense in the context.

This creates profile metadata in `~/.aws/config`; it does not store the
Identity Center password, MFA code, or AWS access keys. The resulting profile
will resemble:

```ini
[sso-session alice-session]
sso_start_url = https://<identity-center-instance>.awsapps.com/start
sso_region = us-east-2
sso_registration_scopes = sso:account:access

[profile alice-dev]
sso_session = alice-session
sso_account_id = <TF_LAB_DEV_ACCOUNT_ID>
sso_role_name = WorkloadLabAdministrator
region = us-east-2
output = json
```

Start login deliberately, especially on a workstation used by multiple
people:

```bash
aws sso login \
  --profile alice-dev \
  --use-device-code \
  --no-browser
```

Open the printed verification URL in a private or dedicated browser context,
authenticate as `alice@example.com`, complete the MFA challenge, and approve
the request. Then verify the resulting temporary AWS identity:

```bash
aws sts get-caller-identity --profile alice-dev
```

An expected response has this shape:

```json
{
  "UserId": "AROA...:alice-dev",
  "Account": "01234098765",
  "Arn": "arn:aws:sts::01234098765:assumed-role/AWSReservedSSO_WorkloadLabAdministrator_<SUFFIX>/alice-dev"
}
```

The account must be the Dev Lab account and the role must be the assigned
permission-set role. `get-caller-identity` is a safe verification call, but it
does not prove that every intended API action is allowed. If the account or
role is unexpected, run `aws sso logout`, sign out of the browser, close stale
private windows, and repeat the login with the intended identity. Do not
continue with Terraform or an exercise until the identity is correct.

## Authentication state exists in two places

AWS CLI SSO authentication involves two independent kinds of state:

1. **AWS CLI SSO cache** — temporary access and registration tokens stored in
   the user's local AWS CLI cache.
2. **Browser session** — cookies identifying the human currently signed in to
   the IAM Identity Center access portal or its upstream identity provider.

This distinction matters when several identities use the same workstation.
Clearing one does not necessarily clear the other:

```text
aws sso logout
  → clears AWS CLI cached SSO sessions
  → does not reliably sign the browser out of the access portal

Browser sign-out or closing all private windows
  → clears or changes browser authentication state
  → does not necessarily remove AWS CLI cached SSO tokens
```

Before switching between named humans, clear both forms of state.

## SSO sessions and AWS CLI profiles

An `sso-session` identifies an IAM Identity Center portal and its cached login.
An AWS CLI profile selects an account and permission set through that session.

Profiles for the same human may share one SSO session. For example, the lab
baseline administrator uses one identity but has assignments in two accounts:

```ini
[sso-session lab-admin]
sso_start_url = https://<identity-center-instance>.awsapps.com/start
sso_region = us-east-2
sso_registration_scopes = sso:account:access

[profile lab-admin-dev]
sso_session = lab-admin
sso_account_id = <TF_LAB_DEV_ACCOUNT_ID>
sso_role_name = WorkloadLabBaselineAdmin
region = us-east-2

[profile lab-admin-test]
sso_session = lab-admin
sso_account_id = <TF_LAB_TEST_ACCOUNT_ID>
sso_role_name = WorkloadLabBaselineAdmin
region = us-east-2
```

One password and MFA authentication can authorize both account profiles because
they represent the same named human and portal session.

Profiles representing different humans must not share an SSO session. The Week
2 exercise profiles use separate sessions:

```text
week2-source
  → test user 1 SSO session
  → Dev Lab
  → WorkloadLabAdministrator

week2-target
  → test user 2 SSO session
  → Test Lab
  → WorkloadLabAdministrator
```

An SSO session name is organizational metadata, not a security boundary by
itself. The human who completes browser authentication determines which
identity receives the cached token.

## Why browser-session reuse causes the wrong identity

When the AWS CLI opens the default browser, that browser may already contain a
valid access-portal session. The authorization page can silently reuse the
currently signed-in identity instead of prompting for the intended one.

Typical symptoms include:

- The CLI lists only permission sets belonging to another persona.
- An exercise profile receives the baseline administrator permission set.
- `get-caller-identity` reports an unexpected account or role;
- MFA is not requested because the existing browser session is still valid.

The AWS CLI profile name does not bind browser authentication to a particular
email address. Naming a profile `week2-source`, for example, does not prevent a
different signed-in user from authorizing it.

## Device authorization with `--use-device-code`

The device-authorization flow separates the terminal process from the browser
used to approve access. Start it with:

```bash
aws sso login \
  --profile <AWS_PROFILE> \
  --use-device-code
```

The CLI displays:

- An AWS verification URL.
- A short-lived device authorization code.
- A message indicating that it is waiting for authorization.

The operator opens the URL, enters the code, authenticates, completes MFA, and
approves access. The waiting CLI process then receives its temporary SSO token.

A device code is a temporary authentication credential. Do not share it or
include it in screenshots, logs, tickets, chat messages, or repository
evidence.

## What `--no-browser` fixes

Use `--no-browser` with the device flow:

```bash
aws sso login \
  --profile <AWS_PROFILE> \
  --use-device-code \
  --no-browser
```

Without `--no-browser`, the AWS CLI may automatically launch the verification
URL in the workstation's default browser. That browser may have an existing
session for the wrong user.

`--no-browser` prevents the CLI from launching a browser automatically. This
allows the operator to deliberately:

- Copy the verification URL printed by the CLI.
- Choose a private or incognito window.
- Choose a dedicated browser profile.
- Use a different browser for each test identity.
- Inspect which user is signing in before approving access.

It addresses accidental reuse of the default browser's authenticated session.
It does **not**:

- Clear existing AWS CLI tokens.
- Clear browser cookies.
- Force Identity Center to request MFA.
- Bind a profile to a particular user.
- Change the permissions granted by an account assignment.
- Prevent the operator from manually opening the URL in the wrong browser.

The operator must still clear stale state and verify the resulting AWS
identity.

## Private browser windows on Ubuntu

After starting a login with `--no-browser`, copy the exact URL printed by the
CLI and open a private window manually.

Firefox:

```bash
firefox --private-window
```

Chromium:

```bash
chromium --incognito
```

Google Chrome:

```bash
google-chrome --incognito
```

Paste the verification URL into that window and enter the displayed code.
Authenticate as the intended named user, provide the password, complete MFA,
and approve the request.

MFA is normally a second factor rather than a replacement for the Identity
Center password:

```text
username → password → MFA → SSO session
```

Terraform creates Identity Center user records but does not activate users,
set passwords, or register MFA devices.

### Private-window isolation caveat

Concurrent private windows from the same browser commonly share one temporary
private browsing session. Opening a second Firefox private window while the
first remains open may therefore reuse the first identity's cookies.

When switching identities, either:

1. close **all** private windows before opening the next one; or
2. use different browsers, such as Firefox private mode for test user 1 and
   Chromium incognito mode for test user 2; or
3. use separate persistent browser profiles dedicated to each identity.

Using different browsers provides the clearest separation during exercises.

## Recommended login sequence for different test users

Clear cached CLI sessions first:

```bash
aws sso logout
```

Sign out of the AWS access portal and close all private windows. Then authorize
the source profile:

```bash
aws sso login \
  --profile week2-source \
  --use-device-code \
  --no-browser
```

Open the URL in a private browser context, authenticate as the user configured
by `TF_VAR_test_user1_email`, and complete MFA. Verify immediately:

```bash
aws sts get-caller-identity --profile week2-source
```

Close that private browser context before authorizing the target profile:

```bash
aws sso login \
  --profile week2-target \
  --use-device-code \
  --no-browser
```

Authenticate as the user configured by `TF_VAR_test_user2_email`, complete MFA,
and verify:

```bash
aws sts get-caller-identity --profile week2-target
```

The profiles should report their expected lab accounts and an assumed role
containing:

```text
AWSReservedSSO_WorkloadLabAdministrator_
```

## Recommended login sequence for the lab administrator

The two lab administrator profiles share one `lab-admin` SSO session because
they represent the same human. Authenticate through either profile:

```bash
aws sso login \
  --profile lab-admin-dev \
  --use-device-code \
  --no-browser
```

Authenticate as the user configured by `TF_VAR_sso_lab_admin_email` and
complete MFA. Then verify both account profiles:

```bash
aws sts get-caller-identity --profile lab-admin-dev
aws sts get-caller-identity --profile lab-admin-test
```

Both roles should contain:

```text
AWSReservedSSO_WorkloadLabBaselineAdmin_
```

The first profile must report `TF_LAB_DEV_ACCOUNT_ID`; the second must report
`TF_LAB_TEST_ACCOUNT_ID`.

## Troubleshooting checklist

If the wrong role or user appears:

1. Run `aws sso logout`.
2. Sign out of the access portal in the browser.
3. Close every private window for that browser.
4. Confirm the profile references the intended `sso_session`, account ID, and
   permission-set name.
5. Repeat login with `--use-device-code --no-browser`.
6. Authenticate in a deliberately selected private browser context.
7. Complete MFA when required.
8. Run `aws sts get-caller-identity --profile <AWS_PROFILE>` immediately.
9. Stop if the account or role is unexpected.

If the correct user sees no expected role, inspect IAM Identity Center rather
than repeatedly reconfiguring the CLI. Verify:

- User activation and MFA registration.
- Group membership.
- Account assignment.
- Permission-set provisioning status.
- The account selected by the profile.
- Whether an existing browser session authorized a different identity.

Never add permissions merely to work around an unexplained SSO identity
mismatch.
