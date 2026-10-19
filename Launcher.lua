local ADDON_NAME, FC = ...

-- Minimap button, LibDataBroker launcher (when a broker display is installed)
-- and Addon Compartment entry, following Forever Profession Master's pattern.
-- The brand mark is a recipe scroll with the cooking icon over its corner.
-- Places that only take a single texture (broker bars, the AddOns list) use
-- the cooking icon alone.
local SCROLL_ICON = "Interface\\Icons\\INV_Scroll_03"
local COOKING_ICON = "Interface\\Icons\\INV_Misc_Food_15"
local ICON = COOKING_ICON
local MINIMAP_PADDING = 10

FC.ICON = ICON

-- Draws the scroll filling `size`, with the cooking icon at about 60% size
-- in the bottom-right corner, outlined so it reads against the scroll.
function FC:CreateBrandIcon(parent, size, layer)
    local scroll = parent:CreateTexture(nil, layer or "ARTWORK", nil, 0)
    scroll:SetTexture(SCROLL_ICON)
    scroll:SetSize(size, size)
    scroll:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local badgeSize = math.floor(size * 0.6 + 0.5)
    local outline = parent:CreateTexture(nil, layer or "ARTWORK", nil, 1)
    outline:SetColorTexture(0, 0, 0, 0.9)
    outline:SetSize(badgeSize + 2, badgeSize + 2)
    outline:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", math.floor(size * 0.15), -math.floor(size * 0.15))

    local cooking = parent:CreateTexture(nil, layer or "ARTWORK", nil, 2)
    cooking:SetTexture(COOKING_ICON)
    cooking:SetSize(badgeSize, badgeSize)
    cooking:SetPoint("CENTER", outline, "CENTER")
    cooking:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    return scroll
end

local function addTooltipLines(tooltip)
    tooltip:AddLine("Forever Chef", 1.00, 0.55, 0.15)
    if FC.db then
        local total, known = FC:RecipeStats()
        tooltip:AddLine(string.format("You know %d of %d Cooking recipes", known, total), 0.72, 0.76, 0.82)
    end
    tooltip:AddLine("Left-click: Open or close", 0.90, 0.92, 0.95)
    tooltip:AddLine("Drag: Move this button", 0.54, 0.60, 0.68)
end

local function showTooltip(owner)
    GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
    addTooltipLines(GameTooltip)
    GameTooltip:Show()
end

local function settings()
    FC.char.ui = FC.char.ui or {}
    return FC.char.ui
end

function FC:UpdateMinimapButtonPosition()
    local button = self.minimapButton
    if not button or button:GetParent() ~= Minimap then return end
    local angle = math.rad(tonumber(settings().minimapAngle) or 200)
    local radius = (Minimap:GetWidth() or 140) * 0.5 + MINIMAP_PADDING
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function moveToCursor()
    local minimapX, minimapY = Minimap:GetCenter()
    if not minimapX then return end
    local cursorX, cursorY = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    settings().minimapAngle = math.deg(math.atan2(cursorY / scale - minimapY, cursorX / scale - minimapX))
    FC:UpdateMinimapButtonPosition()
end

local function createMinimapButton()
    if FC.minimapButton or not Minimap then return end
    -- A named Minimap child is picked up by HidingBar/MBB-style collectors.
    local button = CreateFrame("Button", "ForeverChefMinimapButton", Minimap)
    button:SetSize(32, 32)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(54, 54)
    border:SetPoint("TOPLEFT", 0, 0)

    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    background:SetSize(20, 20)
    background:SetPoint("CENTER")

    -- Nudged up-left so the corner badge stays inside the round border.
    local icon = FC:CreateBrandIcon(button, 18)
    icon:SetPoint("CENTER", -2, 2)

    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    highlight:SetBlendMode("ADD")
    highlight:SetAllPoints()

    button:SetScript("OnClick", function()
        if button.wasDragged then return end
        FC:ToggleWindow()
    end)
    button:SetScript("OnDragStart", function()
        button.wasDragged = true
        button:SetScript("OnUpdate", moveToCursor)
    end)
    button:SetScript("OnDragStop", function()
        button:SetScript("OnUpdate", nil)
        moveToCursor()
        C_Timer.After(0, function() button.wasDragged = nil end)
    end)
    button:SetScript("OnEnter", showTooltip)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)

    FC.minimapButton = button
    FC:UpdateMinimapButtonPosition()
end

local function createBrokerLauncher()
    if type(LibStub) ~= "table" or type(LibStub.GetLibrary) ~= "function" then return end
    local ok, broker = pcall(LibStub.GetLibrary, LibStub, "LibDataBroker-1.1", true)
    if not ok or not broker then return end
    pcall(broker.NewDataObject, broker, "ForeverChef", {
        type = "launcher",
        icon = ICON,
        label = "Forever Chef",
        OnClick = function() FC:ToggleWindow() end,
        OnTooltipShow = addTooltipLines,
    })
end

function ForeverChef_OnAddonCompartmentClick()
    FC:ToggleWindow()
end

function ForeverChef_OnAddonCompartmentEnter(_, menuButtonFrame)
    showTooltip(type(menuButtonFrame) == "table" and menuButtonFrame or UIParent)
end

function ForeverChef_OnAddonCompartmentLeave()
    GameTooltip:Hide()
end

FC:OnInit(function()
    createMinimapButton()
    createBrokerLauncher()
end)
