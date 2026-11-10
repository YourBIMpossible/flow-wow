-- Diagnostics Claude can read from disk. WoW only lets addons write their
-- saved data (WTF\Account\<name>\SavedVariables\Flow.lua), and only writes it
-- on /reload, logout or exit. So Flow keeps:
--   FlowDB.diag.log       recent Flow errors and notable events (newest last)
--   FlowDB.diag.snapshot  what /flow api, nav why, rot why and key test say,
--                         taken automatically on every /reload and logout
-- /flow dump takes a snapshot now (then /reload to write it to disk).
-- Read it with tools\read-diag.ps1.

local _, ns = ...
local D = {}
ns.diag = D

local MAX_LINES = 400

local function db() return ns.db and ns.db.diag end

function ns:Log(category, msg)
    local d = db()
    if not d then return end
    local line = string.format("%s [%s] %s", date("%H:%M:%S"), category or "?", tostring(msg))
    local log = d.log
    if log[#log] == line then return end  -- don't flood with repeats
    log[#log + 1] = line
    while #log > MAX_LINES do table.remove(log, 1) end
end

-- Runs Flow's check commands with chat output captured into a list.
-- Uses the game's print-handler hook (made for this), so nothing global is
-- replaced and the output doesn't appear in chat.
local function capture(fn)
    local lines = {}
    if not (getprinthandler and setprinthandler) then
        local ok, err = pcall(fn)
        if not ok then lines[#lines + 1] = "ERROR: " .. tostring(err) end
        lines[#lines + 1] = "(this client can't capture chat output)"
        return lines
    end
    local previous = getprinthandler()
    setprinthandler(function(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
        -- Strip colour codes so the file is easy to read.
        lines[#lines + 1] = (table.concat(parts, " "):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
    end)
    local ok, err = pcall(fn)
    setprinthandler(previous)
    if not ok then lines[#lines + 1] = "ERROR: " .. tostring(err) end
    return lines
end

local clock = debugprofilestop

-- `spread`: one check per frame, so the after-login snapshot never stalls
-- the game (all 13 checks plus the self-tests in one frame did). At logout
-- it runs all at once: the game writes the saved data straight after.
-- Each check's time goes in its heading, and a slow snapshot is logged.
function D:Snapshot(reason, spread)
    local d = db()
    if not d then return end
    D.gen = (D.gen or 0) + 1
    local gen = D.gen
    local c = ns.commands
    local _, class = UnitClass("player")
    local out = { "taken " .. date("%Y-%m-%d %H:%M:%S") .. " (" .. (reason or "?") .. ")",
                  "character " .. tostring(UnitName("player")) .. " (" .. tostring(class) .. ")"
                      .. ", version " .. (ns.Version and ns.Version() or "?") .. ", level " .. tostring(UnitLevel("player"))
                      .. ", zone " .. tostring(GetZoneText and GetZoneText()) }
    local checks = {
        { "api", function() c.api("") end },
        { "nav why", function() c.nav("why") end },
        { "places", function() if c.places then c.places() end end },
        -- At logout the game reports nothing as castable (health 0/0), so the
        -- rotation check from while you were playing is the one kept.
        { "rot why", function()
            if reason == "reload or logout" and D.lastRot then
                print("(read while playing, at " .. D.lastRot.at .. ")")
                for _, l in ipairs(D.lastRot.lines) do print(l) end
            else c.rot("why") end
        end },
        { "key test", function() c.key("test") end },
        { "party", function() c.party("") end },
        { "gear why", function() c.gear("why") end },
        { "prof plan", function() c.professions("plan") end },
        { "talents", function() c.talents() end },
        { "flow action", function() c.action("") end },
        { "perf", function() c.perf("quick") end },
        { "tests", function()
            -- After login: the run from 8 s after login, not a second one.
            local r = spread and ns.lastTestRun
            if r then
                print(string.format("(run at %s, %.0f ms) tests: %d passed, %d failed (%d checks)",
                    r.at, r.ms, r.passed, r.failed, r.checks))
                for _, l in ipairs(r.out) do print(l) end
            else c.test("") end
        end },
    }
    local i, total, slowName, slowMs = 0, 0, nil, 0
    local function step()
        if gen ~= D.gen then return end  -- a newer snapshot took over
        i = i + 1
        local chk = checks[i]
        if not chk then
            out[2] = out[2] .. string.format(", snapshot took %.0f ms", total)
            d.snapshot = out
            if total > 50 then
                ns:Log("perf", string.format("snapshot (%s) took %.0f ms, slowest %s %.0f ms%s", reason or "?",
                    total, tostring(slowName), slowMs, spread and " (one check per frame)" or ""))
            end
            return
        end
        local t0 = clock and clock()
        local lines = capture(chk[2])
        local ms = t0 and (clock() - t0) or 0
        total = total + ms
        if ms > slowMs then slowName, slowMs = chk[1], ms end
        out[#out + 1] = string.format("--- %s (%.1f ms)", chk[1], ms)
        for _, l in ipairs(lines) do out[#out + 1] = l end
        if spread then C_Timer.After(0, step) end
    end
    if spread then step() return end
    while gen == D.gen and i <= #checks do step() end
end

-- Lua errors from Flow's own files go into the log (and still show as usual).
local function hookErrors()
    if not (geterrorhandler and seterrorhandler) then return end
    local previous = geterrorhandler()
    seterrorhandler(function(err, ...)
        local s = tostring(err)
        if s:find("AddOns[/\\]Flow[/\\]") or s:find("Flow\\Modules") or s:find("Flow/Modules") then
            pcall(ns.Log, ns, "lua error", s)
        end
        if previous then return previous(err, ...) end
    end)
end

ns:OnLoad(function(saved)
    saved.diag = saved.diag or {}
    saved.diag.log = saved.diag.log or {}
    hookErrors()
    ns:Log("session", "loaded v" .. (ns.Version and ns.Version() or "?"))
end)

-- Fresh snapshot right before the game writes the saved data (reload/logout).
ns:On("PLAYER_LOGOUT", function() D:Snapshot("reload or logout") end)
-- After a login or /reload only, not every loading screen (it ran after
-- each dungeon, boat and zone change too).
ns:On("PLAYER_ENTERING_WORLD", function(isLogin, isReload)
    if not (isLogin or isReload) then return end
    C_Timer.After(10, function() pcall(D.Snapshot, D, "after login", true) end)
end)
-- The rotation check, read once a minute while you're playing (out of
-- combat, alive) for the snapshot taken at logout.
C_Timer.NewTicker(60, function()
    if InCombatLockdown() or UnitIsDeadOrGhost("player") or not ns.commands.rot then return end
    D.lastRot = { at = date("%H:%M:%S"), lines = capture(function() ns.commands.rot("why") end) }
end)

ns.commands.dump = function()
    D:Snapshot("/flow dump")
    ns:Print("diagnostics captured. /reload (or log out) to write them to disk for Claude.")
end

ns:Register("help", "diag", { order = 90, title = "Diagnostics", lines = {
    "/flow dump - capture Flow's checks for Claude to read (then /reload). Also automatic on every /reload.",
} })

-------------------------------------------------------------------------------
-- Blocked actions ("Flow has been blocked from an action only available to
-- the Blizzard UI"). The game fires ADDON_ACTION_BLOCKED / _FORBIDDEN with
-- the add-on it blames and the protected function. Flow logs every one,
-- whichever add-on is blamed, so tools\read-diag.ps1 shows them under
-- "Blocked actions", with what you were doing at the time.
--
-- The blamed add-on is the one whose code *tainted* the path, which can be
-- long before the error. To find where, developer installs (Flow.toc has
-- "## X-Flow-Dev: 1"; tools\package.ps1 removes it from releases) turn on
-- the game's taint log (Logs\taint.log), which read-diag.ps1 also reads.
-------------------------------------------------------------------------------

D.blocked = {}

local function context()
    local bits = {}
    if InCombatLockdown() then bits[#bits + 1] = "in combat" end
    for _, name in ipairs({ "GameMenuFrame", "SettingsPanel", "WorldMapFrame", "QuestLogFrame",
                            "FlowStopCard", "FlowNavPanel", "FlowSetup", "FlowSettings" }) do
        local f = _G[name]
        if f and f.IsShown and f:IsShown() then bits[#bits + 1] = name .. " open" end
    end
    return #bits > 0 and table.concat(bits, ", ") or "nothing special open"
end

local function onBlocked(kind)
    return function(addon, func)
        local line = string.format("%s: %s blamed for %s (%s) [v%s]", kind, tostring(addon), tostring(func), context(),
            ns.Version and ns.Version() or "?")
        ns:Log("blocked", line)
        local d = db()
        if d then
            d.blocked = d.blocked or {}
            table.insert(d.blocked, { at = date("%Y-%m-%d %H:%M:%S"), kind = kind, addon = tostring(addon),
                func = tostring(func), context = context(), version = ns.Version and ns.Version() or "?" })
            while #d.blocked > 50 do table.remove(d.blocked, 1) end
        end
    end
end
ns:On("ADDON_ACTION_BLOCKED", onBlocked("BLOCKED"))
ns:On("ADDON_ACTION_FORBIDDEN", onBlocked("FORBIDDEN"))
D._onBlocked = onBlocked  -- (tests)

function D:IsDev()
    local meta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local ok, v = pcall(meta, "Flow", "X-Flow-Dev")
    return ok and v == "1"
end

ns:On("PLAYER_LOGIN", function()
    if D:IsDev() and GetCVar and SetCVar then
        local ok, v = pcall(GetCVar, "taintLog")
        if ok and v ~= "1" and v ~= "2" then pcall(SetCVar, "taintLog", "1") end
    end
end)
