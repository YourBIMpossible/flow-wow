local _, ns = ...

-- RepairStep (S6): while the repair warning (Items/Repair.lua) is on, a
-- guide step to the nearest repair vendor this character has seen
-- (Nav/ServiceSeen.lua saves them, N.Nearest reads them). With none seen
-- on this map, the vendor the warning already knows from imported places;
-- with none at all, no step and the words of the warning alone.
--
-- LOOK ONLY. Nothing here repairs, buys, clicks or opens anything, and
-- nothing moves the player: it reads the warning and saved places and
-- gives a step for the arrow to show. Repairing stays with the player.
--
-- Ported from Flow 0.35.377 Modules/Items/Repair.lua: the nearest repair
-- vendor kept for 10 seconds (:39-55), the line that names it and its
-- distance (:66-68, without the name of the old addon), and the "repair"
-- stop that can be turned off (:96-118, there sell.repairStop). No vendor
-- data is carried here: places are only what this player has seen or
-- imported.
--
-- Pure parts (plain tables in):
--   step  = RepairStep.Of(warning, near)     a step, or nil
--   lines = RepairStep.Lines(warning, step)  what to say
--   place = RepairStep.Place(step)           a place for N.RoutePlan
--
--   warning  what ns.use("repairWarn").Current() gives while gear is low:
--            { worst = { pct, slot, low }, lines, step } ; else nil
--   near     what N.Nearest("repair", client, store) gives:
--            { kind, name, map, x, y, cont, yards } ; else nil
--   step     { kind = "repair", label, place = { cont, map, x, y }, radius,
--              yards (left out when not known), from = "seen" | "imported" }
--            the shape Nav/Errand and Nav/ProfStep give, with a kind
--
-- Module: RepairStep.Declare(k) -> api; api.step(), api.lines().
--   ns.use(RepairStep.NAME) -> { Step = api.step, Lines = api.lines }
-- Setting "nav.repairStep" (bool, default true): false turns the step off,
-- never the warning. The row is declared here, by the module that reads it.
-- Not seen in game: needs game test.

local RS = {}
ns.RepairStep = RS

RS.NAME = "repairStep"
RS.WARNING = "repairWarn"
RS.SETTING = "nav.repairStep"
RS.KIND = "repair"
RS.RADIUS = 10
RS.KEEP = 10
RS.LABEL = "Repair"

local function finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function share(v)
    return finite(v) and v >= 0 and v <= 1
end

local function text(v)
    if type(v) ~= "string" or v == "" then return nil end
    return v
end

local function low(warning)
    return type(warning) == "table" and type(warning.worst) == "table" and finite(warning.worst.pct)
end

local function labelMax()
    local N = ns.Nav
    return N and N.Waypoint and N.Waypoint.LABEL_MAX or 40
end

function RS.Of(warning, near)
    if not low(warning) then return nil end
    if type(near) == "table" then
        if near.kind ~= RS.KIND or near.map == nil or not (share(near.x) and share(near.y)) then return nil end
        local label = RS.LABEL
        local name = text(near.name)
        if name then
            local long = RS.LABEL .. ": " .. name
            if #long <= labelMax() then label = long end
        end
        return {
            kind = RS.KIND, label = label, name = name,
            place = { cont = near.cont, map = near.map, x = near.x, y = near.y },
            radius = RS.RADIUS,
            yards = finite(near.yards) and near.yards >= 0 and near.yards or nil,
            from = "seen",
        }
    end
    local known = warning.step
    if type(known) == "table" and type(known.place) == "table" and known.place.map ~= nil
        and share(known.place.x) and share(known.place.y) then
        local p = known.place
        return {
            kind = RS.KIND, label = text(known.label) or RS.LABEL,
            place = { cont = p.cont, map = p.map, x = p.x, y = p.y },
            radius = finite(known.radius) and known.radius or RS.RADIUS,
            from = "imported",
        }
    end
    return nil
end

function RS.Lines(warning, step)
    if type(warning) ~= "table" or type(warning.lines) ~= "table" then return {} end
    if type(step) ~= "table" or step.from ~= "seen" then
        local out = {}
        for i = 1, #warning.lines do out[i] = warning.lines[i] end
        return out
    end
    local where
    local yards = finite(step.yards) and string.format("about %d yd", math.floor(step.yards + 0.5)) or nil
    if step.name and yards then
        where = step.name .. ", " .. yards
    else
        where = step.name or yards
    end
    local out = { warning.lines[1] }
    if where then out[#out + 1] = "Nearest repair vendor you have seen: " .. where .. "." end
    return out
end

function RS.Place(step)
    if type(step) ~= "table" or type(step.place) ~= "table" then return nil end
    return { kind = RS.KIND, name = step.label, map = step.place.map, x = step.place.x, y = step.place.y }
end

function RS.Declare(k)
    local api = {}
    local ctx
    local near, nearAt, nearFor   -- the nearest kept, when, and for which warning

    local function warning()
        if not ctx then return nil end
        local ok, provider = pcall(ctx.use, RS.WARNING)
        if not ok or type(provider) ~= "table" or type(provider.Current) ~= "function" then return nil end
        local okW, w = pcall(provider.Current)
        if not okW or not low(w) then return nil end
        return w
    end

    -- Legacy keeps the nearest for 10 seconds; so does this. With no clock
    -- to go by it is asked each time, never kept for ever.
    local function nearest(w)
        local now
        if type(ctx.client.uptime) == "function" then
            local ok, t = pcall(ctx.client.uptime)
            if ok and finite(t) then now = t end
        end
        if now and nearAt and nearFor == w and now >= nearAt and now - nearAt < RS.KEEP then return near end
        near = ns.Nav and ns.Nav.Nearest and ns.Nav.Nearest(RS.KIND, ctx.client, ctx.store) or nil
        nearAt, nearFor = now, w
        return near
    end

    local function found()
        local w = warning()
        if not w then
            near, nearAt, nearFor = nil, nil, nil
            return nil, nil
        end
        return w, RS.Of(w, nearest(w))
    end

    function api.step()
        local _, step = found()
        if not step then return nil end
        if ctx.settings and ctx.settings:get(RS.SETTING) == false then return nil end
        return step
    end

    function api.lines()
        local w, step = found()
        return RS.Lines(w, step)
    end

    k:Setting({ key = "nav.repairStep", scope = "account", type = "bool", default = true,
        label = "Repair step" })

    k:Module({
        name = RS.NAME,
        needs = { "client", "store", "settings" },
        provides = { Step = api.step, Lines = api.lines },
        start = function(c)
            ctx = c
        end,
    })
    return api
end

-- The addon's own: declared when this file loads. It gives nothing until
-- the repair warning is on.
ns.repairStep = RS.Declare(ns)
