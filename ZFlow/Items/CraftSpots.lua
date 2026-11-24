local _, ns = ...

-- CraftSpots: where a craft of the player's own succeeded, saved as the
-- anvil, forge or cooking fire that craft needs. Lead section 414 (b).
--
-- The profession plan (Items/ProfPlan.lua) points a craft step at the
-- nearest seen station, but the only list of stations was
--   account "learned.keyStations"
-- which Rotation/KeyActions.lua writes, and only from a classic profession
-- window that names its tool. That list also decides what the key does by
-- a station, so nothing outside Rotation/ may write it. This module keeps
-- its own list,
--   account "learned.craftSpots" = { { kind, map, x, y } }
-- which no key reads: it only ever moves the profession arrow.
--
-- When the game says a cast of the player's succeeded
-- (UNIT_SPELLCAST_SUCCEEDED, unit "player") and the spell is a recipe in
-- the player's saved recipe book (by its id, else by the spell's name), the
-- player's place is saved as that recipe's station: a forge for a Mining
-- recipe (a smelt), else Nav/ProfStep.lua's N.PROF_STATION for the
-- profession (an anvil for Blacksmithing, a fire for Cooking). A profession
-- that needs no station saves nothing. A place within CraftSpots.REACH of a
-- saved one of the same kind is the same place. Past CraftSpots.MAX the
-- oldest goes.
--
-- The place saved is where the player stood, which is by the station, not
-- on it. A fire the player lit is saved like any other and will not be
-- there later: not told apart here.
--
--   CraftSpots.Kind(prof) -> kind or nil
--   CraftSpots.Recipe(book, id, name) -> the book's entry or nil
--   CraftSpots.Add(list, kind, pos) -> changed   (writes into list)
--   CraftSpots.Seen(client, store, id) -> report { ok, reason, kind, changed }
--   CraftSpots.All(store) -> the key's stations and these, one list (a copy)
--   CraftSpots.Declare(k) -> api   (api.last())
--   ns.use(CraftSpots.NAME) -> { Last }
--
-- This only reads the client and saves a place: it casts nothing and no key
-- reads what it saves. No station place is shipped. Not tested in game.
local CraftSpots = ns.CraftSpots or {}
ns.CraftSpots = CraftSpots

CraftSpots.NAME = "craftSpots"
CraftSpots.PATH = "learned.craftSpots"
CraftSpots.KEY_PATH = "learned.keyStations"
CraftSpots.BOOK_PATH = "learned.facts.recipeBook"
CraftSpots.EVENT = "UNIT_SPELLCAST_SUCCEEDED"   -- unit, castGUID, spellID
CraftSpots.REACH = 0.004
CraftSpots.MAX = 200
CraftSpots.SMELT_PROF = "Mining"
CraftSpots.SMELT_KIND = "forge"

local function share(v)
    return type(v) == "number" and v == v and v >= 0 and v <= 1
end

local function spot(s)
    return type(s) == "table" and type(s.kind) == "string" and s.map ~= nil and share(s.x) and share(s.y)
end

function CraftSpots.Kind(prof)
    if type(prof) ~= "string" then return nil end
    if prof == CraftSpots.SMELT_PROF then return CraftSpots.SMELT_KIND end
    local kinds = type(ns.Nav) == "table" and ns.Nav.PROF_STATION or nil
    local kind = type(kinds) == "table" and kinds[prof] or nil
    if type(kind) == "string" then return kind end
    return nil
end

function CraftSpots.Recipe(book, id, name)
    if type(book) ~= "table" then return nil end
    if type(id) == "number" then
        for _, r in pairs(book) do
            if type(r) == "table" and r.id == id then return r end
        end
    end
    if type(name) == "string" and type(book[name]) == "table" then return book[name] end
    return nil
end

function CraftSpots.Add(list, kind, pos)
    if type(list) ~= "table" or type(kind) ~= "string" then return false end
    if type(pos) ~= "table" or pos.map == nil or not (share(pos.x) and share(pos.y)) then return false end
    for _, s in ipairs(list) do
        if spot(s) and s.kind == kind and s.map == pos.map
            and math.abs(s.x - pos.x) <= CraftSpots.REACH and math.abs(s.y - pos.y) <= CraftSpots.REACH then
            return false
        end
    end
    list[#list + 1] = { kind = kind, map = pos.map, x = pos.x, y = pos.y }
    while #list > CraftSpots.MAX do table.remove(list, 1) end
    return true
end

local function ask(client, read, ...)
    if type(client) ~= "table" or type(client[read]) ~= "function" then return nil end
    local ok, v = pcall(client[read], ...)
    if ok then return v end
    return nil
end

local function saved(store, scope, path)
    if type(store) ~= "table" or type(store.get) ~= "function" then return nil end
    local ok, v = pcall(store.get, store, scope, path)
    if ok then return v end
    return nil
end

local function copy(list)
    local out = {}
    for _, s in ipairs(type(list) == "table" and list or {}) do
        if spot(s) then out[#out + 1] = { kind = s.kind, map = s.map, x = s.x, y = s.y } end
    end
    return out
end

function CraftSpots.Seen(client, store, id)
    local report = { changed = false }
    local r = CraftSpots.Recipe(saved(store, "char", CraftSpots.BOOK_PATH), id, ask(client, "spellName", id))
    if r == nil then
        report.ok, report.reason = false, "not a recipe of yours"
        return report
    end
    report.kind = CraftSpots.Kind(r.profession)
    if report.kind == nil then
        report.ok, report.reason = false, "that craft needs no station"
        return report
    end
    if type(store) ~= "table" or type(store.set) ~= "function" then
        report.ok, report.reason = false, "the place cannot be saved"
        return report
    end
    local list = copy(saved(store, "account", CraftSpots.PATH))
    report.changed = CraftSpots.Add(list, report.kind, ask(client, "position"))
    if report.changed and store:set("account", CraftSpots.PATH, list) ~= true then
        report.ok, report.reason, report.changed = false, "the place cannot be saved", false
        return report
    end
    report.ok = true
    return report
end

function CraftSpots.All(store)
    local out = copy(saved(store, "account", CraftSpots.KEY_PATH))
    for _, s in ipairs(copy(saved(store, "account", CraftSpots.PATH))) do out[#out + 1] = s end
    return out
end

function CraftSpots.Declare(k)
    local api = {}
    local last
    function api.last() return last end
    k:Module({
        name = CraftSpots.NAME,
        needs = { "client", "store", "bus" },
        provides = { Last = api.last },
        start = function(ctx)
            ctx.bus:on(CraftSpots.NAME, CraftSpots.EVENT, function(unit, _, id)
                if unit ~= "player" then return end
                last = CraftSpots.Seen(ctx.client, ctx.store, id)
            end)
        end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.craftSpots = CraftSpots.Declare(ns)
