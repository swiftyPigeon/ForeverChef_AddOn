local ADDON_NAME, FC = ...

-- Icons on the world map for every tracked recipe location. Hover for the
-- recipe and NPC. Clicks pass through to the map (opening zones, etc.).
-- Pins are placed on the map canvas by hand rather than through a map data
-- provider, so no XML templates are needed.
local PIN_SIZE = 22
local pins = {}
local hooked

local function mapFrame()
    local frame = _G.WorldMapFrame
    if frame and frame.GetCanvas and frame.GetMapID then return frame end
end

-- Where `entry` falls on the map being shown (0-1 coordinates), or nil when it
-- is off that map. Other maps (continents, parent zones) go through world space.
local function positionOn(mapID, entry)
    if entry.map == mapID then return entry.x / 100, entry.y / 100 end
    if not (C_Map and C_Map.GetWorldPosFromMapPos and C_Map.GetMapPosFromWorldPos and CreateVector2D) then return nil end
    local continent, world = C_Map.GetWorldPosFromMapPos(entry.map, CreateVector2D(entry.x / 100, entry.y / 100))
    if not continent or not world then return nil end
    local _, pos = C_Map.GetMapPosFromWorldPos(continent, world, mapID)
    if not pos then return nil end
    local x, y = pos:GetXY()
    if x < 0 or x > 1 or y < 0 or y > 1 then return nil end
    return x, y
end

local function recipeName(recipeID, label)
    if label then return label end
    local data = FC.CookingData and FC.CookingData[recipeID]
    local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(recipeID)
    return name or (data and data.name) or ("Recipe " .. tostring(recipeID))
end

local function createPin(canvas)
    local pin = CreateFrame("Frame", nil, canvas)
    pin:SetSize(PIN_SIZE, PIN_SIZE)
    pin:SetFrameStrata("HIGH")
    pin.icon = pin:CreateTexture(nil, "ARTWORK")
    pin.icon:SetAllPoints()
    pin.icon:SetTexture(FC.ICON)
    pin:SetScript("OnEnter", function(self)
        local entry = self.entry
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(recipeName(entry.recipeID, entry.label), 1, 0.82, 0.2)
        GameTooltip:AddLine(string.format("%s - %s (%.1f, %.1f)", entry.who or "?", entry.zone or "", entry.x, entry.y), 1, 1, 1)
        GameTooltip:Show()
    end)
    pin:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- Hover only: clicks must reach the map underneath (e.g. opening a zone).
    if pin.SetMouseClickEnabled and pin.SetMouseMotionEnabled then
        pin:SetMouseMotionEnabled(true)
        pin:SetMouseClickEnabled(false)
    else
        pin:EnableMouse(false)
    end
    return pin
end

function FC:RefreshMapPins()
    local frame = mapFrame()
    if not frame or not self.char then return end
    local canvas = frame:GetCanvas()
    local shown = 0
    if canvas and frame:IsShown() then
        local mapID = frame:GetMapID()
        local width, height = canvas:GetWidth(), canvas:GetHeight()
        local container = frame.ScrollContainer
        local scale = container and container.GetCanvasScale and container:GetCanvasScale() or 1
        for _, entry in ipairs(self:Waypoints()) do
            local x, y = positionOn(mapID, entry)
            if x then
                shown = shown + 1
                local pin = pins[shown] or createPin(canvas)
                pins[shown] = pin
                pin.entry = entry
                -- Keep a constant on-screen size whatever the zoom: undo the canvas
                -- scale on the pin, and give offsets in the pin's own units.
                pin:SetScale(1 / scale)
                pin:SetFrameLevel(canvas:GetFrameLevel() + 2000)
                pin:ClearAllPoints()
                pin:SetPoint("CENTER", canvas, "TOPLEFT", x * width * scale, -y * height * scale)
                pin:Show()
            end
        end
    end
    for i = shown + 1, #pins do pins[i]:Hide() end
end

local function safeRefresh()
    local ok, err = pcall(FC.RefreshMapPins, FC)
    if not ok then FC:Debug("Map pins: " .. tostring(err)) end
end

local function hookMap()
    local frame = mapFrame()
    if hooked or not frame then return end
    hooked = true
    frame:HookScript("OnShow", safeRefresh)
    for _, method in ipairs({ "OnMapChanged", "OnCanvasScaleChanged", "OnCanvasSizeChanged" }) do
        if type(frame[method]) == "function" then hooksecurefunc(frame, method, safeRefresh) end
    end
end

FC:OnInit(hookMap)
-- The world map is load-on-demand on some clients; hook it once it exists.
FC:On("ADDON_LOADED", function(_, name)
    if name == "Blizzard_WorldMap" then hookMap() end
end)
FC:On("PLAYER_ENTERING_WORLD", hookMap)
