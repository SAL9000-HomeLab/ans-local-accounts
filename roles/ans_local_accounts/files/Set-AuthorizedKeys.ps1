[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string[]]$Keys,
    [bool]$Exclusive = $false
)

# Writes a user's SSH authorized_keys under their existing profile. A user with no profile on the host is reported and
# left alone: the role does not create Windows accounts, and a profile only appears after the first logon.
$ErrorActionPreference = 'Stop'
$Ansible.Changed = $false
$Ansible.Result = @{ status = 'no_profile'; path = $null }

# Finds profiles by account name. "name" matches any account with that name and "DOMAIN\name" only that account.
# Profiles whose SID no longer resolves to an account are ignored.
$profiles = @(
    foreach ($candidate in Get-CimInstance -ClassName Win32_UserProfile -Filter 'Special = FALSE') {
        try {
            $account = ([System.Security.Principal.SecurityIdentifier]$candidate.SID).Translate(
                [System.Security.Principal.NTAccount]).Value
        }
        catch {
            continue
        }
        $matched = if ($Name.Contains('\')) { $account -ieq $Name } else { $account.Split('\')[-1] -ieq $Name }
        if ($matched -and (Test-Path -LiteralPath $candidate.LocalPath)) { $candidate }
    }
)

if ($profiles.Count -eq 0) { return }
if ($profiles.Count -gt 1) {
    $paths = ($profiles | ForEach-Object LocalPath) -join ', '
    throw "More than one profile matches '$Name' ($paths). Use DOMAIN\name to pick one."
}

$sid = $profiles[0].SID
$sshDirectory = Join-Path -Path $profiles[0].LocalPath -ChildPath '.ssh'
$file = Join-Path -Path $sshDirectory -ChildPath 'authorized_keys'
$Ansible.Result.path = $file

$current = @()
if (Test-Path -LiteralPath $file) {
    $current = @(Get-Content -LiteralPath $file | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}
$wanted = @($Keys | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Select-Object -Unique)
if (-not $Exclusive) {
    $wanted = @($current) + @($wanted | Where-Object { $current -cnotcontains $_ })
}
$contentChanged = ($current -join "`n") -cne ($wanted -join "`n")

# sshd refuses the file unless only the user, SYSTEM and Administrators can write to it, and one of them owns it.
$systemSid = 'S-1-5-18'
$adminsSid = 'S-1-5-32-544'
$aclChanged = $true
if (Test-Path -LiteralPath $file) {
    $acl = Get-Acl -LiteralPath $file
    $sidType = [System.Security.Principal.SecurityIdentifier]
    $rules = @($acl.GetAccessRules($true, $true, $sidType))
    $ruleSids = @($rules | ForEach-Object { $_.IdentityReference.Value } | Sort-Object)
    $aclChanged = -not (
        $acl.AreAccessRulesProtected -and
        ($acl.GetOwner($sidType).Value -in @($sid, $systemSid, $adminsSid)) -and
        (($ruleSids -join ',') -eq ((@($sid, $systemSid, $adminsSid) | Sort-Object) -join ',')) -and
        -not ($rules | Where-Object {
                $_.AccessControlType -ne 'Allow' -or
                $_.FileSystemRights -ne [System.Security.AccessControl.FileSystemRights]::FullControl
            })
    )
}

if ($contentChanged -or $aclChanged) {
    $Ansible.Changed = $true
    $Ansible.Result.status = 'updated'
}
else {
    $Ansible.Result.status = 'unchanged'
}
if ($Ansible.CheckMode -or -not $Ansible.Changed) { return }

if (-not (Test-Path -LiteralPath $sshDirectory)) {
    New-Item -Path $sshDirectory -ItemType Directory | Out-Null
}
if ($contentChanged -or -not (Test-Path -LiteralPath $file)) {
    $text = if ($wanted.Count -gt 0) { ($wanted -join "`n") + "`n" } else { '' }
    [System.IO.File]::WriteAllText($file, $text, (New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $false))
}
if ($aclChanged) {
    $security = New-Object -TypeName System.Security.AccessControl.FileSecurity
    $security.SetSecurityDescriptorSddlForm(
        "D:PAI(A;;FA;;;$sid)(A;;FA;;;SY)(A;;FA;;;BA)", [System.Security.AccessControl.AccessControlSections]::Access)
    [System.IO.File]::SetAccessControl($file, $security)
    & icacls.exe $file /setowner "*$sid" /q | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "icacls could not make $sid the owner of $file (exit code $LASTEXITCODE)." }
}
