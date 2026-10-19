local ADDON_NAME, FC = ...

-- Map waypoints for recipe sources: Blizzard's own user waypoint (with the
-- on-screen tracking arrow), plus a TomTom arrow when TomTom is installed.
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
-- Blizzard allows a single map pin (char.pinnedRecipeID): a newly chosen location
-- gets it; when the pinned one goes (learned, or removed from the map), the pin
-- moves to the closest remaining location. TomTom (if installed) gets an arrow for each.
local tomtomUIDs = {}    -- recipeID -> TomTom waypoint
local placingPin         -- our own pin changes also fire USER_WAYPOINT_UPDATED

local function list()
    FC.char.waypoints = FC.char.waypoints or {}
    return FC.char.waypoints
end

function FC:Waypoints()
    return list()
end

-- The entry whose location holds the map pin, or nil.
function FC:ActiveWaypoint()
    local entries = self.char and self.char.waypoints
    if not entries or #entries == 0 then return nil end
    for _, entry in ipairs(entries) do
        if entry.recipeID == self.char.pinnedRecipeID then return entry end
    end
    return entries[#entries]
end

-- World-space position (continent + yards) of a point on a map, for distances.
local function worldPosition(map, x, y)
    if not (C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D and map) then return nil end
    local continent, pos = C_Map.GetWorldPosFromMapPos(map, CreateVector2D(x / 100, y / 100))
    if not continent or not pos then return nil end
    local wx, wy = pos:GetXY()
    return { continent = continent, x = wx, y = wy }
end

local function playerPosition()
    local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local pos = map and C_Map.GetPlayerMapPosition(map, "player")
    if not pos then return nil end
    local x, y = pos:GetXY()
    return worldPosition(map, x * 100, y * 100)
end

-- The tracked entry closest to `from` (a world position), same continent first;
-- falls back to the newest entry when no distance can be measured.
local function closestEntry(from)
    local entries = FC.char.waypoints or {}
    local best, bestDistance
    if from then
        for _, entry in ipairs(entries) do
            local pos = worldPosition(entry.map, entry.x, entry.y)
            if pos then
                local distance = math.sqrt((pos.x - from.x) ^ 2 + (pos.y - from.y) ^ 2)
                if pos.continent ~= from.continent then distance = distance + 1e9 end
                if not bestDistance or distance < bestDistance then best, bestDistance = entry, distance end
            end
        end
    end
    return best or entries[#entries]
end

function FC:WaypointFor(recipeID)
    for _, entry in ipairs(list()) do
        if entry.recipeID == recipeID then return entry end
    end
end

local function hasMapWaypoint()
    return C_Map and C_Map.HasUserWaypoint and C_Map.HasUserWaypoint()
end

local function refresh()
    FC.listsDirty = true
    if FC.RefreshLists then FC:RefreshLists() end
    if FC.RefreshRecipeDetail then FC:RefreshRecipeDetail() end
end

-- Put Blizzard's single map pin on the newest entry, or remove it when none is left.
local function placeMapPin()
    if not (C_Map and C_Map.SetUserWaypoint) then return false end
    placingPin = true
    local entry = FC:ActiveWaypoint()
    local placed = false
    if not entry then
        if C_Map.ClearUserWaypoint then C_Map.ClearUserWaypoint() end
    elseif UiMapPoint and UiMapPoint.CreateFromCoordinates
        and (not C_Map.CanSetUserWaypointOnMap or C_Map.CanSetUserWaypointOnMap(entry.map)) then
        C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(entry.map, entry.x / 100, entry.y / 100))
        if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
        placed = true
    end
    placingPin = nil
    return placed
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

-- After the pinned entry is gone: pin the closest remaining one to the player
-- (or to where the removed one was) and say which it is.
local function pinClosest(removed)
    local from = playerPosition() or (removed and worldPosition(removed.map, removed.x, removed.y))
    local nextEntry = closestEntry(from)
    FC.char.pinnedRecipeID = nextEntry and nextEntry.recipeID
    placeMapPin()
    if nextEntry then
        FC:ShowToast(string.format("Next waypoint: %s (%s %.1f, %.1f)", nextEntry.who, nextEntry.zone or "", nextEntry.x, nextEntry.y))
    end
end

-- With a recipeID, stops tracking that recipe; without one, clears every waypoint.
function FC:ClearWaypoint(recipeID)
    if recipeID then
        local wasPinned = self:ActiveWaypoint() and self:ActiveWaypoint().recipeID == recipeID
        local removed = removeEntry(recipeID)
        if wasPinned then pinClosest(removed) end
    else
        for _, entry in ipairs(list()) do removeArrow(entry.recipeID) end
        wipe(list())
        self.char.pinnedRecipeID = nil
        placeMapPin()
    end
    refresh()
end

-- Tracks `recipeID` at `location` (replacing that recipe's previous choice) and
-- moves the map pin there. Returns true when a pin or arrow was placed.
function FC:SetWaypoint(location, title, recipeID)
    local mapID = location.map or self:MapIDForZone(location.zone)
    if not mapID or not location.x or not location.y then
        self:ShowToast("No map position for " .. tostring(title) .. " yet.")
        return false
    end
    removeEntry(recipeID)
    local entry = { recipeID = recipeID, who = title, map = mapID, zone = location.zone, x = location.x, y = location.y }
    table.insert(list(), entry)
    self.char.pinnedRecipeID = recipeID
    local pinned = placeMapPin()
    local arrow = addArrow(entry)
    if not (pinned or arrow) then
        removeEntry(recipeID)
        self:ShowToast("This client cannot place map waypoints here.")
        refresh()
        return false
    end
    local count = #list()
    self:ShowToast(string.format("Waypoint set: %s (%s %.1f, %.1f)%s", title, location.zone or "", location.x, location.y,
        count > 1 and string.format(" - %d recipes tracked", count) or ""))
    refresh()
    return true
end

-- The player removed the pin from the map: stop tracking that recipe and move
-- the pin to the next tracked one.
FC:On("USER_WAYPOINT_UPDATED", function()
    if placingPin or not FC.char or not C_Map.HasUserWaypoint or hasMapWaypoint() then return end
    local entry = FC:ActiveWaypoint()
    if entry then
        pinClosest(removeEntry(entry.recipeID))
        refresh()
    end
end)

FC:OnInit(function()
    -- Older versions kept a single waypoint without its location; it cannot be restored.
    FC.char.waypoint = nil
    -- After a reload: put the pin back if it is gone, and recreate TomTom arrows
    -- (they are not saved by TomTom).
    if #list() > 0 then
        if C_Map and C_Map.HasUserWaypoint and not hasMapWaypoint() then placeMapPin() end
        for _, entry in ipairs(list()) do addArrow(entry) end
    end
end)
