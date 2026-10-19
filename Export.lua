local ADDON_NAME, FC = ...

-- Plain-text export so players can paste what they recorded into a GitHub issue
-- or Discord; ForeverChef-tools/build_sources_csv.py --observed reads it back.
-- One record per line, no character names:
--   FCHEF|<format>|<interface>|<faction>
--   S|recipeID|type|faction|who|npcID|zone|mapID|x|y|cost|timesSeen   (Cooking recipe source seen in game)
--   L|name|faction|npcID|zone|mapID|x|y                               (vendor/trainer/quest giver position)
local EXPORT_FORMAT = 2

local function sortedKeys(t)
    local keys = {}
    for k in pairs(t) do table.insert(keys, k) end
    table.sort(keys)
    return keys
end

-- "|" separates fields, so it must not appear inside one.
local function clean(text)
    return (tostring(text or ""):gsub("[|\n]", "/"))
end

function FC:BuildExport()
    local db = self.db
    local lines = {}
    local interface = select(4, GetBuildInfo())
    table.insert(lines, string.format("FCHEF|%d|%s|%s", EXPORT_FORMAT, tostring(interface), UnitFactionGroup("player") or "?"))
    for _, recipeID in ipairs(sortedKeys(db.observed or {})) do
        for _, key in ipairs(sortedKeys(db.observed[recipeID])) do
            local o = db.observed[recipeID][key]
            table.insert(lines, string.format("S|%d|%s|%s|%s|%s|%s|%s|%s|%s|%s|%d", recipeID, clean(o.type), clean(o.faction),
                clean(o.who), tostring(o.npcID or ""), clean(o.zone), tostring(o.map or ""), tostring(o.x or ""),
                tostring(o.y or ""), clean(o.cost), o.seen or 1))
        end
    end
    for _, name in ipairs(sortedKeys(db.npcLocations or {})) do
        local l = db.npcLocations[name]
        table.insert(lines, string.format("L|%s|%s|%s|%s|%s|%s|%s", clean(name), clean(l.faction), tostring(l.npcID or ""),
            clean(l.zone), tostring(l.map or ""), tostring(l.x or ""), tostring(l.y or "")))
    end
    return table.concat(lines, "\n"), #lines
end

local function createWindow()
    local frame = CreateFrame("Frame", "ForeverChefExportFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    frame:SetSize(560, 420)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    if frame.SetBackdrop then
        frame:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        frame:SetBackdropColor(0.05, 0.05, 0.07, 0.95)
    end

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -14)
    title:SetText("Forever Chef Export")
    frame.hint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)

    local scroll = CreateFrame("ScrollFrame", "ForeverChefExportScroll", frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 16, -60)
    scroll:SetPoint("BOTTOMRIGHT", -34, 16)

    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject(ChatFontNormal)
    edit:SetWidth(500)
    edit:SetScript("OnEscapePressed", function() frame:Hide() end)
    -- Read-only: any typing restores the export text.
    edit:SetScript("OnTextChanged", function(self, userInput)
        if userInput then
            self:SetText(frame.text or "")
            self:HighlightText()
        end
    end)
    scroll:SetScrollChild(edit)
    frame.edit = edit

    tinsert(UISpecialFrames, "ForeverChefExportFrame")
    return frame
end

function FC:ShowExport()
    self.exportFrame = self.exportFrame or createWindow()
    local frame = self.exportFrame
    local text, count = self:BuildExport()
    frame.text = text
    frame.hint:SetText(string.format("%d records. Press Ctrl+C to copy, then paste it where the addon author asked.", count))
    frame:Show()
    frame.edit:SetText(text)
    frame.edit:HighlightText()
    frame.edit:SetFocus()
end
