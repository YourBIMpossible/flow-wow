local _, ns = ...

-- Staged reveal (G55): a new player is not faced with every surface at
-- once. They come in one at a time as the player starts to play, each with
-- one line saying what it is. Behaviour from legacy Flow's
-- Modules/Reveal.lua, built in this add-on's shape:
--   arrow    walked R.WALK yards from where they stood, or a quest accepted
--   tracker  this add-on has no tracker yet: the stage is skipped (asked
--            about, it answers "shown") until one exists
--   icon     a live hostile target, or a fight starts
--   advice   a level up, or R.ADVICE_AFTER seconds after the arrow came in
--            (measured on the client clock and saved with the stages, so
--            a reload keeps the wait; with no clock, this session's time)
-- The stages are kept per character at R.PATH (char). A character with
-- none kept yet is decided once: when the account's saved table was not
-- there before this login (a new install), the stages; else (a player who
-- used the add-on before, also on a new character) everything at once.
-- When the client cannot say, everything.
--
-- `<slash> reveal` says what is on screen, `reveal all` shows everything
-- now, `reveal reset` starts the stages over.
--
-- Setting "general.reveal" (bool, account): off shows everything, whatever
-- is kept. Off by default (lead section 294): staging holds nothing back
-- unless the player turned it on. Legacy had it on.
--
-- The surfaces ask R.Open(k, stage): true unless the reveal module on k
-- says the stage is held back. No module, a raising answer, saved data not
-- open yet: true (shown). A change is said on the bus as R.EVENT.
--
-- Reads (through the injected client): now, worldPosition, target, print.
-- Writes: the character's stages only.

local R = ns.Reveal or {}
ns.Reveal = R

R.NAME = "reveal"
R.WORD = "reveal"
R.SETTING = "general.reveal"
R.PATH = "state.reveal"
R.EVENT = "reveal.changed"
R.STAGES = { "arrow", "tracker", "icon", "advice" }
-- Stages whose surface this add-on does not have yet, and what is said.
R.ABSENT = { tracker = "no tracker yet" }
R.WALK = 10            -- yards walked before the arrow comes in (legacy)
R.ADVICE_AFTER = 600   -- seconds after the arrow before the advice (legacy)
R.ARROW_AT = "arrowAt" -- saved with the stages: the client clock (seconds) when the arrow came in
R.EVERY = 0.5         -- seconds between looks at the walk and the clock

-- One line per stage saying what came in.
function R.Hints()
    return {
        arrow = "this arrow points to your next step. Follow it; right-click it for its menu.",
        icon = "this icon shows what to press in a fight.",
        advice = "this panel lists ways to improve your character.",
    }
end

-- Has the player walked `yards` from `start`? Both are world positions
-- { cont, wx, wy }; another continent is no walk.
function R.Moved(start, p, yards)
    if type(start) ~= "table" or type(p) ~= "table" or start.cont ~= p.cont then return false end
    if type(p.wx) ~= "number" or type(p.wy) ~= "number" then return false end
    if type(start.wx) ~= "number" or type(start.wy) ~= "number" then return false end
    yards = yards or R.WALK
    return (p.wx - start.wx) ^ 2 + (p.wy - start.wy) ^ 2 >= yards ^ 2
end

-- The stages a character with none kept starts with, from the store's
-- record of which saved tables were there before this login.
function R.Initial(existed)
    if type(existed) == "table" and existed.account == false then return {} end
    return { all = true }
end

-- Is the stage shown on kernel k? The surfaces' one question.
function R.Open(k, stage)
    if type(k) ~= "table" or type(k.revealed) ~= "function" then return true end
    local ok, v = pcall(k.revealed, stage)
    if not ok then return true end
    return v ~= false
end

function R.Declare(k, diag)
    local api = {}
    local ctx, cancelWatch
    local start, arrowAt   -- where the walk is measured from; when the arrow came in

    local function client() return (ctx and ctx.client) or k.client end

    local function read(name, ...)
        local c = client()
        if type(c) ~= "table" or type(c[name]) ~= "function" then return nil end
        local ok, v = pcall(c[name], ...)
        if not ok then return nil end
        return v
    end

    local function staging()
        if type(k.settings) ~= "table" then return true end
        return k.settings:get(R.SETTING) ~= false
    end

    -- The character's stages, decided on the first ask; nil while the saved
    -- data is not open, or cannot be written.
    local function data()
        local store = k.store
        if type(store) ~= "table" or not store.opened then return nil end
        local d = store:get("char", R.PATH)
        if type(d) == "table" then return d end
        d = R.Initial(store.existed)
        if not store:set("char", R.PATH, d) then return nil end
        return d
    end

    function api.Revealed(stage)
        if R.ABSENT[stage] then return true end
        if not staging() then return true end
        local d = data()
        if not d or d.all == true then return true end
        return d[stage] == true
    end
    k.revealed = api.Revealed

    local function complete(d)
        for _, s in ipairs(R.STAGES) do
            if not R.ABSENT[s] and d[s] ~= true then return false end
        end
        return true
    end

    local function changed(stage)
        if type(k.bus) == "table" then k.bus:emit(R.EVENT, stage) end
    end

    local function say(text)
        local id = k.id or ns.id
        local c = client()
        if type(c) == "table" and type(c.print) == "function" then
            pcall(c.print, tostring(id.title) .. ": " .. text)
        end
    end

    -- Shows one stage: true when it came in now.
    function api.Show(stage, quiet)
        if R.ABSENT[stage] or api.Revealed(stage) then return false end
        local d = data()
        if not d then return false end
        k.store:set("char", R.PATH .. "." .. stage, true)
        if complete(d) then k.store:set("char", R.PATH .. ".all", true) end
        if stage == "arrow" then
            arrowAt = read("now")
            local wall = read("clock")
            if type(wall) == "number" then k.store:set("char", R.PATH .. "." .. R.ARROW_AT, wall) end
        end
        if not quiet then
            local hint = R.Hints()[stage]
            if hint then say(hint) end
        end
        changed(stage)
        return true
    end

    function api.ShowAll()
        local d = data()
        if not d then return false end
        for _, s in ipairs(R.STAGES) do
            if not R.ABSENT[s] and d[s] ~= true then k.store:set("char", R.PATH .. "." .. s, true) end
        end
        k.store:set("char", R.PATH .. ".all", true)
        changed("all")
        return true
    end

    function api.Reset()
        local store = k.store
        if type(store) ~= "table" or not store.opened then return false end
        if not store:set("char", R.PATH, {}) then return false end
        start, arrowAt = nil, nil
        changed("reset")
        return true
    end

    -- The walk and the clock, every R.EVERY seconds while stages are held.
    local function tick()
        if not staging() then return end
        local d = data()
        if not d or d.all == true then return end
        local now = read("now")
        if d.arrow ~= true then
            local p = read("worldPosition")
            if type(p) == "table" and not start then start = p end
            if R.Moved(start, p, R.WALK) then api.Show("arrow") end
            return
        end
        -- RV-1: with the client's clock known, the wait is measured from
        -- the saved R.ARROW_AT, so a reload does not restart it.
        local wall = read("clock")
        if type(wall) == "number" then
            local at = d[R.ARROW_AT]
            if type(at) ~= "number" then
                at = wall
                k.store:set("char", R.PATH .. "." .. R.ARROW_AT, wall)
            end
            if d.advice ~= true and wall - at > R.ADVICE_AFTER then api.Show("advice") end
            return
        end
        -- No clock: this session's time, not saved.
        if type(now) ~= "number" then return end
        if type(arrowAt) ~= "number" then arrowAt = now end
        if d.advice ~= true and now - arrowAt > R.ADVICE_AFTER then api.Show("advice") end
    end

    local function status()
        local list = {}
        for _, s in ipairs(R.STAGES) do
            local word
            if R.ABSENT[s] then word = R.ABSENT[s]
            elseif api.Revealed(s) then word = "on"
            else word = "not yet" end
            list[#list + 1] = s .. " (" .. word .. ")"
        end
        local id = k.id or ns.id
        say("on screen: " .. table.concat(list, ", ") .. ". " .. tostring(id.slash) .. " "
            .. R.WORD .. " all shows everything now; " .. R.WORD .. " reset starts over.")
    end

    if diag and type(diag.commands) == "table" then
        diag.commands[R.WORD] = function(rest)
            local arg = type(rest) == "string" and rest:lower():match("^%s*(%S*)") or ""
            if arg == "all" then
                if api.ShowAll() then say("everything is on screen now.") end
            elseif arg == "reset" then
                if api.Reset() then say("the pieces will come in one at a time again: start walking.") end
            else
                status()
            end
        end
        if type(diag.help) == "table" then
            diag.help[R.WORD] = "what is on screen yet; " .. R.WORD .. " all shows everything now, "
                .. R.WORD .. " reset brings the pieces in one at a time again"
        end
    end

    k:Setting({ key = R.SETTING, scope = "account", type = "bool", default = false,
        label = "New player: show pieces one at a time", group = "general",
        help = "On: on a new install the arrow, the fight icon and the advice panel come in one at a time "
            .. "as you start to play. Off (the default) shows everything at once.",
        synonyms = { "reveal", "new player", "stages", "intro", "one at a time", "tour" } })

    local function target()
        local tg = read("target")
        if type(tg) == "table" and tg.exists == true and tg.hostile == true and tg.dead ~= true then
            api.Show("icon")
        end
    end

    k:Module({
        name = R.NAME,
        needs = { "client", "store", "settings", "bus" },
        provides = { Revealed = api.Revealed, Show = api.Show },
        events = {
            QUEST_ACCEPTED = function() api.Show("arrow") end,
            PLAYER_TARGET_CHANGED = function() target() end,
            PLAYER_REGEN_DISABLED = function() api.Show("icon") end,
            PLAYER_LEVEL_UP = function() api.Show("advice") end,
        },
        ticks = { { every = R.EVERY, when = "always", run = function() tick() end } },
        start = function(c)
            ctx = c
            data()
            -- The setting switched: the surfaces are drawn again.
            local row = c.settings:row(R.SETTING)
            local scope = row and row.scope or "account"
            local path = row and row.path or ("settings." .. R.SETTING)
            cancelWatch = c.store:watch(scope, path, function() changed("setting") end)
            changed("start")
        end,
        stop = function()
            if cancelWatch then cancelWatch() end
            cancelWatch, ctx = nil, nil
        end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.reveal = R.Declare(ns, ns.diag)
