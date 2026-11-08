# ans-local-accounts

Manages local users, local groups and group membership on Linux and Windows hosts with one role,
`ans_local_accounts`, driven by the same two lists on both. It also manages SSH authorized keys on both, and sudo rules
on Linux. On Windows it does not create users. It is meant to be included from [ans-defos] as part of the default OS
configuration, and [site.yml](site.yml) runs it on its own.

Only the accounts in the lists are touched: other users and groups on the host are left alone, and group
membership is only added unless a group is marked `exclusive`.

## Requirements

| Requirement | Version |
| --- | --- |
| ansible-core | >= 2.16 (tested on 2.19 and 2.21) |
| Python | >= 3.10 |

- Linux targets: RHEL/Rocky 9 and 10, Ubuntu 24.04, reached over SSH with `become`. `gpasswd` and `visudo` must be
  installed (they are on all of these).
- Windows targets: Windows Server 2019, 2022 or 2025, reached over PSRP as an administrator. The controller needs
  the Python packages in [requirements.txt](requirements.txt).
- Collections: `ansible.posix` and `ansible.windows`, from [requirements.yml](requirements.yml).

The role gathers the `min` fact subset itself when facts were not gathered, so it works under plays with
`gather_facts: false`.

## Variables

Defaults and the full list of keys are in
[roles/ans_local_accounts/defaults/main.yml](roles/ans_local_accounts/defaults/main.yml).

| Variable | Default | Purpose |
| --- | --- | --- |
| `ans_local_accounts_groups` | `[]` | Local groups to create or remove, and their members. |
| `ans_local_accounts_users` | `[]` | Local users to create or remove, and the groups they belong to. |
| `ans_local_accounts_groups_exclusive` | `false` | Default for a group's `exclusive` key. |
| `ans_local_accounts_authorized_keys_exclusive` | `false` | Default for a user's `authorized_keys_exclusive` key. |
| `ans_local_accounts_remove_home` | `false` | Linux: delete the home directory when a user is removed. |
| `ans_local_accounts_sudoers_prefix` | `ans_local_accounts-` | Linux: prefix of the files written to `/etc/sudoers.d`. |

Keys for each group:

| Key | OS | Purpose |
| --- | --- | --- |
| `name` | both | Group name (required). |
| `state` | both | `present` (default) or `absent`. |
| `members` | both | Accounts that must be members; local or domain (`DOMAIN\name` on Windows). |
| `exclusive` | both | `true` removes members that are not listed (here or in a user's `groups`). |
| `description` | Windows | Group description. |
| `gid`, `system` | Linux | Numeric group id; create a system group. |
| `sudo` | Linux | Sudoers rules for the group, written as `%name <rule>`. |

Keys for each user:

| Key | OS | Purpose |
| --- | --- | --- |
| `name` | both | User name (required). On Windows, `DOMAIN\name` selects a domain account for `groups` and `authorized_keys`. |
| `state` | both | `present` (default) or `absent`. On Windows, `present` does not create the user. |
| `groups` | both | Groups the user is added to. The groups must already exist or be in `ans_local_accounts_groups`. |
| `comment` | both | GECOS field on Linux, description on Windows. |
| `fullname`, `account_disabled`, `password_never_expires` | Windows | Passed to `win_user`; left as is when unset. |
| `uid`, `group`, `shell`, `home`, `create_home`, `system` | Linux | Passed to the `user` module. |
| `create` | Linux | `false` for an account the role must not create or remove, such as an AD user through SSSD (default `true`). |
| `authorized_keys` | both | SSH public keys. On Windows, written only when the user has a profile on the host. |
| `authorized_keys_exclusive` | both | `true` removes keys that are not listed. |
| `sudo` | Linux | Sudoers rules for the user, written as `name <rule>`. |

Example, in group vars or the AWX inventory:

```yaml
ans_local_accounts_groups:
  - name: appadmins
    sudo: ["ALL=(ALL) NOPASSWD: ALL"]
  - name: Administrators              # Windows built-in group: domain group as local administrators
    members: ['EXAMPLE\ServerAdmins']
  - name: Remote Desktop Users        # Windows built-in group
    members: ['EXAMPLE\Support']
ans_local_accounts_users:
  - name: deploy
    comment: Deployment account
    groups: [appadmins]
    authorized_keys:
      - ssh-ed25519 AAAA... deploy@example
  - name: olduser
    state: absent
```

## Behavior

- **Order:** groups are created, then users, then membership, keys and sudo rules; removed users and groups go
  last.
- **Membership:** a group's members are its `members` plus every present user that lists it in `groups`. On Linux
  the role runs `gpasswd` only when `/etc/group` differs, so reruns report no changes. On Windows it uses
  `win_group_membership` (`state: pure` for exclusive groups).
- **Windows domain members:** members named `DOMAIN\name` are looked up on the host first. Those that do not
  resolve, because the host is not joined to that domain or its domain controllers cannot be reached, are reported and
  left out, so one inventory can give a domain group to every Windows host. An exclusive group with such a member is
  reported and not changed at all, since `state: pure` would remove a member that may still be in the group.
- **Exclusive groups:** use them with care on built-in groups such as `Administrators` or `wheel`. Every member that
  is not listed is removed, including built-in accounts and domain groups.
- **Sudo:** each user and group in the lists gets its own file, `/etc/sudoers.d/<prefix>user-<name>` or
  `<prefix>group-<name>`, checked with `visudo` before it is installed. Dots in names become underscores, because
  sudo ignores files with a dot in the name. The file is removed when `sudo` is empty or the account is absent.
  Files for accounts no longer in the lists at all are not cleaned up; set the account to `state: absent` first.
- **Passwords:** the role does not set passwords. New Linux accounts are created locked: SSH key login still works
  (with the default `UsePAM yes`), password login does not.
- **Accounts the role does not create (Linux):** a user with `create: false` is looked up through NSS
  (`getent passwd <name>`), so domain users from SSSD are found. If it resolves, the role creates its home directory
  when missing (with `mkhomedir_helper`, as `pam_mkhomedir` does at first login, mode 0700, then `restorecon` where
  SELinux is on), adds it to groups, and writes its keys and sudo rules. If it does not resolve, for example on a host
  not joined to the domain, it is reported and only its sudo rules are written. An exclusive group with such a member
  is reported and left unchanged. `state: absent` removes its sudo rules but never the account. Example, for hosts
  joined with [ans-ldap-auth] using short names:

  ```yaml
  ans_local_accounts_users:
    - name: jdoe                      # AD user, not EXAMPLE\jdoe
      create: false
      authorized_keys:
        - ssh-ed25519 AAAA... jdoe@example
  ```

- **Windows users:** the role does not create them, until password handling is decided. A listed user that does not
  exist is reported and left out of group membership. Existing users have their `comment`, `fullname`,
  `account_disabled` and `password_never_expires` updated, and `state: absent` still removes them.
- **Windows authorized keys:** for each listed user with `authorized_keys`, the role looks for a profile on the host
  by account name. If there is one, it writes `.ssh\\authorized_keys` there and sets the file's owner and permissions
  the way sshd requires. If not, it reports the user and writes nothing; a profile appears after the first logon. This
  also works for domain users. When a short name matches more than one profile, the task fails and asks for
  `DOMAIN\name`.
- **Windows administrators and SSH:** the default Windows `sshd_config` has `Match Group administrators`, which makes
  sshd read `ProgramData\\ssh\\administrators_authorized_keys` for members of Administrators and ignore the file in
  their profile. Where sshd is installed, the role comments out the `AuthorizedKeysFile` line in that block, so everyone
  uses their own file. It checks the result with `sshd -t` first and restarts sshd if it is running. Keys in the shared
  file stop working, and the role reports when that file has any. Turn this off with
  `ans_local_accounts_windows_sshd_per_user_keys: false`. The role does not install OpenSSH: run it after whatever does,
  and after sshd has started once, because that creates `sshd_config`.

## Inventory

[site.yml](site.yml) runs the role on the `linux` group (with `become`) and the `windows` group (over PSRP), as in
the placeholder [inventory/hosts.yml](inventory/hosts.yml). Put real hosts in the AWX inventory, or in a gitignored
`local/` copy.

## Development and CI

The workflows and lint configs are the shared ones from `ans-template`:

- **Ansible CI** (`.github/workflows/ansible-ci.yml`), on every pull request: `yamllint`,
  `ansible-playbook --syntax-check site.yml`, `ansible-lint`.
- **Linting Validation** (`.github/workflows/ci.yml`), on pull requests: markdownlint, linkspector, yamllint.

Run the same checks locally:

```sh
python3 -m venv .venv && . .venv/bin/activate
pip install "ansible-core>=2.16" "ansible-lint>=6" "yamllint>=1.30" -r requirements.txt
ansible-galaxy collection install -r requirements.yml
yamllint -f parsable .
ansible-playbook -i inventory/hosts.yml --syntax-check site.yml
ansible-lint .
npx markdownlint-cli2 "**/*.md" "#.venv"
```

Add a line under `## [Unreleased]` in [CHANGELOG.md](CHANGELOG.md) with each change. Pushing a `vX.Y.Z` tag
publishes that version's section as a GitHub release.

## License

MIT, see [LICENSE](LICENSE).

[ans-defos]: https://github.com/SAL9000-HomeLab/ans-defos
[ans-ldap-auth]: https://github.com/SAL9000-HomeLab/ans-ldap-auth
