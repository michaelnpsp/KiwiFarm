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
	mobKills             = 0,
	moneyCash            = 0,
	moneyItems           = 0,
	countItems           = 0,
	moneyDaily           = {},
	moneyByQuality       = {},
	countByQuality       = {},
	lootedItems          = {},
	priceByItem          = {},
	priceByQuality       = { [0]={vendor = true}, [1]={vendor = true}, [2]={vendor = true}, [3]={vendor = true}, [4]={vendor = true}, [5]={vendor = true}, [6]={vendor = true}, [7]={vendor = true}, [8]={vendor = true}, [9]={vendor = true} },
	notifyChatByQuality  = { [0]=nil, [1]=true, [2]=true, [3]=true, [4]=true, [5]=true, [6]=true, [7]=true, [8]=true, [9]=true },
	notifyChatPrice      = nil,
	notifySoundByQuality = {},
	notifySoundByPrice   = nil,
	notifySoundPrice     = nil,
	textHide             = { quality=true },
	backColor 	         = { 0, 0, 0, .4 },
	minimapIcon          = { hide = false },
	framePos             = { anchor = 'TOPLEFT', x = 0, y = 0 },
}

--
local time = time
local date = date
local type = type
local next = next
local unpack = unpack
local strfind = strfind
local floor = math.floor
local format = string.format
local tinsert = tinsert
local band = bit.band
local strmatch = strmatch
local IsInInstance = IsInInstance
local GetZoneText = GetZoneText
local GetItemInfo = GetItemInfo
local COMBATLOG_OBJECT_CONTROL_NPC = COMBATLOG_OBJECT_CONTROL_NPC

local config
local resets
local textHide

local combatActive
local combatTime
local combatCurKills = 0
local combatPreKills = 0

local timeLootedItems = 0 -- track changes in config.lootedItems table

-- main frame
local addon = CreateFrame('Frame', "KiwiFarm", UIParent)
addon:EnableMouse(true)
addon:SetMovable(true)
addon:RegisterForDrag("LeftButton")
addon:SetScript("OnDragStart", addon.StartMoving)
addon:SetScript("OnDragStop", function(self)
	self:StopMovingOrSizing()
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
local ZoneTitle
do
	local strcut
	if GetLocale() == "enUS" or GetLocale() == "enGB" then -- standard cut
		local strsub = strsub
		strcut = function(s,c)
			return strsub(s,1,c)
		end
	else -- utf8 cut
		local strbyte = string.byte
		strcut = function(s, c)
			local l, i = #s, 1
			while c>0 and i<=l do
				local b = strbyte(s, i)
				if     b < 192 then	i = i + 1
				elseif b < 224 then i = i + 2
				elseif b < 240 then	i = i + 3
				else				i = i + 4
				end
				c = c - 1
			end
			return s:sub(1, i-1)
		end
	end
	ZoneTitle = setmetatable( {}, { __index = function(t,k) local v=strcut(k,18); t[k]=v; return v; end } )
end

local function strfirstword(str)
	return strmatch(str, "^(.-) ") or str
end

local function FmtQuality(i)
	return format( "|c%s%s|r", select(4,GetItemQualityColor(i)), _G['ITEM_QUALITY'..i..'_DESC'] )
end

local function FmtMoney(money)
	money = money or 0
	local gold   = floor(  money / COPPER_PER_GOLD )
    local silver = floor( (money % COPPER_PER_GOLD) / COPPER_PER_SILVER )
    local copper = floor(  money % COPPER_PER_SILVER )
	return format( config.moneyFmt or "%d|cffffd70ag|r %d|cffc7c7cfs|r %d|cffeda55fc|r", gold, silver, copper)
end

local function FmtMoneyShort(money)
	local str    = ''
	local gold   = floor(  money / COPPER_PER_GOLD )
    local silver = floor( (money % COPPER_PER_GOLD) / COPPER_PER_SILVER )
    local copper = floor(  money % COPPER_PER_SILVER )
	if silver>0 then str = format( "%s %d|cffc7c7cfs|r", str, silver) end
	if copper>0 then str = format( "%s %d|cffeda55fc|r", str, copper) end
	if gold>0 or str=='' then str = format( "%d|cffffd70ag|r%s", gold, str)  end
	return strtrim(str)
end

local function FmtMoneyPlain(money)
	if money then
		local gold   = floor(  money / COPPER_PER_GOLD )
		local silver = floor( (money % COPPER_PER_GOLD) / COPPER_PER_SILVER )
		local copper = floor(  money % COPPER_PER_SILVER )
		return format( "%dg %ds %dc", gold, silver, copper)
	end
end

local function String2Copper(str)
	str = str:gsub(' ','')
	if str~='' then
		local c,s,g = tonumber(strmatch(str,"([%d,.]+)c")), tonumber(strmatch(str,"([%d,.]+)s")), tonumber(strmatch(str,"([%d,.]+)g"))
		if not (c or s or g) then
			g = tonumber(str)
		end
		return floor( (c or 0) + (s or 0)*100 + (g or 0)*10000 )
	end
end

local function RegisterMoney(money)
	local key = date("%Y/%m/%d")
	config.moneyDaily[key] = (config.moneyDaily[key] or 0) + money
end

local function RegisterItem(itemLink, itemName, quantity, money)
	local itemData = config.lootedItems[itemLink]
	if not itemData then
		itemData = { 0, 0 }
		config.lootedItems[itemLink] = itemData
		timeLootedItems = time()
	end
	itemData[1] = itemData[1] + quantity
	itemData[2] = itemData[2] + money
end

-- calculate item price
local GetItemPrice
do
	local max = math.max
	local ItemUpgradeInfo
	local function GetValue(source, itemLink, itemID, name, class, rarity, vendorPrice, userPrice)
		local price
		if source == 'user' then
			price = userPrice
		elseif source == 'vendor' then
			price = vendorPrice
		elseif source == 'Atr:DBMarket' and ItemUpgradeInfo then -- Auctionator: market
			price = Atr_GetAuctionPrice(name)
		elseif source == 'Atr:Destroy' and ItemUpgradeInfo then -- Auctionator: disenchant
			price = Atr_CalcDisenchantPrice(class, rarity, ItemUpgradeInfo:GetUpgradedItemLevel(itemLink)) -- Atr_GetDisenchantValue() is bugged cannot be used
		elseif TSMAPI_FOUR then -- TSM4 sources
			price = TSMAPI_FOUR.CustomPrice.GetValue(source, "i:"..itemID)
		end
		return price or 0
	end
	function GetItemPrice(itemLink)
		ItemUpgradeInfo = Atr_GetAuctionPrice and Atr_CalcDisenchantPrice and LibStub('LibItemUpgradeInfo-1.0',true) -- Check if auctionator is installed
		GetItemPrice = function(itemLink)
			local itemID = strmatch(itemLink, "item:(%d+):") or itemLink
			local name, _, rarity, _, _, _, _, _, _, _, vendorPrice, class = GetItemInfo(itemLink)
			local sources = config.priceByQuality[rarity or 0] or {}
			local price = 0
			for src, user in pairs(sources) do
				price = max( price, GetValue(src, itemLink, itemID, name, class, rarity, vendorPrice, user) )
			end
			return price, rarity, name
		end
		return GetItemPrice(itemLink)
	end
end

-- display farming info
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
				text_header = text_header .. format(" %s\n",FmtQuality(i));
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
		data[#data+1] = ZoneTitle[ GetZoneText() ]
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
			data[#data+1] = (remain==RESET_MAX and '|cFF00ff00') or (remain>0 and '|cFFff8000') or '|cFFff0000'
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
		tinsert( resets, curtime )
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
	wipe(config.lootedItems)
	wipe(config.moneyByQuality)
	wipe(config.countByQuality)
	RefreshText()
	timeLootedItems = time()
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
	elseif button == 'LeftButton' and IsShiftKeyDown() then -- reset instances data
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
			local price, rarity, itemName = GetItemPrice(itemLink)
			local money = price*quantity
			RegisterMoney(money)
			RegisterItem(itemLink, itemName, quantity, money)
			config.moneyItems = config.moneyItems + money
			config.moneyByQuality[rarity] = (config.moneyByQuality[rarity] or 0) + money
			config.countItems = config.countItems + quantity
			config.countByQuality[rarity] = (config.countByQuality[rarity] or 0) + quantity
			if config.notifyChatByQuality[rarity] or (config.notifyChatPrice and money>=config.notifyChatPrice) then
				print( format("|cFF7FFF72KiwiFarm:|r looted %sx%d %s", itemLink, quantity, FmtMoneyShort(money) ) )
			end
			local soundID = config.notifySoundByQuality[rarity] or (config.notifySoundPrice and money>=config.notifySoundPrice and config.notifySoundByPrice)
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
function addon:ZONE_CHANGED_NEW_AREA(event)
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
	elseif self:IsVisible() then
		RefreshText()
	end
	if config.sessionStart then -- to track when the instance save becomes dirty (mobs killed)
		if ins then
			self:RegisterEvent('COMBAT_LOG_EVENT_UNFILTERED')
		else
			self:UnregisterEvent('COMBAT_LOG_EVENT_UNFILTERED')
		end
	end
end
addon.PLAYER_ENTERING_WORLD = addon.ZONE_CHANGED_NEW_AREA

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
	local p, cx, cy = config.framePos, UIParent:GetCenter() -- we are assuming addon frame scale=1 in calculations
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
	addon:SetScript('OnEvent', function(self,event,...) self[event](self,event,...) end)
	addon:RegisterEvent("CHAT_MSG_SYSTEM")
	addon:RegisterEvent("ZONE_CHANGED_NEW_AREA")
	addon:RegisterEvent("PLAYER_ENTERING_WORLD")
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
	-- menu main frame
	local menuFrame = CreateFrame("Frame", "KiwiFarmPopupMenu", UIParent, "UIDropDownMenuTemplate")
	-- our popup menu management
	local showMenu, refreshMenu, splitMenu, wipeMenu
	do
		local function initialize( frame, level, menuList )
			local init = menuList.init
			if init then
				init(menuList)
			end
			for index=1,#menuList do
				local item = menuList[index]
				if type(item.text)=='function' then
					item.textf = item.text
				end
				if item.textf then
					item.text = item.textf(item)
				end
				if item.hasColorSwatch then
					if not item.swatchFunc then
						local get, set = item.get, item.set
						item.swatchFunc  = function() local r,g,b,a = get(item); r,g,b = ColorPickerFrame:GetColorRGB(); set(item, r,g,b,a) end
						item.opacityFunc = function() local r,g,b   = get(item); set(item, r,g,b,1-OpacitySliderFrame:GetValue()) end
						item.cancelFunc  = function(c) set(item, c.r, c.g, c.b, 1-c.opacity) end
					end
					item.r, item.g, item.b, item.opacity = item.get(item)
					item.opacity = 1 - item.opacity
				end
				item.index = index
				UIDropDownMenu_AddButton(item,level)
			end
		end
		-- clear menu table, maintaining special control fields
		function wipeMenu(menu)
			local init = menu.init;	wipe(menu); menu.init = init
		end
		-- split a big menu items table in several submenus
		function splitMenu(menu, field)
			field = field or 'text'
			table.sort(menu, function(a,b) return a[field]<b[field] end )
			local count, items, first, last = #menu
			if count>28 then
				for i=1,count do
					if not items or #items>=28 then
						if items then
							menu[#menu].text = strfirstword(first[field]) .. ' - ' .. strfirstword(last[field])
						end
						items = {}
						tinsert(menu, { notCheckable= true, hasArrow = true, menuList = items } )
						first = menu[1]
					end
					last = table.remove(menu,1)
					tinsert(items, last)
				end
				menu[#menu].text = strfirstword(first[field]) .. ' - ' .. strfirstword(last[field])
			end
		end
		-- refresh last open level menu
		function refreshMenu()
			local frame = UIDROPDOWNMENU_OPEN_MENU
			if frame and frame.menuList and frame:IsShown() then
				local parent, level, value = frame:GetParent(), UIDROPDOWNMENU_MENU_LEVEL, UIDROPDOWNMENU_MENU_VALUE
				HideDropDownMenu(level)
				ToggleDropDownMenu(level, value, nil, nil, nil, nil, frame.menuList, parent)
			end
		end
		-- show my popup menu
		function showMenu(menuList, menuFrame, anchor, x, y, autoHideDelay )
			menuFrame.displayMode = "MENU"
			UIDropDownMenu_Initialize(menuFrame, initialize, "MENU", nil, menuList);
			ToggleDropDownMenu(1, nil, menuFrame, anchor, x, y, menuList, nil, autoHideDelay);
		end
	end
	-- misc functions
	local function InitPriceSources(menu)
		for i=#menu,1,-1 do
			if (menu[i].arg1 =='Atr' and not Atr_GetAuctionPrice) or (menu[i].arg1 =='TSM' and not TSMAPI_FOUR) then
				table.remove(menu,i)
			end
		end
		return true -- means do not call the function anymore
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
	local function AnchorChecked(info)
		return info.value == config.framePos.anchor
	end
	local function SetAnchor(info)
		config.framePos.anchor = info.value
		addon:SavePosition()
		addon:RestorePosition()
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
	local function MinPriceChecked(info)
		return config[info.arg1]~=nil
	end
	local function GetMinPriceText(info)
		return config[info.arg1] and "Price above: "..FmtMoneyShort(config[info.arg1]) or "Minimum Price"
	end
	local function SetMinPrice(info)
		addon:EditDialog('|cFF7FFF72KiwiFarm|r\n Set the minimum price to display looted items in chat:', FmtMoneyPlain(config[info.arg1]), function(v)
			v = String2Copper(v) or 0
			config[info.arg1] = v>0 and v or nil
		end)
	end
	local function NotifyQualityChecked(info)
		return config.notifyChatByQuality[info.value]
	end
	local function SetNotifyQuality(info)
		config.notifyChatByQuality[info.value] = (not config.notifyChatByQuality[info.value]) or nil
	end
	-- menu: quality sources
	local menuQualitySources
	do
		local function checked(info)
			return config.priceByQuality[UIDROPDOWNMENU_MENU_VALUE][info.value]
		end
		local function set(info)
			local sources = config.priceByQuality[UIDROPDOWNMENU_MENU_VALUE]
			sources[info.value] = (not sources[info.value]) or nil
		end
		menuQualitySources = {
			{ text = 'Vendor Price',              value = 'vendor',                     isNotRadio = true, keepShownOnClick = 1, checked = checked, func = set },
			{ text = 'Auctionator: Market Value', value = 'Atr:DBMarket', arg1 = 'Atr', isNotRadio = true, keepShownOnClick = 1, checked = checked, func = set },
			{ text = 'Auctionator: Disenchant',   value = 'Atr:Destroy' , arg1 = 'Atr', isNotRadio = true, keepShownOnClick = 1, checked = checked, func = set },
			{ text = 'TSM4: Market Value',        value = 'DBMarket',     arg1 = 'TSM', isNotRadio = true, keepShownOnClick = 1, checked = checked, func = set },
			{ text = 'TSM4: Min Buyout',          value = 'DBMinBuyout',  arg1 = 'TSM', isNotRadio = true, keepShownOnClick = 1, checked = checked, func = set },
			{ text = 'TSM4: Disenchant',          value = 'Destroy',      arg1 = 'TSM', isNotRadio = true, keepShownOnClick = 1, checked = checked, func = set },
			init = InitPriceSources
		}
	end
	-- menus: item sources, price sources
	local menuPriceItems, menuItemSources
	do
		local function setItemPriceSource(itemLink, source, value)
			local sources = config.priceByItem[itemLink]
			if value then
				if not sources then
					sources = {}; config.priceByItem[itemLink] = sources
					wipeMenu(menuPriceItems)
				end
				sources[source] = value
			elseif sources then
				sources[source] = nil
				if not next(sources) then
					C_Timer.After(.1, function()
						addon:ConfirmDialog( format("%s\nThis item has no defined price. Do you want to delete this item from the price source list?",itemLink), function()
							config.priceByItem[itemLink] = nil
							wipeMenu(menuPriceItems)
						end )
					end )
				end
			end
		end
		local function getItemPriceSource(itemLink, source)
			local sources  = config.priceByItem[itemLink]
			return sources and sources[source]
		end
		local function checked(info)
			return getItemPriceSource(UIDROPDOWNMENU_MENU_VALUE, info.value)
		end
		local function set(info)
			local itemLink, empty = UIDROPDOWNMENU_MENU_VALUE
			if info.value=='user' then
				local price    = FmtMoneyPlain( getItemPriceSource(itemLink,'user') ) or ''
				addon:EditDialog('|cFF7FFF72KiwiFarm|r\n Set a custom price for:\n' .. itemLink, price, function(v)
					setItemPriceSource(itemLink, 'user', String2Copper(v))
				end)
			else
				setItemPriceSource( itemLink, info.value , not getItemPriceSource(itemLink, info.value) )
			end
		end
		local function getText(info)
			local price = getItemPriceSource(UIDROPDOWNMENU_MENU_VALUE,'user')
			return format( 'Price: %s', price and FmtMoneyShort(price) or 'Not Defined')
		end
		-- menu: item price sources
		menuItemSources = {
			{ text = getText,	  				  value = 'user',         				isNotRadio = true, keepShownOnClick = 1, checked = checked, func = set },
			{ text = 'Vendor Price',              value = 'vendor',                     isNotRadio = true, keepShownOnClick = 1, checked = checked, func = set },
			{ text = 'Auctionator: Market Value', value = 'Atr:DBMarket', arg1 = 'Atr', isNotRadio = true, keepShownOnClick = 1, checked = checked, func = set },
			{ text = 'Auctionator: Disenchant',   value = 'Atr:Destroy' , arg1 = 'Atr', isNotRadio = true, keepShownOnClick = 1, checked = checked, func = set },
			{ text = 'TSM4: Market Value',        value = 'DBMarket',     arg1 = 'TSM', isNotRadio = true, keepShownOnClick = 1, checked = checked, func = set },
			{ text = 'TSM4: Min Buyout',          value = 'DBMinBuyout',  arg1 = 'TSM', isNotRadio = true, keepShownOnClick = 1, checked = checked, func = set },
			{ text = 'TSM4: Disenchant',          value = 'Destroy',      arg1 = 'TSM', isNotRadio = true, keepShownOnClick = 1, checked = checked, func = set },
			init = InitPriceSources,
		}
		-- menu: individual items prices
		menuPriceItems = { init = function(menu)
			if not menu[1] then
				wipeMenu(menu)
				for itemLink,sources in pairs(config.priceByItem) do
					local name = strmatch(itemLink, '%|h%[(.+)%]%|h')
					tinsert( menu, { text = itemLink, value = itemLink, arg1 = name, notCheckable = true, hasArrow = true, menuList = menuItemSources } )
				end
				splitMenu(menu, 'arg1')
			end
		end	}
	end
	-- menu: looted items
	local menuLootedItems
	do
		local function getText(info)
			local data = config.lootedItems[info.value]
			return data and format("%sx%d %s", info.value, data[1], FmtMoneyShort(data[2])) or info.value
		end
		menuLootedItems = { init = function(menu)
			if timeLootedItems>(menu.time or -1) then
				wipeMenu(menu)
				for itemLink, data in pairs(config.lootedItems) do
					local name = strmatch(itemLink, '%|h%[(.+)%]%|h')
					tinsert( menu, { text = getText, value = itemLink, arg1 = name, notCheckable = true, hasArrow = true, menuList = menuItemSources } )
				end
				splitMenu(menu, 'arg1')
				menu.time = timeLootedItems
			end
		end }
	end
	-- menu: zones
	local menuZones
	do
		local function ZoneAdd()
			local zone = GetZoneText()
			config.zones = config.zones or {}
			config.zones[zone] = true
			addon:ZONE_CHANGED_NEW_AREA()
			wipeMenu(menuZones)
		end
		local function ZoneDel(info)
			config.zones[info.value] = nil
			if not next(config.zones) then config.zones = nil end
			addon:ZONE_CHANGED_NEW_AREA()
			wipeMenu(menuZones)
		end
		menuZones = { init = function(menu)
			if not menu[1] then
				for zone in pairs(config.zones or {}) do
					menu[#menu+1] = { text = '(-)'..zone, value = zone, notCheckable = true, func = ZoneDel }
				end
				menu[#menu+1] = { text = '(+)Add Current Zone', notCheckable = true, func = ZoneAdd }
			end
		end	}
	end
	-- menu: resets
	local menuResets = { init = function(menu)
		local item = { text = 'None', notCheckable = true }
		for i=1,5 do
			if resets[i] then
				item = menu[i] or { notCheckable = true }
				item.text = date("%H:%M:%S",resets[i])
			end
			menu[i], item = item, nil
		end
	end	}
	-- menu: gold earned by item quality
	local menuGoldQuality = { init = function(menu)
		for i=1,5 do
			menu[i] = menu[i] or { notCheckable = true }
			menu[i].text = format( "%s: %s (%d)", FmtQuality(i-1), FmtMoney(config.moneyByQuality[i-1] or 0), config.countByQuality[i-1] or 0)
		end
	end }
	-- menu: gold earned by day
	local menuGoldDaily = {	init = function(menu)
		local tim, pre, key, money = time()
		for i=1,7 do
			menu[i] = menu[i] or { notCheckable = true }
			key, pre = date("%Y/%m/%d", tim), pre and date("%m/%d", tim) or 'Today'
			money = config.moneyDaily[key] or 0
			menu[i].text = format('%s: %s', pre, money>0 and FmtMoney(money) or '-' )
			tim = tim - 86400
		end
	end	}
	-- menu: sounds
	local menuSounds
	do
		local function set(info)
			local sound, rarity = info.value, UIDROPDOWNMENU_MENU_VALUE
			if rarity>=0 then
				config.notifySoundByQuality[rarity] = sound~=0 and sound or nil
			else
				config.notifySoundByPrice = sound~=0 and sound or nil
			end
			if sound~=0 then PlaySoundFile(sound, "master") end
		end
		local function checked(info)
			local sound, rarity = info.value, UIDROPDOWNMENU_MENU_VALUE
			if rarity>=0 then
				return (config.notifySoundByQuality[rarity] or 0) == sound
			else
				return (config.notifySoundByPrice or 0) == sound
			end
		end
		menuSounds = { init = function(menu)
			tinsert( menu, { text = '[None]', value = 0, func = set, checked = checked } )
			for name, key in pairs(SOUNDS) do
				tinsert( menu, { text = name, value = key, func = set, checked = checked } )
			end
			table.sort(menu, function(a,b) return a.text<b.text end)
			menu.init = nil -- do not call this init function anymore
		end }
	end
	-- menu: fonts
	local menuFonts
	do
		local function set(info)
			config.fontname = info.value; LayoutFrame()
		end
		local function checked(info)
			return info.value == (config.fontname or FONTS.Arial)
		end
		menuFonts  = { init = function(menu)
			local media = LibStub("LibSharedMedia-3.0", true)
			for name, key in pairs(media and media:HashTable('font') or FONTS) do
				tinsert( menu, { text = name, value = key, func = set, checked = checked } )
			end
			splitMenu(menu)
			menu.init = nil -- do not call this init function anymore
		end }
	end
	-- menu: main
	local menuMain = {
		{ text = 'Kiwi Farm [/kfarm]', notCheckable = true, isTitle = true },
		{ text = 'Session Start',      notCheckable = true, func = SessionStart },
		{ text = 'Session Stop',       notCheckable = true, func = SessionStop  },
		{ text = 'Session Clear',      notCheckable = true, func = SessionReset },
		{ text = 'Reset Instances',    notCheckable = true, func = ResetInstances },
		{ text = 'Statistics',         notCheckable = true, isTitle = true },
		{ text = 'Looted Items',       notCheckable = true, hasArrow = true, menuList = menuLootedItems },
		{ text = 'Gold by Qualiy',     notCheckable = true, hasArrow = true, menuList = menuGoldQuality },
		{ text = 'Gold by Day',        notCheckable = true, hasArrow = true, menuList = menuGoldDaily },
		{ text = 'Resets',             notCheckable = true, hasArrow = true, menuList = menuResets },
		{ text = 'Settings',           notCheckable = true, isTitle = true },
		{ text = 'Farming', notCheckable= true, hasArrow = true, menuList = {
			{ text = 'Display Info', notCheckable= true, hasArrow = true, menuList = {
				{ text = 'Lock&Resets',      value = 'reset',   isNotRadio = true, keepShownOnClick = 1, checked = DisplayChecked, func = SetDisplay },
				{ text = 'Mobs&Items Count', value = 'count',   isNotRadio = true, keepShownOnClick = 1, checked = DisplayChecked, func = SetDisplay },
				{ text = 'Gold by Quality',  value = 'quality', isNotRadio = true, keepShownOnClick = 1, checked = DisplayChecked, func = SetDisplay },
			} },
			{ text = 'Price Sources', notCheckable = true, hasArrow = true, menuList = {
				{ text = FmtQuality(1), value = 1, notCheckable= true, hasArrow = true, menuList = menuQualitySources },
				{ text = FmtQuality(2), value = 2, notCheckable= true, hasArrow = true, menuList = menuQualitySources },
				{ text = FmtQuality(3), value = 3, notCheckable= true, hasArrow = true, menuList = menuQualitySources },
				{ text = FmtQuality(4), value = 4, notCheckable= true, hasArrow = true, menuList = menuQualitySources },
				{ text = FmtQuality(5), value = 5, notCheckable= true, hasArrow = true, menuList = menuQualitySources },
				{ text = 'Individual Items', notCheckable= true, hasArrow = true, menuList = menuPriceItems },

			} },
			{ text = 'Farming Zones', notCheckable= true, hasArrow = true, menuList = menuZones },
			{ text = 'Money Format', notCheckable = true, hasArrow = true, menuList = {
				{ text = '999|cffffd70ag|r 99|cffc7c7cfs|r 99|cffeda55fc|r', 	value = '', 							   checked = MoneyFmtChecked, func = SetMoneyFmt },
				{ text = '999|cffffd70ag|r 99|cffc7c7cfs|r', 					value = '%d|cffffd70ag|r %d|cffc7c7cfs|r', checked = MoneyFmtChecked, func = SetMoneyFmt },
				{ text = '999|cffffd70ag|r', 									value = '%d|cffffd70ag|r', 				   checked = MoneyFmtChecked, func = SetMoneyFmt },
			} },
			{ text = 'Notify: Chat', notCheckable = true, hasArrow = true, menuList = {
				{ text = FmtQuality(0), value = 0, isNotRadio = true, keepShownOnClick = 1, checked = NotifyQualityChecked, func = SetNotifyQuality },
				{ text = FmtQuality(1), value = 1, isNotRadio = true, keepShownOnClick = 1, checked = NotifyQualityChecked, func = SetNotifyQuality },
				{ text = FmtQuality(2), value = 2, isNotRadio = true, keepShownOnClick = 1, checked = NotifyQualityChecked, func = SetNotifyQuality },
				{ text = FmtQuality(3), value = 3, isNotRadio = true, keepShownOnClick = 1, checked = NotifyQualityChecked, func = SetNotifyQuality },
				{ text = FmtQuality(4), value = 4, isNotRadio = true, keepShownOnClick = 1, checked = NotifyQualityChecked, func = SetNotifyQuality },
				{ text = FmtQuality(5), value = 5, isNotRadio = true, keepShownOnClick = 1, checked = NotifyQualityChecked, func = SetNotifyQuality },
				{ text = GetMinPriceText, isNotRadio = true, checked = MinPriceChecked, arg1 = "notifyChatPrice", func = SetMinPrice },
			} },
			{ text = 'Notify: Sounds', notCheckable = true, hasArrow = true, menuList = {
				{ text = FmtQuality(1), value = 1, notCheckable= true, hasArrow = true, menuList = menuSounds },
				{ text = FmtQuality(2), value = 2, notCheckable= true, hasArrow = true, menuList = menuSounds },
				{ text = FmtQuality(3), value = 3, notCheckable= true, hasArrow = true, menuList = menuSounds },
				{ text = FmtQuality(4), value = 4, notCheckable= true, hasArrow = true, menuList = menuSounds },
				{ text = FmtQuality(5), value = 5, notCheckable= true, hasArrow = true, menuList = menuSounds },
				{ text = GetMinPriceText,	value = -1, notCheckable = true, arg1 = "notifySoundPrice", func = SetMinPrice, hasArrow = true, menuList = menuSounds },
			} },
		} },
		{ text = 'Frame', notCheckable= true, hasArrow = true, menuList = {
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
				{ text = 'Increase(+)',  value =  1,  notCheckable= true, keepShownOnClick=1, func = SetFontSize },
				{ text = 'Decrease(-)',  value = -1,  notCheckable= true, keepShownOnClick=1, func = SetFontSize },
				{ text = 'Default (14)', value =  0,  notCheckable= true, keepShownOnClick=1, func = SetFontSize },
			} },
			{ text ='Background color ', notCheckable = true, hasColorSwatch = true, hasOpacity = true, get = function() return unpack(config.backColor) end, set = function(info, ...) config.backColor = {...}; SetBackground(); end }
		} },
		{ text = 'Hide Window', notCheckable = true, func = function() addon:Hide() end },
	}
	function addon:ShowMenu()
		showMenu(menuMain, menuFrame, "cursor", 0 , 0, 5)
	end
end

-- Dialogs
do
	local dummy = function() end
	StaticPopupDialogs["KIWIFARM_DIALOG"] = { timeout = 0, whileDead = 1, hideOnEscape = 1, button1 = ACCEPT, button2 = CANCEL }

	function addon:ShowDialog(message, textDefault, funcAccept, funcCancel, textAccept, textCancel)
		local t = StaticPopupDialogs["KIWIFARM_DIALOG"]
		t.OnShow = function (self) if textDefault then self.editBox:SetText(textDefault) end; self:SetFrameStrata("TOOLTIP") end
		t.OnHide = function(self) self:SetFrameStrata("DIALOG")	end
		t.hasEditBox = textDefault and true or nil
		t.text = message
		t.button1 = funcAccept and (textAccept or ACCEPT) or nil
		t.button2 = funcCancel and (textCancel or CANCEL) or nil
		t.OnCancel = funcCancel
		t.OnAccept = funcAccept and function (self)	funcAccept( textDefault and self.editBox:GetText() ) end or nil
		StaticPopup_Show ("KIWIFARM_DIALOG")
	end

	function addon:MessageDialog(message, funcAccept)
		addon:ShowDialog(message, nil, funcAccept or dummy)
	end

	function addon:ConfirmDialog(message, funcAccept, funcCancel, textAccept, textCancel)
		self:ShowDialog(message, nil, funcAccept, funcCancel or dummy, textAccept, textCancel )
	end

	function addon:EditDialog(message, text, funcAccept, funcCancel)
		self:ShowDialog(message, text or "", funcAccept, funcCancel or dummy)
	end
end
