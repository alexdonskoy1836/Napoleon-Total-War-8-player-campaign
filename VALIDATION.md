# Validation record — 9 November 2026

Version: **0.1.0-experimental**. Mod match code: **86B744B1F714**.

## Passed

| Check | Result |
|---|---|
| Supported executable identity and instruction signatures | Exact SHA-256 and original bytes match |
| Native capacity writes | 8 emulated original/patched cases at two load addresses |
| Host/client campaign-specific hooks | 96 emulated branch cases across modes 0–3, capacities 2/4/8, original/patched code and two bases |
| Registers, stack writes, PE relocations | Expected state preserved; no relocation intersects the patch ranges |
| PE structure | Same file size, image size, section count and timestamp; existing text padding mapped for the two stubs |
| Version039 layout | Original and generated files parse/write byte-identically; eight player controls and permanent markers; 1,377 unique component/state/image IDs |
| Lua payload | Napoleon Lua 5.1 float32/32-bit-size ABI; exact shipped payload passes nine mocked behavioral scenarios after host-ABI translation |
| PFH0 movie pack | Built from original layout and payload; all entries extracted and hash checked after writing |
| Europe startpos | Full ABCE traversal; 1,155,124 original structural end pointers checked/rebased; eight playable factions; inverse reconstruction recovers original bytes |
| Victory data | Independent parser verified original five records unchanged and all nine added mode definitions |
| Windows installer | Ten copied-file scenarios passed under Windows PowerShell, including install, verify, repeat operations, altered-file refusal, bad payload refusal and failure rollback |
| Source game preservation | Actual installed executable and Europe startpos retain original SHA-256 hashes |

The installer failure test made the second destination read-only. The attempted
installation restored the already-replaced executable, left the original
startpos intact, removed its active receipt, and left no auto-loaded mod pack.
A subsequent install and uninstall succeeded. Pack publication uses a validated
temporary file and atomic rename so a failed copy cannot leave a partial `.pack`.

## Not performed / not established

- Successful game launch with this mod, visual inspection of the lobby, or a
  real third/eighth client joining. The desktop capture attempts failed with
  timeouts; no in-game success is claimed.
- Correct human control, turn progression, diplomacy, battle spectators, gifting,
  battle results, synchronization or campaign completion with eight humans.
- Correct eight-player save/resume identity restoration. Native metadata still
  has paired identity fields; this remains an explicit unresolved risk.
- Compatibility with `ntwfix`, other mods, other game builds or non-Europe
  campaigns during real play.
- The optional Shogun desync/resync and battle-result/gifting patches are not
  ported and are not included in the passing checks.

## Resulting file hashes

| File | SHA-256 |
|---|---|
| `Napoleon.exe` | `6a39a0f16df85d4ce492cac4e7b6959c1773ff98a6db278686bdb0c55d379c41` |
| Europe `startpos.esf` | `043fda44965eb1a3642a017b298b579161e400690b1f85bbe739f95da24ddf41` |
| `ntw8_campaign.pack` | `3c45752ab62ce91e305275ebb9b0d4568f62ea0f531865fa12c0e9873e6427ad` |

Original hashes are recorded in `supported-build.json`. The engine call-chain
evidence is in `source/ENGINE_EVIDENCE.md`; campaign findings are in
`source/CAMPAIGN_AUDIT.md`. Use `TEST-IN-GAME.md` for the next validation phase.
