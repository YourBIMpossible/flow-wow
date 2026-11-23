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
    function c.saved(name)
        if type(s.saved[name]) ~= "table" then s.saved[name] = {} end
        return s.saved[name]
    end
    function c.savedExists(name) return type(s.saved[name]) == "table" end
    function c.money() return s.money end
    function c.bags() return copyRows(s.bags) end
    function c.bagItems() return copyRows(s.bagItems) end
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
    function c.spell(id)
        if type(id) ~= "number" then return nil end
        local r = s.spells and s.spells[id] or {}
        return { known = r.known, usable = r.usable, noPower = r.noPower }
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
        function h.click(button)
            if clicked then clicked(button) end
        end
        function h.hover(on)
            if hovered then hovered(on and true or false) end
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
        end
    end
    function c.fire(event, ...) events.call(event, ...) end
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
    -- One spell's answers: { known =, usable =, noPower = }; a field left
    -- out reads as not known.
    function c.setSpell(id, row)
        s.spells = s.spells or {}
        s.spells[id] = row and { known = row.known, usable = row.usable, noPower = row.noPower } or nil
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
    c.secureButtons = {}
    local secureFail, secureDrop = {}, {}
    function c.secureButton(spec)
        if s.noFrames then return nil end
        local h = { spec = spec, attrs = {} }
        function h.set(attr, value)
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
    function c.grouped() return s.grouped end
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
    -- GT-1: any tracking on: true when one set on is, false when any was set
    -- and none is on, nil when none was set.
    function c.anyTracking()
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
    return c
end

ns.client = ns.make.fakeClient()
