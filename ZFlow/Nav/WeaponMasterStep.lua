local _, ns = ...

-- WeaponMasterStep (G16): when you are shown an upgrade weapon of a kind
-- your class can learn but you have not trained (Gear/WeaponSkill.lua), a
-- "visit a weapon master" step. Where: the nearest weapon master this
-- player has saved on the map they are on (account "learned.places.npcs",
-- an entry with roles.weaponMaster = true); with none saved, words only
-- ("a weapon master in a capital city teaches <kind>") and no place, so
-- the arrow has no needle for it. No weapon master data is carried here.
--
-- LOOK ONLY. Nothing here trains, buys, clicks or opens anything, and
-- nothing moves the player: it reads what the client shows and saved
-- places and gives a step and words.
--
-- Behaviour from Flow's Modules/Gear/WeaponSkills.lua (the step for an
-- upgrade weapon whose skill you have not trained; never for a kind your
-- class can never use), built in this add-on's shape.
--
-- Pure parts (plain tables in):
--   step  = WeaponMasterStep.Of(wanted, here, npcs)   a step, or nil
--   lines = WeaponMasterStep.Lines(step)              what to say
--
--   wanted  { subclassID, skill }: GearWeaponSkill.Wanted's answer
--   here    client.position(): { map, x, y }; nil: not known
--   npcs    account "learned.places.npcs": { [name] = { map, x, y,
--           roles = { weaponMaster = true } } }
--   step    { kind = "weaponMaster", label, skill, subclassID, name,
--             place = { map, x, y } (left out for words only), radius }
--
-- Module: WeaponMasterStep.Declare(k[, packs]) -> api; api.step(),
--   api.lines(). ns.use(WeaponMasterStep.NAME) -> { Step, Lines }.
--   What was shown is noted when an item tooltip (client.onItemTooltip) or
--   a loot roll (client.onLootRoll) is shown, in memory only: a reload
--   starts with none. Each ask reads client.weaponSkills() again, so a skill
--   learned takes its step away at once (SKILL_LINES_CHANGED needs no
--   listener); skills not read, or the read raising: no step.
-- Setting "nav.weaponMasterStep" (bool, default true): false turns the
-- step off. Not seen in game: needs game test.

local WM = {}
ns.WeaponMasterStep = WM

WM.NAME = "weaponMasterStep"
WM.SETTING = "nav.weaponMasterStep"
WM.KIND = "weaponMaster"
WM.NPCS = "learned.places.npcs"
WM.RADIUS = 10
WM.LABEL = "Weapon master"

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

local function labelMax()
    local N = ns.Nav
    return N and N.Waypoint and N.Waypoint.LABEL_MAX or 40
end

-- The nearest saved weapon master on the map of `here`, by shares of the
-- map; a tie goes to the lower name.
local function nearest(here, npcs)
    if type(here) ~= "table" or here.map == nil or not (share(here.x) and share(here.y)) then return nil end
    if type(npcs) ~= "table" then return nil end
    local best, bestName, bestD
    for name, e in pairs(npcs) do
        if type(name) == "string" and type(e) == "table" and type(e.roles) == "table"
            and e.roles.weaponMaster == true and e.map == here.map and share(e.x) and share(e.y) then
            local dx, dy = e.x - here.x, e.y - here.y
            local d = dx * dx + dy * dy
            if bestD == nil or d < bestD or (d == bestD and name < bestName) then
                best, bestName, bestD = e, name, d
            end
        end
    end
    if not best then return nil end
    return { name = bestName, map = best.map, x = best.x, y = best.y }
end

function WM.Of(wanted, here, npcs)
    if type(wanted) ~= "table" or not text(wanted.skill) then return nil end
    local step = { kind = WM.KIND, label = WM.LABEL, skill = wanted.skill, subclassID = wanted.subclassID,
                   radius = WM.RADIUS }
    local found = nearest(here, npcs)
    if found then
        step.name = found.name
        step.place = { map = found.map, x = found.x, y = found.y }
        local long = WM.LABEL .. ": " .. found.name
        if #long <= labelMax() then step.label = long end
    end
    return step
end

function WM.Lines(step)
    if type(step) ~= "table" or not text(step.skill) then return {} end
    if type(step.place) == "table" and text(step.name) then
        return { "Train " .. step.skill .. " at a weapon master you have seen: " .. step.name .. "." }
    end
    return { "A weapon master in a capital city teaches " .. step.skill .. "." }
end

function WM.Declare(k, packs)
    local api = {}
    local ctx
    local noted = {}      -- subclassID -> skill name, shown this session
    local cancels = {}

    local function ask(read, ...)
        if not ctx or type(ctx.client[read]) ~= "function" then return nil end
        local ok, v = pcall(ctx.client[read], ...)
        if not ok then return nil end
        return v
    end

    local function skills()
        local v = ask("weaponSkills")
        if type(v) ~= "table" then return nil end
        return v
    end

    local function on()
        if not ctx or not ctx.settings then return true end
        return ctx.settings:get(WM.SETTING) ~= false
    end

    local function shown(link)
        if not ctx or not on() or type(link) ~= "string" then return end
        local gear = ask("gear", link)
        if type(gear) ~= "table" then return end
        local class = ask("class")
        local all = packs or ns.Packs
        local pack = nil
        if type(all) == "table" and class ~= nil then pack = all[class] end
        local ok, want = pcall(ns.GearWeaponSkill.Wanted, gear,
            { pack = pack, level = ask("level"), skills = skills() })
        if ok and type(want) == "table" and finite(want.subclassID) and text(want.skill) then
            noted[want.subclassID] = want.skill
        end
    end

    -- The first kind noted, by subclass, that is still not trained. A kind
    -- now trained is let go; with skills not read nothing is said.
    local function wanted()
        local known = skills()
        if not known then return nil end
        local subs = {}
        for sub in pairs(noted) do subs[#subs + 1] = sub end
        table.sort(subs)
        for i = 1, #subs do
            local trained = ns.GearWeaponSkill.Trained(subs[i], known)
            if trained == true then
                noted[subs[i]] = nil
            elseif trained == false then
                return { subclassID = subs[i], skill = noted[subs[i]] }
            end
        end
        return nil
    end

    function api.step()
        if not ctx or not on() then return nil end
        local want = wanted()
        if not want then return nil end
        local npcs = nil
        if ctx.store and type(ctx.store.get) == "function" then
            local ok, v = pcall(ctx.store.get, ctx.store, "account", WM.NPCS)
            if ok then npcs = v end
        end
        return WM.Of(want, ask("position"), npcs)
    end

    function api.lines()
        return WM.Lines(api.step())
    end

    k:Setting({ key = WM.SETTING, scope = "account", type = "bool", default = true,
        label = "Weapon master step", group = "travel.route",
        help = "When you are shown an upgrade weapon you have not trained, say where a weapon master is. It trains nothing.",
        synonyms = { "weapon master", "train", "weapon skill", "route", "step" } })

    k:Module({
        name = WM.NAME,
        needs = { "client", "store", "settings" },
        provides = { Step = api.step, Lines = api.lines },
        start = function(c)
            ctx = c
            if type(c.client.onItemTooltip) == "function" then
                local ok, cancel = pcall(c.client.onItemTooltip, function(link) shown(link) end)
                if ok and type(cancel) == "function" then cancels[#cancels + 1] = cancel end
            end
            if type(c.client.onLootRoll) == "function" then
                local ok, cancel = pcall(c.client.onLootRoll, function(_, link) shown(link) end)
                if ok and type(cancel) == "function" then cancels[#cancels + 1] = cancel end
            end
        end,
        stop = function()
            for i = 1, #cancels do pcall(cancels[i]) end
            cancels = {}
            ctx = nil
        end,
    })
    return api
end

-- The addon's own: declared when this file loads. It gives nothing until
-- an untrained upgrade weapon is shown.
ns.weaponMasterStep = WM.Declare(ns)
