-- TotemMacroManager.lua
-- Minimal addon that builds/updates a castsequence macro from selected totems

local addonName = "TotemMacroManager"
local macroName = "TMM-MACRO"

-- Default suggestions (users can type custom spell names)
local suggestions = {
  "Windfury Totem",
  "Grace of Air Totem",
  "Grounding Totem",
  "Stoneclaw Totem",
  "Strength of Earth Totem",
  "Earthbind Totem",
  "Searing Totem",
  "Magma Totem",
  "Flametongue Totem",
  "Healing Stream Totem",
  "Mana Spring Totem",
  "Mana Tide Totem",
}

-- Saved variables
TMM_DB = TMM_DB or {slots = {air = "", earth = "", fire = "", water = ""}, pos = {}, show = false}
local frame = CreateFrame("Frame", "TMM_Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")

local queuedUpdate = false

-- lists of available totems discovered in the player's spellbook
local totemLists = {air = {}, earth = {}, fire = {}, water = {}}

local function addUnique(tbl, val)
  for _, v in ipairs(tbl) do if v == val then return end end
  table.insert(tbl, val)
end

local function BuildTotemLists()
  totemLists.air = {}
  totemLists.earth = {}
  totemLists.fire = {}
  totemLists.water = {}

  local bookType = BOOKTYPE_SPELL or "spell"
  local numTabs = GetNumSpellTabs() or 0
  for tab = 1, numTabs do
    local _, _, offset, numSlots = GetSpellTabInfo(tab)
    for i = offset + 1, offset + numSlots do
      local spellName = GetSpellBookItemName(i, bookType)
      if spellName and spellName:lower():find("totem") then
        local lower = spellName:lower()
        if lower:find("nature resistance") then
          addUnique(totemLists.air, spellName)
        elseif lower:find("frost resistance") then
          addUnique(totemLists.fire, spellName)
        elseif lower:find("fire resistance") then
          addUnique(totemLists.water, spellName)
        elseif lower:find("air") or lower:find("wind") or lower:find("grace") then
          addUnique(totemLists.air, spellName)
        elseif lower:find("earth") or lower:find("stone") or lower:find("strength") then
          addUnique(totemLists.earth, spellName)
        elseif lower:find("fire") or lower:find("flame") or lower:find("magma") or lower:find("searing") then
          addUnique(totemLists.fire, spellName)
        elseif lower:find("water") or lower:find("stream") or lower:find("mana") or lower:find("tide") then
          addUnique(totemLists.water, spellName)
        end
      end
    end
  end

  -- fallback: if any list is empty, insert common suggestions
  if #totemLists.air == 0 then
    addUnique(totemLists.air, "Windfury Totem")
    addUnique(totemLists.air, "Grace of Air Totem")
  end
  if #totemLists.earth == 0 then
    addUnique(totemLists.earth, "Stoneclaw Totem")
    addUnique(totemLists.earth, "Strength of Earth Totem")
  end
  if #totemLists.fire == 0 then
    addUnique(totemLists.fire, "Searing Totem")
    addUnique(totemLists.fire, "Flametongue Totem")
  end
  if #totemLists.water == 0 then
    addUnique(totemLists.water, "Healing Stream Totem")
    addUnique(totemLists.water, "Mana Spring Totem")
  end
end

local function CreateDropdown(parent, x, y, width, element)
  local dd = CreateFrame("Frame", "TMM_Dropdown_"..element, parent, "UIDropDownMenuTemplate")
  dd:SetPoint("TOPLEFT", x, y)
  UIDropDownMenu_SetWidth(dd, width)
  UIDropDownMenu_Initialize(dd, function(self, level)
    local function selectValue(btn)
      TMM_DB.slots[element] = btn.value
      UIDropDownMenu_SetSelectedValue(dd, btn.value)
      UIDropDownMenu_SetText(dd, btn.text)
      UIDropDownMenu_Refresh(dd)
      ApplyMacro()
    end

    local info = UIDropDownMenu_CreateInfo()
    info.text = "None"
    info.value = ""
    info.func = selectValue
    UIDropDownMenu_AddButton(info, level)

    for _, name in ipairs(totemLists[element]) do
      local it = UIDropDownMenu_CreateInfo()
      it.text = name
      it.value = name
      it.func = selectValue
      UIDropDownMenu_AddButton(it, level)
    end
  end)

  -- set initial selected value/text
  if TMM_DB.slots[element] and TMM_DB.slots[element] ~= "" then
    UIDropDownMenu_SetSelectedValue(dd, TMM_DB.slots[element])
    UIDropDownMenu_SetText(dd, TMM_DB.slots[element])
  else
    UIDropDownMenu_SetSelectedValue(dd, "")
    UIDropDownMenu_SetText(dd, "None")
  end

  return dd
end

local function BuildMacroBody()
  local slots = TMM_DB.slots
  local seq = {}
  if slots.air and slots.air ~= "" then table.insert(seq, slots.air) end
  if slots.earth and slots.earth ~= "" then table.insert(seq, slots.earth) end
  if slots.fire and slots.fire ~= "" then table.insert(seq, slots.fire) end
  if slots.water and slots.water ~= "" then table.insert(seq, slots.water) end

  if #seq == 0 then return "" end
  return "/castsequence reset=15 " .. table.concat(seq, ", ")
end

local function ApplyMacro()
  if InCombatLockdown() or UnitAffectingCombat("player") then
    queuedUpdate = true
    DEFAULT_CHAT_FRAME:AddMessage("[TMM] In combat: macro update queued until you leave combat.")
    return
  end

  local body = BuildMacroBody()
  if body == "" then
    DEFAULT_CHAT_FRAME:AddMessage("[TMM] No totems selected; macro not created.")
    return
  end

  local idx = GetMacroIndexByName(macroName)
  if idx == 0 then
    local success = CreateMacro(macroName, "INV_Misc_QuestionMark", body, nil)
    if success == 0 then
      DEFAULT_CHAT_FRAME:AddMessage("[TMM] Failed to create macro. Macro limit reached?")
      return
    end
    DEFAULT_CHAT_FRAME:AddMessage("[TMM] Macro created: " .. macroName)
  else
    EditMacro(idx, macroName, "INV_Misc_QuestionMark", body)
    DEFAULT_CHAT_FRAME:AddMessage("[TMM] Macro updated: " .. macroName)
  end
end

local function CreateEdit(parent, x, y, width, initial, onEnter)
  local eb = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  eb:SetSize(width, 24)
  eb:SetPoint("TOPLEFT", x, y)
  eb:SetAutoFocus(false)
  eb:SetText(initial or "")
  eb:SetScript("OnEnterPressed", function(self)
    self:ClearFocus()
    if onEnter then onEnter(self:GetText()) end
  end)
  return eb
end

local function BuildUI()
  local ui = CreateFrame("Frame", "TMM_UIFrame", UIParent)
  ui:SetSize(320, 220)
  if TMM_DB.pos and TMM_DB.pos.point then
    ui:SetPoint(TMM_DB.pos.point, UIParent, TMM_DB.pos.relativePoint, TMM_DB.pos.x, TMM_DB.pos.y)
  else
    ui:SetPoint("CENTER")
  end
  ui:SetMovable(true)
  ui:EnableMouse(true)
  ui:RegisterForDrag("LeftButton")
  ui:SetScript("OnDragStart", function(self) self:StartMoving() end)
  ui:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relativePoint, xOfs, yOfs = self:GetPoint(1)
    TMM_DB.pos = {point = point, relativePoint = relativePoint, x = xOfs, y = yOfs}
  end)
  ui:SetClampedToScreen(true)
  ui:SetFrameStrata("MEDIUM")

  -- Build available totem lists from the player's spellbook
  BuildTotemLists()

  local airDD = CreateDropdown(ui, 60, -36, 220, "air")
  local earthDD = CreateDropdown(ui, 60, -66, 220, "earth")
  local fireDD = CreateDropdown(ui, 60, -96, 220, "fire")
  local waterDD = CreateDropdown(ui, 60, -126, 220, "water")

  local btn = CreateFrame("Button", nil, ui, "GameMenuButtonTemplate")
  btn:SetPoint("BOTTOM", 30, 12)
  btn:SetSize(140, 24)
  btn:SetText("Apply Macro Now")
  btn:SetScript("OnClick", ApplyMacro)

  if TMM_DB.show then
    ui:Show()
  else
    ui:Hide()
  end

  SLASH_TMM1 = "/tmm"
  SlashCmdList["TMM"] = function()
    if ui:IsShown() then
      ui:Hide()
      TMM_DB.show = false
    else
      ui:Show()
      TMM_DB.show = true
    end
  end
end

frame:SetScript("OnEvent", function(self, event, arg1, ...)
  if event == "ADDON_LOADED" and arg1 == addonName then
    TMM_DB = TMM_DB or {slots = {air = "", earth = "", fire = "", water = ""}, pos = {}, show = false}
    TMM_DB.show = TMM_DB.show or false
    BuildUI()
    DEFAULT_CHAT_FRAME:AddMessage("[TMM] Loaded. Use /tmm to show or hide the movable widget.")
  elseif event == "PLAYER_REGEN_ENABLED" then
    if queuedUpdate then
      queuedUpdate = false
      ApplyMacro()
    end
  end
end)
