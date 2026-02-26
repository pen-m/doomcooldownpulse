local addonName, addon = ...
DoomCooldownPulse = addon

-- Taint-safe comparison for WoW 12.0+ secret numbers
local function SafeCompare(val, threshold)
    if not val then return false end
    local success, result = pcall(function() return val > threshold end)
    return success and result
end

addon.trackedSpells = {}
addon.activeTrackers = {}
addon.trackerPool = {}
addon.trinketSlots = {13, 14}
addon.itemSpells = {}

-- Settings defaults (from Doom)
addon.defaults = {
    fadeInTime = 0.3,
    fadeOutTime = 0.7,
    maxAlpha = 0.7,
    animScale = 1.5,
    iconSize = 75,
    holdTime = 0,
    petOverlay = {1,1,1},
    showSpellName = nil,
    x = UIParent:GetWidth()*UIParent:GetEffectiveScale()/2,
    y = UIParent:GetHeight()*UIParent:GetEffectiveScale()/2,
    remainingCooldownWhenNotified = 0
}

addon.defaultsPerCharacter = {
    ignoredSpells = "",
    invertIgnored = false
}

function addon:GetSetting(key)
    if DoomCooldownPulseDB and DoomCooldownPulseDB.settings and DoomCooldownPulseDB.settings[key] ~= nil then
        return DoomCooldownPulseDB.settings[key]
    end
    return addon.defaults[key]
end

function addon:SetSetting(key, value)
    if not DoomCooldownPulseDB then DoomCooldownPulseDB = {} end
    if not DoomCooldownPulseDB.settings then DoomCooldownPulseDB.settings = {} end
    DoomCooldownPulseDB.settings[key] = value
end

-- Frame for animation (from Doom)
addon.animationFrame = CreateFrame("Frame", "DoomCooldownPulseFrame", UIParent)
addon.animationFrame:SetSize(1, 1)
addon.animationFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
addon.animationFrame:SetMovable(true)
addon.animationFrame:RegisterForDrag("LeftButton")
addon.animationFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
addon.animationFrame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local x = self:GetLeft() + self:GetWidth()/2
    local y = self:GetBottom() + self:GetHeight()/2
    addon:SetSetting("x", x)
    addon:SetSetting("y", y)
    self:ClearAllPoints()
    self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
end)

addon.animationFrame.TextFrame = addon.animationFrame:CreateFontString(nil, "ARTWORK")
addon.animationFrame.TextFrame:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")
addon.animationFrame.TextFrame:SetShadowOffset(2,-2)
addon.animationFrame.TextFrame:SetPoint("CENTER", addon.animationFrame, "CENTER")
addon.animationFrame.TextFrame:SetWidth(185)
addon.animationFrame.TextFrame:SetJustifyH("CENTER")
addon.animationFrame.TextFrame:SetTextColor(1,1,1)

addon.animationTexture = addon.animationFrame:CreateTexture(nil, "BACKGROUND")
addon.animationTexture:SetAllPoints(addon.animationFrame)

addon.pulseFrames = {}

local function GetPulseFrame()
    for _, frame in ipairs(addon.pulseFrames) do
        if not frame:IsShown() and not frame.animating then
            return frame
        end
    end

    local f = CreateFrame("Frame", nil, addon.animationFrame)
    f:SetPoint("CENTER", addon.animationFrame, "CENTER", 0, 0)

    f.text = f:CreateFontString(nil, "ARTWORK")
    f.text:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")
    f.text:SetShadowOffset(2, -2)
    f.text:SetPoint("CENTER", f, "CENTER")
    f.text:SetWidth(185)
    f.text:SetJustifyH("CENTER")
    f.text:SetTextColor(1, 1, 1)

    f.texture = f:CreateTexture(nil, "BACKGROUND")
    f.texture:SetAllPoints(f)

    table.insert(addon.pulseFrames, f)
    return f
end

-- Pulse Animation (from Doom)
function addon:PlayPulse(icon, isPet, spellName)
    local f = GetPulseFrame()
    f:SetSize(addon:GetSetting("iconSize"), addon:GetSetting("iconSize"))

    -- Lightweight debug instrumentation
    if addon.DCP_DEBUG == nil then addon.DCP_DEBUG = false end
    addon._pulseCounter = addon._pulseCounter or 0
    local texPath = icon
    if type(icon) ~= "string" and icon then
        local ok, t = pcall(function() return icon:GetTexture() end)
        if ok and t then texPath = t end
    end
    if addon.DCP_DEBUG then
        addon._pulseCounter = addon._pulseCounter + 1
        print(string.format("[DCP] Pulse START: %s tex=%s time=%.3f concurrent=%d", tostring(spellName or "<nil>"), tostring(texPath or "<nil>"), GetTime(), addon._pulseCounter))
    end

    f.texture:SetTexture(icon)
    if isPet then
        f.texture:SetVertexColor(unpack(addon:GetSetting("petOverlay")))
    else
        f.texture:SetVertexColor(1, 1, 1)
    end
    if addon:GetSetting("showSpellName") and spellName then
        f.text:SetText(spellName)
    else
        f.text:SetText(nil)
    end
    f:SetAlpha(0)
    f:Show()

    local fadeInTime = addon:GetSetting("fadeInTime")
    local fadeOutTime = addon:GetSetting("fadeOutTime")
    local maxAlpha = addon:GetSetting("maxAlpha")
    local animScale = addon:GetSetting("animScale")
    local holdTime = addon:GetSetting("holdTime")
    local iconSize = addon:GetSetting("iconSize")

    local elapsed = 0
    f.animating = true
    f:SetScript("OnUpdate", function(self, delta)
        elapsed = elapsed + delta
        local totalTime = fadeInTime + holdTime + fadeOutTime
        if elapsed >= totalTime then
            f:Hide()
            f:SetScript("OnUpdate", nil)
            f.text:SetText(nil)
            f.texture:SetTexture(nil)
            f.texture:SetVertexColor(1, 1, 1)
            f.animating = false
            if addon.DCP_DEBUG then
                addon._pulseCounter = math.max(0, (addon._pulseCounter or 1) - 1)
                print(string.format("[DCP] Pulse END: %s time=%.3f concurrent=%d", tostring(spellName or "<nil>"), GetTime(), addon._pulseCounter))
            end
            return
        end

        local alpha = maxAlpha
        if elapsed < fadeInTime then
            alpha = maxAlpha * (elapsed / fadeInTime)
        elseif elapsed >= fadeInTime + holdTime then
            alpha = maxAlpha - (maxAlpha * ((elapsed - holdTime - fadeInTime) / fadeOutTime))
        end
        f:SetAlpha(alpha)

        local scale = iconSize + (iconSize * ((animScale - 1) * (elapsed / totalTime)))
        f:SetWidth(scale)
        f:SetHeight(scale)
    end)
end

-- Cooldown Tracker Pool (from Bloom)
function addon:GetTrackerFrame()
    local f = table.remove(addon.trackerPool)
    if not f then
        f = CreateFrame("Cooldown", nil, UIParent, "CooldownFrameTemplate")
        f:SetSize(1, 1)
        f:SetAlpha(0)
        f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -100, 100) -- Off-screen
    end
    return f
end

function addon:ReleaseTrackerFrame(spellID)
    local f = addon.activeTrackers[spellID]
    if f then
        f:SetScript("OnCooldownDone", nil)
        f:Hide()
        table.insert(addon.trackerPool, f)
        addon.activeTrackers[spellID] = nil
    end
end

-- Spellbook Scanning (from Bloom, adapted)
function addon:ScanSpellbook(silent)
    -- Clear current trackers
    for id in pairs(addon.activeTrackers) do
        addon:ReleaseTrackerFrame(id)
    end

    wipe(addon.trackedSpells)

    local numSkillLines = 0
    if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines then
        numSkillLines = C_SpellBook.GetNumSpellBookSkillLines()
    end

    if numSkillLines == 0 then return 0 end

    for i = 1, numSkillLines do
        local skillLineInfo = C_SpellBook.GetSpellBookSkillLineInfo(i)
        if skillLineInfo then
            local offset = skillLineInfo.itemIndexOffset
            local numSpells = skillLineInfo.numSpellBookItems

            for j = 1, numSpells do
                local slotIndex = offset + j
                local slotInfo = C_SpellBook.GetSpellBookItemInfo(slotIndex, Enum.SpellBookSpellBank.Player)

                if slotInfo and slotInfo.itemType == Enum.SpellBookItemType.Spell then
                    local spellID = slotInfo.spellID
                    local overrideID = C_Spell.GetOverrideSpell(spellID)
                    local realSpellID = overrideID or spellID

                    if realSpellID and not slotInfo.isPassive then
                        -- Prefer base cooldown so we can filter short CDs in combat
                        local duration = 0
                        local baseDuration = GetSpellBaseCooldown(realSpellID)
                        if baseDuration and baseDuration > 0 then
                            duration = baseDuration
                        else
                            -- Fallback to current cooldown if base isn't available
                            local cdInfo = C_Spell.GetSpellCooldown(realSpellID)
                            if cdInfo and SafeCompare(cdInfo.duration, 0) then
                                duration = cdInfo.duration * 1000
                            end
                        end

                        local chargeInfo = C_Spell.GetSpellCharges(realSpellID)
                        if chargeInfo and chargeInfo.cooldownDuration and SafeCompare(chargeInfo.maxCharges, 0) then
                            duration = (duration and SafeCompare(duration, 0)) and duration or (chargeInfo.cooldownDuration * 1000)
                        end

                        addon.trackedSpells[realSpellID] = {
                            id = realSpellID,
                            baseCD = duration or 0,
                            isCharges = (chargeInfo and SafeCompare(chargeInfo.maxCharges, 0)),
                            prevCharges = chargeInfo and chargeInfo.currentCharges
                        }
                    end
                end
            end
        end
    end

    -- Scan pet actions
    for i = 1, NUM_PET_ACTION_SLOTS or 10 do
        local name, texture, isToken, isActive, autoCastAllowed, autoCastEnabled = GetPetActionInfo(i)
        if name and texture then
            -- Pet actions are tracked by index, not spell ID
            addon.trackedSpells["pet:" .. i] = {
                id = i,
                type = "pet",
                name = name,
                texture = texture
            }
        end
    end

    local count = 0
    for _ in pairs(addon.trackedSpells) do count = count + 1 end

    -- silent initialization (no debug output)

    return count
end

-- Track Item Spell (from Doom)
-- Note: This function is not actively used. Item cooldowns are tracked via trinket slot scanning.
function addon:TrackItemSpell(itemID)
    return false
end

-- Process Spell (from Bloom, adapted)
local function ProcessSpell(spellID, data)
    if DoomCooldownPulseDB and DoomCooldownPulseDB[spellID] then return end
    if addon.activeTrackers[spellID] then return end

    local icon = C_Spell.GetSpellTexture(spellID)
    local cooldownInfo = C_Spell.GetSpellCooldown(spellID)
    local isOnGCD = cooldownInfo and cooldownInfo.isOnGCD

    if data.isCharges then
        local chargeInfo = C_Spell.GetSpellCharges(spellID)
        if chargeInfo and SafeCompare(chargeInfo.cooldownStartTime, 0) and not isOnGCD then
            if SafeCompare(chargeInfo.cooldownDuration, 1.9) then
                local f = addon:GetTrackerFrame()
                f:SetCooldown(chargeInfo.cooldownStartTime, chargeInfo.cooldownDuration)
                -- Only track if frame is actually shown (SetCooldown may fail during combat)
                if f:IsShown() then
                    addon.activeTrackers[spellID] = f
                    f:SetScript("OnCooldownDone", function()
                        addon:PlayPulse(icon, false, C_Spell.GetSpellName(spellID))
                        addon:ReleaseTrackerFrame(spellID)
                    end)
                else
                    table.insert(addon.trackerPool, f)
                end
            end
        end
    else
        if not cooldownInfo then return end
        if isOnGCD then return end
        if not SafeCompare(cooldownInfo.startTime, 0) then return end
        if not SafeCompare(cooldownInfo.duration, 1.9) then return end
        local f = addon:GetTrackerFrame()
        f:SetCooldown(cooldownInfo.startTime, cooldownInfo.duration)
        if f:IsShown() then
            addon.activeTrackers[spellID] = f
            f:SetScript("OnCooldownDone", function()
                addon:PlayPulse(icon, false, C_Spell.GetSpellName(spellID))
                addon:ReleaseTrackerFrame(spellID)
            end)
        else
            table.insert(addon.trackerPool, f)
        end
    end
end

-- Process Trinket
local function ProcessTrinket(slotID)
    local key = "trinket:" .. slotID
    if DoomCooldownPulseDB and DoomCooldownPulseDB[key] then return end
    if addon.activeTrackers[key] then return end

    -- Use ItemLocation API instead of protected GetInventoryItemID
    local itemLocation = ItemLocation:CreateFromEquipmentSlot(slotID)
    local itemID = C_Item.GetItemID(itemLocation)
    if not itemID then return end
    
    local startTime, duration, enable = C_Item.GetItemCooldown(itemID)
    if SafeCompare(startTime, 0) and SafeCompare(duration, 1.9) then
        local f = addon:GetTrackerFrame()
        f:SetCooldown(startTime, duration)
        -- Only track if frame is actually shown (SetCooldown may fail during combat)
        if f:IsShown() then
            local icon = C_Item.GetItemIconByID(itemID)
            addon.activeTrackers[key] = f
            f:SetScript("OnCooldownDone", function()
                local itemLink = C_Item.GetItemLink(itemLocation)
                addon:PlayPulse(icon, false, itemLink)
                addon:ReleaseTrackerFrame(key)
            end)
        else
            table.insert(addon.trackerPool, f)
        end
    end
end

-- Process Pet
local function ProcessPet(index)
    local key = "pet:" .. index
    if addon.activeTrackers[key] then return end

    local name, texture = GetPetActionInfo(index)
    local start, duration, enabled = GetPetActionCooldown(index)
    if SafeCompare(start, 0) and SafeCompare(duration, 1.9) then
        local f = addon:GetTrackerFrame()
        f:SetCooldown(start, duration)
        -- Only track if frame is actually shown (SetCooldown may fail during combat)
        if f:IsShown() then
            addon.activeTrackers[key] = f
            f:SetScript("OnCooldownDone", function()
                addon:PlayPulse(texture, true, name)
                addon:ReleaseTrackerFrame(key)
            end)
        else
            table.insert(addon.trackerPool, f)
        end
    end
end
-- Event Handler
local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(self, event, arg1, arg2, arg3)
    if event == "ADDON_LOADED" and arg1 == "DoomCooldownPulse" then
        DoomCooldownPulseDB = DoomCooldownPulseDB or {}
        DoomCooldownPulseDB.settings = DoomCooldownPulseDB.settings or {}
        DoomCooldownPulseDBPerCharacter = DoomCooldownPulseDBPerCharacter or {}
        -- Merge defaults
        for k, v in pairs(addon.defaults) do
            if DoomCooldownPulseDB.settings[k] == nil then
                DoomCooldownPulseDB.settings[k] = v
            end
        end
        for k, v in pairs(addon.defaultsPerCharacter) do
            if DoomCooldownPulseDBPerCharacter[k] == nil then
                DoomCooldownPulseDBPerCharacter[k] = v
            end
        end
        addon.animationFrame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", addon:GetSetting("x"), addon:GetSetting("y"))
        addon:ScanSpellbook(true)
    elseif event == "PLAYER_LOGIN" then
        addon:ScanSpellbook(false)
    elseif event == "SPELLS_CHANGED" then
        addon:ScanSpellbook(true)
    elseif event == "SPELL_UPDATE_COOLDOWN" or event == "UNIT_SPELLCAST_SUCCEEDED" or event == "ACTIONBAR_UPDATE_COOLDOWN" then
        if arg1 and addon.trackedSpells[arg1] then
            ProcessSpell(arg1, addon.trackedSpells[arg1])
        else
            for spellID, data in pairs(addon.trackedSpells) do
                if type(spellID) == "number" then
                    local success, err = pcall(function()
                        ProcessSpell(spellID, data)
                    end)
                    if not success then
                        -- swallow errors during scan to avoid spam
                    end
                end
            end
        end

        -- Check Trinkets
        for _, slotID in ipairs(addon.trinketSlots) do
            ProcessTrinket(slotID)
        end

        -- Check Pets
        for i = 1, NUM_PET_ACTION_SLOTS or 10 do
            if addon.trackedSpells["pet:" .. i] then
                ProcessPet(i)
            end
        end
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        -- Force check
    -- DISABLED in Midnight: COMBAT_LOG_EVENT_UNFILTERED handler removed (see event registration)
    -- elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
    --     local _, subEvent, _, _, _, sourceFlags, _, _, _, _, _, spellID = CombatLogGetCurrentEventInfo()
    --     if subEvent == "SPELL_CAST_SUCCESS" and bit.band(sourceFlags, COMBATLOG_OBJECT_TYPE_PET) == COMBATLOG_OBJECT_TYPE_PET and bit.band(sourceFlags, COMBATLOG_OBJECT_AFFILIATION_MINE) == COMBATLOG_OBJECT_AFFILIATION_MINE then
    --         local name = C_Spell.GetSpellName(spellID)
    --         for i = 1, NUM_PET_ACTION_SLOTS or 10 do
    --             local petName = GetPetActionInfo(i)
    --             if petName == name then
    --                 ProcessPet(i)
    --                 break
    --             end
    --         end
    --     end
    end
end)

eventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("SPELLS_CHANGED")
eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
eventFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
eventFrame:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN")
-- DISABLED in Midnight: COMBAT_LOG_EVENT_UNFILTERED has heavy security restrictions
-- Pet cooldowns are tracked via ProcessPet in the SPELL_UPDATE_COOLDOWN handler instead
-- eventFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")

-- Removed hooksecurefunc on UseAction and UseInventoryItem
-- These hooks were causing taint issues when trying to access protected inventory APIs
-- Item cooldown tracking is already handled by trinket slot scanning in SPELL_UPDATE_COOLDOWN event

-- Slash Command
SLASH_DOOMCOOLDOWNPULSE1 = "/DoomCooldownPulse"
SlashCmdList.DOOMCOOLDOWNPULSE = function(msg)
    if not addon.optionsFrame then
        addon.optionsFrame = addon:CreateOptionsFrame()
    end
    addon.optionsFrame:Show()
end

-- Options Frame (from Doom, adapted)
function addon:CreateOptionsFrame()
    local sliders = {
        { text = "Icon Size", value = "iconSize", min = 30, max = 125, step = 5 },
        { text = "Fade In Time", value = "fadeInTime", min = 0, max = 1.5, step = 0.1 },
        { text = "Fade Out Time", value = "fadeOutTime", min = 0, max = 1.5, step = 0.1 },
        { text = "Max Opacity", value = "maxAlpha", min = 0, max = 1, step = 0.1 },
        { text = "Max Opacity Hold Time", value = "holdTime", min = 0, max = 1.5, step = 0.1 },
        { text = "Animation Scaling", value = "animScale", min = 0, max = 2, step = 0.1 },
        { text = "Show Before Available Time", value = "remainingCooldownWhenNotified", min = 0, max = 3, step = 0.1 },
    }

    local buttons = {
        { text = "Close", func = function(self) self:GetParent():Hide() end },
        { text = "Test", func = function(self)
            addon:TestPulse()
            end },
        { text = "Unlock", func = function(self)
            if (self:GetText() == "Unlock") then
                addon.animationFrame:SetSize(addon:GetSetting("iconSize"), addon:GetSetting("iconSize"))
                self:SetText("Lock")
                addon.animationFrame:SetAlpha(1)
                addon.animationTexture:SetTexture("Interface\\Icons\\Spell_Nature_Earthbind")
                addon.animationFrame:EnableMouse(true)
            else
                addon.animationFrame:SetAlpha(0)
                self:SetText("Unlock")
                addon.animationFrame:EnableMouse(false)
            end end },
        { text = "Defaults", func = function(self)
            for k, v in pairs(addon.defaults) do
                addon:SetSetting(k, v)
            end
            for k, v in pairs(addon.defaultsPerCharacter) do
                DoomCooldownPulseDBPerCharacter[k] = v
            end
            for i, v in pairs(sliders) do
                getglobal("DoomCooldownPulse_OptionsFrameSlider"..i):SetValue(addon:GetSetting(v.value))
            end
            -- Update other UI elements similarly
            addon.animationFrame:ClearAllPoints()
            addon.animationFrame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", addon:GetSetting("x"), addon:GetSetting("y"))
            end },
    }

    local optionsframe = CreateFrame("frame","DoomCooldownPulse_OptionsFrame",UIParent,BackdropTemplateMixin and "BackdropTemplate")
    optionsframe:SetBackdrop({
      bgFile="Interface\\DialogFrame\\UI-DialogBox-Background",
      edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border",
      tile=1, tileSize=32, edgeSize=32,
      insets={left=11, right=12, top=12, bottom=11}
    })
    optionsframe:SetWidth(230)
    optionsframe:SetHeight(610)
    optionsframe:SetPoint("CENTER",UIParent)
    optionsframe:EnableMouse(true)
    optionsframe:SetMovable(true)
    optionsframe:RegisterForDrag("LeftButton")
    optionsframe:SetScript("OnDragStart", function(self) self:StartMoving() end)
    optionsframe:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    optionsframe:SetFrameStrata("FULLSCREEN_DIALOG")
    optionsframe:SetScript("OnHide", function() end)  -- Removed RefreshLocals
    tinsert(UISpecialFrames, "DoomCooldownPulse_OptionsFrame")

    local header = optionsframe:CreateTexture(nil,"ARTWORK")
    header:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header.blp")
    header:SetWidth(350)
    header:SetHeight(68)
    header:SetPoint("TOP",optionsframe,"TOP",0,12)

    local headertext = optionsframe:CreateFontString(nil,"ARTWORK","GameFontNormal")
    headertext:SetPoint("TOP",header,"TOP",0,-14)
    headertext:SetText("Doom_CooldownPulse")

    for i,v in pairs(sliders) do
        local slider = CreateFrame("slider", "DoomCooldownPulse_OptionsFrameSlider"..i, optionsframe, "OptionsSliderTemplate")
        if (i == 1) then
            slider:SetPoint("TOP",optionsframe,"TOP",0,-50)
        else
            slider:SetPoint("TOP",getglobal("DoomCooldownPulse_OptionsFrameSlider"..(i-1)),"BOTTOM",0,-35)
        end
        local valuetext = slider:CreateFontString(nil,"ARTWORK","GameFontNormalSmall")
        valuetext:SetPoint("TOP",slider,"BOTTOM",0,-1)
        valuetext:SetText(format("%.1f", addon:GetSetting(v.value)))
        getglobal("DoomCooldownPulse_OptionsFrameSlider"..i.."Text"):SetText(v.text)
        getglobal("DoomCooldownPulse_OptionsFrameSlider"..i.."Low"):SetText(v.min)
        getglobal("DoomCooldownPulse_OptionsFrameSlider"..i.."High"):SetText(v.max)
        slider:SetMinMaxValues(v.min,v.max)
        slider:SetValueStep(v.step)
        slider:SetObeyStepOnDrag(true)
        slider:SetValue(addon:GetSetting(v.value))
        slider:SetScript("OnValueChanged",function()
            local value = slider:GetValue()
            addon:SetSetting(v.value, value)
            valuetext:SetText(format("%.1f", value))
            if (addon.animationFrame:IsMouseEnabled()) then
                addon.animationFrame:SetWidth(addon:GetSetting("iconSize"))
                addon.animationFrame:SetHeight(addon:GetSetting("iconSize"))
            end
        end)
    end

    local pettext = optionsframe:CreateFontString(nil,"ARTWORK","GameFontNormalSmall")
    pettext:SetPoint("TOPLEFT","DoomCooldownPulse_OptionsFrameSlider"..#sliders,"BOTTOMLEFT",-15,-30)
    pettext:SetText("Pet color overlay:")

    local petcolorselect = CreateFrame('Button',"DoomCooldownPulse_OptionsFramePetColorBox",optionsframe)
    petcolorselect:SetPoint("LEFT",pettext,"RIGHT",10,0)
    petcolorselect:SetWidth(20)
    petcolorselect:SetHeight(20)
    petcolorselect:SetNormalTexture('Interface/ChatFrame/ChatFrameColorSwatch')
    petcolorselect:GetNormalTexture():SetVertexColor(unpack(addon:GetSetting("petOverlay")))
    petcolorselect:SetScript("OnEnter",function(self) GameTooltip:SetOwner(self, "ANCHOR_CURSOR") GameTooltip:SetText("Note: Use white if you don't want any overlay for pet cooldowns") end)
    petcolorselect:SetScript("OnLeave",function(self) GameTooltip:Hide() end)
    petcolorselect:SetScript('OnClick', function(self)
        local r, g, b = unpack(DoomCooldownPulseDB.settings.petOverlay)
        ColorPickerFrame:SetupColorPickerAndShow({
            swatchFunc = function(self) addon:SetSetting("petOverlay", {ColorPickerFrame:GetColorRGB()}) petcolorselect:GetNormalTexture():SetVertexColor(ColorPickerFrame:GetColorRGB()) end,
            cancelFunc = function(self) addon:SetSetting("petOverlay", {r,g,b}) petcolorselect:GetNormalTexture():SetVertexColor(unpack(addon:GetSetting("petOverlay"))) end,
            hasOpacity = false,
            r = r,
            g = g,
            b = b
        })
        ColorPickerFrame:SetPoint("TOPLEFT",optionsframe,"TOPRIGHT")
    end)

    local petcolorselectbg = petcolorselect:CreateTexture(nil, 'BACKGROUND')
    petcolorselectbg:SetWidth(17)
    petcolorselectbg:SetHeight(17)
    petcolorselectbg:SetTexture(1,1,1)
    petcolorselectbg:SetPoint('CENTER')

    local spellnametext = optionsframe:CreateFontString(nil,"ARTWORK","GameFontNormalSmall")
    spellnametext:SetPoint("TOPLEFT",pettext,"BOTTOMLEFT",0,-18)
    spellnametext:SetText("Show spell name:")

    local spellnamecbt = CreateFrame("CheckButton","DoomCooldownPulse_OptionsFrameSpellNameCheckButton",optionsframe,"UICheckButtonTemplate")
    spellnamecbt:SetPoint("LEFT",spellnametext,"RIGHT",6,0)
    spellnamecbt:SetChecked(addon:GetSetting("showSpellName"))
    spellnamecbt:SetScript("OnClick", function(self)
        local newState = self:GetChecked()
        self:SetChecked(newState)
        addon:SetSetting("showSpellName", newState)
    end)

    local ignoretext = optionsframe:CreateFontString(nil,"ARTWORK","GameFontNormalSmall")
    ignoretext:SetPoint("TOPLEFT",spellnametext,"BOTTOMLEFT",0,-18)
    ignoretext:SetText("Filter spells:")

    local ignoretypebuttonblacklist = CreateFrame("Checkbutton","DoomCooldownPulse_OptionsFrameIgnoreTypeButtonBlacklist",optionsframe,"UIRadioButtonTemplate")
    ignoretypebuttonblacklist:SetPoint("TOPLEFT",ignoretext,"BOTTOMLEFT",0,-4)
    ignoretypebuttonblacklist:SetChecked(DoomCooldownPulseDBPerCharacter and not DoomCooldownPulseDBPerCharacter.invertIgnored or false)
    ignoretypebuttonblacklist:SetScript("OnClick", function()
        DoomCooldownPulseDBPerCharacter = DoomCooldownPulseDBPerCharacter or {}
        DoomCooldownPulse_OptionsFrameIgnoreTypeButtonWhitelist:SetChecked(false)
        DoomCooldownPulseDBPerCharacter.invertIgnored = false
    end)

    local ignoretypetextblacklist = optionsframe:CreateFontString(nil,"ARTWORK","GameFontNormalSmall")
    ignoretypetextblacklist:SetPoint("LEFT",ignoretypebuttonblacklist,"RIGHT",4,0)
    ignoretypetextblacklist:SetText("Blacklist")

    local ignoretypebuttonwhitelist = CreateFrame("Checkbutton","DoomCooldownPulse_OptionsFrameIgnoreTypeButtonWhitelist",optionsframe,"UIRadioButtonTemplate")
    ignoretypebuttonwhitelist:SetPoint("LEFT",ignoretypetextblacklist,"RIGHT",10,0)
    ignoretypebuttonwhitelist:SetChecked(DoomCooldownPulseDBPerCharacter and DoomCooldownPulseDBPerCharacter.invertIgnored or false)
    ignoretypebuttonwhitelist:SetScript("OnClick", function()
        DoomCooldownPulseDBPerCharacter = DoomCooldownPulseDBPerCharacter or {}
        DoomCooldownPulse_OptionsFrameIgnoreTypeButtonBlacklist:SetChecked(false)
        DoomCooldownPulseDBPerCharacter.invertIgnored = true
    end)

    local ignoretypetextwhitelist = optionsframe:CreateFontString(nil,"ARTWORK","GameFontNormalSmall")
    ignoretypetextwhitelist:SetPoint("LEFT",ignoretypebuttonwhitelist,"RIGHT",4,0)
    ignoretypetextwhitelist:SetText("Whitelist")

    local ignorebox = CreateFrame("EditBox","DoomCooldownPulse_OptionsFrameIgnoreBox",optionsframe,"InputBoxTemplate")
    ignorebox:SetAutoFocus(false)
    ignorebox:SetPoint("TOPLEFT",ignoretypebuttonblacklist,"BOTTOMLEFT",4,2)
    ignorebox:SetWidth(170)
    ignorebox:SetHeight(32)
    ignorebox:SetText(DoomCooldownPulseDBPerCharacter and DoomCooldownPulseDBPerCharacter.ignoredSpells or "")
    ignorebox:SetScript("OnEnter",function(self) GameTooltip:SetOwner(self, "ANCHOR_CURSOR") GameTooltip:SetText("Note: Separate multiple spells with commas") end)
    ignorebox:SetScript("OnLeave",function(self) GameTooltip:Hide() end)
    ignorebox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    ignorebox:SetScript("OnEditFocusLost",function(self)
        DoomCooldownPulseDBPerCharacter = DoomCooldownPulseDBPerCharacter or {}
        DoomCooldownPulseDBPerCharacter.ignoredSpells = ignorebox:GetText()
    end)

    for i,v in pairs(buttons) do
        local button = CreateFrame("Button", "DoomCooldownPulse_OptionsFrameButton"..i, optionsframe, "UIPanelButtonTemplate")
        button:SetHeight(24)
        button:SetWidth(75)
        button:SetPoint("BOTTOM", optionsframe, "BOTTOM", ((i%2==0 and -1) or 1)*45, 10 + ceil(i/2)*15 + (ceil(i/2)-1)*15)
        button:SetText(v.text)
        button:SetScript("OnClick", function(self) PlaySound(852) v.func(self) end)
    end

    return optionsframe
end

-- Test Pulse
function addon:TestPulse()
    addon:PlayPulse("Interface\\Icons\\Spell_Nature_Earthbind", false, "Test Spell")
end

-- Slash command to toggle debug logging
SLASH_DCPDEBUG1 = "/dcpdebug"
SlashCmdList["DCPDEBUG"] = function(msg)
    addon.DCP_DEBUG = not addon.DCP_DEBUG
    print("DoomCooldownPulse debug: " .. (addon.DCP_DEBUG and "ON" or "OFF"))
end