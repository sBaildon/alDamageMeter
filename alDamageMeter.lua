-- Config start
local anchor = "TOPLEFT"
local x, y = 12, -12
local width, height = 130, 130
local barheight = 14
local spacing = 1
local maxbars = 20
local maxfights = 10
local reportstrings = 10
-- Config end

local boss = LibStub("LibBossIDs-1.0")
local bossname, mobname = nil, nil
local units, guids, bar, barguids, owners, pets = {}, {}, {}, {}, {}, {}
local current, display, fights, udata = {}, {}, {}
local timer = 0
local MainFrame, DisplayFrame
local combatstarted = false
local filter = COMBATLOG_OBJECT_AFFILIATION_RAID + COMBATLOG_OBJECT_AFFILIATION_PARTY + COMBATLOG_OBJECT_AFFILIATION_MINE
local backdrop = {
	bgFile = [=[Interface\ChatFrame\ChatFrameBackground]=],
	edgeFile = [=[Interface\ChatFrame\ChatFrameBackground]=], edgeSize = 1,
	insets = {top = 0, left = 0, bottom = 0, right = 0},
}
local displayMode = {
	'Damage',
	'Healing',
	'Dispels',
	'Interrupts',
}
local sMode = 'Damage'

local menuFrame = CreateFrame("Frame", "alDamageMeterMenu", UIParent, "UIDropDownMenuTemplate")

local dummy = function() return end

local truncate = function(value)
	if value >= 1e6 then
		return string.format('%.2fm', value / 1e6)
	elseif value >= 1e4 then
		return string.format('%.1fk', value / 1e3)
	else
		return string.format('%.0f', value)
	end
end

local IsFriendlyUnit = function(uGUID)
	if guids[uGUID] or owners[uGUID] or uGUID==UnitGUID("player") then
		return true
	else
		return false
	end
end

local IsUnitInCombat = function(uGUID)
	unit = guids[uGUID]
	if unit then
		return UnitAffectingCombat(unit)
	end
	return false
end

local CreateFS = function(frame, fsize, fstyle)
	local fstring = frame:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight')
	fstring:SetFont(GameFontHighlight:GetFont(), fsize, fstyle)
	return fstring
end

local tcopy = function(src)
	local dest = {}
	for k, v in pairs(src) do
		dest[k] = v
	end
	return dest
end

local dps = function(cdata)
	return cdata[sMode] / cdata.combatTime
end

local report = function(channel)
	local message = sMode..":"
	if channel == "Chat" then
		DEFAULT_CHAT_FRAME:AddMessage(message)
	else
		SendChatMessage(message, channel)
	end
	for i, v in pairs(barguids) do
		if i > reportstrings then return end
		if sMode == "Damage" or sMode == "Healing" then
			message = string.format("%2d. %s    %s (%.0f)", i, display[v].name, truncate(display[v][sMode]), dps(display[v]))
		else
			message = string.format("%2d. %s    %s", i, display[v].name, truncate(display[v][sMode]))
		end
		if channel == "Chat" then
			DEFAULT_CHAT_FRAME:AddMessage(message)
		else
			SendChatMessage(message, channel)
		end
	end
end

local reportList = {
	{
		text = "Chat", 
		func = function() report("Chat") end,
	},
	{
		text = "Say", 
		func = function() report("SAY") end,
	},
	{
		text = "Party", 
		func = function() report("PARTY") end,
	},
	{
		text = "Raid", 
		func = function() report("RAID") end,
	},
	{
		text = "Officer", 
		func = function() report("OFFICER") end,
	},
	{
		text = "Guild", 
		func = function() report("GUILD") end,
	},
}

local CreateBar = function()
	local newbar = CreateFrame("Statusbar", nil, DisplayFrame)
	newbar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
	newbar:SetMinMaxValues(0, 100)
	newbar:SetWidth(width)
	newbar:SetHeight(barheight)
	newbar.left = CreateFS(newbar, 11)
	newbar.left:SetPoint("LEFT", 2, 0)
	newbar.left:SetJustifyH("LEFT")
	newbar.right = CreateFS(newbar, 11)
	newbar.right:SetPoint("RIGHT", -2, 0)
	newbar.right:SetJustifyH("RIGHT")
	return newbar
end

local Add = function(uGUID, ammount, mode)
	local unit = guids[uGUID]
	if not unit then return end
	if not current[uGUID] then
		local newdata = {
			name = UnitName(unit),
			class = select(2, UnitClass(unit)),
			combatTime = 1,
		}
		for _, v in pairs(displayMode) do
			newdata[v] = 0
		end
		current[uGUID] = newdata
		tinsert(barguids, uGUID)
	end
	udata = current[uGUID]
	udata[mode] = udata[mode] + ammount
end

local SortMethod = function(a, b)
	return display[b][sMode] < display[a][sMode]
end

local UpdateBars = function(frame)
	table.sort(barguids, SortMethod)
	local color, cur, max
	local num = 0
	for i, v in pairs(barguids) do
		if not bar[i] then 
			bar[i] = CreateBar()
			bar[i]:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -(barheight+spacing)*(i-1))
		end
		cur = display[v]
		max = display[barguids[1]]
		if cur[sMode] == 0 then break end
		bar[i]:SetValue(100 * cur[sMode] / max[sMode])
		color = RAID_CLASS_COLORS[cur.class]
		bar[i]:SetStatusBarColor(color.r, color.g, color.b)
		if sMode == "Damage" or sMode == "Healing" then
			bar[i].right:SetFormattedText("%s (%.0f)", truncate(cur[sMode]), dps(cur))
		else
			bar[i].right:SetFormattedText("%s", truncate(cur[sMode]))
		end
		bar[i].left:SetText(cur.name)
		bar[i]:Show()
		num = num + 1
	end
	DisplayFrame:SetHeight((barheight+spacing)*num)
end

local ResetDisplay = function(fight)
	for i, v in pairs(bar) do
		v:Hide()
	end
	display = fight
	wipe(barguids)
	for guid, v in pairs(display) do
		tinsert(barguids, guid)
	end
	MainFrame:SetVerticalScroll(0)
	UpdateBars(DisplayFrame)
end

local Clean = function()
	numfights = 0
	wipe(current)
	wipe(fights)
	ResetDisplay(current)
end

local SetMode = function(mode)
	sMode = mode
	for i, v in pairs(bar) do
		v:Hide()
	end
	UpdateBars(DisplayFrame)
	MainFrame.title:SetText(sMode)
end

local CreateMenu = function(self, level)
	level = level or 1
	local info = {}
	if level == 1 then
		info.isTitle = 1
		info.text = "Menu"
		info.notCheckable = 1
		UIDropDownMenu_AddButton(info, level)
		wipe(info)
		info.text = "Mode"
		info.hasArrow = 1
		info.value = "Mode"
		info.notCheckable = 1
		UIDropDownMenu_AddButton(info, level)
		wipe(info)
		info.text = "Report to"
		info.hasArrow = 1
		info.value = "Report"
		info.notCheckable = 1
		UIDropDownMenu_AddButton(info, level)
		wipe(info)
		info.text = "Fight"
		info.hasArrow = 1
		info.value = "Fight"
		info.notCheckable = 1
		UIDropDownMenu_AddButton(info, level)
		wipe(info)
		info.text = "Clean"
		info.func = Clean
		info.notCheckable = 1
		UIDropDownMenu_AddButton(info, level)
	elseif level == 2 then
		if UIDROPDOWNMENU_MENU_VALUE == "Mode" then
			for i, v in pairs(displayMode) do
				wipe(info)
				info.text = v
				info.func = function() SetMode(v) end
				info.notCheckable = 1
				UIDropDownMenu_AddButton(info, level)
			end
		end
		if UIDROPDOWNMENU_MENU_VALUE == "Report" then
			for i, v in pairs(reportList) do
				wipe(info)
				info.text = v.text
				info.func = v.func
				info.notCheckable = 1
				UIDropDownMenu_AddButton(info, level)
			end
		end
		if UIDROPDOWNMENU_MENU_VALUE == "Fight" then
			wipe(info)
			info.text = "Current"
			info.func = function() ResetDisplay(current) end
			info.notCheckable = 1
			UIDropDownMenu_AddButton(info, level)
			for i, v in pairs(fights) do
				wipe(info)
				info.text = v.name
				info.func = function() ResetDisplay(v.data) end
				info.notCheckable = 1
				UIDropDownMenu_AddButton(info, level)
			end
		end
	end
end

local Menu = function(self)
	ToggleDropDownMenu(1, nil, menuFrame, self, 0, 0)
end

local EndCombat = function()
	DisplayFrame:SetScript('OnUpdate', nil)
	combatstarted = false
	local fname = bossname or mobname
	if fname then
		if #fights >= maxfights then
			tremove(fights, 1)
		end
		tinsert(fights, {name = fname, data = tcopy(current)})
		mobname, bossname = nil, nil
	end
end

local UpdatePets = function(unit, pet)
	if UnitExists(pet) then
		owners[UnitGUID(pet)] = UnitGUID(unit)
		pets[UnitGUID(unit)] = UnitGUID(pet)
	elseif pets[UnitGUID(unit)] then
		owners[pets[UnitGUID(unit)]] = nil
		pets[UnitGUID(unit)] = nil
	end
end

local CheckUnit = function(unit)
	if UnitExists(unit) then
		guid = UnitGUID(unit)
		if guid == UnitGUID("player") then
			unit = "player"
		end
		units[unit] = guid
		guids[guid] = unit
		pet = unit .. "pet"
		UpdatePets(unit, pet)
	elseif units[unit] then
		guids[units[unit]] = nil
		units[unit] = nil
	end
end

local IsRaidInCombat = function()
	if GetNumRaidMembers() > 0 then
		for i = 1, GetNumRaidMembers(), 1 do
			if UnitExists("raid"..i) and UnitAffectingCombat("raid"..i) then
				return true
			end
		end
	elseif GetNumPartyMembers() > 0 then
		for i = 1, GetNumPartyMembers(), 1 do
			if UnitExists("party"..i) and UnitAffectingCombat("party"..i) then
				return true
			end
		end
	end
	return false
end

local OnUpdate = function(self, elapsed)
	timer = timer + elapsed
	if timer > 0.5 then
		for i, v in pairs(current) do
			if IsUnitInCombat(i) then
				v.combatTime = v.combatTime + timer
			end
		end
		UpdateBars(DisplayFrame)
		if not InCombatLockdown() and not IsRaidInCombat() then
			EndCombat()
		end
		timer = 0
	end
end

local StartCombat = function()
	wipe(current)
	combatstarted = true
	ResetDisplay(current)
	DisplayFrame:SetScript('OnUpdate', OnUpdate)
end

local OnEvent = function(self, event, ...)
	if event == "COMBAT_LOG_EVENT_UNFILTERED" then
		local timestamp, eventType, sourceGUID, sourceName, sourceFlags, destGUID, destName, destFlags = select(1, ...)
		if not bit.band(sourceFlags, filter) then return end
		if eventType=="SWING_DAMAGE" or eventType=="RANGE_DAMAGE" or eventType=="SPELL_DAMAGE" or eventType=="SPELL_PERIODIC_DAMAGE" then
			local ammount = select(eventType=="SWING_DAMAGE" and 9 or 12, ...)
			if IsFriendlyUnit(sourceGUID) and not IsFriendlyUnit(destGUID) and combatstarted then
				if ammount and ammount > 0 then
					sourceGUID = owners[sourceGUID] or sourceGUID
					Add(sourceGUID, ammount, 'Damage')
					if not bossname and boss.BossIDs[tonumber(destGUID:sub(9, 12), 16)] then
						bossname = destName
					elseif not mobname then
						mobname = destName
					end
				end
			end
		elseif eventType=="SPELL_SUMMON" then
			owners[destGUID] = sourceGUID
			pets[sourceGUID] = destGUID
			return
		elseif eventType=="SPELL_HEAL" or eventType=="SPELL_PERIODIC_HEAL" then
			spellId, spellName, spellSchool, ammount, over, school, resist = select(9, ...)
			if IsFriendlyUnit(sourceGUID) and IsFriendlyUnit(destGUID) and combatstarted then
				over = over or 0
				if ammount and ammount > 0 then
					sourceGUID = owners[sourceGUID] or sourceGUID
					Add(sourceGUID, ammount - over, "Healing")
				end
			end
		elseif eventType=="SPELL_DISPEL" then
			if IsFriendlyUnit(sourceGUID) and IsFriendlyUnit(destGUID) and combatstarted then
				sourceGUID = owners[sourceGUID] or sourceGUID
				Add(sourceGUID, 1, "Dispels")
			end
		elseif eventType=="SPELL_INTERRUPT" then
			if IsFriendlyUnit(sourceGUID) and not IsFriendlyUnit(destGUID) and combatstarted then
				sourceGUID = owners[sourceGUID] or sourceGUID
				Add(sourceGUID, 1, "Interrupts")
			end
		else
			return
		end
	elseif event == "ADDON_LOADED" then
		local name = ...
		if name == "alDamageMeter" then
			self:UnregisterEvent("ADDON_LOADED")
			self:SetPoint(anchor, UIParent, anchor, x, y)
			self:SetWidth(width)
			self:SetHeight(height)
			self:SetBackdrop(backdrop)
			self:SetBackdropColor(0, 0, 0, 0.3)
			self:SetBackdropBorderColor(0, 0, 0, 1)
			width = width - 2
			height = height - 2
			MainFrame = CreateFrame("ScrollFrame", "alDamageScrollFrame", self, "UIPanelScrollFrameTemplate")
			_G["alDamageScrollFrameScrollBar"]:SetAlpha(0)
			MainFrame:SetPoint("TOPLEFT", self, "TOPLEFT", 1, -1)
			MainFrame:SetWidth(width)
			MainFrame:SetHeight(height)
			DisplayFrame = CreateFrame("Frame", "alDamageDisplayFrame", UIParent)
			DisplayFrame:SetPoint("TOPLEFT", MainFrame, "TOPLEFT", 0, 0)
			DisplayFrame:SetWidth(width)
			DisplayFrame:SetHeight(height)
			MainFrame:SetScrollChild(DisplayFrame)
			MainFrame:SetHorizontalScroll(0)
			MainFrame:SetVerticalScroll(0)
			MainFrame:EnableMouse(true)
			MainFrame:Show()
			UIDropDownMenu_Initialize(menuFrame, CreateMenu, "MENU")
			local button = CreateFrame("Button", nil, MainFrame)
			button:SetWidth(9)
			button:SetHeight(9)
			local texture = button:CreateTexture(nil, "OVERLAY")
			texture:SetTexture(0, 0.5, 1)
			texture:SetAllPoints(button)
			button:SetPoint("BOTTOMRIGHT", MainFrame, "TOPRIGHT", 0, 2)
			button:SetScript("OnClick", Menu)
			MainFrame.title = CreateFS(MainFrame, 11)
			MainFrame.title:SetPoint("BOTTOMLEFT", MainFrame, "TOPLEFT", 0, 1)
			MainFrame.title:SetText(sMode)
		end
	elseif event == "RAID_ROSTER_UPDATE" or event == "PARTY_MEMBERS_CHANGED" then
		if GetNumRaidMembers() > 0 then
			for i = 1, 40 do
				CheckUnit("raid"..i)
			end
		elseif GetNumPartyMembers() > 0 then
			for i = 1, 4 do
				CheckUnit("party"..i)
			end
		end
	elseif event == "PLAYER_ENTERING_WORLD" then
		units["player"] = UnitGUID("player")
		guids[UnitGUID("player")] = "player"
	elseif event == "PLAYER_REGEN_DISABLED" then
		if not combatstarted then
			StartCombat()
		end
	elseif event == "UNIT_PET" then
		local unit = ...
		local pet = unit .. "pet"
		UpdatePets(unit, pet)
	end
end

local addon = CreateFrame("frame", nil, UIParent)
addon:SetScript('OnEvent', OnEvent)
addon:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
addon:RegisterEvent("ADDON_LOADED")
addon:RegisterEvent("RAID_ROSTER_UPDATE")
addon:RegisterEvent("PARTY_MEMBERS_CHANGED")
addon:RegisterEvent("PLAYER_ENTERING_WORLD")
addon:RegisterEvent("PLAYER_REGEN_DISABLED")
addon:RegisterEvent("UNIT_PET")

SlashCmdList["alDamage"] = function(msg)
	Add(UnitGUID("player"), 100500, "Damage")
	Add(UnitGUID("player"), 10500, "Healing")
	Add(UnitGUID("player"), 1, "Dispels")
	Add(UnitGUID("player"), 3, "Interrupts")
	display = current
	UpdateBars(DisplayFrame)
end
SLASH_alDamage1 = "/aldmg"