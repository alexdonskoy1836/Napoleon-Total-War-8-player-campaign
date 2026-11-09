# Napoleon: Total War — Eight Player Campaign

**Version 0.1.0 — experimental prototype, ready for in-game testing.**

This ports the supplied Shogun 2 mod's approach to the installed Napoleon build:
patch the native session limits, expand the campaign lobby, and build the UI pack
from the player's own files. Napoleon uses different executable code, UI scripts,
archive formats and campaign data, so its patches are specific to Napoleon.

**A working eight-client campaign has not been demonstrated.** Static checks,
instruction emulation, scripted lobby tests, and install/uninstall tests pass.
Game startup, actual lobby rendering, campaign turns, battles, and eight-player
save/resume still need the tests in [TEST-IN-GAME.md](TEST-IN-GAME.md).

## Install

1. Extract the entire ZIP into a normal folder. Everyone closes Napoleon.
2. Run **Install.bat**. It targets:
   `C:\Program Files (x86)\Steam\steamapps\common\Napoleon Total War`.
3. Everyone installs this same package. Run **Verify.bat** and compare the mod
   match code: **86B744B1F714**.
4. Start Napoleon normally through Steam. Host a **new Europe multiplayer
   campaign**, then follow the staged test checklist.

If your game is elsewhere:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -GamePath "D:\SteamLibrary\steamapps\common\Napoleon Total War"
```

Windows PowerShell and .NET included with Windows are sufficient to install.
Python, Java, a compiler installation, and the Shogun game are not required.
If Windows denies writing to the game folder, run Install.bat as administrator.

The installer accepts only the exact supported executable, Europe startpos and
three source UI entries. A mismatch stops the installation before replacement;
do not remove the hash checks to force a different build or campaign overhaul.
Close Steam downloads/updates for this game while installing.

The match code covers this mod's version and three resulting files. It does
**not** establish that everyone has the same DLC, other mods, or all game data.
Use matching game installations and the same other-mod setup for testing.

## What is included

- Native new-campaign and resume-lobby capacity changed from two to eight.
- Host and client campaign-specific hooks bypass a battle-map capacity lookup
  that becomes active above two players. Native battle modes retain that lookup.
- Eight lobby positions with permanent labels, individual player controls,
  ready/name updates, faction reservations, and correctly targeted host kicks.
- A shared invitation control remains usable until the lobby is full.
- Europe multiplayer exposes France, Austria, Britain, Prussia, Russia,
  **Spain, Ottomans and Sweden**. The last three already exist in the world;
  their playability flags and victory-option records are added.
- Original-file backups, deterministic build hashes, installation verification,
  rollback on installation failure, and an uninstaller.

## Scope and known limits

**Start with Europe.** Italy, Egypt and the Peninsular campaign are not adapted
to supply eight playable factions. The shared engine/UI changes also affect
their multiplayer lobby, but those campaigns are outside this prototype's
supported test scope.

**Save/resume is unresolved beyond two players.** The resume lobby capacity is
patched and the campaign-player setup array is dynamic. However, native save
metadata still contains two player identity fields. Whether players 3–8 regain
the correct factions needs real testing; the capacity patch does not prove it.
Test saving and rejoining with three players early, before a long session.

**The Shogun stability patches are not included.** This build does not port its
floating-point/locale changes, automatic or hotkey resync, battle-result fixes,
round-robin spectator unit gifting, or suppression of desync disconnects.
Campaign alliances, spectator behavior and victory behavior remain unverified.
The native campaign's existing turn order is retained; simultaneous turns were
not implemented.

The lobby's map preview still shows the local faction plus one remote faction,
because the native preview API takes two faction keys. Difficulty sliders show
only the local player's flag. These UI limits do not verify or determine the
campaign's underlying player capacity. Save-list UI has not been expanded.

Spain, Ottomans and Sweden use experimental victory options derived from the
original Austria template: 20 regions and the faction's home region by 1812;
14 regions using the original untimed template; and 60 regions plus home by
1812. The original five factions' victory records remain unchanged. Balance and
victory completion for the three added factions are untested.

The existing `ntwfix` files are left untouched. The engine patch keeps the PE
timestamp, image size, file size and section count unchanged, but compatibility
with `ntwfix` during actual multiplayer is not established.

## Uninstall and recovery

Close Napoleon and run **Uninstall.bat**. For another game folder:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -GamePath "D:\SteamLibrary\steamapps\common\Napoleon Total War" -Uninstall
```

The uninstaller restores the exact original executable and Europe startpos and
removes only this package's unchanged movie pack. It refuses to overwrite game
files changed by another program after installation. Original backups remain
in `napoleon8_backup` under the game folder for recovery and reinstalling.

No saves or user preferences are modified by the installer/uninstaller. Keep
experimental saves separate: an eight-player save should not be assumed usable
after restoring the two-player game.

If installation is interrupted, retain `napoleon8_backup`. Its files mirror
their original relative paths. Inspect the error before restoring manually;
do not delete the only original backups. Steam verification can restore stock
files but does not necessarily remove a separately installed movie pack.

## Files changed by installation

| Game-relative path | Action |
|---|---|
| `Napoleon.exe` | Guarded capacity changes and two conditional hooks |
| `data\campaigns\mp_eur_napoleon\startpos.esf` | Eight-faction Europe start position |
| `data\ntw8_campaign.pack` | New PFH0 movie pack, loaded automatically |
| `napoleon8_backup\...` | Original backups and installation/recovery receipt |

Original `data.pack`, Shogun files, other mod files and user scripts are not
overwritten. The package generates replacements locally; it does not ship a
replacement game executable, original artwork, or a complete startpos file.

## Verification and development

See [VALIDATION.md](VALIDATION.md) for performed checks and their limits.
Exact input/output hashes and guarded changes are in `supported-build.json` and
`source/engine-patches.json`. UI and campaign builder source is included.

To build without installing, use a new, empty output directory:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\build.ps1 -GamePath "C:\Program Files (x86)\Steam\steamapps\common\Napoleon Total War" -OutputDirectory "D:\ModBuild\Napoleon8"
```

The generated executable and startpos are for the supported game build. The
installer stages and verifies these same files before it replaces anything.

Development tests require Python with `lupa`, `pefile`, `capstone` and `unicorn`:

```powershell
python tests\test_lobby.py
python tests\verify_engine_v2.py "C:\path\to\original\Napoleon.exe"
python tests\test_installer.py --game-root "C:\path\to\original\game" --work-dir "D:\new-empty-test-directory"
```

The installer test reads the source installation and operates only on disposable
copies. `source/compile_lua.py` rebuilds the included Lua payload from
`source/main_panel.lua`; payload/pack hashes must be regenerated if it changes.

## Attribution

Technique and Version054 layout-tool starting point: Tasman Modding's supplied
[Shogun2-8Player-Coop](https://github.com/TasmanModding/Shogun2-8Player-Coop).
The layout reader was adapted to Napoleon Version039. Napoleon-specific Lua was
derived from this installation and extended in `source/lobby_overrides.lua`.
Local `etwng` UI/ESF documentation helped identify version differences and
playability fields. This is an unofficial experimental modification.
