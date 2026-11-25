local _, ns = ...
-- The zone notice (Flow-parity row A2-24, the data half): after a while in
-- a zone where the player has no quests to do, the notice says which zone
-- that is, why, and a zone with more. Data only: no bar, no chat line, no
-- arrow; nothing acts. The bar is another module's, built on
-- ns.use("zoneNotice").Notice() and the event Z.EVENT.
--
-- What it says comes from the game and the player's own Questie, through
-- two other modules; nothing of Questie is read here and no zone, level or
-- quest table ships here:
--   * whereNext (Nav/WhereNext.lua) Zones(): the zones on the player's
--     continent with quests in the player's level range, and how many.
--     That count is by level, race, class, log and done only: quest
--     chains, reputation and skill are not checked, and Z.WHY_NONE says so.
--   * zoneLeft (Nav/ZoneLeft.lua) Left(): the player's own quests with
--     something left to do on the map they stand on.
-- What is not known stays not known: while whereNext is still reading, or
-- cannot answer (no Questie, level or continent not known, no quest data),
-- or the zone, the time or the player's quests here are not known, there
-- is no notice. Unknown is never "you do not quest here".
--
-- The rules are legacy Flow's (Modules/Nav/ZoneNotice.lua at a529eea; no
-- data of it):
--   * a look every Z.CHECK seconds and on a zone change (lines 32, 226, 228);
--   * nothing until the player has been in the zone Z.SETTLE seconds
--     without a break; a new zone, or the zone not known for a moment,
--     starts the wait again (lines 34, 37, 204-207, 216);
--   * nothing on a flight, in an instance or in a fight (lines 191-196);
--     only a plain yes counts, as there;
--   * nothing for a zone the player said No thanks to, for this
--     character (lines 40-48, 57), nothing for one of the player's zones
--     (Quest here, line 181; Nav.lua:957-961) and nothing with the setting
--     off (line 50);
--   * while all of that holds the notice stays; when one stops holding it
--     is put away, and it comes up again when they hold again (line 217).
-- Not Flow's: which zones. Flow asked about a zone that had quests for the
-- player and was not ticked in its Zones list. Z-Flow has no such list, so
-- the notice is for the zone with nothing for the player: whereNext does
-- not list it and no quest of the player's has a step there. Flow named no
-- other zone; here the first other zone of whereNext's answer is given.
--
-- Pure:
--   Z.Settled(seconds, wait) -> bool
--   Z.Busy(onTaxi, instance, inCombat) -> bool; instance = { inside, kind }
--   Z.Listed(list, map) -> whereNext's row for the map, or nil
--   Z.Better(list, map) -> { map, name, count } (a copy) or nil: the first
--     row of whereNext's answer that is another map with a quest
--   Z.MayAsk(s) -> bool; s = { zone, on, answered, busy, settled }
--   Z.Wanted(s) -> bool; s as above with listed (true, false; nil not
--     known) and mine (the player's quests with a step here; nil not known)
--   Z.Build(map, name, list, info) -> the notice
--
-- Module "zoneNotice" provides:
--   Notice() -> nil, or the notice as of the last look (do not change it):
--     zone     { map, name }: the zone the player is in (client.zone());
--              name is client.mapName(map), absent when the client does
--              not say
--     reason   Z.WHY_NONE
--     count    0: whereNext's finished answer does not list the zone
--     better   { map, name, count } or nil when whereNext lists no other
--              zone; name absent when whereNext has none
--     unplaced how many quests in the level range whereNext could place in
--              no zone (its info.noZone); they may be here. Z.UNPLACED_ONE
--              and Z.UNPLACED say it.
--     info     a copy of whereNext's info: level, doneKnown, logKnown,
--              raceKnown, classKnown, noZone
--   QuestHere() -> true when a notice was up: keeps "I quest here" for the
--     notice's zone, char Z.YES [map] = true, and puts the notice away.
--   NoThanks() -> true when a notice was up: keeps "do not ask again" for
--     the notice's zone, char Z.NO [map] = true, and puts the notice away.
--     Either way that zone is not asked about again on this character, and
--     nothing else is changed: no route, no arrow, no setting.
--   Answer(map) -> Z.SAID_YES, Z.SAID_NO or nil
--   Forget(map) -> true when an answer was there: drops it, so the zone is
--     asked about again.
-- Z.EVENT is sent on the bus when the notice comes up (with the zone's
-- map) and when it is put away (with nil); not at every look.
-- Not tested in game.
ns.Nav = ns.Nav or {}
local N = ns.Nav
local Z = {}
N.ZoneNotice = Z

Z.NAME = "zoneNotice"
Z.ZONES = "whereNext"             -- the module asked for the zones
Z.LEFT = "zoneLeft"               -- the module asked for the player's quests here
Z.SETTING = "nav.zoneNotice"
Z.EVENT = "zoneNotice.changed"
-- Both char, { [map] = true }, where Flow kept the same two answers and
-- where the Flow import puts them (Import/FromFlow.lua: nav.zoneNo,
-- nav.zonesOn), so an answer given in Flow still holds.
Z.NO = "settings.nav.zoneNo"
Z.YES = "settings.nav.zonesOn"
Z.SAID_NO, Z.SAID_YES = "no", "yes"
Z.CHECK = 2                       -- seconds between looks (Flow's Z.CHECK)
Z.SETTLE = 30                     -- seconds in a zone before the notice (Flow's Z.SETTLE)
Z.ASKS = 60                       -- looks in one visit that may find whereNext still reading

Z.WHY_NONE = "Questie shows no quests in your level range here that are not already in your log or done. "
    .. "Quest chains, reputation and skill are not checked."
Z.UNPLACED_ONE = "1 quest in your level range could not be placed in any zone."
Z.UNPLACED = "%d quests in your level range could not be placed in any zone."

local function finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function ask(client, name, ...)
    if type(client) ~= "table" or type(client[name]) ~= "function" then return nil end
    local ok, v = pcall(client[name], ...)
    if not ok then return nil end
    return v
end

-- ------------------------------------------------------------------ pure

function Z.Settled(seconds, wait)
    if not finite(seconds) then return false end
    if not finite(wait) then wait = Z.SETTLE end
    return seconds >= wait
end

function Z.Busy(onTaxi, instance, inCombat)
    if onTaxi == true or inCombat == true then return true end
    return type(instance) == "table" and instance.inside == true
end

function Z.Listed(list, map)
    if type(list) ~= "table" or map == nil then return nil end
    for _, z in ipairs(list) do
        if type(z) == "table" and z.map == map then return z end
    end
    return nil
end

function Z.Better(list, map)
    if type(list) ~= "table" then return nil end
    for _, z in ipairs(list) do
        if type(z) == "table" and z.map ~= nil and z.map ~= map and finite(z.count) and z.count >= 1 then
            return { map = z.map, name = z.name, count = z.count }
        end
    end
    return nil
end

function Z.MayAsk(s)
    if type(s) ~= "table" or s.zone == nil then return false end
    return s.on == true and s.answered == false and s.busy == false and s.settled == true
end

function Z.Wanted(s)
    if not Z.MayAsk(s) then return false end
    return s.listed == false and s.mine == 0
end

function Z.Build(map, name, list, info)
    local n = { zone = { map = map }, reason = Z.WHY_NONE, count = 0, better = Z.Better(list, map),
                unplaced = 0, info = {} }
    if type(name) == "string" and name ~= "" then n.zone.name = name end
    if type(info) == "table" then
        for key, v in pairs(info) do n.info[key] = v end
        if finite(info.noZone) and info.noZone > 0 then n.unplaced = info.noZone end
    end
    return n
end

-- ---------------------------------------------------------------- module

function Z.Declare(k)
    local api = {}
    local ctx
    local notice
    local said = {}               -- [map] = Z.SAID_NO | Z.SAID_YES, this session
    -- The visit: the zone, when the player came into it (nil: the time was
    -- not known), how often whereNext was found still reading, and the
    -- player's quests with a step here once counted.
    local at = { asks = 0 }

    local function put(n)
        local was = notice
        notice = n
        if n == nil and was == nil then return end
        if n ~= nil and was ~= nil and was.zone.map == n.zone.map then return end
        local map
        if n ~= nil then map = n.zone.map end
        if ctx and type(ctx.bus) == "table" then ctx.bus:emit(Z.EVENT, map) end
    end

    local function on()
        local s = ctx and ctx.settings
        if type(s) ~= "table" or type(s.get) ~= "function" then return true end
        local ok, v = pcall(s.get, s, Z.SETTING)
        return not (ok and v == false)
    end

    local function saved(path)
        local st = ctx and ctx.store
        if type(st) ~= "table" or type(st.get) ~= "function" then return nil end
        local ok, v = pcall(st.get, st, "char", path)
        if ok and type(v) == "table" then return v end
        return nil
    end

    -- Sets or drops one map in the table at path, writing a new table.
    local function keep(path, map, yes)
        local st = ctx and ctx.store
        if type(st) ~= "table" or type(st.set) ~= "function" then return false end
        local was, now = saved(path), {}
        if was then
            for key, v in pairs(was) do now[key] = v end
        end
        if yes then now[map] = true else now[map] = nil end
        local ok, done = pcall(st.set, st, "char", path, now)
        return ok and done == true
    end

    function api.answer(map)
        if map == nil then return nil end
        if said[map] ~= nil then return said[map] end
        local no, yes = saved(Z.NO), saved(Z.YES)
        if no and no[map] == true then return Z.SAID_NO end
        if yes and yes[map] == true then return Z.SAID_YES end
        return nil
    end

    local function reply(path, word)
        local n = notice
        if type(n) ~= "table" then return false end
        local map = n.zone.map
        -- Kept for the session even when the saved data cannot be written.
        said[map] = word
        keep(path, map, true)
        put(nil)
        return true
    end

    function api.questHere() return reply(Z.YES, Z.SAID_YES) end
    function api.noThanks() return reply(Z.NO, Z.SAID_NO) end

    function api.forget(map)
        if map == nil then return false end
        local had = said[map] ~= nil
        said[map] = nil
        for _, path in ipairs({ Z.NO, Z.YES }) do
            local t = saved(path)
            if t and t[map] ~= nil then
                had = true
                keep(path, map, false)
            end
        end
        return had
    end

    -- whereNext's answer as it gives it; nothing when it is not there.
    local function zones()
        local use = ctx and ctx.use
        if type(use) ~= "function" then return nil end
        local mod = use(Z.ZONES)
        if type(mod) ~= "table" or type(mod.Zones) ~= "function" then return nil end
        local ok, list, why, info = pcall(mod.Zones)
        if not ok then return nil end
        return list, why, info
    end

    -- How many of the player's quests have a step on their map, or nil
    -- when zoneLeft is not there or does not know.
    local function mineHere()
        local use = ctx and ctx.use
        if type(use) ~= "function" then return nil end
        local mod = use(Z.LEFT)
        if type(mod) ~= "table" or type(mod.Left) ~= "function" then return nil end
        local ok, list = pcall(mod.Left)
        if not ok or type(list) ~= "table" then return nil end
        return #list
    end

    local function look()
        if not ctx then return end
        local c = ctx.client
        local zone
        local z = ask(c, "zone")
        if type(z) == "table" and type(z.zone) == "number" then zone = z.zone end
        local now = ask(c, "now")
        if not (finite(now) and now > 0) then now = nil end
        if zone ~= at.zone then
            at = { zone = zone, since = now, asks = 0 }
        elseif at.since == nil then
            at.since = now
        end
        local s = { zone = zone, on = on(), answered = api.answer(zone) ~= nil,
            busy = Z.Busy(ask(c, "onTaxi"), ask(c, "instance"), ask(c, "inCombat")),
            settled = now ~= nil and at.since ~= nil and Z.Settled(now - at.since) }
        if not Z.MayAsk(s) or at.asks >= Z.ASKS then
            put(nil)
            return
        end
        local list, why, info = zones()
        if type(list) ~= "table" then
            -- Still reading: nothing yet, and asked again at a later look,
            -- Z.ASKS times a visit. whereNext bounds its own tries.
            local W = N.WhereNext
            if W and why == W.WHY_READING then at.asks = at.asks + 1 else at.asks = 0 end
            put(nil)
            return
        end
        at.asks = 0
        s.listed = Z.Listed(list, zone) ~= nil
        if not s.listed then
            if at.mine == nil then at.mine = mineHere() end
            s.mine = at.mine
        end
        if not Z.Wanted(s) then
            put(nil)
            return
        end
        local name = ask(c, "mapName", zone)
        put(Z.Build(zone, name, list, info))
    end

    k:Setting({ key = Z.SETTING, scope = "account", type = "bool", default = true,
        label = "Say when a zone has no quests in your level range", group = "travel.route",
        help = "After 30 seconds in a zone where Questie shows no quests in your level range and none of your quests has a step, a notice names a zone on this continent that has some. Quest chains, reputation and skill are not checked. It changes nothing.",
        synonyms = { "zone", "quests", "notice", "level" } })

    k:Module({
        name = Z.NAME,
        needs = { "client", "store", "settings", "bus", Z.ZONES },
        provides = {
            Notice = function() return notice end,
            QuestHere = function() return api.questHere() end,
            NoThanks = function() return api.noThanks() end,
            Answer = function(map) return api.answer(map) end,
            Forget = function(map) return api.forget(map) end,
        },
        events = {
            ZONE_CHANGED_NEW_AREA = function() look() end,
            PLAYER_ENTERING_WORLD = function() look() end,
            -- The player's quests changed: they are counted again at the next look.
            QUEST_LOG_UPDATE = function() at.mine = nil end,
        },
        ticks = { { every = Z.CHECK, when = "always", run = function() look() end } },
        start = function(c)
            ctx = c
            notice, said, at = nil, {}, { asks = 0 }
        end,
        stop = function()
            ctx, notice, at = nil, nil, { asks = 0 }
        end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login. It
-- asks whereNext nothing until the player has been in a zone Z.SETTLE
-- seconds.
ns.zoneNotice = Z.Declare(ns)
