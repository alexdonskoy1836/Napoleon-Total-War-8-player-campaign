param(
    [string]$GamePath = 'C:\Program Files (x86)\Steam\steamapps\common\Napoleon Total War',
    [switch]$Uninstall,
    [switch]$VerifyOnly
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2
if ($Uninstall -and $VerifyOnly) { throw 'Choose either Uninstall or VerifyOnly.' }
if (-not ('Napoleon8Tools' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot 'lib\ModTools.cs') }
$modProfile = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'supported-build.json') -Raw | ConvertFrom-Json
$game = (Resolve-Path -LiteralPath $GamePath).Path.TrimEnd('\')
$backupDir = Join-Path $game 'napoleon8_backup'
$manifestPath = Join-Path $backupDir 'installed.json'
$packPath = Join-Path $game $modProfile.packPath
function FileHash([string]$path) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    return [Napoleon8Tools]::Hash([IO.File]::ReadAllBytes($path))
}
function AssertClosed {
    if (Get-Process -Name Napoleon -ErrorAction SilentlyContinue) { throw 'Close Napoleon before installing or uninstalling.' }
}
function AtomicReplace([string]$source, [string]$target, [string]$expectedHash) {
    $pending = $target + '.ntw8-' + [Guid]::NewGuid().ToString('N') + '.tmp'
    try {
        [IO.File]::Copy($source, $pending, $false)
        if ((FileHash $pending) -ne $expectedHash) { throw 'Staged replacement failed its hash check.' }
        [IO.File]::Replace($pending, $target, [NullString]::Value)
    } finally {
        if (Test-Path -LiteralPath $pending) { Remove-Item -LiteralPath $pending -Force }
    }
}
function VerifyInstalled {
    foreach ($file in $modProfile.patchedFiles) {
        if ((FileHash (Join-Path $game $file.path)) -ne $file.patchedSha256) { throw "Installed file differs: $($file.path). No changes made." }
    }
    if ((FileHash $packPath) -ne $modProfile.packSha256) { throw 'The installed eight-player pack is missing or changed. No changes made.' }
}
function CheckManifest {
    $state = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    if ($state.version -ne $modProfile.version -or $state.gamePath -ne $game) { throw 'Backup belongs to a different version or game folder. Keep it; do not overwrite it.' }
}

if ($VerifyOnly) {
    if (-not (Test-Path -LiteralPath $manifestPath)) { throw 'This package is not installed in the selected game folder.' }
    CheckManifest
    VerifyInstalled
    Write-Output "Installation verified. Match code: $($modProfile.matchCode)"
    Write-Output 'This checks the mod files only, not all other game files or mods.'
    exit 0
}
AssertClosed

if ($Uninstall) {
    if (-not (Test-Path -LiteralPath $manifestPath)) {
        if ((Test-Path -LiteralPath $backupDir) -and -not (Test-Path -LiteralPath (Join-Path $backupDir 'uninstalled.json'))) {
            throw 'An incomplete backup folder exists. Inspect it before recovery; nothing was changed.'
        }
        if ((FileHash $packPath) -eq $modProfile.packSha256) { throw 'Mod pack found without its installation record. Nothing was changed.' }
        foreach ($file in $modProfile.patchedFiles) {
            if ((FileHash (Join-Path $game $file.path)) -eq $file.patchedSha256) { throw 'Patched game file found without its installation record. Nothing was changed.' }
        }
        Write-Output 'This package is not installed. Nothing changed.'
        exit 0
    }
    CheckManifest
    # Preflight every file before restoring anything. Steam-restored originals are okay.
    foreach ($file in $modProfile.patchedFiles) {
        $current = FileHash (Join-Path $game $file.path)
        if ($current -ne $file.patchedSha256 -and $current -ne $file.originalSha256) { throw "Refusing to replace changed file: $($file.path). Backups retained." }
        $backup = Join-Path $backupDir $file.path
        if ((FileHash $backup) -ne $file.originalSha256) { throw "Original backup is missing or changed: $backup" }
    }
    $packHash = FileHash $packPath
    if ($packHash -and $packHash -ne $modProfile.packSha256) { throw 'Refusing to remove a changed mod pack. Backups retained.' }
    # Originals remain backed up if Windows interrupts any restore operation.
    foreach ($file in $modProfile.patchedFiles) {
        if ((FileHash (Join-Path $game $file.path)) -ne $file.originalSha256) {
            AtomicReplace (Join-Path $backupDir $file.path) (Join-Path $game $file.path) $file.originalSha256
        }
        if ((FileHash (Join-Path $game $file.path)) -ne $file.originalSha256) { throw 'Restore verification failed. Backups retained.' }
    }
    if ($packHash) { Remove-Item -LiteralPath $packPath }
    # Keep original backups and a receipt; a future install can reuse this verified backup.
    Move-Item -LiteralPath $manifestPath -Destination (Join-Path $backupDir 'uninstalled.json') -Force
    Write-Output 'Uninstalled. Original executable and Europe startpos restored; mod pack removed.'
    Write-Output "Original backups retained at: $backupDir"
    exit 0
}

if (Test-Path -LiteralPath $manifestPath) {
    CheckManifest
    VerifyInstalled
    Write-Output "Already installed and verified. Match code: $($modProfile.matchCode)"
    exit 0
}
if (Test-Path -LiteralPath $packPath) { throw 'A pack already exists at the mod destination. Nothing was overwritten.' }
foreach ($file in $modProfile.patchedFiles) {
    if ((FileHash (Join-Path $game $file.path)) -ne $file.originalSha256) { throw "Unsupported or modified $($file.path). Nothing changed. See README.md." }
    $existingBackup = Join-Path $backupDir $file.path
    if ((Test-Path -LiteralPath $existingBackup) -and (FileHash $existingBackup) -ne $file.originalSha256) { throw "Existing backup differs: $existingBackup" }
}

# Build in a unique temporary directory before replacing any game file.
$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
$stage = Join-Path $tempRoot ('napoleon8-' + [Guid]::NewGuid().ToString('N'))
$pendingPack = $packPath + '.' + [Guid]::NewGuid().ToString('N') + '.pending'
$mutating = $false
try {
    & (Join-Path $PSScriptRoot 'build.ps1') -GamePath $game -OutputDirectory $stage
    AssertClosed
    $null = New-Item -ItemType Directory -Force -Path $backupDir
    foreach ($file in $modProfile.patchedFiles) {
        # Recheck in case Steam or another program changed a file during the build.
        if ((FileHash (Join-Path $game $file.path)) -ne $file.originalSha256) { throw 'A game file changed during the build.' }
        $backup = Join-Path $backupDir $file.path
        $null = New-Item -ItemType Directory -Force -Path ([IO.Path]::GetDirectoryName($backup))
        if (-not (Test-Path -LiteralPath $backup)) { Copy-Item -LiteralPath (Join-Path $game $file.path) -Destination $backup }
        if ((FileHash $backup) -ne $file.originalSha256) { throw 'Backup verification failed.' }
    }
    if (Test-Path -LiteralPath $packPath) { throw 'A mod pack appeared during the build.' }
    # Write the recovery record first so a power loss cannot hide a partial install.
    [pscustomobject]@{ version=$modProfile.version; gamePath=$game; createdUtc=[DateTime]::UtcNow.ToString('o'); matchCode=$modProfile.matchCode } |
        ConvertTo-Json | Set-Content -LiteralPath $manifestPath -Encoding UTF8
    $mutating = $true
    foreach ($file in $modProfile.patchedFiles) {
        AtomicReplace (Join-Path $stage $file.path) (Join-Path $game $file.path) $file.patchedSha256
    }
    # A partially copied pack must never appear under an auto-loaded .pack name.
    [IO.File]::Copy((Join-Path $stage $modProfile.packPath), $pendingPack, $false)
    if ((FileHash $pendingPack) -ne $modProfile.packSha256) { throw 'Pending pack failed verification.' }
    [IO.File]::Move($pendingPack, $packPath)
    VerifyInstalled
    Write-Output "Installed experimental Napoleon eight-player campaign. Match code: $($modProfile.matchCode)"
    Write-Output 'All players must install the identical package. Start with a NEW Europe multiplayer campaign.'
    Write-Output 'Read TEST-IN-GAME.md before your first session. Eight-client gameplay is not yet verified.'
} catch {
    $failure = $_
    if ($mutating) {
        try {
            foreach ($file in $modProfile.patchedFiles) {
                if ((FileHash (Join-Path $game $file.path)) -ne $file.originalSha256) {
                    AtomicReplace (Join-Path $backupDir $file.path) (Join-Path $game $file.path) $file.originalSha256
                }
            }
            if ((FileHash $packPath) -eq $modProfile.packSha256) { Remove-Item -LiteralPath $packPath }
            foreach ($file in $modProfile.patchedFiles) {
                if ((FileHash (Join-Path $game $file.path)) -ne $file.originalSha256) { throw 'Rollback verification failed.' }
            }
            Move-Item -LiteralPath $manifestPath -Destination (Join-Path $backupDir 'uninstalled.json') -Force
            Write-Warning 'Installation failed; original game files restored.'
        } catch { Write-Warning "Automatic rollback could not finish. Original backups remain at $backupDir. $($_.Exception.Message)" }
    }
    throw $failure
} finally {
    if (Test-Path -LiteralPath $pendingPack) { Remove-Item -LiteralPath $pendingPack -Force }
    # This is the unique directory this invocation created under the resolved temp root.
    $resolvedStage = [IO.Path]::GetFullPath($stage)
    if ($resolvedStage.StartsWith($tempRoot + '\', [StringComparison]::OrdinalIgnoreCase) -and
        [IO.Path]::GetFileName($resolvedStage) -match '^napoleon8-[0-9a-f]{32}$' -and
        (Test-Path -LiteralPath $resolvedStage)) { Remove-Item -LiteralPath $resolvedStage -Recurse -Force }
}
