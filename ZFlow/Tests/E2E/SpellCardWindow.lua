local _, ns = ...
-- The new-spell card window (G33, lead section 402 item 5) through its real
-- entry, on the whole add-on loaded on a fake client: learning a spell
-- opens the card with the spell and where it sits. Where the game put it on
-- a bar (SPELL_PUSHED_TO_ACTIONBAR), the card says the bar and slot; until
-- then it advises putting it on a bar. The card's setting off: no card.
-- Show and advise only: nothing is placed, bound or cast. Made-up spell
-- ids and slots. Not tested in game.
local tests = {}

local S = ns.SpellCard
local MOONFIRE, REJUV = 8921, 774

local function boot(charSettings)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, charSettings or {})
    c.setClass("DRUID")
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

local function card(c)
    local w = c.kitWindows()[S.ID]
    if type(w) ~= "table" then return nil end
    local out = { shown = w.shown, texts = {} }
    for _, p in ipairs(w.parts or {}) do
        if p.text ~= nil then out.texts[#out.texts + 1] = p.text end
        if p.key == "where" then out.where = p.text end
    end
    return out
end

local function has(list, text)
    for _, v in ipairs(list or {}) do
        if v == text then return true end
    end
    return false
end

tests["spell card window: learning a spell opens the card with the spell and the bar advice"] = function(t)
    local c, addon = boot()
    t.eq(addon:ModuleState(S.NAME), "started")
    t.eq(card(c), nil, "no card before a spell is learned")
    c.learnSpell({ id = MOONFIRE, name = "Moonfire", rank = "Rank 2" })
    local seen = card(c)
    t.ok(seen ~= nil and seen.shown == true, "the card is shown")
    t.ok(seen and has(seen.texts, "Moonfire (Rank 2)"), "the spell and its rank")
    t.eq(seen and seen.where, "Put it on a bar: open your spellbook and drag Moonfire to an action bar.")
end

tests["spell card window: when the game puts the spell on a bar, the card says where"] = function(t)
    local c = boot()
    c.learnSpell({ id = MOONFIRE, name = "Moonfire" })
    c.fire("SPELL_PUSHED_TO_ACTIONBAR", MOONFIRE, 3)
    t.eq(card(c).where, "On your bars: Action Bar 1, slot 3 (the game put it there).")
    c.fire("SPELL_PUSHED_TO_ACTIONBAR", REJUV, 4)
    t.eq(card(c).where, "On your bars: Action Bar 1, slot 3 (the game put it there).", "another spell: unchanged")
end

tests["spell card window: a spell the game placed before it was told learned says where at once"] = function(t)
    local c = boot()
    c.fire("SPELL_PUSHED_TO_ACTIONBAR", REJUV, 4)
    c.learnSpell({ id = REJUV, name = "Rejuvenation" })
    t.eq(card(c).where, "On your bars: Action Bar 1, slot 4 (the game put it there).")
end

tests["spell card window: the next spell learned takes the card over"] = function(t)
    local c = boot()
    c.learnSpell({ id = MOONFIRE, name = "Moonfire" })
    c.learnSpell({ id = REJUV, name = "Rejuvenation" })
    local seen = card(c)
    t.ok(has(seen.texts, "Rejuvenation"))
    t.ok(not has(seen.texts, "Moonfire"), "one card, the newest spell")
end

tests["spell card window: the new-spell card setting off shows no card"] = function(t)
    local c, addon = boot()
    addon.settings:set("spells.newSpellCard", false)
    c.learnSpell({ id = MOONFIRE, name = "Moonfire" })
    t.eq(card(c), nil)
end

tests["spell card window: learning a spell adds no problem and no card fault"] = function(t)
    local c, addon = boot()
    local before = addon.problems:count()
    c.learnSpell({ id = MOONFIRE, name = "Moonfire" })
    t.eq(addon.problems:count(), before, "no new problem")
    t.eq(addon:ModuleState(S.NAME), "started")
end

return tests
