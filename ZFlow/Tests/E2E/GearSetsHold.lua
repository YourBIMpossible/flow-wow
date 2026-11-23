local _, ns = ...
-- Package P-SETS, branch 1 (lead DISPATCH section 230, item 4). Saved gear
-- sets end to end, on the whole add-on loaded on a fake client: the set
-- word saves what the character wears as item keys in its own saved data;
-- every context builder (the sell list, the bank list and the banker word,
-- the loot note) is fed those sets, so Disposition's inSet rule keeps a set
-- piece; hovering a set piece adds the keep line. No acting call is made.
-- Offline: the reads are the fake client's, not the game's. Not tested in game.
-- Made-up items only.
local tests = {}

local CLOAK, SWORD, RING, HELM = 1000, 2000, 15234, 3000
local LINK = {
    cloak = "item:1000:0:0:0:0:0:0:0",
    sword = "item:2000:0:0:0:0:0:0:0",
    ringBear = "item:15234:0:0:0:0:0:588:0",    -- key "15234:588"
    ringEagle = "item:15234:0:0:0:0:0:589:0",   -- the same ID, another suffix
    helm = "item:3000:0:0:0:0:0:0:0",
}
local INFO = {
    [CLOAK] = { name = "Frayed Cloak", quality = 0, sellPrice = 4, classID = 4 },
    [SWORD] = { name = "Bent Sword", quality = 0, sellPrice = 9, classID = 2 },
    [RING] = { name = "Dull Ring", quality = 0, sellPrice = 6, classID = 4 },
    [HELM] = { name = "Dented Helm", quality = 0, sellPrice = 7, classID = 4 },
}
-- What the character wears: back, main hand, a finger.
local WORN = { [15] = LINK.cloak, [16] = LINK.sword, [11] = LINK.ringBear }

-- opts: char, account (saved tables), worn (slot -> link; nil: the worn read
-- is never set, so it is not known), bag (stacks).
local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, opts.account or {})
    c.setSaved(ns.id.charDB, opts.char or {})
    c.setItemInfo(INFO)
    c.setBagItems(opts.bag or { { item = LINK.cloak, count = 1 } })
    if opts.worn then
        for slot, link in pairs(opts.worn) do c.setWorn(slot, link) end
    end
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

local function joined(lines) return table.concat(lines or {}, " / ") end

local function has(lines, text)
    for _, l in ipairs(lines or {}) do
        if l == text then return true end
    end
    return false
end

local function starts(lines, prefix)
    for _, l in ipairs(lines or {}) do
        if l:sub(1, #prefix) == prefix then return true end
    end
    return false
end

local function count(lines, prefix)
    local n = 0
    for _, l in ipairs(lines or {}) do
        if l:sub(1, #prefix) == prefix then n = n + 1 end
    end
    return n
end

-- What one slash line prints, the title taken off.
local function say(c, rest)
    local from = #c.printed
    c.slashes[ns.id.slash](rest)
    local out, p = {}, ns.id.title .. ": "
    for i = from + 1, #c.printed do
        local line = tostring(c.printed[i])
        if line:sub(1, #p) == p then line = line:sub(#p + 1) end
        out[#out + 1] = line
    end
    return out
end

local function panelOf(c, name)
    for _, p in ipairs(c.panels) do
        if type(p.spec) == "table" and p.spec.name == ns.id.framePrefix .. name then return p end
    end
    return nil
end

local function copy(lines)
    local out = {}
    for i, l in ipairs(lines or {}) do out[i] = l end
    return out
end

-- One merchant visit: the sell panel's lines while the window is open.
local function visit(c)
    c.setMerchantOpen(true)
    local p = panelOf(c, "SellList")
    local lines = p and copy(p.lines) or nil
    c.setMerchantOpen(false)
    return lines
end

local function savedSets(c)
    local db = c.saved(ns.id.charDB)
    return type(db.state) == "table" and db.state.gearSets or nil
end

-- The set word -------------------------------------------------------------

-- Fails before: Gear/Sets.lua (the set word, GearSets.Run "save") and
-- Core/Client.lua / ClientFake.lua c.wornLinks are absent: the word prints
-- the add-on's "type help" line and nothing is saved.
tests["gear sets: set save keeps what you wear, by item key, for this character only"] = function(t)
    local c = start({ worn = WORN })
    t.eq(say(c, "set save Tank"), { "Set tank saved: 3 pieces." })
    local sets = savedSets(c)
    t.ok(type(sets) == "table" and #sets == 1, "one set saved for the character")
    local set = type(sets) == "table" and sets[1] or {}
    t.eq(set.name, "tank", "the name as typed (the slash line is lower-cased)")
    t.eq(set.items, { "15234:588", CLOAK, SWORD }, "item keys in slot order: the ring keeps its suffix")
    local fields = {}
    for key in pairs(set) do fields[#fields + 1] = tostring(key) end
    table.sort(fields)
    t.eq(fields, { "items", "name", "slots" }, "a set holds its name, its keys and their slots (no character name)")
    t.eq(set.slots, { 11, 15, 16 }, "the slot each key was worn in, in the same order")
    local account = c.saved(ns.id.accountDB)
    t.eq(account.state, nil, "nothing saved account wide")
end

-- Fails before: the set word is absent (Gear/Sets.lua GearSets.Run, the
-- "not read" answer to c.wornLinks() returning nil).
tests["gear sets: what you wear not readable says so and saves nothing"] = function(t)
    local c = start()
    t.eq(say(c, "set save tank"), { "Can't read what you wear right now, so no set was saved." })
    t.eq(savedSets(c), nil, "nothing saved")
end

-- Fails before: the set word is absent (GearSets.Run, the listing; the
-- imported sets read from account settings.gear.mySets).
tests["gear sets: the set word lists your sets and the imported ones, or says how to make one"] = function(t)
    local account = { settings = { gear = { mySets = { heal = { [1] = LINK.helm, [5] = "item:3001:0:0:0:0:0:0:0" } } } } }
    local c = start({ worn = WORN, account = account,
        bag = { { item = LINK.cloak, count = 1 }, { item = LINK.helm, count = 1 } } })
    t.eq(say(c, "set"), {
        "You have no saved sets. Say " .. ns.id.slash .. " set save <name> to save what you wear as one.",
        "Imported from " .. ns.id.predecessor .. " (not used to keep items): heal (2 pieces)",
    })
    say(c, "set save tank")
    t.eq(say(c, "set"), {
        "Your sets: tank (3 pieces)",
        "Imported from " .. ns.id.predecessor .. " (not used to keep items): heal (2 pieces)",
    })
    -- The imported set is shown only: its helm is still offered (it is
    -- account wide, so it may be another character's).
    local lines = visit(c)
    t.ok(starts(lines, "1 x Dented Helm: "), "the imported set's helm is offered: " .. joined(lines))
    t.ok(has(lines, "Frayed Cloak: in your tank set"), "your own set holds: " .. joined(lines))
end

-- The hold ---------------------------------------------------------------

-- Fails before: UI/SellList.lua Lines builds its context without `sets`
-- (and the set word is absent), so the cloak is offered as junk.
tests["gear sets: a saved set piece is never offered at the merchant; the kept section names the set"] = function(t)
    local c = start({ worn = WORN })
    local before = visit(c)
    t.ok(starts(before, "1 x Frayed Cloak: "), "no set yet: the grey cloak is offered: " .. joined(before))

    say(c, "set save tank")
    local after = visit(c)
    t.ok(not starts(after, "1 x Frayed Cloak: "), "the set piece is not offered: " .. joined(after))
    t.ok(has(after, ns.ItemPresent.KEPT_HEADER), "a kept section: " .. joined(after))
    t.ok(has(after, "Frayed Cloak: in your tank set"), "kept, naming the set: " .. joined(after))
end

-- Fails before: the set word is absent and Reservations.Changed is not
-- called by it, so an open list does not change.
tests["gear sets: saving and forgetting with the merchant open relists at once"] = function(t)
    local c = start({ worn = WORN })
    c.setMerchantOpen(true)
    local p = panelOf(c, "SellList")
    t.ok(starts(p.lines, "1 x Frayed Cloak: "), "offered before: " .. joined(p.lines))
    say(c, "set save tank")
    t.ok(has(p.lines, "Frayed Cloak: in your tank set"), "held at once: " .. joined(p.lines))
    t.eq(say(c, "set forget tank"), { "Set tank forgotten." })
    t.ok(starts(p.lines, "1 x Frayed Cloak: "), "offered again at once: " .. joined(p.lines))
    t.ok(not has(p.lines, "Frayed Cloak: in your tank set"), "no longer held: " .. joined(p.lines))
    c.setMerchantOpen(false)
end

-- Fails before: the set word is absent (GearSets.Run "forget").
tests["gear sets: a forgotten set holds nothing; forgetting one you don't have says so"] = function(t)
    local c = start({ worn = WORN })
    say(c, "set save tank")
    t.ok(not starts(visit(c), "1 x Frayed Cloak: "), "held while saved")
    t.eq(say(c, "set forget tank"), { "Set tank forgotten." })
    t.eq(savedSets(c), {}, "the saved list is empty")
    local lines = visit(c)
    t.ok(starts(lines, "1 x Frayed Cloak: "), "offered again: " .. joined(lines))
    t.eq(say(c, "set forget tank"), { "You have no set named tank." })
end

-- Fails before: the item key match (GearSets.Facts keyed by Items.Key) and
-- the sell list's context feed are absent; the bear ring is offered too.
tests["gear sets: only the exact item is held: the same ID with another suffix is offered"] = function(t)
    local c = start({ worn = WORN, bag = { { item = LINK.ringBear, count = 1 }, { item = LINK.ringEagle, count = 1 } } })
    say(c, "set save tank")
    local lines = visit(c)
    t.eq(count(lines, "1 x Dull Ring: "), 1, "one ring offered (the eagle one): " .. joined(lines))
    t.ok(has(lines, "Dull Ring: in your tank set"), "the bear ring is held: " .. joined(lines))
end

-- Fails before: the set word is absent; the second character fails only
-- if sets were saved account wide (GearSets.PATH is char scope).
tests["gear sets: another character's saved data holds none of your set"] = function(t)
    local c = start({ worn = WORN })
    say(c, "set save tank")
    t.ok(not starts(visit(c), "1 x Frayed Cloak: "), "held for the character that saved it")
    -- A second character: the same account data, its own character data.
    local other = start({ account = c.saved(ns.id.accountDB) })
    local lines = visit(other)
    t.ok(starts(lines, "1 x Frayed Cloak: "), "offered to the other character: " .. joined(lines))
    t.eq(say(other, "set"), { "You have no saved sets. Say " .. ns.id.slash .. " set save <name> to save what you wear as one." })
end

-- Fails before: UI/BankList.lua Context builds without `sets` (the context
-- the banker word, the auction list and the trader use too).
tests["gear sets: a set piece in the bank is not offered for sale by the banker word; the bank list holds it"] = function(t)
    local c, addon = start({ worn = WORN,
        char = { learned = { bankCounts = { at = 1000, counts = { [CLOAK] = 1 } } } } })
    local function toSell()
        local lines, part = say(c, "banker"), nil
        local out = {}
        for _, l in ipairs(lines) do
            if l:find("^In your bank") then part = l:find("sell", 1, true) and "sell" or "bank" end
            if part == "sell" then out[#out + 1] = l end
        end
        return out
    end
    t.ok(starts(toSell(), "1 x Frayed Cloak: junk"), "no set yet: the banker would sell it")
    say(c, "set save tank")
    local after = toSell()
    t.ok(not starts(after, "1 x Frayed Cloak"), "the set piece is not offered for sale: " .. joined(after))
    -- The nothing-to-sell line has no "In your bank" header, so look in the whole answer.
    local all = say(c, "banker")
    t.ok(has(all, addon.Banker.NOTHING_TO_SELL), "nothing in the bank to sell: " .. joined(all))
    -- The bank list's decision context holds it too.
    local d = addon.Disposition.Decide({ key = CLOAK, quality = 0, sellPrice = 4, classID = 4 },
        addon.BankList.Context(addon.store, nil))
    t.eq(d.rule, "inSet", "the bank context keeps it as a set piece")
    t.eq(d.action, "keep")
    -- At the bank it is not offered to put away.
    c.setBankOpen(true)
    local p = panelOf(c, "BankList")
    t.ok(p ~= nil and not starts(p.lines, "1 x Frayed Cloak"), "not offered to bank: " .. joined(p and p.lines))
    c.setBankOpen(false)
end

-- Fails before: Items/LootNote.lua FromItem builds its context without
-- `sets` (and the set word is absent), so looting the cloak notes it as junk.
tests["gear sets: looting a set piece gives no sell note; once forgotten it does"] = function(t)
    local c = start({ worn = WORN })
    c.setOwnLoot(function(line) if line == "loot cloak" then return LINK.cloak, 1 end end)
    say(c, "set save tank")
    local from = #c.printed
    c.fire("CHAT_MSG_LOOT", "loot cloak")
    t.eq(#c.printed, from, "no note for a set piece")
    say(c, "set forget tank")
    from = #c.printed
    c.fire("CHAT_MSG_LOOT", "loot cloak")
    t.eq(#c.printed, from + 1, "a note once the set is forgotten")
    t.ok(tostring(c.printed[#c.printed]):find("Junk: 1 x Frayed Cloak", 1, true) ~= nil,
        "the junk note: " .. tostring(c.printed[#c.printed]))
end

-- Fails before: nothing calls Items/TooltipDisposition.lua at run time
-- (the gear sets module's onItemTooltip listener is absent).
tests["gear sets: hovering a set piece adds the keep line; another suffix gets none"] = function(t)
    local c = start({ worn = WORN })
    local function lines(link)
        local out = {}
        for _, a in ipairs(c.showItemTooltip(link)) do out[#out + 1] = a.text end
        return out
    end
    t.ok(not has(lines(LINK.cloak), "Keep: in your tank set"), "no line before a set is saved")
    say(c, "set save tank")
    t.ok(has(lines(LINK.cloak), "Keep: in your tank set"), "the keep line: " .. joined(lines(LINK.cloak)))
    t.ok(has(lines(LINK.ringBear), "Keep: in your tank set"), "the worn ring too")
    t.ok(not has(lines(LINK.ringEagle), "Keep: in your tank set"), "not the other ring: " .. joined(lines(LINK.ringEagle)))
end

return tests
