param(
    [string]$GamePath = 'C:\Program Files (x86)\Steam\steamapps\common\Napoleon Total War',
    [Parameter(Mandatory=$true)][string]$OutputDirectory
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2
if (-not ('Napoleon8Tools' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot 'lib\ModTools.cs') }
$modProfile = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'supported-build.json') -Raw | ConvertFrom-Json
$game = (Resolve-Path -LiteralPath $GamePath).Path
$dest = [IO.Path]::GetFullPath($OutputDirectory)
if (Test-Path -LiteralPath $dest) {
    if (@(Get-ChildItem -LiteralPath $dest -Force).Count) { throw 'Build output directory must be empty.' }
} else { $null = New-Item -ItemType Directory -Path $dest }

# All hashes are checked before constructing any installable replacement.
$inputs = @{}
foreach ($item in $modProfile.packInputs) {
    $bytes = [Napoleon8Tools]::ReadPackEntry((Join-Path $game $item.pack), $item.entry)
    [Napoleon8Tools]::RequireHash($bytes, $item.sha256, $item.entry)
    $inputs[$item.id] = $bytes
}
$replacements = @{}
foreach ($file in $modProfile.patchedFiles) {
    $bytes = [IO.File]::ReadAllBytes((Join-Path $game $file.path))
    [Napoleon8Tools]::RequireHash($bytes, $file.originalSha256, $file.path)
    if ($file.kind -eq 'startpos') {
        if (-not ('NapoleonStartposPatcher' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot 'lib\StartposPatcher.cs') }
        $scratchStartpos = Join-Path $dest 'startpos.generated'
        Write-Output ([NapoleonStartposPatcher]::Build((Join-Path $game $file.path), $scratchStartpos))
        $patched = [IO.File]::ReadAllBytes($scratchStartpos)
        Remove-Item -LiteralPath $scratchStartpos
    } elseif ($file.kind -eq 'bytes') {
        [int[]]$offsets = @($file.changes | ForEach-Object { [int]$_.offset })
        [byte[]]$before = @($file.changes | ForEach-Object { [byte]$_.before })
        [byte[]]$after = @($file.changes | ForEach-Object { [byte]$_.after })
        $patched = [Napoleon8Tools]::Patch($bytes, $offsets, $before, $after)
    } else { throw 'Unsupported patch kind in build profile.' }
    [Napoleon8Tools]::RequireHash($patched, $file.patchedSha256, $file.path + ' patched result')
    $replacements[$file.path] = $patched
}
$payloads = @{}
foreach ($payload in $modProfile.payloads) {
    $bytes = [IO.File]::ReadAllBytes((Join-Path $PSScriptRoot $payload.file))
    [Napoleon8Tools]::RequireHash($bytes, $payload.sha256, $payload.file)
    $payloads[$payload.entry] = $bytes
}

$sourceLayout = Join-Path $dest 'original-layout.bin'
$newLayout = Join-Path $dest 'eight-player-layout.bin'
[IO.File]::WriteAllBytes($sourceLayout, $inputs['lobby'])
& (Join-Path $PSScriptRoot 'lib\Build-NapoleonLobby.ps1') -Original $sourceLayout -Out $newLayout
$names = New-Object 'System.Collections.Generic.List[string]'
$contents = New-Object 'System.Collections.Generic.List[byte[]]'
$names.Add('ui\frontend ui\mp_grand_campaign')
$contents.Add([IO.File]::ReadAllBytes($newLayout))
foreach ($payload in $modProfile.payloads) { $names.Add($payload.entry); $contents.Add($payloads[$payload.entry]) }
$pack = [Napoleon8Tools]::MoviePack($names.ToArray(), $contents.ToArray())
[Napoleon8Tools]::RequireHash($pack, $modProfile.packSha256, 'Generated movie pack')
$replacements[$modProfile.packPath] = $pack

$report = @()
foreach ($relative in @($replacements.Keys | Sort-Object)) {
    $target = Join-Path $dest $relative
    $null = New-Item -ItemType Directory -Force -Path ([IO.Path]::GetDirectoryName($target))
    [IO.File]::WriteAllBytes($target, $replacements[$relative])
    $report += [pscustomobject]@{ path=$relative; sha256=[Napoleon8Tools]::Hash($replacements[$relative]); bytes=$replacements[$relative].Length }
}
foreach ($entry in $names) {
    $roundtrip = [Napoleon8Tools]::ReadPackEntry((Join-Path $dest $modProfile.packPath), $entry)
    [Napoleon8Tools]::RequireHash($roundtrip, [Napoleon8Tools]::Hash($contents[$names.IndexOf($entry)]), $entry + ' pack roundtrip')
}
Remove-Item -LiteralPath $sourceLayout, $newLayout
[pscustomobject]@{ version=$modProfile.version; validation='Static build; in-game multiplayer testing required'; files=$report } |
    ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $dest 'build-report.json') -Encoding UTF8
Write-Output "Build verified: $dest"
