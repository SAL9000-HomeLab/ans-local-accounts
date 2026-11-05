# Changelog

All notable changes to this project are documented here. Releases are cut by
pushing a `vX.Y.Z` tag; the release workflow publishes the matching section.

## [Unreleased]

- Changed: On Windows the role no longer creates users, until password handling is decided. A listed user that does not
  exist is reported and left out of group membership.
- Added: On Windows, `authorized_keys` and `authorized_keys_exclusive` write the user's `.ssh\authorized_keys` when the
  user has a profile on the host, including domain users. Users with no profile are reported and skipped.
- Changed: `ansible.windows` is at least 3.1.0.
- Added: `ans_local_accounts` role, which manages local users, groups and group membership on Linux and Windows,
  plus SSH authorized keys and sudo rules on Linux.
