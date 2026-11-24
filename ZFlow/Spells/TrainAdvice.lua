local _, ns = ...

-- Training advice (lead sections 387 R7, 388 b): a spell of the class pack
-- at or below the player's level that the player has not learned gets one
-- advisor prompt, "Train Charge at your class trainer (improves DPS)". The
-- alerts list says the advisor's prompts numbered in chat at login and
-- after a level-up. A spell the pack notes as "from a class quest" is left
-- to Spells/ClassQuests.lua. Look-only: nothing is trained or cast.
--
--   prompts = TrainAdvice.Prompts(pack, level, known)
--   shown   = TrainAdvice.Sync(advisor, pack, level, known, shown)
-- known(name) -> true / false, or nil when not read: a spell not read is
-- never advised (nothing is guessed). The pack's levels are first guesses
-- (Rotation/Pack.lua), so the line says "your class trainer", not a level.
--
-- Client reads: level(), class(), spellId(name), spell(id).known. Needs game
-- test: whether spellId names a spell the player has not learned yet; when
-- it does not, the spell is "not read" and no prompt is made.
--
-- Setting (char, on by default): spells.trainAdvice "Spells to train".

local T = {}
ns.TrainAdvice = T

T.NAME = "trainAdvice"
T.SETTING = "spells.trainAdvice"
T.PREFIX = "aps.trainer.advice."
T.PRIORITY = 2
T.TEXT = "Train %s at your class trainer (improves %s)"
T.TEXT_PLAIN = "Train %s at your class trainer"

local function call(f, ...)
    if type(f) ~= "function" then return nil end
    return f(...)
end

local function get(t, k)
    if type(t) ~= "table" then return nil end
    return t[k]
end

local function questSpell(row)
    return type(row.note) == "string" and row.note:find("class quest", 1, true) ~= nil
end

local function improvesText(list)
    if type(list) ~= "table" then return nil end
    local words = {}
    for _, w in ipairs(list) do
        if type(w) == "string" and w ~= "" then words[#words + 1] = w end
    end
    if #words == 0 then return nil end
    if #words == 1 then return words[1] end
    return table.concat(words, ", ", 1, #words - 1) .. " and " .. words[#words]
end

function T.Prompts(pack, level, known)
    local out = {}
    local spells = get(pack, "spells")
    if type(spells) ~= "table" or type(level) ~= "number" or type(known) ~= "function" then return out end
    for name, row in pairs(spells) do
        if type(name) == "string" and type(row) == "table" and type(row.level) == "number"
            and row.level <= level and not questSpell(row) and known(name) == false then
            local why = improvesText(row.improves)
            out[#out + 1] = { id = T.PREFIX .. name, level = row.level, priority = T.PRIORITY,
                text = why and string.format(T.TEXT, name, why) or string.format(T.TEXT_PLAIN, name) }
        end
    end
    table.sort(out, function(a, b)
        if a.level ~= b.level then return a.level < b.level end
        return a.id < b.id
    end)
    return out
end

-- Puts the current prompts in the advisor and removes the ones this module
-- added before that no longer apply. Returns the new shown set.
function T.Sync(advisor, pack, level, known, shown)
    local now = {}
    if type(advisor) ~= "table" or type(advisor.Add) ~= "function" or type(advisor.Remove) ~= "function" then
        return now
    end
    for _, p in ipairs(T.Prompts(pack, level, known)) do
        if advisor.Add(p.id, p.text, p.priority) then now[p.id] = true end
    end
    if type(shown) == "table" then
        for id in pairs(shown) do
            if type(id) == "string" and id:sub(1, #T.PREFIX) == T.PREFIX and not now[id] then
                advisor.Remove(id)
            end
        end
    end
    return now
end

-- known(name) from the client: true or false when the spell's id and its
-- known flag are read, else nil.
function T.Known(client)
    return function(name)
        local id = call(get(client, "spellId"), name)
        if type(id) ~= "number" then return nil end
        local k = get(call(get(client, "spell"), id), "known")
        if type(k) ~= "boolean" then return nil end
        return k
    end
end

function T.Declare(k)
    local shown = {}
    k:Module({
        name = T.NAME,
        needs = { "client", "bus", "advisor" },
        settings = {
            { key = T.SETTING, scope = "char", type = "bool", default = true,
              label = "Spells to train",
              help = "Say which of your class spells you can train at your level and what each improves. It trains nothing.",
              group = "combat.spells", synonyms = { "trainer", "train", "spells", "advice" } },
        },
        start = function(ctx)
            local advisor = ctx.use("advisor")
            local function refresh()
                local ok, err = pcall(function()
                    if ctx.settings:get(T.SETTING) ~= true then
                        shown = T.Sync(advisor, nil, nil, nil, shown)
                        return
                    end
                    local class = call(get(ctx.client, "class"))
                    local pack = type(class) == "string" and get(ns.Packs, class) or nil
                    shown = T.Sync(advisor, pack, call(get(ctx.client, "level")), T.Known(ctx.client), shown)
                end)
                if not ok then k.problems:add("spells", "train advice", tostring(err)) end
            end
            ctx.bus:on(T.NAME, "PLAYER_LEVEL_UP", refresh)
            ctx.bus:on(T.NAME, "TRAINER_CLOSED", refresh)
            refresh()
        end,
    })
end

-- The addon's own: declared when this file loads, started at login.
T.Declare(ns)
