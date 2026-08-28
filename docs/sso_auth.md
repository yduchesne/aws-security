# AWS CLI IAM Identity Center Authentication

## Purpose

This guide explains how AWS CLI IAM Identity Center authentication interacts
with browser sessions, private windows, MFA, and the device-authorization flow.
It is intended for developers who use several named identities or account
profiles on the same Ubuntu workstation.

No AWS password, MFA code, SSO access token, or device code belongs in an AWS
CLI configuration file, environment file, Terraform input, shell script, or
repository evidence.

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

- the CLI lists only permission sets belonging to another persona;
- an exercise profile receives the baseline administrator permission set;
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

- an AWS verification URL;
- a short-lived device authorization code;
- a message indicating that it is waiting for authorization.

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

- copy the verification URL printed by the CLI;
- choose a private or incognito window;
- choose a dedicated browser profile;
- use a different browser for each test identity;
- inspect which user is signing in before approving access.

It addresses accidental reuse of the default browser's authenticated session.
It does **not**:

- clear existing AWS CLI tokens;
- clear browser cookies;
- force Identity Center to request MFA;
- bind a profile to a particular user;
- change the permissions granted by an account assignment;
- prevent the operator from manually opening the URL in the wrong browser.

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

- user activation and MFA registration;
- group membership;
- account assignment;
- permission-set provisioning status;
- the account selected by the profile;
- whether an existing browser session authorized a different identity.

Never add permissions merely to work around an unexplained SSO identity
mismatch.
