local ADDON_NAME, FC = ...

-- Small pop-up for "learned something" messages, shown instead of chat lines.
-- Starts just above action bar 1; Shift+drag its gold border to move it (saved
-- per character). Clicks on the middle pass through to the game world.
local WIDTH = 340
local SHOW_SECONDS = 5
local FADE_SECONDS = 0.6
local EDGE = 6                      -- grab area along the border, in pixels
local GOLD = { 1.00, 0.82, 0.20, 1 }
local BACKGROUND = { 0, 0, 0, 0.72 }

local toast
local queue = {}

local function settings()
    FC.char.ui = FC.char.ui or {}
    return FC.char.ui
end

-- Action bar 1 is MainActionBar on newer clients and MainMenuBar on older ones.
local function defaultAnchor()
    local bar = _G.MainActionBar or _G.MainMenuBar
    if bar and bar.IsShown and bar:IsShown() then
        return "BOTTOM", bar, "TOP", 0, 12
    end
    return "BOTTOM", UIParent, "BOTTOM", 0, 150
end

local function applyPosition()
    toast:ClearAllPoints()
    local saved = settings().toastPoint
    if saved then
        toast:SetPoint(saved[1], UIParent, saved[2], saved[3], saved[4])
    else
        toast:SetPoint(defaultAnchor())
    end
end

local function savePosition()
    local point, _, relativePoint, x, y = toast:GetPoint(1)
    settings().toastPoint = { point, relativePoint, x, y }
end

local function showNext()
    local message = table.remove(queue, 1)
    if not message then
        toast:Hide()
        return
    end
    toast.text:SetText(message)
    toast:SetHeight(math.max(44, toast.text:GetStringHeight() + 36))
    toast.remaining = SHOW_SECONDS
    toast:SetAlpha(1)
    toast:Show()
end

-- Thin mouse-enabled strips along each side: the only part of the toast that
-- takes the mouse, so Shift+drag on the border moves it and the rest clicks through.
local function addGrabEdge(side)
    local edge = CreateFrame("Frame", nil, toast)
    if side == "TOP" or side == "BOTTOM" then
        edge:SetPoint(side .. "LEFT")
        edge:SetPoint(side .. "RIGHT")
        edge:SetHeight(EDGE)
    else
        edge:SetPoint("TOP" .. side)
        edge:SetPoint("BOTTOM" .. side)
        edge:SetWidth(EDGE)
    end
    edge:EnableMouse(true)
    edge:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" and IsShiftKeyDown() then
            toast.moving = true
            toast:StartMoving()
        end
    end)
    edge:SetScript("OnMouseUp", function()
        if not toast.moving then return end
        toast.moving = nil
        toast:StopMovingOrSizing()
        savePosition()
    end)
    edge:SetScript("OnEnter", function(self)
        toast.hovered = true
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Shift+drag the border to move", 1, 1, 1)
        GameTooltip:Show()
    end)
    edge:SetScript("OnLeave", function()
        toast.hovered = nil
        GameTooltip:Hide()
    end)
end

local function createToast()
    toast = CreateFrame("Frame", "ForeverChefToast", UIParent, "BackdropTemplate")
    toast:SetSize(WIDTH, 44)
    toast:SetFrameStrata("DIALOG")
    toast:SetClampedToScreen(true)
    toast:SetMovable(true)
    toast:EnableMouse(false)
    toast:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
    toast:SetBackdropColor(unpack(BACKGROUND))
    toast:SetBackdropBorderColor(unpack(GOLD))

    local icon = FC:CreateBrandIcon(toast, 22)
    icon:SetPoint("TOPLEFT", 10, -10)

    local title = toast:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, 1)
    title:SetText("Forever Chef")
    title:SetTextColor(unpack(GOLD))

    toast.text = toast:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    toast.text:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
    toast.text:SetWidth(WIDTH - 60)
    toast.text:SetJustifyH("LEFT")
    toast.text:SetWordWrap(true)
    toast.text:SetTextColor(1, 1, 1)

    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do addGrabEdge(side) end

    -- Count down while visible; pause while hovered or being moved, then fade.
    toast:SetScript("OnUpdate", function(self, elapsed)
        if self.hovered or self.moving then
            self:SetAlpha(1)
            return
        end
        self.remaining = self.remaining - elapsed
        if self.remaining <= 0 then
            showNext()
        elseif self.remaining < FADE_SECONDS then
            self:SetAlpha(self.remaining / FADE_SECONDS)
        end
    end)

    applyPosition()
    toast:Hide()
end

function FC:ShowToast(message)
    if not toast then createToast() end
    table.insert(queue, message)
    if not toast:IsShown() then showNext() end
end

function FC:ResetToastPosition()
    settings().toastPoint = nil
    if toast then applyPosition() end
end
