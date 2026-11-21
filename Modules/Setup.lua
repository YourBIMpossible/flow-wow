-- Setup table (/flow setup; opens once on first run). Each row is a setting
-- with a tick box showing its CURRENT state (ticked = on). Change any of them
-- and click Apply: it turns things on or off to match. Quick picks:
--   All / None / Flow suggests / WoW default / Revert (back to how they are now)
-- Rows are registered, so features can add their own:
--   ns:Register("setupItem", key, { order, label, why, available = fn,
--       isOn = fn() -> bool, set = fn(on), suggested = bool, default = bool })
--   or an action row: { order, label, why, now = fn() -> text, action = "Set...", run = fn }
--   or an info row:   { order, label, why, now = fn() -> text, info = true }
-- Rows whose setting this client doesn't have are left out.

local _, ns = ...
local S = {}
ns.setup = S

local function cvar(name)
    local ok, v = pcall(GetCVar, name)
    if ok then return v end
end

local function cvarDefault(name)
    local ok, v = pcall(GetCVarDefault, name)
    if ok then return v end
end

-- An on/off CVar row.
local function cvarRow(key, order, label, why, name, onValue, offValue, suggested, isNew)
    ns:Register("setupItem", key, {
        order = order, label = label, why = why,
        available = function() return cvar(name) ~= nil end,
        isOn = function() return cvar(name) == onValue end,
        set = function(on) SetCVar(name, on and onValue or offValue) end,
        suggested = suggested, isNew = isNew,
        default = function() return cvarDefault(name) == onValue end,
    })
end

-- Auto loot: while "Leave junk behind" is on (Items/LootFilter.lua), Flow
-- does the auto-looting and the game's own is off, so this row follows Flow's.
ns:Register("setupItem", "autoLoot", {
    order = 10, label = "Auto loot", why = "Loot everything with one click instead of picking each item.",
    available = function() return cvar("autoLootDefault") ~= nil end,
    isOn = function()
        local L = ns.db.loot
        if L and L.skipJunk then return L.auto ~= false end
        return cvar("autoLootDefault") == "1"
    end,
    set = function(on)
        local L = ns.db.loot
        if L and L.skipJunk then L.auto = on and true or false return end
        SetCVar("autoLootDefault", on and "1" or "0")
    end,
    suggested = true,
    default = function() return cvarDefault("autoLootDefault") == "1" end,
})
cvarRow("enemyPlates", 20, "Enemy nameplates", "Flow's quest marks (skull, diamond) sit on nameplates.",
    "nameplateShowEnemies", "1", "0", true)
cvarRow("friendPlates", 30, "Friendly nameplates", "Shows Flow's star on NPCs your quests mention, and its (o) over the one you're heading to.",
    "nameplateShowFriends", "1", "0", true)
cvarRow("instantQuest", 40, "Instant quest text", "Quest text appears at once instead of scrolling.",
    "instantQuestText", "1", "0", true)
-- Heals with no friendly target land on you, no key to hold (the key that
-- forces it on you anyway is in Flow's settings: "Heal yourself: hold").
cvarRow("autoSelfCast", 45, "Heals land on you with no target",
    "With nobody friendly targeted, a heal or buff casts on you: no key to hold, no clicking yourself first.",
    "autoSelfCast", "1", "0", true, true)
-- Questie puts a "!" at every spawn of every mob that drops a quest-starting
-- item: the map and minimap fill with them. Flow suggests turning that off;
-- it says it once instead (a "quest drop" line in the Flow Tracker when
-- those mobs are near, and a "!" on their nameplates). Same switch as
-- Questie's own "Available Quests from Items" option.
local function questieQuest()
    if not QuestieLoader then return nil end
    local ok, qq = pcall(QuestieLoader.ImportModule, QuestieLoader, "QuestieQuest")
    return ok and qq or nil
end
ns:Register("setupItem", "questieDropIcons", {
    order = 46, label = "Questie: \"!\" at every mob that drops a quest item",
    why = "Off: no ! all over the map for quests that start from a drop. Flow says it once instead: a \"quest drop\" line in the Flow Tracker when those mobs are near you, and a ! on their nameplates.",
    available = function() return Questie and Questie.db and Questie.db.profile and Questie.db.profile.enableAvailableItems ~= nil end,
    isOn = function() return Questie.db.profile.enableAvailableItems ~= false end,
    set = function(on)
        local profile = Questie.db.profile   -- (Questie's own option, the same switch as in its settings)
        profile.enableAvailableItems = on and true or false
        local qq = questieQuest()
        if qq and qq.ToggleAvailableQuests then pcall(qq.ToggleAvailableQuests, on and true or false) end
    end,
    suggested = false, isNew = true,
    default = function() return true end,
})
cvarRow("autoPush", 50, "Auto-place new spells on bars",
    "The game drops newly learned spells into empty bar slots. Leave off if you place spells yourself.",
    "AutoPushSpellToActionBar", "1", "0", false)
-- Fishing and mining with Flow's key: it presses Interact, which only reaches
-- the bobber / vein / herb in front of you with "soft target interact" on.
cvarRow("softInteract", 52, "Interact key reaches objects",
    "Your Interact key (and Flow's key while fishing or mining) reels in the bobber and gathers the vein or herb in front of you.",
    "SoftTargetInteract", "3", "0", true, true)
-- Your health is hidden from add-ons; the game's red low-health flash is how
-- Flow knows to suggest a heal. (The game's option is "don't flash": off = flash.)
cvarRow("lowHealthFlash", 53, "Low-health screen warning",
    "The red screen flash when your health is low. Flow uses it to suggest a heal (your health itself is hidden from add-ons).",
    "doNotFlashLowHealthWarning", "0", "1", true, true)

-- Target of target: classic-style clients have a CVar; newer ones put it in Edit Mode
-- (Target Frame > "Target of Target"), so that case is an info row telling you where.
-- Health and mana as numbers on your own and your target's frames (0.35.254:
-- "a Flow recommended default should be to keep the health and mana numbers
-- on target frames and player frames"). Two of the game's settings between
-- them, depending on the client: statusText (on or off) and
-- statusTextDisplay (NONE, NUMERIC, PERCENT, BOTH). Pure:
--   is it on, going by whichever of the two this client has?
function S.StatusTextOn(statusText, display)
    if statusText == nil and display == nil then return false end
    if statusText ~= nil and statusText ~= "1" then return false end
    if display ~= nil and display == "NONE" then return false end
    return true
end
--   what to set: { statusText, statusTextDisplay }. On keeps the way of
--   showing you already chose (percent, both); numbers when there was none.
function S.StatusTextSet(on, display)
    if not on then return "0", "NONE" end
    return "1", (display ~= nil and display ~= "NONE") and display or "NUMERIC"
end
ns:Register("setupItem", "statusText", {
    order = 54, label = "Health and mana numbers on your and your target's frames",
    why = "The numbers written on the health and mana bars of your own frame and your target's, so you can read how much is left and not only see the bar. (If they don't show at once, /reload.)",
    available = function() return cvar("statusText") ~= nil or cvar("statusTextDisplay") ~= nil end,
    isOn = function() return S.StatusTextOn(cvar("statusText"), cvar("statusTextDisplay")) end,
    set = function(on)
        local text, display = S.StatusTextSet(on, cvar("statusTextDisplay"))
        if cvar("statusText") ~= nil then SetCVar("statusText", text) end
        if cvar("statusTextDisplay") ~= nil then SetCVar("statusTextDisplay", display) end
    end,
    suggested = true, isNew = true,
    default = function() return S.StatusTextOn(cvarDefault("statusText"), cvarDefault("statusTextDisplay")) end,
})
ns:Register("setupItem", "targetOfTarget", {
    order = 55, label = "Target of target",
    why = "Shows who your target is attacking, so you see when a mob turns on you or a party member.",
    available = function() return cvar("showTargetOfTarget") ~= nil end,
    isOn = function() return cvar("showTargetOfTarget") == "1" end,
    set = function(on)
        SetCVar("showTargetOfTarget", on and "1" or "0")
        if TargetofTarget_Update and TargetFrameToT then pcall(TargetofTarget_Update, TargetFrameToT) end
    end,
    suggested = true,
    default = function() return cvarDefault("showTargetOfTarget") == "1" end,
    isNew = true,  -- added after the first-run table: shown once to existing installs too
})
ns:Register("setupItem", "targetOfTargetEdit", {
    order = 55, label = "Target of target",
    why = "Shows who your target is attacking. Turn it on in Edit Mode: Target Frame > Target of Target.",
    available = function() return cvar("showTargetOfTarget") == nil end,
    now = function() return "in Edit Mode" end,
    info = true,
})

ns:Register("setupItem", "zoom", {
    order = 60, label = "Max camera zoom", why = "See more around you while questing.",
    isOn = function() return ns.camera:IsOn() end,
    set = function(on) ns.camera:Set(on) end,
    suggested = true, default = false,
})

-- The game's "Camera Following Style": by default it swings the camera back
-- behind you whenever you move. Off = the camera stays where you put it.
ns:Register("setupItem", "cameraStays", {
    order = 61, label = "Camera stays where you put it",
    why = "Stops the game swinging the camera back behind you when you move (the game's Camera Following Style: Never).",
    available = function() return cvar("cameraSmoothStyle") ~= nil end,
    isOn = function() return cvar("cameraSmoothStyle") == "0" end,
    set = function(on)
        if on then SetCVar("cameraSmoothStyle", "0")
        else SetCVar("cameraSmoothStyle", cvarDefault("cameraSmoothStyle") or "4") end
    end,
    suggested = true,
    default = function() return cvarDefault("cameraSmoothStyle") == "0" end,
    isNew = true,
})
-- (Until F-089 this was switched on silently at the first login. A game
-- setting changes only from this row now: Flow Setup suggests it.)

ns:Register("setupItem", "stamps", {
    order = 70, label = "Chat timestamps", why = "See when each chat line arrived.",
    isOn = function() local v = cvar("showTimestamps"); return v ~= nil and v ~= "none" end,
    set = function(on) SetCVar("showTimestamps", on and "%H:%M:%S " or "none") end,
    suggested = true,
    default = function() local d = cvarDefault("showTimestamps"); return d ~= nil and d ~= "none" end,
})

ns:Register("setupItem", "colorblind", {
    order = 75, label = "Colour-blind route colours",
    why = "Route colours that stay apart for the common kinds of colour blindness (same meaning: route colour = order mode, orange = preview of the hovered step).",
    isOn = function() return ns.theme:ColorBlind() end,
    set = function(on) ns.theme:SetColorBlind(on) end,
    suggested = false, default = false,
})

ns:Register("setupItem", "combatLog", {
    order = 80, label = "Combat log file every session",
    why = "Lets Claude analyse your fights and tune Flow's rotation (tools\\analyze-combatlog.ps1).",
    isOn = function() return ns.db.log and ns.db.log.auto == true end,
    set = function(on)
        ns.db.log.auto = on
        if LoggingCombat then pcall(LoggingCombat, on) end
    end,
    suggested = true, default = false,
})

ns:Register("setupItem", "castKey", {
    order = 90, label = "Flow cast key", why = "One key that casts Flow's suggestion.",
    now = function() return ns.db.cast.key and ns.cast:KeyLabel() or "not set" end,
    action = "Set...",
    run = function() if ns.settings then ns.settings:Open() end end,
})

ns:Register("setupItem", "questie", {
    order = 100, label = "Questie + QuestieDB",
    why = "Quest and NPC locations for the arrow, map route and missed quests. Install it yourself (CurseForge app).",
    now = function() return ns.quests:Source() and ns.quests:Source().label == "Questie" and "installed" or "not found" end,
    info = true,
})

-------------------------------------------------------------------------------
-- Panel
-------------------------------------------------------------------------------

local frame

local function rows()
    local list = {}
    for key, item in ns:Each("setupItem") do
        if not item.available or item.available() then list[#list + 1] = { key = key, item = item } end
    end
    table.sort(list, function(a, b) return (a.item.order or 100) < (b.item.order or 100) end)
    return list
end

local function val(v) if type(v) == "function" then return v() end return v end

local function button(parent, text, w)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, 22)
    b:SetText(text)
    return b
end

local function each(fn)
    for _, row in ipairs(frame.rows) do if row.check then fn(row) end end
end

local function build()
    local list = rows()
    local f = CreateFrame("Frame", "FlowSetup", UIParent)
    f:SetSize(580, 128 + #list * 26)
    local p = ns.db.setup.point
    if p then f:SetPoint(p[1], UIParent, p[2], p[3], p[4]) else f:SetPoint("CENTER", 0, 60) end
    f:SetFrameStrata("DIALOG")
    f:EnableMouse(true)
    tinsert(UISpecialFrames, "FlowSetup")
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.bg:SetColorTexture(0.05, 0.05, 0.08, 0.95)
    f.head = ns.theme:TitleBar(f, "Flow Setup", "Interface\\Icons\\INV_Misc_Gear_01")
    ns:MakeMovable(f, ns.db.setup, true)

    local sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", 16, -36)
    sub:SetText("Ticked = on. Change what you like and click Apply. Hover a row for why. /flow setup reopens this.")
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    close:SetScript("OnClick", function() f:Hide() end)   -- (our own: the game's handler can't close an add-on window in a fight)

    local function header(text, x)
        local h = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        h:SetPoint("TOPLEFT", x, -58)
        h:SetText(text)
    end
    header("Setting", 48); header("Now", 320); header("Flow suggests", 400)

    f.rows = {}
    for i, r in ipairs(list) do
        local item = r.item
        local row = CreateFrame("Frame", nil, f)
        row:SetPoint("TOPLEFT", 12, -74 - (i - 1) * 26)
        row:SetSize(556, 24)
        row:EnableMouse(true)
        row:SetScript("OnEnter", function(self)
            ns.Tip(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(item.label)
            GameTooltip:AddLine(item.why or "", 1, 1, 1, true)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        if item.isOn then
            row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
            row.check:SetSize(22, 22)
            row.check:SetPoint("LEFT", 6, 0)
            row.check:SetScript("OnClick", function() S:RefreshText() end)
        end
        row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.label:SetPoint("LEFT", 36, 0)
        row.label:SetText(item.label)
        row.now = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.now:SetPoint("LEFT", 308, 0)
        row.want = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.want:SetPoint("LEFT", 388, 0)
        if item.isOn then row.want:SetText(item.suggested and "on" or "off") end
        if item.action then
            -- Own column on the right, clear of the text.
            local b = button(row, item.action, 70)
            b:SetPoint("RIGHT", -4, 0)
            b:SetScript("OnClick", function() item.run() end)
        end
        row.item = item
        f.rows[#f.rows + 1] = row
    end

    -- Quick picks + apply.
    local x = 12
    f.picks = {}
    local function pick(text, w, fn)
        local b = button(f, text, w)
        f.picks[text] = b
        b:SetPoint("BOTTOMLEFT", x, 12)
        x = x + w + 4
        b:SetScript("OnClick", function() fn(); S:RefreshText() end)
    end
    pick("All", 50, function() each(function(r) r.check:SetChecked(true) end) end)
    pick("None", 56, function() each(function(r) r.check:SetChecked(false) end) end)
    pick("Flow suggests", 104, function() each(function(r) r.check:SetChecked(r.item.suggested and true or false) end) end)
    pick("WoW default", 96, function() each(function(r) r.check:SetChecked(val(r.item.default) and true or false) end) end)
    -- "Revert", not "Reset": it puts the boxes back to how the settings are
    -- now, not to any defaults (F-090; "WoW default" is the defaults).
    pick("Revert", 60, function() each(function(r) r.check:SetChecked(r.item.isOn() and true or false) end) end)

    local apply = button(f, "Apply", 90)
    apply:SetPoint("BOTTOMRIGHT", -12, 12)
    apply:SetScript("OnClick", function()
        if InCombatLockdown() then ns:Print("can't change settings in combat") return end
        local n = 0
        each(function(r)
            local want = r.check:GetChecked() and true or false
            if want ~= (r.item.isOn() and true or false) then pcall(r.item.set, want); n = n + 1 end
        end)
        S:Finish()
        ns:Print(n .. " setting(s) changed.")
        S:Refresh()
    end)
    f:Hide()
    return f
end

-- (Tests) the stand-alone table, built but not shown.
function S._Table()
    frame = frame or build()
    return frame
end

-- Updates the "Now" column (and marks rows you've changed but not applied).
function S:RefreshText()
    if not frame then return end
    for _, row in ipairs(frame.rows) do
        local item = row.item
        if item.isOn then
            local on = item.isOn() and true or false
            local pending = row.check:GetChecked() ~= on
            row.now:SetText((on and "on" or "off") .. (pending and "  |cffffd200(will change)|r" or ""))
        elseif item.now then
            local ok, t = pcall(item.now)
            row.now:SetText(ok and t or "?")
        end
    end
end

-- Tick boxes back to the current state of each setting.
function S:Refresh()
    if not frame then return end
    for _, row in ipairs(frame.rows) do
        if row.check then row.check:SetChecked(row.item.isOn() and true or false) end
    end
    self:RefreshText()
end

-- The rows, for Flow's Options page ("Suggested WoW settings", Settings.lua).
function S:Rows() return rows() end
S.Value = function(v) if type(v) == "function" then return v() end return v end

-- The suggestions live on Flow's page in the game's Options > AddOns now
-- (Settings.lua); /flow setup and the first-run prompt open that page.
-- The old stand-alone table is kept only for clients without that page.
function S:Open()
    self:MarkSeen()
    if ns.settings and ns.settings.Open and ns.settings:Open("suggest") then return end
    frame = frame or build()
    frame:Show()
    self:Refresh()
end

ns:OnLoad(function(saved)
    saved.setup = saved.setup or {}
end)

-- Suggested rows you've never been shown that are still off (e.g. a row added in an update).
-- Installs from before this list existed count every row as seen except ones marked isNew.
function S:Unseen()
    local db = ns.db.setup
    if not db.seen then
        db.seen = {}
        if db.done then
            for key, item in ns:Each("setupItem") do if not item.isNew then db.seen[key] = true end end
        end
    end
    local out = {}
    for _, r in ipairs(rows()) do
        local it = r.item
        if not db.seen[r.key] and it.isOn and it.suggested and not it.isOn() then out[#out + 1] = it.label end
    end
    return out
end

function S:MarkSeen()
    if not ns.db.setup.seen then self:Unseen() end
    for _, r in ipairs(rows()) do ns.db.setup.seen[r.key] = true end
end

-- Setup counts as done only once you've chosen: Apply here, or "Use Flow's
-- suggestions" / "Keep my settings" on Flow's page. Opening it isn't
-- choosing (F-094: it used to be marked done before it opened, so a player
-- who closed it, or never saw it, kept defaults they'd never been shown).
function S:Done() return ns.db.setup.done == true end
function S:Finish()
    ns.db.setup.done = true
end

-- Pure: what the first-run offer does now. -> "open", "wait" (try again
-- shortly: in a fight, or the rest of Flow isn't on screen yet) or "no".
-- Until you've chosen it's offered once each session; after that, once
-- when an update adds a suggestion you haven't seen.
function S.OfferState(done, unseen, inCombat, adviceShown, offeredThisSession)
    if offeredThisSession then return "no" end
    if done and unseen == 0 then return "no" end
    if inCombat or not adviceShown then return "wait" end
    return "open"
end

S.FIRST_RUN_TEXT = "Flow Setup is open: choose your settings, then click \"Use Flow's suggestions\" or \"Keep my settings\". "
    .. "Until you do, it opens once each login. /flow setup reopens it any time."

local offered, waiting = false, false

-- One go at the offer; `later` schedules the next go (C_Timer.After in game).
function S:TryOffer(later)
    waiting = false
    local unseen = S:Unseen()
    local state = S.OfferState(self:Done(), #unseen, InCombatLockdown(),
        not ns.reveal or ns.reveal:Shown("advice"), offered)
    if state == "wait" then
        -- New to Flow: once the rest is on screen (Reveal.lua), not next login.
        waiting = true
        if later then later(30, function() S:TryOffer(later) end) end
        return state
    end
    if state ~= "open" then return state end
    offered = true
    local wasDone = self:Done()
    S:MarkSeen()
    if wasDone then ns:Print("new in the setup table: " .. table.concat(unseen, ", "))
    else ns:Print(S.FIRST_RUN_TEXT) end
    S:Open()
    return state
end

-- (Tests) sets this session's offer flags; returns the old ones to put back.
function S._OfferFlags(o, w)
    local oldO, oldW = offered, waiting
    offered, waiting = o and true or false, w and true or false
    return oldO, oldW
end

ns:On("PLAYER_ENTERING_WORLD", function()
    if offered or waiting then return end
    if S:Done() and #S:Unseen() == 0 then return end
    waiting = true
    C_Timer.After(30, function() S:TryOffer(C_Timer.After) end)  -- well after the splash, so new players aren't swamped
end)

ns.commands.setup = function() S:Open() end
ns:Register("help", "setup", { order = 4, title = "Setup", lines = {
    "/flow setup - settings table: auto loot, nameplates, zoom, timestamps, combat log, cast key...",
} })
