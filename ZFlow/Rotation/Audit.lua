local _, ns = ...

-- The press audit (S10), ported from Flow 0.35.377
-- Modules/Rotation/Audit.lua: does the key cast what the icon shows?
-- At a press of the rotation key it notes what the icon showed, what the
-- key was set to cast at that moment, whether a fight was on (and for how
-- long), and which spell the game then sent. A press where the icon and
-- the key disagree is kept, so "it showed Moonfire and cast Wrath" can be
-- looked at afterwards instead of guessed at.
--
-- It only reads and writes its own saved rows. It presses nothing.
--
-- Pure, as Flow:
--   Au.Agree(icon, set) -> bool      nil on either side: nothing to compare
--   Au.Judge(press, cast) -> "ok" | "key" | "other" | "nothing"
--   Au.Line(r) -> text               one kept disagreement
--   Au.Report(data) -> lines         the tally and the last disagreements
-- Pure, new here:
--   Au.Stamp(seconds) -> "HH:MM:SSZ" | nil   a clock time as text, in UTC
--   Au.Set(plan, form) -> spell | nil  what the plain key is set to cast:
--               the key slot of the form's row in a key plan. The module
--               hands it the last plan the driver gave: in a fight the
--               driver gives none, and the keys cannot change in a fight.
--   Au.Cast(id, press, idOf) -> name | nil   the spell the game sent, by
--               the name the press knows it under, else "spell <id>"
--   Au.New(opts) -> recorder         press / sent / mark over one data table
-- The module:
--   Au.Declare(k[, diag]) -> { press, mark, report, reset, data }
--     api.press() is the press of the key. NOTHING CALLS IT YET: see below.
--     Words after the slash command: Au.WORD and Au.MARK.
--
-- CLIENT NEEDS, none is in Core/Client.lua yet:
--   a press signal: the secure button of the rotation key calling
--     ns.pressAudit.press() from its PreClick (Flow: Cast.lua called
--     Au.Press from the button's PreClick). Without it nothing is counted.
--   client.screenshot() -> true | false   optional: Flow took a screenshot
--     at a disagreement (at most one every 20 s, 8 a session). Used when
--     the client has it; without it no screenshot is taken.
-- The game event UNIT_SPELLCAST_SENT (unit, target, castGUID, spellID) is
-- listened to as Flow did. Not tested in game.
local Au = {}
ns.Audit = Au

local D = ns.RotationDriver

Au.NAME = "pressAudit"
Au.PATH = "audit"       -- per character
Au.WORD = "audit"
Au.MARK = "mark"
Au.HELP = "how often your key cast what the icon showed; audit reset clears it; audit shots on|off"
Au.MARK_HELP = "note the moment something looked wrong, with what the icon and the key held"
Au.EVENT = "UNIT_SPELLCAST_SENT"
Au.WINDOW = 0.7       -- as Flow: a cast sent this soon after a press belongs to it
Au.KEEP = 25          -- as Flow: disagreements kept
Au.SHOT_EVERY = 20    -- as Flow: seconds between screenshots
Au.SHOT_MAX = 8       -- as Flow: per session
Au.SHOWN = 12         -- as Flow: disagreements listed by the report

-- ------------------------------------------------------------------ pure
function Au.Agree(icon, set)
    if icon == nil or set == nil then return true end
    return icon == set
end

function Au.Judge(press, cast)
    if not cast then return "nothing" end
    if press.icon == nil or cast == press.icon then return "ok" end
    if cast == press.set then return "key" end
    return "other"
end

function Au.Stamp(seconds)
    if type(seconds) ~= "number" or seconds ~= seconds or seconds < 0 then return nil end
    local s = math.floor(seconds) % 86400
    return string.format("%02d:%02d:%02dZ", math.floor(s / 3600), math.floor(s / 60) % 60, s % 60)
end

function Au.Line(r)
    local fight = "not in a fight"
    if r.combat == nil then
        fight = "fight not known"
    elseif r.combat then
        fight = type(r.sinceFight) == "number" and string.format("in a fight for %.1f s", r.sinceFight) or "in a fight"
    end
    return string.format("%s icon %s, key set to %s, cast %s; %s%s%s", r.at or "?", tostring(r.icon), tostring(r.set),
        tostring(r.cast or "nothing"), fight,
        r.lockedTo and ("; locked to " .. tostring(r.lockedTo)) or "", r.shot and "; screenshot" or "")
end

function Au.Report(data)
    local out = {}
    data = type(data) == "table" and data or {}
    local n = type(data.counts) == "table" and data.counts or {}
    local total = (n.ok or 0) + (n.key or 0) + (n.other or 0) + (n.nothing or 0)
    if total == 0 then
        out[1] = "no key presses recorded yet."
        return out
    end
    out[1] = string.format("%d key presses: %d cast what the icon showed, %d cast the key's spell while the icon showed another, %d cast something else, %d cast nothing",
        total, n.ok or 0, n.key or 0, n.other or 0, n.nothing or 0)
    local disagreed = data.disagreed or 0
    out[2] = string.format("the icon and the key disagreed at %d press(es)%s", disagreed,
        disagreed > 0 and ":" or " (the key casts what the icon shows).")
    local list = type(data.list) == "table" and data.list or {}
    for i = #list, math.max(1, #list - (Au.SHOWN - 1)), -1 do out[#out + 1] = "  " .. Au.Line(list[i]) end
    return out
end

function Au.Set(plan, form)
    if type(plan) ~= "table" or type(plan.states) ~= "table" then return nil end
    if type(form) ~= "number" then return nil end
    local row = plan.states[form]
    if type(row) ~= "table" or type(row.key) ~= "string" or row.key == "" then return nil end
    return row.key
end

function Au.Cast(id, press, idOf)
    if type(id) ~= "number" then return nil end
    if type(press) == "table" and type(idOf) == "function" then
        for _, name in ipairs({ press.icon, press.set }) do
            if type(name) == "string" then
                local ok, got = pcall(idOf, name)
                if ok and got == id then return name end
            end
        end
    end
    return "spell " .. tostring(id)
end

local function rows(data)
    if type(data.list) ~= "table" then data.list = {} end
    if type(data.counts) ~= "table" then data.counts = {} end
    if type(data.marks) ~= "table" then data.marks = {} end
    return data
end

local function keep(list, r)
    list[#list + 1] = r
    while #list > Au.KEEP do table.remove(list, 1) end
end

-- opts: data (the saved table), now() seconds, stamp() text or nil,
-- shoot() true when a screenshot was taken, idOf(name) the spell id.
function Au.New(opts)
    opts = type(opts) == "table" and opts or {}
    local data = rows(type(opts.data) == "table" and opts.data or {})
    local now, stamp, shoot, idOf = opts.now, opts.stamp, opts.shoot, opts.idOf
    local last
    local shots, shotAt = 0, nil
    local rec = { data = data }

    local function time()
        if type(now) ~= "function" then return nil end
        local ok, t = pcall(now)
        return ok and type(t) == "number" and t or nil
    end

    local function at()
        if type(stamp) ~= "function" then return nil end
        local ok, text = pcall(stamp)
        return ok and type(text) == "string" and text or nil
    end

    local function shot()
        if data.shots == false or type(shoot) ~= "function" then return false end
        local t = time()
        if shots >= Au.SHOT_MAX or t == nil then return false end
        if shotAt and t - shotAt < Au.SHOT_EVERY then return false end
        shots, shotAt = shots + 1, t
        local ok, took = pcall(shoot)
        return ok and took == true
    end

    local function settle(cast)
        if not last then return end
        local kind = Au.Judge(last, cast)
        data.counts[kind] = (data.counts[kind] or 0) + 1
        if last.kept then last.kept.cast = cast end
        last = nil
    end

    function rec.waiting() return last ~= nil end
    function rec.forget() last = nil end

    -- A press of the key itself. Returns the kept row at a disagreement.
    function rec.press(icon, set, combat, sinceFight, lockedTo)
        if last then settle(nil) end -- the press before got no cast
        last = { t = time(), icon = icon, set = set }
        if Au.Agree(icon, set) then return nil end
        data.disagreed = (data.disagreed or 0) + 1
        local r = { at = at(), icon = icon, set = set, combat = combat, sinceFight = sinceFight, lockedTo = lockedTo }
        r.shot = shot() or nil
        keep(data.list, r)
        last.kept = r
        return r
    end

    -- The game sent a spell. A cast later than the window, or at a moment
    -- that cannot be timed, is not this press's.
    function rec.sent(id)
        if not last then return end
        local t = time()
        if t == nil or last.t == nil or t - last.t > Au.WINDOW then
            settle(nil)
            return
        end
        settle(Au.Cast(id, last, idOf))
    end

    function rec.mark(note, icon, set, combat)
        local r = { at = at(), note = (type(note) == "string" and note ~= "") and note or nil,
            icon = icon, set = set, combat = combat }
        r.shot = shot() or nil
        keep(data.marks, r)
        return r
    end

    function rec.reset()
        data.list, data.counts, data.marks, data.disagreed = {}, {}, {}, nil
        last = nil
    end

    return rec
end

function Au.MarkLine(r)
    return string.format("%s %s | icon %s | key set to %s | in a fight %s%s", r.at or "?", r.note or "(no note)",
        tostring(r.icon), tostring(r.set), tostring(r.combat), r.shot and " | screenshot" or "")
end

-- --------------------------------------------------------------- the module
function Au.Declare(k, diag)
    local client, rec, view, plan
    local fightAt
    local api = {}

    local function read(fn, ...)
        if type(fn) ~= "function" then return nil end
        local ok, v = pcall(fn, ...)
        if ok then return v end
        return nil
    end

    -- The recorder over the saved rows. The rows are the store's own
    -- table, so a change is saved as it is made. Asked for at each use:
    -- the saved table is not there before the client has loaded it.
    local function ready()
        if not client then return nil end
        local data = k.store:table("char", Au.PATH)
        if type(data) ~= "table" then return nil end
        if not rec or rec.data ~= data then
            rec = Au.New({
                data = data,
                now = client.now,
                stamp = function() return Au.Stamp(read(client.clock)) end,
                shoot = type(client.screenshot) == "function" and client.screenshot or nil,
                idOf = client.spellId,
            })
        end
        return rec
    end

    local function iconNow()
        local s = type(view) == "table" and view.suggestion or nil
        local spell = type(s) == "table" and s.spell or nil
        return (type(spell) == "string" and spell ~= "") and spell or nil
    end

    local function setNow() return Au.Set(plan, read(client.form)) end

    -- The last plan the driver gave stays through a fight; the rotation
    -- switched off (no view), it is forgotten.
    local function onView(v)
        view = v
        if type(v) ~= "table" then
            plan = nil
        elseif type(v.keys) == "table" and type(v.keys.plan) == "table" then
            plan = v.keys.plan
        end
    end

    -- true, false, or nil when the client does not say.
    local function combatNow()
        local c = read(client.inCombat)
        if c == true or c == false then return c end
        return nil
    end

    function api.press()
        if not ready() then return nil end
        local combat = combatNow()
        local since
        local t = read(client.now)
        if combat and fightAt and type(t) == "number" then since = t - fightAt end
        return rec.press(iconNow(), setNow(), combat, since, nil)
    end

    function api.mark(note)
        if not ready() then return nil end
        return rec.mark(note, iconNow(), setNow(), combatNow())
    end

    function api.report() return Au.Report(ready() and rec.data or nil) end
    function api.data() return ready() and rec.data or nil end
    function api.reset()
        if ready() then rec.reset() end
    end

    local function say(text) client.print(k.id.title .. ": " .. text) end

    local function run(rest)
        if not ready() then return end
        rest = type(rest) == "string" and rest or ""
        if rest == "reset" then
            api.reset()
            say("press audit cleared")
            return
        end
        local shots = rest:match("^shots%s+(o[nf]f?)$")
        if shots == "on" or shots == "off" then
            rec.data.shots = (shots == "on")
            say("press audit screenshots: " .. shots)
            return
        end
        say("press audit (does the key cast what the icon shows?):")
        local lines = api.report()
        for i = 1, #lines do say("  " .. lines[i]) end
        local marks = rec.data.marks
        for i = #marks, math.max(1, #marks - 4), -1 do say("  marked: " .. Au.MarkLine(marks[i])) end
    end

    local function mark(rest)
        if not ready() then return end
        local r = api.mark(rest)
        say("marked" .. (r and r.shot and ", with a screenshot." or "."))
    end

    k:Module({
        name = Au.NAME,
        needs = { "client", "store", "bus", D.NAME },
        start = function(ctx)
            client = ctx.client
            ctx.bus:on(Au.NAME, D.EVENT, onView)
            client.listen("PLAYER_REGEN_DISABLED", function() fightAt = read(client.now) end)
            client.listen("PLAYER_REGEN_ENABLED", function() fightAt = nil end)
            client.listen(Au.EVENT, function(unit, _, _, spellId)
                if unit ~= "player" or not rec or not rec.waiting() then return end
                rec.sent(spellId)
            end)
        end,
    })

    if diag and type(diag.commands) == "table" then
        diag.commands[Au.WORD] = run
        diag.commands[Au.MARK] = mark
        if type(diag.help) == "table" then
            diag.help[Au.WORD] = Au.HELP
            diag.help[Au.MARK] = Au.MARK_HELP
        end
    end

    return api
end

-- The addon's own.
ns.pressAudit = Au.Declare(ns, ns.diag)
