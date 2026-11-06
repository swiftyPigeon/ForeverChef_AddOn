local ADDON_NAME, FC = ...

-- The "What's New" letter: a parchment note that opens once per account after an
-- update (a few seconds after logging in, never in combat), and again with
-- /fchef news or the header's What's new button. Update LETTER for each release;
-- release.py bump warns when its version does not match the new one.
-- The footnote (getting started, where to send data and report problems) stays the same.
local LETTER = {
    version = "0.8.0",
    greeting = "Dear Cook,",
    paragraphs = {
        "A few new things are in the pantry:",
        "|cff4e1804Your finds can help everyone.|r Forever Chef already notes the recipe vendors, trainers, "
            .. "drops and quest rewards you come across. Now |cff4e1804/fchef export|r shows a link to a short "
            .. "form: copy the link into your browser, paste the export text, and that's it.",
        "|cff4e1804Confirmed by two players.|r A find counts as confirmed once two different players have sent "
            .. "it in; until then it shows as Suggested. Your export carries a random code, never your "
            .. "character's name, so the addon can tell players apart.",
        "|cff4e1804The first export is in.|r The Undercity cooking trainer and recipe vendor now have "
            .. "confirmed map positions. Thank you to the first player who sent theirs!",
        "|cff4e1804Tooltips tell you what you can cook.|r On an ingredient's tooltip, |cff154a1agreen|r "
            .. "recipes are ones you know and have every ingredient for (bags or bank), |cff6a3000orange|r ones "
            .. "you know but are missing something for, and |cff6e1208red|r ones you have not learned yet. "
            .. "Visit your bank once so the addon knows what is in it.",
        "|cff4e1804This letter.|r It turns up once after each update. Type |cff4e1804/fchef news|r to read it again.",
    },
    signature = "Happy cooking,\n|cff4e1804swiftyPigeon|r",
}

local FOOTNOTE = {
    "|cff4e1804Getting started.|r Hover over any ingredient to see the recipes that use it (green: you can "
        .. "make it, orange: you know it but lack ingredients, red: not learned). |cff4e1804/fchef|r opens the recipe list: click a recipe to see where to learn "
        .. "it and set a map waypoint. |cff4e1804/fchef ranks|r shows how to reach your next Cooking rank.",
    "|cff4e1804Help make the data better.|r Type |cff4e1804/fchef export|r and send the text through the link "
        .. "in that window. Seen a wrong vendor, recipe or map position? Report it here (click, then Ctrl+C), "
        .. "or leave a comment on CurseForge:",
}

FC.ISSUES_URL = "https://github.com/swiftyPigeon/ForeverChef_AddOn/issues"

local WIDTH, HEIGHT = 460, 560
local PAD = 30
-- Aged, muted parchment (about half the brightness of white paper); every text colour
-- below keeps at least 4.5:1 contrast against it.
local PAPER  = { 0.75, 0.67, 0.51, 1 }
local EDGE   = { 0.45, 0.35, 0.22, 1 }   -- aged rim and rules
local FRAME  = { 0.18, 0.11, 0.05, 1 }   -- dark brown outer line
local INK    = { 0.12, 0.07, 0.03, 1 }
local FADED  = { 0.20, 0.13, 0.07, 1 }   -- footnote ink

local letter

-- A soft darker band along one edge of the paper, fading inwards.
local CORNERS = { TOP = { "TOPLEFT", "TOPRIGHT" }, BOTTOM = { "BOTTOMLEFT", "BOTTOMRIGHT" },
                  LEFT = { "TOPLEFT", "BOTTOMLEFT" }, RIGHT = { "TOPRIGHT", "BOTTOMRIGHT" } }
local DARK, CLEAR = { 0.36, 0.26, 0.14, 0.55 }, { 0.36, 0.26, 0.14, 0 }
local function shade(parent, side, size)
    local t = parent:CreateTexture(nil, "BORDER")
    t:SetColorTexture(1, 1, 1, 1)
    t:SetPoint(CORNERS[side][1])
    t:SetPoint(CORNERS[side][2])
    local vertical = side == "TOP" or side == "BOTTOM"
    if vertical then t:SetHeight(size) else t:SetWidth(size) end
    -- gradients run bottom -> top (VERTICAL) and left -> right (HORIZONTAL)
    local a, b = DARK, CLEAR
    if side == "TOP" or side == "RIGHT" then a, b = CLEAR, DARK end
    local orientation = vertical and "VERTICAL" or "HORIZONTAL"
    -- Newer clients take colour objects, older ones eight numbers; a flat tint otherwise.
    local ok = CreateColor and pcall(t.SetGradient, t, orientation, CreateColor(a[1], a[2], a[3], a[4]),
        CreateColor(b[1], b[2], b[3], b[4]))
    if not ok and t.SetGradientAlpha then
        ok = pcall(t.SetGradientAlpha, t, orientation, a[1], a[2], a[3], a[4], b[1], b[2], b[3], b[4])
    end
    if not ok then t:SetColorTexture(0.36, 0.26, 0.14, 0.15) end
end

local function rule(parent, anchor, gap)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(unpack(EDGE))
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -gap)
    line:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
    return line
end

local function text(parent, fontObject, size, color, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFontObject(fontObject or GameFontNormal)
    if size then
        local file, _, flags = fs:GetFont()
        if file then fs:SetFont(file, size, flags) end
    end
    fs:SetTextColor(unpack(color))
    fs:SetShadowColor(0, 0, 0, 0)
    fs:SetJustifyH(justify or "LEFT")
    fs:SetJustifyV("TOP")
    fs:SetWordWrap(true)
    fs:SetSpacing(2)
    return fs
end

local function createLetter()
    local frame = CreateFrame("Frame", "ForeverChefLetter", UIParent, "BackdropTemplate")
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetPoint("CENTER", 0, 20)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
    frame:SetBackdropColor(unpack(PAPER))
    frame:SetBackdropBorderColor(unpack(FRAME))
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do shade(frame, side, 26) end
    -- a thin inner line, like the edge of a printed letterhead
    local inner = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    inner:SetPoint("TOPLEFT", 8, -8)
    inner:SetPoint("BOTTOMRIGHT", -8, 8)
    inner:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    inner:SetBackdropBorderColor(unpack(EDGE))

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)

    -- Letterhead
    local logo = FC:CreateBrandIcon(frame, 44)
    logo:SetPoint("TOP", 0, -22)
    local name = text(frame, _G.QuestTitleFont or GameFontNormalLarge, 20, INK, "CENTER")
    name:SetPoint("TOP", logo, "BOTTOM", 0, -6)
    name:SetText("Forever Chef")
    frame.subtitle = text(frame, GameFontNormalSmall, 10, FADED, "CENTER")
    frame.subtitle:SetPoint("TOP", name, "BOTTOM", 0, -4)
    local head = CreateFrame("Frame", nil, frame)
    head:SetPoint("TOPLEFT", PAD, 0)
    head:SetPoint("TOPRIGHT", -PAD, 0)
    head:SetPoint("BOTTOM", frame.subtitle, "BOTTOM", 0, 0)
    local topRule = rule(head, head, 10)

    -- Body (scrolls if a long letter does not fit)
    local scroll = CreateFrame("ScrollFrame", "ForeverChefLetterScroll", frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", topRule, "BOTTOMLEFT", 0, -12)
    scroll:SetPoint("BOTTOMRIGHT", -PAD, 52)
    scroll.scrollBarHideable = true   -- the bar only shows when the letter is too long
    local bar = _G.ForeverChefLetterScrollScrollBar
    if bar then
        bar:ClearAllPoints()
        bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 4, -16)
        bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 4, 16)
    end
    local body = CreateFrame("Frame", nil, scroll)
    body:SetSize(WIDTH - 2 * PAD, 10)
    scroll:SetScrollChild(body)
    frame.scroll, frame.body = scroll, body

    -- Footer: a plain ink "button"
    local done = CreateFrame("Button", nil, frame, "BackdropTemplate")
    done:SetSize(96, 24)
    done:SetPoint("BOTTOM", 0, 18)
    done:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    done:SetBackdropColor(0.68, 0.60, 0.45, 1)
    done:SetBackdropBorderColor(unpack(FRAME))
    local doneText = text(done, GameFontNormal, 12, INK, "CENTER")
    doneText:SetPoint("CENTER")
    doneText:SetText("Close")
    done:SetScript("OnEnter", function(self) self:SetBackdropColor(0.80, 0.72, 0.56, 1) end)
    done:SetScript("OnLeave", function(self) self:SetBackdropColor(0.68, 0.60, 0.45, 1) end)
    done:SetScript("OnClick", function() frame:Hide() end)

    tinsert(UISpecialFrames, "ForeverChefLetter")
    return frame
end

-- Lays the letter out top to bottom inside the scroll child.
local function fill(frame)
    local body, width = frame.body, WIDTH - 2 * PAD - 6
    local y = 0
    local function add(fs, gap)
        fs:SetWidth(width)
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -y)
        y = y + fs:GetStringHeight() + (gap or 10)
        return fs
    end
    local bodyFont = _G.QuestFont or GameFontHighlight

    local greeting = text(body, bodyFont, 14, INK)
    greeting:SetText(LETTER.greeting)
    add(greeting, 8)
    for _, paragraph in ipairs(LETTER.paragraphs) do
        local p = text(body, bodyFont, 13, INK)
        p:SetText(paragraph)
        add(p, 10)
    end
    local sign = text(body, bodyFont, 13, INK, "RIGHT")
    sign:SetText(LETTER.signature)
    add(sign, 16)

    local line = body:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(unpack(EDGE))
    line:SetSize(width * 0.4, 1)
    line:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -y)
    y = y + 10
    for _, note in ipairs(FOOTNOTE) do
        local n = text(body, GameFontHighlightSmall, 11, FADED)
        n:SetText(note)
        add(n, 6)
    end
    local link = FC:CreateLinkBox(body, FC.ISSUES_URL, { 0.70, 0.62, 0.47, 1 }, EDGE, INK, function() frame:Hide() end)
    link:SetFontObject(GameFontHighlightSmall)
    link:SetTextColor(unpack(INK))
    link:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -y)
    link:SetWidth(width)
    y = y + 24 + 4
    body:SetHeight(y)
    frame.filled = true
end

function FC:ShowLetter()
    letter = letter or createLetter()
    letter.subtitle:SetText(string.format("WHAT'S NEW IN VERSION %s", LETTER.version))
    letter:Show()
    -- Text sizes are only right once the frame is on screen.
    if not letter.filled then fill(letter) end
    letter.scroll:SetVerticalScroll(0)
    self.db.letterSeen = LETTER.version
end

function FC:ToggleLetter()
    if letter and letter:IsShown() then letter:Hide() else self:ShowLetter() end
end

-- Once per account per letter: a few seconds after entering the world, out of combat.
local scheduled
local function showWhenFree()
    if FC.db.letterSeen == LETTER.version then return end
    if InCombatLockdown and InCombatLockdown() then
        C_Timer.After(5, showWhenFree)
    else
        FC:ShowLetter()
    end
end

FC:On("PLAYER_ENTERING_WORLD", function()
    if scheduled or not FC.db or FC.db.letterSeen == LETTER.version then return end
    scheduled = true
    C_Timer.After(4, showWhenFree)
end)
