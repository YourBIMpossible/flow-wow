local _, ns = ...

-- The profession picker (G17): a character of level 3 or more with a free
-- primary profession slot gets one advisor prompt saying which profession
-- to learn and why. Advice only: nothing is trained, bought or clicked.
--
-- From the player's own state only: the class token (client.class), the
-- level (client.level) and the professions known (client.professions, the
-- P-GATHER read). The reasons are short lines written here; no guide data.
-- The legacy add-on suggested from class data and let the player pick in a
-- window; here the suggestion is the prompt itself.
--
-- Pure: P.Advice(known, class, level) -> { id, text, priority } or nil.
--   known  { [name] = true } as client.professions gives it; nil: not read.
--          Only the primary professions below count; secondary and
--          weapon lines are passed over.
--   No advice for a read not given, a level not known or below
--   P.MIN_LEVEL, or two primaries already known.
--
-- Module "profPick": needs the advisor. It syncs when the character enters
-- the world, when the skill lines change and every P.EVERY seconds (so a
-- setting changed, or a read that arrives late, shows within that time). A
-- read raising or not given removes the prompt; the module stays on.
-- Setting "professions.picker" (bool, default true): false removes it.
-- Stopped, it removes what it added. Not tested in game.

ns.ProfPick = {}
local P = ns.ProfPick

P.NAME = "profPick"
P.ADVISOR = "advisor"
P.SETTING = "professions.picker"
P.ID = "aps.profPick"
P.PRIORITY = 1
P.MIN_LEVEL = 3
P.EVERY = 5
P.EVENTS = { "PLAYER_ENTERING_WORLD", "SKILL_LINES_CHANGED" }

-- The primary professions, by the name the client gives.
P.PRIMARY = {
    Alchemy = true, Blacksmithing = true, Enchanting = true, Engineering = true, Herbalism = true,
    Leatherworking = true, Mining = true, Skinning = true, Tailoring = true,
}

-- One known primary: the one that goes with it, and why.
P.PARTNER = {
    Herbalism = { "Alchemy", "it turns the herbs you gather into potions." },
    Mining = { "Blacksmithing", "it makes armour and weapons from the ore." },
    Skinning = { "Leatherworking", "it makes armour from the leather." },
    Alchemy = { "Herbalism", "it gathers the herbs it needs." },
    Blacksmithing = { "Mining", "it gathers the ore it needs." },
    Engineering = { "Mining", "it gathers the ore and stone it needs." },
    Leatherworking = { "Skinning", "it gathers the leather it needs." },
    Tailoring = { "Enchanting", "it turns the gear you make or find into enchants." },
    Enchanting = { "Tailoring", "it makes gear from the cloth you loot, to wear or to enchant with." },
}

local CLOTH = "You wear cloth: Tailoring makes bags and cloth gear from the cloth you loot, "
    .. "and Enchanting turns the gear you do not need into enchants."
local LEATHER = "You wear leather: Skinning gives the leather from what you kill "
    .. "and Leatherworking makes your armour from it."
local PLATE = "You wear mail or plate: Mining gives the ore and Blacksmithing makes your armour and weapons from it."

-- No primary known: by the armour the class wears.
P.BY_CLASS = {
    MAGE = CLOTH, PRIEST = CLOTH, WARLOCK = CLOTH,
    ROGUE = LEATHER, DRUID = LEATHER, HUNTER = LEATHER, SHAMAN = LEATHER,
    WARRIOR = PLATE, PALADIN = PLATE,
}
P.ANY_CLASS = "Herbalism and Skinning gather while you level and sell for gold."

local function finite(v) return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge end

function P.Advice(known, class, level)
    if type(known) ~= "table" then return nil end
    if not finite(level) or level < P.MIN_LEVEL then return nil end
    local have = {}
    for name, yes in pairs(known) do
        if yes == true and P.PRIMARY[name] then have[#have + 1] = name end
    end
    if #have >= 2 then return nil end
    local text
    if #have == 1 then
        local mine = have[1]
        local pair = P.PARTNER[mine]
        text = "One profession slot is free. " .. pair[1] .. " goes with your " .. mine .. ": " .. pair[2]
    else
        local why = (type(class) == "string" and P.BY_CLASS[class]) or P.ANY_CLASS
        text = "Two profession slots are free. " .. why
    end
    return { id = P.ID, text = text, priority = P.PRIORITY }
end

-- The module. api.shown(): true while the prompt is in the advisor.
function P.Declare(k)
    local api = {}
    local ctx, shown = nil, false

    function api.shown() return shown end

    local function advisor()
        if not ctx then return nil end
        local ok, found = pcall(ctx.use, P.ADVISOR)
        if not ok or type(found) ~= "table" or type(found.Add) ~= "function"
            or type(found.Remove) ~= "function" then
            return nil
        end
        return found
    end

    local function ask(read)
        if not ctx or type(ctx.client[read]) ~= "function" then return nil end
        local ok, v = pcall(ctx.client[read])
        if not ok then return nil end
        return v
    end

    local function on()
        if not ctx or not ctx.settings then return true end
        return ctx.settings:get(P.SETTING) ~= false
    end

    local function remove(a)
        if shown and a then pcall(a.Remove, P.ID) end
        shown = false
    end

    local function sync()
        local a = advisor()
        if not a then return end
        local want = nil
        if on() then
            local ok, v = pcall(P.Advice, ask("professions"), ask("class"), ask("level"))
            if ok then want = v end
        end
        if type(want) ~= "table" then
            remove(a)
            return
        end
        local ok, added = pcall(a.Add, want.id, want.text, want.priority)
        if ok and added == true then shown = true end
    end

    k:Setting({ key = P.SETTING, scope = "account", type = "bool", default = true,
        label = "Which profession to learn", group = "professions",
        help = "While a primary profession slot is free, the advisor says which profession goes with "
            .. "your class or with the one you have, and why. It trains nothing.",
        synonyms = { "profession", "professions", "choose", "pick", "picker", "learn", "trade", "gathering" } })

    local events = {}
    for _, event in ipairs(P.EVENTS) do
        events[event] = function() sync() end
    end

    k:Module({
        name = P.NAME,
        needs = { "client", "settings", P.ADVISOR },
        provides = { Shown = api.shown },
        events = events,
        ticks = { { every = P.EVERY, when = "always", run = function() sync() end } },
        start = function(c)
            ctx = c
            sync()
        end,
        stop = function()
            remove(advisor())
            ctx = nil
        end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.profPick = P.Declare(ns)
