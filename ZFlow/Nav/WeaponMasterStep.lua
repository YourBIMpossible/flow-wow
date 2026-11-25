local _, ns = ...

-- WeaponMasterStep (G16): when you are shown an upgrade weapon of a kind
-- your class can learn but you have not trained (Gear/WeaponSkill.lua), a
-- "visit a weapon master" step. Where: the nearest weapon master this
-- player has saved on the map they are on (account "learned.places.npcs",
-- an entry with roles.weaponMaster = true). With none saved there, the
-- module asks the profession feed (Nav/ProfFeed.lua's Place, the one owner
-- of the Questie read) for the nearest weapon master known: one saved on
-- another map of this continent, or one the player's own Questie names (an
-- NPC whose sub-name is "Weapon Master", of the player's faction, on this
-- map, else on this continent). One from Questie is one the player has not
-- visited: the step and its words say so, and that which weapons they
-- teach is not known until then. With no Questie, or none found: words
-- only ("a weapon master in a capital city teaches <kind>") and no place,
-- so the arrow has no needle for it. No weapon master place is carried
-- here, and none is guessed. The one exception to carrying no data, by
-- the owner's ruling, lead section 602: Nav/WeaponMasterNames.lua, the
-- names of the weapon masters and the weapon kinds each teaches
-- (approximate, from Flow). With it the feed is asked first for a weapon
-- master the table has WITH the wanted kind (this map, else this
-- continent): the step then says it is from Flow's list and may be out of
-- date, never "not known". A master the table has without the kind is
-- never pointed at. Only when no teacher is found: a weapon master the
-- table says nothing about, with the "not known" line as before. A weapon
-- master the player visited on this map still comes before all of it.
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
--           From the module only, for a weapon master not visited:
--           unvisited = true, detail = WM.NOT_KNOWN (the arrow's line
--           under the label); for one the table has with the kind:
--           unvisited = true, listed = true, detail = WM.LISTED.
--   teach, all = WeaponMasterStep.Teachers(subclassID): the table's names
--           with that kind, and all its names, each { [name] = true } or
--           nil when there is none (no table: nil, nil).
--   step = WeaponMasterStep.Elsewhere(step, place): a step in words given
--           a place when one is known. place(ask) -> { name, map, x, y },
--           from: the feed's Place.
--
-- Module: WeaponMasterStep.Declare(k[, packs]) -> api; api.step(),
--   api.lines(). ns.use(WeaponMasterStep.NAME) -> { Step, Lines }.
--   What was shown is noted when an item tooltip (client.onItemTooltip) or
--   a loot roll (client.onLootRoll) is shown, in memory only: a reload
--   starts with none. Each ask reads client.weaponSkills() again, so a skill
--   learned takes its step away at once (SKILL_LINES_CHANGED needs no
--   listener); skills not read, or the read raising: no step.
--   The feed is looked up when a step is asked for, never when this file
--   loads, so the order of the files does not matter. The first ask only
--   says a place is wanted; the feed reads Questie over the next frames,
--   out of combat, once, and a later ask has the place.
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
-- The step kind the profession feed is asked for a place with
-- (N.ProfPlace.KIND).
WM.ASK = "visit_weapon_master"
-- A weapon master the player has not visited: the skill, then the name.
WM.UNVISITED = "To train %s, try the weapon master %s."
WM.NOT_KNOWN = "You have not visited them: which weapons they teach is not known yet."
-- A weapon master the names table has with the wanted kind.
WM.LISTED = "This is from Flow's list of weapon masters, which is approximate and may be out of date."

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

-- Does the table of names (Nav/WeaponMasterNames.lua) have this master
-- WITHOUT the wanted kind? Only then is a master left out: one the table
-- does not name, no table, or no kind read leaves nobody out.
local function listedWithout(name, subclassID)
    if subclassID == nil then return false end
    local N = ns.Nav
    local list = type(N) == "table" and N.WeaponMasterNames or nil
    local row = type(list) == "table" and list[name] or nil
    if type(row) ~= "table" or type(row.skills) ~= "table" then return false end
    return row.skills[subclassID] ~= true
end

-- The nearest saved weapon master on the map of `here`, by shares of the
-- map; a tie goes to the lower name. One the table has without the wanted
-- kind is passed over (Zen's review, lead section 616): a master the
-- table has without the kind is never pointed at, visited or not.
local function nearest(here, npcs, subclassID)
    if type(here) ~= "table" or here.map == nil or not (share(here.x) and share(here.y)) then return nil end
    if type(npcs) ~= "table" then return nil end
    local best, bestName, bestD
    for name, e in pairs(npcs) do
        if type(name) == "string" and type(e) == "table" and type(e.roles) == "table"
            and e.roles.weaponMaster == true and e.map == here.map and share(e.x) and share(e.y)
            and not listedWithout(name, subclassID) then
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

-- Points step at found = { name, map, x, y }.
local function point(step, found)
    step.name = found.name
    step.place = { map = found.map, x = found.x, y = found.y }
    local long = WM.LABEL .. ": " .. found.name
    if #long <= labelMax() then step.label = long end
end

function WM.Of(wanted, here, npcs)
    if type(wanted) ~= "table" or not text(wanted.skill) then return nil end
    local step = { kind = WM.KIND, label = WM.LABEL, skill = wanted.skill, subclassID = wanted.subclassID,
                   radius = WM.RADIUS }
    local found = nearest(here, npcs, wanted.subclassID)
    if found then point(step, found) end
    return step
end

function WM.Teachers(subclassID)
    local N = ns.Nav
    local list = type(N) == "table" and N.WeaponMasterNames or nil
    if type(list) ~= "table" then return nil, nil end
    local teach, all
    for name, row in pairs(list) do
        if type(name) == "string" and type(row) == "table" and type(row.skills) == "table" then
            all = all or {}
            all[name] = true
            if subclassID ~= nil and row.skills[subclassID] == true then
                teach = teach or {}
                teach[name] = true
            end
        end
    end
    return teach, all
end

-- Only a place said to be a saved one counts as visited.
function WM.Elsewhere(step, place)
    if type(step) ~= "table" or step.place ~= nil or type(place) ~= "function" then return step end
    local function try(ask)
        local ok, to, from = pcall(place, ask)
        if not ok or type(to) ~= "table" or not text(to.name) or to.map == nil
            or not (share(to.x) and share(to.y)) then
            return nil
        end
        return to, from
    end
    local teach, all = WM.Teachers(step.subclassID)
    local to, from
    local listed = false
    -- First a weapon master the table has with the wanted kind.
    if teach then
        to, from = try({ kind = WM.ASK, only = teach })
        listed = to ~= nil
    end
    -- Else one the table says nothing about (with no table: any).
    if not to then to, from = try({ kind = WM.ASK, skip = all }) end
    if not to then return step end
    point(step, to)
    local N = ns.Nav
    local PP = type(N) == "table" and N.ProfPlace or nil
    if type(PP) ~= "table" or PP.SAVED == nil or from ~= PP.SAVED then
        step.unvisited = true
        if listed then
            step.listed = true
            step.detail = WM.LISTED
        else
            step.detail = WM.NOT_KNOWN
        end
    end
    return step
end

function WM.Lines(step)
    if type(step) ~= "table" or not text(step.skill) then return {} end
    if type(step.place) == "table" and text(step.name) then
        if step.unvisited == true then
            local why = WM.NOT_KNOWN
            if step.listed == true then why = WM.LISTED end
            return { WM.UNVISITED:format(step.skill, step.name), why }
        end
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

    -- A step with no weapon master saved on this map: one known elsewhere
    -- (the profession feed's Place, WM.Elsewhere), when there is one.
    local function elsewhere(step)
        local N = ns.Nav
        local feedName = type(N) == "table" and type(N.ProfFeed) == "table" and N.ProfFeed.NAME or nil
        if feedName == nil or type(ctx.use) ~= "function" then return end
        local okUse, feed = pcall(ctx.use, feedName)
        if not okUse or type(feed) ~= "table" or type(feed.Place) ~= "function" then return end
        WM.Elsewhere(step, feed.Place)
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
        local step = WM.Of(want, ask("position"), npcs)
        if step and step.place == nil then elsewhere(step) end
        return step
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
