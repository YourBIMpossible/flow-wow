-- Flow core: shared namespace, saved variables, and a tiny event bus
-- that modules hook into. Add new features as files in Modules\ and list
-- them in Flow.toc.

local ADDON_NAME, ns = ...

ns.name = ADDON_NAME
ns.modules = {}

-------------------------------------------------------------------------------
-- Registries: the extension points. New classes, specs, fight types, metrics,
-- advisors, gear considerations and fight probes are added by registering
-- them from their own files; existing code never needs editing.
-- See docs/ARCHITECTURE.md for every kind and its shape.
-------------------------------------------------------------------------------

local registries = {}

local function registry(kind)
    local r = registries[kind]
    if not r then
        r = { list = {}, byKey = {} }
        registries[kind] = r
    end
    return r
end

-- ns:Register("advisor", "trainer", def). Keys are unique per kind.
function ns:Register(kind, key, value)
    local r = registry(kind)
    if r.byKey[key] ~= nil then
        error(string.format("Flow: %s '%s' registered twice", kind, tostring(key)), 2)
    end
    r.byKey[key] = value
    r.list[#r.list + 1] = { key = key, value = value }
    return value
end

function ns:Get(kind, key)
    return registry(kind).byKey[key]
end

-- for key, value in ns:Each("metric") do ... end  (registration order)
function ns:Each(kind)
    local list, i = registry(kind).list, 0
    return function()
        i = i + 1
        local e = list[i]
        if e then return e.key, e.value end
    end
end

local frame = CreateFrame("Frame")
local handlers = {}

-- ns:On("EVENT_NAME", function(...) end)
function ns:On(event, fn)
    if not handlers[event] then
        handlers[event] = {}
        -- pcall: not every client flavor has every event.
        pcall(frame.RegisterEvent, frame, event)
    end
    table.insert(handlers[event], fn)
end

-- An error in a handler or loader goes to chat and, once per distinct
-- message a session, to the diagnostics log (F-010: not lost on /reload).
local logged = {}
local function logError(where, err)
    local msg = where .. ": " .. tostring(err)
    if ns.Log and ns.db and ns.db.diag and not logged[msg] then
        logged[msg] = true
        ns:Log("error", msg)
    end
end
ns._logError = logError   -- (tests)

frame:SetScript("OnEvent", function(_, event, ...)
    for _, fn in ipairs(handlers[event] or {}) do
        local ok, err = pcall(fn, ...)
        if not ok then
            print("|cffff5555Flow error|r (" .. event .. "): " .. tostring(err))
            logError(event, err)
        end
    end
    -- After every module's own logout work: this character's data goes back
    -- to FlowCharDB before the game writes the saved variables.
    if event == "PLAYER_LOGOUT" and ns.db and ns.charDb then
        local ok, err = pcall(ns.StoreCharacterData, ns, ns.db, ns.charDb)
        if not ok then print("|cffff5555Flow error|r (saving character data): " .. tostring(err)) end
    end
end)
frame:RegisterEvent("PLAYER_LOGOUT")

function ns:Print(msg)
    print("|cff66ccffFlow|r: " .. tostring(msg))
end

-- "Bags nearly full" (F-008): one threshold for every module that advises
-- about bag space (the merchant and bank steps, quest-item advice), so the
-- same screen never gives different answers. free: free bag slots, or nil
-- (not known: not nearly full).
ns.BAGS_NEARLY_FULL = 3
function ns.BagsNearlyFull(free)
    return free ~= nil and free <= ns.BAGS_NEARLY_FULL
end

-------------------------------------------------------------------------------
-- Per-character data. FlowDB is shared by every character on the account
-- (settings, learned trails, NPC places). Anything about one character (its
-- fights, class trainer, recipes, hidden steps...) is declared per character
-- by the module that owns it, next to its ns:OnLoad:
--   ns:PerCharacter("trainer")                 a whole section of ns.db
--   ns:PerCharacter("quests.notOffered")       one field of a section
--   ns:PerCharacter(path, { adopt = fn })      plus what to keep from before
-- It's saved in FlowCharDB (SavedVariablesPerCharacter, so the game keeps one
-- per character) and sits at its usual place in ns.db while you play, so the
-- module's code doesn't change. At logout it goes back to FlowCharDB.
--
-- Data saved before this split was shared by every character. It's parked
-- in FlowDB.legacyShared, and the first time each character logs in it takes
-- what adopt(old, ctx) returns (a copy; nil = start fresh, the default).
-- ctx = { class, level, name }. later = true: adopt runs at PLAYER_LOGIN
-- instead, as adopt(old, ctx, current), for checks that need the game ready
-- (which professions you have); returning false there means "can't tell
-- yet", and it's tried again at the next login. once = true: only the
-- character loaded when the old data is parked adopts it; the rest start
-- fresh (one character's hidden steps and never-sell list aren't an alt's).
-------------------------------------------------------------------------------

local function getPath(t, path)
    for part in path:gmatch("[^%.]+") do
        if type(t) ~= "table" then return nil end
        t = t[part]
    end
    return t
end
local function setPath(t, path, value)
    local parts = {}
    for part in path:gmatch("[^%.]+") do parts[#parts + 1] = part end
    for i = 1, #parts - 1 do
        if type(t[parts[i]]) ~= "table" then
            if value == nil then return end
            t[parts[i]] = {}
        end
        t = t[parts[i]]
    end
    t[parts[#parts]] = value
end
local function deepCopy(v)
    if type(v) ~= "table" then return v end
    local c = {}
    for k, x in pairs(v) do c[k] = deepCopy(x) end
    return c
end
ns.DeepCopy = deepCopy

function ns:PerCharacter(path, def)
    return self:Register("charData", path, def or {})
end

local function context()
    local _, class = UnitClass("player")
    return { class = class, level = UnitLevel("player"), name = UnitName("player") }
end

local function adoptOne(path, def, old, ctx, current)
    if old == nil or not def.adopt then return nil end
    local ok, keep
    if def.later then ok, keep = pcall(def.adopt, deepCopy(old), ctx, current)
    else ok, keep = pcall(def.adopt, deepCopy(old), ctx) end
    if not ok then
        print("|cffff5555Flow|r: couldn't sort old data (" .. path .. "): " .. tostring(keep))
        return nil
    end
    return keep
end

-- At load: park pre-split shared data once, let this character adopt its
-- share, then put this character's data where the modules look for it.
-- (Tables passed in, so the tests can run it on their own.)
function ns:SplitCharacterData(account, char, ctx)
    account.charSplit = account.charSplit or {}
    account.legacyShared = account.legacyShared or {}
    char.data = char.data or {}
    char.adopted = char.adopted or {}
    local legacy, store = account.legacyShared, char.data
    local firstHere = {}   -- paths parked by this very load
    for path in self:Each("charData") do
        if not account.charSplit[path] then
            local v = getPath(account, path)
            if v ~= nil then legacy[path] = v; setPath(account, path, nil) end
            account.charSplit[path] = true
            firstHere[path] = true
        end
    end
    for path, def in self:Each("charData") do
        if not char.adopted[path] and not def.later then
            -- once = true: only the character loaded when the old shared data
            -- was parked takes it (whose hides and keeps they were); every
            -- other character starts fresh. The parked copy stays as it was.
            local adoptable = not def.once or firstHere[path]
            if store[path] == nil and adoptable then store[path] = adoptOne(path, def, legacy[path], ctx) end
            char.adopted[path] = true
        end
        setPath(account, path, store[path])
    end
end

-- At login: adoption that needs the game ready, merged into the live value.
function ns:AdoptLaterCharacterData(account, char, ctx)
    local legacy = account.legacyShared or {}
    for path, def in self:Each("charData") do
        if def.later and not char.adopted[path] then
            local keep = adoptOne(path, def, legacy[path], ctx, getPath(account, path))
            -- false = the game isn't ready to tell yet: try again next login.
            if keep ~= false then
                if keep ~= nil then setPath(account, path, keep) end
                char.adopted[path] = true
            end
        end
    end
end

-- At logout: this character's data back to FlowCharDB, out of FlowDB.
function ns:StoreCharacterData(account, char)
    char.data = char.data or {}
    for path in self:Each("charData") do
        char.data[path] = getPath(account, path)
        setPath(account, path, nil)
    end
end
ns._getPath, ns._setPath = getPath, setPath   -- (tests)

-------------------------------------------------------------------------------
-- Saved-data migrations (F-014). A change to the shape of saved data is a
-- registration, not an ad hoc "if old then" in a module's OnLoad:
--   ns:Register("migration", "0.36-nav-arrows", { order = 3, run = function(db) ... end })
-- Each runs once per account, in `order` (then key), before any module's
-- OnLoad, on FlowDB as saved. FlowDB.migrations[key] = true once it has run,
-- so it never runs twice, and one added out of order still runs. A key is
-- never reused or renamed. One that errors isn't marked: it's logged and
-- tried again at the next load. A fresh install has nothing to convert: every
-- migration is marked done without running. FlowDB.version: the highest
-- `order` applied (for the diagnostics).
-------------------------------------------------------------------------------

-- Pure apart from the registrations: returns the keys it ran, in order, and
-- "key: error" for each that failed.
-- list: { { key, value = { order, run } } } (default: the registrations).
function ns:RunMigrations(db, fresh, list)
    db.migrations = db.migrations or {}
    if not list then
        list = {}
        for key, m in self:Each("migration") do list[#list + 1] = { key = key, value = m } end
    end
    table.sort(list, function(a, b)
        local oa, ob = a.value.order or 0, b.value.order or 0
        if oa ~= ob then return oa < ob end
        return tostring(a.key) < tostring(b.key)
    end)
    local ran, failed = {}, {}
    for _, e in ipairs(list) do
        if not db.migrations[e.key] then
            local ok, err = true, nil
            if not fresh then ok, err = pcall(e.value.run, db) end
            if ok then
                db.migrations[e.key] = true
                db.version = math.max(db.version or 0, e.value.order or 0)
                if not fresh then ran[#ran + 1] = e.key end
            else
                failed[#failed + 1] = tostring(e.key) .. ": " .. tostring(err)
            end
        end
    end
    return ran, failed
end

-- ns:OnLoad(fn): run fn once saved variables (ns.db) are available.
local loaders = {}
function ns:OnLoad(fn)
    table.insert(loaders, fn)
end

ns:On("ADDON_LOADED", function(name)
    if name ~= ADDON_NAME then return end
    ns.freshInstall = (FlowDB == nil)   -- first time with Flow (Reveal.lua: a gentle start)
    FlowDB = FlowDB or {}
    FlowCharDB = FlowCharDB or {}
    ns.db, ns.charDb = FlowDB, FlowCharDB
    local splitOk, splitErr = pcall(ns.SplitCharacterData, ns, FlowDB, FlowCharDB, context())
    if not splitOk then print("|cffff5555Flow load error|r (character data): " .. tostring(splitErr)) end
    local migOk, ranOrErr, failed = pcall(ns.RunMigrations, ns, FlowDB, ns.freshInstall)
    for _, f in ipairs(migOk and failed or { tostring(ranOrErr) }) do
        print("|cffff5555Flow load error|r (saved data update): " .. f)
        logError("migration", f)
    end
    for _, fn in ipairs(loaders) do
        local ok, err = pcall(fn, ns.db)
        if not ok then
            print("|cffff5555Flow load error|r: " .. tostring(err))
            logError("load", err)
        end
    end
end)

ns:On("PLAYER_LOGIN", function()
    if not (ns.db and ns.charDb) then return end
    ns:AdoptLaterCharacterData(ns.db, ns.charDb, context())
end)

-- Tooltips where WoW shows its own: the spot you set in Edit Mode or the
-- interface options (bottom right by default, or at the cursor), not beside
-- whatever you hovered. Setting: "Tooltips where WoW shows them" (on); off,
-- each one opens next to what you hover (`anchor`, e.g. "ANCHOR_RIGHT").
-- Saved inverted (settings.tipsBeside, unset = on): read and write it only here.
function ns.TipsAtGameSpot() return not (ns.db and ns.db.settings and ns.db.settings.tipsBeside) end
function ns.SetTipsAtGameSpot(on) ns.db.settings.tipsBeside = not on end

-- Room for the words (0.35.261). Flow's longer explanations are wrapped
-- lines, and the game wraps those to a narrow box: a column of short ragged
-- lines. A tooltip Flow opens is given a width that sentences fit in; the
-- width goes back to the game's own when it closes (it's the game's tooltip).
ns.TIP_WIDTH = 340
local widened = {}
function ns.WidenTip(tooltip)
    if not (tooltip and tooltip.SetMinimumWidth) then return false end
    if not widened[tooltip] and tooltip.HookScript then
        widened[tooltip] = true
        tooltip:HookScript("OnHide", function(self) if self.SetMinimumWidth then self:SetMinimumWidth(0) end end)
    end
    tooltip:SetMinimumWidth(ns.TIP_WIDTH)
    return true
end
function ns.Tip(owner, anchor, tooltip)
    tooltip = tooltip or GameTooltip
    pcall(ns.WidenTip, tooltip)
    if ns.TipsAtGameSpot() and GameTooltip_SetDefaultAnchor then
        GameTooltip_SetDefaultAnchor(tooltip, owner)
    else
        tooltip:SetOwner(owner, anchor or "ANCHOR_RIGHT")
    end
    return tooltip
end

-- Put a Flow card (the step card, the arrow's drawer) where WoW puts its
-- tooltips. False when there's no fixed spot (tooltips at the cursor) or the
-- setting is off: the caller places it its own way.
function ns.PlaceAtTipSpot(frame, owner)
    if not (ns.TipsAtGameSpot() and GameTooltip_SetDefaultAnchor and GameTooltip) then return false end
    local ok = pcall(GameTooltip_SetDefaultAnchor, GameTooltip, owner or UIParent)
    local point, rel, relPoint, x, y
    if ok and GameTooltip:GetNumPoints() > 0 then point, rel, relPoint, x, y = GameTooltip:GetPoint(1) end
    GameTooltip:Hide()
    if not (point and rel) then return false end
    frame:ClearAllPoints()
    frame:SetPoint(point, rel, relPoint, x, y)
    return true
end

-- The key you hold to move any Flow element: Ctrl, as in Questie (0.35.138;
-- it was Shift, which now shows what Shift + your key casts). Every move
-- asks this one function, so it's one place to change.
ns.MOVE_KEY = "Ctrl"
function ns.MoveKeyDown() return IsControlKeyDown() and true or false end

-- ns:MakeMovable(frame, save, clickable): every Flow element moves the same
-- way: hold Ctrl and drag. Position is stored in save.point. Frames that
-- aren't clickable only take the mouse while Ctrl is held, so they never
-- block clicks in a fight.
local passive = {}
function ns:MakeMovable(frame, save, clickable)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        if ns.MoveKeyDown() then self:StartMoving() end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local a, _, b, x, y = self:GetPoint()
        save.point = { a, b, x, y }
    end)
    if not clickable then
        frame:EnableMouse(false)
        passive[#passive + 1] = frame
    end
end

do
    local watcher, heldWas = CreateFrame("Frame"), false
    watcher:SetScript("OnUpdate", function()
        local held = ns.MoveKeyDown()
        if held == heldWas then return end
        heldWas = held
        for _, f in ipairs(passive) do f:EnableMouse(held) end
    end)
end

-- /flow api: what this game client lets addons do. Useful because Forever is
-- a new client and its restrictions aren't documented yet.
local function apiReport(arg)
    ns.db.api = ns.db.api or {}
    local a, b = (arg or ""):match("^(%S*)%s*(%S*)")
    if a == "combatlog" and (b == "on" or b == "off" or b == "auto") then
        if b == "auto" then ns.db.api.combatLog = nil else ns.db.api.combatLog = (b == "on") end
        ns:Print("combat log use set to " .. b .. ". /reload to apply.")
        return
    end
    local function has(v) return v ~= nil and "yes" or "no" end
    local Safe = ns.api and ns.api.Safe or function(v) return v end
    local function shown(v)
        if v == nil then return "nil" end
        if Safe(v) == nil then return "HIDDEN (secret)" end
        return tostring(v)
    end
    ns:Print("client check:")
    print("  build: " .. tostring((select(1, GetBuildInfo()))) .. " interface " .. tostring((select(4, GetBuildInfo()))))
    print("  secret values: " .. has(issecretvalue))
    print("  combat log function: " .. has(CombatLogGetCurrentEventInfo)
        .. ", Flow uses it: " .. tostring(ns.api and ns.api.CombatLogAllowed()))
    print("  damage meter API: " .. has(C_DamageMeter))
    -- Health is hidden from add-ons here; these say whether anything else
    -- could tell Flow how hurt you are (for the after-fight heal).
    if C_DamageMeter then
        local names = {}
        for k in pairs(C_DamageMeter) do names[#names + 1] = tostring(k) end
        table.sort(names)
        print("    damage meter functions: " .. table.concat(names, ", "))
    end
    local okBar, bar = pcall(function()
        local hb = PlayerFrame and (PlayerFrame.healthbar or (PlayerFrame.PlayerFrameContent and PlayerFrame.PlayerFrameContent.PlayerFrameContentMain
            and PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer
            and PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer.HealthBar))
        return hb and hb:GetValue()
    end)
    local okPct, pct = pcall(function() return UnitHealthPercent and UnitHealthPercent("player") end)
    print("  health bar value: " .. (okBar and shown(bar) or "error") .. ", UnitHealthPercent: " .. has(UnitHealthPercent)
        .. (UnitHealthPercent and (" = " .. (okPct and shown(pct) or "error")) or ""))
    local low = ns.api and ns.api.LowHealthWarning and ns.api.LowHealthWarning()
    print("  low-health warning: " .. (low == nil and "not readable" or tostring(low))
        .. ", stunned etc: " .. tostring(ns.api and ns.api.LossOfControl and ns.api.LossOfControl() or "no")
        .. ", auto attack on: " .. tostring(ns.api and ns.api.Swinging and ns.api.Swinging()))
    print("  C_Spell: " .. has(C_Spell) .. ", C_SpellBook: " .. has(C_SpellBook) .. ", C_Container: " .. has(C_Container))
    -- Anything this client says about height (is the next step above or below
    -- you?): the names in the game's map and navigation tables that sound like it.
    do
        local found = {}
        for _, name in ipairs({ "C_Minimap", "C_Navigation", "C_SuperTrack", "C_QuestLog", "C_Map", "C_TaskQuest" }) do
            local tbl = _G[name]
            if type(tbl) == "table" then
                for k in pairs(tbl) do
                    local word = type(k) == "string" and k:lower() or ""
                    if word:find("height") or word:find("floor") or word:find("vertical") or word:find("elevat")
                        or word:find("above") or word:find("below") or word:find("navigation") or word:find("supertrack") then
                        found[#found + 1] = name .. "." .. k
                    end
                end
            end
        end
        table.sort(found)
        print("  about height or floors (names only): " .. (#found > 0 and table.concat(found, ", "):sub(1, 600) or "nothing by those names"))
    end
    -- The game's own marker in the world for a tracked spot (C_Navigation):
    -- if this client has it, where it sits on screen tells above from below
    -- (0.35.303: "can we have an elevation arrow?"). Names and what they
    -- answer now, nothing set or changed.
    do
        local nav = _G.C_Navigation
        if type(nav) ~= "table" then
            print("  world marker (C_Navigation): no")
        else
            local names = {}
            for k in pairs(nav) do if type(k) == "string" then names[#names + 1] = k end end
            table.sort(names)
            print("  world marker (C_Navigation): " .. table.concat(names, ", "):sub(1, 300))
            local okF, f = pcall(function() return nav.GetFrame and nav.GetFrame() end)
            local okD, d = pcall(function() return nav.GetDistance and nav.GetDistance() end)
            local okV, v = pcall(function() return nav.HasValidScreenPosition and nav.HasValidScreenPosition() end)
            local where = "none"
            if okF and f and f.GetCenter then
                local okC, x, y = pcall(f.GetCenter, f)
                where = okC and x and string.format("%.0f, %.0f (screen %.0f high)", x, y, UIParent:GetHeight() or 0) or "hidden from add-ons"
            end
            local tracking = _G.C_SuperTrack and C_SuperTrack.IsSuperTrackingAnything and select(2, pcall(C_SuperTrack.IsSuperTrackingAnything))
            print(string.format("    tracking anything: %s; its frame: %s at %s; distance: %s; on screen: %s",
                tostring(tracking), okF and f and "yes" or "no", where, okD and tostring(d) or "error", okV and tostring(v) or "error"))
            print("    a spot of your own can be tracked: C_Map.SetUserWaypoint " .. has(C_Map and C_Map.SetUserWaypoint)
                .. ", C_SuperTrack.SetSuperTrackedUserWaypoint " .. has(_G.C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint))
        end
    end
    print("  quest waypoints: " .. has(C_QuestLog and C_QuestLog.GetNextWaypoint)
        .. ", equipment manager: " .. has(C_EquipmentSet and C_EquipmentSet.GetEquipmentSetIDs))
    print("  your health: " .. shown(UnitHealth("player")) .. ", facing: " .. shown(GetPlayerFacing and GetPlayerFacing()))
    -- Heights: does this client give addons a height (z)? Needed for up/down hints.
    local okP, y, x, z = pcall(UnitPosition, "player")
    print("  position: " .. (okP and (shown(y) .. ", " .. shown(x) .. ", height " .. shown(z)) or "not available")
        .. ", indoors: " .. tostring(IsIndoors and IsIndoors()))
    if UnitExists("target") then print("  target health: " .. shown(UnitHealth("target"))) end
    print("  /flow api combatlog on|off|auto")
end

-- /flow slash command; modules can add subcommands to ns.commands.
ns.commands = { api = apiReport }
SLASH_FLOW1 = "/flow"
SlashCmdList.FLOW = function(input)
    local cmd, rest = (input or ""):match("^(%S*)%s*(.-)$")
    cmd = cmd:lower()
    local fn = ns.commands[cmd]
    if fn then
        fn(rest)
    elseif ns.commands.help then
        ns.commands.help()
    else
        ns:Print("commands:")
        for name in pairs(ns.commands) do
            print("  /flow " .. name)
        end
    end
end
