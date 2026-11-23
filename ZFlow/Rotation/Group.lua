local _, ns = ...

-- P-PARTY (lead section 233, rows N7, N51, MAGE-6, PRIEST-2, DRUID-1,
-- CHOOSE-3): your group's buffs and the curses and poisons on them you
-- could remove, suggested out of a fight. Ported from Flow's
-- Modules/Rotation/Engine.lua E:GroupBuff and E:Dispel (there the target
-- button cast them).
--
-- Look only. The suggestion names the party unit and the spell, with
-- look = true and the player's name in `member`; Rotation/Cast.lua never
-- puts a look-only suggestion on the key, so nothing is cast on anyone.
-- The name is shown on the icon's caption only (UI/RotationIcon.lua): it is
-- never in a reason, a trace note or a diag line, and never saved.
--
--   G.Read(client, field, known) -> the snapshot field "party" or "groupOn"
--     Driver.lua's D.Read hands the fields here with known = { pack, ids }.
--     party: client.party(), read only out of a fight (client.inCombat()
--       false) and with the setting not off; each member with
--       kind     GroupTip.Kind(class, role, power), or nil
--       reach    { [spell] = true | false } client.reach(id, unit) for each
--                group row's and each dispel's spell; a spell not known: left out
--       has      { [spell] = seconds left | true | false } client.unitBuff
--                over the row's aura names: seconds (or true, up with the
--                time not known), false (read, not there); left out: not known
--       debuffTypes  client.unitDebuffTypes(unit), or nil
--       The read is kept one second for the same client and pack (Flow kept
--       it a second too: reading the group ten times a second is too much),
--       and forgotten on GROUP_ROSTER_UPDATE.
--     groupOn: the setting G.SETTING; nil before the module starts.
--   G.Step(s, pack, prefs) -> suggestion | nil, note     the chooser's "group" step
--   G.Fits(who, kind, class) -> true | false
--
-- Not tested in game: every client read it uses is a first guess
-- (Core/Client.lua c.party, c.reach, c.unitDebuffTypes, c.unitBuff).

ns.PartyGroup = {}
local G = ns.PartyGroup
local R = ns.Rotation

G.NAME = "partyGroup"
-- The key Flow's import writes (Import/FromFlow.lua, rotation.groupBuffs).
G.SETTING = "rotation.groupBuffs"
G.KEEP = 1
G.REBUFF = 30
-- Who comes first: the tank, then the healer, then everyone else (Flow's ORDER).
G.ORDER = { tank = 1, healer = 2 }

local ctx
local kept   -- { client, pack, at, value }

-- Is the row for this player? "all", or a list holding their kind or class.
function G.Fits(who, kind, class)
    if who == "all" then return true end
    if type(who) ~= "table" then return false end
    for i = 1, #who do
        if (kind ~= nil and who[i] == kind) or (class ~= nil and who[i] == class) then return true end
    end
    return false
end

local function clock(client)
    if type(client.now) ~= "function" then return nil end
    local ok, t = pcall(client.now)
    if ok and type(t) == "number" and t == t then return t end
    return nil
end

local function text(v) return (type(v) == "string" and v ~= "") and v or nil end

-- The spells a member is asked about: each group row's and each dispel's.
local function spellsOf(pack)
    local out, seen = {}, {}
    for _, key in ipairs({ "groups", "dispels" }) do
        local rows = type(pack) == "table" and pack[key] or nil
        if type(rows) == "table" then
            for _, row in ipairs(rows) do
                local name = type(row) == "table" and row.spell or nil
                if type(name) == "string" and not seen[name] then
                    seen[name] = true
                    out[#out + 1] = name
                end
            end
        end
    end
    return out
end

local function readMember(client, m, pack, ids)
    local row = {
        unit = m.unit, name = text(m.name), class = text(m.class), role = text(m.role),
        power = (type(m.power) == "number" and m.power == m.power) and m.power or nil,
        reach = {}, has = {},
    }
    -- Not `x and v or nil`: that turns a read "no" into "not read".
    if type(m.dead) == "boolean" then row.dead = m.dead end
    if type(m.connected) == "boolean" then row.connected = m.connected end
    if type(ns.GroupTip) == "table" and type(ns.GroupTip.Kind) == "function" then
        row.kind = ns.GroupTip.Kind(row.class, row.role, row.power)
    end
    if type(client.reach) == "function" then
        for _, spell in ipairs(spellsOf(pack)) do
            local id = ids[spell]
            if type(id) == "number" then
                local ok, v = pcall(client.reach, id, m.unit)
                if ok and type(v) == "boolean" then row.reach[spell] = v end
            end
        end
    end
    if type(client.unitBuff) == "function" then
        for _, rule in ipairs(type(pack.groups) == "table" and pack.groups or {}) do
            if type(rule) == "table" and type(rule.spell) == "string" and row.has[rule.spell] == nil then
                local names = type(rule.aura) == "table" and rule.aura or { rule.spell }
                local ok, up, left = pcall(client.unitBuff, m.unit, names)
                if ok and up == true then
                    row.has[rule.spell] = (type(left) == "number" and left == left) and left or true
                elseif ok and up == false then
                    row.has[rule.spell] = false
                end
            end
        end
    end
    if type(client.unitDebuffTypes) == "function" then
        local ok, types = pcall(client.unitDebuffTypes, m.unit)
        if ok and type(types) == "table" then
            local copy = {}
            for kind, name in pairs(types) do
                if type(kind) == "string" then copy[kind] = type(name) == "string" and name or kind end
            end
            row.debuffTypes = copy
        end
    end
    return row
end

-- The members as the client gave them, each with what the step needs; nil
-- when the client does not say, or the read raised.
local function readParty(client, pack, ids)
    local ok, list = pcall(client.party)
    if not ok or type(list) ~= "table" then return nil end
    local out = {}
    for _, m in ipairs(list) do
        if type(m) == "table" and type(m.unit) == "string" and m.unit ~= "" then
            out[#out + 1] = readMember(client, m, pack, ids)
        end
    end
    return out
end

function G.Read(client, field, known)
    if type(client) ~= "table" then return nil end
    if field == "groupOn" then
        if not ctx or type(ctx.settings) ~= "table" then return nil end
        return ctx.settings:get(G.SETTING) ~= false
    end
    if field ~= "party" then return nil end
    if type(client.party) ~= "function" then return nil end
    if ctx and type(ctx.settings) == "table" and ctx.settings:get(G.SETTING) == false then return nil end
    if type(client.inCombat) ~= "function" then return nil end
    local okFight, fight = pcall(client.inCombat)
    if not okFight or fight ~= false then return nil end
    known = type(known) == "table" and known or {}
    local pack = type(known.pack) == "table" and known.pack or {}
    local ids = type(known.ids) == "table" and known.ids or {}
    local now = clock(client)
    if kept and now and kept.client == client and kept.pack == pack and now >= kept.at and now - kept.at < G.KEEP then
        return kept.value
    end
    local value = readParty(client, pack, ids)
    if value ~= nil and now then
        kept = { client = client, pack = pack, at = now, value = value }
    else
        kept = nil
    end
    return value
end

-- ------------------------------------------------------------------ choosing

local function allowed(prefs, name)
    return not (prefs and prefs.skip and prefs.skip[name])
end

-- Yours to cast now: known, not switched off, its own condition met, and
-- castable (a cooldown not read is not ready).
local function yours(s, row, prefs)
    if type(row) ~= "table" or type(row.spell) ~= "string" then return false end
    if not R.Knows(s, row.spell) or not allowed(prefs, row.spell) then return false end
    if row.when and not row.when(s) then return false end
    return true
end
local function castable(s, spell) return R.Castable(s, spell) == true end

-- Alive and online as far as was read: dead must be read as no; offline
-- read as yes skips them, not read does not (in reach says they are there).
local function alive(m) return m.dead == false and m.connected ~= false end

local function sortedKinds(types)
    local out = {}
    for kind in pairs(types) do out[#out + 1] = kind end
    table.sort(out)
    return out
end

-- The members, the tank first, then the healer, then everyone else, each
-- in party order.
local function ordered(party)
    local list = {}
    for i, m in ipairs(party) do
        if type(m) == "table" and type(m.unit) == "string" then list[#list + 1] = { m = m, i = i } end
    end
    table.sort(list, function(a, b)
        local oa, ob = G.ORDER[a.m.kind] or 3, G.ORDER[b.m.kind] or 3
        if oa ~= ob then return oa < ob end
        return a.i < b.i
    end)
    local out = {}
    for i, e in ipairs(list) do out[i] = e.m end
    return out
end

local function pick(spell, m, reason)
    return { spell = spell, kind = "group", look = true, unit = m.unit, member = m.name, reason = reason }
end

function G.Step(s, pack, prefs)
    if type(s) ~= "table" or type(pack) ~= "table" then return nil, "no group suggestions" end
    if s.groupOn == false then return nil, "suggestions for your group are switched off" end
    if not R.OutOfFight(s) then
        return nil, s.inCombat and "in a fight" or "not known whether you are in a fight"
    end
    if s.hostile == true then return nil, "an enemy is targeted" end
    if s.hostile ~= false then return nil, "not known whether you have a target" end
    if s.resting == true then return nil, "resting" end
    local party = s.party
    if type(party) ~= "table" then return nil, "your group not read" end
    local members = ordered(party)
    if #members == 0 then return nil, "nobody in your group" end

    -- A curse or poison first (Flow: E:Dispel came long before the buffs).
    for _, m in ipairs(members) do
        local types = m.debuffTypes
        if alive(m) and type(types) == "table" then
            for _, rule in ipairs(type(pack.dispels) == "table" and pack.dispels or {}) do
                if yours(s, rule, prefs) and castable(s, rule.spell)
                    and type(m.reach) == "table" and m.reach[rule.spell] == true then
                    for _, kind in ipairs(sortedKinds(rule.types or {})) do
                        if types[kind] then
                            return pick(rule.spell, m, string.format("%s for %s: %s", rule.spell, m.unit, string.lower(kind)))
                        end
                    end
                end
            end
        end
    end

    local rows = type(pack.groups) == "table" and pack.groups or {}
    if #rows == 0 then return nil, "no buffs for your group" end
    -- Who wants which row: every row that fits them and is yours; of the
    -- rows sharing a slot, only the first of those.
    local wanted = {}
    for i, m in ipairs(members) do
        local taken, w = {}, {}
        for j, row in ipairs(rows) do
            if yours(s, row, prefs) and G.Fits(row.who, m.kind, m.class) then
                local slot = type(row.slot) == "string" and row.slot or nil
                if not (slot and taken[slot]) then
                    if slot then taken[slot] = true end
                    w[j] = true
                end
            end
        end
        wanted[i] = w
    end
    -- Each row in order, for each member in order (Flow's order).
    local unsure = false
    for j, row in ipairs(rows) do
        if type(row) == "table" and type(row.spell) == "string" and castable(s, row.spell) then
            local rebuff = type(row.rebuff) == "number" and row.rebuff or G.REBUFF
            for i, m in ipairs(members) do
                if wanted[i][j] then
                    -- Not `t and t[k] or nil`: a read "missing" (false) must stay false.
                    local reach, has
                    if type(m.reach) == "table" then reach = m.reach[row.spell] end
                    if type(m.has) == "table" then has = m.has[row.spell] end
                    if not alive(m) then
                        if m.dead == nil then unsure = true end
                    elseif reach == true then
                        if has == false then
                            return pick(row.spell, m, string.format("%s for %s: missing", row.spell, m.unit))
                        elseif type(has) == "number" and has <= rebuff then
                            return pick(row.spell, m, string.format("%s for %s: running out", row.spell, m.unit))
                        elseif has == nil then
                            unsure = true
                        end
                    elseif reach == nil then
                        unsure = true
                    end
                end
            end
        end
    end
    if unsure then return nil, "your buffs on your group: not known for some" end
    return nil, "everyone has your buffs"
end

function G.Declare(k)
    local api = {}
    k:Module({
        name = G.NAME,
        needs = { "settings", "bus" },
        settings = { {
            key = G.SETTING, scope = "account", type = "bool", default = true,
            label = "Suggest buffs for your group",
            help = "Out of a fight, names a party member who is missing one of your buffs, or has a curse or "
                .. "poison you can remove, with the spell. It casts nothing; your key is unchanged.",
            group = "Rotation",
        } },
        start = function(c)
            ctx = c
            kept = nil
            -- Someone joined or left: read the group again at once.
            c.bus:on(G.NAME, "GROUP_ROSTER_UPDATE", function() kept = nil end)
        end,
        stop = function()
            ctx = nil
            kept = nil
        end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.partyGroup = G.Declare(ns)
