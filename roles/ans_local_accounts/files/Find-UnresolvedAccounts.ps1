[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string[]]$Name
)

# Returns the account names that do not resolve to a SID on this host, such as a domain group on a host that is not
# joined to that domain, or a domain whose controllers cannot be reached. Changes nothing, so it also runs in check
# mode (SupportsShouldProcess).
$ErrorActionPreference = 'Stop'
$Ansible.Changed = $false

$unresolved = @(
    foreach ($account in $Name) {
        try {
            $null = ([System.Security.Principal.NTAccount]$account).Translate(
                [System.Security.Principal.SecurityIdentifier])
        }
        catch {
            $account
        }
    }
)

$Ansible.Result = @{ unresolved = $unresolved }
