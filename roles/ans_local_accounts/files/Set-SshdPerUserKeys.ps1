[CmdletBinding(SupportsShouldProcess)]
param()

# Makes sshd read each user's own .ssh\authorized_keys, including for members of Administrators. Windows OpenSSH's
# default sshd_config sends those members to a shared file instead, with an AuthorizedKeysFile line under
# "Match Group administrators". Only that line is commented out: anything else in the block must stay limited to
# administrators, and an empty Match block is valid.
$ErrorActionPreference = 'Stop'
$Ansible.Changed = $false
$Ansible.Result = @{ status = 'not_installed'; admin_keys_ignored = $false }

$service = Get-CimInstance -ClassName Win32_Service -Filter "Name = 'sshd'"
if (-not $service) { return }

$sshDirectory = Join-Path -Path $env:ProgramData -ChildPath 'ssh'
$config = Join-Path -Path $sshDirectory -ChildPath 'sshd_config'
if (-not (Test-Path -LiteralPath $config)) {
    # sshd creates the file the first time it starts.
    $Ansible.Result.status = 'no_config'
    return
}

$original = [System.IO.File]::ReadAllText($config)
$inAdminBlock = $false
$updated = (
    $original -split '(?<=\n)' | ForEach-Object {
        if ($_ -match '^\s*Match\s') {
            $inAdminBlock = $_ -match '^\s*Match\s+Group\s+"?administrators"?\s*(#.*)?$'
        }
        if ($inAdminBlock -and $_ -match '^\s*AuthorizedKeysFile[\s=]') { "#$_" } else { $_ }
    }
) -join ''

if ($updated -ceq $original) {
    $Ansible.Result.status = 'unchanged'
    return
}

$Ansible.Changed = $true
$Ansible.Result.status = 'updated'

# Keys in the shared file stop working once sshd is restarted.
$adminKeys = Join-Path -Path $sshDirectory -ChildPath 'administrators_authorized_keys'
if (Test-Path -LiteralPath $adminKeys) {
    $Ansible.Result.admin_keys_ignored = [bool](
        Get-Content -LiteralPath $adminKeys | Where-Object { $_.Trim() -and -not $_.Trim().StartsWith('#') })
}

if ($Ansible.CheckMode) { return }

# Check the new file before it replaces the one sshd is using.
$sshd = if ($service.PathName -match '^\s*(?:"([^"]+)"|(\S+))') { "$($Matches[1])$($Matches[2])" }
$encoding = New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $false
$candidate = "$config.ans-new"
try {
    [System.IO.File]::WriteAllText($candidate, $updated, $encoding)
    # Windows PowerShell turns a native command's stderr into a terminating error when this is Stop.
    $ErrorActionPreference = 'Continue'
    $output = & $sshd -t -f $candidate 2>&1
    $exitCode = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    if ($exitCode -ne 0) { throw "sshd rejected the new configuration, nothing was changed: $($output -join ' ')" }
    # Writing over the file, rather than moving the new one into place, keeps its owner and permissions.
    [System.IO.File]::WriteAllText($config, $updated, $encoding)
}
finally {
    Remove-Item -LiteralPath $candidate -Force -ErrorAction SilentlyContinue
}

if ($service.State -eq 'Running') { Restart-Service -Name sshd }
