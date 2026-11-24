local _, ns = ...
-- The new-spell line (G33, UI/SpellCard.lua) on the whole add-on loaded on
-- a fake client, a priest, through its real entry: the game telling that a
-- spell was learned (client onSpellLearned, played by c.learnSpell; wired by
-- Spells/TrainerModule.lua). The player reads one line in chat, and a tip
-- line for a spell the class pack gives one. Show only: nothing is cast,
-- bound or set on a secure button. Unknown data: a learned spell with no
-- name, no rank, and a class that is not known. Not tested in game.
local tests = {}

local M = ns.TrainerModule

local function start(class)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    if class then c.setClass(class) end
    c.setFaction("Alliance"); c.setLevel(20); c.setDead(false); c.setCombat(false)
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

local function learned(c, spell)
    local from = #c.printed + 1
    c.learnSpell(spell)
    local out = {}
    for i = from, #c.printed do out[#out + 1] = tostring(c.printed[i]) end
    return out
end

local function secureCount(c)
    local binds = type(c.bindingCalls) == "function" and #c.bindingCalls() or 0
    return #c.secureGiven + binds + #(c.clickRows or {})
end

tests["spell card: a learned spell prints its name and rank, and the pack's tip"] = function(t)
    local c, addon = start("PRIEST")
    local title = ns.id.title .. ": "
    t.eq(addon.settings:get(M.SETTING_CARD), true, "on by default")
    local before = secureCount(c)
    t.eq(learned(c, { id = 2061, name = "Flash Heal", rank = "Rank 1" }),
        { title .. "New spell: Flash Heal (Rank 1)" }, "one line, no tip for a rule spell")
    local pack = ns.Packs and ns.Packs.PRIEST
    local row = pack and pack.spells and pack.spells["Mind Soothe"]
    local tip = row and row.tip
    t.ok(type(tip) == "string", "the priest pack has a tip for Mind Soothe")
    t.eq(learned(c, { id = 453, name = "Mind Soothe", rank = "Rank 1" }),
        { title .. "New spell: Mind Soothe (Rank 1)", title .. "Tip: " .. tostring(tip) }, "the tip line follows")
    t.eq(secureCount(c), before, "nothing cast, bound or set")

    addon.settings:set(M.SETTING_CARD, false)
    t.eq(learned(c, { id = 2061, name = "Flash Heal", rank = "Rank 2" }), {}, "switched off: no line")
end

tests["spell card: unknown data: no name, no rank, no class"] = function(t)
    local c = start(nil)
    local title = ns.id.title .. ": "
    local before = secureCount(c)
    t.eq(learned(c, { id = 1 }), {}, "a spell with no name: no line")
    t.eq(learned(c, { id = 2, name = "" }), {}, "an empty name: no line")
    t.eq(learned(c, { id = 3, name = "Attack", rank = "" }), { title .. "New spell: Attack" }, "no rank: none guessed")
    t.eq(learned(c, { id = 453, name = "Mind Soothe" }), { title .. "New spell: Mind Soothe" },
        "class not known: no pack, no tip")
    t.eq(secureCount(c), before, "nothing cast, bound or set")
end

return tests
