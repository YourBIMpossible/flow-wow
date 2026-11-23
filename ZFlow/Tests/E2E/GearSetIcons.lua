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

-- A saved set as Gear/Sets.lua keeps it.
local function savedSet(name, items) return { name = name, items = items } end

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
    t.eq(icon.tip, { "tank", "You wear all of it.", "Dull Ring", "Frayed Cloak", "Bent Sword" })
end

-- Lead section 236: what is worn is read late (not known at login).
tests["set icons: what you wear read late: no edge until it is known"] = function(t)
    local char = { state = { gearSets = { savedSet("tank", { "15234:588", CLOAK, SWORD }) } } }
    local c = start({ on = true, char = char })
    local row = rowOf(c)
    if not row then t.ok(false, "no set icon row") return end
    t.eq(iconOf(row, "tank").edge, false, "not known: no edge")
    t.eq(iconOf(row, "tank").tip, { "tank", "Dull Ring", "Frayed Cloak", "Bent Sword" }, "no wear line while not known")
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

return tests
