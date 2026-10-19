local ADDON_NAME, FC = ...

-- Bump when the saved data layout changes in a way old data cannot be read.
local DB_VERSION = 2

local events = CreateFrame("Frame")
local handlers = {}
local initializers = {}

function FC:Print(message)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff4fc3a1Forever Chef|r  " .. tostring(message))
    end
end

-- Something was learned: shown as a pop-up (Toast.lua) unless turned off with /fchef quiet.
function FC:Notify(message)
    self.listsDirty = true
    if not self.char or self.char.quiet then return end
    if self.ShowToast then self:ShowToast(message) else self:Print(message) end
end

function FC:Debug(message)
    if self.char and self.char.debug then self:Print("|cff888888" .. tostring(message) .. "|r") end
end

-- Several modules can listen to the same event, so events are fanned out here
-- instead of each module owning its own frame.
function FC:On(event, fn)
    if not handlers[event] then
        handlers[event] = {}
        -- pcall: an event this client does not have must not stop the file loading.
        if not pcall(events.RegisterEvent, events, event) then return end
    end
    table.insert(handlers[event], fn)
end

function FC:OnInit(fn)
    table.insert(initializers, fn)
end

events:SetScript("OnEvent", function(_, event, ...)
    for _, fn in ipairs(handlers[event]) do
        local ok, err = pcall(fn, event, ...)
        if not ok then FC:Debug(event .. ": " .. tostring(err)) end
    end
end)

function FC.Round(value, places)
    local mult = 10 ^ (places or 0)
    return math.floor(value * mult + 0.5) / mult
end

local function newDB()
    return { version = DB_VERSION, recipes = {}, observed = {}, npcLocations = {} }
end

FC:On("ADDON_LOADED", function(_, name)
    if name ~= ADDON_NAME then return end
    if type(ForeverChefDB) ~= "table" or ForeverChefDB.version ~= DB_VERSION then
        ForeverChefDB = newDB()
    end
    ForeverChefCharDB = ForeverChefCharDB or {}
    -- Travel recording (routes, flights, towns) was removed in 0.6.0: drop what it saved.
    for _, key in ipairs({ "nextId", "nodes", "edges", "flights", "towns" }) do ForeverChefDB[key] = nil end
    ForeverChefCharDB.knownFlightPoints = nil
    FC.db = ForeverChefDB
    FC.char = ForeverChefCharDB
    for _, fn in ipairs(initializers) do
        local ok, err = pcall(fn)
        if not ok then FC:Print("Startup error: " .. tostring(err)) end
    end
    FC:Print("Cooking recipes are on your ingredient tooltips. Click the cooking scroll on the minimap or type /fchef.")
end)

function FC:HandleSlash(message)
    local command = strtrim((message or ""):lower())
    if command == "export" then
        self:ShowExport()
    elseif command == "debug" then
        self.char.debug = not self.char.debug
        self:Print("Debug messages " .. (self.char.debug and "on." or "off."))
    elseif command == "quiet" then
        self.char.quiet = not self.char.quiet
        self:Print(self.char.quiet and "Pop-ups off. /fchef quiet turns them back on." or "Pop-ups on.")
    elseif command == "toast" then
        self:ShowToast("This is where Forever Chef pop-ups appear. Shift+drag the gold border to move it.")
    elseif command == "toast reset" then
        self:ResetToastPosition()
        self:ShowToast("Pop-up moved back above action bar 1.")
    elseif command == "" then
        self:ToggleWindow()
    elseif command == "reset" then
        StaticPopup_Show("FOREVERCHEF_RESET")
    else
        local total, known = self:RecipeStats()
        self:Print(string.format("You know %d of %d Cooking recipes.", known, total))
        self:Print(string.format("Recorded in game: %d recipe sources, %d NPC positions.", self:ObservedCount(), self:NPCLocationCount()))
        self:Print("Commands: /fchef (window) | status | export | quiet | toast | toast reset | debug | reset")
    end
end

StaticPopupDialogs["FOREVERCHEF_RESET"] = {
    text = "Erase the recipe sources and NPC positions Forever Chef recorded on this account?",
    button1 = YES,
    button2 = NO,
    OnAccept = function()
        ForeverChefDB = newDB()
        FC.db = ForeverChefDB
        FC.RebuildRecipeIndex()
        FC.listsDirty = true
        FC:Print("Recorded data erased.")
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

SLASH_FOREVERCHEF1 = "/fchef"
SLASH_FOREVERCHEF2 = "/foreverchef"
SlashCmdList.FOREVERCHEF = function(message) FC:HandleSlash(message) end
