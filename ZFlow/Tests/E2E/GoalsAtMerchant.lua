local _, ns = ...
-- Lead sections 214/215 (Zen). Goals at the merchant, end to end, on the
-- whole add-on loaded on a fake client: a goal SAVED for the character
-- (settings.goals, as Items/Goals.lua reads it) or added with the goal word
-- -> the "goals" Reservations source -> one evaluation per merchant visit
-- -> the sell list the player is shown. No test-only source.
-- Offline: the reads are the fake client's, not the game's. Not tested in game.
local tests = {}

local PELT = 4865
local INFO = {
    [PELT] = { name = "Ruined Pelt", quality = 0, sellPrice = 5, classID = 15 },
}
local BAG = { { item = PELT, count = 15 }, { item = PELT, count = 5 } }   -- 20 pelts

-- goals: what settings.goals holds for this character (nil: nothing saved).
-- bagsUnread: the bag read answers nil (setBagItems is never called).
local function start(goals, bagsUnread)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, goals ~= nil and { settings = { goals = goals } } or {})
    c.setItemInfo(INFO)
    if not bagsUnread then c.setBagItems(BAG) end
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

local function panelOf(c)
    for _, p in ipairs(c.panels) do
        if type(p.spec) == "table" and p.spec.name == ns.id.framePrefix .. "SellList" then return p end
    end
    return nil
end

local function joined(lines) return table.concat(lines or {}, " / ") end

local function has(lines, text)
    for _, l in ipairs(lines or {}) do
        if l == text then return true end
    end
    return false
end

local function finds(lines, text)
    for _, l in ipairs(lines or {}) do
        if l:find(text, 1, true) then return true end
    end
    return false
end

-- The counts of the pelt rows offered for sale ("<n> x Ruined Pelt: ...").
local function peltRows(lines)
    local out = {}
    for _, l in ipairs(lines or {}) do
        local n = l:match("^(%d+) x Ruined Pelt: ")
        if n then out[#out + 1] = tonumber(n) end
    end
    return out
end

-- One merchant visit: the sell panel as the player sees it while the window
-- is open. -> shown, a copy of its lines (nil when there is no panel).
local function visit(c)
    c.setMerchantOpen(true)
    local p = panelOf(c)
    local shown, lines = p ~= nil and p.shown or false, nil
    if p then
        lines = {}
        for i, l in ipairs(p.lines) do lines[i] = l end
    end
    c.setMerchantOpen(false)
    return shown, lines
end

-- What one slash line prints.
local function say(c, rest)
    local from = #c.printed
    c.slashes[ns.id.slash](rest)
    local out = {}
    for i = from + 1, #c.printed do out[#out + 1] = tostring(c.printed[i]) end
    return out
end

tests["goals at merchant: a saved goal of 8 of 20 leaves 12 to sell and says 8 are held"] = function(t)
    local c = start({ { item = PELT, count = 8 } })
    local shown, lines = visit(c)
    t.ok(shown, "the sell panel is shown at the merchant")
    t.eq(peltRows(lines), { 12 }, "one pelt row, twelve offered: " .. joined(lines))
    t.ok(has(lines, ns.ItemPresent.KEPT_HEADER), "a kept part: " .. joined(lines))
    t.ok(has(lines, "Ruined Pelt: 8 held for your steps"), "eight held, with why: " .. joined(lines))
    t.ok(not finds(lines, "eservations not known"), "no unknown line: " .. joined(lines))
end

tests["goals at merchant: a goal added with the goal word shows at the next merchant list"] = function(t)
    local c = start(nil)
    local shown, before = visit(c)
    t.ok(shown, "the sell panel is shown at the first visit")
    t.eq(peltRows(before), { 20 }, "no goal yet: all twenty offered: " .. joined(before))
    t.ok(not finds(before, "held for your steps"), "nothing held yet: " .. joined(before))

    t.eq(say(c, "goal add " .. PELT .. " 8"), { ns.id.title .. ": Goal set: keep 8 x Ruined Pelt." },
        "the word says the goal is set")

    local shownAgain, after = visit(c)
    t.ok(shownAgain, "the sell panel is shown at the next visit")
    t.eq(peltRows(after), { 12 }, "the new hold: twelve offered: " .. joined(after))
    t.ok(has(after, "Ruined Pelt: 8 held for your steps"), "eight held, with why: " .. joined(after))
end

tests["goals at merchant: bags not read with a goal saved gives no sell advice and says it can't list"] = function(t)
    local c, addon = start({ { item = PELT, count = 8 } }, true)
    t.eq(addon.reservations.Current().status, addon.Reservations.UNAVAILABLE,
        "the goal can't be worked out without the bags")
    local shown, lines = visit(c)
    t.ok(shown, "the sell panel is shown at the merchant")
    t.ok(has(lines, "Can't list what to sell: " .. ns.ItemSell.BAGS_UNREAD), "says it can't list: " .. joined(lines))
    t.eq(peltRows(lines), {}, "no pelt offered: " .. joined(lines))
    t.ok(not has(lines, ns.ItemPresent.SELL_HEADER), "no sell header: " .. joined(lines))
    t.ok(not has(lines, ns.ItemPresent.NOTHING_TO_SELL), "not told there is nothing to sell either: " .. joined(lines))
    -- Section 220 (Zen's section 218 read): the panel above does NOT depend
    -- on the goal. With the bags not read the sell list says it can't list
    -- before it looks at the reservations (UI/SellList.lua Lines: the
    -- unavailable case needs the bags read), so the same bags with no goal
    -- saved give the same panel. Only the status depends on the goal:
    -- unavailable with it, none without it. Both halves are pinned here.
    local c2, addon2 = start(nil, true)
    t.eq(addon2.reservations.Current().status, addon2.Reservations.NONE,
        "no goal, bags not read: nothing reserved, not unavailable")
    local shown2, lines2 = visit(c2)
    t.ok(shown2, "the sell panel is shown with no goal too")
    t.eq(lines2, lines, "the same panel with no goal: the goal shows only in the status")
end

-- Section 216 case (5), through settings.goals: a goal for more than the
-- bags hold holds what the bags hold, never more, and offers none of it.
tests["goals at merchant: a saved goal of 30 with 20 in the bags offers none and says 20 are held"] = function(t)
    local c, addon = start({ { item = PELT, count = 30 } })
    t.eq(addon.reservations.Current().status, addon.Reservations.OK, "the goal is worked out")
    local shown, lines = visit(c)
    t.ok(shown, "the sell panel is shown at the merchant")
    t.eq(peltRows(lines), {}, "no pelt offered: " .. joined(lines))
    t.ok(has(lines, "Ruined Pelt: 20 held for your steps"), "twenty held, the bag count: " .. joined(lines))
    t.ok(not finds(lines, "30 held"), "never the goal's thirty: " .. joined(lines))
    t.ok(not finds(lines, "eservations not known"), "no unknown line: " .. joined(lines))
end

tests["goals at merchant: no goal saved gives the sell advice there was before goals"] = function(t)
    local c, addon = start(nil)
    t.eq(addon.reservations.Current().status, addon.Reservations.NONE, "no goal: nothing reserved")
    local shown, lines = visit(c)
    t.ok(shown, "the sell panel is shown at the merchant")
    t.eq(peltRows(lines), { 20 }, "all twenty offered: " .. joined(lines))
    t.ok(not finds(lines, "held for your steps"), "nothing held: " .. joined(lines))
    t.ok(not finds(lines, "eservations not known"), "no unknown line: " .. joined(lines))
    -- The same list as one made with an explicit "none" evaluation and no
    -- grants: what the sell list said before goals existed. (Lead section
    -- 222, SR-3 and MyBuddy GE-1: an explicit evaluation, not nil, so the
    -- comparison stays a real one once Lines treats a missing evaluation as
    -- unavailable. The guard that carries the case is the asserts above.)
    t.eq(lines, addon.SellList.Lines(c, nil, nil, { status = addon.Reservations.NONE }),
        "the list with nothing reserved")
end

return tests
