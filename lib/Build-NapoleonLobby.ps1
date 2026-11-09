param(
    [Parameter(Mandatory=$true)][string]$Original,
    [Parameter(Mandatory=$true)][string]$Out
)
$ErrorActionPreference = 'Stop'
if (-not ('Layout' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot 'Layout039.cs') }
$originalBytes = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $Original))
$root = [Layout]::Read($originalBytes)
if (-not [Linq.Enumerable]::SequenceEqual($originalBytes, [Layout]::Write($root))) { throw 'Original layout failed lossless round-trip.' }

function Sub($node, $name) {
    $child = $node.List('children') | Where-Object { $_.Str('name') -eq $name } | Select-Object -First 1
    if (-not $child) { throw "Missing '$name' under '$($node.Str('name'))'." }
    return $child
}
function SetI($node, $name, $value) { $node.Field($name).V = [int]$value }
function XY($node, $x, $y) { SetI $node 'x' $x; SetI $node 'y' $y }
function Text($node, $name, $value) { $node.Field($name).V = [Text.Encoding]::Unicode.GetBytes($value) }
function Label($node, $x, $y, $w) {
    XY $node $x $y
    foreach ($state in $node.List('states')) { SetI $state 'w' $w; SetI $state 'a3' 1 }
}
function ResizeFrame($node, $width, $height) {
    foreach ($state in $node.List('states')) {
        $oldWidth = $state.I('w'); $oldHeight = $state.I('h')
        $dw = $width - $oldWidth; $dh = $height - $oldHeight
        foreach ($piece in $state.List('state_images')) {
            if ($piece.I('x') -ge ($oldWidth / 2)) { SetI $piece 'x' ($piece.I('x') + $dw) }
            elseif (($piece.I('x') + $piece.I('w')) -gt ($oldWidth / 2)) { SetI $piece 'w' ($piece.I('w') + $dw) }
            if ($piece.I('y') -ge ($oldHeight / 2)) { SetI $piece 'y' ($piece.I('y') + $dh) }
            elseif (($piece.I('y') + $piece.I('h')) -gt ($oldHeight / 2)) { SetI $piece 'h' ($piece.I('h') + $dh) }
            if ($piece.I('w') -lt 0 -or $piece.I('h') -lt 0) { throw 'Negative image dimensions after resizing slot frame.' }
        }
        SetI $state 'w' $width; SetI $state 'h' $height
    }
}

$main = [Layout]::FindComponent($root, 'main_panel')
$cartouche = Sub $main 'cartouche'
$p1 = Sub $cartouche 'player_1'
$p2 = Sub $cartouche 'player_2'
$oldKick = Sub $main 'button_kick'
$kickTemplate = [Layout]::DeepClone($oldKick)
$oldKick.SetStr('name', 'legacy_button_kick')
XY $oldKick 2000 2000

# Preserve the original map and lower settings/chat panels. Eight 176-pixel cards fit
# in four columns around the 510-pixel map. Parent remains a transparent container;
# each 64x64 player component still displays its unscaled Steam avatar.
XY $cartouche 0 0
$cartouche.List('images').Clear()
foreach ($state in $cartouche.List('states')) {
    SetI $state 'w' 1280; SetI $state 'h' 410
    $state.List('state_images').Clear()
}
$cartouche.Field('image_ref').V = [uint32]0
Label (Sub $cartouche 'season_year') 550 306 180
XY (Sub $cartouche 'turns_tx') 555 338
XY (Sub $main 'button_invite') 620 375

$taken = New-Object 'System.Collections.Generic.HashSet[uint32]'
foreach ($uid in [Layout]::AllU32($root)) { [void]$taken.Add($uid) }
$script:nextUid = [uint32]0x7E4E0001
$alloc = [Func[uint32]] {
    while ($taken.Contains($script:nextUid)) { $script:nextUid++ }
    $value = $script:nextUid
    [void]$taken.Add($value)
    $script:nextUid++
    return $value
}

$players = @($p1, $p2)
foreach ($number in 3..8) {
    $copy = [Layout]::DeepClone($p2)
    [void][Layout]::Reassign($copy, $alloc)
    $copy.SetStr('name', "player_$number")
    $cartouche.List('children').Add($copy)
    $players += $copy
}
$columns = @(8, 194, 910, 1096)
$placement = @(@(0,0), @(2,0), @(1,0), @(3,0), @(0,1), @(2,1), @(1,1), @(3,1))
# Static markers sit behind the player components so all eight positions remain
# visible when the player script hides empty slots. Reuse stock frame artwork.
$frameTemplate = [Layout]::DeepClone((Sub $main 'victory_conditions'))
$frameTemplate.List('children').Clear()
$frameTemplate.List('events').Clear()
$frameTemplate.List('anims').Clear()
$frameTemplate.SetStr('s2', '')
$frameTemplate.SetStr('template', '')
ResizeFrame $frameTemplate 176 174
$labelTemplate = [Layout]::DeepClone((Sub $p2 'dy_player_name'))
for ($index=0; $index -lt 8; $index++) {
    $number=$index+1
    $frame=[Layout]::DeepClone($frameTemplate)
    [void][Layout]::Reassign($frame,$alloc)
    $frame.SetStr('name', "slot_frame$number")
    XY $frame $columns[$placement[$index][0]] (4 + 182 * $placement[$index][1])
    $label=[Layout]::DeepClone($labelTemplate)
    [void][Layout]::Reassign($label,$alloc)
    $label.SetStr('name', "slot_label$number")
    Label $label 8 143 112
    foreach ($state in $label.List('states')) {
        Text $state 'text' "Player $number"
        Text $state 'w3' ''
    }
    $frame.List('children').Add($label)
    $cartouche.List('children').Insert($index,$frame)
}
for ($index=0; $index -lt 8; $index++) {
    $panel = $players[$index]
    $x = $columns[$placement[$index][0]] + 8
    $y = 12 + 182 * $placement[$index][1]
    XY $panel $x $y
    XY (Sub $panel 'border') 0 0
    XY (Sub $panel 'mini_flag') 88 18
    XY (Sub $panel 'status') 65 37
    XY (Sub $panel 'icon_voicechat') 68 7
    Label (Sub $panel 'dy_player_name') -4 72 168
    Label (Sub $panel 'dy_faction_name') -4 98 168
    $kick = [Layout]::DeepClone($kickTemplate)
    [void][Layout]::Reassign($kick, $alloc)
    XY $kick 124 126
    $panel.List('children').Add($kick)
}

$heading = [Layout]::FindComponent($root, 'heading_txt')
foreach ($state in $heading.List('states')) {
    Text $state 'text' 'Eight Player Campaign'
    Text $state 'w3' ''
}

$bytes = [Layout]::Write($root)
$verified = [Layout]::Read($bytes)
if (-not [Linq.Enumerable]::SequenceEqual($bytes, [Layout]::Write($verified))) { throw 'Modified layout failed lossless round-trip.' }
$definitions = foreach ($component in [Layout]::Components($verified)) {
    $component.U('uid')
    foreach ($state in $component.List('states')) { $state.U('uid') }
    foreach ($image in $component.List('images')) { $image.U('uid') }
}
$duplicates = @($definitions | Group-Object | Where-Object Count -gt 1)
if ($duplicates.Count) { throw 'Duplicate component/state/image UIDs in layout.' }
foreach ($number in 1..8) {
    $panel = [Layout]::FindComponent($verified, "player_$number")
    if (-not $panel) { throw "Missing player_$number" }
    $null = Sub $panel 'button_kick'
    if (-not [Layout]::FindComponent($verified, "slot_label$number")) { throw "Missing static marker for player_$number" }
}
$outPath = [IO.Path]::GetFullPath($Out)
$null = New-Item -ItemType Directory -Force -Path ([IO.Path]::GetDirectoryName($outPath))
[IO.File]::WriteAllBytes($outPath, $bytes)
Write-Output "Built Version039 eight-player layout: $($bytes.Length) bytes; $($definitions.Count) unique UIDs; lossless read/write verified."
