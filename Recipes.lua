local ADDON_NAME, FC = ...

-- Cooking recipes on ingredient tooltips: green = this character knows the
-- recipe, red = not yet. Every recipe comes from the built-in list
-- (CookingData.lua), so tooltips work before the Cooking window is opened and
-- on characters without Cooking. Opening the Cooking window adds anything the
-- list is missing (hotfixed recipes) and the trainer/vendor text for unlearned
-- recipes.
--   db.recipes[recipeID]    = { name, reagents = { [itemID] = count }, source }  -- from the Cooking window
--   char.knownRecipes[id]   = true                                               -- seen learned in the Cooking window
local COOKING_SKILL_LINE = 185
local COOKING_SPELL = 2550
local MAX_TOOLTIP_RECIPES = 14
local KNOWN_COLOR = { 0.25, 0.82, 0.36 }
local UNKNOWN_COLOR = { 0.93, 0.27, 0.24 }
local HEADER_ICON = "|TInterface\\Icons\\INV_Misc_Food_15:14:14:0:0|t "

local recipes = {}     -- recipeID -> { name, reagents = { [itemID] = count }, items, auto, source }
local byReagent = {}   -- itemID -> { recipeID, ... }
local byScroll = {}    -- recipe scroll itemID -> { recipeID, ... }
-- Forever keeps some Classic recipes next to a reworked copy with the same name
-- (Basic Campfire). They are one recipe to the player: copies[id] lists every ID
-- sharing its name, and primary[id] is the one the window shows.
local copies, primary = {}, {}
local scanPending

local function isSecret(value)
    return issecretvalue and issecretvalue(value)
end

local function spellName(spellID, fallback)
    local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)
    if not name and GetSpellInfo then name = GetSpellInfo(spellID) end
    return name or fallback
end

-- Built-in list first, then anything learned from the Cooking window on top.
local function rebuildIndex()
    wipe(recipes)
    wipe(byReagent)
    wipe(byScroll)
    for recipeID, data in pairs(FC.CookingData or {}) do
        local reagents = {}
        for i = 1, #data.reagents - 1, 2 do reagents[data.reagents[i]] = data.reagents[i + 1] end
        recipes[recipeID] = { name = data.name, reagents = reagents, items = data.items, auto = data.auto,
            creates = data.creates, effect = data.effect }
    end
    for recipeID, scanned in pairs(FC.db.recipes) do
        local recipe = recipes[recipeID] or { name = scanned.name, reagents = {} }
        if next(scanned.reagents or {}) then recipe.reagents = scanned.reagents end
        recipe.source = scanned.source
        recipes[recipeID] = recipe
    end
    wipe(copies)
    wipe(primary)
    local byName = {}
    for recipeID, recipe in pairs(recipes) do
        byName[recipe.name] = byName[recipe.name] or {}
        table.insert(byName[recipe.name], recipeID)
    end
    -- Show the copy with researched sources, else the one with game data
    -- (automatic, creates an item), else the newest ID.
    local function rank(id)
        local recipe = recipes[id]
        return (FC.CookingSources and FC.CookingSources[id] and 4 or 0) + ((recipe.auto or recipe.creates) and 2 or 0)
    end
    for _, ids in pairs(byName) do
        table.sort(ids, function(a, b)
            if rank(a) ~= rank(b) then return rank(a) > rank(b) end
            return a > b
        end)
        for _, id in ipairs(ids) do copies[id], primary[id] = ids, ids[1] end
    end
    for recipeID, recipe in pairs(recipes) do
        for itemID in pairs(recipe.reagents) do
            byReagent[itemID] = byReagent[itemID] or {}
            table.insert(byReagent[itemID], recipeID)
        end
        for _, scrollID in ipairs(recipe.items or {}) do
            byScroll[scrollID] = byScroll[scrollID] or {}
            table.insert(byScroll[scrollID], recipeID)
        end
    end
end
FC.RebuildRecipeIndex = rebuildIndex

-- Cooking recipes with this name (the game's localized name or the built-in
-- English one), e.g. to match a trainer's list. nil if none.
function FC:RecipesNamed(name)
    local found
    for recipeID, recipe in pairs(recipes) do
        if spellName(recipeID, recipe.name) == name or recipe.name == name then
            found = found or {}
            table.insert(found, recipeID)
        end
    end
    return found
end

-- Cooking recipes taught by a recipe scroll item, or nil if it is not one.
function FC:RecipesForScroll(itemID)
    return byScroll[itemID]
end

local function knowsSpell(recipeID)
    if FC.char.knownRecipes[recipeID] then return true end
    if IsPlayerSpell then
        local ok, known = pcall(IsPlayerSpell, recipeID)
        if ok and known and not isSecret(known) then return true end
    end
    return false
end

-- Known when this character knows the recipe or a same-name copy of it.
function FC:IsRecipeKnown(recipeID)
    for _, id in ipairs(copies[recipeID] or { recipeID }) do
        if knowsSpell(id) then return true end
    end
    return false
end

-- Cooking window scanning -----------------------------------------------------

local function itemIDFromReagent(reagent)
    local id = reagent.itemID or (reagent.item and reagent.item.itemID)
    if not id and reagent.itemLink then id = tostring(reagent.itemLink):match("item:(%d+)") end
    return tonumber(id)
end

local function readReagents(recipeID)
    if not C_TradeSkillUI.GetRecipeSchematic then return nil end
    local ok, schematic = pcall(C_TradeSkillUI.GetRecipeSchematic, recipeID, false)
    if not ok or type(schematic) ~= "table" or type(schematic.reagentSlotSchematics) ~= "table" then return nil end
    local reagents = {}
    for _, slot in ipairs(schematic.reagentSlotSchematics) do
        for _, reagent in ipairs(slot.reagents or {}) do
            local itemID = itemIDFromReagent(reagent)
            if itemID then reagents[itemID] = tonumber(slot.quantityRequired) or 1 end
        end
    end
    return reagents
end

local function cookingWindowOpen()
    if C_TradeSkillUI.GetBaseProfessionInfo then
        local ok, info = pcall(C_TradeSkillUI.GetBaseProfessionInfo)
        if ok and type(info) == "table" then
            local id = tonumber(info.professionID or info.skillLineID or info.parentProfessionID)
            if id then return id == COOKING_SKILL_LINE end
            local name = info.professionName or info.name
            if name then return name == spellName(COOKING_SPELL, "Cooking") end
        end
    end
    return GetTradeSkillLine and GetTradeSkillLine() == spellName(COOKING_SPELL, "Cooking")
end

-- Another player's linked Cooking, a guild list, or an NPC crafter would
-- otherwise mark recipes as known that this character does not have.
local function viewingOwnProfession()
    for _, name in ipairs({ "IsTradeSkillLinked", "IsTradeSkillGuild", "IsNPCCrafting" }) do
        local fn = C_TradeSkillUI[name]
        if fn then
            local ok, result = pcall(fn)
            if ok and result then return false end
        end
    end
    return true
end

function FC:ScanCooking()
    if not (C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs and C_TradeSkillUI.GetRecipeInfo) then return end
    if not cookingWindowOpen() or not viewingOwnProfession() then return end
    local ok, recipeIDs = pcall(C_TradeSkillUI.GetAllRecipeIDs)
    if not ok or type(recipeIDs) ~= "table" or #recipeIDs == 0 then return end

    local known, learned = self.char.knownRecipes, 0
    for _, recipeID in ipairs(recipeIDs) do
        local good, info = pcall(C_TradeSkillUI.GetRecipeInfo, recipeID)
        if good and type(info) == "table" and info.name then
            local isLearned = info.learned == true or info.isLearned == true
            local scanned = self.db.recipes[recipeID] or {}
            scanned.name = info.name
            scanned.reagents = readReagents(recipeID) or scanned.reagents or {}
            if not isLearned and C_TradeSkillUI.GetRecipeSourceText then
                local sourceOK, source = pcall(C_TradeSkillUI.GetRecipeSourceText, recipeID)
                if sourceOK and type(source) == "string" and source ~= "" then scanned.source = source end
            end
            self.db.recipes[recipeID] = scanned
            known[recipeID] = isLearned or nil
            if isLearned then learned = learned + 1 end
        end
    end
    rebuildIndex()
    self.listsDirty = true
    self:ClearWaypointIfLearned()
    if self.char.cookingKnownCount ~= learned then
        self.char.cookingKnownCount = learned
        self:Notify(string.format("You know %d Cooking recipes.", learned))
    end
end

-- TRADE_SKILL_LIST_UPDATE can fire many times while the window fills in.
local function queueScan()
    if scanPending then return end
    scanPending = true
    C_Timer.After(0.5, function()
        scanPending = nil
        local ok, err = pcall(FC.ScanCooking, FC)
        if not ok then FC:Debug("Cooking scan: " .. tostring(err)) end
    end)
end

-- Where to learn (CookingSources.lua) -------------------------------------------

-- Sources with these factions can be used by anyone; "" means the guide did not say.
local OPEN_TO_ALL = { Neutral = true, Both = true, [""] = true }

-- Sources this character's faction can use: ones recorded in game first, then
-- the researched list, then (with neither) single-website suggestions. `other`
-- names the faction of a hidden source, so "Alliance only" can be shown when
-- nothing usable is left.
local function usableSources(recipeID)
    local all = {}
    for _, source in ipairs(FC:ObservedSources(recipeID)) do table.insert(all, source) end
    for _, source in ipairs(FC.CookingSources and FC.CookingSources[recipeID] or {}) do table.insert(all, source) end
    if #all == 0 then
        for _, source in ipairs(FC.SuggestedSources and FC.SuggestedSources[recipeID] or {}) do table.insert(all, source) end
    end
    if #all == 0 then return nil end
    local faction = UnitFactionGroup and UnitFactionGroup("player")
    local usable, other = {}, nil
    for _, source in ipairs(all) do
        if OPEN_TO_ALL[source.faction] or source.faction == faction then
            table.insert(usable, source)
        else
            other = source.faction
        end
    end
    return usable, other
end

local function sourceLabel(source)
    if source.faction == "Alliance" or source.faction == "Horde" or source.faction == "Neutral" then
        return source.type .. " (" .. source.faction .. ")"
    end
    return source.type
end

-- "Tarren Mill, Hillsbrad Foothills" -> "Hillsbrad Foothills";
-- "Desolace (southern caravan stop, 40,79)" -> "Desolace".
local function zoneOf(place)
    local text = tostring(place or ""):gsub("%s*%b()", "")
    local zone = text:match("([^,]+)$") or ""
    return (zone:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- The zone where this character can learn the recipe: one zone name,
-- "Multiple Zones", or "" when no usable source has a zone.
function FC:RecipeZone(recipeID)
    local usable = usableSources(recipeID)
    if not usable then return "" end
    local faction = UnitFactionGroup and UnitFactionGroup("player")
    local zones, count = {}, 0
    local function add(place)
        local zone = zoneOf(place)
        if zone ~= "" and not zones[zone] then
            zones[zone] = true
            count = count + 1
        end
    end
    for _, source in ipairs(usable) do
        if source.type == "Trainer" and source.faction == "Both" then
            for _, trainer in ipairs(self.CookingTrainers or {}) do
                if trainer.faction == faction then add(trainer.zone) end
            end
        else
            for place in ((source.place or source.zone or "") .. ";"):gmatch("([^;]*);") do add(place) end
        end
    end
    if count == 0 then return "" end
    if count > 1 then return "Multiple Zones" end
    return next(zones)
end

-- Short form for tooltips, e.g. "Vendor (Horde)" or "Alliance only".
-- With `bare`, just the method ("Vendor", "Drop", "Quest", ... or "Unknown") for the
-- Recipes tab; the detail pop-up has the rest.
function FC:RecipeSourceShort(recipeID, bare)
    local usable, other = usableSources(recipeID)
    if usable and usable[1] then return bare and usable[1].type or sourceLabel(usable[1]) end
    if other then return other .. " only" end
    -- The game data marks it as learned together with Cooking.
    if recipes[recipeID] and recipes[recipeID].auto then return "Automatic" end
    -- Nothing confirmed or suggested.
    return "Unknown"
end

-- Tooltips ---------------------------------------------------------------------

local function addTooltipLines(tooltip, itemID)
    local list = itemID and byReagent[itemID]
    if not list then return false end

    -- Forever reworked some recipes under new IDs with the same name: show one line.
    local byName = {}
    for _, recipeID in ipairs(list) do
        local recipe = recipes[recipeID]
        local name = spellName(recipeID, recipe.name)
        local entry = byName[name]
        if not entry then
            entry = { name = name, known = false, count = recipe.reagents[itemID] or 1, recipeID = recipeID }
            byName[name] = entry
        elseif FC.CookingSources and FC.CookingSources[recipeID] then
            entry.recipeID = recipeID   -- prefer the copy that has researched sources
        end
        entry.known = entry.known or FC:IsRecipeKnown(recipeID)
    end
    local entries = {}
    for _, entry in pairs(byName) do table.insert(entries, entry) end
    table.sort(entries, function(a, b)
        if a.known ~= b.known then return a.known end
        return a.name < b.name
    end)

    tooltip:AddLine(" ")
    tooltip:AddLine(HEADER_ICON .. "Cooking recipes", unpack(FC.COLORS.accent))
    for i, entry in ipairs(entries) do
        if i > MAX_TOOLTIP_RECIPES then
            tooltip:AddLine(string.format("   ...and %d more (see /fchef)", #entries - MAX_TOOLTIP_RECIPES), 0.54, 0.60, 0.68)
            break
        end
        local color = entry.known and KNOWN_COLOR or UNKNOWN_COLOR
        local count = entry.count > 1 and string.format(" (x%d)", entry.count) or ""
        if entry.known then
            tooltip:AddLine("   " .. entry.name .. count, color[1], color[2], color[3])
        else
            tooltip:AddDoubleLine("   " .. entry.name .. count, FC:RecipeSourceShort(entry.recipeID),
                color[1], color[2], color[3], 0.54, 0.60, 0.68)
        end
    end
    return true
end

local function itemIDFromTooltip(tooltip, data)
    local id = data and data.id
    if isSecret(id) then return nil end
    if type(id) == "number" then return id end
    if tooltip.GetItem then
        local _, link = tooltip:GetItem()
        if link and not isSecret(link) then return tonumber(link:match("item:(%d+)")) end
    end
end

local function onItemTooltip(tooltip, data)
    if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
    local ok, added = pcall(addTooltipLines, tooltip, itemIDFromTooltip(tooltip, data))
    if not ok then FC:Debug("Tooltip: " .. tostring(added)) end
    if ok and added then tooltip:Show() end
end

-- Recipes tab ------------------------------------------------------------------

-- Item names arrive from the server the first time they are asked for; until
-- then this returns nil and asks for them (GET_ITEM_INFO_RECEIVED follows).
-- Clients differ in which lookup they offer, so try each.
function FC:ItemName(itemID)
    local name
    if C_Item and C_Item.GetItemNameByID then name = C_Item.GetItemNameByID(itemID) end
    if not name and C_Item and C_Item.GetItemInfo then name = C_Item.GetItemInfo(itemID) end
    if not name and GetItemInfo then name = GetItemInfo(itemID) end
    if not name then
        if C_Item and C_Item.RequestLoadItemDataByID then
            C_Item.RequestLoadItemDataByID(itemID)
        elseif GetItemInfo then
            GetItemInfo(itemID)
        end
    end
    return name
end

local function itemName(itemID)
    return FC:ItemName(itemID)
end

-- Detail pop-up ----------------------------------------------------------------

-- What eating the food does: the game's own "Use:" text for the item the recipe
-- creates when the client has it, otherwise the text built in from the game data.
function FC:FoodEffect(recipeID)
    local recipe = recipes[recipeID]
    if not recipe or not recipe.creates then return nil end
    local spellID
    if C_Item and C_Item.GetItemSpell then
        spellID = select(2, C_Item.GetItemSpell(recipe.creates))
    elseif GetItemSpell then
        spellID = select(2, GetItemSpell(recipe.creates))
    end
    local live
    if spellID then
        if C_Spell and C_Spell.GetSpellDescription then
            live = C_Spell.GetSpellDescription(spellID)
        elseif GetSpellDescription then
            live = GetSpellDescription(spellID)
        end
    end
    if live and not isSecret(live) and live ~= "" then return live end
    return recipe.effect
end

-- Buff filters for the recipe window, in menu order: { key, label, patterns }.
-- Matched against the built-in English effect text (the game's own text can be
-- in another language). "health" (food with no buff) and "other" are decided
-- in RecipeBuffs.
FC.BUFF_FILTERS = {
    { "strength", "Strength", { "%d+ strength" } },
    { "agility", "Agility", { "%d+ agility" } },
    { "stamina", "Stamina", { "%d+ stamina", "stamina%-boosting" } },
    { "intellect", "Intellect", { "%d+ intellect" } },
    { "spirit", "Spirit", { "%d+ spirit", "and spirit" } },
    { "attack", "Attack Power", { "%d+ attack power" } },
    { "spell", "Spell Damage", { "%d+ spell damage", "spell damage by" } },
    { "healing", "Healing", { "%d+ healing power", "healing done by" } },
    { "crit", "Critical Strike", { "critical strike" } },
    { "armor", "Armor", { "%d+ armor" } },
    { "fishing", "Fishing skill", { "fishing skill" } },
    { "herbalism", "Herbalism skill", { "herbalism skill" } },
    { "speed", "Movement speed", { "movement speed" } },
    { "mana", "Restores mana", { "%d+ mana" } },
    { "camp", "Camp features", { "camp%a* feature" } },
    { "health", "Health only (no buff)" },
    { "other", "Other effects" },
}

-- The buff filter keys a recipe's food matches, as a set.
function FC:RecipeBuffs(recipeID)
    local recipe = recipes[recipeID]
    local effect = recipe and recipe.effect and recipe.effect:lower() or ""
    local buffs, any = {}, false
    for _, filter in ipairs(self.BUFF_FILTERS) do
        for _, pattern in ipairs(filter[3] or {}) do
            if effect:find(pattern) then
                buffs[filter[1]], any = true, true
                break
            end
        end
    end
    if not any then
        if effect:find("%d+ health") or effect:find("heals %d+") then buffs.health = true else buffs.other = true end
    end
    return buffs
end

-- Splits "a; b; ; d" keeping empty entries, so names/zones/coords stay aligned.
local function splitList(text)
    local list = {}
    for part in ((text or "") .. ";"):gmatch("([^;]*);") do
        table.insert(list, (part:gsub("^%s+", ""):gsub("%s+$", "")))
    end
    return list
end

-- "x,y" (2+ sources agree) or "x,y?" (one source only: unconfirmed).
local function parseXY(text)
    local x, y, mark = (text or ""):match("^%s*([%d%.]+)%s*,%s*([%d%.]+)%s*(%??)")
    return tonumber(x), tonumber(y), mark == "?"
end

-- Everything the detail pop-up shows for one recipe. Each location is one NPC
-- (or mob/quest) with a map position when one is known: recorded in game first,
-- then positions verified by two or more sources.
function FC:RecipeDetail(recipeID)
    local recipe = recipes[recipeID]
    if not recipe then return nil end
    local faction = UnitFactionGroup and UnitFactionGroup("player")
    local detail = {
        id = recipeID, name = spellName(recipeID, recipe.name), known = self:IsRecipeKnown(recipeID),
        skill = self.CookingSkill and self.CookingSkill[recipeID], reagents = {}, locations = {}, hidden = {},
        effect = self:FoodEffect(recipeID),
        gameText = recipe.source and tostring(recipe.source):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|n", "\n"),
    }
    for itemID, count in pairs(recipe.reagents) do table.insert(detail.reagents, { itemID = itemID, count = count }) end
    table.sort(detail.reagents, function(a, b) return a.itemID < b.itemID end)

    local added = {}
    local function add(location)
        local key = location.label .. "|" .. (location.quest or "") .. "|" .. location.who .. "|" .. (location.zone or "")
        if added[key] then return end
        added[key] = true
        local recorded = location.who and self:NPCLocation(location.who)
        if recorded then
            location.zone, location.map, location.x, location.y, location.recorded, location.unconfirmed =
                recorded.zone, recorded.map, recorded.x, recorded.y, true, nil
        end
        table.insert(detail.locations, location)
    end
    local function usable(source)
        if OPEN_TO_ALL[source.faction] or source.faction == faction then return true end
        detail.hidden[source.faction] = true
        return false
    end

    for _, source in ipairs(self:ObservedSources(recipeID)) do
        if usable(source) then
            add({ label = sourceLabel(source), who = source.who, zone = source.place, map = source.map,
                x = source.x, y = source.y, cost = source.cost, recorded = source.x ~= nil })
        end
    end
    for _, source in ipairs(self.CookingSources and self.CookingSources[recipeID] or {}) do
        if usable(source) then
            if source.type == "Trainer" and source.faction == "Both" then
                for _, trainer in ipairs(self.CookingTrainers or {}) do
                    if trainer.faction == faction then
                        add({ label = "Trainer", who = trainer.name, zone = trainer.zone, x = trainer.x, y = trainer.y,
                            unconfirmed = trainer.unconfirmed })
                    end
                end
            elseif source.type == "Automatic" then
                add({ label = "Automatic", who = "Learned with Cooking", noWaypoint = true })
            elseif source.giver then
                -- Quests point at the NPC who gives them.
                local x, y, unconfirmed = parseXY(source.coords)
                add({ label = sourceLabel(source), who = source.giver, quest = source.who, zone = source.zone,
                    x = x, y = y, unconfirmed = unconfirmed })
            else
                local names, zones, coords = splitList(source.who), splitList(source.zone), splitList(source.coords)
                for i, name in ipairs(names) do
                    local x, y, unconfirmed = parseXY(coords[i])
                    add({ label = sourceLabel(source), who = name, zone = zones[i] ~= "" and zones[i] or zones[1] or "",
                        x = x, y = y, unconfirmed = unconfirmed, cost = source.cost })
                end
            end
        end
    end
    -- Nothing confirmed: show what a single website suggests (marked Suggested until
    -- it is found in game), or Unknown.
    if #detail.locations == 0 and not next(detail.hidden) then
        for _, source in ipairs(self.SuggestedSources and self.SuggestedSources[recipeID] or {}) do
            if OPEN_TO_ALL[source.faction] or source.faction == faction then
                local x, y = parseXY(source.coords)
                if source.giver then
                    add({ label = sourceLabel(source), who = source.giver, quest = source.who, zone = source.zone,
                        x = x, y = y, suggested = true, note = source.note })
                else
                    add({ label = sourceLabel(source), who = source.who, zone = source.zone, x = x, y = y,
                        suggested = true, note = source.note })
                end
            end
        end
    end
    if #detail.locations == 0 and not next(detail.hidden) and recipe.auto then
        add({ label = "Automatic", who = "learned together with Cooking", noWaypoint = true })
    end
    if #detail.locations == 0 and not next(detail.hidden) then
        add({ label = "Unknown", who = "not confirmed yet", noWaypoint = true,
            note = "No two sources agree on where this is learned. It is recorded here once you find it in game." })
    end
    return detail
end

function FC:RecipeRows()
    local rows = {}
    for recipeID, recipe in pairs(recipes) do
        -- same-name copies show as one row (see `primary`)
        if primary[recipeID] == recipeID then
            local known = self:IsRecipeKnown(recipeID)
            -- [New] only when every same-name copy is new to Forever
            local new = true
            for _, id in ipairs(copies[recipeID]) do
                if not (FC.NewRecipes and FC.NewRecipes[id]) then new = false end
            end
            table.insert(rows, {
                id = recipeID, name = spellName(recipeID, recipe.name), known = known, new = new,
                buffs = self:RecipeBuffs(recipeID),
                learnFrom = known and "" or self:RecipeSourceShort(recipeID, true),
                category = known and "Known" or self:RecipeSourceShort(recipeID, true),
                zone = known and "" or self:RecipeZone(recipeID),
            })
        end
    end
    return rows
end

-- Total Cooking recipes and how many this character knows.
function FC:RecipeStats()
    local total, known = 0, 0
    for recipeID in pairs(recipes) do
        if primary[recipeID] == recipeID then
            total = total + 1
            if self:IsRecipeKnown(recipeID) then known = known + 1 end
        end
    end
    return total, known
end

function FC:RecipeCount()
    local n = 0
    for _ in pairs(recipes) do n = n + 1 end
    return n
end

FC:OnInit(function()
    FC.db.recipes = FC.db.recipes or {}
    FC.char.knownRecipes = FC.char.knownRecipes or {}
    rebuildIndex()

    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, onItemTooltip)
    elseif GameTooltip and GameTooltip.HookScript then
        GameTooltip:HookScript("OnTooltipSetItem", function(tooltip) onItemTooltip(tooltip) end)
        if ItemRefTooltip then ItemRefTooltip:HookScript("OnTooltipSetItem", function(tooltip) onItemTooltip(tooltip) end) end
    end
end)

FC:On("TRADE_SKILL_SHOW", queueScan)
FC:On("TRADE_SKILL_LIST_UPDATE", queueScan)
FC:On("TRADE_SKILL_DATA_SOURCE_CHANGED", queueScan)
-- A waypoint set for a recipe is no longer needed once that recipe is learned.
function FC:ClearWaypointIfLearned()
    local learned = {}
    for _, entry in ipairs(self:Waypoints()) do
        if entry.recipeID and self:IsRecipeKnown(entry.recipeID) then table.insert(learned, entry.recipeID) end
    end
    for _, recipeID in ipairs(learned) do
        local recipe = recipes[recipeID]
        self:ClearWaypoint(recipeID)
        self:Notify(string.format("Learned %s - waypoint removed.", spellName(recipeID, recipe and recipe.name or "the recipe")))
    end
end

-- Both events carry the learned spell/recipe ID. The spellbook can lag a moment
-- behind, so a Cooking recipe named by the event is marked known directly.
local function onLearned(_, id)
    if type(id) == "number" and not isSecret(id) and recipes[id] then FC.char.knownRecipes[id] = true end
    FC.listsDirty = true
    C_Timer.After(0.5, function() FC:ClearWaypointIfLearned() end)
end
FC:On("LEARNED_SPELL_IN_TAB", onLearned)
FC:On("NEW_RECIPE_LEARNED", onLearned)
-- Item names arrive asynchronously; refresh what shows them, at most twice a second.
local namesPending
local function itemNamesArrived()
    FC.listsDirty = true
    if namesPending then return end
    namesPending = true
    C_Timer.After(0.5, function()
        namesPending = nil
        if FC.RefreshRecipeDetail then FC:RefreshRecipeDetail() end
    end)
end
FC:On("GET_ITEM_INFO_RECEIVED", itemNamesArrived)
FC:On("SPELL_TEXT_UPDATE", itemNamesArrived)
FC:On("ITEM_DATA_LOAD_RESULT", itemNamesArrived)
