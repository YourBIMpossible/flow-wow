-- Client boundary: the only file that touches the game client. Everything
-- else calls ns.client.* (or the client handed to its kernel), so the same
-- code runs offline against Core/ClientFake.lua.
--
-- Nothing here has been run in the game. Every client name is looked up in
-- `env` when it is needed and a missing one never errors: the call returns
-- the documented fallback instead. Names marked "first guess" are not
-- confirmed to exist on interface 16001.
local _, ns = ...
ns.make = ns.make or {}

-- Keeps handler lists per key; `first(key)` runs when a key gets its first
-- handler and `last(key)` when it loses its last one.
local function Listeners(first, last)
    local lists = {}
    local L = {}
    function L.add(key, fn)
        local list = lists[key]
        if not list then
            list = {}
            lists[key] = list
            first(key)
        end
        local entry = { fn = fn }
        list[#list + 1] = entry
        return function()
            if entry.dead then return end
            entry.dead = true
            local cur = lists[key]
            if not cur then return end
            for i = #cur, 1, -1 do
                if cur[i] == entry then table.remove(cur, i) end
            end
            if #cur == 0 then
                lists[key] = nil
                last(key)
            end
        end
    end
    function L.call(key, ...)
        local list = lists[key]
        if not list then return end
        local snapshot = {}
        for i = 1, #list do snapshot[i] = list[i] end
        for i = 1, #snapshot do
            if not snapshot[i].dead then snapshot[i].fn(...) end
        end
    end
    return L
end
ns.make.listeners = Listeners

-- The real client. `env` is the table the client's globals live in (_G in
-- the game; a hand-built table in tests).
function ns.make.client(env)
    local c = {}
    local eventFrame, tickFrame
    local events, ticks

    local function call(fn, ...)
        if type(fn) ~= "function" then return false end
        return pcall(fn, ...)
    end

    local function newFrame()
        local ok, f = call(env.CreateFrame, "Frame")
        if ok and f then return f end
        return nil
    end

    events = Listeners(function(event)
        if not eventFrame then
            eventFrame = newFrame()
            if eventFrame then
                eventFrame:SetScript("OnEvent", function(_, name, ...) events.call(name, ...) end)
            end
        end
        -- pcall: registering an event name this client does not have errors.
        if eventFrame then pcall(eventFrame.RegisterEvent, eventFrame, event) end
    end, function(event)
        if eventFrame then pcall(eventFrame.UnregisterEvent, eventFrame, event) end
    end)

    ticks = Listeners(function()
        tickFrame = tickFrame or newFrame()
        if tickFrame then
            tickFrame:SetScript("OnUpdate", function(_, elapsed) ticks.call("frame", elapsed or 0) end)
        end
    end, function()
        if tickFrame then tickFrame:SetScript("OnUpdate", nil) end
    end)

    -- Seconds since the client started (0 when the client has no GetTime).
    function c.now()
        local ok, t = call(env.GetTime)
        return ok and tonumber(t) or 0
    end

    -- Milliseconds, fine-grained, for timing work. debugprofilestop is a
    -- first guess on 16001; falls back to GetTime, which only moves per frame.
    function c.clockMs()
        local ok, ms = call(env.debugprofilestop)
        if ok and tonumber(ms) then return tonumber(ms) end
        return c.now() * 1000
    end

    function c.print(text)
        call(env.print, tostring(text))
    end

    -- fn(...) is called with the event's arguments. Returns a cancel function.
    function c.listen(event, fn)
        return events.add(event, fn)
    end

    -- fn(elapsedSeconds) every drawn frame. Returns a cancel function.
    function c.onFrame(fn)
        return ticks.add("frame", fn)
    end

    -- True when the named addon is loaded. C_AddOns.IsAddOnLoaded is a first
    -- guess on 16001 (Flow's Splash.lua uses the same call); the bare global
    -- is the older form of it.
    function c.addonLoaded(name)
        local group = env.C_AddOns
        local fn = (type(group) == "table" and group.IsAddOnLoaded) or env.IsAddOnLoaded
        local ok, loaded = call(fn, name)
        return (ok and loaded) and true or false
    end

    -- InCombatLockdown is the protected-action lock; UnitAffectingCombat is
    -- the fallback when it is absent.
    function c.inCombat()
        local ok, locked = call(env.InCombatLockdown)
        if ok then return locked and true or false end
        local ok2, fighting = call(env.UnitAffectingCombat, "player")
        return (ok2 and fighting) and true or false
    end

    ---------------------------------------------------------------------
    -- Reads for Items and Nav. nil always means "not known": a count that
    -- could not be read in full is never returned as a smaller count or 0.
    ---------------------------------------------------------------------

    -- A container call: C_Container.<name> when the client has it, else the
    -- bare global of the same name (the older form). Flow uses this pair.
    local function container(name)
        local group = env.C_Container
        local fn = type(group) == "table" and group[name] or nil
        if type(fn) ~= "function" then fn = env[name] end
        return fn
    end

    local function mapCall(name, ...)
        local group = env.C_Map
        return call(type(group) == "table" and group[name] or nil, ...)
    end

    local function wholeCount(n)
        return type(n) == "number" and n >= 0 and n == math.floor(n)
    end

    -- The player's copper, or nil.
    function c.money()
        local ok, copper = call(env.GetMoney)
        if ok and wholeCount(copper) then return copper end
        return nil
    end

    -- The backpack (0) and the bags worn after it. NUM_BAG_SLOTS is a first
    -- guess on 16001; Flow reads bags 0 to 4.
    local function bagIds()
        local last = env.NUM_BAG_SLOTS
        if not wholeCount(last) then last = 4 end
        local ids = {}
        for bag = 0, last do ids[#ids + 1] = bag end
        return ids
    end

    -- One row per bag that is there:
    --   { { bag = id, free = n, total = n, family = n or nil }, ... }
    -- family is the second value of GetContainerNumFreeSlots (0: takes
    -- anything); nil when the client does not give one (first guess that it
    -- does on 16001). nil when any bag could not be read.
    function c.bags()
        local slotsOf, freeOf = container("GetContainerNumSlots"), container("GetContainerNumFreeSlots")
        local out = {}
        for _, bag in ipairs(bagIds()) do
            local ok, total = call(slotsOf, bag)
            if not ok or not wholeCount(total) then return nil end
            if total > 0 then
                local okFree, free, family = call(freeOf, bag)
                if not okFree or not wholeCount(free) then return nil end
                out[#out + 1] = { bag = bag, free = free, total = total,
                    family = type(family) == "number" and family or nil }
            end
        end
        return out
    end

    -- What is in one slot: item (a link, else an item ID) and its count;
    -- nil for an empty slot; false when the slot could not be read.
    -- C_Container.GetContainerItemInfo answers with a table (hyperlink,
    -- itemID, stackCount); the bare global answers with a list where the
    -- count is 2nd, the link 7th and the ID 10th. Both as Flow reads them.
    local function slotItem(bag, slot)
        local ok, a, n, _, _, _, _, link, _, _, id = call(container("GetContainerItemInfo"), bag, slot)
        if not ok then return false end
        if a == nil then return nil end
        local item, count
        if type(a) == "table" then
            item, count = a.hyperlink or a.itemID, a.stackCount
        else
            item, count = link or id, n
            if item == nil then
                local okLink, l = call(container("GetContainerItemLink"), bag, slot)
                item = okLink and l or nil
            end
        end
        if (type(item) ~= "string" and type(item) ~= "number") or not wholeCount(count) then return false end
        return item, count
    end

    -- Every stack in those containers: { { item = link or ID, count = n }, ... }
    -- nil when any container or slot could not be read.
    local function stacks(ids)
        local slotsOf = container("GetContainerNumSlots")
        local out = {}
        for _, bag in ipairs(ids) do
            local ok, total = call(slotsOf, bag)
            if not ok or not wholeCount(total) then return nil end
            for slot = 1, total do
                local item, count = slotItem(bag, slot)
                if item == false then return nil end
                if item ~= nil then out[#out + 1] = { item = item, count = count } end
            end
        end
        return out
    end

    -- The stacks in the bags, or nil. Not summed and not keyed: the caller
    -- says what "the same item" is (ns.make.resourceRead).
    function c.bagItems()
        return stacks(bagIds())
    end

    -- The bank's containers: the main bank, the reagent bank, the bank bags
    -- and the character bank tabs; never the account-wide bank. Flow's list
    -- (Crafting/SkillPlan.lua). Every constant here is a first guess on
    -- 16001; one the client does not have is left out, and -1 and 7 stand
    -- in for the main bank and the number of bank bags.
    local function bankIds()
        local ids, seen = {}, {}
        local function add(bag)
            if type(bag) == "number" and not seen[bag] then
                seen[bag] = true
                ids[#ids + 1] = bag
            end
        end
        add(env.BANK_CONTAINER or -1)
        add(env.REAGENTBANK_CONTAINER)
        local first = (tonumber(env.NUM_TOTAL_EQUIPPED_BAG_SLOTS) or tonumber(env.NUM_BAG_SLOTS) or 4) + 1
        for bag = first, first + (tonumber(env.NUM_BANKBAGSLOTS) or 7) - 1 do add(bag) end
        local index = type(env.Enum) == "table" and env.Enum.BagIndex
        if type(index) == "table" then
            local names = {}
            for name in pairs(index) do
                if type(name) == "string" and (name == "Bank" or name == "Reagentbank" or name:find("^CharacterBankTab")) then
                    names[#names + 1] = name
                end
            end
            table.sort(names)
            for _, name in ipairs(names) do add(index[name]) end
        end
        return ids
    end

    -- Starts following the bank window (BANKFRAME_OPENED / BANKFRAME_CLOSED,
    -- the events Flow uses). Call once, early: before it, bankOpen() only
    -- has the first guess below.
    local bankState, bankWatched
    function c.watchBank()
        if bankWatched then return end
        bankWatched = true
        events.add("BANKFRAME_OPENED", function() bankState = true end)
        events.add("BANKFRAME_CLOSED", function() bankState = false end)
    end

    -- true / false, or nil when not known. Known from the last bank event
    -- once watchBank() has seen one; before that from BankFrame:IsShown(),
    -- a first guess on 16001 (Flow does not use it).
    function c.bankOpen()
        if bankState ~= nil then return bankState end
        local frame = env.BankFrame
        if type(frame) ~= "table" then return nil end
        local ok, shown = call(frame.IsShown, frame)
        if not ok then return nil end
        return shown and true or false
    end

    -- The stacks in the bank, in the shape of bagItems(). Only while the
    -- bank is known to be open; nil otherwise (the client answers "empty"
    -- for a closed bank, which is not a count). The caller keeps what it
    -- saw and when.
    function c.bankItems()
        if c.bankOpen() ~= true then return nil end
        return stacks(bankIds())
    end

    local function playerMap()
        local ok, map = mapCall("GetBestMapForUnit", "player")
        if ok and type(map) == "number" then return map end
        return nil
    end

    -- map, x, y and the client's own position value, or nil.
    local function playerPoint()
        local map = playerMap()
        if not map then return nil end
        local ok, pos = mapCall("GetPlayerMapPosition", map, "player")
        if not ok or type(pos) ~= "table" then return nil end
        local okXY, x, y = call(pos.GetXY, pos)
        if not okXY then x, y = pos.x, pos.y end
        if type(x) ~= "number" or type(y) ~= "number" or x ~= x or y ~= y then return nil end
        return map, x, y, pos
    end

    -- Where the player is on the map the client picks for them:
    -- { map = uiMapID, x = 0..1, y = 0..1 }, or nil (no map, or a place the
    -- client gives no position for). The C_Map calls are the ones Flow's
    -- Nav.lua uses.
    function c.position()
        local map, x, y = playerPoint()
        if not map then return nil end
        return { map = map, x = x, y = y }
    end

    -- The zone a map belongs to: the map itself or the nearest parent that
    -- is a zone or wider (Flow's N.ZoneOf). nil when the client won't say.
    local function zoneOf(map)
        local kinds = type(env.Enum) == "table" and env.Enum.UIMapType
        local zoneType = type(kinds) == "table" and tonumber(kinds.Zone) or 3
        for _ = 1, 6 do
            local ok, info = mapCall("GetMapInfo", map)
            if not ok or type(info) ~= "table" then return nil end
            if (tonumber(info.mapType) or zoneType) <= zoneType then return map end
            if type(info.parentMapID) ~= "number" or info.parentMapID == 0 then return nil end
            map = info.parentMapID
        end
        return nil
    end

    -- { cont = n or nil, zone = n or nil } for the player, or nil when
    -- neither is known. zone is a uiMapID. cont is the continent number
    -- C_Map.GetWorldPosFromMapPos gives for the player's position (the same
    -- number Flow keeps in a point's `cont`); it is nil where the client
    -- gives no position.
    function c.zone()
        local map = playerMap()
        if not map then return nil end
        local zone, cont = zoneOf(map), nil
        local _, _, _, pos = playerPoint()
        if pos then
            local ok, id = mapCall("GetWorldPosFromMapPos", map, pos)
            if ok and type(id) == "number" then cont = id end
        end
        if zone == nil and cont == nil then return nil end
        return { cont = cont, zone = zone }
    end

    -- The protected-action lock alone: true / false, or nil when the client
    -- has no InCombatLockdown. inCombat() above is the one that falls back.
    function c.combatLockdown()
        local ok, locked = call(env.InCombatLockdown)
        if not ok then return nil end
        return locked and true or false
    end

    -- The saved-variable table of that name, created empty when the client
    -- has not loaded one. Never cached by callers: the client replaces the
    -- global when it loads saved data.
    function c.saved(name)
        local t = env[name]
        if type(t) ~= "table" then
            t = {}
            env[name] = t
        end
        return t
    end

    -- True when a table of that name already exists; creates nothing.
    function c.savedExists(name)
        return type(env[name]) == "table"
    end

    ---------------------------------------------------------------------
    -- Diagnostics only (Core/Diag.lua). Not for feature code: a feature
    -- gets a named read above.
    ---------------------------------------------------------------------

    -- The value at a dotted client name ("GetMoney", "C_Map.GetMapInfo"),
    -- or nil.
    local function lookup(path)
        local at = env
        for seg in tostring(path):gmatch("[^%.]+") do
            if type(at) ~= "table" then return nil end
            at = at[seg]
        end
        return at
    end

    -- The Lua type of that name: "function", "table", "number", "nil" ...
    function c.typeOf(path)
        return type(lookup(path))
    end

    -- Calls that name under pcall. Returns ok, then what it returned (or
    -- the error text). ok is false when the name is not a function.
    function c.raw(path, ...)
        local fn = lookup(path)
        if type(fn) ~= "function" then return false, "not a function" end
        return pcall(fn, ...)
    end

    -- What is at that name, as plain data: a number, string or boolean as
    -- it is; a table as { key = plain value or type name }, one level deep
    -- and `limit` keys at most (default 300); anything else nil.
    function c.peek(path, limit)
        local v = lookup(path)
        local kind = type(v)
        if kind == "number" or kind == "string" or kind == "boolean" then return v end
        if kind ~= "table" then return nil end
        local out, n = {}, 0
        local ok = pcall(function()
            for key, value in pairs(v) do
                if n >= (limit or 300) then break end
                local vk = type(value)
                out[tostring(key)] = (vk == "number" or vk == "string" or vk == "boolean") and value or vk
                n = n + 1
            end
        end)
        if not ok then return nil end
        return out
    end

    -- The client's global names that match a Lua pattern, sorted, `limit`
    -- at most (default 300).
    function c.globalNames(pattern, limit)
        local out = {}
        pcall(function()
            for name in pairs(env) do
                if type(name) == "string" and name:find(pattern) then out[#out + 1] = name end
            end
        end)
        table.sort(out)
        for i = #out, (limit or 300) + 1, -1 do out[i] = nil end
        return out
    end

    -- Calls fn(text) for every Lua error the client reports, from any
    -- addon, then hands the error on to whatever handled it before. Returns
    -- false when the client has no error handler to chain to.
    function c.onError(fn)
        local get, set = env.geterrorhandler, env.seterrorhandler
        if type(get) ~= "function" or type(set) ~= "function" then return false end
        local before = get()
        set(function(err, ...)
            pcall(fn, tostring(err))
            if type(before) == "function" then return before(err, ...) end
        end)
        return true
    end

    -- Registers a slash command. tag is the client's key for it, command
    -- the text the player types; fn(rest) gets what follows it. Returns
    -- false when the client has no slash table.
    function c.slash(tag, command, fn)
        if type(env.SlashCmdList) ~= "table" then return false end
        env["SLASH_" .. tag .. "1"] = command
        env.SlashCmdList[tag] = function(rest) fn(rest or "") end
        return true
    end

    ---------------------------------------------------------------------
    -- Drawing. Thin on purpose: what a panel says and where it stands is
    -- decided by the caller (UI/DevPanel.lua). No frame method here has
    -- been seen on 16001, so each is looked up and called under pcall: one
    -- the client lacks is skipped and the rest still run.
    ---------------------------------------------------------------------

    -- obj:name(...) under pcall. ok is false when obj has no such method.
    local function method(obj, name, ...)
        if obj == nil then return false end
        local ok, fn = pcall(function() return obj[name] end)
        if not ok or type(fn) ~= "function" then return false end
        return pcall(fn, obj, ...)
    end

    -- The version text the client read from this addon's TOC, or nil.
    -- GetAddOnMetadata (C_AddOns or bare) is a first guess on 16001.
    function c.version(name)
        local group = env.C_AddOns
        local fn = (type(group) == "table" and group.GetAddOnMetadata) or env.GetAddOnMetadata
        local ok, text = call(fn, name, "Version")
        if ok and type(text) == "string" and text ~= "" then return text end
        return nil
    end

    -- Width and height of the area frames are placed in (UIParent, in its
    -- own units), or nil when the client will not say.
    function c.screen()
        local parent = env.UIParent
        local okW, w = method(parent, "GetWidth")
        local okH, h = method(parent, "GetHeight")
        if okW and okH and type(w) == "number" and type(h) == "number" and w > 0 and h > 0 then
            return w, h
        end
        return nil
    end

    -- A small movable text panel, or nil when the client cannot make one.
    --   spec = { name = global frame name or nil, width = n, height = n }
    -- The handle:
    --   h.setLines({ "text", ... })   the lines shown, top to bottom
    --   h.place({ anchor, relative anchor, x, y })   against the screen
    --   h.show(on)
    --   h.onMoved(fn)   fn(point) after the player drags it; point is plain
    --                   data in the shape place() takes. Not called when the
    --                   client will not say where the panel now stands.
    -- A new panel is hidden and has no place until told.
    function c.panel(spec)
        spec = type(spec) == "table" and spec or {}
        local parent = env.UIParent
        local ok, f = call(env.CreateFrame, "Frame", spec.name, parent)
        if not ok or f == nil then return nil end
        local h, moved = {}, nil
        local width, height = tonumber(spec.width) or 200, tonumber(spec.height) or 80

        method(f, "Hide")
        if not method(f, "SetSize", width, height) then
            method(f, "SetWidth", width)
            method(f, "SetHeight", height)
        end
        method(f, "SetFrameStrata", "MEDIUM")
        method(f, "SetClampedToScreen", true)

        -- A dark backing. SetColorTexture is the newer call; the older
        -- SetTexture took the same four numbers.
        local okBg, bg = method(f, "CreateTexture", nil, "BACKGROUND")
        if okBg and bg ~= nil then
            method(bg, "SetAllPoints", f)
            if not method(bg, "SetColorTexture", 0, 0, 0, 0.6) then method(bg, "SetTexture", 0, 0, 0, 0.6) end
        end

        local okText, text = method(f, "CreateFontString", nil, "OVERLAY", "GameFontNormalSmall")
        if not okText then text = nil end
        if text ~= nil then
            method(text, "SetPoint", "TOPLEFT", f, "TOPLEFT", 6, -6)
            method(text, "SetPoint", "BOTTOMRIGHT", f, "BOTTOMRIGHT", -6, 6)
            method(text, "SetJustifyH", "LEFT")
            method(text, "SetJustifyV", "TOP")
        end

        -- Where the frame stands now, as plain data, or nil. GetPoint gives
        -- anchor, relative frame, relative anchor, x, y; the frame's left and
        -- bottom edge is the fallback.
        local function standing()
            local okP, a, _, r, x, y = method(f, "GetPoint", 1)
            if okP and type(a) == "string" and type(x) == "number" and type(y) == "number" then
                return { a, type(r) == "string" and r or a, x, y }
            end
            local okL, left = method(f, "GetLeft")
            local okB, bottom = method(f, "GetBottom")
            if okL and okB and type(left) == "number" and type(bottom) == "number" then
                return { "BOTTOMLEFT", "BOTTOMLEFT", left, bottom }
            end
            return nil
        end

        -- The handlers close over the frame: they use none of the arguments
        -- the client passes, so it does not matter whether `self` is one.
        method(f, "SetMovable", true)
        method(f, "EnableMouse", true)
        method(f, "RegisterForDrag", "LeftButton")
        method(f, "SetScript", "OnDragStart", function() method(f, "StartMoving") end)
        method(f, "SetScript", "OnDragStop", function()
            method(f, "StopMovingOrSizing")
            -- The client would otherwise keep a moved named frame's place
            -- in its own layout cache and put it back there itself.
            method(f, "SetUserPlaced", false)
            local point = standing()
            if point and moved then pcall(moved, point) end
        end)

        function h.setLines(lines)
            if text == nil then return end
            local out = {}
            for i = 1, #(lines or {}) do out[i] = tostring(lines[i]) end
            method(text, "SetText", table.concat(out, "\n"))
        end
        function h.place(point)
            if type(point) ~= "table" then return end
            method(f, "ClearAllPoints")
            method(f, "SetPoint", point[1], parent, point[2], point[3], point[4])
        end
        function h.show(on)
            method(f, on and "Show" or "Hide")
        end
        function h.onMoved(fn)
            moved = fn
        end
        return h
    end

    return c
end

ns.client = ns.make.client(_G)
