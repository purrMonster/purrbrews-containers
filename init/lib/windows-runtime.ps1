# Helpers for installing code executed as SYSTEM. Dot-source; no actions at import.
function New-AdminOnlyDirectoryAcl {
    $acl = New-Object Security.AccessControl.DirectorySecurity
    $acl.SetSecurityDescriptorSddlForm('O:BAG:BAD:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)')
    return $acl
}

function New-AdminOnlyFileAcl {
    $acl = New-Object Security.AccessControl.FileSecurity
    $acl.SetSecurityDescriptorSddlForm('O:BAG:BAD:P(A;;FA;;;SY)(A;;FA;;;BA)')
    return $acl
}

function Copy-AdminOnlyFile([string]$Source, [string]$Destination) {
    $inputStream = [IO.File]::OpenRead($Source)
    try {
        $outputStream = New-Object IO.FileStream -ArgumentList @(
            $Destination, [IO.FileMode]::Create, [Security.AccessControl.FileSystemRights]::Write,
            [IO.FileShare]::None, 4096, [IO.FileOptions]::None, (New-AdminOnlyFileAcl))
        try { $inputStream.CopyTo($outputStream) } finally { $outputStream.Dispose() }
    } finally { $inputStream.Dispose() }
}

function Assert-AdminOnlyAcl($Acl, [string]$Path, [switch]$Ancestor) {
    $trusted = @('S-1-5-18', 'S-1-5-32-544',
        'S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464') # TrustedInstaller
    if ($Acl.GetOwner([Security.Principal.SecurityIdentifier]).Value -notin $trusted) {
        throw "Untrusted owner on SYSTEM runtime path: $Path"
    }
    $rights = [Security.AccessControl.FileSystemRights]
    $mutation = $rights::Delete -bor $rights::DeleteSubdirectoriesAndFiles -bor
                $rights::ChangePermissions -bor $rights::TakeOwnership -bor
                $rights::WriteData -bor $rights::WriteAttributes
    if (-not $Ancestor) {
        $mutation = $mutation -bor $rights::AppendData -bor $rights::WriteExtendedAttributes
    }
    foreach ($rule in $Acl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier])) {
        if ($rule.PropagationFlags -band [Security.AccessControl.PropagationFlags]::InheritOnly) { continue }
        if ($rule.AccessControlType -eq 'Allow' -and (-not $Ancestor -or ($rule.FileSystemRights -band $mutation)) -and
            $rule.IdentityReference.Value -notin $trusted) {
            throw "Non-administrator access on SYSTEM runtime path: $Path"
        }
    }
}

function Assert-AdminOnlyPath([string]$Path, [switch]$Ancestor) {
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        throw "Reparse points are not allowed in SYSTEM runtime paths: $Path"
    }
    Assert-AdminOnlyAcl (Get-Acl -LiteralPath $Path) $Path -Ancestor:$Ancestor
    $parent = if ($item.PSIsContainer) { $item.Parent } else { $item.Directory }
    if ($parent) { Assert-AdminOnlyPath $parent.FullName -Ancestor }
}

function Install-TraefikRuntime([string]$Source, [string]$Destination) {
    # Parent validation prevents a writable ancestor from replacing a protected
    # directory. Refuse unsafe existing trees instead of adopting their contents.
    Assert-AdminOnlyPath (Split-Path -Parent $Destination) -Ancestor
    if (-not (Test-Path -LiteralPath $Destination)) {
        # Windows PowerShell/.NET Framework creates the directory with its ACL
        # atomically: no interval in which an unprivileged writer can populate it.
        [IO.Directory]::CreateDirectory($Destination, (New-AdminOnlyDirectoryAcl)) | Out-Null
    }
    Assert-AdminOnlyPath $Destination
    foreach ($item in Get-ChildItem -LiteralPath $Destination -Force -Recurse) {
        Assert-AdminOnlyPath $item.FullName
    }
    foreach ($name in @('start.ps1', 'traefik.exe', 'secrets.env.local', 'config')) {
        $path = Join-Path $Source $name
        if (-not (Test-Path -LiteralPath $path)) { throw "Missing Traefik runtime input: $name" }
        $items = @(Get-Item -LiteralPath $path -Force)
        if ($items[0].PSIsContainer) { $items += @(Get-ChildItem -LiteralPath $path -Force -Recurse) }
        if (@($items | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }).Count) {
            throw "Reparse points are not allowed in Traefik runtime inputs: $name"
        }
    }
    # Explicit elevated installation is the trust boundary. Copy bytes, not source
    # ACLs, and keep later non-elevated edits in the checkout away from SYSTEM.
    foreach ($name in @('start.ps1', 'traefik.exe', 'secrets.env.local')) {
        Copy-AdminOnlyFile (Join-Path $Source $name) (Join-Path $Destination $name)
    }
    $config = Join-Path $Destination 'config'
    [IO.Directory]::CreateDirectory($config, (New-AdminOnlyDirectoryAcl)) | Out-Null
    foreach ($item in Get-ChildItem -LiteralPath (Join-Path $Source 'config') -Force -Recurse) {
        $relative = $item.FullName.Substring((Join-Path $Source 'config').Length).TrimStart('\')
        $target = Join-Path $config $relative
        if ($item.PSIsContainer) { [IO.Directory]::CreateDirectory($target, (New-AdminOnlyDirectoryAcl)) | Out-Null }
        else {
            [IO.Directory]::CreateDirectory((Split-Path -Parent $target), (New-AdminOnlyDirectoryAcl)) | Out-Null
            Copy-AdminOnlyFile $item.FullName $target
        }
    }
    $obsolete = Join-Path $config 'dynamic\ollama.yml'
    if (Test-Path -LiteralPath $obsolete) { Remove-Item -LiteralPath $obsolete -Force }
    $data = Join-Path $Destination 'data'
    [IO.Directory]::CreateDirectory($data, (New-AdminOnlyDirectoryAcl)) | Out-Null
    $certificate = Join-Path $data 'acme.json'
    $previous = Join-Path $Source 'data\acme.json'
    if (-not (Test-Path -LiteralPath $certificate) -and (Test-Path -LiteralPath $previous)) {
        if ((Get-Item -LiteralPath $previous -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw 'Certificate migration source must not be a reparse point'
        }
        Copy-AdminOnlyFile $previous $certificate
    }
    foreach ($item in Get-ChildItem -LiteralPath $Destination -Force -Recurse) {
        Assert-AdminOnlyPath $item.FullName
    }
    return $Destination
}
