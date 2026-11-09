local utils = require("Utilities")
local this = UIComponent(Address)
local advanced_options_panel = UIComponent(this:Find("advanced_options"))
local cartouche = UIComponent(this:Find("cartouche"))
local root = UIComponent(Component.Root())
local friends_panel = UIComponent(this:Find("friends_list"))
local campaign_details, current_prefs, mp_interface
local quitting = false
local quit_msg, local_players_faction, other_players_faction, theatres
advanced_options_panel:SetVisible(false)
local maps = {
  europe_main = {
    Component = "map_nap_europe"
  },
  italy_main = {
    Component = "map_nap_italy"
  },
  egypt_main = {
    Component = "map_nap_egypt"
  },
  spain_main = {
    Component = "map_nap_spain"
  }
}
local players = {
  UIComponent(this:Find("player_1")),
  UIComponent(this:Find("player_2"))
}
function list_factions()
  local factions = campaign_details.Factions
  local f = {}
  for k, v in pairs(factions) do
    f[#f + 1] = v
  end
  factions = f
  table.sort(factions, function(a, b)
    return a.ListOrder < b.ListOrder
  end)
  return factions
end
function OnUpdate()
  players[1]:LuaCall("Update")
  players[2]:LuaCall("Update")
  if quitting == true then
    if FrontEnd.MPCurrentGameDetails("campaign") == nil then
      Component.LockPriority(0)
      root:LuaCall("TransitionBack")
      if quit_msg ~= nil then
        root:LuaCall("NetworkError", quit_msg)
      end
    end
  elseif FrontEnd.MPHasLobby() and mp_interface == nil then
    CreateMpInterface()
  end
end
function OnDestroyed()
  out.tom("On destroyed called")
  mp_interface = nil
  collectgarbage("collect")
end
function TransitionBack(msg)
  out.tom("MP Campaign Transition back called", mp_interface)
  if mp_interface ~= nil then
    mp_interface:LeaveLobby()
    mp_interface = nil
    quitting = true
    if type(msg) == "string" then
      quit_msg = msg
    end
  end
end
function CreateMpInterface()
  mp_interface = UIMPInterface(FrontEnd.MPInterface())
  local player_details = mp_interface:PlayerDetails()
  for i, v in ipairs(player_details) do
    if #v > 0 then
      OnPlayerJoined(v[1].Slot, v[1].Name, v[1].Faction, v[1].Ready)
    end
  end
  if mp_interface:LocalPlayerHosting() then
    UIComponent(this:Find("button_kick")):SetVisible(false)
    UIComponent(this:Find("button_invite")):SetVisible(FrontEnd.MPIsOnline())
    UIComponent(this:Find("button_options")):SetVisible(true)
    local options = advanced_options_panel:LuaCall("CurrentOptions")
    options.campaign_difficulty = current_prefs.campaign_difficulty
    options.battle_difficulty = current_prefs.battle_difficulty
    mp_interface:SetCampaignGameOptions(options)
  else
    UIComponent(this:Find("button_kick")):SetVisible(false)
    UIComponent(this:Find("button_invite")):SetVisible(false)
    UIComponent(this:Find("button_options")):SetVisible(false)
  end
end
function InitDifficultySlider(slider, initial_value)
  slider:SetProperty("maxValue", 3)
  slider:LuaCall("Reset")
  slider:LuaCall("ValueSet", initial_value)
  local h2 = UIComponent(slider:Find("handle2"))
  h2:SetMoveable(false)
  h2:SetVisible(false)
  slider:SetProperty("Notify", Address)
end
function SetDifficultySliderFaction(slider_id, handle_id, fac_details)
  local diff_panel = UIComponent(this:Find("difficulty_settings"))
  local slider = UIComponent(diff_panel:Find(slider_id))
  local handle
  if handle_id == 1 then
    handle = UIComponent(slider:Find("handle"))
  else
    handle = UIComponent(slider:Find("handle2"))
  end
  handle:SetVisible(true)
  local image = UIImage(fac_details.FlagPath .. "/flag_132.tga")
  image:SetComponentTexture(handle:Find("mini_flag"), 0)
end
function Initialise(game_details)
  FrontEnd.SetCurrentGameType(1)
  current_prefs = game_details
  theatres = FrontEnd.TheatreList(game_details.Map)
  campaign_details = FrontEnd.CampaignDetails(game_details.Map, true)
  InitDifficultySlider(UIComponent(this:Find("cmp_diff_slider")), game_details.campaign_difficulty)
  InitDifficultySlider(UIComponent(this:Find("btl_diff_slider")), game_details.battle_difficulty)
  players[1]:LuaCall("SetFactionList", list_factions)
  players[2]:LuaCall("SetFactionList", list_factions)
  UIComponent(this:Find("button_kick")):SetVisible(false)
  UIComponent(this:Find("button_invite")):SetVisible(false)
  for k, v in pairs(maps) do
    v.Component = UIComponent(this:Find(maps[k].Component))
    if theatres[k] ~= nil then
      v.Component:SetVisible(true)
      local image = UIImage(theatres[k].Map)
      image:SetComponentTexture(v.Component:Address(), 0)
      local overlay = v.Component:Find("map_overlay")
      UIComponent(overlay):SetVisible(false)
    else
      v.Component:SetVisible(false)
    end
  end
  advanced_options_panel:LuaCall("Initialise", nil, game_details)
  OnCampaignParamsChanged(game_details.battle_type, game_details.turn_time, game_details.time_limit, 0, game_details.CPU_moves, game_details.game_type, game_details.unit_scale, game_details.play_AI_battles)
  UIComponent(this:Find("season_year")):SetStateText(game_details.Date)
  UIComponent(this:Find("Turns")):SetStateText(game_details.Turns)
  UIComponent(this:Find("dy_victory_conditions")):SetStateText("")
  this:StealShortcutKey("ESCAPE")
end
function DifficultyLevelString(value)
  value = utils.Clamp(value, 0, 3)
  return FrontEnd.LocalisationString("difficulty_level_" .. tostring(value + 1))
end
function Notify(addr, value)
  if addr == this:Find("cmp_diff_slider") or addr == this:Find("btl_diff_slider") then
    FrontEnd.TriggerSliderUpdateEvent(UIComponent(addr):Id())
    UIComponent(UIComponent(addr):Find("handle")):SetTooltipText(DifficultyLevelString(value), true)
    local o = SaveOptions()
    mp_interface:SetCampaignGameOptions(o)
  end
end
function SetSliderHandle2(slider, new_level)
  slider = UIComponent(slider)
  slider:SetProperty("Notify", "")
  local current = slider:GetProperty("Value")
  slider:LuaCall("ValueSet", new_level)
  local x1 = UIComponent(slider:Find("handle")):Position()
  local handle = UIComponent(slider:Find("handle2"))
  local x2, y = handle:Position()
  handle:MoveTo(x1, y)
  slider:LuaCall("ValueSet", current)
  slider:SetProperty("Notify", Address)
end
function OnCampaignDifficultyChanged(local_change, new_level)
  if local_change == false then
    SetSliderHandle2(this:Find("cmp_diff_slider"), new_level)
  else
    UIComponent(this:Find("cmp_diff_slider")):LuaCall("ValueSet", new_level)
  end
end
function OnBattleDifficultyChanged(local_change, new_level)
  if local_change == false then
    SetSliderHandle2(this:Find("btl_diff_slider"), new_level)
  else
    UIComponent(this:Find("btl_diff_slider")):LuaCall("ValueSet", new_level)
  end
end
function OnTeamLeaderChanged()
end
function OnStartCountDown(seconds_remaining)
  local ready_button = UIComponent(this:Find("button_ready"))
  local ready_txt = UIComponent(UIComponent(this:Find("button_ready")):Find(0))
  if seconds_remaining ~= -1 then
    ready_txt:SetVisible(true)
    ready_txt:SetStateText(tostring(seconds_remaining))
  elseif ready_txt:Visible() == true then
    ready_txt:SetVisible(false)
  end
end
function OnCampaignParamsChanged(battles_fought, turn_time_limit, battle_time_limit, deploy_time_limit, show_ai_moves, game_type, unit_scale, play_AI_battles)
  out.tom("Campaign params changed.  Game type = " .. tostring(game_type))
  current_prefs.battle_type = battles_fought
  current_prefs.turn_time = turn_time_limit
  current_prefs.game_type = game_type
  current_prefs.time_limit = battle_time_limit
  current_prefs.unit_scale = unit_scale
  current_prefs.play_AI_battles = play_AI_battles
  local battle_type_states = {
    [1] = {
      [true] = "auto_ai",
      [false] = "auto_no_ai"
    },
    [2] = {
      [true] = "fight_ai",
      [false] = "fight_no_ai"
    }
  }
  local selected_strings = advanced_options_panel:LuaCall("DropdownStrings")
  local victory_conditions = UIComponent(this:Find("victory_conditions"))
  local battle_setting = UIComponent(victory_conditions:Find("battle_setting"))
  battle_setting:SetState(battle_type_states[battles_fought + 1][play_AI_battles])
  local turn_time_setting = UIComponent(victory_conditions:Find("turn_time_setting"))
  turn_time_setting:SetStateText(advanced_options_panel:LuaCall("FindTurnTimeString", turn_time_limit))
  local battle_time_setting = UIComponent(victory_conditions:Find("time_setting"))
  battle_time_setting:SetStateText(advanced_options_panel:LuaCall("FindBattleTimeLimitString", battle_time_limit))
  local unit_scale_setting = UIComponent(victory_conditions:Find("unit_scale_setting"))
  unit_scale_setting:SetStateText(advanced_options_panel:LuaCall("FindUnitScaleString", unit_scale))
  local ai_moves = UIComponent(victory_conditions:Find("ai_moves_setting"))
  if show_ai_moves == false then
    ai_moves:SetStateText(FrontEnd.LocalisationString("no"))
  else
    ai_moves:SetStateText(FrontEnd.LocalisationString("yes"))
  end
  SetVictoryConditionsText()
end
function SetVictoryConditionsText()
  local vc = UIComponent(this:Find("dy_victory_conditions"))
  if local_players_faction ~= nil then
    local condition_string = campaign_details.Factions[local_players_faction].VictoryConditions[current_prefs.game_type + 1]
    out.tom(local_players_faction, current_prefs.game_type, condition_string)
    if condition_string ~= nil then
      local w, h = vc:SetStateText(condition_string)
      vc:Resize(w, h)
    end
  end
  local victory_conditions = UIComponent(this:Find("victory_conditions"))
  local list = UIComponent(victory_conditions:Find("listview"))
  list:LuaCall("SetListExtents")
end
function OnShortcut()
end
function OnKey(key, v, ended)
  if key == "ESCAPE" and ended then
    TransitionBack()
  end
end
function DeclareReady()
  if mp_interface ~= nil then
    button_ready = UIComponent(this:Find("button_ready"))
    if button_ready:CurrentState() == "Unselected_depress" then
      Component.LockPriority(10)
      mp_interface:DeclareReady(true)
    else
      Component.LockPriority(0)
      mp_interface:DeclareReady(false)
    end
  end
end
function ShowAdvancedOptions()
  Component.LockPriority(mp_interface:LocalPlayerHosting() and 20 or 21)
  advanced_options_panel:SetVisible(true)
  local button = UIComponent(this:Find("button_ok"))
  button:StealShortcutKey("RETURN")
  button:SetGlobal("OnKey", function(key, v, ended)
    if key == "RETURN" and ended then
      AcceptAdvancedOptions()
    end
  end)
  button:SetGlobal("OnShortcut", function()
  end)
  button = UIComponent(this:Find("button_cancel"))
  button:StealShortcutKey("ESCAPE")
  button:SetGlobal("OnKey", function(key, v, ended)
    if key == "ESCAPE" and ended then
      CancelAdvancedOptions()
    end
  end)
  button:SetGlobal("OnShortcut", function()
  end)
end
function AcceptAdvancedOptions()
  if mp_interface:LocalPlayerHosting() then
    current_prefs = SaveOptions()
    mp_interface:SetCampaignGameOptions(current_prefs)
  end
  CancelAdvancedOptions()
end
function CancelAdvancedOptions()
  Component.LockPriority(0)
  advanced_options_panel:SetVisible(false)
  UIComponent(this:Find("button_ok")):StealShortcutKey(false)
  UIComponent(this:Find("button_cancel")):StealShortcutKey(false)
end
function FactionAndVCType()
  local dropdown = FindPlayerBaseForSlot(mp_interface:LocalPlayerSlot(), "mini_flag")
  return dropdown:LuaCall("SelectedOption"), current_prefs.game_type
end
function SaveOptions()
  local options = advanced_options_panel:LuaCall("CurrentOptions")
  options.campaign_difficulty = UIComponent(this:Find("cmp_diff_slider")):GetProperty("Value")
  options.battle_difficulty = UIComponent(this:Find("btl_diff_slider")):GetProperty("Value")
  return options
end
function FindPlayerBaseForSlot(slot, component_to_find)
  local player_1_slot = UIComponent(cartouche:Find("player_1")):GlobalExists("PlayerSlot")
  local player_index = (player_1_slot == nil or player_1_slot == slot) and 1 or 2
  local base = UIComponent(cartouche:Find("player_" .. player_index))
  if component_to_find == nil then
    return base
  else
    return UIComponent(base:Find(component_to_find))
  end
end
function FilterFaction(slot, faction, taken)
  if #faction > 0 then
    local player_1_base = this:Find("player_1")
    local player_2_base = this:Find("player_2")
    local slot_player_base = FindPlayerBaseForSlot(slot):Address()
    if slot_player_base == player_1_base then
      out.tom("Filtering faction " .. faction .. " from player 2's list (" .. tostring(taken) .. ")")
      UIComponent(player_2_base):LuaCall("AllocateFaction", faction, taken)
    else
      UIComponent(player_1_base):LuaCall("AllocateFaction", faction, taken)
    end
  end
end
function InviteFriends()
  out.tom("Inviting friends")
  friends_panel:LuaCall("Initialise")
end
function OnPlayerJoined(slot, name, faction, ready)
  local local_slot = mp_interface:LocalPlayerSlot()
  local local_player_joined = slot == local_slot
  if local_player_joined == false then
    UIComponent(this:Find("button_kick")):SetVisible(true)
    UIComponent(this:Find("button_invite")):SetState("inactive")
  end
  FilterFaction(slot, faction, true)
  out.tom("Player joined: (slot, name, faction, local_slot, ready)", slot, name, faction, local_slot, ready)
  local player = FindPlayerBaseForSlot(slot)
  player:LuaCall("Initialise", mp_interface, slot, name, faction, current_prefs.resumed)
  if faction ~= nil and #faction > 0 then
    OnPlayerFactionChanged(slot, faction)
  else
    mp_interface:SetFaction(slot, player:LuaCall("FirstAvailableFaction"))
  end
  local player_difficulties = mp_interface:GetPlayerDifficultySettings()
  if player_difficulties ~= nil then
    for i, v in ipairs(player_difficulties) do
      if v.IsLocal == false then
        OnCampaignDifficultyChanged(false, v.CampaignDifficulty)
        OnBattleDifficultyChanged(false, v.BattleDifficulty)
      end
    end
  end
  OnPlayerReadyChanged(slot, ready)
end
function OnTexturePopulate(set)
  if set then
    OnPlayerFactionChanged(mp_interface:LocalPlayerSlot(), local_players_faction)
  end
end
this:SetEventCallback("OnTexturePopulate", OnTexturePopulate)
function OnPlayerFactionChanged(slot, faction)
  out.tom(tostring(slot) .. ": Player faction changed", faction)
  local player_base = FindPlayerBaseForSlot(slot)
  local prev_faction
  if faction ~= nil then
    local fac_details = campaign_details.Factions[faction]
    local game_type_options = UIComponent(this:Find("dropdown_game_type"))
    game_type_options:LuaCall("SetOptions", fac_details.GameTypes)
    current_prefs = SaveOptions()
    prev_faction = player_base:LuaCall("SelectFaction", fac_details)
    local handle = slot == mp_interface:LocalPlayerSlot() and 1 or 2
    SetDifficultySliderFaction("cmp_diff_slider", handle, fac_details)
    SetDifficultySliderFaction("btl_diff_slider", handle, fac_details)
  else
    prev_faction = player_base:LuaCall("ClearDetails")
  end
  if slot == mp_interface:LocalPlayerSlot() then
    local_players_faction = faction
    SetVictoryConditionsText()
  else
    other_players_faction = faction
  end
  if prev_faction ~= nil and #prev_faction > 0 then
    out.tom(tostring(slot) .. ": Previous faction", tostring(prev_faction))
    FilterFaction(slot, prev_faction, false)
  end
  if faction ~= nil then
    FilterFaction(slot, faction, true)
  end
  local theatre_list = {}
  for k, v in pairs(theatres) do
    theatre_list[#theatre_list + 1] = k
  end
  local theatre_maps = FrontEnd.GenerateRegionOwnershipMaps(theatre_list, campaign_details.Key, local_players_faction, other_players_faction, current_prefs.game_type)
  for k, v in pairs(theatre_maps) do
    local image = UIImage(theatre_maps[k])
    local overlay = maps[k].Component:Find("map_overlay")
    image:SetComponentTexture(overlay, 0)
    UIComponent(overlay):SetVisible(true)
  end
end
function OnDisconnected(msg)
  TransitionBack(msg)
end
function OnPlayerLeft(slot, reason)
  if slot ~= mp_interface:LocalPlayerSlot() then
    UIComponent(this:Find("button_invite")):SetState("normal")
    UIComponent(this:Find("button_kick")):SetVisible(false)
    UIComponent(UIComponent(this:Find("cmp_diff_slider")):Find("handle2")):SetVisible(false)
    UIComponent(UIComponent(this:Find("btl_diff_slider")):Find("handle2")):SetVisible(false)
    OnPlayerFactionChanged(slot, nil)
  end
end
function OnPlayerNameChanged(slot, player_name)
  local player_base = FindPlayerBaseForSlot(slot)
  local name = UIComponent(player_base:Find("dy_player_name"))
  name:SetStateText(player_name)
end
function OnPlayerReadyChanged(slot, ready)
  local player_base = FindPlayerBaseForSlot(slot)
  local status = UIComponent(player_base:Find("status"))
  status:SetVisible(true)
  status:SetState(ready and "ready" or "not_ready")
  if mp_interface:LocalPlayerSlot() == slot then
    local ready_txt = UIComponent(UIComponent(this:Find("button_ready")):Find(0))
    ready_txt:SetState(ready and "not ready" or "ready")
  end
end
function KickPlayer()
  local player_details = mp_interface:PlayerDetails()
  mp_interface:KickPlayer(player_details[2][1].Slot)
end


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
