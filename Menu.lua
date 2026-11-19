--[[
MagicQuestTracker - Context menus.

Menus are described with the same builder calls as Blizzard's MenuUtil
(CreateTitle, CreateButton, CreateCheckbox, CreateRadio, CreateDivider,
nested CreateButton for submenus, SetEnabled) and drawn with LibDropdown-1.0,
which uses its own frames. Opening Blizzard's shared menu system from addon
code runs it under our taint, the same class of problem the old
UIDropDownMenu had.
]]

local mod = LibStub("AceAddon-3.0"):GetAddon("MagicQuestTracker")

----------------------------------------------------------------
-- Description builder (a MenuUtil-like subset)
----------------------------------------------------------------

local Description = {}
Description.__index = Description

local function NewDescription(kind, text)
   return setmetatable({ kind = kind, text = text, children = {}, enabled = true }, Description)
end

function Description:Add(kind, text)
   local child = NewDescription(kind, text)
   self.children[#self.children + 1] = child
   return child
end

function Description:CreateTitle(text)
   return self:Add("title", text)
end

function Description:CreateDivider()
   return self:Add("divider")
end

--- A button; adding entries to it makes it a submenu.
function Description:CreateButton(text, callback)
   local button = self:Add("button", text)
   button.callback = callback
   return button
end

function Description:CreateCheckbox(text, isSelected, setSelected)
   local checkbox = self:Add("checkbox", text)
   checkbox.isSelected, checkbox.setSelected = isSelected, setSelected
   return checkbox
end

function Description:CreateRadio(text, isSelected, setSelected)
   local radio = self:Add("radio", text)
   radio.isSelected, radio.setSelected = isSelected, setSelected
   return radio
end

function Description:SetEnabled(enabled)
   self.enabled = enabled and true or false
end

----------------------------------------------------------------
-- LibDropdown rendering (Ace3 option tables)
----------------------------------------------------------------

local LibDropdown = LibStub("LibDropdown-1.0")

-- LibDropdown pools its frames and releases a menu itself (outside click,
-- escape, the next menu), so each open keeps its own handle, cleared once
-- that menu is gone: closing never releases a frame reused by a later menu.
local function CloseMenu(handle)
   local menu = handle.menu
   handle.menu = nil
   if menu and menu:IsShown() then menu:Release() end
end

local function Disabled(desc)
   if desc.enabled then return nil end
   return true
end

local function ToOptions(desc, handle)
   local args = {}
   for i, child in ipairs(desc.children) do
      local option
      if child.kind == "title" then
         option = { type = "header", name = child.text or "" }
      elseif child.kind == "divider" then
         option = { type = "header", name = "" }
      elseif child.kind == "button" and #child.children > 0 then
         option = { type = "group", name = child.text or "", args = ToOptions(child, handle) }
      elseif child.kind == "button" then
         local callback = child.callback
         option = {
            type = "execute",
            name = child.text or "",
            func = function()
               CloseMenu(handle)
               if callback then callback() end
            end,
         }
      elseif child.kind == "checkbox" or child.kind == "radio" then
         local isSelected, setSelected = child.isSelected, child.setSelected
         option = {
            type = "toggle",
            name = child.text or "",
            get = function() return isSelected and isSelected() and true or false end,
            set = function() if setSelected then setSelected() end end,
         }
      end
      if option then
         option.order = i
         option.disabled = Disabled(child)
         args["e" .. i] = option
      end
   end
   return args
end

local function ShowWithLibDropdown(root)
   local handle = {}
   local menu = LibDropdown:OpenAce3Menu({ type = "group", name = "MagicQuestTracker", args = ToOptions(root, handle) })
   if not menu then return end
   handle.menu = menu
   local scale = menu:GetEffectiveScale()
   local x, y = GetCursorPosition()
   menu:ClearAllPoints()
   menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale, y / scale)
   menu:SetClampedToScreen(true)
end

----------------------------------------------------------------
-- Public
----------------------------------------------------------------

--- Shows a context menu at the cursor. build(root) adds the entries, with
--- the same calls as a MenuUtil generator.
function mod:ShowContextMenu(_, build)
   local root = NewDescription("root")
   build(nil, root)
   ShowWithLibDropdown(root)
end
