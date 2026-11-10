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

frame:SetScript("OnEvent", function(_, event, ...)
    for _, fn in ipairs(handlers[event] or {}) do
        local ok, err = pcall(fn, ...)
        if not ok then
            print("|cffff5555Flow error|r (" .. event .. "): " .. tostring(err))
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

-------------------------------------------------------------------------------
-- Per-character data. FlowDB is shared by every character on the account
-- (settings, learned trails, NPC places). Anything about one character (its
-- fights, class trainer, recipes, hidden stops...) is declared per character
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
-- yet", and it's tried again at the next login.
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
    for path in self:Each("charData") do
        if not account.charSplit[path] then
            local v = getPath(account, path)
            if v ~= nil then legacy[path] = v; setPath(account, path, nil) end
            account.charSplit[path] = true
        end
    end
    for path, def in self:Each("charData") do
        if not char.adopted[path] and not def.later then
            if store[path] == nil then store[path] = adoptOne(path, def, legacy[path], ctx) end
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
    for _, fn in ipairs(loaders) do
        local ok, err = pcall(fn, ns.db)
        if not ok then
            print("|cffff5555Flow load error|r: " .. tostring(err))
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
function ns.TipsAtGameSpot() return not (ns.db and ns.db.settings and ns.db.settings.tipsBeside) end

function ns.Tip(owner, anchor, tooltip)
    tooltip = tooltip or GameTooltip
    if ns.TipsAtGameSpot() and GameTooltip_SetDefaultAnchor then
        GameTooltip_SetDefaultAnchor(tooltip, owner)
    else
        tooltip:SetOwner(owner, anchor or "ANCHOR_RIGHT")
    end
    return tooltip
end

-- Put a Flow card (the stop card, the arrow's drawer) where WoW puts its
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

-- ns:MakeMovable(frame, save, clickable): every Flow element moves the same
-- way: hold Shift and drag. Position is stored in save.point. Frames that
-- aren't clickable only take the mouse while Shift is held, so they never
-- block clicks in a fight.
local passive = {}
function ns:MakeMovable(frame, save, clickable)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        if IsShiftKeyDown() then self:StartMoving() end
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
    local watcher, shiftWas = CreateFrame("Frame"), false
    watcher:SetScript("OnUpdate", function()
        local shift = IsShiftKeyDown() and true or false
        if shift == shiftWas then return end
        shiftWas = shift
        for _, f in ipairs(passive) do f:EnableMouse(shift) end
    end)
end

-- Sizes a button can take with Ctrl + mouse wheel: half to double size, in
-- steps of a tenth. ClampScale rounds to the nearest 5 % and keeps it in range.
ns.SCALE_MIN, ns.SCALE_MAX, ns.SCALE_STEP = 0.5, 2, 0.1
function ns.ClampScale(s)
    s = tonumber(s) or 1
    s = math.floor(s * 20 + 0.5) / 20
    return math.max(ns.SCALE_MIN, math.min(ns.SCALE_MAX, s))
end

-- ns:MoveHandle(target, opts): moving and resizing a secure button (the
-- Flow button, the buff button). Out of combat, hold Shift and a "drag to
-- move" handle appears over it; hold Ctrl and the same handle resizes it
-- with the mouse wheel. Dragging the secure button itself didn't work (it
-- takes the press as a click), and a secure button can't move or change
-- size in a fight, so the handle does both, and only out of combat.
-- opts.name: what it's called in the tooltip ("the Flow button").
-- opts.save: table (or function returning it) where .point and .scale go.
-- opts.also: function returning frames that resize along with it.
-- opts.onDone: called after each move or resize.
local handles = {}
function ns:MoveHandle(target, opts)
    local h = CreateFrame("Frame", nil, UIParent)
    h.target, h.opts = target, opts
    h:SetFrameStrata("DIALOG")
    h:EnableMouse(true)
    h:EnableMouseWheel(true)
    h.bg = h:CreateTexture(nil, "BACKGROUND")
    h.bg:SetAllPoints()
    h.edge = {}
    local o = ns.theme.arrow
    for i, pts in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" },
                           { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
        local t = h:CreateTexture(nil, "BORDER")
        t:SetPoint(pts[1]); t:SetPoint(pts[2])
        if i <= 2 then t:SetHeight(2) else t:SetWidth(2) end
        h.edge[i] = t
    end
    -- The label sits ABOVE the button (under it is the button's own text,
    -- which it would cover), on a small dark tab so it reads.
    h.text = h:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    h.text:SetPoint("BOTTOM", h, "TOP", 0, 4)
    h.tab = h:CreateTexture(nil, "BACKGROUND")
    h.tab:SetPoint("TOPLEFT", h.text, "TOPLEFT", -4, 2)
    h.tab:SetPoint("BOTTOMRIGHT", h.text, "BOTTOMRIGHT", 4, -2)
    h.tab:SetColorTexture(0, 0, 0, 0.6)

    -- Hover: it lights up, so it's clear you can grab it.
    function h:Paint(hot)
        self.bg:SetColorTexture(o[1], o[2], o[3], hot and 0.35 or 0.12)
        for _, t in ipairs(self.edge) do t:SetColorTexture(o[1], o[2], o[3], hot and 1 or 0.7) end
        self.text:SetTextColor(hot and 1 or o[1], hot and 1 or o[2], hot and 1 or o[3])
    end
    function h:Label()
        local parts = {}
        if IsShiftKeyDown() then parts[#parts + 1] = "drag to move" end
        if IsControlKeyDown() then
            parts[#parts + 1] = string.format("wheel to resize (%d%%)", math.floor(target:GetScale() * 100 + 0.5))
        end
        self.text:SetText(table.concat(parts, " · "))
    end
    -- Show while Shift or Ctrl is held (out of combat, button on screen).
    function h:Refresh()
        local want = (IsShiftKeyDown() or IsControlKeyDown()) and not InCombatLockdown() and target:IsShown()
        if want then
            self:ClearAllPoints()
            self:SetAllPoints(target)
            self:Label()
            self:Show()
        elseif not self.moving then
            self:Hide()
        end
    end
    -- Remember the spot by the button's centre on the screen, so it no
    -- longer depends on whatever it was first attached to.
    function h:Save()
        local x, y = target:GetCenter()
        if not x then return end
        target:ClearAllPoints()
        target:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
        local save = type(opts.save) == "function" and opts.save() or opts.save
        save.point = { "CENTER", "BOTTOMLEFT", x, y }
        save.scale = target:GetScale()
        if opts.onDone then opts.onDone() end
    end
    -- A drag still going when a fight starts is finished at the start of the
    -- fight (still allowed then); a release during the fight does nothing.
    function h:Finish()
        if not self.moving or InCombatLockdown() then return end
        self.moving = false
        target:StopMovingOrSizing()
        self:Save()
    end
    -- One wheel notch with Ctrl held: a tenth bigger or smaller.
    function h:Resize(delta)
        if IsControlKeyDown() then self:ScaleBy(delta) end
    end
    -- Resize keeping the centre still on the screen.
    function h:ScaleBy(delta)
        if InCombatLockdown() then return end
        local old = target:GetScale()
        local new = ns.ClampScale(old + (delta > 0 and ns.SCALE_STEP or -ns.SCALE_STEP))
        if new == old then return end
        local x, y = target:GetCenter()
        target:SetScale(new)
        for _, f in ipairs(opts.also and opts.also() or {}) do f:SetScale(new) end
        if x then
            target:ClearAllPoints()
            target:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x * old / new, y * old / new)
        end
        self:Save()
        self:Label()
    end

    h:Paint(false)
    h:SetScript("OnEnter", function(self)
        self:Paint(true)
        pcall(SetCursor, "UI_MOVE_CURSOR")
        ns.Tip(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Move or resize " .. (opts.name or "this button"), 1, 1, 1)
        GameTooltip:AddLine("Shift: drag to move. Ctrl: mouse wheel to resize.", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("Let go of the key to use it again.", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    h:SetScript("OnLeave", function(self)
        self:Paint(false)
        pcall(ResetCursor)
        GameTooltip:Hide()
    end)
    h:SetScript("OnMouseDown", function(self)
        if InCombatLockdown() or not IsShiftKeyDown() then return end
        target:StartMoving()
        self.moving = true
    end)
    h:SetScript("OnMouseUp", function(self) self:Finish() end)
    h:SetScript("OnMouseWheel", function(self, delta) self:Resize(delta) end)
    h:Hide()
    target:SetMovable(true)
    target:SetClampedToScreen(true)
    handles[#handles + 1] = h
    return h
end

-- Put a button back where and at the size you left it (x0, y0: the default
-- spot from the screen centre).
function ns.RestorePlace(frame, save, x0, y0)
    frame:SetScale(ns.ClampScale(save.scale or 1))
    local p = save.point
    frame:ClearAllPoints()
    if p then frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else frame:SetPoint("CENTER", UIParent, "CENTER", x0 or 0, y0 or 0) end
end

ns:On("MODIFIER_STATE_CHANGED", function()
    for _, h in ipairs(handles) do h:Refresh() end
end)
ns:On("PLAYER_REGEN_DISABLED", function()
    for _, h in ipairs(handles) do h:Finish(); h.moving = false; h:Hide() end
end)

-- /flow api: what this game client lets addons do. Useful because Forever is
-- a new client and its restrictions aren't documented yet.
local function apiReport(arg)
    ns.db.api = ns.db.api or {}
    local a, b = (arg or ""):match("^(%S*)%s*(%S*)")
    if a == "height" then
        if ns.heightProbe then ns.heightProbe:Run(b) else ns:Print("height probe not loaded: restart the game") end
        return
    end
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
    print("  quest waypoints: " .. has(C_QuestLog and C_QuestLog.GetNextWaypoint)
        .. ", equipment manager: " .. has(C_EquipmentSet and C_EquipmentSet.GetEquipmentSetIDs))
    print("  your health: " .. shown(UnitHealth("player")) .. ", facing: " .. shown(GetPlayerFacing and GetPlayerFacing()))
    -- Heights: does this client give addons a height (z)? Needed for up/down hints.
    local okP, y, x, z = pcall(UnitPosition, "player")
    print("  position: " .. (okP and (shown(y) .. ", " .. shown(x) .. ", height " .. shown(z)) or "not available")
        .. ", indoors: " .. tostring(IsIndoors and IsIndoors()))
    if UnitExists("target") then print("  target health: " .. shown(UnitHealth("target"))) end
    print("  /flow api combatlog on|off|auto   /flow api height [pin|watch]")
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
