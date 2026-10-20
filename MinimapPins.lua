local ADDON_NAME, FC = ...

-- The addon icon on the minimap for every tracked recipe location. Locations beyond
-- the minimap's range are a light blue arrow on its edge, pointing their way.
local PIN_SIZE = 16
local ARROW_SIZE = 11
local ARROW = "Interface\\AddOns\\ForeverChef\\Media\\WaypointArrow.blp"
local UPDATE_SECONDS = 0.1

-- Minimap view diameter in yards for each zoom level (0-5), outdoors and indoors.
local VIEW_YARDS = {
    outdoor = { [0] = 466.67, 400, 333.33, 266.67, 200, 133.33 },
    indoor = { [0] = 300, 240, 180, 120, 80, 50 },
}

local pins = {}
local driver
local elapsed = 0

local function isSecret(value)
    return issecretvalue and issecretvalue(value)
end

local function createPin()
    local pin = CreateFrame("Frame", nil, Minimap)
    pin:SetSize(PIN_SIZE, PIN_SIZE)
    pin:SetFrameStrata("MEDIUM")
    pin:SetFrameLevel(Minimap:GetFrameLevel() + 5)
    pin.icon = pin:CreateTexture(nil, "ARTWORK")
    pin.icon:SetAllPoints()
    pin.icon:SetTexture(FC.ICON)
    pin.arrow = pin:CreateTexture(nil, "ARTWORK")
    pin.arrow:SetSize(ARROW_SIZE, ARROW_SIZE)
    pin.arrow:SetPoint("CENTER")
    pin.arrow:SetTexture(ARROW)
    pin.arrow:Hide()
    -- Hover shows a tooltip, but clicks must reach the minimap underneath
    -- (pinging, opening the map). Clients that cannot separate the two get no
    -- tooltip rather than icons that swallow clicks.
    if pin.SetMouseClickEnabled and pin.SetMouseMotionEnabled then
        pin:SetMouseMotionEnabled(true)
        pin:SetMouseClickEnabled(false)
    else
        pin:EnableMouse(false)
    end
    pin:SetScript("OnEnter", function(self)
        local entry = self.entry
        local data = FC.CookingData and FC.CookingData[entry.recipeID]
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine(entry.label or (data and data.name) or "Recipe", 1, 0.82, 0.2)
        GameTooltip:AddLine(string.format("%s - %s", entry.who or "?", entry.zone or ""), 1, 1, 1)
        GameTooltip:AddLine(string.format("%d yards", self.yards or 0), 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    pin:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return pin
end

-- The player's zone map and position on it (0-1), or nil (instances, loading).
local function playerOnMap()
    if IsInInstance and IsInInstance() then return nil end
    local best = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local mapID = best and FC.Geo.ZoneMapID(best) or best
    local pos = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
    if not pos then return nil end
    local x, y = pos:GetXY()
    if isSecret(x) then return nil end
    return mapID, x, y
end

-- Where `entry` falls on `mapID` in 0-1 coordinates (may be outside 0-1 when it
-- lies beyond that map's edges), via world space for other zones.
local function entryOnMap(entry, mapID)
    if entry.map == mapID then return entry.x / 100, entry.y / 100 end
    if not (C_Map.GetWorldPosFromMapPos and C_Map.GetMapPosFromWorldPos and CreateVector2D) then return nil end
    local continent, world = C_Map.GetWorldPosFromMapPos(entry.map, CreateVector2D(entry.x / 100, entry.y / 100))
    if not continent or not world then return nil end
    local _, pos = C_Map.GetMapPosFromWorldPos(continent, world, mapID)
    if not pos then return nil end
    return pos:GetXY()
end

local function viewRadiusYards()
    local zoom = Minimap.GetZoom and Minimap:GetZoom() or 0
    local indoors = IsIndoors and IsIndoors()
    return (VIEW_YARDS[indoors and "indoor" or "outdoor"][zoom] or 466.67) / 2
end

function FC:RefreshMinimapPins()
    if not Minimap or not self.char then return end
    local entries = self:Waypoints()
    local mapID, px, py = playerOnMap()
    local width, height
    if mapID and C_Map.GetMapWorldSize then width, height = C_Map.GetMapWorldSize(mapID) end
    local shown = 0
    if mapID and width and height and width > 0 and height > 0 and #entries > 0 then
        local radiusYards = viewRadiusYards()
        local radiusPixels = Minimap:GetWidth() / 2
        local rotate = GetCVar and GetCVar("rotateMinimap") == "1"
        local facing = rotate and GetPlayerFacing and GetPlayerFacing()
        if isSecret(facing) then facing = nil end
        -- offsets in yards: east (+x) and south (+y) of the player
        local placed = {}
        for _, entry in ipairs(entries) do
            local ex, ey = entryOnMap(entry, mapID)
            if ex then
                local dx, dy = (ex - px) * width, (ey - py) * height
                table.insert(placed, { entry = entry, dx = dx, dy = dy, yards = math.sqrt(dx * dx + dy * dy) })
            end
        end
        for _, p in ipairs(placed) do
            local dx, dy = p.dx, p.dy
            if facing then
                -- a rotating minimap keeps the player's facing at the top
                local c, s = math.cos(facing), math.sin(facing)
                dx, dy = dx * c - dy * s, dx * s + dy * c
            end
            local x, y = dx / radiusYards * radiusPixels, dy / radiusYards * radiusPixels
            local length = math.sqrt(x * x + y * y)
            local edge = radiusPixels - ARROW_SIZE / 2
            local onEdge = length > edge
            if onEdge then x, y = x / length * edge, y / length * edge end
            shown = shown + 1
            local pin = pins[shown] or createPin()
            pins[shown] = pin
            pin.entry, pin.yards, pin.onEdge = p.entry, p.yards, onEdge
            -- the arrow texture points up; turn it toward the location (x east, y south)
            local arrow = onEdge and pin.arrow.SetRotation
            if arrow then pin.arrow:SetRotation(math.atan2(-x, -y)) end
            pin.arrow:SetShown(arrow and true or false)
            pin.icon:SetShown(not arrow)
            pin:SetAlpha((onEdge and not arrow) and 0.6 or 1)
            pin:ClearAllPoints()
            pin:SetPoint("CENTER", Minimap, "CENTER", x, -y)
            pin:Show()
        end
    end
    for i = shown + 1, #pins do pins[i]:Hide() end
end

-- Positions change as the player moves and turns, so refresh on a short timer
-- while anything is tracked; with nothing tracked the timer does no work.
FC:OnInit(function()
    if not Minimap then return end
    driver = CreateFrame("Frame")
    driver:SetScript("OnUpdate", function(_, delta)
        elapsed = elapsed + delta
        if elapsed < UPDATE_SECONDS then return end
        elapsed = 0
        if #FC:Waypoints() == 0 and not (pins[1] and pins[1]:IsShown()) then return end
        local ok, err = pcall(FC.RefreshMinimapPins, FC)
        if not ok then FC:Debug("Minimap pins: " .. tostring(err)) end
    end)
end)
