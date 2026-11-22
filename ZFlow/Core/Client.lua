-- Client boundary: the only file that touches the game client. Everything
-- else calls ns.client.* (or the client handed to its kernel), so the same
-- code runs offline against Core/ClientFake.lua.
--
-- Every client name is looked up in `env` when it is needed and a missing
-- one never errors: the call returns the documented fallback instead.
-- Seen working in the game on interface 16001 (build 1.60.1): money, bags,
-- bag contents, position, zone, the combat lock and the bank events. Names
-- still marked "first guess" have not been seen there. Every name the
-- merchant read uses is a first guess: MERCHANT_SHOW, MERCHANT_CLOSED,
-- MerchantFrame:IsShown, GetMerchantNumItems, GetMerchantItemLink,
-- C_MerchantFrame.GetItemInfo and GetMerchantItemInfo.
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
    -- A call runs over a snapshot of its list, so a listener may add or
    -- remove listeners. The snapshot table is kept and used again: a call
    -- makes none. It is taken out of `spare` while in use, so a call made
    -- from inside a listener, or one after a listener failed, finds none
    -- and makes its own; the last to finish is kept.
    local spare = {}
    function L.call(key, ...)
        local list = lists[key]
        if not list then return end
        local snapshot = spare or {}
        spare = nil
        local n = #list
        for i = 1, n do snapshot[i] = list[i] end
        for i = 1, n do
            local entry = snapshot[i]
            snapshot[i] = nil
            if not entry.dead then entry.fn(...) end
        end
        spare = snapshot
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

    -- What could not be set up, for c.listenFaults(): the events something
    -- listens to that the client never took, and the frames it did not make.
    local unregistered = {}   -- event name -> true
    local noEventFrame, noTickFrame = false, false

    events = Listeners(function(event)
        if not eventFrame then
            eventFrame = newFrame()
            if eventFrame then
                eventFrame:SetScript("OnEvent", function(_, name, ...) events.call(name, ...) end)
            end
        end
        noEventFrame = eventFrame == nil
        -- pcall: registering an event name this client does not have errors.
        -- The listener is kept either way; the event just never arrives.
        if eventFrame and pcall(eventFrame.RegisterEvent, eventFrame, event) then
            unregistered[event] = nil
        else
            unregistered[event] = true
        end
    end, function(event)
        unregistered[event] = nil
        if eventFrame then pcall(eventFrame.UnregisterEvent, eventFrame, event) end
    end)

    ticks = Listeners(function()
        tickFrame = tickFrame or newFrame()
        noTickFrame = tickFrame == nil
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

    -- The wall clock: seconds since 1970, the same clock in every session
    -- (now() starts again with the client), so a time that is saved comes
    -- from here. nil when not known, never now() or 0 in its place. time()
    -- is a first guess on 16001: not seen in game.
    function c.clock()
        local ok, t = call(env.time)
        if not ok or type(t) ~= "number" or t ~= t or t <= 0 or t == math.huge then return nil end
        return t
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

    -- What listening could not set up, as fresh plain data:
    --   notRegistered  the event names something listens to that the client
    --                  did not take (it refused the name, or there is no
    --                  frame to register on), sorted
    --   noEventFrame   true when the frame that receives events was not made
    --   noTickFrame    true when the frame that draws onFrame was not made
    -- Listeners to these are kept; they are simply never called.
    function c.listenFaults()
        local names = {}
        for event in pairs(unregistered) do names[#names + 1] = event end
        table.sort(names)
        return { notRegistered = names, noEventFrame = noEventFrame, noTickFrame = noTickFrame }
    end

    -- Seconds since the client started, or nil when the client will not say.
    -- now() without the made-up 0: for a time that is kept or saved, where 0
    -- would read as a real moment. A time that has to mean anything after a
    -- reload is not this one; it starts again each session.
    function c.uptime()
        local ok, t = call(env.GetTime)
        if not ok then return nil end
        return tonumber(t)
    end

    -- InCombatLockdown is the protected-action lock; UnitAffectingCombat is
    -- the fallback when it is absent. true, false, or nil when neither read
    -- worked: not knowing is not "out of combat", and a caller about to do
    -- something combat forbids has to treat nil as in combat.
    function c.inCombat()
        local ok, locked = call(env.InCombatLockdown)
        if ok then return locked and true or false end
        local ok2, fighting = call(env.UnitAffectingCombat, "player")
        if ok2 then return fighting and true or false end
        return nil
    end

    ---------------------------------------------------------------------
    -- Reads for Items and Nav. nil always means "not known": a count that
    -- could not be read in full is never returned as a smaller count or 0.
    ---------------------------------------------------------------------

    -- A container call: C_Container.<name>. Seen in game on 16001: the bare
    -- globals of the same names are not there, so they are not tried.
    local function container(name)
        local group = env.C_Container
        local fn = type(group) == "table" and group[name] or nil
        return type(fn) == "function" and fn or nil
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

    -- The backpack (0) and the bags worn after it. Seen in game on 16001:
    -- NUM_BAG_SLOTS is a number and bags 0 to 4 read.
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
    -- itemID, stackCount). Anything else is not read.
    local function slotItem(bag, slot)
        local ok, info = call(container("GetContainerItemInfo"), bag, slot)
        if not ok then return false end
        if info == nil then return nil end
        if type(info) ~= "table" then return false end
        local item, count = info.hyperlink or info.itemID, info.stackCount
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

    -- The character's bank tabs, as the client lists them:
    -- C_Bank.FetchPurchasedBankTabIDs(Enum.BankType.Character). Never the
    -- account-wide bank. On 16001 the bank is tabs only (seen in game: one
    -- tab, container 6); the old main bank, bank bag and reagent bank
    -- numbers are not there (-1 is the keyring, 5 the reagent bag).
    -- nil when the client will not list them.
    local function bankIds()
        local bank, enum = env.C_Bank, env.Enum
        local kind = type(enum) == "table" and type(enum.BankType) == "table" and enum.BankType.Character
        if type(bank) ~= "table" or type(kind) ~= "number" then return nil end
        local ok, tabs = call(bank.FetchPurchasedBankTabIDs, kind)
        if not ok or type(tabs) ~= "table" then return nil end
        local ids = {}
        for i = 1, #tabs do
            if type(tabs[i]) ~= "number" then return nil end
            ids[i] = tabs[i]
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
        local ids = bankIds()
        if not ids then return nil end
        return stacks(ids)
    end

    -- Starts following the merchant window (MERCHANT_SHOW / MERCHANT_CLOSED,
    -- first guesses: not seen in game on 16001). Call once, early: before
    -- it, merchantOpen() only has the first guess below.
    local merchantState, merchantWatched
    function c.watchMerchant()
        if merchantWatched then return end
        merchantWatched = true
        events.add("MERCHANT_SHOW", function() merchantState = true end)
        events.add("MERCHANT_CLOSED", function() merchantState = false end)
    end

    -- true / false, or nil when not known. Known from the last merchant
    -- event once watchMerchant() has seen one; before that from
    -- MerchantFrame:IsShown(), a first guess on 16001.
    function c.merchantOpen()
        if merchantState ~= nil then return merchantState end
        local frame = env.MerchantFrame
        if type(frame) ~= "table" then return nil end
        local ok, shown = call(frame.IsShown, frame)
        if not ok then return nil end
        return shown and true or false
    end

    -- What the window shows for one item on sale: read?, price, stack,
    -- other currency. First guesses, neither seen in game on 16001:
    -- C_MerchantFrame.GetItemInfo(index) answering a table (price,
    -- stackCount, hasExtendedCost) where the client has it, else
    -- GetMerchantItemInfo(index) answering name, texture, price, quantity,
    -- numAvailable, isPurchasable, isUsable, extendedCost.
    local function merchantPrice(index)
        local api = env.C_MerchantFrame
        if type(api) == "table" and type(api.GetItemInfo) == "function" then
            local ok, info = call(api.GetItemInfo, index)
            if not ok then return false end
            if type(info) ~= "table" then return true end
            return true, info.price, info.stackCount, info.hasExtendedCost
        end
        local ok, _, _, price, quantity, _, _, _, extended = call(env.GetMerchantItemInfo, index)
        if not ok then return false end
        return true, price, quantity, extended
    end

    -- Every item the open merchant has on sale, in the window's order:
    --   { { index = n, item = link, price = copper for the stack shown,
    --       stack = how many that price buys, other = true / false }, ... }
    -- A field the client did not give is left out, never guessed: no item,
    -- no price (never 0 in its place), no stack. other = true says the
    -- item costs something that is not coin; left out when not known.
    -- nil unless the window is known to be open, and nil when the count or
    -- any one item could not be read: never a shorter list. This only
    -- reads. Nothing here buys, sells or picks anything up.
    -- First guesses: GetMerchantNumItems, GetMerchantItemLink(index).
    function c.merchantItems()
        if c.merchantOpen() ~= true then return nil end
        local ok, count = call(env.GetMerchantNumItems)
        if not ok or not wholeCount(count) then return nil end
        local out = {}
        for index = 1, count do
            local okLink, link = call(env.GetMerchantItemLink, index)
            if not okLink then return nil end
            local okPrice, price, stack, other = merchantPrice(index)
            if not okPrice then return nil end
            local row = { index = index }
            if type(link) == "string" then row.item = link end
            if wholeCount(price) then row.price = price end
            if wholeCount(stack) and stack > 0 then row.stack = stack end
            if other ~= nil then row.other = other and true or false end
            out[index] = row
        end
        return out
    end

    -- The profession whose window is open, and every recipe in it:
    --   { profession = skill line, skill = n, max = n,
    --     recipes = { { id =, name =, learned = true / false }, ... } }
    -- nil when no profession window is open or the client will not say.
    -- Seen in game on 16001 (Blacksmithing): for a moment after the window
    -- opens the client says "ready" but is still changing its data source,
    -- and lists no recipes. That is not an empty profession, so it is nil
    -- until IsDataSourceChanging answers false. One recipe that cannot be
    -- read makes the whole reading nil: never a shorter list.
    function c.recipes()
        local ui = env.C_TradeSkillUI
        if type(ui) ~= "table" then return nil end
        local okReady, ready = call(ui.IsTradeSkillReady)
        if not okReady or ready ~= true then return nil end
        local okChanging, changing = call(ui.IsDataSourceChanging)
        if not okChanging or changing ~= false then return nil end
        local okBase, base = call(ui.GetBaseProfessionInfo)
        if not okBase or type(base) ~= "table" then return nil end
        local line = base.professionID
        if type(line) ~= "number" or line <= 0 then return nil end
        if type(base.skillLevel) ~= "number" or type(base.maxSkillLevel) ~= "number" then return nil end
        local okIds, ids = call(ui.GetAllRecipeIDs)
        if not okIds or type(ids) ~= "table" then return nil end
        local rows = {}
        for i = 1, #ids do
            local okInfo, info = call(ui.GetRecipeInfo, ids[i])
            if not okInfo or type(info) ~= "table" or type(info.learned) ~= "boolean" then return nil end
            rows[i] = { id = ids[i], name = type(info.name) == "string" and info.name or nil, learned = info.learned }
        end
        return { profession = line, skill = base.skillLevel, max = base.maxSkillLevel, recipes = rows }
    end

    -- A plain true / false the client lets this code see, else nil. The
    -- client can hand back a value it marks secret (issecretvalue); that is
    -- "not known", never read as false.
    local function hidden(v)
        if env.issecretvalue == nil then return false end
        local okSecret, secret = call(env.issecretvalue, v)
        return not okSecret or secret ~= false
    end

    local function flag(ok, v)
        if not ok or hidden(v) or type(v) ~= "boolean" then return nil end
        return v
    end

    -- The id of one of your spells, by its name as the client spells it, or
    -- nil. Only the client is asked (C_Spell.GetSpellInfo): no id comes from
    -- a table in this addon. Asking by name is a first guess on 16001; by id
    -- it was seen in game to answer with a table holding spellID.
    function c.spellId(name)
        if type(name) ~= "string" or name == "" then return nil end
        local group = env.C_Spell
        local ok, info = call(type(group) == "table" and group.GetSpellInfo or nil, name)
        if not ok or type(info) ~= "table" then return nil end
        local id = info.spellID
        if hidden(id) or type(id) ~= "number" or id <= 0 then return nil end
        return id
    end

    -- Which way you face, in radians (0 = north, turning left adds), or nil.
    -- GetPlayerFacing; the client gives nothing where it hides facing.
    function c.facing()
        local ok, f = call(env.GetPlayerFacing)
        if not ok or hidden(f) or type(f) ~= "number" or f ~= f then return nil end
        return f
    end

    -- What the client says about one of your spells, by spell id:
    --   { known =, usable =, noPower = }   each true, false or nil
    -- nil for a field means the client did not say; it is never guessed.
    -- noPower is the client's own "not enough power" answer, not an amount.
    -- Seen in game on 16001, out of a fight: C_Spell.IsSpellUsable gives two
    -- plain booleans. In a fight it has not been observed.
    function c.spell(id)
        if type(id) ~= "number" then return nil end
        local group = type(env.C_Spell) == "table" and env.C_Spell or {}
        local row = { known = flag(call(env.IsPlayerSpell, id)) }
        local ok, usable, noPower = call(group.IsSpellUsable, id)
        row.usable = flag(ok, usable)
        row.noPower = flag(ok, noPower)
        return row
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

    -- Whether the player is dead or a ghost: true, false, or nil when the
    -- client gives no plain yes or no. Only "player" is ever asked about.
    -- UnitIsDeadOrGhost is the call Flow's Nav.lua uses; a first guess on
    -- 16001, its answer has not been seen there.
    function c.dead()
        return flag(call(env.UnitIsDeadOrGhost, "player"))
    end

    -- Whether the player is a ghost (released, not yet back in the body):
    -- true, false, or nil when the client does not say. A 1 is read as true.
    -- First guess on 16001: UnitIsGhost has not been seen to exist or answer
    -- there. Asked for "player" only.
    function c.ghost()
        local ok, v = call(env.UnitIsGhost, "player")
        if not ok or hidden(v) then return nil end
        if v == true or v == 1 then return true end
        if v == false then return false end
        return nil
    end

    -- Where the player's corpse is on the map the client picks for the
    -- player: { map = uiMapID, x = 0..1, y = 0..1 }; false when the client
    -- answered and gave no position on that map; nil when it cannot be told
    -- (no map for the player, no such read, the read raised, the answer
    -- itself hidden, an answer that is no position, or x or y hidden or no
    -- number). A hidden answer is asked about before it is compared or read.
    -- C_DeathInfo.GetCorpseMapPosition is the call Flow's Nav.lua uses; a
    -- first guess on 16001, its answer has not been seen there.
    function c.corpse()
        local map = playerMap()
        if not map then return nil end
        local group = env.C_DeathInfo
        local ok, pos = call(type(group) == "table" and group.GetCorpseMapPosition or nil, map)
        if not ok or hidden(pos) then return nil end
        -- false: the client answered, and gave no position on this map. That
        -- a plain nil from the read means "not on this map" is a first guess
        -- on 16001, not observed in a client.
        if pos == nil then return false end
        if type(pos) ~= "table" then return nil end
        local okXY, x, y = call(pos.GetXY, pos)
        if not okXY then x, y = pos.x, pos.y end
        if hidden(x) or hidden(y) or type(x) ~= "number" or type(y) ~= "number" then return nil end
        if x ~= x or y ~= y then return nil end
        return { map = map, x = x, y = y }
    end

    -- The player's own map waypoint (the pin they set on the world map):
    -- { map = uiMapID, x = 0..1, y = 0..1 }, or nil (no such call, none
    -- set, or an answer that is not a map with two shares). Asks
    -- C_Map.HasUserWaypoint, where the client has it, then
    -- C_Map.GetUserWaypoint. Both are the retail names; a first guess on
    -- 16001, where neither has been seen to exist or answer.
    function c.waypoint()
        local group = env.C_Map
        if type(group) ~= "table" then return nil end
        if group.HasUserWaypoint ~= nil and flag(mapCall("HasUserWaypoint")) ~= true then return nil end
        local ok, point = mapCall("GetUserWaypoint")
        if not ok or hidden(point) or type(point) ~= "table" then return nil end
        local map, pos = point.uiMapID, point.position
        -- The position is checked itself, not only what it holds: a hidden
        -- table may answer its fields with plain-looking numbers (IT3).
        if hidden(map) or type(map) ~= "number" or hidden(pos) or type(pos) ~= "table" then return nil end
        local okXY, x, y = call(pos.GetXY, pos)
        if not okXY then x, y = pos.x, pos.y end
        if hidden(x) or hidden(y) or type(x) ~= "number" or type(y) ~= "number" then return nil end
        if not (x >= 0 and x <= 1 and y >= 0 and y <= 1) then return nil end
        return { map = map, x = x, y = y }
    end

    -- The world place of one corner of a map, as two numbers, or nil.
    local function corner(map, x, y)
        local okVec, vec = call(env.CreateVector2D, x, y)
        if not okVec or vec == nil then return nil end
        local ok, _, world = mapCall("GetWorldPosFromMapPos", map, vec)
        if not ok or type(world) ~= "table" then return nil end
        local okXY, wx, wy = call(world.GetXY, world)
        if not okXY then wx, wy = world.x, world.y end
        if hidden(wx) or hidden(wy) or type(wx) ~= "number" or type(wy) ~= "number" then return nil end
        if wx ~= wx or wy ~= wy then return nil end
        return wx, wy
    end

    -- How wide and tall a map is, in yards: { w = n, h = n }, or nil. Only
    -- the client is asked (the world places of the map's two corners, by
    -- C_Map.GetWorldPosFromMapPos); no size comes from a table in this
    -- addon. In the world's own numbers the first runs north to south and
    -- the second east to west, so the width is the second. A first guess on
    -- 16001: the calls exist there, the corner answers have not been seen.
    function c.mapSize(map)
        if type(map) ~= "number" then return nil end
        local x0, y0 = corner(map, 0, 0)
        local x1, y1 = corner(map, 1, 1)
        if not x0 or not x1 then return nil end
        local w, h = math.abs(y0 - y1), math.abs(x0 - x1)
        if not (w > 0 and h > 0) or w == math.huge or h == math.huge then return nil end
        return { w = w, h = h }
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
    --   h.onMoved(fn, failed)   fn(point) after the player drags it; point is plain
    --                   data in the shape place() takes. Not called when the
    --                   client will not say where the panel now stands.
    -- A new panel is hidden and has no place until told.
    function c.panel(spec)
        spec = type(spec) == "table" and spec or {}
        local parent = env.UIParent
        local ok, f = call(env.CreateFrame, "Frame", spec.name, parent)
        if not ok or f == nil then return nil end
        local h, moved, movedFailed = {}, nil, nil
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
            if point and moved then
                -- An error in fn must not reach the client's drag handler.
                -- It goes back to whoever gave fn, to record.
                local ok, err = pcall(moved, point)
                if not ok and movedFailed then pcall(movedFailed, err) end
            end
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
        -- failed(err), when given, is called with the error of an fn that
        -- failed; without it the error is dropped.
        function h.onMoved(fn, failed)
            moved = fn
            movedFailed = type(failed) == "function" and failed or nil
        end
        return h
    end

    -- Arrow frames, by handle: attach() needs the other arrow's frame.
    local arrowFrames = setmetatable({}, { __mode = "k" })

    -- A movable guide arrow, or nil when the client cannot make one.
    --   spec = { name = global frame name or nil, size = n (the frame),
    --            art = n (the drawn body), artPath = folder of the arrow
    --            textures ending in a separator, needle = { w, h } (the
    --            profession needle's body), level = frame level,
    --            halo = { w, h, y } (the arrived ring: its size, and the
    --            height of the ring, ripple and beams against the centre),
    --            beam = { w, h } (the beams before their first draw),
    --            beamUp = { l, r, t, b }, beamDown = { l, r, t, b } (the
    --            beams' texcoords) }
    -- The halo, beam and texcoord numbers are Nav/ArrowMotion's, handed in
    -- by the caller: there is no copy of them here, and a spec without them
    -- gets no size, height or texcoord made up. Without halo[3] the ring,
    -- the ripple and the beams are given no place, and a texture with no
    -- place is not drawn: such an arrow has no arrived ring at all. That is
    -- not reported: the one caller (UI/Arrow.lua) always gives all three.
    -- Three frames: the frame that is placed, dragged and shown (scale 1);
    -- on it a holder that carries the art and takes the scale, one level
    -- up; and a text frame for the label, a child of the placed frame (so
    -- unscaled: its offsets are screen units at every scale), one level
    -- above the holder so the label is over the art, in front and behind
    -- alike. Without a text frame the label is the placed frame's, under
    -- the art. First guess on 16001, not observed in a client: that a child
    -- frame one level up draws over its sibling's art. Needs a client check.
    -- The handle:
    --   h.place({ anchor, relative anchor, x, y })   against the screen
    --   h.attach(other)        centred on another arrow handle, following it
    --   h.show(on)             hiding ends a drag in progress
    --   h.look("pointer" | "needle")
    --   h.draw(d)              one frame of Nav/ArrowMotion's ArrowStep table.
    --                          Makes no table or function, and looks no
    --                          method up, after the arrow is made. The ripple
    --                          and beams are sized only from d.ripple / d.beam.
    --   h.scale(n), h.alpha(n)
    --   h.behind(on)           under the other arrow: the frame and its
    --                          holder go down two levels and take no mouse;
    --                          ends a drag in progress
    --   h.dragging()           true while the player is dragging it
    --   h.text(lines, point)   lines under / over it, point { a, r, x, y }
    --                          against the placed frame; no lines: hidden
    --   h.onMoved(fn)          fn(point) after the player drags it
    -- A new arrow is hidden and has no place until told.
    function c.arrow(spec)
        spec = type(spec) == "table" and spec or {}
        local parent = env.UIParent
        local ok, f = call(env.CreateFrame, "Frame", spec.name, parent)
        if not ok or f == nil then return nil end
        local h, moved, dragging = {}, nil, false
        local size = tonumber(spec.size) or 56
        local art = tonumber(spec.art) or 64
        local path = type(spec.artPath) == "string" and spec.artPath or ""
        local needle = type(spec.needle) == "table" and spec.needle or {}
        local needleW, needleH = tonumber(needle[1]) or art * 0.4, tonumber(needle[2]) or art
        local level = tonumber(spec.level) or 5
        local haloSpec = type(spec.halo) == "table" and spec.halo or nil
        local beamSpec = type(spec.beam) == "table" and spec.beam or nil
        local haloY = haloSpec and tonumber(haloSpec[3]) or nil

        method(f, "Hide")
        if not method(f, "SetSize", size, size) then
            method(f, "SetWidth", size)
            method(f, "SetHeight", size)
        end
        method(f, "SetFrameStrata", "HIGH")
        method(f, "SetFrameLevel", level)
        method(f, "SetClampedToScreen", true)

        -- This arrow's methods, looked up once per object and name (false:
        -- the object has none), so a frame's draw looks nothing up and makes
        -- nothing. `method` makes a function on every call.
        local known = {}
        local function lookup(obj, name)
            local of = known[obj]
            if of == nil then
                of = {}
                known[obj] = of
            end
            local fn = of[name]
            if fn == nil then
                local okF, got = pcall(function() return obj[name] end)
                fn = okF and type(got) == "function" and got or false
                of[name] = fn
            end
            return fn
        end
        local function fast(obj, name, ...)
            if obj == nil then return false end
            local fn = lookup(obj, name)
            if not fn then return false end
            return pcall(fn, obj, ...)
        end
        local function sized(t, w, ht)
            if not fast(t, "SetSize", w, ht) then
                fast(t, "SetWidth", w)
                fast(t, "SetHeight", ht)
            end
        end
        -- The art sits on a holder centred on the frame. Scale is the
        -- holder's: the frame that is placed stays at scale 1, so a saved
        -- point means the same place at every scale. Without a holder the
        -- frame itself is scaled.
        local okH, holder = call(env.CreateFrame, "Frame", nil, f)
        if not okH or holder == nil then holder = f end
        if holder ~= f then
            sized(holder, size, size)
            method(holder, "SetPoint", "CENTER", f, "CENTER", 0, 0)
        end
        -- The text frame: the label's, over the art. It covers the placed
        -- frame and takes no mouse.
        local okT, textFrame = call(env.CreateFrame, "Frame", nil, f)
        if not okT or textFrame == nil then textFrame = f end
        if textFrame ~= f then
            method(textFrame, "SetAllPoints", f)
            -- Said, not left to the client's default: it covers the placed
            -- frame, and a click or drag there must reach that frame.
            method(textFrame, "EnableMouse", false)
        end
        -- The levels for the placed frame at `to`: the holder one up, the
        -- text frame one above the holder.
        local function levels(to)
            method(f, "SetFrameLevel", to)
            local top = to
            if holder ~= f then
                top = to + 1
                method(holder, "SetFrameLevel", top)
            end
            if textFrame ~= f then method(textFrame, "SetFrameLevel", top + 1) end
        end
        levels(level)
        local function tex(file, layer, sub, blend)
            local okT, t = method(holder, "CreateTexture", nil, layer, nil, sub)
            if not okT or t == nil then return nil end
            method(t, "SetTexture", path .. file)
            if blend then method(t, "SetBlendMode", blend) end
            return t
        end
        local shadow = tex("ArrowShadow", "BACKGROUND", 1)
        local pool = tex("ArrowGlow", "BACKGROUND", 2, "ADD")
        local body = tex("ArrowBody", "ARTWORK", 1)
        local shine = tex("ArrowShine", "ARTWORK", 2, "ADD")
        local halo = tex("ArrowRing", "BACKGROUND", 3, "ADD")
        local ripple = tex("ArrowRing", "BACKGROUND", 4, "ADD")
        local beam = tex("ArrowBeam", "ARTWORK", 3, "ADD")
        local beamDown = tex("ArrowBeam", "ARTWORK", 3, "ADD")
        if body == nil then return nil end

        -- The texture lists a draw walks, made once; a texture the client
        -- did not make is left out.
        local function list(...)
            local out = {}
            for i = 1, select("#", ...) do
                local t = select(i, ...)
                if t ~= nil then out[#out + 1] = t end
            end
            return out
        end
        local cut = list(shadow, body, shine)                           -- cut from the sheet, or turned
        local tinted = list(body, pool, halo, ripple, beam, beamDown)   -- take the colour
        local ring = list(halo, ripple, beam, beamDown)                 -- shown on arrival
        local beams = list(beam, beamDown)
        local DRAWN = { "SetRotation", "SetTexCoord", "SetVertexColor", "SetAlpha", "SetPoint",
                        "Show", "Hide", "SetSize", "SetWidth", "SetHeight" }
        for _, t in ipairs(list(shadow, pool, body, shine, halo, ripple, beam, beamDown)) do
            for i = 1, #DRAWN do lookup(t, DRAWN[i]) end
        end

        sized(pool, 60, 36)
        method(pool, "SetPoint", "CENTER", holder, "CENTER", 0, -3)
        if haloSpec and tonumber(haloSpec[1]) and tonumber(haloSpec[2]) then
            sized(halo, tonumber(haloSpec[1]), tonumber(haloSpec[2]))
        end
        if beamSpec and tonumber(beamSpec[1]) and tonumber(beamSpec[2]) then
            for i = 1, #beams do sized(beams[i], tonumber(beamSpec[1]), tonumber(beamSpec[2])) end
        end
        if haloY then
            method(halo, "SetPoint", "CENTER", holder, "CENTER", 0, haloY)
            method(ripple, "SetPoint", "CENTER", holder, "CENTER", 0, haloY)
            method(beam, "SetPoint", "BOTTOM", holder, "CENTER", 0, haloY)
            method(beamDown, "SetPoint", "TOP", holder, "CENTER", 0, haloY)
        end
        local function coords(t, tc)
            if type(tc) == "table" then method(t, "SetTexCoord", tc[1], tc[2], tc[3], tc[4]) end
        end
        coords(beam, spec.beamUp)
        coords(beamDown, spec.beamDown)
        for i = 1, #ring do fast(ring[i], "Hide") end

        -- The text is the text frame's, not the holder's: unscaled.
        local okText, label = method(textFrame, "CreateFontString", nil, "OVERLAY", "GameFontNormal")
        if not okText then label = nil end
        if label ~= nil then
            method(label, "SetJustifyH", "CENTER")
            method(label, "Hide")
        end

        -- The needle turns its one upright cell where the client can turn a
        -- texture; elsewhere it takes the sheet's cells as the pointer does.
        local current, turns = "pointer", false
        local function shape(look)
            current = look == "needle" and "needle" or "pointer"
            turns = false
            if current == "needle" then
                turns = fast(body, "SetRotation", 0) and true or false
            else
                fast(body, "SetRotation", 0)
                fast(shine, "SetRotation", 0)
                fast(shadow, "SetRotation", 0)
            end
            local w, ht = art, art
            if current == "needle" then w, ht = (turns and needleW or needleH), needleH end
            for i = 1, #cut do
                local t = cut[i]
                sized(t, w, ht)
                method(t, "ClearAllPoints")
                fast(t, "SetPoint", "CENTER", holder, "CENTER", 0, 0)
            end
            if turns then
                for i = 1, #cut do fast(cut[i], "SetTexCoord", 0, 1 / 16, 0, 1 / 8) end
            end
            fast(pool, current == "needle" and "Hide" or "Show")
        end
        shape("pointer")

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

        -- Ends a drag that will get no OnDragStop: the arrow was hidden or
        -- sent behind with the button still down. The place is not saved.
        local function letGo()
            if not dragging then return end
            dragging = false
            method(f, "StopMovingOrSizing")
            method(f, "SetUserPlaced", false)
        end

        method(f, "SetMovable", true)
        method(f, "EnableMouse", true)
        method(f, "RegisterForDrag", "LeftButton")
        method(f, "SetScript", "OnDragStart", function()
            -- The arrow moves only while Ctrl is held, as in the
            -- predecessor: a plain left drag does nothing. Asked once, at
            -- the start; a client that cannot say starts no drag.
            local okKey, held = call(env.IsControlKeyDown)
            if not (okKey and held == true) then return end
            dragging = true
            method(f, "StartMoving")
        end)
        method(f, "SetScript", "OnDragStop", function()
            -- No drag in progress: it was let go when the arrow was hidden
            -- or sent behind, and the client fires this late. Nothing is
            -- stopped again and no place is saved.
            if not dragging then return end
            dragging = false
            method(f, "StopMovingOrSizing")
            method(f, "SetUserPlaced", false)
            local point = standing()
            if point and moved then pcall(moved, point) end
        end)
        method(f, "SetScript", "OnHide", letGo)

        function h.place(point)
            if type(point) ~= "table" then return end
            method(f, "ClearAllPoints")
            method(f, "SetPoint", point[1], parent, point[2], point[3], point[4])
        end
        function h.attach(other)
            local to = arrowFrames[other]
            if to == nil then return end
            method(f, "ClearAllPoints")
            method(f, "SetPoint", "CENTER", to, "CENTER", 0, 0)
        end
        function h.show(on)
            if not on then letGo() end
            method(f, on and "Show" or "Hide")
        end
        function h.look(look)
            if look ~= current then shape(look) end
        end
        function h.draw(d)
            if type(d) ~= "table" then return end
            local r, g, b = 1, 1, 1
            local col = d.colour
            if type(col) == "table" then r, g, b = col[1] or 1, col[2] or 1, col[3] or 1 end
            if turns then
                local turn = d.turn or 0
                for i = 1, #cut do fast(cut[i], "SetRotation", turn) end
            elseif type(d.cell) == "table" then
                local cl = d.cell
                for i = 1, #cut do fast(cut[i], "SetTexCoord", cl[1], cl[2], cl[3], cl[4]) end
            end
            for i = 1, #tinted do fast(tinted[i], "SetVertexColor", r, g, b) end
            local on = d.body or 1
            if current == "needle" then
                -- The needle is the quieter arrow: lower opacities, no float.
                fast(body, "SetAlpha", on * 0.9)
                fast(shine, "SetAlpha", on * 0.55)
                fast(shadow, "SetAlpha", on * 0.45)
            else
                fast(body, "SetAlpha", on)
                fast(shine, "SetAlpha", d.shine or 0.9)
                fast(shadow, "SetAlpha", d.shadow or 0.75)
                fast(pool, "SetAlpha", d.pool or 0.35)
                fast(body, "SetPoint", "CENTER", holder, "CENTER", 0, d.bodyY or 0)
            end
            local arrived = d.arrived and true or false
            for i = 1, #ring do fast(ring[i], arrived and "Show" or "Hide") end
            if arrived then
                fast(halo, "SetAlpha", d.halo or 0)
                local rp, bm = d.ripple, d.beam
                local rw, rh, ra, bw, bh, ba
                if type(rp) == "table" then rw, rh, ra = rp[1], rp[2], rp[3] end
                if type(bm) == "table" then bw, bh, ba = bm[1], bm[2], bm[3] end
                if type(rw) == "number" and type(rh) == "number" then sized(ripple, rw, rh) end
                fast(ripple, "SetAlpha", ra or 0)
                for i = 1, #beams do
                    if type(bw) == "number" and type(bh) == "number" then sized(beams[i], bw, bh) end
                    fast(beams[i], "SetAlpha", ba or 0)
                end
            end
        end
        function h.scale(n)
            if type(n) ~= "number" or n <= 0 then return end
            -- The frame keeps its size: resizing it would move a point
            -- saved on one of its corners.
            method(holder, "SetScale", n)
        end
        -- True while the player is dragging this arrow: it is not re-placed.
        function h.dragging()
            return dragging
        end
        function h.alpha(n)
            if type(n) == "number" then method(f, "SetAlpha", n) end
        end
        function h.behind(on)
            if on then letGo() end
            -- The holder and the text frame are frames of their own: left at
            -- their levels they would keep the art and the text above the
            -- arrow this one is meant to be under.
            levels(on and math.max(level - 2, 0) or level)
            method(f, "EnableMouse", not on)
        end
        function h.text(lines, point)
            if label == nil then return end
            local out = {}
            for i = 1, #(type(lines) == "table" and lines or {}) do out[i] = tostring(lines[i]) end
            if #out == 0 or type(point) ~= "table" then
                method(label, "Hide")
                return
            end
            method(label, "SetText", table.concat(out, "\n"))
            method(label, "ClearAllPoints")
            method(label, "SetPoint", point[1], f, point[2], point[3], point[4])
            method(label, "Show")
        end
        function h.onMoved(fn)
            moved = fn
        end
        arrowFrames[h] = f
        return h
    end

    return c
end

ns.client = ns.make.client(_G)
