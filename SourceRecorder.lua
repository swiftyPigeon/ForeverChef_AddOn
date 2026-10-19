local ADDON_NAME, FC = ...

-- Records where Cooking recipe scrolls are actually found in game, filling the
-- gaps the researched list (CookingSources.lua) cannot:
--   merchant windows -> Vendor (the vendor's own faction, price or currency cost)
--   loot windows     -> Drop / Container (anyone can loot, so Neutral)
--   quest rewards    -> Quest (the quest giver's faction)
-- Saved account-wide, shown ahead of researched sources, and included in /fchef export.
--   db.observed[recipeID]["<type>:<who id>"] = { type, faction, who, npcID, quest, zone, map, x, y, cost, seen, last }
local Geo = FC.Geo

local nameByGUID = {}   -- recently targeted/moused-over units, to name loot sources
local namesCached = 0
local MAX_CACHED_NAMES = 300
local merchantPending

local function isSecret(value)
    return issecretvalue and issecretvalue(value)
end

local function itemIDFromLink(link)
    if not link or isSecret(link) then return nil end
    return tonumber(tostring(link):match("item:(%d+)"))
end

-- "Creature-0-1-2-3-<npcID>-<spawn>" -> npcID; also returns the GUID's kind.
local function parseGUID(guid)
    if not guid or isSecret(guid) then return nil end
    local kind, _, _, _, _, id = strsplit("-", guid)
    return tonumber(id), kind
end

-- Unit factions are "Alliance"/"Horde"; anything else (goblins, caravans) is Neutral.
local function unitFaction(unit)
    local faction = UnitFactionGroup and UnitFactionGroup(unit)
    if isSecret(faction) then return "" end
    if faction == "Alliance" or faction == "Horde" then return faction end
    return "Neutral"
end

local function money(copper)
    copper = tonumber(copper) or 0
    if copper <= 0 then return "" end
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local parts = {}
    if g > 0 then table.insert(parts, g .. "g") end
    if s > 0 then table.insert(parts, s .. "s") end
    if c > 0 then table.insert(parts, c .. "c") end
    return table.concat(parts, " ")
end

-- Where the player stands, as zone name plus coordinates (0-100) on the zone's
-- map (not a building or cave sub-map), so waypoints can be placed from it.
local function here()
    local zone = (GetZoneText and GetZoneText()) or ""
    local sub = (GetSubZoneText and GetSubZoneText()) or ""
    if sub ~= "" and sub ~= zone then zone = sub .. ", " .. zone end
    local best = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local mapID = best and (Geo.ZoneMapID(best) or best)
    local pos = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
    local x, y
    if pos then
        x, y = pos:GetXY()
        x, y = FC.Round(x * 100, 1), FC.Round(y * 100, 1)
    end
    return zone, mapID, x, y
end

local function record(itemID, source)
    local recipeIDs = FC:RecipesForScroll(itemID)
    if not recipeIDs then return end
    local zone, mapID, x, y = here()
    for _, recipeID in ipairs(recipeIDs) do
        FC.db.observed[recipeID] = FC.db.observed[recipeID] or {}
        local key = source.type .. ":" .. tostring(source.npcID or source.quest or source.who)
        local entry = FC.db.observed[recipeID][key]
        if not entry then
            entry = { seen = 0 }
            FC.db.observed[recipeID][key] = entry
            FC:Notify(string.format("Found where to learn %s: %s %s (%s).",
                FC.CookingData[recipeID] and FC.CookingData[recipeID].name or ("recipe " .. recipeID),
                source.type:lower(), source.who, zone))
            FC.listsDirty = true
        end
        for k, v in pairs(source) do entry[k] = v end
        entry.zone, entry.map, entry.x, entry.y = zone, mapID, x, y
        entry.seen, entry.last = entry.seen + 1, time()
    end
end

-- NPC positions -------------------------------------------------------------------
-- While a merchant or trainer window is open the player stands next to the NPC,
-- so their position is the NPC's. Recorded positions count as verified.
--   db.npcLocations[name] = { npcID, faction, zone, map, x, y, last }
local function recordNPCLocation()
    local npcID = parseGUID(UnitGUID and UnitGUID("npc"))
    local who = UnitName and UnitName("npc")
    if not npcID or not who or isSecret(who) then return end
    local _, mapID, x, y = here()
    if not mapID or not x then return end
    local info = C_Map.GetMapInfo(mapID)
    FC.db.npcLocations[who] = { npcID = npcID, faction = unitFaction("npc"), zone = info and info.name or "",
        map = mapID, x = x, y = y, last = time() }
end

function FC:NPCLocation(name)
    return self.db.npcLocations and self.db.npcLocations[name]
end

-- Merchants ---------------------------------------------------------------------

local function merchantCost(index, price)
    local parts = {}
    if GetMerchantItemCostInfo and GetMerchantItemCostItem then
        for i = 1, (GetMerchantItemCostInfo(index) or 0) do
            local _, value, link, currencyName = GetMerchantItemCostItem(index, i)
            local name = currencyName or (link and link:match("%[(.-)%]"))
            if value and name then table.insert(parts, value .. " " .. name) end
        end
    end
    if money(price) ~= "" then table.insert(parts, 1, money(price)) end
    return table.concat(parts, " + ")
end

local function merchantItem(index)
    local link = (C_MerchantFrame and C_MerchantFrame.GetItemLink and C_MerchantFrame.GetItemLink(index))
        or (GetMerchantItemLink and GetMerchantItemLink(index))
    local price
    if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
        local info = C_MerchantFrame.GetItemInfo(index)
        price = info and info.price
    elseif GetMerchantItemInfo then
        price = select(3, GetMerchantItemInfo(index))
    end
    return itemIDFromLink(link), price
end

local function scanMerchant()
    local count = (C_MerchantFrame and C_MerchantFrame.GetNumItems and C_MerchantFrame.GetNumItems())
        or (GetMerchantNumItems and GetMerchantNumItems()) or 0
    local guid = UnitGUID and UnitGUID("npc")
    local npcID = parseGUID(guid)
    local who = UnitName and UnitName("npc")
    if not npcID or not who or isSecret(who) then return end
    recordNPCLocation()
    local faction = unitFaction("npc")
    for index = 1, count do
        local itemID, price = merchantItem(index)
        if itemID and FC:RecipesForScroll(itemID) then
            record(itemID, { type = "Vendor", faction = faction, who = who, npcID = npcID, cost = merchantCost(index, price) })
        end
    end
end

-- Merchant items can arrive over several updates; scan once things settle.
local function queueMerchantScan()
    if merchantPending then return end
    merchantPending = true
    C_Timer.After(0.5, function()
        merchantPending = nil
        local ok, err = pcall(scanMerchant)
        if not ok then FC:Debug("Merchant scan: " .. tostring(err)) end
    end)
end

-- Loot --------------------------------------------------------------------------

local function rememberUnit(unit)
    local guid = UnitGUID and UnitGUID(unit)
    local name = UnitName and UnitName(unit)
    if not guid or not name or isSecret(guid) or isSecret(name) or nameByGUID[guid] then return end
    if namesCached >= MAX_CACHED_NAMES then
        wipe(nameByGUID)
        namesCached = 0
    end
    nameByGUID[guid] = name
    namesCached = namesCached + 1
end

local function scanLoot()
    if not (GetNumLootItems and GetLootSlotLink and GetLootSourceInfo) then return end
    for slot = 1, GetNumLootItems() do
        local itemID = itemIDFromLink(GetLootSlotLink(slot))
        if itemID and FC:RecipesForScroll(itemID) then
            local guid = GetLootSourceInfo(slot)
            local id, kind = parseGUID(guid)
            local source = { type = "Drop", faction = "Neutral", npcID = id }
            if kind == "Creature" or kind == "Vehicle" then
                source.who = nameByGUID[guid] or ("NPC #" .. tostring(id))
            elseif kind == "GameObject" then
                source.type, source.who = "Container", "Object #" .. tostring(id)
            else
                source.type, source.who, source.npcID = "Container", "An item (lockbox, clam, ...)", nil
            end
            record(itemID, source)
        end
    end
end

-- Quests ------------------------------------------------------------------------

local function scanQuestRewards()
    if not GetQuestItemLink then return end
    local title = GetTitleText and GetTitleText()
    local giver = UnitName and UnitName("npc")
    if not title or isSecret(title) then return end
    for _, kind in ipairs({ "reward", "choice" }) do
        local count = (kind == "reward" and GetNumQuestRewards and GetNumQuestRewards())
            or (kind == "choice" and GetNumQuestChoices and GetNumQuestChoices()) or 0
        for i = 1, count do
            local itemID = itemIDFromLink(GetQuestItemLink(kind, i))
            if itemID and FC:RecipesForScroll(itemID) then
                local who = title
                if giver and not isSecret(giver) then who = title .. " (from " .. giver .. ")" end
                record(itemID, { type = "Quest", faction = unitFaction("npc"), who = who, quest = title })
            end
        end
    end
end

-- Read side ---------------------------------------------------------------------

-- Recorded sources in the same shape as CookingSources.lua entries, newest first.
function FC:ObservedSources(recipeID)
    local list = {}
    for _, entry in pairs(self.db and self.db.observed and self.db.observed[recipeID] or {}) do
        local zone = entry.zone or ""
        if entry.x then zone = string.format("%s (%.1f, %.1f)", zone, entry.x, entry.y) end
        table.insert(list, { type = entry.type, faction = entry.faction or "", who = entry.who or "?", zone = zone,
            cost = entry.cost, seenInGame = true, last = entry.last or 0,
            place = entry.zone, map = entry.map, x = entry.x, y = entry.y })
    end
    table.sort(list, function(a, b) return a.last > b.last end)
    return list
end

function FC:NPCLocationCount()
    local n = 0
    for _ in pairs(self.db.npcLocations or {}) do n = n + 1 end
    return n
end

function FC:ObservedCount()
    local n = 0
    for _, sources in pairs(self.db.observed or {}) do
        for _ in pairs(sources) do n = n + 1 end
    end
    return n
end

FC:OnInit(function()
    FC.db.observed = FC.db.observed or {}
    FC.db.npcLocations = FC.db.npcLocations or {}
end)

local function safely(fn)
    return function()
        local ok, err = pcall(fn)
        if not ok then FC:Debug("Source recorder: " .. tostring(err)) end
    end
end

FC:On("MERCHANT_SHOW", queueMerchantScan)
FC:On("MERCHANT_UPDATE", queueMerchantScan)
FC:On("LOOT_OPENED", safely(scanLoot))
FC:On("TRAINER_SHOW", safely(recordNPCLocation))
-- Quest dialogs: the player stands at the quest giver (objects and items have no NPC ID and are skipped).
for _, event in ipairs({ "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE", "QUEST_GREETING" }) do
    FC:On(event, safely(recordNPCLocation))
end
FC:On("QUEST_DETAIL", safely(scanQuestRewards))
FC:On("QUEST_COMPLETE", safely(scanQuestRewards))
FC:On("PLAYER_TARGET_CHANGED", function() rememberUnit("target") end)
FC:On("UPDATE_MOUSEOVER_UNIT", function() rememberUnit("mouseover") end)
