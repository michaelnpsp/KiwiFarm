-- KiwiFarm Classic (C) 2019 MiCHaEL
local addonName = ...

local MARGIN = 4
local RESET_MAX = 5
local COLOR_TRANSPARENT = { 0,0,0,0 }
local FONTS = { Arial = 'Fonts\\ARIALN.TTF', FrizQT = 'Fonts\\FRIZQT__.TTF', Morpheus = 'Fonts\\MORPHEUS.TTF', Skurri = 'Fonts\\SKURRI.TTF' }

local time = time
local strfind = strfind
local floor = math.floor
local band = bit.band
local COMBATLOG_OBJECT_CONTROL_NPC = COMBATLOG_OBJECT_CONTROL_NPC
local IsInInstance = IsInInstance

local config
local resets
local lockspent

-- main frame
local addon = CreateFrame('Frame', "KiwiFarm", UIParent)
addon:EnableMouse(true)
addon:SetMovable(true)
addon:RegisterForDrag("LeftButton")
addon:SetScript("OnDragStart", addon.StartMoving)
addon:SetScript("OnDragStop", addon.StopMovingOrSizing)
-- background texture
local backTexture = addon:CreateTexture()
backTexture:SetAllPoints()
-- text left
local text0 = addon:CreateFontString()
text0:SetPoint('TOPLEFT')
text0:SetJustifyH('LEFT')
-- text right
local text = addon:CreateFontString()
text:SetPoint('TOPRIGHT')
text:SetJustifyH('RIGHT')
-- timer
local timer = addon:CreateAnimationGroup()
timer.animation = timer:CreateAnimation()
timer.animation:SetDuration(1)
timer:SetLooping("REPEAT")

-- utils
local function FmtMoney(money)
	money = money or 0
	local gold   = floor(  money / COPPER_PER_GOLD )
    local silver = floor( (money % COPPER_PER_GOLD) / COPPER_PER_SILVER )
    local copper = floor(  money % COPPER_PER_SILVER )
	return string.format( "%d|cffffd70ag|r %d|cffc7c7cfs|r %d|cffeda55fc|r", gold, silver, copper)
end

local function RegisterMoney(money)
	local key = floor( time() / 86400 )
	config.daily[key] = (config.daily[key] or 0) + money
end


-- update text
local function RefreshText()
	local curtime = time()
	-- refresh reset data if first reset is +1hour old
	while (#resets>0 and curtime-resets[1]>3600) or #resets>RESET_MAX do -- remove old resets(>1hour)
		table.remove(resets,1)
	end
	-- some info
	local timeLast  = resets[#resets]
	local timeLock  = #resets>0 and resets[1]+3600 or nil
	local remain    = RESET_MAX-#resets
	-- time of last reset in last hour, or if there are no resets time when the instance was marked as modified (some mob killed)
	local sReset = (timeLast and curtime-timeLast) or (lockspent and curtime-lockspent) or 0
	local m1, s1 = floor(sReset/60), sReset%60
	-- unlock time
	local sUnlock = timeLock and timeLock-curtime or 0
	local m2, s2 = floor(sUnlock/60), sUnlock%60
	-- locked info
	local locked = remain<=0 and (sUnlock>60*5 and '|cFFff0000' or '|cFFff8000') or ''
	local spent  = lockspent and '|cFFff8000' or '|cFF00ff00'
	-- session duration
	local sSession = curtime - (config.sessionStart or curtime) + (config.sessionDuration or 0)
	local m0, s0 = floor(sSession/60), sSession%60
	-- money info
	local mTotal = config.moneyCash+config.moneyItems
	local mTotalHour = sSession>0 and floor(mTotal*3600/sSession) or 0
	-- create display text
	text:SetFormattedText(
		"\n%dm %ds\n%s%dm %ds|r\n%d\n%s%dm %ds\n%s\n%s\n%s\n%s",
		m0,s0,spent,m1,s1,remain,locked,m2,s2,FmtMoney(config.moneyCash),FmtMoney(config.moneyItems),FmtMoney(mTotal), FmtMoney(mTotalHour)
	)
	-- update timer status
	local stopped = #resets==0 and not lockspent and not config.sessionStart
	if stopped ~= not timer:IsPlaying() then
		if stopped then
			timer:Stop()
		else
			timer:Play()
		end
	end
end

-- add reset
local function AddReset()
	local curtime = time()
	if curtime-(resets[#resets] or 0)>3 then -- ignore reset of additional instances
		lockspent = nil
		table.insert( resets, curtime )
		RefreshText()
	end
end

-- session start
local function SessionStart()
	if not config.sessionStart then
		config.sessionStart = time()
		config.moneyCash  = config.moneyCash or 0
		config.moneyItems = config.moneyItems or 0
		RefreshText()
	end
end

-- session stop
local function SessionStop()
	if config.sessionStart then
		local curtime = time()
		config.sessionDuration = (config.sessionDuration or 0) + (curtime - (config.sessionStart or curtime))
		config.sessionStart = nil
	end
end

-- session reset
local function SessionReset()
	config.sessionStart = config.sessionStart and time() or nil
	config.sessionDuration = nil
	config.moneyCash  = 0
	config.moneyItems = 0
	RefreshText()
end

-- main frame becomes visible
addon:SetScript("OnShow", function(self)
	self:RegisterEvent("CHAT_MSG_SYSTEM")
	self:RegisterEvent("CHAT_MSG_LOOT")
	self:RegisterEvent("CHAT_MSG_MONEY")
	RefreshText()
end)

-- main frame becomes invisible
addon:SetScript("OnHide", function(self)
	self:UnregisterEvent("CHAT_MSG_SYSTEM")
	self:UnregisterEvent("CHAT_MSG_LOOT")
	self:UnregisterEvent("CHAT_MSG_MONEY")
end)

-- shift+mouse click to reset instances
addon:SetScript("OnMouseUp", function(self, button)
	if button == 'RightButton' then
		addon:ShowMenu()
	elseif IsShiftKeyDown() then -- reset instances data
		ResetInstances()
	elseif IsControlKeyDown() then -- reset session
		SessionReset()
	end
end)

-- track reset instance event
local PATTERN_RESET = '^'..INSTANCE_RESET_SUCCESS:gsub("([^%w])","%%%1"):gsub('%%%%s','.+')..'$'
function addon:CHAT_MSG_SYSTEM(event,msg)
	if strfind(msg,PATTERN_RESET) then
		AddReset()
	end
end

-- looted items
local PATTERN_LOOTS = LOOT_ITEM_SELF:gsub("%%s", "(.+)")
local PATTERN_LOOTM = LOOT_ITEM_SELF_MULTIPLE:gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)")
function addon:CHAT_MSG_LOOT(event,msg)
	if config.sessionStart then
		local itemLink, quantity = strmatch(msg, PATTERN_LOOTM)
		if not itemLink then
			quantity = 1
			itemLink = strmatch(msg, PATTERN_LOOTS)
		end
		if itemLink then
			local price = select( 11, GetItemInfo(itemLink) ) or 0
			local money = price*quantity
			config.moneyItems = config.moneyItems + money
			RegisterMoney(money)
			print("Item Price:", FmtMoney(price), quantity, itemLink)
		end
	end
end

-- looted gold
do
	local digits = {}
	local func = function(n) digits[#digits+1]=n end
	function addon:CHAT_MSG_MONEY(event,msg)
		if config.sessionStart then
			wipe(digits)
			msg:gsub("%d+",func)
			local copper
			if #digits==3 then -- gold + silver + copper
				copper = digits[1]*10000+digits[2]*100+digits[3]
			elseif #digits == 2 then -- siver + copper
				copper = digits[1]*100+digits[2]
			else -- copper
				copper = digits[1]
			end
			config.moneyCash = config.moneyCash + copper
			RegisterMoney(copper)
			print("Money Gained:", FmtMoney(copper))
		end
	end
end

-- zones management
function addon:ZONE_CHANGED_NEW_AREA()
	if not config.disabled and (not config.zones or config.zones[GetZoneText()]) then
		local ins,typ = IsInInstance()
		if ins then
			if not config.sessionStart then -- session start time
				SessionStart()
			end
			if #resets>=RESET_MAX then -- locked but inside instance, means locked expired before estimated unlock time
				table.remove(resets,1)
			end
			if not lockspent and typ=='party' then
				self:RegisterEvent('COMBAT_LOG_EVENT_UNFILTERED')
			end
		elseif not lockspent then
			self:UnregisterEvent('COMBAT_LOG_EVENT_UNFILTERED')
		end
		self:Show()
	elseif addon:IsVisible() then
		self:Hide()
		self:UnregisterEvent('COMBAT_LOG_EVENT_UNFILTERED')
	end
end

-- save hidden reset on player logout
do
	local isLogout
	hooksecurefunc("Logout", function() isLogout=true end)
	hooksecurefunc("Quit",   function() isLogout=true end)
	hooksecurefunc("CancelLogout", function() isLogout=nil end)
	function addon:PLAYER_LOGOUT()
		if lockspent then
			if isLogout then -- logout
				AddReset()
			else -- reload ui
				config.lockspent = lockspent
			end
		end
	end
end

-- If we kill a npc inside instance a ResetInstance() is executed on player logout, so we need this to track
-- and save this hidden reset, see addon:PLAYER_LOGOUT()
function addon:COMBAT_LOG_EVENT_UNFILTERED()
	local _, eventType,_,_,_,_,_,dstGUID,_,dstFlags = CombatLogGetCurrentEventInfo()
	if eventType == 'UNIT_DIED' and band(dstFlags,COMBATLOG_OBJECT_CONTROL_NPC)~=0 and IsInInstance() then
		lockspent = time()
		addon:UnregisterEvent('COMBAT_LOG_EVENT_UNFILTERED')
		timer:Play()
	end
end

-- layout main frame
local function LayoutFrame()
	if addon:GetNumPoints()==0 then
		addon:SetPoint("TOPLEFT",UIParent, 'CENTER', 0,0)
	end
	-- background
	backTexture:SetColorTexture( unpack(config.backColor or COLOR_TRANSPARENT) )
	-- text main data
	text:ClearAllPoints()
	text:SetPoint('TOPRIGHT', -MARGIN, -MARGIN)
	text:SetPoint('TOPLEFT', MARGIN, -MARGIN)
	text:SetJustifyH('RIGHT')
	text:SetFont(config.fontname or FONTS.Arial or STANDARD_TEXT_FONT, config.fontsize or 14, 'OUTLINE')
	local t = text:GetText()
	text:SetText(nil)
	text:SetText(t)
	-- text headers
	text0:ClearAllPoints()
	text0:SetPoint('TOPLEFT', MARGIN, -MARGIN)
	text0:SetJustifyH('LEFT')
	text0:SetFont(config.fontname or FONTS.Arial or STANDARD_TEXT_FONT, config.fontsize or 14, 'OUTLINE')
	text0:SetText(nil)
	text0:SetText( "|cFFa0a0ffKiwi Farm:|r\nSession Duration:\nLast Reset:\nRemaining:\nLocked:\nCurrency:\nItems:\nTotal:\nTotal (per hour):" )
	-- main frame size
	addon:SetHeight( text0:GetHeight() + MARGIN*2 )
	addon:SetWidth( text0:GetWidth() * 1.6 + MARGIN*2 )
end

-- initialize
local function Initialize()
	local serverKey = GetRealmName()
	local root = KiwiFarmDB
	if not root then
		root = {}; KiwiFarmDB = root
	end
	config = root[serverKey]
	if not config then
		config = { resets = {} }; root[serverKey] = config
	end
	config.backColor = config.backColor or { 0,0,0,0 }
	config.daily = config.daily or {}
	config.moneyCash  = config.moneyCash or 0
	config.moneyItems = config.moneyItems  or 0
 	resets = config.resets
	lockspent = config.lockspent -- only to save lockspent variable between reloads
	config.lockspent = nil
	addon:SetScript('OnEvent', function(self,event,...)	self[event](self,event,...) end)
	addon:RegisterEvent("CHAT_MSG_SYSTEM")
	addon:RegisterEvent("CHAT_MSG_LOOT")
	addon:RegisterEvent("CHAT_MSG_MONEY")
	addon:RegisterEvent("ZONE_CHANGED_NEW_AREA")
	addon:RegisterEvent("PLAYER_LOGOUT")
	timer:SetScript("OnLoop", RefreshText)
	LayoutFrame()
	RefreshText()
	addon:ZONE_CHANGED_NEW_AREA()
end

-- init events
addon:RegisterEvent("ADDON_LOADED")
addon:RegisterEvent("PLAYER_LOGIN")
addon:SetScript("OnEvent", function(frame, event, name)
	if event == "ADDON_LOADED" and name == addonName then
		addon.__loaded = true
	end
	if addon.__loaded and IsLoggedIn() then
		addon:UnregisterAllEvents()
		Initialize()
	end
end)

-- config cmdline
SLASH_KIWIFARM1 = "/kfarm"
SlashCmdList.KIWIFARM = function(args)
	local arg1,arg2,arg3 = strsplit(" ",args,3)
	arg1, arg2 = strlower(arg1 or ''), strlower(arg2 or '')
	if arg1 == 'show' then
		config.disabled = nil
		addon:Show()
		addon:ZONE_CHANGED_NEW_AREA()
	elseif arg1 == 'hide' then
		config.disabled = true
		addon:Hide()
	elseif arg1 == 'font' then
		if tonumber(arg2) then
			config.fontsize = tonumber(arg2)
		else
			config.fontname = FONTS[ strlower(strsub(arg2,1,1)) ]
		end
		LayoutFrame()
	elseif arg1 == 'reset' then
		ResetInstances()
	elseif arg1 == 'clear' then
		wipe(resets)
	elseif arg1 =='zone' then
		if arg2 == 'clear' then
			config.zones = nil
		elseif arg2 == 'add' then
			local zone = GetZoneText()
			config.zones = config.zones or {}
			config.zones[zone] = true
		end
		addon:ZONE_CHANGED_NEW_AREA()
	else
		print("KiwiFarm Classic:")
		print("  Last Reset: time elapsed from last instance reset.")
		print("  Remaining: available resets (5/hour max).")
		print("  Locked: locked duration if all resets are used.")
		print("  Shift-Click to Reset Instances.")
		print("Commands:")
		print("  /kfarm")
		print("  /kfarm show||hide")
		print("  /kfarm font size||a||f||s||m")
		print("  /kfarm zone clear||add  -- clear all zones or add the current zone")
		print("  /kfarm reset  -- reset instances")
		print("  /kfarm clear  -- remove all saved resets")

	end
	RefreshText()
	print("KiwiFarm setup:")
	print("  font name: " .. (config.fontname or FONTS.Arial))
	print("  font size: " .. (config.fontsize or 14))
	if config.zones then
		for zone in pairs(config.zones) do
			print( '  zone: ' .. zone )
		end
	end
	for i,t in ipairs(config.resets) do
		print( string.format('  reset%d: %s',i, date("%H:%M:%S",t) ) )
	end
end

-- config popup menu
do
	local menuFrame = CreateFrame("Frame", "KiwiFarmPopupMenu", UIParent, "UIDropDownMenuTemplate")
	local function SetBackground()
		backTexture:SetColorTexture( unpack(config.backColor or COLOR_TRANSPARENT) )
	end
	local function SetFontSize(info)
		if info.value~=0 then
			config.fontsize = (config.fontsize or 14) + info.value
			if config.fontsize<5 then config.fontsize = 5 end
		else
			config.fontsize = 14
		end
		LayoutFrame()
	end
	local function SetFont(info)
		config.fontname = info.value
		LayoutFrame()
	end
	local function FontChecked(info)
		return info.value == (config.fontname or FONTS.Arial)
	end
	local function ZoneAdd()
		local zone = GetZoneText()
		config.zones = config.zones or {}
		config.zones[zone] = true
		addon:ZONE_CHANGED_NEW_AREA()
	end
	local function ZoneDel(info)
		config.zones[info.value] = nil
		if not next(config.zones) then config.zones = nil end
		addon:ZONE_CHANGED_NEW_AREA()
	end
	local menuFonts = {}
	local menuZones = {}
	local menuDaily = {}
	local menuTable = {
		{ text = 'Kiwi Farm [/kfarm]', notCheckable= true, isTitle = true },
		{ text = 'Session',     notCheckable= true, hasArrow = true, menuList = {
			{ text = 'Start Session',   notCheckable = true, func = SessionStart },
			{ text = 'Stop Session',    notCheckable = true, func = SessionStop  },
			{ text = 'Reset Session',   notCheckable = true, func = SessionReset },
		} },
		{ text = 'Gold per day', notCheckable= true, hasArrow = true, menuList = menuDaily },
		{ text = 'Farming Zones',   notCheckable= true, hasArrow = true, menuList = menuZones },
		{ text = 'Reset Instances', notCheckable = true, func = ResetInstances },
		{ text = 'Appearance',      notCheckable = true, isTitle = true },
		{ text = 'Font', notCheckable= true, hasArrow = true, menuList = menuFonts },
		{ text = 'Font Size', notCheckable= true, hasArrow = true, menuList = {
			{ text = 'Increase++',   value =  1,  notCheckable= true, keepShownOnClick=1, func = SetFontSize },
			{ text = 'Decrease--',   value = -1,  notCheckable= true, keepShownOnClick=1, func = SetFontSize },
			{ text = 'Default (14)', value =  0,  notCheckable= true, keepShownOnClick=1, func = SetFontSize },
		} },
		{
		  text = 'Background Color', notCheckable= true, hasColorSwatch = true, hasOpacity= true,
		  swatchFunc = function() local c=config.backColor; c[1],c[2],c[3]=ColorPickerFrame:GetColorRGB(); SetBackground(); end,
		  opacityFunc= function() config.backColor[4] = 1 - OpacitySliderFrame:GetValue(); SetBackground(); end,
		  cancelFunc = function(c) local cc=config.backColor; cc[1], cc[2], cc[3], cc[4] = c.r, c.g, c.b, 1-c.opacity; SetBackground(); end,
		},
		{ text = 'Hide Addon',   notCheckable = true, func = function() config.disabled=true; addon:Hide() end },
	}
	function addon:ShowMenu()
		-- refresh daily money
		local day, header = floor(time()/86400), 'Today:'
		for i=1,7 do
			local money, item = config.daily[day]
			if money then
				item = menuDaily[i] or { notCheckable= true }
				item.text = string.format('%s %s', header, FmtMoney(money) )
			end
			menuDaily[i] = item
			day = day - 1
			header = date("%m/%d:",day*86400)
		end
		-- refresh zones
		wipe(menuZones)
		menuZones[1] = { text = '(+)Add Current Zone', notCheckable = true, func = ZoneAdd }
		for zone in pairs(config.zones or {}) do
			menuZones[#menuZones+1] = { text = '(-)'..zone, value = zone, notCheckable = true, func = ZoneDel }
		end
		-- refresh fonts
		if #menuFonts==0 then
			local media = LibStub("LibSharedMedia-3.0", true)
			for name, key in pairs(media and media:HashTable('font') or FONTS) do
				table.insert( menuFonts, { text = name, value = key, func = SetFont, checked = FontChecked } )
			end
		end
		-- refresh colors
		for _,o in ipairs(menuTable) do
			if o.hasColorSwatch then
				o.r, o.g, o.b, o.opacity = unpack(config.backColor)
				o.opacity = 1 - o.opacity
				break
			end
		end
		EasyMenu(menuTable, menuFrame, "cursor", 0 , 0, "MENU", 1)
	end
end
