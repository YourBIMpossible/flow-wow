local _, ns = ...
-- Your threat on each enemy's nameplate (S8, lead section 178;
-- WoW/from-lazy/RESEARCH-S8.md). Ported from legacy Flow 0.35.377
-- (Modules/PlateThreat.lua): in a fight, in a group or with a pet out,
-- every enemy nameplate whose threat list you are on gets a small number at
-- its right: your threat share, coloured by where you stand.
--   tanking (the tank role, or a bear)   green: on you; orange: on you but
--             someone has more; yellow: not on you, you have more; red: not
--             on you
--   anyone else, by the share itself     calm < 50 <= mid < 90 <= high
--             < 100 <= over (over pulses)
--   a share the game hides               by the status when that is plain,
--             else white
-- Differences from legacy Flow (lead section 178): your own share only, so
-- "who is closest behind" is gone (no party unit is read); no product name
-- in what the player reads.
--
-- THE DISPLAY SINK (option A). The game may hide threat shares from addons
-- in a fight. Then the client handle writes the share onto its own label
-- and this module is told only "hidden": the value never comes here, and
-- nothing here compares or adds it. A plain share comes back as a number,
-- so the colours and the tests work on it.
--
-- LOOK ONLY: nothing clicks, targets, casts or writes a CVar; no frame is
-- secure. The client reads (Core/Client.lua, S8) are FIRST GUESSES, not seen
-- in game on 1.60.1:
--   client.plates(fn), client.canAttack(unit), client.grouped(),
--   client.plateLabel(unit) with h.threat(), client.petGUID(),
--   client.unitBuff("player", PT.BEAR) for a bear. There is no read of the
--   form's name (client.form() is only a number), so a bear is told by its
--   form's buff, as Classes/Druid.lua names the forms.
--
-- Pure:
--   PT.Band(pct) -> "calm" | "mid" | "high" | "over" | nil
--   PT.Look(state, pct, tank) -> colour key, flash
--   PT.State(status, tank) -> "safe" | "losing" | "pulling" | "lost"
--                           | "danger" | "low" | "hidden"
--   PT.Text(pct) -> "85%" | ""
--   PT.Tanking(role, bear) -> true | false   a role not known is not tank
--   PT.Wanted(on, always, grouped, pet) -> true | false
-- PT.Declare(k, diag) -> api
--   api.status() -> { on, always, wanted, tanking, fighting, inView, shown, last }
--     last: "shown", "hidden", "unknown", or nil before the first read
--   api.lines()   what the word PT.WORD prints
-- Settings (account): plateThreat.off, plateThreat.always (the import
-- targets in Import/FromFlow.lua; rows in Settings/Model.lua).
-- Not tested in game.
local PT = {}
ns.PlateThreat = PT

PT.NAME = "plateThreat"
PT.WORD = "threat"
PT.HELP = "your threat on enemy nameplates: what shows and why; threat on or threat off switches it"
PT.OFF = "plateThreat.off"
PT.ALWAYS = "plateThreat.always"
-- When it appears, in one line (lead section 296): its settings row and the
-- buttons word say it, so a player who sees nothing can find out why.
PT.WHEN = "Shows in a fight when you are in a group or have a pet out; tick \"when alone too\" for solo fights."
PT.ROLE = "spec.role"           -- Rotation/Role.lua's setting
PT.TICK = 0.5                   -- seconds between looks, only in a fight
PT.OVER, PT.HIGH, PT.MID = 100, 90, 50
PT.BEAR = { "Bear Form", "Dire Bear Form" }
PT.WORDS = { shown = "shown", hidden = "hidden by the game", unknown = "not known" }

-- As legacy Flow.
PT.COLORS = {
    over    = { 1.00, 0.15, 0.15 },
    high    = { 1.00, 0.25, 0.25 },
    mid     = { 1.00, 0.90, 0.20 },
    calm    = { 0.35, 1.00, 0.35 },
    safe    = { 0.35, 1.00, 0.35 },
    losing  = { 1.00, 0.55, 0.10 },
    pulling = { 1.00, 0.90, 0.20 },
    lost    = { 1.00, 0.25, 0.25 },
    danger  = { 1.00, 0.25, 0.25 },
    low     = { 0.75, 0.75, 0.75 },
    hidden  = { 1.00, 1.00, 1.00 },
}

function PT.Band(pct)
    if type(pct) ~= "number" then return nil end
    if pct >= PT.OVER then return "over" end
    if pct >= PT.HIGH then return "high" end
    if pct >= PT.MID then return "mid" end
    return "calm"
end

-- tank: the tank colours, by state. Else by the share's band; a share not
-- known (hidden) goes by the state.
function PT.Look(state, pct, tank)
    if tank or type(pct) ~= "number" then return state, false end
    local band = PT.Band(pct)
    return band, band == "over"
end

-- status: the game's 0..3 (3: on you; 2: on you, someone has more; 1: not on
-- you, you have more than who it is on; 0: not on you); nil: not known.
function PT.State(status, tank)
    if type(status) ~= "number" then return "hidden" end
    if tank then
        if status >= 3 then return "safe" end
        if status == 2 then return "losing" end
        if status == 1 then return "pulling" end
        return "lost"
    end
    if status >= 2 then return "danger" end
    if status == 1 then return "pulling" end
    return "low"
end

function PT.Text(pct)
    if type(pct) ~= "number" then return "" end
    return string.format("%d%%", math.floor(pct + 0.5))
end

function PT.Tanking(role, bear)
    return role == "tank" or bear == true
end

-- Alone, everything is on you: shown only in a group, with a pet out, or
-- with the "always" setting; never when off.
function PT.Wanted(on, always, grouped, pet)
    if on ~= true then return false end
    if always == true then return true end
    return grouped == true or pet == true
end

-- One read of the client, or nil when it has no such read or it fails.
local function ask(client, name, ...)
    if type(client) ~= "table" or type(client[name]) ~= "function" then return nil end
    local ok, v = pcall(client[name], ...)
    if not ok then return nil end
    return v
end

local function yes(v)
    if v == nil then return "not known" end
    return v and "yes" or "no"
end

function PT.Declare(k, diag)
    local api = {}
    local ctx
    local inView = {}          -- [unit] = true: the enemy plates on screen
    local labels = {}          -- [unit] = the client's label handle
    local glows = {}           -- [unit] = the region that pulses
    local fighting, shown, last = false, 0, nil
    local cancelPlates, cancelTick, pulse

    local function on() return ctx ~= nil and ctx.settings:get(PT.OFF) ~= true end
    local function always() return ctx ~= nil and ctx.settings:get(PT.ALWAYS) == true end

    local function wantedNow()
        if not ctx then return false end
        local client = ctx.client
        return PT.Wanted(on(), always(), ask(client, "grouped"), ask(client, "petGUID") ~= nil)
    end

    local function tankingNow()
        if not ctx then return false end
        local role = ctx.settings:get(PT.ROLE)
        if role == "tank" then return true end
        return PT.Tanking(role, ask(ctx.client, "unitBuff", "player", PT.BEAR))
    end

    -- D-32 (lead section 727): the shared pulse of Rotation/Pulse.lua when
    -- this kernel has it started, so one frame listener drives everything
    -- that pulses (as Flow's Modules/Pulse.lua:34); else a set of its own,
    -- made at the first use (a kernel with no rotation). The look is the
    -- same: both work the brightness out from the clock alone.
    local function pulseSet()
        local P = ns.Pulse
        if type(P) == "table" and k:ModuleState(P.NAME) == "started" then
            local shared = k.use(P.NAME)
            if type(shared) == "table" and type(shared.add) == "function" and type(shared.remove) == "function" then
                return shared
            end
        end
        if not pulse and ctx and type(P) == "table" and type(P.New) == "function" then
            pulse = P.New({ onFrame = ctx.client.onFrame, now = ctx.client.now })
        end
        return pulse
    end

    local function unglow(unit)
        local g = glows[unit]
        glows[unit] = nil
        local set = g and pulseSet()
        if set then set.remove(g, 1) end
    end

    local function glow(unit, h, flash)
        if not flash then
            unglow(unit)
            return
        end
        local set = pulseSet()
        if glows[unit] or not set then return end
        local g = { setAlpha = function(a) h.alpha(a) end }
        if set.add(g) then glows[unit] = g end
    end

    local function hideOne(unit)
        unglow(unit)
        local h = labels[unit]
        if h then h.show(false) end
    end

    local function hideAll()
        for unit in pairs(labels) do hideOne(unit) end
        shown = 0
    end

    local function drawOne(unit, wanted, tank)
        local client = ctx.client
        if not wanted or ask(client, "canAttack", unit) ~= true then
            hideOne(unit)
            return
        end
        local h = labels[unit]
        if not h then
            h = ask(client, "plateLabel", unit)
            if type(h) ~= "table" then return end
            labels[unit] = h
        end
        local state, status, pct = h.threat()
        last = state or "unknown"
        if state ~= "shown" and state ~= "hidden" then
            hideOne(unit)
            return
        end
        -- A hidden share is on the label already, written by the client.
        if state == "shown" then h.text(PT.Text(pct)) else pct = nil end
        local key, flash = PT.Look(PT.State(status, tank), pct, tank)
        local colour = PT.COLORS[key] or PT.COLORS.hidden
        h.color(colour[1], colour[2], colour[3])
        glow(unit, h, flash)
        h.show(true)
        shown = shown + 1
    end

    local function refresh()
        if not ctx then return end
        local wanted = wantedNow()
        local tank = wanted and tankingNow() or false
        shown = 0
        for unit in pairs(inView) do drawOne(unit, wanted, tank) end
    end

    local function startFight()
        fighting = true
        if not cancelTick then cancelTick = ctx.sched:every(PT.NAME, PT.TICK, refresh) end
        refresh()
    end

    local function endFight()
        fighting = false
        if cancelTick then
            cancelTick()
            cancelTick = nil
        end
        hideAll()
    end

    local function onPlate(what, unit)
        if not ctx then return end
        -- A plate frame is handed out again: what was on it before goes.
        hideOne(unit)
        labels[unit] = nil
        if what == "added" then
            inView[unit] = true
            if fighting then
                local wanted = wantedNow()
                drawOne(unit, wanted, wanted and tankingNow() or false)
            end
        else
            inView[unit] = nil
        end
    end

    function api.status()
        local n = 0
        for _ in pairs(inView) do n = n + 1 end
        return { on = on(), always = always(), wanted = wantedNow(), tanking = tankingNow(),
            fighting = fighting, inView = n, shown = shown, last = last }
    end

    function api.lines()
        local s = api.status()
        local client = ctx and ctx.client
        local out = {
            ("threat on nameplates: %s; wanted now: %s; you are %s; in a fight: %s; %d nameplate(s) in view, %d with a number")
                :format(s.on and "on" or "off", yes(s.wanted), s.tanking and "tanking" or "not tanking",
                    yes(s.fighting), s.inView, s.shown),
            "  last threat read: " .. (s.last and PT.WORDS[s.last] or "none yet"),
            ("  in a group: %s; pet out: %s; shown when alone too: %s")
                :format(yes(ask(client, "grouped")), yes(ask(client, "petGUID") ~= nil), yes(s.always)),
        }
        return out
    end

    local function say(line)
        if ctx then ctx.client.print(ns.id.title .. ": " .. line) end
    end

    -- The switches (lead section 178; their model rows are in Settings/Model.lua).
    k:Setting({ key = PT.OFF, scope = "account", type = "bool", default = false,
        label = "Hide your threat on enemy nameplates", group = "combat.plates", help = PT.WHEN,
        synonyms = { "threat", "aggro", "nameplate" } })
    k:Setting({ key = PT.ALWAYS, scope = "account", type = "bool", default = false,
        label = "Show your threat on enemy nameplates when alone too", group = "combat.plates", help = PT.WHEN,
        synonyms = { "threat", "aggro", "nameplate", "solo" } })

    k:Module({
        name = PT.NAME,
        needs = { "client", "settings", "bus", "sched" },
        start = function(c)
            ctx = c
            local client = c.client
            cancelPlates = ask(client, "plates", onPlate)
            c.bus:on(PT.NAME, "PLAYER_REGEN_DISABLED", startFight)
            c.bus:on(PT.NAME, "PLAYER_REGEN_ENABLED", endFight)
            c.bus:on(PT.NAME, "UNIT_THREAT_LIST_UPDATE", function()
                if fighting then refresh() end
            end)
            -- Loaded in a fight (a reload): the looks start now.
            if ask(client, "inCombat") == true then startFight() end
        end,
        stop = function()
            if type(cancelPlates) == "function" then pcall(cancelPlates) end
            cancelPlates = nil
            if cancelTick then pcall(cancelTick) end
            cancelTick = nil
            fighting = false
            hideAll()
            inView, labels = {}, {}
        end,
    })

    if diag and type(diag.commands) == "table" then
        diag.commands[PT.WORD] = function(rest)
            if not ctx then return end
            local word = tostring(rest or ""):lower():match("^%s*(%S*)")
            if word == "on" or word == "off" then
                ctx.settings:set(PT.OFF, word == "off")
                if word == "off" then hideAll() elseif fighting then refresh() end
            end
            local lines = api.lines()
            say(lines[1])
            for i = 2, #lines do ctx.client.print(lines[i]) end
        end
        if type(diag.help) == "table" then diag.help[PT.WORD] = PT.HELP end
    end
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.plateThreat = PT.Declare(ns, ns.diag)
