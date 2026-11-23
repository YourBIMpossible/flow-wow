local _, ns = ...
-- N55 (lead DISPATCH sections 237 item 5 and 238 item 4; RESEARCH-N55): the
-- boss loot panel, on the whole add-on loaded on a fake client. A paladin
-- fights a boss; the panel lists the drops this account has itself seen
-- from that boss (learned from the roll, the loot line and the loot window
-- that follow a kill), the pieces that are an upgrade for the chosen role
-- on top at full strength, the rest of what the class can use below and
-- faded, another armour type only when some role's weights score it above
-- what is worn. Look only: nothing is rolled, picked, whispered or
-- targeted. No loot table is copied: with nothing seen it says so.
-- Made-up bosses, items and players. Not tested in game.
local tests = {}

local NAME = "bossLoot"
local SETTING = "loot.bossPanel"
local FULL, FADED, END = "|cffffffff", "|cff808080", "|r"

local ENC, BOSS = 501, "Gravelmaw the Unfed"            -- made up
local NPC = 7001
local GUID = "Creature-0-0-0-0-7001-00000A"
local GUID2 = "Creature-0-0-0-0-7001-00000B"            -- the same boss, another spawn
local STRAY = "Creature-0-0-0-0-7002-00000C"            -- an elite nobody learned
local LOOTER = "Bramblewick"                            -- made up, never to be saved

local HELM, GRIPS, ROBE, CUFFS, DAGGER, BOOTS, TOOTH = 4001, 4002, 4003, 4004, 4006, 4007, 4008
local function roll(id) return "item:" .. id .. ":0:0:0:0:0:0:0" end   -- as a roll or a loot line names it
local function plain(id) return "item:" .. id end                      -- as the panel asks about it

local STA, DEF = "ITEM_MOD_STAMINA_SHORT", "ITEM_MOD_DEFENSE_SKILL_RATING_SHORT"
local INT, HEAL, STR = "ITEM_MOD_INTELLECT_SHORT", "ITEM_MOD_SPELL_HEALING_DONE_SHORT", "ITEM_MOD_STRENGTH_SHORT"

local NAMES = {
    [HELM] = "Thornhelm", [GRIPS] = "Sunward Grips", [ROBE] = "Moth Robe", [CUFFS] = "Dawnweave Cuffs",
    [DAGGER] = "Needle of Spite", [BOOTS] = "Dull Sabatons", [TOOTH] = "Odd Tooth",
}
-- What drops: plate for a tank, plate for a healer, a weak cloth robe, cloth
-- cuffs a healer would want, a dagger a paladin cannot use, plain plate
-- boots, and a tooth that is not gear.
local DROPS = {
    [HELM] = { kind = "INVTYPE_HEAD", classID = 4, subclassID = 4, minLevel = 50, unmet = {},
               stats = { [STA] = 20, [DEF] = 10 } },
    [GRIPS] = { kind = "INVTYPE_HAND", classID = 4, subclassID = 4, minLevel = 50, unmet = {},
                stats = { [INT] = 15, [HEAL] = 20 } },
    [ROBE] = { kind = "INVTYPE_ROBE", classID = 4, subclassID = 1, minLevel = 50, unmet = {},
               stats = { [INT] = 2 } },
    [CUFFS] = { kind = "INVTYPE_WRIST", classID = 4, subclassID = 1, minLevel = 50, unmet = {},
                stats = { [INT] = 30, [HEAL] = 40 } },
    [DAGGER] = { kind = "INVTYPE_WEAPON", classID = 2, subclassID = 15, minLevel = 50, unmet = { "Dagger" },
                 stats = { [STA] = 50 } },
    [BOOTS] = { kind = "INVTYPE_FEET", classID = 4, subclassID = 4, minLevel = 50, unmet = {},
                stats = { [STA] = 1 } },
}
-- What is worn, by inventory slot: head, hands, chest, wrist, feet.
local WORN = {
    [1] = { id = 3001, kind = "INVTYPE_HEAD", stats = { [STA] = 5, [INT] = 8 } },
    [10] = { id = 3002, kind = "INVTYPE_HAND", stats = { [STA] = 12, [STR] = 8 } },
    [5] = { id = 3003, kind = "INVTYPE_CHEST", stats = { [STA] = 30, [INT] = 10 } },
    [9] = { id = 3004, kind = "INVTYPE_WRIST", stats = { [STA] = 10 } },
    [8] = { id = 3007, kind = "INVTYPE_FEET", stats = { [STA] = 9 } },
}

-- opts: account, char (saved tables); role ("tank" unless given; false: none
-- chosen); items = false: no item is known to the client yet.
local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, opts.account or {})
    c.setSaved(ns.id.charDB, opts.char or {})
    c.setClass("PALADIN"); c.setFaction("Alliance"); c.setLevel(60); c.setDead(false)
    local info = {}
    c.setItemInfo(info)
    for slot, w in pairs(WORN) do
        c.setItem(plain(w.id), { kind = w.kind, stats = w.stats })
        c.setWorn(slot, plain(w.id))
    end
    if opts.items ~= false then
        for id, name in pairs(NAMES) do info[id] = { name = name } end
        for id, item in pairs(DROPS) do c.setItem(plain(id), item) end
    end
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    if opts.role ~= false and not opts.char then addon.settings:set("spec.role", opts.role or "tank") end
    c.setTarget({ exists = false }); c.setCombat(false)
    c.advance(2, 4)
    return c, addon, info
end

local function panelOf(c)
    for _, p in ipairs(c.panels) do
        if type(p.spec) == "table" and p.spec.name == ns.id.framePrefix .. "BossLoot" then return p end
    end
    return nil
end

local function shownLines(c)
    local p = panelOf(c)
    if not p or not p.shown then return nil end
    local out = {}
    for i, l in ipairs(p.lines) do out[i] = l end
    return out
end

local function joined(lines) return table.concat(lines or { "(hidden)" }, " / ") end

local function errorsOf(addon)
    local use = addon.use(NAME)
    return type(use) == "table" and use.Errors() or nil
end

local function pull(c)
    c.setBossUnit({ exists = true, guid = GUID, name = BOSS })
    c.fire("ENCOUNTER_START", ENC, BOSS, 1, 5)
    c.setCombat(true)
end

local function down(c)
    c.fire("ENCOUNTER_END", ENC, BOSS, 1, 5, 1)
    c.setBossUnit({ exists = false })
    c.setCombat(false)
end

-- One kill of the boss; `ids` are rolled on afterwards.
local function killWith(c, ids)
    pull(c)
    down(c)
    for i, id in ipairs(ids) do c.offerRoll(i, roll(id)) end
end

local function holds(v, text, depth)
    depth = depth or 0
    if depth > 20 then return false end
    if type(v) == "string" then return v:find(text, 1, true) ~= nil end
    if type(v) ~= "table" then return false end
    for key, value in pairs(v) do
        if holds(key, text, depth + 1) or holds(value, text, depth + 1) then return true end
    end
    return false
end

local EVERYTHING = { HELM, GRIPS, ROBE, CUFFS, DAGGER, BOOTS, TOOTH }
local TANK_LIST = {
    BOSS .. ": loot you have seen drop",
    FULL .. "Thornhelm: upgrade +25 for Protection, seen 1 of 1 kill" .. END,
    FADED .. "Dawnweave Cuffs: +63 for Holy, seen 1 of 1 kill" .. END,
    FADED .. "Sunward Grips: +29 for Holy, seen 1 of 1 kill" .. END,
    FADED .. "Dull Sabatons: no upgrade, seen 1 of 1 kill" .. END,
}

-- The module and its row ----------------------------------------------------

-- Fails before: UI/BossLoot.lua is absent (no module "bossLoot", no row
-- "loot.bossPanel", no panel made by BossLoot.Declare's start).
tests["boss loot: the module starts, its row is on by default, the panel waits hidden at a side"] = function(t)
    local c, addon = start()
    t.eq((addon:ModuleState(NAME)), "started")
    local row = addon.settings:row(SETTING)
    t.ok(type(row) == "table", "the row " .. SETTING)
    t.eq(row and { row.type, row.default, row.scope, row.group }, { "bool", true, "account", "Gear" })
    t.eq(addon.settings:get(SETTING), true, "on by default")
    local p = panelOf(c)
    t.ok(p ~= nil, "a panel named for the boss loot")
    t.eq(p and p.shown, false, "hidden with no boss")
    t.eq(p and p.point, { "LEFT", "LEFT", 20, -120 }, "at the left edge, below the middle: never over the middle")
    t.ok(p and p.spec.closable ~= true, "nothing to click on it")
end

-- Fails before: Settings/Model.lua has no "loot.bossPanel" row.
tests["boss loot: the settings model has the row, on by default"] = function(t)
    local model = ns.Settings.Model.Default()
    local row = model:row(SETTING)
    t.ok(row ~= nil, "a model row")
    t.eq(row and { row.type, row.default }, { "bool", true })
end

-- Recognised, nothing seen ---------------------------------------------------

-- Fails before: UI/BossLoot.lua (the ENCOUNTER_START handler and
-- BossLoot.Lines' "no loot seen" line) is absent: no panel at all.
tests["boss loot: a boss never killed: one plain line, no made-up item; hidden when the fight ends"] = function(t)
    local c, addon = start()
    pull(c)
    t.eq(shownLines(c), { BOSS .. ": no loot seen from this boss yet. What drops is remembered from now on." })
    c.fire("ENCOUNTER_END", ENC, BOSS, 1, 5, 0)      -- a wipe
    c.setCombat(false)
    t.eq(shownLines(c), nil, "hidden after the fight")
    local book = c.saved(ns.id.accountDB).learned
    t.eq(type(book) == "table" and book.bossLoot or nil, nil, "a wipe is no kill: nothing saved")
    t.eq(errorsOf(addon), 0)
end

-- Learning and the order rule -------------------------------------------------

-- Fails before: UI/BossLoot.lua is absent: the kill (ENCOUNTER_END), the
-- rolls taught by client.onLootRoll, BossLoot.Rows (the order rule) and
-- BossLoot.Lines.
tests["boss loot: rolls after a kill are learned; next pull lists them, your role's upgrade on top, the rest faded"] = function(t)
    local c, addon = start()
    killWith(c, EVERYTHING)
    t.eq(shownLines(c), nil, "hidden once the boss is down")
    pull(c)
    t.eq(shownLines(c), TANK_LIST, joined(shownLines(c)))
    local lines = shownLines(c) or {}
    for _, hidden in ipairs({ "Moth Robe", "Needle of Spite", "Odd Tooth" }) do
        t.ok(not holds(lines, hidden), "not shown: " .. hidden)
    end
    t.eq(errorsOf(addon), 0)
end

-- Fails before: BossLoot.Rows' order by the chosen role (spec.role) is absent.
tests["boss loot: as a healer the same drops reorder: the healing pieces on top, the tank helm below"] = function(t)
    local c = start({ role = "heal" })
    killWith(c, EVERYTHING)
    pull(c)
    t.eq(shownLines(c), {
        BOSS .. ": loot you have seen drop",
        FULL .. "Dawnweave Cuffs: upgrade +63 for Holy, seen 1 of 1 kill" .. END,
        FULL .. "Sunward Grips: upgrade +29 for Holy, seen 1 of 1 kill" .. END,
        FADED .. "Thornhelm: +25 for Protection, seen 1 of 1 kill" .. END,
        FADED .. "Dull Sabatons: no upgrade, seen 1 of 1 kill" .. END,
    }, joined(shownLines(c)))
end

-- Fails before: BossLoot.Rows' other-armour rule is absent (cloth is shown
-- only when some role's weights score it above what is worn).
tests["boss loot: another armour type shows only when it beats what is worn"] = function(t)
    local c = start()
    killWith(c, { ROBE, CUFFS })
    pull(c)
    local lines = shownLines(c)
    t.ok(holds(lines, "Dawnweave Cuffs"), "the cloth cuffs score above the worn wrists for a healer: " .. joined(lines))
    t.ok(not holds(lines, "Moth Robe"), "the weak cloth robe is left out: " .. joined(lines))
end

-- Fails before: BossLoot.Lines' no-role line and Rows' no-role order are absent.
tests["boss loot: no role chosen: every role's upgrade is full strength, and a line says how to choose"] = function(t)
    local c = start({ role = false })
    killWith(c, { HELM, GRIPS })
    pull(c)
    t.eq(shownLines(c), {
        BOSS .. ": loot you have seen drop",
        "Say " .. ns.id.slash .. " role to put your own role's pieces first.",
        FULL .. "Sunward Grips: upgrade +29 for Holy, seen 1 of 1 kill" .. END,
        FULL .. "Thornhelm: upgrade +25 for Protection, seen 1 of 1 kill" .. END,
    }, joined(shownLines(c)))
end

-- Fails before: the kill count and the per-kill count in UI/BossLoot.lua
-- (BossLoot.Kill, BossLoot.Teach) are absent.
tests["boss loot: seen n of m kills: a piece rolled twice in one kill counts once"] = function(t)
    local c = start()
    killWith(c, { HELM, HELM, BOOTS })
    killWith(c, { HELM })
    pull(c)
    t.eq(shownLines(c), {
        BOSS .. ": loot you have seen drop",
        FULL .. "Thornhelm: upgrade +25 for Protection, seen 2 of 2 kills" .. END,
        FADED .. "Dull Sabatons: no upgrade, seen 1 of 2 kills" .. END,
    }, joined(shownLines(c)))
end

-- Fails before: the CHAT_MSG_LOOT handler in UI/BossLoot.lua and
-- client.lootLine (Core/Client.lua, Core/ClientFake.lua) are absent.
tests["boss loot: a loot line after the kill teaches the item; the looter's name is never saved"] = function(t)
    local c = start()
    local line = LOOTER .. " receives loot: " .. roll(GRIPS) .. "."
    c.setLootLine(function(text) if text == line then return roll(GRIPS), 1 end end)
    killWith(c, {})
    c.fire("CHAT_MSG_LOOT", line)
    c.fire("CHAT_MSG_LOOT", "some other line")
    pull(c)
    t.eq(shownLines(c), {
        BOSS .. ": loot you have seen drop",
        FADED .. "Sunward Grips: +29 for Holy, seen 1 of 1 kill" .. END,
    }, joined(shownLines(c)))
    t.ok(not holds(c.saved(ns.id.accountDB), LOOTER), "no player name in the account data")
    t.ok(not holds(c.saved(ns.id.charDB), LOOTER), "no player name in the character data")
    t.ok(not holds(c.printed, LOOTER), "and none printed")
end

-- Fails before: the teaching window in UI/BossLoot.lua is absent (it shuts
-- when the next fight starts, and BossLoot.WINDOW seconds after the kill).
tests["boss loot: a roll outside the time after a kill is nobody's: not learned"] = function(t)
    local c = start()
    c.offerRoll(1, roll(HELM))                       -- no boss was killed
    killWith(c, { BOOTS })
    c.setCombat(true)                                -- the next pull: trash
    c.offerRoll(2, roll(GRIPS))
    c.setCombat(false)
    killWith(c, {})
    c.advance(600, 10)                               -- long after the second kill
    c.offerRoll(3, roll(CUFFS))
    pull(c)
    t.eq(shownLines(c), {
        BOSS .. ": loot you have seen drop",
        FADED .. "Dull Sabatons: no upgrade, seen 1 of 2 kills" .. END,
    }, joined(shownLines(c)))
end

-- A boss with no encounter event ----------------------------------------------

local function corpse(guid, items)
    return { source = { kind = "creature", how = "corpse", guid = guid, id = NPC, name = "Old Mossback" }, items = items }
end

-- Fails before: UI/BossLoot.lua's target route (client.targetRank
-- "worldboss", client.guid) and its LOOT_OPENED handler are absent.
tests["boss loot: a world boss target in a fight is recognised; its corpse loot is learned for the next one"] = function(t)
    local c, addon = start()
    c.setTargetRank("worldboss"); c.setGuid("target", GUID)
    c.setTarget({ exists = true, hostile = true, dead = false })
    c.fire("PLAYER_TARGET_CHANGED")
    t.eq(shownLines(c), nil, "not in a fight yet: nothing")
    c.setCombat(true)
    t.eq(shownLines(c), { "This boss: no loot seen from this boss yet. What drops is remembered from now on." })
    c.setTarget({ exists = true, hostile = true, dead = true })
    c.setCombat(false)
    c.advance(2, 4)
    t.eq(shownLines(c), nil, "hidden once it is dead")
    c.setLootWindow(corpse(GUID, { { item = roll(HELM), count = 1 }, { item = roll(BOOTS), count = 1 } }))
    c.fire("LOOT_OPENED")
    c.fire("LOOT_OPENED")                            -- the same corpse opened again
    -- The next one of its kind.
    c.setGuid("target", GUID2); c.setTarget({ exists = true, hostile = true, dead = false })
    c.fire("PLAYER_TARGET_CHANGED"); c.setCombat(true)
    t.eq(shownLines(c), {
        "Old Mossback: loot you have seen drop",
        FULL .. "Thornhelm: upgrade +25 for Protection, seen 1 of 1 kill" .. END,
        FADED .. "Dull Sabatons: no upgrade, seen 1 of 1 kill" .. END,
    }, joined(shownLines(c)))
    t.eq(errorsOf(addon), 0)
end

-- Fails before: UI/BossLoot.lua's last route (client.instance, an elite
-- target already in the boss book) is absent.
tests["boss loot: in an instance an elite already in the book is recognised; an elite never learned is not"] = function(t)
    local c = start()
    c.setTargetRank("worldboss"); c.setGuid("target", GUID)
    c.setTarget({ exists = true, hostile = true, dead = false }); c.setCombat(true)
    c.setTarget({ exists = true, hostile = true, dead = true }); c.setCombat(false); c.advance(2, 4)
    c.setLootWindow(corpse(GUID, { { item = roll(HELM), count = 1 } }))
    c.fire("LOOT_OPENED")
    -- Later the game calls the same creature only "elite".
    c.setTargetRank("elite"); c.setGuid("target", GUID2)
    c.setTarget({ exists = true, hostile = true, dead = false }); c.setCombat(true)
    t.eq(shownLines(c), nil, "not known to be in an instance: not recognised")
    c.setInstance({ inside = true, kind = "party" }); c.advance(2, 4)
    t.ok(holds(shownLines(c), "Thornhelm"), "in an instance: recognised by the book: " .. joined(shownLines(c)))
    c.setGuid("target", STRAY); c.fire("PLAYER_TARGET_CHANGED")
    t.eq(shownLines(c), nil, "an elite that was never a boss: nothing")
end

-- The setting -------------------------------------------------------------------

-- Fails before: the row "loot.bossPanel" and its watch in UI/BossLoot.lua are absent.
tests["boss loot: the setting hides the panel at once and brings it back; drops are still learned while off"] = function(t)
    local c, addon = start()
    killWith(c, { HELM })
    pull(c)
    t.ok(shownLines(c) ~= nil, "on by default: shown, so this test can fail")
    t.eq(addon.settings:set(SETTING, false), true, "the row takes off")
    t.eq(shownLines(c), nil, "off: hidden at once")
    down(c)
    c.offerRoll(9, roll(BOOTS))
    pull(c)
    t.eq(shownLines(c), nil, "off: still hidden in the next fight")
    addon.settings:set(SETTING, true)
    t.eq(shownLines(c), {
        BOSS .. ": loot you have seen drop",
        FULL .. "Thornhelm: upgrade +25 for Protection, seen 1 of 2 kills" .. END,
        FADED .. "Dull Sabatons: no upgrade, seen 1 of 2 kills" .. END,
    }, joined(shownLines(c)))
end

-- Fails before: the saved place (layout.bossLoot) in UI/BossLoot.lua is absent.
tests["boss loot: dragged to another place, the panel is there after a reload"] = function(t)
    local c = start()
    local p = panelOf(c)
    t.ok(p ~= nil, "a panel")
    if not p then return end
    p.drag({ "TOPRIGHT", "TOPRIGHT", -40, -300 })
    local c2 = start({ account = c.saved(ns.id.accountDB), char = c.saved(ns.id.charDB) })
    t.eq(panelOf(c2) and panelOf(c2).point, { "TOPRIGHT", "TOPRIGHT", -40, -300 })
end

-- Look only -------------------------------------------------------------------

-- Fails before: there is no boss loot module to hold to this (the first
-- assertion: the panel is shown).
tests["boss loot: look only: nothing is crafted or clicked through it, and it says nothing in chat"] = function(t)
    local c = start()
    local printed = #c.printed
    killWith(c, EVERYTHING)
    pull(c)
    t.ok(shownLines(c) ~= nil, "shown")
    for i = printed + 1, #c.printed do
        local line = tostring(c.printed[i])
        t.ok(not line:find(BOSS, 1, true), "the boss is not named in chat")
        for _, name in pairs(NAMES) do t.ok(not line:find(name, 1, true), "no drop is named in chat: " .. name) end
    end
    t.eq(#c.crafts, 0, "nothing crafted")
    for _, b in ipairs(c.secureButtons) do
        t.ok(not tostring(type(b.spec) == "table" and b.spec.name or ""):find("BossLoot", 1, true), "no button of its own")
    end
end

-- Lead section 236 ---------------------------------------------------------------

-- (a) Data late and in parts. The drop is learned from a roll while the
-- client knows nothing of the item. The line waits; then the name and the
-- slot come without the stats or the level; then everything. A verdict is
-- shown only at the end: never a guess between.
-- Fails before: UI/BossLoot.lua's waiting line (BossLoot.Rows state "wait")
-- and its GET_ITEM_INFO_RECEIVED handler are absent.
tests["boss loot 236(a): item data late and in parts: the line waits, then says not known, then the verdict"] = function(t)
    local c, addon, info = start({ items = false })
    killWith(c, { HELM })
    pull(c)
    t.eq(shownLines(c), {
        BOSS .. ": loot you have seen drop",
        FADED .. "Item 4001: not read yet, seen 1 of 1 kill" .. END,
    }, "nothing known of the item: it waits")
    -- Part one: the name and where it is worn; no stats, no level, no marks.
    info[HELM] = { name = NAMES[HELM] }
    c.setItem(plain(HELM), { kind = "INVTYPE_HEAD", classID = 4, subclassID = 4 })
    c.fire("GET_ITEM_INFO_RECEIVED", HELM, true)
    t.eq(shownLines(c), {
        BOSS .. ": loot you have seen drop",
        FADED .. "Thornhelm: not known whether you can use it, seen 1 of 1 kill" .. END,
    }, "half read: no verdict, never an upgrade")
    -- Part two: everything.
    c.setItem(plain(HELM), DROPS[HELM])
    c.fire("GET_ITEM_INFO_RECEIVED", HELM, true)
    t.eq(shownLines(c), {
        BOSS .. ": loot you have seen drop",
        FULL .. "Thornhelm: upgrade +25 for Protection, seen 1 of 1 kill" .. END,
    }, "all read: the verdict")
    t.eq(errorsOf(addon), 0)
end

-- (a) again, with no event: a line that waits is asked again on the clock.
-- Fails before: UI/BossLoot.lua's tick is absent.
tests["boss loot 236(a): a waiting line is read again without any event"] = function(t)
    local c, _, info = start({ items = false })
    killWith(c, { HELM })
    pull(c)
    t.ok(holds(shownLines(c), "Item 4001: not read yet"), joined(shownLines(c)))
    info[HELM] = { name = NAMES[HELM] }
    c.setItem(plain(HELM), DROPS[HELM])
    c.advance(3, 6)
    t.ok(holds(shownLines(c), "Thornhelm: upgrade +25 for Protection"), joined(shownLines(c)))
end

-- (b) A reload in the middle. Drops learned on one add-on instance are
-- shown by a second one built from the saved account data, in the middle
-- of the next fight: no ENCOUNTER_START reaches the second instance, so it
-- knows the boss by its boss unit and the creature the first one saw.
-- Fails before: the account book (learned.bossLoot), the creature kept
-- beside the encounter, and the boss unit route (client.bossUnit) are absent.
tests["boss loot 236(b): a reload mid-fight: the second instance shows what the first learned"] = function(t)
    local c = start()
    killWith(c, EVERYTHING)
    pull(c)
    t.eq(shownLines(c), TANK_LIST, "learned and shown by the first instance")
    local account, char = c.saved(ns.id.accountDB), c.saved(ns.id.charDB)
    t.ok(type(account.learned) == "table" and type(account.learned.bossLoot) == "table", "saved account wide")
    t.ok(not holds(char, "bossLoot"), "nothing of it in the character's data")
    -- The reload: a new client and add-on over the same saved tables.
    local c2, addon2 = start({ account = account, char = char })
    t.eq(shownLines(c2), nil, "no fight known yet")
    c2.setBossUnit({ exists = true, guid = GUID, name = BOSS })
    c2.setCombat(true)
    t.eq(shownLines(c2), TANK_LIST, joined(shownLines(c2)))
    t.eq(errorsOf(addon2), 0)
    -- Another character of the account, never in the fight before.
    local c3 = start({ account = account, role = "heal" })
    pull(c3)
    t.ok(holds(shownLines(c3), "Dawnweave Cuffs: upgrade +63 for Holy"), "account wide: " .. joined(shownLines(c3)))
end

-- (c) A read that raises, then recovers. First the item read: the line
-- waits, no error escapes, and the verdict comes when the read answers.
-- Then a read the recognition needs: no boss is claimed while it raises,
-- and the panel appears when it answers.
-- Fails before: UI/BossLoot.lua guards no read (it is absent); the fake's
-- c.setReadFails is absent too.
tests["boss loot 236(c): the item read raises, then answers: the line waits, no error, then the verdict"] = function(t)
    local c, addon = start()
    killWith(c, { HELM })
    c.setReadFails("gear", true)
    pull(c)
    t.eq(shownLines(c), {
        BOSS .. ": loot you have seen drop",
        FADED .. "Thornhelm: not read yet, seen 1 of 1 kill" .. END,
    }, "the read raises: the line waits")
    t.eq(errorsOf(addon), 0, "no error escaped")
    t.eq((addon:ModuleState(NAME)), "started", "the module is still on")
    c.setReadFails("gear", false)
    c.advance(3, 6)
    t.eq(shownLines(c), {
        BOSS .. ": loot you have seen drop",
        FULL .. "Thornhelm: upgrade +25 for Protection, seen 1 of 1 kill" .. END,
    }, "the read answers: the verdict")
end

tests["boss loot 236(c): a recognition read raises, then answers: no boss claimed, no error, then the panel"] = function(t)
    local c, addon = start()
    c.setBossUnit({ exists = true, guid = GUID, name = BOSS })
    c.setReadFails("bossUnit", true)
    c.setCombat(true)
    c.advance(3, 6)
    t.eq(shownLines(c), nil, "the boss unit read raises: no boss is claimed")
    t.eq(errorsOf(addon), 0, "no error escaped")
    t.eq((addon:ModuleState(NAME)), "started")
    c.setReadFails("bossUnit", false)
    c.advance(3, 6)
    t.eq(shownLines(c), { BOSS .. ": no loot seen from this boss yet. What drops is remembered from now on." },
        "the read answers: the panel")
end

return tests
