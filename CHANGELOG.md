# Changelog

All notable changes to this project are documented here. Releases are cut by
pushing a `vX.Y.Z` tag; the release workflow publishes the matching section.

## [Unreleased]

- Added: `create: false` on a Linux user, for accounts the role must not create or remove, such as AD users through
  SSSD. When the account resolves, the role creates its home directory if missing (`mkhomedir_helper`) and manages its
  groups and keys; when it does not, it is reported and skipped. An exclusive group with such a member is left unchanged.
- Added: On Windows, group members named `DOMAIN\name` that do not resolve on the host (not joined to that domain, or no
  domain controller reachable) are reported and left out instead of failing the run. An exclusive group with such a
  member is left unchanged. This replaces the domain administrators group task in ans-defos.
- Changed: On Windows the role no longer creates users, until password handling is decided. A listed user that does not
  exist is reported and left out of group membership.
- Added: On Windows, `authorized_keys` and `authorized_keys_exclusive` write the user's `.ssh\authorized_keys` when the
  user has a profile on the host, including domain users. Users with no profile are reported and skipped.
- Added: On Windows hosts with sshd, members of Administrators use their own `authorized_keys` instead of the shared
  `administrators_authorized_keys`, which stops working (`ans_local_accounts_windows_sshd_per_user_keys`, on by default).
- Changed: `ansible.windows` is at least 3.1.0.
- Added: `ans_local_accounts` role, which manages local users, groups and group membership on Linux and Windows,
  plus SSH authorized keys and sudo rules on Linux.
