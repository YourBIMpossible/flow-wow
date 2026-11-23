local _, ns = ...
-- Package P-SETS, branch 2 (S19, lead DISPATCH sections 227 and 230). The
-- set icons end to end, on the whole add-on loaded on a fake client: with
-- gear.setIcons on, a row with an icon for each saved set; the set you wear
-- has the edge; hovering lists its pieces; the row's place is kept.
-- Offline: the reads are the fake client's, not the game's. Not tested in game.
-- Made-up items only.
local tests = {}

local CLOAK, SWORD, RING, HELM = 1000, 2000, 15234, 3000
local LINK = {
    cloak = "item:1000:0:0:0:0:0:0:0",
    sword = "item:2000:0:0:0:0:0:0:0",
    ringBear = "item:15234:0:0:0:0:0:588:0",
    helm = "item:3000:0:0:0:0:0:0:0",
}
local INFO = {
    [CLOAK] = { name = "Frayed Cloak", quality = 0, sellPrice = 4, classID = 4 },
    [SWORD] = { name = "Bent Sword", quality = 0, sellPrice = 9, classID = 2 },
    [RING] = { name = "Dull Ring", quality = 0, sellPrice = 6, classID = 4 },
    [HELM] = { name = "Dented Helm", quality = 0, sellPrice = 7, classID = 4 },
}
-- Back, main hand, a finger.
local WORN = { [15] = LINK.cloak, [16] = LINK.sword, [11] = LINK.ringBear }

-- opts: on (gear.setIcons), account, char (saved tables), worn (slot ->
-- link; nil: never set, so not known), bag (stacks).
local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    local account = opts.account or {}
    if opts.on ~= nil then
        account.settings = account.settings or {}
        account.settings.gear = account.settings.gear or {}
        account.settings.gear.setIcons = opts.on
    end
    c.setSaved(ns.id.accountDB, account)
    c.setSaved(ns.id.charDB, opts.char or {})
    c.setItemInfo(INFO)
    c.setBagItems(opts.bag or {})
    if opts.worn then
        for slot, link in pairs(opts.worn) do c.setWorn(slot, link) end
    end
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

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

local function rowOf(c)
    for _, r in ipairs(c.iconRows or {}) do
        if type(r.spec) == "table" and r.spec.name == ns.id.framePrefix .. "SetIcons" then return r end
    end
    return nil
end

local function keys(row)
    local out = {}
    for i, icon in ipairs(row and row.icons or {}) do out[i] = icon.key end
    return out
end

local function iconOf(row, key)
    for _, icon in ipairs(row and row.icons or {}) do
        if icon.key == key then return icon end
    end
    return nil
end

-- A saved set as Gear/Sets.lua keeps it (slots: the inventory slot each
-- piece was worn in, as saved; nil for a set saved before slots were kept).
local function savedSet(name, items, slots) return { name = name, items = items, slots = slots } end

-- Fails before: Gear/SetIcons.lua and c.iconRow are absent: no row is made.
tests["set icons: an icon for each saved set with the setting on"] = function(t)
    local c = start({ on = true, worn = WORN })
    say(c, "set save tank")
    say(c, "set save heal")
    local row = rowOf(c)
    if not row then t.ok(false, "no set icon row") return end
    t.eq(keys(row), { "tank", "heal" }, "one icon per set, in the order saved")
    t.eq(row.shown(), true)
    say(c, "set forget heal")
    t.eq(keys(row), { "tank" }, "a forgotten set's icon goes at once")
end

-- Fails before: the setting row gear.setIcons is absent (or on by default).
tests["set icons: none with the setting off, which is the default"] = function(t)
    for _, opts in ipairs({ { on = false, worn = WORN }, { worn = WORN } }) do
        local c = start(opts)
        say(c, "set save tank")
        local row = rowOf(c)
        t.ok(row == nil or (row.shown() == false and #row.icons == 0), "no icons shown: " .. tostring(opts.on))
    end
    local c = start({ on = true })
    t.eq(rowOf(c), nil, "on, but no set saved: no row made")
end

-- Fails before: GearSetIcons.Icons (the edge: every piece worn) is absent.
tests["set icons: the set you wear has the edge, and loses it when a piece comes off"] = function(t)
    local c = start({ on = true, worn = WORN })
    say(c, "set save tank")
    local row = rowOf(c)
    if not row then t.ok(false, "no set icon row") return end
    t.eq(iconOf(row, "tank").edge, true, "all three worn: edged")
    c.setWorn(15, false)
    c.fire("PLAYER_EQUIPMENT_CHANGED", 15, true)
    t.eq(iconOf(row, "tank").edge, false, "the cloak off: no edge")
    t.eq(iconOf(row, "tank").tip[2], "You wear 2 of its 3 pieces.")
end

-- Fails before: GearSetIcons.Icons builds no tip.
tests["set icons: hovering a set lists its pieces"] = function(t)
    local c = start({ on = true, worn = WORN })
    say(c, "set save tank")
    local icon = iconOf(rowOf(c), "tank")
    if not icon then t.ok(false, "no tank icon") return end
    t.eq(icon.tip, { "tank", "You wear all of it.", "Dull Ring", "Frayed Cloak", "Bent Sword", ns.GearSetIcons.CLICK })
end

-- Lead section 236: what is worn is read late (not known at login).
tests["set icons: what you wear read late: no edge until it is known"] = function(t)
    local char = { state = { gearSets = { savedSet("tank", { "15234:588", CLOAK, SWORD }) } } }
    local c = start({ on = true, char = char })
    local row = rowOf(c)
    if not row then t.ok(false, "no set icon row") return end
    t.eq(iconOf(row, "tank").edge, false, "not known: no edge")
    t.eq(iconOf(row, "tank").tip, { "tank", "Dull Ring", "Frayed Cloak", "Bent Sword", ns.GearSetIcons.CLICK },
        "no wear line while not known")
    for slot, link in pairs(WORN) do c.setWorn(slot, link) end
    c.fire("PLAYER_EQUIPMENT_CHANGED", 16, false)
    t.eq(iconOf(row, "tank").edge, true, "known now: edged")
end

tests["set icons: at most twelve"] = function(t)
    local list = {}
    for i = 1, 14 do list[i] = savedSet("set" .. i, { CLOAK }) end
    local c = start({ on = true, char = { state = { gearSets = list } } })
    t.eq(#keys(rowOf(c)), 12)
end

-- Lead section 236: a reload keeps the setting and where the row stands.
tests["set icons: a reload keeps the setting and the row's place"] = function(t)
    local c = start({ on = true, worn = WORN })
    say(c, "set save tank")
    local row = rowOf(c)
    if not row then t.ok(false, "no set icon row") return end
    t.eq(row.point, ns.GearSetIcons.DEFAULT_POINT, "the default place at first")
    row.drag({ "TOPLEFT", "TOPLEFT", 120, -240 })
    local again = start({ account = c.saved(ns.id.accountDB), char = c.saved(ns.id.charDB), worn = WORN })
    local row2 = rowOf(again)
    if not row2 then t.ok(false, "no row after the reload") return end
    t.eq(row2.shown(), true, "still on")
    t.eq(row2.point, { "TOPLEFT", "TOPLEFT", 120, -240 }, "where it was moved to")
    t.eq(keys(row2), { "tank" })
    -- Nothing saved holds a character name: the place is anchors and numbers.
    local saved = c.saved(ns.id.accountDB).layout.setIcons
    t.eq(saved, { point = { "TOPLEFT", "TOPLEFT", 120, -240 } })
end

-- Equip on click (ACTING) ---------------------------------------------------

local function items(c)
    local out = {}
    for i, e in ipairs(c.equips) do out[i] = e.item end
    return out
end

-- The slot asked with each call, in call order ("none" for no slot).
local function slotsAsked(c)
    local out = {}
    for i, e in ipairs(c.equips) do
        if e.slot == nil then out[i] = "none" else out[i] = e.slot end
    end
    return out
end

-- Saved wearing all three; then the cloak and the sword come off. In the
-- bags: the cloak and a helm (not in the set); the sword is gone.
local function offAndClick(opts)
    opts = opts or {}
    local c, addon = start({ on = true, worn = WORN,
        bag = opts.bag or { { item = LINK.cloak, count = 1 }, { item = LINK.helm, count = 1 } } })
    say(c, "set save tank")
    c.setWorn(15, false)
    c.setWorn(16, false)
    c.fire("PLAYER_EQUIPMENT_CHANGED", 15, true)
    return c, addon
end

local function click(c, key)
    local from = #c.printed
    local pressed = rowOf(c).press(key)
    local out, p = {}, ns.id.title .. ": "
    for i = from + 1, #c.printed do
        local line = tostring(c.printed[i])
        if line:sub(1, #p) == p then line = line:sub(#p + 1) end
        out[#out + 1] = line
    end
    return pressed, out
end

-- Fails before: the row's act is nil (look only) and c.equipItem is absent.
tests["set icons: a click out of combat puts on the set's pieces from the bags, one call each"] = function(t)
    local c = offAndClick()
    local pressed, said = click(c, "tank")
    t.eq(pressed, true, "the icon took the click")
    t.eq(c.equipCalls, 1, "one call: the one piece in the bags and not worn")
    t.eq(items(c), { LINK.cloak }, "the cloak; never the helm (not in the set), the ring (worn) or the sword (not in the bags)")
    t.eq(said, { "Asked to equip 1 piece of tank; 1 not in your bags." })
end

-- ST-1: each piece goes to the slot it was saved in, so the second of a
-- pair never replaces the first (two rings, two trinkets, two weapons).
-- Fails before: equipSet asks equipItem(item) with no slot.
tests["set icons: two of one piece take two from the bags, each to its saved slot"] = function(t)
    for _, pair in ipairs({ { 11, 12 }, { 13, 14 }, { 16, 17 } }) do
        local c = start({ on = true,
            char = { state = { gearSets = { savedSet("pair", { "15234:588", "15234:588" }, pair) } } },
            worn = { [pair[1]] = false }, bag = { { item = LINK.ringBear, count = 3 } } })
        local _, said = click(c, "pair")
        t.eq(items(c), { LINK.ringBear, LINK.ringBear }, "two, never more than the set holds")
        t.eq(slotsAsked(c), pair, "each call asks its saved slot")
        t.eq(said, { "Asked to equip 2 pieces of pair; 0 not in your bags." })
    end
end

-- S3-1: a pair saved in two slots, the first slot's piece off (the second
-- still wears its own), one more in the bags: the bag piece goes to the
-- first slot, the empty one. Matched by saved slot, not by item key.
-- Fails before: the worn piece in the second slot counts for the first, so
-- the bag piece is sent to the second slot ({ 12 }, { 14 }, { 17 }).
tests["set icons: one of a pair off: the bag piece goes to the empty saved slot"] = function(t)
    for _, pair in ipairs({ { 11, 12 }, { 13, 14 }, { 16, 17 } }) do
        local c = start({ on = true,
            char = { state = { gearSets = { savedSet("pair", { "15234:588", "15234:588" }, pair) } } },
            worn = { [pair[1]] = false, [pair[2]] = LINK.ringBear }, bag = { { item = LINK.ringBear, count = 1 } } })
        local _, said = click(c, "pair")
        t.eq(slotsAsked(c), { pair[1] }, "the empty slot is asked, once")
        t.eq(said, { "Asked to equip 1 piece of pair; 0 not in your bags." })
    end
end

-- S3-1: both of a pair worn where saved: nothing is asked.
tests["set icons: a pair worn in its saved slots asks nothing"] = function(t)
    local c = start({ on = true,
        char = { state = { gearSets = { savedSet("pair", { "15234:588", "15234:588" }, { 11, 12 }) } } },
        worn = { [11] = LINK.ringBear, [12] = LINK.ringBear }, bag = { { item = LINK.ringBear, count = 1 } } })
    local _, said = click(c, "pair")
    t.eq(c.equipCalls, 0)
    t.eq(said, { ns.GearSetIcons.ALREADY:format("pair") })
end

-- S3-2: one bad saved slot drops only that piece's slot; the others keep
-- theirs, and the tip says how many have none.
-- Fails before: one bad slot drops every slot ({ "none", "none" }) and the
-- tip has no line for it.
tests["set icons: a bad saved slot drops only that piece's slot, and is said"] = function(t)
    local c = start({ on = true,
        char = { state = { gearSets = { savedSet("mixed", { "15234:588", CLOAK }, { 11, 99 }) } } },
        worn = { [11] = false }, bag = { { item = LINK.ringBear, count = 1 }, { item = LINK.cloak, count = 1 } } })
    local icon = iconOf(rowOf(c), "mixed")
    if not icon then t.ok(false, "no mixed icon") return end
    t.eq(icon.tip[#icon.tip - 1], "Pieces with no saved slot: 1 (the game picks where they go).",
        "the tip counts the pieces without a slot")
    click(c, "mixed")
    t.eq(slotsAsked(c), { 11, "none" }, "the ring keeps its slot; the cloak gets the game's choice")
end

-- A set saved before slots were kept: the game picks the slot, as before.
tests["set icons: a set saved without slots asks no slot"] = function(t)
    local c = start({ on = true, char = { state = { gearSets = { savedSet("rings", { "15234:588" }) } } },
        worn = { [11] = false }, bag = { { item = LINK.ringBear, count = 1 } } })
    click(c, "rings")
    t.eq(slotsAsked(c), { "none" })
end

-- S4-3 (lead section 279): saved with a slots table that holds no slot at
-- all: every piece counts as one without a slot, and the game picks.
tests["set icons: a slots table with no slot in it: every piece is counted and asks no slot"] = function(t)
    local c, addon = start({ on = true,
        char = { state = { gearSets = { savedSet("bare", { "15234:588", CLOAK }, {}) } } },
        worn = { [11] = false }, bag = { { item = LINK.ringBear, count = 1 }, { item = LINK.cloak, count = 1 } } })
    local sets = ns.GearSets.Saved(addon.store)
    t.eq(#sets, 1, "the set reads")
    t.eq(sets[1] and sets[1].noSlot, 2, "both pieces have no slot that reads")
    local icon = iconOf(rowOf(c), "bare")
    if not icon then t.ok(false, "no bare icon") return end
    t.eq(icon.tip[#icon.tip - 1], "Pieces with no saved slot: 2 (the game picks where they go).",
        "the tip counts both")
    click(c, "bare")
    t.eq(slotsAsked(c), { "none", "none" })
end

-- S4-3: a set saved before slots were kept has no count of missing slots
-- (nothing was lost), so its tip has no line about them.
tests["set icons: a set saved without slots has no count of pieces without one"] = function(t)
    local c, addon = start({ on = true, char = { state = { gearSets = { savedSet("rings", { "15234:588" }) } } },
        worn = { [11] = false }, bag = { { item = LINK.ringBear, count = 1 } } })
    local sets = ns.GearSets.Saved(addon.store)
    t.eq(#sets, 1, "the set reads")
    t.eq(sets[1] and sets[1].noSlot, nil, "no count")
    t.eq(sets[1] and sets[1].slots, nil, "and no slots")
    local icon = iconOf(rowOf(c), "rings")
    if not icon then t.ok(false, "no rings icon") return end
    for _, tipLine in ipairs(icon.tip) do
        t.ok(not tostring(tipLine):find("no saved slot", 1, true), "no line about slots: " .. tostring(tipLine))
    end
end

-- ST-1 end to end: two rings worn, saved, taken off; a click puts each back
-- in the finger it was saved in. Fails before: no slot is saved or asked.
tests["set icons: set save keeps each piece's slot; the click asks it"] = function(t)
    local c = start({ on = true, worn = { [11] = LINK.ringBear, [12] = LINK.ringBear },
        bag = { { item = LINK.ringBear, count = 2 } } })
    say(c, "set save rings")
    c.setWorn(11, false)
    c.setWorn(12, false)
    c.fire("PLAYER_EQUIPMENT_CHANGED", 11, true)
    click(c, "rings")
    t.eq(slotsAsked(c), { 11, 12 })
end

-- Fails before: the click handler (GearSetIcons equipSet) is absent.
tests["set icons: a click in combat, or with combat not known, equips nothing and says why"] = function(t)
    local c = offAndClick()
    c.setCombat(true)
    local _, said = click(c, "tank")
    t.eq(c.equipCalls, 0, "no call in combat")
    t.eq(said, { ns.GearSetIcons.IN_COMBAT })
    c.setCombatUnknown(true)
    _, said = click(c, "tank")
    t.eq(c.equipCalls, 0, "no call while combat is not known")
    t.eq(said, { ns.GearSetIcons.COMBAT_UNKNOWN })
    c.setCombatUnknown(false)
    click(c, "tank")
    t.eq(c.equipCalls, 1, "out of combat again: the click equips")
end

tests["set icons: what you wear not read: nothing is equipped"] = function(t)
    local c = offAndClick()
    c.setWornUnread(true)
    local _, said = click(c, "tank")
    t.eq(said, { ns.GearSetIcons.CANT_READ_WORN })
    t.eq(c.equipCalls, 0)
    -- The plan alone: the bags not read asks nothing either.
    local plan, why = ns.GearSetIcons.Plan({ name = "tank", items = { CLOAK } }, {}, nil)
    t.eq(plan, nil)
    t.eq(why, ns.GearSetIcons.CANT_READ_BAGS)
end

-- Lead section 236: the call raises once, then works; no retry by itself.
tests["set icons: equip raising once says so; the next click puts it on"] = function(t)
    local c = offAndClick()
    c.setEquipFails(1)
    local _, said = click(c, "tank")
    t.eq(c.equipCalls, 1, "one call, no retry")
    t.eq(#c.equips, 0)
    t.eq(said, { "Asked to equip 0 pieces of tank; 1 not in your bags. 1 piece could not be put on; click again to try." })
    c.advance(30, 60)
    c.fire("PLAYER_EQUIPMENT_CHANGED", 15, false)
    t.eq(c.equipCalls, 1, "nothing retried by a timer or an event")
    _, said = click(c, "tank")
    t.eq(items(c), { LINK.cloak })
    t.eq(said, { "Asked to equip 1 piece of tank; 1 not in your bags." })
end

-- SR-6 style recorder: c.equipCalls counts every call, refused ones too.
-- Boot, events, ticks, a reload, the set word, the setting: zero calls.
tests["set icons: nothing is equipped without the click"] = function(t)
    local c = offAndClick()
    for _, ev in ipairs({ "PLAYER_EQUIPMENT_CHANGED", "PLAYER_ENTERING_WORLD", "BAG_UPDATE", "BAG_UPDATE_DELAYED",
        "PLAYER_REGEN_ENABLED", "UNIT_INVENTORY_CHANGED", "EQUIPMENT_SWAP_FINISHED" }) do
        c.fire(ev)
    end
    c.setCombat(true)
    c.setCombat(false)
    c.advance(120, 240)
    say(c, "set")
    say(c, "set save heal")
    t.eq(c.equipCalls, 0, "no call before a reload")
    local again = start({ account = c.saved(ns.id.accountDB), char = c.saved(ns.id.charDB),
        bag = { { item = LINK.cloak, count = 1 } } })
    again.fire("PLAYER_EQUIPMENT_CHANGED")
    again.advance(60, 120)
    t.eq(again.equipCalls, 0, "no call after a reload")
    t.ok(rowOf(again) ~= nil and #rowOf(again).icons == 2, "the icons are there to click")
end

tests["set icons: a click on the row with the setting off is not possible"] = function(t)
    local c, addon = offAndClick()
    local row = rowOf(c)
    addon.settings:set(ns.GearSetIcons.SETTING, false)
    t.eq(row.shown(), false, "hidden once off")
    t.eq(row.press("tank"), false, "no icon to click once off")
    t.eq(c.equipCalls, 0)
end

return tests
