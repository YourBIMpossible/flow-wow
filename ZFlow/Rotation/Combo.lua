local _, ns = ...

-- Combo points for the finisher (ROGUE-2, lead section 236): when is a
-- finisher due. The rotation gets snapshot.finisherReady from it (through
-- Rotation/Driver.lua, extra.combo).
--
-- Two ways, the first that answers wins:
--   * read: client.combo().points, when the client gives a plain whole
--     number (GetComboPoints("player", "target"), else UnitPower of the
--     combo power type; Core/Client.lua c.combo). Whether 16001 gives one
--     is not known: combo points may be a hidden amount (R.FROM_AMOUNT in
--     Rotation/Snapshot.lua). A hidden or missing answer is not a read.
--   * counted: an ESTIMATE kept here from your own casts that went off
--     (UNIT_SPELLCAST_SUCCEEDED, unit "player"): a builder adds its points,
--     a finisher spends them all. A new target (PLAYER_TARGET_CHANGED) and
--     the end of the fight (PLAYER_REGEN_ENABLED) start again from 0. It
--     cannot see a miss, a dodge or a talent's extra point, so it can be
--     out by one or two; the read takes over as soon as the client gives one.
--
-- What counts comes from the class pack's options.combo:
--   options.combo = { need = 5, max = 5,
--                     builders = { ["Sinister Strike"] = 1, ... },
--                     finishers = { Eviscerate = true, ... } }
-- A class without options.combo is never counted and gets no finisherReady.
-- It only watches and counts: nothing is cast, pressed or set, and nothing
-- is saved. Not tested in game.
--
-- Pure:
--   CB.Add(count, name, rules)  -> the count after your cast of `name`
--   CB.Ready(read, counted, need) -> due (true/false, or nil when not
--                                    known), and how: "read" or "counted"
-- Module (ns.use("combo")):
--   Count() -> the counted estimate for the class you play, or nil when
--              your class has no options.combo or the class is not read

local CB = {}
ns.Combo = CB

CB.NAME = "combo"
CB.EVENT = "UNIT_SPELLCAST_SUCCEEDED"   -- unit, castGUID, spellID
CB.TARGET = "PLAYER_TARGET_CHANGED"
CB.FIGHT_END = "PLAYER_REGEN_ENABLED"
CB.MAX = 5

local function whole(v)
    return type(v) == "number" and v == v and v >= 0 and v ~= math.huge and v == math.floor(v)
end

function CB.Add(count, name, rules)
    count = whole(count) and count or 0
    if type(rules) ~= "table" or type(name) ~= "string" then return count end
    if type(rules.finishers) == "table" and rules.finishers[name] then return 0 end
    local add = type(rules.builders) == "table" and rules.builders[name] or nil
    if not whole(add) then return count end
    local most = whole(rules.max) and rules.max or CB.MAX
    return math.min(count + add, most)
end

function CB.Ready(read, counted, need)
    if not whole(need) or need < 1 then return nil, nil end
    if whole(read) then return read >= need, "read" end
    if whole(counted) then return counted >= need, "counted" end
    return nil, nil
end

function CB.Declare(k, packs)
    local client
    local api = {}
    local count = 0

    local function read(fn, ...)
        if type(fn) ~= "function" then return nil end
        local ok, v = pcall(fn, ...)
        if ok then return v end
        return nil
    end

    local function rules()
        local class = client and read(client.class) or nil
        if type(class) ~= "string" then return nil end
        local all = packs or ns.Packs
        local pack = type(all) == "table" and all[class] or nil
        local options = type(pack) == "table" and pack.options or nil
        local combo = type(options) == "table" and options.combo or nil
        return type(combo) == "table" and combo or nil
    end

    local function cast(unit, _, id)
        if unit ~= "player" or type(id) ~= "number" then return end
        local r = rules()
        if not r then return end
        local name = read(client.spellName, id)
        count = CB.Add(count, type(name) == "string" and name or nil, r)
    end

    function api.count()
        if not rules() then return nil end
        return count
    end

    k:Module({
        name = CB.NAME,
        needs = { "client" },
        provides = { Count = api.count },
        start = function(ctx)
            client = ctx.client
            client.listen(CB.EVENT, cast)
            client.listen(CB.TARGET, function() count = 0 end)
            client.listen(CB.FIGHT_END, function() count = 0 end)
        end,
    })

    return api
end

-- The addon's own.
ns.combo = CB.Declare(ns)
