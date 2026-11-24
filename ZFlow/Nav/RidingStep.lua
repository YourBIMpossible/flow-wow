local _, ns = ...

-- RidingStep (G45): when the player reaches the level for riding (40) or
-- for the next riding tier (60) and does not have it, one advisor line
-- says so, with the cost and the trainer only as the game showed them, and
-- the route has a step to the riding trainer when one has been seen on the
-- map the player is on.
--
-- Where things come from:
--   level      client.level()
--   riding     client.skillRanks(): a skill line named as riding ("Horse
--              Riding", "Riding", "Undead Horsemanship", "Mechanostrider
--              Piloting"); rank 75 is the first tier, 150 the second.
--              Skills not read, or a riding line with no rank read: not
--              known, nothing is said.
--   trainer    a trainer window (TRAINER_SHOW, client.trainer()) whose list
--              holds a riding service saves that npc in account
--              "learned.places.npcs" (the shape Nav/WeaponMasterSeen.lua
--              writes) with roles.ridingTrainer = true, map, x, y and
--              ridingCosts[level required] = the cost the list showed.
--   money      client.money(); short of the cost seen: "You need <n> more."
-- No price, place or coordinate is carried here: a price not seen is "price
-- not seen yet"; no trainer seen is "Ask a city guard for the riding
-- trainer." Mount vendors: Z-Flow keeps no merchant lists by kind, so the
-- mount is words only.
--
-- Pure parts:
--   due   = RidingStep.Due(level, ranks)             { tier, level, rank, words } or nil
--   step  = RidingStep.Of(due, here, npcs, money)    a step, or nil
--   lines = RidingStep.Lines(step)                   what to say
--   RidingStep.IsRiding(name) -> true | false
--   step { kind = "riding", label, tier, level, words, name, cost, money,
--          place = { map, x, y } (only on the player's map), radius }
--
-- Module: RidingStep.Declare(k) -> api; api.step(), api.lines().
--   ns.use(RidingStep.NAME) -> { Step, Lines }. The advisor line (id
--   RidingStep.PROMPT) is the lines joined, kept in step at login, level-up,
--   skill and money changes and at a trainer.
-- Setting "nav.ridingStep" (bool, default true): false turns it off.
-- LOOK ONLY: nothing trains, buys, mounts or clicks. Not seen in game.

local R = {}
ns.RidingStep = R

R.NAME = "ridingStep"
R.SETTING = "nav.ridingStep"
R.KIND = "riding"
R.NPCS = "learned.places.npcs"
R.PROMPT = "nav.riding"
R.PRIORITY = 1
R.RADIUS = 10
R.LABEL = "Riding trainer"
R.TIERS = {
    { level = 40, rank = 75, words = "riding",
      mount = "Then buy a mount from a mount vendor (a city guard knows where)." },
    { level = 60, rank = 150, words = "faster riding",
      mount = "Then buy a fast mount from a mount vendor." },
}
R.EVENTS = { "PLAYER_ENTERING_WORLD", "PLAYER_LEVEL_UP", "SKILL_LINES_CHANGED", "PLAYER_MONEY" }

local function finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function share(v)
    return finite(v) and v >= 0 and v <= 1
end

local function text(v)
    return type(v) == "string" and v ~= ""
end

local function coin(copper)
    local P = ns.Prices
    if P and type(P.Coin) == "function" then return P.Coin(copper) end
    return nil
end

local function labelMax()
    local N = ns.Nav
    return N and N.Waypoint and N.Waypoint.LABEL_MAX or 40
end

function R.IsRiding(name)
    if not text(name) then return false end
    if name:find("Riding$") or name:find("Horsemanship", 1, true) or name:find("Piloting", 1, true) then
        return true
    end
    return false
end

function R.Due(level, ranks)
    if not finite(level) or type(ranks) ~= "table" then return nil end
    local have = 0
    for name, row in pairs(ranks) do
        if R.IsRiding(name) then
            local rank = type(row) == "table" and row.rank or nil
            if not finite(rank) then return nil end
            if rank > have then have = rank end
        end
    end
    for i = 1, #R.TIERS do
        local tier = R.TIERS[i]
        if have < tier.rank then
            if level < tier.level then return nil end
            return { tier = i, level = tier.level, rank = tier.rank, words = tier.words }
        end
    end
    return nil
end

local function costOf(e, level)
    if type(e) ~= "table" or type(e.ridingCosts) ~= "table" then return nil end
    local v = e.ridingCosts[level]
    if finite(v) and v >= 0 then return v end
    return nil
end

-- The trainer to name: the nearest saved riding trainer on the player's
-- map (shares of the map), else the lowest-named one anywhere (no place).
local function pick(here, npcs)
    if type(npcs) ~= "table" then return nil end
    local onMap = type(here) == "table" and here.map ~= nil and share(here.x) and share(here.y)
    local near, nearName, nearD, any, anyName
    for name, e in pairs(npcs) do
        if type(name) == "string" and type(e) == "table" and type(e.roles) == "table"
            and e.roles.ridingTrainer == true then
            if anyName == nil or name < anyName then any, anyName = e, name end
            if onMap and e.map == here.map and share(e.x) and share(e.y) then
                local dx, dy = e.x - here.x, e.y - here.y
                local d = dx * dx + dy * dy
                if nearD == nil or d < nearD or (d == nearD and name < nearName) then
                    near, nearName, nearD = e, name, d
                end
            end
        end
    end
    if near then return near, nearName, true end
    if any then return any, anyName, false end
    return nil
end

function R.Of(due, here, npcs, money)
    if type(due) ~= "table" or not finite(due.level) or not text(due.words) then return nil end
    local step = { kind = R.KIND, label = R.LABEL, tier = due.tier, level = due.level, words = due.words,
                   radius = R.RADIUS }
    if finite(money) then step.money = money end
    local e, name, placed = pick(here, npcs)
    if e then
        step.name = name
        step.cost = costOf(e, due.level)
        if placed then
            step.place = { map = e.map, x = e.x, y = e.y }
            local long = R.LABEL .. ": " .. name
            if #long <= labelMax() then step.label = long end
        end
    end
    if step.cost == nil and type(npcs) == "table" then
        local names = {}
        for n, other in pairs(npcs) do
            if type(n) == "string" and type(other) == "table" and type(other.roles) == "table"
                and other.roles.ridingTrainer == true then
                names[#names + 1] = n
            end
        end
        table.sort(names)
        for i = 1, #names do
            local v = costOf(npcs[names[i]], due.level)
            if v then
                step.cost = v
                break
            end
        end
    end
    return step
end

function R.Lines(step)
    if type(step) ~= "table" or not text(step.words) then return {} end
    local head = "You can learn " .. step.words .. " now"
    local price = finite(step.cost) and coin(step.cost) or nil
    local lines = {}
    if text(step.name) and price then
        lines[1] = head .. ": about " .. price .. " at the riding trainer " .. step.name .. "."
    elseif text(step.name) then
        lines[1] = head .. " at the riding trainer " .. step.name .. " (price not seen yet)."
    elseif price then
        lines[1] = head .. ": about " .. price .. ". Ask a city guard for the riding trainer."
    else
        lines[1] = head .. " (price not seen yet). Ask a city guard for the riding trainer."
    end
    if finite(step.cost) and finite(step.money) and step.money < step.cost then
        local short = coin(step.cost - step.money)
        if short then lines[#lines + 1] = "You need " .. short .. " more." end
    end
    local tier = R.TIERS[step.tier]
    if type(tier) == "table" and text(tier.mount) then lines[#lines + 1] = tier.mount end
    return lines
end

-- A trainer window whose list holds a riding service: that npc is saved
-- as a riding trainer with the costs the list showed. Writes nothing when
-- any part is not known.
function R.Seen(client, store)
    local function ask(read)
        if type(client) ~= "table" or type(client[read]) ~= "function" then return nil end
        local ok, v = pcall(client[read])
        if not ok then return nil end
        return v
    end
    local tr = ask("trainer")
    if type(tr) ~= "table" or not text(tr.npc) or type(tr.services) ~= "table" then return false end
    local costs, riding = {}, false
    for i = 1, #tr.services do
        local row = tr.services[i]
        if type(row) == "table" and R.IsRiding(row.name) then
            riding = true
            if finite(row.level) and finite(row.cost) and row.cost >= 0 then costs[row.level] = row.cost end
        end
    end
    if not riding then return false end
    local pos = ask("position")
    if type(pos) ~= "table" or not finite(pos.map) or not share(pos.x) or not share(pos.y) then return false end
    if type(store) ~= "table" or type(store.get) ~= "function" or type(store.set) ~= "function" then return false end
    local okGet, npcs = pcall(store.get, store, "account", R.NPCS)
    if not okGet or (npcs ~= nil and type(npcs) ~= "table") then return false end
    npcs = npcs or {}
    local e = {}
    if type(npcs[tr.npc]) == "table" then
        for key, v in pairs(npcs[tr.npc]) do e[key] = v end
    end
    local roles, kept = {}, {}
    if type(e.roles) == "table" then for key, v in pairs(e.roles) do roles[key] = v end end
    if type(e.ridingCosts) == "table" then for key, v in pairs(e.ridingCosts) do kept[key] = v end end
    for level, cost in pairs(costs) do kept[level] = cost end
    roles.ridingTrainer = true
    e.roles = roles
    if next(kept) ~= nil then e.ridingCosts = kept end
    e.map, e.x, e.y = pos.map, pos.x, pos.y
    local faction = ask("faction")
    if text(faction) then
        local factions = {}
        if type(e.factions) == "table" then for key, v in pairs(e.factions) do factions[key] = v end end
        factions[faction] = true
        e.factions = factions
    end
    npcs[tr.npc] = e
    local okSet, set = pcall(store.set, store, "account", R.NPCS, npcs)
    return okSet and set == true
end

function R.Declare(k)
    local api = {}
    local ctx
    local shown

    local function ask(read)
        if not ctx or type(ctx.client[read]) ~= "function" then return nil end
        local ok, v = pcall(ctx.client[read])
        if not ok then return nil end
        return v
    end

    local function on()
        if not ctx or not ctx.settings then return true end
        return ctx.settings:get(R.SETTING) ~= false
    end

    function api.step()
        if not ctx or not on() then return nil end
        local due = R.Due(ask("level"), ask("skillRanks"))
        if not due then return nil end
        local npcs
        if ctx.store and type(ctx.store.get) == "function" then
            local ok, v = pcall(ctx.store.get, ctx.store, "account", R.NPCS)
            if ok then npcs = v end
        end
        return R.Of(due, ask("position"), npcs, ask("money"))
    end

    function api.lines()
        return R.Lines(api.step())
    end

    local function refresh()
        local advisor = ctx and ctx.use and ctx.use("advisor")
        if type(advisor) ~= "table" then return end
        local lines = api.lines()
        local said = #lines > 0 and table.concat(lines, " ") or nil
        if said == shown then return end
        if said then advisor.Add(R.PROMPT, said, R.PRIORITY) else advisor.Remove(R.PROMPT) end
        shown = said
    end

    k:Setting({ key = R.SETTING, scope = "account", type = "bool", default = true,
        label = "Riding step", group = "travel.route",
        help = "When you can learn riding, say the cost and the trainer you have seen. It trains and buys nothing.",
        synonyms = { "riding", "mount", "train", "route", "step" } })

    k:Module({
        name = R.NAME,
        needs = { "client", "store", "bus", "settings", "advisor" },
        provides = { Step = api.step, Lines = api.lines },
        start = function(c)
            ctx = c
            shown = nil
            if type(c.client.watchTrainer) == "function" then pcall(c.client.watchTrainer) end
            for i = 1, #R.EVENTS do
                c.bus:on(R.NAME, R.EVENTS[i], function() pcall(refresh) end)
            end
            c.bus:on(R.NAME, "TRAINER_SHOW", function()
                pcall(R.Seen, c.client, c.store)
                pcall(refresh)
            end)
            pcall(refresh)
        end,
        stop = function()
            ctx = nil
        end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.ridingStep = R.Declare(ns)
