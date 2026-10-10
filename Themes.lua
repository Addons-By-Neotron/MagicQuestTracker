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
local L = LibStub("AceLocale-3.0"):GetLocale("MagicQuestTracker")
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
local HEADER_KINDS = { "title", "section", "zone" }
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
   bg:SetWidth(bg.naturalWidth + mod:GetLayoutSettings().width - BLIZZARD_TRACKER_WIDTH)
   bg:Show()
   HideBorder(title)
   title.minimize:GetHighlightTexture():SetAlpha(1)
   title.minimize:ClearAllPoints()
   title.minimize:SetPoint("RIGHT", -2, 0)
   return math.max(30, mod:GetFonts().title.size + TITLE_PADDING), 7
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
-- set separately for the title, section headers and zone headers.
-- Custom themes are named and stored in global.themes, shared by all
-- profiles; profile.theme selects one (or "blizzard").
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
   local settings = mod:GetThemeSettings()[kind]
   local inset = BorderInset(kind)
   local bg = owner.bg
   local color = settings.color
   local art = ATLAS_TEXTURES[settings.texture]
   bg:ClearAllPoints()
   if art then
      -- Placed like the Blizzard theme does.
      bg:SetAtlas(art.atlas, true)
      if art.centered then
         bg:SetWidth(bg:GetWidth() + mod:GetLayoutSettings().width - BLIZZARD_TRACKER_WIDTH)
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
   local settings = mod:GetThemeSettings().title
   local inset = StyleBar(title, "title", 0)
   title.minimize:GetHighlightTexture():SetAlpha(settings.borderedButton and 1 or 0)
   title.minimize:ClearAllPoints()
   title.minimize:SetPoint("RIGHT", -2 - inset, 0)
   local minHeight, textIndent = ArtMetrics(settings)
   return math.max(minHeight, mod:GetFonts().title.size + TITLE_PADDING) + 2 * inset, textIndent + inset
end

function custom.MinimizeAtlas(minimized)
   if mod:GetThemeSettings().title.borderedButton then
      return blizzard.MinimizeAtlas(minimized)
   end
   return minimized and "ui-questtrackerbutton-secondary-expand" or "ui-questtrackerbutton-secondary-collapse"
end

function custom.HeaderLayout(kind, profile)
   -- Headers without a visible bar or border stay plain text.
   local settings = mod:GetThemeSettings()[kind]
   if settings.color.a == 0 and not backdrops[kind] then
      return false
   end
   local inset = BorderInset(kind)
   local minHeight, textIndent = ArtMetrics(settings)
   return true, minHeight + 2 * inset, textIndent + inset, 6 + 2 * inset
end

function custom.StyleHeader(line, kind, left)
   local inset = StyleBar(line, kind, left)
   line.collapseIcon:SetPoint("RIGHT", -2 - inset, 0)
end

----------------------------------------------------------------

local BLIZZARD = "blizzard"

--- Settings of the selected custom theme, or nil for a built-in theme.
function mod:GetCustomTheme()
   return self.db.global.themes[self.db.profile.theme]
end

----------------------------------------------------------------
-- Built-in presets: read-only dark themes drawn by the Custom renderer.
-- They only change colors, bars and background; fonts and spacing are
-- standard.
-- "New theme" copies one to customize it.
----------------------------------------------------------------

local function Hex(hex)
   return {
      r = tonumber(hex:sub(1, 2), 16) / 255,
      g = tonumber(hex:sub(3, 4), 16) / 255,
      b = tonumber(hex:sub(5, 6), 16) / 255,
   }
end

-- A dark preset from a palette (hex colors):
--   bg, bar        background and title/section bars
--   body, emphasis, secondary   objectives, current zone, dimmed text
--   title, section, zone, quest, tag, arrow   accents
--   green, yellow, orange, red  difficulty, time left and failed
local function DarkPreset(c)
   local theme = CopyTable(mod.themeDefaults)
   local function Bar(settings)
      settings.texture = "Solid"
      settings.color = Hex(c.bar)
      settings.color.a = 1
   end
   Bar(theme.title)
   theme.title.borderedButton = false
   Bar(theme.section)
   theme.background.texture = "Solid"
   theme.background.color = Hex(c.bg)
   theme.background.alpha = 0.85
   theme.background.hoverAlpha = 0.95
   theme.layout.padding = 4
   local colors = theme.colors
   colors.title = Hex(c.title)
   colors.section = Hex(c.section)
   colors.zone = Hex(c.zone)
   colors.currentZone = Hex(c.emphasis)
   colors.quest = Hex(c.quest)
   colors.questTag = Hex(c.tag)
   colors.objective = Hex(c.body)
   colors.complete = Hex(c.secondary)
   colors.failed = Hex(c.red)
   colors.timeLeft = Hex(c.orange)
   colors.distance = Hex(c.secondary)
   colors.arrow = Hex(c.arrow)
   colors.scrollbar = Hex(c.secondary)
   colors.trivial = Hex(c.secondary)
   colors.standard = Hex(c.green)
   colors.difficult = Hex(c.yellow)
   colors.verydifficult = Hex(c.orange)
   colors.impossible = Hex(c.red)
   return theme
end

local PRESETS = {
   -- https://ethanschoonover.com/solarized/
   ["Solarized Dark"] = DarkPreset({
      bg = "002b36", bar = "073642", body = "839496", emphasis = "93a1a1", secondary = "586e75",
      title = "b58900", section = "268bd2", zone = "2aa198", quest = "b58900", tag = "6c71c4", arrow = "2aa198",
      green = "859900", yellow = "b58900", orange = "cb4b16", red = "dc322f",
   }),
   -- https://www.nordtheme.com/
   ["Nord"] = DarkPreset({
      bg = "2e3440", bar = "3b4252", body = "d8dee9", emphasis = "eceff4", secondary = "7b88a1",
      title = "88c0d0", section = "81a1c1", zone = "8fbcbb", quest = "ebcb8b", tag = "b48ead", arrow = "88c0d0",
      green = "a3be8c", yellow = "ebcb8b", orange = "d08770", red = "bf616a",
   }),
   -- https://draculatheme.com/
   ["Dracula"] = DarkPreset({
      bg = "282a36", bar = "44475a", body = "f8f8f2", emphasis = "ffffff", secondary = "6272a4",
      title = "ff79c6", section = "bd93f9", zone = "8be9fd", quest = "f1fa8c", tag = "ffb86c", arrow = "8be9fd",
      green = "50fa7b", yellow = "f1fa8c", orange = "ffb86c", red = "ff5555",
   }),
   -- https://github.com/morhetz/gruvbox
   ["Gruvbox Dark"] = DarkPreset({
      bg = "282828", bar = "3c3836", body = "ebdbb2", emphasis = "fbf1c7", secondary = "928374",
      title = "fabd2f", section = "83a598", zone = "8ec07c", quest = "fabd2f", tag = "d3869b", arrow = "8ec07c",
      green = "b8bb26", yellow = "fabd2f", orange = "fe8019", red = "fb4934",
   }),
   -- https://catppuccin.com/ (Mocha)
   ["Catppuccin Mocha"] = DarkPreset({
      bg = "1e1e2e", bar = "313244", body = "cdd6f4", emphasis = "b4befe", secondary = "7f849c",
      title = "cba6f7", section = "89b4fa", zone = "94e2d5", quest = "f9e2af", tag = "f5c2e7", arrow = "89dceb",
      green = "a6e3a1", yellow = "f9e2af", orange = "fab387", red = "f38ba8",
   }),
   -- https://github.com/folke/tokyonight.nvim (Night)
   ["Tokyo Night"] = DarkPreset({
      bg = "1a1b26", bar = "24283b", body = "a9b1d6", emphasis = "c0caf5", secondary = "565f89",
      title = "bb9af7", section = "7aa2f7", zone = "7dcfff", quest = "e0af68", tag = "bb9af7", arrow = "7dcfff",
      green = "9ece6a", yellow = "e0af68", orange = "ff9e64", red = "f7768e",
   }),
   -- Atom One Dark
   ["One Dark"] = DarkPreset({
      bg = "282c34", bar = "2c313a", body = "abb2bf", emphasis = "dcdfe4", secondary = "5c6370",
      title = "c678dd", section = "61afef", zone = "56b6c2", quest = "e5c07b", tag = "d19a66", arrow = "56b6c2",
      green = "98c379", yellow = "e5c07b", orange = "d19a66", red = "e06c75",
   }),
   -- Monokai: neutral olive-grey
   ["Monokai"] = DarkPreset({
      bg = "272822", bar = "3e3d32", body = "f8f8f2", emphasis = "ffffff", secondary = "75715e",
      title = "e6db74", section = "fd971f", zone = "a6e22e", quest = "e6db74", tag = "ae81ff", arrow = "66d9ef",
      green = "a6e22e", yellow = "e6db74", orange = "fd971f", red = "f92672",
   }),
   -- https://github.com/sainnhe/everforest (Dark, medium): green-grey
   ["Everforest Dark"] = DarkPreset({
      bg = "2d353b", bar = "343f44", body = "d3c6aa", emphasis = "e5dfc5", secondary = "859289",
      title = "dbbc7f", section = "a7c080", zone = "83c092", quest = "dbbc7f", tag = "d699b6", arrow = "83c092",
      green = "a7c080", yellow = "dbbc7f", orange = "e69875", red = "e67e80",
   }),
   -- https://rosepinetheme.com/: muted purple
   ["Rose Pine"] = DarkPreset({
      bg = "191724", bar = "26233a", body = "e0def4", emphasis = "ffffff", secondary = "6e6a86",
      title = "ebbcba", section = "c4a7e7", zone = "9ccfd8", quest = "f6c177", tag = "eb6f92", arrow = "9ccfd8",
      green = "9ccfd8", yellow = "f6c177", orange = "ebbcba", red = "eb6f92",
   }),
   -- https://github.com/rebelot/kanagawa.nvim (Dragon): warm black
   ["Kanagawa Dragon"] = DarkPreset({
      bg = "181616", bar = "282727", body = "c5c9c5", emphasis = "c8c093", secondary = "737c73",
      title = "c4b28a", section = "b6927b", zone = "8ea4a2", quest = "c4b28a", tag = "a292a3", arrow = "8ea4a2",
      green = "87a987", yellow = "c4b28a", orange = "b98d7b", red = "c4746e",
   }),
   -- https://github.com/chriskempson/tomorrow-theme (Night): neutral charcoal
   ["Tomorrow Night"] = DarkPreset({
      bg = "1d1f21", bar = "282a2e", body = "c5c8c6", emphasis = "ffffff", secondary = "969896",
      title = "f0c674", section = "b294bb", zone = "8abeb7", quest = "f0c674", tag = "de935f", arrow = "8abeb7",
      green = "b5bd68", yellow = "f0c674", orange = "de935f", red = "cc6666",
   }),
   -- Zenburn: low-contrast grey
   ["Zenburn"] = DarkPreset({
      bg = "3f3f3f", bar = "4f4f4f", body = "dcdccc", emphasis = "ffffef", secondary = "8f8f8f",
      title = "f0dfaf", section = "dfaf8f", zone = "93e0e3", quest = "f0dfaf", tag = "dc8cc3", arrow = "93e0e3",
      green = "9fc59f", yellow = "f0dfaf", orange = "dfaf8f", red = "cc9393",
   }),
}

--- Settings to show in the options: the selected theme's, or the Blizzard look.
function mod:GetDisplayTheme()
   return self:GetThemeSettings() or self.themeDefaults
end

--- Settings of the selected theme (custom or preset), or nil for the Blizzard theme.
function mod:GetThemeSettings()
   local name = self.db.profile.theme
   return self.db.global.themes[name] or PRESETS[name]
end

--- Tracker background settings of the selected theme.
function mod:GetBackground()
   local theme = self:GetThemeSettings()
   return theme and theme.background or self.themeDefaults.background
end

--- Font settings ([role] = { face, size, outline }) of the selected theme.
function mod:GetFonts()
   local theme = self:GetThemeSettings()
   return theme and theme.fonts or self.themeDefaults.fonts
end

-- Text colors of the selected theme as { r, g, b } arrays (for unpack),
-- rebuilt by RefreshTheme.
local textColors = {}

--- Text colors ([key] = { r, g, b }) of the selected theme; see themeDefaults.colors.
function mod:GetTextColors()
   return textColors
end

--- Content spacing (padding, line spacing) of the selected theme.
function mod:GetContentLayout()
   local theme = self:GetThemeSettings()
   return theme and theme.layout or self.themeDefaults.layout
end

function mod:GetTheme()
   return self:GetThemeSettings() and custom or blizzard
end

--- Theme names for dropdowns: [key] = display name.
function mod:GetThemeList()
   local list = { [BLIZZARD] = L["Blizzard"] }
   for name in pairs(PRESETS) do
      list[name] = name
   end
   for name in pairs(self.db.global.themes) do
      list[name] = name
   end
   return list
end

--- Returns an error message if name can't be used for a new theme.
function mod:ValidateThemeName(name)
   name = strtrim(name or "")
   if name == "" then
      return L["Enter a theme name."]
   elseif name:lower() == BLIZZARD or PRESETS[name] or self.db.global.themes[name] then
      return L["A theme with that name already exists."]
   end
end

--- Creates a theme from the selected one (built-in or custom) and selects it.
function mod:CreateTheme(name)
   name = strtrim(name)
   self.db.global.themes[name] = CopyTable(self:GetThemeSettings() or self.themeDefaults)
   self:SelectTheme(name)
end

--- Renames the selected theme; profiles using it follow the new name.
function mod:RenameTheme(name)
   local old = self.db.profile.theme
   local themes = self.db.global.themes
   if not themes[old] then return end
   name = strtrim(name)
   themes[name], themes[old] = themes[old], nil
   for _, profile in pairs(self.db.profiles) do
      if profile.theme == old then
         profile.theme = name
      end
   end
   self:SelectTheme(name)
end

function mod:DeleteTheme()
   local name = self.db.profile.theme
   if not self:GetCustomTheme() then return end
   self.db.global.themes[name] = nil
   self:SelectTheme(BLIZZARD)
end

--- Makes the selected custom theme look like the Blizzard theme.
function mod:ResetThemeToBlizzard()
   local settings = self:GetCustomTheme()
   if not settings then return end
   for kind, defaults in pairs(self.themeDefaults) do
      settings[kind] = CopyTable(defaults)
   end
   self:ApplyLayout()
end

function mod:SelectTheme(name)
   self.db.profile.theme = name
   self:ApplyLayout()
   self:NotifyOptionsChanged()
end

-- Fills in settings missing from a saved theme (AceDB drops values equal to
-- the defaults they had when saved).
local function FillDefaults(settings, defaults)
   for key, value in pairs(defaults) do
      if settings[key] == nil then
         settings[key] = type(value) == "table" and CopyTable(value) or value
      elseif type(value) == "table" and type(settings[key]) == "table" then
         FillDefaults(settings[key], value)
      end
   end
   return settings
end

-- Settings that used to be per profile, by theme table:
-- { old profile key, theme key, old default }.
local OLD_SETTINGS = {
   background = {
      { "backgroundTexture", "texture", "Solid" },
      { "backgroundColor", "color", { r = 0, g = 0, b = 0 } },
      { "backgroundAlpha", "alpha", 0 },
      { "backgroundHoverAlpha", "hoverAlpha", 0.4 },
      { "backgroundBorder", "border", "None" },
      { "backgroundBorderSize", "borderSize", 12 },
      { "backgroundBorderColor", "borderColor", { r = 0.6, g = 0.6, b = 0.6 } },
   },
   layout = {
      { "padding", "padding", 0 },
      { "sectionSpacing", "sectionSpacing", 10 },
      { "zoneSpacing", "zoneSpacing", 8 },
      { "zoneHeaderSpacing", "zoneHeaderSpacing", 2 },
      { "questSpacing", "questSpacing", 6 },
      { "objectiveSpacing", "objectiveSpacing", 1 },
   },
}

----------------------------------------------------------------
-- Import / export: "MQT1:" followed by { name = ..., theme = ... } as
-- CBOR, deflate compressed and Base64 encoded (C_EncodingUtil, the same
-- format Blizzard uses for cooldown manager layouts). Imported settings
-- are checked against the theme defaults, so unknown keys and wrong types
-- are dropped.
----------------------------------------------------------------

local EXPORT_PREFIX = "MQT1:"
local Encoding = C_EncodingUtil

function mod:CanImportExportThemes()
   return Encoding ~= nil and Encoding.SerializeCBOR ~= nil
end

--- Export string for the selected theme, or "" for the Blizzard theme.
function mod:ExportTheme()
   local theme = self:GetCustomTheme()
   if not (theme and self:CanImportExportThemes()) then return "" end
   local data = Encoding.SerializeCBOR({ name = self.db.profile.theme, theme = theme })
   return EXPORT_PREFIX .. Encoding.EncodeBase64(Encoding.CompressString(data))
end

local function Decode(text)
   local compressed = Encoding.DecodeBase64(text)
   return Encoding.DeserializeCBOR(Encoding.DecompressString(compressed))
end

-- Copies the values whose keys and types match the defaults.
local function Sanitize(data, defaults)
   local result = {}
   for key, default in pairs(defaults) do
      local value = data[key]
      if type(value) == type(default) then
         result[key] = type(value) == "table" and Sanitize(value, default) or value
      end
   end
   return FillDefaults(result, defaults)
end

--- Returns the theme name and settings from an export string, or nil and an error.
function mod:ParseThemeImport(text)
   text = (text or ""):gsub("%s", "")
   if not self:CanImportExportThemes() or text:sub(1, #EXPORT_PREFIX) ~= EXPORT_PREFIX then
      return nil, L["This is not a theme export string."]
   end
   local ok, data = pcall(Decode, text:sub(#EXPORT_PREFIX + 1))
   if not ok or type(data) ~= "table" or type(data.theme) ~= "table" then
      return nil, L["This theme export string is damaged."]
   end
   local name = type(data.name) == "string" and strtrim(data.name) or ""
   return name ~= "" and name or L["Imported"], data.theme
end

--- Returns name, or name with a number added if a theme with it exists.
function mod:GetFreeThemeName(name)
   local base, count = name, 1
   while self:ValidateThemeName(name) do
      count = count + 1
      name = format("%s (%d)", base, count)
   end
   return name
end

--- Imports a theme under a free name and selects it.
function mod:ImportTheme(text)
   local name, theme = self:ParseThemeImport(text)
   if not name then return end
   name = self:GetFreeThemeName(name)
   self.db.global.themes[name] = Sanitize(theme, self.themeDefaults)
   self:SelectTheme(name)
end

--- Moves the old per-profile "custom" (earlier "simple") theme and the
--- profile's background, spacing and font settings to a named theme.
function mod:MigrateCustomTheme()
   local profile = self.db.profile
   local old = profile.custom
   profile.custom, profile.simple = nil, nil
   local themes = self.db.global.themes
   if profile.theme == "custom" or profile.theme == "simple" then
      local name = L["Custom"]
      themes[name] = themes[name] or old or {}
      profile.theme = name
   end
   local selected = themes[profile.theme]
   for key, entries in pairs(OLD_SETTINGS) do
      if selected and not selected[key] then
         local settings = {}
         for _, entry in ipairs(entries) do
            local value = profile[entry[1]]
            if value == nil then value = entry[3] end
            settings[entry[2]] = type(value) == "table" and CopyTable(value) or value
         end
         selected[key] = settings
      end
      for _, entry in ipairs(entries) do
         profile[entry[1]] = nil
      end
   end
   if selected and not selected.fonts and profile.fonts then
      selected.fonts = profile.fonts  -- missing values are filled in below
   end
   profile.fonts = nil
   for _, settings in pairs(self.db.global.themes) do
      FillDefaults(settings, self.themeDefaults)
   end
end

--- Call when theme settings change; header lines restyle on next render.
function mod:RefreshTheme()
   self.themeVersion = self.themeVersion + 1
   local theme = self:GetThemeSettings()
   local colors = theme and theme.colors or self.themeDefaults.colors
   -- New tables, so cached highlight colors don't go stale.
   textColors = {}
   for key, c in pairs(colors) do
      textColors[key] = { c.r, c.g, c.b }
   end
   local tag = colors.questTag
   textColors.questTagCode = format("|cff%02x%02x%02x", tag.r * 255 + 0.5, tag.g * 255 + 0.5, tag.b * 255 + 0.5)
   wipe(backdrops)
   for _, kind in ipairs(HEADER_KINDS) do
      local settings = theme and theme[kind]
      local edge = settings and settings.border ~= "None" and media:Fetch("border", settings.border)
      backdrops[kind] = edge and edge ~= "" and { edgeFile = edge, edgeSize = settings.borderSize } or false
   end
end
