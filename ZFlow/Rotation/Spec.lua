local _, ns = ...

-- The spec word (G31): the spec your class's pack recommends while you
-- level alone, and why, then the role you chose (Rotation/Role.lua). And
-- one line, with the same lines after it, when you reach the level talents
-- open at. It only prints: no setting, talent, form or gear is touched, and
-- the word changes nothing whatever follows it (the role word sets a role).
--
-- Unspent points are not read, so nothing is said of them until a
-- readable talent API is seen in this client (probe ZP2). The points spent
-- per tree are read only to say where the role comes from (D-new-7).
--
--   Sp.Recommended(pack) -> rec or nil
--     rec = { role, name, why }   the pack's levelling row: its role, the
--     pack's own name for that role (or nil), the reasons that are words.
--     nil: no pack, no row, or a row naming a role the pack has no part for.
--   Sp.Lines(pack, chosen) -> lines
--     pack    the class pack, or nil when the class has none
--     chosen  the role setting: "dps", "heal", "tank"; anything else: none
--   Sp.Declare(k[, diag, packs]) -> { lines = fn }
--     the module on kernel k, and the word Sp.WORD after the slash command.
local Sp = {}
ns.RotationSpec = Sp

local Ro = ns.RotationRole

Sp.NAME = "rotationSpec"
Sp.WORD = "spec"
Sp.HELP = "the levelling spec recommended for your class and why, and the role you chose"
-- The level the first talent point comes at. Carried over from the old
-- add-on's spec reminder (Modules/Spec.lua); not read from this client.
Sp.TALENT_LEVEL = 10
Sp.LEVEL_EVENT = "PLAYER_LEVEL_UP"
Sp.UNLOCKED = "talents unlocked: you have your first talent point to spend."
Sp.NO_CLASS = "your class is not known yet. Try again in a moment."
Sp.NO_PACK = "there is no rotation for your class, so no levelling spec is recommended."
Sp.NO_ROW = "no levelling spec is recommended for your class yet."

local function roleOf(value)
    if type(value) == "string" and Ro.WORDS[value] ~= nil then return value end
    return nil
end

-- The pack's row for a role, or nil; and its own name for it, or nil.
local function partOf(pack, role)
    if type(pack) ~= "table" or type(pack.roles) ~= "table" then return nil, nil end
    local row = pack.roles[role]
    if type(row) ~= "table" then return nil, nil end
    local name = nil
    if type(row.name) == "string" and row.name ~= "" then name = row.name end
    return row, name
end

-- A role in words, with the pack's own name for it when it has one.
local function named(role, name)
    if name ~= nil then return Ro.WORDS[role] .. " (" .. name .. ")" end
    return Ro.WORDS[role]
end

function Sp.Recommended(pack)
    if type(pack) ~= "table" or type(pack.levelling) ~= "table" then return nil end
    local role = roleOf(pack.levelling.role)
    if role == nil then return nil end
    local row, name = partOf(pack, role)
    if row == nil then return nil end
    local why = {}
    if type(pack.levelling.why) == "table" then
        for _, reason in ipairs(pack.levelling.why) do
            if type(reason) == "string" and reason ~= "" then why[#why + 1] = reason end
        end
    end
    return { role = role, name = name, why = why }
end

-- The line about the role you chose, beside what is recommended (rec may
-- be nil).
local function roleLine(pack, chosen, rec)
    local role = roleOf(chosen)
    if role == nil then
        return "no role chosen. " .. ns.id.slash .. " " .. Ro.WORD .. " dps, heal or tank sets one."
    end
    local row, name = partOf(pack, role)
    if row == nil then
        local word = Ro.WORDS[role]
        return "your role is set to " .. word .. ", but your class's rotation has no " .. word .. " part."
    end
    local set = "your role is set to " .. named(role, name)
    if rec == nil then return set .. "." end
    if rec.role == role then return set .. ", the recommended one." end
    return set .. ". That is yours to choose: the recommendation is for levelling alone."
end

function Sp.Lines(pack, chosen)
    if type(pack) ~= "table" then return { Sp.NO_PACK } end
    local rec = Sp.Recommended(pack)
    if rec == nil then return { Sp.NO_ROW, roleLine(pack, chosen, nil) } end
    local spec = Ro.WORDS[rec.role]
    if rec.name ~= nil then spec = rec.name .. " (" .. spec .. ")" end
    local lines = { "recommended levelling spec: " .. spec .. "." }
    for i = 1, #rec.why do lines[#lines + 1] = rec.why[i] end
    lines[#lines + 1] = roleLine(pack, chosen, rec)
    return lines
end

-- D-new-7: which role the spec word speaks of, and where it came from.
-- Your own role setting wins; when it is not set, the talent tree you put
-- the most points in; before talents, the pack's recommended levelling
-- role. Only words: the rotation reads none of this, so what the key casts
-- is unchanged. Talents are read as the client gives them (each tree's
-- name and points spent: CLIENT NEED talentTrees), and a tree is matched
-- to a role by the pack's own name for that role. No talent table is
-- written here.
--
--   Sp.FromTalents(pack, trees) -> role, tree name, points; or nil
--   Sp.Source(pack, chosen, trees) -> { role, from, talents, tree, points }
--     from: "setting", "talents" or "default"
--   Sp.SourceLines(pack, chosen, trees) -> lines
function Sp.FromTalents(pack, trees)
    if type(pack) ~= "table" or type(pack.roles) ~= "table" or type(trees) ~= "table" then return nil end
    local best, bestPoints, tie = nil, 0, false
    for _, tree in ipairs(trees) do
        if type(tree) == "table" and type(tree.name) == "string" and type(tree.points) == "number" then
            if tree.points > bestPoints then
                best, bestPoints, tie = tree.name, tree.points, false
            elseif tree.points == bestPoints and bestPoints > 0 then
                tie = true
            end
        end
    end
    -- An even split says nothing about which way the build leans.
    if best == nil or tie then return nil end
    for _, role in ipairs({ "dps", "heal", "tank" }) do
        local _, name = partOf(pack, role)
        if name ~= nil and name:lower() == best:lower() then return role, name, bestPoints end
    end
    return nil
end

function Sp.Source(pack, chosen, trees)
    local talents, tree, points = Sp.FromTalents(pack, trees)
    local out = { talents = talents, tree = tree, points = points }
    local set = roleOf(chosen)
    if set ~= nil then
        out.role, out.from = set, "setting"
    elseif talents ~= nil then
        out.role, out.from = talents, "talents"
    else
        local rec = Sp.Recommended(pack)
        out.from = "default"
        if rec ~= nil then out.role = rec.role end
    end
    return out
end

function Sp.SourceLines(pack, chosen, trees)
    local s = Sp.Source(pack, chosen, trees)
    if s.role == nil then
        return { "spec in use: not known. No role set, no talent points read, and nothing recommended." }
    end
    local _, name = partOf(pack, s.role)
    local what = "spec in use: " .. named(s.role, name)
    if s.from == "setting" then
        local lines = { what .. ", from your role setting." }
        if s.talents ~= nil and s.talents ~= s.role then
            lines[#lines + 1] = "note: your talents lean to " .. named(s.talents, s.tree)
                .. " (" .. s.points .. " points there), not the role you set."
        end
        return lines
    end
    if s.from == "talents" then
        return { what .. ", from your talents (" .. s.points .. " points in " .. s.tree .. ")." }
    end
    return { what .. ", the default: no role set and no talent points read, so the recommended one." }
end

-- The module on kernel k. diag (optional) is what Diag.Start returned;
-- packs: { [class token] = pack }, ns.Packs when left out.
function Sp.Declare(k, diag, packs)
    local api = {}
    local client

    -- The class token, or nil while it is not known: no client yet, no
    -- such read, no answer, or the read raised.
    local function classNow()
        if type(client) ~= "table" or type(client.class) ~= "function" then return nil end
        local ok, class = pcall(client.class)
        if ok and type(class) == "string" and class ~= "" then return class end
        return nil
    end

    function api.lines()
        local class = classNow()
        if class == nil then return { Sp.NO_CLASS } end
        local all = packs or ns.Packs
        local pack = nil
        if type(all) == "table" then pack = all[class] end
        return Sp.Lines(pack, k.settings:get(Ro.SETTING))
    end

    local function say(text)
        if client then client.print(ns.id.title .. ": " .. text) end
    end

    -- The talent trees, or nil while not known: no such read, no answer,
    -- or the read raised.
    local function treesNow()
        if type(client) ~= "table" or type(client.talentTrees) ~= "function" then return nil end
        local ok, trees = pcall(client.talentTrees)
        if ok and type(trees) == "table" then return trees end
        return nil
    end

    -- Where the role comes from; nothing when the class or its pack is
    -- not known, since there is no role to speak of.
    function api.sourceLines()
        local class = classNow()
        if class == nil then return {} end
        local all = packs or ns.Packs
        if type(all) ~= "table" or type(all[class]) ~= "table" then return {} end
        return Sp.SourceLines(all[class], k.settings:get(Ro.SETTING), treesNow())
    end

    local function run()
        local lines = api.lines()
        for i = 1, #lines do say(lines[i]) end
        local more = api.sourceLines()
        for i = 1, #more do say(more[i]) end
    end

    -- Only the level the event itself names counts: a level-up that names
    -- none is never taken for the talent level.
    local function onLevel(level)
        if type(level) ~= "number" or level ~= Sp.TALENT_LEVEL then return end
        say(Sp.UNLOCKED)
        local class = classNow()
        local all = packs or ns.Packs
        -- A class with no rotation has nothing recommended: the level line alone.
        if class ~= nil and (type(all) ~= "table" or type(all[class]) ~= "table") then return end
        run()
    end

    k:Module({
        name = Sp.NAME,
        needs = { "client", "store", "bus", Ro.NAME },
        start = function(ctx)
            client = ctx.client
            ctx.bus:on(Sp.NAME, Sp.LEVEL_EVENT, onLevel)
        end,
    })

    if diag and type(diag.commands) == "table" then
        diag.commands[Sp.WORD] = run
        if type(diag.help) == "table" then diag.help[Sp.WORD] = Sp.HELP end
    end

    return api
end

-- The addon's own: declared when this file loads. It says nothing until
-- the word is used or the talent level is reached.
ns.rotationSpec = Sp.Declare(ns, ns.diag)
