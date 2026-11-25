-- Fake client for offline tests: same surface as Core/Client.lua, driven by
-- the test. Listed as `dev` in manifest.lua, so it is never in the TOC.
-- Loading this file replaces ns.client with a fake: the offline runner has
-- no game client, and the shared kernel must not look for one.
--
--   local c = ns.make.fakeClient{ now = 50 }
--   c.advance(1.0, 10)      -- one second in ten frames
--   c.setClock(1700000000)  -- the wall clock; not known until set
--   c.fire("SOME_EVENT", 1) -- to everything that listens
--   c.setCombat(true)       -- also fires the combat start / end event
--   c.setLoaded("Name", true); c.setSaved("NameDB", {...}); c.burn(5)
--   c.setMoney(12345); c.setBags{ { free = 3, total = 16, family = 0 } }
--   c.setBagItems{ { item = 2318, count = 4 } }; c.setBank{ ... }
--   c.setRecipes{ profession = 164, skill = 104, max = 150, recipes = { ... } }
--   c.setRecipeSchematic(2963, { makes = 2996, yield = 1, mats = { [2589] = 2 } })
--   c.setTradeSkillRows{ name = "Tailoring", rows = { { index = 2, name = "Bolt of Linen Cloth" } }, whole = true }
--   c.setSpell(5176, { known = true, usable = false, noPower = true })
--   c.setSpellId("Wrath", 5176)   c.setFacing(1.57)
--   c.setMapSize(1411, 5287.5, 3525); c.setMapCont(1411, 1)
--   c.setBankOpen(true)     -- also fires the bank opened / closed event
--   c.setMerchant{ { item = "item:2318", price = 60, stack = 1 } }
--   c.setMerchantOpen(true) -- also fires the merchant shown / closed event
--   ns.make.fakeClient{ env = { GetMoney = function() return 5 end } }; c.slashes["/x"]("rest")
--   c.setZone(1, 1411); c.setPosition(1411, 0.5, 0.25); c.setLockdown(true)
--   c.setDead(true); c.setCorpse(1411, 0.3, 0.6)
--   c.setCorpse(false)               on no position of the player's map; nil: not known
--   c.setGhost(true)                 false: dead, not released; nil: not known
--   c.setWaypoint(1411, 0.4, 0.2)   -- c.setWaypoint(nil): none set
--   c.setScreen(1024, 768); c.setVersion("0.1.0"); c.setFrames(false)
--   c.panels[1].lines / .point / .shown / .spec; c.panels[1].drag({ "CENTER", "CENTER", 0, 0 })
--   c.panel({ closable = true }) has h.onClose(fn, failed); h.close() is the
--   player closing it. c.setCloseRoute(false): a client with no close route.
--   c.arrows[1].point / .attached / .shown / .drawn / .lines; c.arrows[1].drag(point)
--   c.setQuestLog({ { id = 1, title = "A", objectives = { { text = "x", done = false } } } })
--   c.setQuestieModule("QuestieDB", { GetQuest = fn }); c.setMinimap({ size = 140, radius = 100, rotates = false })
--   c.minimapPins[1].x / .y / .edge / .shown / .places / .hides / .spec
--   c.setItemInfo{ [2318] = { name = "Light Leather", quality = 1, sellPrice = 15, classID = 7 } }
--   c.setDurability{ [5] = { cur = 40, max = 100 } }; c.setOwnLoot(function(line) return link, count end)
--   c.setLootWindow{ source = { kind = "creature", guid = "...", id = 1 }, items = { { item = 97, count = 1 } } }
--   c.setXp{ cur = 450, max = 1000, rested = 0 }; c.setWatchedFaction(false); c.setGameTime(14, 5)
--   c.infoBars[1].text / .shown / .point / .tipLines; c.infoBars[1].drag(point) / .resize(w, h)
-- What a test has not set is unknown (nil), as on a client that won't say.
local _, ns = ...
ns.make = ns.make or {}

-- A copy of a list of flat rows, so a test and the fake share no table.
local function copyRows(rows)
    if type(rows) ~= "table" then return nil end
    local out = {}
    for i = 1, #rows do
        local row = {}
        for k, v in pairs(rows[i]) do row[k] = v end
        out[i] = row
    end
    return out
end

function ns.make.fakeClient(opts)
    opts = opts or {}
    local s = { t = opts.now or 1000, ms = 0, combat = false, bankOpen = false, merchantOpen = false, loaded = {}, saved = {}, listening = {}, eventFaults = {}, frames = 0 }
    -- The craft repeat runner step (section 240), set in the craft section.
    local repeatFrame
    local c = { printed = {} }

    local events = ns.make.listeners(
        function(event) s.listening[event] = true end,
        function(event) s.listening[event] = nil end)
    local ticks = ns.make.listeners(
        function() s.frames = 1 end,
        function() s.frames = 0 end)

    -- the client surface
    function c.now() return s.noTime and 0 or s.t end
    function c.clock() return s.clock end
    function c.clockMs() return s.ms end
    -- As on the real client: every line said goes to the onPrint listeners,
    -- and one that raises does not stop the line being said.
    local prints = ns.make.listeners(function() end, function() end)
    function c.print(text)
        text = tostring(text)
        c.printed[#c.printed + 1] = text
        prints.call("print", text)
    end
    function c.onPrint(fn)
        if type(fn) ~= "function" then return function() end end
        return prints.add("print", function(text) pcall(fn, text) end)
    end
    function c.listen(event, fn) return events.add(event, fn) end
    function c.onFrame(fn) return ticks.add("frame", fn) end
    function c.addonLoaded(name) return s.loaded[name] == true end
    function c.inCombat() return s.combat end
    function c.uptime()
        if s.noTime then return nil end
        return s.t
    end
    function c.listenFaults()
        local names = {}
        for event in pairs(s.eventFaults) do names[#names + 1] = event end
        table.sort(names)
        return { notRegistered = names, noEventFrame = s.noEventFrame and true or false,
            noTickFrame = s.noTickFrame and true or false }
    end
    local madeHere = {}
    function c.saved(name)
        if type(s.saved[name]) ~= "table" then
            s.saved[name] = {}
            madeHere[name] = s.saved[name]
        end
        return s.saved[name]
    end
    function c.savedMadeHere(name)
        return madeHere[name] ~= nil and s.saved[name] == madeHere[name]
    end
    function c.savedExists(name) return type(s.saved[name]) == "table" end
    function c.money() return s.money end
    function c.bags() return copyRows(s.bags) end
    function c.bagItems() return copyRows(s.bagItems) end
    -- Lead section 337 item 1, as the real client's: each stack set with
    -- c.setBagItems and where it is. A row's own bag and slot when the test
    -- gave them, else bag 0 and its place in the list. nil when no bag is set.
    local function slotRows()
        if type(s.bagItems) ~= "table" then return nil end
        local out = {}
        for i, row in ipairs(s.bagItems) do
            out[i] = { bag = row.bag or 0, slot = row.slot or i, item = row.item, count = row.count }
        end
        return out
    end
    function c.bagSlots()
        local rows = slotRows()
        if rows == nil then return nil end
        table.sort(rows, function(a, b)
            if a.bag ~= b.bag then return a.bag < b.bag end
            return a.slot < b.slot
        end)
        return rows
    end
    function c.bagSlot(bag, slot)
        if type(bag) ~= "number" or type(slot) ~= "number" then return false end
        for _, row in ipairs(slotRows() or {}) do
            if row.bag == bag and row.slot == slot then return row.item, row.count end
        end
        return nil
    end
    -- Lead section 337 item 1 (ACTING), as the real client's: the slot sold
    -- leaves the bags and is kept in c.soldSlots, in the order sold.
    c.soldSlots = {}
    function c.sellBagItem(bag, slot)
        if c.combatLockdown() ~= false then return nil, "combat" end
        if s.merchantOpen ~= true then return nil, "closed" end
        if type(s.bagItems) ~= "table" or type(bag) ~= "number" or type(slot) ~= "number" then return nil, "bad" end
        local found = nil
        for i, row in ipairs(s.bagItems) do
            if found == nil and (row.bag or 0) == bag and (row.slot or i) == slot then found = i end
        end
        if found == nil then return nil, "bad" end
        local kept = {}
        for i, row in ipairs(s.bagItems) do
            if i ~= found then
                local copy = {}
                for k, v in pairs(row) do copy[k] = v end
                copy.bag, copy.slot = row.bag or 0, row.slot or i
                kept[#kept + 1] = copy
            end
        end
        local row = s.bagItems[found]
        s.bagItems = kept
        c.soldSlots[#c.soldSlots + 1] = { bag = bag, slot = slot, item = row.item, count = row.count }
        return true
    end
    function c.watchBank() end
    function c.bankOpen() return s.bankOpen end
    function c.bankItems()
        if s.bankOpen ~= true then return nil end
        return copyRows(s.bank)
    end
    function c.watchMerchant() end
    function c.merchantOpen() return s.merchantOpen end
    function c.merchantItems()
        if s.merchantOpen ~= true then return nil end
        return copyRows(s.merchant)
    end
    function c.returnableItems()
        if s.merchantOpen ~= true then return nil end
        return copyRows(s.buyback)
    end
    function c.recipes()
        local r = s.recipes
        if type(r) ~= "table" then return nil end
        return {
            profession = r.profession,
            name = type(r.name) == "string" and r.name or nil,
            skill = r.skill,
            max = r.max,
            recipes = copyRows(r.recipes) or {},
        }
    end
    -- Section 227 (P-GOALS-RECIPE): one recipe's product, yield and mats, a
    -- copy; nil when none is set for that id.
    function c.recipeSchematic(id)
        local r = s.schematics and s.schematics[id]
        if type(r) ~= "table" then return nil end
        local mats = {}
        for item, n in pairs(type(r.mats) == "table" and r.mats or {}) do mats[item] = n end
        return { makes = r.makes, yield = r.yield, mats = mats }
    end
    -- Section 231 item 1: the classic fallback, by trade skill row index; a
    -- copy, nil when none is set for that index.
    -- Section 233 (GR2-1): the classic window's rows, a copy; nil when none
    -- are set. Section 245 (RB2-2): collapsed, filtered and whole as set;
    -- not set, they are nil: unknown, never "every learned recipe".
    function c.tradeSkillRows()
        local r = s.tradeRows
        if type(r) ~= "table" then return nil end
        return { name = r.name, skill = r.skill, max = r.max, rows = copyRows(r.rows) or {},
                 collapsed = r.collapsed, filtered = r.filtered, whole = r.whole }
    end
    -- Section 238: name, difficulty and partial too, as the client gives.
    function c.tradeSkillSchematic(index)
        local r = s.tradeSchematics and s.tradeSchematics[index]
        if type(r) ~= "table" then return nil end
        local mats = {}
        for item, n in pairs(type(r.mats) == "table" and r.mats or {}) do mats[item] = n end
        return { name = r.name, difficulty = r.difficulty, makes = r.makes, yield = r.yield, mats = mats,
                 partial = r.partial }
    end
    -- N24: the tools one classic row needs, a copy; nil when not set.
    function c.tradeSkillTools(index)
        local list = s.tradeTools and s.tradeTools[index]
        if type(list) ~= "table" then return nil end
        local out = {}
        for i, tool in ipairs(list) do out[i] = { name = tool.name, has = tool.has } end
        return out
    end
    function c.spell(id)
        if type(id) ~= "number" then return nil end
        local r = s.spells and s.spells[id] or {}
        return { known = r.known, usable = r.usable, noPower = r.noPower, name = r.name }
    end
    function c.spellId(name) return s.spellIds and s.spellIds[name] or nil end
    function c.watchTrainer() end
    -- A copy of the service rows, or nil.
    local function copyRowsOf(rows)
        if type(rows) ~= "table" then return nil end
        local out = {}
        for i = 1, #rows do
            local r = {}
            for k, v in pairs(rows[i]) do r[k] = v end
            out[i] = r
        end
        return out
    end
    function c.trainer()
        local r = s.trainer
        if type(r) ~= "table" then return nil end
        local filter = nil
        if type(r.filter) == "table" then
            filter = { available = r.filter.available, unavailable = r.filter.unavailable, known = r.filter.known }
        end
        return { profession = r.profession, npc = r.npc, services = copyRowsOf(r.services), filter = filter }
    end
    -- As the real client's (F8): fn({ id, name, rank }) for each spell learned
    -- with learnSpell; the answer takes the listener back.
    function c.onSpellLearned(fn)
        if type(fn) ~= "function" then return nil end
        s.learnedListeners = s.learnedListeners or {}
        table.insert(s.learnedListeners, fn)
        return function()
            for i = #s.learnedListeners, 1, -1 do
                if s.learnedListeners[i] == fn then table.remove(s.learnedListeners, i) end
            end
        end
    end
    -- Plays the game telling that a spell was learned.
    function c.learnSpell(spell)
        local copy = { id = spell and spell.id, name = spell and spell.name, rank = spell and spell.rank }
        for _, fn in ipairs({ unpack(s.learnedListeners or {}) }) do fn(copy) end
    end
    function c.faction() return s.faction end
    function c.class() return s.class end
    function c.stealthed() return s.stealthed end
    function c.target()
        local r = s.target
        if type(r) ~= "table" then return nil end
        if not r.exists then return { exists = false } end
        return { exists = true, hostile = r.hostile, dead = r.dead }
    end
    function c.inRange(id)
        if type(id) ~= "number" or not s.ranges then return nil end
        return s.ranges[id]
    end
    -- As the real client's (F4): fn(rollID, link, show) for each roll offered
    -- with offerRoll; the answer takes the listener back.
    function c.onLootRoll(fn)
        if type(fn) ~= "function" then return nil end
        s.rollListeners = s.rollListeners or {}
        table.insert(s.rollListeners, fn)
        return function()
            for i = #s.rollListeners, 1, -1 do
                if s.rollListeners[i] == fn then table.remove(s.rollListeners, i) end
            end
        end
    end
    -- Plays the game offering a roll on `link`: every onLootRoll listener is
    -- told, and what they showed comes back as { { text, r, g, b } ... }.
    function c.offerRoll(rollID, link)
        local shown = {}
        local function show(text, r, g, b) shown[#shown + 1] = { text = text, r = r, g = g, b = b } end
        for _, fn in ipairs({ unpack(s.rollListeners or {}) }) do fn(rollID, link, show) end
        return shown
    end
    function c.level() return s.level end
    -- As the real client's: fn(link, add) for each item tooltip shown with
    -- showItemTooltip; the answer takes the listener back.
    function c.onItemTooltip(fn)
        if type(fn) ~= "function" then return nil end
        s.tooltipListeners = s.tooltipListeners or {}
        table.insert(s.tooltipListeners, fn)
        return function()
            for i = #s.tooltipListeners, 1, -1 do
                if s.tooltipListeners[i] == fn then table.remove(s.tooltipListeners, i) end
            end
        end
    end
    -- A copy of a flat table, or nil for anything else.
    local function copyFlat(t)
        if type(t) ~= "table" then return nil end
        local out = {}
        for key, value in pairs(t) do out[key] = value end
        return out
    end
    -- One item as gear() gives it: its kind and a copy of its stats; a link
    -- nobody described gives an item with nothing known.
    local function gearItem(link)
        local item = s.items and s.items[link] or nil
        if not item then return {} end
        return { kind = item.kind, stats = copyFlat(item.stats) }
    end
    -- As the real client's gear(): { kind, stats, classID, subclassID,
    -- minLevel, unmet, speed, worn, dualWield }. Worn items carry kind and
    -- stats only, as the real client's do.
    function c.gear(link)
        local out = { worn = {}, dualWield = s.dualWield }
        if type(link) == "string" and link ~= "" then
            local item = gearItem(link)
            out.kind, out.stats = item.kind, item.stats
            local more = s.items and s.items[link] or nil
            if more then
                out.classID, out.subclassID, out.minLevel = more.classID, more.subclassID, more.minLevel
                out.unmet, out.speed = copyFlat(more.unmet), more.speed
            end
        end
        for slot, worn in pairs(s.worn or {}) do
            if worn == false then
                out.worn[slot] = false
            elseif type(worn) == "string" then
                out.worn[slot] = gearItem(worn)
            end
        end
        return out
    end
    function c.spellCooldown(id)
        if type(id) ~= "number" or not s.cooldowns then return nil end
        return s.cooldowns[id]
    end
    function c.spellCooldownLeft(id)
        if type(id) ~= "number" or not s.cooldownLeft then return nil end
        return s.cooldownLeft[id]
    end
    function c.facing() return s.facing end
    -- The quest log: a copy of what setQuestLog was given, or nil.
    function c.questLog()
        if type(s.questLog) ~= "table" then return nil end
        local rows = {}
        for i, r in ipairs(s.questLog) do
            local row = { id = r.id, title = r.title, complete = r.complete, failed = r.failed, objectives = {} }
            for j, o in ipairs(r.objectives or {}) do row.objectives[j] = { text = o.text, done = o.done } end
            rows[i] = row
        end
        return rows
    end
    -- Each focus read on its own, as setQuestFocusReads was given it.
    function c.questFocusReads() return s.questFocusReads end
    -- Which quest the player follows: a copy of what setQuestFocus was
    -- given, or nil for no such read.
    function c.questFocus()
        local f = s.questFocus
        if type(f) ~= "table" then return nil end
        local out = { quest = f.quest }
        if type(f.watched) == "table" then
            out.watched = {}
            for i, id in ipairs(f.watched) do out.watched[i] = id end
        end
        return out
    end
    -- The Questie module of that name as set, itself (not a copy), or nil.
    function c.questieModule(name)
        return s.questie and s.questie[name] or nil
    end
    -- The dungeon journal: nil (as made) is a client with no journal
    -- calls. setJournal({ [encounter] = { name =, items = { id } } }, shown)
    -- makes one; shown: its window is open, so no loot is given.
    function c.setJournal(map, shown) s.journal, s.journalShown = map, shown and true or nil end
    c.journalAsks = {}
    function c.journalBoss(instance, encounter, withLoot)
        c.journalAsks[#c.journalAsks + 1] = { instance = instance, encounter = encounter, withLoot = withLoot }
        if type(s.journal) ~= "table" then return nil end
        local row = s.journal[encounter]
        if type(row) ~= "table" then return nil end
        local out = { name = row.name, items = {} }
        if not withLoot then return out end
        if s.journalShown then
            out.shown = true
            return out
        end
        for i, id in ipairs(row.items or {}) do out.items[i] = id end
        return out
    end
    function c.minimap()
        local r = s.minimap
        if type(r) ~= "table" then return nil end
        return { size = r.size, radius = r.radius, rotates = r.rotates, square = r.square }
    end
    -- Every minimap pin made is in c.minimapPins, in order.
    c.minimapPins = {}
    function c.minimapPin(spec)
        if s.noFrames then return nil end
        local h = { spec = spec, shown = false, places = 0, hides = 0 }
        function h.place(x, y, edge)
            if type(x) ~= "number" or type(y) ~= "number" then return end
            h.x, h.y, h.edge, h.shown = x, y, edge and true or false, true
            h.places = h.places + 1
        end
        function h.hide()
            h.shown = false
            h.hides = h.hides + 1
        end
        c.minimapPins[#c.minimapPins + 1] = h
        return h
    end
    -- The facts of one item: a copy of the row setItemInfo has for its ID,
    -- or nil. item: a link or an ID.
    function c.itemInfo(item)
        if type(s.itemInfo) ~= "table" then return nil end
        local id = item
        if ns.Items and type(ns.Items.Id) == "function" then id = ns.Items.Id(item) or item end
        local row = s.itemInfo[id]
        if type(row) ~= "table" then return nil end
        local out = {}
        for k, v in pairs(row) do out[k] = v end
        return out
    end
    -- { [slot] = { cur =, max = } }: a copy of what setDurability was given,
    -- or nil.
    function c.durability()
        if type(s.durability) ~= "table" then return nil end
        local out = {}
        for slot, r in pairs(s.durability) do
            if type(r) == "table" then out[slot] = { cur = r.cur, max = r.max } end
        end
        return out
    end
    -- Whose loot a chat line is: what the function given to setOwnLoot
    -- answers (item, count), or nil when none was given.
    function c.ownLoot(line)
        if type(s.ownLoot) ~= "function" then return nil end
        return s.ownLoot(line)
    end
    -- The open loot window: a copy of what setLootWindow was given, or nil.
    function c.lootWindow()
        local r = s.lootWindow
        if type(r) ~= "table" then return nil end
        local out = { items = {} }
        for i, row in ipairs(type(r.items) == "table" and r.items or {}) do
            out.items[i] = { item = row.item, count = row.count }
        end
        if type(r.source) == "table" then
            out.source = {}
            for k, v in pairs(r.source) do out.source[k] = v end
        end
        return out
    end
    function c.mapSize(map)
        local r = s.mapSizes and s.mapSizes[map]
        return r and { w = r.w, h = r.h } or nil
    end
    function c.mapCont(map)
        return s.mapConts and s.mapConts[map] or nil
    end
    function c.position()
        if not s.position then return nil end
        return { map = s.position.map, x = s.position.x, y = s.position.y }
    end
    function c.dead() return s.dead end
    function c.ghost() return s.ghost end
    function c.corpse()
        if s.corpse == false then return false end
        if not s.corpse then return nil end
        return { map = s.corpse.map, x = s.corpse.x, y = s.corpse.y }
    end
    function c.waypoint()
        if not s.waypoint then return nil end
        return { map = s.waypoint.map, x = s.waypoint.x, y = s.waypoint.y }
    end
    function c.zone()
        if not s.zone then return nil end
        return { cont = s.zone.cont, zone = s.zone.zone }
    end
    function c.combatLockdown()
        if s.lockdownSet then return s.lockdown end
        return s.combat
    end

    -- Diagnostics: names resolve in opts.env, a table the test hands over.
    local env = opts.env or {}
    local function lookup(path)
        local at = env
        for seg in tostring(path):gmatch("[^%.]+") do
            if type(at) ~= "table" then return nil end
            at = at[seg]
        end
        return at
    end
    function c.typeOf(path) return type(lookup(path)) end
    function c.raw(path, ...)
        local fn = lookup(path)
        if type(fn) ~= "function" then return false, "not a function" end
        return pcall(fn, ...)
    end
    function c.peek(path, limit)
        local v = lookup(path)
        local kind = type(v)
        if kind == "number" or kind == "string" or kind == "boolean" then return v end
        if kind ~= "table" then return nil end
        local out, n = {}, 0
        for key, value in pairs(v) do
            if n >= (limit or 300) then break end
            local vk = type(value)
            out[tostring(key)] = (vk == "number" or vk == "string" or vk == "boolean") and value or vk
            n = n + 1
        end
        return out
    end
    function c.globalNames(pattern, limit)
        local out = {}
        for name in pairs(env) do
            if type(name) == "string" and name:find(pattern) then out[#out + 1] = name end
        end
        table.sort(out)
        for i = #out, (limit or 300) + 1, -1 do out[i] = nil end
        return out
    end
    local errorFns = {}
    function c.onError(fn) errorFns[#errorFns + 1] = fn return true end
    -- The test's control: a Lua error reported by the client.
    function c.raise(text) for i = 1, #errorFns do errorFns[i](text) end end
    c.slashes = {}
    function c.slash(tag, command, fn)
        c.slashes[command] = function(rest) fn(rest or "") end
        return true
    end

    -- Drawing. Every panel made is in c.panels, in order.
    c.panels = {}
    -- The copy box, with the focus rules of the real one (L6-N). Every box
    -- made is in c.copyBoxes, in order: { spec, text, shown, focused } and
    -- the test's controls click() (the player clicks in the text) and
    -- escape() (the player presses Escape). Showing a box never focuses
    -- it; hiding it and Escape always release focus.
    c.copyBoxes = {}
    function c.copyBox(spec)
        if s.noFrames then return nil end
        local box = { spec = spec, text = "", shown = false, focused = false }
        local h = {}
        function h.setText(text) box.text = tostring(text == nil and "" or text) end
        function h.show(on)
            box.shown = on and true or false
            if not box.shown then box.focused = false end
        end
        function box.click()
            if box.shown then box.focused = true end
        end
        function box.escape()
            box.focused = false
            box.shown = false
        end
        c.copyBoxes[#c.copyBoxes + 1] = box
        return h
    end
    function c.version() return s.version end
    function c.screen()
        if not s.screen then return nil end
        return s.screen[1], s.screen[2]
    end
    function c.panel(spec)
        if s.noFrames then return nil end
        local h = { spec = spec, lines = {}, shown = false, places = 0 }
        local moved
        function h.setLines(lines)
            h.lines = {}
            for i = 1, #(lines or {}) do h.lines[i] = tostring(lines[i]) end
        end
        function h.place(point)
            if type(point) ~= "table" then return end
            h.point = { point[1], point[2], point[3], point[4] }
            h.places = h.places + 1
        end
        function h.show(on) h.shown = on and true or false end
        local movedFailed
        function h.onMoved(fn, failed)
            moved = fn
            movedFailed = type(failed) == "function" and failed or nil
        end
        -- The test's control: the player let the panel go at this point.
        -- As on the real client, an error in the moved callback goes to
        -- `failed` when one was given and is dropped otherwise.
        function h.drag(point)
            h.point = { point[1], point[2], point[3], point[4] }
            if moved then
                local ok, err = pcall(moved, { point[1], point[2], point[3], point[4] })
                if not ok and movedFailed then movedFailed(err) end
            end
        end
        -- A closable panel, as on the real client: onClose only when
        -- there is a close route. close() is the test's control: the
        -- player closed it by the button or Escape. Nothing on a panel
        -- that is not shown.
        if type(spec) == "table" and spec.closable == true and not s.noCloseRoute then
            local closed = type(spec.onClose) == "function" and spec.onClose or nil
            local closedFailed
            function h.onClose(fn, failed)
                closed = type(fn) == "function" and fn or nil
                closedFailed = type(failed) == "function" and failed or nil
            end
            function h.close()
                if not h.shown then return end
                h.shown = false
                if closed then
                    local ok, err = pcall(closed)
                    if not ok and closedFailed then closedFailed(err) end
                end
            end
        end
        c.panels[#c.panels + 1] = h
        return h
    end

    -- Every icon made is in c.icons, in order: .spec, .shown, .texture,
    -- .point, .places, .marked ("far" or nil, the last mark).
    -- setTexture(nil) clears and answers false, as on the
    -- client. drag(point) is the test's control: the player let it go
    -- there; without the move key (c.setMoveKey(false)) nothing happens.
    c.icons = {}
    function c.icon(spec)
        if s.noFrames then return nil end
        local h = { spec = spec, shown = false, places = 0 }
        local moved, movedFailed
        function h.setTexture(tex)
            h.texture = tex
            return tex ~= nil
        end
        function h.place(point)
            if type(point) ~= "table" then return end
            h.point = { point[1], point[2], point[3], point[4] }
            h.places = h.places + 1
        end
        function h.show(on) h.shown = on and true or false end
        function h.mark(look)
            h.marked = look == "far" and "far" or nil
            return true
        end
        function h.onMoved(fn, failed)
            moved = fn
            movedFailed = type(failed) == "function" and failed or nil
        end
        function h.drag(point)
            if s.noMoveKey then return end
            h.point = { point[1], point[2], point[3], point[4] }
            if moved then
                local ok, err = pcall(moved, { point[1], point[2], point[3], point[4] })
                if not ok and movedFailed then movedFailed(err) end
            end
        end
        c.icons[#c.icons + 1] = h
        return h
    end
    function c.spellTexture(id) return s.spellTextures and s.spellTextures[id] or nil end

    -- Every arrow made is in c.arrows, in order. A handle keeps what it
    -- was last told: point or attached (the other handle), shown, lookIs,
    -- drawn (the last draw table), scaled, faded (alpha), under (behind),
    -- lines and textPoint, and shaped (the last shapes table; nil: the
    -- arrow is drawn from its pictures), tipLines (the tooltip's lines;
    -- nil: none) and menuItems (the open menu's rows; nil: closed).
    c.arrows = {}
    function c.arrow(spec)
        if s.noFrames then return nil end
        local h = { spec = spec, shown = false, lookIs = "pointer", draws = 0, lines = {} }
        local moved, clicked, hovered, pick
        function h.place(point)
            if type(point) ~= "table" then return end
            h.point, h.attached = { point[1], point[2], point[3], point[4] }, nil
        end
        function h.attach(other) h.attached, h.point = other, nil end
        function h.show(on)
            h.shown = on and true or false
            -- As the client: a hidden arrow keeps no menu and no tooltip.
            if not h.shown then h.menuItems, pick, h.tipLines = nil, nil, nil end
        end
        function h.look(look) h.lookIs = look == "needle" and "needle" or "pointer" end
        function h.draw(d) h.drawn, h.draws = d, h.draws + 1 end
        function h.shapes(shapes) h.shaped = shapes end
        function h.canShapes() return not s.noLines end
        function h.scale(n) h.scaled = n end
        function h.alpha(n) h.faded = n end
        function h.behind(on) h.under = on and true or false end
        function h.text(lines, point)
            h.lines = {}
            for i = 1, #(type(lines) == "table" and lines or {}) do h.lines[i] = tostring(lines[i]) end
            h.textPoint = (#h.lines > 0 and type(point) == "table") and { point[1], point[2], point[3], point[4] } or nil
        end
        function h.onMoved(fn) moved = fn end
        function h.onClick(fn) clicked = type(fn) == "function" and fn or nil end
        function h.onHover(fn) hovered = type(fn) == "function" and fn or nil end
        function h.tip(lines)
            local out = {}
            for i = 1, #(type(lines) == "table" and lines or {}) do out[i] = tostring(lines[i]) end
            h.tipLines = #out > 0 and out or nil
        end
        function h.menu(items, fn)
            if type(items) ~= "table" or #items == 0 then
                h.menuItems, pick = nil, nil
                return
            end
            h.menuItems, pick = items, type(fn) == "function" and fn or nil
        end
        -- The test's controls. click: a button let go over the arrow
        -- ("left", "right", or anything else to see it ignored). hover: the
        -- pointer comes (true) or goes. choose: the player clicks the menu
        -- row with this key; the menu closes first, as on the client. The
        -- fake does not refuse a row that is not offered: the caller must.
        -- As the client (Core/Client.lua, OnMouseUp, OnEnter, OnLeave): an
        -- arrow under the other one hears no click and no hover.
        function h.click(button)
            if clicked and not h.under then clicked(button) end
        end
        function h.hover(on)
            if hovered and not h.under then hovered(on and true or false) end
        end
        function h.choose(key)
            local fn = pick
            h.menuItems, pick = nil, nil
            if fn then fn(key) end
        end
        -- The test's control: h.held = true while the player holds it.
        function h.dragging() return h.held == true end
        -- The test's control: the player let the arrow go at this point.
        -- Without the move key (c.setMoveKey(false)) no drag started:
        -- nothing moves and nothing is told.
        function h.drag(point)
            if s.noMoveKey then return end
            h.point, h.attached = { point[1], point[2], point[3], point[4] }, nil
            if moved then moved({ point[1], point[2], point[3], point[4] }) end
        end
        c.arrows[#c.arrows + 1] = h
        return h
    end

    -- the test's controls
    -- The player presses Escape: an open arrow menu closes and nothing is
    -- chosen. -> true when a menu closed (the key was taken, as the game
    -- does for a listed frame that is shown), false when none was open.
    function c.escape()
        local taken = false
        for i = 1, #c.arrows do
            local h = c.arrows[i]
            if h.menuItems ~= nil then
                h.menu(nil)
                taken = true
            end
        end
        return taken
    end
    -- nil: the client will not say how big the screen is.
    function c.setScreen(w, h) s.screen = (w and h) and { w, h } or nil end
    function c.setVersion(text) s.version = text end
    -- Internal switches for the tests only (opts.internal = { name = true }):
    -- the feedback, paused by lead section 284, answers on here. The game
    -- client has no such call.
    local internal = type(opts.internal) == "table" and opts.internal or {}
    function c.internal(name) return internal[name] == true end
    -- false: a client that cannot make frames (panel() answers nil).
    function c.setFrames(on) s.noFrames = not on end
    -- false: a client where a closable panel gets neither a close button
    -- nor the Escape route (panel() answers a handle with no onClose).
    function c.setCloseRoute(on) s.noCloseRoute = not on end
    -- false: a client that will not say the time (uptime() nil, now() 0).
    function c.setTime(on) s.noTime = not on end
    -- What listenFaults() answers: an event the client refused, and (false)
    -- an event frame that was not made. Events still fire here either way.
    function c.setEventFault(event, on) s.eventFaults[event] = on and true or nil end
    function c.setEventFrame(on) s.noEventFrame = not on end
    -- false: listenFaults() says the tick frame was not made. Frames still
    -- tick here either way.
    function c.setTickFrame(on) s.noTickFrame = not on end
    -- false: a client that draws no lines (an arrow's canShapes() is false).
    function c.setLines(on) s.noLines = not on end
    -- The key that lets an arrow be dragged (Ctrl): held until told not.
    function c.setMoveKey(on) s.noMoveKey = not on end
    -- Moves the clock by `seconds`, drawing `frames` frames (default 1).
    function c.advance(seconds, frames)
        frames = frames or 1
        local t0 = s.t
        for i = 1, frames do
            s.t = t0 + seconds * i / frames
            ticks.call("frame", seconds / frames)
            if repeatFrame then repeatFrame() end
        end
    end
    function c.fire(event, ...) events.call(event, ...) end
    -- P-READS: plays the real client handing on a secret event argument:
    -- each argument that is c.SECRET reaches the listeners as nil.
    function c.fireSecret(event, ...)
        local n = select("#", ...)
        local args = { ... }
        for i = 1, n do
            if rawequal(args[i], c.SECRET) then args[i] = nil end
        end
        events.call(event, unpack(args, 1, n))
    end
    -- What clock() gives; nil: the client will not say. advance() does not
    -- move it.
    function c.setClock(seconds) s.clock = seconds end
    function c.setCombat(on)
        on = on and true or false
        if on == s.combat then return end
        s.combat = on
        events.call(on and "PLAYER_REGEN_DISABLED" or "PLAYER_REGEN_ENABLED")
    end
    function c.setLoaded(name, on) s.loaded[name] = on and true or nil end
    function c.setSaved(name, tbl) s.saved[name] = tbl end
    -- Each takes nil for "unknown".
    function c.setMoney(copper) s.money = copper end
    function c.setBags(rows) s.bags = copyRows(rows) end
    function c.setBagItems(stacks) s.bagItems = copyRows(stacks) end
    -- What the bank holds; bankItems() gives it only while the bank is open.
    function c.setBank(stacks) s.bank = copyRows(stacks) end
    -- true / false fire the bank event; nil is "not known" and fires nothing.
    function c.setBankOpen(on)
        if on == nil then s.bankOpen = nil return end
        on = on and true or false
        if on == s.bankOpen then return end
        s.bankOpen = on
        events.call(on and "BANKFRAME_OPENED" or "BANKFRAME_CLOSED")
    end
    -- What the merchant has on sale, in the shape of merchantItems():
    -- { { index =, item =, price =, stack =, other = }, ... }; nil for a
    -- window that cannot be read. merchantItems() gives it only while the
    -- window is open.
    function c.setMerchant(rows) s.merchant = copyRows(rows) end
    -- G3: the merchant's Buyback tab, in the shape of returnableItems():
    -- { { index =, item =, name =, price =, count = }, ... }; nil for a tab
    -- that cannot be read. returnableItems() gives it only while the window is
    -- open.
    function c.setReturnable(rows) s.buyback = copyRows(rows) end
    -- true / false fire the merchant event; nil is "not known" and fires nothing.
    function c.setMerchantOpen(on)
        if on == nil then s.merchantOpen = nil return end
        on = on and true or false
        if on == s.merchantOpen then return end
        s.merchantOpen = on
        events.call(on and "MERCHANT_SHOW" or "MERCHANT_CLOSED")
    end
    -- The open profession window: { profession =, skill =, max =,
    -- recipes = { { id =, name =, learned = }, ... } }; nil for none.
    function c.setRecipes(r) s.recipes = r end
    -- One recipe's schematic: { makes =, yield =, mats = { [item] = n } };
    -- nil: the client can't read it.
    function c.setRecipeSchematic(id, r)
        s.schematics = s.schematics or {}
        s.schematics[id] = r
    end
    -- One trade skill row's schematic (section 231), as above; nil: the
    -- client can't read it.
    function c.setTradeSkillSchematic(index, r)
        s.tradeSchematics = s.tradeSchematics or {}
        s.tradeSchematics[index] = r
    end
    -- The classic window's rows (section 233): { name =, rows = { { index =,
    -- name = } } }; nil: no classic window answers. Section 245 (RB2-2):
    -- collapsed = true / filtered = true say the window hid rows; whole =
    -- true says the rows are every learned recipe (the real client does not
    -- say so yet). Left out: unknown, and RecipeBook drops nothing.
    function c.setTradeSkillRows(r) s.tradeRows = r end
    -- N24: the tools one classic row needs, { { name =, has = } }; nil: the
    -- client can not read them.
    function c.setTradeSkillTools(index, list)
        s.tradeTools = s.tradeTools or {}
        s.tradeTools[index] = list
    end
    -- One spell's answers: { known =, usable =, noPower = }; a field left
    -- out reads as not known.
    function c.setSpell(id, row)
        s.spells = s.spells or {}
        s.spells[id] = row and { known = row.known, usable = row.usable, noPower = row.noPower,
            name = row.name } or nil
    end
    function c.setSpellId(name, id)
        s.spellIds = s.spellIds or {}
        s.spellIds[name] = id
    end
    -- nil: the client gives no texture for this spell.
    function c.setSpellTexture(id, tex)
        s.spellTextures = s.spellTextures or {}
        s.spellTextures[id] = tex
    end
    -- The open trainer window: { profession = name or nil, npc = name };
    -- nil for closed or not known.
    -- { profession, npc, services, filter }; services and filter as the real
    -- client gives them (F8). The table is kept as given; trainer() copies.
    -- F7 probe: which dotted paths apiPresent answers true for, and the
    -- UNIT_COMBAT watchers; unitCombat(unit, readable) plays one event.
    function c.setApi(path, on)
        s.apis = s.apis or {}
        s.apis[path] = on and true or nil
    end
    function c.apiPresent(path) return (s.apis and s.apis[path]) == true end
    function c.watchUnitCombat(fn)
        if type(fn) ~= "function" then return nil end
        s.unitCombat = s.unitCombat or {}
        table.insert(s.unitCombat, fn)
        return function()
            for i = #s.unitCombat, 1, -1 do
                if s.unitCombat[i] == fn then table.remove(s.unitCombat, i) end
            end
        end
    end
    function c.unitCombat(unit, readable)
        for _, fn in ipairs({ unpack(s.unitCombat or {}) }) do fn(unit, readable and true or false) end
    end
    -- Settings controls: the game's Options page, as the real client's
    -- optionsPage. setOptionsPage(false) plays a client with no route.
    -- optionsRows(), optionsStatus() and optionsAct(key, value) let a test
    -- read what was drawn and play a control being changed.
    function c.setOptionsPage(on) s.noOptionsPage = (on == false) end
    function c.optionsPage(spec)
        if s.noOptionsPage then return nil end
        local h, showFns = {}, {}
        s.options = { title = spec and spec.title, opened = 0, shown = false }
        function h.open()
            s.options.opened = s.options.opened + 1
            s.options.shown = true
            for _, fn in ipairs(showFns) do fn() end
            return true
        end
        function h.onShow(fn) showFns[#showFns + 1] = fn end
        function h.shown() return s.options.shown end
        function h.draw(rows, act)
            local copy = {}
            for i, r in ipairs(rows or {}) do
                local row = {}
                for k2, v in pairs(r) do row[k2] = v end
                copy[i] = row
            end
            s.options.rows, s.options.act = copy, act
            return true
        end
        function h.status(text) s.options.status = text end
        return h
    end
    function c.optionsRows() return s.options and s.options.rows end
    function c.optionsStatus() return s.options and s.options.status end
    function c.optionsOpened() return s.options and s.options.opened or 0 end
    function c.optionsHide() if s.options then s.options.shown = false end end
    function c.optionsAct(key, value)
        if s.options and type(s.options.act) == "function" then return s.options.act(key, value) end
    end
    -- Lead section 410: the twin of c.optionsNative, the add-on's settings
    -- as the game's own rows. Off until setOptionsNative(true): a client
    -- with no such rows is the start, as nothing shows 16001 has them.
    --   c.nativeOptions() -> { title, rows, topics, opened = { topic id or
    --     false, ... } } or nil; c.nativeRow(key) -> the row of that key
    --   c.nativeSet(key, value) -> plays the player changing the row: false
    --     when the row's `can` says no, else what its set gave
    --   c.nativePress(label) -> true when a button row of that label ran
    function c.setOptionsNative(on) s.nativeOn = (on == true) end
    function c.optionsNative(spec)
        if not s.nativeOn or type(spec) ~= "table" then return nil end
        local n = 0
        local function count(rows)
            for _, r in ipairs(rows or {}) do
                if r.kind ~= "header" then n = n + 1 end
            end
        end
        count(spec.rows)
        for _, topic in ipairs(spec.topics or {}) do count(topic.rows) end
        if n == 0 then return nil end
        s.native = { title = spec.title, rows = spec.rows or {}, topics = spec.topics or {}, opened = {} }
        local h = {}
        function h.open(topicId)
            if s.nativeOpenFails then return false end
            s.native.opened[#s.native.opened + 1] = topicId or false
            return true
        end
        function h.count() return n end
        function h.order() return "new" end
        return h
    end
    function c.setNativeOpenFails(on) s.nativeOpenFails = (on == true) end
    function c.nativeOptions() return s.native end
    local function nativeEach(fn)
        if not s.native then return nil end
        for _, r in ipairs(s.native.rows) do
            local got = fn(r)
            if got ~= nil then return got end
        end
        for _, topic in ipairs(s.native.topics) do
            for _, r in ipairs(topic.rows or {}) do
                local got = fn(r, topic)
                if got ~= nil then return got end
            end
        end
        return nil
    end
    function c.nativeRow(key)
        return nativeEach(function(r) if r.key == key and r.kind ~= "button" then return r end end)
    end
    function c.nativeSet(key, value)
        local r = c.nativeRow(key)
        if not r then return nil end
        if type(r.can) == "function" and r.can() ~= true then return false end
        return r.set(value)
    end
    function c.nativePress(label)
        local r = nativeEach(function(row) if row.kind == "button" and row.label == label then return row end end)
        if not r then return false end
        r.run()
        return true
    end
    -- S28 sound restart: setSound{ ways = { name, ... }, fail = text or nil,
    -- noEvent = true } and speakersChanged() to play the game's event.
    -- restarted() counts the restarts made, with byHand for each.
    function c.setSound(cfg) s.sound = cfg or {} end
    function c.soundWays() return (s.sound and s.sound.ways) or {} end
    function c.restartSound(byHand)
        s.restarts = s.restarts or {}
        local cfg = s.sound or {}
        if cfg.fail then return false, cfg.fail end
        local ways = cfg.ways or {}
        if #ways == 0 then return false, "this game gives add-ons no way to restart its sound" end
        s.restarts[#s.restarts + 1] = { byHand = byHand == true }
        return true, ways[1]
    end
    function c.restarted() return s.restarts or {} end
    function c.watchSoundDevices(fn)
        if type(fn) ~= "function" or (s.sound and s.sound.noEvent) then return nil end
        s.soundWatchers = s.soundWatchers or {}
        table.insert(s.soundWatchers, fn)
        return true
    end
    function c.speakersChanged()
        for _, fn in ipairs(s.soundWatchers or {}) do fn() end
    end
    function c.setTrainer(r)
        s.trainer = r and { profession = r.profession, npc = r.npc, services = r.services, filter = r.filter } or nil
    end
    -- "Horde", "Alliance", or nil for not known.
    function c.setFaction(group) s.faction = group end
    -- The class token ("DRUID"), or nil for not known.
    function c.setClass(token) s.class = token end
    -- Stealthed: true, false, or nil for not known (the start).
    function c.setStealthed(on)
        if on == nil then s.stealthed = nil else s.stealthed = on and true or false end
    end
    -- Your target: { exists = true or false, hostile = ..., dead = ... },
    -- or nil for not known (the start). hostile and dead are true, false,
    -- or left out for not known; with exists false they are dropped.
    function c.setTarget(r)
        if type(r) ~= "table" or type(r.exists) ~= "boolean" then
            s.target = nil
            return
        end
        local function yesNo(v) if type(v) == "boolean" then return v end return nil end
        s.target = { exists = r.exists, hostile = yesNo(r.hostile), dead = yesNo(r.dead) }
    end
    -- Whether one spell reaches the target: true, false, or nil for not
    -- known. A spell never set is not known.
    function c.setInRange(id, on)
        s.ranges = s.ranges or {}
        if on == nil then s.ranges[id] = nil else s.ranges[id] = on and true or false end
    end
    -- Gear, for gear(): nothing is known until set.
    -- One item by its link: { kind, stats }; nil takes it back. The stats
    -- are copied.
    function c.setItem(link, item)
        s.items = s.items or {}
        if type(item) ~= "table" then
            s.items[link] = nil
            return
        end
        s.items[link] = { kind = item.kind, stats = copyFlat(item.stats),
                          classID = item.classID, subclassID = item.subclassID, minLevel = item.minLevel,
                          unmet = copyFlat(item.unmet), speed = item.speed }
    end
    -- Your level for level(): a number, or nil for not known (the start).
    function c.setLevel(n) s.level = n end
    -- Plays the game filling its item tooltip for `link`: every onItemTooltip
    -- listener is told, and what they added comes back as
    -- { { text, r, g, b } ... }.
    function c.showItemTooltip(link)
        local added = {}
        local function add(text, r, g, b) added[#added + 1] = { text = text, r = r, g = g, b = b } end
        for _, fn in ipairs({ unpack(s.tooltipListeners or {}) }) do fn(link, add) end
        return added
    end
    -- What one inventory slot holds: a link (an item worn), false (read and
    -- empty), or nil (not read).
    function c.setWorn(slot, link)
        s.worn = s.worn or {}
        s.worn[slot] = link
    end
    -- Dual wield: true, false, or anything else for not known.
    function c.setDualWield(on)
        if type(on) == "boolean" then s.dualWield = on else s.dualWield = nil end
    end
    -- One spell's cooldown: true (on cooldown), false (ready), nil for
    -- not known. A spell never set is not known.
    function c.setSpellCooldown(id, on)
        s.cooldowns = s.cooldowns or {}
        s.cooldowns[id] = on
    end
    -- Seconds left on one spell's cooldown; nil for not known. A spell
    -- never set is not known.
    function c.setSpellCooldownLeft(id, left)
        s.cooldownLeft = s.cooldownLeft or {}
        s.cooldownLeft[id] = left
    end
    -- Radians, 0 = north; nil for not known.
    function c.setFacing(f) s.facing = f end
    -- The quest log rows as client.questLog() gives them; nil: not known.
    function c.setQuestLog(rows) s.questLog = rows end
    -- The quest the player picked out, and the watch list ({ id, ... }), as
    -- client.questFocus() gives them. Both nil: no such read on this client.
    -- quest nil with a list: a read, and no quest picked out.
    function c.setQuestFocusReads(reads) s.questFocusReads = reads end
    function c.setQuestFocus(quest, watched)
        if quest == nil and watched == nil then s.questFocus = nil return end
        s.questFocus = { quest = quest, watched = watched }
    end
    -- A Questie module by name; mod nil takes it away. With none set,
    -- Questie is not there.
    function c.setQuestieModule(name, mod)
        s.questie = s.questie or {}
        s.questie[name] = mod
    end
    -- { size, radius, rotates, square } as client.minimap() gives it; a
    -- field left out is not known. nil: no minimap.
    function c.setMinimap(r) s.minimap = r end
    -- Item facts by item ID, each as client.itemInfo() gives it; nil: the
    -- client says nothing about any item.
    function c.setItemInfo(map) s.itemInfo = map end
    -- Section 226 (CF-30): an item's tooltip text and icon by item ID, as
    -- client.itemLines() and client.itemTexture() give them; nil: not read.
    function c.setItemLines(id, lines)
        s.itemLines = s.itemLines or {}
        s.itemLines[id] = type(lines) == "table" and lines or nil
    end
    function c.itemLines(item)
        local id = ns.Items and ns.Items.Id(item) or item
        local lines = s.itemLines and s.itemLines[id] or nil
        if type(lines) ~= "table" then return nil end
        local out = {}
        for i = 1, #lines do out[i] = lines[i] end
        return out
    end
    function c.setItemTexture(id, tex)
        s.itemTextures = s.itemTextures or {}
        s.itemTextures[id] = tex
    end
    function c.itemTexture(item)
        local id = ns.Items and ns.Items.Id(item) or item
        return s.itemTextures and s.itemTextures[id] or nil
    end
    -- { [slot] = { cur =, max = } } as client.durability() gives it; nil:
    -- not known.
    function c.setDurability(readings) s.durability = readings end
    -- fn(line) answering item, count for the player's own loot line and nil
    -- for any other; nil: whose loot a line is cannot be told.
    function c.setOwnLoot(fn) s.ownLoot = fn end
    -- { source =, items = } as client.lootWindow() gives it; nil: not known.
    -- It fires nothing: a test fires the loot event itself.
    function c.setLootWindow(r) s.lootWindow = r end
    -- A map's width and height in yards; leave both out for not known.
    function c.setMapSize(map, w, h)
        s.mapSizes = s.mapSizes or {}
        s.mapSizes[map] = w and h and { w = w, h = h } or nil
    end
    -- A map's continent number; leave it out for not known.
    function c.setMapCont(map, cont)
        s.mapConts = s.mapConts or {}
        s.mapConts[map] = cont
    end
    function c.setZone(cont, zone)
        s.zone = (cont ~= nil or zone ~= nil) and { cont = cont, zone = zone } or nil
    end
    function c.setPosition(map, x, y)
        s.position = map and { map = map, x = x, y = y } or nil
    end
    -- Dead or a ghost: true or false; nil for not known.
    function c.setDead(v)
        if v == nil then s.dead = nil else s.dead = v and true or false end
    end
    -- A ghost: true or false; nil for not known.
    function c.setGhost(v)
        if v == nil then s.ghost = nil else s.ghost = v and true or false end
    end
    -- The corpse, as shares of a map; false for "the client answered: on no
    -- position of the player's map"; leave the map out for not known.
    function c.setCorpse(map, x, y)
        if map == false then
            s.corpse = false
            return
        end
        s.corpse = map and { map = map, x = x, y = y } or nil
    end
    -- The player's own map waypoint, as shares of a map; leave the map out
    -- for none set.
    function c.setWaypoint(map, x, y)
        s.waypoint = map and { map = map, x = x, y = y } or nil
    end
    -- Until this is called the lock follows setCombat. nil: not known.
    function c.setLockdown(on)
        s.lockdownSet = true
        if on == nil then s.lockdown = nil else s.lockdown = on and true or false end
    end
    -- Work that takes `ms` milliseconds: moves only the fine clock.
    function c.burn(ms) s.ms = s.ms + ms end
    -- Sorted names of the events something listens to.
    function c.events()
        local out = {}
        for event in pairs(s.listening) do out[#out + 1] = event end
        table.sort(out)
        return out
    end
    -- True while something is subscribed to the frame tick.
    function c.ticking() return s.frames == 1 end

    -- F9 window buttons: the same read as Core/Client.lua. A window is
    -- there only when a test says so: c.setWindow(frameName, { protected =
    -- true / false / "unsaid", shown = true / false }); protected left out
    -- is a plain no, shown left out is not said.
    -- c.setWindow(frameName, false) takes it away. Every button
    -- made is in c.windowButtons, in order: .frame, .spec, .shown.
    -- click() is the control of the test: the player clicked it (nothing
    -- on a button that is not shown).
    -- Section 142: w.parts = { field name, ... } says which parts the
    -- window has; left out, it has every part asked for. A button asked
    -- for with spec.inside gets h.placedOn, or is not made when the
    -- window has none of the parts named.
    c.windowButtons = {}
    local gameWindows = {}
    function c.setWindow(frameName, w)
        if w == false then gameWindows[frameName] = nil return end
        gameWindows[frameName] = type(w) == "table" and w or {}
    end
    local function fakeProtected(w)
        if w.protected == nil or w.protected == false then return false end
        if w.protected == true then return true end
        return nil
    end
    function c.windowState(frameName)
        local w = gameWindows[frameName]
        if not w then return nil end
        local shown = w.shown
        if type(shown) ~= "boolean" then shown = nil end
        return { shown = shown, protected = fakeProtected(w) }
    end
    function c.windowButton(frameName, spec)
        if type(spec) ~= "table" then return nil, "bad ask" end
        local w = gameWindows[frameName]
        if not w then return nil, "no window" end
        if c.inCombat() ~= false then return nil, "in combat" end
        local protected = fakeProtected(w)
        if protected == nil then return nil, "its window will not say whether it is protected" end
        if protected then return nil, "its window is protected" end
        local placedOn
        if type(spec.inside) == "table" then
            for _, field in ipairs(spec.inside) do
                local there = w.parts == nil
                for _, part in ipairs(type(w.parts) == "table" and w.parts or {}) do
                    if part == field then there = true end
                end
                if there and type(field) == "string" then placedOn = field break end
            end
            if placedOn == nil then return nil, "its place inside the window was not found" end
        end
        if s.noFrames then return nil, "no frame" end
        local h = { frame = frameName, spec = spec, shown = false, placedOn = placedOn }
        function h.visible()
            local now = gameWindows[frameName]
            if not now or type(now.shown) ~= "boolean" then return nil end
            return h.shown and now.shown
        end
        local clicked, clickFailed
        function h.onClick(fn, failed)
            clicked = type(fn) == "function" and fn or nil
            clickFailed = type(failed) == "function" and failed or nil
        end
        function h.show(on) h.shown = on and true or false end
        function h.click()
            if not h.shown or not clicked then return end
            local ok, err = pcall(clicked)
            if not ok and clickFailed then clickFailed(err) end
        end
        c.windowButtons[#c.windowButtons + 1] = h
        return h
    end

    -- F6, the rotation helper. form(): what setForm gave (a number, or nil
    -- for not known: the start). petBattle() and vehicle(): true, false, or
    -- nil for not known (the start).
    function c.form() return s.form end
    function c.setForm(n) s.form = type(n) == "number" and n or nil end
    function c.petBattle() return s.petBattle end
    function c.setPetBattle(on)
        if on == nil then s.petBattle = nil else s.petBattle = on and true or false end
    end
    function c.vehicle() return s.vehicle end
    function c.setVehicle(on)
        if on == nil then s.vehicle = nil else s.vehicle = on and true or false end
    end
    -- Every secure button made is in c.secureButtons, in order: .spec and
    -- .attrs (what it holds). set refuses with "lockdown" while
    -- combatLockdown() is not false (it follows setCombat / setLockdown).
    -- failSecureAttr(attr, true): setting that one is "refused".
    -- dropSecureAttr(attr, true): setting it answers true and keeps nothing.
    -- Section 246 (N63-E): every set asked for, kept or refused, is logged
    -- in order: h.given = { { attr, value } } on the button, and
    -- c.secureGiven = { { name, attr, value } } over every button.
    -- c.secureMacros() lists the rows of c.secureGiven that make a button
    -- a macro: a type attribute ("type", "*type-alt", "shift-type1", ...)
    -- given "macro", or a macro or macro text attribute ("macro",
    -- "macrotext", "*macrotext-alt", ...) given a value. Section 249 (CT-2):
    -- names and values are compared lower-cased, so "MACRO" is caught too.
    -- A macro-type
    -- secure button does not act on this client (the press arrives with the
    -- right macro and nothing is cast), so no Z-Flow button may be one.
    c.secureButtons = {}
    c.secureGiven = {}
    local secureFail, secureDrop = {}, {}
    function c.secureButton(spec)
        if s.noFrames then return nil end
        local h = { spec = spec, attrs = {}, given = {} }
        function h.set(attr, value)
            h.given[#h.given + 1] = { attr = attr, value = value }
            c.secureGiven[#c.secureGiven + 1] = {
                name = type(spec) == "table" and spec.name or nil, attr = attr, value = value }
            if c.combatLockdown() ~= false then return false, "lockdown" end
            if secureFail[attr] then return false, "refused" end
            if not secureDrop[attr] then h.attrs[attr] = value end
            return true
        end
        function h.get(attr) return h.attrs[attr] end
        c.secureButtons[#c.secureButtons + 1] = h
        return h
    end
    function c.failSecureAttr(attr, on) secureFail[attr] = on and true or nil end
    function c.secureMacros()
        local out = {}
        for _, g in ipairs(c.secureGiven) do
            local attr = string.lower(tostring(g.attr))
            local value = type(g.value) == "string" and string.lower(g.value) or g.value
            local isType = attr:find("type", 1, true) ~= nil
            if (isType and value == "macro")
                or (not isType and attr:find("macro", 1, true) and g.value ~= nil) then
                out[#out + 1] = g
            end
        end
        return out
    end
    function c.dropSecureAttr(attr, on) secureDrop[attr] = on and true or nil end

    -- F2 errand stops: the same reads as Core/Client.lua, set by a test.
    local guids = {}
    function c.guid(unit)
        if unit ~= "player" and unit ~= "pet" and unit ~= "target" then return nil end
        return guids[unit]
    end
    function c.setGuid(unit, id) guids[unit] = type(id) == "string" and id ~= "" and id or nil end
    function c.playerGUID() return c.guid("player") end
    function c.petGUID() return c.guid("pet") end
    function c.serviceNpc()
        local n = s.serviceNpc
        return n and { guid = n.guid, name = n.name } or nil
    end
    function c.setServiceNpc(guid, name)
        if guid == nil and name == nil then s.serviceNpc = nil return end
        s.serviceNpc = { guid = guid, name = name }
    end
    function c.merchantRepairs() return s.merchantRepairs end
    function c.setMerchantRepairs(v)
        if v == true or v == false then s.merchantRepairs = v else s.merchantRepairs = nil end
    end
    -- Copper, or nil for not known; given only at a merchant that repairs.
    function c.repairCost()
        if s.merchantRepairs ~= true then return nil end
        return s.repairCost
    end
    function c.setRepairCost(v)
        if type(v) == "number" and v >= 0 and v == math.floor(v) then s.repairCost = v else s.repairCost = nil end
    end
    function c.bindLocation() return s.bindLocation end
    function c.setBindLocation(name) s.bindLocation = type(name) == "string" and name ~= "" and name or nil end
    function c.hearthCooldown() return s.hearthCooldown end
    function c.setHearthCooldown(v) s.hearthCooldown = type(v) == "number" and v >= 0 and v or nil end

    -- F7, the fight log. guid(unit): what setGuid gave for "player", "pet"
    -- or "target" (nil, the start: not known); any other unit is nil.
    -- targetRank(): what setTargetRank gave. watchCombatLog(fn) answers
    -- true and combatLog(...) hands its values to every watcher; after
    -- setCombatLog(false) it answers nil and takes no watcher (the event
    -- not taken); after setCombatLog("none") it answers nil and "no log"
    -- (the client has no combat-log read).
    -- guid, setGuid, playerGUID and petGUID are above, with the errand reads.
    local logWatchers = {}
    function c.targetRank() return s.targetRank end
    function c.setTargetRank(rank) s.targetRank = type(rank) == "string" and rank ~= "" and rank or nil end
    function c.watchCombatLog(fn)
        if type(fn) ~= "function" then return nil end
        if s.combatLog == "none" then return nil, "no log" end
        if s.combatLog == false then return nil end
        logWatchers[#logWatchers + 1] = fn
        return true
    end
    function c.setCombatLog(on)
        if on == "none" then s.combatLog = "none" else s.combatLog = on and true or false end
    end
    -- Slash commands another addon owns: setSlashTaken(command, on) says
    -- so, slashTaken answers as the real boundary does, and unslash gives a
    -- command back.
    local slashTags, slashOthers = {}, {}
    local plainSlash = c.slash
    function c.slash(tag, command, fn)
        slashTags[tag] = command
        return plainSlash(tag, command, fn)
    end
    function c.setSlashTaken(command, on) slashOthers[command] = on and true or nil end
    function c.slashTaken(command, ownTag)
        if type(command) ~= "string" then return nil end
        if slashOthers[command] then return true end
        for tag, held in pairs(slashTags) do
            if tag ~= ownTag and held == command then return true end
        end
        return false
    end
    function c.unslash(tag)
        local command = slashTags[tag]
        if command == nil then return false end
        slashTags[tag] = nil
        c.slashes[command] = nil
        return true
    end
    function c.combatLog(...)
        for i = 1, #logWatchers do logWatchers[i](...) end
    end

    -- S29 alignment guides. setFrameRect(name, rect or nil); the screen is
    -- setScreen's, above; watchMoves takes callbacks for a name that has a
    -- rect set (any other name: nil, as the client with no such frame);
    -- moveFrame(name, rect) calls onMove, dropFrame(name, rect) calls onDrop
    -- and answers its dx, dy. guideLines() keeps every show in guideShows()
    -- ({ x, ylo, yhi, y, xlo, xhi }) and whether they are up in guidesUp().
    local frameRects, moveWatch, guideShows, guidesUp = {}, {}, {}, false
    function c.setFrameRect(name, rect) frameRects[name] = rect end
    function c.frameRect(name)
        local r = frameRects[name]
        if type(r) ~= "table" then return nil end
        return { l = r.l, r = r.r, b = r.b, t = r.t, dockedTo = r.dockedTo }
    end
    function c.watchMoves(name, onMove, onDrop)
        if type(frameRects[name]) ~= "table" then return nil end
        moveWatch[name] = { onMove = onMove, onDrop = onDrop }
        return true
    end
    function c.watched(name) return moveWatch[name] ~= nil end
    function c.moveFrame(name, rect)
        local w = moveWatch[name]
        if w and type(w.onMove) == "function" then w.onMove(rect) end
    end
    function c.dropFrame(name, rect)
        local w = moveWatch[name]
        if w and type(w.onDrop) == "function" then return w.onDrop(rect) end
        return nil
    end
    function c.guideLines()
        if s.noGuideLines then return nil end
        return {
            show = function(...) guideShows[#guideShows + 1] = { ... }; guidesUp = true end,
            hide = function() guidesUp = false end,
        }
    end
    function c.setGuideLines(on) s.noGuideLines = not on end
    function c.guideShows() return guideShows end
    function c.guidesUp() return guidesUp end
    -- S20 merchant button marks. markMerchantButtons keeps the item numbers
    -- it was given (merchantMarked()) and answers how many, or nil (and
    -- keeps none) while no merchant is open. merchantRedraw() calls every
    -- onMerchantRedraw listener, as the window drawing a new page would.
    local merchantRedrawFns, merchantMarkedNow = {}, nil
    function c.markMerchantButtons(indexes)
        if s.merchantOpen ~= true then
            merchantMarkedNow = nil
            return nil
        end
        merchantMarkedNow = {}
        local n = 0
        for index, on in pairs(type(indexes) == "table" and indexes or {}) do
            if on then
                merchantMarkedNow[index] = true
                n = n + 1
            end
        end
        return n
    end
    function c.merchantMarked() return merchantMarkedNow end
    function c.onMerchantRedraw(fn)
        if type(fn) ~= "function" then return nil end
        merchantRedrawFns[#merchantRedrawFns + 1] = fn
        return true
    end
    function c.merchantRedraw()
        for _, fn in ipairs({ unpack(merchantRedrawFns) }) do fn() end
    end

    -- S35: worldPosition() and onTaxi(), both unknown (nil) until set.
    --   c.setWorldPosition(cont, wx, wy)   c.setWorldPosition(nil): not known
    --   c.setOnTaxi(true / false)          c.setOnTaxi(nil): not known
    function c.worldPosition()
        local w = s.world
        if not w then return nil end
        return { cont = w.cont, wx = w.wx, wy = w.wy }
    end
    function c.setWorldPosition(cont, wx, wy)
        s.world = cont ~= nil and { cont = cont, wx = wx, wy = wy } or nil
    end
    function c.onTaxi() return s.onTaxi end
    function c.setOnTaxi(v)
        if v == nil then s.onTaxi = nil else s.onTaxi = v and true or false end
    end

    -- Every slot icon made (S13) is in c.slotIcons, in order: .spec, .shown,
    -- .texture, .point, .places, .marked ({ r, g, b } or nil).
    c.slotIcons = {}
    function c.slotIcon(spec)
        if s.noFrames then return nil end
        local h = { spec = spec, shown = false, places = 0 }
        function h.setTexture(tex)
            h.texture = tex
            return tex ~= nil
        end
        function h.place(point)
            if type(point) ~= "table" then return end
            h.point = { point[1], point[2], point[3], point[4] }
            h.places = h.places + 1
        end
        function h.show(on) h.shown = on and true or false end
        function h.mark(r, g, b)
            if type(r) == "number" and type(g) == "number" and type(b) == "number" then
                h.marked = { r, g, b }
                return true
            end
            h.marked = nil
            return false
        end
        c.slotIcons[#c.slotIcons + 1] = h
        return h
    end
    -- modifiers(): what setModifiers gave (ctrl, shift, alt); nil each until
    -- told: not known.
    function c.modifiers()
        local m = s.modifiers
        if not m then return nil, nil, nil end
        return m[1], m[2], m[3]
    end
    function c.setModifiers(ctrl, shift, alt) s.modifiers = { ctrl, shift, alt } end

    -- S4 auction prices. setRealm(name or nil). watchAuctionResults takes
    -- listeners (nil after setAuctionHouse(false)); auctionResult(id, row)
    -- tells them, as a search the player ran would.
    local auctionFns = {}
    function c.setRealm(name) s.realm = name end
    function c.realm() return s.realm end
    function c.setAuctionHouse(on) s.noAuctionHouse = not on end
    function c.watchAuctionResults(fn)
        if s.noAuctionHouse or type(fn) ~= "function" then return nil end
        auctionFns[#auctionFns + 1] = fn
        return true
    end
    function c.auctionResult(id, row)
        for _, fn in ipairs({ unpack(auctionFns) }) do fn(id, row) end
    end

    -- S17 group buff tooltip. As the real client's: onUnitTooltip(fn) ->
    -- cancel, fn(unit, add) for each unit tooltip shown with showUnitTooltip;
    -- unitInfo(unit) and unitBuff(unit, names) answer from what was set.
    function c.onUnitTooltip(fn)
        if type(fn) ~= "function" then return nil end
        s.unitTooltipListeners = s.unitTooltipListeners or {}
        table.insert(s.unitTooltipListeners, fn)
        return function()
            for i = #s.unitTooltipListeners, 1, -1 do
                if s.unitTooltipListeners[i] == fn then table.remove(s.unitTooltipListeners, i) end
            end
        end
    end
    -- A copy of what was set for the unit; nothing known for one not set.
    function c.unitInfo(unit)
        if type(unit) ~= "string" or unit == "" then return nil end
        local out = {}
        for key, value in pairs(s.units and s.units[unit] or {}) do out[key] = value end
        return out
    end
    -- Rows in order, as the real client reads them: a name that is no text
    -- (hidden) before a match is "not known"; buffs not set are not known.
    function c.unitBuff(unit, names)
        if type(unit) ~= "string" or unit == "" or type(names) ~= "table" then return nil end
        local rows = s.unitBuffs and s.unitBuffs[unit]
        if type(rows) ~= "table" then return nil end
        for i = 1, #rows do
            local row = rows[i]
            if type(row) ~= "table" or type(row.name) ~= "string" then return nil end
            for j = 1, #names do
                if names[j] == row.name then return true, row.left, row.name end
            end
        end
        return false
    end
    -- info: { exists, player, isSelf, friendly, class, role, power }, each
    -- left out for not known; nil forgets the unit.
    function c.setUnit(unit, info)
        s.units = s.units or {}
        s.units[unit] = info
    end
    -- rows: { { name = text or false for hidden, left = seconds, math.huge
    -- for no end, or nil } ... }; nil for a buff list that cannot be read.
    function c.setUnitBuffs(unit, rows)
        s.unitBuffs = s.unitBuffs or {}
        s.unitBuffs[unit] = rows
    end
    -- N64: the enchant on your weapons, in the shape Plexy's P-READS note
    -- names for the real read (item 5, not yet in Core/Client.lua):
    --   c.weaponEnchant() -> { main = { has, left, charges }, off = ... } or nil
    -- has true or false, left seconds (nil: not known), charges a number or
    -- nil; a hand not read is left out. setWeaponEnchant(nil): not read;
    -- setWeaponEnchantFails(true): the read raises.
    function c.weaponEnchant()
        if s.weaponEnchantFails then error("weapon enchant read failed (test)") end
        if type(s.weaponEnchant) ~= "table" then return nil end
        local out = {}
        for hand, row in pairs(s.weaponEnchant) do
            if type(row) == "table" then
                out[hand] = { has = row.has, left = row.left, charges = row.charges }
            end
        end
        return out
    end
    function c.setWeaponEnchant(t) s.weaponEnchant = t end
    function c.setWeaponEnchantFails(on) s.weaponEnchantFails = (on == true) end
    -- P-READS twins (lead section 260 item 1): each answers what a test set,
    -- and nil (not known) before. Shapes as on the real client:
    --   channel() -> { name, spellId, endsAt } | false | nil
    --   totems() -> { [slot] = { name, spellId, left } or false } | nil
    --   targetBuffs() -> { [name] = secondsLeft or true } | nil
    --   enemiesNear() -> near, close, onYou | nil
    --   plateCasts and plateEnemies: the class-b twins further down.
    --   creatureType(unit) -> text | nil
    --   buffLength(unit, names) -> the row field `length` of setUnitBuffs,
    --                              name | false | nil
    --   buffLength(unit, names, true): only a row whose field `caster` is
    --                              "player"; another caster passed over; a
    --                              caster not set or c.SECRET: nil, name
    local function copied(v)
        if type(v) ~= "table" then return v end
        local out = {}
        for k, x in pairs(v) do out[k] = copied(x) end
        return out
    end
    function c.channel() return copied(s.channel) end
    function c.setChannel(v) s.channel = v end
    function c.totems() return copied(s.totems) end
    function c.setTotems(v) s.totems = v end
    function c.targetBuffs() return copied(s.targetBuffs) end
    function c.setTargetBuffs(v) s.targetBuffs = v end
    function c.enemiesNear()
        local e = s.enemiesNear
        if type(e) ~= "table" then return nil end
        return e.near, e.close, e.onYou
    end
    function c.setEnemiesNear(near, close, onYou)
        if near == nil then s.enemiesNear = nil return end
        s.enemiesNear = { near = near, close = close, onYou = onYou }
    end
    function c.creatureType(unit)
        if type(s.creatureTypes) ~= "table" then return nil end
        return s.creatureTypes[unit]
    end
    function c.setCreatureType(unit, v)
        s.creatureTypes = s.creatureTypes or {}
        s.creatureTypes[unit] = v
    end
    function c.buffLength(unit, names, mine)
        if type(unit) ~= "string" or unit == "" or type(names) ~= "table" then return nil end
        local rows = s.unitBuffs and s.unitBuffs[unit]
        if type(rows) ~= "table" then return nil end
        for i = 1, #rows do
            local row = rows[i]
            if type(row) ~= "table" or type(row.name) ~= "string" then return nil end
            for j = 1, #names do
                if names[j] == row.name then
                    if mine ~= true then return row.length, row.name end
                    if type(row.caster) ~= "string" then return nil, row.name end
                    if row.caster == "player" then return row.length, row.name end
                end
            end
        end
        return false
    end
    -- Plays the game filling its tooltip for `unit`: every onUnitTooltip
    -- listener is told, and what they added comes back as
    -- { { text, r, g, b } ... }.
    function c.showUnitTooltip(unit)
        local added = {}
        local function add(text, r, g, b) added[#added + 1] = { text = text, r = r, g = g, b = b } end
        for _, fn in ipairs({ unpack(s.unitTooltipListeners or {}) }) do fn(unit, add) end
        return added
    end

    -- S34: mounted() is unknown (nil) until set.
    --   c.setMounted(true / false)   c.setMounted(nil): not known
    function c.mounted() return s.mounted end
    function c.setMounted(v)
        if v == nil then s.mounted = nil else s.mounted = v and true or false end
    end
    -- Section 235 item 4: fishingPole() is unknown (nil) until set.
    --   c.setFishingPole(true / false)   c.setFishingPole(nil): not known
    function c.fishingPole() return s.fishingPole end
    function c.setFishingPole(v)
        if v == nil then s.fishingPole = nil else s.fishingPole = v and true or false end
    end
    -- G25: heldBy() is unknown (nil) until set; false: nothing holds you.
    function c.heldBy() return s.heldBy end
    function c.setHeldBy(v) s.heldBy = v end
    -- N8: lowHealth() and itemCooldown(id) are unknown (nil) until set.
    --   c.setLowHealth(true / false)   c.setLowHealth(nil): not known
    --   c.setItemCooldown(id, secs)    secs 0: ready; nil: not known
    function c.lowHealth() return s.lowHealth end
    function c.setLowHealth(v)
        if v == nil then s.lowHealth = nil else s.lowHealth = v and true or false end
    end
    function c.itemCooldown(item)
        local id = ns.Items and ns.Items.Id(item) or item
        return s.itemCooldowns and s.itemCooldowns[id] or nil
    end
    function c.setItemCooldown(item, secs)
        local id = ns.Items and ns.Items.Id(item) or item
        s.itemCooldowns = s.itemCooldowns or {}
        s.itemCooldowns[id] = (type(secs) == "number" and secs >= 0) and secs or nil
    end

    -- S42: questItem(questID), itemCount(item), itemUse(item), all unknown
    -- (nil) until set.
    --   c.setQuestItem(questID, id, link)  id nil: the quest has none; link
    --                                      defaults to "item:<id>"
    --   c.setItemCount(item, n)            n nil: not known
    --   c.setItemUse(item, true / false)   nil: not known
    function c.questItem(questID)
        local q = s.questItems and s.questItems[questID] or nil
        if type(q) ~= "table" then return nil end
        return { id = q.id, link = q.link }
    end
    function c.setQuestItem(questID, id, link)
        s.questItems = s.questItems or {}
        s.questItems[questID] = id and { id = id, link = link or ("item:" .. tostring(id)) } or nil
    end
    function c.itemCount(item)
        if not s.itemCounts then return nil end
        return s.itemCounts[item]
    end
    function c.setItemCount(item, n)
        s.itemCounts = s.itemCounts or {}
        s.itemCounts[item] = n
    end
    function c.itemUse(item)
        if not s.itemUses then return nil end
        return s.itemUses[item]
    end
    function c.setItemUse(item, v)
        s.itemUses = s.itemUses or {}
        if v == nil then s.itemUses[item] = nil else s.itemUses[item] = v and true or false end
    end

    -- S44: mapCorners(map) is unknown (nil) until set.
    --   c.setMapCorners(map, { cont, ox, oy, ex, ey, sx, sy })  nil: not known
    function c.mapCorners(map)
        local m = s.mapCorners and s.mapCorners[map] or nil
        if type(m) ~= "table" then return nil end
        return { cont = m.cont, ox = m.ox, oy = m.oy, ex = m.ex, ey = m.ey, sx = m.sx, sy = m.sy }
    end
    function c.setMapCorners(map, corners)
        s.mapCorners = s.mapCorners or {}
        s.mapCorners[map] = type(corners) == "table" and corners or nil
    end

    -- S2 trader. As the real client's: watchAuctionRows(fn) -> true, or nil
    -- after setAuctionHouse(false); auctionRows(id, rows[, kind]) plays one
    -- of the player's searches answering with rows = { { unit =, qty = } ... }.
    -- kind is "commodity" (when not given) or "item". A watcher's error
    -- stays here, as in the real client (R7).
    function c.watchAuctionRows(fn)
        if s.noAuctionHouse or type(fn) ~= "function" then return nil end
        s.auctionRowsFns = s.auctionRowsFns or {}
        table.insert(s.auctionRowsFns, fn)
        return true
    end
    function c.auctionRows(id, rows, kind)
        kind = kind or "commodity"
        for _, fn in ipairs({ unpack(s.auctionRowsFns or {}) }) do pcall(fn, id, rows, kind) end
    end
    -- S3 slice 3. As the real client's: globalText(name),
    -- onSystemMessage(fn) -> cancel, auctionOutcome(line).
    -- setGlobalText(name, text) sets one of the client's texts;
    -- systemMessage(text) plays one CHAT_MSG_SYSTEM line: a non-text line is
    -- dropped and a listener's error stays here, as in the real client.
    function c.setGlobalText(name, text)
        s.globalTexts = s.globalTexts or {}
        s.globalTexts[name] = text
    end
    function c.globalText(name)
        local v = s.globalTexts and s.globalTexts[name]
        if type(v) ~= "string" or v == "" then return nil end
        return v
    end
    function c.onSystemMessage(fn)
        if type(fn) ~= "function" then return nil end
        s.systemFns = s.systemFns or {}
        table.insert(s.systemFns, fn)
        return function()
            for i = #s.systemFns, 1, -1 do
                if s.systemFns[i] == fn then table.remove(s.systemFns, i) end
            end
        end
    end
    function c.systemMessage(text)
        if type(text) ~= "string" then return end
        for _, fn in ipairs({ unpack(s.systemFns or {}) }) do pcall(fn, text) end
    end
    -- A text with one %s and no other % as a whole-line pattern.
    local function outcomePattern(fmt)
        if type(fmt) ~= "string" then return nil end
        local a, b = fmt:find("%s", 1, true)
        if not a then return nil end
        local head, tail = fmt:sub(1, a - 1), fmt:sub(b + 1)
        if head:find("%", 1, true) or tail:find("%", 1, true) then return nil end
        return "^" .. head:gsub("%W", "%%%0") .. "(.+)" .. tail:gsub("%W", "%%%0") .. "$"
    end
    function c.auctionOutcome(line)
        if type(line) ~= "string" or line == "" then return nil end
        for _, o in ipairs({ { "sold", "ERR_AUCTION_SOLD_S" }, { "expired", "ERR_AUCTION_EXPIRED_S" } }) do
            local pattern = outcomePattern(c.globalText(o[2]))
            local name = pattern and line:match(pattern)
            if name then return o[1], name end
        end
        return nil
    end

    -- S8 nameplate threat and combo points. As the real client's; every
    -- read is unknown (nil) until set.
    --   c.SECRET   stands in for a value the game hides: it may be stored
    --              and handed on; adding, comparing, indexing or joining it
    --              raises, so a module that looked at it fails its test.
    --   c.addPlate(unit[, part]) / c.removePlate(unit)   a nameplate comes
    --              into view / goes (the client's events fire). part: what a
    --              bar hangs under there, "power", "health" (the default)
    --              or "plate"
    --   c.setPlate(unit, part)   the same without the event ("target" too);
    --              nil: no plate for it on screen
    --   c.setThreat(unit, status, pct)   pct a number, c.SECRET or nil;
    --              status a number, c.SECRET or nil; c.setThreat(unit): on
    --              no threat list there
    --   c.setCanAttack(unit, v)   c.setGrouped(v)   nil: not known
    --   c.setCombo(points, max)   points a number, c.SECRET or nil
    --   c.setComboColor(r, g, b)  c.setComboColor(nil): not known
    -- c.plateLabels[i]: .unit, .shown, .says (the text set, or c.SECRET as
    --   the client passed it through), .format (what the hidden value was
    --   formatted with), .rgb, .alphaNow, .reads (threat reads)
    -- c.comboBars[i]: .shown, .hung, .under, .max, .value (a number, or
    --   c.SECRET as the client passed it through), .rgb, .reads, .hangs
    local function refuse() error("a hidden value was looked at", 2) end
    c.SECRET = setmetatable({}, {
        __index = refuse, __newindex = refuse, __call = refuse, __concat = refuse, __len = refuse,
        __unm = refuse, __add = refuse, __sub = refuse, __mul = refuse, __div = refuse, __mod = refuse,
        __pow = refuse, __lt = refuse, __le = refuse,
        __tostring = function() return "(a hidden value)" end,
    })
    local function plateUnit(unit)
        return type(unit) == "string" and unit:find("^nameplate%d+$") ~= nil
    end
    local PARTS = { power = true, health = true, plate = true }
    function c.setPlate(unit, part)
        s.plates = s.plates or {}
        if part == true then part = "health" end
        s.plates[unit] = PARTS[part] and part or nil
    end
    function c.addPlate(unit, part)
        c.setPlate(unit, part or "health")
        events.call("NAME_PLATE_UNIT_ADDED", unit)
    end
    function c.removePlate(unit)
        c.setPlate(unit, nil)
        events.call("NAME_PLATE_UNIT_REMOVED", unit)
    end
    function c.plates(fn)
        if type(fn) ~= "function" then return nil end
        local function tell(what)
            return function(unit)
                if plateUnit(unit) then pcall(fn, what, unit) end
            end
        end
        local offAdded = events.add("NAME_PLATE_UNIT_ADDED", tell("added"))
        local offRemoved = events.add("NAME_PLATE_UNIT_REMOVED", tell("removed"))
        return function()
            offAdded()
            offRemoved()
        end
    end
    function c.canAttack(unit)
        if unit ~= "target" and not plateUnit(unit) then return nil end
        if not s.attackable then return nil end
        return s.attackable[unit]
    end
    function c.setCanAttack(unit, v)
        s.attackable = s.attackable or {}
        if v == nil then s.attackable[unit] = nil else s.attackable[unit] = v and true or false end
    end
    -- Lead section 242: the enemies on nameplates and the casts on them, as
    -- the real client.plateEnemies and client.plateCasts (P-READS, Plexy):
    -- nil until set (not read); each answer is a fresh copy of the rows.
    local function copyPlateRows(list)
        if type(list) ~= "table" then return nil end
        local out = {}
        for i, row in ipairs(list) do
            local r = {}
            for k, v in pairs(row) do r[k] = v end
            out[i] = r
        end
        return out
    end
    function c.setPlateEnemies(list) s.plateEnemies = copyPlateRows(list) end
    function c.plateEnemies() return copyPlateRows(s.plateEnemies) end
    function c.setPlateCasts(list) s.plateCasts = copyPlateRows(list) end
    function c.plateCasts() return copyPlateRows(s.plateCasts) end
    function c.grouped() return s.grouped end
    -- The friends list, by player id (party invites): not known until set.
    function c.setFriend(guid, v) s.friends = s.friends or {}; s.friends[guid] = v end
    function c.isFriend(guid) return s.friends and s.friends[guid] or nil end
    function c.setGrouped(v)
        if v == nil then s.grouped = nil else s.grouped = v and true or false end
    end
    function c.setThreat(unit, status, pct)
        s.threats = s.threats or {}
        if status == nil and pct == nil then
            s.threats[unit] = nil
        else
            s.threats[unit] = { status = status, pct = pct }
        end
    end
    local function rgbOf(r, g, b)
        if type(r) == "number" and type(g) == "number" and type(b) == "number" then return { r, g, b } end
        return nil
    end
    c.plateLabels = {}
    function c.plateLabel(unit)
        if s.noFrames or not plateUnit(unit) or not (s.plates and s.plates[unit]) then return nil end
        local h = { unit = unit, shown = false, reads = 0 }
        function h.show(on) h.shown = on and true or false end
        function h.text(text)
            if type(text) ~= "string" then return end
            h.says, h.format = text, nil
        end
        function h.color(r, g, b) h.rgb = rgbOf(r, g, b) or h.rgb end
        function h.alpha(a)
            if type(a) == "number" then h.alphaNow = a end
        end
        function h.threat()
            h.reads = h.reads + 1
            local r = s.threats and s.threats[unit]
            if type(r) ~= "table" or r.pct == nil then return nil end
            local status = type(r.status) == "number" and r.status or nil
            if rawequal(r.pct, c.SECRET) then
                h.says, h.format = r.pct, "%.0f%%"
                return "hidden", status
            end
            if type(r.pct) ~= "number" then return nil end
            return "shown", status, r.pct
        end
        c.plateLabels[#c.plateLabels + 1] = h
        return h
    end
    c.comboBars = {}
    function c.comboBar()
        if s.noFrames then return nil end
        local h = { shown = false, reads = 0, hangs = 0 }
        function h.hang(unit)
            h.hangs = h.hangs + 1
            if unit ~= "target" and not plateUnit(unit) then return nil end
            local part = s.plates and s.plates[unit] or nil
            h.hung, h.under = part and unit or nil, part
            return part
        end
        function h.sections(n)
            if type(n) ~= "number" or n < 1 or n > 10 or n ~= math.floor(n) then return false end
            h.max = n
            return true
        end
        function h.fill(n)
            if type(n) ~= "number" then return false end
            h.value = n
            return true
        end
        function h.color(r, g, b) h.rgb = rgbOf(r, g, b) or h.rgb end
        function h.show(on) h.shown = on and true or false end
        function h.fillFromGame()
            h.reads = h.reads + 1
            local p = s.comboPoints
            if p == nil then return nil end
            if rawequal(p, c.SECRET) then
                h.value = p
                return "hidden"
            end
            if type(p) ~= "number" then return nil end
            return "shown", p
        end
        c.comboBars[#c.comboBars + 1] = h
        return h
    end
    function c.combo()
        local p = s.comboPoints
        return { points = type(p) == "number" and p or nil, max = s.comboMax }
    end
    function c.setCombo(points, max)
        s.comboPoints = points
        s.comboMax = type(max) == "number" and max or nil
    end
    function c.comboColor()
        local col = s.comboColor
        if not col then return nil end
        return { r = col.r, g = col.g, b = col.b }
    end
    function c.setComboColor(r, g, b)
        if type(r) == "number" and type(g) == "number" and type(b) == "number" then
            s.comboColor = { r = r, g = g, b = b }
        else
            s.comboColor = nil
        end
    end

    -- Section 183 (C1): the rotation's buffs, form and current reads. Each
    -- starts not known (nil). setPlayerBuffs(map or nil): the map handed
    -- back as a copy. setFormName(name, known): known false (or left out
    -- with no name) means not known. setCurrentSpell(id, v): v true, false
    -- or nil (not known) for that spell id.
    function c.playerBuffs()
        if type(s.playerBuffs) ~= "table" then return nil end
        local out = {}
        for k, v in pairs(s.playerBuffs) do out[k] = v end
        return out
    end
    function c.setPlayerBuffs(map) s.playerBuffs = type(map) == "table" and map or nil end
    -- Section 187: your debuffs on the target, the same way. Starts not
    -- known (nil). setTargetDebuffs(map or nil): handed back as a copy.
    function c.targetDebuffs()
        if type(s.targetDebuffs) ~= "table" then return nil end
        local out = {}
        for k, v in pairs(s.targetDebuffs) do out[k] = v end
        return out
    end
    function c.setTargetDebuffs(map) s.targetDebuffs = type(map) == "table" and map or nil end
    function c.formName()
        if s.formKnown ~= true then return nil, false end
        return s.formName, true
    end
    function c.setFormName(name, known)
        s.formName = type(name) == "string" and name or nil
        if known == nil then known = s.formName ~= nil end
        s.formKnown = known and true or false
    end
    function c.currentSpell(id)
        if type(id) ~= "number" or type(s.currentSpells) ~= "table" then return nil end
        return s.currentSpells[id]
    end
    function c.setCurrentSpell(id, v)
        s.currentSpells = s.currentSpells or {}
        if v == nil then s.currentSpells[id] = nil else s.currentSpells[id] = v and true or false end
    end

    -- Flights (DISPATCH section 182 item 2). As the real client's
    -- taxiNodes(): unknown (nil) until set; a copy each time.
    --   c.setTaxiNodes({ map, here, nodes = { { name, x, y, state } } })
    --   c.setTaxiNodes(nil): no flight map open
    function c.setTaxiNodes(read) s.taxiNodes = type(read) == "table" and read or nil end
    function c.taxiNodes()
        local r = s.taxiNodes
        if type(r) ~= "table" then return nil end
        local nodes = {}
        for i, n in ipairs(type(r.nodes) == "table" and r.nodes or {}) do
            nodes[i] = { name = n.name, x = n.x, y = n.y, state = n.state }
        end
        return { map = r.map, here = r.here, nodes = nodes }
    end

    -- Flight marks (lead section 187 section 7), as the real client's
    -- taxiMark() and mapPins(). nil when setFrames(false). Each made is
    -- kept in order:
    --   c.taxiMarks[1].node / .label / .shown / .marks / .hides
    --   c.mapPinSets[1].pins / .lines / .shown / .draws / .clears
    --   c.setWorldMap(uiMapID or nil): what h.map() answers (nil: the world
    --   map is not shown).
    c.taxiMarks = {}
    function c.taxiMark()
        if s.noFrames then return nil end
        local h = { shown = false, marks = 0, hides = 0 }
        function h.mark(node, text)
            if type(node) ~= "table" then return false end
            h.node = { name = node.name, x = node.x, y = node.y }
            h.label = text
            h.shown = true
            h.marks = h.marks + 1
            return true
        end
        function h.hide()
            h.shown = false
            h.hides = h.hides + 1
        end
        c.taxiMarks[#c.taxiMarks + 1] = h
        return h
    end
    c.mapPinSets = {}
    function c.setWorldMap(map) s.worldMap = map end
    -- Map names: c.setMapName(map, name); mapName(map) is nil until told.
    function c.setMapName(map, name)
        s.mapNames = s.mapNames or {}
        s.mapNames[map] = name
    end
    function c.mapName(map) return s.mapNames and s.mapNames[map] or nil end
    -- Area names: c.setAreaName(area, name); areaName(area) is nil until told.
    function c.setAreaName(area, name)
        s.areaNames = s.areaNames or {}
        s.areaNames[area] = name
    end
    function c.areaName(area) return s.areaNames and s.areaNames[area] or nil end
    -- The player's Alt + left click on the world map: mapClick(fn) keeps
    -- fn (nil and a reason with no frames); c.clickMap(map, x, y) is the
    -- player doing it.
    c.mapClicks = {}
    function c.mapClick(fn)
        if s.noFrames then return nil, "no world map" end
        if type(fn) ~= "function" then return nil, "no function" end
        c.mapClicks[#c.mapClicks + 1] = fn
        return true
    end
    function c.clickMap(map, x, y)
        for _, fn in ipairs(c.mapClicks) do fn(map, x, y) end
    end
    function c.mapPins()
        if s.noFrames then return nil end
        local h = { pins = {}, lines = {}, shown = false, draws = 0, clears = 0 }
        function h.map() return s.worldMap end
        function h.draw(pins, lines)
            h.pins = copyRows(type(pins) == "table" and pins or {})
            h.lines = copyRows(type(lines) == "table" and lines or {})
            h.shown = #h.pins > 0 or #h.lines > 0
            h.draws = h.draws + 1
            return true
        end
        function h.clear()
            h.pins, h.lines, h.shown = {}, {}, false
            h.clears = h.clears + 1
        end
        c.mapPinSets[#c.mapPinSets + 1] = h
        return h
    end

    -- Route lines (section 447 F7), as the real client's c.mapRouteLines:
    -- each handle made is kept in c.routeLineSets; h.lines is the last
    -- drawn, copied.
    c.routeLineSets = {}
    function c.mapRouteLines()
        if s.noFrames then return nil end
        local h = { lines = {}, shown = false, draws = 0, clears = 0 }
        function h.map() return s.worldMap end
        function h.draw(lines)
            h.lines = copyRows(type(lines) == "table" and lines or {})
            h.shown = #h.lines > 0
            h.draws = h.draws + 1
            return true
        end
        function h.clear()
            h.lines, h.shown = {}, false
            h.clears = h.clears + 1
        end
        c.routeLineSets[#c.routeLineSets + 1] = h
        return h
    end

    -- Pet state (lead section 197), as the real client's pet(): not known
    -- (nil) until set; a copy each time.
    --   c.setPet({ exists = true or false, dead, inCombat, family, happiness, powerKind })
    --   c.setPet(nil), or no plain exists: not known again
    -- dead and inCombat: true or false, else not known; family: a non-empty
    -- word; happiness: "unhappy", "content" or "happy"; powerKind: a number.
    -- Anything else is left out (not known). With exists false the rest is
    -- dropped.
    local PET_MOODS = { unhappy = true, content = true, happy = true }
    -- P-GATHER. c.setTracking(spell, on): true / false; nil: not known.
    -- c.setProfessions({ name, ... }) or nil: not read.
    function c.tracking(spell) return s.trackingOn and s.trackingOn[spell] end
    function c.setTracking(spell, on)
        s.trackingOn = s.trackingOn or {}
        if on == nil then s.trackingOn[spell] = nil else s.trackingOn[spell] = on and true or false end
    end
    -- GK-4: the whole tracking list as the client lists it, town kinds and
    -- entries whose active is not known included:
    --   c.setTrackingList({ { name, active = true | false | nil, town = true }, ... })
    -- nil clears it (back to setTracking's spells). While a list is set,
    -- anyTracking answers from it by the real client's rule (GK-2, GK-3):
    -- town entries left out; one of yours on: true; else one not known: nil;
    -- else false.
    function c.setTrackingList(list)
        if type(list) ~= "table" then s.trackingList = nil return end
        s.trackingList = {}
        for i, e in ipairs(list) do
            s.trackingList[i] = { name = e.name, active = e.active, town = e.town == true }
        end
    end
    -- GT-1: any tracking on: true when one set on is, false when any was set
    -- and none is on, nil when none was set.
    function c.anyTracking()
        if s.trackingList then
            local unknown = false
            for _, e in ipairs(s.trackingList) do
                if not e.town then
                    if e.active == nil then unknown = true elseif e.active then return true end
                end
            end
            if unknown then return nil end
            return false
        end
        if not s.trackingOn then return nil end
        for _, on in pairs(s.trackingOn) do
            if on == true then return true end
        end
        return false
    end
    function c.professions()
        if not s.professions then return nil end
        local out = {}
        for k, v in pairs(s.professions) do out[k] = v end
        return out
    end
    function c.setProfessions(list)
        if type(list) ~= "table" then s.professions = nil return end
        s.professions = {}
        for _, name in ipairs(list) do s.professions[name] = true end
    end
    function c.setPet(r)
        if type(r) ~= "table" or type(r.exists) ~= "boolean" then
            s.pet = nil
            return
        end
        if not r.exists then
            s.pet = { exists = false }
            return
        end
        local function yesNo(v) if type(v) == "boolean" then return v end return nil end
        s.pet = {
            exists = true, dead = yesNo(r.dead), inCombat = yesNo(r.inCombat),
            hurt = yesNo(r.hurt),
            family = (type(r.family) == "string" and r.family ~= "") and r.family or nil,
            happiness = PET_MOODS[r.happiness or ""] and r.happiness or nil,
            powerKind = (type(r.powerKind) == "number" and r.powerKind == r.powerKind) and r.powerKind or nil,
        }
    end
    function c.pet()
        if type(s.pet) ~= "table" then return nil end
        local out = {}
        for k, v in pairs(s.pet) do out[k] = v end
        return out
    end

    -- ------------------------------------------------------- craft (P-CRAFT)
    -- The craft reads: not known (nil) until a test sets them.
    local usableOf, whyOf = {}, {}
    function c.setRecipeUsable(id, v, why) usableOf[id], whyOf[id] = v, why end
    function c.recipeUsable(id) return usableOf[id], whyOf[id] end
    function c.setMoving(on) s.moving = on end
    function c.moving() return s.moving end
    -- Yards a second (the arrow's time to arrive): not known until set.
    function c.setSpeed(v) s.speed = v end
    function c.speed() return s.speed end

    -- Every craft the add-on asked for, in order: { id =, n = }. A refused
    -- craft is not logged. setCraftFails(why) makes every craft answer
    -- nil, why (nil again lets them through).
    c.crafts = {}
    local craftFails
    function c.setCraftFails(why) craftFails = why end
    -- Section 240, the repeat runner: setCraftRepeat(seconds) makes each
    -- craft asked with a repeat count n finish n times by itself, one
    -- UNIT_SPELLCAST_SUCCEEDED ("player", a cast guid, the recipe) each
    -- `seconds` of advance(). stopCraftRepeat drops the finishes still to
    -- come; a new ask replaces the run. nil: nothing finishes by itself
    -- (the tests fire each finish). How the real client paces its repeat
    -- and orders its events is not known: Needs game test.
    local repeatEvery, repeatRun
    function c.setCraftRepeat(seconds) repeatEvery, repeatRun = seconds, nil end
    function c.craftRecipe(id, n)
        if s.combat ~= false then return nil, "combat" end
        if craftFails then return nil, craftFails end
        c.crafts[#c.crafts + 1] = { id = id, n = n }
        if type(repeatEvery) == "number" and repeatEvery > 0 then
            repeatRun = { id = id, left = type(n) == "number" and n or 1, at = s.t + repeatEvery }
        end
        return true
    end
    -- One frame of the runner (called from advance, after the frame
    -- ticks): each finish that is due, in order. No frame listener, so the
    -- tick counts other tests pin do not change.
    function repeatFrame()
        while repeatRun and repeatRun.left > 0 and s.t >= repeatRun.at do
            local run = repeatRun
            run.left = run.left - 1
            run.at = run.at + repeatEvery
            if run.left <= 0 then repeatRun = nil end
            events.call("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-fake", run.id)
        end
    end
    -- How many times the add-on asked the game to stop a craft repeat.
    c.repeatStops = 0
    function c.stopCraftRepeat()
        c.repeatStops = c.repeatStops + 1
        repeatRun = nil
        return true
    end

    -- G59: the game settings by name. c.putGameSetting seeds a value (not a write);
    -- c.gameSettingLimit(name, most) makes the game keep its value on a write above
    -- most (the call still answers true); c.setGameSettingFails(why) makes every
    -- write answer nil, why. Every write asked for is in c.gameSettingWrites as
    -- { name, value }. Not seeded: nil, not known.
    local cvars, cvarMost, cvarFail = {}, {}, nil
    c.gameSettingWrites = {}
    function c.putGameSetting(name, v) cvars[name] = v end
    function c.gameSettingLimit(name, most) cvarMost[name] = most end
    function c.setGameSettingFails(why) cvarFail = why end
    function c.gameSetting(name) return cvars[name] end
    function c.setGameSetting(name, v)
        if s.combat ~= false then return nil, "combat" end   -- as the client: not asked in a fight
        c.gameSettingWrites[#c.gameSettingWrites + 1] = { name, v }
        if cvarFail then return nil, cvarFail end
        local most, n = cvarMost[name], tonumber(v)
        if most and n and n > most then return true end
        cvars[name] = v
        return true
    end
    -- G59: the combat log file, on or off; seeded by c.putCombatLogFile, nil
    -- until then. Every write asked for is in c.logFileWrites.
    local logging
    c.logFileWrites = {}
    function c.putCombatLogFile(on) logging = on end
    function c.combatLogFile() return logging end
    function c.setCombatLogFile(on)
        if s.combat ~= false then return nil, "combat" end   -- as the client: not asked in a fight
        c.logFileWrites[#c.logFileWrites + 1] = on
        if type(on) ~= "boolean" then return nil, "bad" end
        logging = on
        return true
    end

    -- Every row panel made, in order. h.rows is the last draw (copied);
    -- press(key, value) is the player clicking that row: false for an
    -- info row, a row not enabled, no act, or a number outside min..max;
    -- else act(key[, value]) and true. The fake jumps to any value where
    -- the real panel steps by one.
    c.rowPanels = {}
    function c.rowPanel(spec)
        if s.noFrames then return nil end
        local h = { spec = spec, rows = {}, places = 0 }
        local open, act, closed, closedFailed = false, nil, nil, nil
        function h.draw(rows, fn)
            h.rows = {}
            for i, row in ipairs(type(rows) == "table" and rows or {}) do
                local copy = {}
                for k, v in pairs(row) do copy[k] = v end
                h.rows[i] = copy
            end
            act = type(fn) == "function" and fn or nil
        end
        function h.show(on) open = on and true or false end
        function h.shown() return open end
        function h.place(point)
            if type(point) ~= "table" then return end
            h.point = { point[1], point[2], point[3], point[4] }
            h.places = h.places + 1
        end
        function h.onMoved() end
        function h.onClose(fn, failed)
            closed = type(fn) == "function" and fn or nil
            closedFailed = type(failed) == "function" and failed or nil
        end
        function h.press(key, value)
            for _, row in ipairs(h.rows) do
                if row.key == key and row.kind ~= "info" then
                    if row.enabled == false or not act then return false end
                    if row.kind == "number" then
                        if type(value) ~= "number" then return false end
                        if type(row.min) == "number" and value < row.min then return false end
                        if type(row.max) == "number" and value > row.max then return false end
                        pcall(act, key, value)
                    else
                        pcall(act, key)
                    end
                    return true
                end
            end
            return false
        end
        function h.close()
            if not open then return end
            open = false
            if closed then
                local ok, err = pcall(closed)
                if not ok and closedFailed then closedFailed(err) end
            end
        end
        c.rowPanels[#c.rowPanels + 1] = h
        return h
    end

    -- A spell's name by id, as the real client's spellName(id) (CF-32): the
    -- name setSpellId gave that id, else nil (not read).
    function c.spellName(id)
        if type(id) ~= "number" then return nil end
        for name, known in pairs(s.spellIds or {}) do
            if known == id then return name end
        end
        return nil
    end

    -- Your own buffs, as the real client's ownBuffs() (N13): a copy of the
    -- map setOwnBuffs gave (nil: not known). Until setOwnBuffs is called,
    -- every buff setPlayerBuffs gave counts as yours.
    function c.setOwnBuffs(map)
        s.ownBuffsSet = true
        s.ownBuffs = type(map) == "table" and map or nil
    end
    function c.ownBuffs()
        local from = s.playerBuffs
        if s.ownBuffsSet then from = s.ownBuffs end
        if type(from) ~= "table" then return nil end
        local out = {}
        for k, v in pairs(from) do out[k] = v end
        return out
    end

    -- Worn links (P-SETS), as the real client's wornLinks(): { [slot] =
    -- link } from what setWorn was given (a link worn; false or nil: none
    -- there). nil (not known) until setWorn is called, or after
    -- setWornUnread(true).
    function c.wornLinks()
        if s.wornUnread or type(s.worn) ~= "table" then return nil end
        local out = {}
        for slot, link in pairs(s.worn) do
            if type(link) == "string" and link ~= "" then out[slot] = link end
        end
        return out
    end
    function c.setWornUnread(on) s.wornUnread = on and true or nil end

    -- Your group (P-PARTY), as the real client's party(), reach(id, unit)
    -- and unitDebuffTypes(unit); each nil (not known) until set.
    --   c.setParty(list)                  { { unit, name, class, role, power,
    --                                     dead, connected }, ... } (a field
    --                                     left out: not known); nil: not known
    --   c.setReach(unit, spellId, v)      true, false, or nil (not known)
    --   c.setUnitDebuffs(unit, map)       { [type] = debuff name }; nil: not known
    --   c.setPartyFails(on), c.setReachFails(on)   the read raises while on
    --                                     (lead section 236: a read that
    --                                     fails, then recovers)
    function c.setParty(list) s.party = list end
    function c.party()
        if s.partyFails then error("party read failed (test)") end
        if type(s.party) ~= "table" then return nil end
        local out = {}
        for i, m in ipairs(s.party) do
            local row = {}
            for k, v in pairs(m) do row[k] = v end
            out[i] = row
        end
        return out
    end
    function c.setPartyFails(on) s.partyFails = on and true or nil end
    function c.setReach(unit, spellId, v)
        s.reach = s.reach or {}
        s.reach[unit] = s.reach[unit] or {}
        s.reach[unit][spellId] = v
    end
    function c.reach(spellId, unit)
        if s.reachFails then error("reach read failed (test)") end
        local r = s.reach and s.reach[unit]
        if type(r) ~= "table" or type(r[spellId]) ~= "boolean" then return nil end
        return r[spellId]
    end
    function c.setReachFails(on) s.reachFails = on and true or nil end
    function c.setUnitDebuffs(unit, map)
        s.unitDebuffs = s.unitDebuffs or {}
        s.unitDebuffs[unit] = map
    end
    function c.unitDebuffTypes(unit)
        local m = s.unitDebuffs and s.unitDebuffs[unit]
        if type(m) ~= "table" then return nil end
        local out = {}
        for k, v in pairs(m) do out[k] = v end
        return out
    end
    -- The icon's caption (P-PARTY), as the real client's: h.caption(text)
    -- on every icon; h.captionText is the last text, nil when hidden.
    do
        local plainIcon = c.icon
        function c.icon(spec)
            local h = plainIcon(spec)
            if type(h) ~= "table" then return h end
            function h.caption(words)
                h.captionText = (type(words) == "string" and words ~= "") and words or nil
                return true
            end
            return h
        end
    end
    -- N55, the boss loot panel: the same reads as Core/Client.lua, set by a
    -- test; each nil (not known) until set.
    --   c.setBossUnit(r)       { exists, guid, name } as c.bossUnit() gives
    --                          it; with exists false nothing more is said
    --   c.setInstance(r)       { inside, kind } as c.instance() gives it
    --   c.setLootLine(fn)      fn(line) answering item, count for a loot
    --                          line (anyone's) and nil for any other
    --   c.setReadFails(name, on)   the read c[name] raises while on (lead
    --                          section 236: a read that fails, then
    --                          recovers). For any read of this client; a
    --                          caller that kept the function itself from
    --                          before the first call is not reached.
    function c.setBossUnit(r) s.bossUnit = type(r) == "table" and r or nil end
    function c.bossUnit()
        local r = s.bossUnit
        if type(r) ~= "table" or type(r.exists) ~= "boolean" then return nil end
        if not r.exists then return { exists = false } end
        return { exists = true, guid = r.guid, name = r.name }
    end
    function c.setInstance(r) s.instance = type(r) == "table" and r or nil end
    function c.instance()
        local r = s.instance
        if type(r) ~= "table" or type(r.inside) ~= "boolean" then return nil end
        return { inside = r.inside, kind = r.kind }
    end
    function c.setLootLine(fn) s.lootLine = fn end
    function c.lootLine(line)
        if type(s.lootLine) ~= "function" then return nil end
        return s.lootLine(line)
    end
    do
        local failing, wrapped = {}, {}
        function c.setReadFails(name, on)
            if type(c[name]) ~= "function" then return end
            if not wrapped[name] then
                wrapped[name] = true
                local plainRead = c[name]
                c[name] = function(...)
                    if failing[name] then error(tostring(name) .. " read failed (test)") end
                    return plainRead(...)
                end
            end
            failing[name] = on and true or nil
        end
    end

    -- Settings topics and search, and menus with submenus (lead sections
    -- 238 and 239). Added last, around what is above.
    --
    -- The Options page: draw(rows, act, nav) keeps nav as the real page's
    -- topic buttons, search box and Open topic buttons call it.
    --   c.optionsNav("topic", id) / c.optionsNav("search", text)   the test
    --     plays the player choosing a topic or searching ("" clears)
    --   c.setOptionsPageFault(n)   the next n asks for the page raise, as a
    --     client whose registration fails; the one after answers as usual
    --   c.optionsPagesMade()       how many pages were handed out
    local optionsBase = c.optionsPage
    function c.setOptionsPageFault(n) s.optionsFaults = tonumber(n) or 0 end
    function c.optionsPagesMade() return s.optionsMade or 0 end
    function c.optionsPage(spec)
        if (s.optionsFaults or 0) > 0 then
            s.optionsFaults = s.optionsFaults - 1
            error("the options page could not be registered", 0)
        end
        local h = optionsBase(spec)
        if not h then return h end
        s.optionsMade = (s.optionsMade or 0) + 1
        local draw = h.draw
        function h.draw(rows, act, nav)
            s.optionsNav = type(nav) == "function" and nav or nil
            return draw(rows, act)
        end
        return h
    end
    function c.optionsNav(kind, value)
        if type(s.optionsNav) == "function" then return s.optionsNav(kind, value) end
        return nil
    end

    -- Menu rows with a submenu. A level of a menu is the rows the arrow
    -- was last given; a row marked `more` opens another level when chosen
    -- (UI/ArrowMenu.lua). As on the real menu, only a row of the open level
    -- that is not a heading, a divider or greyed takes a click.
    --   h.pickRow(key) -> true when that row was offered and was clicked
    --   h.enter(key)   -> true when it was a submenu row and its level is
    --                     now the open one
    --   h.menuDepth       how many submenus deep the open level is
    local arrowBase = c.arrow
    function c.arrow(spec)
        local h = arrowBase(spec)
        if not h then return h end
        h.menuDepth = 0
        local function offered(key)
            for _, row in ipairs(h.menuItems or {}) do
                if type(row) == "table" and row.key == key and not row.title and not row.sep
                    and not row.disabled then
                    return row
                end
            end
            return nil
        end
        function h.pickRow(key)
            if not offered(key) then return false end
            h.choose(key)
            if h.menuItems == nil then h.menuDepth = 0 end
            return true
        end
        function h.enter(key)
            local row = offered(key)
            if not row or row.more ~= true then return false end
            h.choose(key)
            if h.menuItems == nil then
                h.menuDepth = 0
                return false
            end
            h.menuDepth = h.menuDepth + 1
            return true
        end
        return h
    end

    -- Lead section 243 (P-PARTY 2). setUnitBuffFails(unit, on): that unit's
    -- buff read raises while on (one member's aura read failing). And the
    -- icon's look-only mark, as the real client's: mark("look") keeps
    -- "look" in h.marked; any other mark is the icon's own.
    do
        local failing = {}
        function c.setUnitBuffFails(unit, on) failing[unit] = on and true or nil end
        local plainBuff = c.unitBuff
        function c.unitBuff(unit, names)
            if failing[unit] then error("buff read failed (test)") end
            return plainBuff(unit, names)
        end
        local plainIcon = c.icon
        function c.icon(spec)
            local h = plainIcon(spec)
            if type(h) ~= "table" then return h end
            local plainMark = h.mark
            function h.mark(look, ...)
                if look == "look" then
                    h.marked = "look"
                    return true
                end
                return plainMark(look, ...)
            end
            return h
        end
    end
    -- N59: the info bar reads, unknown (nil) until a test sets them.
    -- c.setXp{ cur, max, rested }; c.setWatchedFaction(t or false: none
    -- watched); c.setGameTime(h, m); c.setFramerate(n); c.setLatency(home, world).
    local function ibCopy(t)
        if type(t) ~= "table" then return t end
        local out = {}
        for k, v in pairs(t) do out[k] = v end
        return out
    end
    function c.setXp(t) s.xp = ibCopy(t) end
    function c.xp() return ibCopy(s.xp) end
    function c.setWatchedFaction(v) s.watchedFaction = ibCopy(v) end
    function c.watchedFaction() return ibCopy(s.watchedFaction) end
    function c.setGameTime(h, m)
        if h == nil then s.gameTime = nil else s.gameTime = { hour = h, minute = m } end
    end
    function c.gameTime() return ibCopy(s.gameTime) end
    function c.setFramerate(n) s.framerate = n end
    function c.framerate() return s.framerate end
    function c.setLatency(home, world)
        if home == nil then s.latency = nil else s.latency = { home = home, world = world } end
    end
    function c.latency() return ibCopy(s.latency) end
    -- No data broker library offline: the feed is never made.
    function c.broker() return nil end

    -- Every info bar made is in c.infoBars, in order: .spec, .text,
    -- .shown, .fontSize, .alpha, .width, .height, .point, .locked,
    -- .tipLines. The test's controls: drag(point), resize(w, h) (neither
    -- while locked), click(button), hover(on).
    c.infoBars = {}
    function c.infoBar(spec)
        if s.noFrames then return nil end
        spec = type(spec) == "table" and spec or {}
        local b = { spec = spec, shown = false, width = spec.width, height = spec.height, locked = false }
        local h = {}
        local moved, resized, clicked, hovered
        local function tell(fn, ...) if type(fn) == "function" then pcall(fn, ...) end end
        function h.setText(text) b.text = tostring(text or "") end
        function h.show(on) b.shown = on and true or false end
        function h.font(size) b.fontSize = size end
        function h.alpha(a) b.alpha = a end
        function h.size(w, ht) b.width, b.height = w, ht end
        function h.place(point)
            if type(point) ~= "table" then return end
            b.point = { point[1], point[2], point[3], point[4] }
        end
        function h.lock(on) b.locked = on and true or false end
        function h.onMoved(fn) moved = fn end
        function h.onResized(fn) resized = fn end
        function h.onClick(fn) clicked = fn end
        function h.onHover(fn) hovered = fn end
        function h.tip(lines)
            if type(lines) ~= "table" or #lines == 0 then b.tipLines = nil; return end
            b.tipLines = {}
            for i = 1, #lines do b.tipLines[i] = tostring(lines[i]) end
        end
        function b.drag(point)
            if b.locked then return end
            b.point = { point[1], point[2], point[3], point[4] }
            tell(moved, { point[1], point[2], point[3], point[4] })
        end
        function b.resize(w, ht)
            if b.locked then return end
            b.width, b.height = w, ht
            tell(resized, w, ht)
        end
        function b.click(button) tell(clicked, button) end
        function b.hover(on) tell(hovered, on and true or false) end
        c.infoBars[#c.infoBars + 1] = b
        return h
    end

    -- N57: the game's key bindings and the key-capture overlay, as the real
    -- client's wrappers (Core/Client.lua, end). Added last.
    --   c.setBindings({ { key, action }, ... })   the game's binding set as
    --     loaded: live and saved alike, in that order
    --   c.bindingMap() / c.savedBindingMap()   key -> action, copies: what
    --     is bound now, and what SaveBindings last kept (a reload reads it)
    --   c.overrideKeys()   key -> button, this session's override bindings
    --   c.bindingCalls()   the names of the binding writes that went through
    --   c.setBindingReads(false)   bindingKeys and bindingAction answer nil
    --     (the client does not say); true: they answer again
    --   c.setBindingWriteFault(n)  the next n setBindingClick calls raise
    --   c.pressKey(chord) -> true when an open overlay took it; "ESCAPE"
    --     cancels it.  c.keyCaptureOpen() -> true while one waits
    -- The writes refuse with "lockdown" while combatLockdown() is not false.
    do
        local live, saved, order, overrides, calls = {}, {}, {}, {}, {}
        local unread, faults = false, 0
        local capture
        local function copy(t)
            local out = {}
            for k2, v in pairs(t) do out[k2] = v end
            return out
        end
        local function unbind(key)
            live[key] = nil
            for i = #order, 1, -1 do
                if order[i] == key then table.remove(order, i) end
            end
        end
        local function bind(key, action)
            unbind(key)
            live[key] = action
            order[#order + 1] = key
        end
        local function locked() return c.combatLockdown() ~= false end
        function c.setBindings(list)
            live, saved, order = {}, {}, {}
            for _, pair in ipairs(list or {}) do
                bind(pair[1], pair[2])
                saved[pair[1]] = pair[2]
            end
        end
        function c.bindingMap() return copy(live) end
        function c.savedBindingMap() return copy(saved) end
        function c.overrideKeys() return copy(overrides) end
        function c.bindingCalls() return copy(calls) end
        function c.setBindingReads(on) unread = (on == false) end
        function c.setBindingWriteFault(n) faults = tonumber(n) or 0 end

        function c.bindingKeys(action)
            if unread or type(action) ~= "string" then return nil end
            local out = {}
            for _, key in ipairs(order) do
                if live[key] == action then out[#out + 1] = key end
            end
            return out
        end
        function c.bindingAction(key)
            if unread or type(key) ~= "string" or key == "" then return nil end
            return live[key] or ""
        end
        -- S23 (P-KEYS slice B): the twin of c.bindingOverride. Another
        -- add-on's override (c.setForeignOverride) wins, then ours
        -- (c.overrideBindingClick), then the game's binding; "" for none.
        -- c.setBindingOverrideFails(true): the read raises until set false.
        local foreign, overrideFails = {}, false
        function c.setForeignOverride(key, action) foreign[key] = action end
        function c.setBindingOverrideFails(on) overrideFails = (on == true) end
        function c.bindingOverride(key)
            if overrideFails then error("GetBindingAction failed (test)", 0) end
            if unread or type(key) ~= "string" or key == "" then return nil end
            if foreign[key] ~= nil then return foreign[key] end
            if overrides[key] ~= nil then return "CLICK " .. tostring(overrides[key]) .. ":LeftButton" end
            return live[key] or ""
        end
        function c.setBindingClick(key, button)
            if locked() then return false, "lockdown" end
            if faults > 0 then
                faults = faults - 1
                error("SetBindingClick failed (test)", 0)
            end
            bind(key, "CLICK " .. tostring(button) .. ":LeftButton")
            calls[#calls + 1] = "setBindingClick"
            return true
        end
        function c.clearBinding(key)
            if locked() then return false, "lockdown" end
            unbind(key)
            calls[#calls + 1] = "clearBinding"
            return true
        end
        function c.saveBindings()
            if locked() then return false, "lockdown" end
            saved = copy(live)
            calls[#calls + 1] = "saveBindings"
            return true
        end
        function c.overrideBindingClick(key, button)
            if locked() then return false, "lockdown" end
            overrides[key] = button
            calls[#calls + 1] = "overrideBindingClick"
            return true
        end
        function c.clearOverrideKeys()
            if locked() then return false, "lockdown" end
            overrides = {}
            calls[#calls + 1] = "clearOverrideKeys"
            return true
        end

        function c.keyCapture()
            local h = { waiting = false }
            function h.start(text, onKey, onCancel)
                h.waiting, h.text, h.onKey, h.onCancel = true, text, onKey, onCancel
                return true
            end
            function h.stop() h.waiting = false end
            function h.open() return h.waiting end
            capture = h
            return h
        end
        function c.keyCaptureOpen() return capture ~= nil and capture.waiting == true end
        function c.pressKey(chord)
            if not c.keyCaptureOpen() then return false end
            local h = capture
            h.waiting = false
            if chord == "ESCAPE" then
                if type(h.onCancel) == "function" then h.onCancel() end
            elseif type(h.onKey) == "function" then
                h.onKey(chord)
            end
            return true
        end
        -- G34: the twins of c.setBinding and c.bindHover (hover-to-bind).
        --   c.setBarButtons({ frame name, ... })  the buttons on the screen
        --   c.bindHoverOpen() -> true while the mode's covers are up
        --   c.bindHoverIds()  the ids that took a cover, in order
        --   c.bindHoverOver(id | nil)  the mouse goes onto that cover (false
        --     when it has none), or off them all
        --   c.bindHoverKey(chord) -> true when the mode took the press:
        --     "ESCAPE" cancels; any other is told with the cover the mouse is on
        --   c.bindHoverRight(id) -> true: a right click on that cover
        --   c.bindHoverLabels()  the text on each cover, by id
        local barButtons, hover = {}, nil
        function c.setBarButtons(list)
            barButtons = {}
            for _, name in ipairs(list or {}) do barButtons[name] = true end
        end
        function c.setBinding(key, command)
            if type(key) ~= "string" or key == "" or type(command) ~= "string" or command == "" then
                return false, "no key"
            end
            if locked() then return false, "lockdown" end
            bind(key, command)
            calls[#calls + 1] = "setBinding"
            return true
        end
        function c.bindHover()
            local h = { on = false, ids = {}, has = {}, texts = {} }
            function h.stop() h.on, h.over, h.ids, h.has, h.texts = false, nil, {}, {}, {} end
            function h.start(targets, onKey, onCancel, onClear)
                h.stop()
                for _, target in ipairs(targets or {}) do
                    if barButtons[target.frame] and target.id ~= nil then
                        h.ids[#h.ids + 1] = target.id
                        h.has[target.id] = true
                    end
                end
                if #h.ids == 0 then return 0 end
                h.on, h.onKey, h.onCancel, h.onClear = true, onKey, onCancel, onClear
                return #h.ids
            end
            function h.labels(texts)
                h.texts = {}
                if type(texts) == "table" then
                    for id in pairs(h.has) do h.texts[id] = texts[id] end
                end
            end
            function h.open() return h.on end
            hover = h
            return h
        end
        function c.bindHoverOpen() return hover ~= nil and hover.on == true end
        function c.bindHoverIds()
            local out = {}
            for i, id in ipairs(hover and hover.ids or {}) do out[i] = id end
            return out
        end
        function c.bindHoverLabels()
            local out = {}
            for id, text in pairs(hover and hover.texts or {}) do out[id] = text end
            return out
        end
        function c.bindHoverOver(id)
            if not c.bindHoverOpen() then return false end
            if id ~= nil and not hover.has[id] then return false end
            hover.over = id
            return true
        end
        function c.bindHoverKey(chord)
            if not c.bindHoverOpen() then return false end
            if chord == "ESCAPE" then
                if type(hover.onCancel) == "function" then hover.onCancel() end
                return true
            end
            if type(hover.onKey) == "function" then hover.onKey(chord, hover.over) end
            return true
        end
        function c.bindHoverRight(id)
            if not c.bindHoverOpen() or not hover.has[id] then return false end
            if type(hover.onClear) == "function" then hover.onClear(id) end
            return true
        end
    end

    -- Slider rows of the Options page (row N57), as the real page draws
    -- them. Added last, around the page above.
    --   c.optionsDrag(key, value)  the player drags that row's slider to
    --     value and lets go: act(key, value on the row's step, inside its
    --     limits). false when the row is not a slider or cannot be set.
    --   c.setSliders(false)        a client that gives no Slider frame:
    --     every slider row is drawn as the stepper (kind "number")
    local optionsWithNav = c.optionsPage
    function c.setSliders(on) s.noSliders = (on == false) end
    function c.optionsPage(spec)
        local h = optionsWithNav(spec)
        if not h then return h end
        local draw = h.draw
        function h.draw(rows, act, nav)
            local ok = draw(rows, act, nav)
            if s.noSliders and s.options and type(s.options.rows) == "table" then
                for _, row in ipairs(s.options.rows) do
                    if row.kind == "slider" then row.kind = "number" end
                end
            end
            return ok
        end
        return h
    end
    function c.optionsDrag(key, value)
        if not s.options or type(s.options.rows) ~= "table" or type(value) ~= "number" then return false end
        for _, row in ipairs(s.options.rows) do
            if row.key == key and row.kind == "slider" then
                if row.settable ~= true or type(s.options.act) ~= "function" then return false end
                local step = 1
                if type(row.step) == "number" and row.step > 0 then step = row.step end
                local v = row.min + math.floor((value - row.min) / step + 0.5) * step
                if v < row.min then v = row.min end
                if v > row.max then v = row.max end
                s.options.act(key, v)
                return true
            end
        end
        return false
    end

    -- Text entry (N73), as the real client's textEntry: every one made is
    -- in c.textEntries, in order: { spec, shown, words, text }. The test's
    -- controls: e.type(text) is the player typing that and pressing Enter
    -- (false when it is not on the screen), e.escape() is Escape.
    -- setTextEntry(false) plays a client that cannot make one.
    c.textEntries = {}
    function c.setTextEntry(on) s.noTextEntry = (on == false) end
    function c.textEntry(spec)
        if s.noFrames or s.noTextEntry then return nil end
        local e = { spec = spec, shown = false, words = "", text = "" }
        local h, told = {}, nil
        function h.ask(words, text, fn)
            told = nil
            if type(fn) == "function" then told = fn end
            e.words, e.text = "", ""
            if type(words) == "string" then e.words = words end
            if type(text) == "string" then e.text = text end
            e.shown = true
        end
        function h.show(on)
            if on then return end
            e.shown, told = false, nil
        end
        function h.shown() return e.shown end
        function e.type(text)
            if not e.shown then return false end
            local fn = told
            e.shown, told = false, nil
            if fn then fn(tostring(text)) end
            return true
        end
        function e.escape() e.shown, told = false, nil end
        c.textEntries[#c.textEntries + 1] = e
        return h
    end

    -- N67: other add-ons' data as the real client reads it.
    -- setGatherMateNodes(map, rows): GatherMate2 is there with those rows
    -- on that map ({ { kind, x, y, node } }); a map not set has none.
    -- setGatherMateNodes(nil): GatherMate2 is gone. c.gatherMateAsks counts
    -- every ask. setAttuneProgress(rows | nil): Attune's rows, or none.
    -- Each answer is a copy.
    c.gatherMateAsks = 0
    local function copyRows(rows)
        local out = {}
        for i, r in ipairs(rows) do
            local row = {}
            for key, v in pairs(r) do row[key] = v end
            out[i] = row
        end
        return out
    end
    function c.setGatherMateNodes(map, rows)
        if map == nil then
            s.gatherMate = nil
            return
        end
        s.gatherMate = s.gatherMate or {}
        s.gatherMate[map] = rows
    end
    function c.gatherMateNodes(map)
        c.gatherMateAsks = c.gatherMateAsks + 1
        if type(s.gatherMate) ~= "table" or type(map) ~= "number" then return nil end
        local rows = s.gatherMate[map]
        if type(rows) ~= "table" then return {} end
        return copyRows(rows)
    end
    function c.setAttuneProgress(rows) s.attune = rows end
    function c.attuneProgress()
        if type(s.attune) ~= "table" then return nil end
        return copyRows(s.attune)
    end
    -- The macro icon window (N72), as the real client's macroPopup: nil and
    -- { "MacroPopupFrame" } until setMacroPopup{ icons } or { missing }.
    -- Every window set with icons is in c.macroPopups, in order. The test's
    -- controls on one: p.open() (a fresh provider, OnShow), p.close(),
    -- p.visible() (what the grid shows), p.click(i) (p.selected), p.type(s)
    -- (the player typing in the box; false with no box), p.filter(kind) (a
    -- filter button); p.box = { text, hint, shown } once the box is made.
    -- setFrames(false): no box. setSpellbook(list) sets what
    -- spellbookIcons() answers; c.spellbookReads counts the reads.
    c.macroPopups = {}
    c.spellbookReads = 0
    function c.setMacroPopup(spec)
        spec = spec or {}
        if type(spec.missing) == "table" and #spec.missing > 0 then
            s.macroMissing = {}
            for i = 1, #spec.missing do s.macroMissing[i] = spec.missing[i] end
            s.macroPopup = nil
            return
        end
        s.macroMissing = nil
        local p = { icons = {}, isOpen = false }
        for i, v in ipairs(spec.icons or {}) do p.icons[i] = v end
        local h, showFn, hideFn, onText, onFilter
        local list
        function p.visible()
            local out = {}
            for i, v in ipairs(list or p.icons) do out[i] = v end
            return out
        end
        function p.open()
            p.isOpen, list = true, nil
            if showFn then showFn() end
        end
        function p.close()
            p.isOpen, list = false, nil
            if hideFn then hideFn() end
        end
        function p.click(i) p.selected = p.visible()[i] end
        function p.type(text)
            if not p.box then return false end
            p.box.text = tostring(text)
            if onText then onText(p.box.text) end
            return true
        end
        function p.filter(kind)
            if not p.box then return false end
            if onFilter then onFilter(kind) end
            return true
        end
        h = {}
        function h.shown() return p.isOpen end
        function h.count()
            if not p.isOpen then return nil end
            return #p.icons
        end
        function h.icon(i)
            if not p.isOpen then return nil end
            return p.icons[i]
        end
        function h.show(shown)
            if not p.isOpen then return false end
            if shown == nil then
                list = nil
                return true
            end
            list = {}
            for i, v in ipairs(shown) do list[i] = v end
            return true
        end
        function h.onShow(fn) showFn = type(fn) == "function" and fn or nil end
        function h.onHide(fn) hideFn = type(fn) == "function" and fn or nil end
        local b
        function h.addBox(boxSpec)
            if b then return b end
            if s.noFrames or type(boxSpec) ~= "table" then return nil end
            onText, onFilter = boxSpec.onText, boxSpec.onFilter
            p.box = { text = "", hint = nil, shown = true }
            b = {}
            function b.setText(text)
                p.box.text = type(text) == "string" and text or ""
                if onText then onText(p.box.text) end
            end
            function b.hint(text) p.box.hint = type(text) == "string" and text or "" end
            function b.show(on) p.box.shown = on and true or false end
            return b
        end
        p.handle = h
        s.macroPopup = p
        c.macroPopups[#c.macroPopups + 1] = p
    end
    function c.macroPopup()
        if s.macroMissing then
            local out = {}
            for i = 1, #s.macroMissing do out[i] = s.macroMissing[i] end
            return nil, out
        end
        if not s.macroPopup then return nil, { "MacroPopupFrame" } end
        return s.macroPopup.handle
    end
    function c.setSpellbook(list) s.spellbook = list end
    function c.spellbookIcons()
        c.spellbookReads = c.spellbookReads + 1
        if type(s.spellbook) ~= "table" then return nil end
        local out = {}
        for i, row in ipairs(s.spellbook) do out[i] = { name = row.name, icon = row.icon } end
        return out
    end

    -- PRIEST-3 (P-SELFBUFF): your own debuffs by name, as the real client's
    -- playerDebuffs(): a copy of the map set, nil when none was set.
    function c.setPlayerDebuffs(map) s.playerDebuffs = type(map) == "table" and map or nil end
    function c.playerDebuffs()
        if type(s.playerDebuffs) ~= "table" then return nil end
        local out = {}
        for k, v in pairs(s.playerDebuffs) do out[k] = v end
        return out
    end
    -- S12 care key (P-KEYS slice A): the twin of Core/Client.lua c.unitCare.
    --   c.setUnitCare(unit, row)   { exists, friend, isSelf, dead, hurt }
    --                              (a field left out: not known); nil: not known
    --   c.setUnitCareFails(on)     the read raises while on (lead section
    --                              236: a read that fails, then recovers)
    function c.setUnitCare(unit, row)
        s.unitCare = s.unitCare or {}
        if type(row) == "table" then s.unitCare[unit] = row else s.unitCare[unit] = nil end
    end
    function c.setUnitCareFails(on) s.unitCareFails = (on == true) end
    function c.unitCare(unit)
        if s.unitCareFails then error("unit care read failed (test)") end
        local row = s.unitCare and s.unitCare[unit]
        if type(row) ~= "table" then return nil end
        local out = {}
        for k, v in pairs(row) do out[k] = v end
        return out
    end
    -- N2 (P-KEYS slice D): the twin of Core/Client.lua c.targetCorpse;
    -- nil (not known) until set. N20 uses the N24 c.tradeSkillTools(index).
    --   c.setTargetCorpse(row)       { exists, dead, player, lootable, needs }
    --   c.setTargetCorpseFails(on)   the read raises while on (lead section
    --                                236: a read that fails, then recovers)
    function c.setTargetCorpse(row)
        if type(row) == "table" then s.targetCorpse = row else s.targetCorpse = nil end
    end
    function c.setTargetCorpseFails(on) s.targetCorpseFails = (on == true) end
    function c.targetCorpse()
        if s.targetCorpseFails then error("target corpse read failed (test)") end
        if type(s.targetCorpse) ~= "table" then return nil end
        local out = {}
        for k, v in pairs(s.targetCorpse) do out[k] = v end
        return out
    end
    -- S15 click slots and S29 move handle (P-KEYS slice C). clickRow keeps
    -- every row it makes in c.clickRows: h.spec, h.slots[i] = { attrs,
    -- shown, icon }, h.shown (the row), h.point and h.given (every set
    -- asked, in order). Each set is also kept in c.secureGiven under the
    -- button name spec.name .. i, so secureMacros() sees it. Not made
    -- (nil) with frames off or while combatLockdown() is not a plain false;
    -- set, show and place answer false, "lockdown" then. moveHandle keeps
    -- spec in c.moveHandles[target] for a target a row was made under, and
    -- dragHandle(target, point) stands in for a drag that ends at point:
    -- false, "lockdown" in a fight, false, "absent" with no handle, else
    -- onMoved(point) and true.
    c.clickRows = {}
    c.moveHandles = {}
    function c.clickRow(spec)
        if s.noFrames then return nil end
        if type(spec) ~= "table" or type(spec.name) ~= "string" then return nil end
        if type(spec.count) ~= "number" or spec.count < 1 then return nil end
        if c.combatLockdown() ~= false then return nil end
        local h = { spec = spec, slots = {}, shown = false, point = nil, given = {} }
        for i = 1, spec.count do h.slots[i] = { attrs = {}, shown = false, icon = nil } end
        function h.set(i, attr, value)
            local slot = h.slots[i]
            if slot == nil then return false, "absent" end
            h.given[#h.given + 1] = { slot = i, attr = attr, value = value }
            c.secureGiven[#c.secureGiven + 1] = { name = spec.name .. i, attr = attr, value = value }
            if c.combatLockdown() ~= false then return false, "lockdown" end
            if secureFail[attr] then return false, "refused" end
            slot.attrs[attr] = value
            return true
        end
        function h.get(i, attr)
            local slot = h.slots[i]
            if slot == nil then return nil end
            return slot.attrs[attr]
        end
        function h.show(i, on)
            if i ~= 0 and h.slots[i] == nil then return false, "absent" end
            if c.combatLockdown() ~= false then return false, "lockdown" end
            if i == 0 then h.shown = on == true else h.slots[i].shown = on == true end
            return true
        end
        function h.isShown(i)
            if i == 0 then return h.shown end
            local slot = h.slots[i]
            return slot ~= nil and slot.shown
        end
        function h.icon(i, texture)
            local slot = h.slots[i]
            if slot == nil or texture == nil then return false end
            slot.icon = texture
            return true
        end
        function h.place(point)
            if type(point) ~= "table" then return false, "refused" end
            if c.combatLockdown() ~= false then return false, "lockdown" end
            h.point = { point[1], point[2], point[3], point[4] }
            return true
        end
        c.clickRows[#c.clickRows + 1] = h
        return h
    end
    function c.moveHandle(spec)
        if type(spec) ~= "table" or type(spec.target) ~= "string" then return nil end
        local found = false
        for _, row in ipairs(c.clickRows) do
            if row.spec.name == spec.target then found = true end
        end
        if not found then return nil end
        c.moveHandles[spec.target] = spec
        return { show = function() return true end }
    end
    function c.dragHandle(target, point)
        local spec = c.moveHandles[target]
        if spec == nil then return false, "absent" end
        if c.combatLockdown() ~= false then return false, "lockdown" end
        if type(spec.onMoved) == "function" then pcall(spec.onMoved, point) end
        return true
    end
    -- Flow and self buttons (Rotation/FlowButton.lua). Each helper answers
    -- nil for a name no clickRow made. buttonFace keeps { empty } in
    -- c.buttonFaces[button]. ctrlDrag keeps spec in c.ctrlDrags[target]
    -- (nil while combatLockdown() is not a plain false), and
    -- ctrlDragTo(target, point, ctrl) stands in for a drag that ends at
    -- point: false, "absent" with none; false, "noCtrl" without Ctrl held;
    -- false, "lockdown" in a fight; else onMoved(point) and true. hoverTip
    -- keeps spec in c.hoverTips[frame]; hoverTipText(frame) -> the line
    -- pointing at it shows, or nil.
    c.buttonFaces, c.ctrlDrags, c.hoverTips = {}, {}, {}
    local function rowButton(name)
        for _, row in ipairs(c.clickRows) do
            if row.spec.name == name then return true end
            for i = 1, row.spec.count do
                if row.spec.name .. i == name then return true end
            end
        end
        return false
    end
    function c.buttonFace(spec)
        if type(spec) ~= "table" or not rowButton(spec.button) then return nil end
        local face = { empty = false }
        c.buttonFaces[spec.button] = face
        return { empty = function(on) face.empty = on == true; return true end }
    end
    -- Lead section 409: the face also keeps label (spec.label) and dimmed
    -- (the last h.dim mode: "picture", "gone" or nil).
    -- Lead section 409: every icon also has h.fade(on); h.faded is the last.
    local unfadedIcon = c.icon
    function c.icon(spec)
        local h = unfadedIcon(spec)
        if type(h) ~= "table" then return h end
        function h.fade(on)
            h.faded = on == true
            return true
        end
        return h
    end
    local plainButtonFace = c.buttonFace
    function c.buttonFace(spec)
        local h = plainButtonFace(spec)
        if h == nil then return nil end
        local face = c.buttonFaces[spec.button]
        face.label = spec.label
        function h.dim(mode)
            if mode == "picture" or mode == "gone" then face.dimmed = mode else face.dimmed = nil end
            return true
        end
        return h
    end
    -- Lead section 415: dim also takes "word" (the plain face, no "?"),
    -- and h.mouse(on) keeps face.mouse; under the lock it changes nothing,
    -- answers false, "lockdown" and counts face.mouseInLock.
    local dimmedButtonFace = c.buttonFace
    function c.buttonFace(spec)
        local h = dimmedButtonFace(spec)
        if h == nil then return nil end
        local face = c.buttonFaces[spec.button]
        local dimOld = h.dim
        function h.dim(mode)
            if mode == "word" then face.dimmed = "word"; return true end
            return dimOld(mode)
        end
        function h.mouse(on)
            if c.combatLockdown() ~= false then
                face.mouseInLock = (face.mouseInLock or 0) + 1
                return false, "lockdown"
            end
            face.mouse = on == true
            return true
        end
        return h
    end
    function c.ctrlDrag(spec)
        if type(spec) ~= "table" or not rowButton(spec.target) or not rowButton(spec.button) then return nil end
        if c.combatLockdown() ~= false then return nil end
        c.ctrlDrags[spec.target] = spec
        return true
    end
    function c.ctrlDragTo(target, point, ctrl)
        local spec = c.ctrlDrags[target]
        if spec == nil then return false, "absent" end
        if ctrl ~= true then return false, "noCtrl" end
        if c.combatLockdown() ~= false then return false, "lockdown" end
        if type(spec.onMoved) == "function" then pcall(spec.onMoved, point) end
        return true
    end
    function c.hoverTip(spec)
        if type(spec) ~= "table" or type(spec.text) ~= "function" or not rowButton(spec.frame) then return nil end
        c.hoverTips[spec.frame] = spec
        return true
    end
    function c.hoverTipText(frame)
        local spec = c.hoverTips[frame]
        if spec == nil then return nil end
        local ok, text = pcall(spec.text)
        if not ok or type(text) ~= "string" then return nil end
        return text
    end
    -- Lead section 340: hoverTip also takes a named icon (c.icon with
    -- spec.name), as the real client takes any named frame: the rotation
    -- icon's tooltip.
    local iconNames = {}
    local namedIcon = c.icon
    function c.icon(spec)
        local h = namedIcon(spec)
        if type(h) == "table" and type(spec) == "table" and type(spec.name) == "string" then
            iconNames[spec.name] = true
        end
        return h
    end
    local rowTip = c.hoverTip
    function c.hoverTip(spec)
        if type(spec) == "table" and type(spec.text) == "function" and iconNames[spec.frame] then
            c.hoverTips[spec.frame] = spec
            return true
        end
        return rowTip(spec)
    end



    -- G16: the skill lines you know, as the real client's weaponSkills():
    --   c.setWeaponSkills({ "Swords", ... }) or nil (not read, the start);
    --   c.setWeaponSkillsFails(on): the read raises while on (lead
    --   section 236: a read that fails, then recovers).
    function c.setWeaponSkills(list) s.weaponSkills = type(list) == "table" and list or nil end
    function c.setWeaponSkillsFails(on) s.weaponSkillsFails = on and true or nil end
    -- Lead section 337 item 2: the skill ranks for skillRanks(),
    -- { [name] = { rank, max } }; nil (the start): not read.
    function c.setSkillRanks(map)
        s.skillRanks = nil
        if type(map) == "table" then s.skillRanks = map end
    end
    function c.skillRanks()
        if type(s.skillRanks) ~= "table" then return nil end
        local out = {}
        for name, r in pairs(s.skillRanks) do out[name] = { rank = r.rank, max = r.max } end
        return out
    end
    function c.weaponSkills()
        if s.weaponSkillsFails then error("weapon skill read failed (test)") end
        if type(s.weaponSkills) ~= "table" then return nil end
        local out = {}
        for _, name in ipairs(s.weaponSkills) do out[name] = true end
        return out
    end

    -- G60: text-to-speech, as the real client's speech/speak/stopSpeech:
    --   c.setSpeech({ voices = { { voiceID, name } } }) or nil (the call
    --   absent, the start); c.setSpeakFails(n): the next n speak calls raise
    --   (lead section 236). c.spoken() -> what was said, { text, voice } in
    --   order; c.speakCalls() -> every speak asked; c.speechStops() -> stops.
    --   c.setNpcText(kind, text) / c.npcText(kind): the open window's words.
    s.spoken, s.speakCalls, s.speechStops, s.npcText = {}, 0, 0, {}
    function c.setSpeech(v)
        s.speech = nil
        if type(v) == "table" then s.speech = v end
    end
    function c.setSpeakFails(n) s.speakFails = type(n) == "number" and n or 0 end
    function c.speech()
        if type(s.speech) ~= "table" then return nil end
        local voices = {}
        for i, v in ipairs(s.speech.voices or {}) do voices[i] = { voiceID = v.voiceID, name = v.name } end
        -- Lead section 270: as given to setSpeech; left out (nil) is unknown.
        return { voices = voices, localPlayback = s.speech.localPlayback }
    end
    function c.speak(text, voice)
        s.speakCalls = s.speakCalls + 1
        if type(s.speech) ~= "table" then return false, "no text-to-speech call" end
        if (s.speakFails or 0) > 0 then
            s.speakFails = s.speakFails - 1
            error("speak failed (test)")
        end
        s.spoken[#s.spoken + 1] = { text = text, voice = voice }
        return true
    end
    function c.stopSpeech()
        if type(s.speech) ~= "table" then return false end
        s.speechStops = s.speechStops + 1
        return true
    end
    function c.spoken()
        local out = {}
        for i, v in ipairs(s.spoken) do out[i] = v end
        return out
    end
    function c.speakCalls() return s.speakCalls end
    function c.speechStops() return s.speechStops end
    function c.setNpcText(kind, text) s.npcText[kind] = text end
    function c.npcText(kind)
        local v = s.npcText[kind]
        if type(v) ~= "string" or v == "" then return nil end
        return v
    end
    -- P-QOL: the open window's NPC, "male", "female" or nil (not known,
    -- the start), as the real client's npcSex.
    function c.setNpcSex(v) s.npcSex = v end
    function c.npcSex()
        if s.npcSex == "male" or s.npcSex == "female" then return s.npcSex end
        return nil
    end
    -- N39 and N40 (P-KEYS slice E): the target's name and the spell it
    -- casts, as the real client's; setTargetCastFails makes the read raise.
    function c.setTargetName(name) s.targetName = name end
    function c.targetName()
        if type(s.targetName) ~= "string" or s.targetName == "" then return nil end
        return s.targetName
    end
    function c.setTargetCast(name) s.targetCast = name end
    function c.setTargetCastFails(on) s.targetCastFails = on == true end
    function c.targetCast()
        if s.targetCastFails then error("the target cast read failed (test)") end
        if type(s.targetCast) == "string" and s.targetCast ~= "" then return s.targetCast end
        return false
    end

    -- G51: the creature on a nameplate and the quest mark over it, as the
    -- real client.plateCreature and client.plateQuestMark:
    --   c.setPlateCreature(unit, npcId) (nil: not known);
    --   c.setPlateCreatureFails(on): the read raises while on (lead
    --   section 236: a read that fails, then recovers).
    -- c.plateQuestMarks[i]: .unit, .shown, .says, .rgb; one per call, as
    --   plateLabels. A mark needs the plate on screen (c.addPlate).
    do
        local creatures = {}
        local function isPlate(unit)
            return type(unit) == "string" and unit:find("^nameplate%d+$") ~= nil
        end
        function c.setPlateCreature(unit, id) creatures[unit] = id end
        function c.setPlateCreatureFails(on) s.plateCreatureFails = on and true or nil end
        function c.plateCreature(unit)
            if s.plateCreatureFails then error("plate creature read failed (test)") end
            if not isPlate(unit) then return nil end
            return creatures[unit]
        end
        c.plateQuestMarks = {}
        function c.plateQuestMark(unit)
            if s.noFrames or not isPlate(unit) or not (s.plates and s.plates[unit]) then return nil end
            local h = { unit = unit, shown = false }
            function h.show(on) h.shown = on and true or false end
            function h.text(text)
                if type(text) == "string" then h.says = text end
            end
            function h.color(r, g, b)
                if type(r) == "number" and type(g) == "number" and type(b) == "number" then h.rgb = { r, g, b } end
            end
            c.plateQuestMarks[#c.plateQuestMarks + 1] = h
            return h
        end
    end
    -- N68: the alert sound, as the real client's playAlert(). Each sound
    -- played is recorded; c.setAlertSound({ fail = why }) makes it fail
    -- with why ("noCall", "raised"), nothing played.
    local alertsPlayed = {}
    function c.setAlertSound(opts) s.alertSound = type(opts) == "table" and opts or nil end
    function c.playAlert()
        local fail = s.alertSound and s.alertSound.fail
        if fail then return nil, fail end
        alertsPlayed[#alertsPlayed + 1] = true
        return true
    end
    function c.alertsPlayed()
        local out = {}
        for i = 1, #alertsPlayed do out[i] = alertsPlayed[i] end
        return out
    end
    -- G14: the quest reward choices and the mark on one, as the real
    -- client's questChoices() and markRewardChoice(index):
    --   c.setQuestChoices({ { index, link } ... }) or nil (not readable,
    --     the start); a row without a link is a choice not loaded yet;
    --   c.setQuestChoicesFails(on): the read raises while on (lead
    --     section 236: a read that fails, then recovers);
    --   c.rewardMarked(): the choice marked now, or nil.
    do
        local rewardMark, rewardKind = nil, nil
        function c.setQuestChoices(rows)
            if type(rows) == "table" then s.questChoices = rows else s.questChoices = nil end
        end
        function c.setQuestChoicesFails(on) s.questChoicesFails = on == true end
        function c.questChoices()
            if s.questChoicesFails then error("quest choice read failed (test)") end
            if type(s.questChoices) ~= "table" then return nil end
            local out = {}
            for i, row in ipairs(s.questChoices) do out[i] = { index = row.index, link = row.link } end
            return out
        end
        function c.markRewardChoice(index, kind)
            if type(index) ~= "number" then
                rewardMark, rewardKind = nil, nil
                return nil
            end
            rewardMark, rewardKind = index, kind
            return true
        end
        function c.rewardMarked() return rewardMark end
        -- G14 coin: "upgrade" (the arrow) or "coin" (sell it), or nil.
        function c.rewardMarkKind() return rewardKind end
    end
    -- G14 bag badge: the marks drawn on bag slots, as the real client's
    -- markBagSlots(marks): c.bagMarks() is a copy of the last marks, {}
    -- before any.
    do
        local bagMarks = {}
        function c.markBagSlots(marks)
            bagMarks = {}
            for i, m in ipairs(type(marks) == "table" and marks or {}) do
                bagMarks[i] = { bag = m.bag, slot = m.slot, text = m.text }
            end
            return #bagMarks
        end
        function c.bagMarks()
            local out = {}
            for i, m in ipairs(bagMarks) do out[i] = { bag = m.bag, slot = m.slot, text = m.text } end
            return out
        end
    end
    -- S21: the value on a loot roll's item, as the real client's
    -- rollValue(rollID, text, r, g, b): true, kept per roll; no text clears
    -- it. c.rollValueOf(rollID) -> { text, r, g, b } shown now, or nil.
    do
        local rollValues = {}
        function c.rollValue(rollID, text, r, g, b)
            if type(rollID) ~= "number" then return nil end
            if type(text) ~= "string" or text == "" then
                rollValues[rollID] = nil
                return true
            end
            rollValues[rollID] = { text = text, r = r, g = g, b = b }
            return true
        end
        function c.rollValueOf(rollID)
            local v = rollValues[rollID]
            if v == nil then return nil end
            return { text = v.text, r = v.r, g = v.g, b = v.b }
        end
    end

    -- S19 (P-SETS branch 2): the set icon row, as the real client's
    -- iconRow(spec). c.iconRows[i] is each row made, in order: .spec,
    -- .icons (the last draw, copied, at most 12), .point (the last place),
    -- shown(). press(key) is the player's left click on that icon: false
    -- when no such icon is drawn or no act was given, else act(key) under
    -- pcall and true. drag(point) is the player moving the row: the
    -- onMoved fn is told point (its error goes to the failed fn).
    c.iconRows = {}
    function c.iconRow(spec)
        if s.noFrames then return nil end
        local h = { spec = spec, icons = {}, places = 0 }
        local open, act, moved, movedFailed = false, nil, nil, nil
        function h.draw(icons, fn)
            h.icons = {}
            for _, icon in ipairs(type(icons) == "table" and icons or {}) do
                if #h.icons >= 12 then break end
                if type(icon) == "table" then
                    local copy = {}
                    for k, v in pairs(icon) do copy[k] = v end
                    h.icons[#h.icons + 1] = copy
                end
            end
            act = type(fn) == "function" and fn or nil
        end
        function h.show(on) open = on and true or false end
        function h.shown() return open end
        function h.place(point)
            if type(point) ~= "table" then return end
            h.point = { point[1], point[2], point[3], point[4] }
            h.places = h.places + 1
        end
        function h.onMoved(fn, failed)
            moved = type(fn) == "function" and fn or nil
            movedFailed = type(failed) == "function" and failed or nil
        end
        function h.press(key)
            for _, icon in ipairs(h.icons) do
                if icon.key == key then
                    if not act then return false end
                    pcall(act, key)
                    return true
                end
            end
            return false
        end
        function h.drag(point)
            h.point = { point[1], point[2], point[3], point[4] }
            if not moved then return end
            local ok, err = pcall(moved, point)
            if not ok and movedFailed then pcall(movedFailed, err) end
        end
        c.iconRows[#c.iconRows + 1] = h
        return h
    end

    -- S19 (acting): equipItem, as the real client's. Every call is counted
    -- in c.equipCalls (the recorder: a call without the click is seen);
    -- each item put on is in c.equips { item =, slot = }. Out of combat
    -- only: combat true or not known (setCombatUnknown) answers "combat".
    -- setEquipFails(n): the next n calls raise ("raised"), then it works.
    c.equips, c.equipCalls = {}, 0
    function c.setEquipFails(n) s.equipFails = n end
    function c.setCombatUnknown(on)
        if on then s.combat = nil else s.combat = false end
    end
    function c.equipItem(item, slot)
        c.equipCalls = c.equipCalls + 1
        if s.combat ~= false then return nil, "combat" end
        if (s.equipFails or 0) > 0 then
            s.equipFails = s.equipFails - 1
            return nil, "raised"
        end
        c.equips[#c.equips + 1] = { item = item, slot = slot }
        return true
    end

    -- S20 vendor marks (lead section 230): the merchant's pages, the
    -- per-role badges, and the money read raising. As the real client's
    -- markMerchantSpecs(badges) (badges { [item number] = { { role, state }
    -- ... } }) and markMerchantButtons, each draw is worked out for the page
    -- shown when it is called, so a page turned without a redraw keeps the
    -- old marks:
    --   c.setMerchantPage(page, perPage)   (page 1, 10 a page at the start)
    --   c.merchantButtons() -> { [button] = { up = arrow shown, specs = { { role,
    --     state } ... } } } for the buttons showing anything; {} when closed.
    --   c.setMoneyFails(on): money() raises while on (section 236).
    --   c.setMerchantTab(tab): MerchantFrame.selectedTab (1, on sale, at the
    --     start); any other tab is the buyback tab, where nothing is drawn
    --     and markMerchantSpecs gives 0, as the real client.
    -- As the real client, at most 12 buttons are drawn whatever the page size.
    do
        local BUTTONS = 12
        local page, per, tab = 1, 10, 1
        local specsNow, drawn = nil, {}
        local function draw()
            drawn = {}
            local arrows = c.merchantMarked()
            if s.merchantOpen ~= true or (tab ~= nil and tab ~= 1) then return end
            for i = 1, math.min(per, BUTTONS) do
                local index = (page - 1) * per + i
                local up = type(arrows) == "table" and arrows[index] == true
                local list = nil
                if type(specsNow) == "table" then list = specsNow[index] end
                if up or list ~= nil then
                    local copy = {}
                    for j, b in ipairs(list or {}) do copy[j] = { role = b.role, state = b.state } end
                    drawn[i] = { up = up, specs = copy }
                end
            end
        end
        function c.setMerchantPage(p, n)
            if type(p) == "number" then page = p end
            if type(n) == "number" then per = n end
        end
        function c.setMerchantTab(n) tab = n end
        local plainMark = c.markMerchantButtons
        function c.markMerchantButtons(indexes)
            local n = plainMark(indexes)
            draw()
            return n
        end
        function c.markMerchantSpecs(badges)
            if s.merchantOpen ~= true then
                specsNow = nil
                draw()
                return nil
            end
            specsNow = {}
            for index, list in pairs(type(badges) == "table" and badges or {}) do
                if type(index) == "number" and type(list) == "table" then specsNow[index] = list end
            end
            draw()
            local n = 0
            for _, b in pairs(drawn) do
                if #b.specs > 0 then n = n + 1 end
            end
            return n
        end
        function c.merchantButtons()
            local out = {}
            for i, b in pairs(drawn) do
                local copy = {}
                for j, x in ipairs(b.specs) do copy[j] = { role = x.role, state = x.state } end
                out[i] = { up = b.up, specs = copy }
            end
            return out
        end
        local plainMoney = c.money
        function c.setMoneyFails(on) s.moneyFails = on == true end
        function c.money()
            if s.moneyFails then error("money read failed (test)") end
            return plainMoney()
        end
    end
    -- N60a: chat (UI/Chat.lua). chatLines, chatFilter, onLinkClick and
    -- pratModule answer as the real client's do. The test's controls:
    --   c.setChatLines(index, { text, ... })  what a chat window holds; nil:
    --                              the window is not there (the start)
    --   c.pushChat(event, text[, index]) -> shown
    --                              one chat line arrives: it goes through
    --                              every filter of that event, as the game
    --                              runs them, and what comes out is added to
    --                              window `index` (1 when left out) and
    --                              returned. What is no text passes unread.
    --   c.chatFilterCount(event)   how many filters that event has now
    --   c.clickLink(link) -> n     the player clicks a chat link (the text
    --                              between |H and |h): the game handles it
    --                              itself (c.linkClicks, every click in
    --                              order), then every listener of its kind
    --                              is told; n is how many were
    --   c.setPratModule(name, on)  what Prat says of its module: true,
    --                              false, or nil for nothing (the start)
    --   c.setChatFilters(false)    a client with no chat filter
    --   c.setLinkHook(false)       a client with no link click to follow
    do
        local CHAT_LINES_MAX = 500
        local windows, filters, kinds, prat = {}, {}, {}, {}
        c.linkClicks = {}

        function c.setChatLines(index, list)
            if type(list) ~= "table" then windows[index] = nil return end
            local copy = {}
            for i = 1, #list do copy[i] = list[i] end
            windows[index] = copy
        end
        function c.chatLines(index, max)
            local all = windows[index]
            if type(all) ~= "table" then return nil end
            max = math.floor(tonumber(max) or CHAT_LINES_MAX)
            if max < 1 then max = 1 end
            if max > CHAT_LINES_MAX then max = CHAT_LINES_MAX end
            local texts = {}
            for i = 1, #all do
                if type(all[i]) == "string" then texts[#texts + 1] = all[i] end
            end
            local from = #texts - max + 1
            if from < 1 then from = 1 end
            local out = {}
            for i = from, #texts do out[#out + 1] = texts[i] end
            return out
        end

        function c.setChatFilters(on) s.noChatFilter = on == false end
        function c.chatFilter(events, fn)
            if s.noChatFilter or type(events) ~= "table" or type(fn) ~= "function" then return nil end
            local entry = { events = {}, fn = fn }
            local any = false
            for _, event in ipairs(events) do
                if type(event) == "string" and event ~= "" then
                    entry.events[event] = true
                    any = true
                end
            end
            if not any then return nil end
            filters[#filters + 1] = entry
            return function()
                for i = #filters, 1, -1 do
                    if filters[i] == entry then table.remove(filters, i) end
                end
            end
        end
        function c.chatFilterCount(event)
            local n = 0
            for i = 1, #filters do
                if filters[i].events[event] then n = n + 1 end
            end
            return n
        end
        -- N60d: info { guid =, channel = } is the line's GUID and channel
        -- text; a filter's second answer { channel = } changes the channel
        -- text. The channel text shown is the second return.
        function c.pushChat(event, text, index, author, info)
            local shown = text
            local channel = nil
            if type(info) == "table" then channel = info.channel end
            for i = 1, #filters do
                if filters[i].events[event] and type(shown) == "string" then
                    local view = {}
                    if type(info) == "table" then view.guid, view.line = info.guid, info.line end
                    view.channel = channel
                    local ok, new, change = pcall(filters[i].fn, shown, event, author, view)
                    -- N60e: { hide = true } hides the line: no later
                    -- filter sees it, no window gets it, nil comes back.
                    if ok and type(change) == "table" and change.hide == true then return nil, channel end
                    if ok and type(new) == "string" then shown = new end
                    if ok and type(change) == "table" and type(change.channel) == "string" and channel ~= nil then
                        channel = change.channel
                    end
                end
            end
            index = index or 1
            windows[index] = windows[index] or {}
            table.insert(windows[index], shown)
            return shown, channel
        end

        function c.setLinkHook(on) s.noLinkHook = on == false end
        function c.onLinkClick(kind, fn)
            if s.noLinkHook or type(kind) ~= "string" or kind == "" or type(fn) ~= "function" then return nil end
            kinds[kind] = fn
            return function()
                if kinds[kind] == fn then kinds[kind] = nil end
            end
        end
        function c.clickLink(link)
            c.linkClicks[#c.linkClicks + 1] = link
            if type(link) ~= "string" then return 0 end
            local n = 0
            for kind, fn in pairs(kinds) do
                if link:sub(1, #kind + 1) == kind .. ":" then
                    n = n + 1
                    pcall(fn, link:sub(#kind + 2))
                end
            end
            return n
        end

        function c.setPratModule(name, on) prat[name] = on end
        function c.pratModule(name)
            local on = prat[name]
            if type(on) ~= "boolean" then return nil end
            return on
        end
    end
    -- RH-1 (lead section 279): a client on which no roll frame is found.
    -- c.setRollFrame(false): as the real client's show (F4) then does,
    -- offerRoll's show prints the link and the text once per roll offered,
    -- unless told { quiet = true } (show's trailing table), nothing is
    -- shown above a roll, and rollValue draws nothing (nil).
    -- c.setRollFrame(true): roll frames are found again (as made).
    do
        local plainOffer, plainValue = c.offerRoll, c.rollValue
        function c.setRollFrame(on) s.noRollFrame = on == false end
        function c.offerRoll(rollID, link)
            if not s.noRollFrame then return plainOffer(rollID, link) end
            local printed = false
            local function show(text, _, _, _, opts)
                if type(text) ~= "string" or text == "" then return end
                local quiet = type(opts) == "table" and opts.quiet == true
                if printed or quiet then return end
                printed = true
                c.print(ns.id.title .. ": " .. tostring(link) .. " " .. text)
            end
            for _, fn in ipairs({ unpack(s.rollListeners or {}) }) do fn(rollID, link, show) end
            return {}
        end
        function c.rollValue(rollID, ...)
            if s.noRollFrame then return nil end
            return plainValue(rollID, ...)
        end
    end

    -- Lead section 303 (Dungeon Quests). c.setRaceId(n) (nil: not known);
    -- c.setQuestDone(id, true / false / nil). Not set: not known.
    function c.setRaceId(n) s.raceId = n end
    function c.raceId() return s.raceId end
    function c.setQuestDone(id, v)
        s.questDone = s.questDone or {}
        s.questDone[id] = v
    end
    function c.questDone(id)
        if type(id) ~= "number" then return nil end
        return s.questDone and s.questDone[id]
    end

    -- The window kit's login probe (lead DISPATCH section 297 item 3 and
    -- section 303 item 5): kitProbe(rows), as the real client's, answered
    -- from a script; nothing is made or drawn.
    --   c.setKitProbe(fnOrTable)   a table { [row id] = text } or a function
    --     (row) -> text; a row it gives no text for answers "works", and so
    --     does every row with no script (as made). A table's EJ_LOADED is
    --     the journal answer; without one it is "yes" when
    --     setLoaded("Blizzard_EncounterJournal", true) was said, else "no".
    --     A function that raises makes kitProbe raise.
    --   c.setKitProbeCombat(on)    the probe is refused (nil, "combat")
    --     while on. Combat true or not known (setCombat, setCombatUnknown)
    --     refuses it too, as the real client's InCombatLockdown does.
    --   c.kitProbeCalls            every call, refused ones too.
    do
        local JOURNAL = "Blizzard_EncounterJournal"
        local script, refusing = nil, false
        c.kitProbeCalls = 0
        function c.setKitProbe(fnOrTable) script = fnOrTable end
        function c.setKitProbeCombat(on) refusing = on and true or false end
        function c.kitProbe(rows)
            c.kitProbeCalls = c.kitProbeCalls + 1
            if refusing or s.combat ~= false then return nil, "combat" end
            local out = {}
            if type(rows) == "table" then
                for i = 1, #rows do
                    local row = rows[i]
                    if type(row) == "table" and type(row.id) == "string" then
                        local text = nil
                        if type(script) == "function" then
                            text = script(row)
                        elseif type(script) == "table" then
                            text = script[row.id]
                        end
                        if type(text) ~= "string" then text = "works" end
                        out[row.id] = text
                    end
                end
            end
            local journal = nil
            if type(script) == "table" then journal = script.EJ_LOADED end
            if type(journal) ~= "string" then
                if s.loaded[JOURNAL] == true then journal = "yes" else journal = "no" end
            end
            out.EJ_LOADED = journal
            return out
        end
    end

    -- The window kit (lead sections 287, 291 item 1 and 292): c.kitWindow
    -- and c.kitProbe, as the real client's. Nothing is drawn; a window is
    -- recorded by its id.
    --   c.kitWindows() -> { [id] = { shown, point, width, height,
    --     parts = { { kind, path, key, text, note } ... in Kit.Each order } } }
    --     (a copy)
    -- The test's controls, each standing in for the player; each answers
    -- true when the part's own function was run, false when there is no such
    -- window or part, the part is not of that kind, or it is disabled (a
    -- part is disabled by its own enabled = false or its row's):
    --   c.kitClick(id, pathOrKey)        a button, a bind button, or a check
    --                                    box (which turns over and tells
    --                                    onToggle its new state)
    --   c.kitSelect(id, pathOrKey, i)    tabs, a topic list, a choice
    --   c.kitType(id, pathOrKey, text)   a header's search box, a text box
    --   c.kitChange(id, pathOrKey, v)    a number, within its min and max
    --   c.kitClose(id)                   the player closes it: onClose once;
    --                                    false when it is not shown
    --   c.kitDrag(id, point, w, h)       moved or resized: onMoved
    --   c.setKitFails(n)                 the next n kitWindow calls answer
    --                                    nil (and tell failed)
    --   c.setKitProbe(result, reason)    what kitProbe answers out of
    --                                    combat (nil, reason for none)
    -- A caller function that raises goes to extra.failed, as on the real
    -- client. setFrames(false) makes kitWindow answer nil. The art is the
    -- default client's: every name in Kit.look.unproven is "fallback".
    do
        local kits = {}   -- id -> { handle =, rec =, tree =, cb =, parts = { [path or key] = entry }, slots = }
        local kitFails = 0

        local function deep(v)
            if type(v) ~= "table" then return v end
            local out = {}
            for key, value in pairs(v) do out[key] = deep(value) end
            return out
        end
        local function told(w, fn, ...)
            if type(fn) ~= "function" then return end
            local ok, err = pcall(fn, ...)
            if not ok and type(w.cb.failed) == "function" then pcall(w.cb.failed, err) end
        end
        -- Reads a tree into the window: the record's parts, and each part
        -- by its path and by its key, with whether it can be used.
        local function read(w, tree)
            local list, byName, slots = {}, {}, {}
            local byPart = {}
            local size = ns.Kit.look.size
            local function one(part, live)
                local entry = { part = part, live = live and part.enabled ~= false, checked = part.checked == true }
                local row = { kind = part.kind, path = part.path, key = part.key, text = ns.Kit.TextOf(part),
                    note = part.note }
                -- Lead section 408: a line that wraps, and the rows the
                -- fake takes it to fill (c.KIT_LETTER wide a letter: a
                -- count, not the game's fonts).
                if part.kind == "line" and part.wrap == true then
                    local room = (w.rec.width or tree.width) - 2 * size.pad - 2 * size.gapSmall
                    local per = math.max(math.floor(room / c.KIT_LETTER), 1)
                    row.wrap = true
                    row.rows = math.max(math.ceil(#tostring(row.text or "") / per), 1)
                end
                byPart[part] = row
                list[#list + 1] = row
                byName[part.path] = entry
                if part.kind ~= "bind" and part.key ~= nil then byName[part.key] = entry end
                if part.kind == "footer" and part.slot ~= nil then slots[part.slot] = { slot = part.slot } end
                return entry
            end
            local function walk(parts)
                for i = 1, #(parts or {}) do
                    local part = parts[i]
                    local entry = one(part, true)
                    if part.control then one(part.control, entry.live) end
                    if part.children then walk(part.children) end
                    if part.buttons then walk(part.buttons) end
                end
            end
            walk(tree.children)
            w.tree, w.parts, w.slots, w.rec.parts = tree, byName, slots, list
            w.rec.title = tree.title
            -- As the real client's fit (lead section 408): the title bar,
            -- the padding and the parts. The fake knows the height of lines
            -- only; any other part counts as one row.
            if tree.fit == true then
                local tall = 0
                for i = 1, #tree.children do
                    local part = tree.children[i]
                    if part.kind == "line" and type(part.sub) == "string" and part.sub ~= "" then
                        tall = tall + size.rowHeightDesc
                    elseif byPart[part] ~= nil and byPart[part].rows ~= nil then
                        tall = tall + byPart[part].rows * size.lineHeight
                    else
                        tall = tall + size.lineHeight
                    end
                end
                w.rec.height = size.title + 2 * size.pad + tall
            end
        end
        -- The window, and the part of that path or key when it can be used.
        local function entryOf(id, name)
            local w = kits[id]
            if w == nil or name == nil then return nil, nil end
            local entry = w.parts[name]
            if entry == nil or not entry.live then return w, nil end
            return w, entry
        end

        -- As the real client's: the probe's answers are kept (c.kitSaid()
        -- reads them back in a test), and c.kitDrawnTell(id, art) stands in
        -- for a draw telling the listener.
        local said, drawnFn = {}, nil
        function c.kitKnown(rows)
            said = {}
            if type(rows) ~= "table" then return end
            for id, text in pairs(rows) do
                if type(id) == "string" and type(text) == "string" then said[id] = text end
            end
        end
        function c.kitSaid()
            local out = {}
            for id, text in pairs(said) do out[id] = text end
            return out
        end
        function c.onKitDrawn(fn)
            if type(fn) == "function" then drawnFn = fn else drawnFn = nil end
        end
        function c.kitDrawnTell(id, art)
            if drawnFn ~= nil then pcall(drawnFn, id, art) end
        end
        function c.setKitFails(n) kitFails = tonumber(n) or 0 end
        -- How wide the fake takes one letter of a wrapping line to be.
        c.KIT_LETTER = 7
        function c.kitWindow(id, tree, extra)
            local cb = type(extra) == "table" and extra or {}
            local bad = s.noFrames or type(id) ~= "string" or type(tree) ~= "table" or tree.kind ~= "window"
                or type(tree.children) ~= "table"
            if kitFails > 0 then
                kitFails = kitFails - 1
                bad = true
            end
            if bad then
                if type(cb.failed) == "function" then pcall(cb.failed, "no kit window (test)") end
                return nil
            end
            local w = kits[id]
            if w ~= nil then
                w.cb = cb
                read(w, tree)
                return w.handle
            end
            local point = type(cb.point) == "table" and cb.point or tree.point
            w = { cb = cb, rec = { shown = false, point = { point[1], point[2], point[3], point[4] },
                width = tonumber(cb.width) or tree.width, height = tonumber(cb.height) or tree.height } }
            read(w, tree)
            local h = {}
            function h.update(now)
                if type(now) ~= "table" or now.kind ~= "window" or type(now.children) ~= "table" then return false end
                read(w, now)
                return true
            end
            -- As the real client's h.place (lead section 348): records the
            -- new place and size; the size never below the least size.
            function h.place(point, width, height)
                if point ~= nil then
                    if type(point) ~= "table" or type(point[1]) ~= "string" or type(point[2]) ~= "string"
                        or type(point[3]) ~= "number" or type(point[4]) ~= "number" then
                        return false, "a place is anchor, screen anchor, x, y"
                    end
                end
                for _, v in ipairs({ width or 1, height or 1 }) do
                    if type(v) ~= "number" or v ~= v or v <= 0 or v == math.huge then
                        return false, "a size is a number above 0"
                    end
                end
                if point ~= nil then w.rec.point = { point[1], point[2], point[3], point[4] } end
                if width ~= nil then w.rec.width = math.max(width, tonumber(w.tree.minWidth) or 0) end
                -- A window that fits keeps the height of its parts.
                if height ~= nil and w.tree.fit ~= true then
                    w.rec.height = math.max(height, tonumber(w.tree.minHeight) or 0)
                end
                return true
            end
            function h.show(on) w.rec.shown = on and true or false end
            function h.shown() return w.rec.shown end
            function h.close() w.rec.shown = false end
            -- As the real client draws: the four parts with no row of the
            -- parts list are the game's own; a part with a row is the game's
            -- own only when the login probe said its row works (kitKnown),
            -- else its plain form; pictures not yet seen are plain.
            function h.art()
                local out = { close = "first", check = "first", input = "first", scroll = "first" }
                for key, row in pairs({ frame = "T2", search = "T5", tab = "T7", button = "T16" }) do
                    local text = said[row]
                    if text == "works" then out[key] = "first" else out[key] = "fallback" end
                end
                for key in pairs(ns.Kit.look.unproven or {}) do out[key] = "fallback" end
                return out
            end
            function h.slot(name) return w.slots[name] end
            w.handle = h
            kits[id] = w
            return h
        end
        function c.kitWindows()
            local out = {}
            for id, w in pairs(kits) do out[id] = deep(w.rec) end
            return out
        end
        function c.kitClick(id, name)
            local w, entry = entryOf(id, name)
            if entry == nil then return false end
            local part = entry.part
            if part.kind == "button" or part.kind == "bind" then
                told(w, part.onClick)
                return true
            end
            -- A list row with a click, and a section that folds.
            if part.kind == "line" then
                if type(part.onClick) ~= "function" then return false end
                told(w, part.onClick)
                return true
            end
            if part.kind == "section" then
                if part.folded == nil then return false end
                told(w, part.onFold, not part.folded)
                return true
            end
            if part.kind == "checkbox" then
                entry.checked = not entry.checked
                told(w, part.onToggle, entry.checked)
                return true
            end
            return false
        end
        function c.kitSelect(id, name, i)
            local w, entry = entryOf(id, name)
            if entry == nil then return false end
            local part = entry.part
            if part.kind ~= "tabs" and part.kind ~= "topicList" and part.kind ~= "choice" then return false end
            if type(i) ~= "number" or part.items[i] == nil then return false end
            told(w, part.onSelect, i)
            return true
        end
        function c.kitType(id, name, text)
            local w, entry = entryOf(id, name)
            if entry == nil or type(text) ~= "string" then return false end
            local part = entry.part
            if part.kind == "header" and part.search ~= nil then
                told(w, part.search.onText, text)
                return true
            end
            if part.kind == "text" then
                told(w, part.onText, text)
                return true
            end
            return false
        end
        function c.kitChange(id, name, value)
            local w, entry = entryOf(id, name)
            if entry == nil or type(value) ~= "number" then return false end
            local part = entry.part
            if part.kind ~= "number" then return false end
            if part.min ~= nil and value < part.min then return false end
            if part.max ~= nil and value > part.max then return false end
            told(w, part.onChange, value)
            return true
        end
        function c.kitClose(id)
            local w = kits[id]
            if w == nil or not w.rec.shown then return false end
            w.rec.shown = false
            told(w, w.cb.onClose)
            return true
        end
        function c.kitDrag(id, point, width, height)
            local w = kits[id]
            if w == nil or type(point) ~= "table" then return false end
            w.rec.point = { point[1], point[2], point[3], point[4] }
            if type(width) == "number" then w.rec.width = width end
            if type(height) == "number" then w.rec.height = height end
            told(w, w.cb.onMoved, { point[1], point[2], point[3], point[4] }, w.rec.width, w.rec.height)
            return true
        end
    end
    -- The settings window (lead sections 285 item 3 and 303 item 2), as the
    -- real client's c.settingsWindow: the caller's tree goes to c.kitWindow
    -- above (so c.kitWindows, c.kitClick, c.kitSelect and c.kitType play the
    -- player on it), and what was drawn is kept where the Options page's
    -- was, so the reads a test already has are the window's:
    --   c.optionsRows(), c.optionsStatus(), c.optionsAct(key, value),
    --   c.optionsNav(kind, value), c.optionsDrag, c.optionsOpened(),
    --   c.optionsHide() (the player closes it), c.optionsPagesMade()
    -- and new here:
    --   c.optionsLayout() -> what stands beside the rows (a copy of the
    --     layout last drawn): title, topics, topic, search ...
    --   c.optionsShown() -> true while the window is shown
    --   c.setSettingsDrawFault(n)  the next n draws of the window raise;
    --     nothing is kept of a draw that raised
    -- setOptionsPage(false) plays a client with no settings window and no
    -- entry in the game's Options; setOptionsPageFault(n) makes the next n
    -- asks for the window raise.
    --
    -- The add-on's entry in the game's Options > AddOns is a page asked for
    -- with spec.entry = true. It is kept apart from the window:
    --   c.optionsEntry() -> { title, rows, status, shown } (the live record)
    --     or nil when no entry was asked for
    --   c.optionsEntryShow() -> true: the player opens the entry
    --   c.optionsEntryPress(key) -> true when that button of the entry is
    --     there and what it ran answered true
    do
        local pageBase = c.optionsPage
        local drawFaults = 0
        local entryNav, entryShow

        local function copyOf(v)
            if type(v) ~= "table" then return v end
            local out = {}
            for key, value in pairs(v) do out[key] = copyOf(value) end
            return out
        end

        function c.setSettingsDrawFault(n) drawFaults = tonumber(n) or 0 end
        function c.optionsLayout() return s.options and s.options.layout end
        function c.optionsShown() return s.options ~= nil and s.options.shown == true end

        function c.optionsPage(spec)
            if type(spec) ~= "table" or spec.entry ~= true then return pageBase(spec) end
            if s.noOptionsPage then return nil end
            local e = { title = spec.title, shown = false }
            local h, showFns = {}, {}
            s.optionsEntry, entryShow, entryNav = e, showFns, nil
            function h.open() return false end
            function h.onShow(fn) showFns[#showFns + 1] = fn end
            function h.shown() return e.shown end
            function h.draw(rows, _, nav)
                e.rows = copyOf(rows or {})
                entryNav = nil
                if type(nav) == "function" then entryNav = nav end
                return true
            end
            function h.status(text) e.status = text end
            return h
        end
        function c.optionsEntry() return s.optionsEntry end
        function c.optionsEntryShow()
            if not s.optionsEntry then return false end
            s.optionsEntry.shown = true
            for _, fn in ipairs(entryShow) do fn() end
            return true
        end
        function c.optionsEntryPress(key)
            if not s.optionsEntry or type(entryNav) ~= "function" then return false end
            for _, r in ipairs(s.optionsEntry.rows or {}) do
                for _, action in ipairs(type(r.actions) == "table" and r.actions or {}) do
                    if action.key == key and action.enabled ~= false then
                        return entryNav("action", key) == true
                    end
                end
            end
            return false
        end

        function c.settingsWindow(spec)
            if type(spec) ~= "table" or type(spec.id) ~= "string" or type(spec.build) ~= "function" then
                return nil
            end
            local base = pageBase({ title = spec.title, name = spec.name })
            if not base then return nil end
            local record = s.options
            local extra = { name = spec.name, point = spec.point, width = spec.width, height = spec.height,
                onMoved = spec.onMoved, failed = spec.failed }
            -- The player closing the kit window closes what the reads show.
            function extra.onClose()
                record.shown = false
                if type(spec.onClose) == "function" then spec.onClose() end
            end
            local h
            local page = {}
            function page.draw(rows, act, nav, layout)
                if drawFaults > 0 then
                    drawFaults = drawFaults - 1
                    error("the settings window could not be drawn (test)", 0)
                end
                local tree, why = spec.build(rows, act, nav, layout)
                if type(tree) ~= "table" then return false, why or "the settings window has no tree" end
                if h == nil then
                    h = c.kitWindow(spec.id, tree, extra)
                    if h == nil then return false, "the kit could not draw the settings window" end
                elseif h.update(tree) ~= true then
                    return false, "the kit could not draw the settings window again"
                end
                base.draw(rows, act, nav)
                record.layout = copyOf(layout)
                if type(layout) == "table" and layout.status ~= nil then base.status(layout.status) end
                return true
            end
            function page.open()
                if h == nil then return false, "the settings window was not drawn" end
                h.show(true)
                return base.open()
            end
            function page.hide()
                if h ~= nil then h.show(false) end
                record.shown = false
            end
            function page.shown() return record.shown == true end
            return page
        end
    end
    -- N60b: chat readability (UI/Chat.lua). chatFont, setChatFont,
    -- chatFading, setChatFading, chatWheel, chatTabAlpha and localTime
    -- answer as the real client's do. The test's controls:
    --   c.setChatFrame(i, { font =, fading =, time = })  chat window i is
    --                              there (nil: it is not, the start)
    --   c.chatFrame(i) -> record   { font, fading, time, tabAlpha, moves }:
    --                              moves lists each scroll step in order
    --                              ("up", "down", "top", "bottom")
    --   c.wheelChat(i, delta[, { ctrl =, shift = }])
    --                              one wheel notch: the game scrolls one
    --                              line, then the wheel hook runs
    --   c.fadeTab(i, alpha)        the game sets tab i's alpha (its fade)
    --   c.setLocalTime(h, m, s)    the local clock; nil: not known
    do
        local frames, wheels, tabHolds = {}, {}, {}
        local clockNow = nil

        function c.setChatFrame(i, spec)
            if type(spec) ~= "table" then frames[i] = nil return end
            frames[i] = { font = spec.font, fading = spec.fading == true, time = spec.time, tabAlpha = 1,
                asked = 1, moves = {} }
        end
        function c.chatFrame(i) return frames[i] end

        function c.chatFont(i)
            local f = frames[i]
            if f == nil then return nil end
            return f.font
        end
        function c.setChatFont(i, size)
            local f = frames[i]
            if f == nil or type(size) ~= "number" or size <= 0 then return nil end
            f.font = size
            return true
        end
        function c.chatFading(i)
            local f = frames[i]
            if f == nil then return nil end
            return { fading = f.fading, time = f.time }
        end
        function c.setChatFading(i, fading, time)
            local f = frames[i]
            if f == nil or type(fading) ~= "boolean" then return nil end
            f.fading = fading
            if type(time) == "number" and time > 0 then f.time = time end
            return true
        end

        function c.chatWheel(i, fn)
            if frames[i] == nil or type(fn) ~= "function" then return nil end
            local w = wheels[i] or {}
            wheels[i] = w
            w.fn = fn
            return function()
                if w.fn == fn then w.fn = nil end
            end
        end
        function c.wheelChat(i, delta, keys)
            local f = frames[i]
            if f == nil then return end
            keys = keys or {}
            local step = "down"
            if delta > 0 then step = "up" end
            f.moves[#f.moves + 1] = step
            local w = wheels[i]
            if w == nil or w.fn == nil then return end
            local ok, what = pcall(w.fn, delta, keys.ctrl == true, keys.shift == true)
            if not ok then return end
            if what == "top" or what == "bottom" then
                f.moves[#f.moves + 1] = what
            elseif type(what) == "number" and what >= 1 then
                for _ = 1, math.min(math.floor(what), 50) do f.moves[#f.moves + 1] = step end
            end
        end

        function c.chatTabAlpha(i, alpha)
            local f = frames[i]
            if f == nil then return nil end
            if type(alpha) == "number" then
                tabHolds[i] = alpha
                f.tabAlpha = alpha
            else
                tabHolds[i] = nil
                f.tabAlpha = f.asked
            end
            return true
        end
        function c.fadeTab(i, alpha)
            local f = frames[i]
            if f == nil then return end
            f.asked = alpha
            local hold = tabHolds[i]
            if hold ~= nil and alpha < hold then
                f.tabAlpha = hold
            else
                f.tabAlpha = alpha
            end
        end

        function c.setLocalTime(h, m, s)
            if type(h) ~= "number" then clockNow = nil return end
            clockNow = { h, m, s }
        end
        function c.localTime()
            if clockNow == nil then return nil end
            return clockNow[1], clockNow[2], clockNow[3]
        end
    end
    -- N60c: the player's own name, as the real client's playerName().
    --   c.setPlayerName(name)        the name; nil: not known (the start)
    --   c.setPlayerNameFails(on)     true: the read raises, until false
    -- c.pushChat's fourth argument is the line's author.
    do
        local playerNow, nameFails = nil, false
        function c.setPlayerName(name) playerNow = name end
        function c.setPlayerNameFails(on) nameFails = on == true end
        function c.playerName()
            if nameFails then error("player name read failed (test)") end
            if type(playerNow) ~= "string" or playerNow == "" then return nil end
            return playerNow
        end
    end

    -- G38: indoors; c.setIndoors(true | false | nil), nil for not known.
    function c.indoors() return s.indoors end
    function c.setIndoors(v)
        if v == nil then s.indoors = nil else s.indoors = v and true or false end
    end
    -- G47: a party member's position; c.setUnitPosition(unit, map, x, y),
    -- leave map out for not known.
    function c.unitPosition(unit)
        local p = s.unitPositions and s.unitPositions[unit]
        if type(p) ~= "table" then return nil end
        return { map = p.map, x = p.x, y = p.y }
    end
    function c.setUnitPosition(unit, map, x, y)
        s.unitPositions = s.unitPositions or {}
        s.unitPositions[unit] = map and { map = map, x = x, y = y } or nil
    end

    -- The minimap button (UI/MinimapButton.lua). Every one made is in
    -- c.minimapButtons, in order; nil and "no frame" after c.setFrames(false).
    -- Test controls on a handle h:
    --   h.click(button)  a click: "right", else a left click
    --   h.choose(key)    the player clicks the open menu's row with this
    --                    key; the menu closes first, as on the client
    --   h.menuItems      the open menu's rows; nil: closed
    --   h.drag(angle)    dragged to that angle (degrees, 0 right, 90 up) on
    --                    the rim and dropped: the drag function is told
    --                    dx, dy 50 from the middle at that angle, done true
    --   h.shown, h.x, h.y, h.places, h.tipLines, h.spec
    c.minimapButtons = {}
    function c.minimapButton(spec)
        if s.noFrames then return nil, "no frame" end
        local h = { spec = spec, shown = false, places = 0 }
        local clickFn, dragFn, pick
        function h.place(x, y)
            if type(x) ~= "number" or type(y) ~= "number" then return end
            h.x, h.y = x, y
            h.places = h.places + 1
        end
        function h.show(on)
            h.shown = on and true or false
            if not h.shown then h.menuItems, pick = nil, nil end
        end
        function h.menu(items, fn)
            if type(items) ~= "table" or #items == 0 then
                h.menuItems, pick = nil, nil
                return
            end
            h.menuItems, pick = items, type(fn) == "function" and fn or nil
        end
        function h.choose(key)
            local fn = pick
            h.menuItems, pick = nil, nil
            if fn then fn(key) end
        end
        function h.onClick(fn) clickFn = fn end
        function h.onDrag(fn) dragFn = fn end
        function h.tip(lines) h.tipLines = lines end
        function h.click(button)
            if type(clickFn) == "function" then clickFn(button == "right" and "right" or "left") end
        end
        function h.drag(angle)
            if type(dragFn) ~= "function" or type(angle) ~= "number" then return end
            local a = math.rad(angle)
            dragFn(math.cos(a) * 50, math.sin(a) * 50, true)
        end
        c.minimapButtons[#c.minimapButtons + 1] = h
        return h
    end

    -- Lead section 340: the real client's c.kitFocus and c.kitOwner. The
    -- fake has no mouse: the line is what c.setKitFocus last set.
    --   c.kitFocus() -> line;  c.kitOwner(frame) -> nil
    --   c.setKitFocus(line)   the line kitFocus answers next
    do
        local focusLine = "focus: nothing under the mouse"
        function c.kitFocus() return focusLine end
        function c.kitOwner() return nil end
        function c.setKitFocus(line)
            if type(line) == "string" then focusLine = line end
        end
    end

    -- N60d: chat part 4 (UI/Chat.lua). classOfGuid, chatNameByClass,
    -- setChatNameByClass, chatTypeHeader, setChatTypeHeader, editBox and
    -- setEditBox answer as the real client's do. The test's controls:
    --   c.setGuidClass(guid, class)   the class file a GUID reads as
    --   c.setGuidClassFails(on)       true: the GUID read raises, until false
    --   c.nameByClass(chatType)       the game's "colour names by class" now
    --   c.chatHeader(name)            the game's label text of a chat kind now
    --   c.editBoxState() -> { alt =, history = }  the main edit box now
    do
        local guidClass, guidFails = {}, false
        local byClass = {}
        local headers = {
            SAY = "%s says: ", YELL = "%s yells: ",
            GUILD = "|Hchannel:GUILD|h[Guild]|h %s: ", OFFICER = "|Hchannel:OFFICER|h[Officer]|h %s: ",
            PARTY = "|Hchannel:PARTY|h[Party]|h %s: ", PARTY_LEADER = "|Hchannel:PARTY|h[Party Leader]|h %s: ",
            RAID = "|Hchannel:RAID|h[Raid]|h %s: ", RAID_LEADER = "|Hchannel:RAID|h[Raid Leader]|h %s: ",
            RAID_WARNING = "[Raid Warning] %s: ",
            INSTANCE_CHAT = "|Hchannel:INSTANCE_CHAT|h[Instance]|h %s: ",
            INSTANCE_CHAT_LEADER = "|Hchannel:INSTANCE_CHAT|h[Instance Leader]|h %s: ",
        }
        local edit = { alt = true, history = 32 }

        function c.setGuidClass(guid, class) guidClass[guid] = class end
        function c.setGuidClassFails(on) guidFails = on == true end
        function c.classOfGuid(guid)
            if guidFails then error("GUID read failed (test)") end
            if type(guid) ~= "string" then return nil end
            return guidClass[guid]
        end

        function c.chatNameByClass(chatType)
            if type(chatType) ~= "string" then return nil end
            return byClass[chatType] == true
        end
        function c.setChatNameByClass(chatType, on)
            if type(chatType) ~= "string" or type(on) ~= "boolean" then return nil end
            byClass[chatType] = on
            return true
        end
        function c.nameByClass(chatType) return byClass[chatType] == true end

        function c.chatTypeHeader(name) return headers[name] end
        function c.setChatTypeHeader(name, text)
            if headers[name] == nil or type(text) ~= "string" then return nil end
            headers[name] = text
            return true
        end
        function c.chatHeader(name) return headers[name] end

        function c.editBox() return { alt = edit.alt, history = edit.history } end
        function c.setEditBox(alt, history)
            if type(alt) ~= "boolean" or type(history) ~= "number" then return nil end
            edit.alt, edit.history = alt, history
            return true
        end
        function c.editBoxState() return { alt = edit.alt, history = edit.history } end
    end

    -- G48 (P-TRIP): the real client's c.addonPrefix and c.addonSend. A send
    -- is recorded in c.addonSent ({ prefix, text, channel }) and delivered
    -- to this client and every linked one that took the prefix, as
    -- CHAT_MSG_ADDON (prefix, text, channel, sender), like the real echo.
    --   c.linkAddon(other)       other gets this client's sends (one way)
    --   c.setAddonRefuse(why)    every send answers nil, why (nil: sends)
    --   c.setAddonName(name)     the sender name others see ("Player")
    --   c.addonDeliver(prefix, text, channel, sender)   one message in
    -- Not in a party (c.setGrouped not true): nil, "not in a party".
    do
        local links, prefixes = {}, {}
        local addonRefusal
        local me = "Player"
        c.addonSent = {}
        function c.addonPrefix(prefix)
            if type(prefix) ~= "string" or prefix == "" or #prefix > 16 then return false end
            prefixes[prefix] = true
            return true
        end
        function c.addonDeliver(prefix, text, channel, sender)
            if prefixes[prefix] then c.fire("CHAT_MSG_ADDON", prefix, text, channel, sender) end
        end
        function c.addonSend(prefix, text, channel)
            if channel ~= "PARTY" then return nil, "only the party channel" end
            if type(prefix) ~= "string" or type(text) ~= "string" then return nil, "nothing to send" end
            if #text > 255 then return nil, "message too long" end
            if addonRefusal ~= nil then return nil, addonRefusal end
            if s.grouped ~= true then return nil, "not in a party" end
            c.addonSent[#c.addonSent + 1] = { prefix = prefix, text = text, channel = channel }
            for _, other in ipairs(links) do other.addonDeliver(prefix, text, channel, me) end
            c.addonDeliver(prefix, text, channel, me)
            return true
        end
        function c.linkAddon(other) links[#links + 1] = other end
        function c.setAddonRefuse(why) addonRefusal = why end
        function c.setAddonName(name) me = tostring(name) end
    end
    -- P-EVIDENCE+: the raw tracking list (c.trackingRaw) and the profession
    -- window's raw answers (c.tradeSkillAnswers), each a copy of what was
    -- set, in the real read's shape; nil when none is set (no such read).
    --   c.setTrackingRaw({ count = n, entries = { { form, kind, name, hasActive, active, ... } } })
    --   c.setTradeSkillAnswers({ open, rows, headers, expanded, collapsed, unknown, subClass, invSlot })
    local function evidenceCopy(v)
        if type(v) ~= "table" then return v end
        local out = {}
        for key, value in pairs(v) do out[key] = evidenceCopy(value) end
        return out
    end
    function c.setTrackingRaw(r) s.evidenceTracking = evidenceCopy(r) end
    function c.trackingRaw() return evidenceCopy(s.evidenceTracking) end
    function c.setTradeSkillAnswers(r) s.evidenceTradeAnswers = evidenceCopy(r) end
    function c.tradeSkillAnswers() return evidenceCopy(s.evidenceTradeAnswers) end
    -- The route beside the quest log and on the map, as the real client's
    -- questLogFrame(), showMap(), mapInfo(), routePins() and mapCard().
    --   c.setQuestLogFrame({ shown, right, top, height } or nil)
    --   c.mapsShown: every uiMapID showMap was asked for, in order; the
    --       world map then shows it (as c.setWorldMap).
    --   c.setMapInfo(map, { name, low, high } or nil)
    --   c.routePinSets[1].pins / .shown / .draws / .clears
    --   c.mapCards[1].card / .shown / .shows / .hides
    -- nil (or false for showMap) when setFrames(false).
    function c.setQuestLogFrame(t)
        s.questLogFrame = type(t) == "table"
            and { shown = t.shown == true, right = t.right, top = t.top, height = t.height } or nil
    end
    function c.questLogFrame()
        local t = s.questLogFrame
        if s.noFrames or not t then return nil end
        return { shown = t.shown, right = t.right, top = t.top, height = t.height }
    end
    c.mapsShown = {}
    function c.showMap(map)
        if s.noFrames or type(map) ~= "number" then return false end
        c.mapsShown[#c.mapsShown + 1] = map
        s.worldMap = map
        return true
    end
    function c.setMapInfo(map, info)
        s.mapInfo = s.mapInfo or {}
        s.mapInfo[map] = type(info) == "table" and { name = info.name, low = info.low, high = info.high } or nil
    end
    function c.mapInfo(map)
        local t = s.mapInfo and s.mapInfo[map]
        if not t then return nil end
        return { name = t.name, low = t.low, high = t.high }
    end
    c.routePinSets = {}
    function c.routePins()
        if s.noFrames then return nil end
        local h = { pins = {}, shown = false, draws = 0, clears = 0 }
        function h.map() return s.worldMap end
        function h.draw(pins)
            h.pins = copyRows(type(pins) == "table" and pins or {})
            h.shown = #h.pins > 0
            h.draws = h.draws + 1
            return true
        end
        function h.clear()
            h.pins, h.shown = {}, false
            h.clears = h.clears + 1
        end
        c.routePinSets[#c.routePinSets + 1] = h
        return h
    end
    c.mapCards = {}
    function c.mapCard()
        if s.noFrames then return nil end
        local h = { shown = false, shows = 0, hides = 0 }
        function h.show(card)
            if type(card) ~= "table" then return false end
            local lines = {}
            for i, l in ipairs(type(card.lines) == "table" and card.lines or {}) do lines[i] = l end
            h.card = { title = card.title, lines = lines }
            h.shown = true
            h.shows = h.shows + 1
            return true
        end
        function h.hide()
            h.shown = false
            h.hides = h.hides + 1
        end
        c.mapCards[#c.mapCards + 1] = h
        return h
    end
    -- Lead section 382: the name of a map's continent; nil until set.
    --   c.setMapContName(map, name)   name nil: not known
    function c.mapContName(map)
        return s.mapContNames and s.mapContNames[map] or nil
    end
    function c.setMapContName(map, name)
        s.mapContNames = s.mapContNames or {}
        s.mapContNames[map] = name
    end

    -- P-QUEST (lead section 354 item 4): c.setQuestShareable(id, true /
    -- false / nil). Not set: not known.
    function c.setQuestShareable(id, v)
        s.questShareable = s.questShareable or {}
        s.questShareable[id] = v
    end
    function c.questShareable(id)
        if type(id) ~= "number" then return nil end
        return s.questShareable and s.questShareable[id]
    end
    -- Section 401: the close-enemy reads, as the real client's; unknown (nil)
    -- until set. setTargetClose({ near, noMana, onYou }); setHitOnYouAge(
    -- seconds, false for no hit, or nil).
    function c.targetClose()
        local r = s.targetClose
        if type(r) ~= "table" then return nil end
        return { near = r.near, noMana = r.noMana, onYou = r.onYou }
    end
    function c.setTargetClose(r) s.targetClose = r end
    function c.hitOnYouAge() return s.hitOnYouAge end
    function c.setHitOnYouAge(v) s.hitOnYouAge = v end

    -- G4 bag marks, as the real client's c.markBagKinds: what was drawn is
    -- kept, by kind, for c.bagMarksDrawn() -> { [bag] = { [slot] = kind } }.
    -- The real client takes texture paths; a path is turned back into its
    -- kind here (Items/BagMarks.lua TEXTURE), so a test reads kinds.
    do
        local drawnMarks = {}
        function c.markBagKinds(marks)
            drawnMarks = {}
            local kindOf = {}
            for kind, path in pairs(ns.BagMarks and ns.BagMarks.TEXTURE or {}) do kindOf[path] = kind end
            local n = 0
            for bag, slots in pairs(type(marks) == "table" and marks or {}) do
                for slot, path in pairs(type(slots) == "table" and slots or {}) do
                    drawnMarks[bag] = drawnMarks[bag] or {}
                    drawnMarks[bag][slot] = kindOf[path] or path
                    n = n + 1
                end
            end
            return n
        end
        function c.bagMarksDrawn()
            local out = {}
            for bag, slots in pairs(drawnMarks) do
                out[bag] = {}
                for slot, kind in pairs(slots) do out[bag][slot] = kind end
            end
            return out
        end
        function c.onBagRedraw(fn) return type(fn) == "function" or nil end
    end

    -- Lead section 303 (d): c.setInstanceName(text) (nil: not known).
    function c.setInstanceName(name) s.instanceName = name end
    function c.instanceName()
        if type(s.instanceName) ~= "string" or s.instanceName == "" then return nil end
        return s.instanceName
    end

    -- S32: c.setPlaceText(zone, sub): the zone and sub-zone words; not set,
    -- placeText() is nil (not known).
    function c.setPlaceText(zone, sub)
        local function w(v) return type(v) == "string" and v ~= "" and v or nil end
        s.placeText = (w(zone) or w(sub)) and { zone = w(zone), sub = w(sub) } or nil
    end
    function c.placeText()
        local p = s.placeText
        if p == nil then return nil end
        return { zone = p.zone, sub = p.sub }
    end
    -- G14 probe: the quest reward buttons as c.rewardButtons() answers them
    -- (Core/Client.lua); setRewardButtons(list or nil) sets them, nil:
    -- none found.
    do
        local rewardButtonRows = nil
        function c.setRewardButtons(rows) rewardButtonRows = rows end
        function c.rewardButtons()
            if type(rewardButtonRows) ~= "table" then return nil end
            local out = {}
            for i, r in ipairs(rewardButtonRows) do
                out[i] = { index = r.index, id = r.id, kind = r.kind }
            end
            return out
        end
    end
    -- G47 (lead section 397 item 15): c.setGroupLeader("player" / a unit /
    -- false for not grouped / nil for not known).
    function c.setGroupLeader(v) s.groupLeader = v end
    function c.groupLeader() return s.groupLeader end

    -- G50 (ACTING), as the real client's: a quest shared is kept in
    -- c.sharedQuests, in the order shared. c.setShareRefuse(why): every
    -- share answers nil, why (nil: shares).
    c.sharedQuests = {}
    function c.setShareRefuse(why) s.shareRefuse = why end
    function c.shareQuest(id)
        if type(id) ~= "number" then return nil, "bad" end
        local found = false
        for _, row in ipairs(type(s.questLog) == "table" and s.questLog or {}) do
            if type(row) == "table" and row.id == id then found = true end
        end
        if not found then return nil, "notInLog" end
        if s.shareRefuse ~= nil then return nil, s.shareRefuse end
        c.sharedQuests[#c.sharedQuests + 1] = id
        return true
    end
    -- KNOW lane (C-48, C-56): the spells on the action bars, as the real
    -- client's c.actionSpells() answers them: { [spell name] = slot }.
    -- c.setActionSpells(map or nil); nil (as made): the bars are not known.
    do
        local barSpells = nil
        function c.setActionSpells(map) barSpells = map end
        function c.actionSpells()
            if type(barSpells) ~= "table" then return nil end
            local out = {}
            for name, slot in pairs(barSpells) do out[name] = slot end
            return out
        end
    end
    return c
end

ns.client = ns.make.fakeClient()

-- C-61, C-49 (Spells/Talents.lua): unspent talent points, as the real
-- client's unspentTalents() is asked for. c.setUnspentTalents(n): a count,
-- or nil for not known. c.setUnspentTalentsRaise(true): the read raises
-- until set back to false.
do
    local make = ns.make.fakeClient
    ns.make.fakeClient = function(...)
        local c = make(...)
        local points, raises = nil, false
        function c.setUnspentTalents(n) points = n end
        function c.setUnspentTalentsRaise(on) raises = on == true end
        function c.unspentTalents()
            if raises then error("unspentTalents raised") end
            return points
        end
        return c
    end
end

-- C-62 (UI/TalentsWindow.lua): the talents the player has, as the real
-- client's talentRanks() is asked for: { [talent name] = rank }.
-- c.setTalentRanks(map or nil); nil (as made): not known.
do
    local make = ns.make.fakeClient
    ns.make.fakeClient = function(...)
        local c = make(...)
        local ranks = nil
        function c.setTalentRanks(map) ranks = map end
        function c.talentRanks()
            if type(ranks) ~= "table" then return nil end
            local out = {}
            for name, rank in pairs(ranks) do out[name] = rank end
            return out
        end
        return c
    end
end
