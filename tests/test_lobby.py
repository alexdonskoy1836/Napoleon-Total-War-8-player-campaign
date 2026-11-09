"""Behavior tests for Napoleon lobby Lua using Lua 5.1 and a small engine/UI model.

This validates script logic; it does not substitute for multiplayer engine tests.
"""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'source'))
from lupa.lua51 import LuaRuntime
from compile_lua import convert

MOCK = r'''
package.preload.Utilities = function() return {Clamp=function(v,a,b) return math.max(a,math.min(b,v)) end} end
out = {tom=function(...) end}
nodes = {}
native_calls = {kicks={},factions={},ready={},options={}}
pending = {}
local Node = {}
Node.__index = Node
function NewNode(id, parent)
  local n=setmetatable({id=id,parent=parent,children={},visible=true,state='up',props={Value=1},globals={},calls={},x=0,y=0},Node)
  if parent then table.insert(parent.children,n) end
  nodes[id]=nodes[id] or n
  return n
end
function Node:Find(id)
  if type(id)=='number' then return self.children[id+1] end
  for _,n in ipairs(self.children) do if n.id==id then return n end end
  for _,n in ipairs(self.children) do local x=n:Find(id);if x then return x end end
  return nil
end
function Node:Parent(id)
  if id==nil then return self.parent end
  local p=self.parent
  if type(id)=='number' then for _=2,id do p=p.parent end;return p end
  while p and p.id~=id do p=p.parent end
  return p
end
function Node:Id() return self.id end
function Node:Address() return self end
function Node:ChildCount() return #self.children end
function Node:SetVisible(v) self.visible=v end
function Node:Visible() return self.visible end
function Node:PropagateVisibility(v) self.visible=v;for _,n in ipairs(self.children) do n:PropagateVisibility(v) end end
function Node:SetState(v)
  if self.id=='mini_flag' and self.parent.id:match('^player_') then
    assert(v=='inactive' or v=='roll' or v=='up' or v=='down' or v=='down_off', 'Unknown faction dropdown state '..tostring(v))
  end
  self.state=v
end
function Node:CurrentState() return self.state end
function Node:SetStateText(v) self.text=v;return 120,24 end
function Node:SetTooltipText(v) self.tooltip=v end
function Node:Resize(w,h) self.w,self.h=w,h end
function Node:Position() return self.x,self.y end
function Node:MoveTo(x,y) self.x,self.y=x,y end
function Node:SetMoveable(v) self.moveable=v end
function Node:SetProperty(k,v) self.props[k]=v end
function Node:GetProperty(k) return self.props[k] end
function Node:SetGlobal(k,v) self.globals[k]=v end
function Node:GlobalExists(k) return self.globals[k] end
function Node:StealShortcutKey(...) end
function Node:SetEventCallback(k,v) self.globals[k]=v end
function Node:LuaCall(method,...)
  self.calls[method]=(self.calls[method] or 0)+1
  if self.globals[method] then return self.globals[method](...) end
  local args={...}
  if method=='SetFactionList' then self.faction_list=args[1]; self.allocated={} end
  if method=='AllocateFaction' then self.allocated=self.allocated or {};self.allocated[args[1]]=args[2] end
  if method=='FirstAvailableFaction' then
    for _,f in ipairs(self.faction_list()) do if not self.allocated[f.Key] then return f.Key end end
    return nil
  end
  if method=='Initialise' and self.id:match('^player_') then
    self.globals.PlayerSlot=args[2];self.globals.Faction=args[4];self.visible=true
    for _,c in ipairs(self.children) do c.visible=true end
    self:Find('dy_player_name').text=args[3]
    self:Find('mini_flag').state=(args[2]~=iface.local_slot or args[5]) and 'inactive' or 'up'
  end
  if method=='SelectFaction' then
    local prev=self.globals.Faction;self.globals.Faction=args[1].Key
    self:Find('dy_faction_name').text=args[1].Name;return prev
  end
  if method=='ClearDetails' then
    local prev=self.globals.Faction;self.globals.PlayerSlot=nil;self.globals.Faction=nil
    self:PropagateVisibility(false);return prev
  end
  if method=='CurrentOptions' then return {campaign_difficulty=1,battle_difficulty=1,game_type=0} end
  if method=='DropdownStrings' then return {} end
  if method=='SelectedOption' then return self.parent.globals.Faction end
  if method=='FindTurnTimeString' or method=='FindBattleTimeLimitString' or method=='FindUnitScaleString' then return 'value' end
  if method=='ValueSet' then self.props.Value=args[1] end
  return nil
end
function UIComponent(n) assert(type(n)=='table','UIComponent received invalid address '..tostring(n));return n end
root_node=NewNode('root')
main=NewNode('main_panel',root_node)
cartouche_node=NewNode('cartouche',main)
for i=1,8 do
  local p=NewNode('player_'..i,cartouche_node)
  for _,id in ipairs({'mini_flag','icon_voicechat','dy_faction_name','dy_player_name','status','button_kick'}) do NewNode(id,p) end
end
for _,id in ipairs({'advanced_options','friends_list','button_options','button_invite','legacy_button_kick','season_year','Turns','button_ready','dropdown_game_type','dy_victory_conditions'}) do NewNode(id,main) end
NewNode('countdown',nodes.button_ready)
local diff=NewNode('difficulty_settings',main)
for _,id in ipairs({'cmp_diff_slider','btl_diff_slider'}) do
  local slider=NewNode(id,diff)
  for _,h in ipairs({'handle','handle2'}) do NewNode('mini_flag',NewNode(h,slider)) end
end
local vc=NewNode('victory_conditions',main)
for _,id in ipairs({'battle_setting','turn_time_setting','time_setting','unit_scale_setting','ai_moves_setting','listview'}) do NewNode(id,vc) end
for _,id in ipairs({'map_nap_europe','map_nap_italy','map_nap_egypt','map_nap_spain'}) do NewNode('map_overlay',NewNode(id,main)) end
Component={Root=function() return root_node end,LockPriority=function(v) end}
Address=main
function UIImage(path) return {SetComponentTexture=function(...) end} end
function UIMPInterface(n) return n end
factions={}
for i=1,8 do factions['f'..i]={Key='f'..i,ListOrder=i,Name='Faction '..i,FlagPath='flags/f'..i,GameTypes={},VictoryConditions={[1]='Win',[2]='Win'}} end
campaign={Key='mp_europe',Factions=factions}
iface={local_slot=10,host=true,roster={{},{}},left=false}
function iface:PlayerDetails() return self.roster end
function iface:LocalPlayerSlot() return self.local_slot end
function iface:LocalPlayerHosting() return self.host end
function iface:SetCampaignGameOptions(v) table.insert(native_calls.options,v) end
function iface:GetPlayerDifficultySettings() return {} end
function iface:PlayerVOIPTalking() return false end
function iface:PlayerVOIPActive() return false end
function iface:PlayerIdFromSlot(slot) return slot end
function iface:SetFaction(slot,faction)
  assert(faction~=nil,'native SetFaction called with nil')
  table.insert(native_calls.factions,{slot,faction})
  for _,team in ipairs(self.roster) do for _,p in ipairs(team) do if p.Slot==slot then p.Faction=faction end end end
  table.insert(pending,function() OnPlayerFactionChanged(slot,faction) end)
end
function iface:KickPlayer(slot) table.insert(native_calls.kicks,slot) end
function iface:DeclareReady(v) table.insert(native_calls.ready,v) end
function iface:LeaveLobby() self.left=true end
FrontEnd={
  MPInterface=function() return iface end,
  MPCurrentGameDetails=function() return iface.left and nil or {} end,
  MPHasLobby=function() return true end,
  MPIsOnline=function() return true end,
  MPOnlinePresence=function() return {} end,
  SetCurrentGameType=function(...) end,
  TheatreList=function() return {europe_main={Map='map'}} end,
  CampaignDetails=function() return campaign end,
  LocalisationString=function(v) return v end,
  TriggerSliderUpdateEvent=function(...) end,
  GenerateRegionOwnershipMaps=function(...) return {} end
}
game_details={Map='mp_europe',campaign_difficulty=1,battle_difficulty=1,battle_type=0,turn_time=0,time_limit=0,CPU_moves=false,game_type=0,unit_scale=1,play_AI_battles=true,Date='1805',Turns='1',resumed=false}
function Drain() while #pending>0 do local fn=table.remove(pending,1);fn() end end
function AddRoster(slot,faction,team)
  local p={Slot=slot,Name='Player '..slot,Faction=faction,Ready=false}
  table.insert(iface.roster[team or 1],p);return p
end
function RemoveRoster(slot)
  for _,team in ipairs(iface.roster) do for i=#team,1,-1 do if team[i].Slot==slot then table.remove(team,i) end end end
end
'''

def new_runtime():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(MOCK)
    # Execute the exact shipped payload through a host-ABI translation.
    bytecode = (ROOT / 'payload' / 'main_panel.luac').read_bytes()
    assert bytecode[:12] == bytes.fromhex('1b4c75615100010404040400')
    binary_vm = LuaRuntime(encoding=None)
    host_header = binary_vm.eval(b'string.dump(function() end)')[:12]
    lua.execute(convert(bytecode, size_t=host_header[8], number=host_header[10]))
    return lua

def run_case(name, source):
    lua = new_runtime()
    lua.execute(source)
    print('PASS', name)

if __name__ == '__main__':
    run_case('load and empty lobby initialization', 'Initialise(game_details); CreateMpInterface(); OnUpdate()')
    run_case('eight players across both native teams, ready/name updates, exact kicks', r'''
      for i=0,7 do AddRoster(10+i,'f'..(i+1),i<4 and 1 or 2) end
      Initialise(game_details);CreateMpInterface();OnUpdate()
      local seen={}
      for i=0,7 do
        local p=FindPlayerBaseForSlot(10+i)
        assert(p and not seen[p],'missing or shared player panel');seen[p]=true
        assert(p.globals.PlayerSlot==10+i)
        assert(p.globals.Faction=='f'..(i+1))
        assert(p.calls.Update>0,'player update was skipped')
        OnPlayerNameChanged(10+i,'Renamed '..i)
        assert(p:Find('dy_player_name').text=='Renamed '..i)
        OnPlayerReadyChanged(10+i,true)
        assert(p:Find('status').state=='ready')
        assert(p:Find('button_kick').visible==(i~=0),'incorrect host kick visibility')
        p:LuaCall('KickPlayer')
      end
      assert(#native_calls.kicks==7)
      for i=1,7 do assert(native_calls.kicks[i]==10+i,'kick targeted wrong player') end
      assert(nodes.button_invite.state=='inactive','full lobby invite remains active')
      assert(FindPlayerBaseForSlot(10):Find('mini_flag').state=='up')
      assert(FindPlayerBaseForSlot(17):Find('mini_flag').state=='inactive')
      local f,vc=FactionAndVCType();assert(f=='f1' and vc==0)
    ''')
    run_case('faction changes reserve and release every other dropdown', r'''
      AddRoster(10,'f1',1);AddRoster(91,'f2',2)
      Initialise(game_details);CreateMpInterface()
      local p1=FindPlayerBaseForSlot(10);local p2=FindPlayerBaseForSlot(91)
      assert(p1.allocated.f2 and not p1.allocated.f1)
      assert(p2.allocated.f1 and not p2.allocated.f2)
      OnPlayerFactionChanged(91,'f3')
      for i=1,8 do
        local p=cartouche_node:Find('player_'..i)
        assert(not p.allocated.f2,'old faction remained allocated')
        assert(p.allocated.f3==(p~=p2),'new faction filtering incorrect')
      end
      OnPlayerFactionChanged(91,'unknown_faction')
      assert(p2.globals.Faction=='f3','invalid faction overwrote state')
    ''')
    run_case('leave releases slot/faction; replacement gets correct kick and visibility', r'''
      for i=0,7 do AddRoster(10+i,'f'..(i+1),i<4 and 1 or 2) end
      Initialise(game_details);CreateMpInterface()
      local old=FindPlayerBaseForSlot(15)
      RemoveRoster(15);OnPlayerLeft(15,'quit')
      assert(FindPlayerBaseForSlot(15)==nil)
      assert(not old.visible and not old:Find('button_kick').visible)
      assert(nodes.button_invite.state=='normal')
      for i=1,8 do assert(not cartouche_node:Find('player_'..i).allocated.f6) end
      AddRoster(99,'f6',2);OnPlayerJoined(99,'Replacement','f6',false)
      assert(FindPlayerBaseForSlot(99)==old,'freed panel was not reused')
      assert(old.visible and old:Find('button_kick').visible)
      assert(old:Find('status').state=='not_ready')
      old:LuaCall('KickPlayer');assert(native_calls.kicks[#native_calls.kicks]==99)
      KickPlayer(15);assert(#native_calls.kicks==1,'stale occupant could be kicked')
    ''')
    run_case('client authority and local selection with arbitrary ordering', r'''
      iface.host=false;iface.local_slot=67
      AddRoster(41,'f1',1);AddRoster(67,'f2',2);AddRoster(98,'f3',2)
      Initialise(game_details);CreateMpInterface()
      for i=1,8 do
        local p=cartouche_node:Find('player_'..i)
        assert(not p:Find('button_kick').visible)
        p:LuaCall('KickPlayer')
      end
      KickPlayer(41);assert(#native_calls.kicks==0,'client issued native kick')
      assert(not nodes.button_invite.visible)
      assert(FindPlayerBaseForSlot(67):Find('mini_flag').state=='up')
      nodes.button_ready.state='Unselected_depress';DeclareReady()
      assert(native_calls.ready[1]==true)
    ''')
    run_case('resumed session preserves faction ownership and locks selection', r'''
      game_details.resumed=true
      for i=0,7 do AddRoster(10+i,'f'..(i+1),i<4 and 1 or 2) end
      Initialise(game_details);CreateMpInterface()
      assert(#native_calls.factions==0,'resume changed an assigned faction')
      for i=0,7 do assert(FindPlayerBaseForSlot(10+i):Find('mini_flag').state=='inactive') end
    ''')
    run_case('automatic local choice excludes all preexisting factions across teams', r'''
      AddRoster(10,'',1)
      for i=2,8 do AddRoster(20+i,'f'..i,i<5 and 1 or 2) end
      Initialise(game_details);CreateMpInterface();Drain()
      assert(#native_calls.factions==1)
      assert(native_calls.factions[1][1]==10 and native_calls.factions[1][2]=='f1')
      assert(FindPlayerBaseForSlot(10).globals.Faction=='f1')
    ''')
    run_case('exhausted faction list never sends nil faction; remote empty join waits', r'''
      for i=3,8 do factions['f'..i]=nil end
      AddRoster(10,'',1);AddRoster(20,'f1',1);AddRoster(30,'f2',2)
      Initialise(game_details);CreateMpInterface()
      assert(#native_calls.factions==0,'no faction available but native setter invoked')
      AddRoster(40,'',2);OnPlayerJoined(40,'Waiting','',false)
      assert(#native_calls.factions==0,'host overwrote remote automatic choice')
    ''')
    run_case('out-of-range and stale callbacks do not corrupt eight real players', r'''
      for i=0,7 do AddRoster(10+i,'f'..(i+1),i<4 and 1 or 2) end
      Initialise(game_details);CreateMpInterface()
      OnPlayerJoined(300,'Ninth','f1',false)
      assert(FindPlayerBaseForSlot(300)==nil)
      OnPlayerReadyChanged(300,true);OnPlayerNameChanged(300,'No panel')
      OnPlayerFactionChanged(300,'f2');OnPlayerLeft(300,'none');KickPlayer(300)
      OnPlayerJoined(nil,'Invalid',nil,false)
      for i=0,7 do assert(FindPlayerBaseForSlot(10+i).globals.Faction=='f'..(i+1)) end
      assert(#native_calls.kicks==0)
    ''')
