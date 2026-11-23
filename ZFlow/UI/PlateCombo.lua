local _, ns = ...
-- Your combo points on your target's nameplate (S8, lead section 178;
-- WoW/from-lazy/RESEARCH-S8.md). Ported from legacy Flow 0.35.377
-- (Modules/PlateCombo.lua): for a rogue, or a druid in Cat Form, with a live
-- enemy targeted whose nameplate is on screen, one bar right under that
-- plate's health bar (under its power bar when it shows one), cut into a
-- section for each point you can hold and filled a section a point, in the
-- game's combo point colour.
--
-- THE DISPLAY SINK (option A). The game may hide the count from addons.
-- Then the client handle sets it on its own bar (StatusBar:SetValue) and
-- this module is told only "hidden": the value never comes here. A plain
-- count comes back as a number and is drawn from here. A count not known at
-- all is not drawn: the bar is put away, never shown as 0 (legacy Flow's
-- A.ComboPoints read an unknown count as 0).
--
-- LOOK ONLY: nothing clicks, targets, casts or writes a CVar; the target is
-- read, never chosen. The game's own setting for this
-- (nameplateResourceOnTarget) is not read or written. The client reads
-- (Core/Client.lua, S8) are FIRST GUESSES, not seen in game on 1.60.1:
--   client.comboBar() with h.hang, h.sections, h.fill, h.fillFromGame;
--   client.combo() (the most points), client.comboColor(), client.plates(fn),
--   client.class(), client.target(), client.unitBuff("player", PC.CAT).
-- There is no read of the form's name (client.form() is only a number), so
-- Cat Form is told by its form's buff, as Classes/Druid.lua names the forms.
--
-- Pure:
--   PC.Uses(class, cat) -> true | false
--   PC.Wanted(on, class, cat, target) -> true | false
--     target: client.target()'s { exists, hostile, dead }; dead not known
--     is not taken as dead (as legacy Flow)
--   PC.Fill(points, max) -> points | nil, max   max clamped to 1..10, PC.MAX
--     when not known; points clamped to 0..max, nil when not known
--   PC.BarColor(color) -> r, g, b   color { r, g, b } or nil (PC.COLOR)
-- PC.Declare(k, diag) -> api
--   api.status() -> { on, uses, wanted, shown, under, last, points, max }
--     last: "shown", "hidden", "unknown", or nil before the first read
--   api.lines()   what the word PC.WORD prints
-- Setting (account): plateCombo.off (the import target in
-- Import/FromFlow.lua; its row in Settings/Model.lua).
-- Not tested in game.
local PC = {}
ns.PlateCombo = PC

PC.NAME = "plateCombo"
PC.WORD = "combo"
PC.HELP = "combo points on your target's nameplate: what shows and why; combo on or combo off switches it"
PC.OFF = "plateCombo.off"
PC.TICK = 0.2                         -- seconds between looks while it is wanted
PC.MAX = 5                            -- sections when the most is not known
PC.COLOR = { 1.00, 0.96, 0.41 }       -- the game's combo point colour, where it does not say
PC.CAT = { "Cat Form" }
PC.WORDS = { hidden = "hidden by the game", unknown = "not known" }

function PC.Uses(class, cat)
    if class == "ROGUE" then return true end
    return class == "DRUID" and cat == true
end

function PC.Wanted(on, class, cat, target)
    if on ~= true or type(target) ~= "table" then return false end
    if target.exists ~= true or target.hostile ~= true or target.dead == true then return false end
    return PC.Uses(class, cat)
end

function PC.Fill(points, max)
    if type(max) ~= "number" or max ~= max then max = PC.MAX end
    max = math.max(1, math.min(math.floor(max), 10))
    if type(points) ~= "number" or points ~= points then return nil, max end
    return math.max(0, math.min(math.floor(points), max)), max
end

function PC.BarColor(color)
    if type(color) == "table" and type(color.r) == "number" and type(color.g) == "number"
        and type(color.b) == "number" then
        return color.r, color.g, color.b
    end
    return PC.COLOR[1], PC.COLOR[2], PC.COLOR[3]
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

function PC.Declare(k, diag)
    local api = {}
    local ctx
    local bar, cancelTick, cancelPlates
    local shown, under, last, points, most = false, nil, nil, nil, nil

    local function on() return ctx ~= nil and ctx.settings:get(PC.OFF) ~= true end

    local function catNow(client, class)
        if class ~= "DRUID" then return nil end
        return ask(client, "unitBuff", "player", PC.CAT)
    end

    local function wantedNow()
        if not ctx then return false end
        local client = ctx.client
        local class = ask(client, "class")
        return PC.Wanted(on(), class, catNow(client, class), ask(client, "target"))
    end

    local function hide()
        if bar then bar.show(false) end
        shown = false
    end

    local function stopTick()
        if cancelTick then
            cancelTick()
            cancelTick = nil
        end
    end

    -- Draws (or puts away) the bar for now. -> shown, wanted
    local function update()
        if not ctx then return false, false end
        if not wantedNow() then
            hide()
            stopTick()
            return false, false
        end
        local client = ctx.client
        if not bar then
            local made = ask(client, "comboBar")
            if type(made) ~= "table" then return false, true end
            bar = made
        end
        under = bar.hang("target")
        if under == nil then
            -- No plate for the target on screen yet: keep looking.
            hide()
            return false, true
        end
        local info = ask(client, "combo")
        local _, top = PC.Fill(nil, type(info) == "table" and info.max or nil)
        most = top
        bar.sections(top)
        bar.color(PC.BarColor(ask(client, "comboColor")))
        local state, n = bar.fillFromGame()
        last = state or "unknown"
        if state == "shown" then
            points = PC.Fill(n, top)
            bar.fill(points)
        elseif state == "hidden" then
            -- On the bar already, set by the client.
            points = nil
        else
            points = nil
            hide()
            return false, true
        end
        bar.show(true)
        shown = true
        return true, true
    end

    -- update, and the looks every PC.TICK seconds while it is wanted.
    local function refresh()
        if not ctx then return end
        local _, wanted = update()
        if wanted and not cancelTick then cancelTick = ctx.sched:every(PC.NAME, PC.TICK, update) end
    end

    function api.status()
        local client = ctx and ctx.client
        local class = ask(client, "class")
        local uses
        if class ~= nil then uses = PC.Uses(class, catNow(client, class)) end
        return { on = on(), uses = uses, wanted = wantedNow(), shown = shown, under = under,
            last = last, points = points, max = most }
    end

    function api.lines()
        local s = api.status()
        local read
        if s.last == "shown" and s.points ~= nil and s.max ~= nil then
            read = ("shown (%d of %d)"):format(s.points, s.max)
        elseif s.last ~= nil then
            read = PC.WORDS[s.last] or PC.WORDS.unknown
        else
            read = "none yet"
        end
        return {
            ("combo points on the nameplate: %s; your class uses them now: %s; wanted now: %s; shown: %s; hung under: %s")
                :format(s.on and "on" or "off", yes(s.uses), yes(s.wanted), yes(s.shown), s.under or "nothing yet"),
            "  last combo read: " .. read,
        }
    end

    local function say(line)
        if ctx then ctx.client.print(ns.id.title .. ": " .. line) end
    end

    -- The switch (lead section 178; its model row is in Settings/Model.lua).
    k:Setting({ key = PC.OFF, scope = "account", type = "bool", default = false,
        label = "Hide combo points on your target's nameplate", group = "combat.plates",
        synonyms = { "combo points", "nameplate", "rogue", "druid" } })

    k:Module({
        name = PC.NAME,
        needs = { "client", "settings", "bus", "sched" },
        start = function(c)
            ctx = c
            for _, event in ipairs({ "PLAYER_TARGET_CHANGED", "UPDATE_SHAPESHIFT_FORM", "PLAYER_ENTERING_WORLD",
                "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
                c.bus:on(PC.NAME, event, refresh)
            end
            c.bus:on(PC.NAME, "UNIT_POWER_UPDATE", function(unit)
                if unit == "player" and shown then update() end
            end)
            -- A plate comes or goes: the bar is hung again where it now belongs.
            cancelPlates = ask(c.client, "plates", function() refresh() end)
            refresh()
        end,
        stop = function()
            if type(cancelPlates) == "function" then pcall(cancelPlates) end
            cancelPlates = nil
            if cancelTick then pcall(cancelTick) end
            cancelTick = nil
            hide()
        end,
    })

    if diag and type(diag.commands) == "table" then
        diag.commands[PC.WORD] = function(rest)
            if not ctx then return end
            local word = tostring(rest or ""):lower():match("^%s*(%S*)")
            if word == "on" or word == "off" then
                ctx.settings:set(PC.OFF, word == "off")
                refresh()
            end
            local lines = api.lines()
            say(lines[1])
            for i = 2, #lines do ctx.client.print(lines[i]) end
        end
        if type(diag.help) == "table" then diag.help[PC.WORD] = PC.HELP end
    end
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.plateCombo = PC.Declare(ns, ns.diag)
