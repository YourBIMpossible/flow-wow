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
--   c.setMapSize(1411, 5287.5, 3525)
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
--   c.arrows[1].point / .attached / .shown / .drawn / .lines; c.arrows[1].drag(point)
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
    function c.print(text) c.printed[#c.printed + 1] = tostring(text) end
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
    function c.trainer()
        local r = s.trainer
        if type(r) ~= "table" then return nil end
        return { profession = r.profession, npc = r.npc }
    end
    function c.faction() return s.faction end
    function c.class() return s.class end
    function c.stealthed() return s.stealthed end
    function c.spellCooldown(id)
        if type(id) ~= "number" or not s.cooldowns then return nil end
        return s.cooldowns[id]
    end
    function c.facing() return s.facing end
    function c.mapSize(map)
        local r = s.mapSizes and s.mapSizes[map]
        return r and { w = r.w, h = r.h } or nil
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
        c.panels[#c.panels + 1] = h
        return h
    end

    -- Every arrow made is in c.arrows, in order. A handle keeps what it
    -- was last told: point or attached (the other handle), shown, lookIs,
    -- drawn (the last draw table), scaled, faded (alpha), under (behind),
    -- lines and textPoint, and shaped (the last shapes table; nil: the
    -- arrow is drawn from its pictures).
    c.arrows = {}
    function c.arrow(spec)
        if s.noFrames then return nil end
        local h = { spec = spec, shown = false, lookIs = "pointer", draws = 0, lines = {} }
        local moved
        function h.place(point)
            if type(point) ~= "table" then return end
            h.point, h.attached = { point[1], point[2], point[3], point[4] }, nil
        end
        function h.attach(other) h.attached, h.point = other, nil end
        function h.show(on) h.shown = on and true or false end
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
    -- nil: the client will not say how big the screen is.
    function c.setScreen(w, h) s.screen = (w and h) and { w, h } or nil end
    function c.setVersion(text) s.version = text end
    -- false: a client that cannot make frames (panel() answers nil).
    function c.setFrames(on) s.noFrames = not on end
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
    -- The open trainer window: { profession = name or nil, npc = name };
    -- nil for closed or not known.
    function c.setTrainer(r) s.trainer = r and { profession = r.profession, npc = r.npc } or nil end
    -- "Horde", "Alliance", or nil for not known.
    function c.setFaction(group) s.faction = group end
    -- The class token ("DRUID"), or nil for not known.
    function c.setClass(token) s.class = token end
    -- Stealthed: true, false, or nil for not known (the start).
    function c.setStealthed(on)
        if on == nil then s.stealthed = nil else s.stealthed = on and true or false end
    end
    -- One spell's cooldown: true (on cooldown), false (ready), nil for
    -- not known. A spell never set is not known.
    function c.setSpellCooldown(id, on)
        s.cooldowns = s.cooldowns or {}
        s.cooldowns[id] = on
    end
    -- Radians, 0 = north; nil for not known.
    function c.setFacing(f) s.facing = f end
    -- A map's width and height in yards; leave both out for not known.
    function c.setMapSize(map, w, h)
        s.mapSizes = s.mapSizes or {}
        s.mapSizes[map] = w and h and { w = w, h = h } or nil
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

    return c
end

ns.client = ns.make.fakeClient()
