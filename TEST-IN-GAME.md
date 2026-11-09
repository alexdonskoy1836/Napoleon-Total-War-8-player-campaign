# In-game test checklist

This is the first runtime validation pass. Automated tests cannot prove that
eight clients will stay synchronized or resume the same saved campaign.
Use a disposable new Europe campaign and record the first failing step.

## 1. Prepare every PC

- Extract and install the same version on every PC. Close the game first.
- Run Verify.bat. Everyone should see **86B744B1F714**.
- Use the same game version, DLC and other-mod setup. For the first comparison,
  use stock campaign data with this package; campaign overhauls are rejected by
  the startpos hash check.
- Keep existing campaign saves separate. Each participating player needs their
  own usable game session/account; local mock tests do not replace those clients.

## 2. One host: inspect the lobby

Host a new **Europe multiplayer campaign**.

Pass: the lobby opens without errors, shows Eight Player Campaign and eight
numbered positions, and all controls fit at your resolution. The host's own
faction/ready controls must remain clickable. Open the faction list and confirm:
France, Austria, Britain, Prussia, Russia, Spain, Ottomans and Sweden.

Report missing panels, invisible text, overlapping dropdowns, or an inaccessible
Ready button. The layout was built for Napoleon's stock 1280-coordinate canvas;
actual rendering and scaling have not yet been inspected in game.

## 3. Three players: expose the first extra-player failures

Join two more clients, including one of Spain/Ottomans/Sweden. Every client must
see all three players in separate positions with the same names and factions.
Select three different factions; check that selecting one reserves it everywhere.
Have the host kick the third player, then reconnect. The intended player must be
kicked, and the remaining players must keep their identity and faction.

Ready all three and start. Confirm that three human players actually control
three factions, and complete one entire turn cycle. **Save, quit all clients,
and resume now.** Verify the same three accounts regain the same three factions.
Resume identity handling beyond two players is a known unresolved area.

## 4. Eight-player lobby and campaign start

Use a fresh test campaign. Join clients sequentially until all eight positions
are occupied. Check every player's name, faction and ready state on all clients.
No player should overwrite another slot or become an unintended spectator.

Assign all eight different factions. Kick a middle slot, reconnect, then check
the replacement's controls and faction reservation. Clients must not have usable
host-only kick controls. Ready all eight and start the campaign.

Pass: all clients finish loading and each controls the correct faction. Visible
eight-slot UI alone is not a passing eight-player campaign test.

## 5. Turns and diplomacy

Play at least three full turn cycles. Include army movement, recruitment,
construction, taxation and diplomacy. Every human must receive a turn; no human
faction should be processed as AI. Compare turn/date, ownership and army positions
between clients. Exercise a diplomacy prompt while another human is waiting.

Check alliances explicitly. This prototype does not automatically establish
eight-way co-op alliances or change the game's normal diplomacy rules.

## 6. Battles and returning to the map

Test a land battle with multiple spectators, then an autoresolve and a naval
battle. Check who can participate/spectate, whether unit gifting works, whether
all clients leave the battle, and whether everyone agrees on casualties, winner,
army position and ownership afterward.

The Shogun spectator gifting and allied battle-result fixes are not ported.
Capture mismatches or dropped clients as failures; do not assume continuing a
divergent battle is safe or that this prototype will resynchronize it.

## 7. Eight-player save and resume

Have the host save, quit all clients, restart and resume with the same eight
accounts. Check all eight faction assignments and control, then play another
full turn and a battle. Repeat after a player leaves and rejoins the lobby.

Pass: no faction swaps, missing humans, lost clients, frozen turns or immediately
divergent state. This is a release-blocking test, not a cosmetic save-list check.

## 8. Added-faction objectives and rollback

On separate short tests, inspect the three victory modes for Spain, Ottomans and
Sweden. Confirm targets/date/home-region requirements display without errors.
Victory completion and long-term balance will need longer campaigns.

Close the game and run Uninstall.bat. Confirm the original two-player lobby and
stock Europe selection return. Existing `ntwfix` and other unrelated files should
remain present. Run Install.bat again only when continuing this experiment.

## If something fails

Stop at the first reproducible failure. Record:

- Package version, match codes, stage above, host versus client, player count,
  selected factions, game mode and the exact action immediately before failure.
- Exact error text or a screenshot, plus whether all clients saw the same issue.
- Relevant game/Steam crash or game log files if produced, and the test save if
  the failure involves resuming. Copy existing logs; no debug logging was enabled
  automatically by this package.
- Other enabled mods, `ntwfix` version if used, and display resolution for UI bugs.

Keep original backups and the failed test save. Successful file verification
does not rule out native engine or synchronization bugs.
