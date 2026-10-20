local ADDON_NAME, FC = ...

-- Pop-up with everything about one Cooking recipe, opened by clicking its row in
-- the Recipes tab: status, required skill, ingredients (and how many you carry),
-- every place to learn it, and what eating the food does. Each place with a map position has a radio
-- button that sets a map waypoint (and a TomTom arrow when TomTom is installed). A recipe with no
-- confirmed place shows "Suggested" ones instead (named by a single website).
local C = FC.COLORS
local WIDTH, HEIGHT = 400, 460
local ROW_GAP = 4

local popup

local function backdrop(frame, bg, edge)
    frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    frame:SetBackdropColor(unpack(bg))
    frame:SetBackdropBorderColor(unpack(edge))
end

local function newText(parent, size, color)
    local text = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetFont(STANDARD_TEXT_FONT, size, "")
    text:SetTextColor(unpack(color))
    text:SetJustifyH("LEFT")
    text:SetWordWrap(true)
    return text
end

-- Radio button drawn from the standard radio texture: normal, checked, highlight.
local function setRadio(radio, checked, enabled)
    radio.checked = checked
    radio.icon:SetTexCoord(checked and 0.25 or 0, checked and 0.5 or 0.25, 0, 1)
    radio.icon:SetDesaturated(not enabled)
    radio:SetAlpha(enabled and 1 or 0.35)
    radio:SetEnabled(enabled)
end

local function itemLabel(itemID)
    return FC:ItemName(itemID) or ("Item #" .. itemID .. " (loading)")
end

local function itemCount(itemID)
    local count = C_Item and C_Item.GetItemCount and C_Item.GetItemCount(itemID)
    if not count and GetItemCount then count = GetItemCount(itemID) end
    return count or 0
end

-- Pools: text lines and location rows are reused between recipes.
local function takeText(size, color)
    popup.textIndex = popup.textIndex + 1
    local text = popup.texts[popup.textIndex]
    if not text then
        text = newText(popup.content, size, color)
        popup.texts[popup.textIndex] = text
    end
    text:SetFont(STANDARD_TEXT_FONT, size, "")
    text:SetTextColor(unpack(color))
    text:ClearAllPoints()
    text:SetWidth(WIDTH - 52)
    text:Show()
    return text
end

local function takeLocationRow()
    popup.rowIndex = popup.rowIndex + 1
    local row = popup.locationRows[popup.rowIndex]
    if not row then
        row = CreateFrame("Frame", nil, popup.content)
        row:SetWidth(WIDTH - 44)
        row.radio = CreateFrame("Button", nil, row)
        row.radio:SetSize(16, 16)
        row.radio:SetPoint("TOPLEFT", 0, -1)
        row.radio.icon = row.radio:CreateTexture(nil, "ARTWORK")
        row.radio.icon:SetAllPoints()
        row.radio.icon:SetTexture("Interface\\Buttons\\UI-RadioButton")
        local highlight = row.radio:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetTexture("Interface\\Buttons\\UI-RadioButton")
        highlight:SetTexCoord(0.5, 0.75, 0, 1)
        highlight:SetBlendMode("ADD")
        row.title = newText(row, 11, C.text)
        row.title:SetPoint("TOPLEFT", row.radio, "TOPRIGHT", 6, 0)
        row.title:SetWidth(WIDTH - 72)
        row.where = newText(row, 10, C.muted)
        row.where:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -2)
        row.where:SetWidth(WIDTH - 72)
        row.radio:SetScript("OnClick", function(self)
            local location = self:GetParent().location
            if self.checked then
                FC:ClearWaypoint(popup.recipeID)   -- clicking the selected one turns it off
                FC:ShowToast("Waypoint removed.")
            elseif FC:SetWaypoint(location, location.who, popup.recipeID) then
                FC:RefreshRecipeDetail()
            end
        end)
        popup.locationRows[popup.rowIndex] = row
    end
    row:ClearAllPoints()
    row:Show()
    return row
end

local function placeText(text, y, indent)
    text:SetPoint("TOPLEFT", popup.content, "TOPLEFT", indent or 0, -y)
    return y + text:GetStringHeight() + ROW_GAP
end

local function heading(text, y)
    local line = takeText(10, C.accent)
    line:SetText(text)
    return placeText(line, y + 8)
end

local function render(detail)
    popup.textIndex, popup.rowIndex = 0, 0
    popup.title:SetText(detail.name)
    local status = detail.known and "|cff40d15cKnown|r" or "|cffed4540Not known|r"
    if detail.skill then status = status .. "   |cff8a99adRequires Cooking " .. detail.skill .. "|r" end
    popup.status:SetText(status)

    local y = 0
    y = heading("INGREDIENTS", y)
    for _, reagent in ipairs(detail.reagents) do
        local have = itemCount(reagent.itemID)
        local line = takeText(11, C.text)
        local color = have >= reagent.count and "|cff40d15c" or "|cff8a99ad"
        line:SetText(string.format("%d x %s   %s(you have %d)|r", reagent.count, itemLabel(reagent.itemID), color, have))
        y = placeText(line, y, 4)
    end

    y = heading("WHERE TO LEARN", y)
    for i, location in ipairs(detail.locations) do
        local row = takeLocationRow()
        row.location = location
        row.key = detail.id .. ":" .. i .. ":" .. location.who
        local label = location.suggested and ("|cffe0b040Suggested|r  " .. location.label) or location.label
        row.title:SetText(label .. "  -  " .. (location.quest or location.who))
        local hasPosition = not location.noWaypoint and location.x
            and (location.map or FC:MapIDForZone(location.zone))
        local where
        if location.suggested then
            where = location.zone or ""
            if location.x then
                where = string.format("%s  (%.1f, %.1f)%s", where, location.x, location.y,
                    location.recorded and "  - recorded in game" or "")
            end
            if location.note and location.note ~= "" then where = where .. (where ~= "" and "\n" or "") .. location.note end
        elseif location.note then
            where = location.note
        elseif location.noWaypoint then
            where = ""
        elseif hasPosition then
            local quality = (location.recorded and "  - recorded in game")
                or (location.unconfirmed and "  - |cffe0b0401 source, unconfirmed|r") or ""
            where = string.format("%s  (%.1f, %.1f)%s", location.zone or "", location.x, location.y, quality)
        else
            where = (location.zone and location.zone ~= "" and (location.zone .. "  -  ") or "")
                .. "no map position yet; talk to them once to save it"
        end
        if location.quest then where = "from " .. location.who .. (where ~= "" and (", " .. where) or "") end
        if location.cost and location.cost ~= "" then where = where .. "\n" .. location.cost end
        row.where:SetText(where)
        local waypoint = FC:WaypointFor(detail.id)
        local selected = hasPosition and waypoint and waypoint.who == location.who
        setRadio(row.radio, selected and true or false, hasPosition and true or false)
        row:SetHeight(row.title:GetStringHeight() + row.where:GetStringHeight() + 4)
        row:SetPoint("TOPLEFT", popup.content, "TOPLEFT", 4, -y)
        y = y + row:GetHeight() + ROW_GAP + 2
    end
    if detail.locations[1] and detail.locations[1].suggested then
        local line = takeText(10, C.muted)
        line:SetText("Suggested by one source only; confirmed once found in game.")
        y = placeText(line, y + 2, 4)
    end
    local hidden = {}
    for faction in pairs(detail.hidden) do table.insert(hidden, faction) end
    if #hidden > 0 then
        table.sort(hidden)
        local line = takeText(10, C.muted)
        line:SetText("Also available to " .. table.concat(hidden, " and ") .. " (hidden for your faction).")
        y = placeText(line, y + 2, 4)
    end
    if detail.effect and detail.effect ~= "" then
        y = heading("EFFECT", y)
        local line = takeText(11, C.text)
        line:SetText(detail.effect)
        y = placeText(line, y, 4)
    end
    if detail.gameText and detail.gameText ~= "" then
        y = heading("IN-GAME SOURCE TEXT", y)
        local line = takeText(10, C.text)
        line:SetText(detail.gameText)
        y = placeText(line, y, 4)
    end

    for i = popup.textIndex + 1, #popup.texts do popup.texts[i]:Hide() end
    for i = popup.rowIndex + 1, #popup.locationRows do popup.locationRows[i]:Hide() end
    popup.content:SetHeight(math.max(1, y))
end

local function create()
    popup = CreateFrame("Frame", "ForeverChefRecipeDetail", UIParent, "BackdropTemplate")
    popup:SetSize(WIDTH, HEIGHT)
    popup:SetFrameStrata("HIGH")
    popup:SetToplevel(true)
    popup:SetClampedToScreen(true)
    popup:SetMovable(true)
    popup:EnableMouse(true)
    popup:RegisterForDrag("LeftButton")
    popup:SetScript("OnDragStart", popup.StartMoving)
    popup:SetScript("OnDragStop", popup.StopMovingOrSizing)
    backdrop(popup, C.background, C.border)
    popup.texts, popup.locationRows = {}, {}

    local icon = FC:CreateBrandIcon(popup, 26)
    icon:SetPoint("TOPLEFT", 14, -14)
    popup.title = newText(popup, 15, C.text)
    popup.title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, 1)
    popup.title:SetWidth(WIDTH - 110)
    popup.status = newText(popup, 11, C.text)
    popup.status:SetPoint("TOPLEFT", popup.title, "BOTTOMLEFT", 0, -3)

    local close = CreateFrame("Button", nil, popup, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)

    local scroll = CreateFrame("ScrollFrame", "ForeverChefRecipeDetailScroll", popup, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 16, -60)
    scroll:SetPoint("BOTTOMRIGHT", -32, 50)
    popup.content = CreateFrame("Frame", nil, scroll)
    popup.content:SetSize(WIDTH - 48, 1)
    scroll:SetScrollChild(popup.content)

    local clear = CreateFrame("Button", nil, popup, "BackdropTemplate")
    clear:SetSize(130, 26)
    clear:SetPoint("BOTTOMLEFT", 16, 14)
    backdrop(clear, C.raised, C.border)
    clear.label = newText(clear, 10, C.text)
    clear.label:SetPoint("CENTER")
    clear.label:SetText("Clear this waypoint")
    clear:SetScript("OnClick", function()
        if not FC:WaypointFor(popup.recipeID) then
            FC:ShowToast("This recipe has no waypoint.")
            return
        end
        FC:ClearWaypoint(popup.recipeID)
        FC:ShowToast("Waypoint cleared.")
    end)
    clear:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(unpack(C.accent)) end)
    clear:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(unpack(C.border)) end)

    tinsert(UISpecialFrames, "ForeverChefRecipeDetail")
    popup:Hide()
end

function FC:ShowRecipeDetail(recipeID)
    if not popup then create() end
    if FC.HideRanks then FC:HideRanks() end   -- they share a spot
    local detail = self:RecipeDetail(recipeID)
    if not detail then return end
    popup.recipeID = recipeID
    popup:ClearAllPoints()
    local main = _G.ForeverChefFrame
    if main and main:IsShown() then
        popup:SetPoint("TOPLEFT", main, "TOPRIGHT", 8, 0)
    else
        popup:SetPoint("CENTER")
    end
    render(detail)
    popup:Show()
end

function FC:RefreshRecipeDetail()
    if popup and popup:IsShown() and popup.recipeID then
        local detail = self:RecipeDetail(popup.recipeID)
        if detail then render(detail) end
    end
end
