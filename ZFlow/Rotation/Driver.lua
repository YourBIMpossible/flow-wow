local _, ns = ...

-- Rotation driver: each tick it reads the client, asks the chooser, and
-- holds the answer as a view for whoever shows it. It suggests; it presses
-- nothing: no attribute, binding, cast or frame is touched here, and the
-- key plan is only worked out, never applied.
--
--   D.Read(client, pack, ids[, role]) -> read(field)
--     the reader ns.Snapshot takes. dead, inCombat, stealthed, hostile,
--     spells, buffs, targetDebuffs, form and current are asked of the
--     client; role is the
--     one handed in; every other field answers nil (not known), never a
--     guess.
--       role       the role you chose (the setting D.ROLE), when it is
--                  "dps", "heal" or "tank" and the pack has a part for it;
--                  anything else: nil. No talent is read: the rotation
--                  plays the role you say, or none.
--       stealthed  client.stealthed() as it answered; nil when the client
--                  has no such read
--       hostile    from client.target() -> { exists, hostile, dead } or nil:
--                  true for a target that is there, hostile and alive; false
--                  when any of the three was read the other way; nil for
--                  anything else, or when the client has no such read
--       buffs      client.playerBuffs() as it answered: { [name] = seconds
--                  left or true }, {} for read and none, nil when not known
--                  or the client has no such read
--       targetDebuffs  client.targetDebuffs(): your own debuffs on the
--                  target, the same shape and the same not known (187)
--       form       client.formName(): the form name, or nil for no form
--                  and for not known alike
--       formKnown  true when client.formName() said its answer is known
--                  (a form name, or no form); nil otherwise, never false.
--                  form nil with formKnown true is no form (section 186)
--       current    { [spell name] = true or false } over the pack's spell
--                  ids, from client.currentSpell(id); a spell whose answer
--                  was not read is left out; nil when the client has no
--                  such read or no spell was read
--       spells     each row also gets inRange = client.inRange(spell id)
--                  when the client has that read and the answer is true or
--                  false; otherwise range stays not known
--   D.Step(client, pack[, prefs, bias, applied, role]) -> view
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
--     notRead     the reads the pack names in options.reads (formKnown,
--                 buffs, targetDebuffs) that came back not known, in the
--                 pack's order; {} when every one was read (section 187)
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
-- The role you chose (Rotation/Role.lua declares the row).
D.ROLE = "spec.role"
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

-- What is queued or toggled on, by spell name: only answers read as yes
-- or no are kept; nil when nothing could be read (section 183).
local function currentOf(client, ids)
    if type(client.currentSpell) ~= "function" or type(ids) ~= "table" then return nil end
    local out, any = {}, false
    for name, id in pairs(ids) do
        local asked, on = pcall(client.currentSpell, id)
        if asked and type(on) == "boolean" then
            out[name] = on
            any = true
        end
    end
    return any and out or nil
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

local ROLES = { dps = true, heal = true, tank = true }
local function roleIn(pack, role)
    if type(role) ~= "string" or not ROLES[role] then return nil end
    if type(pack) ~= "table" or type(pack.roles) ~= "table" or type(pack.roles[role]) ~= "table" then return nil end
    return role
end

function D.Read(client, pack, ids, role)
    -- Lead section 187: the form is asked of the client once for a read,
    -- and both fields (form, formKnown) come from that one answer.
    -- The answer is kept only for the other field of the pair, and used
    -- once: a field asked again asks the client again.
    local kept
    local function form(field)
        if kept ~= nil and kept.field ~= field then
            local name, known = kept.name, kept.known
            kept = nil
            return name, known
        end
        local name, known = client.formName()
        kept = { field = field, name = name, known = known }
        return name, known
    end
    return function(field)
        if field == "role" then return roleIn(pack, role) end
        if field == "dead" then return client.dead() end
        if field == "inCombat" then return client.inCombat() end
        if field == "stealthed" then
            if type(client.stealthed) ~= "function" then return nil end
            return client.stealthed()
        end
        if field == "hostile" then return hostileOf(client) end
        if field == "spells" then return spellRows(client, pack, ids) end
        if field == "buffs" then
            if type(client.playerBuffs) ~= "function" then return nil end
            return client.playerBuffs()
        end
        if field == "targetDebuffs" then
            if type(client.targetDebuffs) ~= "function" then return nil end
            return client.targetDebuffs()
        end
        if field == "form" then
            if type(client.formName) ~= "function" then return nil end
            local name = form("form")
            return type(name) == "string" and name or nil
        end
        if field == "formKnown" then
            if type(client.formName) ~= "function" then return nil end
            local name, known = form("formKnown")
            if known ~= true then return nil end
            if name == nil or type(name) == "string" then return true end
            return nil
        end
        if field == "current" then return currentOf(client, ids) end
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
    -- Lead section 187: with nothing picked, the reason shown is the last
    -- step that was stopped by a read nobody gave ("not known ..."), not
    -- the step after it. A list that had rules ready but could not read
    -- their range was followed by "nothing out of range", and that was
    -- what the player was told.
    if type(last) == "table" and last.result ~= "pick" then
        for i = #trace, 1, -1 do
            local row = trace[i]
            if type(row) == "table" and type(row.note) == "string" and row.note:find("not known", 1, true) then
                last = row
                break
            end
        end
    end
    if type(last) == "table" then
        why.step, why.result, why.note, why.spell = last.step, last.result, last.note, last.spell
    end
    return why
end

function D.Step(client, pack, prefs, bias, applied, role)
    if type(pack) ~= "table" then
        return { pack = false, trace = {}, why = { pack = false } }
    end
    local ids, missing = RR.SpellIds(pack, client.spellId)
    local snapshot = ns.Snapshot(D.Read(client, pack, ids, role))
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

    -- The reads the pack leans on that came back not known (section 187).
    local readsMissing = {}
    local options = type(pack.options) == "table" and pack.options or {}
    for _, field in ipairs(type(options.reads) == "table" and options.reads or {}) do
        if snapshot[field] == nil then readsMissing[#readsMissing + 1] = field end
    end

    return {
        pack = true,
        snapshot = snapshot,
        suggestion = suggestion,
        trace = trace,
        lockdown = lockdown,
        keys = keys,
        attrs = attrs,
        unread = notRead,
        notRead = readsMissing,
        missing = missing,
        passed = passed,
        why = D.Why(snapshot, trace, keys, lockdown),
    }
end

-- One tick's work: the class's pack, then a step.
local function work(client, packs, role)
    local class = type(client.class) == "function" and client.class() or nil
    local pack = type(class) == "string" and type(packs) == "table" and packs[class] or nil
    return D.Step(client, pack, nil, nil, nil, role)
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
        local ok, got = pcall(work, ctx.client, packs or ns.Packs, ctx.settings:get(D.ROLE))
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
