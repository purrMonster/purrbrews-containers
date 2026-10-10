# Offline regression checks; no scheduled tasks, firewall rules or real credentials.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
. (Join-Path $repo 'init/lib/windows-runtime.ps1')
$assertPath = ${function:Assert-AdminOnlyPath}
Assert-AdminOnlyPath ([Environment]::GetFolderPath('ProgramFiles')) -Ancestor

function Assert-Rejected([scriptblock]$Action, [string]$Expected) {
    try { & $Action } catch {
        if ($_.Exception.Message -notlike "*$Expected*") { throw }
        return
    }
    throw "Expected rejection: $Expected"
}

$acl = New-AdminOnlyDirectoryAcl
Assert-AdminOnlyAcl $acl 'fixture'
if (-not $acl.AreAccessRulesProtected) { throw 'Runtime ACL inherits permissions' }
$fileAcl = New-AdminOnlyFileAcl
Assert-AdminOnlyAcl $fileAcl 'file-fixture'
if (-not $fileAcl.AreAccessRulesProtected) { throw 'Runtime file ACL inherits permissions' }
foreach ($sddl in @(
    'O:BAG:BAD:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)(A;OICI;FW;;;BU)',
    'O:BAG:BAD:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)(A;OICI;FR;;;BU)',
    'O:BUG:BAD:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)'
)) {
    $unsafe = New-Object Security.AccessControl.DirectorySecurity
    $unsafe.SetSecurityDescriptorSddlForm($sddl)
    Assert-Rejected { Assert-AdminOnlyAcl $unsafe 'fixture' } 'SYSTEM runtime path'
}
$parentAcl = New-Object Security.AccessControl.DirectorySecurity
$parentAcl.SetSecurityDescriptorSddlForm('O:BAG:BAD:P(A;OICI;FA;;;BA)(A;;FR;;;BU)')
Assert-AdminOnlyAcl $parentAcl 'parent' -Ancestor
$parentAcl.SetSecurityDescriptorSddlForm('O:BAG:BAD:P(A;OICI;FA;;;BA)(A;;0x40;;;BU)')
Assert-Rejected { Assert-AdminOnlyAcl $parentAcl 'parent' -Ancestor } 'Non-administrator'

# Exercise atomic directory/file creation with current-user ACLs in a fixture.
# The production ACL factories and validation above were tested independently;
# no elevation or actual SYSTEM installation is needed for the copy operations.
$fixture = Join-Path $repo ('graphify-out/verification/runtime-' + [guid]::NewGuid().ToString('N'))
$source = Join-Path $fixture 'source'
$target = Join-Path $fixture 'runtime'
New-Item -ItemType Directory -Path (Join-Path $source 'config/dynamic'), (Join-Path $source 'data') -Force | Out-Null
foreach ($name in @('start.ps1', 'traefik.exe', 'secrets.env.local', 'config/traefik.yml', 'config/dynamic/llama-swap.yml', 'data/acme.json')) {
    [IO.File]::WriteAllText((Join-Path $source $name), "fixture-$name")
}
$script:ValidatedPaths = @()
function Assert-AdminOnlyPath([string]$Path, [switch]$Ancestor) { $script:ValidatedPaths += $Path }
$fixtureSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$script:FixtureDirectoryAcl = New-Object Security.AccessControl.DirectorySecurity
$script:FixtureDirectoryAcl.SetSecurityDescriptorSddlForm("O:${fixtureSid}D:P(A;OICI;FA;;;$fixtureSid)")
$script:FixtureFileAcl = New-Object Security.AccessControl.FileSecurity
$script:FixtureFileAcl.SetSecurityDescriptorSddlForm("O:${fixtureSid}D:P(A;;FA;;;$fixtureSid)")
function New-AdminOnlyDirectoryAcl { return $script:FixtureDirectoryAcl }
function New-AdminOnlyFileAcl { return $script:FixtureFileAcl }
$installed = Install-TraefikRuntime $source $target
if ($installed -ne $target) { throw 'Wrong runtime path' }
foreach ($name in @('start.ps1', 'traefik.exe', 'secrets.env.local', 'config/traefik.yml', 'config/dynamic/llama-swap.yml', 'data/acme.json')) {
    if ([IO.File]::ReadAllText((Join-Path $target $name)) -ne "fixture-$name") { throw "Missing installed file: $name" }
    if ([IO.Path]::GetFullPath((Join-Path $target $name)) -notin $script:ValidatedPaths) { throw "Missing ACL check: $name" }
}
[IO.File]::WriteAllText((Join-Path $source 'start.ps1'), 'changed-checkout')
if ([IO.File]::ReadAllText((Join-Path $target 'start.ps1')) -ne 'fixture-start.ps1') { throw 'Runtime follows source edits' }
[IO.File]::WriteAllText((Join-Path $target 'data/acme.json'), 'renewed-certificate')
Install-TraefikRuntime $source $target | Out-Null
if ([IO.File]::ReadAllText((Join-Path $target 'data/acme.json')) -ne 'renewed-certificate') { throw 'Existing certificate overwritten' }

$outside = Join-Path $fixture 'outside'
New-Item -ItemType Directory -Path $outside | Out-Null
New-Item -ItemType Junction -Path (Join-Path $source 'config/unsafe') -Target $outside | Out-Null
Assert-Rejected { & $assertPath (Join-Path $source 'config/unsafe') } 'Reparse points'
Assert-Rejected { Install-TraefikRuntime $source $target } 'Reparse points'
'Windows runtime regression checks passed: ACLs, protected copies, certificate retention and reparse refusal.'
