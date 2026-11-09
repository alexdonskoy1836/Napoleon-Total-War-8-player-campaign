# Napoleon lobby and Europe campaign audit

## Observed source constraints

Napoleon's original lobby script binds exactly two player components, updates and
initializes only those components, maps every slot other than the first to the
second panel, filters factions only between that pair, and kicks the first member
of the second team. The native engine audit established that `PlayerDetails()` has
two teams with dynamic member arrays. It must be flattened at both levels.

The source also disables invite after one remote joins, clears remote controls
when any remote leaves, stores only one `other_players_faction`, and uses one
remote difficulty handle. The native ownership preview API accepts two faction
keys. The extension retains this preview for the local faction and first remote
panel, while showing only the local difficulty handle. These are display limits.

`lobby_overrides.lua` provides up to eight arbitrary slot IDs, independent of team
or numerical slot range. It allocates a free panel on join, updates every panel,
filters selected factions across all panels, binds each panel's own kick action,
checks host authority and live membership before kicking, and restores capacity
after departures. A reused local dropdown returns to its actual `up` state. Resume
locking is stored separately from mutable options. Nil factions, unknown callback
slots and exhausted faction lists are guarded. Every member of both teams is
initialized; faction allocations are reserved before automatic local selection.

## Europe startpos findings

The loose file `data/campaigns/mp_eur_napoleon/startpos.esf` is ABCE. It contains 41
faction setups, but only France, Austria, Britain, Prussia and Russia are playable.
Each faction has three `CAMPAIGN_PLAYER_SETUP` instances: preopen metadata,
campaign setup, and the live world faction. `FACTION_INFOS` has two further
playability flags. Sweden, Spain and Ottomans already exist in the campaign world
and own 2, 4 and 5 regions respectively.

The existing etwng source's `make_faction_playable` helper identifies the same
flags. Its `NodesDescriptions.xml` describes the second setup boolean as
`Playable`, and the first two `FACTION_INFOS` booleans as playability flags.
The original `VICTORY_CONDITION_OPTIONS` array has entries only for the five
playable factions, so changing boolean flags alone is incomplete.

`StartposPatcher.cs` applies thirteen boolean changes and Sweden's list order
0-to-8 change. It adds three victory-option entries derived from the user's own
Austria template, preserving all five original entries byte for byte. New modes:

| Mode | Target | Deadline | Required home region |
|---|---|---|---|
| 1 | 20 regions | 1812, same native date as template | faction home region |
| 4 | 14 regions | no deadline, same native template | none |
| 3 | 60 regions | 1812, same native date as template | faction home region |

Home regions are `eur_rumelia`, `eur_spain`, and `eur_sweden`; ownership is verified
in the original `REGION_OWNERSHIPS` table. These new victory objectives are
experimental mod choices, not original campaign objectives or tested balance.

## Build and verification

Public API: `NapoleonStartposPatcher.Build(input, output)`. The output must be a
separate staged file. PowerShell can load the source with `Add-Type -Path`.

- Original size: 32,333,496 bytes.
- Original SHA256: `F55B607894CEFD86E62DBF150DB3111B92443919762B2EB6EA2E854C830071D2`.
- Patched size: 32,334,725 bytes.
- Patched SHA256: `043FDA44965EB1A3642A017B298B579161E400690B1F85BBE739F95DA24DDF41`.

The builder accepts only the exact original. It traverses 1,155,124 original
structural absolute end pointers, replaces the victory array, rebases all required
offsets including the footer pointer, reparses the result, checks eight playable
factions in all setup instances, and verifies its deterministic output hash.
Inverse reconstruction must reproduce every original byte. Both original and
rebuilt victory arrays must round-trip byte-identically through its writer.

The independent Python parser also traversed the complete output and checked all
eight playability sets, original five victory subtrees, and all nine new victory
mode definitions. Results are in `startpos-validation.json`.

The UI agent's separate Lua 5.1 mock suite passes nine scenarios, including both
teams, eight arbitrary slots, leave/rejoin, own-panel kick targeting, non-host
restrictions, nil and exhausted faction selection, and resume locking. The tests
execute converted float32-ABI bytecode translated back to the host Lua ABI.

These checks establish structure and script behavior. They do not establish
eight-client gameplay, native network capacity, turn progression, battle outcomes,
save/reload, resynchronization, or campaign victory behavior.

## Required runtime checklist

1. Host MP Europe; confirm eight visible positions and eight selectable factions.
2. Join with players 2 through 8 across both teams; check distinct name, avatar,
   faction, ready status, host-only kick buttons, and invite capacity.
3. Change factions and verify the same faction cannot be chosen by another client.
4. Kick a middle slot; reconnect and confirm existing panels keep their identities.
5. Start once everyone is ready; confirm all eight factions are human-controlled.
6. Complete a full turn cycle, including all new factions and diplomacy prompts.
7. Fight a land battle with multiple spectators, gift units, and compare results.
8. Exercise naval battle and autoresolve, watching for desync or lost clients.
9. Save, quit, and resume with all eight accounts; verify faction assignments,
   locked selection, turn state, and saved campaign membership.
10. Test all three victory modes for the new factions; verify targets and dates.
11. Uninstall and verify hashes match the recorded originals exactly.
