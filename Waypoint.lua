--[[
**********************************************************************
MagicQuestTracker - Quest waypoints (TomTom or Blizzard navigation).
**********************************************************************
Copyright (C) 2026 NeoTron

This file is part of MagicQuestTracker, a World of Warcraft Addon

MagicQuestTracker is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

MagicQuestTracker is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
General Public License for more details.

You should have received a copy of the GNU General Public License
along with MagicQuestTracker.  If not, see <https://www.gnu.org/licenses/>.

**********************************************************************
]]
local mod = LibStub("AceAddon-3.0"):GetAddon("MagicQuestTracker")
local L = LibStub("AceLocale-3.0"):GetLocale("MagicQuestTracker")

local C_Map = C_Map
local C_QuestLog = C_QuestLog

----------------------------------------------------------------
-- Quest waypoints
--
-- The location is the quest's map POI: the objective area while in
-- progress, the turn-in NPC when complete. Lookup order:
--   1. POIs on the player's map and its parents (up to the continent)
--   2. C_QuestLog.GetNextWaypoint (quests routed through other zones)
--   3. The zone map named like the quest's log header, on this continent
----------------------------------------------------------------

local function GetPlayerContinent()
   local continentType = Enum.UIMapType and Enum.UIMapType.Continent or 2
   local mapID = C_Map.GetBestMapForUnit("player")
   while mapID and mapID > 0 do
      local info = C_Map.GetMapInfo(mapID)
      if not info then return nil end
      if info.mapType == continentType then return mapID end
      mapID = info.parentMapID
   end
end

-- Map ID of the zone named like a quest log header ("Wetlands", or
-- "Excavation Site: Wetlands" -> "Wetlands"), searched on this continent.
local function FindZoneMap(header)
   local continent = header and GetPlayerContinent()
   if not continent then return nil end
   local parentZone = header:match(":%s*(.-)%s*$")
   local zoneType = Enum.UIMapType and Enum.UIMapType.Zone or 3
   for _, info in ipairs(C_Map.GetMapChildrenInfo(continent, zoneType, true) or {}) do
      if info.name == header or info.name == parentZone then
         return info.mapID
      end
   end
end

local function FindOnMap(mapID, questID)
   for _, poi in ipairs(C_QuestLog.GetQuestsOnMap(mapID) or {}) do
      if poi.questID == questID then
         return { mapID = mapID, x = poi.x, y = poi.y }
      end
   end
end

--- Returns { mapID, x, y } for the quest's next location, or nil.
function mod:GetQuestLocation(quest)
   local questID = quest.questID
   if quest.isTask then
      return self.GetTaskLocation(questID)
   end
   local location = quest.poi
   if not location then
      local pois = self:CollectQuestPOIs()
      location = pois[questID]
      pois[questID] = nil
      mod.deepDel(pois)
   end
   if location then return location end

   if C_QuestLog.GetNextWaypoint then
      local mapID, x, y = C_QuestLog.GetNextWaypoint(questID)
      if mapID and x and y then
         return { mapID = mapID, x = x, y = y }
      end
   end

   local zoneMap = FindZoneMap(quest.zoneName)
   return zoneMap and FindOnMap(zoneMap, questID)
end

function mod:HasTomTom()
   return TomTom and TomTom.AddWaypoint and true or false
end

local function SetTomTomWaypoint(self, quest)
   local location = self:GetQuestLocation(quest)
   if not location then
      self:info(L["No location known for %s."], quest.title)
      return
   end
   -- Replace our previous waypoint rather than piling them up.
   if self.tomtomWaypoint and TomTom.RemoveWaypoint then
      TomTom:RemoveWaypoint(self.tomtomWaypoint)
   end
   self.tomtomWaypoint = TomTom:AddWaypoint(location.mapID, location.x, location.y, {
      title = quest.title,
      crazy = true,
      from = "MagicQuestTracker",
   })
end

--- Focuses (super tracks) a quest; 0 stops focusing. Called from addon
--- code, this fires SUPER_TRACKING_CHANGED tainted, and Blizzard's handlers
--- (map pins, objective tracker) then trip over protected calls and secret
--- auras. That can't be avoided, but in combat it is deferred until combat
--- ends, where secret auras make it fail.
function mod:SetSuperTrackedQuest(questID)
   if not self.db.profile.blizzardFocus then
      self.pendingSuperTrack = nil
      return
   end
   if InCombatLockdown() then
      self.pendingSuperTrack = questID
      return
   end
   self.pendingSuperTrack = nil
   C_SuperTrack.SetSuperTrackedQuestID(questID)
end

function mod:ApplyPendingSuperTrack()
   if self.pendingSuperTrack then
      self:SetSuperTrackedQuest(self.pendingSuperTrack)
   end
end

--- Navigates to the quest using the configured method: a TomTom waypoint,
--- Blizzard's navigation (focusing / super tracking the quest), or both.
--- Without TomTom, Blizzard's navigation is always used. With Blizzard
--- quest focus turned off, only TomTom is used (if present).
function mod:SetQuestWaypoint(quest, mode)
   mode = mode or self.db.profile.waypointMode
   local focus = self.db.profile.blizzardFocus
   local useTomTom = self:HasTomTom() and (mode ~= "blizzard" or not focus)
   if focus and (mode ~= "tomtom" or not useTomTom) then
      self:SetSuperTrackedQuest(quest.questID)
   end
   if useTomTom then
      SetTomTomWaypoint(self, quest)
   end
end
