# Napoleon engine port evidence

Inspected installed `Napoleon.exe` read-only. Image base `0x00400000`, x86 PE32,
length 17,895,424 bytes. No game file was modified by this investigation.

Original SHA-256:
`44880ec1770f600163a336eec83b4366901484c5cceec83dc326e2932f02a054`

Current V2 patched SHA-256:
`6a39a0f16df85d4ce492cac4e7b6959c1773ff98a6db278686bdb0c55d379c41`

Use `patch-manifest-v2.json`; the earlier two-byte-only manifest is superseded.
The earlier two-byte-only version is insufficient: it enables a battle-map lookup
for campaign maps during native lobby creation.

## Verified patch sites

| Purpose | Instruction VA | Immediate VA | Immediate file offset | Before | After |
|---|---|---|---|---|---|
| New campaign host capacity | `00473811` | `00473818` | `00072C18` | `02` | `08` |
| Saved campaign host capacity | `004A8027` | `004A802E` | `000A742E` | `02` | `08` |

Full guarded instruction signatures:

* New: `C7 84 24 AC 00 00 00 02 00 00 00` = `mov dword ptr [esp+0xAC],2`.
* Resume: `C7 84 24 D8 00 00 00 02 00 00 00` = `mov dword ptr [esp+0xD8],2`.

Both write session-descriptor field `+0x34`. Changing the low byte of the four-byte
immediate makes the field 8. Neither immediate intersects a PE HIGHLOW relocation.

Two additional conditional hooks are required. The existing 260-byte zero padding
at the end of `.text` provides space; 33 bytes at VA `01306900` and 24 bytes at
`01306940` hold position-independent code. Existing `.text` VirtualSize is extended
from `00F058FC` to its existing raw size `00F05A00`. No section, import, file length,
section address, or SizeOfImage changes.

* Host hook: VA `004A8703`, 14 original bytes
  `83 7E 34 02 89 7C 24 14 89 7C 24 18 76 3A`.
* Client hook: VA `004A9E72`, 9 original bytes
  `83 F8 02 0F 86 95 00 00 00`.
* All exact before/after bytes and file offsets are in the V2 manifest.

### Campaign-only map-capacity correction

Native lobby creation divides TotalPlayers by two into per-team capacities.
When TotalPlayers exceeds two, the old code looks up the map in the
`EMPIREUTILITY::BATTLE_RECORD` table and clamps capacities to fields `+4C/+50`.
The lookup is `004A8711..004A8747` in the host path and
`004A9E7B..004A9F0C` in the client path. The lookup returns NULL for a missing key;
the following code dereferences it without a NULL check. Campaign maps should not
go through this battle-map lookup.

The new hooks skip that lookup only for campaign mode 3, preserving the
TotalPlayers/2 capacities (four per team). The discriminator is session
`+583B4`, populated from session descriptor integer key 0 immediately before the
hook in both paths (`004A86E5..E9`, `004A9E46..4A`). `MPHostCampaign` uses
`004A14B0`, which sets key 0 to 3 (`004A14B7..004A1501`). Other modes keep their
original count and map-dependent capacity behavior.

### New host call chain

* Registration at `004021C0` references string `MPHostCampaign` (`01310F58`) and
  function `00473650`.
* `00473650` constructs a descriptor starting at stack `+0x78`; the instruction at
  `00473811` writes descriptor `+0x34=2`.
* Call `0047388C -> 004A74E0` receives that descriptor.
* `004A74E0` copies `+0x34` unchanged (`004A75E8`, `004A75F1`) to the descriptor
  passed through `004A764F -> 004A76F0`.
* Independent meaning check: `MPHostCustomBattle` (`00473920`) reads Lua key
  `TotalPlayers` (string `01315428`) into stack `+0x54`, then copies it into the
  same `+0x34` field at `00473FA7`; it calls the same host routine at `00474026`.

### Saved campaign call chain

* `004859D0` opens `MULTIPLAYER_CAMPAIGN_SAVE_GAME` (`013149E0`) and its
  `multiplayer` record (`01314A00`).
* `00485AD6 -> 004A7D00` prepares the resumed campaign lobby.
* At `004A8027`, the resumed descriptor (`esp+0xA4`) gets `+0x34=2`.
* It is passed directly to `004A76F0` at `004A808D`.

### Common session capacity check

`004A76F0` reads descriptor fields `+0x38` and `+0x34`, sums them, and rejects
values greater than 16 (`004A770B..004A7714`). The two campaign paths set `+0x38`
to zero. Eight therefore passes this identified native check. This is not proof
that every downstream subsystem supports eight campaign players.

Other host paths using capacity 2 were identified as debug console tests,
`Drop-In Battle`, and `Quick Battle`; they are deliberately excluded.

## Additional compatibility findings

* Native `PlayerDetails` is `0044AC30`. It returns exactly two TEAM arrays (outer
  loop `0044B223`), each containing a dynamic member list (`004A4A80`). The old
  campaign Lua picks only `team[1]`; all team members must be traversed by the port.
* `DeclareReady` (`0044B4A0 -> 004BD940`) and inspected readiness checks
  (`004A4DA0`) use generic player-count iteration through
  `004A4480 -> 004B1210`, which reads `[player-manager+0x300]`.
* The `CAMPAIGN_PLAYERS_SETUP` writer (`00891BD0`) loops over the vector count at
  `+8` with entry stride `0xBC`, calling `00891CB0` for each
  `CAMPAIGN_PLAYER_SETUP` (`00891C39..00891C74`).
* Its reader (`00890110`) grows allocation according to the record count and
  loops through records (`00890280..008902DD`). This serialization structure is
  dynamic; no fixed-two cap was found in this structure. Other save metadata and
  campaign runtime assumptions have not been exhaustively audited.
* Native player records are eight `0x60`-byte entries; count is at `+300`.
  Allocation `004987A0` reuses holes then rejects count >=8 (`004987C1`).
* Auto team placement (`004A62B0`) chooses the team with most remaining capacity;
  handshake at `004AAB35..54` disconnects a new member if none remains. With the
  campaign-only hooks above, the two teams each have capacity four.
* `004A2580` finds a free within-team army index by scanning up to eight members.
  Team is stored in player `+5C` low two bits; army index in its upper bits.
* Save metadata parser `00888970` still reads paired strings and two 64-bit IDs
  (`+78`, `+80`). Resume copies paired strings `+34/+40` into session
  `+58388/+58394`. Their full relationship to resumed identities for players 3–8
  has not been established. This is a concrete remaining resume limitation to
  test; dynamic CAMPAIGN_PLAYERS_SETUP alone does not resolve it.

## Validation performed

Run `python verify_engine_v2.py <original Napoleon.exe>` with `pefile`, `capstone`,
and `unicorn` available, alongside the helper `verify_engine.py`; it reads `source/engine-patches.json`
from the package. Install the Python dependencies described in README.md.

Passed: exact original hash; both instruction signatures; PE x86/image base;
file-offset mapping; decoded instruction boundaries; no patch overlap or HIGHLOW
relocation intersection; descriptor instruction emulation at two load addresses
(8 cases); original/patched host/client branches across modes 0/1/2/3, capacities
2/4/8, and two load addresses (96 cases); exact expected stack writes and all
general registers preserved; same file/image size and section count; exact V2
patched hash. It does not write an executable or alter the installation.

Not validated: real game startup, an eight-person lobby, eight humans entering a
campaign, turn progression, battles and spectators, real save/reload, desync or
alliance behavior. No claim of equivalent runtime success to the Shogun mod is
supported by these static and emulated checks alone. The Shogun-specific desync,
floating-point, resync and spectator battle patches have not been ported.
