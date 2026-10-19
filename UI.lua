local ADDON_NAME, FC = ...

-- Same dark palette as Forever Profession Master, with a fire accent.
FC.COLORS = {
    background = { 0.035, 0.043, 0.055, 0.98 },
    panel      = { 0.060, 0.071, 0.090, 0.98 },
    raised     = { 0.088, 0.102, 0.128, 1.00 },
    hover      = { 0.115, 0.132, 0.160, 1.00 },
    border     = { 0.145, 0.170, 0.205, 1.00 },
    accent     = { 1.00, 0.55, 0.15, 1.00 },
    text       = { 0.91, 0.94, 0.97, 1.00 },
    muted      = { 0.54, 0.60, 0.68, 1.00 },
    good       = { 0.23, 0.84, 0.48, 1.00 },
    warning    = { 0.96, 0.72, 0.20, 1.00 },
    waypoint   = { 1.00, 0.82, 0.20, 1.00 },   -- recipe whose waypoint is on the map
}
local C = FC.COLORS

local WIDTH, HEIGHT = 620, 480
local ROW_HEIGHT = 22

local function backdrop(frame, bg, edge)
    if not frame.SetBackdrop then return end
    frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    frame:SetBackdropColor(unpack(bg or C.panel))
    frame:SetBackdropBorderColor(unpack(edge or C.border))
end

local function label(parent, size, color, justify)
    local text = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetFont(STANDARD_TEXT_FONT, size or 11, "")
    text:SetTextColor(unpack(color or C.text))
    text:SetJustifyH(justify or "LEFT")
    text:SetWordWrap(false)
    return text
end

local function button(parent, text, width, onClick)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(width, 26)
    backdrop(b, C.raised, C.border)
    b.label = label(b, 10, C.text, "CENTER")
    b.label:SetPoint("CENTER")
    b.label:SetText(text)
    b:SetScript("OnEnter", function(self)
        self:SetBackdropColor(unpack(C.hover))
        self:SetBackdropBorderColor(unpack(C.accent))
    end)
    b:SetScript("OnLeave", function(self)
        self:SetBackdropColor(unpack(self.active and { C.accent[1] * 0.28, C.accent[2] * 0.28, C.accent[3] * 0.28, 1 } or C.raised))
        self:SetBackdropBorderColor(unpack(self.active and C.accent or C.border))
    end)
    b:SetScript("OnClick", onClick)
    return b
end

-- The recipe table: column layout, row builder, and what to say when it is empty.
-- (Kept as a list of tables so more views can be added later.)
-- Columns are { title, width, justify, group = true }; clicking a header sorts by
-- it, and a `group` column also gathers rows under collapsible headings.
-- Rows hold display text in [1..n], raw sort values in `sort`, group keys in `group`.
local TABS = {
    {
        id = "RECIPES", title = "Recipes",
        columns = { { "Cooking recipe", 215 }, { "Status", 90, nil, group = true }, { "Learn from", 105, nil, group = true },
            { "Zone", 150, nil, group = true } },
        empty = "No Cooking recipes found.",
        rows = function()
            local rows = {}
            for _, r in ipairs(FC:RecipeRows()) do
                local status = r.known and "Known" or "Not known"
                table.insert(rows, {
                    r.name, r.known and "|cff40d15cKnown|r" or "|cffed4540Not known|r", r.learnFrom, r.zone,
                    sort = { r.name, status, r.learnFrom, r.zone },
                    group = { nil, status, r.category, r.zone },
                    known = r.known, recipeID = r.id,
                })
            end
            table.sort(rows, function(a, b)
                if a.known ~= b.known then return not a.known end
                return a[1] < b[1]
            end)
            return rows
        end,
    },
}

local ARROW_UP = " |TInterface\\Buttons\\Arrow-Up-Up:10:10:0:-3|t"
local ARROW_DOWN = " |TInterface\\Buttons\\Arrow-Down-Up:10:10:0:2|t"

local function plainText(value)
    return (tostring(value or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

local function sortValue(row, column)
    local value = row.sort and row.sort[column]
    if value == nil then value = plainText(row[column]) end
    return value
end

local function less(a, b)
    if type(a) == "number" and type(b) == "number" then return a < b end
    return tostring(a):lower() < tostring(b):lower()
end

local MAX_LEVELS = 3

-- Turns a tab's rows into what is drawn. `levels` is the stack of clicked
-- headers, outermost first: { { column, descending }, ... }. Rows are sorted by
-- every level in turn; each level whose column groups adds a heading row when
-- its value changes, nested under the outer ones (depth 1, 2, ...). Rows under
-- a folded heading are left out. Headings carry `path`, the keys from the
-- outermost level down, which is what folding remembers.
local function displayList(tab, rows, levels, collapsed)
    if not levels or #levels == 0 then return rows end
    local function key(row, level)
        local column = level.column
        if tab.columns[column].group then return (row.group and row.group[column]) or plainText(row[column]) end
        return sortValue(row, column)
    end
    table.sort(rows, function(a, b)
        for _, level in ipairs(levels) do
            local ka, kb = key(a, level), key(b, level)
            if ka ~= kb then
                if level.descending then return less(kb, ka) end
                return less(ka, kb)
            end
        end
        return less(sortValue(a, 1), sortValue(b, 1))
    end)

    local grouping = {}
    for _, level in ipairs(levels) do
        if tab.columns[level.column].group then table.insert(grouping, level) end
    end
    if #grouping == 0 then return rows end

    local function pathOf(row, depth)
        local keys = {}
        for d = 1, depth do keys[d] = tostring(key(row, grouping[d])) end
        return table.concat(keys, " > ")
    end
    local counts = {}
    for _, row in ipairs(rows) do
        for depth = 1, #grouping do
            local path = pathOf(row, depth)
            counts[path] = (counts[path] or 0) + 1
        end
    end
    local list, current = {}, {}
    for _, row in ipairs(rows) do
        local hidden = false
        for depth = 1, #grouping do
            local path = pathOf(row, depth)
            if path ~= current[depth] then
                current[depth] = path
                for deeper = depth + 1, #grouping do current[deeper] = nil end
                if not hidden then
                    table.insert(list, { heading = true, depth = depth, path = path,
                        key = key(row, grouping[depth]), count = counts[path] })
                end
            end
            if collapsed[path] then hidden = true end
        end
        if not hidden then table.insert(list, row) end
    end
    return list
end

local function levelIndex(levels, column)
    for i, level in ipairs(levels or {}) do
        if level.column == column then return i end
    end
end

local window

local function getRow(index)
    local rows = window.rows
    if rows[index] then return rows[index] end
    local row = CreateFrame("Frame", nil, window.list.content)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
    row:SetPoint("RIGHT", window.list.content, "RIGHT")
    row.stripe = row:CreateTexture(nil, "BACKGROUND")
    row.stripe:SetAllPoints()
    row.stripe:SetColorTexture(1, 1, 1, index % 2 == 0 and 0.025 or 0)
    row.cells = {}
    for i = 1, 4 do row.cells[i] = label(row, 11, i == 1 and C.text or C.muted) end
    row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
    row.highlight:SetAllPoints()
    row.highlight:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.12)
    -- Group headings fold or unfold their group; recipe rows open the detail pop-up.
    row:SetScript("OnMouseUp", function(self)
        if self.headingKey then
            local collapsed = window.collapsed[window.tab.id]
            collapsed[self.headingKey] = not collapsed[self.headingKey] or nil   -- headingKey is the heading's path
            FC:RefreshLists()
        elseif self.recipeID then
            FC:ShowRecipeDetail(self.recipeID)
        end
    end)
    rows[index] = row
    return row
end

local function layoutCells(cells, columns)
    local x = 8
    for i, cell in ipairs(cells) do
        local column = columns[i]
        cell:ClearAllPoints()
        if column then
            cell:SetPoint("LEFT", cell:GetParent(), "LEFT", x, 0)
            cell:SetWidth(column[2] - 12)
            cell:SetJustifyH(column[3] or "LEFT")
            x = x + column[2]
            cell:Show()
        else
            cell:Hide()
        end
    end
end

function FC:RefreshLists()
    if not window or not window:IsShown() then return end
    local total, known = self:RecipeStats()
    window.stats[1].value:SetText(total)
    window.stats[2].value:SetText(known)
    window.stats[3].value:SetText(total - known)
    window.stats[4].value:SetText(self:ObservedCount())

    local tab = window.tab
    local levels = window.sortState[tab.id]
    window.collapsed[tab.id] = window.collapsed[tab.id] or {}
    layoutCells(window.headerCells, tab.columns)
    for i, header in ipairs(window.headerButtons) do
        local column = tab.columns[i]
        if column then
            header:ClearAllPoints()
            header:SetPoint("LEFT", window.headerCells[i], "LEFT", -4, 0)
            header:SetSize(column[2] - 4, 22)
            header:Show()
            local index = levelIndex(levels, i)
            local marker = ""
            if index then
                -- The level number only matters once several headers are stacked.
                marker = (#levels > 1 and (" " .. index) or "") .. (levels[index].descending and ARROW_DOWN or ARROW_UP)
            end
            window.headerCells[i]:SetText(column[1]:upper() .. marker)
            window.headerCells[i]:SetTextColor(unpack(index and C.accent or C.muted))
        else
            header:Hide()
        end
    end

    local data = displayList(tab, tab.rows(), levels, window.collapsed[tab.id])
    for i, values in ipairs(data) do
        local row = getRow(i)
        layoutCells(row.cells, tab.columns)
        if values.heading then
            local folded = window.collapsed[tab.id][values.path]
            row.headingKey, row.recipeID = values.path, nil
            row:EnableMouse(true)
            local indent = string.rep("      ", values.depth - 1)
            row.cells[1]:SetText(string.format("%s%s %s  (%d)", indent, folded and "[+]" or "[-]",
                tostring(values.key ~= "" and values.key or "(none)"), values.count))
            row.cells[1]:SetWidth(WIDTH - 80)
            -- Outer groups in the accent colour, nested ones lighter.
            row.cells[1]:SetTextColor(unpack(values.depth == 1 and C.accent or C.text))
            for c = 2, #row.cells do row.cells[c]:Hide() end
            row.stripe:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], values.depth == 1 and 0.10 or 0.05)
        else
            row.headingKey, row.recipeID = nil, values.recipeID
            row:EnableMouse(values.recipeID ~= nil)
            local tracked = values.recipeID and FC:WaypointFor(values.recipeID)
            row.cells[1]:SetTextColor(unpack(tracked and C.waypoint or C.text))
            for c = 2, #row.cells do row.cells[c]:SetTextColor(unpack(tracked and C.waypoint or C.muted)) end
            for c = 1, #tab.columns do row.cells[c]:SetText(tostring(values[c] or "")) end
            row.stripe:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.025 or 0)
        end
        row:Show()
    end
    for i = #data + 1, #window.rows do window.rows[i]:Hide() end
    window.list.content:SetHeight(math.max(1, #data * ROW_HEIGHT))
    window.emptyText:SetText(tab.empty)
    if #data == 0 then window.emptyText:Show() else window.emptyText:Hide() end
    window.quietButton.label:SetText(self.char.quiet and "Pop-ups: Off" or "Pop-ups: On")
    window.clearWaypointsButton:SetAlpha(#self:Waypoints() > 0 and 1 or 0.45)
    self.listsDirty = nil
end

local function createWindow()
    local frame = CreateFrame("Frame", "ForeverChefFrame", UIParent, "BackdropTemplate")
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("HIGH")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    backdrop(frame, C.background, C.border)
    window = frame
    frame.rows = {}

    -- Header
    local header = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(52)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() frame:StartMoving() end)
    header:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)
    backdrop(header, C.panel, C.border)

    local icon = FC:CreateBrandIcon(header, 30)
    icon:SetPoint("LEFT", 12, 3)
    local title = label(header, 16, C.text)
    title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -2)
    title:SetText("FOREVER CHEF")
    local subtitle = label(header, 10, C.muted)
    subtitle:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 10, 2)
    subtitle:SetText("COOKING RECIPES AND WHERE TO LEARN THEM")
    local close = button(header, "×", 30, function() frame:Hide() end)
    close:SetPoint("RIGHT", -11, 0)
    close.label:SetFont(STANDARD_TEXT_FONT, 17, "")

    -- Counters
    frame.stats = {}
    local statNames = { "Cooking recipes", "Known", "Not known", "Found in game" }
    local statWidth = (WIDTH - 32 - 3 * 8) / 4
    for i, name in ipairs(statNames) do
        local tile = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        tile:SetSize(statWidth, 48)
        tile:SetPoint("TOPLEFT", 16 + (i - 1) * (statWidth + 8), -64)
        backdrop(tile, C.panel, C.border)
        tile.value = label(tile, 18, C.text)
        tile.value:SetPoint("TOPLEFT", 10, -7)
        local caption = label(tile, 9, C.muted)
        caption:SetPoint("BOTTOMLEFT", 10, 7)
        caption:SetText(name:upper())
        frame.stats[i] = tile
    end

    frame.tab = TABS[1]

    -- List
    local listBox = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    listBox:SetPoint("TOPLEFT", 16, -124)
    listBox:SetPoint("BOTTOMRIGHT", -16, 52)
    backdrop(listBox, C.panel, C.border)
    local headerRow = CreateFrame("Frame", nil, listBox)
    headerRow:SetPoint("TOPLEFT", 1, -1)
    headerRow:SetPoint("TOPRIGHT", -1, -1)
    headerRow:SetHeight(22)
    frame.headerCells = {}
    frame.headerButtons = {}
    frame.sortState, frame.collapsed = {}, {}
    for i = 1, 4 do
        frame.headerCells[i] = label(headerRow, 9, C.muted)
        -- Headers stack: a new column is added inside the current grouping;
        -- clicking an active one reverses it, a third click removes just that level.
        local header = CreateFrame("Button", nil, headerRow)
        header:SetScript("OnClick", function()
            local id = frame.tab.id
            frame.sortState[id] = frame.sortState[id] or {}
            local levels = frame.sortState[id]
            local index = levelIndex(levels, i)
            if not index then
                if #levels >= MAX_LEVELS then table.remove(levels, 1) end
                table.insert(levels, { column = i })
            elseif not levels[index].descending then
                levels[index].descending = true
            else
                table.remove(levels, index)
            end
            frame.collapsed[id] = {}
            FC:RefreshLists()
        end)
        header:SetScript("OnEnter", function(self)
            local column = frame.tab.columns[i]
            if not column then return end
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(column.group and "Click to group by " .. column[1] or "Click to sort by " .. column[1], 1, 1, 1)
            GameTooltip:AddLine("Adds to the current grouping. Click again to reverse,", 0.7, 0.7, 0.7)
            GameTooltip:AddLine("a third time to remove just this column.", 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end)
        header:SetScript("OnLeave", function() GameTooltip:Hide() end)
        frame.headerButtons[i] = header
    end

    local scroll = CreateFrame("ScrollFrame", "ForeverChefListScroll", listBox, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 1, -24)
    scroll:SetPoint("BOTTOMRIGHT", -24, 2)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(WIDTH - 32 - 26, 1)
    scroll:SetScrollChild(content)
    scroll.content = content
    frame.list = scroll

    frame.emptyText = label(listBox, 11, C.muted, "CENTER")
    frame.emptyText:SetPoint("CENTER", 0, -10)
    frame.emptyText:SetWidth(WIDTH - 100)
    frame.emptyText:SetWordWrap(true)

    -- Footer
    local export = button(frame, "Export data", 110, function() FC:ShowExport() end)
    export:SetPoint("BOTTOMLEFT", 16, 16)
    frame.quietButton = button(frame, "", 150, function()
        FC.char.quiet = not FC.char.quiet
        FC:RefreshLists()
    end)
    frame.quietButton:SetPoint("LEFT", export, "RIGHT", 8, 0)
    -- Clears the map pin and TomTom arrow Forever Chef set (dimmed when there is none).
    frame.clearWaypointsButton = button(frame, "Reset All Waypoints", 150, function()
        local count = #FC:Waypoints()
        if count == 0 then
            FC:ShowToast("There is no Forever Chef waypoint to clear.")
            return
        end
        FC:ClearWaypoint()
        FC:ShowToast(count == 1 and "Waypoint cleared." or string.format("%d waypoints cleared.", count))
    end)
    frame.clearWaypointsButton:SetPoint("LEFT", frame.quietButton, "RIGHT", 8, 0)
    -- Erasing learned data is /fchef reset only, so it cannot be clicked by accident.
    local hint = label(frame, 10, C.muted, "RIGHT")
    hint:SetPoint("BOTTOMRIGHT", -16, 23)
    hint:SetText("Click a recipe for details")

    -- Redraw at most once a second, and only when something changed.
    local elapsed = 0
    frame:SetScript("OnUpdate", function(_, delta)
        elapsed = elapsed + delta
        if elapsed < 1 then return end
        elapsed = 0
        if FC.listsDirty then FC:RefreshLists() end
    end)
    frame:SetScript("OnShow", function() FC:RefreshLists() end)

    tinsert(UISpecialFrames, "ForeverChefFrame")
    frame:Hide()
    return frame
end

function FC:ToggleWindow()
    window = window or createWindow()
    if window:IsShown() then window:Hide() else window:Show() end
end
