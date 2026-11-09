
-- Napoleon eight-player lobby extension. Append to the game's main_panel.lua
-- so its existing local campaign/preferences/interface values remain in scope.
-- Native PlayerDetails is an array of TWO TEAMS, each containing all members.
-- Native slot IDs are identifiers: do not assume 0..7 or team index == slot.
local n8_capacity = 8
local n8_slot_panel = {}
local n8_panel_slot = {}
local n8_factions = {}
local n8_resumed = false
local n8_initialise_original = Initialise
players = {}
for i = 1, n8_capacity do
  players[i] = UIComponent(cartouche:Find("player_" .. i))
end

local function n8_members()
  local members = {}
  if mp_interface == nil then return members end
  local teams = mp_interface:PlayerDetails() or {}
  for _, team in ipairs(teams) do
    for _, member in ipairs(team) do
      if member.Slot ~= nil then members[#members + 1] = member end
    end
  end
  return members
end

local function n8_claim(slot)
  if slot == nil then return nil end
  if n8_slot_panel[slot] ~= nil then return players[n8_slot_panel[slot]] end
  for i = 1, n8_capacity do
    if n8_panel_slot[i] == nil then
      n8_panel_slot[i] = slot
      n8_slot_panel[slot] = i
      return players[i]
    end
  end
  out.tom("Eight-player lobby: rejected additional UI slot", tostring(slot))
  return nil
end

function FindPlayerBaseForSlot(slot, component_to_find)
  local index = n8_slot_panel[slot]
  if index == nil then return nil end
  local base = players[index]
  if component_to_find == nil then return base end
  return UIComponent(base:Find(component_to_find))
end

local function n8_refresh_controls()
  local hosting = mp_interface ~= nil and mp_interface:LocalPlayerHosting()
  local local_slot = mp_interface ~= nil and mp_interface:LocalPlayerSlot() or nil
  local occupied = 0
  for i = 1, n8_capacity do
    local slot = n8_panel_slot[i]
    if slot ~= nil then occupied = occupied + 1 end
    UIComponent(players[i]:Find("button_kick")):SetVisible(
      hosting and slot ~= nil and slot ~= local_slot)
  end
  local invite = UIComponent(this:Find("button_invite"))
  invite:SetVisible(hosting and FrontEnd.MPIsOnline())
  invite:SetState(occupied < n8_capacity and "normal" or "inactive")
  UIComponent(this:Find("button_options")):SetVisible(hosting)
  -- There are only two native difficulty slider handles. Show the local handle;
  -- hiding the second avoids assigning seven different players to one flag.
  UIComponent(UIComponent(this:Find("cmp_diff_slider")):Find("handle2")):SetVisible(false)
  UIComponent(UIComponent(this:Find("btl_diff_slider")):Find("handle2")):SetVisible(false)
end

local function n8_refresh_filters()
  if campaign_details == nil or campaign_details.Factions == nil then return end
  for i = 1, n8_capacity do
    local own_slot = n8_panel_slot[i]
    for key, _ in pairs(campaign_details.Factions) do
      local taken = false
      for slot, faction in pairs(n8_factions) do
        if slot ~= own_slot and faction == key then taken = true; break end
      end
      players[i]:LuaCall("AllocateFaction", key, taken)
    end
  end
end

function FilterFaction(slot, faction, taken)
  if type(faction) ~= "string" or #faction == 0 then return end
  if taken then
    n8_factions[slot] = faction
  elseif n8_factions[slot] == faction then
    n8_factions[slot] = nil
  end
  n8_refresh_filters()
end

local function n8_refresh_map()
  if campaign_details == nil or theatres == nil or current_prefs == nil then return end
  -- This engine API accepts exactly two faction keys. Keep its map preview
  -- deterministic: local player and first occupied remote panel only.
  other_players_faction = nil
  local local_slot = mp_interface ~= nil and mp_interface:LocalPlayerSlot() or nil
  for i = 1, n8_capacity do
    local slot = n8_panel_slot[i]
    if slot ~= nil and slot ~= local_slot and n8_factions[slot] ~= nil then
      other_players_faction = n8_factions[slot]
      break
    end
  end
  local theatre_list = {}
  for key, _ in pairs(theatres) do theatre_list[#theatre_list + 1] = key end
  local generated = FrontEnd.GenerateRegionOwnershipMaps(theatre_list,
    campaign_details.Key, local_players_faction, other_players_faction,
    current_prefs.game_type) or {}
  for key, path in pairs(generated) do
    if maps[key] ~= nil then
      local overlay = maps[key].Component:Find("map_overlay")
      UIImage(path):SetComponentTexture(overlay, 0)
      UIComponent(overlay):SetVisible(true)
    end
  end
end

function Initialise(game_details)
  n8_slot_panel = {}
  n8_panel_slot = {}
  n8_factions = {}
  n8_resumed = game_details.resumed and true or false
  local_players_faction = nil
  other_players_faction = nil
  n8_initialise_original(game_details)
  for i = 1, n8_capacity do
    players[i]:LuaCall("SetFactionList", list_factions)
    players[i]:LuaCall("ClearDetails")
    local panel_index = i
    players[i]:SetGlobal("KickPlayer", function()
      KickPlayer(n8_panel_slot[panel_index])
    end)
  end
  n8_refresh_controls()
end

function CreateMpInterface()
  mp_interface = UIMPInterface(FrontEnd.MPInterface())
  local members = n8_members()
  -- Reserve every existing faction before any local automatic selection.
  -- This also handles a resumed session whose local member is listed first.
  for _, member in ipairs(members) do
    n8_claim(member.Slot)
    if type(member.Faction) == "string" and #member.Faction > 0 then
      n8_factions[member.Slot] = member.Faction
    end
  end
  n8_refresh_filters()
  for _, member in ipairs(members) do
    OnPlayerJoined(member.Slot, member.Name, member.Faction, member.Ready)
  end
  if mp_interface:LocalPlayerHosting() then
    local options = advanced_options_panel:LuaCall("CurrentOptions")
    options.campaign_difficulty = current_prefs.campaign_difficulty
    options.battle_difficulty = current_prefs.battle_difficulty
    mp_interface:SetCampaignGameOptions(options)
  end
  n8_refresh_controls()
end

function OnUpdate()
  for i = 1, n8_capacity do players[i]:LuaCall("Update") end
  if quitting == true then
    if FrontEnd.MPCurrentGameDetails("campaign") == nil then
      Component.LockPriority(0)
      root:LuaCall("TransitionBack")
      if quit_msg ~= nil then root:LuaCall("NetworkError", quit_msg) end
    end
  elseif FrontEnd.MPHasLobby() and mp_interface == nil then
    CreateMpInterface()
  end
end

function OnPlayerJoined(slot, name, faction, ready)
  if mp_interface == nil then return end
  local player = n8_claim(slot)
  if player == nil then return end
  local is_local = slot == mp_interface:LocalPlayerSlot()
  if type(faction) == "string" and #faction > 0 then n8_factions[slot] = faction end
  n8_refresh_filters()
  player:LuaCall("Initialise", mp_interface, slot, name or "", faction, n8_resumed)
  -- Reused components may retain the previous occupant's inactive state.
  UIComponent(player:Find("mini_flag")):SetState(
    is_local and not n8_resumed and "up" or "inactive")
  if type(faction) == "string" and #faction > 0 then
    OnPlayerFactionChanged(slot, faction)
  elseif is_local and not n8_resumed then
    local available = player:LuaCall("FirstAvailableFaction")
    if type(available) == "string" and #available > 0 then
      mp_interface:SetFaction(slot, available)
    else
      out.tom("Eight-player lobby: no selectable faction remains", tostring(slot))
    end
  end
  local difficulties = mp_interface:GetPlayerDifficultySettings() or {}
  for _, settings in ipairs(difficulties) do
    if settings.IsLocal then
      OnCampaignDifficultyChanged(true, settings.CampaignDifficulty)
      OnBattleDifficultyChanged(true, settings.BattleDifficulty)
      break
    end
  end
  OnPlayerReadyChanged(slot, ready)
  n8_refresh_controls()
end

function OnPlayerFactionChanged(slot, faction)
  local player = FindPlayerBaseForSlot(slot)
  if player == nil or mp_interface == nil or campaign_details == nil then return end
  if faction == "" then faction = nil end
  if faction ~= nil then
    local details = campaign_details.Factions[faction]
    if details == nil then
      out.tom("Eight-player lobby: unknown faction", tostring(faction))
      return
    end
    player:LuaCall("SelectFaction", details)
    n8_factions[slot] = faction
    if slot == mp_interface:LocalPlayerSlot() then
      if details.GameTypes ~= nil then
        UIComponent(this:Find("dropdown_game_type")):LuaCall("SetOptions", details.GameTypes)
        current_prefs = SaveOptions()
      end
      local_players_faction = faction
      SetDifficultySliderFaction("cmp_diff_slider", 1, details)
      SetDifficultySliderFaction("btl_diff_slider", 1, details)
      SetVictoryConditionsText()
    end
  else
    n8_factions[slot] = nil
    player:LuaCall("ClearDetails")
    if slot == mp_interface:LocalPlayerSlot() then local_players_faction = nil end
  end
  n8_refresh_filters()
  n8_refresh_map()
  n8_refresh_controls()
end

function SetVictoryConditionsText()
  local vc = UIComponent(this:Find("dy_victory_conditions"))
  local details = campaign_details and campaign_details.Factions[local_players_faction]
  local condition = details and details.VictoryConditions and
    details.VictoryConditions[current_prefs.game_type + 1]
  if condition ~= nil then
    local width, height = vc:SetStateText(condition)
    vc:Resize(width, height)
  else
    vc:SetStateText("")
  end
  local pane = UIComponent(this:Find("victory_conditions"))
  UIComponent(pane:Find("listview")):LuaCall("SetListExtents")
end

function OnPlayerLeft(slot, reason)
  local index = n8_slot_panel[slot]
  if index == nil then return end
  players[index]:LuaCall("ClearDetails")
  n8_factions[slot] = nil
  n8_slot_panel[slot] = nil
  n8_panel_slot[index] = nil
  if mp_interface ~= nil and slot == mp_interface:LocalPlayerSlot() then
    local_players_faction = nil
  end
  n8_refresh_filters()
  n8_refresh_map()
  n8_refresh_controls()
end

function OnPlayerNameChanged(slot, player_name)
  local player = FindPlayerBaseForSlot(slot)
  if player ~= nil then
    UIComponent(player:Find("dy_player_name")):SetStateText(player_name or "")
  end
end

function OnPlayerReadyChanged(slot, ready)
  local player = FindPlayerBaseForSlot(slot)
  if player == nil then return end
  local status = UIComponent(player:Find("status"))
  status:SetVisible(true)
  status:SetState(ready and "ready" or "not_ready")
  if mp_interface ~= nil and mp_interface:LocalPlayerSlot() == slot then
    UIComponent(UIComponent(this:Find("button_ready")):Find(0)):SetState(
      ready and "not ready" or "ready")
  end
end

function KickPlayer(slot)
  if mp_interface == nil or not mp_interface:LocalPlayerHosting() or slot == nil or
    slot == mp_interface:LocalPlayerSlot() or n8_slot_panel[slot] == nil then return end
  for _, member in ipairs(n8_members()) do
    if member.Slot == slot then mp_interface:KickPlayer(slot); return end
  end
end

function FactionAndVCType()
  if mp_interface == nil then return nil end
  local dropdown = FindPlayerBaseForSlot(mp_interface:LocalPlayerSlot(), "mini_flag")
  if dropdown == nil then return nil end
  return dropdown:LuaCall("SelectedOption"), current_prefs.game_type
end

function OnCampaignDifficultyChanged(local_change, new_level)
  if local_change then
    UIComponent(this:Find("cmp_diff_slider")):LuaCall("ValueSet", new_level)
  end
end

function OnBattleDifficultyChanged(local_change, new_level)
  if local_change then
    UIComponent(this:Find("btl_diff_slider")):LuaCall("ValueSet", new_level)
  end
end

function OnTexturePopulate(set)
  if set and mp_interface ~= nil and local_players_faction ~= nil then
    OnPlayerFactionChanged(mp_interface:LocalPlayerSlot(), local_players_faction)
  end
end
this:SetEventCallback("OnTexturePopulate", OnTexturePopulate)
