local _, ns = ...

-- Repair (L6-C, S6): an early warning when gear you wear is worn down, and
-- a guide step to the nearest repair vendor this player's characters have
-- seen, when one is known; otherwise the warning is text only.
--
-- LOOK ONLY. Nothing here repairs, buys, clicks or opens anything: it reads
-- durability and saved places and says what it sees. Repairing stays the
-- player's (auto-repair is a vendor automation decided elsewhere).
--
-- Pure parts (no game reads; plain tables in):
--   w      = Repair.Worst(readings, threshold)  the most worn item, or nil
--   low    = Repair.Low(pct, threshold)         true only for a known share under it
--   vendor = Repair.Vendor(npcs, here)          the repair vendor to go to, or nil
--   step   = Repair.Step(vendor, here)          a guide step, or nil (text only)
--   lines  = Repair.Lines(worst, threshold, vendor)
-- Ported from Flow's Modules/Items/Repair.lua:13-37 (threshold, worst, low)
-- and :57-72 (the words, without Flow's own name and its auto-repair line).
--
--   readings  what client.durability() gives (CLIENT NEED):
--             { [slot] = { cur, max } } for the items you wear that have
--             durability; nil when it was not read
--   w         { pct = 0..1, slot, low = how many are under the threshold }
--   npcs      account "learned.places.npcs": { [name] = { map, x, y,
--             roles = { repair = true }, factions = { [faction] = true }, seen } }
--   here      { position = { map, x, y }, zone = { cont }, faction,
--               mapSize = fn(map) -> { w, h } in yards }; what is not known
--             is left out and not guessed
--   vendor    { name, map, x, y, onMap }
--   step      { label = "Repair at <name>", place = { cont, map, x, y },
--               radius = Repair.NEAR }, the shape Nav/ProfStep gives
--
-- Module: Repair.Declare(k) -> api; api.current() -> { lines, step, worst }
-- while something is low, else nil. One chat line when gear first goes low;
-- not again until it has been fine in between. Checked on entering the world
-- and on UPDATE_INVENTORY_DURABILITY (CLIENT NEED: the event).
-- Setting: "repair.warnBelow" (number, 0..1, default 0.20): the row is the
-- lead's to add; until it is there the default is used.

local Repair = {}
ns.Repair = Repair

Repair.THRESHOLD = 0.20      -- Flow's Repair.lua:13
Repair.NEAR = 10             -- yards from the vendor that count as there (as N.PROF_NEAR)
Repair.NAME = "repairWarn"
Repair.SETTING = "repair.warnBelow"
Repair.EVENT = "UPDATE_INVENTORY_DURABILITY"
Repair.NO_VENDOR = "No repair vendor known yet: one is learned each time you use one."

local function finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function share(v)
    return finite(v) and v >= 0 and v <= 1
end

local function thresholdOf(threshold)
    if finite(threshold) and threshold > 0 and threshold <= 1 then return threshold end
    return Repair.THRESHOLD
end

function Repair.Worst(readings, threshold)
    if type(readings) ~= "table" then return nil end
    threshold = thresholdOf(threshold)
    local pct, slot, low
    for s, r in pairs(readings) do
        if type(r) == "table" and finite(r.cur) and finite(r.max) and r.max > 0 and r.cur >= 0 and r.cur <= r.max then
            local p = r.cur / r.max
            low = (low or 0) + (p < threshold and 1 or 0)
            if pct == nil or p < pct or (p == pct and tostring(s) < tostring(slot)) then pct, slot = p, s end
        end
    end
    if pct == nil then return nil end
    return { pct = pct, slot = slot, low = low }
end

function Repair.Low(pct, threshold)
    return finite(pct) and pct < thresholdOf(threshold) or false
end

-- Most recently seen first, then the lowest name; one with a date first.
local function before(a, b)
    if a.seen ~= b.seen then
        if a.seen and b.seen then return a.seen > b.seen end
        return a.seen ~= nil
    end
    return a.name < b.name
end

local function sizeOf(here, map)
    if type(here.mapSize) ~= "function" then return nil end
    local ok, size = pcall(here.mapSize, map)
    if not ok or type(size) ~= "table" then return nil end
    if not (finite(size.w) and finite(size.h) and size.w > 0 and size.h > 0) then return nil end
    return size
end

-- A repair vendor of your faction on your map, the nearest when distance
-- can be told; else the most recently seen one anywhere. nil when none is
-- known, or your faction is not known.
function Repair.Vendor(npcs, here)
    if type(npcs) ~= "table" then return nil end
    here = type(here) == "table" and here or {}
    if type(here.faction) ~= "string" then return nil end
    local list = {}
    for name, e in pairs(npcs) do
        if type(name) == "string" and type(e) == "table" and type(e.roles) == "table" and e.roles.repair == true
            and finite(e.map) and share(e.x) and share(e.y)
            and type(e.factions) == "table" and e.factions[here.faction] == true then
            list[#list + 1] = { name = name, map = e.map, x = e.x, y = e.y, seen = finite(e.seen) and e.seen or nil }
        end
    end
    if #list == 0 then return nil end
    local at = type(here.position) == "table" and here.position or nil
    local onMap = {}
    if at and at.map ~= nil then
        for _, c in ipairs(list) do
            if c.map == at.map then onMap[#onMap + 1] = c end
        end
    end
    local pick, near = nil, #onMap > 0
    local pool = near and onMap or list
    local size = near and finite(at.x) and finite(at.y) and sizeOf(here, at.map) or nil
    local bestD
    for _, c in ipairs(pool) do
        if size then
            local dx, dy = (c.x - at.x) * size.w, (c.y - at.y) * size.h
            local d = dx * dx + dy * dy
            if not pick or d < bestD or (d == bestD and before(c, pick)) then pick, bestD = c, d end
        elseif not pick or before(c, pick) then
            pick = c
        end
    end
    return { name = pick.name, map = pick.map, x = pick.x, y = pick.y, onMap = near }
end

function Repair.Step(vendor, here)
    if type(vendor) ~= "table" or type(vendor.name) ~= "string" then return nil end
    here = type(here) == "table" and here or {}
    local cont
    if vendor.onMap and type(here.zone) == "table" then cont = here.zone.cont end
    local step = { place = { cont = cont, map = vendor.map, x = vendor.x, y = vendor.y }, radius = Repair.NEAR }
    local label = "Repair at " .. vendor.name
    local max = ns.Nav and ns.Nav.Waypoint and ns.Nav.Waypoint.LABEL_MAX or 40
    if #label <= max then step.label = label end
    return step
end

function Repair.Lines(worst, threshold, vendor)
    threshold = thresholdOf(threshold)
    if type(worst) ~= "table" or not Repair.Low(worst.pct, threshold) then return {} end
    local pct = math.floor(worst.pct * 100 + 0.5)
    local more = ""
    if finite(worst.low) and worst.low > 1 then
        more = string.format(" (%d items under %d%%)", worst.low, math.floor(threshold * 100 + 0.5))
    end
    local out = { string.format("An item you wear is at %d%% durability%s.", pct, more) }
    if type(vendor) == "table" and type(vendor.name) == "string" then
        out[#out + 1] = "Repair at " .. vendor.name .. "."
    else
        out[#out + 1] = Repair.NO_VENDOR
    end
    return out
end

-- One read of the client, or nil when it has no such read or it fails.
local function ask(client, name, ...)
    if type(client) ~= "table" or type(client[name]) ~= "function" then return nil end
    local ok, v = pcall(client[name], ...)
    if not ok then return nil end
    return v
end

local function saved(store, scope, path)
    if type(store) ~= "table" or type(store.get) ~= "function" then return nil end
    local ok, v = pcall(store.get, store, scope, path)
    if not ok then return nil end
    return v
end

-- One check: the warning, or nil when nothing is low (or nothing was read).
function Repair.Check(client, store, threshold)
    local worst = Repair.Worst(ask(client, "durability"), threshold)
    if not worst or not Repair.Low(worst.pct, threshold) then return nil end
    local here = {
        position = ask(client, "position"), zone = ask(client, "zone"), faction = ask(client, "faction"),
        mapSize = function(map) return ask(client, "mapSize", map) end,
    }
    local vendor = Repair.Vendor(saved(store, "account", "learned.places.npcs"), here)
    return { worst = worst, lines = Repair.Lines(worst, threshold, vendor), step = Repair.Step(vendor, here) }
end

function Repair.Declare(k)
    local api = {}
    local current, warned = nil, false
    function api.current() return current end
    k:Module({
        name = Repair.NAME,
        needs = { "client", "store", "bus", "settings" },
        provides = { Current = api.current },
        start = function(ctx)
            local function check()
                current = Repair.Check(ctx.client, ctx.store, ctx.settings:get(Repair.SETTING))
                if current and not warned then
                    warned = true
                    local id = k.id or ns.id
                    ctx.client.print(id.title .. ": " .. table.concat(current.lines, " "))
                elseif not current then
                    warned = false
                end
            end
            ctx.bus:on(Repair.NAME, "PLAYER_ENTERING_WORLD", check)
            ctx.bus:on(Repair.NAME, Repair.EVENT, check)
        end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.repair = Repair.Declare(ns)
