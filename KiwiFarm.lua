-- KiwiFarm (C) 2019 MiCHaEL
local addonName = ...

--
local RESET_MAX = (WOW_PROJECT_ID == WOW_PROJECT_CLASSIC) and 5 or 10
local MARGIN = 4
local COLOR_TRANSPARENT = { 0,0,0,0 }
local FONTS = {
	Arial = 'Fonts\\ARIALN.TTF',
	FrizQT = 'Fonts\\FRIZQT__.TTF',
	Morpheus = 'Fonts\\MORPHEUS.TTF',
	Skurri = 'Fonts\\SKURRI.TTF'
}
local SOUNDS = {
	["Auction Window Open"] = "Sound/Interface/AuctionWindowOpen.ogg",
	["Auction Window Close"] = "Sound/Interface/AuctionWindowClose.ogg",
	["Coin" ] =  "Sound/interface/lootcoinlarge.ogg",
	["Money"] =  "sound/interface/imoneydialogopen.ogg",
	["Level Up"] = "Sound/Interface/LevelUp.ogg",
	["Gun Fire"] = "sound/item/weapons/gunfire01.ogg",
	["Player Invite"] = "Sound/Interface/iPlayerInviteA.ogg",
	["Raid Warning"] = "Sound/Interface/RaidWarning.ogg",
	["Ready Check"] = "Sound/Interface/ReadyCheck.ogg",
}

local DEFAULTS = {
	mobKills       = 0,
	moneyCash      = 0,
	moneyItems     = 0,
	countItems     = 0,
	priceByRarity  = {},
	soundByRarity  = {},
	priceMaxSource = {},
	moneyDaily     = {},
	moneyByQuality = {},
	countByQuality = {},
	textHide       = { quality = true },
	backColor 	   = { 0, 0, 0, .4 },
	minimapIcon    = { hide = false },
	framePos       = { anchor = 'TOPLEFT', x = 0, y = 0 },
}

--
local time = time
local date = date
local unpack = unpack
local strfind = strfind
local floor = math.floor
local band = bit.band
local strmatch = strmatch
local IsInInstance = IsInInstance
local GetZoneText = GetZoneText
local COMBATLOG_OBJECT_CONTROL_NPC = COMBATLOG_OBJECT_CONTROL_NPC

local config
local resets
local textHide

local combatActive
local combatTime
local combatCurKills = 0
local combatPreKills = 0

-- main frame
local addon = CreateFrame('Frame', "KiwiFarm", UIParent)
addon:EnableMouse(true)
addon:SetMovable(true)
addon:RegisterForDrag("LeftButton")
addon:SetScript("OnDragStart", addon.StartMoving)
addon:SetScript("OnDragStop", function(self)
	self:StopMovingOrSizing() -- we are assuming addon frame scale=1 in calculations
	self:SetUserPlaced(false)
	self:SavePosition()
	self:RestorePosition()
end )
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
local function FmtQuality(i)
	return string.format( "|c%s%s|r", select(4,GetItemQualityColor(i)), _G['ITEM_QUALITY'..i..'_DESC'] )
end

local function FmtMoney(money)
	money = money or 0
	local gold   = floor(  money / COPPER_PER_GOLD )
    local silver = floor( (money % COPPER_PER_GOLD) / COPPER_PER_SILVER )
    local copper = floor(  money % COPPER_PER_SILVER )
	return string.format( config.moneyFmt or "%d|cffffd70ag|r %d|cffc7c7cfs|r %d|cffeda55fc|r", gold, silver, copper)
end

local function RegisterMoney(money)
	local key = date("%Y/%m/%d")
	config.moneyDaily[key] = (config.moneyDaily[key] or 0) + money
end

local GetItemValue
do
	local function GetValue(source, itemID, name, class, rarity, level, vendorPrice)
		local price
		if source == 'Atr:DBMarket' then -- Auctionator: market
			price = Atr_GetAuctionBuyout and Atr_GetAuctionBuyout(name)
		elseif source == 'Atr:Destroy' then -- Auctionator: disenchant
			price = Atr_CalcDisenchantPrice and Atr_CalcDisenchantPrice(class,rarity,level) -- Atr_GetDisenchantValue() is bugged cannot be used
		elseif source ~= 'Vendor' then -- TSM4 sources
			price = TSMAPI_FOUR.CustomPrice.GetValue(source, "i:"..itemID)
		end
		return price or vendorPrice
	end
	function GetItemValue(itemLink)
		local itemID = strmatch(itemLink, "item:(%d+):") or itemLink
		local name, link, rarity, level, minLevel, typ, subTyp, stackCount, equipLoc, icon, vendorPrice, class = GetItemInfo(itemLink)
		local source = config.priceByRarity[rarity or 0]
		if source == 'MaxPrice' then
			local price = vendorPrice
			for src in pairs(config.priceMaxSource) do
				price = math.max( price, GetValue(src, itemID, name, class, rarity, level, vendorPrice) )
			end
			return price, rarity
		elseif source then
			return GetValue(source, itemID, name, class, rarity, level, vendorPrice), rarity
		else
			return vendorPrice, rarity
		end
	end
end

local PrepareText, RefreshText
do
	local text_header
	local text_mask
	local data = {}
	-- prepare text
	function PrepareText()
		-- header & session duration
		text_header =              "|cFF7FFF72KiwiFarm:|r\nSession:\n"
		text_mask   =	           "|cFF7FFF72%s|r\n"      -- zone
		text_mask   = text_mask .. "%s%02d:%02d:%02d|r\n"  -- session duration
		-- instance reset & lock info
		if not textHide.reset then
			text_header = text_header .. "Resets:\nLocked:\n"
			text_mask   = text_mask   .. "(%s%d|r) %s%02d:%02d|r\n"  -- last reset
			text_mask   = text_mask   .. "(%s%d|r) %s%02d:%02d|r\n"  -- lock time
		end
		-- count data
		if not textHide.count then
			-- mobs killed
			text_header = text_header .. "Mobs killed:\n"
			text_mask   = text_mask   .. "(%d) %d\n"
			-- items looted
			text_header = text_header .. "Items looted:\n"
			text_mask   = text_mask   .. "%d\n"
		end
		-- gold cash & items
		text_header = text_header .. "Gold cash:\nGold items:\n"
		text_mask   = text_mask   .. "%s\n"  -- money cash
		text_mask   = text_mask   .. "%s\n"  -- money items
		-- gold by item quality
		if not textHide.quality then
			for i=0,5 do -- gold by qualities (poor to legendary)
				text_header = text_header .. string.format(" %s\n",FmtQuality(i));
				text_mask   = text_mask   .. "(%d) %s\n"
			end
		end
		-- gold hour & total
		text_header = text_header .. "Gold/hour:\nGold total:"
		text_mask   = text_mask .. "%s\n" -- money per hour
		text_mask   = text_mask .. "%s" -- money total
		text0:SetText(text_header)
	end
	-- refresh text
	function RefreshText()
		local curtime = time()
		-- refresh reset data if first reset is +1hour old
		while (#resets>0 and curtime-resets[1]>3600) or #resets>RESET_MAX do -- remove old resets(>1hour)
			table.remove(resets,1)
		end
		-- reset old data
		wipe(data)
		-- zone text
		data[#data+1] = GetZoneText()
		-- session duration
		local sSession = curtime - (config.sessionStart or curtime) + (config.sessionDuration or 0)
		local m0, s0 = floor(sSession/60), sSession%60
		local h0, m0 = floor(m0/60), m0%60
		data[#data+1] = config.sessionStart and '|cFF00ff00' or '|cFFff0000'
		data[#data+1] = h0
		data[#data+1] = m0
		data[#data+1] = s0
		-- reset data
		if not textHide.reset then
			local timeLast  = resets[#resets]
			local timeLock  = #resets>0 and resets[1]+3600 or nil
			local remain    = RESET_MAX-#resets
			local sReset = (timeLast and curtime-timeLast) or 0 -- (config.lockspent and curtime-config.lockspent) or 0
			local sUnlock = timeLock and timeLock-curtime or 0
			--
			data[#data+1] = remain>0 and '|cFF00ff00' or '|cFFff0000'
			data[#data+1] = #resets
			data[#data+1] = config.lockspent and '|cFFff8000' or '|cFF00ff00'
			data[#data+1] = floor(sReset/60)
			data[#data+1] = sReset%60
			--
			data[#data+1] = remain>0 and '|cFF00ff00' or '|cFFff0000'
			data[#data+1] = remain
			data[#data+1] = remain<=0 and (sUnlock>60*5 and '|cFFff0000' or '|cFFff8000') or '|cFF00ff00'
			data[#data+1] = floor(sUnlock/60)
			data[#data+1] = sUnlock%60
		end
		-- count data
		if not textHide.count then
			-- mob kills
			data[#data+1] = combatCurKills or combatPreKills
			data[#data+1] = config.mobKills
			-- items looted
			data[#data+1] = config.countItems
		end
		-- gold info
		data[#data+1] = FmtMoney(config.moneyCash)
		data[#data+1] = FmtMoney(config.moneyItems)
		if not textHide.quality then
			for i=0,5 do
				data[#data+1] = config.countByQuality[i] or 0
				data[#data+1] = FmtMoney(config.moneyByQuality[i] or 0)
			end
		end
		local total = config.moneyCash+config.moneyItems
		data[#data+1] = FmtMoney(sSession>0 and floor(total*3600/sSession) or 0)
		data[#data+1] = FmtMoney(total)
		-- set text
		text:SetFormattedText( text_mask, unpack(data) )
		-- update timer status
		local stopped = #resets==0 and not config.lockspent and not config.sessionStart
		if stopped ~= not timer:IsPlaying() then
			if stopped then
				timer:Stop()
			else
				timer:Play()
			end
		end
	end
end

-- add reset
local function AddReset()
	local curtime = time()
	if curtime-(resets[#resets] or 0)>3 then -- ignore reset of additional instances
		config.lockspent = nil
		table.insert( resets, curtime )
		if addon:IsVisible() then
			RefreshText()
		end
	end
end

-- session start
local function SessionStart(force)
	if not config.sessionStart or force==true then
		config.sessionStart = config.sessionStart or time()
		config.moneyCash  = config.moneyCash or 0
		config.moneyItems = config.moneyItems or 0
		config.countItems = config.countItems or 0
		config.mobKills   = config.mobKills or 0
		addon:RegisterEvent("PLAYER_REGEN_DISABLED")
		addon:RegisterEvent("PLAYER_REGEN_ENABLED")
		addon:RegisterEvent("CHAT_MSG_LOOT")
		addon:RegisterEvent("CHAT_MSG_MONEY")
		addon:RegisterEvent('COMBAT_LOG_EVENT_UNFILTERED')
		RefreshText()
	end
end

-- session stop
local function SessionStop()
	if config.sessionStart then
		local curtime = time()
		config.sessionDuration = (config.sessionDuration or 0) + (curtime - (config.sessionStart or curtime))
		config.sessionStart = nil
		addon:UnregisterEvent("PLAYER_REGEN_DISABLED")
		addon:UnregisterEvent("PLAYER_REGEN_ENABLED")
		addon:UnregisterEvent("CHAT_MSG_LOOT")
		addon:UnregisterEvent("CHAT_MSG_MONEY")
		addon:UnregisterEvent('COMBAT_LOG_EVENT_UNFILTERED')
	end
end

-- session clear
local function SessionReset()
	config.sessionStart = config.sessionStart and time() or nil
	config.sessionDuration = nil
	config.mobKills   = 0
	config.moneyCash  = 0
	config.moneyItems = 0
	config.countItems = 0
	wipe(config.moneyByQuality)
	wipe(config.countByQuality)
	RefreshText()
end

-- main frame becomes visible
addon:SetScript("OnShow", function(self)
	RefreshText()
end)

-- main frame becomes invisible
addon:SetScript("OnHide", function(self)
end)

-- shift+mouse click to reset instances
addon:SetScript("OnMouseUp", function(self, button)
	if button == 'RightButton' then
		addon:ShowMenu()
	elseif IsShiftKeyDown() then -- reset instances data
		ResetInstances()
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
			local price, rarity = GetItemValue(itemLink)
			local money = price*quantity
			config.moneyItems = config.moneyItems + money
			RegisterMoney(money)
			config.moneyByQuality[rarity] = (config.moneyByQuality[rarity] or 0) + money
			config.countItems = config.countItems + quantity
			config.countByQuality[rarity] = (config.countByQuality[rarity] or 0) + quantity
			if rarity>=2 then -- display only green or superior
				print( string.format("|cFF7FFF72KiwiFarm:|r looted %sx%d %s", itemLink, quantity, FmtMoney(money) ) )
			end
			local soundID = config.soundByRarity[rarity]
			if soundID then
				PlaySoundFile(soundID, "master")
			end
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
			local copper = digits[#digits] + (digits[#digits-1] or 0)*100 + (digits[#digits-2] or 0)*10000
			config.moneyCash = config.moneyCash + copper
			RegisterMoney(copper)
		end
	end
end

-- combat start
function addon:PLAYER_REGEN_DISABLED()
	combatActive = true
	combatPreKills = combatCurKills or combatPreKills
	combatCurKills = nil
	combatTime  = time()
end

-- combat end
function addon:PLAYER_REGEN_ENABLED()
	combatActive = nil
end

-- zones management
function addon:ZONE_CHANGED_NEW_AREA()
	local ins,typ = IsInInstance()
	if ins and #resets>=RESET_MAX then -- locked but inside instance, means locked expired before estimated unlock time
		table.remove(resets,1)
	end
	if config.zones then
		if config.zones[GetZoneText()] then
			if ins then
				SessionStart()
			else
				RefreshText()
			end
			self:Show()
		else
			SessionStop()
			self:Hide()
		end
	end
	if config.sessionStart then -- to track when the instance save becomes dirty (mobs killed)
		if ins then
			self:RegisterEvent('COMBAT_LOG_EVENT_UNFILTERED')
		else
			self:UnregisterEvent('COMBAT_LOG_EVENT_UNFILTERED')
		end
	end
end

-- stop session and register automatic reset on player logout
do
	local isLogout
	hooksecurefunc("Logout", function() isLogout=true end)
	hooksecurefunc("Quit",   function() isLogout=true end)
	hooksecurefunc("CancelLogout", function() isLogout=nil end)
	function addon:PLAYER_LOGOUT()
		if isLogout then
			if config.lockspent and not IsInInstance() then
				AddReset()
			end
			SessionStop()
		end
	end
end

-- If we kill a npc inside instance a ResetInstance() is executed on player logout, so we need this to track
-- and save this hidden reset, see addon:PLAYER_LOGOUT()
function addon:COMBAT_LOG_EVENT_UNFILTERED()
	local _, eventType,_,_,_,_,_,dstGUID,_,dstFlags = CombatLogGetCurrentEventInfo()
	if eventType == 'UNIT_DIED' and band(dstFlags,COMBATLOG_OBJECT_CONTROL_NPC)~=0 then
		if not config.lockspent then
			config.lockspent = time()
			timer:Play()
		end
		config.mobKills = config.mobKills + 1
		combatCurKills = (combatCurKills or 0) + 1
	end
end

-- restore main frame position
function addon:RestorePosition()
	addon:ClearAllPoints()
	addon:SetPoint( config.framePos.anchor, UIParent, 'CENTER', config.framePos.x, config.framePos.y )
end

-- save main frame position
function addon:SavePosition()
	local p, cx, cy = config.framePos, UIParent:GetCenter()
	local x = (p.anchor:find("LEFT")   and self:GetLeft())   or (p.anchor:find("RIGHT") and self:GetRight()) or self:GetLeft()+self:GetWidth()/2
	local y = (p.anchor:find("BOTTOM") and self:GetBottom()) or (p.anchor:find("TOP")   and self:GetTop())   or self:GetTop() -self:GetHeight()/2
	p.x, p.y = x-cx, y-cy
end

-- layout main frame
local function LayoutFrame()
	-- background
	backTexture:SetColorTexture( unpack(config.backColor or COLOR_TRANSPARENT) )
	-- text headers
	text0:ClearAllPoints()
	text0:SetPoint('TOPLEFT', MARGIN, -MARGIN)
	text0:SetJustifyH('LEFT')
	text0:SetJustifyV('TOP')
	text0:SetFont(config.fontname or FONTS.Arial or STANDARD_TEXT_FONT, config.fontsize or 14, 'OUTLINE')
	PrepareText()
	-- text main data
	text:ClearAllPoints()
	text:SetPoint('TOPRIGHT', -MARGIN, -MARGIN)
	text:SetPoint('TOPLEFT', MARGIN, -MARGIN)
	text:SetJustifyH('RIGHT')
	text:SetJustifyV('TOP')
	text:SetFont(config.fontname or FONTS.Arial or STANDARD_TEXT_FONT, config.fontsize or 14, 'OUTLINE')
	RefreshText()
	-- main frame size
	addon:SetHeight( text0:GetHeight() + MARGIN*2 )
	addon:SetWidth( config.frameWidth or (text0:GetWidth() * 2.3) + MARGIN*2 )
end

-- initialize
local function Initialize()
	-- database setup
	local serverKey = GetRealmName()
	local root = KiwiFarmDB
	if not root then
		root = {}; KiwiFarmDB = root
	end
	config = root[serverKey]
	if not config then
		config = { resets = {} }; root[serverKey] = config
	end
	for k,v in pairs(DEFAULTS) do -- apply missing default values
		if config[k]==nil then
			config[k] = v
		end
	end
 	resets = config.resets
	textHide = config.textHide
	-- minimap icon
	LibStub("LibDBIcon-1.0"):Register(addonName, LibStub("LibDataBroker-1.1"):NewDataObject(addonName, {
		type  = "launcher",
		label = GetAddOnInfo( addonName, "Title"),
		icon  = "Interface\\AddOns\\KiwiFarm\\KiwiFarm",
		OnClick = function(self, button)
			if button == 'RightButton' then
				addon:ShowMenu()
			else
				addon:SetShown( not addon:IsVisible() )
			end
		end,
		OnTooltipShow = function(tooltip)
			tooltip:AddDoubleLine("Kiwi Farm", GetAddOnMetadata(addonName, "Version") )
			tooltip:AddLine("|cFFff4040Left Click|r toggle window visibility\n|cFFff4040Right Click|r open config menu", 0.2, 1, 0.2)
		end,
	}) , config.minimapIcon)
	-- timer
	timer:SetScript("OnLoop", RefreshText)
	-- events
	addon:SetScript('OnEvent', function(self,event,...)	self[event](self,event,...) end)
	addon:RegisterEvent("CHAT_MSG_SYSTEM")
	addon:RegisterEvent("ZONE_CHANGED_NEW_AREA")
	addon:RegisterEvent("PLAYER_LOGOUT")
	-- frame position
	addon:RestorePosition()
	-- frame size & appearance
	LayoutFrame()
	-- session
	if config.sessionStart then
		SessionStart(true)
	else
		RefreshText()
	end
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
SLASH_KIWIFARM1,SLASH_KIWIFARM2 = "/kfarm", "/kiwifarm"
SlashCmdList.KIWIFARM = function(args)
	local arg1,arg2,arg3 = strsplit(" ",args,3)
	arg1, arg2 = strlower(arg1 or ''), strlower(arg2 or '')
	if arg1 == 'show' then
		addon:Show()
	elseif arg1 == 'hide' then
		addon:Hide()
	elseif arg1 == 'config' then
		addon:ShowMenu()
	elseif arg1 == 'minimap' then
		config.minimapIcon.hide = not config.minimapIcon.hide
		if config.minimapIcon.hide then
			LibStub("LibDBIcon-1.0"):Hide(addonName)
		else
			LibStub("LibDBIcon-1.0"):Show(addonName)
		end
	else
		print("Kiwi Farm:")
		print("  Right-Click to display config menu.")
		print("  Shift-Click to reset instances.")
		print("  Click&Drag to move main frame.")
		print("Commands:")
		print("  /kfarm show     -- show main window")
		print("  /kfarm hide     -- hide main window")
 		print("  /kfarm config   -- display config menu")
		print("  /kfarm minimap  -- toggle minimap icon visibility")
	end
end

-- config popup menu
do
	local menuFrame = CreateFrame("Frame", "KiwiFarmPopupMenu", UIParent, "UIDropDownMenuTemplate")
	local menuColors = {}
	local function CreateColorItem(text, get, set, key)
		local item = {
			text = text, notCheckable = true, hasColorSwatch = true, hasOpacity = true,
			swatchFunc  = function() local r,g,b,a = get(); r,g,b = ColorPickerFrame:GetColorRGB(); set(r,g,b,a) end,
			opacityFunc = function() local r,g,b   = get(); set(r,g,b,1-OpacitySliderFrame:GetValue()) end,
			cancelFunc  = function(c) set(c.r, c.g, c.b, 1-c.opacity) end,
		}
		menuColors[item] = get
		return item
	end
	local function SortMenu(menu)
		table.sort(menu, function(a,b) return a.text<b.text end)
	end
	local function MenuSplit(menu)
		SortMenu(menu)
		local count, items, first, last = #menu
		if count>28 then
			for i=1,count do
				if not items or #items>=28 then
					if items then
						menu[#menu].text = strsub(first.text,1,1) .. '-' .. strsub(last.text,1,1)
					end
					items = {}
					table.insert(menu, { notCheckable= true, hasArrow = true, menuList = items } )
					first = menu[1]
				end
				last = table.remove(menu,1)
				table.insert(items, last)
			end
			menu[#menu].text = strsub(first.text,1,1) .. '-' .. strsub(last.text,1,1)
		end
	end
	local function SetBackground()
		backTexture:SetColorTexture( unpack(config.backColor or COLOR_TRANSPARENT) )
	end
	local function SetWidth(info)
		config.frameWidth = info.value~=0 and math.max( (config.frameWidth or addon:GetWidth()) + info.value, 50) or nil
		LayoutFrame()
	end
	local function SetFontSize(info)
		config.fontsize = info.value~=0 and math.max( (config.fontsize or 14) + info.value, 5) or 14
		LayoutFrame()
	end
	local function SetFont(info)
		config.fontname = info.value
		LayoutFrame()
	end
	local function AnchorChecked(info)
		return info.value == config.framePos.anchor
	end
	local function SetAnchor(info)
		config.framePos.anchor = info.value
		addon:SavePosition()
		addon:RestorePosition()
	end
	local function FontChecked(info)
		return info.value == (config.fontname or FONTS.Arial)
	end
	local function SetSound(info)
		local sound, rarity = info.value, UIDROPDOWNMENU_MENU_VALUE
		config.soundByRarity[rarity] = sound~=0 and sound or nil
		if sound~=0 then PlaySoundFile(sound, "master") end
	end
	local function SoundChecked(info)
		local sound, rarity = info.value, UIDROPDOWNMENU_MENU_VALUE
		return (config.soundByRarity[rarity] or 0) == sound
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
	local function SetItemPrice(info)
		local source, rarity = info.value, UIDROPDOWNMENU_MENU_VALUE
		config.priceByRarity[rarity] = source~='Vendor' and source or nil
 	end
	local function PriceChecked(info)
		local source, rarity = info.value, UIDROPDOWNMENU_MENU_VALUE
		return (config.priceByRarity[rarity] or "Vendor") == source
	end
	local function SetMaxPriceSource(info)
		config.priceMaxSource[info.value] = (not config.priceMaxSource[info.value]) or nil
	end
	local function MaxPriceSourceChecked(info)
		return config.priceMaxSource[info.value]
	end
	local function MoneyFmtChecked(info)
		return info.value == (config.moneyFmt or '')
	end
	local function SetMoneyFmt(info)
		config.moneyFmt = info.value~='' and info.value or nil
		RefreshText()
	end
	local function DisplayChecked(info)
		return not textHide[info.value]
	end
	local function SetDisplay(info)
		textHide[info.value] = (not textHide[info.value]) or nil
		PrepareText(); LayoutFrame(); RefreshText()
	end
	local menuSounds = {}
	local menuFonts  = {}
	local menuZones  = {}
	local itemResetNone = { text = 'None', notCheckable = true }
	local menuResets    = { { text = 'Instance Resets', notCheckable= true, isTitle = true } }
	local menuGoldDaily = {
		{ text = 'Daily Gold Earned', notCheckable= true, isTitle = true },
		{ notCheckable = true },
		{ notCheckable = true },
		{ notCheckable = true },
		{ notCheckable = true },
		{ notCheckable = true },
		{ notCheckable = true },
		{ notCheckable = true },
	}
	local menuGoldQuality = {
		{ text = 'Gold by Items Quality', notCheckable= true, isTitle = true },
		{ notCheckable = true },
		{ notCheckable = true },
		{ notCheckable = true },
		{ notCheckable = true },
		{ notCheckable = true },
		{ notCheckable = true },
	}
	local menuSources = {
		{ text = 'Vendor Price',              value = 'Vendor',                     checked = PriceChecked, func = SetItemPrice },
		{ text = 'Auctionator: Market Value', value = 'Atr:DBMarket', arg1 = 'Atr', checked = PriceChecked, func = SetItemPrice },
		{ text = 'Auctionator: Disenchant',   value = 'Atr:Destroy' , arg1 = 'Atr', checked = PriceChecked, func = SetItemPrice },
		{ text = 'TSM4: Market Value',        value = 'DBMarket',     arg1 = 'TSM', checked = PriceChecked, func = SetItemPrice },
		{ text = 'TSM4: Min Buyout',          value = 'DBMinBuyout',  arg1 = 'TSM', checked = PriceChecked, func = SetItemPrice },
		{ text = 'TSM4: Disenchant',          value = 'Destroy',      arg1 = 'TSM', checked = PriceChecked, func = SetItemPrice },
		{ text = 'Max Price',                 value = 'MaxPrice',                   checked = PriceChecked, func = SetItemPrice },
	}
	local menuMaxSources = {
		{ text = 'Vendor Price (Always active)', isNotRadio = true, checked = true },
		{ text = 'Auctionator: Market Value', value = 'Atr:DBMarket', arg1 = 'Atr', isNotRadio = true, keepShownOnClick = 1, checked = MaxPriceSourceChecked, func = SetMaxPriceSource },
		{ text = 'Auctionator: Disenchant',   value = 'Atr:Destroy',  arg1 = 'Atr', isNotRadio = true, keepShownOnClick = 1, checked = MaxPriceSourceChecked, func = SetMaxPriceSource },
		{ text = 'TSM4: Market Value',        value = 'DBMarket',     arg1 = 'TSM', isNotRadio = true, keepShownOnClick = 1, checked = MaxPriceSourceChecked, func = SetMaxPriceSource },
		{ text = 'TSM4: Min Buyout',          value = 'DBMinBuyout',  arg1 = 'TSM', isNotRadio = true, keepShownOnClick = 1, checked = MaxPriceSourceChecked, func = SetMaxPriceSource },
		{ text = 'TSM4: Disenchant',          value = 'Destroy',      arg1 = 'TSM', isNotRadio = true, keepShownOnClick = 1, checked = MaxPriceSourceChecked, func = SetMaxPriceSource },
	}
	local menuTable = {
		{ text = 'Kiwi Farm [/kfarm]', notCheckable= true, isTitle = true },
		{ text = 'Session Start',   notCheckable = true, func = SessionStart },
		{ text = 'Session Stop',   notCheckable = true, func = SessionStop  },
		{ text = 'Session Clear',   notCheckable = true, func = SessionReset },
		{ text = 'Reset Instances', notCheckable = true, func = ResetInstances },
		{ text = 'Statistics', notCheckable= true, isTitle = true },
		{ text = 'Gold/Daily',  notCheckable= true, hasArrow = true, menuList = menuGoldDaily },
		{ text = 'Gold/Qualiy', notCheckable= true, hasArrow = true, menuList = menuGoldQuality },
		{ text = 'Resets',      notCheckable= true, hasArrow = true, menuList = menuResets },
		{ text = 'Settings',        notCheckable = true, isTitle = true },
		{ text = 'Farming', notCheckable= true, hasArrow = true, menuList = {
			{ text = 'Farming Settings', notCheckable= true, isTitle = true },
			{ text = 'Display Info', notCheckable= true, hasArrow = true, menuList = {
				{ text = 'Lock&Resets',      value = 'reset',   isNotRadio = true, keepShownOnClick = 1, checked = DisplayChecked, func = SetDisplay },
				{ text = 'Mobs&Items Count', value = 'count',   isNotRadio = true, keepShownOnClick = 1, checked = DisplayChecked, func = SetDisplay },
				{ text = 'Gold by Quality',  value = 'quality', isNotRadio = true, keepShownOnClick = 1, checked = DisplayChecked, func = SetDisplay },
			} },
			{ text = 'Money Format', notCheckable = true, hasArrow = true, menuList = {
				{ text = '999|cffffd70ag|r 99|cffc7c7cfs|r 99|cffeda55fc|r', 	value = '', 							   checked = MoneyFmtChecked, func = SetMoneyFmt },
				{ text = '999|cffffd70ag|r 99|cffc7c7cfs|r', 					value = '%d|cffffd70ag|r %d|cffc7c7cfs|r', checked = MoneyFmtChecked, func = SetMoneyFmt },
				{ text = '999|cffffd70ag|r', 									value = '%d|cffffd70ag|r', 				   checked = MoneyFmtChecked, func = SetMoneyFmt },
			} },
			{ text = 'Zones', notCheckable= true, hasArrow = true, menuList = menuZones },
			{ text = 'Prices', notCheckable = true, hasArrow = true, menuList = {
				{ text = 'Prices by Quality', notCheckable = true, isTitle = true },
				{ text = FmtQuality(1), value = 1, notCheckable= true, hasArrow = true, menuList = menuSources },
				{ text = FmtQuality(2), value = 2, notCheckable= true, hasArrow = true, menuList = menuSources },
				{ text = FmtQuality(3), value = 3, notCheckable= true, hasArrow = true, menuList = menuSources },
				{ text = FmtQuality(4), value = 4, notCheckable= true, hasArrow = true, menuList = menuSources },
				{ text = FmtQuality(5), value = 5, notCheckable= true, hasArrow = true, menuList = menuSources },
				{ text = '|cFFc0c000Max Price Sources:|r', notCheckable= true, hasArrow = true, menuList = menuMaxSources }
			} },
			{ text = 'Sounds', notCheckable = true, hasArrow = true, menuList = {
				{ text = 'Looted items Sound', notCheckable = true, isTitle = true },
				{ text = FmtQuality(1), value = 1, notCheckable= true, hasArrow = true, menuList = menuSounds },
				{ text = FmtQuality(2), value = 2, notCheckable= true, hasArrow = true, menuList = menuSounds },
				{ text = FmtQuality(3), value = 3, notCheckable= true, hasArrow = true, menuList = menuSounds },
				{ text = FmtQuality(4), value = 4, notCheckable= true, hasArrow = true, menuList = menuSounds },
				{ text = FmtQuality(5), value = 5, notCheckable= true, hasArrow = true, menuList = menuSounds },
			} },
		} },
		{ text = 'Frame', notCheckable= true, hasArrow = true, menuList = {
			{ text = 'Frame Settings', notCheckable= true, isTitle = true },
			{ text = 'Frame Anchor', notCheckable= true, hasArrow = true, menuList = {
				{ text = 'Top Left',     value = 'TOPLEFT',     checked = AnchorChecked, func = SetAnchor },
				{ text = 'Top Right',    value = 'TOPRIGHT',    checked = AnchorChecked, func = SetAnchor },
				{ text = 'Bottom Left',  value = 'BOTTOMLEFT',  checked = AnchorChecked, func = SetAnchor },
				{ text = 'Bottom Right', value = 'BOTTOMRIGHT', checked = AnchorChecked, func = SetAnchor },
				{ text = 'Left',   		 value = 'LEFT',   		checked = AnchorChecked, func = SetAnchor },
				{ text = 'Right',  		 value = 'RIGHT',  		checked = AnchorChecked, func = SetAnchor },
				{ text = 'Top',    		 value = 'TOP',    		checked = AnchorChecked, func = SetAnchor },
				{ text = 'Bottom', 		 value = 'BOTTOM', 		checked = AnchorChecked, func = SetAnchor },
				{ text = 'Center', 		 value = 'CENTER', 		checked = AnchorChecked, func = SetAnchor },
			} },
			{ text = 'Frame Width', notCheckable= true, hasArrow = true, menuList = {
				{ text = 'Increase(+)',   value =  1,  notCheckable= true, keepShownOnClick=1, func = SetWidth },
				{ text = 'Decrease(-)',   value = -1,  notCheckable= true, keepShownOnClick=1, func = SetWidth },
				{ text = 'Default',       value =  0,  notCheckable= true, keepShownOnClick=1, func = SetWidth },
			} },
			{ text = 'Text Font', notCheckable= true, hasArrow = true, menuList = menuFonts },
			{ text = 'Text Size', notCheckable= true, hasArrow = true, menuList = {
				{ text = 'Increase(+)',   value =  1,  notCheckable= true, keepShownOnClick=1, func = SetFontSize },
				{ text = 'Decrease(-)',   value = -1,  notCheckable= true, keepShownOnClick=1, func = SetFontSize },
				{ text = 'Default (14)', value =  0,  notCheckable= true, keepShownOnClick=1, func = SetFontSize },
			} },
			CreateColorItem( 'Background color', function() return unpack(config.backColor) end, function(...) config.backColor = {...}; SetBackground(); end )
		} },
		{ text = 'Hide Window', notCheckable = true, func = function() addon:Hide() end },
	}
	function addon:ShowMenu()
		local media = LibStub("LibSharedMedia-3.0", true)
		-- fill sounds
		table.insert( menuSounds, { text = '[None]', value = 0, func = SetSound, checked = SoundChecked } )
		for name, key in pairs(SOUNDS) do
			table.insert( menuSounds, { text = name, value = key, func = SetSound, checked = SoundChecked } )
		end
		SortMenu(menuSounds)
		-- fill fonts
		for name, key in pairs(media and media:HashTable('font') or FONTS) do
			table.insert( menuFonts, { text = name, value = key, func = SetFont, checked = FontChecked } )
		end
		MenuSplit(menuFonts)
		-- remove non existant sources
		for _,menu in ipairs( { menuSources, menuMaxSources } ) do
			for i=#menu,1,-1 do
				if (menu[i].arg1 =='Atr' and not Atr_GetAuctionBuyout) or (menu[i].arg1 =='TSM' and not TSMAPI_FOUR) then
					table.remove(menu,i)
				end
			end
		end
		-- real show menu
		self.ShowMenu = function()
			-- refresh quality money
			for i=2,6 do
				menuGoldQuality[i].text = string.format( "%s: %s (%d)", FmtQuality(i-2), FmtMoney(config.moneyByQuality[i] or 0), config.countByQuality[i] or 0)
			end
			-- refresh daily money
			local tim, pre, key, money = time()
			for i=2,8 do
				key, pre = date("%Y/%m/%d", tim), pre and date("%m/%d", tim) or 'Today'
				money = config.moneyDaily[key] or 0
				menuGoldDaily[i].text = string.format('%s: %s', pre, money>0 and FmtMoney(money) or '-' )
				tim = tim - 86400
			end
			-- refresh resets
			local item = itemResetNone
			for i=1,5 do
				if resets[i] then
					item = menuResets[i+1] or { notCheckable = true }
					item.text = date("%H:%M:%S",resets[i])
				end
				menuResets[i+1], item = item, nil
			end
			-- refresh zones
			wipe(menuZones)
			menuZones[1] = { text = 'Farming Zones', notCheckable = true, isTitle = true }
			for zone in pairs(config.zones or {}) do
				menuZones[#menuZones+1] = { text = '(-)'..zone, value = zone, notCheckable = true, func = ZoneDel }
			end
			menuZones[#menuZones+1] = { text = '(+)Add Current Zone', notCheckable = true, func = ZoneAdd }
			-- refresh colors
			for item,get in pairs(menuColors) do
				item.r, item.g, item.b, item.opacity = get()
				item.opacity = 1 - item.opacity
			end
			-- open menu
			EasyMenu(menuTable, menuFrame, "cursor", 0 , 0, "MENU", 1)
		end
		self:ShowMenu()
	end
end
