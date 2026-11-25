local _, ns = ...
-- The panels say what they are (owner's report, lead sections 561 item 6 and
-- 564 R8): the first time "Advice" and "Your buffs" show, a row under the
-- title says what the panel is. That it was said is kept for the account,
-- so it is not said again after a reload. The words are not tested (lead
-- section 559); where they show and the saved data are. Whole add-on on a
-- fake client. Not tested in game.
local tests = {}

local A, B = ns.Advisor, ns.BuffStrip

local function start(account)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, account or { layout = { arrowIntroSeen = true } })
    c.setSaved(ns.id.charDB, {})
    c.setScreen(1024, 768)
    c.setFrameRect(B.FRAME, { l = 20, r = 250, b = 640, t = 740 })
    c.setClass("MAGE")
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(2, 4)
    return c, addon
end

local function part(c, id, key)
    local w = c.kitWindows()[id]
    for _, p in ipairs(w and w.parts or {}) do
        if p.key == key then return p end
    end
    return nil
end

tests["panels explain: Advice says what it is above its prompts, once for the account"] = function(t)
    local c, addon = start()
    addon.advisor.Add("test.one", "Repair your gear.", 10)
    c.advance(1, 2)
    local about = part(c, A.KIT_ID, "about")
    t.ok(about ~= nil, "a row says what the panel is")
    t.eq(about and about.kind, "section", "not one of the prompts")
    local w = c.kitWindows()[A.KIT_ID]
    t.eq(w and w.parts[1] and w.parts[1].key, "about", "above the prompts")
    t.eq(addon.store:get("account", A.EXPLAINED), true, "kept: it was said")
    local c2, addon2 = start(c.saved(ns.id.accountDB))
    addon2.advisor.Add("test.one", "Repair your gear.", 10)
    c2.advance(1, 2)
    t.ok(c2.kitWindows()[A.KIT_ID] ~= nil, "the panel shows after the reload")
    t.eq(part(c2, A.KIT_ID, "about"), nil, "and does not say it again")
end

tests["panels explain: Your buffs says what it is the first time, not after a reload"] = function(t)
    local c, addon = start()
    c.setPlayerBuffs({ ["Arcane Intellect"] = 1500 })
    c.advance(B.EVERY + 0.1, 2)
    t.ok(part(c, B.ID, "about") ~= nil, "a row says what the strip is")
    t.eq(addon.store:get("account", B.EXPLAINED), true, "kept: it was said")
    local c2 = start(c.saved(ns.id.accountDB))
    c2.setPlayerBuffs({ ["Arcane Intellect"] = 1500 })
    c2.advance(B.EVERY + 0.1, 2)
    t.ok(c2.kitWindows()[B.ID] ~= nil, "the strip shows after the reload")
    t.eq(part(c2, B.ID, "about"), nil, "and does not say it again")
end

return tests
