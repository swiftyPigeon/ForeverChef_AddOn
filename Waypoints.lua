local ADDON_NAME, FC = ...

-- Map waypoints for recipe sources: Forever Chef's own icons on the world map
-- and minimap (MapPins.lua, MinimapPins.lua), plus a TomTom arrow when TomTom is
-- installed. The game's own map pin is never used.
-- Locations are { zone = "<zone name>", x, y } in 0-100 map coordinates, or
-- carry `map` (a uiMapID) when it was recorded in game.
local AZEROTH = 947
local ZONE_TYPE = Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3

local mapIDByName
local tomtomUID

-- Zone names -> uiMapID, read from the client so it matches its maps and locale.
local function buildZoneIndex()
    mapIDByName = {}
    if not (C_Map and C_Map.GetMapChildrenInfo) then return end
    for _, info in ipairs(C_Map.GetMapChildrenInfo(AZEROTH, ZONE_TYPE, true) or {}) do
        if info.name and not mapIDByName[info.name] then mapIDByName[info.name] = info.mapID end
    end
end

function FC:MapIDForZone(zone)
    if not mapIDByName then buildZoneIndex() end
    -- Drop notes in brackets first: "Stormwind City (Old Town, upstairs ...)" -> "Stormwind City"
    zone = tostring(zone or ""):gsub("%s*%b()", "")
    if mapIDByName[zone] then return mapIDByName[zone] end
    -- "Booty Bay, Stranglethorn Vale" -> try each comma-separated part, last first.
    local parts = {}
    for part in zone:gmatch("[^,]+") do table.insert(parts, (part:gsub("^%s+", ""):gsub("%s+$", ""))) end
    for i = #parts, 1, -1 do
        local name = parts[i]:gsub("%s*%(.*%)$", "")
        if mapIDByName[name] then return mapIDByName[name] end
    end
end

-- Several recipes can be tracked at once, one chosen location each, saved per
-- character in order: char.waypoints = { { recipeID, who, map, zone, x, y }, ... }.
-- Every tracked location gets an icon, and TomTom (if installed) an arrow.
local tomtomUIDs = {}    -- recipeID -> TomTom waypoint

local function list()
    FC.char.waypoints = FC.char.waypoints or {}
    return FC.char.waypoints
end

function FC:Waypoints()
    return list()
end

function FC:WaypointFor(recipeID)
    for _, entry in ipairs(list()) do
        if entry.recipeID == recipeID then return entry end
    end
end

local function refresh()
    FC.listsDirty = true
    if FC.RefreshLists then FC:RefreshLists() end
    if FC.RefreshRecipeDetail then FC:RefreshRecipeDetail() end
    -- map drawing must never stop a waypoint from being set or cleared
    if FC.RefreshMapPins then pcall(FC.RefreshMapPins, FC) end
    if FC.RefreshMinimapPins then pcall(FC.RefreshMinimapPins, FC) end
    if FC.RefreshRanks then pcall(FC.RefreshRanks, FC) end
end

local function addArrow(entry)
    if not (TomTom and TomTom.AddWaypoint) then return false end
    local ok, uid = pcall(TomTom.AddWaypoint, TomTom, entry.map, entry.x / 100, entry.y / 100,
        { title = entry.who, persistent = false, minimap = true, world = true })
    if ok and uid then tomtomUIDs[entry.recipeID or 0] = uid end
    return ok and uid ~= nil
end

local function removeArrow(recipeID)
    local uid = tomtomUIDs[recipeID or 0]
    if uid and TomTom and TomTom.RemoveWaypoint then pcall(TomTom.RemoveWaypoint, TomTom, uid) end
    tomtomUIDs[recipeID or 0] = nil
end

local function removeEntry(recipeID)
    local entries = list()
    local removed
    for i = #entries, 1, -1 do
        if entries[i].recipeID == recipeID then removed = table.remove(entries, i) end
    end
    removeArrow(recipeID)
    return removed
end

-- With a recipeID, stops tracking that recipe; without one, clears every waypoint.
function FC:ClearWaypoint(recipeID)
    if recipeID then
        removeEntry(recipeID)
    else
        for _, entry in ipairs(list()) do removeArrow(entry.recipeID) end
        wipe(list())
    end
    refresh()
end

-- Tracks `recipeID` at `location` (replacing that recipe's previous choice).
-- Returns true when it is tracked.
-- `recipeID` can also be a string key (e.g. "rank:Expert"); `label` then names it
-- on the map and minimap icons.
function FC:SetWaypoint(location, title, recipeID, label)
    local mapID = location.map or self:MapIDForZone(location.zone)
    if not mapID or not location.x or not location.y then
        self:ShowToast("No map position for " .. tostring(title) .. " yet.")
        return false
    end
    removeEntry(recipeID)
    local entry = { recipeID = recipeID, who = title, map = mapID, zone = location.zone, x = location.x, y = location.y,
        label = label }
    table.insert(list(), entry)
    addArrow(entry)
    local count = #list()
    self:ShowToast(string.format("Waypoint set: %s (%s %.1f, %.1f)%s", title, location.zone or "", location.x, location.y,
        count > 1 and string.format(" - %d recipes tracked", count) or ""))
    refresh()
    return true
end

FC:OnInit(function()
    -- Older versions kept a single waypoint without its location; it cannot be restored.
    FC.char.waypoint = nil
    -- Versions up to 0.6.1 put the game's own map pin on a tracked location:
    -- remove it once, if it is still on one of ours.
    if FC.char.pinnedRecipeID ~= nil then
        local point = C_Map and C_Map.GetUserWaypoint and C_Map.GetUserWaypoint()
        local px, py
        if point and point.position then px, py = point.position:GetXY() end
        for _, entry in ipairs(px and list() or {}) do
            if entry.map == point.uiMapID and math.abs(entry.x - px * 100) < 0.1 and math.abs(entry.y - py * 100) < 0.1 then
                C_Map.ClearUserWaypoint()
                break
            end
        end
        FC.char.pinnedRecipeID = nil
    end
    -- After a reload: recreate TomTom arrows (they are not saved by TomTom).
    for _, entry in ipairs(list()) do addArrow(entry) end
end)
