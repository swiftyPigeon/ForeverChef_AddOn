local ADDON_NAME, FC = ...

-- "Cooking ranks" window: how to reach each rank (Apprentice -> Artisan), who
-- teaches it and where, with waypoint radios. Facts come from CookingRanks
-- (two or more sites agree) plus what trainer windows showed in game.
local C = FC.COLORS
local WIDTH, HEIGHT = 400, 480
local GAP = 4
local RANK_ORDER = { "Apprentice", "Journeyman", "Expert", "Artisan" }

local panel

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

local function parseXY(text)
    local x, y, mark = (text or ""):match("^%s*([%d%.]+)%s*,%s*([%d%.]+)%s*(%??)")
    return tonumber(x), tonumber(y), mark == "?"
end

-- The player's Cooking skill and cap, or nil when the client does not say.
function FC:PlayerCookingSkill()
    if GetProfessions and GetProfessionInfo then
        -- GetProfessions returns nil for empty slots (e.g. no second profession),
        -- so walk every slot instead of stopping at the first gap.
        local slots = { GetProfessions() }
        for slot = 1, 10 do
            local index = slots[slot]
            if index then
                local _, _, skill, max, _, _, skillLine = GetProfessionInfo(index)
                if skillLine == 185 then return skill, max end
            end
        end
    end
    if GetNumSkillLines and GetSkillLineInfo then
        local cooking = (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(2550)) or "Cooking"
        for i = 1, GetNumSkillLines() do
            local name, isHeader, _, rank, _, _, max = GetSkillLineInfo(i)
            if not isHeader and name == cooking then return rank, max end
        end
    end
end

local function currentRank(max)
    for _, rank in ipairs(FC.CookingRanks or {}) do
        if rank.max == max then return rank.rank end
    end
end

-- Pools of text lines and location rows, reused between refreshes.
local function takeText(size, color)
    panel.textIndex = panel.textIndex + 1
    local text = panel.texts[panel.textIndex]
    if not text then
        text = newText(panel.content, size, color)
        panel.texts[panel.textIndex] = text
    end
    text:SetFont(STANDARD_TEXT_FONT, size, "")
    text:SetTextColor(unpack(color))
    text:ClearAllPoints()
    text:SetWidth(WIDTH - 52)
    text:Show()
    return text
end

local function setRadio(radio, checked, enabled)
    radio.checked = checked
    radio.icon:SetTexCoord(checked and 0.25 or 0, checked and 0.5 or 0.25, 0, 1)
    radio:SetAlpha(enabled and 1 or 0.35)
    radio:SetEnabled(enabled)
end

local function takeRow()
    panel.rowIndex = panel.rowIndex + 1
    local row = panel.rows[panel.rowIndex]
    if not row then
        row = CreateFrame("Frame", nil, panel.content)
        row:SetWidth(WIDTH - 44)
        row.radio = CreateFrame("Button", nil, row)
        row.radio:SetSize(16, 16)
        row.radio:SetPoint("TOPLEFT", 0, -1)
        row.radio.icon = row.radio:CreateTexture(nil, "ARTWORK")
        row.radio.icon:SetAllPoints()
        row.radio.icon:SetTexture("Interface\\Buttons\\UI-RadioButton")
        row.title = newText(row, 11, C.text)
        row.title:SetPoint("TOPLEFT", row.radio, "TOPRIGHT", 6, 0)
        row.title:SetWidth(WIDTH - 72)
        row.where = newText(row, 10, C.muted)
        row.where:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -2)
        row.where:SetWidth(WIDTH - 72)
        row.radio:SetScript("OnClick", function(self)
            local r = self:GetParent()
            if self.checked then
                FC:ClearWaypoint(r.key)
            else
                FC:SetWaypoint(r.location, r.location.who, r.key, r.label)
            end
            FC:RefreshRanks()
        end)
        panel.rows[panel.rowIndex] = row
    end
    row:ClearAllPoints()
    row:Show()
    return row
end

local function place(region, y, indent)
    region:SetPoint("TOPLEFT", panel.content, "TOPLEFT", indent or 0, -y)
    local height = region.GetStringHeight and region:GetStringHeight() or region:GetHeight()
    return y + height + GAP
end

local function line(y, text, size, color, indent)
    local t = takeText(size or 11, color or C.text)
    t:SetText(text)
    return place(t, y, indent or 4)
end

-- A location row with a waypoint radio. Recorded positions beat researched ones.
local function locationRow(y, key, label, title, location)
    local recorded = FC:NPCLocation(location.who)
    if recorded then
        location.zone, location.map, location.x, location.y, location.recorded, location.unconfirmed =
            recorded.zone, recorded.map, recorded.x, recorded.y, true, nil
    end
    local row = takeRow()
    row.key, row.label, row.location = key, label, location
    row.title:SetText(title)
    local hasPosition = location.x and (location.map or FC:MapIDForZone(location.zone))
    local where
    if hasPosition then
        local quality = (location.recorded and "  - recorded in game")
            or (location.unconfirmed and "  - |cffe0b0401 source, unconfirmed|r") or ""
        where = string.format("%s  (%.1f, %.1f)%s", location.zone or "", location.x, location.y, quality)
    else
        where = (location.zone or "") .. "  -  no map position yet; talk to them once to save it"
    end
    if location.note and location.note ~= "" then where = location.note .. "\n" .. where end
    row.where:SetText(where)
    local waypoint = FC:WaypointFor(key)
    setRadio(row.radio, hasPosition and waypoint and waypoint.who == location.who and true or false, hasPosition and true or false)
    row:SetHeight(row.title:GetStringHeight() + row.where:GetStringHeight() + 4)
    row:SetPoint("TOPLEFT", panel.content, "TOPLEFT", 4, -y)
    return y + row:GetHeight() + GAP + 2
end

-- Cooking trainers of the player's faction with a known position, by zone then name
-- (a fixed order, so the list does not jump around as you travel).
local function factionTrainers(faction)
    local list = {}
    for _, trainer in ipairs(FC.CookingTrainers or {}) do
        if trainer.faction == faction then table.insert(list, trainer) end
    end
    table.sort(list, function(a, b)
        if a.zone ~= b.zone then return a.zone < b.zone end
        return a.name < b.name
    end)
    return list
end

-- One waypoint for "a Cooking trainer", whichever the player picked; it stays until
-- they talk to that trainer (or reach a rank no trainer teaches).
local TRAINER_KEY = "rank:trainer"

local function render()
    panel.textIndex, panel.rowIndex = 0, 0
    local faction = UnitFactionGroup and UnitFactionGroup("player")
    local skill, max = FC:PlayerCookingSkill()
    local mine = max and currentRank(max)
    panel.status:SetText(skill and string.format("Your Cooking: %d / %d%s", skill, max, mine and ("  (" .. mine .. ")") or "")
        or "You have not learned Cooking yet")

    local y = 0
    local nextFound = false
    -- every trainer teaches every trainer rank: list them once, under the last one
    local lastTrainerRank
    for _, rank in ipairs(FC.CookingRanks or {}) do
        if rank.trainer then lastTrainerRank = rank.rank end
    end
    for _, rank in ipairs(FC.CookingRanks or {}) do
        local tag = ""
        if mine == rank.rank then
            tag = "  |cff40d15c(your rank)|r"
        elseif not nextFound and (not max or rank.max > max) then
            tag, nextFound = "  |cffffd133(next)|r", true
        end
        local heading = takeText(11, C.accent)
        heading:SetText(string.format("%s  -  skill up to %d%s", rank.rank:upper(), rank.max, tag))
        y = place(heading, y + 8)

        y = line(y, rank.how)
        local needs = {}
        if rank.skill then table.insert(needs, "Cooking " .. rank.skill) end
        if rank.level then table.insert(needs, "level " .. rank.level) end
        if #needs > 0 then y = line(y, "Requires " .. table.concat(needs, ", "), 10, C.muted) end
        if rank.cost then y = line(y, "Cost: " .. rank.cost, 10, C.muted) end
        if rank.items then y = line(y, "Bring: " .. rank.items, 10, C.muted) end
        if rank.note then y = line(y, rank.note, 10, C.muted) end

        if rank.trainer then
            if rank.rank ~= lastTrainerRank then
                y = line(y, "Trainers are listed under " .. lastTrainerRank .. " below.", 10, C.muted)
            else
                for _, trainer in ipairs(factionTrainers(faction)) do
                    y = locationRow(y, TRAINER_KEY, "Cooking trainer", "Trainer  -  " .. trainer.name,
                        { who = trainer.name, zone = trainer.zone, x = trainer.x, y = trainer.y,
                            unconfirmed = trainer.unconfirmed })
                end
            end
            -- trainers seen in game listing this rank
            local seen = {}
            for name, info in pairs(FC.db.trainerRanks or {}) do
                if info.ranks[rank.rank] and (info.faction == faction or info.faction == "Neutral") then
                    table.insert(seen, name .. " (" .. (info.zone or "") .. ")")
                end
            end
            table.sort(seen)
            if #seen > 0 then y = line(y, "Seen in game teaching it: " .. table.concat(seen, ", "), 10, C.good) end
        end
        for _, step in ipairs(rank.steps or {}) do
            if step.faction == faction or step.faction == "Neutral" or step.faction == "Both" then
                local x, yy, unconfirmed = parseXY(step.coords)
                y = locationRow(y, "rank:" .. rank.rank .. ":" .. step.who, rank.rank .. " Cooking",
                    step.type .. "  -  " .. step.who,
                    { who = step.who, zone = step.zone, x = x, y = yy, unconfirmed = unconfirmed, note = step.note })
            end
        end
    end
    y = line(y + 8, "Only facts two or more guides agree on are shown, plus what trainers showed you in game.", 9, C.muted)

    for i = panel.textIndex + 1, #panel.texts do panel.texts[i]:Hide() end
    for i = panel.rowIndex + 1, #panel.rows do panel.rows[i]:Hide() end
    panel.content:SetHeight(math.max(1, y))
end

local function create()
    panel = CreateFrame("Frame", "ForeverChefRanks", UIParent, "BackdropTemplate")
    panel:SetSize(WIDTH, HEIGHT)
    panel:SetFrameStrata("HIGH")
    panel:SetToplevel(true)
    panel:SetClampedToScreen(true)
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    backdrop(panel, C.background, C.border)
    panel.texts, panel.rows = {}, {}

    local icon = FC:CreateBrandIcon(panel, 30)
    icon:SetPoint("TOPLEFT", 12, -12)
    local title = newText(panel, 15, C.text)
    title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, 1)
    title:SetText("Cooking ranks")
    panel.status = newText(panel, 11, C.muted)
    panel.status:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)

    local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)

    local scroll = CreateFrame("ScrollFrame", "ForeverChefRanksScroll", panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 16, -60)
    scroll:SetPoint("BOTTOMRIGHT", -32, 14)
    panel.content = CreateFrame("Frame", nil, scroll)
    panel.content:SetSize(WIDTH - 48, 1)
    scroll:SetScrollChild(panel.content)

    tinsert(UISpecialFrames, "ForeverChefRanks")
    panel:Hide()
end

function FC:ToggleRanks()
    if not panel then create() end
    if panel:IsShown() then
        panel:Hide()
        return
    end
    local detail = _G.ForeverChefRecipeDetail
    if detail and detail:IsShown() then detail:Hide() end   -- they share a spot
    panel:ClearAllPoints()
    local main = _G.ForeverChefFrame
    if main and main:IsShown() then
        panel:SetPoint("TOPLEFT", main, "TOPRIGHT", 8, 0)
    else
        panel:SetPoint("CENTER")
    end
    render()
    panel:Show()
end

function FC:RefreshRanks()
    if panel and panel:IsShown() then render() end
end

-- A rank waypoint ("rank:<Rank>" or "rank:<Rank>:<who>") is no longer needed once
-- the player's Cooking cap reaches that rank.
function FC:ClearReachedRankWaypoints()
    local _, max = self:PlayerCookingSkill()
    if not max then return end
    local reached = {}
    for _, rank in ipairs(self.CookingRanks or {}) do
        if rank.max <= max then reached[rank.rank] = true end
    end
    local done = {}
    local trainerRanksLeft = false
    for _, rank in ipairs(self.CookingRanks or {}) do
        if rank.trainer and not reached[rank.rank] then trainerRanksLeft = true end
    end
    for _, entry in ipairs(self:Waypoints()) do
        local rank = type(entry.recipeID) == "string" and entry.recipeID:match("^rank:([^:]+)")
        if rank == "trainer" then
            if not trainerRanksLeft then table.insert(done, entry.recipeID) end
        elseif rank and reached[rank] then
            table.insert(done, entry.recipeID)
        end
    end
    for _, key in ipairs(done) do self:ClearWaypoint(key) end
    if #done > 0 then self:Notify("Cooking rank reached - its waypoint removed.") end
end
FC:On("SKILL_LINES_CHANGED", function() C_Timer.After(0.5, function() FC:ClearReachedRankWaypoints() end) end)

-- Talking to the NPC a rank waypoint points at means you got there: clear it.
local function arrivedAtNPC()
    local who = UnitName and UnitName("npc")
    if not who or (issecretvalue and issecretvalue(who)) then return end
    local done = {}
    for _, entry in ipairs(FC:Waypoints()) do
        if type(entry.recipeID) == "string" and entry.recipeID:match("^rank:") and entry.who == who then
            table.insert(done, entry.recipeID)
        end
    end
    for _, key in ipairs(done) do FC:ClearWaypoint(key) end
    if #done > 0 then FC:Notify("Reached " .. who .. " - waypoint removed.") end
end
for _, event in ipairs({ "TRAINER_SHOW", "MERCHANT_SHOW", "GOSSIP_SHOW", "QUEST_DETAIL", "QUEST_GREETING" }) do
    FC:On(event, arrivedAtNPC)
end

function FC:HideRanks()
    if panel then panel:Hide() end
end
