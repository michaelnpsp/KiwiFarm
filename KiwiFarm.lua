-- ============================================================================
-- KiwiFarm (C) 2019 MiCHaEL
-- ============================================================================

local addonName = ...

-- main frame
local addon = CreateFrame('Frame', "KiwiFarm", UIParent)

-- version check
local isRetailBuild = true
--[===[@non-retail@
isRetailBuild = false
--@end-non-retail@]===]
local CLASSIC = select(4,GetBuildInfo())<30000
if isRetailBuild==CLASSIC and GetAddOnMetadata("KiwiFarm","Version")~=('@'..'project-version'..'@') then
	local err = string.format("KiwiFarm Critical Error: Wrong version. This version was packaged for World of Warcraft %s.", isRetailBuild and 'Retail' or 'Classic')
	print(err); assert(false, err)
end

-- locale
local L = LibStub('AceLocale-3.0'):GetLocale('KiwiFarm', true)

-- database keys
local serverKey = GetRealmName()
local charKey   = UnitName("player") .. " - " .. serverKey

-- default values
local RESET_MAX = CLASSIC and 5 or 10
local RESET_DAY = 30
local MARGIN = 4
local COLOR_TRANSPARENT = { 0,0,0,0 }
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
local SOUNDS = CLASSIC and {
	["Auction Window Open"] = "sound/interface/auctionwindowopen.ogg",
	["Auction Window Close"] = "sound/interface/auctionwindowclose.ogg",
	["Coin" ] = "sound/interface/lootcoinlarge.ogg",
	["Money"] = "sound/interface/imoneydialogopen.ogg",
	["Level Up"] = "sound/interface/levelup.ogg",
	["Pick Up Gems"] = "sound/interface/pickup/pickupgems.ogg",
	["Player Invite"] = "sound/interface/iplayerinvitea.ogg",
	["Put Down Gems"] = "sound/interface/pickup/putdowngems.ogg",
	["PvP Enter Queue"] = "sound/spells/pvpenterqueue.ogg",
	["PvP Through Queue"] =	"sound/spells/pvpthroughqueue.ogg",
	["Raid Warning"] = "sound/interface/raidwarning.ogg",
	["Ready Check"] = "sound/interface/readycheck.ogg",
	["Quest List Open"] = "sound/interface/iquestlogopena.ogg",
} or {
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

local DEFRESET = {
	resets  = {count=0,countd=0}, -- resets per hour
	resetsd = {}, -- resets per day  (max 30, only for classic)
}

local DEFDATA = {
	-- money
	moneyCash      = 0,
	moneyItems     = 0,
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
local DEFAULT = {
	-- data/stats
	session = {},
	total   = {},
	daily   = {},
	zone    = {},
	-- fields blacklists
	collect = { total = {}, daily = {}, zone = {} },
	-- instances locks&resets per character
	resetData = {},
	-- reset chat notification
	resetsNotify = {},
	-- prices
	priceByItem = {},
	priceByQuality = { [0]={vendor=true}, [1]={vendor=true}, [2]={vendor=true}, [3]={vendor=true}, [4]={vendor=true}, [5]={vendor=true} },
	ignoreEnchantingMats = nil,
	-- farming zones
	zones = nil,
	-- loot notification
	notify = { [1]={chat=0}, [2]={chat=0}, [3]={chat=0}, [4]={chat=0}, [5]={chat=0}, sound={} },
	-- appearance
	visible     = true, -- main frame visibility
	moneyFmt    = nil,
	disabled    = { quality=true }, -- disabled text sections
	backColor 	= { 0, 0, 0, .4 },
	fontName    = nil,
	fontsize    = nil,
	framePos    = { anchor = 'TOPLEFT', x = 0, y = 0 },
	minimapIcon = { hide = false },
	-- debug
	debug = {}
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
local floor = math.floor
local strlower = strlower
local format = string.format
local band = bit.band
local strmatch = strmatch
local GetZoneText = GetZoneText
local IsInInstance = IsInInstance
local GetInstanceInfo = GetInstanceInfo
local GetItemInfo = GetItemInfo
local COPPER_PER_GOLD = COPPER_PER_GOLD
local COPPER_PER_SILVER = COPPER_PER_SILVER
local COMBATLOG_OBJECT_CONTROL_NPC = COMBATLOG_OBJECT_CONTROL_NPC

-- database references
local config   -- database realm table
local session  -- config.session
local resets   -- config.resets     instance resets table
local resetsd  -- config.resetsd
local disabled -- config.disabled   texts table
local notify   -- config.notify     notifications table
local collect  -- config.collect

-- miscellaneous variables
local inInstance
local curZoneName = ''
local combatActive
local combatCurKills = 0
local combatPreKills = 0
local timeLootedItems = 0 -- track changes in config.lootedItems table

-- main frame elements
local texture -- background texture
local textl   -- left text
local textr   -- right text
local timer   -- update timer

-- ============================================================================
-- utils & misc functions
-- ============================================================================

local function InitDB(dst, src, reset, norecurse)
	if type(dst)~="table" then
		dst = {}
	elseif reset then
		wipe(dst)
	end
	for k,v in pairs(src) do
		if type(v)=="table" and not norecurse then
			dst[k] = InitDB(dst[k] or {}, v)
		elseif dst[k]==nil then
			dst[k] = v
		end
	end
	return dst
end

local UpdateDB = CLASSIC and function(config)
	local data = config.resetData
	local char = data[charKey] or DEFRESET
	if config.resets then -- move resets per realm to resets per char (due to blizzard hotfix) but only in classic version
		char.resets = config.resets or char.resets
		config.resets  = nil
	end
	if config.resetsd then -- move resets per realm to resets per char (due to blizzard hotfix) but only in classic version
		char.resetsd = config.resetsd or char.resetsd
		config.resetsd = nil
	end
	char.resets.count  = char.resets.count  or 0
	char.resets.countd = char.resets.countd or 0
	data[charKey] = char
end or function(config)
	config.resets  = config.resets  or {}
	config.resetsd = config.resetsd or {}
	config.resets.count  = config.resets.count  or 0
	config.resets.countd = config.resets.countd or 0
end

local function AddDB(dst, src, blacklist)
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

local function GetZoneDB(key)
	key = key or curZoneName
	local data = config.zone[key]
	if not data then
		data = InitDB({ _type = 'zone', _key = key }, DEFDATA)
		config.zone[key] = data
	end
	return data
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

-- text format functions
local function strfirstword(str)
	return strmatch(str, "^(.-) ") or str
end

local function FmtQuality(i)
	return format( "|c%s%s|r", select(4,GetItemQualityColor(i)), _G['ITEM_QUALITY'..i..'_DESC'] )
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

-- dialogs
do
	local DUMMY = function() end
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
			print( fmtLoot(itemLink, quantity, money, true) )
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
				MikSBT.DisplayMessage(text, MikSBT.DISPLAYTYPE_NOTIFICATION, false, 255, 255, 255)
			else
				print(L['|cFF7FFF72KiwiFarm:|r Warning, MikScrollingCombatText addon is not installed, change the notifications setup or install MSBT.'])
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
if CLASSIC then
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
		elseif TSM_API and TSM_API.GetCustomPriceValue then -- TSM sources
			price = TSM_API.GetCustomPriceValue(source, "i:"..itemID)
		end
		return price or 0
	end
	function GetItemPrice(itemLink)
		ItemUpgradeInfo = Atr_GetAuctionPrice and Atr_CalcDisenchantPrice and LibStub('LibItemUpgradeInfo-1.0',true) -- Check if auctionator is installed
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
	-- register instance reset
	function LockAddReset(zone)
		local ctime = time()
		if CLASSIC then
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
		resets[#resets+1] =  { zone = zone, time =  ctime, reseted = ctime}
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
				if CLASSIC then
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
			if CLASSIC then
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
		text_header = text_header .. L["Gold/hour:\nGold total:"]
		text_mask   = text_mask .. "%s\n" -- money per hour
		text_mask   = text_mask .. "%s" -- money total
		textl:SetText(text_header)
	end
	-- refresh text
	function RefreshText()
		local curtime = time()
		-- delete old data
		local exptime = curtime - 3600
		while (#resets>0 and resets[1].time<exptime) or #resets>RESET_MAX do -- remove old resets(>1hour)
			LockDel(1)
		end
		if CLASSIC then
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
		local sSession = curtime - (session.startTime or curtime) + (session.duration or 0)
		local m0, s0 = floor(sSession/60), sSession%60
		local h0, m0 = floor(m0/60), m0%60
		data[#data+1] = (session.startTime and '|cFF00ff00') or (session.duration and '|cFFff8000') or '|cFFff0000'
		data[#data+1] = h0
		data[#data+1] = m0
		data[#data+1] = s0
		-- reset data
		if not disabled.reset then
			local dirtyC   = resets.countd>0 and '|cFFff8000' or '|cFF00ff00'
			local remain   = RESET_MAX-resets.count
			local timeLock = #resets>0 and resets[1].time+3600 or nil
			local sUnlock  = timeLock and timeLock-curtime or 0
			if CLASSIC then
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
		data[#data+1] = FmtMoney(session.moneyCash)
		data[#data+1] = FmtMoney(session.moneyItems)
		if not disabled.quality then
			for i=0,5 do
				data[#data+1] = FmtMoney(session.moneyByQuality[i] or 0)
			end
		end
		local total = session.moneyCash+session.moneyItems
		data[#data+1] = FmtMoney(sSession>0 and floor(total*3600/sSession) or 0)
		data[#data+1] = FmtMoney(total)
		-- set text
		textr:SetFormattedText( text_mask, unpack(data) )
		-- update timer status
		local stopped = #resets==0 and not session.startTime
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
		addon:RegisterEvent("PLAYER_REGEN_DISABLED")
		addon:RegisterEvent("PLAYER_REGEN_ENABLED")
		addon:RegisterEvent("CHAT_MSG_LOOT")
		addon:RegisterEvent("CHAT_MSG_MONEY")
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
		addon:UnregisterEvent("PLAYER_REGEN_DISABLED")
		addon:UnregisterEvent("PLAYER_REGEN_ENABLED")
		addon:UnregisterEvent("CHAT_MSG_LOOT")
		addon:UnregisterEvent("CHAT_MSG_MONEY")
	end
end

-- session finish
local function SessionFinish()
	if session.startTime or session.duration then
		local curTime     = time()
		local zoneName    = session.zoneName or curZoneName
		session.duration  = (session.duration or 0) + (curTime - (session.startTime or curTime))
		session.startTime = nil
		session.endTime   = nil
		session.zoneName  = nil
		if session.moneyCash>0 or session.moneyItems>0 or session.countItems>0 or session.countMobs>0 then
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
	addon:SetHeight( textl:GetHeight() + MARGIN*2 )
	addon:SetWidth( config.frameWidth or (textl:GetWidth() * 2.3) + MARGIN*2 )
	addon:SetScript('OnUpdate', UpdateFrameAlpha)
end

-- layout main frame
local function LayoutFrame()
	addon:SetAlpha(0)
	-- background
	texture:SetColorTexture( unpack(config.backColor or COLOR_TRANSPARENT) )
	-- text left
	textl:ClearAllPoints()
	textl:SetPoint('TOPLEFT', MARGIN, -MARGIN)
	textl:SetJustifyH('LEFT')
	textl:SetJustifyV('TOP')
	SetTextFont(textl, config.fontName, config.fontSize, 'OUTLINE')
	PrepareText()
	-- text right
	textr:ClearAllPoints()
	textr:SetPoint('TOPRIGHT', -MARGIN, -MARGIN)
	textr:SetPoint('TOPLEFT', MARGIN, -MARGIN)
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
		addon:ShowMenu()
	elseif button == 'LeftButton' and IsShiftKeyDown() then -- reset instances data
		ResetInstances()
	end
end)

-- track reset instance event
-- in classic the game displays a reset failed message so we assume the reset was sucesfully in this case (github ticket #3).
local PATTERN_RESET = '^'..INSTANCE_RESET_SUCCESS:gsub("([^%w])","%%%1"):gsub('%%%%s','(.+)')..'$'
local PATTERN_RESET_FAILED = '^'..INSTANCE_RESET_FAILED:gsub("([^%w])","%%%1"):gsub('%%%%s','(.+)')..'$'
function addon:CHAT_MSG_SYSTEM(event,msg)
	local zone = strmatch(msg,PATTERN_RESET) or ( CLASSIC and strmatch(msg,PATTERN_RESET_FAILED) )
	if zone then
		LockAddReset(zone)
		if addon:IsVisible() then
			RefreshText()
		end
		SendMessageToHomeGroup()
	end
end

-- looted items
local PATTERN_LOOTS = LOOT_ITEM_SELF:gsub("%%s", "(.+)")
local PATTERN_LOOTM = LOOT_ITEM_SELF_MULTIPLE:gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)")
function addon:CHAT_MSG_LOOT(event,msg)
	if session.startTime then
		local itemLink, quantity = strmatch(msg, PATTERN_LOOTM)
		if not itemLink then
			quantity = 1
			itemLink = strmatch(msg, PATTERN_LOOTS)
		end
		if itemLink then
			local price, rarity, itemName = GetItemPrice(itemLink)
			if price then
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

-- looted gold
do
	local pattern = GetLocale()=='ruRU' and '%d+ ' or '%d+' -- space added for russian language because there are a |4 prefix in copper/silver/gold russian text
	local digits = {}
	local func = function(n) digits[#digits+1]=tonumber(n) end
	function addon:CHAT_MSG_MONEY(event,msg)
		if session.startTime then
			wipe(digits)
			gsub(msg,pattern,func)
			local money = digits[#digits] + (digits[#digits-1] or 0)*100 + (digits[#digits-2] or 0)*10000
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

-- combat start
function addon:PLAYER_REGEN_DISABLED()
	combatActive = true
	combatPreKills = combatCurKills or combatPreKills
	combatCurKills = nil
end

-- combat end
function addon:PLAYER_REGEN_ENABLED()
	combatActive = nil
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
				if config.farmZones then
					if config.farmZones[zone] then
						if inInstance and (lastZoneKey or time()-(session.endTime or 0)<300) then -- continue session if logout was less than 5 minutes
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
		end
		config.reloadUI = not isLogout or nil
	end
end

-- If we kill a npc inside instance a ResetInstance() is executed on player logout, so we need this to track
-- and save this hidden reset, see addon:PLAYER_LOGOUT()
function addon:COMBAT_LOG_EVENT_UNFILTERED()
	local _, eventType,_,_,_,_,_,dstGUID,dstName,dstFlags = CombatLogGetCurrentEventInfo()
	if eventType == 'UNIT_DIED' and band(dstFlags,COMBATLOG_OBJECT_CONTROL_NPC)~=0 then
		if inInstance and not resets[curZoneName] then
			LockAddInstance(curZoneName) -- register used instance
			timer:Play()
		end
		if session.startTime then
			session.countMobs = session.countMobs + 1
			session.killedMobs[dstName] = (session.killedMobs[dstName] or 0) + 1
			combatCurKills = (combatCurKills or 0) + 1
		end
	end
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
	addon:SetMovable(true)
	addon:RegisterForDrag("LeftButton")
	addon:SetScript("OnDragStart", addon.StartMoving)
	addon:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		self:SetUserPlaced(false)
		SavePosition()
		RestorePosition()
	end )
	-- background texture
	texture = addon:CreateTexture()
	texture:SetAllPoints()
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
	local root = KiwiFarmDB
	if not root then root = {}; KiwiFarmDB = root; end
	config = root[serverKey]
	if not config then config = {}; root[serverKey] = config; end
	addon.config = config
	InitDB(config, DEFAULT, false, true)
	InitDB(config.session, DEFDATA)
	InitDB(config.total, DEFDATA)
	UpdateDB(config)
	session  = config.session
	notify   = config.notify
	disabled = config.disabled
	collect  = config.collect
	resets   = config.resets  or config.resetData[charKey].resets
	resetsd  = config.resetsd or config.resetData[charKey].resetsd
	-- remove old data from database
	local key = date("%Y/%m/%d", time()-86400*7)
	for k,v in next, config.daily do
		if k<key then config.daily[k] = nil; end
	end
	-- minimap icon
	LibStub("LibDBIcon-1.0"):Register(addonName, LibStub("LibDataBroker-1.1"):NewDataObject(addonName, {
		type  = "launcher",
		label = GetAddOnInfo( addonName, "Title"),
		icon  = "Interface\\AddOns\\KiwiFarm\\KiwiFarm",
		OnClick = function(self, button)
			if button == 'RightButton' then
				addon:ShowMenu()
			else
				addon:SetShown( not addon:IsShown() )
				config.visible = addon:IsShown()
			end
		end,
		OnTooltipShow = function(tooltip)
			tooltip:AddDoubleLine("KiwiFarm", GetAddOnMetadata(addonName, "Version") )
			tooltip:AddLine(L["|cFFff4040Left Click|r toggle window visibility\n|cFFff4040Right Click|r open config menu"], 0.2, 1, 0.2)
		end,
	}) , config.minimapIcon)
	-- events
	addon:SetScript('OnEvent', function(self,event,...) self[event](self,event,...) end)
	addon:RegisterEvent('COMBAT_LOG_EVENT_UNFILTERED')
	addon:RegisterEvent("ZONE_CHANGED_NEW_AREA")
	addon:RegisterEvent("PLAYER_ENTERING_WORLD")
	addon:RegisterEvent("CHAT_MSG_SYSTEM")
	addon:RegisterEvent("PLAYER_LOGOUT")
	-- frame position
	RestorePosition()
	-- frame size & appearance
	LayoutFrame()
	-- session
	if session.startTime then
		SessionStart(true)
	end
	-- mainframe initial visibility
	addon:SetShown( config.visible and (not config.farmZones or config.reloadUI) )
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
		addon:SetShown( not addon:IsShown() )
	elseif arg1 == 'start'  then
		SessionStart()
	elseif arg1 == 'stop' then
		SessionStop()
	elseif arg1 == 'finish' then
		SessionFinish()
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
		print("  /kfarm toggle   -- show/hide main window")
		print("  /kfarm start    -- session start")
		print("  /kfarm stop     -- session stop")
		print("  /kfarm finish   -- session finish")
 		print("  /kfarm config   -- display config menu")
		print("  /kfarm minimap  -- toggle minimap icon visibility")
	end
end

-- ============================================================================
-- config popup menu
-- ============================================================================

do
	-- popup menu main frame
	local menuFrame = CreateFrame("Frame", "KiwiFarmPopupMenu", UIParent, "UIDropDownMenuTemplate")

	-- generic & enhanced popup menu management code, reusable for other menus
	local showMenu, refreshMenu, getMenuLevel, getMenuValue
	do
		-- menu initialization: special management of enhanced menuList tables, using fields not supported by the base UIDropDownMenu code.
		local function initialize( frame, level, menuList )
			if level then
				frame.menuValues[level] = UIDROPDOWNMENU_MENU_VALUE
				local init = menuList.init
				if init then -- custom initialization function for the menuList
					init(menuList, level, frame)
				end
				for index=1,#menuList do
					local item = menuList[index]
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
				fsort = fsort or 'text'
				fdisp = fdisp or fsort
				table.sort(menu, function(a,b) return a[fsort]<b[fsort] end )
				local items, first, last
				if count>28 then
					for i=1,count do
						if not items or #items>=28 then
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

	local function InitPriceSources(menu)
		for i=#menu,1,-1 do
			if (menu[i].arg1 =='Atr' and not Atr_GetAuctionPrice) or (menu[i].arg1 =='TSM' and not TSMAPI) then
				tremove(menu,i)
			end
		end
		menu.init = nil -- means do not call the function anymore
	end
	local function SetBackground()
		texture:SetColorTexture( unpack(config.backColor or COLOR_TRANSPARENT) )
	end
	local function SetWidth(info)
		config.frameWidth = info.value~=0 and math.max( (config.frameWidth or addon:GetWidth()) + info.value, 50) or nil
		LayoutFrame()
	end
	local function SetFontSize(info)
		config.fontSize = info.value~=0 and math.max( (config.fontSize or 14) + info.value, 5) or 14
		LayoutFrame()
	end
	local function AnchorChecked(info)
		return info.value == config.framePos.anchor
	end
	local function SetAnchor(info)
		config.framePos.anchor = info.value
		SavePosition()
		RestorePosition()
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
		return (session.startTime and L['Session Pause']) or (session.duration and L['Session Continue']) or L['Session Start']
	end
	local function setSession()
		if session.startTime then
			SessionStop()
		else
			SessionStart()
		end
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
		if CLASSIC and #resetsd>0 then
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
			{ text = L['Vendor Price'],              value = 'vendor',                     isNotRadio = true, keepShownOnClick = 1, checked = checked, func = set },
			{ text = L['Auctionator: Market Value'], value = 'Atr:DBMarket', arg1 = 'Atr', isNotRadio = true, keepShownOnClick = 1, checked = checked, func = set },
			{ text = L['Auctionator: Disenchant'],   value = 'Atr:Destroy' , arg1 = 'Atr', isNotRadio = true, keepShownOnClick = 1, checked = checked, func = set },
			{ text = L['TSM: Market Value'],         value = 'DBMarket',     arg1 = 'TSM', isNotRadio = true, keepShownOnClick = 1, checked = checked, func = set },
			{ text = L['TSM: Min Buyout'],           value = 'DBMinBuyout',  arg1 = 'TSM', isNotRadio = true, keepShownOnClick = 1, checked = checked, func = set },
			{ text = L['TSM: Disenchant'],           value = 'Destroy',      arg1 = 'TSM', isNotRadio = true, keepShownOnClick = 1, checked = checked, func = set },
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
			{ text = getText,	  				     value = 'user',         			   isNotRadio = true, keepShownOnClick = 1, checked = checked, func = set },
			{ text = L['Vendor Price'],              value = 'vendor',                     isNotRadio = true, keepShownOnClick = 1, checked = checked, func = set },
			{ text = L['Auctionator: Market Value'], value = 'Atr:DBMarket', arg1 = 'Atr', isNotRadio = true, keepShownOnClick = 1, checked = checked, func = set },
			{ text = L['Auctionator: Disenchant'],   value = 'Atr:Destroy' , arg1 = 'Atr', isNotRadio = true, keepShownOnClick = 1, checked = checked, func = set },
			{ text = L['TSM: Market Value'],        value = 'DBMarket',     arg1 = 'TSM', isNotRadio = true, keepShownOnClick = 1, checked = checked, func = set },
			{ text = L['TSM: Min Buyout'],          value = 'DBMinBuyout',  arg1 = 'TSM', isNotRadio = true, keepShownOnClick = 1, checked = checked, func = set },
			{ text = L['TSM: Disenchant'],          value = 'Destroy',      arg1 = 'TSM', isNotRadio = true, keepShownOnClick = 1, checked = checked, func = set },
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
		local function initText(info, level)
			local groupKey = info.value
			if type(groupKey) ~= 'number' then -- special cases ('price' and 'money' groups notifications require a minimum price/gold amount)
				local price = notify[groupKey] and notify[groupKey][info.arg1]
				return price and format("%s (+%s)", info.arg2, FmtMoneyShort(price)) or format(L["%s (click to set price)"], info.arg2)
			end
			return info.arg2
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
			{ text = initText, useParentValue = true, arg1 = 'combat', arg2 = L['CombatText: Scroll'],     isNotRadio = true, keepShownOnClick = 1, checked = checked, func = setNotify },
			{ text = initText, useParentValue = true, arg1 = 'crit',   arg2 = L['CombatText: Crit'],       isNotRadio = true, keepShownOnClick = 1, checked = checked, func = setNotify },
			{ text = initText, useParentValue = true, arg1 = 'msbt',   arg2 = L['MSBT: Notification'], 	isNotRadio = true, keepShownOnClick = 1, checked = checked, func = setNotify },
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

	-- submenu: stats
	local menuStats = {
		{ notCheckable = true },
		{ notCheckable = true },
		{ notCheckable = true },
		{ notCheckable = true },
		{ notCheckable = true },
		{ text = L['Looted Items'], notCheckable = true, hasArrow = true, menuList = menuGoldQuality },
		{ text = L['Killed Mobs'],  notCheckable = true, hasArrow = true, menuList = menuKilledMobs  },
		{ text = L['Maintenance'],  notCheckable = true, hasArrow = true, menuList = menuStatsMisc   },
		init = function(menu,level)
			local curTime = time()
			local field = getMenuValue(level)
			stats = config[field] or field
			local money = stats.moneyCash+stats.moneyItems
			local duration = curTime - (stats.startTime or curTime) + (stats.duration or 0)
			local mhour = duration>0 and floor(money*3600/duration) or 0
			local ftime = (stats.duration or 0) + curTime - (stats.startTime or curTime)
			menu[1].text = format(L["Farm Time: %s"], FmtDuration(ftime))
			menu[2].text = format(L["Gold cash: %s"], FmtMoney(stats.moneyCash))
			menu[3].text = format(L["Gold items: %s"], FmtMoney(stats.moneyItems))
			menu[4].text = format(L["Gold/hour: %s"], FmtMoney(mhour))
			menu[5].text = format(L["Gold total: %s"], FmtMoney(money))
			menu[6].text = format(L["Items looted (%d)"], stats.countItems)
			menu[7].text = format(L["Mobs killed (%d)"], stats.countMobs)
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
				local money = data and data.moneyCash+data.moneyItems or 0
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
		{ text = getSessionText,       notCheckable = true, func = setSession },
		{ text = L['Session Finish'],     notCheckable = true, disabled = function() return not (session.startTime or session.duration) end, func = SessionFinish },
		{ text = L['Reset Instances'],    notCheckable = true, func = ResetInstances },
		{ text = L['Statistics'],         notCheckable = true, isTitle = true },
		{ text = L['Session'],            notCheckable = true, hasArrow = true, value = 'session', menuList = menuStats },
		{ text = L['Daily'],              notCheckable = true, hasArrow = true, menuList = menuDaily },
		{ text = L['Zones'],              notCheckable = true, hasArrow = true, menuList = menuZone },
		{ text = L['Totals'],             notCheckable = true, hasArrow = true, value = 'total',   menuList = menuStats },
		{ text = L['Resets'],             notCheckable = true, hasArrow = true, menuList = menuResets },
		{ text = L['Settings'],           notCheckable = true, isTitle = true },
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
		{ text = L['Miscellaneous'], notCheckable= true, hasArrow = true, menuList = {
			{ text = L['Display Info'], notCheckable= true, hasArrow = true, menuList = {
				{ text = L['Lock&Resets'],      value = 'reset',   isNotRadio = true, keepShownOnClick = 1, checked = DisplayChecked, func = SetDisplay },
				{ text = L['Mobs&Items Count'], value = 'count',   isNotRadio = true, keepShownOnClick = 1, checked = DisplayChecked, func = SetDisplay },
				{ text = L['Gold by Quality'],  value = 'quality', isNotRadio = true, keepShownOnClick = 1, checked = DisplayChecked, func = SetDisplay },
			} },
			{ text = L['Money Format'], notCheckable = true, hasArrow = true, menuList = {
				{ text = '999|cffffd70ag|r 99|cffc7c7cfs|r 99|cffeda55fc|r', value = '', 							    checked = MoneyFmtChecked, func = SetMoneyFmt },
				{ text = '999|cffffd70ag|r 99|cffc7c7cfs|r', 				 value = '%d|cffffd70ag|r %d|cffc7c7cfs|r', checked = MoneyFmtChecked, func = SetMoneyFmt },
				{ text = '999|cffffd70ag|r', 								 value = '%d|cffffd70ag|r', 				checked = MoneyFmtChecked, func = SetMoneyFmt },
			} },
			{ text = L['Data Collection'], notCheckable= true, hasArrow = true, menuList = menuCollect },
			{ text = L['Farming Zones'],   notCheckable= true, hasArrow = true, menuList = menuZones },
			{ text = L['Reset Notification'],   notCheckable= true, hasArrow = true, menuList = menuResetNotify },
		} },
		{ text = L['Appearance'], notCheckable= true, hasArrow = true, menuList = {
			{ text = L['Frame Anchor'], notCheckable= true, hasArrow = true, menuList = {
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
			{ text = L['Frame Width'], notCheckable= true, hasArrow = true, menuList = {
				{ text = L['Increase(+)'],   value =  1,  notCheckable= true, keepShownOnClick=1, func = SetWidth },
				{ text = L['Decrease(-)'],   value = -1,  notCheckable= true, keepShownOnClick=1, func = SetWidth },
				{ text = L['Default'],       value =  0,  notCheckable= true, keepShownOnClick=1, func = SetWidth },
			} },
			{ text = L['Text Font'], notCheckable= true, hasArrow = true, menuList = menuFonts },
			{ text = L['Text Size'], notCheckable= true, hasArrow = true, menuList = {
				{ text = L['Increase(+)'],  value =  1,  notCheckable= true, keepShownOnClick=1, func = SetFontSize },
				{ text = L['Decrease(-)'],  value = -1,  notCheckable= true, keepShownOnClick=1, func = SetFontSize },
				{ text = L['Default (14)'], value =  0,  notCheckable= true, keepShownOnClick=1, func = SetFontSize },
			} },
			{ text =L['Background color '], notCheckable = true, hasColorSwatch = true, hasOpacity = true,
				get = function() return unpack(config.backColor) end,
				set = function(info, ...) config.backColor = {...}; SetBackground(); end,
			},
			{ text = L['Hide Window'], notCheckable = true, func = function() addon:Hide() end },
		} },
	}

	function addon:ShowMenu()
		showMenu(menuMain, menuFrame, "cursor", 0 , 0)
	end
end
