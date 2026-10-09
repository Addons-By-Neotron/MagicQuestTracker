--[[
**********************************************************************
MagicQuestTracker - Header themes.
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
local media = LibStub("LibSharedMedia-3.0")

----------------------------------------------------------------
-- Themes style the tracker title and the section / zone headers.
--
-- Each theme provides:
--   StyleTitle(title, profile)   -> title bar height
--   MinimizeAtlas(minimized)     -> atlas for the minimize button
--   HeaderLayout(kind, profile)  -> isBar, minHeight, textIndent, padding
--   StyleHeader(line, kind, left)   (only called when HeaderLayout says isBar)
--
-- kind is "section" (Quests, World Quests, ...) or "zone". Header styling
-- is costly (SetBackdrop), so lines are only restyled when the theme
-- version (bumped by RefreshTheme) or their header kind changes.
----------------------------------------------------------------

local WHITE = "Interface\\Buttons\\WHITE8X8"
local TITLE_ATLAS = "ui-questtracker-primary-objective-header"
local HEADER_ATLAS = "UI-QuestTracker-Secondary-Objective-Header"
local BLIZZARD_TRACKER_WIDTH = 260
local TITLE_PADDING = 6

mod.themeVersion = 0

-- Blizzard's tracker header art, offered next to the SharedMedia statusbar
-- textures for the Custom theme. Atlases can't be registered with
-- LibSharedMedia (it only holds file paths), so they are handled here.
--   centered: drawn at natural size, centered, widened with the tracker
--   minHeight: header height the art is designed for
local ATLAS_TEXTURES = {
   ["Blizzard Tracker Title"] = { atlas = TITLE_ATLAS, centered = true, minHeight = 30 },
   ["Blizzard Tracker Header"] = { atlas = HEADER_ATLAS, minHeight = 24 },
}

--- Statusbar textures plus the Blizzard header art, for the texture dropdown.
--- Values are preview paths (the art previews as its whole texture file).
function mod:GetBarTextureList()
   local list = {}
   for name, path in pairs(media:HashTable("statusbar")) do
      list[name] = path
   end
   for name, art in pairs(ATLAS_TEXTURES) do
      local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(art.atlas)
      list[name] = info and info.file or name
   end
   return list
end

local function CreateBorder(owner)
   local border = CreateFrame("Frame", nil, owner, "BackdropTemplate")
   border:EnableMouse(false)
   owner.border = border
   return border
end

local function HideBorder(owner)
   if owner.border then owner.border:Hide() end
end

----------------------------------------------------------------
-- Blizzard: the built-in objective tracker's header art.
----------------------------------------------------------------

local blizzard = {}

function blizzard.StyleTitle(title, profile)
   local bg = title.bg
   bg:ClearAllPoints()
   bg:SetVertexColor(1, 1, 1, 1)
   -- Natural size, centered: on Blizzard's 260 px header the art overhangs
   -- both ends (the swirl left of the text). Keep that overhang at any width.
   bg:SetAtlas(TITLE_ATLAS, true)
   bg.naturalWidth = bg.naturalWidth or bg:GetWidth()
   bg:SetPoint("CENTER")
   bg:SetWidth(bg.naturalWidth + profile.width - BLIZZARD_TRACKER_WIDTH)
   bg:Show()
   HideBorder(title)
   title.minimize:GetHighlightTexture():SetAlpha(1)
   title.minimize:ClearAllPoints()
   title.minimize:SetPoint("RIGHT", -2, 0)
   return math.max(30, profile.fonts.title.size + TITLE_PADDING), 7
end

function blizzard.MinimizeAtlas(minimized)
   return minimized and "ui-questtrackerbutton-expand-all" or "ui-questtrackerbutton-collapse-all"
end

function blizzard.HeaderLayout(kind)
   if kind == "section" then
      return true, 24, 7, 6
   end
   return false
end

function blizzard.StyleHeader(line)
   local bg = line.bg
   bg:ClearAllPoints()
   bg:SetVertexColor(1, 1, 1, 1)
   bg:SetAtlas(HEADER_ATLAS, true)
   bg:SetPoint("LEFT")
   bg:SetPoint("RIGHT")
   HideBorder(line)
   line.collapseIcon:SetPoint("RIGHT", -2, 0)
end

----------------------------------------------------------------
-- Custom: colored bars with a SharedMedia texture and optional border,
-- set separately for the title, section headers and zone headers
-- (profile.custom[kind]).
----------------------------------------------------------------

local custom = {}
-- Per kind; replaced (never modified) on refresh, as SetBackdrop ignores a
-- table it already has. false = no border.
local backdrops = {}

-- Space taken by the border edge, kept clear of the bar and text.
local function BorderInset(kind)
   local backdrop = backdrops[kind]
   if not backdrop then return 0 end
   return math.floor(backdrop.edgeSize / 4 + 0.5)
end

local function StyleBar(owner, kind, left)
   local profile = mod.db.profile
   local settings = profile.custom[kind]
   local inset = BorderInset(kind)
   local bg = owner.bg
   local color = settings.color
   local art = ATLAS_TEXTURES[settings.texture]
   bg:ClearAllPoints()
   if art then
      -- Placed like the Blizzard theme does.
      bg:SetAtlas(art.atlas, true)
      if art.centered then
         bg:SetWidth(bg:GetWidth() + profile.width - BLIZZARD_TRACKER_WIDTH)
         bg:SetPoint("CENTER")
      else
         bg:SetPoint("LEFT", left, 0)
         bg:SetPoint("RIGHT")
      end
   else
      bg:SetTexture(media:Fetch("statusbar", settings.texture) or WHITE)
      bg:SetTexCoord(0, 1, 0, 1)
      bg:SetPoint("TOPLEFT", left + inset, -inset)
      bg:SetPoint("BOTTOMRIGHT", -inset, inset)
   end
   bg:SetVertexColor(color.r, color.g, color.b, color.a)
   bg:Show()

   local backdrop = backdrops[kind]
   if backdrop then
      local border = owner.border or CreateBorder(owner)
      border:ClearAllPoints()
      border:SetPoint("TOPLEFT", left, 0)
      border:SetPoint("BOTTOMRIGHT")
      border:SetBackdrop(backdrop)
      local c = settings.borderColor
      border:SetBackdropBorderColor(c.r, c.g, c.b, c.a)
      border:Show()
   else
      HideBorder(owner)
   end
   return inset
end

-- Height and text inset the art is designed for, or flat bar defaults.
local function ArtMetrics(settings)
   local art = ATLAS_TEXTURES[settings.texture]
   if art then return art.minHeight, 7 end
   return 0, 4
end

function custom.StyleTitle(title, profile)
   local settings = profile.custom.title
   local inset = StyleBar(title, "title", 0)
   title.minimize:GetHighlightTexture():SetAlpha(settings.borderedButton and 1 or 0)
   title.minimize:ClearAllPoints()
   title.minimize:SetPoint("RIGHT", -2 - inset, 0)
   local minHeight, textIndent = ArtMetrics(settings)
   return math.max(minHeight, profile.fonts.title.size + TITLE_PADDING) + 2 * inset, textIndent + inset
end

function custom.MinimizeAtlas(minimized)
   if mod.db.profile.custom.title.borderedButton then
      return blizzard.MinimizeAtlas(minimized)
   end
   return minimized and "ui-questtrackerbutton-secondary-expand" or "ui-questtrackerbutton-secondary-collapse"
end

function custom.HeaderLayout(kind, profile)
   -- Headers without a visible bar or border stay plain text.
   if profile.custom[kind].color.a == 0 and not backdrops[kind] then
      return false
   end
   local inset = BorderInset(kind)
   local minHeight, textIndent = ArtMetrics(profile.custom[kind])
   return true, minHeight + 2 * inset, textIndent + inset, 6 + 2 * inset
end

function custom.StyleHeader(line, kind, left)
   local inset = StyleBar(line, kind, left)
   line.collapseIcon:SetPoint("RIGHT", -2 - inset, 0)
end

----------------------------------------------------------------

local themes = {
   blizzard = blizzard,
   custom = custom,
}

function mod:GetTheme()
   return themes[self.db.profile.theme] or blizzard
end

--- Call when theme settings change; header lines restyle on next render.
function mod:RefreshTheme()
   self.themeVersion = self.themeVersion + 1
   for kind, settings in pairs(self.db.profile.custom) do
      local edge = settings.border ~= "None" and media:Fetch("border", settings.border)
      backdrops[kind] = edge and edge ~= "" and { edgeFile = edge, edgeSize = settings.borderSize } or false
   end
end
