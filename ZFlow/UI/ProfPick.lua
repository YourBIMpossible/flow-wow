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
--
-- The choices of Flow's profession card (lead section 274), as the word
-- P.WORD on the slash command, which the prompt names; saved per character
-- at char P.STATE:
--   later          Not now: no prompt until the next level (as Flow did)
--   choose <a> <b> Choose others: the advice follows the pair named
--   route          Add to my route: a "learn <profession>" step, at the
--                  nearest trainer of it this player has seen, else words
--                  only (the arrow takes it only with a place)
--   reset          clears all three

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
P.KIND = "profTrainer"
P.RADIUS = 10
P.NPCS = "learned.places.npcs"   -- account
P.STATE = "state.profPick"       -- char: { snoozeLevel, chosen = { a, b }, route = true }
P.WORD = "professions"
P.HELP = "which profession to learn: later (not until your next level), choose <a> <b> (your own pair), "
    .. "route (a step to its trainer), reset"

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

local CLOTH_PAIR = { "Tailoring", "Enchanting", CLOTH }
local LEATHER_PAIR = { "Skinning", "Leatherworking", LEATHER }
local PLATE_PAIR = { "Mining", "Blacksmithing", PLATE }

-- No primary known: by the armour the class wears ({ first, second, why }).
P.BY_CLASS = {
    MAGE = CLOTH_PAIR, PRIEST = CLOTH_PAIR, WARLOCK = CLOTH_PAIR,
    ROGUE = LEATHER_PAIR, DRUID = LEATHER_PAIR, HUNTER = LEATHER_PAIR, SHAMAN = LEATHER_PAIR,
    WARRIOR = PLATE_PAIR, PALADIN = PLATE_PAIR,
}
P.ANY_CLASS = { "Herbalism", "Skinning", "Herbalism and Skinning gather while you level and sell for gold." }

local function finite(v) return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge end

-- The primary profession named by a word, any case; nil for none.
function P.Primary(word)
    if type(word) ~= "string" then return nil end
    local low = word:lower()
    for name in pairs(P.PRIMARY) do
        if name:lower() == low then return name end
    end
    return nil
end

-- plan (optional, the saved choices): { chosen = { name, ... },
-- snoozeLevel = n }. With a pair chosen the advice follows it: the chosen
-- ones not yet known. A snooze hides the advice up to and at snoozeLevel.
-- The answer's wants lists the professions advised, in order.
function P.Advice(known, class, level, plan)
    if type(known) ~= "table" then return nil end
    if not finite(level) or level < P.MIN_LEVEL then return nil end
    if type(plan) == "table" and finite(plan.snoozeLevel) and level <= plan.snoozeLevel then return nil end
    if type(plan) == "table" and type(plan.chosen) == "table" and #plan.chosen > 0 then
        local wants = {}
        for _, name in ipairs(plan.chosen) do
            if P.PRIMARY[name] and known[name] ~= true then wants[#wants + 1] = name end
        end
        if #wants == 0 then return nil end
        return { id = P.ID, priority = P.PRIORITY, wants = wants,
                 text = "Your choice: learn " .. table.concat(wants, " and ") .. "." }
    end
    local have = {}
    for name, yes in pairs(known) do
        if yes == true and P.PRIMARY[name] then have[#have + 1] = name end
    end
    if #have >= 2 then return nil end
    local text, wants
    if #have == 1 then
        local mine = have[1]
        local pair = P.PARTNER[mine]
        if type(pair) ~= "table" or type(pair[1]) ~= "string" or type(pair[2]) ~= "string" then return nil end
        text = "One profession slot is free. " .. pair[1] .. " goes with your " .. mine .. ": " .. pair[2]
        wants = { pair[1] }
    else
        local pick = (type(class) == "string" and P.BY_CLASS[class]) or P.ANY_CLASS
        text = "Two profession slots are free. " .. pick[3]
        wants = { pick[1], pick[2] }
    end
    return { id = P.ID, text = text, priority = P.PRIORITY, wants = wants }
end

-- The route step for one profession (the shape of Nav/WeaponMasterStep.lua):
-- the nearest trainer of it this player has seen on the map of `here`, or
-- words only (no place) when none is saved. npcs: account
-- "learned.places.npcs" as Nav/ProfSeen.lua saves it; a trainer saved for
-- other factions only is left out (with the faction known).
local function share(v) return finite(v) and v >= 0 and v <= 1 end

function P.StepOf(skill, here, npcs, faction)
    if type(skill) ~= "string" or skill == "" then return nil end
    local step = { kind = P.KIND, label = "Learn " .. skill, skill = skill, radius = P.RADIUS }
    if type(here) ~= "table" or here.map == nil or not share(here.x) or not share(here.y)
        or type(npcs) ~= "table" then
        return step
    end
    local best, bestName, bestD
    for name, e in pairs(npcs) do
        local fits = type(name) == "string" and type(e) == "table" and type(e.trains) == "table"
            and e.trains[skill] == true and e.map == here.map and share(e.x) and share(e.y)
        if fits and type(faction) == "string" and type(e.factions) == "table" and next(e.factions) ~= nil then
            fits = e.factions[faction] == true
        end
        if fits then
            local dx, dy = e.x - here.x, e.y - here.y
            local d = dx * dx + dy * dy
            if bestD == nil or d < bestD or (d == bestD and name < bestName) then
                best, bestName, bestD = e, name, d
            end
        end
    end
    if best then
        step.name = bestName
        step.place = { map = best.map, x = best.x, y = best.y }
        local long = step.label .. ": " .. bestName
        local max = ns.Nav and ns.Nav.Waypoint and ns.Nav.Waypoint.LABEL_MAX or 40
        if #long <= max then step.label = long end
    end
    return step
end

function P.Lines(step)
    if type(step) ~= "table" or type(step.skill) ~= "string" then return {} end
    if type(step.place) == "table" and type(step.name) == "string" then
        return { "Learn " .. step.skill .. " from " .. step.name .. ", a trainer you have seen." }
    end
    return { "A " .. step.skill .. " trainer in a capital city teaches it." }
end

-- The module. api.shown(): true while the prompt is in the advisor.
-- api.step() / api.lines(): the route step asked for with "route", and
-- what to say for it. diag (optional): what Diag.Start returned; the word
-- P.WORD and its help line are added to its commands.
function P.Declare(k, diag)
    local api = {}
    -- last: the text this module last put in the advisor.
    local ctx, shown, last = nil, false, nil

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

    -- The saved choices of this character, or an empty table.
    local function plan()
        if not ctx or type(ctx.store) ~= "table" or type(ctx.store.get) ~= "function" then return {} end
        local ok, v = pcall(ctx.store.get, ctx.store, "char", P.STATE)
        if ok and type(v) == "table" then return v end
        return {}
    end

    local function save(p)
        if not ctx or type(ctx.store) ~= "table" or type(ctx.store.set) ~= "function" then return false end
        local ok, done = pcall(ctx.store.set, ctx.store, "char", P.STATE, p)
        return ok and done == true
    end

    local function hint()
        local id = type(k) == "table" and k.id
        if type(id) == "table" and type(id.slash) == "string" then
            return " Choices: " .. id.slash .. " " .. P.WORD .. "."
        end
        return ""
    end

    local function remove(a)
        if shown and a then pcall(a.Remove, P.ID) end
        shown, last = false, nil
    end

    local function sync()
        local a = advisor()
        if not a then return end
        local want = nil
        if on() then
            local ok, v = pcall(P.Advice, ask("professions"), ask("class"), ask("level"), plan())
            if ok then want = v end
        end
        if type(want) ~= "table" then
            remove(a)
            return
        end
        local text = want.text .. hint()
        -- The same text already in the advisor: nothing to add (lead 274 PP-1).
        if shown and last == text then return end
        local ok, added = pcall(a.Add, want.id, text, want.priority)
        if ok and added == true then
            shown, last = true, text
        end
    end

    -- The step asked for: the first profession still advised (the snooze
    -- does not hide a step the player asked for).
    function api.step()
        if not ctx or not on() then return nil end
        local p = plan()
        if p.route ~= true then return nil end
        local ok, want = pcall(P.Advice, ask("professions"), ask("class"), ask("level"),
            { chosen = p.chosen })
        if not ok or type(want) ~= "table" or type(want.wants) ~= "table" then return nil end
        local npcs = nil
        if type(ctx.store) == "table" and type(ctx.store.get) == "function" then
            local okN, v = pcall(ctx.store.get, ctx.store, "account", P.NPCS)
            if okN then npcs = v end
        end
        local okS, step = pcall(P.StepOf, want.wants[1], ask("position"), npcs, ask("faction"))
        if okS then return step end
        return nil
    end

    function api.lines() return P.Lines(api.step()) end

    -- The word. Returns the lines to print.
    function api.run(rest)
        if not ctx then return { "not started yet." } end
        local words = {}
        for w in tostring(rest or ""):gmatch("%S+") do words[#words + 1] = w end
        local verb = words[1] and words[1]:lower()
        local p = plan()
        local out
        if verb == "later" then
            local level = ask("level")
            if not finite(level) then
                out = { "your level is not known yet; try again in a moment." }
            else
                p.snoozeLevel = level
                if save(p) then
                    out = { "not now: the advice comes back at level " .. (level + 1) .. ", or with "
                        .. P.WORD .. " reset." }
                else
                    out = { "could not save that." }
                end
            end
        elseif verb == "choose" then
            local chosen, bad = {}, nil
            for i = 2, #words do
                local name = P.Primary(words[i])
                if not name then
                    bad = words[i]
                elseif chosen[1] ~= name then
                    chosen[#chosen + 1] = name
                end
            end
            if bad then
                out = { "\"" .. bad .. "\" is no primary profession. Name one or two of: Alchemy, Blacksmithing, "
                    .. "Enchanting, Engineering, Herbalism, Leatherworking, Mining, Skinning, Tailoring." }
            elseif #chosen == 0 or #chosen > 2 then
                out = { "name one or two professions: " .. P.WORD .. " choose <a> <b>." }
            else
                p.chosen = chosen
                if save(p) then
                    out = { "your choice is saved: " .. table.concat(chosen, " and ") .. "." }
                else
                    out = { "could not save that." }
                end
            end
        elseif verb == "route" then
            p.route = true
            if save(p) then
                local lines = api.lines()
                out = { "a step to the trainer is on your route." }
                for i = 1, #lines do out[#out + 1] = lines[i] end
            else
                out = { "could not save that." }
            end
        elseif verb == "reset" then
            if save({}) then
                out = { "your profession choices are cleared." }
            else
                out = { "could not save that." }
            end
        else
            local ok, want = pcall(P.Advice, ask("professions"), ask("class"), ask("level"), plan())
            if ok and type(want) == "table" then
                out = { want.text }
            else
                out = { "no profession advice now." }
            end
            out[#out + 1] = P.HELP .. "."
        end
        sync()
        return out
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
        needs = { "client", "store", "settings", P.ADVISOR },
        provides = { Shown = api.shown, Step = api.step, Lines = api.lines },
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

    if type(diag) == "table" and type(diag.commands) == "table" then
        diag.commands[P.WORD] = function(rest)
            local lines = api.run(rest)
            if not ctx or type(ctx.client.print) ~= "function" then return end
            local title = type(k.id) == "table" and k.id.title or ""
            for i = 1, #lines do pcall(ctx.client.print, title .. ": " .. lines[i]) end
        end
        if type(diag.help) == "table" then diag.help[P.WORD] = P.HELP end
    end
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.profPick = P.Declare(ns, ns.diag)
