local ADDON_NAME, FC = ...

-- /fchef export: a plain-text block of what was found in game that the built-in
-- data does not already confirm, for players to paste into a GitHub issue or
-- Discord. ForeverChef-tools/build_sources_csv.py --observed reads it back.
-- Everything comes from the log SourceRecorder.lua keeps while you play; only
-- these are written (no character names):
--   Recipe | recipeID | name | type | faction | who | npc <id> | zone | map <id> | x, y | cost | seen <n>
--     a place a recipe was found that no two sources confirm yet
--   NPC | name | faction | npc <id> | zone | map <id> | x, y
--     a position recorded in game for an NPC in those finds, or one the built-in
--     data has no confirmed position for
local EXPORT_FORMAT = 3

local function sortedKeys(t)
    local keys = {}
    for k in pairs(t) do table.insert(keys, k) end
    table.sort(keys)
    return keys
end

-- " | " separates fields, so "|" must not appear inside one.
local function clean(text)
    return (tostring(text or ""):gsub("[|\n]", "/"))
end

local function coords(x, y)
    if not x or not y then return "" end
    return string.format("%.1f, %.1f", x, y)
end

-- Names the built-in data already confirms for a recipe ("*trainer" when any
-- Cooking trainer teaches it).
local function confirmedNames(recipeID)
    local names = {}
    for _, source in ipairs(FC.CookingSources and FC.CookingSources[recipeID] or {}) do
        if source.type == "Trainer" and source.faction == "Both" then names["*trainer"] = true end
        for name in ((source.who or "") .. ";"):gmatch("%s*([^;]-)%s*;") do names[name] = true end
        if source.giver then names[source.giver] = true end
    end
    return names
end

local function isNewFind(recipeID, entry)
    local names = confirmedNames(recipeID)
    if entry.type == "Trainer" and names["*trainer"] then return false end
    return not names[entry.who or ""] and not names[entry.quest or ""] and not names[entry.giver or ""]
end

-- NPCs the built-in data has no confirmed position for ("x,y?" or none).
local function unconfirmedNPCs()
    local names = {}
    local function check(who, coordList)
        local list = {}
        for c in ((coordList or "") .. ";"):gmatch("%s*([^;]-)%s*;") do table.insert(list, c) end
        local i = 0
        for name in ((who or "") .. ";"):gmatch("%s*([^;]-)%s*;") do
            i = i + 1
            local c = list[i] or ""
            if name ~= "" and (c == "" or c:find("?", 1, true)) then names[name] = true end
        end
    end
    for _, group in ipairs({ FC.CookingSources or {}, FC.SuggestedSources or {} }) do
        for _, sources in pairs(group) do
            for _, source in ipairs(sources) do check(source.giver or source.who, source.coords) end
        end
    end
    for _, rank in ipairs(FC.CookingRanks or {}) do
        for _, step in ipairs(rank.steps or {}) do check(step.who, step.coords) end
    end
    for _, trainer in ipairs(FC.CookingTrainers or {}) do
        if trainer.unconfirmed then names[trainer.name] = true end
    end
    return names
end

function FC:BuildExport()
    local db = self.db
    local metadata = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
    local version = metadata and metadata(ADDON_NAME, "Version") or "?"
    local finds, npcs, wanted = {}, {}, unconfirmedNPCs()
    for _, recipeID in ipairs(sortedKeys(db.observed or {})) do
        local name = self.CookingData[recipeID] and self.CookingData[recipeID].name or ""
        for _, key in ipairs(sortedKeys(db.observed[recipeID])) do
            local o = db.observed[recipeID][key]
            if isNewFind(recipeID, o) then
                if o.who then wanted[o.who] = true end
                table.insert(finds, string.format("Recipe | %d | %s | %s | %s | %s | npc %s | %s | map %s | %s | %s | seen %d",
                    recipeID, clean(name), clean(o.type), clean(o.faction), clean(o.who), tostring(o.npcID or ""),
                    clean(o.zone), tostring(o.map or ""), coords(o.x, o.y), clean(o.cost), o.seen or 1))
            end
        end
    end
    for _, name in ipairs(sortedKeys(db.npcLocations or {})) do
        local l = db.npcLocations[name]
        if wanted[name] then
            table.insert(npcs, string.format("NPC | %s | %s | npc %s | %s | map %s | %s", clean(name), clean(l.faction),
                tostring(l.npcID or ""), clean(l.zone), tostring(l.map or ""), coords(l.x, l.y)))
        end
    end
    if #finds + #npcs == 0 then return nil, 0, 0 end
    local lines = { string.format("Forever Chef %s export | format %d | %s | interface %s", version, EXPORT_FORMAT,
        UnitFactionGroup("player") or "?", tostring(select(4, GetBuildInfo()))) }
    for _, line in ipairs(finds) do table.insert(lines, line) end
    for _, line in ipairs(npcs) do table.insert(lines, line) end
    return table.concat(lines, "\n"), #finds, #npcs
end

local function createWindow()
    local C = FC.COLORS   -- defined in UI.lua, which loads after this file
    local frame = CreateFrame("Frame", "ForeverChefExportFrame", UIParent, "BackdropTemplate")
    frame:SetSize(560, 420)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    frame:SetBackdropColor(C.background[1], C.background[2], C.background[3], 1)
    frame:SetBackdropBorderColor(unpack(C.border))

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -14)
    title:SetText("Forever Chef Export")
    frame.hint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    frame.hint:SetPoint("RIGHT", -40, 0)
    frame.hint:SetJustifyH("LEFT")

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)

    local box = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    box:SetPoint("TOPLEFT", 12, -64)
    box:SetPoint("BOTTOMRIGHT", -12, 12)
    box:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    box:SetBackdropColor(unpack(C.panel))
    box:SetBackdropBorderColor(unpack(C.border))

    local scroll = CreateFrame("ScrollFrame", "ForeverChefExportScroll", box, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 8, -8)
    scroll:SetPoint("BOTTOMRIGHT", -28, 8)

    -- A multi-line EditBox needs a real size to draw its text inside a scroll frame.
    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject(ChatFontNormal)
    edit:SetTextColor(unpack(C.text))
    edit:SetSize(490, 300)
    edit:SetScript("OnEscapePressed", function() frame:Hide() end)
    -- Read-only: any typing puts the export text back, selected for copying.
    edit:SetScript("OnTextChanged", function(self, userInput)
        if userInput then
            self:SetText(frame.text or "")
            self:HighlightText()
        end
    end)
    edit:SetScript("OnCursorChanged", function(self, _, y, _, height)
        if ScrollingEdit_OnCursorChanged then ScrollingEdit_OnCursorChanged(self, 0, y, 0, height) end
    end)
    edit:SetScript("OnUpdate", function(self, elapsed)
        if ScrollingEdit_OnUpdate then ScrollingEdit_OnUpdate(self, elapsed, scroll) end
    end)
    scroll:SetScrollChild(edit)
    scroll:EnableMouse(true)
    scroll:SetScript("OnMouseDown", function() edit:SetFocus() end)
    frame.edit = edit

    tinsert(UISpecialFrames, "ForeverChefExportFrame")
    return frame
end

function FC:ShowExport()
    local text, finds, npcs = self:BuildExport()
    if not text then
        self:Print("Nothing new to export yet. Open recipe vendors and Cooking trainers, loot recipes, and talk to the "
            .. "NPCs from Suggested and Unknown recipes; what the addon does not already confirm is collected here.")
        return
    end
    self.exportFrame = self.exportFrame or createWindow()
    local frame = self.exportFrame
    frame.text = text
    frame.hint:SetText(string.format("%d recipe finds and %d NPC positions not yet confirmed. Ctrl+C copies the "
        .. "selected text; paste it into a GitHub issue for the addon.", finds, npcs))
    frame:Show()
    frame.edit:SetText(text)
    frame.edit:HighlightText()
    frame.edit:SetFocus()
end
