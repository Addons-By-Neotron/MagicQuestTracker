local mod = LibStub("AceAddon-3.0"):GetAddon("MagicQuestTracker")

local C_Map = C_Map
local C_QuestLog = C_QuestLog
local atan2, sqrt = math.atan2, math.sqrt

----------------------------------------------------------------
-- Direction arrows
--
-- Quest POI positions come from C_QuestLog.GetQuestsOnMap for the
-- player's map and its parents (up to the continent), so quests in
-- neighbouring zones get a direction too. The player's position is read
-- on the same map, and map coordinates are scaled to yards to correct for
-- the map's aspect ratio. Position and facing are unavailable in
-- instances, so no arrows are shown there.
----------------------------------------------------------------

local ARROW_INTERVAL = 0.05

--- Returns [questID] = { mapID, x, y } for quests with a POI near the player.
function mod:CollectQuestPOIs()
   local pois = {}
   if IsInInstance() then return pois end

   local continentType = Enum.UIMapType and Enum.UIMapType.Continent or 2
   local mapID = C_Map.GetBestMapForUnit("player")
   while mapID and mapID > 0 do
      local info = C_Map.GetMapInfo(mapID)
      if not info then break end
      if C_Map.GetPlayerMapPosition(mapID, "player") then
         for _, poi in ipairs(C_QuestLog.GetQuestsOnMap(mapID) or {}) do
            if not pois[poi.questID] then
               pois[poi.questID] = { mapID = mapID, x = poi.x, y = poi.y }
            end
         end
      end
      if info.mapType <= continentType then break end
      mapID = info.parentMapID
   end
   return pois
end

-- Map size in yards: { width, height }, or false if unknown.
local mapSizes = {}

local function WorldDistance(a, b)
   local dx, dy = b.x - a.x, b.y - a.y
   return sqrt(dx * dx + dy * dy)
end

local function GetMapSize(mapID)
   local size = mapSizes[mapID]
   if size == nil then
      local _, origin = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(0, 0))
      local _, right = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(1, 0))
      local _, down = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(0, 1))
      if origin and right and down then
         size = { WorldDistance(origin, right), WorldDistance(origin, down) }
      else
         size = false
      end
      mapSizes[mapID] = size
   end
   return size
end

local playerPositions = {}

--- Rotates the arrows of all visible quest lines toward their POI.
function mod:UpdateArrows()
   local facing = GetPlayerFacing()
   wipe(playerPositions)
   for i = 1, self.numLinesUsed or 0 do
      local line = self.lines[i]
      local target = line.arrowTarget
      if target then
         local shown = false
         if facing then
            local pos = playerPositions[target.mapID]
            if pos == nil then
               pos = C_Map.GetPlayerMapPosition(target.mapID, "player") or false
               playerPositions[target.mapID] = pos
            end
            local size = GetMapSize(target.mapID)
            if pos and size then
               local px, py = pos:GetXY()
               local east = (target.x - px) * size[1]
               local south = (target.y - py) * size[2]
               -- Facing is radians counter-clockwise from north, as is SetRotation.
               line.arrow:SetRotation(atan2(-east, -south) - facing)
               shown = true
            end
         end
         line.arrow:SetShown(shown)
      end
   end
end

function mod:TickArrows(elapsed)
   self.arrowElapsed = (self.arrowElapsed or 0) + elapsed
   if self.arrowElapsed < ARROW_INTERVAL then return end
   self.arrowElapsed = 0
   if self.db.profile.showDirection then
      self:UpdateArrows()
   end
end
