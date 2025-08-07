-- ============================================================================
-- KiwiFarm (C) 2019 MiCHaEL
-- ============================================================================

local addonName = ...

-- main frame
local addon = CreateFrame('Frame', "KiwiFarm", UIParent, BackdropTemplateMixin and "BackdropTemplate")

-- locale
local L = LibStub('AceLocale-3.0'):GetLocale('KiwiFarm', true)

-- game version
local VERSION = select(4,GetBuildInfo())
local VANILA  = VERSION<30000
local CLASSIC = VERSION<90000
local RETAIL  = VERSION>=90000

-- addon version
local GetAddOnInfo = C_AddOns and C_AddOns.GetAddOnInfo or GetAddOnInfo
local GetAddOnMetadata = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
local versionToc = GetAddOnMetadata(addonName, "Version")
local versionStr = (versionToc=='\@project-version\@' and 'Dev' or versionToc)

-- player GUID
local playerGUID = UnitGUID("player")

-- addon icon
local iconTexture = "Interface\\AddOns\\KiwiFarm\\KiwiFarm.tga"

-- database keys
local serverKey = GetRealmName()
local charKey   = UnitName("player") .. " - " .. serverKey

-- max player level by exapansion (not using game table because does not exist in Shadowlands)
local MAX_PLAYER_LEVEL_TABLE = {
	[0] = 60,  -- Vanilla
	[1] = 70,  -- TBC
	[2] = 80,  -- Wotlk
	[3] = 85,  -- Cataclism
	[4] = 90,  -- MoP
	[5] = 100, -- WoD
	[6] = 110, -- Legion
	[7] = 120, -- BoA,
	[8] = 60,  -- ShadowLands
	[9] = 70,  -- Dragonflight
	[10] = 80, -- TWW
}
local isPlayerLeveling
do
	-- local isSoD = C_Seasons and C_Seasons.GetActiveSeason and C_Seasons.GetActiveSeason()==2 -- season of discovery
	local level = UnitLevel('player')
	local levelMax = (MAX_PLAYER_LEVEL_TABLE[GetExpansionLevel()] or 0)
	isPlayerLeveling = level < levelMax
end

-- default values
local RESET_MAX = VANILA and 5 or 10
local RESET_DAY = 30
local COLOR_WHITE = { 1,1,1,1 }
local COLOR_TRANSPARENT = { 0,0,0,0 }
local ITEM_QUALITY_COLORS = ITEM_QUALITY_COLORS
local FONTS = (GetLocale() == 'zhCN') and {
	Arial = 'Fonts\\ARHei.TTF',
	FrizQT = 'Fonts\\ARHei.TTF',
	Morpheus = 'Fonts\\ARHei.TTF',
	Skurri = 'Fonts\\ARHei.TTF',
	} or {
	Arial = 'Fonts\\ARIALN.TTF',
	FrizQT = 'Fonts\\FRIZQT__.TTF',
	Morpheus = 'Fonts\\MORPHEUS.TTF',
	Skurri = 'Fonts\\SKURRI.TTF',
}
local SOUNDS = {
	["Auction Window Open"] = 567482,
	["Auction Window Close"] = 567499,
	["Coin" ] = 567428,
	["Money"] = 567483,
	["Level Up"] = 569593,
	["Pick Up Gems"] = 567568,
	["Player Invite"] = 567451,
	["Put Down Gems"] = 567574,
	["PvP Enter Queue"] = 568587,
	["PvP Through Queue"] =	568011,
	["Raid Warning"] =567397,
	["Ready Check"] = 567478,
	["Quest List Open"] = 567504,
}
local BORDERS = {
	["None"] = [[]],
	["Blizzard Tooltip"] = [[Interface\Tooltips\UI-Tooltip-Border]],
	["Blizzard Party"] = [[Interface\CHARACTERFRAME\UI-Party-Border]],
	["Blizzard Dialog"] = [[Interface\DialogFrame\UI-DialogBox-Border]],
	["Blizzard Dialog Gold"] = [[Interface\DialogFrame\UI-DialogBox-Gold-Border]],
	["Blizzard Chat Bubble"] = [[Interface\Tooltips\ChatBubble-Backdrop]],
	["Blizzard Achievement Wood"] = [[Interface\AchievementFrame\UI-Achievement-WoodBorder]],
}

local DEFROOT = {
	profilePerChar = {},
}

local DEFSERVER = {
	leveling = {}, 	-- leveling info per character
	resetData = VANILA and {}, -- reset data per character for classic
	resets    = (not VANILA) and {count=0,countd=0}, -- reset data per server for retail
	resetsd   = (not VANILA) and {}, -- reset data per server for retail
}

local DEFRESET = {
	resets  = {count=0,countd=0}, -- resets per hour
	resetsd = {}, -- resets per day  (max 30, only for classic)
}

local DEFDATA = {
	-- money
	moneyCash      = 0,
	moneyItems     = 0,
	moneyQuests    = 0,
	moneyByQuality = {},
	-- items
	countItems     = 0,
	countByQuality = {},
	lootedItems    = {},
	-- mobs
	countMobs      = 0,
	killedMobs     = {},
}

-- database defaults
local DEFCONFIG = {
	-- data/stats
	session = {},
	total   = {},
	daily   = {},
	zone    = {},
	-- fields blacklists
	collect = { total = {}, daily = {}, zone = {} },
	-- reset chat notification
	resetsNotify = {},
	-- prices
	priceByItem = {},
	priceByQuality = { [0]={vendor=true}, [1]={vendor=true}, [2]={vendor=true}, [3]={vendor=true}, [4]={vendor=true}, [5]={vendor=true} },
	ignoreEnchantingMats = nil,
	-- loot notification
	notifyArea = nil,
	notify = { [1]={chat=0}, [2]={chat=0}, [3]={chat=0}, [4]={chat=0}, [5]={chat=0}, sound={} },
	-- session control, farming zones
	farmZones = nil,
	farmDisableZones = nil,
	farmAutoStart = nil,
	farmAutoFinish = nil,
	-- appearance
	visible   = true, -- main frame visibility
	moneyFmt  = nil,
	disabled  = { quality=true }, -- disabled text sections
	backColor = { 0, 0, 0, .4 },
	borderColor = { 1, 1, 1, 1 },
	borderTexture = nil,
	fontName  = nil,
	fontsize  = nil,
	frameMargin = 4,
	frameStrata = nil,
	framePos  = { anchor = 'TOPLEFT', x = 0, y = 0 },
	-- minimap icon
	minimapIcon = { hide = false },
}

-- local references
local time = time
local date = date
local type = type
local next = next
local print = print
local pairs = pairs
local ipairs = ipairs
local unpack = unpack
local tinsert = tinsert
local tremove = tremove
local tonumber = tonumber
local gsub = gsub
local strfind = strfind
local strlower = strlower
local max = math.max
local floor = math.floor
local format = string.format
local band = bit.band
local strmatch = strmatch
local GetZoneText = GetZoneText
local IsInInstance = IsInInstance
local GetInstanceInfo = GetInstanceInfo
local GetItemInfo = GetItemInfo or C_Item.GetItemInfo
local UnitXP = UnitXP
local UnitXPMax = UnitXPMax
local COPPER_PER_GOLD = COPPER_PER_GOLD
local COPPER_PER_SILVER = COPPER_PER_SILVER

-- database references
local root     -- root database table for all servers and chars
local server   -- database realtm table
local config   -- char-server data table
local session  -- config.session
local disabled -- config.disabled   texts table
local notify   -- config.notify     notifications table
local collect  -- config.collect
local leveling -- server.leveling[charKey]  leveling info
local resets   -- server.resets  | server.resetData[charKey].resets   instance resets table
local resetsd  -- server.resetsd | server.resetData[charKey].resetsd  instance resets table

-- miscellaneous variables
local inInstance
local curZoneName = ''
local combatActive
local combatCurKills = 0
local combatPreKills = 0
local timeLootedItems = 0 -- track changes in config.lootedItems table
local combatStartXP = 0
local enemyGUIDS = {}

-- main frame elements
local textl   -- left text
local textr   -- right text
local timer   -- update timer

-- ============================================================================
-- utils & misc functions
-- ============================================================================

local function InitDB(dst, src, reset, norecurse)
	if type(dst)~='table' then
		dst = {}
	elseif reset then
		wipe(dst)
	end
	if src then
		for k,v in pairs(src) do
			if type(v)=="table" and not norecurse then
				dst[k] = InitDB(dst[k] or {}, v)
			elseif dst[k]==nil then
				dst[k] = v
			end
		end
	end
	return dst
end

local function InitKeyDB(db, key, src, reset, norecurse)
	if db[key]==nil then db[key] = {}; end
	return InitDB( db[key], src, reset, norecurse )
end

local function CreateDB()
	local root   = InitKeyDB( _G, "KiwiFarmDB", DEFROOT)
	local server = InitKeyDB( root, serverKey, DEFSERVER)
	local config = InitKeyDB( root, root.profilePerChar[charKey] and charKey or serverKey, DEFCONFIG, false, true)
	InitDB(config.session, DEFDATA)
	InitDB(config.total, DEFDATA)
	if VANILA then -- move resets per realm to resets per char (due to blizzard hotfix) but only in classic version
		local char = InitKeyDB( server.resetData, charKey, DEFRESET )
		char.resetsd = server.resetsd or char.resetsd
		char.resets = server.resets or char.resets
		char.resets.count = char.resets.count or 0
		char.resets.countd = char.resets.countd or 0
		server.resets  = nil
		server.resetsd = nil
	end
	if not config.__version then
		for k,v in pairs(config.zone) do
			v.moneyQuests = v.moneyQuests or 0
		end
		for k,v in pairs(config.daily) do
			v.moneyQuests = v.moneyQuests or 0
		end
		config.__version = 1
	end
	return  root, server, config
end

local function AddDB(dst, src, blacklist)
	if dst then
		for k,v in pairs(src) do
			if not (blacklist and blacklist[k]) then
				local typ = type(v)
				if typ=="table" then
					dst[k] = AddDB(dst[k] or {}, v)
				elseif typ=='number' then
					dst[k] = (dst[k] or 0) + v
				end
			end
		end
		return dst
	end
end

local function GetZoneDB(key)
	key = key or curZoneName
	if key and key~='' then
		local data = config.zone[key]
		if not data then
			data = InitDB({ _type = 'zone', _key = key }, DEFDATA)
			config.zone[key] = data
		end
		return data
	end
end

local function GetDailyDB(datetime)
	local key  = date("%Y/%m/%d", datetime)
	local data = config.daily[key]
	if not data then
		data = InitDB({ _type = 'daily', _key = key }, DEFDATA)
		config.daily[key] = data
	end
	return data
end

local function IsDungeon()
	local _,typ = GetInstanceInfo()
	return typ=='party' or typ=='raid'
end

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

local function GetSessionGeneralStats()
	local curtime  = time()
	local duration = curtime - (session.startTime or curtime) + (session.duration or 0)
	local total    = session.moneyCash+session.moneyItems+session.moneyQuests
	local hourly   = duration>0 and floor(total*3600/duration) or 0
	local m0, s0   = floor(duration/60), duration%60
	local h0, m0   = floor(m0/60), m0%60
	return total, hourly, session.moneyCash, session.moneyItems, session.moneyQuests, h0, m0, s0
end

-- text format functions
local function strfirstword(str)
	return strmatch(str, "^(.-) ") or str
end

local function GetItemQualityColorHex(i)
	local color = ITEM_QUALITY_COLORS[i]
	return color and color.hex or '|cFFffffff'
end

local function FmtQuality(i)
	return format( "%s%s|r", GetItemQualityColorHex(i), _G['ITEM_QUALITY'..i..'_DESC'] )
end

local function FmtDuration(seconds)
	local m,s = floor(seconds/60), seconds%60
	local h,m = floor(m/60), m%60
	local d,h = floor(h/24), h%24
	if d>0 then
		return format("%dd %dh %dm %ds",d,h,m,s)
	elseif h>0 then
		return format("%dh %dm %ds",h,m,s)
	else
		return format("%dm %ds",m,s)
	end
end

local function FmtMoney(money)
	money = money or 0
	local gold   = floor(  money / COPPER_PER_GOLD )
    local silver = floor( (money % COPPER_PER_GOLD) / COPPER_PER_SILVER )
    local copper = floor(  money % COPPER_PER_SILVER )
	return format( config.moneyFmt or "%d|cffffd70ag|r %d|cffc7c7cfs|r %d|cffeda55fc|r", gold, silver, copper)
end

local function FmtMoneyPlain(money)
	money = money or 0
	local gold   = floor(  money / COPPER_PER_GOLD )
    local silver = floor( (money % COPPER_PER_GOLD) / COPPER_PER_SILVER )
    local copper = floor(  money % COPPER_PER_SILVER )
	return format( config.moneyFmt or "%dg %ds %dc", gold, silver, copper)
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
	str = strlower(gsub(str,' ',''))
	if str~='' then
		local c,s,g = tonumber(strmatch(str,"([%d,.]+)c")), tonumber(strmatch(str,"([%d,.]+)s")), tonumber(strmatch(str,"([%d,.]+)g"))
		if not (c or s or g) then
			g = tonumber(str)
		end
		return floor( (c or 0) + (s or 0)*100 + (g or 0)*10000 )
	end
end

-- fonts
local function SetTextFont(widget, name, size, flags)
	widget:SetFont(name or FONTS.Arial or STANDARD_TEXT_FONT, size or 14, flags or 'OUTLINE')
	if not widget:GetFont() then
		widget:SetFont(STANDARD_TEXT_FONT, size or 14, flags or 'OUTLINE')
	end
end

-- group or raid members unit
local GetGroupRaidMembers
do
	local party = { 'party1', 'party2', 'party3', 'party4' }
	local raid  = {}
	for i=1,40 do raid[#raid+1] = 'raid'..i; end
	function GetGroupRaidMembers()
		if IsInRaid() then
			return raid
		elseif GetNumGroupMembers()>0 then
			return party
		end
	end
end

-- dialogs
do
	local DUMMY = function() end
	StaticPopupDialogs["KIWIFARM_DIALOG"] = { timeout = 0, whileDead = 1, hideOnEscape = 1, button1 = ACCEPT, button2 = CANCEL }

	function addon:ShowDialog(message, textDefault, funcAccept, funcCancel, textAccept, textCancel)
		local t = StaticPopupDialogs["KIWIFARM_DIALOG"]
		t.OnShow = function (self) if textDefault then (self.editBox or self:GetEditBox()):SetText(textDefault) end; self:SetFrameStrata("TOOLTIP") end
		t.OnHide = function(self) self:SetFrameStrata("DIALOG")	end
		t.hasEditBox = textDefault and true or nil
		t.text = message
		t.button1 = funcAccept and (textAccept or ACCEPT) or nil
		t.button2 = funcCancel and (textCancel or CANCEL) or nil
		t.OnCancel = funcCancel
		t.OnAccept = funcAccept and function (self) funcAccept( textDefault and (self.editBox or self:GetEditBox()):GetText() ) end or nil
		StaticPopup_Show ("KIWIFARM_DIALOG")
	end

	function addon:MessageDialog(message, funcAccept)
		addon:ShowDialog(message, nil, funcAccept or DUMMY)
	end

	function addon:ConfirmDialog(message, funcAccept, funcCancel, textAccept, textCancel)
		self:ShowDialog(message, nil, funcAccept, funcCancel or DUMMY, textAccept, textCancel )
	end

	function addon:EditDialog(message, text, funcAccept, funcCancel)
		self:ShowDialog(message, text or "", funcAccept, funcCancel or DUMMY)
	end
end

-- ============================================================================
-- addon specific functions
-- ============================================================================

-- send message to group
local function SendMessageToHomeGroup()
	local cfg = config.resetsNotify
	if cfg.message and IsInGroup(LE_PARTY_CATEGORY_HOME) then
		local channel
		if IsInRaid(LE_PARTY_CATEGORY_HOME) then
			if cfg['RAID_WARNING'] and not IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
				channel = (select(2, GetRaidRosterInfo(UnitInRaid("player") or 1)))>0 and 'RAID_WARNING'
			end
			if not channel then
				channel = cfg['RAID'] and 'RAID'
			end
		else
			channel = cfg['PARTY'] and 'PARTY'
		end
		if channel then
			SendChatMessage(cfg.message, channel)
		end
	end
end

-- notification functions
local Notify, NotifyEnd
do
	local function fmtLoot(itemLink, quantity, money, pref )
		local prefix = pref and '|cFF7FFF72KiwiFarm:|r ' or ''
		if itemLink then
			return format("%s%sx%d %s", prefix, itemLink, quantity, FmtMoneyShort(money) )
		else
			return format(L["%sYou loot %s"], prefix, FmtMoneyShort(money) )
		end
	end
	local notified = {}
	local channels = {
		chat = function(itemLink, quantity, money)
			local m = fmtLoot(itemLink, quantity, money, true)
			local f = config.chatFrame and _G['ChatFrame'..config.chatFrame]
			if f then
				f:AddMessage(m)
			else
				print(m)
			end
		end,
		combat = function(itemLink, quantity, money)
			if CombatText_AddMessage then
				local text = fmtLoot(itemLink, quantity, money)
				CombatText_AddMessage(text, COMBAT_TEXT_SCROLL_FUNCTION, 1, 1, 1)
			else
				print(L['|cFF7FFF72KiwiFarm:|r Warning, Blizzard Floating Combat Text is not enabled, change the notifications setup or goto Interface Options>Combat to enable this feature.'])
			end
		end,
		crit = function(itemLink, quantity, money)
			if CombatText_AddMessage then
				local text = fmtLoot(itemLink, quantity, money)
				CombatText_AddMessage(text, COMBAT_TEXT_SCROLL_FUNCTION, 1, 1, 1, 'crit')
			else
				print(L['|cFF7FFF72KiwiFarm:|r Warning, Blizzard Floating Combat Text is not enabled, change the notifications setup or goto Interface Options>Combat to enable this feature.'])
			end
		end,
		msbt = function(itemLink, quantity, money)
			if MikSBT then
				local text = fmtLoot(itemLink, quantity, money)
				MikSBT.DisplayMessage(text, config.notifyArea or MikSBT.DISPLAYTYPE_NOTIFICATION, false, 255, 255, 255)
			else
				print(L['|cFF7FFF72KiwiFarm:|r Warning, MikScrollingCombatText addon is not installed, change the notifications setup or install MSBT.'])
			end
		end,
		parrot = function(itemLink, quantity, money)
			if Parrot then
				local text = fmtLoot(itemLink, quantity, money)
				Parrot:ShowMessage(text, config.notifyArea or "Notification")
			else
				print(L['|cFF7FFF72KiwiFarm:|r Warning, Parrot2 addon is not installed, change the notifications setup or install Parrot2.'])
			end
		end,
		sound = function(_, _, _, groupKey)
			local sound = notify.sound[groupKey]
			if sound then PlaySoundFile(sound, "master") end
		end,
	}
	function Notify(groupKey, itemLink, quantity, money)
		for channel,v in pairs(notify[groupKey]) do
			if not notified[channel] then
				local func = channels[channel]
				if func and money>=v then
					func(itemLink, quantity, money, groupKey)
					notified[channel] = true
				end
			end
		end
	end
	function NotifyEnd()
		wipe(notified)
	end
end

-- items & price functions
local IsEnchantingMat
if VERSION<30000 then -- Vanilla or Burning Crusade
	local ENCHANTING = {
		[10940] = true, [11134] = true, [16203] = true,	[11135] = true, [11174] = true,	[14344] = true,
		[11082] = true, [11137] = true,	[11083] = true,	[10998] = true,	[20725] = true,	[11138] = true,
		[11084] = true,	[11139] = true,	[11178] = true,	[10938] = true,	[11176] = true,	[14343] = true,
		[11177] = true,	[10939] = true,	[10978] = true,	[16204] = true,	[16202] = true,	[11175] = true,
	}
	function IsEnchantingMat(itemID)
		return ENCHANTING[itemID]
	end
else
	function IsEnchantingMat(_, class, subClass)
		return class==7 and subClass==12
	end
end

-- calculate item price
local GetItemPrice
do
	-- auctionator addon
	local Auctionator_GetMarketPrice, Auctionator_GetDisenchantPrice, ItemUpgradeInfo
	local function InitAuctionator()
		if VANILA and Atr_GetAuctionPrice and Atr_CalcDisenchantPrice then -- auctionator ClassicFix (GepyFix)
			ItemUpgradeInfo = LibStub('LibItemUpgradeInfo-1.0',true)
			Auctionator_GetMarketPrice = function(name, itemID)
				return Atr_GetAuctionPrice(name)
			end
			Auctionator_GetDisenchantPrice = function(itemLink, class, rarity)
				return Atr_CalcDisenchantPrice(class, rarity, ItemUpgradeInfo:GetUpgradedItemLevel(itemLink)) -- Atr_GetDisenchantValue() is bugged cannot be used
			end
		elseif Auctionator and Auctionator.API and Auctionator.API.v1 then -- Auctionator original version for retail or classic
			local GetAuctionPriceByItemID = Auctionator.API.v1.GetAuctionPriceByItemID
			local GetDisenchantAuctionPrice = Auctionator.API.v1.GetDisenchantPriceByItemLink
			ItemUpgradeInfo = true
			Auctionator_GetMarketPrice = function(_, itemID)
				return GetAuctionPriceByItemID('KiwiFarm',itemID)
			end
			Auctionator_GetDisenchantPrice = function(itemLink)
				return GetDisenchantAuctionPrice('KiwiFarm', itemLink)
			end
		end
	end
	-- aux addon
	local AuxHistory, AuxInfo, AuxDisenchant
	local function InitAuxAddon()
		if _G.require and _G.aux_frame then
			AuxHistory = _G.require('aux.core.history')
			AuxInfo = _G.require('aux.util.info')
			AuxDisenchant = _G.require('aux.core.disenchant')
		end
	end
	local function GenAuxItemKey(itemLink)
		local item_id, suffix_id = AuxInfo.parse_link(itemLink)
		return item_id .. ':'.. suffix_id
	end
	-- common code
	local function GetValue(source, itemLink, itemID, name, class, rarity, vendorPrice, userPrice)
		local price
		if source == 'user' then
			price = userPrice
		elseif source == 'vendor' then
			price = vendorPrice
		elseif source == 'Atr:DBMarket' and ItemUpgradeInfo then -- Auctionator: market
			price = Auctionator_GetMarketPrice(name, itemID)
		elseif source == 'Atr:Destroy' and ItemUpgradeInfo then -- Auctionator: disenchant
			price = Auctionator_GetDisenchantPrice(itemLink, class, rarity)
		elseif source == 'Aux:Market' and AuxHistory then
			price = AuxHistory.market_value( GenAuxItemKey(itemLink) )
		elseif source == 'Aux:MinBuyout' and AuxHistory then
			price = AuxHistory.value( GenAuxItemKey(itemLink) )
		elseif source == 'Aux:Disenchant' and AuxDisenchant then
			local item = AuxInfo.item(itemID)
			price = item and AuxDisenchant.value(item.item_id, item.slot, item.quality, item.level)
		elseif source == 'REC:Market' and RECrystallize_PriceCheck then
			price = RECrystallize_PriceCheck(itemLink)
		elseif TSM_API and TSM_API.GetCustomPriceValue then -- TSM sources
			price = TSM_API.GetCustomPriceValue(source, "i:"..itemID)
		end
		return price or 0
	end
	function GetItemPrice(itemLink)
		InitAuxAddon()
		InitAuctionator()
		GetItemPrice = function(itemLink)
			local itemID = tonumber(strmatch(itemLink, "item:(%d+):"))
			local name, _, rarity, _, _, _, _, _, _, _, vendorPrice, class, subClass = GetItemInfo(itemLink)
			if not (config.ignoreEnchantingMats and IsEnchantingMat(itemID, class, subClass)) then
				local price, sources = 0, config.priceByItem[itemLink] or config.priceByQuality[rarity or 0] or {}
				for src, user in pairs(sources) do
					price = max( price, GetValue(src, itemLink, itemID, name, class, rarity, vendorPrice, user) )
				end
				return price, rarity, name
			end
		end
		return GetItemPrice(itemLink)
	end
end

-- lock&resets management
local LockAddReset, LockAddInstance, LockDel, LockResetAll
do
	local function LockAddCharReset(zone, ctime, resets, resetsd)
		if VANILA then
			resetsd[#resetsd+1] = ctime -- classic to track 30/24h limit
		end
		resets.count = resets.count + 1
		for i=#resets,1,-1 do
			if resets[i].zone==zone and not resets[i].reseted then
				resets[i].time = ctime
				resets[i].reseted = ctime
				resets.countd = resets.countd - 1
				resets[zone] = nil
				return
			end
		end
		resets[#resets+1] =  { zone = zone, time = ctime, reseted = ctime}
	end
	local function CheckPartyAlts(zone, ctime) -- reset of alts in party/raid for classic
		if VANILA then
			local units = GetGroupRaidMembers()
			if units then
				for _,unit in ipairs(units) do
					if not UnitExists(unit) then break end
					local nameKey = UnitName(unit) .. " - " .. serverKey
					if charKey~=nameKey then
						local resetChar = server.resetData[nameKey]
						if resetChar then
							LockAddCharReset(zone, ctime, resetChar.resets, resetChar.resetsd, true)
						end
					end
				end
			end
		end
	end
	-- register instance reset
	function LockAddReset(zone)
		local ctime = time()
		LockAddCharReset(zone, ctime, resets, resetsd) -- current char reset
		CheckPartyAlts(zone, ctime)
	end
	-- add used instance
	function LockAddInstance(zone)
		resets[zone] = true
		resets.countd = resets.countd + 1
		resets[#resets+1] =  { zone = zone, time =  time() }
	end
	-- delete instance
	function LockDel(i)
		if resets[i].reseted then
			resets.count = resets.count - 1
		else
			resets[ resets[i].zone ] = nil
			resets.countd = resets.countd - 1
		end
		tremove(resets,i)
	end
	-- reset all used/dirty instances
	function LockResetAll()
		local ctime = time()
		local i, expire = #resets, ctime-3600
		while i>0 and resets[i].time>expire do
			if not resets[i].reseted and (not inInstance or resets[i].zone~=curZoneName) then
				resets[i].time = ctime
				resets[i].reseted = ctime
				resets.count = resets.count + 1
				resets[ resets[i].zone ] = nil
				resets.countd = resets.countd - 1
				if VANILA then
					resetsd[#resetsd+1] = ctime -- classic to track 30/24h limit
				end
			end
			i = i - 1
		end
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
		text_header =              L["|cFF7FFF72KiwiFarm:|r\nSession:\n"]
		text_mask   =	           "|cFF7FFF72%s|r\n"      -- zone
		text_mask   = text_mask .. "%s%02d:%02d:%02d|r\n"  -- session duration
		-- instance reset & lock info
		if not disabled.reset then
			text_header = text_header .. L["Resets:\n"]
			if VANILA then
				text_mask   = text_mask .. "%s%d|r||%s%d|r||%s%02d:%02d|r\n"  -- last reset
			else
				text_mask   = text_mask .. "%s%d|r||%s%02d:%02d|r\n"  -- last reset
			end
		end
		-- count data
		if not disabled.count then
			-- mobs killed
			text_header = text_header .. L["Mobs killed:\n"]
			text_mask   = text_mask   .. "%d||%d\n"
			-- items looted
			text_header = text_header .. L["Items looted:\n"]
			text_mask   = text_mask   .. "%d\n"
		end
		-- gold cash & items
		if not disabled.gold then
			if not disabled.quests then
				text_header = text_header .. L["Gold quests:\n"]
				text_mask   = text_mask   .. "%s\n"  -- money quests
			end
			text_header = text_header .. L["Gold cash:\nGold items:\n"]
			text_mask   = text_mask   .. "%s\n"  -- money cash
			text_mask   = text_mask   .. "%s\n"  -- money items
			-- gold by item quality
			if not disabled.quality then
				for i=0,5 do -- gold by qualities (poor to legendary)
					text_header = text_header .. format(" %s\n",FmtQuality(i))
					text_mask   = text_mask   .. "%s\n"
				end
			end
			-- gold hour & total
			text_header = text_header .. L["Gold/hour:\nGold total:\n"]
			text_mask   = text_mask .. "%s\n" -- money per hour
			text_mask   = text_mask .. "%s\n" -- money total
		end
		-- leveling xp
		if isPlayerLeveling and not disabled.experience then
			text_header = text_header .. L["XP/hour:\nXP remaining:\nXP last pull:\nXP level up:\n"]
			text_mask  = text_mask .. "%.1fk\n" -- xp/hour
			text_mask  = text_mask .. "%.1fk\n" -- xp remain
			text_mask  = text_mask .. "%d\n"    -- xp last pull
			text_mask  = text_mask .. "%s\n"   -- xp ding time
		end
		textl:SetText(text_header)
	end
	-- refresh text
	function RefreshText()
		local curtime = time()
		local xpEnabled = isPlayerLeveling and not disabled.experience
		-- delete old data
		local exptime = curtime - 3600
		while (#resets>0 and resets[1].time<exptime) or #resets>RESET_MAX do -- remove old resets(>1hour)
			LockDel(1)
		end
		if VANILA then
			local exptime = curtime - 86400
			while (#resetsd>0 and resetsd[1]<exptime) or #resets>RESET_DAY do -- remove old daily resets for classic (>24hour)
				tremove(resetsd,1)
			end
		end
		-- reset old data
		wipe(data)
		-- zone text
		data[#data+1] = ZoneTitle[curZoneName]
		-- session duration
		local sSession
		if session.startTime or session.duration then
			sSession = curtime - (session.startTime or curtime) + (session.duration or 0)
			data[#data+1] = (session.startTime and '|cFF00ff00') or (session.duration and '|cFFff8000') or '|cFFff0000'
		elseif xpEnabled then
			sSession = curtime - (leveling.startTime or curtime) + (leveling.duration or 0)
			data[#data+1] = '|cFF00ffff'
		else
			sSession = 0
			data[#data+1] = '|cFFff0000'
		end
		local m0, s0 = floor(sSession/60), sSession%60
		local h0, m0 = floor(m0/60), m0%60
		data[#data+1] = h0
		data[#data+1] = m0
		data[#data+1] = s0
		-- reset data
		if not disabled.reset then
			local dirtyC   = resets.countd>0 and '|cFFff8000' or '|cFF00ff00'
			local remain   = RESET_MAX-resets.count
			local timeLock = #resets>0 and resets[1].time+3600 or nil
			local sUnlock  = timeLock and timeLock-curtime or 0
			if VANILA then
				local remaind = math.max( RESET_DAY - #resetsd, 0 )
				data[#data+1] = (remaind>5 and '|cFF00ff00') or (remaind>0 and '|cFFff8000') or '|cFFff0000'
				data[#data+1] =  remaind
			end
			-- resets remain
			data[#data+1] = (remain>resets.countd and '|cFF00ff00') or (remain>0 and '|cFFff8000') or '|cFFff0000'
			data[#data+1] = remain
			-- unlock time if all resets are spent
			data[#data+1] = (remain<=0 and '|cFFff0000') or dirtyC
			data[#data+1] = floor(sUnlock/60)
			data[#data+1] = sUnlock%60
		end
		-- count data
		if not disabled.count then
			-- mob kills
			data[#data+1] = combatCurKills or combatPreKills
			data[#data+1] = session.countMobs
			-- items looted
			data[#data+1] = session.countItems
		end
		-- gold info
		if not disabled.gold then
			if not disabled.quests then
				data[#data+1] = FmtMoney(session.moneyQuests)
			end
			data[#data+1] = FmtMoney(session.moneyCash)
			data[#data+1] = FmtMoney(session.moneyItems)
			if not disabled.quality then
				for i=0,5 do
					data[#data+1] = FmtMoney(session.moneyByQuality[i] or 0)
				end
			end
			local total = session.moneyCash+session.moneyItems+session.moneyQuests
			data[#data+1] = FmtMoney(sSession>0 and floor(total*3600/sSession) or 0)
			data[#data+1] = FmtMoney(total)
		end
		-- leveling xp info
		if xpEnabled then
		    local xpMax = UnitXPMax("player")
			local xpCur = UnitXP("player")
			if xpMax>0 then -- workaround to blizzard bug, xp functions return 0 for an instant when player is dead and click Release Spirit
				if xpCur<leveling.xpLastXP then
					leveling.xpFromXP = leveling.xpFromXP-leveling.xpMaxXP
					leveling.xpMaxXP  = xpMax
				end
				leveling.xpLastXP = xpCur
				local xpDuration = curtime - leveling.startTime + (leveling.duration or 0)
				local xpPerHour  = (xpCur - leveling.xpFromXP) / xpDuration * 3600
				local xpRemain   = xpMax - xpCur
				local minutes    = xpPerHour>0 and xpRemain / xpPerHour * 60 or 0
				data[#data+1] = xpPerHour / 1000          -- xp/hour
				data[#data+1] = xpRemain / 1000           -- remain xp to level up
				data[#data+1] = leveling.xpLastPull or 0  -- xp last pull
				data[#data+1] = minutes>=60 and format("%dh %02dm", minutes/60, minutes%60) or format("%dm", minutes)
			else -- game returned wrong data, set all zero
				data[#data+1] = 0
				data[#data+1] = 0
				data[#data+1] = 0
				data[#data+1] = 0
			end
		end
		-- set text
		textr:SetFormattedText( text_mask, unpack(data) )
		-- update timer status
		local stopped = (#resets==0 and not session.startTime) and (not xpEnabled)
		if stopped ~= not timer:IsPlaying() then
			if stopped then
				timer:Stop()
			else
				timer:Play()
			end
		end
	end
end

-- adjust the money stats of a looted item whose price was changed by the user.
local function AdjustLootedItemMoneyStats(itemLink)
	local data = session.lootedItems[itemLink]
	if data then
		local money, quantity = data[1], data[2]
		local newPrice, quality = GetItemPrice(itemLink)
		if newPrice then
			local newMoney = newPrice * quantity
			local moneyDiff = newMoney - money
			if moneyDiff ~= 0 then
				session.lootedItems[itemLink] = { money+moneyDiff, quantity }
				session.moneyItems = math.max(0, session.moneyItems + moneyDiff)
				session.moneyByQuality[quality] = math.max(0, session.moneyByQuality[quality] + moneyDiff)
				RefreshText()
			end
		end
	end
end

-- session start
local function SessionStart(refresh)
	if not session.startTime or refresh then
		session.startTime = session.startTime or time()
		session.endTime = nil
		addon:RegisterEvent("CHAT_MSG_LOOT")
		addon:RegisterEvent("CHAT_MSG_MONEY")
		addon:RegisterEvent("QUEST_TURNED_IN")
		RefreshText()
	end
end

-- session stop
local function SessionStop()
	if session.startTime then
		local curTime = time()
		session.duration = (session.duration or 0) + (curTime - (session.startTime or curTime))
		session.startTime = nil
		session.endTime = curTime
		addon:UnregisterEvent("CHAT_MSG_LOOT")
		addon:UnregisterEvent("CHAT_MSG_MONEY")
		addon:UnregisterEvent("QUEST_TURNED_IN")
		return curTime
	end
	return session.endTime or time()
end

-- session finish
local function SessionFinish()
	if session.startTime or session.duration then
		local curTime     = SessionStop()
		local zoneName    = session.zoneName
		session.endTime   = nil
		session.zoneName  = nil
		if session.moneyCash>0 or session.moneyItems>0 or session.moneyQuests>0 or session.countItems>0 or session.countMobs>0 then
			AddDB(config.total, session, collect.total)
			AddDB(GetDailyDB(curTime), session, collect.daily)
			AddDB(GetZoneDB(zoneName), session, collect.zone)
		end
		InitDB(session, DEFDATA,  true)
		session.duration = nil
		timeLootedItems = curTime
		RefreshText()
	end
end

-- toggle start/stop session
local function SessionTogglePause()
	if session.startTime then
		SessionStop()
	else
		SessionStart()
	end
end

-- toggle start/finish session
local function SessionToggleFinish()
	if session.startTime then
		SessionFinish()
	else
		SessionStart()
	end
end

-- leveling reset xp info
local function LevelingReset()
	leveling.startTime  = time()-1
	leveling.duration   = nil
	leveling.xpMaxXP    = UnitXPMax('player')
	leveling.xpLastXP   = UnitXP('player')
	leveling.xpFromXP   = leveling.xpLastXP
	leveling.xpLastPull = nil
end

-- leveling continue
local function LevelingContinue()
	leveling.startTime = time()-1
end

-- leveling stop/pause
local function LevelingStop()
	if isPlayerLeveling then
		local curTime = time()
		leveling.duration = (leveling.duration or 0) + (curTime - (leveling.startTime or curTime))
		leveling.startTime = nil
	end
end

-- leveling init
local function LevelingInit()
	if isPlayerLeveling then -- player not max level ?
		leveling = server.leveling[charKey] or {}
		if not leveling.startTime then
			if leveling.xpLastXP~=UnitXP('player') or leveling.xpMaxXP~=UnitXPMax('player') then
				LevelingReset()
			else
				LevelingContinue()
			end
		end
	end
	server.leveling[charKey] = leveling -- assigning nil if player is at max level
end

-- restore frame strata
local function RestoreStrata()
	addon:SetFrameStrata(config.frameStrata or 'MEDIUM')
end

-- restore main frame position
local function RestorePosition()
	addon:ClearAllPoints()
	addon:SetPoint( config.framePos.anchor, UIParent, 'CENTER', config.framePos.x, config.framePos.y )
end

-- save main frame position
local function SavePosition()
	local p, cx, cy = config.framePos, UIParent:GetCenter() -- we are assuming addon frame scale=1 in calculations
	local x = (p.anchor:find("LEFT")   and addon:GetLeft())   or (p.anchor:find("RIGHT") and addon:GetRight()) or addon:GetLeft()+addon:GetWidth()/2
	local y = (p.anchor:find("BOTTOM") and addon:GetBottom()) or (p.anchor:find("TOP")   and addon:GetTop())   or addon:GetTop() -addon:GetHeight()/2
	p.x, p.y = x-cx, y-cy
end

-- frame visibility (needed to avoid visual glicth when layout is changed)
local function UpdateFrameAlpha()
	addon:SetScript('OnUpdate', nil)
	addon:SetAlpha(1)
end

-- frame sizing
local function UpdateFrameSize()
	addon:SetHeight( textl:GetHeight() + config.frameMargin*2 )
	addon:SetWidth( config.frameWidth or (textl:GetWidth() * 2.3) + config.frameMargin*2 )
	addon:SetScript('OnUpdate', UpdateFrameAlpha)
end

-- change main frame visibility: nil == toggle visibility
local function UpdateFrameVisibility(visible)
	if addon.plugin then return end
	if visible == nil then
		visible = not addon:IsShown()
	end
	addon:SetShown(visible)
	config.visible = visible
end

-- click on any launcher button
local function MinimapButtonMouseClick(button)
	if button == 'RightButton' or addon.plugin then
		addon:ShowMenu()
	else
		UpdateFrameVisibility()
	end
end

-- show tooltip on mouseover launcher button
local function MinimapButtonTooltipShow(tooltip)
	tooltip:AddDoubleLine("KiwiFarm", versionStr)
	if session.startTime or session.duration then
		local total, hourly, cash, quests, items, hh, mm = GetSessionGeneralStats()
		local cc = session.startTime and '|cFF00ff00' or '|cFFff8000'
		local ss = hh>0 and format("%s%dh %dm|r",cc,hh,mm) or format("%s%dm|r",cc,mm)
		tooltip:AddDoubleLine(L["Session:"],    ss, 1,1,1)
		tooltip:AddDoubleLine(L["Gold quests:"], FmtMoney(quests),  1,1,1, 1,1,1)
		tooltip:AddDoubleLine(L["Gold cash:"],  FmtMoney(cash),   1,1,1, 1,1,1)
		tooltip:AddDoubleLine(L["Gold items:"], FmtMoney(items),  1,1,1, 1,1,1)
		tooltip:AddDoubleLine(L["Gold/hour:"],  FmtMoney(hourly), 1,1,1, 1,1,1)
		tooltip:AddDoubleLine(L["Gold total:"], FmtMoney(total),  1,1,1, 1,1,1)
	end
	tooltip:AddLine(L["|cFFff4040Left Click|r toggle visibility\n|cFFff4040Right Click|r open menu"], 0.2, 1, 0.2)
end

local function SetBackground()
	if addon.plugin then return end
	if config.borderTexture then
		addon:SetBackdrop({
			bgFile = "Interface\\Buttons\\WHITE8X8",
			edgeFile = config.borderTexture,
			tile = true, tileSize = 8, edgeSize = 16,
			insets = { left = 4, right = 4, top = 4, bottom = 4 },
		})
		addon:SetBackdropBorderColor( unpack(config.borderColor or COLOR_WHITE) )
	else
		addon:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
	end
	addon:SetBackdropColor( unpack(config.backColor or COLOR_TRANSPARENT) )
end

-- layout main frame
local function LayoutFrame()
	addon:SetAlpha(0)
	-- background
	SetBackground()
	-- text left
	textl:ClearAllPoints()
	textl:SetPoint('TOPLEFT', config.frameMargin, -config.frameMargin)
	textl:SetJustifyH('LEFT')
	textl:SetJustifyV('TOP')
	SetTextFont(textl, config.fontName, config.fontSize, 'OUTLINE')
	PrepareText()
	-- text right
	textr:ClearAllPoints()
	textr:SetPoint('TOPRIGHT', -config.frameMargin, -config.frameMargin)
	textr:SetPoint('TOPLEFT', config.frameMargin, -config.frameMargin)
	textr:SetJustifyH('RIGHT')
	textr:SetJustifyV('TOP')
	SetTextFont(textr, config.fontName, config.fontSize, 'OUTLINE')
	RefreshText()
	-- delayed frame sizing, because textl:GetHeight() returns incorrect height on first login for some fonts.
	addon:SetScript("OnUpdate", UpdateFrameSize)
end

-- ============================================================================
-- events
-- ============================================================================

-- main frame becomes visible
addon:SetScript("OnShow", function(self)
	RefreshText()
end)

-- shift+mouse click to reset instances
addon:SetScript("OnMouseUp", function(self, button)
	if button == 'RightButton' then
		addon:ShowMenu(true)
	elseif button == 'LeftButton' and IsShiftKeyDown() then -- reset instances data
		ResetInstances()
	end
end)

-- track reset instance event
-- in classic the game displays a reset failed message so we assume the reset was sucesfully in this case (github ticket #3).
local PATTERN_RESET = '^'..INSTANCE_RESET_SUCCESS:gsub("([^%w])","%%%1"):gsub('%%%%s','(.+)')..'$'
local PATTERN_RESET_FAILED = '^'..INSTANCE_RESET_FAILED:gsub("([^%w])","%%%1"):gsub('%%%%s','(.+)')..'$'
function addon:CHAT_MSG_SYSTEM(event,msg)
	local zone = strmatch(msg,PATTERN_RESET) or ( VANILA and strmatch(msg,PATTERN_RESET_FAILED) )
	if zone then
		LockAddReset(zone)
		if addon:IsVisible() then
			RefreshText()
		end
		SendMessageToHomeGroup()
	end
end

-- looted items
do
	local loot_patterns = {
		LOOT_ITEM_SELF_MULTIPLE:gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)"),
		LOOT_ITEM_PUSHED_SELF_MULTIPLE:gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)"),
		LOOT_ITEM_SELF:gsub("%%s", "(.+)"),
		LOOT_ITEM_PUSHED_SELF:gsub("%%s", "(.+)"),
	}
	local function GetItemInfoFromMsg(msg)
		for _,pattern in ipairs(loot_patterns) do
			local itemLink, quantity = strmatch(msg, pattern)
			if itemLink then
				return itemLink, tonumber(quantity) or 1
			end
		end
	end
	function addon:CHAT_MSG_LOOT(event,msg)
		if session.startTime then
			local itemLink, quantity = GetItemInfoFromMsg(msg)
			if itemLink then
				local price, rarity, itemName = GetItemPrice(itemLink)
				if price and rarity then
					local money = price*quantity
					-- register item looted
					local data = session.lootedItems[itemLink]
					if data then
						data[1] = data[1] + money
						data[2] = data[2] + quantity
					else
						session.lootedItems[itemLink] = { money, quantity }
						timeLootedItems = time()
					end
					-- register item money earned
					session.moneyItems = session.moneyItems + money
					session.moneyByQuality[rarity] = (session.moneyByQuality[rarity] or 0) + money
					-- register counts
					session.countItems = session.countItems + quantity
					session.countByQuality[rarity] = (session.countByQuality[rarity] or 0) + quantity
					-- register zone if necessary
					if not session.zoneName then
						session.zoneName = curZoneName
					end
					-- notifications
					if notify[rarity] then Notify(rarity,   itemLink, quantity, money) end
					if notify.price   then Notify('price',  itemLink, quantity, money) end
					NotifyEnd()
				end
			end
		end
	end
end

-- looted gold
do
	local GOLD_PTN = gsub(_G.GOLD_AMOUNT, "%%d", "(%1+)")
	local SILV_PTN = gsub(_G.SILVER_AMOUNT, "%%d", "(%1+)")
	local COPP_PTN = gsub(_G.COPPER_AMOUNT, "%%d", "(%1+)")
	function addon:CHAT_MSG_MONEY(event,msg)
		if session.startTime then
			local g = strmatch(msg, GOLD_PTN) or 0
			local s = strmatch(msg, SILV_PTN) or 0
			local c = strmatch(msg, COPP_PTN) or 0
			local money = g*10000 + s*100 + c
			session.moneyCash = session.moneyCash + money
			-- register zone if necessary
			if not session.zoneName then
				session.zoneName = curZoneName
			end
			-- notify
			if notify.money then
				Notify('money', nil, nil, money); NotifyEnd()
			end
		end
	end
end

-- gold awarded in quests
function addon:QUEST_TURNED_IN(event,_,_,money)
	if disabled.quests then return end
	session.moneyQuests = session.moneyQuests + money
	-- register zone if necessary
	if not session.zoneName then
		session.zoneName = curZoneName
	end
	-- notify
	if notify.money then
		Notify('money', nil, nil, money); NotifyEnd()
	end
end

-- combat start
function addon:PLAYER_REGEN_DISABLED()
	combatActive = true
	combatPreKills = combatCurKills or combatPreKills
	combatCurKills = nil
	if isPlayerLeveling then
		combatStartXP = UnitXP('player')
	end
end

-- combat end
function addon:PLAYER_REGEN_ENABLED()
	combatActive = nil
	if isPlayerLeveling then
		local pullXP = UnitXP('player') - combatStartXP
		if pullXP>0 then
			leveling.xpLastPull = pullXP
		end
	end
	wipe(enemyGUIDS)
end

-- zones management
do
	local lastZoneKey
	function addon:ZONE_CHANGED_NEW_AREA(event)
		inInstance = IsInInstance()
		local zone =  inInstance and GetInstanceInfo() or GetZoneText()
		if zone and zone~='' then
			local zoneKey = format("%s:%s",zone,tostring(inInstance))
			if zoneKey ~= lastZoneKey or (not event) then -- no event => called from config
				if inInstance and #resets>=RESET_MAX then -- locked but inside instance, means locked expired before estimated unlock time
					LockDel(1)
				end
				curZoneName = zone
				if not addon.plugin and config.farmZones and not config.farmDisableZones then
					if config.farmZones[zone] then
						if lastZoneKey or time()-(session.endTime or 0)<300 then -- continue session if logout->login < 5 minutes
							SessionStart()
						end
						self:Show()
					elseif not config.reloadUI then
						SessionStop()
						self:Hide()
					end
				end
				if config.reloadUI then -- clear reloadUI flag if set
					config.reloadUI = nil
				end
				if self:IsVisible() then
					RefreshText()
				end
				lastZoneKey = zoneKey
			end
		end
	end
	addon.PLAYER_ENTERING_WORLD = addon.ZONE_CHANGED_NEW_AREA
end

-- stop session and register automatic reset on player logout
do
	local isLogout
	hooksecurefunc("Logout", function() isLogout=true end)
	hooksecurefunc("Quit",   function() isLogout=true end)
	hooksecurefunc("CancelLogout", function() isLogout=nil end)
	function addon:PLAYER_LOGOUT()
		if isLogout then
			LockResetAll() -- we must reset all used instances on logout
			SessionStop()
			LevelingStop()
		end
		config.reloadUI = not isLogout or nil
	end
end

-- If we kill a npc inside instance a ResetInstance() is executed on player logout, so we need this to track
-- and save this hidden reset, see addon:PLAYER_LOGOUT()
-- addon:COMBAT_LOG_EVENT_UNFILTERED()
do
	local COMBATLOG_OBJECT_TYPE_NPC = COMBATLOG_OBJECT_TYPE_NPC
	local CombatLogGetCurrentEventInfo = CombatLogGetCurrentEventInfo
	local Events = {
		UNIT_DIED = true,
		SPELL_DAMAGE = true,
		SWING_DAMAGE = true,
		RANGE_DAMAGE = true,
		SPELL_PERIODIC_DAMAGE = true,
		SPELL_BUILDING_DAMAGE = true,
	}
	function addon:COMBAT_LOG_EVENT_UNFILTERED()
		local _, eventType,_,srcGUID,srcName,_,_,dstGUID,dstName,dstFlags = CombatLogGetCurrentEventInfo()
		if Events[eventType] then
			if eventType == 'UNIT_DIED' then
				if inInstance and not resets[curZoneName] and IsDungeon() then
					LockAddInstance(curZoneName) -- register used instance
					timer:Play()
				end
				if session.startTime and (inInstance or enemyGUIDS[dstGUID])  then
					enemyGUIDS[dstGUID] = nil
					session.countMobs = session.countMobs + 1
					session.killedMobs[dstName] = (session.killedMobs[dstName] or 0) + 1
					combatCurKills = (combatCurKills or 0) + 1
					if not session.zoneName then session.zoneName = curZoneName end
				end
			elseif srcGUID==playerGUID and enemyGUIDS[dstGUID]==nil and band(dstFlags,COMBATLOG_OBJECT_TYPE_NPC) then
				enemyGUIDS[dstGUID] = true
			end
		end
	end
end

-- session control on first boot or reload UI
local function SessionRecover()
	if session.startTime then -- this is a reload UI
		SessionStart(true)
	else -- login
		if config.farmAutoFinish then -- and time()-(session.endTime or 0) > 300 then -- close last session
			SessionFinish()
		end
		if config.farmAutoStart then -- open a new session
			SessionStart(true)
		end
	end
end

-- ============================================================================
-- Standalone window setup
-- ============================================================================

local function SetupStandaloneFrame()
	addon:SetMovable(true)
	addon:RegisterForDrag("LeftButton")
	addon:SetScript("OnDragStart", addon.StartMoving)
	addon:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		self:SetUserPlaced(false)
		SavePosition()
		RestorePosition()
	end )
	RestoreStrata()
	RestorePosition()
	LayoutFrame()
	SessionRecover()
	addon:SetShown( config.visible and (not config.farmZones or config.reloadUI) )
end

-- ============================================================================
-- details plugin setup
-- ============================================================================

local function SetupPluginFrame()
	if not config.details then return end
	local Details = _G.Details
	if not Details then print("KiwiFarm warning: this addon is configured as a Details plugin but Details addon is not installed!"); return; end
	local Plugin = Details:NewPluginObject("Details_KiwiFarm")
	Plugin:SetPluginDescription( C_AddOns.GetAddOnMetadata("KiwiFarm", "Notes") )
	addon.plugin = Plugin
	LayoutFrame()
	Plugin.OnDetailsEvent = function(self, event, ...)
		local instance = self:GetPluginInstance()
		if instance and (event == "SHOW" or instance == select(1,...)) then
			self.Frame:SetSize(instance:GetSize())
			addon.instance = instance
			addon:SetFrameLevel(5)
			LayoutFrame()
		end
	end
	UpdateFrameSize = function(self)
		local _, h = self.instance:GetSize()
		local th = h-config.frameMargin*2
		textl:SetHeight(th)
		textr:SetHeight(th)
		self:SetAlpha(1)
	end
	addon:SetScript("OnMouseUp", function(self, button)
		if button == 'RightButton' and not IsShiftKeyDown() then
			self.instance.windowSwitchButton:GetScript("OnMouseDown")(self.instance.windowSwitchButton, button)
		elseif button == 'LeftButton' and IsShiftKeyDown() then
			ResetInstances()
		else
			self:ShowMenu()
		end
	end)
	Details:InstallPlugin("RAID", 'KiwiFarm', iconTexture, Plugin, "DETAILS_PLUGIN_KIWIFARM", 1, C_AddOns.GetAddOnMetadata("KiwiFarm", "Author"), versionStr)
	Details:RegisterEvent(Plugin, "DETAILS_INSTANCE_ENDRESIZE")
	Details:RegisterEvent(Plugin, "DETAILS_INSTANCE_SIZECHANGED")
	Details:RegisterEvent(Plugin, "DETAILS_INSTANCE_STARTSTRETCH")
	Details:RegisterEvent(Plugin, "DETAILS_INSTANCE_ENDSTRETCH")
	Details:RegisterEvent(Plugin, "DETAILS_OPTIONS_MODIFIED")
	-- reparent frame to details frame
	addon:Hide()
	addon:SetParent(Plugin.Frame)
	addon:ClearAllPoints()
	addon:SetAllPoints()
	addon:Show()
	SessionRecover()
	return true
end

-- ============================================================================
-- addon entry point
-- ============================================================================

addon:RegisterEvent("ADDON_LOADED")
addon:RegisterEvent("PLAYER_LOGIN")
addon:SetScript("OnEvent", function(frame, event, name)
	if event == "ADDON_LOADED" and name == addonName then
		addon.__loaded = true
	end
	if not (addon.__loaded and IsLoggedIn()) then return end
	-- unregister init events
	addon:UnregisterAllEvents()
	-- main frame init
	addon:Hide()
	addon:SetSize(1,1)
	addon:EnableMouse(true)
	-- text left
	textl = addon:CreateFontString()
	-- text right
	textr = addon:CreateFontString()
	-- timer
	timer = addon:CreateAnimationGroup()
	timer.animation = timer:CreateAnimation()
	timer.animation:SetDuration(1)
	timer:SetLooping("REPEAT")
	timer:SetScript("OnLoop", RefreshText)
	-- database setup
	root, server, config = CreateDB()
	session  = config.session
	notify   = config.notify
	disabled = config.disabled
	collect  = config.collect
	resets   = server.resets  or server.resetData[charKey].resets
	resetsd  = server.resetsd or server.resetData[charKey].resetsd
	-- remove old data from database
	local key = date("%Y/%m/%d", time()-86400*7)
	for k,v in next, config.daily do
		if k<key then config.daily[k] = nil; end
	end
	-- init leveling session
	LevelingInit()
	-- compartment icon
	if AddonCompartmentFrame and AddonCompartmentFrame.RegisterAddon then
		AddonCompartmentFrame:RegisterAddon({
			text = "KiwiFarm",
			icon  = iconTexture,
			registerForAnyClick = true,
			notCheckable = true,
			func = function(_,_,_,_,button) MinimapButtonMouseClick(button) end,
		})
	end
	-- minimap icon
	LibStub("LibDBIcon-1.0"):Register(addonName, LibStub("LibDataBroker-1.1"):NewDataObject(addonName, {
		type  = "launcher",
		label = GetAddOnInfo( addonName, "Title"),
		icon  = iconTexture,
		OnClick = function(_, button) MinimapButtonMouseClick(button) end,
		OnTooltipShow = MinimapButtonTooltipShow,
	}) , config.minimapIcon)
	-- events
	addon:SetScript('OnEvent', function(self,event,...) self[event](self,event,...) end)
	addon:RegisterEvent("PLAYER_REGEN_DISABLED")
	addon:RegisterEvent("PLAYER_REGEN_ENABLED")
	addon:RegisterEvent('COMBAT_LOG_EVENT_UNFILTERED')
	addon:RegisterEvent("ZONE_CHANGED_NEW_AREA")
	addon:RegisterEvent("PLAYER_ENTERING_WORLD")
	addon:RegisterEvent("CHAT_MSG_SYSTEM")
	addon:RegisterEvent("PLAYER_LOGOUT")
	-- mainframe setup
	if not SetupPluginFrame() then
		SetupStandaloneFrame()
	end
end)

-- ============================================================================
-- config cmdline
-- ============================================================================

SLASH_KIWIFARM1,SLASH_KIWIFARM2 = "/kfarm", "/kiwifarm"
SlashCmdList.KIWIFARM = function(args)
	local arg1,arg2,arg3 = strsplit(" ",args,3)
	arg1, arg2 = strlower(arg1 or ''), strlower(arg2 or '')
	if arg1 == 'show' then
		addon:Show()
	elseif arg1 == 'hide' then
		addon:Hide()
	elseif arg1 == 'toggle' then
		UpdateFrameVisibility()
	elseif arg1 == 'start'  then
		SessionStart()
	elseif arg1 == 'stop' then
		SessionStop()
	elseif arg1 == 'finish' then
		SessionFinish()
	elseif arg1 =='startstop' then
		SessionTogglePause()
	elseif arg1 =='startfinish' then
		SessionToggleFinish()
	elseif arg1 == 'config' then
		addon:ShowMenu()
	elseif arg1 == 'resetpos' then
		config.framePos.x, config.framePos.x = 0, 0
		RestorePosition()
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
		print("  /kfarm show        -- show main window")
		print("  /kfarm hide        -- hide main window")
		print("  /kfarm toggle      -- show/hide main window")
		print("  /kfarm start       -- session start")
		print("  /kfarm stop        -- session stop")
		print("  /kfarm finish      -- session finish")
		print("  /kfarm startstop   -- session start/stop toggle")
		print("  /kfarm startfinish -- session start/finish toggle")
 		print("  /kfarm config      -- display config menu")
		print("  /kfarm minimap     -- toggle minimap icon visibility")
		print("  /kfarm resetpos    -- reset main window position")
	end
end

-- ============================================================================
-- config popup menu
-- ============================================================================

do
	-- popup menu main frame
	local menuFrame
	-- generic & enhanced popup menu management code, reusable for other menus
	local showMenu, refreshMenu, getMenuLevel, getMenuValue
	do
		-- workaround for classic submenus bug, level 3 submenu only displays up to 8 items without this
		local function FixClassicBug(level, count)
			local name = "DropDownList"..level
			local frame = _G[name]
			for index = 1, count do
				local button = _G[ name.."Button"..index ]
				if button and frame~=button:GetParent() then
					button:SetParent(frame)
				end
			end
		end
		-- color picker management
		local function picker_get_alpha()
			local a = ColorPickerFrame.SetupColorPickerAndShow and ColorPickerFrame:GetColorAlpha() or OpacitySliderFrame:GetValue()
			return WOW_PROJECT_ID~=WOW_PROJECT_MAINLINE and 1-a or a
		end
		local function picker_get_prev_color(c)
			local r, g, b, a
			if ColorPickerFrame.SetupColorPickerAndShow then
				r, g, b, a = ColorPickerFrame:GetPreviousValues()
			else
				r, g, b, a = c.r, c.g, c.b, c.opacity
			end
			return r, g, b, (WOW_PROJECT_ID~=WOW_PROJECT_MAINLINE and 1-a or a)
		end
		-- menu initialization: special management of enhanced menuList tables, using fields not supported by the base UIDropDownMenu code.
		local function initialize( frame, level, menuList )
			if level then
				frame.menuValues[level] = UIDROPDOWNMENU_MENU_VALUE
				local init = menuList.init
				if init then -- custom initialization function for the menuList
					init(menuList, level, frame)
				end
				if CLASSIC then
					FixClassicBug(level, #menuList)
				end
				for index=1,#menuList do
					local item = menuList[index]
					if item.hidden==nil or not item.hidden(item) then
						if item.useParentValue then -- use the value of the parent popup, needed to make splitMenu() transparent
							item.value = UIDROPDOWNMENU_MENU_VALUE
						end
						if type(item.text)=='function' then -- save function text in another field for later use
							item.textf = item.text
						end
						if type(item.disabled)=='function' then
							item.disabledf = item.disabled
						end
						if item.disabledf then -- support for functions instead of only booleans
							item.disabled = item.disabledf(item, level, frame)
						end
						if item.textf then -- support for functions instead of only strings
							item.text = item.textf(item, level, frame)
						end
						if item.hasColorSwatch then -- simplified color management, only definition of get&set functions required to retrieve&save the color
							if not item.swatchFunc then
								local get, set = item.get, item.set
								item.swatchFunc  = function() local r,g,b,a = get(item); r,g,b = ColorPickerFrame:GetColorRGB(); set(item,r,g,b,a) end
								item.opacityFunc = function() local r,g,b = get(item); set(item,r,g,b,picker_get_alpha()); end
								item.cancelFunc = function(c) set(item, picker_get_prev_color(c)); end
							end
							item.r, item.g, item.b, item.opacity = item.get(item)
							item.opacity = 1 - item.opacity
						end
						item.index = index
						UIDropDownMenu_AddButton(item,level)
					end
				end
			end
		end
		-- get the MENU_LEVEL of the specified menu element ( element = DropDownList|button|nil )
		function getMenuLevel(element)
			return element and ((element.dropdown and element:GetID()) or element:GetParent():GetID()) or UIDROPDOWNMENU_MENU_LEVEL
		end
		-- get the MENU_VALUE of the specified menu element ( element = level|DropDownList|button|nil )
		function getMenuValue(element)
			return element and (UIDROPDOWNMENU_OPEN_MENU.menuValues[type(element)=='table' and getMenuLevel(element) or element]) or UIDROPDOWNMENU_MENU_VALUE
		end
		-- refresh a submenu ( element = level | button | dropdownlist )
		function refreshMenu(element, hideChilds)
			local level = type(element)=='number' and element or getMenuLevel(element)
			if hideChilds then CloseDropDownMenus(level+1) end
			local frame = _G["DropDownList"..level]
			if frame and frame:IsShown() then
				local _, anchorTo = frame:GetPoint(1)
				if anchorTo and anchorTo.menuList then
					ToggleDropDownMenu(level, getMenuValue(level), nil, nil, nil, nil, anchorTo.menuList, anchorTo)
					return true
				end
			end
		end
		-- show my enhanced popup menu
		function showMenu(menuList, menuFrame, anchor, x, y, autoHideDelay )
			menuFrame = menuFrame or CreateFrame("Frame", "KiwiFarmPopupMenu", UIParent, "UIDropDownMenuTemplate")
			menuFrame.displayMode = "MENU"
			menuFrame.menuValues = menuFrame.menuValues  or {}
			UIDropDownMenu_Initialize(menuFrame, initialize, "MENU", nil, menuList);
			ToggleDropDownMenu(1, nil, menuFrame, anchor, x, y, menuList, nil, autoHideDelay);
		end
	end
	-- menu definition helper functions
	local defMenuStart, defMenuAdd, defMenuEnd, splitMenu, wipeMenu
	do
		-- store unused tables to avoid generate garbage
		local tables = {}
		-- clear menu table, preserving special control fields
		function wipeMenu(menu)
			local init = menu.init;	wipe(menu); menu.init = init
		end
		-- split a big menu items table in several submenus
		function splitMenu(menu, fsort, fdisp)
			local count = #menu
			if count>1 then
				local max = math.ceil( count/math.ceil(count/28) )
				fsort = fsort or 'text'
				fdisp = fdisp or fsort
				table.sort(menu, function(a,b) return a[fsort]<b[fsort] end )
				local items, first, last
				if count>max then
					for i=1,count do
						if not items or #items>=max then
							if items then
								menu[#menu].text = strfirstword(first[fdisp]) .. ' - ' .. strfirstword(last[fdisp])
							end
							items = {}
							tinsert(menu, { notCheckable = true, hasArrow = true, useParentValue = true, menuList = items } )
							first = menu[1]
						end
						last = table.remove(menu,1)
						tinsert(items, last)
					end
					menu[#menu].text = strfirstword(first[fdisp]) .. ' - ' .. strfirstword(last[fdisp])
					menu._split = true
					return true
				end
			end
		end
		-- start menu definition
		function defMenuStart(menu)
			local split = menu._split
			for _,item in ipairs(menu) do
				if split and item.menuList then
					for _,item in ipairs(item.menuList) do
						tables[#tables+1] = item; wipe(item)
					end
				end
				tables[#tables+1] = item; wipe(item)
			end
			wipeMenu(menu)
		end
		-- add an item to the menu
		function defMenuAdd(menu, text, value, menuList)
			local item = tremove(tables) or {}
			item.text, item.value, item.notCheckable, item.menuList, item.hasArrow = text, value, true, menuList, (menuList~=nil) or nil
			menu[#menu+1] = item
			return item
		end
		-- end menu definition
		function defMenuEnd(menu, text)
			if #menu==0 and text then
				menu[1] = tremove(tables) or {}
				menu[1].text, menu[1].notCheckable = text, true
			end
		end
	end

	-- here starts the definition of the KiwiFrame menu
	local stats -- reference to table stats data ( = config.session | config.total | config.zone[key] | config.daily[key] )
	local stats_duration, stats_goldhour -- last submenu stats data cached
	local openedFromMain -- was the menu opened from the main window ?
	local function InitPriceSources(menu)
		for i=#menu,1,-1 do
			local arg = menu[i].arg1
			if (arg =='Atr' and not Atr_GetAuctionPrice and not Auctionator) or (arg =='TSM' and not TSM_API) or (arg == 'Aux' and not aux_frame) or (arg == 'REC' and not RECrystallize_PriceCheck) then
				tremove(menu,i)
			end
		end
		menu.init = nil -- means do not call the function anymore
	end
	local function SetWidth(info)
		config.frameWidth = info.value~=0 and math.max( (config.frameWidth or addon:GetWidth()) + info.value, 50) or nil
		LayoutFrame()
	end
	local function SetMargin(info)
		config.frameMargin = info.value~=0 and math.max( (config.frameMargin or 4) + info.value, 0) or 4
		LayoutFrame()
	end
	local function SetFontSize(info)
		config.fontSize = info.value~=0 and math.max( (config.fontSize or 14) + info.value, 5) or 14
		LayoutFrame()
	end
	local function StrataChecked(info)
		return info.value == (config.frameStrata or 'MEDIUM')
	end
	local function SetStrata(info)
		config.frameStrata = info.value~='MEDIUM' and info.value or nil
		RestoreStrata()
	end
	local function AnchorChecked(info)
		return info.value == config.framePos.anchor
	end
	local function SetAnchor(info)
		config.framePos.anchor = info.value
		SavePosition()
		RestorePosition()
	end
	local function ChatFrameIdentify()
		print('|cFF7FFF72KiwiFarm:|r This is Chat Frame: Default')
		for i=1,10 do
			local f = _G['ChatFrame'..i]
			if f then f:AddMessage( '|cFF7FFF72KiwiFarm:|r This is Chat Frame: '..i ) end
		end
	end
	local function ChatFrameChecked(info)
		return info.value == (config.chatFrame or 0)
	end
	local function SetChatFrame(info)
		config.chatFrame = info.value~=0 and info.value or nil
	end
	local function MoneyFmtChecked(info)
		return info.value == (config.moneyFmt or '')
	end
	local function SetMoneyFmt(info)
		config.moneyFmt = info.value~='' and info.value or nil
		RefreshText()
	end
	local function DisplayChecked(info)
		return not disabled[info.value]
	end
	local function SetDisplay(info)
		disabled[info.value] = (not disabled[info.value]) or nil
		LayoutFrame()
	end
	local function getSessionText()
		return (session.startTime and L['Session Pause']) or (session.duration and L['Session Resume']) or L['Session Start']
	end
	local function setSessionFinish()
		addon:ConfirmDialog( L["Are you sure you want to finish current farm session ?"], SessionFinish )
	end
	local function NotifyAreaChecked(info)
		local name = config.notifyArea or 'Notification'
		if info and info.value~='' then
			return info.value == name
		else
			return name~='Notification' and name~='Incoming' and name~='Outgoing'
		end
	end
	local function SetNotifyArea(info)
		if info.value~='' then
			config.notifyArea = (info.value~='Notification') and info.value or nil
		else
			addon:EditDialog(L['|cFF7FFF72KiwiFarm|r\nChange the MSBT/Parrot2 Scroll Area name to display KiwiFarm notifications. You can leave the field blank to use the default value.'], config.notifyArea or 'Notification', function(v)
				v = strtrim(v); config.notifyArea = (v~='Notification' and v~='') and v or nil
			end)
		end
	end
	local function GetNotifyArea(info)
		return NotifyAreaChecked() and L['Other: ']..config.notifyArea or L['Set other ...']
	end
	local function GetNotifyAreaTitle()
		if MikSBT and not Parrot then
			return L['MSBT Scroll Area']
		elseif Parrot and not MikSBT then
			return L['Parrot2 Scroll Area']
		else
			return L['MSBT/Parrot2 Scroll Area']
		end
	end
	local function isPlugin()
		return config.details~=nil
	end

	-- submenu: farmZones
	local menuZones
	do
		local function ZoneAdd()
			local zone = curZoneName
			config.farmZones = config.farmZones or {}
			config.farmZones[zone] = true
			addon:ZONE_CHANGED_NEW_AREA()
			wipeMenu(menuZones)
		end
		local function ZoneDel(info)
			config.farmZones[info.value] = nil
			if not next(config.farmZones) then config.farmZones = nil end
			addon:ZONE_CHANGED_NEW_AREA()
			wipeMenu(menuZones)
		end
		menuZones = { init = function(menu)
			if not menu[1] then
				for zone in pairs(config.farmZones or {}) do
					menu[#menu+1] = { text = '(-)'..zone, value = zone, notCheckable = true, func = ZoneDel }
				end
				menu[#menu+1] = { text = L['(+)Add Current Zone'], notCheckable = true, func = ZoneAdd }
			end
		end	}
	end

	-- submenu: resets
	local menuResets = { init = function(menu)
		defMenuStart(menu)
		for _,reset in ipairs(resets) do
			defMenuAdd(menu, format(reset.reseted and "%s - %s" or "|cFF808080%s - %s|r", date("%H:%M:%S",reset.time), reset.zone) )
		end
		if VANILA and #resetsd>0 then
			defMenuAdd(menu, format("|cFFf0f000Next Daily Unlock: |r%s", FmtDuration( math.max( resetsd[1]+86400-time(),0) ) ) )
		end
		defMenuEnd(menu, L['None'])
	end	}

	-- submenu: quality sources
	local menuQualitySources
	do
		local function checked(info)
			return config.priceByQuality[getMenuValue(info)][info.value]
		end
		local function set(info)
			local sources = config.priceByQuality[getMenuValue(info)]
			sources[info.value] = (not sources[info.value]) or nil
		end
		menuQualitySources = {
			{ text = L['Vendor Price'],                value = 'vendor',                       isNotRadio = true, keepShownOnClick = 1, checked = checked, func = set },
			{ text = L['Auctionator: Market Value'],   value = 'Atr:DBMarket',   arg1 = 'Atr', isNotRadio = true, keepShownOnClick = 1, checked = checked, func = set },
			{ text = L['Auctionator: Disenchant'],     value = 'Atr:Destroy' ,   arg1 = 'Atr', isNotRadio = true, keepShownOnClick = 1, checked = checked, func = set },
			{ text = L['TSM: Market Value'],           value = 'DBMarket',       arg1 = 'TSM', isNotRadio = true, keepShownOnClick = 1, checked = checked, func = set },
			{ text = L['TSM: Historical'],             value = 'DBHistorical',   arg1 = 'TSM', isNotRadio = true, keepShownOnClick = 1, checked = checked, func = set },
			{ text = L['TSM: Recent'],           	   value = 'DBRecent',       arg1 = 'TSM', isNotRadio = true, keepShownOnClick = 1, checked = checked, func = set },
			{ text = L['TSM: Min Buyout'],             value = 'DBMinBuyout',    arg1 = 'TSM', isNotRadio = true, keepShownOnClick = 1, checked = checked, func = set },
			{ text = L['TSM: Disenchant'],             value = 'Destroy',        arg1 = 'TSM', isNotRadio = true, keepShownOnClick = 1, checked = checked, func = set },
			{ text = L['Aux: Market Value'],           value = 'Aux:Market',     arg1 = 'Aux', isNotRadio = true, keepShownOnClick = 1, checked = checked, func = set },
			{ text = L['Aux: Min Buyout'],             value = 'Aux:MinBuyout',  arg1 = 'Aux', isNotRadio = true, keepShownOnClick = 1, checked = checked, func = set },
			{ text = L['Aux: Disenchant'],             value = 'Aux:Disenchant', arg1 = 'Aux', isNotRadio = true, keepShownOnClick = 1, checked = checked, func = set },
			{ text = L['RECrystallize: Market Value'], value = 'REC:Market',     arg1 = 'REC', isNotRadio = true, keepShownOnClick = 1, checked = checked, func = set },
			init = InitPriceSources
		}
	end

	-- submenus: item sources, price sources
	local menuPriceItems, menuItemSources
	do
		-- hackish way to refresh the price of the items in the parent buttons (quality money & item money).
		-- parent buttons must set arg2 = function that returns the text to display (see menuLootedItems init code)
		local function refreshParentButtons(info)
			local button = select(2, info:GetParent():GetPoint())
			if button and type(button.arg2) == 'function' then
				UIDropDownMenu_SetButtonText(getMenuLevel(button), button:GetID(), button.arg2(button))
				local button = select(2, button:GetParent():GetPoint())
				if button and type(button.arg2) == 'function' then
					UIDropDownMenu_SetButtonText(getMenuLevel(button), button:GetID(), button.arg2(button))
				end
			end
		end
		local function deleteItem(itemLink, confirm)
			if not confirm then
				config.priceByItem[itemLink] = nil
				wipeMenu(menuPriceItems)
				AdjustLootedItemMoneyStats(itemLink)
				return
			end
			C_Timer.After(.1,function()
				addon:ConfirmDialog( format(L["%s\nThis item has no defined price. Do you want to delete this item?"],itemLink), function() deleteItem(itemLink) end)
			end)
		end
		local function setItemPriceSource(info, itemLink, source, value)
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
					deleteItem(itemLink, info.arg2 )
				end
			end
			AdjustLootedItemMoneyStats(itemLink)
			refreshParentButtons(info)
		end
		local function getItemPriceSource(itemLink, source)
			local sources  = config.priceByItem[itemLink]
			return sources and sources[source]
		end
		local function checked(info)
			return getItemPriceSource(getMenuValue(info), info.value)
		end
		local function set(info)
			info.arg2 = getMenuValue(getMenuLevel(info)-1)=='specific'
			local itemLink, empty = getMenuValue(info)
			if info.value=='user' then
				local price    = FmtMoneyPlain( getItemPriceSource(itemLink,'user') ) or ''
				addon:EditDialog(L['|cFF7FFF72KiwiFarm|r\n Set a custom price for:\n'] .. itemLink, price, function(v)
					setItemPriceSource(info, itemLink, 'user', String2Copper(v))
				end)
			else
				setItemPriceSource(info, itemLink, info.value , not getItemPriceSource(itemLink, info.value))
			end
		end
		local function getText(info, level)
			local price = getItemPriceSource(getMenuValue(level),'user')
			return format( L['Price: %s'], price and FmtMoneyShort(price) or L['Not Defined'])
		end
		-- submenu: item price sources
		menuItemSources = {
			{ text = getText,	  				       value = 'user',                         isNotRadio = true, keepShownOnClick = 1, checked = checked, func = set },
			{ text = L['Vendor Price'],                value = 'vendor',                       isNotRadio = true, keepShownOnClick = 1, checked = checked, func = set },
			{ text = L['Auctionator: Market Value'],   value = 'Atr:DBMarket',   arg1 = 'Atr', isNotRadio = true, keepShownOnClick = 1, checked = checked, func = set },
			{ text = L['Auctionator: Disenchant'],     value = 'Atr:Destroy' ,   arg1 = 'Atr', isNotRadio = true, keepShownOnClick = 1, checked = checked, func = set },
			{ text = L['TSM: Market Value'],           value = 'DBMarket',       arg1 = 'TSM', isNotRadio = true, keepShownOnClick = 1, checked = checked, func = set },
			{ text = L['TSM: Historical'],             value = 'DBHistorical',   arg1 = 'TSM', isNotRadio = true, keepShownOnClick = 1, checked = checked, func = set },
			{ text = L['TSM: Recent'],           	   value = 'DBRecent',       arg1 = 'TSM', isNotRadio = true, keepShownOnClick = 1, checked = checked, func = set },
			{ text = L['TSM: Min Buyout'],             value = 'DBMinBuyout',    arg1 = 'TSM', isNotRadio = true, keepShownOnClick = 1, checked = checked, func = set },
			{ text = L['TSM: Disenchant'],             value = 'Destroy',        arg1 = 'TSM', isNotRadio = true, keepShownOnClick = 1, checked = checked, func = set },
			{ text = L['Aux: Market Value'],           value = 'Aux:Market',     arg1 = 'Aux', isNotRadio = true, keepShownOnClick = 1, checked = checked, func = set },
			{ text = L['Aux: Min Buyout'],             value = 'Aux:MinBuyout',  arg1 = 'Aux', isNotRadio = true, keepShownOnClick = 1, checked = checked, func = set },
			{ text = L['Aux: Disenchant'],             value = 'Aux:Disenchant', arg1 = 'Aux', isNotRadio = true, keepShownOnClick = 1, checked = checked, func = set },
			{ text = L['RECrystallize: Market Value'], value = 'REC:Market',     arg1 = 'REC', isNotRadio = true, keepShownOnClick = 1, checked = checked, func = set },
			init = InitPriceSources,
		}
		-- submenu: individual items prices
		menuPriceItems = { init = function(menu)
			if not menu[1] then
				for itemLink,sources in pairs(config.priceByItem) do
					local name = strmatch(itemLink, '%|h%[(.+)%]%|h')
					tinsert( menu, { text = itemLink, value = itemLink, arg1 = name, notCheckable = true, hasArrow = true, menuList = menuItemSources } )
				end
				splitMenu(menu, 'arg1')
			end
		end	}
	end

	-- submenu: looted items
	local menuLootedItems
	do
		local function getText(info)
			local data = stats.lootedItems and stats.lootedItems[info.value]
			return data and format("%sx%d %s", info.value, data[2], FmtMoneyShort(data[1])) or info.value
		end
		menuLootedItems = { init = function(menu, level)
			local value = getMenuValue(level)
			if timeLootedItems>(menu.time or -1) or value~=menu.value then
				defMenuStart(menu)
				if stats.lootedItems then
					for itemLink in pairs(stats.lootedItems) do
						if type(value)~='number' or value==select(3,GetItemInfo(itemLink)) then
							local name = strmatch(itemLink, '%|h%[(.+)%]%|h')
							local item = defMenuAdd(menu, getText, itemLink, menuItemSources)
							item.arg1, item.arg2 = name, getText
						end
					end
				end
				defMenuEnd(menu,'None')
				splitMenu(menu, 'arg1')
				menu.time  = timeLootedItems
				menu.value = value
			end
		end }
	end

	-- submenu: killed Mobs
	local menuKilledMobs
	do
		local function getText(info)
			local value = stats.killedMobs[info.value]
			return value and format("%s: %d", info.value, value ) or L['None']
		end
		menuKilledMobs = {
			init = function(menu)
				defMenuStart(menu)
				for name, count in pairs(stats.killedMobs) do
					defMenuAdd( menu, getText, name )
				end
				defMenuEnd(menu,L['None'])
				splitMenu(menu, 'value')
			end
		}
	end

	-- submenu: fonts
	local menuFonts
	do
		local function set(info)
			config.fontName = info.value
			LayoutFrame()
			refreshMenu()
		end
		local function checked(info)
			return info.value == (config.fontName or FONTS.Arial)
		end
		menuFonts  = { init = function(menu)
			local media = LibStub("LibSharedMedia-3.0", true)
			for name, key in pairs(media and media:HashTable('font') or FONTS) do
				tinsert( menu, { text = name, value = key, keepShownOnClick = 1, func = set, checked = checked } )
			end
			splitMenu(menu)
			menu.init = nil -- do not call this init function anymore
		end }
	end

	-- submenu: background textures
	local menuBorderTextures
	do
		local function set(info)
			config.borderTexture = info.value~='' and info.value or nil
			SetBackground()
			refreshMenu()
		end
		local function checked(info)
			return info.value == (config.borderTexture or '')
		end
		menuBorderTextures  = { init = function(menu)
			local media = LibStub("LibSharedMedia-3.0", true)
			for name, key in pairs(media and media:HashTable('border') or BORDERS) do
				tinsert( menu, { text = name, value = key, keepShownOnClick = 1, func = set, checked = checked } )
			end
			splitMenu(menu)
			menu.init = nil -- do not call this init function anymore
		end }
	end

	-- submenu: sounds
	local menuSounds
	do
		-- groupKey = qualityID | 'price'
		local function set(info)
			local sound, groupKey = info.value, getMenuValue(info)
			notify.sound[groupKey] = sound
			PlaySoundFile(sound,"master")
			refreshMenu()
		end
		local function checked(info)
			local sound, groupKey = info.value, getMenuValue(info)
			return notify.sound[groupKey] == sound
		end
		menuSounds = { init = function(menu)
			local blacklist = { ['None']=true, ['BugSack: Fatality']=true }
			local media = LibStub("LibSharedMedia-3.0", true)
			if media then
				for name,fileID in pairs(SOUNDS) do
					media:Register("sound", name, fileID)
				end
			end
			for name, key in pairs(media and media:HashTable('sound') or SOUNDS) do
				if not blacklist[name] then
					tinsert( menu, { text = name, value = key, arg1=strlower(name), func = set, checked = checked, keepShownOnClick = 1 } )
				end
			end
			splitMenu(menu, 'arg1', 'text')
			menu.init = nil -- do not call this init function anymore
		end }
	end

	-- submenu: notify
	local menuNotify
	do
		-- info.value = qualityID | 'price' ; info.arg1 = 'chat'|'combat'|'crit'|'sound'
		local notifyAddons =  { msbt = L['MSBT: '], parrot = L['Parrot2: '] }
		local function notifyText(info)
			local msg = notifyAddons[info.arg1]
			return msg and msg..(config.notifyArea or 'Notification') or info.arg2
		end
		local function initText(info, level)
			local groupKey = info.value
			if type(groupKey) ~= 'number' then -- special cases ('price' and 'money' groups notifications require a minimum price/gold amount)
				local price = notify[groupKey] and notify[groupKey][info.arg1]
				return price and format("%s (+%s)", notifyText(info), FmtMoneyShort(price)) or format(L["%s (click to set price)"], notifyText(info))
			end
			return notifyText(info)
		end
		local function checked(info)
			local groupKey, channelKey = info.value, info.arg1
			return notify[groupKey] and notify[groupKey][channelKey]~=nil
		end
		local function set(info,value)
			local groupKey, channelKey = info.value, info.arg1
			notify[groupKey] = notify[groupKey] or {}
			notify[groupKey][channelKey] = value or nil
			if not next(notify[groupKey]) then notify[groupKey] = nil end
			if channelKey=='sound' then -- special case for sounds
				notify.sound[groupKey] = nil
				refreshMenu(getMenuLevel(info), true)
			end
		end
		local function setNotify(info)
			if type(info.value) ~= 'number' then -- 'price' & 'money' groups
				local price = notify[info.value] and notify[info.value][info.arg1]
				addon:EditDialog(L['|cFF7FFF72KiwiFarm|r\nSet the minimum gold amount to display a notification. You can leave the field blank to remove the minimum gold.'], FmtMoneyPlain(price), function(v)
					set(info, String2Copper(v) )
					refreshMenu(info)
				end)
			else -- quality groups (0-5)
				set(info, not checked(info) and 0)
			end
		end
		menuNotify = {
			{ text = initText, useParentValue = true, arg1 = 'chat',   arg2 = L['Chat Text'],   		    isNotRadio = true, keepShownOnClick = 1, checked = checked, func = setNotify },
			{ text = initText, useParentValue = true, arg1 = 'combat', arg2 = L['CombatText: Scroll'],   	isNotRadio = true, keepShownOnClick = 1, checked = checked, func = setNotify },
			{ text = initText, useParentValue = true, arg1 = 'crit',   arg2 = L['CombatText: Crit'],    	isNotRadio = true, keepShownOnClick = 1, checked = checked, func = setNotify },
			{ text = initText, useParentValue = true, arg1 = 'msbt',   arg2 = 'MSBT', 	    				isNotRadio = true, keepShownOnClick = 1, checked = checked, func = setNotify },
			{ text = initText, useParentValue = true, arg1 = 'parrot', arg2 = 'Parrot2', 					isNotRadio = true, keepShownOnClick = 1, checked = checked, func = setNotify },
			{ text = initText, useParentValue = true, arg1 = 'sound',  arg2 = L['Sound'],       		    isNotRadio = true, keepShownOnClick = 1, checked = checked, func = setNotify },
			init = function(menu, level)
				local groupKey = getMenuValue(level)
				local value = notify[groupKey] and notify[groupKey].sound
				menu[#menu].hasArrow = value and true or nil
				menu[#menu].menuList = value and menuSounds or nil
			end,
		}
	end

	-- submenu: gold earned by item quality
	local menuGoldQuality
	do
		local function getText(info)
			local quality = info.value
			return format( "%s: %s (%d)", FmtQuality(quality), FmtMoney(stats.moneyByQuality[quality] or 0), stats.countByQuality[quality] or 0)
		end
		menuGoldQuality = {
			{ text = getText, arg2 = getText, notCheckable = true, hasArrow = true, value = 0, menuList = menuLootedItems },
			{ text = getText, arg2 = getText, notCheckable = true, hasArrow = true, value = 1, menuList = menuLootedItems },
			{ text = getText, arg2 = getText, notCheckable = true, hasArrow = true, value = 2, menuList = menuLootedItems },
			{ text = getText, arg2 = getText, notCheckable = true, hasArrow = true, value = 3, menuList = menuLootedItems },
			{ text = getText, arg2 = getText, notCheckable = true, hasArrow = true, value = 4, menuList = menuLootedItems },
		}
	end

	-- submenu: stats maintenance
	local menuStatsMisc = {
		{ text = L['Clear looted items'],  disabled = function() return not next(stats.lootedItems) end, notCheckable = true, func = function()
			addon:ConfirmDialog( L["Are you sure you want to delete all looted items stored in this section ?"], function()
				wipe(stats.lootedItems)
				timeLootedItems = time()
			end)
		end	},
		{ text = L['Clear killed mobs'],  disabled = function() return not next(stats.killedMobs) end, notCheckable = true, func = function()
			addon:ConfirmDialog( L["Are you sure you want to delete all killed mobs stored in this section ?"], function()
				wipe(stats.killedMobs)
			end)
		end	},
		{ text = L['Clear all data'], notCheckable = true, func = function()
			local stats = stats
			addon:ConfirmDialog( L["Are you sure you want to delete all data in this section ?"], function()
				if stats._type then
					config[stats._type][stats._key] = nil  -- zone & daily
				else
					InitDB(stats, DEFDATA, true) -- session & total
				end
				CloseDropDownMenus()
			end)
		end },
	}

	-- submenu: report to
	local menuReportTo
	do
		local titles = {
			daily   = L["Farm Date: %s"],
			zone    = L["Farm Zone: %s"],
		}
		local function channelHidden(info)
			if info.value=='PARTY' then
				return not IsInGroup(LE_PARTY_CATEGORY_HOME)
			elseif info.value=='RAID' then
				return not IsInRaid(LE_PARTY_CATEGORY_HOME)
			elseif info.value=='GUILD' then
				return not GetGuildInfo("player")
			end
		end
		local function reportStats(channel, player)
			SendChatMessage( ':::::::::KiwiFarm Report:::::::::', channel, nil, player )
			if stats._key then
				SendChatMessage( format(titles[stats._type],stats._key), channel, nil, player)
			end
			SendChatMessage( format(L["Farm Time: %s"], FmtDuration(stats_duration)), channel, nil, player )
			SendChatMessage( format(L["Mobs killed: %d"], stats.countMobs), channel, nil, player )
			SendChatMessage( format(L["Items looted: %d"], stats.countItems), channel, nil, player )
			SendChatMessage( format(L["Gold quests: %s"], FmtMoneyPlain(stats.moneyQuests)),  channel, nil, player )
			SendChatMessage( format(L["Gold cash: %s"], FmtMoneyPlain(stats.moneyCash)),  channel, nil, player )
			SendChatMessage( format(L["Gold items: %s"], FmtMoneyPlain(stats.moneyItems)), channel, nil, player )
			SendChatMessage( format(L["Gold/hour: %s"], FmtMoneyPlain(stats_goldhour)),  channel, nil, player )
			SendChatMessage( format(L["Gold total: %s"], FmtMoneyPlain(stats.moneyCash+stats.moneyItems+stats.moneyQuests)), channel, nil, player )
		end
		local function reportChannel(info)
			reportStats(info.value)
		end
		local function reportWhisper(info)
			addon:EditDialog( L["Type Player Name:"], '', function(player)
				player = strtrim(player)
				if player~='' then
					reportStats('WHISPER', player)
				end
			end )
		end
		menuReportTo = {
			{ text = L['Guild'],   notCheckable = true, value = 'GUILD',   hidden = channelHidden, func = reportChannel },
			{ text = L['Party'],   notCheckable = true, value = 'PARTY',   hidden = channelHidden, func = reportChannel },
			{ text = L['Raid'],    notCheckable = true, value = 'RAID',    hidden = channelHidden, func = reportChannel },
			{ text = L['Whisper'], notCheckable = true, value = 'WHISPER', hidden = channelHidden, func = reportWhisper },
		}
	end

	-- submenu: stats
	local menuStats = {
		{ notCheckable = true },
		{ notCheckable = true },
		{ notCheckable = true },
		{ notCheckable = true },
		{ notCheckable = true },
		{ notCheckable = true },
		{ text = L['Looted Items'], notCheckable = true, hasArrow = true, menuList = menuGoldQuality },
		{ text = L['Killed Mobs'],  notCheckable = true, hasArrow = true, menuList = menuKilledMobs  },
		{ text = L['Maintenance'],  notCheckable = true, hasArrow = true, menuList = menuStatsMisc   },
		{ text = L['Report To'],    notCheckable = true, hasArrow = true, menuList = menuReportTo    },
		init = function(menu,level)
			local curTime = time()
			local field = getMenuValue(level)
			stats = config[field] or field
			local money = stats.moneyCash+stats.moneyItems+stats.moneyQuests
			local duration = curTime - (stats.startTime or curTime) + (stats.duration or 0)
			local mhour = duration>0 and floor(money*3600/duration) or 0
			local ftime = (stats.duration or 0) + curTime - (stats.startTime or curTime)
			menu[1].text = format(L["Farm Time: %s"], FmtDuration(ftime))
			menu[2].text = format(L["Gold quests: %s"], FmtMoney(stats.moneyQuests))
			menu[3].text = format(L["Gold cash: %s"], FmtMoney(stats.moneyCash))
			menu[4].text = format(L["Gold items: %s"], FmtMoney(stats.moneyItems))
			menu[5].text = format(L["Gold/hour: %s"], FmtMoney(mhour))
			menu[6].text = format(L["Gold total: %s"], FmtMoney(money))
			menu[7].text = format(L["Items looted (%d)"], stats.countItems)
			menu[8].text = format(L["Mobs killed (%d)"], stats.countMobs)
			stats_duration, stats_goldhour = ftime, mhour
			timeLootedItems = curTime
		end,
	}

	-- submenu: daily stats
	local menuDaily = {	init = function(menu)
		defMenuStart(menu)
		local tim, pre, key = time()
		for i=1,7 do
			key, pre = date("%Y/%m/%d", tim), pre and date("%m/%d", tim) or L['Today']
			local data = config.daily[key]
			if data then
				local money = data and data.moneyCash+data.moneyItems+data.moneyQuests or 0
				defMenuAdd(menu, format('%s: %s', pre, FmtMoney(money)), data, menuStats)
			else
				defMenuAdd(menu, format('%s: -', pre))
			end
			tim = tim - 86400
		end
		defMenuEnd(menu, L['None'])
		while #menu>1 and menu[#menu].value==nil do
			tremove(menu)
		end
	end	}

	-- submenu: zone stats
	local menuZone = {
		init = function(menu)
			defMenuStart(menu)
			for zoneName, data in pairs(config.zone) do
				defMenuAdd(menu, zoneName, data, menuStats)
			end
			defMenuEnd(menu, L['None'])
		end
	}

	-- submenu: data collect
	local menuCollect
	do
		local function checked(info)
			return not collect[info.value][info.arg1]
		end
		local function set(info)
			collect[info.value][info.arg1] = not collect[info.value][info.arg1] or nil
		end
		menuCollect = {
			{ text = L['Total Stats'], notCheckable = true, isTitle = true},
			{ text = L['Detailed mobs info'],  value = 'total', arg1 = 'killedMobs',  keepShownOnClick = 1, isNotRadio = true, checked = checked, func = set },
			{ text = L['Detailed items info'], value = 'total', arg1 = 'lootedItems', keepShownOnClick = 1, isNotRadio = true, checked = checked, func = set },
			{ text = L['Daily Stats'],  notCheckable = true, isTitle = true},
			{ text = L['Detailed mobs info'],  value = 'daily', arg1 = 'killedMobs',  keepShownOnClick = 1, isNotRadio = true, checked = checked, func = set },
			{ text = L['Detailed items info'], value = 'daily', arg1 = 'lootedItems', keepShownOnClick = 1, isNotRadio = true, checked = checked, func = set },
			{ text = L['Zone Stats'],   notCheckable = true, isTitle = true},
			{ text = L['Detailed mobs info'],  value = 'zone',  arg1 = 'killedMobs',  keepShownOnClick = 1, isNotRadio = true, checked = checked, func = set },
			{ text = L['Detailed items info'], value = 'zone',  arg1 = 'lootedItems', keepShownOnClick = 1, isNotRadio = true, checked = checked, func = set },
		}
	end

	-- submenu: reset notification
	local menuResetNotify
	do
		local function checked(info)
			return config.resetsNotify[info.value]
		end
		local function set(info)
			config.resetsNotify[info.value] = (not config.resetsNotify[info.value]) or nil
		end
		local function setMessage(info)
			addon:EditDialog(L['|cFF7FFF72KiwiFarm|r\nSet a message to send to your party or raid when instances are reset. You can leave the field blank to disable the notification.'],
				config.resetsNotify.message,
				function(v) config.resetsNotify.message = strtrim(v)~='' and v or nil; end
			)
		end
		menuResetNotify = {
			{ text = L['Reset Message'],  notCheckable = true, isTitle = true},
			{ text = '', notCheckable = true, func = setMessage },
			{ text = L['Notification Channels'], notCheckable = true, isTitle = true},
			{ text = L['Party'],        value = 'PARTY',        keepShownOnClick = 1, isNotRadio = true, checked = checked, func = set },
			{ text = L['Raid'],         value = 'RAID',         keepShownOnClick = 1, isNotRadio = true, checked = checked, func = set },
			{ text = L['Raid Warning'], value = 'RAID_WARNING', keepShownOnClick = 1, isNotRadio = true, checked = checked, func = set },
			init = function(menu)
				menu[2].text = config.resetsNotify.message or L['(click to set)']
			end,
		}
	end

	-- menu: main
	local menuMain = {
		{ text = L['Kiwi Farm [/kfarm]'], notCheckable = true, isTitle = true },
		{ text = getSessionText, notCheckable = true, func = SessionTogglePause },
		{ text = L['Session Finish'],     notCheckable = true, disabled = function() return not (session.startTime or session.duration) end, func = setSessionFinish },
		{ text = L['Reset Instances'],    notCheckable = true, func = ResetInstances },
		{ text = L['Reset XP Info'],      notCheckable = true, func = LevelingReset, hidden = function() return not isPlayerLeveling end },
		{ text = L['Statistics'],         notCheckable = true, isTitle = true },
		{ text = L['Session'],            notCheckable = true, hasArrow = true, value = 'session', menuList = menuStats },
		{ text = L['Daily'],              notCheckable = true, hasArrow = true, menuList = menuDaily },
		{ text = L['Zones'],              notCheckable = true, hasArrow = true, menuList = menuZone },
		{ text = L['Totals'],             notCheckable = true, hasArrow = true, value = 'total',   menuList = menuStats },
		{ text = L['Resets'],             notCheckable = true, hasArrow = true, menuList = menuResets },
		{ text = L['Settings'],           notCheckable = true, isTitle = true },
		{ text = L['Session Control'], notCheckable = true, hasArrow = true, menuList = {
			{ text = L['Start/Resume session on Login'],   isNotRadio = true, keepShownOnClick = 1, checked = function() return config.farmAutoStart; end, func = function() config.farmAutoStart = (not config.farmAutoStart) or nil; end },
			{ text = L['Finish session on Logout'], isNotRadio = true, keepShownOnClick = 1, checked = function() return config.farmAutoFinish; end, func = function() config.farmAutoFinish = (not config.farmAutoFinish) or nil; end },
			{ text = L['Start session on entering Zones'],  isNotRadio = true, keepShownOnClick = 1, checked = function() return not config.farmDisableZones; end, func = function() config.farmDisableZones = (not config.farmDisableZones) or nil; end, hasArrow = true, menuList = menuZones },
		} },
		{ text = L['Display Info'], notCheckable= true, hasArrow = true, menuList = {
			{ text = L['Lock&Resets'],      value = 'reset',      isNotRadio = true, keepShownOnClick = 1, checked = DisplayChecked, func = SetDisplay },
			{ text = L['Mobs&Items Count'], value = 'count',      isNotRadio = true, keepShownOnClick = 1, checked = DisplayChecked, func = SetDisplay },
			{ text = L['Gold Earned'],      value = 'gold',       isNotRadio = true, keepShownOnClick = 1, checked = DisplayChecked, func = SetDisplay },
			{ text = L['Gold by Quality'],  value = 'quality',    isNotRadio = true, keepShownOnClick = 1, checked = DisplayChecked, func = SetDisplay },
			{ text = L['Gold quests'],      value = 'quests',     isNotRadio = true, keepShownOnClick = 1, checked = DisplayChecked, func = SetDisplay },
			{ text = L['Leveling XP Info'], value = 'experience', isNotRadio = true, keepShownOnClick = 1, checked = DisplayChecked, func = SetDisplay },
		} },
		{ text = L['Prices of Items'], notCheckable = true, hasArrow = true, menuList = {
			{ text = FmtQuality(0), value = 0, notCheckable= true, hasArrow = true, menuList = menuQualitySources },
			{ text = FmtQuality(1), value = 1, notCheckable= true, hasArrow = true, menuList = menuQualitySources },
			{ text = FmtQuality(2), value = 2, notCheckable= true, hasArrow = true, menuList = menuQualitySources },
			{ text = FmtQuality(3), value = 3, notCheckable= true, hasArrow = true, menuList = menuQualitySources },
			{ text = FmtQuality(4), value = 4, notCheckable= true, hasArrow = true, menuList = menuQualitySources },
			{ text = FmtQuality(5), value = 5, notCheckable= true, hasArrow = true, menuList = menuQualitySources },
			{ text = L['Specific Items'], notCheckable= true, hasArrow = true, value = 'specific', menuList = menuPriceItems },
			{ text = L['Ignore enchanting mats'], isNotRadio = true, keepShownOnClick = 1,
				checked = function() return config.ignoreEnchantingMats; end,
				func = function() config.ignoreEnchantingMats = not config.ignoreEnchantingMats or nil; end
			},
		} },
		{ text = L['Notifications'], notCheckable = true, hasArrow = true, menuList = {
			{ text = FmtQuality(0),  value = 0, notCheckable = true, hasArrow = true, menuList = menuNotify },
			{ text = FmtQuality(1),  value = 1, notCheckable = true, hasArrow = true, menuList = menuNotify },
			{ text = FmtQuality(2),  value = 2, notCheckable = true, hasArrow = true, menuList = menuNotify },
			{ text = FmtQuality(3),  value = 3, notCheckable = true, hasArrow = true, menuList = menuNotify },
			{ text = FmtQuality(4),  value = 4, notCheckable = true, hasArrow = true, menuList = menuNotify },
			{ text = FmtQuality(5),  value = 5, notCheckable = true, hasArrow = true, menuList = menuNotify },
			{ text = L['All Items looted'], value = 'price', notCheckable = true, hasArrow = true, menuList = menuNotify },
			{ text = L['Money looted'], value = 'money', notCheckable = true, hasArrow = true, menuList = menuNotify },
		} },
		{ text = L['Appearance'], notCheckable= true, hasArrow = true, menuList = {
			{ text = L['Frame Strata'], hidden = isPlugin, notCheckable= true, hasArrow = true, menuList = {
				{ text = L['HIGH'],    value = 'HIGH',   checked = StrataChecked, func = SetStrata },
				{ text = L['MEDIUM'],  value = 'MEDIUM', checked = StrataChecked, func = SetStrata },
				{ text = L['LOW'],     value = 'LOW',  	 checked = StrataChecked, func = SetStrata },
			} },
			{ text = L['Frame Anchor'], hidden = isPlugin, notCheckable= true, hasArrow = true, menuList = {
				{ text = L['Top Left'],     value = 'TOPLEFT',     checked = AnchorChecked, func = SetAnchor },
				{ text = L['Top Right'],    value = 'TOPRIGHT',    checked = AnchorChecked, func = SetAnchor },
				{ text = L['Bottom Left'],  value = 'BOTTOMLEFT',  checked = AnchorChecked, func = SetAnchor },
				{ text = L['Bottom Right'], value = 'BOTTOMRIGHT', checked = AnchorChecked, func = SetAnchor },
				{ text = L['Left'],   		 value = 'LEFT',   		checked = AnchorChecked, func = SetAnchor },
				{ text = L['Right'],  		 value = 'RIGHT',  		checked = AnchorChecked, func = SetAnchor },
				{ text = L['Top'],    		 value = 'TOP',    		checked = AnchorChecked, func = SetAnchor },
				{ text = L['Bottom'], 		 value = 'BOTTOM', 		checked = AnchorChecked, func = SetAnchor },
				{ text = L['Center'], 		 value = 'CENTER', 		checked = AnchorChecked, func = SetAnchor },
			} },
			{ text = L['Frame Width'], hidden = isPlugin, notCheckable= true, hasArrow = true, menuList = {
				{ text = L['Increase(+)'],   value =  1,  notCheckable= true, keepShownOnClick=1, func = SetWidth },
				{ text = L['Decrease(-)'],   value = -1,  notCheckable= true, keepShownOnClick=1, func = SetWidth },
				{ text = L['Default'],       value =  0,  notCheckable= true, keepShownOnClick=1, func = SetWidth },
			} },
			{ text = L['Frame Margin'], notCheckable= true, hasArrow = true, menuList = {
				{ text = L['Increase(+)'],   value =  1,  notCheckable= true, keepShownOnClick=1, func = SetMargin },
				{ text = L['Decrease(-)'],   value = -1,  notCheckable= true, keepShownOnClick=1, func = SetMargin },
				{ text = L['Default'],       value =  0,  notCheckable= true, keepShownOnClick=1, func = SetMargin },
			} },
			{ text = L['Text Size'], notCheckable= true, hasArrow = true, menuList = {
				{ text = L['Increase(+)'],  value =  1,  notCheckable= true, keepShownOnClick=1, func = SetFontSize },
				{ text = L['Decrease(-)'],  value = -1,  notCheckable= true, keepShownOnClick=1, func = SetFontSize },
				{ text = L['Default (14)'], value =  0,  notCheckable= true, keepShownOnClick=1, func = SetFontSize },
			} },
			{ text = L['Text Font'], notCheckable= true, hasArrow = true, menuList = menuFonts },
			{ text = L['Border Texture'], hidden = isPlugin, notCheckable= true, hasArrow = true, menuList = menuBorderTextures },
			{ text =L['Border color '], hidden = isPlugin, notCheckable = true, hasColorSwatch = true, hasOpacity = true,
				get = function() return unpack(config.borderColor) end,
				set = function(info, ...) config.borderColor = {...}; SetBackground(); end,
			},
			{ text =L['Background color '], notCheckable = true, hasColorSwatch = true, hasOpacity = true,
				get = function() return unpack(config.backColor) end,
				set = function(info, ...) config.backColor = {...}; SetBackground(); end,
			},
		} },
		{ text = L['Miscellaneous'], notCheckable= true, hasArrow = true, menuList = {
			{ text = L['Chat Text Frame'], notCheckable = true, hasArrow = true, menuList = {
				{ text = L['Default'],         value =  0, checked = ChatFrameChecked, func = SetChatFrame },
				{ text = L['Chat Frame'] .. ' 1',  value =  1, checked = ChatFrameChecked, func = SetChatFrame },
				{ text = L['Chat Frame'] .. ' 2',  value =  2, checked = ChatFrameChecked, func = SetChatFrame },
				{ text = L['Chat Frame'] .. ' 3',  value =  3, checked = ChatFrameChecked, func = SetChatFrame },
				{ text = L['Chat Frame'] .. ' 4',  value =  4, checked = ChatFrameChecked, func = SetChatFrame },
				{ text = L['Chat Frame'] .. ' 5',  value =  5, checked = ChatFrameChecked, func = SetChatFrame },
				{ text = L['Chat Frame'] .. ' 6',  value =  6, checked = ChatFrameChecked, func = SetChatFrame },
				{ text = L['Chat Frame'] .. ' 7',  value =  7, checked = ChatFrameChecked, func = SetChatFrame },
				{ text = L['Chat Frame'] .. ' 8',  value =  8, checked = ChatFrameChecked, func = SetChatFrame },
				{ text = L['Chat Frame'] .. ' 9',  value =  9, checked = ChatFrameChecked, func = SetChatFrame },
				{ text = L['Chat Frame'] .. ' 10', value = 10, checked = ChatFrameChecked, func = SetChatFrame },
				{ text = L['Identify Chat Frames'], notCheckable = true, func = ChatFrameIdentify },
			} },
			{ text = L['Money Format'], notCheckable = true, hasArrow = true, menuList = {
				{ text = '999|cffffd70ag|r 99|cffc7c7cfs|r 99|cffeda55fc|r', value = '', 							    checked = MoneyFmtChecked, func = SetMoneyFmt },
				{ text = '999|cffffd70ag|r 99|cffc7c7cfs|r', 				 value = '%d|cffffd70ag|r %d|cffc7c7cfs|r', checked = MoneyFmtChecked, func = SetMoneyFmt },
				{ text = '999|cffffd70ag|r', 								 value = '%d|cffffd70ag|r', 				checked = MoneyFmtChecked, func = SetMoneyFmt },
			} },
			{ text = L['Data Collection'], notCheckable= true, hasArrow = true, menuList = menuCollect },
			{ text = L['Reset Notification'],   notCheckable = true, hasArrow = true, menuList = menuResetNotify },
			{ text = GetNotifyAreaTitle, notCheckable = true, hasArrow = true, menuList = {
				{ text = 'Notification', value = 'Notification', checked = NotifyAreaChecked, func = SetNotifyArea },
				{ text = 'Incoming',     value = 'Incoming',     checked = NotifyAreaChecked, func = SetNotifyArea },
				{ text = 'Outgoing',     value = 'Outgoing',     checked = NotifyAreaChecked, func = SetNotifyArea },
				{ text = GetNotifyArea,  value = '',             checked = NotifyAreaChecked, func = SetNotifyArea },
			} },
		} },
		{ text = L['System'], notCheckable = true, hasArrow = true, menuList = {
			{ text = L['Details Plugin'], isNotRadio = true, keepShownOnClick = 1, checked = function() return config.details end,
					func = function()
						local msg = config.details and
									L["KiwiFarm stats will be displayed in a standalone window. Are you sure you want to disable KiwiFarm Details Plugin?"] or
						            L["KiwiFarm stats will be displayed in a Details window. Are you sure you want to enable KiwiFarm Details Plugin?"]
						addon:ConfirmDialog( msg, function() config.details = not config.details or nil; ReloadUI(); end)
					end,
			},
			{ text = L['Profile per Character'], isNotRadio = true, keepShownOnClick = 1, checked = function() return root.profilePerChar[charKey] end,
					func = function() addon:ConfirmDialog( L["UI must be reloaded. Are you Sure?"], function()
							root.profilePerChar[charKey] = not root.profilePerChar[charKey] or nil; ReloadUI();
					end) end,
			},
		} },
		{ text = L['Hide Window'], notCheckable = true, hidden = function() return not openedFromMain or addon.plugin~=nil end, func = function() UpdateFrameVisibility(false); end },
	}
	function addon:ShowMenu(fromMain)
		openedFromMain = fromMain
		showMenu(menuMain, menuFrame, "cursor", 0 , 0)
	end
end
