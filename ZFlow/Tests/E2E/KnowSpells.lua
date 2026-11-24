local _, ns = ...
-- KNOW lane, slice 2 (C-48, C-56, C-58), end to end on the whole add-on
-- loaded on a fake client, for each of the nine classes. Three class spells
-- are known: the first is on a bar, the second is on no bar, the third is
-- under a key that casts it.
--   C-48  the advisor says "Put <second> on your action bars"
--   C-56  the spells word opens the Spells window; the second spell has a
--         row and a Skip button, which stops the advice
--   C-58  the spellkeys word lists the key that casts the third spell
-- Section 236: the bars changing later, a bars read that raises and then
-- recovers, and a reload. Offline: the reads are the fake client's, not the
-- game's. Not tested in game.
local tests = {}

local CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
local KEY = "F5"

local function W() return ns.SpellsWindow or {} end

-- The first three spell names of the class pack, a to z.
local function three(class)
    local names = {}
    local pack = type(ns.Packs) == "table" and ns.Packs[class] or nil
    for name in pairs(type(pack) == "table" and type(pack.spells) == "table" and pack.spells or {}) do
        names[#names + 1] = name
    end
    table.sort(names)
    return names[1], names[2], names[3], names
end

-- opts: class, bars (false: not known; nil: the first spell on slot 1),
-- char (saved ahead), combat
local function boot(opts)
    opts = opts or {}
    local class = opts.class or "DRUID"
    local onBar, offBar, keyed, names = three(class)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, opts.char or {})
    c.setClass(class); c.setFaction("Alliance"); c.setLevel(20); c.setCombat(opts.combat == true)
    local known = { [onBar] = true, [offBar] = true, [keyed] = true }
    for i, name in ipairs(names) do
        c.setSpellId(name, 1000 + i)
        c.setSpell(1000 + i, { known = known[name] == true })
    end
    if opts.bars ~= false then c.setActionSpells(opts.bars or { [onBar] = 1 }) end
    c.setBindings({ { KEY, "SPELL " .. keyed } })
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon, addon.problems:count(), { onBar = onBar, offBar = offBar, keyed = keyed }
end

local function advice(addon, name)
    for _, p in ipairs(addon.advisor.List()) do
        if p.id == tostring(W().PREFIX) .. name then return p.text end
    end
    return nil
end

local function typed(c, rest)
    local from = #c.printed
    c.slashes[ns.id.slash](rest)
    local out = {}
    for i = from + 1, #c.printed do out[#out + 1] = c.printed[i] end
    return out
end

local function has(lines, text)
    for _, line in ipairs(lines) do
        if tostring(line) == text then return true end
    end
    return false
end

local function window(c)
    return c.kitWindows()[W().ID or "spells"]
end

local function part(rec, key)
    for _, p in ipairs(rec and rec.parts or {}) do
        if p.key == key then return p end
    end
    return nil
end

local function textOf(rec, key)
    local p = part(rec, key)
    if p == nil then return nil end
    return p.text
end

for _, class in ipairs(CLASSES) do
    -- C-48. Red on f31dd929: there is no such prompt (advice(...) is nil).
    tests["know 2: " .. class .. " a known spell on no bar gets the advice; one on a bar or a key does not"] = function(t)
        local _, addon, base, s = boot({ class = class })
        t.eq(advice(addon, s.offBar), "Put " .. s.offBar .. " on your action bars")
        t.eq(advice(addon, s.onBar), nil, "on a bar")
        t.eq(advice(addon, s.keyed), nil, "under a key")
        t.eq(addon.problems:count(), base, "no new problem")
    end

    -- C-56. Red on f31dd929: the word opens nothing (window(c) is nil).
    tests["know 2: " .. class .. " the spells word opens the window; Skip stops the advice for that spell"] = function(t)
        local c, addon, base, s = boot({ class = class })
        typed(c, "spells")
        local rec = window(c)
        t.ok(rec ~= nil and rec.shown == true, "the window is open")
        t.eq(textOf(rec, "row." .. s.offBar), s.offBar .. ": on no bar")
        t.eq(part(rec, "row." .. s.onBar), nil, "a spell on a bar has no row")
        t.eq(part(rec, "row." .. s.keyed), nil, "a spell under a key has no row")
        t.eq(textOf(rec, "skip." .. s.offBar), "Skip")
        t.eq(c.kitClick("spells", "skip." .. s.offBar), true, "Skip can be pressed")
        rec = window(c)
        t.eq(textOf(rec, "row." .. s.offBar), s.offBar .. ": skipped, no reminder")
        t.eq(textOf(rec, "skip." .. s.offBar), "Ask again")
        t.eq(advice(addon, s.offBar), nil, "no advice once skipped")
        t.eq(addon.store:get("char", "spells.skipped"), { [s.offBar] = true })
        t.eq(c.kitClick("spells", "skip." .. s.offBar), true, "Ask again can be pressed")
        t.eq(advice(addon, s.offBar), "Put " .. s.offBar .. " on your action bars", "asked again")
        t.eq(addon.problems:count(), base, "no new problem")
    end

    -- C-58. Red on f31dd929: the word is not one the slash command knows,
    -- so the heading is not printed (has(...) is false).
    tests["know 2: " .. class .. " the spellkeys word lists the key that casts a spell directly"] = function(t)
        local c, addon, base, s = boot({ class = class })
        local lines = typed(c, "spellkeys")
        t.ok(has(lines, ns.id.title .. ": keys that cast a spell directly (not from a bar):"), "the heading")
        t.ok(has(lines, "  " .. KEY .. ": " .. s.keyed), "the key and its spell")
        t.eq(#lines, 2, "nothing else")
        t.eq(addon.problems:count(), base, "no new problem")
    end
end

tests["know 2: no key bound says so; the help word has both words"] = function(t)
    local c = boot()
    c.setBindings({})
    t.ok(has(typed(c, "spellkeys"), ns.id.title .. ": no key casts a spell directly: they all go through your bars."),
        "none")
    for _, word in ipairs({ "spells", "spellkeys" }) do
        local line = typed(c, "help " .. word)[1]
        t.ok(type(line) == "string" and line:find(ns.id.slash .. " " .. word .. " - ", 1, true) ~= nil, tostring(line))
    end
end

tests["know 2: bars that cannot be read give no advice, and the row says so"] = function(t)
    local c, addon, _, s = boot({ bars = false })
    t.eq(advice(addon, s.offBar), nil, "not known is never 'on no bar'")
    typed(c, "spells")
    t.eq(textOf(window(c), "row." .. s.offBar), s.offBar .. ": your bars could not be read")
end

tests["know 2: the advice setting off gives none; nothing known gives the empty line"] = function(t)
    local c, addon, _, s = boot()
    addon.settings:set("spells.barAdvice", false)
    c.advance(2, 2)
    c.fire("ACTIONBAR_SLOT_CHANGED", 1)
    t.eq(advice(addon, s.offBar), nil, "switched off")
    c.setActionSpells({ [s.onBar] = 1, [s.offBar] = 2 })
    typed(c, "spells")
    t.ok(part(window(c), "empty") ~= nil, "nothing waiting: the empty line")
end

tests["know 2: a new spell learned out of a fight opens the window with it at the top"] = function(t)
    local c, addon = boot()
    t.eq(window(c), nil, "closed until asked")
    c.learnSpell({ id = 4242, name = "Test Spell", rank = "Rank 1" })
    local rec = window(c)
    t.ok(rec ~= nil and rec.shown == true, "opened")
    t.ok(part(rec, "new") ~= nil, "the learned section")
    t.eq(textOf(rec, "row.Test Spell"), "Test Spell (Rank 1): on no bar")
    t.eq(addon.use("spellsWindow").Fresh(), { "Test Spell" })
end

tests["know 2: a higher rank, a spell learned in a fight, or the setting off opens nothing"] = function(t)
    local c = boot()
    c.learnSpell({ id = 4243, name = "Test Spell", rank = "Rank 2" })
    t.eq(window(c), nil, "a higher rank")
    local c2 = boot({ combat = true })
    c2.learnSpell({ id = 4242, name = "Test Spell", rank = "Rank 1" })
    t.eq(window(c2), nil, "in a fight")
    local c3, addon3 = boot()
    addon3.settings:set("spells.openList", false)
    c3.learnSpell({ id = 4242, name = "Test Spell", rank = "Rank 1" })
    t.eq(window(c3), nil, "switched off")
end

-- Section 236: data arriving late. The spell is dragged to a bar later.
tests["know 2: the advice goes when the spell is put on a bar"] = function(t)
    local c, addon, _, s = boot()
    t.eq(advice(addon, s.offBar), "Put " .. s.offBar .. " on your action bars")
    c.setActionSpells({ [s.onBar] = 1, [s.offBar] = 2 })
    c.advance(2, 2)
    c.fire("ACTIONBAR_SLOT_CHANGED", 2)
    t.eq(advice(addon, s.offBar), nil)
end

-- Section 236: a read that raises, then recovers.
tests["know 2: a bars read that raises gives no advice, and it comes back once the read answers"] = function(t)
    local c, addon, base, s = boot()
    local real = c.actionSpells
    c.actionSpells = function() error("bars read failed") end
    c.advance(2, 2)
    c.fire("ACTIONBAR_SLOT_CHANGED", 1)
    t.eq(advice(addon, s.offBar), nil, "not known while it raises")
    c.actionSpells = real
    c.advance(2, 2)
    c.fire("ACTIONBAR_SLOT_CHANGED", 1)
    t.eq(advice(addon, s.offBar), "Put " .. s.offBar .. " on your action bars")
    t.eq(addon.problems:count(), base, "no new problem")
end

-- Section 236: a reload. A skipped spell stays skipped.
tests["know 2: a skipped spell stays skipped over a reload"] = function(t)
    local c, _, _, s = boot()
    typed(c, "spells")
    c.kitClick("spells", "skip." .. s.offBar)
    local c2, addon2 = boot({ char = c.saved(ns.id.charDB) })
    t.eq(advice(addon2, s.offBar), nil, "still skipped")
    typed(c2, "spells")
    t.eq(textOf(window(c2), "row." .. s.offBar), s.offBar .. ": skipped, no reminder")
end

return tests
