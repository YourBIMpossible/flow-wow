local _, ns = ...
-- The macro icon search (row N72, lead section 248 item 4) on the whole
-- add-on loaded on a fake client: the box on the icon window of the macro
-- editor, its filters, the index built on first use in slices, and a click
-- that selects through the window itself. Per lead section 236: the macro
-- window loading late, a name missing on the client, a reload in the middle
-- of a search, the setting turned off and on, and a spellbook read that
-- raises, then recovers. Offline: the fake client, not the game. Not tested
-- in game. Made-up names and icons only.
local tests = {}

local FIRE_FILE = "Interface\\Icons\\Spell_Fire_FlameBolt"
local GEM_FILE = "Interface\\Icons\\INV_Misc_Gem_01"
local ICONS = { 101, 102, 201, 202, 300, FIRE_FILE, GEM_FILE }
local SPELLS = { { name = "Fireball", icon = 101 }, { name = "Frostbolt", icon = 102 },
                 { name = "Fire Ward", icon = 101 } }

-- opts: account, popup (what setMacroPopup is given), spells, loaded
-- (false: the macro window is not loaded at login), before(c).
local function boot(opts)
    opts = opts or {}
    local c = ns.make.fakeClient({ env = {} })
    c.setSaved(ns.id.accountDB, opts.account or {})
    c.setSaved(ns.id.charDB, {})
    c.setVersion("0.1.0")
    c.setMacroPopup(opts.popup or { icons = ICONS })
    c.setSpellbook(opts.spells or SPELLS)
    c.setBagItems({ { item = 9001, count = 3 }, { item = 9002, count = 20 } })
    c.setItemInfo({ [9001] = { name = "Fire Oil" }, [9002] = { name = "Linen Cloth" } })
    c.setItemTexture(9001, 201)
    c.setItemTexture(9002, 202)
    if opts.loaded ~= false then c.setLoaded("Blizzard_MacroUI", true) end
    if opts.before then opts.before(c) end
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

local function popup(c) return c.macroPopups and c.macroPopups[#c.macroPopups] or nil end

local function ready(t, c, addon)
    t.ok(type(addon.MacroIcons) == "table", "the macro icon search is in the add-on")
    t.ok(type(c.setMacroPopup) == "function", "the fake has the macro window")
    return type(addon.MacroIcons) == "table" and type(c.setMacroPopup) == "function"
end

-- A few frames, enough for any index and search of the small data here.
local function settle(c) c.advance(1, 30) end

-- The problems of the macro icon search only: other modules of the add-on
-- note their own on this bare fake (a cast read, a tooltip hook).
local function ours(addon)
    local n = 0
    for _, e in ipairs(addon.problems:list()) do
        if e.kind == "macro icons" or e.owner == "macroIcons" then n = n + 1 end
    end
    return n
end

local function said(c, text)
    local n = 0
    for _, line in ipairs(c.printed) do
        if tostring(line):find(text, 1, true) then n = n + 1 end
    end
    return n
end

tests["macro icons: the box comes when the macro window loads, before or after login"] = function(t)
    local c, addon = boot({ loaded = false })
    if not ready(t, c, addon) then return end
    local p = popup(c)
    t.eq(p and p.box, nil, "no box while the macro window is not loaded")
    c.setLoaded("Blizzard_MacroUI", true)
    c.fire("ADDON_LOADED", "Blizzard_MacroUI")
    settle(c)
    p = popup(c)
    t.ok(p ~= nil and type(p.box) == "table", "the box once it loaded")
    local c2, addon2 = boot()
    if not ready(t, c2, addon2) then return end
    t.ok(type(popup(c2).box) == "table", "loaded before login: the box at once")
    t.eq(ours(addon2), 0)
end

tests["macro icons: typing filters the grid by spell, item and file name; a click selects; clearing restores"] = function(t)
    local c, addon = boot()
    if not ready(t, c, addon) then return end
    local p = popup(c)
    p.open()
    t.eq(p.visible(), ICONS, "the full list before typing")
    p.type("fire")
    settle(c)
    t.eq(p.visible(), { 101, 201, FIRE_FILE }, "spells, then items, then file names, each icon once")
    t.eq(p.box.hint, "3 matches")
    p.click(2)
    t.eq(p.selected, 201, "the click selects through the window")
    p.type("")
    settle(c)
    t.eq(p.visible(), ICONS, "cleared: every icon again")
    t.eq(p.box.hint == nil or p.box.hint == "", true, "no hint on an empty box")
    t.eq(ours(addon), 0)
end

tests["macro icons: the index is built on first use of the box, not before, and again after the window reopens"] = function(t)
    local c, addon = boot()
    if not ready(t, c, addon) then return end
    local p = popup(c)
    p.open()
    settle(c)
    t.eq(c.spellbookReads, 0, "opening the window reads nothing")
    p.type("fire")
    settle(c)
    p.type("frost")
    settle(c)
    t.eq(c.spellbookReads, 1, "one read for both searches")
    t.eq(p.visible(), { 102 })
    p.close()
    settle(c)
    p.open()
    p.type("fire")
    settle(c)
    t.eq(c.spellbookReads, 2, "built again after the window reopened: new spells may be known")
end

tests["macro icons: the All, Spells and Items filters"] = function(t)
    local c, addon = boot()
    if not ready(t, c, addon) then return end
    local p = popup(c)
    p.open()
    p.type("fire")
    p.filter("spells")
    settle(c)
    t.eq(p.visible(), { 101 })
    p.filter("items")
    settle(c)
    t.eq(p.visible(), { 201 })
    p.filter("all")
    p.type("gem")
    settle(c)
    t.eq(p.visible(), { GEM_FILE }, "file names under All")
    p.filter("spells")
    settle(c)
    t.eq(p.visible(), {})
    t.eq(p.box.hint, "No icon matches.")
end

tests["macro icons: a large spellbook is indexed over several frames and results come at most a capped number a frame"] = function(t)
    local spells = {}
    for i = 1, 600 do spells[i] = { name = "Fire " .. i, icon = 1000 + i } end
    local c, addon = boot({ spells = spells })
    if not ready(t, c, addon) then return end
    local MI = addon.MacroIcons
    local p = popup(c)
    p.open()
    p.type("fire")
    t.eq(p.box.hint, "Searching...", "nothing done while typing")
    local last, frames, steps = #p.visible(), 0, 0
    while frames < 200 and p.box.hint == "Searching..." do
        c.advance(0.02, 1)
        frames = frames + 1
        local now = #p.visible()
        t.ok(now - last <= MI.CAP, "at most CAP a frame, got " .. (now - last))
        if now ~= last then steps = steps + 1 end
        last = now
    end
    t.ok(frames >= 3, "more than one frame: " .. frames)
    t.ok(steps >= 2, "shown as it goes: " .. steps)
    t.eq(#p.visible(), 602, "600 spells, the one item and the one file name")
    t.eq(p.box.hint, "602 matches")
end

tests["macro icons: a name missing on the client, no box, and diag says why"] = function(t)
    local c, addon = boot({ popup = { missing = { "IconDataProviderMixin" } } })
    if not ready(t, c, addon) then return end
    t.eq(popup(c), nil, "no window handle")
    c.slashes[ns.id.slash]("diag")
    t.eq(said(c, ns.id.title .. ": macro icon search: not added: missing IconDataProviderMixin."), 1)
    t.eq(ours(addon), 0, "a missing name is not a problem of the add-on")
end

tests["macro icons: diag says how far the search got"] = function(t)
    local c, addon = boot({ loaded = false })
    if not ready(t, c, addon) then return end
    local line = ns.id.title .. ": macro icon search: "
    c.slashes[ns.id.slash]("diag")
    t.eq(said(c, line .. "waiting for the macro window to load."), 1)
    c.setLoaded("Blizzard_MacroUI", true)
    c.fire("ADDON_LOADED", "Blizzard_MacroUI")
    settle(c)
    c.slashes[ns.id.slash]("diag")
    t.eq(said(c, line .. "added; index not built yet."), 1)
    local p = popup(c)
    p.open()
    p.type("fire")
    settle(c)
    c.slashes[ns.id.slash]("diag")
    t.eq(said(c, line .. "added; index of 5 names and 2 file names."), 1)
    addon.settings:set(addon.MacroIcons.SETTING, false)
    c.slashes[ns.id.slash]("diag")
    t.eq(said(c, line .. "off."), 1)
end

tests["macro icons reload: a search in the middle saves nothing, and the box is empty again"] = function(t)
    local c, addon = boot()
    if not ready(t, c, addon) then return end
    local p = popup(c)
    p.open()
    p.type("fire")
    c.advance(0.02, 1)
    local function holds(v)
        if type(v) == "string" then return v:lower():find("fire", 1, true) ~= nil end
        if type(v) ~= "table" then return false end
        for key, value in pairs(v) do
            if holds(key) or holds(value) then return true end
        end
        return false
    end
    t.eq(holds(c.saved(ns.id.accountDB)) or holds(c.saved(ns.id.charDB)), false, "the search is not kept")
    local c2, addon2 = boot({ account = c.saved(ns.id.accountDB) })
    if not ready(t, c2, addon2) then return end
    local p2 = popup(c2)
    p2.open()
    settle(c2)
    t.eq(p2.box.text, "")
    t.eq(p2.visible(), ICONS)
end

tests["macro icons setting: off hides the box and restores the list; on shows it again; off at login adds none"] = function(t)
    local c, addon = boot()
    if not ready(t, c, addon) then return end
    local MI = addon.MacroIcons
    t.eq(addon.settings:get(MI.SETTING), true, "on by default")
    local p = popup(c)
    p.open()
    p.type("fire")
    settle(c)
    addon.settings:set(MI.SETTING, false)
    settle(c)
    t.eq(p.box.shown, false)
    t.eq(p.visible(), ICONS, "the full list back")
    addon.settings:set(MI.SETTING, true)
    settle(c)
    t.eq(p.box.shown, true)
    t.eq(p.box.text, "")
    addon.settings:set(MI.SETTING, false)
    local c2, addon2 = boot({ account = c.saved(ns.id.accountDB) })
    if not ready(t, c2, addon2) then return end
    t.eq(addon2.settings:get(MI.SETTING), false, "kept off")
    t.eq(popup(c2).box, nil, "no box made")
end

tests["macro icons: a spellbook read that raises keeps the item matches and is one problem; then it recovers"] = function(t)
    local real
    local c, addon = boot({ before = function(c0)
        real = c0.spellbookIcons
        c0.spellbookIcons = function() error("spellbook boom") end
    end })
    if not ready(t, c, addon) then return end
    local start = ours(addon)
    local p = popup(c)
    p.open()
    p.type("fire")
    settle(c)
    t.eq(p.visible(), { 201, FIRE_FILE }, "items and file names still found")
    t.eq(ours(addon), start + 1, "one problem")
    c.spellbookIcons = real
    p.close()
    settle(c)
    p.open()
    p.type("fire")
    settle(c)
    t.eq(p.visible(), { 101, 201, FIRE_FILE }, "spells again once the read works")
end

return tests
