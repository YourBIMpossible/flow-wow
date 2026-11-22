local _, ns = ...

-- Rotation driver: each tick it reads the client, asks the chooser, and
-- holds the answer as a view for whoever shows it. It suggests; it presses
-- nothing: no attribute, binding, cast or frame is touched here, and the
-- key plan is only worked out, never applied.
--
--   D.Read(client, pack, ids) -> read(field)
--     the reader ns.Snapshot takes. dead, inCombat, stealthed, hostile and
--     spells are asked of the client; every other field answers nil (not
--     known), never a guess.
--       stealthed  client.stealthed() as it answered; nil when the client
--                  has no such read
--       hostile    from client.target() -> { exists, hostile, dead } or nil:
--                  true for a target that is there, hostile and alive; false
--                  when any of the three was read the other way; nil for
--                  anything else, or when the client has no such read
--       spells     each row also gets inRange = client.inRange(spell id)
--                  when the client has that read and the answer is true or
--                  false; otherwise range stays not known
--   D.Step(client, pack[, prefs, bias, applied]) -> view
--     one read and one choice. A read that fails is an error (not caught
--     here; the tick catches it).
--   D.Why(snapshot, trace, keys, lockdown) -> why
--   D.Declare(k[, packs]) -> api           declares the module on kernel k
--     packs: { [class token] = pack }, ns.Packs when left out.
--     api.view()       the view held, nil when off or before the first
--     api.errors()     how many ticks failed
--     api.lastError()  the last failure as text, or nil
--   ns.use(D.NAME) -> { View = api.view, Errors = api.errors }
--
--   view = {
--     pack        true; false when there is no pack for this class, and then
--                 the view holds only pack, trace = {} and why = { pack = false }:
--                 nothing was read and the chooser was not called
--     snapshot    ns.Snapshot of the read
--     suggestion  what ns.Choose picked, or nil. suggestion.passed (below)
--                 is added when it is not empty
--     trace       ns.Choose's trace
--     lockdown    client.combatLockdown() as it answered (nil: not known)
--     keys        ns.cast.Apply(plan, applied, lockdown)
--     attrs       ns.cast.Attributes(suggestion, plan, applied, lockdown)
--     unread      the pack's spells that could not be read (sorted)
--     missing     the pack's spells with no id (sorted)
--     passed      the spells the chooser's steps passed by only because
--                 nobody read their cooldown (sorted, each once): the trace
--                 rows' own passed lists put together. A spell no step came
--                 to is not in it
--     why         the plain reasons, see below
--     stale       true on a view kept from an earlier tick because this
--                 tick's read failed; absent on a fresh view
--   }
--   why = { dead, inCombat, lockdown    as read (nil: not known),
--           refused, reason             from keys, when the keys are refused,
--           step, result, note, spell   the last row of the trace }
--
-- The module is declared off: char setting D.SETTING. While off nothing is
-- read and no view is held. Switched on, each tick publishes its view on
-- the bus as D.EVENT; switched off, one D.EVENT with no view, then nothing.
-- A tick whose read fails keeps the last good view (a copy marked stale),
-- counts the error and never counts against the module.
--
-- Not tested in game: every client read used here is a first guess.

local D = ns.RotationDriver or {}
ns.RotationDriver = D

D.NAME = "rotationDriver"
D.EVENT = "rotation.suggested"
D.SETTING = "rotation.enabled"
D.EVERY = 0.2

local RR = ns.RotationReader

-- Is an enemy targeted? Yes or no only from what the target read gave.
local function hostileOf(client)
    if type(client.target) ~= "function" then return nil end
    local target = client.target()
    if type(target) ~= "table" then return nil end
    if target.exists == false or target.hostile == false or target.dead == true then return false end
    if target.exists == true and target.hostile == true and target.dead == false then return true end
    return nil
end

-- The pack's spell rows, each with its range when the client can tell.
local function spellRows(client, pack, ids)
    local rows = RR.SpellRows(pack, ids, client.spell, client.spellCooldown).rows
    if type(client.inRange) ~= "function" then return rows end
    for name, row in pairs(rows) do
        local asked, near = pcall(client.inRange, ids[name])
        if asked and type(near) == "boolean" then row.inRange = near end
    end
    return rows
end

function D.Read(client, pack, ids)
    return function(field)
        if field == "dead" then return client.dead() end
        if field == "inCombat" then return client.inCombat() end
        if field == "stealthed" then
            if type(client.stealthed) ~= "function" then return nil end
            return client.stealthed()
        end
        if field == "hostile" then return hostileOf(client) end
        if field == "spells" then return spellRows(client, pack, ids) end
        return nil
    end
end

-- The spells the steps passed by for a cooldown nobody read: the trace
-- rows' passed lists as one (sorted, each once).
local function passedIn(trace)
    local seen, out = {}, {}
    for _, row in ipairs(trace) do
        for _, name in ipairs(row.passed or {}) do
            if not seen[name] then
                seen[name] = true
                out[#out + 1] = name
            end
        end
    end
    table.sort(out)
    return out
end

function D.Why(snapshot, trace, keys, lockdown)
    local why = {}
    if type(snapshot) == "table" then
        why.dead, why.inCombat = snapshot.dead, snapshot.inCombat
    end
    why.lockdown = lockdown
    if type(keys) == "table" and keys.ok ~= true then
        why.refused, why.reason = keys.refused, keys.reason
    end
    local last = type(trace) == "table" and trace[#trace] or nil
    if type(last) == "table" then
        why.step, why.result, why.note, why.spell = last.step, last.result, last.note, last.spell
    end
    return why
end

function D.Step(client, pack, prefs, bias, applied)
    if type(pack) ~= "table" then
        return { pack = false, trace = {}, why = { pack = false } }
    end
    local ids, missing = RR.SpellIds(pack, client.spellId)
    local snapshot = ns.Snapshot(D.Read(client, pack, ids))
    local suggestion, trace = ns.Choose(snapshot, pack, prefs, bias)
    local passed = passedIn(trace)
    if suggestion and #passed > 0 then suggestion.passed = passed end

    local lockdown = client.combatLockdown()
    local plan = ns.KeyPlan(pack, prefs)
    local keys = ns.cast.Apply(plan, applied, lockdown)
    local attrs = ns.cast.Attributes(suggestion, plan, applied, lockdown, nil)

    -- Not read: no id, or no row came back for it.
    local notRead = {}
    for _, name in ipairs(RR.SpellNames(pack)) do
        if type(snapshot.spells) ~= "table" or snapshot.spells[name] == nil then notRead[#notRead + 1] = name end
    end
    table.sort(notRead)

    return {
        pack = true,
        snapshot = snapshot,
        suggestion = suggestion,
        trace = trace,
        lockdown = lockdown,
        keys = keys,
        attrs = attrs,
        unread = notRead,
        missing = missing,
        passed = passed,
        why = D.Why(snapshot, trace, keys, lockdown),
    }
end

-- One tick's work: the class's pack, then a step.
local function work(client, packs)
    local class = type(client.class) == "function" and client.class() or nil
    local pack = type(class) == "string" and type(packs) == "table" and packs[class] or nil
    return D.Step(client, pack)
end

function D.Declare(k, packs)
    local api = {}
    local view, errors, lastError = nil, 0, nil
    function api.view() return view end
    function api.errors() return errors end
    function api.lastError() return lastError end

    local function tick(ctx)
        if ctx.settings:get(D.SETTING) ~= true then
            if view ~= nil then
                view = nil
                ctx.bus:emit(D.EVENT, nil)
            end
            return
        end
        local ok, got = pcall(work, ctx.client, packs or ns.Packs)
        if ok then
            view = got
        else
            errors, lastError = errors + 1, tostring(got)
            if view == nil then return end
            if view.stale ~= true then
                local kept = {}
                for key, value in pairs(view) do kept[key] = value end
                kept.stale = true
                view = kept
            end
        end
        ctx.bus:emit(D.EVENT, view)
    end

    k:Module({
        name = D.NAME,
        needs = { "client", "store", "bus" },
        settings = { {
            key = D.SETTING, scope = "char", type = "bool", default = false,
            label = "Suggest the next spell",
            help = "Works out which spell to press next. It presses nothing for you.",
            group = "Rotation",
        } },
        provides = { View = api.view, Errors = api.errors },
        ticks = { { every = D.EVERY, run = tick } },
    })
    return api
end

-- The addon's own: declared when this file loads, started at login, off
-- until the setting is switched on.
ns.rotationDriver = D.Declare(ns)
