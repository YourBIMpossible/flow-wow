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
    -- What the client itself does with an event before any listener hears
    -- of it: event name -> fn(...). A listener that asks the client about
    -- the thing the event is about then gets today's answer, whichever
    -- order the listeners were added in (CR1). A step runs unguarded, so
    -- one that raised would stop every listener of its event: each step
    -- is one plain assignment and nothing else (CT3).
    local first = {}

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
                eventFrame:SetScript("OnEvent", function(_, name, ...)
                    -- P-READS (lead section 248): an argument the client
                    -- marks secret, or will not say about, is handed on as
                    -- nil; the count of arguments is kept. issecretvalue is
                    -- a first guess on this client. Only nil arguments are
                    -- never asked about.
                    if type(env.issecretvalue) == "function" then
                        local n = select("#", ...)
                        local args, found = { ... }, false
                        for i = 1, n do
                            if args[i] ~= nil then
                                local okSecret, secret = pcall(env.issecretvalue, args[i])
                                if not okSecret or secret ~= false then
                                    args[i] = nil
                                    found = true
                                end
                            end
                        end
                        if found then
                            local ownSecret = first[name]
                            if ownSecret then ownSecret(unpack(args, 1, n)) end
                            events.call(name, unpack(args, 1, n))
                            return
                        end
                    end
                    local own = first[name]
                    if own then own(...) end
                    events.call(name, ...)
                end)
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
    -- Docs (warcraft.wiki.gg, API time): timestamp = time([dateTable]); name and
    -- arguments match.
    function c.clock()
        local ok, t = call(env.time)
        if not ok or type(t) ~= "number" or t ~= t or t <= 0 or t == math.huge then return nil end
        return t
    end

    -- Milliseconds, fine-grained, for timing work. debugprofilestop is a
    -- first guess on 16001; falls back to GetTime, which only moves per frame.
    -- Docs (warcraft.wiki.gg, API debugprofilestop): elapsedMilliseconds =
    -- debugprofilestop(), listed for the 1.x clients; name and arguments match.
    function c.clockMs()
        local ok, ms = call(env.debugprofilestop)
        if ok and tonumber(ms) then return tonumber(ms) end
        return c.now() * 1000
    end

    -- Every line said also goes to the onPrint listeners (the copy box). A
    -- listener that raises misses that line and no more: saying a line
    -- never fails because of who listens, and the others still hear it.
    -- A client with no print still feeds them.
    local prints = Listeners(function() end, function() end)
    function c.print(text)
        text = tostring(text)
        call(env.print, text)
        prints.call("print", text)
    end

    -- fn(text) for every line c.print says. Returns a cancel function.
    function c.onPrint(fn)
        if type(fn) ~= "function" then return function() end end
        return prints.add("print", function(text) pcall(fn, text) end)
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
    -- Docs (warcraft.wiki.gg, API C_Container.GetContainerNumFreeSlots):
    -- numFreeSlots, bagFamily = ...(bagIndex); the second value matches.
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

    -- Lead section 337 item 1 (the sell list's "Sell these" button): the
    -- bag stacks with where each one is, and one slot read again before it
    -- is sold. Read with the same C_Container calls as bagItems above
    -- (GetContainerNumSlots, GetContainerItemInfo); first guess, not seen
    -- in game, that a slot's answer is the same one bagItems reads.
    --   c.bagSlots() -> { { bag = id, slot = n, item = link or ID, count = n }, ... }
    --     in bag then slot order; nil when any bag or slot could not be read
    --   c.bagSlot(bag, slot) -> item, count; nil for an empty slot; false
    --     when it could not be read or bag and slot are not whole numbers
    function c.bagSlots()
        local slotsOf = container("GetContainerNumSlots")
        local out = {}
        for _, bag in ipairs(bagIds()) do
            local ok, total = call(slotsOf, bag)
            if not ok or not wholeCount(total) then return nil end
            for slot = 1, total do
                local item, count = slotItem(bag, slot)
                if item == false then return nil end
                if item ~= nil then out[#out + 1] = { bag = bag, slot = slot, item = item, count = count } end
            end
        end
        return out
    end

    function c.bagSlot(bag, slot)
        if not wholeCount(bag) or not wholeCount(slot) or slot < 1 then return false end
        return slotItem(bag, slot)
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
    -- has the first guess below, unless something else listens to these
    -- events. The window's state is set before any listener of either
    -- event runs (`first`, as for the trainer window), so bankOpen()
    -- answers inside a BANKFRAME_OPENED listener whichever order the
    -- listeners were added in. The two listeners here only make the client
    -- take the events.
    local bankState, bankWatched
    first.BANKFRAME_OPENED = function() bankState = true end
    first.BANKFRAME_CLOSED = function() bankState = false end
    function c.watchBank()
        if bankWatched then return end
        bankWatched = true
        events.add("BANKFRAME_OPENED", function() end)
        events.add("BANKFRAME_CLOSED", function() end)
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
    -- it, merchantOpen() only has the first guess below, unless something
    -- else listens to these events. The window's state is set before any
    -- listener of either event runs (`first`), so merchantOpen() answers
    -- inside a MERCHANT_SHOW listener whichever order the listeners were
    -- added in. The two listeners here only make the client take the
    -- events.
    local merchantState, merchantWatched
    first.MERCHANT_SHOW = function() merchantState = true end
    first.MERCHANT_CLOSED = function() merchantState = false end
    function c.watchMerchant()
        if merchantWatched then return end
        merchantWatched = true
        events.add("MERCHANT_SHOW", function() end)
        events.add("MERCHANT_CLOSED", function() end)
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

    -- True when the client marks a value secret (issecretvalue), or will
    -- not say: such a value is "not known", never read as false or as 0.
    local function hidden(v)
        if env.issecretvalue == nil then return false end
        local okSecret, secret = call(env.issecretvalue, v)
        return not okSecret or secret ~= false
    end

    -- Lead section 337 item 1 (ACTING): sells one bag slot to the open
    -- merchant, only on the player click (Items/SellThese.lua). First guess,
    -- not seen in game on 16001: C_Container.UseContainerItem(bag, slot)
    -- sells the slot while the merchant window is open. Asked only when
    -- InCombatLockdown answers a plain false and the merchant is open, both
    -- read again here for each slot.
    --   c.sellBagItem(bag, slot) -> true, or nil and why:
    --     "combat", "closed", "bad" (not a bag slot), "noCall", "raised"
    function c.sellBagItem(bag, slot)
        local okLock, locked = call(env.InCombatLockdown)
        if not okLock or hidden(locked) or locked ~= false then return nil, "combat" end
        if c.merchantOpen() ~= true then return nil, "closed" end
        if not wholeCount(bag) or not wholeCount(slot) or slot < 1 then return nil, "bad" end
        local fn = container("UseContainerItem")
        if fn == nil then return nil, "noCall" end
        if not pcall(fn, bag, slot) then return nil, "raised" end
        return true
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
            if not ok or (info ~= nil and hidden(info)) then return false end
            if type(info) ~= "table" then return true end
            if (info.price ~= nil and hidden(info.price)) or (info.stackCount ~= nil and hidden(info.stackCount)) then
                return false
            end
            return true, info.price, info.stackCount, info.hasExtendedCost
        end
        local ok, _, _, price, quantity, _, _, _, extended = call(env.GetMerchantItemInfo, index)
        if not ok or (price ~= nil and hidden(price)) or (quantity ~= nil and hidden(quantity)) then return false end
        return true, price, quantity, extended
    end

    -- Every item the open merchant has on sale, in the window's order:
    --   { { index = n, item = link, price = copper for the stack shown,
    --       stack = how many that price buys, other = true / false }, ... }
    -- A field the client did not give is left out, never guessed: no item,
    -- no price (never 0 in its place), no stack. other = true says the
    -- item costs something that is not coin; left out when not known.
    -- nil unless the window is known to be open, and nil when the count or
    -- any one item could not be read: never a shorter list. A count, link,
    -- price or stack the client marks secret is "could not be read" too:
    -- the whole reading is nil. This only
    -- reads. Nothing here buys, sells or picks anything up.
    -- First guesses: GetMerchantNumItems, GetMerchantItemLink(index).
    -- A link, price or stack the client did not give at all (nil: an item
    -- not cached yet, say) is never asked about for secrecy, because the
    -- client raises when asked about nil. That row only loses the field.
    function c.merchantItems()
        if c.merchantOpen() ~= true then return nil end
        local ok, count = call(env.GetMerchantNumItems)
        if not ok or hidden(count) or not wholeCount(count) then return nil end
        local out = {}
        for index = 1, count do
            local okLink, link = call(env.GetMerchantItemLink, index)
            if not okLink or (link ~= nil and hidden(link)) then return nil end
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

    -- G3: what is on the open merchant's Buyback tab, in the tab's order:
    --   { { index = n, item = link, name = text, price = copper to buy it
    --       back, count = how many }, ... }
    -- A field the client did not give is left out, never guessed. nil
    -- unless the merchant window is known to be open, and nil when the
    -- count or any one item could not be read or is marked secret: never a
    -- shorter list. This only reads. Nothing here buys anything back.
    -- First guesses, not seen in game on 16001: GetNumBuybackItems,
    -- GetBuybackItemLink(index), GetBuybackItemInfo(index) answering name,
    -- texture, price, quantity.
    function c.returnableItems()
        if c.merchantOpen() ~= true then return nil end
        local ok, count = call(env.GetNumBuybackItems)
        if not ok or hidden(count) or not wholeCount(count) then return nil end
        local out = {}
        for index = 1, count do
            local okLink, link = call(env.GetBuybackItemLink, index)
            if not okLink or (link ~= nil and hidden(link)) then return nil end
            local okInfo, name, _, price, quantity = call(env.GetBuybackItemInfo, index)
            if not okInfo or (name ~= nil and hidden(name)) or (price ~= nil and hidden(price))
                or (quantity ~= nil and hidden(quantity)) then
                return nil
            end
            local row = { index = index }
            if type(link) == "string" then row.item = link end
            if type(name) == "string" and name ~= "" then row.name = name end
            if wholeCount(price) then row.price = price end
            if wholeCount(quantity) and quantity > 0 then row.count = quantity end
            out[index] = row
        end
        return out
    end

    -- The profession whose window is open, and every recipe in it:
    --   { profession = skill line, skill = n, max = n,
    --     recipes = { { id =, name =, learned = true / false,
    --                   difficulty =, skillUps = }, ... } }
    -- difficulty is the window colour (optimal, medium, easy, trivial) from
    -- relativeDifficulty 0 to 3, and skillUps is numSkillUps when it is a
    -- whole count; each is left out when the client gives anything else.
    -- Needs game test: relativeDifficulty and numSkillUps on 16001 (P-PROF);
    -- captured as the Diag fields recipeDifficulty and recipeSkillUps.
    -- nil when no profession window is open or the client will not say.
    -- Seen in game on 16001 (Blacksmithing): for a moment after the window
    -- opens the client says "ready" but is still changing its data source,
    -- and lists no recipes. That is not an empty profession, so it is nil
    -- until IsDataSourceChanging answers false. One recipe that cannot be
    -- read makes the whole reading nil: never a shorter list.
    local RELATIVE_DIFFICULTY = { [0] = "optimal", [1] = "medium", [2] = "easy", [3] = "trivial" }

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
            rows[i] = { id = ids[i], name = type(info.name) == "string" and info.name or nil, learned = info.learned,
                difficulty = RELATIVE_DIFFICULTY[info.relativeDifficulty],
                skillUps = wholeCount(info.numSkillUps) and info.numSkillUps or nil }
        end
        local out = { profession = line, skill = base.skillLevel, max = base.maxSkillLevel, recipes = rows }
        -- The profession's name as the client spells it (professionName, a
        -- first guess on 16001): given only when it is a plain string.
        local name = base.professionName
        if type(name) == "string" and not hidden(name) then out.name = name end
        return out
    end

    -- Section 227 (P-GOALS-RECIPE): one recipe's product, how many one
    -- craft makes, and its required basic mats:
    --   { makes = item ID, yield = n, mats = { [item ID] = n a craft } }
    -- from C_TradeSkillUI.GetRecipeSchematic(id, false). Optional and
    -- finishing slots are left out; a required slot names its first reagent.
    -- Anything that can't be read makes the whole answer nil: never a
    -- shorter list. The field names are first guesses, not seen in game.
    function c.recipeSchematic(id)
        if type(id) ~= "number" then return nil end
        local ui = env.C_TradeSkillUI
        if type(ui) ~= "table" then return nil end
        local ok, s = call(ui.GetRecipeSchematic, id, false)
        if not ok or type(s) ~= "table" then return nil end
        local function count(n, least)
            return wholeCount(n) and n < math.huge and n >= least
        end
        local makes = s.outputItemID
        if not count(makes, 1) then return nil end
        local yield = s.quantityMin
        if yield == nil then yield = 1 end
        if not count(yield, 1) then return nil end
        local slots = s.reagentSlotSchematics
        if type(slots) ~= "table" then return nil end
        local mats = {}
        for i = 1, #slots do
            local slot = slots[i]
            if type(slot) ~= "table" then return nil end
            local basic = slot.reagentType == nil or slot.reagentType == 1
            if basic and slot.required ~= false then
                local first = type(slot.reagents) == "table" and slot.reagents[1] or nil
                local item = type(first) == "table" and first.itemID or nil
                local n = slot.quantityRequired
                if not count(item, 1) or not count(n, 1) then return nil end
                mats[item] = (mats[item] or 0) + n
            end
        end
        if next(mats) == nil then return nil end
        return { makes = makes, yield = yield, mats = mats }
    end

    -- P-PROF (N23): the colour words the classic window gives a recipe row.
    -- Needs game test: the words on 16001. Section 245 (lead item 1, LOW):
    -- one table for tradeSkillRows and tradeSkillSchematic; a word not in
    -- it is left out, never saved as it came.
    local ROW_DIFFICULTY = { optimal = "optimal", medium = "medium", easy = "easy", trivial = "trivial", difficult = "difficult" }

    -- N24 (lead section 274 item 2): the tools a classic recipe row needs,
    -- GetTradeSkillTools(index), answered in pairs (name, carried):
    --   { { name =, has = true | false } }, {} when the recipe needs none.
    -- Carried 1 or true is carried; nothing, 0 or false is not. nil when the
    -- call is missing or raises, the row is no whole number from 1, a name
    -- is empty, not text or secret, or a carried answer is any other value.
    -- Look only. Needs game test: the call and its answer shape on 16001.
    local function packed(...) return select("#", ...), { ... } end
    function c.tradeSkillTools(index)
        if not wholeCount(index) or index < 1 or index == math.huge then return nil end
        local n, a = packed(call(env.GetTradeSkillTools, index))
        if a[1] ~= true then return nil end
        local out = {}
        for i = 2, n, 2 do
            local name, carried = a[i], a[i + 1]
            if name ~= nil or carried ~= nil then
                if type(name) ~= "string" or hidden(name) or name == "" then return nil end
                if carried ~= nil and hidden(carried) then return nil end
                local has
                if carried == 1 or carried == true then
                    has = true
                elseif carried == nil or carried == 0 or carried == false then
                    has = false
                else
                    return nil
                end
                out[#out + 1] = { name = name, has = has }
            end
        end
        return out
    end

    -- Section 231 item 1: the fallback for recipeSchematic when the client
    -- has no C_TradeSkillUI.GetRecipeSchematic (not in CLIENT-NAMES-16001).
    -- The classic reads of the open trade skill window, by row index, not
    -- recipe id: GetTradeSkillItemLink(index) for the product,
    -- GetTradeSkillNumMade(index) for the yield (its least; none given: one),
    -- GetTradeSkillNumReagents(index), then for each reagent
    -- GetTradeSkillReagentItemLink(index, r) for the item and the third answer
    -- of GetTradeSkillReagentInfo(index, r) for how many a craft takes.
    -- Section 238 (RF-1 to RF-3, as Flow's readClassic in
    -- Modules/Crafting/Recipes.lua): GetTradeSkillInfo(index) first, for the
    -- row's name and kind (its difficulty, a ROW_DIFFICULTY word or left
    -- out); a "header" or "subheader" row is
    -- no recipe: nil (RF-2). A product link that is no item link (an
    -- enchant) gives makes nil, the reagents kept (RF-1); no product link
    -- yet gives makes nil and partial. A reagent whose item or count is not
    -- read yet is left out and the answer says partial = true (RF-3). No
    -- reagent count, or none (RF-4), or any other read that fails: nil.
    --   { name =, difficulty =, makes = (nil: no item), yield =, mats =,
    --     partial = (true, or nil when every reagent was read) }
    -- First guesses, not seen in game. Items/RecipeBook.lua calls it for
    -- each row of tradeSkillRows (section 233, GR2-1).
    function c.tradeSkillSchematic(index)
        if not wholeCount(index) or index < 1 or index == math.huge then return nil end
        local okInfo, name, kind = call(env.GetTradeSkillInfo, index)
        if not okInfo or type(kind) ~= "string" or hidden(kind) then return nil end
        if kind == "header" or kind == "subheader" then return nil end
        if type(name) ~= "string" or hidden(name) or name == "" then return nil end
        local function itemOf(ok, link)
            if not ok or type(link) ~= "string" or hidden(link) then return nil end
            local id = tonumber(link:match("item:(%d+)"))
            if not id or id <= 0 then return nil end
            return id
        end
        local function count(n, least)
            return wholeCount(n) and n < math.huge and n >= least
        end
        local okLink, link = call(env.GetTradeSkillItemLink, index)
        if not okLink then return nil end
        local makes, partial
        if link == nil then
            partial = true
        elseif type(link) ~= "string" or hidden(link) then
            return nil
        elseif link:find("item:", 1, true) then
            makes = itemOf(true, link)
            if not makes then return nil end
        end
        local yield = 1
        if env.GetTradeSkillNumMade ~= nil then
            local okMade, least = call(env.GetTradeSkillNumMade, index)
            if not okMade then return nil end
            if least ~= nil then yield = least end
        end
        if not count(yield, 1) then return nil end
        local okN, n = call(env.GetTradeSkillNumReagents, index)
        if not okN or not count(n, 1) then return nil end
        local mats = {}
        for r = 1, n do
            local item = itemOf(call(env.GetTradeSkillReagentItemLink, index, r))
            local okNeed, _, _, need = call(env.GetTradeSkillReagentInfo, index, r)
            if item and okNeed and count(need, 1) then
                mats[item] = (mats[item] or 0) + need
            else
                partial = true
            end
        end
        return { name = name, difficulty = ROW_DIFFICULTY[kind], makes = makes, yield = yield, mats = mats,
                 partial = partial }
    end

    -- Section 233 (GR2-1): the rows of the classic trade skill window, for
    -- when C_TradeSkillUI can't be read. GetTradeSkillLine() for the
    -- profession's name, skill and max ("UNKNOWN" or no name: no window),
    -- GetNumTradeSkills() rows (0: no window), and GetTradeSkillInfo(i) for
    -- each row's name and kind; "header" and "subheader" rows are left out.
    -- Every other row is a recipe the player has learned. Only what the
    -- window shows: a collapsed header hides its rows. Section 238 (RF-2):
    -- each row keeps its kind as its difficulty, as Flow did.
    --   { name =, skill =, max =, rows = { { index = i, name =, difficulty = } },
    --     collapsed =, filtered = }   (section 245, below)
    -- Anything that can't be read makes the whole answer nil: never a
    -- shorter list. First guesses, not seen in game.
    -- Section 245 (RB2-2): whether the rows are every learned recipe.
    --   collapsed = true when a header's fourth GetTradeSkillInfo answer
    --     (isExpanded) is false; false when every header says true (or 1);
    --     nil when one says anything else (nil may be a collapsed header
    --     on clients that answer 1/nil). No header: false.
    --   filtered = false when GetTradeSkillSubClassFilter(0) and
    --     GetTradeSkillInvSlotFilter(0) both say "all" (true or 1); true
    --     when one answers anything else; nil when one is missing, fails or
    --     is secret.
    --   whole is never set here: no reliable read of the "have materials"
    --   box or the name search box is known, so whether they hide rows is
    --   unknown, and RecipeBook drops nothing from this read.
    --   Section 253 (RB4-1): RecipeBook now counts collapsed = false and
    --   filtered = false as every learned recipe, as legacy Flow did.
    -- All first guesses, needs game test (Core/Diag.lua NAMES lists the
    -- names, and the candidates for the two unknown reads).
    local function allShown(fn)
        if fn == nil then return nil end
        local ok, on = call(fn, 0)
        if not ok then return nil end
        if on ~= nil and hidden(on) then return nil end
        return on == true or on == 1
    end

    function c.tradeSkillRows()
        local okLine, name, skill, max = call(env.GetTradeSkillLine)
        if not okLine or type(name) ~= "string" or hidden(name) or name == "" or name == "UNKNOWN" then
            return nil
        end
        local okN, n = call(env.GetNumTradeSkills)
        if not okN or not wholeCount(n) or n < 1 or n == math.huge then return nil end
        local rows, collapsed = {}, false
        for i = 1, n do
            local okInfo, rowName, kind, _, expanded = call(env.GetTradeSkillInfo, i)
            if not okInfo or type(kind) ~= "string" or hidden(kind) then return nil end
            if kind ~= "header" and kind ~= "subheader" then
                if type(rowName) ~= "string" or hidden(rowName) or rowName == "" then return nil end
                rows[#rows + 1] = { index = i, name = rowName, difficulty = ROW_DIFFICULTY[kind] }
            elseif expanded == nil or hidden(expanded) then
                if collapsed ~= true then collapsed = nil end
            elseif expanded == false then
                collapsed = true
            elseif expanded ~= true and expanded ~= 1 then
                if collapsed ~= true then collapsed = nil end
            end
        end
        local out = { name = name, rows = rows, collapsed = collapsed }
        local sub, slot = allShown(env.GetTradeSkillSubClassFilter), allShown(env.GetTradeSkillInvSlotFilter)
        if sub == false or slot == false then
            out.filtered = true
        elseif sub == true and slot == true then
            out.filtered = false
        end
        if wholeCount(skill) and not hidden(skill) then out.skill = skill end
        if wholeCount(max) and not hidden(max) then out.max = max end
        return out
    end

    -- A string the client gave and did not mark secret, or nil.
    local function text(ok, v)
        if not ok or v == nil or hidden(v) or type(v) ~= "string" or v == "" then return nil end
        return v
    end

    -- Starts following the trainer window (TRAINER_SHOW / TRAINER_CLOSED,
    -- first guesses: not seen in game on 16001). trainer() calls it too.
    -- The window's state is set before any listener of either event runs
    -- (`first`), so trainer() answers inside a TRAINER_SHOW listener that
    -- was added before this was first called, or that is the first to call
    -- it (CR1). The two listeners here only make the client take the
    -- events.
    local trainerState, trainerWatched
    first.TRAINER_SHOW = function() trainerState = true end
    first.TRAINER_CLOSED = function() trainerState = false end
    function c.watchTrainer()
        if trainerWatched then return end
        trainerWatched = true
        events.add("TRAINER_SHOW", function() end)
        events.add("TRAINER_CLOSED", function() end)
    end

    -- true / false, or nil when not known: the last trainer event, and
    -- before any event ClassTrainerFrame:IsShown(), a first guess.
    local function trainerOpen()
        if trainerState ~= nil then return trainerState end
        local frame = env.ClassTrainerFrame
        if type(frame) ~= "table" then return nil end
        local ok, shown = call(frame.IsShown, frame)
        if not ok then return nil end
        return shown and true or false
    end

    -- ---------------------------------------------------------------- F8
    -- Trainer and spell learning (FEATURE-PLAN F8, owner Plexy since LEDGER
    -- 125): the service rows and the window's filter, added to the one
    -- trainer read below (no second trainer read). First guesses, not seen in
    -- game on 16001: GetNumTrainerServices(), GetTrainerServiceInfo(i) (name,
    -- rank, category "available" / "unavailable" / "used" / "header"),
    -- GetTrainerServiceCost(i), GetTrainerServiceLevelReq(i) and
    -- GetTrainerServiceTypeFilter("available" / "unavailable" / "used").
    -- Checked (LEDGER 129) against Flow, which used them on this client:
    -- GetNumTrainerServices, GetTrainerServiceInfo (newer answer order, no
    -- rank), GetTrainerServiceCost, GetTrainerServiceLevelReq (Modules/Trainer.lua),
    -- GetTrainerServiceSkillLine(1) (Modules/Nav/Places.lua). Still a first
    -- guess: GetTrainerServiceTypeFilter (Flow never called it).
    --
    -- services { { name, rank, state, cost, level } ... } in the window's order:
    --          state "available", "unavailable" or "known" (the game's
    --          "used"); header rows are left out. rank, cost and level are
    --          left out of a row when not read. One row whose name or state
    --          cannot be read drops the whole list (never a shorter list).
    -- filter   { available, unavailable, known }, each true or false; nil
    --          when any of the three cannot be read.
    -- Look-only: nothing is trained or bought.
    local SERVICE_STATE = { available = "available", unavailable = "unavailable", used = "known" }
    local function wholeOrNil(ok, v)
        if not ok or v == nil or hidden(v) or type(v) ~= "number" or v ~= v then return nil end
        if v < 0 or v == math.huge or v ~= math.floor(v) then return nil end
        return v
    end
    local function trainerFilter()
        local out = {}
        for game, ours in pairs({ available = "available", unavailable = "unavailable", used = "known" }) do
            -- Older clients answer 1 for shown and nothing for hidden: an
            -- answer of nothing from a call that ran is "not shown".
            local ok, on = call(env.GetTrainerServiceTypeFilter, game)
            if not ok then return nil end
            if on == nil then on = false end
            if hidden(on) then return nil end
            if on == 1 then on = true elseif on == 0 then on = false end
            if type(on) ~= "boolean" then return nil end
            out[ours] = on
        end
        return out
    end
    -- N23 (lead section 274 item 2): the profession skill a trainer recipe
    -- needs, the second answer of GetTrainerServiceSkillReq(i) (the first is
    -- the skill name); a whole number from 1, else nil and left out of the
    -- row. Needs game test: the answer order on 16001.
    local function skillReq(i)
        local ok, _, skill = call(env.GetTrainerServiceSkillReq, i)
        local v = wholeOrNil(ok, skill)
        if v == nil or v < 1 then return nil end
        return v
    end
    local function trainerServices()
        local n = wholeOrNil(call(env.GetNumTrainerServices))
        if not n then return nil, trainerFilter() end
        local rows = {}
        for i = 1, n do
            -- Two answer orders (source: Flow's Modules/Trainer.lua serviceInfo,
            -- used on this client): classic clients give (name, rankText,
            -- category); newer ones, WoW: Forever included, (name, category,
            -- icon) and no rank. The category word tells them apart.
            local ok, name, a, b = call(env.GetTrainerServiceInfo, i)
            local rank, category
            if not ok then return nil, trainerFilter() end
            if type(a) == "string" and not hidden(a) and (SERVICE_STATE[a] or a == "header") then
                category = a
            else
                rank, category = a, b
            end
            if category ~= nil and hidden(category) then return nil, trainerFilter() end
            if category ~= "header" then
                local state = SERVICE_STATE[category]
                name = text(ok, name)
                if not state or not name then return nil, trainerFilter() end
                rows[#rows + 1] = {
                    name = name, rank = text(ok, rank), state = state,
                    cost = wholeOrNil(call(env.GetTrainerServiceCost, i)),
                    level = wholeOrNil(call(env.GetTrainerServiceLevelReq, i)),
                    skill = skillReq(i),
                }
            end
        end
        return rows, trainerFilter()
    end

    -- The trainer whose window is open:
    --   { profession = name or nil, npc = name, services, filter }
    -- services and filter as above (F8).
    -- nil unless the window is known to be open, nil for a player, and nil
    -- when the client will not say whether it is a player or what it is
    -- called. profession is the trainer's first skill line as the client
    -- spells it, left out when it is not said. Only the unit "npc" is
    -- asked about. Every call here is a first guess, not seen in game on
    -- 16001: UnitIsPlayer("npc"), UnitName("npc"),
    -- GetTrainerServiceSkillLine(1).
    function c.trainer()
        c.watchTrainer()
        if trainerOpen() ~= true then return nil end
        local okPlayer, player = call(env.UnitIsPlayer, "npc")
        if not okPlayer or player == nil or hidden(player) or player ~= false then return nil end
        local npc = text(call(env.UnitName, "npc"))
        if not npc then return nil end
        local out = { profession = text(call(env.GetTrainerServiceSkillLine, 1)), npc = npc }
        out.services, out.filter = trainerServices()
        return out
    end

    -- F8: told when you learn a spell.
    --   client.onSpellLearned(fn) -> cancel;  fn({ id, name, rank })
    -- Events: LEARNED_SPELL_IN_SKILL_LINE (spellID, ...) and
    -- LEARNED_SPELL_IN_TAB (spellID, ...). Source: Flow's Modules/NewSpell.lua
    -- found on this client that LEARNED_SPELL_IN_TAB does not exist and the
    -- event is LEARNED_SPELL_IN_SKILL_LINE; both are followed, and the same
    -- spell told twice within a second is told once. That the first argument
    -- is the spell id is a first guess (Flow did not read the arguments).
    -- Name: C_Spell.GetSpellInfo(id).name where the client has it (Flow's
    -- Modules/Rotation/Compat.lua SpellInfo prefers it), else GetSpellInfo's
    -- first answer. Rank: C_Spell.GetSpellSubtext or GetSpellSubtext where
    -- present, else GetSpellInfo's second answer when that is text; a first
    -- guess. A spell with no readable name tells nobody; a rank not read is
    -- left out. fn's errors stay here.
    local learnedListeners, learnedWatched = {}, false
    local lastLearned, lastLearnedAt
    local function spellName(id)
        local group = env.C_Spell
        if type(group) == "table" and type(group.GetSpellInfo) == "function" then
            local ok, info = call(group.GetSpellInfo, id)
            if not ok or type(info) ~= "table" or hidden(info) then return nil end
            return text(true, info.name), nil
        end
        local ok, name, oldRank = call(env.GetSpellInfo, id)
        return text(ok, name), text(ok, oldRank)
    end
    local function spellLearned(id)
        if type(id) ~= "number" or hidden(id) then return end
        local now = c.uptime()   -- nil when the client gives no time: then nothing is held back
        if lastLearned == id and type(now) == "number" and type(lastLearnedAt) == "number"
            and now - lastLearnedAt < 1 then
            return
        end
        lastLearned, lastLearnedAt = id, now
        local name, oldRank = spellName(id)
        if not name then return end
        local subtext = env.GetSpellSubtext
        if type(env.C_Spell) == "table" and type(env.C_Spell.GetSpellSubtext) == "function" then
            subtext = env.C_Spell.GetSpellSubtext
        end
        local rank = text(call(subtext, id)) or oldRank
        for _, fn in ipairs({ unpack(learnedListeners) }) do
            pcall(fn, { id = id, name = name, rank = rank })
        end
    end
    function c.onSpellLearned(fn)
        if type(fn) ~= "function" then return nil end
        if not learnedWatched then
            learnedWatched = true
            events.add("LEARNED_SPELL_IN_SKILL_LINE", spellLearned)
            events.add("LEARNED_SPELL_IN_TAB", spellLearned)
        end
        learnedListeners[#learnedListeners + 1] = fn
        return function()
            for i = #learnedListeners, 1, -1 do
                if learnedListeners[i] == fn then table.remove(learnedListeners, i) end
            end
        end
    end
    -- -------------------------------------------------------------- end F8

    -- "Horde", "Alliance", or nil when not known (any other answer, no
    -- answer, a secret one). UnitFactionGroup("player"), a first guess:
    -- not seen in game on 16001.
    function c.faction()
        local group = text(call(env.UnitFactionGroup, "player"))
        if group == "Horde" or group == "Alliance" then return group end
        return nil
    end

    -- Your class token ("DRUID"), the same in every language, or nil when
    -- not known. The second answer of UnitClass("player"), a first guess:
    -- not seen in game on 16001.
    function c.class()
        local ok, _, token = call(env.UnitClass, "player")
        return text(ok, token)
    end

    -- Are you stealthed: true, false, or nil when not known (no call, a
    -- failed call, a secret answer, or anything but true or false: no
    -- answer is not "not stealthed"). IsStealthed(), a first guess: not
    -- seen in game on 16001. It names no unit and only reads.
    function c.stealthed()
        local ok, on = call(env.IsStealthed)
        if not ok or on == nil or hidden(on) or type(on) ~= "boolean" then return nil end
        return on
    end

    -- True or false as the client gave it, else nil: a failed or missing
    -- call, no answer, a secret answer, or anything but true or false.
    local function yesNo(ok, v)
        if not ok or v == nil or hidden(v) or type(v) ~= "boolean" then return nil end
        return v
    end

    -- Your target: { exists, hostile, dead }, or nil when the client does
    -- not say whether you have one. With no target the table holds only
    -- exists = false and nothing more is asked. hostile and dead are each
    -- true, false, or nil when not known: no answer is never "friendly" or
    -- "alive". First guesses, not seen in game on 16001:
    -- UnitExists("target"), UnitCanAttack("player", "target") and
    -- UnitIsDead("target"). Only "player" and "target" are named, and
    -- nothing is changed: the target is read, never chosen.
    function c.target()
        local exists = yesNo(call(env.UnitExists, "target"))
        if exists == nil then return nil end
        if not exists then return { exists = false } end
        return {
            exists = true,
            hostile = yesNo(call(env.UnitCanAttack, "player", "target")),
            dead = yesNo(call(env.UnitIsDead, "target")),
        }
    end

    -- Does one of your spells reach your target: true, false, or nil when
    -- not known (no call, a failed call, no answer, a secret answer,
    -- anything but true or false, or an id that is not a number: then the
    -- client is not asked). C_Spell.IsSpellInRange(id, "target"), a first
    -- guess: not seen in game on 16001. It is thought to give no answer
    -- with no target, or for a spell that has no range; that is nil here,
    -- never "out of range".
    function c.inRange(spellId)
        if type(spellId) ~= "number" then return nil end
        local group = env.C_Spell
        if type(group) ~= "table" then return nil end
        return yesNo(call(group.IsSpellInRange, spellId, "target"))
    end

    -- An item's stats by its link, as the client keys them: a copy, or nil
    -- when not read (no call, a failed call, no answer, a secret answer, or
    -- an answer that is no table). A stat whose value is secret is kept as
    -- false: on the item, not read. First guesses, not seen in game on
    -- 16001: C_Item.GetItemStats(link) where the client has it, else
    -- GetItemStats(link).
    local function itemStats(link)
        local group = env.C_Item
        local ok, raw
        if type(group) == "table" and type(group.GetItemStats) == "function" then
            ok, raw = call(group.GetItemStats, link)
        else
            ok, raw = call(env.GetItemStats, link)
        end
        if not ok or raw == nil or hidden(raw) or type(raw) ~= "table" then return nil end
        local out = {}
        for key, value in pairs(raw) do
            if hidden(value) then out[key] = false else out[key] = value end
        end
        return out
    end

    -- An item's equip location by its link ("INVTYPE_HEAD"), or nil when
    -- not said: no call, a failed call, a secret answer, or anything but a
    -- non-empty string. First guesses, not seen in game on 16001: the
    -- fourth answer of C_Item.GetItemInfoInstant(link) where the client has
    -- it, else of GetItemInfoInstant(link).
    local function itemKind(link)
        local group = env.C_Item
        local fn = env.GetItemInfoInstant
        if type(group) == "table" and type(group.GetItemInfoInstant) == "function" then
            fn = group.GetItemInfoInstant
        end
        local ok, _, _, _, where = call(fn, link)
        return text(ok, where)
    end

    -- The inventory slots that are compared: Gear/Read.lua's SLOT_OF. Not
    -- the shirt (4), not the tabard (19).
    local GEAR_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 }

    -- What the client says about one item and about what you wear, as the
    -- raw tables ns.GearRead.Shapes takes:
    --   { kind, stats, classID, subclassID, minLevel, unmet, speed, worn, dualWield }
    -- kind, stats   the item `link` names (see the two reads above); both
    --               left out when link is not a non-empty string.
    -- classID, subclassID, minLevel, unmet, speed   the same item (the F3
    --               block below); minLevel, unmet and speed only once it is
    --               loaded. Worn items carry kind and stats only.
    -- worn          { [inventory slot number] = { kind, stats } for an item,
    --                 false for a slot the client says holds nothing }.
    --               A slot is false only when GetInventoryItemID("player",
    --               slot) answers with no id at all. A slot whose id cannot
    --               be asked for, or is secret or no number, and a slot with
    --               an id but no link yet (the item is not loaded), have no
    --               entry: not read, which is never the same as empty.
    -- dualWield     true or false from CanDualWield(); left out otherwise.
    -- This only reads, and names no unit but "player". Nothing is equipped,
    -- moved or picked up. First guesses, not seen in game on 16001:
    -- GetInventoryItemID, GetInventoryItemLink, CanDualWield, and whether
    -- slot 18 (ranged) exists on this client. Before your character's items
    -- are loaded the client may give no id for any slot; this cannot tell
    -- that from empty slots, so it is to be asked after login.
    -- ---------------------------------------------------------------- F3
    -- Gear advice on hover (FEATURE-PLAN F3, owner Plexy): the item's class
    -- and level, what the game marks on it, its speed, your level, and the
    -- item tooltip hook. Every call here is a first guess, not seen in game
    -- on 16001; each answer that cannot be read is left out, never a default.
    -- Checked (LEDGER 129) against the predecessor Flow, which called these on
    -- this client: C_Item.GetItemStats / GetItemStats (Modules/Gear/Score.lua),
    -- C_Item.GetItemInfoInstant / GetItemInfoInstant with classID and subclassID
    -- as the 6th and 7th answers (Score.lua), C_Item.GetItemInfo / GetItemInfo
    -- with minLevel 5th (Score.lua), C_TooltipInfo.GetHyperlink lines with
    -- leftText and rightText (Modules/Gear/Analyzers.lua), TooltipDataProcessor
    -- with Enum.TooltipDataType.Item, tooltip:GetItem(), OnTooltipSetItem
    -- (Score.lua, Modules/Items/HaveCount.lua), UnitLevel, GetInventoryItemID,
    -- GetInventoryItemLink, CanDualWield. Not seen used anywhere, so still a
    -- first guess: the lines' leftColor / rightColor and the red they carry,
    -- and the SPEED string.

    -- A whole number of zero or more the client gave, not secret, or nil.
    local function whole(ok, v)
        if not ok or v == nil or hidden(v) or type(v) ~= "number" or v ~= v then return nil end
        if v < 0 or v == math.huge or v ~= math.floor(v) then return nil end
        return v
    end

    -- The item's class and subclass numbers (armor 4, weapons 2), in the
    -- client's own spelling: the sixth and seventh answers of the same
    -- GetItemInfoInstant call itemKind makes.
    local function itemType(link)
        local group = env.C_Item
        local fn = env.GetItemInfoInstant
        if type(group) == "table" and type(group.GetItemInfoInstant) == "function" then
            fn = group.GetItemInfoInstant
        end
        local ok, _, _, _, _, _, class, subclass = call(fn, link)
        return whole(ok, class), whole(ok, subclass)
    end

    -- Whether the item is loaded, and the level it needs: GetItemInfo's
    -- first answer (its name: nil while the item is not loaded) and fifth.
    -- C_Item.GetItemInfo where the client has it.
    local function itemLoaded(link)
        local group = env.C_Item
        local fn = env.GetItemInfo
        if type(group) == "table" and type(group.GetItemInfo) == "function" then fn = group.GetItemInfo end
        local ok, name, _, _, _, minLevel = call(fn, link)
        if not text(ok, name) then return false, nil end
        return true, whole(ok, minLevel)
    end

    -- The game's red for "you do not meet this" (RED_FONT_COLOR, 1 / 0.125 /
    -- 0.125), read off a line's colour table.
    local function isRed(colour)
        if type(colour) ~= "table" or hidden(colour) then return false end
        local r, g, b = colour.r, colour.g, colour.b
        if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then return false end
        if hidden(r) or hidden(g) or hidden(b) then return false end
        return r > 0.95 and g < 0.25 and b < 0.25
    end

    -- A weapon's speed from a tooltip text: the client's own SPEED word, a
    -- space, and a number with a point or a comma ("Speed 2.60").
    -- The word is the client's SPEED string; where it is missing, "Speed",
    -- the word Flow's Modules/Gear/Analyzers.lua matched on this client.
    local function speedOf(s)
        local word = env.SPEED
        if type(word) ~= "string" or word == "" then word = "Speed" end
        if type(s) ~= "string" or hidden(s) or type(word) ~= "string" or word == "" then return nil end
        if s:sub(1, #word + 1) ~= word .. " " then return nil end
        local digits = s:sub(#word + 2):match("^(%d+[%.,]%d+)$") or s:sub(#word + 2):match("^(%d+)$")
        local n = digits and tonumber((digits:gsub(",", "."))) or nil
        if not n or n <= 0 then return nil end
        return n
    end

    -- From the item's tooltip data (C_TooltipInfo.GetHyperlink(link)):
    -- unmet, the lines the game draws in red, left and right, in its own
    -- words (a red text that cannot be read is false: still a mark); and the
    -- weapon's speed. nil, nil when the data cannot be read.
    local function itemTooltip(link)
        local group = env.C_TooltipInfo
        if type(group) ~= "table" then return nil, nil end
        local ok, data = call(group.GetHyperlink, link)
        if not ok or type(data) ~= "table" or hidden(data) or type(data.lines) ~= "table" then return nil, nil end
        local unmet, speed = {}, nil
        for i = 1, #data.lines do
            local line = data.lines[i]
            if type(line) == "table" then
                for _, side in ipairs({ "left", "right" }) do
                    local s = line[side .. "Text"]
                    if isRed(line[side .. "Color"]) then
                        unmet[#unmet + 1] = text(true, s) or false
                    end
                    speed = speed or speedOf(s)
                end
            end
        end
        return unmet, speed
    end

    -- Your level: UnitLevel("player"), a whole number above 0, or nil.
    function c.level()
        local n = whole(call(env.UnitLevel, "player"))
        if not n or n < 1 then return nil end
        return n
    end

    -- Section 226 (CF-30): an item's tooltip text, left side, top to bottom,
    -- from C_TooltipInfo.GetItemByID(id), or GetHyperlink for a link; nil
    -- when the data cannot be read. First guess, not seen in game on 16001.
    function c.itemLines(item)
        local group = env.C_TooltipInfo
        if type(group) ~= "table" then return nil end
        local fn = (type(item) == "number" and group.GetItemByID) or (type(item) == "string" and group.GetHyperlink) or nil
        local ok, data = call(fn, item)
        if not ok or type(data) ~= "table" or hidden(data) or type(data.lines) ~= "table" then return nil end
        local out = {}
        for i = 1, #data.lines do
            local line = data.lines[i]
            local s = type(line) == "table" and text(true, line.leftText) or nil
            if s then out[#out + 1] = s end
        end
        return out
    end

    -- Section 226 (CF-30): an item's icon texture by id or link:
    -- C_Item.GetItemIconByID, then the older GetItemIcon. nil when neither
    -- gives one. First guess, not seen in game on 16001.
    function c.itemTexture(item)
        if item == nil then return nil end
        local group = env.C_Item
        local reads = { type(group) == "table" and group.GetItemIconByID or false, env.GetItemIcon or false }
        for i = 1, 2 do
            local ok, tex = call(reads[i], item)
            if ok and not hidden(tex) then
                if type(tex) == "number" and tex > 0 then return tex end
                if type(tex) == "string" and tex ~= "" then return tex end
            end
        end
        return nil
    end

    -- Told each time the game's item tooltip has been filled for an item:
    --   client.onItemTooltip(fn) -> cancel;  fn(link, add);  add(text, r, g, b)
    -- add appends one line to that tooltip. fn's errors stay here. Route A:
    -- GameTooltip:HookScript("OnTooltipSetItem") where the tooltip has that
    -- script; route B: TooltipDataProcessor.AddTooltipPostCall for item data,
    -- GameTooltip only. Neither replaces a script or a function of the game;
    -- a hook cannot be taken back, so cancel only stops fn being told. nil
    -- when the client offers neither. No link, or a secret one: fn is not told.
    local tooltipListeners, tooltipHooked = {}, false
    local function tooltipFilled(tip)
        if type(tip) ~= "table" or type(tip.GetItem) ~= "function" then return end
        local ok, _, link = pcall(tip.GetItem, tip)
        link = text(ok, link)
        if not link then return end
        local function add(s, r, g, b)
            if type(s) ~= "string" or type(tip.AddLine) ~= "function" then return end
            pcall(tip.AddLine, tip, s, r, g, b)
        end
        for _, fn in ipairs({ unpack(tooltipListeners) }) do pcall(fn, link, add) end
    end
    -- Order and guard (source: Flow's Modules/Gear/Score.lua hookTooltips,
    -- used on this client): TooltipDataProcessor first where the client has
    -- it; OnTooltipSetItem only otherwise, because it can fire twice for one
    -- hover, so lines are added once per fill and the mark is cleared on
    -- OnTooltipCleared.
    local function hookTooltip()
        if tooltipHooked then return true end
        local proc, enum = env.TooltipDataProcessor, env.Enum
        local itemData = type(enum) == "table" and type(enum.TooltipDataType) == "table"
            and enum.TooltipDataType.Item or nil
        if type(proc) == "table" and itemData ~= nil
            and call(proc.AddTooltipPostCall, itemData, function(t2)
                if t2 == env.GameTooltip then tooltipFilled(t2) end
            end) then
            tooltipHooked = true
            return true
        end
        local tip = env.GameTooltip
        if type(tip) == "table" and type(tip.HookScript) == "function" then
            local okHas, has = call(tip.HasScript, tip, "OnTooltipSetItem")
            local filled = false
            if okHas and has == true and call(tip.HookScript, tip, "OnTooltipSetItem", function(t2)
                if filled then return end
                filled = true
                tooltipFilled(t2)
            end) then
                call(tip.HookScript, tip, "OnTooltipCleared", function() filled = false end)
                tooltipHooked = true
                return true
            end
        end
        return false
    end
    function c.onItemTooltip(fn)
        if type(fn) ~= "function" or not hookTooltip() then return nil end
        tooltipListeners[#tooltipListeners + 1] = fn
        return function()
            for i = #tooltipListeners, 1, -1 do
                if tooltipListeners[i] == fn then table.remove(tooltipListeners, i) end
            end
        end
    end
    -- -------------------------------------------------------------- end F3

    -- ---------------------------------------------------------------- F4
    -- Merchant and roll marks (FEATURE-PLAN F4, owner Plexy): the loot-roll
    -- hook. The merchant reads F4 uses (merchantItems, watchMerchant) are
    -- above and unchanged. First guesses, not seen in game on 16001:
    -- START_LOOT_ROLL (rollID) and CANCEL_LOOT_ROLL (rollID),
    -- GetLootRollItemLink(rollID), and the roll frames GroupLootFrame1..4
    -- with their rollID field.
    -- Checked (LEDGER 129) against Flow, which used them on this client:
    -- START_LOOT_ROLL (rollID), GetLootRollItemLink(rollID), GroupLootFrame1..4
    -- and GroupLootContainer children with rollID (Modules/Gear/RollHint.lua).
    -- Still a first guess: CANCEL_LOOT_ROLL, and a child frame of ours on the
    -- roll frame staying free of taint.
    --
    --   client.onLootRoll(fn) -> cancel;  fn(rollID, link, show)
    --   show(text, r, g, b[, opts])
    -- show puts one short text above that roll's frame, on a frame of ours
    -- made as a child of it, so it hides with it; one per roll frame, reused.
    -- Nothing of the game's frame is called or written, and nothing rolls.
    -- When the roll frame cannot be found, show prints the link and the text
    -- once instead; not when told opts.quiet == true (RH-1: the listener
    -- says the roll in chat itself, or has said this one already).
    -- No link, or a secret one: fn is not told.
    local rollListeners, rollWatched = {}, false
    local rollMarks = {}      -- roll frame -> { holder, text, rollID }
    -- Source: Flow's Modules/Gear/RollHint.lua framesFor, used on this
    -- client: GroupLootFrame1..NUM_GROUP_LOOT_FRAMES (4 when not given), and
    -- on newer clients the children of GroupLootContainer, each with rollID.
    local function rollMatches(f, rollID)
        if type(f) ~= "table" then return false end
        local ok, id = pcall(function() return f.rollID end)
        return ok and id ~= nil and not hidden(id) and id == rollID
    end
    local function rollFrame(rollID)
        local count = env.NUM_GROUP_LOOT_FRAMES
        if type(count) ~= "number" or count < 1 or count > 20 then count = 4 end
        for i = 1, count do
            local f = env["GroupLootFrame" .. i]
            if rollMatches(f, rollID) then return f end
        end
        local box = env.GroupLootContainer
        if type(box) == "table" then
            local ok, kids = pcall(function() return { box:GetChildren() } end)
            if ok then
                for _, f in ipairs(kids) do
                    if rollMatches(f, rollID) then return f end
                end
            end
        end
        return nil
    end
    local function rollMark(frame)
        local m = rollMarks[frame]
        if m then return m end
        local ok, holder = call(env.CreateFrame, "Frame", nil, frame)
        if not ok or type(holder) ~= "table" then return nil end
        local okText, fs = call(holder.CreateFontString, holder, nil, "OVERLAY", "GameFontNormalSmall")
        if not okText or type(fs) ~= "table" then return nil end
        call(holder.SetSize, holder, 1, 1)
        call(holder.SetPoint, holder, "BOTTOM", frame, "TOP", 0, 2)
        call(fs.SetPoint, fs, "BOTTOM", holder, "BOTTOM", 0, 0)
        m = { holder = holder, text = fs }
        rollMarks[frame] = m
        return m
    end
    local function rollStarted(rollID)
        if type(rollID) ~= "number" or hidden(rollID) then return end
        local link = text(call(env.GetLootRollItemLink, rollID))
        if not link then return end
        local printed = false
        local function show(s, r, g, b, opts)
            if type(s) ~= "string" or s == "" then return end
            local frame = rollFrame(rollID)
            local m = frame and rollMark(frame) or nil
            if not m then
                local quiet = type(opts) == "table" and opts.quiet == true
                if not printed and not quiet then
                    printed = true
                    c.print((ns.id and ns.id.title or "") .. ": " .. link .. " " .. s)
                end
                return
            end
            m.rollID = rollID
            call(m.text.SetText, m.text, s)
            if type(r) == "number" then call(m.text.SetTextColor, m.text, r, g, b) end
            call(m.holder.Show, m.holder)
        end
        for _, fn in ipairs({ unpack(rollListeners) }) do pcall(fn, rollID, link, show) end
    end
    local function rollCancelled(rollID)
        for _, m in pairs(rollMarks) do
            if m.rollID == rollID then
                m.rollID = nil
                call(m.holder.Hide, m.holder)
            end
        end
    end
    function c.onLootRoll(fn)
        if type(fn) ~= "function" then return nil end
        if not rollWatched then
            rollWatched = true
            events.add("START_LOOT_ROLL", rollStarted)
            events.add("CANCEL_LOOT_ROLL", rollCancelled)
        end
        rollListeners[#rollListeners + 1] = fn
        return function()
            for i = #rollListeners, 1, -1 do
                if rollListeners[i] == fn then table.remove(rollListeners, i) end
            end
        end
    end
    -- -------------------------------------------------------------- end F4

    function c.gear(link)
        local out = { worn = {} }
        if type(link) == "string" and link ~= "" then
            out.kind, out.stats = itemKind(link), itemStats(link)
            out.classID, out.subclassID = itemType(link)
            -- What needs the item loaded is left out until it is: an item
            -- not loaded must not read as "the game marks nothing".
            local loaded, minLevel = itemLoaded(link)
            if loaded then
                out.minLevel = minLevel
                out.unmet, out.speed = itemTooltip(link)
            end
        end
        for i = 1, #GEAR_SLOTS do
            local slot = GEAR_SLOTS[i]
            local ok, id = call(env.GetInventoryItemID, "player", slot)
            if ok then
                if id == nil then
                    out.worn[slot] = false
                elseif not hidden(id) and type(id) == "number" then
                    local worn = text(call(env.GetInventoryItemLink, "player", slot))
                    if worn then out.worn[slot] = { kind = itemKind(worn), stats = itemStats(worn) } end
                end
            end
        end
        out.dualWield = yesNo(call(env.CanDualWield))
        return out
    end

    -- One spell's cooldown as the client gives it: read?, start, length,
    -- the client's own "this is the global cooldown" mark (true, false, or
    -- nil where it gives none), and waiting: true when the client marks
    -- the cooldown as not started yet (it starts when something else ends,
    -- as Prowl's does), nil otherwise. First guesses, not seen in game on
    -- 16001: C_Spell.GetSpellCooldown(id) answering a table (startTime,
    -- duration, isOnGCD, isEnabled) where the client has it, else
    -- GetSpellCooldown(id) answering start, duration, enabled (1 or 0, or
    -- true or false).
    local function cooldownTimes(id)
        local group = env.C_Spell
        local start, length, mark, enabled
        if type(group) == "table" and type(group.GetSpellCooldown) == "function" then
            local ok, info = call(group.GetSpellCooldown, id)
            if not ok or info == nil or hidden(info) or type(info) ~= "table" then return false end
            start, length, mark, enabled = info.startTime, info.duration, info.isOnGCD, info.isEnabled
            if mark ~= nil and (hidden(mark) or type(mark) ~= "boolean") then mark = nil end
        else
            local ok, s, d, e = call(env.GetSpellCooldown, id)
            if not ok then return false end
            start, length, enabled = s, d, e
        end
        local waiting = nil
        if enabled ~= nil and not hidden(enabled) and (enabled == false or enabled == 0) then waiting = true end
        if start == nil or length == nil or hidden(start) or hidden(length) then return false end
        if type(start) ~= "number" or type(length) ~= "number" then return false end
        return true, start, length, mark, waiting
    end

    -- The spell the client keeps the global cooldown on (61304), a first
    -- guess: not seen in game on 16001.
    local GLOBAL_COOLDOWN = 61304

    -- Is one of your spells on cooldown, by spell id: true (on its own
    -- cooldown), false (ready, or only the global cooldown is running),
    -- nil when not known: no such spell, no call, an odd or secret answer.
    -- Where the client does not mark the global cooldown itself, a running
    -- cooldown is compared with the global cooldown's start and length; if
    -- that cannot be read either, the answer is nil, never "ready". A
    -- cooldown the client marks as waiting to start is nil too (CR2): its
    -- start reads 0, and the spell is not ready.
    -- This only reads. Nothing here casts.
    function c.spellCooldown(id)
        if type(id) ~= "number" then return nil end
        local ok, start, length, mark, waiting = cooldownTimes(id)
        if not ok or waiting then return nil end
        if start <= 0 or length <= 0 then return false end
        if mark ~= nil then return not mark end
        local okGlobal, gStart, gLength = cooldownTimes(GLOBAL_COOLDOWN)
        if not okGlobal then return nil end
        if gLength > 0 and gStart == start and gLength == length then return false end
        return true
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

    -- The texture of a spell by id (a file id or a path), or nil. Only the
    -- client is asked: C_Spell.GetSpellTexture, then the older
    -- GetSpellTexture. First guess, not seen in game; no texture comes from
    -- a table in this addon.
    -- P-GATHER. Is this minimap tracking (Find Minerals, Find Herbs) on?
    -- true / false; nil when it cant be told. C_Minimap's tracking list by
    -- name, else the one tracking texture against the spell's own. First
    -- guess, as Flow read it (Modules/Rotation/Actions.lua); not seen in game.
    function c.tracking(spell)
        if type(spell) ~= "string" or spell == "" then return nil end
        local M = env.C_Minimap
        if type(M) == "table" then
            local okN, n = call(M.GetNumTrackingTypes)
            if okN and type(n) == "number" and not hidden(n) then
                for i = 1, n do
                    local ok, a, _, active = call(M.GetTrackingInfo, i)
                    if ok then
                        local name, on = a, active
                        if type(a) == "table" then name, on = a.name, a.active end
                        if not hidden(name) and name == spell and not hidden(on) then return on and true or false end
                    end
                end
            end
        end
        local okT, cur = call(env.GetTrackingTexture)
        if okT and not hidden(cur) then
            if cur == nil then return false end
            local tex = c.spellTexture(c.spellId(spell))
            if tex ~= nil then return cur == tex end
        end
        return nil
    end

    -- GT-1. Is any minimap tracking you chose on (Flow's X.AnyTracked)?
    -- true / false; nil when it cant be told. First guess; not seen in game.
    -- GK-2: the town kinds (the client's type or category "townsfolk" or
    -- "other": Flight Master, Repair, Mailbox) are no spell you cast and are
    -- left out, as Flow's Compat.lua TrackingEntry. A kind not named counts
    -- as yours. GK-3: one of yours whose active is not given or hidden makes
    -- the answer nil (not known), never false, unless another is on.
    local TOWN_TRACKING = { townsfolk = true, other = true }
    function c.anyTracking()
        local M = env.C_Minimap
        if type(M) == "table" then
            local okN, n = call(M.GetNumTrackingTypes)
            if okN and type(n) == "number" and not hidden(n) then
                local unknown = false
                for i = 1, n do
                    local ok, a, _, active, category = call(M.GetTrackingInfo, i)
                    if ok and a ~= nil then
                        local on, kind = active, category
                        if type(a) == "table" then on, kind = a.active, a.type end
                        if kind ~= nil and hidden(kind) then kind = nil end
                        if not (type(kind) == "string" and TOWN_TRACKING[kind]) then
                            if on == nil or hidden(on) then
                                unknown = true
                            elseif on then
                                return true
                            end
                        end
                    end
                end
                if unknown then return nil end
                return false
            end
        end
        local okT, cur = call(env.GetTrackingTexture)
        if okT and not hidden(cur) then return cur ~= nil end
        return nil
    end

    -- P-GATHER. The professions you have: { [name] = true }, empty when read
    -- and none, nil when the client gives no read. GetProfessions with
    -- GetProfessionInfo, else the skill lines (GetNumSkillLines,
    -- GetSkillLineInfo, headers left out). First guess; not seen in game.
    function c.professions()
        local out, read = {}, false
        local okP, a, b, c3, d, e = call(env.GetProfessions)
        if okP then
            read = true
            for _, index in ipairs({ a, b, c3, d, e }) do
                if type(index) == "number" and not hidden(index) then
                    local ok, name = call(env.GetProfessionInfo, index)
                    if ok and type(name) == "string" and not hidden(name) and name ~= "" then out[name] = true end
                end
            end
        end
        if next(out) == nil then
            local okN, n = call(env.GetNumSkillLines)
            if okN and type(n) == "number" and not hidden(n) then
                read = true
                for i = 1, n do
                    local ok, name, header = call(env.GetSkillLineInfo, i)
                    if ok and not header and type(name) == "string" and not hidden(name) and name ~= "" then
                        out[name] = true
                    end
                end
            end
        end
        return read and out or nil
    end

    function c.spellTexture(id)
        if type(id) ~= "number" then return nil end
        local group = env.C_Spell
        local reads = { type(group) == "table" and group.GetSpellTexture or nil, env.GetSpellTexture }
        for i = 1, 2 do
            local ok, tex = call(reads[i], id)
            if ok and not hidden(tex) then
                if type(tex) == "number" and tex > 0 then return tex end
                if type(tex) == "string" and tex ~= "" then return tex end
            end
        end
        return nil
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
    -- known asks C_SpellBook.IsSpellKnown (the name on warcraft.wiki.gg,
    -- Patch 1.60.1/API changes), then the bare IsPlayerSpell, which is not
    -- listed for this client. Neither has been seen in game.
    function c.spell(id)
        if type(id) ~= "number" then return nil end
        local group = type(env.C_Spell) == "table" and env.C_Spell or {}
        local book = type(env.C_SpellBook) == "table" and env.C_SpellBook or {}
        local okKnown, known = call(book.IsSpellKnown, id)
        if not okKnown then okKnown, known = call(env.IsPlayerSpell, id) end
        local row = { known = flag(okKnown, known) }
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
    -- Name and argument checked on warcraft.wiki.gg (API UnitIsDeadOrGhost).
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
    -- Name checked on warcraft.wiki.gg (API
    -- C_DeathInfo.GetCorpseMapPosition).
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
    -- Both names checked on warcraft.wiki.gg (API C_Map.HasUserWaypoint,
    -- API C_Map.GetUserWaypoint).
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
    -- Name and arguments checked on warcraft.wiki.gg (API
    -- C_Map.GetWorldPosFromMapPos). Which of the two numbers runs which
    -- way is not stated there: needs game test.
    function c.mapSize(map)
        if type(map) ~= "number" then return nil end
        local x0, y0 = corner(map, 0, 0)
        local x1, y1 = corner(map, 1, 1)
        if not x0 or not x1 then return nil end
        local w, h = math.abs(y0 - y1), math.abs(x0 - x1)
        if not (w > 0 and h > 0) or w == math.huge or h == math.huge then return nil end
        return { w = w, h = h }
    end

    -- The continent number of a map, or nil: the first answer of
    -- C_Map.GetWorldPosFromMapPos for the middle of the map, the same
    -- number c.zone() gives as cont (lead section 184 G1). nil when the
    -- client will not say; never guessed. Needs game test: that the middle
    -- of a map gives the number the player's own spot on it gives.
    function c.mapCont(map)
        if type(map) ~= "number" then return nil end
        local okVec, vec = call(env.CreateVector2D, 0.5, 0.5)
        if not okVec or vec == nil then return nil end
        local ok, id = mapCall("GetWorldPosFromMapPos", map, vec)
        if not ok or hidden(id) or type(id) ~= "number" or id ~= id then return nil end
        return id
    end

    -- A map's name as the game shows it ("Westfall"), or nil (R7, the
    -- leaving-zone chat line). C_Map.GetMapInfo(map).name: first guess on
    -- 16001, named on warcraft.wiki.gg, not seen in game.
    function c.mapName(map)
        if type(map) ~= "number" then return nil end
        local ok, info = mapCall("GetMapInfo", map)
        if not ok or type(info) ~= "table" or hidden(info.name) then return nil end
        if type(info.name) ~= "string" or info.name == "" then return nil end
        return info.name
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
    local madeHere = {}
    function c.saved(name)
        local t = env[name]
        if type(t) ~= "table" then
            t = {}
            env[name] = t
            madeHere[name] = t
        end
        return t
    end

    -- True when the table of that name is an empty one c.saved made itself
    -- (asked before the client loaded saved data, or nothing was saved):
    -- it is not proof of an earlier login. The client replaces the global
    -- when it loads a saved one, and then this is false.
    function c.savedMadeHere(name)
        return madeHere[name] ~= nil and env[name] == madeHere[name]
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
    -- Docs (warcraft.wiki.gg, API C_AddOns.GetAddOnMetadata): value =
    -- C_AddOns.GetAddOnMetadata(name, variable), text or nil; matches.
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
    --   spec = { name = global frame name or nil, width = n, height = n,
    --            closable = true or nil, onClose = fn or nil }
    -- The handle:
    --   h.setLines({ "text", ... })   the lines shown, top to bottom
    --   h.place({ anchor, relative anchor, x, y })   against the screen
    --   h.show(on)
    --   h.onMoved(fn, failed)   fn(point) after the player drags it; point is plain
    --                   data in the shape place() takes. Not called when the
    --                   client will not say where the panel now stands.
    -- A new panel is hidden and has no place until told.
    --
    -- spec.closable = true: the player can close the panel. Two routes, each
    -- made when the client allows it: a close button in the top right
    -- corner, and Escape (the name of the frame goes in the game list
    -- UISpecialFrames once, as for the arrow menu; only with a name that was
    -- not already a global, and only when the client has the list).
    --   h.onClose(fn, failed)   fn() once each time the player closes the
    --                   panel by the button or by Escape. Not for
    --                   h.show(false), and not when the whole interface is
    --                   hidden. spec.onClose is the fn until this is called.
    --                   failed(err) as for onMoved.
    -- h.onClose is there only when at least one route was made: a caller
    -- that must not show what cannot be closed asks type(h.onClose).
    -- A first guess throughout: not seen in game.
    -- Docs (warcraft.wiki.gg), names and arguments match: API Frame
    -- SetMovable, RegisterForDrag, StartMoving, StopMovingOrSizing,
    -- SetUserPlaced, SetClampedToScreen, SetFrameStrata; GetPoint answers
    -- anchor, relative frame, relative anchor, x, y; SetSize(width, height);
    -- UIHANDLER OnDragStart, OnDragStop; UIHANDLER OnHide, which that page
    -- says also runs when a frame it stands on is hidden. UISpecialFrames
    -- and the UIPanelCloseButton template have no page: needs a game test.
    -- The panel, its frame, and whether it is open (shown by the add-on and
    -- not since hidden or closed): c.panel and c.rowPanel share it.
    local function panelFrame(spec)
        spec = type(spec) == "table" and spec or {}
        local parent = env.UIParent
        -- Asked before the frame is made: making it takes the name.
        local nameFree = type(spec.name) == "string" and spec.name ~= "" and env[spec.name] == nil
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
        -- open: shown by show(true) and not yet hidden by show(false) or
        -- closed by the player. Only a hide while open is the player's.
        local open = false
        function h.show(on)
            open = on and true or false
            method(f, on and "Show" or "Hide")
        end
        -- failed(err), when given, is called with the error of an fn that
        -- failed; without it the error is dropped.
        function h.onMoved(fn, failed)
            moved = fn
            movedFailed = type(failed) == "function" and failed or nil
        end

        if spec.closable == true then
            local closed = type(spec.onClose) == "function" and spec.onClose or nil
            local closedFailed
            local function playerClosed()
                if not open then return end
                open = false
                if closed then
                    local okC, err = pcall(closed)
                    if not okC and closedFailed then pcall(closedFailed, err) end
                end
            end

            -- The button. The game template draws the usual cross; a client
            -- without it gets a plain button with an x.
            local okB, button = call(env.CreateFrame, "Button", nil, f, "UIPanelCloseButton")
            if not okB or button == nil then
                okB, button = call(env.CreateFrame, "Button", nil, f)
                if okB and button ~= nil then
                    method(button, "SetNormalFontObject", "GameFontNormalSmall")
                    method(button, "SetText", "x")
                end
            end
            if not okB then button = nil end
            if button ~= nil then
                if not method(button, "SetSize", 20, 20) then
                    method(button, "SetWidth", 20)
                    method(button, "SetHeight", 20)
                end
                method(button, "SetPoint", "TOPRIGHT", f, "TOPRIGHT", 0, 0)
                -- The text keeps clear of the button.
                if text ~= nil then method(text, "SetPoint", "BOTTOMRIGHT", f, "BOTTOMRIGHT", -22, 6) end
                method(button, "SetScript", "OnClick", function()
                    if not open then return end
                    method(f, "Hide")
                    -- OnHide has told it already on a client that runs it.
                    playerClosed()
                end)
            end

            -- Escape.
            local special = env.UISpecialFrames
            local escape = false
            if nameFree and type(special) == "table" then
                local there = false
                for i = 1, #special do
                    if special[i] == spec.name then there = true end
                end
                if not there then special[#special + 1] = spec.name end
                escape = true
            end

            if button ~= nil or escape then
                -- The game also runs OnHide when something the panel stands
                -- on is hidden (the whole interface, Alt-Z): the panel
                -- itself is then still shown, and that is not a close.
                method(f, "SetScript", "OnHide", function()
                    local okS, shown = method(f, "IsShown")
                    if okS and shown then return end
                    playerClosed()
                end)
                function h.onClose(fn, failed)
                    closed = type(fn) == "function" and fn or nil
                    closedFailed = type(failed) == "function" and failed or nil
                end
            end
        end
        return h, f, function() return open end
    end
    function c.panel(spec)
        local h = panelFrame(spec)
        return h
    end

    -- The quest log of the player (F1), or nil when the client will not
    -- say:
    --   { { id =, title =, complete =, failed =,
    --       objectives = { { text =, done = } } } }
    -- Headers are left out. complete and failed are true, false, or nil
    -- when the client did not say; an objective has done = true or false
    -- and text or nil. Read only: nothing is accepted, handed in or
    -- abandoned. First guesses, none seen in game on 16001:
    -- C_QuestLog.GetNumQuestLogEntries, GetInfo(index) answering a table
    -- (title, questID, isHeader), IsComplete(id), IsFailed(id) and
    -- GetQuestObjectives(id) answering { { text, finished } }; else the
    -- older GetNumQuestLogEntries, GetQuestLogTitle(index) (title, level,
    -- group, header, collapsed, complete 1 / -1, frequency, id) and
    -- GetQuestLogLeaderBoard(objective, index) (text, kind, finished).
    -- Docs (warcraft.wiki.gg), names, arguments and fields match: API
    -- C_QuestLog.GetNumQuestLogEntries, GetInfo, IsComplete, IsFailed and
    -- GetQuestObjectives, all listed for build 1.60.1. The older
    -- GetNumQuestLogEntries and GetQuestLogTitle (complete 6th as 1 / -1,
    -- id 8th) match too but are not listed for 1.60.1, so the first path
    -- is the likely one here. API GetQuestLogLeaderBoard matches. The page
    -- for GetNumQuestLeaderBoards names its argument a quest id where this
    -- passes the place in the log: needs a game test.
    local function questFlag(fn, id)
        local ok, v = call(fn, id)
        if not ok or hidden(v) then return nil end
        if v == true then return true end
        if v == false then return false end
        return nil
    end
    -- No watch list is read past this many rows, whatever the client says.
    local QUEST_WATCH_MAX = 100
    function c.questLog()
        local rows = {}
        local group = env.C_QuestLog
        if type(group) == "table" and type(group.GetNumQuestLogEntries) == "function"
            and type(group.GetInfo) == "function" then
            local okN, n = call(group.GetNumQuestLogEntries)
            if not okN or hidden(n) or type(n) ~= "number" then return nil end
            for i = 1, n do
                local okI, info = call(group.GetInfo, i)
                if okI and type(info) == "table" and not hidden(info.questID) and not hidden(info.title)
                    and info.isHeader ~= true and type(info.questID) == "number" and info.questID > 0
                    and type(info.title) == "string" then
                    local objectives = {}
                    local okO, list = call(group.GetQuestObjectives, info.questID)
                    if okO and type(list) == "table" then
                        for j = 1, #list do
                            local o = list[j]
                            local text = type(o) == "table" and not hidden(o.text)
                                and type(o.text) == "string" and o.text or nil
                            objectives[j] = { text = text, done = type(o) == "table" and o.finished == true }
                        end
                    end
                    rows[#rows + 1] = {
                        id = info.questID, title = info.title,
                        complete = questFlag(group.IsComplete, info.questID),
                        failed = questFlag(group.IsFailed, info.questID),
                        objectives = objectives,
                    }
                end
            end
            return rows
        end
        local okN, n = call(env.GetNumQuestLogEntries)
        if not okN or hidden(n) or type(n) ~= "number" then return nil end
        for i = 1, n do
            local okT, title, _, _, header, _, state, _, id = call(env.GetQuestLogTitle, i)
            if okT and not header and type(title) == "string" and type(id) == "number" and id > 0 then
                local objectives = {}
                local okC, count = call(env.GetNumQuestLeaderBoards, i)
                if okC and type(count) == "number" then
                    for j = 1, count do
                        local okO, text, _, finished = call(env.GetQuestLogLeaderBoard, j, i)
                        objectives[j] = {
                            text = okO and type(text) == "string" and text or nil,
                            done = okO and (finished == true or finished == 1) or false,
                        }
                    end
                end
                rows[#rows + 1] = {
                    id = id, title = title,
                    complete = state == 1 or state == true,
                    failed = state == -1,
                    objectives = objectives,
                }
            end
        end
        return rows
    end

    -- Which of the quests the player follows (section 131), or nil when this
    -- client gives no such read at all:
    --   { quest = id or nil, watched = { id, ... } or nil }
    -- quest: the one quest the player has picked out. Asked, in this order:
    -- C_SuperTrack.GetSuperTrackedQuestID(), the bare
    -- GetSuperTrackedQuestID(), then the quest the tracker of Questie is
    -- set on (Questie.db.char.TrackerFocus). A number above 0 is a quest;
    -- anything else, or an answer the client hides, is "none picked".
    -- watched: the quests on the watch list of the player, in its order.
    -- Asked of C_QuestLog.GetNumQuestWatches() and
    -- C_QuestLog.GetQuestIDForQuestWatchIndex(i); else the bare
    -- GetNumQuestWatches() with GetQuestIndexForWatch(i), the id then being
    -- the 8th answer of GetQuestLogTitle(index) as in questLog above. nil
    -- when neither pair is there; an empty list when nothing is watched.
    -- Read only: nothing here sets what is tracked or watched.
    -- Sources: warcraft.wiki.gg, the pages API
    -- C_SuperTrack.GetSuperTrackedQuestID, API C_QuestLog.GetNumQuestWatches
    -- and API C_QuestLog.GetQuestIDForQuestWatchIndex: each lists this
    -- client from 1.60.1. The bare watch names have no row for this client
    -- there and are asked second. Not settled: none of these names is in
    -- the list on that site of calls added in 1.60.1, so the two pages
    -- disagree. The Questie field is from the public repository of Questie,
    -- Modules/Tracker/TrackerUtils.lua (FocusQuest sets it to the quest id,
    -- UnFocus clears it); a text answer starting with the id is read too,
    -- as a guess. Every call here needs game test.
    -- Each focus read on its own, for questFocus and for the arrow's own
    -- report (arrow why): superTrack and questie are nil for no such read or
    -- a failed one, false for a read that named no quest, else the quest
    -- id; watched is the watch list, or nil for no such read.
    local function focusReads()
        local reads = {}
        local function questId(v)
            if hidden(v) then return nil end
            if type(v) == "string" then v = tonumber(v:match("^(%d+)")) end
            if type(v) == "number" and v > 0 then return v end
            return nil
        end
        local track = type(env.C_SuperTrack) == "table" and env.C_SuperTrack or {}
        local okQ, q = call(track.GetSuperTrackedQuestID)
        if not okQ then okQ, q = call(env.GetSuperTrackedQuestID) end
        if okQ then reads.superTrack = questId(q) or false end
        local okF, f = call(function() return env.Questie.db.char.TrackerFocus end)
        if okF then reads.questie = questId(f) or false end
        local group = type(env.C_QuestLog) == "table" and env.C_QuestLog or {}
        local okN, n = call(group.GetNumQuestWatches)
        if okN and not hidden(n) and type(n) == "number" then
            local list = {}
            for i = 1, math.min(n, QUEST_WATCH_MAX) do
                local okI, id = call(group.GetQuestIDForQuestWatchIndex, i)
                if okI then list[#list + 1] = questId(id) end
            end
            reads.watched = list
        else
            okN, n = call(env.GetNumQuestWatches)
            if okN and not hidden(n) and type(n) == "number" then
                local list = {}
                for i = 1, math.min(n, QUEST_WATCH_MAX) do
                    local okI, index = call(env.GetQuestIndexForWatch, i)
                    if okI and not hidden(index) and type(index) == "number" then
                        local okT, _, _, _, _, _, _, _, id = call(env.GetQuestLogTitle, index)
                        if okT then list[#list + 1] = questId(id) end
                    end
                end
                reads.watched = list
            end
        end
        return reads
    end
    function c.questFocus()
        local r = focusReads()
        if r.superTrack == nil and r.questie == nil and r.watched == nil then return nil end
        return { quest = r.superTrack or r.questie or nil, watched = r.watched }
    end
    -- The same reads, each on its own (see focusReads). Read only.
    function c.questFocusReads() return focusReads() end

    -- A module of the installed Questie by name, or nil: Questie is not
    -- there, or its loader gave none. Asked of Questie at runtime through
    -- its own loader (QuestieLoader:ImportModule); nothing of Questie is
    -- copied into this addon or changed. A first guess: not seen in game.
    -- Source: Questie's public repository, Modules/Libs/QuestieLoader.lua:
    -- a global QuestieLoader with the method ImportModule(name); matches.
    -- Whether Questie loads on this client needs a game test.
    function c.questieModule(name)
        if type(name) ~= "string" or name == "" then return nil end
        local loader = env.QuestieLoader
        if type(loader) ~= "table" then return nil end
        local ok, mod = method(loader, "ImportModule", name)
        if not ok or type(mod) ~= "table" then return nil end
        return mod
    end

    -- The minimap as the client says it is (F1), or nil without one:
    --   { size =, radius =, rotates =, square = }
    -- size: how wide the frame is. radius: yards from the middle to the
    -- edge at the zoom now, only when the client itself says it
    -- (C_Minimap.GetViewRadius); no table of yards per zoom step is in this
    -- addon, so on a client without that call it is nil. rotates: true or
    -- false from the rotateMinimap setting, nil when not said. square: true
    -- when GetMinimapShape says "SQUARE", else nil. First guesses, none
    -- seen in game on 16001.
    -- Docs (warcraft.wiki.gg): API C_Minimap.GetViewRadius answers yards, no
    -- arguments (added in 9.0.1; not listed for the 1.x clients, so it may
    -- be absent here). No page for the rotateMinimap setting or for
    -- GetMinimapShape, which the client's own docs do not list: other addons
    -- that square the minimap define it. Needs a game test.
    function c.minimap()
        local frame = env.Minimap
        if frame == nil then return nil end
        local out = {}
        local okW, w = method(frame, "GetWidth")
        if okW and not hidden(w) and type(w) == "number" and w == w and w > 0 then out.size = w end
        local group = env.C_Minimap
        if type(group) == "table" then
            local okR, r = call(group.GetViewRadius)
            if okR and not hidden(r) and type(r) == "number" and r == r and r > 0 then out.radius = r end
        end
        local okC, v = call(env.GetCVar, "rotateMinimap")
        if not okC and type(env.C_CVar) == "table" then okC, v = call(env.C_CVar.GetCVar, "rotateMinimap") end
        if okC and not hidden(v) then
            if v == "1" or v == 1 or v == true then
                out.rotates = true
            elseif v == "0" or v == 0 or v == false then
                out.rotates = false
            end
        end
        local okS, shape = call(env.GetMinimapShape)
        if okS and shape == "SQUARE" then out.square = true end
        return out
    end
    -- G59 (lead section 226): a game setting read by name, as the game
    -- gives it (text), or nil when no call answers. A read only: nothing is
    -- written here. Docs (warcraft.wiki.gg): C_CVar.GetCVar(name), and the
    -- older GetCVar(name), answer the value as text. A number is turned to
    -- its text. Needs game test on 16001.
    function c.gameSetting(name)
        if type(name) ~= "string" or name == "" then return nil end
        local function text(ok, v)
            if not ok or hidden(v) then return nil end
            if type(v) == "string" then return v end
            if type(v) == "number" and v == v then return tostring(v) end
            return nil
        end
        local v
        if type(env.C_CVar) == "table" then v = text(call(env.C_CVar.GetCVar, name)) end
        if v == nil then v = text(call(env.GetCVar, name)) end
        return v
    end

    -- G59: whether the game writes the combat log to its file. LoggingCombat
    -- called with no value only reads (docs: it answers the state). Older
    -- clients answer 1 or nil, so nil from a call that ran is off. nil when
    -- the call is missing or raised. Needs game test on 16001.
    function c.combatLogFile()
        if type(env.LoggingCombat) ~= "function" then return nil end
        local ok, v = call(env.LoggingCombat)
        if not ok or hidden(v) then return nil end
        if v == nil or v == false or v == 0 then return false end
        if v == true or v == 1 then return true end
        return nil
    end

    -- G59 ACTS: the two writes behind the game options, called only by
    -- UI/GameOptions.lua on the player own choice (the settings page or the
    -- setting word). Nothing else may call them. Only the two settings the
    -- options use can be written; any other name is refused before the game
    -- is asked. Docs (warcraft.wiki.gg): C_CVar.SetCVar(name, value) answers
    -- whether it took; the older SetCVar(name, value) answers nothing.
    -- LoggingCombat(on) turns the combat log file on or off. Needs game test
    -- on 16001: each write, and a write in a fight.
    local GAME_SETTINGS = { cameraDistanceMaxZoomFactor = true, showTimestamps = true }
    function c.setGameSetting(name, v)
        if type(name) ~= "string" or not GAME_SETTINGS[name] then return nil, "notAllowed" end
        if type(v) ~= "string" then return nil, "bad" end
        if c.inCombat() ~= false then return nil, "combat" end   -- a fight, or not known (section 266 GO-1)
        local fn = type(env.C_CVar) == "table" and env.C_CVar.SetCVar or nil
        if type(fn) ~= "function" then fn = env.SetCVar end
        if type(fn) ~= "function" then return nil, "noCall" end
        local ok, done = call(fn, name, v)
        if not ok then return nil, "raised" end
        if done == false then return nil, "bad" end
        return true
    end

    function c.setCombatLogFile(on)
        if type(on) ~= "boolean" then return nil, "bad" end
        if c.inCombat() ~= false then return nil, "combat" end   -- a fight, or not known (section 266 GO-1)
        if type(env.LoggingCombat) ~= "function" then return nil, "noCall" end
        local ok = call(env.LoggingCombat, on)
        if not ok then return nil, "raised" end
        return true
    end


    -- One small mark on the minimap (F1), or nil when the client cannot
    -- make it. Hidden when made; it takes no mouse and holds no action.
    --   spec = { name = global frame name or nil, size = n }
    --   h.place(x, y, edge)   shows it, its middle x to the right and y up
    --                   from the middle of the minimap; edge true (the place
    --                   is off the minimap) draws it fainter
    --   h.hide()
    -- A first guess: not seen in game.
    -- Docs (warcraft.wiki.gg, API TextureBase SetColorTexture): (r, g, b [, a]),
    -- added in 7.0.3 and listed for the 1.x clients; matches. How the pin
    -- looks on the minimap needs a game test.
    function c.minimapPin(spec)
        spec = type(spec) == "table" and spec or {}
        local map = env.Minimap
        if map == nil then return nil end
        local ok, f = call(env.CreateFrame, "Frame", spec.name, map)
        if not ok or f == nil then return nil end
        local size = tonumber(spec.size) or 12
        method(f, "Hide")
        if not method(f, "SetSize", size, size) then
            method(f, "SetWidth", size)
            method(f, "SetHeight", size)
        end
        method(f, "EnableMouse", false)
        local okTex, tex = method(f, "CreateTexture", nil, "OVERLAY")
        if okTex and tex ~= nil then
            method(tex, "SetAllPoints", f)
            if not method(tex, "SetColorTexture", 1, 0.82, 0, 1) then method(tex, "SetTexture", 1, 0.82, 0, 1) end
        end
        local h = {}
        function h.place(x, y, edge)
            if type(x) ~= "number" or type(y) ~= "number" or x ~= x or y ~= y then return end
            method(f, "ClearAllPoints")
            method(f, "SetPoint", "CENTER", map, "CENTER", x, y)
            method(f, "SetAlpha", edge and 0.6 or 1)
            method(f, "Show")
        end
        function h.hide() method(f, "Hide") end
        return h
    end
    -- Bags and vendor helper (FEATURE-PLAN F5, owner Lazy): what an item
    -- is, how worn the gear is, whose loot a chat line is, and what the open
    -- loot window holds. Read only: nothing is sold, bought, repaired,
    -- looted or moved. Every call here is a first guess, not seen in game on
    -- 16001; an answer that cannot be read is left out, never a default.
    -- Docs (warcraft.wiki.gg), names, arguments and positions match: API
    -- C_Item.GetItemInfo (quality 3rd, sell price 11th, class 12th, subclass
    -- 13th), API GetInventoryItemDurability (current, maximum), API
    -- GetNumLootItems, API GetLootSlotLink, API GetLootSlotInfo (quantity
    -- 3rd), API GetLootSourceInfo (guid 1st), API UnitGUID. The texts
    -- LOOT_ITEM_SELF and LOOT_ITEM_SELF_MULTIPLE have no page: needs a game
    -- test.

    -- One item's facts, or nil when the client says nothing about it:
    --   { name =, quality =, sellPrice =, classID =, subclassID =, level =,
    --     minLevel = } (level, minLevel: N8, as Flow ranks healing items)
    -- item: a link or an item ID. GetItemInfo (C_Item.GetItemInfo where the
    -- client has it): name 1st, quality 3rd, sell price 11th, class 12th,
    -- subclass 13th. An item the client has not loaded yet has no name,
    -- quality or price; its class and subclass then come from
    -- GetItemInfoInstant, as in c.gear. classID and subclassID are the
    -- client's own numbers, spelled as in c.gear.
    function c.itemInfo(item)
        if item == nil then return nil end
        local group = env.C_Item
        local fn = env.GetItemInfo
        if type(group) == "table" and type(group.GetItemInfo) == "function" then fn = group.GetItemInfo end
        local ok, name, _, quality, level, minLevel, _, _, _, _, _, price, class, subclass = call(fn, item)
        local out = {}
        out.name = text(ok, name)
        out.quality = whole(ok, quality)
        out.level = whole(ok, level)
        out.minLevel = whole(ok, minLevel)
        out.sellPrice = whole(ok, price)
        out.classID = whole(ok, class)
        out.subclassID = whole(ok, subclass)
        if out.classID == nil then
            local instantClass, instantSubclass = itemType(item)
            out.classID = instantClass
            if out.subclassID == nil then out.subclassID = instantSubclass end
        end
        if next(out) == nil then return nil end
        return out
    end

    -- How worn the gear is, or nil when the client will not say:
    --   { [slot] = { cur = n, max = n } }
    -- One row for each worn slot that has durability; a slot with nothing
    -- in it, or with an item that does not wear, has no row, so a reading
    -- with no rows is "nothing wears", not "not known".
    -- GetInventoryItemDurability(slot) answers current, maximum.
    function c.durability()
        if type(env.GetInventoryItemDurability) ~= "function" then return nil end
        local out = {}
        for i = 1, #GEAR_SLOTS do
            local slot = GEAR_SLOTS[i]
            local ok, cur, max = call(env.GetInventoryItemDurability, slot)
            if not ok then return nil end
            if (cur ~= nil and hidden(cur)) or (max ~= nil and hidden(max)) then return nil end
            cur, max = whole(true, cur), whole(true, max)
            if cur and max and max > 0 then out[slot] = { cur = cur, max = max } end
        end
        return out
    end

    -- The words of a loot line as a pattern. fmt is the client's own text
    -- for the line (in the language of the client), with %s for the item
    -- and %d for the count, or the numbered forms %1$s and %2$d. Answers
    -- the pattern and, for each capture in order, "s" or "d".
    local function lootPattern(fmt)
        if type(fmt) ~= "string" or fmt == "" or hidden(fmt) then return nil end
        local out, kinds, i = {}, {}, 1
        while i <= #fmt do
            local kind = fmt:match("^%%%d%$([sd])", i)
            local len = 4
            if not kind then
                kind = fmt:match("^%%([sd])", i)
                len = 2
            end
            if kind then
                kinds[#kinds + 1] = kind
                out[#out + 1] = kind == "s" and "(.+)" or "(%d+)"
                i = i + len
            else
                local ch = fmt:sub(i, i):gsub("%W", "%%%0")
                out[#out + 1] = ch
                i = i + 1
            end
        end
        return "^" .. table.concat(out) .. "$", kinds
    end

    -- Whose loot a CHAT_MSG_LOOT line is. For the player's own loot line:
    -- the item link and the count (1 when the line names none). For anyone
    -- else's line, a line it cannot read, or a client without the texts:
    -- nil. The texts are the client's own LOOT_ITEM_SELF_MULTIPLE and
    -- LOOT_ITEM_SELF; no English is written here. Lines for an item that
    -- was made, bought or given (LOOT_ITEM_PUSHED_SELF) are not loot and
    -- are not read.
    function c.ownLoot(line)
        if type(line) ~= "string" or line == "" or hidden(line) then return nil end
        local forms = { env.LOOT_ITEM_SELF_MULTIPLE or false, env.LOOT_ITEM_SELF or false }
        for f = 1, 2 do
            local pattern, kinds = lootPattern(forms[f])
            if pattern then
                local caps = { line:match(pattern) }
                if #caps > 0 and #caps == #kinds then
                    local link, count = nil, nil
                    for i = 1, #kinds do
                        if kinds[i] == "s" then link = caps[i] else count = tonumber(caps[i]) end
                    end
                    if type(link) == "string" and link:find("item:%d+") then
                        return link, count or 1
                    end
                end
            end
        end
        return nil
    end

    -- What the open loot window holds, or nil when the client will not say:
    --   { source = { kind = "creature", guid =, id =, name = },
    --     items = { { item = link, count = n } } }
    -- GetNumLootItems, GetLootSlotLink(slot), GetLootSlotInfo(slot) (count
    -- 3rd) and GetLootSourceInfo(slot) (the GUID of what is looted, 1st).
    -- A slot with no link (coins) is left out; a count not read is nil.
    -- source is there only with a GUID; kind is "creature" for a Creature
    -- GUID and its sixth part is the id; name only when the target has that
    -- same GUID. source.how is NOT given: no call here tells a corpse from
    -- a skinning or a pickpocket window (all three carry the GUID of the
    -- creature), and saying "corpse" would be a guess.
    function c.lootWindow()
        local okN, n = call(env.GetNumLootItems)
        n = whole(okN, n)
        if not n then return nil end
        local items, guid = {}, nil
        for slot = 1, n do
            local link = text(call(env.GetLootSlotLink, slot))
            if link then
                local okI, _, _, quantity = call(env.GetLootSlotInfo, slot)
                items[#items + 1] = { item = link, count = whole(okI, quantity) }
            end
            if guid == nil then guid = text(call(env.GetLootSourceInfo, slot)) end
        end
        local source
        if guid then
            source = { guid = guid }
            -- Docs (warcraft.wiki.gg, API UnitGUID): type, 0, server, instance,
            -- zone, id, spawn. That page says build 1.60.1 hides the server
            -- and spawn parts, so only the type and the id are read here;
            -- the other parts may hold anything.
            local kind, id = guid:match("^(%a+)%-[^-]*%-[^-]*%-[^-]*%-[^-]*%-(%d+)%-[^-]*$")
            if kind == "Creature" then
                source.kind = "creature"
                source.id = tonumber(id)
                if text(call(env.UnitGUID, "target")) == guid then
                    source.name = text(call(env.UnitName, "target"))
                end
            end
        end
        return { source = source, items = items }
    end
    -- A box of text the player can select and copy (L6-K, with the focus
    -- rules of L6-N), or nil when the client cannot make one. First guess,
    -- not seen in game.
    --   spec = { name = global frame name or nil, width, height, title }
    --   h.setText(text), h.show(on)
    -- The box never takes the keyboard by itself: auto-focus is off, so it
    -- has focus only after the player clicks in the text. It gives focus
    -- back whenever it is hidden, however that happens, and on Escape,
    -- which also hides it. A client that will not turn auto-focus off gets
    -- no box. It is its own edit box: the chat edit box is not used and no
    -- chat frame is hooked. Its length is not limited. Typing in it changes
    -- nothing: the text is put back. A new box is hidden.
    -- Docs (warcraft.wiki.gg), names and arguments match: API EditBox
    -- SetAutoFocus([autoFocus]), UIHANDLER OnTextChanged (self, userInput),
    -- UIHANDLER OnEscapePressed (self), API TextureBase SetColorTexture.
    -- The page for EditBox SetMaxLetters does not say that 0 is no limit:
    -- needs a game test.
    function c.copyBox(spec)
        spec = type(spec) == "table" and spec or {}
        local parent = env.UIParent
        -- A name is used only when no global has it already.
        local name = type(spec.name) == "string" and spec.name ~= "" and env[spec.name] == nil and spec.name or nil
        local okF, f = call(env.CreateFrame, "Frame", name, parent)
        if not okF or f == nil then return nil end
        local width, height = tonumber(spec.width) or 520, tonumber(spec.height) or 320
        method(f, "Hide")

        -- The template draws the scroll bar and needs a name for it; a
        -- client without it, or a box without a name, gets a plain one.
        local okS, scroll = false, nil
        if name then okS, scroll = call(env.CreateFrame, "ScrollFrame", name .. "Scroll", f, "UIPanelScrollFrameTemplate") end
        if not okS or scroll == nil then okS, scroll = call(env.CreateFrame, "ScrollFrame", nil, f) end
        if not okS then scroll = nil end

        local okE, edit = call(env.CreateFrame, "EditBox", nil, scroll or f)
        if not okE or edit == nil then return nil end
        -- First, before the box can be shown: no focus unless clicked.
        if not method(edit, "SetAutoFocus", false) then return nil end
        method(edit, "ClearFocus")
        method(edit, "SetMultiLine", true)
        method(edit, "SetMaxLetters", 0)
        method(edit, "SetFontObject", "ChatFontNormal")
        method(edit, "SetWidth", width - 44)

        if not method(f, "SetSize", width, height) then
            method(f, "SetWidth", width)
            method(f, "SetHeight", height)
        end
        method(f, "SetPoint", "CENTER", parent, "CENTER", 0, 0)
        method(f, "SetFrameStrata", "DIALOG")
        method(f, "SetClampedToScreen", true)
        method(f, "EnableMouse", true)

        local okBg, bg = method(f, "CreateTexture", nil, "BACKGROUND")
        if okBg and bg ~= nil then
            method(bg, "SetAllPoints", f)
            if not method(bg, "SetColorTexture", 0, 0, 0, 0.85) then method(bg, "SetTexture", 0, 0, 0, 0.85) end
        end

        local okT, title = method(f, "CreateFontString", nil, "OVERLAY", "GameFontNormalSmall")
        if okT and title ~= nil then
            method(title, "SetPoint", "TOPLEFT", f, "TOPLEFT", 8, -8)
            method(title, "SetText", type(spec.title) == "string" and spec.title or "")
        end

        if scroll ~= nil then
            method(scroll, "SetPoint", "TOPLEFT", f, "TOPLEFT", 8, -26)
            method(scroll, "SetPoint", "BOTTOMRIGHT", f, "BOTTOMRIGHT", -30, 8)
            method(scroll, "SetScrollChild", edit)
        else
            method(edit, "SetPoint", "TOPLEFT", f, "TOPLEFT", 8, -26)
            method(edit, "SetPoint", "BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 8)
        end

        local h = {}
        local held, setting = "", false
        local function release() method(edit, "ClearFocus") end
        local function put(text)
            setting = true
            method(edit, "SetText", text)
            setting = false
        end

        -- The handlers close over the frames: they use none of the
        -- arguments the client passes.
        method(f, "SetScript", "OnHide", release)
        method(edit, "SetScript", "OnEscapePressed", function()
            release()
            method(f, "Hide")
        end)
        method(edit, "SetScript", "OnTextChanged", function()
            if setting then return end
            local okG, now = method(edit, "GetText")
            if okG and now ~= held then put(held) end
        end)

        local okB, button = call(env.CreateFrame, "Button", nil, f, "UIPanelCloseButton")
        if okB and button ~= nil then
            method(button, "SetPoint", "TOPRIGHT", f, "TOPRIGHT", 0, 0)
            method(button, "SetScript", "OnClick", function()
                release()
                method(f, "Hide")
            end)
        end

        function h.setText(text)
            held = tostring(text == nil and "" or text)
            put(held)
            -- What the client holds is what a later change is told from.
            local okG, now = method(edit, "GetText")
            if okG and type(now) == "string" then held = now end
            method(edit, "SetCursorPosition", 0)
        end

        function h.show(on)
            if on then
                method(f, "Show")
            else
                -- Not left to OnHide alone: a client may not run it.
                release()
                method(f, "Hide")
            end
        end
        return h
    end

    -- One movable icon, or nil when the client cannot make a frame. First
    -- guess, not seen in game (WOW-ROTATION-ICON).
    --   spec = { name = global frame name or nil, size = n }
    --   h.setTexture(tex) -> true when the client took it. tex is what
    --                   spellTexture gave (a file id or a path); nil clears
    --                   the picture and answers false.
    --   h.place(point), h.show(on), h.onMoved(fn, failed): as the panel's.
    --   h.mark(look) -> true when the client took it. "far" tints the
    --                   picture red (the action bar's out of range colour);
    --                   anything else puts the plain colour back.
    -- It moves only while Ctrl is held, like the arrows; a client that will
    -- not say whether Ctrl is held starts no drag. It takes no click and
    -- holds no secure action. A new icon is hidden and has no place.
    function c.icon(spec)
        spec = type(spec) == "table" and spec or {}
        local parent = env.UIParent
        local ok, f = call(env.CreateFrame, "Frame", spec.name, parent)
        if not ok or f == nil then return nil end
        local h, moved, movedFailed, dragging = {}, nil, nil, false
        local size = tonumber(spec.size) or 48

        method(f, "Hide")
        if not method(f, "SetSize", size, size) then
            method(f, "SetWidth", size)
            method(f, "SetHeight", size)
        end
        method(f, "SetFrameStrata", "MEDIUM")
        method(f, "SetClampedToScreen", true)

        local okTex, tex = method(f, "CreateTexture", nil, "ARTWORK")
        if not okTex then tex = nil end
        if tex ~= nil then method(tex, "SetAllPoints", f) end

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

        method(f, "SetMovable", true)
        method(f, "EnableMouse", true)
        method(f, "RegisterForDrag", "LeftButton")
        method(f, "SetScript", "OnDragStart", function()
            local okKey, held = call(env.IsControlKeyDown)
            if not (okKey and held == true) then return end
            dragging = true
            method(f, "StartMoving")
        end)
        method(f, "SetScript", "OnDragStop", function()
            if not dragging then return end
            dragging = false
            method(f, "StopMovingOrSizing")
            method(f, "SetUserPlaced", false)
            local point = standing()
            if point and moved then
                local okM, err = pcall(moved, point)
                if not okM and movedFailed then pcall(movedFailed, err) end
            end
        end)

        function h.setTexture(value)
            if tex == nil then return false end
            local okSet = method(tex, "SetTexture", value)
            return okSet and value ~= nil
        end
        function h.place(point)
            if type(point) ~= "table" then return end
            method(f, "ClearAllPoints")
            method(f, "SetPoint", point[1], parent, point[2], point[3], point[4])
        end
        function h.show(on)
            method(f, on and "Show" or "Hide")
        end
        function h.mark(look)
            if tex == nil then return false end
            if look == "far" then
                return (method(tex, "SetVertexColor", 1, 0.3, 0.3)) and true or false
            end
            return (method(tex, "SetVertexColor", 1, 1, 1)) and true or false
        end
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
    --                          holder go down two levels. It keeps the mouse
    --                          on a rim past the arrow on top, for a
    --                          Ctrl-drag only: clicks and the pointer there
    --                          tell nothing. Going under ends a drag in
    --                          progress; staying under does not.
    --   h.dragging()           true while the player is dragging it
    --   h.text(lines, point)   lines under / over it, point { a, r, x, y }
    --                          against the placed frame; no lines: hidden
    --   h.onMoved(fn)          fn(point) after the player drags it
    -- A new arrow is hidden and has no place until told.
    -- The arrows' one menu (AM5): made at the first right click and used by
    -- both arrows after that. A full-screen catcher under the panel closes
    -- it at a click anywhere else. Rows are plain buttons: a click tells
    -- the key of its row to whoever opened the menu, and does nothing else.
    -- Nothing here is a secure frame, nothing acts on the game world, and
    -- no protected call is made. Every call is a first guess, not seen in
    -- game on 16001. owner is the arrow handle the menu is open for.
    local MENU_ROW, MENU_PAD, MENU_MARK, MENU_WIDTH = 18, 6, 22, 170
    -- How far past its art the arrow under the other one can be grabbed for
    -- a Ctrl-drag, in screen units. A first guess, not seen in game.
    local BEHIND_GRAB = 8
    local menu = { rows = {}, keys = {} }
    -- A made catcher is hidden here whether or not a menu is open (AI1): it
    -- covers the screen, so it must never outlive the menu it is under.
    local function menuClose()
        menu.owner, menu.pick = nil, nil
        if menu.catcher then method(menu.catcher, "Hide") end
    end
    -- Escape (owner decision D9, route a): the catcher has a global name,
    -- `name` .. "Menu" from the first arrow that opens the menu, and that
    -- name is put in the game list UISpecialFrames once. The game hides a
    -- listed frame that is shown at Escape and takes the key only then, so
    -- with no menu open the key stays with the game. Hidden by the game or
    -- by us, OnHide leaves the menu closed: no owner, nothing to choose.
    -- A name that is already a global is not taken over, and without a name
    -- or without the list the menu opens as before, with no Escape route.
    -- A first guess throughout: not seen in game on 16001.
    -- UISpecialFrames could not be confirmed from public docs: needs game
    -- test.
    local function menuFrames(name)
        if menu.panel then return true end
        if not menu.catcher then
            local global = type(name) == "string" and name ~= "" and (name .. "Menu") or nil
            if global ~= nil and env[global] ~= nil then global = nil end
            local ok, catcher = call(env.CreateFrame, "Button", global, env.UIParent)
            if not ok or catcher == nil then return false end
            menu.catcher = catcher
            local special = env.UISpecialFrames
            if global ~= nil and type(special) == "table" then
                local there = false
                for i = 1, #special do
                    if special[i] == global then there = true end
                end
                if not there then special[#special + 1] = global end
            end
            -- The game makes a frame shown. Hidden at once (AI1): only a
            -- menu that has opened fully shows it, so a panel that cannot
            -- be made leaves nothing over the screen.
            method(catcher, "Hide")
            method(catcher, "SetFrameStrata", "FULLSCREEN_DIALOG")
            method(catcher, "SetAllPoints", env.UIParent)
            method(catcher, "EnableMouse", true)
            method(catcher, "RegisterForClicks", "AnyUp")
            method(catcher, "SetScript", "OnClick", menuClose)
            method(catcher, "SetScript", "OnHide", function()
                menu.owner, menu.pick = nil, nil
            end)
        end
        local ok, panel = call(env.CreateFrame, "Frame", nil, menu.catcher)
        if not ok or panel == nil then return false end
        menu.panel = panel
        -- The panel takes the mouse: a click between two rows closes nothing.
        method(panel, "EnableMouse", true)
        local okB, back = method(panel, "CreateTexture", nil, "BACKGROUND")
        if okB and back ~= nil then
            method(back, "SetAllPoints", panel)
            method(back, "SetColorTexture", 0.05, 0.05, 0.05, 0.92)
        end
        return true
    end
    local function menuRow(i)
        local r = menu.rows[i]
        if r then return r end
        local ok, button = call(env.CreateFrame, "Button", nil, menu.panel)
        if not ok or button == nil then return nil end
        r = { button = button }
        local okM, mark = method(button, "CreateTexture", nil, "ARTWORK")
        if okM and mark ~= nil then
            r.mark = mark
            method(mark, "SetTexture", "Interface\\Buttons\\UI-CheckBox-Check")
            method(mark, "SetSize", MENU_ROW - 4, MENU_ROW - 4)
            method(mark, "SetPoint", "LEFT", button, "LEFT", 4, 0)
        end
        local okT, text = method(button, "CreateFontString", nil, "OVERLAY", "GameFontHighlightSmall")
        if okT and text ~= nil then
            r.text = text
            method(text, "SetPoint", "LEFT", button, "LEFT", MENU_MARK, 0)
        end
        method(button, "RegisterForClicks", "AnyUp")
        method(button, "SetScript", "OnClick", function()
            local key, pick = menu.keys[i], menu.pick
            if key == nil or menu.owner == nil then return end
            menuClose()
            if pick then pcall(pick, key) end
        end)
        menu.rows[i] = r
        return r
    end
    -- Opens the menu for the arrow handle `owner` (frame f) with `items`
    -- (UI/ArrowMenu's rows); pick(key) is told the row chosen.
    local function menuOpen(owner, f, items, pick, name)
        if type(items) ~= "table" or #items == 0 or not menuFrames(name) then
            menuClose()
            return
        end
        local panel, widest = menu.panel, 0
        for i = 1, #items do
            local item = type(items[i]) == "table" and items[i] or {}
            local r = menuRow(i)
            menu.keys[i] = nil
            if r then
                local plain = not item.title and not item.sep and not item.disabled
                if plain and type(item.key) == "string" then menu.keys[i] = item.key end
                method(r.button, "ClearAllPoints")
                method(r.button, "SetPoint", "TOPLEFT", panel, "TOPLEFT", MENU_PAD, -MENU_PAD - (i - 1) * MENU_ROW)
                if r.text then
                    method(r.text, "SetText", type(item.text) == "string" and item.text or "")
                    if item.title then
                        method(r.text, "SetTextColor", 1, 0.82, 0)
                    elseif item.disabled then
                        method(r.text, "SetTextColor", 0.5, 0.5, 0.5)
                    else
                        method(r.text, "SetTextColor", 1, 1, 1)
                    end
                    local okW, w = method(r.text, "GetStringWidth")
                    if okW and type(w) == "number" and not hidden(w) and w > widest then widest = w end
                end
                if r.mark then method(r.mark, item.checked == true and "Show" or "Hide") end
                method(r.button, "Show")
            end
        end
        for i = #items + 1, #menu.rows do
            menu.keys[i] = nil
            method(menu.rows[i].button, "Hide")
        end
        local width = math.max(MENU_WIDTH, widest + MENU_MARK + MENU_PAD)
        for i = 1, #items do
            if menu.rows[i] then method(menu.rows[i].button, "SetSize", width, MENU_ROW) end
        end
        method(panel, "SetSize", width + 2 * MENU_PAD, #items * MENU_ROW + 2 * MENU_PAD)
        -- At the pointer where the client says where that is, else under
        -- the arrow.
        method(panel, "ClearAllPoints")
        local okC, x, y = call(env.GetCursorPosition)
        local okS, scale = method(env.UIParent, "GetEffectiveScale")
        local at = false
        if okC and okS and type(x) == "number" and type(y) == "number" and type(scale) == "number"
            and not hidden(x) and not hidden(y) and not hidden(scale) and scale > 0 then
            at = method(panel, "SetPoint", "TOPLEFT", env.UIParent, "BOTTOMLEFT", x / scale, y / scale)
        end
        if not at then method(panel, "SetPoint", "TOPLEFT", f, "BOTTOMLEFT", 0, 0) end
        menu.owner, menu.pick = owner, type(pick) == "function" and pick or nil
        method(menu.catcher, "Show")
    end

    function c.arrow(spec)
        spec = type(spec) == "table" and spec or {}
        local parent = env.UIParent
        local ok, f = call(env.CreateFrame, "Frame", spec.name, parent)
        if not ok or f == nil then return nil end
        local h, moved, dragging = {}, nil, false
        -- clicked, hovered: what the caller wants told (AM5). dragged: the
        -- button now down has moved the arrow. tipped: the client's tooltip
        -- was last filled by this arrow.
        local clicked, hovered, dragged, tipped = nil, nil, false, false
        -- under: this arrow is behind the other one (h.behind).
        local under = false
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
            dragged = true
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
        -- Clicks and the pointer (AM5). A click is a left or right button
        -- let go over the arrow that did not move it: the client may fire
        -- the end of a drag before or after the button's release, so the
        -- mark is cleared by the release and again by the next press. A
        -- client that cannot say whether the pointer is still over the
        -- arrow counts the click. The caller's handler is only told; an
        -- error in it stays here. First guesses, not seen in game on 16001:
        -- OnMouseDown / OnMouseUp(button) on a plain frame, IsMouseOver,
        -- OnEnter / OnLeave.
        -- Docs (warcraft.wiki.gg): UIHANDLER OnMouseUp (self, button, upInside);
        -- API ScriptRegion IsMouseOver answers true or false; names and
        -- arguments match.
        method(f, "SetScript", "OnMouseDown", function() dragged = false end)
        method(f, "SetScript", "OnMouseUp", function(_, button)
            if dragged then
                dragged = false
                return
            end
            -- Under the other arrow only a Ctrl-drag is heard.
            if under then return end
            local which = (button == "LeftButton" and "left") or (button == "RightButton" and "right") or nil
            if not which or not clicked then return end
            local okOver, over = method(f, "IsMouseOver")
            if okOver and over == false then return end
            pcall(clicked, which)
        end)
        method(f, "SetScript", "OnEnter", function()
            if hovered and not under then pcall(hovered, true) end
        end)
        method(f, "SetScript", "OnLeave", function()
            if hovered and not under then pcall(hovered, false) end
        end)
        -- Hidden: a drag is let go, and this arrow's menu and tooltip go
        -- with it.
        method(f, "SetScript", "OnHide", function()
            letGo()
            if menu.owner == h then menuClose() end
            h.tip(nil)
        end)

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
        -- The older styles (Nav/ArrowStyles.lua): the arrow drawn from lines
        -- and dots in place of its pictures. First guess: the calls are the
        -- ones the predecessor's arrow made; none was checked on the client
        -- from here.
        local MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
        local pictures = list(shadow, pool, body, shine, halo, ripple, beam, beamDown)
        local lineList, dotList, dotKind = {}, {}, {}
        local linesUp, dotsUp, shapesOn = 0, 0, false
        -- True when this client can draw them.
        function h.canShapes()
            return lookup(holder, "CreateLine") ~= false
        end
        -- s: what Nav.ArrowShapes answers; nil: back to the pictures. A line
        -- or dot the client did not make is left out.
        function h.shapes(s)
            if type(s) ~= "table" then
                if not shapesOn then return end
                shapesOn = false
                for i = 1, linesUp do if lineList[i] then fast(lineList[i], "Hide") end end
                for i = 1, dotsUp do if dotList[i] then fast(dotList[i], "Hide") end end
                linesUp, dotsUp = 0, 0
                for i = 1, #cut do fast(cut[i], "Show") end
                fast(pool, current == "needle" and "Hide" or "Show")
                return
            end
            if not shapesOn then
                shapesOn = true
                for i = 1, #pictures do fast(pictures[i], "Hide") end
            end
            local lines, nl = s.lines, tonumber(s.nl) or 0
            for i = 1, nl do
                local e = lines[i]
                local l = lineList[i]
                if l == nil then
                    local okL, made = method(holder, "CreateLine", nil, e.layer)
                    l = okL and made or false
                    lineList[i] = l
                end
                if l then
                    fast(l, "SetDrawLayer", e.layer, e.sub)
                    fast(l, "SetThickness", e.thick)
                    fast(l, "SetStartPoint", "CENTER", holder, e.x1, e.y1)
                    fast(l, "SetEndPoint", "CENTER", holder, e.x2, e.y2)
                    fast(l, "SetColorTexture", e.r, e.g, e.b, e.a)
                    fast(l, "Show")
                end
            end
            for i = nl + 1, linesUp do if lineList[i] then fast(lineList[i], "Hide") end end
            linesUp = nl
            local dots, nd = s.dots, tonumber(s.nd) or 0
            for i = 1, nd do
                local e = dots[i]
                local d = dotList[i]
                if d == nil then
                    local okD, made = method(holder, "CreateTexture", nil, e.layer, nil, e.sub)
                    d = okD and made or false
                    dotList[i] = d
                end
                if d then
                    -- A disc is the round mask, tinted; a picture is cut in
                    -- from its border; a square is a plain colour.
                    local kind = e.tex ~= nil and e.tex or (e.round and "round" or "square")
                    if dotKind[i] ~= kind then
                        dotKind[i] = kind
                        if e.tex ~= nil then
                            fast(d, "SetTexture", e.tex)
                            fast(d, "SetTexCoord", 0.08, 0.92, 0.08, 0.92)
                        else
                            fast(d, "SetTexCoord", 0, 1, 0, 1)
                            if e.round then fast(d, "SetTexture", MASK) end
                        end
                    end
                    if kind == "square" then
                        fast(d, "SetColorTexture", e.r, e.g, e.b, e.a)
                        fast(d, "SetVertexColor", 1, 1, 1, 1)
                    else
                        fast(d, "SetVertexColor", e.r, e.g, e.b, e.a)
                    end
                    fast(d, "SetDrawLayer", e.layer, e.sub)
                    sized(d, e.w, e.h)
                    fast(d, "SetPoint", "CENTER", holder, "CENTER", e.x, e.y)
                    fast(d, "Show")
                end
            end
            for i = nd + 1, dotsUp do if dotList[i] then fast(dotList[i], "Hide") end end
            dotsUp = nd
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
            on = on and true or false
            -- Going under ends a drag. Told again while already under (the
            -- caller says it at every update) it must not: that drag began
            -- on this arrow while it was under, and is how it is pulled
            -- out of the stack.
            if on and not under then letGo() end
            -- The holder and the text frame are frames of their own: left at
            -- their levels they would keep the art and the text above the
            -- arrow this one is meant to be under.
            levels(on and math.max(level - 2, 0) or level)
            -- Under, the arrow on top covers this frame and takes the
            -- mouse there. The hit rectangle is widened so that a rim
            -- stays reachable: where the art shows past the frame, and
            -- BEHIND_GRAB more. In front it is the frame itself. First
            -- guess, not seen in game: SetHitRectInsets with negative
            -- insets, and the frame on top winning where the two overlap.
            if on ~= under then
                local rim = on and -((math.max(art - size, 0)) / 2 + BEHIND_GRAB) or 0
                method(f, "SetHitRectInsets", rim, rim, rim, rim)
            end
            under = on
            method(f, "EnableMouse", true)
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
        -- fn("left" | "right") at a click on the arrow; nil: no one is told.
        function h.onClick(fn)
            clicked = type(fn) == "function" and fn or nil
        end
        -- fn(true) when the pointer comes over the arrow, fn(false) when it
        -- leaves; nil: no one is told.
        function h.onHover(fn)
            hovered = type(fn) == "function" and fn or nil
        end
        -- The client's own tooltip beside the arrow with these lines, the
        -- first as its title; nil or no lines takes it away, unless this
        -- arrow did not fill it or another frame has taken it since.
        -- First guesses, not seen in game on 16001: GameTooltip with
        -- SetOwner(frame, "ANCHOR_RIGHT"), ClearLines, AddLine(text, r, g,
        -- b, wrap), Show, Hide, IsOwned(frame).
        -- Docs (warcraft.wiki.gg, API GameTooltip SetOwner): (owner, anchor [, x,
        -- y]); matches. IsOwned has no page: needs a game test.
        function h.tip(lines)
            local tip = env.GameTooltip
            if tip == nil then return end
            local out = {}
            for i = 1, #(type(lines) == "table" and lines or {}) do out[i] = tostring(lines[i]) end
            if #out == 0 then
                if not tipped then return end
                tipped = false
                -- Hidden only when the tooltip says it is this arrow's
                -- (AI2): no answer is not known, and is left alone.
                local okOwned, owned = method(tip, "IsOwned", f)
                if not okOwned or owned ~= true then return end
                method(tip, "Hide")
                return
            end
            method(tip, "SetOwner", f, "ANCHOR_RIGHT")
            method(tip, "ClearLines")
            method(tip, "AddLine", out[1], 1, 1, 1)
            for i = 2, #out do method(tip, "AddLine", out[i], 0.8, 0.8, 0.8, true) end
            method(tip, "Show")
            tipped = true
        end
        -- The menu at the pointer with these rows (UI/ArrowMenu's);
        -- pick(key) is told the row chosen, once, after the menu has
        -- closed. nil or no rows closes this arrow's menu.
        function h.menu(items, pick)
            if type(items) ~= "table" or #items == 0 then
                if menu.owner == h then menuClose() end
                return
            end
            menuOpen(h, f, items, pick, spec.name)
        end
        arrowFrames[h] = f
        return h
    end

    -- F9 window buttons: the one read UI/WindowButtons.lua asks for.
    --
    -- c.windowButton(frameName, spec) -> h, or nil and why. A plain button
    -- on one of the game's own windows. spec = { name, text, tip, point =
    -- { anchor, relAnchor, x, y } }. nil, and nothing is made, when the
    -- window is not there ("no window"), when the client does not say
    -- plainly that the player is out of combat ("in combat"), when no
    -- frame could be made ("no frame"), or on a bad ask ("bad ask"). The
    -- button is an ordinary Button: no secure template, no attribute, no
    -- action. It only tells its caller.
    --
    -- A protected window stops it again (section 134): nil and
    -- "its window is protected" when IsProtected answers true, nil and
    -- "its window will not say whether it is protected" when it
    -- gives no plain true / false. Section 132 took this check away on a
    -- guess; what stopped the button the owner did not see was never
    -- found, so the check is back and the reason is now said. What the
    -- public sources say (WoW\from-twin\RESEARCH-merchant-button.md): the
    -- merchant window is not declared protected in the public UI source
    -- for this client, and other addons put plain buttons on it with no
    -- such check. None of that has been seen in game. c.windowState below
    -- lets one look in game settle it. Needs game test.
    --
    -- Section 142: spec.inside = { field name, ... } places the button
    -- against a part of the window instead of the window itself: the
    -- first named field of the window that is a frame. The button is
    -- still a child of the window. When none of the named fields is
    -- there, nothing is made: nil and
    -- "its place inside the window was not found" (a guess at
    -- another place could sit under something again). spec.strata is
    -- given to SetFrameStrata when it is a string. h.placedOn is the
    -- field name used, nil for the window itself. Why: the owner saw the
    -- world map button under the quest log header at the top right of
    -- the window. The map window field ScrollContainer (the map
    -- itself) is named in the public UI source for this client family
    -- and used by two installed addons
    -- (WoW\from-twin\RESEARCH-worldmap-button.md). Frame:SetFrameStrata
    -- (warcraft.wiki.gg). Not seen in game. Needs game test.
    --   h.onClick(fn, failed)  fn() on a left click; failed(err) is told the
    --                          error of an fn that failed.
    --   h.show(on)
    -- First guesses, none seen in game: IsProtected on the window frame,
    -- the UIPanelButtonTemplate look, GameTooltip for the tip.
    -- IsProtected and UIPanelButtonTemplate checked on warcraft.wiki.gg and
    -- in the public name lists of Ketho/BlizzardInterfaceResources (forever
    -- branch).
    -- Section 130, each name and its arguments read on warcraft.wiki.gg:
    --   CreateFrame(frameType, name, parent, template)   (API CreateFrame)
    --   ScriptRegion:IsProtected() -> isProtected, isProtectedExplicitly
    --   InCombatLockdown() -> a true / false
    --   Button:RegisterForClicks("LeftButtonUp"): a listed word, and the
    --     one a button has when never told
    --   Button:SetText(text); SetSize(width, height), SetWidth, SetHeight
    --   SetPoint(point, relativeTo, relativePoint, offsetX, offsetY)
    --   OnClick(self, button, down); OnEnter and OnLeave(self, motion)
    --   GameTooltip:SetOwner(owner, anchor), "ANCHOR_RIGHT" a listed word
    --   GameTooltip:SetText(text)
    -- The template has no page of its own there; the pages for CreateFrame
    -- and RegisterForClicks use it by this name.
    -- Needs game test: GameTooltip:IsOwned (no page; named only as
    -- IsOwned(frame) -> true / false on the SetOwner page); whether
    -- IsProtected answers plainly on this client (its page marks the answer
    -- as one the client may hide, and a hidden answer makes no button);
    -- SetNormalFontObject with a font name (the page lists string or Font,
    -- no more; used only when the template is missing).
    function c.windowButton(frameName, spec)
        if type(frameName) ~= "string" or frameName == "" or type(spec) ~= "table" then
            return nil, "bad ask"
        end
        local frame = env[frameName]
        if type(frame) ~= "table" then return nil, "no window" end
        if c.inCombat() ~= false then return nil, "in combat" end
        local okP, protected = method(frame, "IsProtected")
        if not okP or hidden(protected) or type(protected) ~= "boolean" then
            return nil, "its window will not say whether it is protected"
        end
        if protected then return nil, "its window is protected" end

        local against, placedOn = frame, nil
        if type(spec.inside) == "table" then
            against = nil
            for _, field in ipairs(spec.inside) do
                if type(field) == "string" then
                    local okF, part = pcall(function() return frame[field] end)
                    if okF and not hidden(part) and type(part) == "table" then
                        against, placedOn = part, field
                        break
                    end
                end
            end
            if against == nil then return nil, "its place inside the window was not found" end
        end

        local name = spec.name
        if type(name) ~= "string" or name == "" or env[name] ~= nil then name = nil end
        local ok, b = call(env.CreateFrame, "Button", name, frame, "UIPanelButtonTemplate")
        if not ok or b == nil then
            ok, b = call(env.CreateFrame, "Button", name, frame)
            if ok and b ~= nil then method(b, "SetNormalFontObject", "GameFontNormalSmall") end
        end
        if not ok or b == nil then return nil, "no frame" end

        local label = type(spec.text) == "string" and spec.text or ""
        method(b, "Hide")
        method(b, "SetText", label)
        local width = 24 + 7 * #label
        if not method(b, "SetSize", width, 22) then
            method(b, "SetWidth", width)
            method(b, "SetHeight", 22)
        end
        local p = type(spec.point) == "table" and spec.point or {}
        if type(spec.strata) == "string" then method(b, "SetFrameStrata", spec.strata) end
        method(b, "SetPoint", type(p[1]) == "string" and p[1] or "TOPRIGHT", against,
            type(p[2]) == "string" and p[2] or "TOPRIGHT", tonumber(p[3]) or 0, tonumber(p[4]) or 0)
        method(b, "RegisterForClicks", "LeftButtonUp")

        local h, clicked, clickFailed = { placedOn = placedOn }, nil, nil
        -- The handlers close over the button: they use none of the
        -- arguments the client passes.
        method(b, "SetScript", "OnClick", function()
            if not clicked then return end
            -- An error in fn must not reach the click handler of the client.
            local okC, err = pcall(clicked)
            if not okC and clickFailed then pcall(clickFailed, err) end
        end)
        if type(spec.tip) == "string" and spec.tip ~= "" then
            method(b, "SetScript", "OnEnter", function()
                local tip = env.GameTooltip
                if tip == nil then return end
                if not method(tip, "SetOwner", b, "ANCHOR_RIGHT") then return end
                method(tip, "SetText", spec.tip)
                method(tip, "Show")
            end)
            method(b, "SetScript", "OnLeave", function()
                local tip = env.GameTooltip
                if tip == nil then return end
                local okO, mine = method(tip, "IsOwned", b)
                -- Hidden only when the tooltip says it is this button that owns it.
                if okO and mine == true then method(tip, "Hide") end
            end)
        end

        function h.onClick(fn, failed)
            clicked = type(fn) == "function" and fn or nil
            clickFailed = type(failed) == "function" and failed or nil
        end
        function h.show(on) method(b, on and "Show" or "Hide") end
        -- true / false: whether the button can be seen now (it is shown and
        -- so is every parent); nil when the client does not say plainly.
        -- Region:IsVisible (warcraft.wiki.gg). Needs game test.
        function h.visible()
            local okV, v = method(b, "IsVisible")
            if not okV or hidden(v) or type(v) ~= "boolean" then return nil end
            return v
        end
        return h
    end

    -- c.windowState(frameName) -> nil when there is no such window, else
    -- { shown = true / false / nil, protected = true / false / nil }; nil
    -- inside is an answer the client did not give plainly. It only reads.
    -- UI/WindowButtons.lua prints it, so one look in game says what the
    -- window is on this client. Region:IsShown and
    -- ScriptRegion:IsProtected (warcraft.wiki.gg). Needs game test.
    function c.windowState(frameName)
        local frame = type(frameName) == "string" and env[frameName] or nil
        if type(frame) ~= "table" then return nil end
        local function plain(name)
            local ok, v = method(frame, name)
            if not ok or hidden(v) or type(v) ~= "boolean" then return nil end
            return v
        end
        return { shown = plain("IsShown"), protected = plain("IsProtected") }
    end

    ---------------------------------------------------------------------
    -- F6, the rotation helper: its reads and its one secure frame, kept
    -- together. All first guesses: not seen in game on 16001.
    -- Names checked on warcraft.wiki.gg (API GetShapeshiftForm, API
    -- UnitInVehicle, API C_PetBattles.IsInBattle, API InCombatLockdown,
    -- SecureActionButtonTemplate). What IsInBattle answers with, and which
    -- click (key down or key up) the template acts on, need game test.
    ---------------------------------------------------------------------

    -- The form you are in: a number (0 is no form), or nil when not known
    -- (no call, a failed call, a secret answer, or anything but a number).
    -- GetShapeshiftForm(). It names no unit and only reads.
    function c.form()
        local ok, n = call(env.GetShapeshiftForm)
        if not ok or n == nil or hidden(n) or type(n) ~= "number" then return nil end
        return n
    end

    -- In a pet battle: true, false, or nil when not known. A client with
    -- no C_PetBattles.IsInBattle does not say. It only reads.
    function c.petBattle()
        local api = env.C_PetBattles
        if type(api) ~= "table" then return nil end
        return yesNo(call(api.IsInBattle))
    end

    -- In a vehicle: true, false, or nil when not known.
    -- UnitInVehicle("player"): no unit but you is asked about.
    function c.vehicle()
        return yesNo(call(env.UnitInVehicle, "player"))
    end

    -- A secure button for the key frame (Rotation/KeyFrame.lua), or nil
    -- when the client made none. It is made from the client's own
    -- SecureActionButtonTemplate: with no size and no art it takes no
    -- mouse click, and it is hidden when it is made outside a fight (in
    -- one, hiding it is the client's to refuse, so it is not asked).
    --   h.set(attr, value) -> true, or false and why. It asks
    --                   InCombatLockdown() first: anything but a plain
    --                   false is "lockdown" and the frame is not touched.
    --                   A SetAttribute that fails is "refused".
    --   h.get(attr) -> what the frame holds for it, or nil.
    -- Nothing here binds a key, registers a state driver, clicks the
    -- button, or casts: it holds attributes, and only you press the key.
    function c.secureButton(spec)
        spec = type(spec) == "table" and spec or {}
        local ok, f = call(env.CreateFrame, "Button", spec.name, env.UIParent, "SecureActionButtonTemplate")
        if not ok or f == nil then return nil end
        local function unlocked()
            local okLock, locked = call(env.InCombatLockdown)
            return okLock and locked == false
        end
        if unlocked() then method(f, "Hide") end
        local h = {}
        function h.set(attr, value)
            if not unlocked() then return false, "lockdown" end
            if not method(f, "SetAttribute", attr, value) then return false, "refused" end
            return true
        end
        function h.get(attr)
            local okGet, v = method(f, "GetAttribute", attr)
            if not okGet then return nil end
            return v
        end
        return h
    end

    -- F2 errand stops: the reads Nav/ServiceSeen.lua, Nav/HearthSeen.lua,
    -- Nav/HearthStep.lua and Nav/Errand.lua ask for. Each only reads. An
    -- answer the client hides, or one of the wrong kind, is "not known".
    -- First guesses, none seen in game: UnitGUID, CanMerchantRepair,
    -- GetBindLocation, GetItemCount and GetItemCooldown.
    -- Checked on warcraft.wiki.gg (the API pages, and Patch 1.60.1/API
    -- changes): UnitGUID, CanMerchantRepair and GetBindLocation are there by
    -- those names. The item count and the item cooldown are there as
    -- C_Item.GetItemCount and C_Container.GetItemCooldown; the bare names
    -- are not listed for this client and are asked second. What
    -- CanMerchantRepair answers with needs game test.
    --
    -- c.guid(unit) -> text or nil. Only the player, the pet and the target;
    -- any other unit is nil and the client is not asked. Shared with F7,
    -- which carries the same lines.
    local GUID_UNITS = { player = true, pet = true, target = true }
    function c.guid(unit)
        if type(unit) ~= "string" or not GUID_UNITS[unit] then return nil end
        local ok, id = call(env.UnitGUID, unit)
        if not ok or id == nil or hidden(id) or type(id) ~= "string" or id == "" then return nil end
        return id
    end
    function c.playerGUID() return c.guid("player") end
    function c.petGUID() return c.guid("pet") end

    -- c.serviceNpc() -> { guid, name } or nil: the npc whose window is
    -- open (unit "npc", as c.trainer reads it). Nil unless the client says
    -- plainly that it is no player. A part not known is left out; nil when
    -- neither is known.
    function c.serviceNpc()
        local okP, isPlayer = call(env.UnitIsPlayer, "npc")
        if not okP or hidden(isPlayer) or isPlayer ~= false then return nil end
        local name = text(call(env.UnitName, "npc"))
        local guid
        local okG, id = call(env.UnitGUID, "npc")
        if okG and id ~= nil and not hidden(id) and type(id) == "string" and id ~= "" then guid = id end
        if name == nil and guid == nil then return nil end
        return { guid = guid, name = name }
    end

    -- c.merchantRepairs() -> true, false, or nil when not known.
    function c.merchantRepairs()
        local ok, v = call(env.CanMerchantRepair)
        if not ok or v == nil or hidden(v) then return nil end
        if v == true or v == 1 then return true end
        if v == false or v == 0 then return false end
        return nil
    end

    -- c.bindLocation() -> the name of the place the hearthstone is set to,
    -- or nil.
    function c.bindLocation()
        return text(call(env.GetBindLocation))
    end

    -- c.hearthCooldown() -> seconds until the hearthstone is ready, 0 when
    -- ready, nil when not known or the player carries no stone. It never
    -- uses the stone.
    local HEARTHSTONE = 6948
    function c.hearthCooldown()
        local items = type(env.C_Item) == "table" and env.C_Item or {}
        local bags = type(env.C_Container) == "table" and env.C_Container or {}
        local okN, n = call(items.GetItemCount, HEARTHSTONE)
        if not okN then okN, n = call(env.GetItemCount, HEARTHSTONE) end
        if not okN or n == nil or hidden(n) or type(n) ~= "number" or n < 1 then return nil end
        local ok, start, duration = call(bags.GetItemCooldown, HEARTHSTONE)
        if not ok then ok, start, duration = call(env.GetItemCooldown, HEARTHSTONE) end
        if not ok or start == nil or duration == nil or hidden(start) or hidden(duration) then return nil end
        if type(start) ~= "number" or type(duration) ~= "number" then return nil end
        if start ~= start or duration ~= duration or start < 0 or duration < 0 then return nil end
        if start == 0 or duration == 0 then return 0 end
        local okT, now = call(env.GetTime)
        if not okT or now == nil or hidden(now) or type(now) ~= "number" then return nil end
        local left = start + duration - now
        if left ~= left or left == math.huge then return nil end
        if left < 0 then return 0 end
        return left
    end

    -- N8 (lead section 238): c.itemCooldown(id) -> seconds until the item
    -- is ready, 0 when ready, nil when not known. The same read as
    -- c.hearthCooldown, for any item id (a whole number above 0). A first
    -- guess, not seen in game. It never uses the item.
    function c.itemCooldown(id)
        if type(id) ~= "number" or id <= 0 or id % 1 ~= 0 then return nil end
        local bags = type(env.C_Container) == "table" and env.C_Container or {}
        local ok, start, duration = call(bags.GetItemCooldown, id)
        if not ok then ok, start, duration = call(env.GetItemCooldown, id) end
        if not ok or start == nil or duration == nil or hidden(start) or hidden(duration) then return nil end
        if type(start) ~= "number" or type(duration) ~= "number" then return nil end
        if start ~= start or duration ~= duration or start < 0 or duration < 0 then return nil end
        if start == 0 or duration == 0 then return 0 end
        local okT, now = call(env.GetTime)
        if not okT or now == nil or hidden(now) or type(now) ~= "number" then return nil end
        local left = start + duration - now
        if left ~= left or left == math.huge then return nil end
        if left < 0 then return 0 end
        return left
    end

    ---------------------------------------------------------------------
    -- F7, the fight log and death report: its reads, kept together. All
    -- first guesses: not seen in game on 16001.
    -- Checked on warcraft.wiki.gg: UnitClassification is there by that
    -- name. CombatLogGetCurrentEventInfo is not listed for this client, and
    -- the combat-log event is listed as closed to addons since 12.0.0.
    -- With no such read watchCombatLog answers nil and registers nothing.
    -- Lead section 195: C_CombatLog.GetCurrentEventInfo is asked first, the
    -- old global second. Needs game test: which of the two 16001 has, and
    -- that the values come in the same order.
    ---------------------------------------------------------------------

    -- c.guid(unit), c.playerGUID() and c.petGUID() are above, with the
    -- errand reads: one read, shared.

    -- The rank word of your target as the client gives it ("elite",
    -- "normal", ...), or nil when not known or with no word.
    -- UnitClassification("target").
    function c.targetRank()
        local ok, rank = call(env.UnitClassification, "target")
        if not ok or rank == nil or hidden(rank) or type(rank) ~= "string" or rank == "" then return nil end
        return rank
    end

    -- The combat-log read of this client: C_CombatLog.GetCurrentEventInfo
    -- when it is a function, else CombatLogGetCurrentEventInfo when it is
    -- one, else nil. Looked up again at each event; a lookup that raises
    -- counts as no read.
    local function logRead()
        local ok, space = pcall(function() return env.C_CombatLog end)
        if ok and type(space) == "table" then
            local found, fn = pcall(function() return space.GetCurrentEventInfo end)
            if found and type(fn) == "function" then return fn end
        end
        local old = env.CombatLogGetCurrentEventInfo
        if type(old) == "function" then return old end
        return nil
    end

    -- Calls fn with the values of each combat-log event, in the client's
    -- own order: COMBAT_LOG_EVENT_UNFILTERED, read with logRead() above.
    -- Answers true when the feed was taken; nil and "no log" when the
    -- client has neither read; nil and "not taken" when it did not take the
    -- event (fn is then never called). A read that fails does not call fn
    -- that time. A secret value is handed over as nil, never as it is. It
    -- only reads: the log is not filtered, cleared or written to.
    local logBuf = {}
    function c.watchCombatLog(fn)
        if type(fn) ~= "function" then return nil end
        if logRead() == nil then return nil, "no log" end
        local function pass(ok, ...)
            if not ok then return end
            local n = select("#", ...)
            for i = 1, n do
                local v = select(i, ...)
                if v ~= nil and hidden(v) then v = nil end
                logBuf[i] = v
            end
            for i = n + 1, #logBuf do logBuf[i] = nil end
            fn(unpack(logBuf, 1, n))
        end
        local cancel = events.add("COMBAT_LOG_EVENT_UNFILTERED", function()
            local read = logRead()
            if read ~= nil then pass(pcall(read)) end
        end)
        if unregistered["COMBAT_LOG_EVENT_UNFILTERED"] then
            cancel()
            return nil, "not taken"
        end
        return true
    end

    ---------------------------------------------------------------------
    -- Settings controls (Plexy, LEDGER 134/135; WoW/from-plexy/
    -- RESEARCH-settings-controls.md): Z-Flow's page in the game's
    -- Options > AddOns, with controls. The pattern is legacy Flow's, which
    -- ran on this client (Modules/Settings.lua): a canvas registered with
    -- Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory,
    -- else InterfaceOptions_AddCategory; opened with
    -- Settings.OpenToCategory(category:GetID()), else
    -- InterfaceOptionsFrame_OpenToCategory (twice on older clients); built
    -- from UICheckButtonTemplate check buttons, UIPanelButtonTemplate buttons,
    -- InputBoxTemplate edit boxes and a UIPanelScrollFrameTemplate scroll
    -- frame. No Blizzard panel function (ShowUIPanel, HideUIPanel) is called.
    -- Needs a game test: the page under Options > AddOns, and each control.
    --
    --   c.optionsPage(spec) -> handle, or nil when the client has no options
    --   page route. spec = { title = text, name = global frame name or nil }
    --   h.open() -> true when the game's Options was asked to open at the page
    --   h.onShow(fn)   fn() each time the page is shown
    --   h.shown() -> true while it is on the screen
    --   h.draw(rows, act)   rows top to bottom, each one of
    --     { kind = "group", text }
    --     { kind = "toggle", key, label, value, settable, why }
    --     { kind = "choice", key, label, value, choices, settable, why }
    --     { kind = "number", key, label, value, min, max, step, settable, why }
    --     { kind = "text", key, label, value, settable, why }
    --     { kind = "info", key, label, shown }
    --   act(key, value) is called when the player changes a control; the
    --   page is redrawn by whoever answers it.
    --   h.status(text)   one line under the title
    ---------------------------------------------------------------------
    function c.optionsPage(spec)
        spec = type(spec) == "table" and spec or {}
        local S = env.Settings
        local okC, canvas = call(env.CreateFrame, "Frame", spec.name)
        if not okC or type(canvas) ~= "table" then return nil end
        local title = type(spec.title) == "string" and spec.title or "Add-on"
        canvas.name = title
        local category, route
        if type(S) == "table" and type(S.RegisterCanvasLayoutCategory) == "function"
            and type(S.RegisterAddOnCategory) == "function" then
            local ok, cat = call(S.RegisterCanvasLayoutCategory, canvas, title)
            if ok and cat ~= nil then
                category, route = cat, "settings"
                call(S.RegisterAddOnCategory, cat)
            end
        end
        if not route and type(env.InterfaceOptions_AddCategory) == "function" then
            if call(env.InterfaceOptions_AddCategory, canvas) then route = "interface" end
        end
        if not route then return nil end

        local h, showFns, built = {}, {}, nil
        local function build()
            if built then return built end
            local b = { checks = {}, buttons = {}, labels = {}, edits = {}, sliders = {}, n = {} }
            local okS, scroll = call(env.CreateFrame, "ScrollFrame", nil, canvas, "UIPanelScrollFrameTemplate")
            if not okS or type(scroll) ~= "table" then return nil end
            method(scroll, "SetPoint", "TOPLEFT", canvas, "TOPLEFT", 0, -40)
            method(scroll, "SetPoint", "BOTTOMRIGHT", canvas, "BOTTOMRIGHT", -28, 4)
            local okF, body = call(env.CreateFrame, "Frame", nil, scroll)
            if not okF or type(body) ~= "table" then return nil end
            method(body, "SetSize", 560, 400)
            method(scroll, "SetScrollChild", body)
            local okT, head = method(canvas, "CreateFontString", nil, "OVERLAY", "GameFontNormalLarge")
            if okT and head then
                method(head, "SetPoint", "TOPLEFT", canvas, "TOPLEFT", 16, -12)
                method(head, "SetText", title)
            end
            local okSt, status = method(canvas, "CreateFontString", nil, "OVERLAY", "GameFontHighlightSmall")
            if okSt and status then method(status, "SetPoint", "TOPLEFT", canvas, "TOPLEFT", 16, -30) end
            b.body, b.status = body, (okSt and status) or nil
            built = b
            return b
        end
        -- One widget of a kind from the page's pool, made when the pool is short.
        local function take(b, kind, make)
            b.n[kind] = (b.n[kind] or 0) + 1
            local list = b[kind]
            local w = list[b.n[kind]]
            if w == nil then
                w = make() or false
                list[b.n[kind]] = w
            end
            if not w then return nil end
            method(w, "ClearAllPoints")
            method(w, "Show")
            return w
        end
        local function label(b, text, x, y, font)
            local fs = take(b, "labels", function()
                local ok, f = method(b.body, "CreateFontString", nil, "OVERLAY", font or "GameFontHighlight")
                return ok and f or nil
            end)
            if fs then
                method(fs, "SetPoint", "TOPLEFT", b.body, "TOPLEFT", x, y)
                method(fs, "SetText", text)
            end
            return fs
        end
        local function button(b, text, x, y, width, onClick, on, enabled)
            local w = take(b, "buttons", function()
                local ok, f = call(env.CreateFrame, "Button", nil, b.body, "UIPanelButtonTemplate")
                return ok and f or nil
            end)
            if not w then return nil end
            method(w, "SetSize", width, 20)
            method(w, "SetPoint", "TOPLEFT", b.body, "TOPLEFT", x, y)
            method(w, "SetText", on and ("[" .. text .. "]") or text)
            if enabled then method(w, "Enable") else method(w, "Disable") end
            method(w, "SetScript", "OnClick", function() onClick() end)
            return w
        end

        -- A slider row (row N57, lead section 249): a Slider frame made from
        -- plain parts, as legacy Flow's page made its own on this client
        -- (Modules/Settings.lua slider: no game template, since which slider
        -- templates a client has varies). -> true when it was drawn; false,
        -- with nothing drawn, when the row has no two limits or the client
        -- gives no Slider frame or one without a slider's calls: the caller
        -- then draws the minus and plus stepper.
        -- Dragging moves the value shown beside it; changed(key, value) is
        -- told once, when the mouse button is let go, with the value put on
        -- the row's step and inside its limits. Setting it from a draw
        -- tells nothing. First guesses, not seen in game: Slider
        -- SetOrientation, SetThumbTexture, GetThumbTexture, SetMinMaxValues,
        -- SetValueStep, SetObeyStepOnDrag, SetValue, OnValueChanged (self,
        -- value) and OnMouseUp, as legacy used them.
        local function sliderRow(b, r, text, key, can, y, changed)
            if type(r.min) ~= "number" or type(r.max) ~= "number" or type(r.value) ~= "number" then return false end
            if r.max <= r.min or r.max ~= r.max or r.min ~= r.min then return false end
            local step = 1
            if type(r.step) == "number" and r.step > 0 then step = r.step end
            local w = take(b, "sliders", function()
                local ok, f = call(env.CreateFrame, "Slider", nil, b.body)
                if not ok or f == nil then return nil end
                if not method(f, "SetOrientation", "HORIZONTAL") then return nil end
                if not method(f, "SetThumbTexture", "Interface\\Buttons\\WHITE8X8") then return nil end
                method(f, "EnableMouse", true)
                local okT, track = method(f, "CreateTexture", nil, "BACKGROUND")
                if okT and track ~= nil then
                    method(track, "SetPoint", "LEFT", f, "LEFT", 0, 0)
                    method(track, "SetPoint", "RIGHT", f, "RIGHT", 0, 0)
                    method(track, "SetHeight", 4)
                    method(track, "SetColorTexture", 1, 1, 1, 0.2)
                end
                local okG, thumb = method(f, "GetThumbTexture")
                if okG and thumb ~= nil then
                    method(thumb, "SetSize", 8, 18)
                    method(thumb, "SetVertexColor", 1, 0.82, 0.25, 1)
                end
                return f
            end)
            if not w then return false end
            -- The last draw's script is taken off first: setting the value
            -- below must not write into a label that row no longer has.
            method(w, "SetScript", "OnValueChanged", nil)
            method(w, "SetScript", "OnMouseUp", nil)
            if not (method(w, "SetMinMaxValues", r.min, r.max) and method(w, "SetValueStep", step)
                and method(w, "SetValue", r.value)) then
                method(w, "Hide")
                return false
            end
            method(w, "SetObeyStepOnDrag", true)
            method(w, "SetSize", 150, 18)
            method(w, "SetPoint", "TOPLEFT", b.body, "TOPLEFT", 220, y - 2)
            if can then method(w, "Enable") else method(w, "Disable") end
            label(b, text, 16, y - 2)
            local shownValue = label(b, tostring(r.value), 378, y - 2)
            local pending = r.value
            method(w, "SetScript", "OnValueChanged", function(_, v)
                if type(v) ~= "number" or hidden(v) or v ~= v then return end
                v = r.min + math.floor((v - r.min) / step + 0.5) * step
                if v < r.min then v = r.min end
                if v > r.max then v = r.max end
                v = math.floor(v * 1000000 + 0.5) / 1000000
                pending = v
                if shownValue then method(shownValue, "SetText", tostring(v)) end
            end)
            method(w, "SetScript", "OnMouseUp", function()
                if not can or pending == r.value then return end
                changed(key, pending)
            end)
            return true
        end

        -- Topics and search (lead sections 238, 239). nav(kind, value) is told
        -- "topic" and its id, or "search" and the typed text ("" for Clear);
        -- it changes no setting. More row kinds:
        --   { kind = "search", label, value, clear }   an edit box and Clear
        --   { kind = "topics", topics = { { id, name, on }, ... } }
        --                                    a button each, wrapped in lines
        --   { kind = "section", text }, { kind = "note", text }   one line
        --   { kind = "slider", key, label, value, min, max, step, settable, why }
        --                                    sliderRow above, else the stepper
        --   { kind = "actions", actions = { { key, label }, ... } }
        --                                    a button each; a press asks
        --                                    nav("action", key), never act
        -- and on a setting row: under (a small line below it), jump and
        -- jumpText (a button on that line that asks nav for topic `jump`),
        -- help (the row's description, small, wrapped, below those).
        -- First guesses as the rest of the page: not seen in game.
        function h.draw(rows, act, nav)
            local b = build()
            if not b then return false end
            for _, kind in ipairs({ "checks", "buttons", "labels", "edits", "sliders" }) do
                for _, w in ipairs(b[kind]) do if w then method(w, "Hide") end end
                b.n[kind] = 0
            end
            local y = -4
            local function changed(key, value)
                if type(act) == "function" then pcall(act, key, value) end
            end
            for _, r in ipairs(type(rows) == "table" and rows or {}) do
                if r.kind == "group" then
                    y = y - 8
                    label(b, tostring(r.text or ""), 8, y, "GameFontNormal")
                    y = y - 22
                elseif r.kind == "section" or r.kind == "note" then
                    label(b, tostring(r.text or ""), 12, y - 2,
                        r.kind == "section" and "GameFontNormalSmall" or "GameFontHighlightSmall")
                    y = y - 18
                elseif r.kind == "search" then
                    label(b, tostring(r.label or ""), 16, y - 2)
                    local typedNow = type(r.value) == "string" and r.value or ""
                    local w = take(b, "edits", function()
                        local ok, f = call(env.CreateFrame, "EditBox", nil, b.body, "InputBoxTemplate")
                        return ok and f or nil
                    end)
                    if w then
                        method(w, "SetSize", 220, 20)
                        method(w, "SetPoint", "TOPLEFT", b.body, "TOPLEFT", 96, y)
                        method(w, "SetAutoFocus", false)
                        method(w, "SetText", typedNow)
                        method(w, "Enable")
                        method(w, "SetScript", "OnEnterPressed", function(self)
                            local okT, typed = method(self, "GetText")
                            method(self, "ClearFocus")
                            if okT and type(typed) == "string" and type(nav) == "function" then
                                pcall(nav, "search", typed)
                            end
                        end)
                        method(w, "SetScript", "OnEscapePressed", function(self) method(self, "ClearFocus") end)
                    end
                    button(b, tostring(r.clear or "x"), 324, y, 60, function()
                        if type(nav) == "function" then pcall(nav, "search", "") end
                    end, false, typedNow ~= "")
                    y = y - 28
                elseif r.kind == "topics" then
                    local x = 8
                    for _, topic in ipairs(type(r.topics) == "table" and r.topics or {}) do
                        local id, name = topic.id, tostring(topic.name or topic.id or "")
                        local width = 20 + 6 * #name
                        if x > 8 and x + width > 552 then x, y = 8, y - 22 end
                        button(b, name, x, y, width, function()
                            if type(nav) == "function" then pcall(nav, "topic", id) end
                        end, topic.on == true, true)
                        x = x + width + 4
                    end
                    y = y - 28
                elseif r.kind == "actions" then
                    -- Added for the key rows (UI/SettingsKeys.lua), all
                    -- optional: label (and shown) as a line above the
                    -- buttons, an action's enabled = false greys it, and
                    -- why stands after the buttons.
                    if type(r.label) == "string" then
                        local line = r.label
                        if r.shown ~= nil then line = line .. ": " .. tostring(r.shown) end
                        label(b, line, 16, y - 2)
                        y = y - 20
                    end
                    local x = 8
                    for _, action in ipairs(type(r.actions) == "table" and r.actions or {}) do
                        local name, words = action.key, tostring(action.label or action.key or "")
                        local width = 20 + 6 * #words
                        button(b, words, x, y, width, function()
                            if type(nav) == "function" then pcall(nav, "action", name) end
                        end, false, action.enabled ~= false)
                        x = x + width + 8
                    end
                    if type(r.why) == "string" and r.why ~= "" then
                        label(b, r.why, x, y - 2, "GameFontDisableSmall")
                    end
                    y = y - 28
                else
                    local text = tostring(r.label or r.key or "")
                    local can = r.settable == true
                    local key = r.key
                    if r.kind == "toggle" then
                        local w = take(b, "checks", function()
                            local ok, f = call(env.CreateFrame, "CheckButton", nil, b.body, "UICheckButtonTemplate")
                            return ok and f or nil
                        end)
                        if w then
                            method(w, "SetSize", 24, 24)
                            method(w, "SetPoint", "TOPLEFT", b.body, "TOPLEFT", 12, y + 3)
                            method(w, "SetChecked", r.value == true)
                            if can then method(w, "Enable") else method(w, "Disable") end
                            method(w, "SetScript", "OnClick", function(self)
                                local okG, on = method(self, "GetChecked")
                                changed(key, (okG and on) and true or false)
                            end)
                        end
                        label(b, text, 40, y - 2)
                    elseif r.kind == "choice" then
                        label(b, text, 16, y - 2)
                        local x = 220
                        for _, choice in ipairs(type(r.choices) == "table" and r.choices or {}) do
                            local value = choice
                            local width = 16 + 7 * #tostring(choice)
                            button(b, tostring(choice), x, y, width, function() changed(key, value) end,
                                choice == r.value, can)
                            x = x + width + 4
                        end
                    elseif r.kind == "slider" and sliderRow(b, r, text, key, can, y, changed) then
                        -- Drawn as a slider. One that could not be made
                        -- falls through to the stepper below.
                    elseif r.kind == "number" or r.kind == "slider" then
                        label(b, text, 16, y - 2)
                        local step = (type(r.step) == "number" and r.step > 0) and r.step or 1
                        local value = type(r.value) == "number" and r.value or nil
                        local lower = value ~= nil and (type(r.min) ~= "number" or value - step >= r.min)
                        local higher = value ~= nil and (type(r.max) ~= "number" or value + step <= r.max)
                        button(b, "-", 220, y, 24, function() changed(key, value - step) end, false, can and lower)
                        label(b, value and tostring(value) or "not set", 250, y - 2)
                        button(b, "+", 300, y, 24, function() changed(key, value + step) end, false, can and higher)
                    elseif r.kind == "text" then
                        label(b, text, 16, y - 2)
                        local w = take(b, "edits", function()
                            local ok, f = call(env.CreateFrame, "EditBox", nil, b.body, "InputBoxTemplate")
                            return ok and f or nil
                        end)
                        if w then
                            method(w, "SetSize", 180, 20)
                            method(w, "SetPoint", "TOPLEFT", b.body, "TOPLEFT", 224, y)
                            method(w, "SetAutoFocus", false)
                            method(w, "SetText", type(r.value) == "string" and r.value or "")
                            if can then method(w, "Enable") else method(w, "Disable") end
                            method(w, "SetScript", "OnEnterPressed", function(self)
                                local okT, typed = method(self, "GetText")
                                method(self, "ClearFocus")
                                if okT and type(typed) == "string" then changed(key, typed) end
                            end)
                            method(w, "SetScript", "OnEscapePressed", function(self) method(self, "ClearFocus") end)
                        else
                            label(b, tostring(r.value or ""), 224, y - 2)
                        end
                    else
                        label(b, text .. ": " .. tostring(r.shown or ""), 16, y - 2)
                    end
                    if not can and r.kind ~= "info" and type(r.why) == "string" then
                        label(b, r.why, 420, y - 2, "GameFontDisableSmall")
                    end
                    if type(r.under) == "string" and r.under ~= "" then
                        local ux = 40
                        if r.jump ~= nil then
                            local to = r.jump
                            -- jumpKind "open": the row's own window, not a topic.
                            local how = "topic"
                            if r.jumpKind == "open" then how = "open" end
                            button(b, tostring(r.jumpText or ">"), 40, y - 22, 90, function()
                                if type(nav) == "function" then pcall(nav, how, to) end
                            end, false, true)
                            ux = 136
                        end
                        label(b, r.under, ux, y - 24, "GameFontDisableSmall")
                        y = y - (r.jump ~= nil and 22 or 14)
                    end
                    -- The row's description, wrapped over as many lines as
                    -- its length asks for (a guess at 90 letters a line).
                    if type(r.help) == "string" and r.help ~= "" then
                        local fs = label(b, r.help, 40, y - 24, "GameFontDisableSmall")
                        if fs then
                            method(fs, "SetWidth", 500)
                            method(fs, "SetJustifyH", "LEFT")
                        end
                        y = y - 12 * math.ceil(#r.help / 90) - 2
                    end
                    y = y - 26
                end
            end
            method(b.body, "SetHeight", math.max(40, -y + 10))
            return true
        end
        function h.status(text)
            local b = build()
            if b and b.status then method(b.status, "SetText", type(text) == "string" and text or "") end
        end
        function h.onShow(fn)
            if type(fn) == "function" then showFns[#showFns + 1] = fn end
        end
        function h.shown()
            local ok, on = method(canvas, "IsVisible")
            return ok and on == true
        end
        method(canvas, "SetScript", "OnShow", function()
            for _, fn in ipairs({ unpack(showFns) }) do pcall(fn) end
        end)
        function h.open()
            if route == "settings" and type(S.OpenToCategory) == "function" then
                local id = category
                if type(category) == "table" and type(category.GetID) == "function" then
                    local okId, got = pcall(category.GetID, category)
                    if okId and got ~= nil then id = got end
                end
                return (call(S.OpenToCategory, id))
            end
            if route == "interface" and type(env.InterfaceOptionsFrame_OpenToCategory) == "function" then
                local ok = call(env.InterfaceOptionsFrame_OpenToCategory, canvas)
                call(env.InterfaceOptionsFrame_OpenToCategory, canvas)
                return ok
            end
            return false
        end
        return h
    end

    ---------------------------------------------------------------------
    -- S28 sound restart (Plexy, LEDGER 143; WoW/from-plexy/
    -- RESEARCH-sound-restart.md). Ported from legacy Flow's Modules/Sound.lua,
    -- which ran on this client: Sound_GameSystem_RestartSoundSystem, and
    -- ConsoleExec("Sound_RestartSoundSystem") only when the player asked by
    -- hand (a console the game keeps for itself gives one "blocked" message
    -- the player asked for, never one each time the screen sleeps); the
    -- SOUND_DEVICE_UPDATE event when the speakers change. Not seen by Z-Flow
    -- in game: needs a game test.
    --
    --   c.soundWays(byHand) -> { name, ... }   the ways this client offers
    --   c.restartSound(byHand) -> true, how | false, why
    --   c.watchSoundDevices(fn) -> true when the client takes the event, else
    --     nil; fn() each time the game says its list of speakers changed
    local function soundWays(byHand)
        local out = {}
        if type(env.Sound_GameSystem_RestartSoundSystem) == "function" then
            out[#out + 1] = { name = "Sound_GameSystem_RestartSoundSystem", fn = env.Sound_GameSystem_RestartSoundSystem }
        end
        if byHand and type(env.ConsoleExec) == "function" then
            local exec = env.ConsoleExec
            out[#out + 1] = { name = "the console's Sound_RestartSoundSystem",
                fn = function() return exec("Sound_RestartSoundSystem") end }
        end
        return out
    end
    function c.soundWays(byHand)
        local names = {}
        for i, w in ipairs(soundWays(byHand)) do names[i] = w.name end
        return names
    end
    function c.restartSound(byHand)
        local tried = {}
        for _, w in ipairs(soundWays(byHand)) do
            local ok, err = pcall(w.fn)
            if ok then return true, w.name end
            tried[#tried + 1] = w.name .. ": " .. tostring(err)
        end
        if #tried > 0 then return false, table.concat(tried, "; ") end
        return false, "this game gives add-ons no way to restart its sound"
    end
    function c.watchSoundDevices(fn)
        if type(fn) ~= "function" then return nil end
        local cancel = events.add("SOUND_DEVICE_UPDATE", function() pcall(fn) end)
        if unregistered["SOUND_DEVICE_UPDATE"] then
            cancel()
            return nil
        end
        return true
    end

    -- F7 probe (Plexy, LEDGER 134; WoW/from-plexy/RESEARCH-fight-log.md): two
    -- narrow reads for /zflow fights probe, so one game session settles what
    -- this client gives the fight log instead of the combat log.
    --   c.apiPresent(path) -> true / false: whether the dotted global path
    --     ("C_DamageMeter", "C_DeathRecap.GetRecapEvents") names a function or
    --     a table. It only looks; nothing is called.
    --   c.watchUnitCombat(fn) -> cancel: fn(unit, readable) for each UNIT_COMBAT
    --     event; unit nil when secret or not text; readable true only for an
    --     amount that is a plain, non-secret number. The amount itself is not
    --     handed on. UNIT_COMBAT is an event legacy Flow listened to on this
    --     client (Modules/Rotation/Engine.lua); its payload is a first guess.
    function c.apiPresent(path)
        if type(path) ~= "string" or path == "" then return false end
        local v = env
        for part in path:gmatch("[^%.]+") do
            if type(v) ~= "table" then return false end
            local ok, nextV = pcall(function() return v[part] end)
            if not ok then return false end
            v = nextV
        end
        return type(v) == "function" or type(v) == "table"
    end
    function c.watchUnitCombat(fn)
        if type(fn) ~= "function" then return nil end
        return events.add("UNIT_COMBAT", function(unit, _, _, amount)
            local who = (type(unit) == "string" and not hidden(unit)) and unit or nil
            local readable = amount ~= nil and not hidden(amount) and type(amount) == "number" and amount == amount
            pcall(fn, who, readable)
        end)
    end

    -- S29 alignment guides (UI/MoveGuides.lua). New reads, added at the end
    -- (lead section 150): no handle above is changed. They find a frame of ours by
    -- the name its handle gave it, and work in UIParent's units (a frame's
    -- own sides times its scale over UIParent's).
    -- Docs (warcraft.wiki.gg): API hooksecurefunc([table,] name, hook), the
    -- hook runs after the original with its arguments; ScriptRegion GetLeft,
    -- GetRight, GetBottom, GetTop, IsVisible; Region GetEffectiveScale;
    -- Region GetPoint(index) -> point, relativeTo, relativePoint, x, y.
    -- First guesses, none seen in game on 16001.
    local function guideScale(f)
        local okS, s = method(f, "GetEffectiveScale")
        local okU, u = method(env.UIParent, "GetEffectiveScale")
        if okS and okU and type(s) == "number" and type(u) == "number" and s > 0 and u > 0 then return s / u end
        return nil
    end
    local function guideFrame(name)
        if type(name) ~= "string" or name == "" then return nil end
        local okG, f = pcall(function() return env[name] end)
        if okG and type(f) == "table" then return f end
        return nil
    end
    local GUIDE_SIDES = { { "l", "GetLeft" }, { "r", "GetRight" }, { "b", "GetBottom" }, { "t", "GetTop" } }

    -- Our named frame's rectangle: { l =, r =, b =, t =, dockedTo = the name
    -- of the frame it hangs from, or nil }. nil when there is no such frame,
    -- it is not on the screen, or a side is not read.
    function c.frameRect(name)
        local f = guideFrame(name)
        if not f then return nil end
        local okV, shown = method(f, "IsVisible")
        if not okV or shown ~= true then return nil end
        local s = guideScale(f)
        if not s then return nil end
        local out = {}
        for _, side in ipairs(GUIDE_SIDES) do
            local okR, v = method(f, side[2])
            if not okR or hidden(v) or type(v) ~= "number" or v ~= v then return nil end
            out[side[1]] = v * s
        end
        local okP, _, rel = method(f, "GetPoint", 1)
        if okP and type(rel) == "table" and rel ~= env.UIParent then
            local okN, relName = method(rel, "GetName")
            if okN and type(relName) == "string" then out.dockedTo = relName end
        end
        return out
    end

    -- Told when the player moves our named frame: its own StartMoving and
    -- StopMovingOrSizing are hooked (after them), so the handle that moves
    -- it is not changed. onMove(rect) every frame while it moves. onDrop(rect)
    -- when it is let go, inside StopMovingOrSizing, so before the handle
    -- reads the place it saves: onDrop answers dx, dy and the frame is
    -- shifted by them, so the place saved is the lined-up one. A frame let
    -- go while hidden is not shifted. Watching a name again replaces its
    -- callbacks. true when watched; nil with no such frame or no hook.
    local guideWatch, guideMoving, guideTicker = {}, nil, nil
    function c.watchMoves(name, onMove, onDrop)
        local f = guideFrame(name)
        if not f or type(env.hooksecurefunc) ~= "function" then return nil end
        if guideWatch[name] then
            guideWatch[name].onMove, guideWatch[name].onDrop = onMove, onDrop
            return true
        end
        if not guideTicker then
            local okF, w = call(env.CreateFrame, "Frame", nil, env.UIParent)
            if not okF or w == nil then return nil end
            guideTicker = w
            method(w, "Hide")
            method(w, "SetScript", "OnUpdate", function()
                local m = guideMoving and guideWatch[guideMoving]
                if not m then method(w, "Hide") return end
                local r = c.frameRect(guideMoving)
                if r and type(m.onMove) == "function" then pcall(m.onMove, r) end
            end)
        end
        local watch = { onMove = onMove, onDrop = onDrop }
        local okA = pcall(env.hooksecurefunc, f, "StartMoving", function()
            guideMoving = name
            method(guideTicker, "Show")
        end)
        if not okA then return nil end
        local okB = pcall(env.hooksecurefunc, f, "StopMovingOrSizing", function()
            if guideMoving ~= name then return end
            guideMoving = nil
            method(guideTicker, "Hide")
            local r = c.frameRect(name)
            if not r or type(watch.onDrop) ~= "function" then return end
            local okD, dx, dy = pcall(watch.onDrop, r)
            if not okD then return end
            dx, dy = tonumber(dx) or 0, tonumber(dy) or 0
            if dx == 0 and dy == 0 then return end
            local s = guideScale(f)
            local okP, a, rel, ra, x, y = method(f, "GetPoint", 1)
            if not (s and okP and type(a) == "string" and type(x) == "number" and type(y) == "number") then return end
            method(f, "ClearAllPoints")
            method(f, "SetPoint", a, rel, ra, x + dx / s, y + dy / s)
        end)
        if not okB then return nil end
        guideWatch[name] = watch
        return true
    end

    -- Two thin lines of ours over the screen, in UIParent's units:
    --   h.show(x, ylo, yhi, y, xlo, xhi)   a line up at x from ylo to yhi and
    --                                      one across at y from xlo to xhi;
    --                                      either is left out when its x or y is nil
    --   h.hide()
    -- They take no clicks. nil when the client gives no frame.
    function c.guideLines()
        local okF, f = call(env.CreateFrame, "Frame", nil, env.UIParent)
        if not okF or f == nil then return nil end
        method(f, "SetAllPoints", env.UIParent)
        method(f, "SetFrameStrata", "TOOLTIP")
        method(f, "EnableMouse", false)
        local function line()
            local okT, t = method(f, "CreateTexture", nil, "OVERLAY")
            if not okT or t == nil then return nil end
            method(t, "SetColorTexture", 1, 0.82, 0, 0.9)
            method(t, "Hide")
            return t
        end
        local up, across = line(), line()
        local function put(t, x, y, w, hgt)
            if t == nil then return end
            if x == nil then method(t, "Hide") return end
            method(t, "ClearAllPoints")
            method(t, "SetPoint", "BOTTOMLEFT", f, "BOTTOMLEFT", x, y)
            method(t, "SetSize", w, hgt)
            method(t, "Show")
        end
        local h = {}
        function h.show(x, ylo, yhi, y, xlo, xhi)
            if type(x) == "number" and type(ylo) == "number" and type(yhi) == "number" then
                put(up, x - 0.5, ylo, 1, math.max(1, yhi - ylo))
            else
                put(up, nil)
            end
            if type(y) == "number" and type(xlo) == "number" and type(xhi) == "number" then
                put(across, xlo, y - 0.5, math.max(1, xhi - xlo), 1)
            else
                put(across, nil)
            end
            method(f, "Show")
        end
        function h.hide() method(f, "Hide") end
        method(f, "Hide")
        return h
    end
    -- S20 marks on the merchant window's own item buttons, as legacy Flow's
    -- Modules/Gear/MerchantMarks.lua drew them: a texture of ours on each
    -- button (nothing of the window is called), the window's redraw followed
    -- with hooksecurefunc. New reads, added at the end (lead section 150).
    -- First guesses, none seen in game on 16001: MerchantItem<i>ItemButton,
    -- MerchantFrame.page and .selectedTab, MERCHANT_ITEMS_PER_PAGE,
    -- MerchantFrame_Update, the atlas "bags-greenarrow" (else the pet
    -- battle "strong" badge, a green arrow up).
    -- Docs (warcraft.wiki.gg): API hooksecurefunc; Texture SetAtlas; Region
    -- CreateTexture(name, layer, template, sublevel).
    local MERCHANT_BUTTONS = 12 -- 10 on sale a page, 12 on the buyback tab
    local merchantBadges = {}
    local function merchantBadge(i)
        if merchantBadges[i] ~= nil then return merchantBadges[i] or nil end
        local okB, b = pcall(function() return env["MerchantItem" .. i .. "ItemButton"] end)
        if not okB or type(b) ~= "table" then return nil end -- not kept: it may come later
        local okT, t = method(b, "CreateTexture", nil, "OVERLAY", nil, 7)
        if not okT or t == nil then
            merchantBadges[i] = false
            return nil
        end
        method(t, "SetSize", 14, 14)
        method(t, "SetPoint", "TOPLEFT", b, "TOPLEFT", 1, -1)
        local okA, set = method(t, "SetAtlas", "bags-greenarrow")
        if not okA or set == false then
            method(t, "SetTexture", "Interface\\PetBattles\\BattleBar-AbilityBadge-Strong")
        end
        method(t, "Hide")
        merchantBadges[i] = t
        return t
    end

    -- Marks the items of the merchant page that `indexes` names ({ [the
    -- merchant's item number] = true }) and hides the other marks. None on
    -- the buyback tab. How many it marked, or nil (every mark hidden) when
    -- no merchant window is open or its page cannot be read.
    function c.markMerchantButtons(indexes)
        indexes = type(indexes) == "table" and indexes or {}
        local frame = env.MerchantFrame
        local okP, page = pcall(function() return frame.page end)
        local okT, tab = pcall(function() return frame.selectedTab end)
        local per = env.MERCHANT_ITEMS_PER_PAGE
        local readable = c.merchantOpen() == true and okP and type(page) == "number" and page >= 1
            and type(per) == "number" and per >= 1
        local buyback = okT and tab ~= nil and tab ~= 1
        local n = 0
        for i = 1, MERCHANT_BUTTONS do
            local t = merchantBadge(i)
            if t then
                local index = readable and (page - 1) * per + i or nil
                if readable and not buyback and i <= per and indexes[index] then
                    method(t, "Show")
                    n = n + 1
                else
                    method(t, "Hide")
                end
            end
        end
        if not readable then return nil end
        return n
    end

    -- fn() whenever the merchant window draws itself again (a new page, the
    -- buyback tab): MerchantFrame_Update hooked, else its page buttons and
    -- tabs. true when followed; nil when the client offers neither (asked
    -- again on the next call).
    local merchantRedraw, merchantFollowed = {}, false
    local function merchantTell()
        for _, fn in ipairs({ unpack(merchantRedraw) }) do pcall(fn) end
    end
    function c.onMerchantRedraw(fn)
        if type(fn) ~= "function" then return nil end
        local known = false
        for _, f in ipairs(merchantRedraw) do
            if f == fn then known = true end
        end
        if not known then merchantRedraw[#merchantRedraw + 1] = fn end
        if merchantFollowed then return true end
        if type(env.hooksecurefunc) == "function" and type(env.MerchantFrame_Update) == "function"
            and pcall(env.hooksecurefunc, "MerchantFrame_Update", merchantTell) then
            merchantFollowed = true
            return true
        end
        for _, name in ipairs({ "MerchantNextPageButton", "MerchantPrevPageButton", "MerchantFrameTab1", "MerchantFrameTab2" }) do
            local okN, b = pcall(function() return env[name] end)
            if okN and type(b) == "table" and method(b, "HookScript", "OnClick", merchantTell) then merchantFollowed = true end
        end
        return merchantFollowed or nil
    end

    -- S35 (LEDGER 150/153; WoW/from-zen/RESEARCH-S35.md): the two reads
    -- Nav/Gates.lua needs before it may learn a gate. Both only read.
    --   c.worldPosition() -> { cont, wx, wy }: the continent and the world
    --     position in yards of where the player stands, or nil when the
    --     client gives no map, no position, no world point, or marks any of
    --     it secret. C_Map.GetWorldPosFromMapPos(map, position) is the call
    --     legacy Flow's N:PlayerPos uses (Modules/Nav/Nav.lua:40-52), asked
    --     with the client's own position value; a first guess on 16001.
    --   c.onTaxi() -> true / false, or nil when the client gives no plain
    --     yes or no. UnitOnTaxi("player") is the call legacy Flow uses
    --     (Modules/Nav/Nav.lua:4688); a first guess on 16001. nil is "not
    --     known", never "not on a taxi": Gates learns only on a plain false.
    function c.worldPosition()
        local map, _, _, pos = playerPoint()
        if not map then return nil end
        local ok, cont, world = mapCall("GetWorldPosFromMapPos", map, pos)
        if not ok or type(world) ~= "table" then return nil end
        if type(cont) ~= "number" or hidden(cont) then return nil end
        local okXY, wx, wy = call(world.GetXY, world)
        if not okXY then wx, wy = world.x, world.y end
        if type(wx) ~= "number" or type(wy) ~= "number" then return nil end
        if hidden(wx) or hidden(wy) then return nil end
        if wx ~= wx or wy ~= wy then return nil end
        return { cont = cont, wx = wx, wy = wy }
    end
    function c.onTaxi()
        return flag(call(env.UnitOnTaxi, "player"))
    end
    -- Whether a slash command already belongs to someone else.
    --   c.slashTaken(command, ownTag) -> true when a tag other than ownTag
    --     lists the command (any case) or the client has already looked it
    --     up for another handler; false when it is free or ownTag's; nil
    --     when there is no slash table to read (unknown, not free).
    --   c.unslash(tag) -> true when the tag held a command and it was given
    --     back; false when there was nothing to give back.
    -- Legacy Flow asked the same before claiming "/way"
    -- (Modules/Nav/Waypoint.lua:260-262: SlashCmdList.TOMTOM_WAY or
    -- hash_SlashCmdList["/WAY"]). Reading every tag's SLASH_<tag><n> texts
    -- is the general form of that; needs game test.
    function c.slashTaken(command, ownTag)
        local list = env.SlashCmdList
        if type(list) ~= "table" or type(command) ~= "string" or command == "" then return nil end
        local hash = env.hash_SlashCmdList
        if type(hash) == "table" then
            local held = hash[command:upper()]
            if held ~= nil and (ownTag == nil or held ~= list[ownTag]) then return true end
        end
        local want = command:lower()
        for tag in pairs(list) do
            if tag ~= ownTag and type(tag) == "string" then
                for n = 1, 20 do
                    local text = env["SLASH_" .. tag .. n]
                    if type(text) ~= "string" then break end
                    if text:lower() == want then return true end
                end
            end
        end
        return false
    end
    function c.unslash(tag)
        local list = env.SlashCmdList
        if type(list) ~= "table" or type(tag) ~= "string" or list[tag] == nil then return false end
        local fn, text = list[tag], env["SLASH_" .. tag .. "1"]
        local hash = env.hash_SlashCmdList
        if type(hash) == "table" and type(text) == "string" and hash[text:upper()] == fn then
            hash[text:upper()] = nil
        end
        list[tag] = nil
        env["SLASH_" .. tag .. "1"] = nil
        return true
    end
    -- S4 auction prices, read passively (L6-F option A): only the answers to
    -- searches the player runs in the auction window. Nothing here sends a
    -- search, posts, bids or buys. New reads, added at the end (lead
    -- section 150). First guesses, none seen in game on 16001 (legacy Flow
    -- 0.35.202: "This client only has the newer auction house"):
    -- GetRealmName; events COMMODITY_SEARCH_RESULTS_UPDATED(itemID) and
    -- ITEM_SEARCH_RESULTS_UPDATED(itemKey); C_AuctionHouse
    -- GetCommoditySearchResultInfo(itemID, 1) and GetItemSearchResultInfo(
    -- itemKey, 1) answering a table (unitPrice, buyoutAmount, quantity).
    -- Docs (warcraft.wiki.gg): the same names and fields. `/zflow auction
    -- probe` (Items/AuctionLog.lua) says which of them this client has.

    -- The realm's name, or nil.
    function c.realm()
        local ok, name = call(env.GetRealmName)
        if ok and not hidden(name) and type(name) == "string" and name ~= "" then return name end
        return nil
    end

    -- fn(itemID, row) for the cheapest row (PA1, below) of each search the player runs:
    -- row = { unitPrice =, buyoutAmount =, quantity = }, each a number or
    -- nil. Rows that cannot be read are not told. true when followed; nil
    -- when the client has neither result read (no event is then asked for).
    local auctionFns, auctionFollowed = {}, false
    -- One delivered row, its numbers only, or nil.
    local function auctionRowAt(read, what, i)
        local house = env.C_AuctionHouse
        if type(house) ~= "table" then return nil end
        local ok, row = call(house[read], what, i)
        if not ok or type(row) ~= "table" then return nil end
        local out = {}
        for _, f in ipairs({ "unitPrice", "buyoutAmount", "quantity" }) do
            local okF, v = pcall(function() return row[f] end)
            if okF and not hidden(v) and type(v) == "number" and v == v then out[f] = v end
        end
        return out
    end
    -- The price for one a row asks (legacy Flow's AH.UnitFrom), or nil.
    local function auctionUnit(row)
        if type(row) ~= "table" then return nil end
        if type(row.unitPrice) == "number" and row.unitPrice > 0 then return row.unitPrice end
        local n = row.quantity or 1
        if type(row.buyoutAmount) == "number" and row.buyoutAmount > 0 and type(n) == "number" and n > 0 then
            return row.buyoutAmount / n
        end
        return nil
    end
    -- PA1 (lead section 164): the row with the lowest price for one among
    -- the rows the client has already delivered for this search, read up to
    -- AUCTION_ROWS of them; row 1 alone when the client will not say how
    -- many. No further rows are asked of the server.
    -- Docs (warcraft.wiki.gg): C_AuctionHouse.GetNumCommoditySearchResults(
    -- itemID) and GetNumItemSearchResults(itemKey) -> the rows received.
    local AUCTION_ROWS = 50
    local function auctionRow(read, count, what)
        local house = env.C_AuctionHouse
        if type(house) ~= "table" then return nil end
        local okN, n = call(house[count], what)
        if not okN or hidden(n) or type(n) ~= "number" or n ~= n or n < 1 then n = 1 end
        n = math.min(math.floor(n), AUCTION_ROWS)
        local best, bestUnit = nil, nil
        for i = 1, n do
            local row = auctionRowAt(read, what, i)
            local unit = auctionUnit(row)
            if unit and (bestUnit == nil or unit < bestUnit) then best, bestUnit = row, unit end
        end
        return best
    end
    local function auctionTell(id, row)
        if type(id) ~= "number" or row == nil then return end
        for _, fn in ipairs({ unpack(auctionFns) }) do pcall(fn, id, row) end
    end
    function c.watchAuctionResults(fn)
        if type(fn) ~= "function" then return nil end
        auctionFns[#auctionFns + 1] = fn
        if auctionFollowed then return true end
        local house = env.C_AuctionHouse
        if type(house) ~= "table" then return nil end
        if type(house.GetCommoditySearchResultInfo) == "function" then
            events.add("COMMODITY_SEARCH_RESULTS_UPDATED", function(itemID)
                if hidden(itemID) then return end
                auctionTell(itemID, auctionRow("GetCommoditySearchResultInfo", "GetNumCommoditySearchResults", itemID))
            end)
            auctionFollowed = true
        end
        if type(house.GetItemSearchResultInfo) == "function" then
            events.add("ITEM_SEARCH_RESULTS_UPDATED", function(itemKey)
                if type(itemKey) ~= "table" then return end
                local okI, id = pcall(function() return itemKey.itemID end)
                if not okI or hidden(id) then return end
                auctionTell(id, auctionRow("GetItemSearchResultInfo", "GetNumItemSearchResults", itemKey))
            end)
            auctionFollowed = true
        end
        return auctionFollowed or nil
    end

    -- One small picture with a word over it and a coloured edge (S13, the
    -- modifier queue), or nil when the client cannot make a frame. First
    -- guess, not seen in game.
    --   spec = { name = global frame name or nil, size = n, label = text }
    --   h.setTexture(tex) -> true when the client took it; nil clears the
    --                   picture and answers false.
    --   h.place(point), h.show(on): as the icon's.
    --   h.mark(r, g, b) -> true when an edge was drawn: the edge and the
    --                   word in that colour. h.mark(nil): no edge, the word
    --                   grey; answers false.
    -- It takes no mouse, no click and no drag, and holds no secure action.
    -- The frame calls are the ones the icon and the panel above already
    -- make. Checked against the API pages (see RESEARCH-modifier-queue.md):
    -- a plain Frame takes no mouse unless asked, so EnableMouse(false) only
    -- says so; BACKGROUND draws behind ARTWORK, OVERLAY in front; a flat
    -- colour is SetColorTexture since 7.0.3 and was SetTexture(r, g, b, a)
    -- before it, so both are tried.
    function c.slotIcon(spec)
        spec = type(spec) == "table" and spec or {}
        local parent = env.UIParent
        local ok, f = call(env.CreateFrame, "Frame", spec.name, parent)
        if not ok or f == nil then return nil end
        local h = {}
        local size = tonumber(spec.size) or 30

        method(f, "Hide")
        if not method(f, "SetSize", size, size) then
            method(f, "SetWidth", size)
            method(f, "SetHeight", size)
        end
        method(f, "SetFrameStrata", "MEDIUM")
        method(f, "EnableMouse", false)

        -- The edge: a flat square two wider all round, behind the picture.
        local okRing, ring = method(f, "CreateTexture", nil, "BACKGROUND")
        if not okRing then ring = nil end
        if ring ~= nil then
            method(ring, "SetPoint", "TOPLEFT", f, "TOPLEFT", -2, 2)
            method(ring, "SetPoint", "BOTTOMRIGHT", f, "BOTTOMRIGHT", 2, -2)
            method(ring, "Hide")
        end

        local okTex, tex = method(f, "CreateTexture", nil, "ARTWORK")
        if not okTex then tex = nil end
        if tex ~= nil then method(tex, "SetAllPoints", f) end

        local okText, text = method(f, "CreateFontString", nil, "OVERLAY", "GameFontNormalSmall")
        if not okText then text = nil end
        if text ~= nil then
            method(text, "SetPoint", "BOTTOM", f, "TOP", 0, 2)
            method(text, "SetText", type(spec.label) == "string" and spec.label or "")
            method(text, "SetTextColor", 0.85, 0.85, 0.85)
        end

        function h.setTexture(value)
            if tex == nil then return false end
            local okSet = method(tex, "SetTexture", value)
            return okSet and value ~= nil
        end
        function h.place(point)
            if type(point) ~= "table" then return end
            method(f, "ClearAllPoints")
            method(f, "SetPoint", point[1], parent, point[2], point[3], point[4])
        end
        function h.show(on)
            method(f, on and "Show" or "Hide")
        end
        function h.mark(r, g, b)
            if type(r) == "number" and type(g) == "number" and type(b) == "number" then
                if text ~= nil then method(text, "SetTextColor", r, g, b) end
                if ring == nil then return false end
                if not method(ring, "SetColorTexture", r, g, b, 1) then method(ring, "SetTexture", r, g, b, 1) end
                method(ring, "Show")
                return true
            end
            if ring ~= nil then method(ring, "Hide") end
            if text ~= nil then method(text, "SetTextColor", 0.85, 0.85, 0.85) end
            return false
        end
        return h
    end

    -- Which modifier keys are down now: ctrl, shift, alt, each true or false,
    -- or nil for one the client has no read for or whose read raised (not
    -- known, never "up"). A read only: nothing is bound or pressed. Not seen
    -- in game. The API page gives a boolean answer; 1 is also taken as down
    -- in case this client answers the old way (not confirmed either way),
    -- so a nil from a read that ran is "up". Flow 0.35.377 uses all three
    -- as plain truth tests (Modules/BindMode.lua).
    function c.modifiers()
        local function down(fn)
            if type(fn) ~= "function" then return nil end
            local ok, v = pcall(fn)
            if not ok then return nil end
            return v == true or v == 1
        end
        return down(env.IsControlKeyDown), down(env.IsShiftKeyDown), down(env.IsAltKeyDown)
    end

    -- ---------------------------------------------------------------- S17
    -- Group buff tooltip (owner Twin): the unit tooltip hook and two reads of
    -- the unit it shows. Every call here is a first guess, not seen in game
    -- on this client: needs a game test. Reads only, of the hovered unit:
    -- nothing targets, casts or clicks, and no health, power amount, name or
    -- GUID is read.
    --
    -- Told each time the game's own tooltip has been filled for a unit:
    --   client.onUnitTooltip(fn) -> cancel;  fn(unit, add);  add(text, r, g, b)
    -- unit is the token the tooltip gives (GameTooltip:GetUnit, the second
    -- answer). add appends one line of text. fn's errors stay here. The
    -- routes and their order are the item hook's above: the data post call
    -- for unit data first, GameTooltip only; else OnTooltipSetUnit where the
    -- tooltip has that script, once per fill. Neither replaces anything of
    -- the game; a hook cannot be taken back, so cancel only stops fn being
    -- told. nil when the client offers neither. No token, or a secret one:
    -- fn is not told.
    local unitListeners, unitHooked = {}, false
    local function unitFilled(tip)
        if type(tip) ~= "table" or type(tip.GetUnit) ~= "function" then return end
        local ok, _, unit = pcall(tip.GetUnit, tip)
        unit = text(ok, unit)
        if not unit then return end
        local function add(s, r, g, b)
            if type(s) ~= "string" or type(tip.AddLine) ~= "function" then return end
            pcall(tip.AddLine, tip, s, r, g, b)
        end
        for _, fn in ipairs({ unpack(unitListeners) }) do pcall(fn, unit, add) end
    end
    local function hookUnitTooltip()
        if unitHooked then return true end
        local proc, enum = env.TooltipDataProcessor, env.Enum
        local unitData = type(enum) == "table" and type(enum.TooltipDataType) == "table"
            and enum.TooltipDataType.Unit or nil
        if type(proc) == "table" and unitData ~= nil
            and call(proc.AddTooltipPostCall, unitData, function(t2)
                if t2 == env.GameTooltip then unitFilled(t2) end
            end) then
            unitHooked = true
            return true
        end
        local tip = env.GameTooltip
        if type(tip) == "table" and type(tip.HookScript) == "function" then
            local okHas, has = call(tip.HasScript, tip, "OnTooltipSetUnit")
            local filled = false
            if okHas and has == true and call(tip.HookScript, tip, "OnTooltipSetUnit", function(t2)
                if filled then return end
                filled = true
                unitFilled(t2)
            end) then
                call(tip.HookScript, tip, "OnTooltipCleared", function() filled = false end)
                unitHooked = true
                return true
            end
        end
        return false
    end
    function c.onUnitTooltip(fn)
        if type(fn) ~= "function" or not hookUnitTooltip() then return nil end
        unitListeners[#unitListeners + 1] = fn
        return function()
            for i = #unitListeners, 1, -1 do
                if unitListeners[i] == fn then table.remove(unitListeners, i) end
            end
        end
    end

    -- What the client says of a unit, for the tooltip only:
    --   { exists, player, isSelf, friendly, class, role, power }
    -- exists, player, isSelf and friendly are each true, false, or nil when
    -- the read is absent, raised, was hidden or was not a yes or no: never a
    -- guess. class is the class token (UnitClass, second answer), role the
    -- group role as the game names it ("TANK", "HEALER", "DAMAGER", "NONE"),
    -- power the kind of power bar (UnitPowerType, first answer: a number,
    -- never an amount). nil when no unit is asked about.
    function c.unitInfo(unit)
        if type(unit) ~= "string" or unit == "" then return nil end
        local info = {}
        info.exists = yesNo(call(env.UnitExists, unit))
        info.player = yesNo(call(env.UnitIsPlayer, unit))
        info.isSelf = yesNo(call(env.UnitIsUnit, unit, "player"))
        info.friendly = yesNo(call(env.UnitIsFriend, "player", unit))
        local okClass, _, class = call(env.UnitClass, unit)
        info.class = text(okClass, class)
        info.role = text(call(env.UnitGroupRolesAssigned, unit))
        local okPower, power = call(env.UnitPowerType, unit)
        if okPower and power ~= nil and not hidden(power) and type(power) == "number" then
            info.power = power
        end
        return info
    end

    -- Does the unit have one of these buffs?
    --   client.unitBuff(unit, names) -> up, secondsLeft, found
    -- up: true (found, with the name that matched), false (every buff was
    -- read and none is one of the names), nil (not known: no read, a read
    -- that raised, or a row or a name the client hides, met before a match).
    -- secondsLeft: math.huge for a buff with no end, nil when not known.
    -- C_UnitAuras.GetAuraDataByIndex(unit, i, "HELPFUL") where the client has
    -- it, else UnitBuff(unit, i, "HELPFUL") (name first, end time sixth).
    -- At most 40 rows are asked for.
    function c.unitBuff(unit, names)
        if type(unit) ~= "string" or unit == "" or type(names) ~= "table" then return nil end
        local wanted = {}
        for i = 1, #names do
            if type(names[i]) == "string" then wanted[names[i]] = true end
        end
        local auras = env.C_UnitAuras
        local byIndex = type(auras) == "table" and auras.GetAuraDataByIndex or nil
        local old = env.UnitBuff
        if type(byIndex) ~= "function" and type(old) ~= "function" then return nil end
        for i = 1, 40 do
            local name, expires
            if type(byIndex) == "function" then
                local ok, row = pcall(byIndex, unit, i, "HELPFUL")
                if not ok then return nil end
                if row == nil then return false end
                if hidden(row) or type(row) ~= "table" then return nil end
                name, expires = row.name, row.expirationTime
            else
                local got = { pcall(old, unit, i, "HELPFUL") }
                if not got[1] then return nil end
                if got[2] == nil then return false end
                name, expires = got[2], got[7]
            end
            if hidden(name) or type(name) ~= "string" then return nil end
            if wanted[name] then
                if expires == nil or hidden(expires) or type(expires) ~= "number" then return true, nil, name end
                if expires == 0 then return true, math.huge, name end
                return true, expires - c.now(), name
            end
        end
        return false
    end
    -- ------------------------------------------------------------ end S17

    -- S34 trip timing (LEDGER 153/169; WoW/from-zen/RESEARCH-S34.md): are
    -- you mounted. True, false, or nil when not known (no call, a failed
    -- call, a secret answer, or anything but a boolean). It only reads.
    -- Docs (warcraft.wiki.gg, API IsMounted): no argument, a boolean, listed
    -- for 1.60.1. Legacy Flow asks the same (Modules/Nav/Legs.lua:298).
    -- A first guess: not seen in game on this client.
    function c.mounted()
        return flag(call(env.IsMounted))
    end

    -- Section 235 item 4: is a fishing pole in your main hand. True, false,
    -- or nil when not known. GetInventoryItemID("player", 16) (the main
    -- hand; no id: nothing there, false), then the item's class and
    -- subclass from GetItemInfoInstant (C_Item first, as c.gear): weapon 2,
    -- subclass 20 is a fishing pole. A class not read: nil, never false.
    -- Both names are in CLIENT-NAMES-16001; the read is a first guess, not
    -- seen in game. It only reads.
    function c.fishingPole()
        local ok, id = call(env.GetInventoryItemID, "player", 16)
        if not ok then return nil end
        if id == nil then return false end
        if hidden(id) or type(id) ~= "number" then return nil end
        local class, subclass = itemType(id)
        if class == nil or subclass == nil then return nil end
        return class == 2 and subclass == 20
    end

    -- N8 (lead section 238): the game's low-health warning, as Flow reads it
    -- (Modules/Rotation/BuffItems.lua): LowHealthFrame shown, and not faded
    -- out (alpha above 0.05; an alpha not read counts as shown). True,
    -- false, or nil when not known (no frame, a failed or secret answer).
    -- A first guess, not seen in game. It only reads.
    function c.lowHealth()
        local f = env.LowHealthFrame
        if type(f) ~= "table" then return nil end
        local ok, shown = call(f.IsShown, f)
        if not ok or shown == nil or hidden(shown) then return nil end
        if not shown then return false end
        local okA, a = call(f.GetAlpha, f)
        if not okA or a == nil or hidden(a) or type(a) ~= "number" then return true end
        return a > 0.05
    end

    -- S42 quest item on the quest arrow (LEDGER 169/172;
    -- WoW/from-zen/RESEARCH-S42.md). Three reads, each only reads: nothing
    -- uses an item here (no UseQuestLogSpecialItem, no secure button; the
    -- click is parked behind G23). FIRST GUESSES: not seen in game on 1.60.1
    -- and not seen in an installed addon (lead section 169 D).
    -- Docs (warcraft.wiki.gg, read 2026-11-22), all listed for 1.60.1 unless
    -- said: C_QuestLog.GetLogIndexForQuestID(questID) -> index or nil;
    -- GetQuestLogIndexByID(questID) -> index, 0 when not in the log (NOT
    -- listed for 1.60.1: asked second); GetQuestLogSpecialItemInfo(index)
    -- -> link, icon, charges, showWhenComplete (index in the log, not the
    -- quest id); C_Item.GetItemCount(item) -> count (GetItemCount second);
    -- C_Item.GetItemSpell(item) -> name, id, "may return nothing"
    -- (GetItemSpell second, not listed for 1.60.1). Legacy Flow asks the
    -- same: Modules/Nav/QuestItems.lua:80-106.

    -- A quest's place in the log, or nil when it is not there or not known.
    local function questLogIndex(questID)
        local group = env.C_QuestLog
        if type(group) == "table" then
            local ok, i = call(group.GetLogIndexForQuestID, questID)
            if ok and type(i) == "number" and not hidden(i) and i > 0 then return i end
        end
        local ok, i = call(env.GetQuestLogIndexByID, questID)
        if ok and type(i) == "number" and not hidden(i) and i > 0 then return i end
        return nil
    end

    -- The game's own item for a quest in the log: { id, link }, or nil
    -- (not in the log, no item, an answer that is not an item link, or a
    -- secret one).
    function c.questItem(questID)
        if type(questID) ~= "number" then return nil end
        local index = questLogIndex(questID)
        if not index then return nil end
        local ok, link = call(env.GetQuestLogSpecialItemInfo, index)
        if not ok or type(link) ~= "string" or hidden(link) then return nil end
        local id = tonumber(link:match("item:(%d+)"))
        if not id or id <= 0 then return nil end
        return { id = id, link = link }
    end

    -- How many of an item are in the bags: a whole number of 0 or more, or
    -- nil when not known. item: an item ID or link.
    function c.itemCount(item)
        if item == nil then return nil end
        local group = env.C_Item
        local fn = env.GetItemCount
        if type(group) == "table" and type(group.GetItemCount) == "function" then fn = group.GetItemCount end
        local ok, n = call(fn, item)
        if not ok or type(n) ~= "number" or hidden(n) then return nil end
        if n ~= n or n < 0 or n ~= math.floor(n) or n == math.huge then return nil end
        return n
    end

    -- Whether using an item does something (it has a spell): true, false
    -- when the read ran and named no spell, nil when not known (no read, a
    -- failed read, a secret or odd answer).
    function c.itemUse(item)
        if item == nil then return nil end
        local group = env.C_Item
        local fn = env.GetItemSpell
        if type(group) == "table" and type(group.GetItemSpell) == "function" then fn = group.GetItemSpell end
        if type(fn) ~= "function" then return nil end
        local ok, name = call(fn, item)
        if not ok then return nil end
        if name == nil then return false end
        if type(name) ~= "string" or hidden(name) then return nil end
        return name ~= ""
    end

    -- S44 quest place on another map (lead section 173): where a map lies in
    -- the world, so a step on another map can be pointed at (Nav/GuideRead.lua).
    -- Only reads. C_Map.GetWorldPosFromMapPos(map, CreateVector2D(x, y)) is
    -- the call c.worldPosition already makes (S35; RESEARCH-S35.md), asked
    -- here for three points of the map: 0,0, 1,0 and 0,1. Legacy Flow does
    -- the same (Modules/Nav/Nav.lua:55-61 and 104-123: map corners and the
    -- map's east and south axes). A first guess: not seen in game on 1.60.1.
    -- CreateVector2D is the client's own; with none, a plain { x, y } is
    -- asked with (whether the client takes it is not known).
    local function mapWorld(map, x, y)
        local okV, vec = call(env.CreateVector2D, x, y)
        if not okV or type(vec) ~= "table" then vec = { x = x, y = y } end
        local ok, cont, world = mapCall("GetWorldPosFromMapPos", map, vec)
        if not ok or type(world) ~= "table" then return nil end
        if type(cont) ~= "number" or hidden(cont) then return nil end
        local okXY, wx, wy = call(world.GetXY, world)
        if not okXY then wx, wy = world.x, world.y end
        if type(wx) ~= "number" or type(wy) ~= "number" or hidden(wx) or hidden(wy) then return nil end
        if wx ~= wx or wy ~= wy then return nil end
        return cont, wx, wy
    end

    -- A map's corners in the world: { cont, ox, oy (the point 0,0),
    -- ex, ey (1,0, the east edge's end), sx, sy (0,1, the south edge's end) },
    -- or nil when any is not known or they are not on one continent.
    function c.mapCorners(map)
        if map == nil then return nil end
        local c0, ox, oy = mapWorld(map, 0, 0)
        local c1, ex, ey = mapWorld(map, 1, 0)
        local c2, sx, sy = mapWorld(map, 0, 1)
        if c0 == nil or c0 ~= c1 or c0 ~= c2 then return nil end
        return { cont = c0, ox = ox, oy = oy, ex = ex, ey = ey, sx = sx, sy = sy }
    end

    -- ----------------------------------------------------------------- S2
    -- The trader (owner Twin): every priced row of a search the player runs,
    -- not the cheapest alone. The same events, reads and limits as the S4
    -- block above (lead section 170): no further rows are asked of the
    -- server, nothing searches, bids, buys or posts. First guesses, not seen
    -- in game: needs a game test.
    --
    --   client.watchAuctionRows(fn) -> true | nil;  fn(itemID, rows, kind)
    -- kind is "commodity" or "item": which search the rows answer (R4).
    -- rows = { { unit =, qty = } ... } in the order the client gives them:
    -- unit is the price for one, qty how many (left out when the client
    -- hides it or it is no whole count above zero: never made up). A row
    -- with no readable price is left out. At most AUCTION_ROWS rows are
    -- read; row 1 alone when the client will not say how many. A search
    -- with nothing priced is told with no rows. A hidden or unreadable item
    -- ID is not told. fn's errors stay here. nil when the client has
    -- neither result read (no event is then asked for).
    local rowsFns, rowsFollowed = {}, false
    local function auctionRows(read, count, what)
        local house = env.C_AuctionHouse
        if type(house) ~= "table" then return nil end
        local okN, n = call(house[count], what)
        if not okN or hidden(n) or type(n) ~= "number" or n ~= n or n < 1 then n = 1 end
        n = math.min(math.floor(n), AUCTION_ROWS)
        local out = {}
        for i = 1, n do
            local row = auctionRowAt(read, what, i)
            local unit = auctionUnit(row)
            if unit then
                local qty = row.quantity
                if type(qty) ~= "number" or qty < 1 or qty ~= math.floor(qty) then qty = nil end
                out[#out + 1] = { unit = unit, qty = qty }
            end
        end
        return out
    end
    local function rowsTell(id, rows, kind)
        if type(id) ~= "number" or rows == nil then return end
        for _, fn in ipairs({ unpack(rowsFns) }) do pcall(fn, id, rows, kind) end
    end
    function c.watchAuctionRows(fn)
        if type(fn) ~= "function" then return nil end
        rowsFns[#rowsFns + 1] = fn
        if rowsFollowed then return true end
        local house = env.C_AuctionHouse
        if type(house) ~= "table" then return nil end
        if type(house.GetCommoditySearchResultInfo) == "function" then
            events.add("COMMODITY_SEARCH_RESULTS_UPDATED", function(itemID)
                if hidden(itemID) then return end
                rowsTell(itemID, auctionRows("GetCommoditySearchResultInfo", "GetNumCommoditySearchResults", itemID),
                    "commodity")
            end)
            rowsFollowed = true
        end
        if type(house.GetItemSearchResultInfo) == "function" then
            events.add("ITEM_SEARCH_RESULTS_UPDATED", function(itemKey)
                if type(itemKey) ~= "table" then return end
                local okI, id = pcall(function() return itemKey.itemID end)
                if not okI or hidden(id) then return end
                rowsTell(id, auctionRows("GetItemSearchResultInfo", "GetNumItemSearchResults", itemKey), "item")
            end)
            rowsFollowed = true
        end
        return rowsFollowed or nil
    end
    -- ------------------------------------------------------------- end S2

    -- ---------------------------------------------------------------- S3
    -- S3 slice 3 (lead section 181): the lines that say an auction sold or
    -- came back unsold.
    --   client.globalText(name) -> the client's own text of that name, or nil
    --   client.onSystemMessage(fn) -> cancel | nil;  fn(line), CHAT_MSG_SYSTEM
    --   client.auctionOutcome(line) -> "sold" | "expired", item name; or nil
    -- The texts are the client's own ERR_AUCTION_SOLD_S and
    -- ERR_AUCTION_EXPIRED_S; no English is written here. A hidden or
    -- non-text line never reaches a listener. Needs game test on 16001:
    -- that these lines come as CHAT_MSG_SYSTEM, and in these texts.
    function c.globalText(name)
        if type(name) ~= "string" then return nil end
        local ok, v = pcall(function() return env[name] end)
        if not ok or type(v) ~= "string" or v == "" or hidden(v) then return nil end
        return v
    end

    local systemFns, systemFollowed = {}, false
    local function systemLine(line)
        if type(line) ~= "string" or hidden(line) then return end
        for _, fn in ipairs({ unpack(systemFns) }) do pcall(fn, line) end
    end
    function c.onSystemMessage(fn)
        if type(fn) ~= "function" then return nil end
        if not systemFollowed then
            events.add("CHAT_MSG_SYSTEM", systemLine)
            systemFollowed = true
        end
        systemFns[#systemFns + 1] = fn
        return function()
            for i = #systemFns, 1, -1 do
                if systemFns[i] == fn then table.remove(systemFns, i) end
            end
        end
    end

    local OUTCOMES = { { "sold", "ERR_AUCTION_SOLD_S" }, { "expired", "ERR_AUCTION_EXPIRED_S" } }
    function c.auctionOutcome(line)
        if type(line) ~= "string" or line == "" or hidden(line) then return nil end
        for _, o in ipairs(OUTCOMES) do
            local pattern, kinds = lootPattern(c.globalText(o[2]))
            if pattern and #kinds == 1 and kinds[1] == "s" then
                local name = line:match(pattern)
                if name then return o[1], name end
            end
        end
        return nil
    end
    -- ------------------------------------------------------------- end S3

    -- ----------------------------------------------------------------- S8
    -- Nameplate threat and combo points (lead section 178; WoW/from-lazy/
    -- RESEARCH-S8.md): UI/PlateThreat.lua and UI/PlateCombo.lua. LOOK ONLY:
    -- nothing here clicks, targets, casts or writes a CVar; no frame is
    -- secure or takes the mouse. Only "player", "target" and enemy
    -- nameplate units ("nameplateN") are named: no party or raid unit.
    --
    -- THE DISPLAY SINK (lead section 178, option A). A threat share and a
    -- combo count are amounts this client may hide (secret values). A
    -- hidden one never leaves this file: the label or the bar that read it
    -- writes it onto its own widget (FontString:SetFormattedText,
    -- StatusBar:SetValue) and the caller is told only "hidden". Nothing
    -- hidden is compared, added to or kept. A plain one is handed back as a
    -- number and the caller draws it.
    --
    --   client.plates(fn) -> cancel | nil   fn("added" | "removed", unit) on
    --                     NAME_PLATE_UNIT_ADDED / _REMOVED; unit is always
    --                     "nameplateN" (any other, or a hidden one, is not told)
    --   client.canAttack(unit) -> true | false | nil   "target" or nameplateN
    --                     only; any other unit is nil and not asked about
    --   client.grouped() -> true | false | nil   IsInGroup()
    --   client.plateLabel(unit) -> h | nil   a small text at the right of
    --                     that unit's nameplate (one frame per plate frame,
    --                     made the first time). nil: no nameplate unit, no
    --                     plate on screen, no frames.
    --     h.show(on), h.text(s), h.color(r, g, b), h.alpha(a)
    --     h.threat() -> "shown", status, pct   pct plain; not drawn here
    --                 -> "hidden", status      pct hidden; written here
    --                 -> nil                   on no threat list, or not known
    --                 status: the game's 0..3, or nil when hidden or odd
    --   client.comboBar() -> h | nil   a bar for combo points, hidden until shown
    --     h.hang(unit) -> "power" | "health" | "plate" | nil   under that
    --                 unit's plate ("target" or nameplateN): under its power
    --                 bar when one shows, else its health bar, else the plate;
    --                 nil when no plate is on screen. Hung again only when
    --                 the plate or the part changed.
    --     h.sections(n) -> true | false   n whole, 1..10: the fill's range and
    --                 a divider at each point
    --     h.fill(n), h.color(r, g, b), h.show(on)
    --     h.fillFromGame() -> "shown", n   n plain, whole, 0 or more; not drawn
    --                      -> "hidden"     hidden; set on the bar here
    --                      -> nil          not known (never 0 in its place)
    --   client.combo() -> { points, max }   plain whole numbers only; a field
    --                     not known is left out
    --   client.comboColor() -> { r, g, b } | nil   PowerBarColor's combo row
    --
    -- FIRST GUESSES, none seen in game on 1.60.1 (16001) and none seen in an
    -- installed addon. Docs read on warcraft.wiki.gg 2026-11-22 (see
    -- RESEARCH-S8.md): API_UnitDetailedThreatSituation (isTanking, status,
    -- scaledPercentage, rawPercentage, rawThreat = (unit, mobUnit); secret
    -- when unit threat values are restricted; may return nothing),
    -- API_C_NamePlate.GetNamePlateForUnit (unitToken; friendly plates in
    -- instances are not handed out; the frame has UnitFrame),
    -- NAME_PLATE_UNIT_ADDED and NAME_PLATE_UNIT_REMOVED (payload
    -- "nameplateN"), API_GetComboPoints ((unit, target) -> 0..5; 0 for a
    -- friendly or missing target), API_UnitPower (combo points are power
    -- type 4; secret when unit power is restricted), API_issecretvalue and
    -- Secret_Values (a hidden value may be stored, passed on and given to
    -- string.format; comparing or adding one raises), API_StatusBar_SetValue
    -- (takes a hidden value). FontString:SetFormattedText taking a hidden
    -- value is from the page summary only (the fetch was cut): less firm.
    -- Not read: the pages of UnitPowerMax, IsInGroup, UnitCanAttack (c.target
    -- uses it already) and PowerBarColor; legacy Flow 0.35.377 uses each
    -- (Modules/PlateThreat.lua, Modules/PlateCombo.lua). The nameplate's
    -- parts (UnitFrame.powerBar / healthBar ...) are legacy Flow's guess too.
    do
        local THREAT_FORMAT = "%.0f%%"
        local LABEL_GAP, LABEL_RAISE, LABEL_FONT = 2, 12, 10
        local BAR_WIDTH, BAR_HEIGHT, BAR_DROP = 110, 5, 1
        local BAR_TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"
        local COMBO_POWER = 4

        local function plateUnit(unit)
            return type(unit) == "string" and unit:find("^nameplate%d+$") ~= nil
        end

        -- obj[key] under pcall: a frame may refuse a field read.
        local function field(obj, key)
            local ok, v = pcall(function() return obj[key] end)
            if ok then return v end
            return nil
        end

        local function plateOf(unit)
            local group = env.C_NamePlate
            if type(group) ~= "table" then return nil end
            local ok, plate = call(group.GetNamePlateForUnit, unit)
            if not ok or type(plate) ~= "table" then return nil end
            return plate
        end

        local function levelOf(f)
            local ok, n = method(f, "GetFrameLevel")
            if ok and type(n) == "number" and not hidden(n) then return n end
            return nil
        end

        local function sized(f, w, ht)
            if not method(f, "SetSize", w, ht) then
                method(f, "SetWidth", w)
                method(f, "SetHeight", ht)
            end
        end

        function c.plates(fn)
            if type(fn) ~= "function" then return nil end
            local function tell(what)
                return function(unit)
                    if unit == nil or hidden(unit) or not plateUnit(unit) then return end
                    pcall(fn, what, unit)
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
            return yesNo(call(env.UnitCanAttack, "player", unit))
        end

        function c.grouped()
            return yesNo(call(env.IsInGroup))
        end

        -- The labels made, by plate frame (the game hands a plate frame out
        -- again for another unit). Weak keys: a frame the game lets go is
        -- not held here. Nothing is written onto the game's own frames.
        local labels = setmetatable({}, { __mode = "k" })

        -- As legacy Flow's label: a frame on the plate, at its right, raised
        -- clear of the level, in the game's font, 10, outlined.
        local function makeLabel(plate)
            local ok, f = call(env.CreateFrame, "Frame", nil, plate)
            if not ok or f == nil then return nil end
            method(f, "Hide")
            sized(f, 1, LABEL_RAISE)
            method(f, "SetPoint", "LEFT", plate, "RIGHT", LABEL_GAP, LABEL_RAISE)
            method(f, "EnableMouse", false)
            local level = levelOf(plate)
            if level then method(f, "SetFrameLevel", level + 10) end
            local okText, fs = method(f, "CreateFontString", nil, "OVERLAY", "GameFontNormalSmall")
            if not okText then fs = nil end
            if fs ~= nil then
                local font = env.STANDARD_TEXT_FONT
                if type(font) ~= "string" or font == "" then font = "Fonts\\FRIZQT__.TTF" end
                method(fs, "SetFont", font, LABEL_FONT, "OUTLINE")
                method(fs, "SetPoint", "LEFT", f, "LEFT", 0, 0)
            end
            return { frame = f, text = fs }
        end

        -- The game's threat status, 0..3, when plain and whole; else nil.
        local function threatStatus(v)
            if v == nil or hidden(v) or type(v) ~= "number" then return nil end
            if v ~= math.floor(v) or v < 0 or v > 3 then return nil end
            return v
        end

        function c.plateLabel(unit)
            if not plateUnit(unit) then return nil end
            local plate = plateOf(unit)
            if plate == nil then return nil end
            local made = labels[plate]
            if made == nil then
                made = makeLabel(plate)
                if made == nil then return nil end
                labels[plate] = made
            end
            local f, fs = made.frame, made.text
            local h = {}
            function h.show(on) method(f, on and "Show" or "Hide") end
            function h.text(s)
                if fs ~= nil and type(s) == "string" then method(fs, "SetText", s) end
            end
            function h.color(r, g, b)
                if fs ~= nil and type(r) == "number" and type(g) == "number" and type(b) == "number" then
                    method(fs, "SetTextColor", r, g, b)
                end
            end
            function h.alpha(a)
                if fs ~= nil and type(a) == "number" then method(fs, "SetAlpha", a) end
            end
            -- Your own share only ("player" against this plate's unit); the
            -- raw share first, else the scaled one (legacy Flow's P.Read).
            function h.threat()
                local ok, _, status, scaled, raw = call(env.UnitDetailedThreatSituation, "player", unit)
                if not ok then return nil end
                local st = threatStatus(status)
                local pct = raw
                if pct == nil then pct = scaled end
                if pct == nil then return nil end
                if hidden(pct) then
                    -- The sink: onto the label as it is, and no further.
                    if fs == nil then return nil end
                    if method(fs, "SetFormattedText", THREAT_FORMAT, pct) then return "hidden", st end
                    local okF, s = pcall(string.format, THREAT_FORMAT, pct)
                    if okF and type(s) == "string" and method(fs, "SetText", s) then return "hidden", st end
                    return nil
                end
                if type(pct) ~= "number" or pct ~= pct or pct < 0 or pct == math.huge then return nil end
                return "shown", st, pct
            end
            return h
        end

        -- Combo points' power type: the client's own number for it, else 4.
        local function comboType()
            local enum = env.Enum
            local kinds = type(enum) == "table" and field(enum, "PowerType") or nil
            local n = type(kinds) == "table" and field(kinds, "ComboPoints") or nil
            if type(n) == "number" and not hidden(n) then return n end
            return COMBO_POWER
        end

        -- true and the count as the client gave it (perhaps hidden), or
        -- false. GetComboPoints("player", "target") first, UnitPower second,
        -- as legacy Flow (Modules/Rotation/Compat.lua A.ComboPoints), but an
        -- answer not given is not known, never 0.
        local function comboRead()
            local ok, n = call(env.GetComboPoints, "player", "target")
            if ok and n ~= nil then return true, n end
            ok, n = call(env.UnitPower, "player", comboType())
            if ok and n ~= nil then return true, n end
            return false, nil
        end

        function c.combo()
            local _, n = comboRead()
            local okMax, most = call(env.UnitPowerMax, "player", comboType())
            local max = wholeOrNil(okMax, most)
            if max == 0 then max = nil end
            return { points = wholeOrNil(true, n), max = max }
        end

        local function share(v)
            if v == nil or hidden(v) or type(v) ~= "number" or v ~= v or v < 0 or v > 1 then return nil end
            return v
        end

        function c.comboColor()
            local colors = env.PowerBarColor
            if type(colors) ~= "table" then return nil end
            local row = field(colors, "COMBO_POINTS")
            if type(row) ~= "table" then row = field(colors, COMBO_POWER) end
            if type(row) ~= "table" then return nil end
            local r, g, b = share(field(row, "r")), share(field(row, "g")), share(field(row, "b"))
            if r == nil or g == nil or b == nil then return nil end
            return { r = r, g = g, b = b }
        end

        local function isShown(frame)
            local ok, v = method(frame, "IsShown")
            if not ok or v == nil then return false end
            return flag(ok, v) == true
        end

        -- What a bar hangs under on a plate (legacy Flow's PC.Under): the
        -- power bar when one shows, else the health bar, else the plate.
        local POWER_PARTS = { "powerBar", "PowerBar", "manabar", "ManaBar" }
        local function partOf(plate)
            local uf = field(plate, "UnitFrame")
            if type(uf) == "table" then
                for i = 1, #POWER_PARTS do
                    local p = field(uf, POWER_PARTS[i])
                    if type(p) == "table" and isShown(p) then return p, "power" end
                end
                local hb = field(uf, "healthBar") or field(uf, "HealthBar")
                if hb == nil then
                    local box = field(uf, "HealthBarsContainer")
                    if type(box) == "table" then hb = field(box, "healthBar") or box end
                end
                if type(hb) == "table" and isShown(hb) then return hb, "health" end
            end
            return plate, "plate"
        end

        -- As legacy Flow's bar: 5 high, the game's bar texture, a dark back
        -- and a thin dark edge; the dividers each ride an unseen bar filled
        -- to that many points, so nothing is measured.
        function c.comboBar()
            local ok, f = call(env.CreateFrame, "Frame", nil, env.UIParent)
            if not ok or f == nil then return nil end
            method(f, "Hide")
            sized(f, BAR_WIDTH, BAR_HEIGHT)
            method(f, "EnableMouse", false)
            local okFill, fill = call(env.CreateFrame, "StatusBar", nil, f)
            if not okFill or fill == nil then return nil end
            method(fill, "SetAllPoints", f)
            method(fill, "SetStatusBarTexture", BAR_TEXTURE)
            local okEdge, edge = method(f, "CreateTexture", nil, "BACKGROUND", nil, -2)
            if okEdge and edge ~= nil then
                method(edge, "SetPoint", "TOPLEFT", f, "TOPLEFT", -1, 1)
                method(edge, "SetPoint", "BOTTOMRIGHT", f, "BOTTOMRIGHT", 1, -1)
                if not method(edge, "SetColorTexture", 0, 0, 0, 0.9) then method(edge, "SetTexture", 0, 0, 0, 0.9) end
            end
            local okBack, back = method(f, "CreateTexture", nil, "BACKGROUND", nil, -1)
            if okBack and back ~= nil then
                method(back, "SetAllPoints", f)
                method(back, "SetTexture", BAR_TEXTURE)
                method(back, "SetVertexColor", 0.18, 0.17, 0.1, 0.9)
            end
            local okLines, lines = call(env.CreateFrame, "Frame", nil, f)
            if not okLines then lines = nil end
            if lines ~= nil then
                method(lines, "SetAllPoints", f)
                local level = levelOf(fill)
                if level then method(lines, "SetFrameLevel", level + 2) end
            end

            local marks, dividers = {}, {}
            local most, plateNow, partNow, whatNow
            local h = {}

            -- The unseen bar and the divider for point k, made the first time.
            local function mark(k)
                if marks[k] ~= nil then return marks[k], dividers[k] end
                local okM, m = call(env.CreateFrame, "StatusBar", nil, f)
                if not okM or m == nil then return nil end
                method(m, "SetAllPoints", f)
                method(m, "SetStatusBarTexture", BAR_TEXTURE)
                method(m, "SetStatusBarColor", 0, 0, 0, 0)
                local d = false
                if lines ~= nil then
                    local okD, tex = method(lines, "CreateTexture", nil, "OVERLAY")
                    if okD and tex ~= nil then
                        d = tex
                        if not method(d, "SetColorTexture", 0, 0, 0, 1) then method(d, "SetTexture", 0, 0, 0, 1) end
                        method(d, "SetWidth", 1)
                        local okEnd, ends = method(m, "GetStatusBarTexture")
                        if okEnd and ends ~= nil then
                            method(d, "SetPoint", "TOP", ends, "TOPRIGHT", 0, 0)
                            method(d, "SetPoint", "BOTTOM", ends, "BOTTOMRIGHT", 0, 0)
                        end
                    end
                end
                marks[k], dividers[k] = m, d
                return m, d
            end

            function h.sections(n)
                if type(n) ~= "number" or n ~= n or n < 1 or n > 10 or n ~= math.floor(n) then return false end
                if n == most then return true end
                most = n
                method(fill, "SetMinMaxValues", 0, n)
                for k = 1, 9 do
                    if k <= n - 1 then
                        local m, d = mark(k)
                        if m ~= nil then
                            method(m, "SetMinMaxValues", 0, n)
                            method(m, "SetValue", k)
                            method(m, "Show")
                            if d then method(d, "Show") end
                        end
                    elseif marks[k] ~= nil then
                        method(marks[k], "Hide")
                        if dividers[k] then method(dividers[k], "Hide") end
                    end
                end
                return true
            end

            function h.fill(n)
                if type(n) ~= "number" or n ~= n then return false end
                return (method(fill, "SetValue", n))
            end

            function h.color(r, g, b)
                if type(r) == "number" and type(g) == "number" and type(b) == "number" then
                    method(fill, "SetStatusBarColor", r, g, b)
                end
            end

            function h.show(on) method(f, on and "Show" or "Hide") end

            function h.hang(unit)
                if unit ~= "target" and not plateUnit(unit) then return nil end
                local plate = plateOf(unit)
                if plate == nil then
                    plateNow, partNow, whatNow = nil, nil, nil
                    return nil
                end
                local part, what = partOf(plate)
                if plate == plateNow and part == partNow then return whatNow end
                plateNow, partNow, whatNow = plate, part, what
                method(f, "SetParent", plate)
                method(f, "ClearAllPoints")
                if what == "plate" then
                    sized(f, BAR_WIDTH, BAR_HEIGHT)
                    method(f, "SetPoint", "TOP", plate, "BOTTOM", 0, -BAR_DROP - 2)
                else
                    method(f, "SetHeight", BAR_HEIGHT)
                    method(f, "SetPoint", "TOPLEFT", part, "BOTTOMLEFT", 0, -BAR_DROP - 1)
                    method(f, "SetPoint", "TOPRIGHT", part, "BOTTOMRIGHT", 0, -BAR_DROP - 1)
                end
                local level = levelOf(plate)
                if level then method(f, "SetFrameLevel", level + 10) end
                return what
            end

            function h.fillFromGame()
                local okRead, n = comboRead()
                if not okRead then return nil end
                if hidden(n) then
                    -- The sink: onto the bar as it is, and no further.
                    if method(fill, "SetValue", n) then return "hidden" end
                    return nil
                end
                local plain = wholeOrNil(true, n)
                if plain == nil then return nil end
                return "shown", plain
            end

            return h
        end

        -- P-READS (lead sections 237 item 4, 260 item 1; Plexy's
        -- RESEARCH-P-READS.md): the enemy plates around you, read only.
        -- First guesses, none seen in game: C_NamePlate.GetNamePlates() for
        -- the list, each plate's namePlateUnitToken (else UnitFrame.unit),
        -- UnitCanAttack, UnitAffectingCombat, UnitThreatSituation,
        -- UnitIsUnit, CheckInteractDistance (3: about ten yards),
        -- UnitCastingInfo, UnitChannelInfo, UnitCreatureType.
        local function plateList()
            local group = env.C_NamePlate
            if type(group) ~= "table" then return nil end
            local ok, list = call(group.GetNamePlates)
            if not ok or list == nil or hidden(list) or type(list) ~= "table" then return nil end
            return list
        end

        local function plateToken(plate)
            if type(plate) ~= "table" then return nil end
            local unit = field(plate, "namePlateUnitToken")
            if unit == nil then
                local frame = field(plate, "UnitFrame")
                if type(frame) == "table" then unit = field(frame, "unit") end
            end
            if unit == nil or hidden(unit) or not plateUnit(unit) then return nil end
            return unit
        end

        -- c.enemiesNear() -> near, close, onYou, or nil when not known
        --   near   plates you can attack that are in a fight
        --   close  of those, the ones within CheckInteractDistance(unit, 3);
        --          nil when that read is refused for any of them
        --   onYou  of those, the ones with you on their threat list, else
        --          the ones whose target is you
        -- nil when the list or any plate's attack or fight answer is not
        -- read: never 0 in place of not known. No plates: 0, 0, 0.
        function c.enemiesNear()
            local list = plateList()
            if list == nil then return nil end
            local near, close, onYou, closeKnown = 0, 0, 0, true
            for _, plate in ipairs(list) do
                local unit = plateToken(plate)
                if unit == nil then return nil end
                local attack = yesNo(call(env.UnitCanAttack, "player", unit))
                if attack == nil then return nil end
                if attack then
                    local fighting = yesNo(call(env.UnitAffectingCombat, unit))
                    if fighting == nil then return nil end
                    if fighting then
                        near = near + 1
                        local okNear, d = call(env.CheckInteractDistance, unit, 3)
                        if not okNear or (d ~= nil and hidden(d)) then
                            closeKnown = false
                        elseif d == true or d == 1 then
                            close = close + 1
                        end
                        local okThreat, status = call(env.UnitThreatSituation, "player", unit)
                        if okThreat and threatStatus(status) ~= nil then
                            onYou = onYou + 1
                        elseif yesNo(call(env.UnitIsUnit, unit .. "target", "player")) then
                            onYou = onYou + 1
                        end
                    end
                end
            end
            if not closeKnown then close = nil end
            return near, close, onYou
        end

        -- The plate unit's name (for the live caption only) and whether it
        -- is your target; each nil when not read or hidden.
        local function plateWho(unit)
            local name = text(call(env.UnitName, unit))
            local isTarget = yesNo(call(env.UnitIsUnit, unit, "target"))
            return name, isTarget
        end

        -- c.plateCasts() -> { { unit, name, spell, interruptible, isTarget,
        --   spellId, channel, endsAt } ... } or nil when the plate list is
        -- not read. The row shape is the class-b one (lead section 262):
        -- name is the enemy, spell the spell. UnitCastingInfo (name, text,
        -- texture, startMs, endMs, tradeSkill, castID, notInterruptible,
        -- spellId), else UnitChannelInfo (the same less castID). A cast whose
        -- spell name is hidden is left out; any other field hidden or not
        -- read is left out. endsAt is in the clock of c.now().
        function c.plateCasts()
            local list = plateList()
            if list == nil then return nil end
            local out = {}
            for _, plate in ipairs(list) do
                local unit = plateToken(plate)
                if unit ~= nil then
                    local ok, name, _, _, _, endMs, _, _, locked, id = call(env.UnitCastingInfo, unit)
                    local channel = false
                    if not ok or name == nil then
                        local okCh, chName, _, _, _, chEnd, _, chLocked, chId = call(env.UnitChannelInfo, unit)
                        ok, name, endMs, locked, id, channel = okCh, chName, chEnd, chLocked, chId, true
                    end
                    local spell = text(ok, name)
                    if spell ~= nil then
                        local who, isTarget = plateWho(unit)
                        local row = { unit = unit, name = who, spell = spell, channel = channel, isTarget = isTarget }
                        if endMs ~= nil and not hidden(endMs) and type(endMs) == "number" then
                            row.endsAt = endMs / 1000
                        end
                        if locked ~= nil and not hidden(locked) and type(locked) == "boolean" then
                            row.interruptible = not locked
                        end
                        if id ~= nil and not hidden(id) and type(id) == "number" then row.spellId = id end
                        out[#out + 1] = row
                    end
                end
            end
            return out
        end

        -- Debuff names read as a crowd control that holds the enemy (first
        -- guess names; Polymorph by any of its forms).
        -- Named limit (review R2-2): English names only. On a client in
        -- another language none matches, so controlled reads false for an
        -- enemy that is held. Matching by spell id would fix it, but no id
        -- of these effects is in the repo data and guessing them is not
        -- allowed. Evidence still needed: the spell ids of the held effects
        -- on Forever, from a capture (the debuff rows' spellId).
        local HELD = {
            ["Shackle Undead"] = true, ["Hibernate"] = true, ["Sap"] = true,
            ["Freezing Trap Effect"] = true, ["Banish"] = true, ["Fear"] = true,
            ["Seduction"] = true, ["Scare Beast"] = true, ["Repentance"] = true,
            ["Gouge"] = true, ["Blind"] = true, ["Psychic Scream"] = true,
            ["Howl of Terror"] = true, ["Intimidating Shout"] = true,
        }

        -- true when a held debuff is on the unit, false when its debuffs were
        -- read and none is, nil when a debuff or its name is not read.
        local function held(unit)
            local auras = env.C_UnitAuras
            local byIndex
            if type(auras) == "table" then byIndex = auras.GetAuraDataByIndex end
            local old = env.UnitDebuff
            if type(byIndex) ~= "function" and type(old) ~= "function" then return nil end
            for i = 1, 40 do
                local name
                if type(byIndex) == "function" then
                    local ok, row = pcall(byIndex, unit, i, "HARMFUL")
                    if not ok then return nil end
                    if row == nil then return false end
                    if hidden(row) or type(row) ~= "table" then return nil end
                    name = row.name
                else
                    local ok, got = pcall(old, unit, i)
                    if not ok then return nil end
                    if got == nil then return false end
                    name = got
                end
                if name == nil or hidden(name) or type(name) ~= "string" then return nil end
                if HELD[name] or name:find("^Polymorph") then return true end
            end
            return false
        end

        -- c.plateEnemies() -> { { unit, name, isTarget, creature, controlled,
        --   threat } ... } or nil when the plate list is not read. The class-b
        -- row shape (lead section 262). Only the plates you can attack; a
        -- plate whose attack answer is not read is left out. creature is the
        -- client word (UnitCreatureType), threat your threat status 0..3
        -- (UnitThreatSituation), controlled a held debuff on it. Any field
        -- hidden or not read is left out: never false or 0 in its place.
        function c.plateEnemies()
            local list = plateList()
            if list == nil then return nil end
            local out = {}
            for _, plate in ipairs(list) do
                local unit = plateToken(plate)
                if unit ~= nil and yesNo(call(env.UnitCanAttack, "player", unit)) == true then
                    local who, isTarget = plateWho(unit)
                    local okThreat, status = call(env.UnitThreatSituation, "player", unit)
                    local threat
                    if okThreat then threat = threatStatus(status) end
                    out[#out + 1] = {
                        unit = unit, name = who, isTarget = isTarget,
                        creature = text(call(env.UnitCreatureType, unit)),
                        controlled = held(unit), threat = threat,
                    }
                end
            end
            return out
        end

        -- c.creatureType(unit) -> the client's word ("Beast", "Humanoid"...)
        -- or nil. Only "target" or a plate unit is asked about.
        function c.creatureType(unit)
            if unit ~= "target" and not plateUnit(unit) then return nil end
            return text(call(env.UnitCreatureType, unit))
        end
    end
    -- ------------------------------------------------------------- end S8

    -- Section 183 (C1): the three reads the rotation takes for buffs, form
    -- and what is queued or toggled on. Each answers nil when not known,
    -- never an empty answer made up. Not tested in game; each read below is
    -- a first guess from the API pages (warcraft.wiki.gg API_C_UnitAuras.
    -- GetAuraDataByIndex, API_UnitBuff, API_GetShapeshiftForm,
    -- API_GetShapeshiftFormInfo, API_IsCurrentSpell).
    --
    -- c.targetDebuffs() -> { [name] = secondsLeft or true } or nil
    --   Section 187: your own debuffs on your target, read the same way as
    --   playerBuffs with the unit "target" and the filter "HARMFUL|PLAYER":
    --   C_UnitAuras.GetAuraDataByIndex where present, else UnitDebuff. No
    --   target reads as an empty list. A first guess from the API pages
    --   (API_C_UnitAuras.GetAuraDataByIndex, API_UnitDebuff), not seen in
    --   game.
    --
    -- c.playerBuffs() -> { [name] = secondsLeft or true } or nil
    --   every buff on you, read to the end of the list. secondsLeft is
    --   math.huge for a buff with no end; true when the end time is hidden or
    --   not a number. nil when the client has no read, a read raised, or a
    --   row or a name was hidden (one buff not seen makes the whole list not
    --   known). A full read with no buff gives an empty table.
    --   C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL") where present,
    --   else UnitBuff("player", i, "HELPFUL"); at most 40 rows.
    local function aurasOf(unit, filter, old)
        local auras = env.C_UnitAuras
        local byIndex = type(auras) == "table" and auras.GetAuraDataByIndex or nil
        if type(byIndex) ~= "function" and type(old) ~= "function" then return nil end
        local out = {}
        for i = 1, 40 do
            local name, expires
            if type(byIndex) == "function" then
                local ok, row = pcall(byIndex, unit, i, filter)
                if not ok then return nil end
                if row == nil then return out end
                if hidden(row) or type(row) ~= "table" then return nil end
                name, expires = row.name, row.expirationTime
            else
                local got = { pcall(old, unit, i, filter) }
                if not got[1] then return nil end
                if got[2] == nil then return out end
                name, expires = got[2], got[7]
            end
            if hidden(name) or type(name) ~= "string" then return nil end
            local left
            if expires == nil or hidden(expires) or type(expires) ~= "number" then
                left = true
            elseif expires == 0 then
                left = math.huge
            else
                left = expires - c.now()
            end
            local had = out[name]
            if had == nil or (type(had) == "number" and type(left) == "number" and left > had) or left == true then
                out[name] = left
            end
        end
        return out
    end
    function c.playerBuffs() return aurasOf("player", "HELPFUL", env.UnitBuff) end
    function c.targetDebuffs() return aurasOf("target", "HARMFUL|PLAYER", env.UnitDebuff) end

    -- ------------------------------------------------- shared reads (P-READS)
    -- Lead sections 237 item 4, 243 (N64), 248, 260 item 1; Plexy's
    -- RESEARCH-P-READS.md. Reads only; each answers nil when not known,
    -- never 0, false or an empty list in its place. Every client name here
    -- is a first guess unless the client names table lists it; none was
    -- seen in game.
    local function plainNumber(v)
        return v ~= nil and not hidden(v) and type(v) == "number" and v == v
    end

    -- c.channel() -> { name, spellId, endsAt } | false | nil
    --   UnitChannelInfo("player"): name, text, texture, startMs, endMs,
    --   tradeSkill, notInterruptible, spellId. false: not channelling.
    --   endsAt is in the clock of c.now(). A hidden name or end: nil; a
    --   hidden spellId is left out.
    function c.channel()
        local ok, name, _, _, _, endMs, _, _, id = call(env.UnitChannelInfo, "player")
        if not ok then return nil end
        if name == nil then return false end
        name = text(true, name)
        if name == nil or not plainNumber(endMs) then return nil end
        local out = { name = name, endsAt = endMs / 1000 }
        if plainNumber(id) then out.spellId = id end
        return out
    end

    -- c.weaponEnchant() -> { main = { has, left, charges }, off = ... } or nil
    --   C_Item.GetWeaponEnchantInfo(slot) per hand (0 main, 1 off), a list
    --   of rows or one row { hasEnchant, timeLeft (ms), charges }; an empty
    --   list is a bare hand, no answer a hand not known. Else the old
    --   GetWeaponEnchantInfo() with no argument: hasMain, mainMs,
    --   mainCharges, mainId, hasOff, offMs, offCharges, offId. left is in
    --   seconds. A hidden part is left out; left and charges only for a hand
    --   that has one. nil: no read, a read that raised, or an answer hidden
    --   whole.
    local function enchantHand(row)
        local out = {}
        local has = row.hasEnchant
        if has == nil or hidden(has) or type(has) ~= "boolean" then return out end
        out.has = has
        if not has then return out end
        if plainNumber(row.timeLeft) and row.timeLeft >= 0 then out.left = row.timeLeft / 1000 end
        if plainNumber(row.charges) then out.charges = row.charges end
        return out
    end
    function c.weaponEnchant()
        local items = env.C_Item
        local byHand
        if type(items) == "table" then byHand = items.GetWeaponEnchantInfo end
        if type(byHand) == "function" then
            local out = {}
            local hands = { "main", "off" }
            for slot = 0, 1 do
                local hand = hands[slot + 1]
                local ok, v = pcall(byHand, slot)
                if not ok or (v ~= nil and hidden(v)) then return nil end
                if type(v) == "table" then
                    local row = v
                    if v.hasEnchant == nil then
                        row = v[1]
                        if row ~= nil and hidden(row) then return nil end
                    end
                    if type(row) == "table" then
                        out[hand] = enchantHand(row)
                    else
                        out[hand] = { has = false }
                    end
                else
                    out[hand] = {}
                end
            end
            return out
        end
        local got = { call(env.GetWeaponEnchantInfo) }
        if not got[1] then return nil end
        return {
            main = enchantHand({ hasEnchant = got[2], timeLeft = got[3], charges = got[4] }),
            off = enchantHand({ hasEnchant = got[6], timeLeft = got[7], charges = got[8] }),
        }
    end

    -- c.totems() -> { [slot] = { name, spellId, left } or false } or nil
    --   GetTotemInfo(slot) for slots 1 to 4: haveTotem, name, startTime,
    --   duration, icon, modRate, spellId. false: no totem in the slot. A slot
    --   whose answer or name is hidden is left out; a hidden spellId or time
    --   leaves that field out. nil: no read or a read that raised.
    function c.totems()
        if type(env.GetTotemInfo) ~= "function" then return nil end
        local out = {}
        for slot = 1, 4 do
            local ok, have, name, start, length, _, _, id = call(env.GetTotemInfo, slot)
            if not ok then return nil end
            local there = yesNo(true, have)
            if there == false then
                out[slot] = false
            elseif there then
                name = text(true, name)
                if name ~= nil then
                    local row = { name = name }
                    if plainNumber(id) then row.spellId = id end
                    if plainNumber(start) and plainNumber(length) then row.left = start + length - c.now() end
                    out[slot] = row
                end
            end
        end
        return out
    end

    -- Every row of a unit's buffs, in order, as { name, duration, expires,
    -- caster }: the name from the spell id (spellName) when the row has
    -- none. nil for no read, a read that raised, or a row or a name not
    -- read. caster (review R2-1) is the row's sourceUnit, else UnitBuff's
    -- seventh answer, as given (hidden or nil kept): a first guess, not in
    -- the client names table, not seen in game.
    local function buffRows(unit)
        local auras = env.C_UnitAuras
        local byIndex
        if type(auras) == "table" then byIndex = auras.GetAuraDataByIndex end
        local old = env.UnitBuff
        if type(byIndex) ~= "function" and type(old) ~= "function" then return nil end
        local rows = {}
        for i = 1, 40 do
            local name, length, expires, caster
            if type(byIndex) == "function" then
                local ok, row = pcall(byIndex, unit, i, "HELPFUL")
                if not ok then return nil end
                if row == nil then return rows end
                if hidden(row) or type(row) ~= "table" then return nil end
                name, length, expires, caster = row.name, row.duration, row.expirationTime, row.sourceUnit
                if name == nil and plainNumber(row.spellId) then name = spellName(row.spellId) end
            else
                local got = { pcall(old, unit, i, "HELPFUL") }
                if not got[1] then return nil end
                if got[2] == nil then return rows end
                name, length, expires, caster = got[2], got[6], got[7], got[8]
            end
            if name == nil or hidden(name) or type(name) ~= "string" then return nil end
            rows[#rows + 1] = { name = name, duration = length, expires = expires, caster = caster }
        end
        return rows
    end

    -- c.targetBuffs() -> { [name] = secondsLeft or true } or nil
    --   your target's buffs, read as playerBuffs is, the name from the
    --   spell id when the row gives none. secondsLeft math.huge for no end,
    --   true when the end is not read. No buff: an empty table.
    function c.targetBuffs()
        local rows = buffRows("target")
        if rows == nil then return nil end
        local out = {}
        for _, row in ipairs(rows) do
            local left, expires = true, row.expires
            if plainNumber(expires) then
                if expires == 0 then left = math.huge else left = expires - c.now() end
            end
            local had = out[row.name]
            if had == nil or left == true or (type(had) == "number" and type(left) == "number" and left > had) then
                out[row.name] = left
            end
        end
        return out
    end

    -- c.buffLength(unit, names) -> seconds, name | nil, name | false | nil
    --   The CLIENT NEED from N64: the whole length of the first buff on the
    --   unit that is one of the names, from the client (the row duration;
    --   the fifth answer of UnitBuff). 0 is no end: math.huge. A hidden
    --   length gives nil and the name. false: read, none there. nil: not
    --   known.
    --   c.buffLength(unit, names, true) (review R2-1): only a buff you cast
    --   (the caster "player"); a row of another caster is passed over, and
    --   a caster hidden or not read gives nil and the name.
    function c.buffLength(unit, names, mine)
        if type(unit) ~= "string" or unit == "" or type(names) ~= "table" then return nil end
        local rows = buffRows(unit)
        if rows == nil then return nil end
        local wanted = {}
        for i = 1, #names do
            if type(names[i]) == "string" then wanted[names[i]] = true end
        end
        for _, row in ipairs(rows) do
            local theirs = false
            if wanted[row.name] and mine == true then
                if row.caster == nil or hidden(row.caster) or type(row.caster) ~= "string" then return nil, row.name end
                theirs = row.caster ~= "player"
            end
            if wanted[row.name] and not theirs then
                if not plainNumber(row.duration) then return nil, row.name end
                if row.duration == 0 then return math.huge, row.name end
                return row.duration, row.name
            end
        end
        return false
    end
    -- ------------------------------------------------- end shared reads

    -- c.formName() -> name or nil, known
    --   GetShapeshiftForm(): 0 gives nil, true (no form). A form number gives
    --   the spell name of GetShapeshiftFormInfo(n)'s fourth answer (the
    --   spell id), read as spellName does. Anything not read gives nil,
    --   false. The second answer is the only way to tell "no form" from
    --   "not known".
    function c.formName()
        local ok, n = call(env.GetShapeshiftForm)
        if not ok or hidden(n) or type(n) ~= "number" then return nil, false end
        if n == 0 then return nil, true end
        local got = { call(env.GetShapeshiftFormInfo, n) }
        if not got[1] then return nil, false end
        local id = got[5]
        if hidden(id) or type(id) ~= "number" then return nil, false end
        local name = spellName(id)
        if type(name) ~= "string" then return nil, false end
        return name, true
    end

    -- c.currentSpell(id) -> true | false | nil
    --   C_Spell.IsCurrentSpell(id) where present, else IsCurrentSpell(id).
    --   true when the spell is queued or toggled on (Attack swinging), false
    --   when not; nil when there is no read, it raised, or the answer was
    --   hidden or not a yes or no. A 1 / nil answer of older clients is read
    --   as true / false only for the old global.
    function c.currentSpell(id)
        if type(id) ~= "number" then return nil end
        local group = env.C_Spell
        local fn = type(group) == "table" and group.IsCurrentSpell or nil
        local old = false
        if type(fn) ~= "function" then fn, old = env.IsCurrentSpell, true end
        if type(fn) ~= "function" then return nil end
        local ok, v = pcall(fn, id)
        if not ok or hidden(v) then return nil end
        if type(v) == "boolean" then return v end
        if old and v == 1 then return true end
        if old and v == nil then return false end
        return nil
    end
    -- ----------------------------------------------------------- end 183

    -- ------------------------------------------------------------ flights
    -- DISPATCH section 182 item 2 (RESEARCH-FLIGHTS.md section 6, "New
    -- client functions" 1; legacy Flow Modules/Nav/Nav.lua:2723-2749,
    -- N.ReadTaxiNodes). The flight points on the open flight map:
    --   c.taxiNodes() -> { map = uiMapID or nil, here = name or nil,
    --                      nodes = { { name, x, y, state } ... } } or nil
    -- x, y are shares (0..1) of the flight map `map`. state is "current",
    -- "reachable", "unreachable", or nil when the client gives none it
    -- names (never guessed). here only from a node read plainly as current.
    -- A node whose name or place is hidden, missing or odd is left out.
    -- nil when no node is read: no flight map open, no such calls, a read
    -- that raised, or a hidden list.
    -- Asks GetTaxiMapID, then C_TaxiMap.GetAllTaxiNodes(map) with
    -- Enum.FlightPathState; without them NumTaxiNodes, TaxiNodeGetType
    -- ("CURRENT", "REACHABLE"), TaxiNodePosition, TaxiNodeName. All first
    -- guesses, not seen on 1.60.1 (names from legacy Flow; warcraft.wiki.gg
    -- not checked from here). LOOK ONLY: no node is taken or selected, and
    -- no frame is made.
    local function plainName(v)
        if v == nil or hidden(v) or type(v) ~= "string" or v == "" then return nil end
        return v
    end
    local function plainShare(v)
        if v == nil or hidden(v) or type(v) ~= "number" or v ~= v then return nil end
        return v
    end
    function c.taxiNodes()
        local okMap, map = call(env.GetTaxiMapID)
        if not okMap or map == nil or hidden(map) or type(map) ~= "number" then map = nil end
        local nodes, here = {}, nil
        local group = env.C_TaxiMap
        local all = type(group) == "table" and group.GetAllTaxiNodes or nil
        if map ~= nil and type(all) == "function" then
            local ok, list = call(all, map)
            if not ok or list == nil or hidden(list) or type(list) ~= "table" then return nil end
            local enum = type(env.Enum) == "table" and env.Enum.FlightPathState or nil
            local names = {}
            if type(enum) == "table" then
                for _, pair in ipairs({ { "Current", "current" }, { "Reachable", "reachable" },
                    { "Unreachable", "unreachable" } }) do
                    local v = enum[pair[1]]
                    if v ~= nil then names[v] = pair[2] end
                end
            end
            for _, n in ipairs(list) do
                if type(n) == "table" and not hidden(n) then
                    local name, pos, state = plainName(n.name), n.position, n.state
                    local x, y
                    if name and pos ~= nil and not hidden(pos) and type(pos) == "table" then
                        local okXY, px, py = call(pos.GetXY, pos)
                        if not okXY then px, py = pos.x, pos.y end
                        x, y = plainShare(px), plainShare(py)
                    end
                    if name and x and y then
                        local word = nil
                        if state ~= nil and not hidden(state) then word = names[state] end
                        nodes[#nodes + 1] = { name = name, x = x, y = y, state = word }
                        if word == "current" then here = name end
                    end
                end
            end
        else
            local okN, count = call(env.NumTaxiNodes)
            if not okN or count == nil or hidden(count) or type(count) ~= "number" or count ~= count then
                return nil
            end
            local kinds = { CURRENT = "current", REACHABLE = "reachable" }
            for i = 1, math.min(math.floor(count), 200) do
                local okName, rawName = call(env.TaxiNodeName, i)
                local okPos, px, py = call(env.TaxiNodePosition, i)
                local name = okName and plainName(rawName) or nil
                local x = okPos and plainShare(px) or nil
                local y = okPos and plainShare(py) or nil
                if name and x and y then
                    local okKind, kind = call(env.TaxiNodeGetType, i)
                    local word = nil
                    if okKind and kind ~= nil and not hidden(kind) and type(kind) == "string" then word = kinds[kind] end
                    nodes[#nodes + 1] = { name = name, x = x, y = y, state = word }
                    if word == "current" then here = name end
                end
            end
        end
        if #nodes == 0 then return nil end
        return { map = map, here = here, nodes = nodes }
    end
    -- --------------------------------------------------------- end flights

    -- ------------------------------------------------------- flight marks
    -- Lead DISPATCH section 187 section 7 (CLIENT NEEDs of Nav/TaxiMark.lua
    -- and Nav/MapFlights.lua; legacy Flow 0.35.377 Modules/Nav/TaxiMark.lua
    -- :66-150 and Modules/Nav/MapFlights.lua :300-530). LOOK ONLY: plain
    -- frames that take no mouse, have no template and hold no action. No
    -- node is taken or selected, no CVar is set.
    --
    -- c.taxiMark() -> h, or nil when there is no flight map frame
    -- (TaxiFrame, else FlightMapFrame) or no frame could be made. Hidden
    -- when made.
    --   h.mark(node, text) -> true | false   node = { name, x, y } as
    --       c.taxiNodes() gives it. Rings the game's own button for that
    --       name (TaxiButton<i> where TaxiNodeName(i) is the name and the
    --       button is visible), else stands at the node's share (x right,
    --       y down) of TaxiRouteMap (else the flight map frame). text: the
    --       words under it. false, and hidden, when neither place is known.
    --   h.hide()
    -- All first guesses, not seen on 1.60.1: TaxiFrame, FlightMapFrame,
    -- TaxiRouteMap, TaxiButton<i>, NumTaxiNodes, TaxiNodeName (names from
    -- legacy Flow and the Blizzard classic UI; CLIENT-NAMES-16001.txt was
    -- not reachable from Zen), Region:IsVisible, CreateFontString with
    -- GameFontNormalSmall, SetColorTexture.
    function c.taxiMark()
        local parent = env.TaxiFrame
        if parent == nil then parent = env.FlightMapFrame end
        if parent == nil then return nil end
        local ok, f = call(env.CreateFrame, "Frame", nil, parent)
        if not ok or f == nil then return nil end
        method(f, "Hide")
        method(f, "EnableMouse", false)
        if not method(f, "SetSize", 34, 34) then
            method(f, "SetWidth", 34)
            method(f, "SetHeight", 34)
        end
        local okTex, ring = method(f, "CreateTexture", nil, "OVERLAY")
        if okTex and ring ~= nil then
            method(ring, "SetAllPoints", f)
            if not method(ring, "SetColorTexture", 0.3, 1, 0.4, 0.45) then method(ring, "SetTexture", 0.3, 1, 0.4, 0.45) end
        end
        local okLabel, label = method(f, "CreateFontString", nil, "OVERLAY", "GameFontNormalSmall")
        if not okLabel then label = nil end
        if label ~= nil then method(label, "SetPoint", "TOP", f, "BOTTOM", 0, -2) end

        -- The game's own visible button for a node of that name, or nil.
        local function button(name)
            local okN, count = call(env.NumTaxiNodes)
            if not okN or count == nil or hidden(count) or type(count) ~= "number" or count ~= count then return nil end
            for i = 1, math.min(math.floor(count), 200) do
                local okName, n = call(env.TaxiNodeName, i)
                if okName and n ~= nil and not hidden(n) and n == name then
                    local b = env["TaxiButton" .. i]
                    if b ~= nil then
                        local okV, visible = method(b, "IsVisible")
                        if okV and visible == true then return b end
                    end
                    return nil
                end
            end
            return nil
        end

        local function size(region)
            local okW, w = method(region, "GetWidth")
            local okH, ht = method(region, "GetHeight")
            if not okW or not okH or w == nil or ht == nil or hidden(w) or hidden(ht) then return nil end
            if type(w) ~= "number" or type(ht) ~= "number" or w ~= w or ht ~= ht or w <= 0 or ht <= 0 then return nil end
            return w, ht
        end

        local h = {}
        function h.mark(node, words)
            if type(node) ~= "table" then return false end
            local at = type(node.name) == "string" and button(node.name) or nil
            method(f, "ClearAllPoints")
            if at ~= nil then
                method(f, "SetPoint", "CENTER", at, "CENTER", 0, 0)
            else
                local x, y = node.x, node.y
                local area = env.TaxiRouteMap
                if area == nil then area = parent end
                local w, ht = size(area)
                if type(x) ~= "number" or type(y) ~= "number" or x ~= x or y ~= y or not w then
                    method(f, "Hide")
                    return false
                end
                method(f, "SetPoint", "CENTER", area, "TOPLEFT", x * w, -y * ht)
            end
            if label ~= nil then method(label, "SetText", tostring(words or "")) end
            method(f, "Show")
            return true
        end
        function h.hide() method(f, "Hide") end
        return h
    end

    -- The name of a map as the client says it (C_Map.GetMapInfo(map).name),
    -- or nil. Checked on warcraft.wiki.gg (API C_Map.GetMapInfo). A first
    -- guess on 16001: needs game test.
    function c.mapName(map)
        if type(map) ~= "number" then return nil end
        local ok, info = mapCall("GetMapInfo", map)
        if not ok or type(info) ~= "table" then return nil end
        local name = info.name
        if hidden(name) or type(name) ~= "string" or name == "" then return nil end
        return name
    end

    -- c.mapClick(fn) -> true when the world map will tell of the player's
    -- own Alt + left clicks on it, else nil and a reason. fn(map, x, y):
    -- the uiMapID the map showed when the button went down and where the
    -- cursor was on it then, as shares 0..1 (x right, y down). A click
    -- outside the map, without Alt, or with another button tells nothing.
    -- Hooks only (HookScript OnMouseDown / OnMouseUp on
    -- WorldMapFrame.ScrollContainer): the map's own click still runs, and
    -- nothing is clicked or moved for the player. Where the button went
    -- down is kept, since the map's own click may have changed the map by
    -- the time the button comes up. First guesses, not seen on 16001:
    -- ScrollContainer:GetNormalizedCursorPosition (MapCanvasScrollController
    -- Mixin), HookScript on it, IsAltKeyDown. Needs a game test.
    function c.mapClick(fn)
        if type(fn) ~= "function" then return nil, "no function" end
        local wm = env.WorldMapFrame
        if wm == nil then return nil, "no world map" end
        local okS, scroll = pcall(function() return wm.ScrollContainer end)
        if not okS or scroll == nil then return nil, "no map canvas" end
        local function plain(v) return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge end
        local down
        local okD = method(scroll, "HookScript", "OnMouseDown", function(_, button)
            down = nil
            if button ~= "LeftButton" then return end
            local okA, alt = call(env.IsAltKeyDown)
            if not okA or hidden(alt) or not alt then return end
            local okM, map = method(wm, "GetMapID")
            local okP, x, y = method(scroll, "GetNormalizedCursorPosition")
            if not okM or not okP or hidden(map) or hidden(x) or hidden(y) then return end
            if type(map) ~= "number" or not plain(x) or not plain(y) then return end
            if x < 0 or x > 1 or y < 0 or y > 1 then return end
            down = { map, x, y }
        end)
        local okU = method(scroll, "HookScript", "OnMouseUp", function(_, button)
            local at = down
            down = nil
            if at == nil or button ~= "LeftButton" then return end
            pcall(fn, at[1], at[2], at[3])
        end)
        if not okD or not okU then return nil, "no hook" end
        return true
    end

    -- c.mapPins() -> h, or nil when there is no world map, no canvas
    -- (WorldMapFrame.ScrollContainer.Child) or no frame could be made. One
    -- plain frame over the canvas, no mouse; its dots and lines are made
    -- as needed and kept.
    --   h.map() -> the uiMapID the world map shows, or nil when it is not
    --       shown or will not say (WorldMapFrame:IsShown, :GetMapID).
    --   h.draw(pins, lines)
    --       pins  = { { name, kind = "have" | "new", role, x, y } }
    --       lines = { { from, to, ax, ay, bx, by } }
    --       x, y: shares (x right, y down) of the shown map. Draws these and
    --       hides any made before past their count; a pin or line not placed
    --       by plain numbers is skipped.
    --   h.clear()   hides them all
    -- All first guesses, not seen on 1.60.1: WorldMapFrame, its
    -- ScrollContainer.Child canvas (named in RESEARCH-worldmap-button.md),
    -- IsShown, GetMapID, CreateLine, SetStartPoint, SetEndPoint,
    -- SetThickness, SetColorTexture. The canvas's own scale (legacy
    -- divided by it) is not read: the dots may draw small or large when
    -- the map is zoomed. Needs a game test.
    function c.mapPins()
        local wm = env.WorldMapFrame
        if wm == nil then return nil end
        local okC, canvas = pcall(function() return wm.ScrollContainer.Child end)
        if not okC or canvas == nil then return nil end
        local ok, host = call(env.CreateFrame, "Frame", nil, canvas)
        if not ok or host == nil then return nil end
        method(host, "EnableMouse", false)
        method(host, "SetAllPoints", canvas)
        local dots, lines = {}, {}
        local nDots, nLines = 0, 0
        local COLOUR = {
            from = { 0.3, 1, 0.4 }, to = { 0.3, 1, 0.4 },
            have = { 1, 0.82, 0 }, new = { 0.6, 0.6, 0.6 },
        }
        local function plain(v) return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge end

        local h = {}
        function h.map()
            local okS, shown = method(wm, "IsShown")
            if not okS or shown ~= true then return nil end
            local okM, map = method(wm, "GetMapID")
            if not okM or map == nil or hidden(map) or type(map) ~= "number" or map ~= map then return nil end
            return map
        end
        function h.clear()
            for i = 1, nDots do if dots[i] then method(dots[i], "Hide") end end
            for i = 1, nLines do if lines[i] then method(lines[i], "Hide") end end
            nDots, nLines = 0, 0
        end
        function h.draw(pins, segs)
            local okW, w = method(canvas, "GetWidth")
            local okH, ht = method(canvas, "GetHeight")
            if not okW or not okH or w == nil or ht == nil or hidden(w) or hidden(ht)
                or not plain(w) or not plain(ht) or w <= 0 or ht <= 0 then
                h.clear()
                return false
            end
            local n = 0
            for _, p in ipairs(type(pins) == "table" and pins or {}) do
                if type(p) == "table" and plain(p.x) and plain(p.y) then
                    n = n + 1
                    local d = dots[n]
                    if d == nil then
                        local okT, made = method(host, "CreateTexture", nil, "OVERLAY")
                        d = okT and made or false
                        dots[n] = d
                    end
                    if d then
                        local col = COLOUR[p.role or ""] or COLOUR[p.kind or ""] or COLOUR.new
                        method(d, "SetSize", 10, 10)
                        method(d, "SetColorTexture", col[1], col[2], col[3], 1)
                        method(d, "ClearAllPoints")
                        method(d, "SetPoint", "CENTER", canvas, "TOPLEFT", p.x * w, -p.y * ht)
                        method(d, "Show")
                    end
                end
            end
            for i = n + 1, nDots do if dots[i] then method(dots[i], "Hide") end end
            nDots = n
            local m = 0
            for _, l in ipairs(type(segs) == "table" and segs or {}) do
                if type(l) == "table" and plain(l.ax) and plain(l.ay) and plain(l.bx) and plain(l.by) then
                    m = m + 1
                    local line = lines[m]
                    if line == nil then
                        local okL, made = method(host, "CreateLine", nil, "ARTWORK")
                        line = okL and made or false
                        lines[m] = line
                    end
                    if line then
                        method(line, "SetThickness", 2)
                        method(line, "SetColorTexture", 0.3, 1, 0.4, 0.8)
                        method(line, "SetStartPoint", "TOPLEFT", canvas, l.ax * w, -l.ay * ht)
                        method(line, "SetEndPoint", "TOPLEFT", canvas, l.bx * w, -l.by * ht)
                        method(line, "Show")
                    end
                end
            end
            for i = m + 1, nLines do if lines[i] then method(lines[i], "Hide") end end
            nLines = m
            return true
        end
        return h
    end
    -- --------------------------------------------------- end flight marks

    -- ------------------------------------------------ pet state (section 197)
    -- c.pet() -> nil | { exists = false }
    --          | { exists = true, dead, inCombat, family, happiness, powerKind }
    -- Your own pet, read only; no pet command is ever asked of the client.
    --   nil             not known: UnitExists("pet") is missing, raised, gave
    --                   no plain yes or no, or the answer was secret. It never
    --                   means "no pet".
    --   exists = false  the client says there is no pet; nothing more is asked.
    -- Each other field is nil when not known, never false, 0 or "":
    --   dead       UnitIsDead("pet")
    --   inCombat   UnitAffectingCombat("pet")
    --   family     UnitCreatureFamily("pet"), the client's own word
    --   happiness  GetPetHappiness(): 1, 2, 3 as "unhappy", "content",
    --              "happy" (a first guess at the mapping); nil for a pet
    --              that has none (a demon)
    --   powerKind  UnitPowerType("pet"), the kind of power bar; never an amount
    -- No health or power amount is read (R.FROM_AMOUNT). UnitExists, UnitIsDead,
    -- UnitAffectingCombat and UnitPowerType are functions on 16001 (the names
    -- table); UnitCreatureFamily and GetPetHappiness were not asked yet.
    local PET_HAPPINESS = { "unhappy", "content", "happy" }
    function c.pet()
        local exists = yesNo(call(env.UnitExists, "pet"))
        if exists == nil then return nil end
        if not exists then return { exists = false } end
        local out = { exists = true }
        out.dead = yesNo(call(env.UnitIsDead, "pet"))
        out.inCombat = yesNo(call(env.UnitAffectingCombat, "pet"))
        out.family = text(call(env.UnitCreatureFamily, "pet"))
        local okMood, mood = call(env.GetPetHappiness)
        if okMood and mood ~= nil and not hidden(mood) and type(mood) == "number" then
            out.happiness = PET_HAPPINESS[mood]
        end
        local okKind, kind = call(env.UnitPowerType, "pet")
        if okKind and kind ~= nil and not hidden(kind) and type(kind) == "number" and kind == kind then
            out.powerKind = kind
        end
        -- P-READS (lead section 237 item 4): hurt, a yes or no only; no
        -- amount is kept or handed on. UnitHealth below UnitHealthMax when
        -- both are plain, else UnitHealthPercent (above 1: on a scale of
        -- 100), else not known. UnitHealthPercent is a first guess.
        local okNow, now = call(env.UnitHealth, "pet")
        local okMost, most = call(env.UnitHealthMax, "pet")
        if okNow and okMost and plainNumber(now) and plainNumber(most) and most > 0 then
            out.hurt = now < most
        else
            local okShare, share = call(env.UnitHealthPercent, "pet")
            if okShare and plainNumber(share) then
                if share > 1 then out.hurt = share < 100 else out.hurt = share < 1 end
            end
        end
        return out
    end
    -- ------------------------------------------------------- end pet state

    -- ------------------------------------------------------- craft (P-CRAFT)
    -- The reads and the bar the craft queue needs (lead section 226: #34
    -- Smelt All, G21 the craft bar; UI/CraftBar.lua). Needs game test: every
    -- call here is a first guess on 16001, read from the client names.
    -- Unknown stays unknown: nil is never "nothing needed", "usable" or
    -- "standing still".
    local function wholeId(n)
        return type(n) == "number" and not hidden(n) and n == n and n >= 1 and n < math.huge
            and n == math.floor(n)
    end

    -- Whether the recipe can be made here and now: true; false and the
    -- client reason (disabledReason) when it gives one; nil when not
    -- known. From C_TradeSkillUI.GetRecipeInfo(id): learned, disabled.
    function c.recipeUsable(id)
        if not wholeId(id) then return nil end
        local ui = env.C_TradeSkillUI
        if type(ui) ~= "table" then return nil end
        local ok, info = call(ui.GetRecipeInfo, id)
        if not ok or type(info) ~= "table" then return nil end
        if info.learned == false then return false end
        if info.disabled == true then
            local why = info.disabledReason
            if type(why) == "string" and why ~= "" and not hidden(why) then return false, why end
            return false
        end
        if info.disabled == false and info.learned == true then return true end
        return nil
    end

    -- Whether the player is moving: GetUnitSpeed("player") above 0, else
    -- IsPlayerMoving() when it answers a plain true or false, else nil.
    function c.moving()
        local ok, speed = call(env.GetUnitSpeed, "player")
        if ok and type(speed) == "number" and not hidden(speed) and speed == speed and speed >= 0 then
            return speed > 0
        end
        local okFlag, flag = call(env.IsPlayerMoving)
        if okFlag and type(flag) == "boolean" then return flag end
        return nil
    end

    -- Is the player with this id on the friends list? C_FriendList.IsFriend(
    -- guid): true, false, or nil when the game does not say. A first guess:
    -- not seen in game.
    function c.isFriend(guid)
        if type(guid) ~= "string" or guid == "" then return nil end
        local list = env.C_FriendList
        if type(list) ~= "table" then return nil end
        return yesNo(call(list.IsFriend, guid))
    end

    -- How fast the player is moving, in yards a second: GetUnitSpeed(
    -- "player") (0 standing still), or nil when it cannot be read.
    function c.speed()
        local ok, speed = call(env.GetUnitSpeed, "player")
        if ok and type(speed) == "number" and not hidden(speed) and speed == speed and speed >= 0
            and speed < math.huge then
            return speed
        end
        return nil
    end

    -- A panel of rows (the craft bar): c.panel h, always closable, with
    -- shown() and draw(rows, act). rows, top to bottom:
    --   { kind = "info", text = }
    --   { kind = "number", key =, label =, value =, min =, max =, enabled = }
    --   { kind = "button", key =, label =, enabled = }
    -- A number reads "label: value" with a "-" and a "+": a click asks
    -- act(key, value - 1) or act(key, value + 1), never past min or max; the
    -- panel keeps no value itself, the next draw shows it. A button asks
    -- act(key). act runs under pcall: its error stays in the panel.
    -- enabled == false disables the row buttons. Rows are pooled and a
    -- draw replaces the last one; the frame grows with the rows (no
    -- scrolling). Needs game test: UIPanelButtonTemplate, the row layout.
    local ROW = 20
    function c.rowPanel(spec)
        local own = {}
        for key, v in pairs(type(spec) == "table" and spec or {}) do own[key] = v end
        own.closable = true
        local h, f, isOpen = panelFrame(own)
        if h == nil then return nil end
        h.shown = isOpen
        local width = tonumber(own.width) or 200
        local fonts, buttons = {}, {}

        local function font(i)
            if fonts[i] == nil then
                local ok, made = method(f, "CreateFontString", nil, "OVERLAY", "GameFontNormalSmall")
                if not ok or made == nil then return nil end
                method(made, "SetJustifyH", "LEFT")
                fonts[i] = made
            end
            return fonts[i]
        end
        local function button(i)
            if buttons[i] == nil then
                local ok, made = call(env.CreateFrame, "Button", nil, f, "UIPanelButtonTemplate")
                if not ok or made == nil then ok, made = call(env.CreateFrame, "Button", nil, f) end
                if not ok or made == nil then return nil end
                buttons[i] = made
            end
            return buttons[i]
        end

        function h.draw(rows, act)
            local fontsUsed, buttonsUsed, y = 0, 0, -24
            local function ask(...)
                if type(act) == "function" then pcall(act, ...) end
            end
            local function line(text, room)
                fontsUsed = fontsUsed + 1
                local fs = font(fontsUsed)
                if fs == nil then return end
                method(fs, "ClearAllPoints")
                method(fs, "SetPoint", "TOPLEFT", f, "TOPLEFT", 6, y)
                method(fs, "SetWidth", width - 12 - room)
                method(fs, "SetText", text)
                method(fs, "Show")
            end
            local function push(label, enabled, x, w, onClick)
                buttonsUsed = buttonsUsed + 1
                local b = button(buttonsUsed)
                if b == nil then return end
                method(b, "ClearAllPoints")
                method(b, "SetWidth", w)
                method(b, "SetHeight", ROW - 2)
                method(b, "SetPoint", "TOPLEFT", f, "TOPLEFT", x, y)
                method(b, "SetText", label)
                method(b, enabled and "Enable" or "Disable")
                method(b, "SetScript", "OnClick", function()
                    if enabled then onClick() end
                end)
                method(b, "Show")
            end
            for _, row in ipairs(type(rows) == "table" and rows or {}) do
                if type(row) == "table" then
                    local enabled = row.enabled ~= false
                    local drawn = true
                    if row.kind == "info" then
                        line(tostring(row.text or ""), 0)
                    elseif row.kind == "number" and type(row.value) == "number" then
                        local v = row.value
                        local least = tonumber(row.min) or -math.huge
                        local most = tonumber(row.max) or math.huge
                        line(tostring(row.label) .. ": " .. tostring(v), 54)
                        push("-", enabled, width - 52, 22, function()
                            if v - 1 >= least then ask(row.key, v - 1) end
                        end)
                        push("+", enabled, width - 28, 22, function()
                            if v + 1 <= most then ask(row.key, v + 1) end
                        end)
                    elseif row.kind == "button" then
                        push(tostring(row.label), enabled, 6, width - 12, function() ask(row.key) end)
                    else
                        drawn = false
                    end
                    if drawn then y = y - ROW end
                end
            end
            for i = fontsUsed + 1, #fonts do
                method(fonts[i], "SetText", "")
                method(fonts[i], "Hide")
            end
            for i = buttonsUsed + 1, #buttons do method(buttons[i], "Hide") end
            method(f, "SetHeight", 6 - y)
        end
        return h
    end

    -- ACTING (section 227 item 4, section 234): one ask of the recipe, n
    -- as the game repeat count, only on the player own click on the craft
    -- bar (UI/CraftBar.lua); never from a finish, a timer or the tick.
    -- C_TradeSkillUI.CraftRecipe(id, n). Out of combat only: combat true or
    -- not known asks nothing. -> true | nil, "combat" | "bad" | "noCall" |
    -- "raised". Needs game test: the call and its repeat count.
    function c.craftRecipe(id, n)
        if c.inCombat() ~= false then return nil, "combat" end
        if not wholeId(id) or not wholeId(n) then return nil, "bad" end
        local ui = env.C_TradeSkillUI
        local fn = type(ui) == "table" and ui.CraftRecipe or nil
        if type(fn) ~= "function" then return nil, "noCall" end
        if not pcall(fn, id, n) then return nil, "raised" end
        return true
    end
    -- Section 234: asks the game to stop the repeat of the craft the
    -- player click started (C_TradeSkillUI.StopRecipeRepeat). Not a craft:
    -- it only ends one, so it is asked in combat too. -> true | nil,
    -- "noCall" | "raised". Needs game test: StopRecipeRepeat is in the
    -- 16001 name list, its place under C_TradeSkillUI is a guess.
    function c.stopCraftRepeat()
        local ui = env.C_TradeSkillUI
        local fn = type(ui) == "table" and ui.StopRecipeRepeat or nil
        if type(fn) ~= "function" then return nil, "noCall" end
        if not pcall(fn) then return nil, "raised" end
        return true
    end
    -- ------------------------------------------------------- end craft

    -- ------------------------------------------- spell name by id (CF-32)
    -- c.spellName(id) -> the spell's name, or nil when not read. The same
    -- read the learned-spell watch uses above: C_Spell.GetSpellInfo(id).name
    -- where the client has it, else GetSpellInfo's first answer; no rank.
    -- For your own casts, which the client names by id
    -- (UNIT_SPELLCAST_SUCCEEDED): Rotation/OwnCasts.lua and
    -- Rotation/FormSpells.lua. A first guess, not seen in game.
    function c.spellName(id)
        if type(id) ~= "number" or hidden(id) then return nil end
        local name = spellName(id)
        return name
    end
    -- --------------------------------------------- end spell name by id

    -- ------------------------------------------- your own buffs (N13)
    -- c.ownBuffs() -> { [name] = secondsLeft or true } or nil
    --   the buffs on you that you put up yourself: read as playerBuffs, with
    --   the filter "HELPFUL|PLAYER" (the PLAYER filter targetDebuffs uses
    --   for your own debuffs). Another paladin's aura on you is not in it.
    --   The same not known as playerBuffs. A first guess from the API pages
    --   (API_C_UnitAuras.GetAuraDataByIndex, API_UnitBuff), not seen in game.
    function c.ownBuffs() return aurasOf("player", "HELPFUL|PLAYER", env.UnitBuff) end
    -- ------------------------------------------ end your own buffs

    -- ------------------------------------------------ worn links (P-SETS)
    -- c.wornLinks() -> { [slot] = link } for inventory slots 1..19, or nil
    -- Read only (Gear/Sets.lua saves a set from it). An empty slot is left
    -- out. nil means not known, never "nothing worn": GetInventoryItemLink
    -- is missing, raised for a slot, or gave a secret or non-text answer.
    -- A first guess, not seen in game on 16001 (Flow's Modules/Gear/Sets.lua
    -- saveWorn reads the same call for slots 1..19).
    function c.wornLinks()
        if type(env.GetInventoryItemLink) ~= "function" then return nil end
        local out = {}
        for slot = 1, 19 do
            local ok, link = call(env.GetInventoryItemLink, "player", slot)
            if not ok then return nil end
            if link ~= nil then
                if hidden(link) or type(link) ~= "string" then return nil end
                if link ~= "" then out[slot] = link end
            end
        end
        return out
    end
    -- --------------------------------------------------- end worn links

    -- --------------------------------------------- your group (P-PARTY)
    -- Read only, for the rotation's group step (Rotation/Group.lua): what
    -- it suggests for another player is only shown, never cast. First
    -- guesses, not seen in game on 16001. Each call under pcall; any answer
    -- not given, raised, secret or of the wrong kind is nil (not known).
    -- Your party (party1..4), or in a raid every other raid member
    -- (raid1..40, yourself left out by UnitIsUnit).
    local PARTY_UNITS = { party1 = true, party2 = true, party3 = true, party4 = true }
    -- 243: in a raid, raid1..40 as well.
    for i = 1, 40 do PARTY_UNITS["raid" .. i] = true end

    -- c.party() -> { { unit, name, class, role, power, dead, connected }, ... } | nil
    --   the other players in your party, in party order; {} when you are
    --   alone. nil when whether one is there is not known (UnitExists gave
    --   no yes or no for any party unit). Each field is left out when not
    --   known: name UnitName; class UnitClass's second answer (the token);
    --   role UnitGroupRolesAssigned; power UnitPowerType's first answer (a
    --   kind, never an amount); dead UnitIsDead; connected UnitIsConnected.
    --   The name is for the live caption only: never saved.
    --   Lead section 243: in a raid (UnitExists("raid1")), every other raid
    --   member, raid1..40, you left out by UnitIsUnit(unit, "player"); nil
    --   when that cannot be told for one of them.
    function c.party()
        local out = {}
        local inRaid = yesNo(call(env.UnitExists, "raid1"))
        if inRaid == nil then return nil end
        local prefix, last = "party", 4
        if inRaid then prefix, last = "raid", 40 end
        for i = 1, last do
            local unit = prefix .. i
            local there = yesNo(call(env.UnitExists, unit))
            if there == nil then return nil end
            if there and inRaid then
                local you = yesNo(call(env.UnitIsUnit, unit, "player"))
                if you == nil then return nil end
                if you then there = false end
            end
            if there then
                local row = { unit = unit }
                -- 248 PP2-2: the realm (UnitName's second answer) and the
                -- GUID, for memory of your casts only: never saved.
                local okName, name, realm = call(env.UnitName, unit)
                row.name = text(okName, name)
                row.realm = text(okName, realm)
                row.guid = text(call(env.UnitGUID, unit))
                local okClass, _, class = call(env.UnitClass, unit)
                row.class = text(okClass, class)
                row.role = text(call(env.UnitGroupRolesAssigned, unit))
                local okPower, power = call(env.UnitPowerType, unit)
                if okPower and power ~= nil and not hidden(power) and type(power) == "number" and power == power then
                    row.power = power
                end
                row.dead = yesNo(call(env.UnitIsDead, unit))
                row.connected = yesNo(call(env.UnitIsConnected, unit))
                out[#out + 1] = row
            end
        end
        return out
    end

    -- c.reach(spellId, unit) -> true | false | nil
    --   C_Spell.IsSpellInRange(id, unit) for a party unit: in reach of that
    --   spell (which also says they are there and in sight); nil for no
    --   answer, and for any unit that is not party1..4 (not asked).
    function c.reach(spellId, unit)
        if type(spellId) ~= "number" or not PARTY_UNITS[unit] then return nil end
        local group = env.C_Spell
        if type(group) ~= "table" then return nil end
        return yesNo(call(group.IsSpellInRange, spellId, unit))
    end

    -- c.unitDebuffTypes(unit) -> { [type] = debuff name } | nil
    --   the curses, poisons, diseases and magic on you ("player") or a party
    --   member, by type (C_UnitAuras.GetAuraDataByIndex(unit, i, "HARMFUL"),
    --   the row's dispelName), the first debuff's name for each type ({}
    --   when nothing removable is on them). nil when not known: no call, a
    --   raise, or a row or a type the client hides. At most 40 rows.
    function c.unitDebuffTypes(unit)
        if unit ~= "player" and not PARTY_UNITS[unit] then return nil end
        local auras = env.C_UnitAuras
        local byIndex = type(auras) == "table" and auras.GetAuraDataByIndex or nil
        if type(byIndex) ~= "function" then return nil end
        local out = {}
        for i = 1, 40 do
            local ok, row = pcall(byIndex, unit, i, "HARMFUL")
            if not ok then return nil end
            if row == nil then return out end
            if hidden(row) or type(row) ~= "table" then return nil end
            local kind = row.dispelName
            if kind ~= nil then
                if hidden(kind) or type(kind) ~= "string" then return nil end
                if kind ~= "" and out[kind] == nil then
                    local name = row.name
                    if name == nil or hidden(name) or type(name) ~= "string" or name == "" then name = kind end
                    out[kind] = name
                end
            end
        end
        return out
    end

    -- The icon's caption: h.caption(text) on an icon c.icon made, a line
    -- of text under it ("Mark of the Wild on <name>"); nil or "" hides it.
    -- The live screen only: nothing is kept. Made the first time it is
    -- asked for, on the icon's frame, found by the name the icon was made
    -- with (spec.name); an icon with no name, or whose frame is not found,
    -- has no caption. A first guess, not seen in game.
    do
        local plainIcon = c.icon
        function c.icon(spec)
            local h = plainIcon(spec)
            if type(h) ~= "table" or type(spec) ~= "table" or type(spec.name) ~= "string" then return h end
            local okFrame, frame = pcall(function() return env[spec.name] end)
            if not okFrame or frame == nil then return h end
            -- Lead section 243: the look-only mark, a blue tint over the
            -- picture (made the first time it is asked for). "look" puts
            -- the picture's own colour back and shows the tint; any other
            -- mark hides the tint and goes to the icon's own mark.
            local plainMark, tint = h.mark, nil
            function h.mark(look, ...)
                if look == "look" then
                    if tint == nil then
                        local okMade, made = method(frame, "CreateTexture", nil, "OVERLAY")
                        if not okMade or made == nil then return false end
                        tint = made
                        method(tint, "SetAllPoints", frame)
                        method(tint, "SetColorTexture", 0.35, 0.65, 1, 0.45)
                    end
                    if type(plainMark) == "function" then pcall(plainMark, nil) end
                    local okShow = method(tint, "Show")
                    return okShow and true or false
                end
                if tint ~= nil then method(tint, "Hide") end
                if type(plainMark) ~= "function" then return false end
                return plainMark(look, ...)
            end
            local line
            function h.caption(words)
                local shown = type(words) == "string" and words ~= ""
                if line == nil then
                    if not shown then return true end
                    local okMade, made = method(frame, "CreateFontString", nil, "OVERLAY", "GameFontNormalSmall")
                    if not okMade or made == nil then return false end
                    line = made
                    method(line, "SetPoint", "TOP", frame, "BOTTOM", 0, -2)
                end
                local okSet = method(line, "SetText", shown and words or "")
                method(line, shown and "Show" or "Hide")
                return okSet and true or false
            end
            return h
        end
    end
    -- ----------------------------------------------- end your group
    -- ---------------------------------------------------------------- N55
    -- The boss loot panel (lead sections 237 item 5 and 238 item 4, owner
    -- Zen; RESEARCH-N55): the boss unit, whether you are in an instance,
    -- and the item of anyone's loot line. Read only: no unit is targeted,
    -- nothing is looted, rolled on or said. Every call here is a first
    -- guess, not seen in game on 16001; an answer that cannot be read is
    -- left out, never a default. The capture asks each name (Diag.NAMES).

    -- c.bossUnit() -> { exists, guid, name } | nil
    --   the unit "boss1" (the game's first boss frame): UnitExists,
    --   UnitGUID, UnitName. nil when the client does not say whether there
    --   is one; { exists = false } when it says there is none, and then
    --   nothing more is asked. guid and name are each left out when not
    --   read. Only "boss1" is named.
    function c.bossUnit()
        local exists = yesNo(call(env.UnitExists, "boss1"))
        if exists == nil then return nil end
        if not exists then return { exists = false } end
        return {
            exists = true,
            guid = text(call(env.UnitGUID, "boss1")),
            name = text(call(env.UnitName, "boss1")),
        }
    end

    -- c.instance() -> { inside, kind } | nil
    --   whether you are in an instance: IsInInstance() (inside, and the
    --   kind as the game names it: "party", "raid", "none", ...); else the
    --   second answer of GetInstanceInfo(), where "none" is not inside.
    --   nil when neither says.
    function c.instance()
        local ok, inside, kind = call(env.IsInInstance)
        if yesNo(ok, inside) ~= nil then
            return { inside = inside, kind = text(ok, kind) }
        end
        local okInfo, _, infoKind = call(env.GetInstanceInfo)
        infoKind = text(okInfo, infoKind)
        if infoKind == nil then return nil end
        return { inside = infoKind ~= "none", kind = infoKind }
    end

    -- c.lootLine(line) -> item link, count | nil
    --   the item of a CHAT_MSG_LOOT line, whoever looted it: your own
    --   (LOOT_ITEM_SELF_MULTIPLE, LOOT_ITEM_SELF) or another player's
    --   (LOOT_ITEM_MULTIPLE, LOOT_ITEM), by the client's own texts; no
    --   English is written here. The looter's name is matched and dropped:
    --   it is never returned. count is 1 when the line names none. nil for
    --   a line that is none of the four (a roll, something made or
    --   bought), one with no item link, or a client without the texts.
    function c.lootLine(line)
        if type(line) ~= "string" or line == "" or hidden(line) then return nil end
        local forms = { env.LOOT_ITEM_SELF_MULTIPLE or false, env.LOOT_ITEM_SELF or false,
                        env.LOOT_ITEM_MULTIPLE or false, env.LOOT_ITEM or false }
        for f = 1, 4 do
            local pattern, kinds = lootPattern(forms[f])
            if pattern then
                local caps = { line:match(pattern) }
                if #caps > 0 and #caps == #kinds then
                    local link, count = nil, nil
                    for i = 1, #kinds do
                        if kinds[i] == "d" then
                            count = tonumber(caps[i])
                        elseif type(caps[i]) == "string" and caps[i]:find("item:%d+") then
                            link = caps[i]
                        end
                    end
                    if link then return link, count or 1 end
                end
            end
        end
        return nil
    end
    -- ------------------------------------------------------------ end N55
    -- ------------------------------------------------------------ N59
    -- N59 (lead section 243): the info bar. c.infoBar(spec) makes one plain
    -- frame (never a secure template, no attribute set) with a dark backing,
    -- one text and a resize grip; it returns a handle, or nil when the
    -- client makes no frame. spec: name, width, height.
    -- h.setText(s), h.show(on), h.font(size), h.alpha(a) (backing 0..1),
    -- h.size(w, h), h.place(point), h.lock(on), h.onMoved(fn(point)),
    -- h.onResized(fn(w, h)), h.onClick(fn(button)), h.onHover(fn(on)),
    -- h.tip(lines) (nil hides the tip it showed).
    -- A drag is not a click: the release that ends a drag says nothing.
    -- Every handler the add-on gives runs under pcall; an error is dropped
    -- here, the caller records its own.
    -- Docs (warcraft.wiki.gg), not seen in game on 16001: Frame
    -- SetResizable, StartSizing("BOTTOMRIGHT"), SetResizeBounds;
    -- FontString GetFont / SetFont(path, size, flags); UIHANDLER OnEnter,
    -- OnLeave, OnMouseUp(button), OnMouseDown(button). Needs game test.
    function c.infoBar(spec)
        spec = type(spec) == "table" and spec or {}
        local parent = env.UIParent
        local ok, f = call(env.CreateFrame, "Frame", spec.name, parent)
        if not ok or f == nil then return nil end
        local h = {}
        local width, height = tonumber(spec.width) or 300, tonumber(spec.height) or 20
        local locked, dragged = false, false
        local moved, resized, clicked, hovered
        local tipped = false

        method(f, "Hide")
        if not method(f, "SetSize", width, height) then
            method(f, "SetWidth", width)
            method(f, "SetHeight", height)
        end
        method(f, "SetFrameStrata", "MEDIUM")
        method(f, "SetClampedToScreen", true)

        -- Lead sections 320 and 350: the shared look, from the one theme file
        -- (UI/Kit/Theme.lua, read when the bar is made): its fill, a thin
        -- edge and its small font; the bar keeps its own layout. Without the
        -- theme: the old black backing and font, no edge.
        local look = type(ns.Kit) == "table" and type(ns.Kit.look) == "table" and ns.Kit.look or nil
        local fill, edgeColor, edgeSize, barFont = { 0, 0, 0 }, nil, 1, "GameFontNormalSmall"
        if look ~= nil and type(look.color) == "table" then
            if type(look.color.fill) == "table" then fill = look.color.fill end
            if type(look.color.edge) == "table" then edgeColor = look.color.edge end
        end
        if look ~= nil and type(look.size) == "table" and type(look.size.edge) == "number" then edgeSize = look.size.edge end
        if look ~= nil and type(look.font) == "table" and type(look.font.small) == "string" then barFont = look.font.small end

        local okBg, bg = method(f, "CreateTexture", nil, "BACKGROUND")
        if not okBg then bg = nil end
        if bg ~= nil then
            method(bg, "SetAllPoints", f)
            if not method(bg, "SetColorTexture", fill[1], fill[2], fill[3], 0.6) then
                method(bg, "SetTexture", fill[1], fill[2], fill[3], 0.6)
            end
        end
        if edgeColor ~= nil then
            for _, side in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" },
                { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
                local okE, line = method(f, "CreateTexture", nil, "BORDER")
                if okE and line ~= nil then
                    method(line, "SetPoint", side[1], f, side[1], 0, 0)
                    method(line, "SetPoint", side[2], f, side[2], 0, 0)
                    if side[1] == "TOPLEFT" and side[2] == "TOPRIGHT" or side[1] == "BOTTOMLEFT" then
                        method(line, "SetHeight", edgeSize)
                    else
                        method(line, "SetWidth", edgeSize)
                    end
                    method(line, "SetColorTexture", edgeColor[1], edgeColor[2], edgeColor[3], edgeColor[4])
                end
            end
        end

        local okText, text = method(f, "CreateFontString", nil, "OVERLAY", barFont)
        if not okText then text = nil end
        if text ~= nil then
            method(text, "SetPoint", "TOPLEFT", f, "TOPLEFT", 6, -4)
            method(text, "SetPoint", "BOTTOMRIGHT", f, "BOTTOMRIGHT", -6, 4)
            method(text, "SetJustifyH", "LEFT")
            method(text, "SetJustifyV", "TOP")
        end

        local function tell(fn, ...)
            if type(fn) == "function" then pcall(fn, ...) end
        end

        local function standing()
            local okP, a, _, r, x, y = method(f, "GetPoint", 1)
            if okP and type(a) == "string" and type(x) == "number" and type(y) == "number" then
                return { a, type(r) == "string" and r or a, x, y }
            end
            return nil
        end

        method(f, "SetMovable", true)
        method(f, "SetResizable", true)
        method(f, "SetResizeBounds", 60, 14)
        method(f, "EnableMouse", true)
        method(f, "RegisterForDrag", "LeftButton")
        method(f, "SetScript", "OnDragStart", function()
            if locked then return end
            dragged = true
            method(f, "StartMoving")
        end)
        method(f, "SetScript", "OnDragStop", function()
            method(f, "StopMovingOrSizing")
            method(f, "SetUserPlaced", false)
            local point = standing()
            if point then tell(moved, point) end
        end)
        method(f, "SetScript", "OnMouseUp", function(_, button)
            if dragged then
                dragged = false
                return
            end
            tell(clicked, button)
        end)
        method(f, "SetScript", "OnEnter", function() tell(hovered, true) end)
        method(f, "SetScript", "OnLeave", function() tell(hovered, false) end)

        -- The grip: a small plain button at the lower right corner.
        local okG, grip = call(env.CreateFrame, "Button", nil, f)
        if okG and grip ~= nil then
            method(grip, "SetSize", 10, 10)
            method(grip, "SetPoint", "BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
            method(grip, "EnableMouse", true)
            method(grip, "SetScript", "OnMouseDown", function()
                if locked then return end
                method(f, "StartSizing", "BOTTOMRIGHT")
            end)
            method(grip, "SetScript", "OnMouseUp", function()
                method(f, "StopMovingOrSizing")
                if locked then return end
                local okW, w = method(f, "GetWidth")
                local okH, ht = method(f, "GetHeight")
                if okW and okH and type(w) == "number" and type(ht) == "number" then tell(resized, w, ht) end
            end)
        end

        function h.setText(s)
            if text ~= nil then method(text, "SetText", tostring(s or "")) end
        end
        function h.show(on) method(f, on and "Show" or "Hide") end
        function h.font(size)
            size = tonumber(size)
            if text == nil or size == nil then return end
            local okF, path, _, flags = method(text, "GetFont")
            if okF and type(path) == "string" then method(text, "SetFont", path, size, flags or "") end
        end
        function h.alpha(a)
            a = tonumber(a)
            if bg == nil or a == nil then return end
            if not method(bg, "SetColorTexture", fill[1], fill[2], fill[3], a) then
                method(bg, "SetTexture", fill[1], fill[2], fill[3], a)
            end
        end
        function h.size(w, ht)
            w, ht = tonumber(w), tonumber(ht)
            if w == nil or ht == nil then return end
            method(f, "SetSize", w, ht)
        end
        function h.place(point)
            if type(point) ~= "table" then return end
            method(f, "ClearAllPoints")
            method(f, "SetPoint", point[1], parent, point[2], point[3], point[4])
        end
        function h.lock(on) locked = on and true or false end
        function h.onMoved(fn) moved = fn end
        function h.onResized(fn) resized = fn end
        function h.onClick(fn) clicked = fn end
        function h.onHover(fn) hovered = fn end
        function h.tip(lines)
            local tip = env.GameTooltip
            if tip == nil then return end
            if type(lines) ~= "table" or #lines == 0 then
                if tipped then
                    local okO, owned = method(tip, "IsOwned", f)
                    if okO and owned then method(tip, "Hide") end
                end
                tipped = false
                return
            end
            method(tip, "SetOwner", f, "ANCHOR_BOTTOM")
            method(tip, "ClearLines")
            for i, line in ipairs(lines) do
                if i == 1 then method(tip, "AddLine", tostring(line), 1, 1, 1)
                else method(tip, "AddLine", tostring(line), 0.8, 0.8, 0.8, true) end
            end
            method(tip, "Show")
            tipped = true
        end
        return h
    end

    -- c.xp() -> {cur, max, rested} or nil. rested is 0 when the client says
    -- nil (not rested). nil when the required amount is not above 0.
    -- Docs: UnitXP, UnitXPMax, GetXPExhaustion. Needs game test.
    function c.xp()
        local okC, cur = call(env.UnitXP, "player")
        local okM, max = call(env.UnitXPMax, "player")
        if not okC or not okM or hidden(cur) or hidden(max) then return nil end
        if type(cur) ~= "number" or type(max) ~= "number" or cur ~= cur or max ~= max then return nil end
        if max <= 0 or cur < 0 then return nil end
        local okR, rested = call(env.GetXPExhaustion)
        if not okR or rested == nil or hidden(rested) or type(rested) ~= "number" or rested ~= rested then rested = 0 end
        return { cur = cur, max = max, rested = rested }
    end

    -- c.watchedFaction() -> {name, standing, label, min, max, value}, false
    -- when none is watched, nil when not known. C_Reputation
    -- .GetWatchedFactionData first (newer clients), else
    -- GetWatchedFactionInfo (name, standing, min, max, value). The label is
    -- the client's FACTION_STANDING_LABEL<n> string (FACTION_STANDING_LABEL1
    -- and up). Docs only, not seen in game on 16001. Needs game test.
    function c.watchedFaction()
        local name, standing, low, high, value
        local rep = type(env.C_Reputation) == "table" and env.C_Reputation or {}
        local okN, data = call(rep.GetWatchedFactionData)
        if okN and type(data) == "table" then
            name, standing = data.name, data.reaction
            low, high, value = data.currentReactionThreshold, data.nextReactionThreshold, data.currentStanding
        elseif okN and data == nil and rep.GetWatchedFactionData ~= nil then
            return false
        else
            local ok
            ok, name, standing, low, high, value = call(env.GetWatchedFactionInfo)
            if not ok then return nil end
            if name == nil then return false end
        end
        if hidden(name) or type(name) ~= "string" then return nil end
        for _, v in ipairs({ standing, low, high, value }) do
            if hidden(v) or type(v) ~= "number" or v ~= v then return nil end
        end
        local label = env["FACTION_STANDING_LABEL" .. tostring(standing)]
        if type(label) ~= "string" or hidden(label) then label = nil end
        return { name = name, standing = standing, label = label, min = low, max = high, value = value }
    end

    -- c.gameTime() -> {hour, minute} server time, or nil. Docs: GetGameTime.
    function c.gameTime()
        local ok, hour, minute = call(env.GetGameTime)
        hour, minute = whole(ok, hour), whole(ok, minute)
        if hour == nil or minute == nil or hour > 23 or minute > 59 then return nil end
        return { hour = hour, minute = minute }
    end

    -- c.framerate() -> whole frames a second, or nil. Docs: GetFramerate.
    function c.framerate()
        local ok, n = call(env.GetFramerate)
        if not ok or hidden(n) or type(n) ~= "number" or n ~= n or n < 0 or n == math.huge then return nil end
        return math.floor(n)
    end

    -- c.latency() -> {home, world} in ms, or nil. GetNetStats answers
    -- bandwidth in, out, home latency, world latency. Docs only.
    function c.latency()
        local ok, _, _, home, world = call(env.GetNetStats)
        home, world = whole(ok, home), whole(ok, world)
        if home == nil or world == nil then return nil end
        return { home = home, world = world }
    end

    -- c.broker(name, obj) -> the data object LibDataBroker-1.1 made, or nil
    -- when LibStub or the library is not loaded. The add-on never loads
    -- either itself. Docs (LibDataBroker-1.1 README): NewDataObject(name,
    -- table). Needs game test.
    function c.broker(name, obj)
        if type(name) ~= "string" or type(obj) ~= "table" then return nil end
        local okL, lib = call(env.LibStub, "LibDataBroker-1.1", true)
        if not okL or type(lib) ~= "table" then return nil end
        local okD, made = pcall(function() return lib:NewDataObject(name, obj) end)
        if not okD or made == nil then return nil end
        return made
    end
    -- ------------------------------------------------------------ end N59

    -- ------------------------------------------------- text entry (N73)
    -- c.textEntry(spec) -> h, or nil when the client cannot make one. A
    -- small plain frame with a line of words and ONE edit box, for a line
    -- the player types (UI/Feedback.lua). spec = { name = global frame
    -- name or nil, width }. A new one is hidden.
    --   h.ask(words, text, fn)  shows it with `words` above the box and
    --                           `text` in it; fn(typed) is told once, when
    --                           the player presses Enter, after it is hidden
    --   h.show(false)           hides it; nothing is told
    --   h.shown() -> true while it is on the screen
    -- Escape hides it and tells nothing. As the copy box, it never takes
    -- the keyboard by itself (auto-focus off: the player clicks in the box)
    -- and gives focus back whenever it is hidden; a client that will not
    -- turn auto-focus off gets none. It is a plain Frame and EditBox: no
    -- secure template, no attribute, nothing of the game's is opened, and
    -- what is typed goes only to fn. A first guess, not seen in game; every
    -- name is one the copy box and the Options page already use
    -- (CreateFrame, InputBoxTemplate, SetAutoFocus, OnEnterPressed,
    -- OnEscapePressed, SetColorTexture).
    function c.textEntry(spec)
        spec = type(spec) == "table" and spec or {}
        local name = spec.name
        if type(name) ~= "string" or name == "" or env[name] ~= nil then name = nil end
        local ok, f = call(env.CreateFrame, "Frame", name, env.UIParent)
        if not ok or f == nil then return nil end
        method(f, "Hide")
        local width = tonumber(spec.width) or 420
        method(f, "SetSize", width, 70)
        method(f, "SetPoint", "CENTER", env.UIParent, "CENTER", 0, 140)
        method(f, "SetFrameStrata", "DIALOG")
        method(f, "EnableMouse", true)
        local okB, back = method(f, "CreateTexture", nil, "BACKGROUND")
        if okB and back ~= nil then
            method(back, "SetAllPoints", f)
            method(back, "SetColorTexture", 0.05, 0.05, 0.05, 0.92)
        end
        local okT, title = method(f, "CreateFontString", nil, "OVERLAY", "GameFontNormal")
        if not okT then title = nil end
        if title ~= nil then method(title, "SetPoint", "TOPLEFT", f, "TOPLEFT", 12, -10) end
        local okE, edit = call(env.CreateFrame, "EditBox", nil, f, "InputBoxTemplate")
        if not okE or edit == nil then return nil end
        if not method(edit, "SetAutoFocus", false) then return nil end
        method(edit, "SetSize", width - 32, 20)
        method(edit, "SetPoint", "TOPLEFT", f, "TOPLEFT", 18, -36)

        local h, told = {}, nil
        local function close()
            method(edit, "ClearFocus")
            method(f, "Hide")
        end
        method(edit, "SetScript", "OnEnterPressed", function(self)
            local okG, typed = method(self, "GetText")
            local fn = told
            told = nil
            close()
            if fn and okG and type(typed) == "string" and not hidden(typed) then pcall(fn, typed) end
        end)
        method(edit, "SetScript", "OnEscapePressed", function()
            told = nil
            close()
        end)
        method(f, "SetScript", "OnHide", function() method(edit, "ClearFocus") end)
        function h.ask(words, text, fn)
            told = nil
            if type(fn) == "function" then told = fn end
            local shownWords, shownText = "", ""
            if type(words) == "string" then shownWords = words end
            if type(text) == "string" then shownText = text end
            if title ~= nil then method(title, "SetText", shownWords) end
            method(edit, "SetText", shownText)
            method(f, "Show")
        end
        function h.show(on)
            if on then return end
            told = nil
            close()
        end
        function h.shown()
            local okV, on = method(f, "IsVisible")
            return okV and on == true
        end
        return h
    end
    -- --------------------------------------------- end text entry
    -- ---------------------------------------------------------- N57 keys
    -- Key bindings for the rotation key (lead section 249 item 2; Plexy's
    -- note 1 of section 250, from CLIENT-NAMES-16001, wowless's 1.60.1 API
    -- list and the game's own Blizzard_Keybindings.lua). Added at the end:
    -- no handle above is changed. Called only from the settings page on the
    -- player's own key press (UI/SettingsKeys.lua); nothing here binds on
    -- load, on an event or on a timer.
    --   reads (allowed in combat; nil when the client does not say):
    --   c.bindingKeys(action) -> { key, ... }   GetBindingKey(action, nil,
    --       context); an empty list when none is bound
    --   c.bindingAction(key, forAction) -> action text, "" for none;
    --       GetBindingAction(key, nil, context) - in wowless and the game's
    --       panel, never asked of 16001 (a capture field)
    --   The context is C_KeyBindings.GetBindingContextForAction(action),
    --   passed when the client gives one (Plexy, change 1).
    --   writes (acting; each refused with "lockdown" while InCombatLockdown
    --   is not a plain false - not known counts as locked; false and why,
    --   never an error):
    --   c.setBindingClick(key, button) -> SetBindingClick(key, button, "LeftButton")
    --   c.clearBinding(key, forAction) -> SetBinding(key, nil, context)
    --   c.saveBindings()               -> SaveBindings(GetCurrentBindingSet())
    --   c.overrideBindingClick(key, button) -> SetOverrideBindingClick(owner,
    --       true, key, button, "LeftButton"): for this session only, the
    --       game's own binding kept under it; owner is a frame of the client's
    --   c.clearOverrideKeys()          -> ClearOverrideBindings(owner)
    --   the overlay (show):
    --   c.keyCapture(spec) -> h | nil   spec = { name } a full-screen button
    --       that takes the keyboard (legacy Flow's Modules/Settings.lua:920:
    --       EnableKeyboard, SetPropagateKeyboardInput(false), OnKeyDown)
    --     h.start(text, onKey, onCancel) -> true   shows it with text; the
    --       next key press: Escape -> onCancel(); a bare modifier
    --       (IsKeyPressIgnoredForBinding, else the modifier keys) waits;
    --       any other -> onKey(chord), the chord from
    --       CreateKeyChordStringUsingMetaKeyState(key), else ALT-CTRL-SHIFT-
    --       from the modifiers held. It hides itself before either is called.
    --     h.stop()   hides it;  h.open() -> true while it waits
    --   Mouse buttons are not taken. First guesses: not seen in game.
    local function bindingContext(action)
        local group = env.C_KeyBindings
        if type(action) ~= "string" or type(group) ~= "table" then return nil end
        local ok, context = call(group.GetBindingContextForAction, action)
        if not ok or context == nil or hidden(context) then return nil end
        return context
    end
    -- true only when the lock is read and is plainly off.
    local function unlocked()
        local ok, locked = call(env.InCombatLockdown)
        return ok and locked == false
    end
    local function bindingCall(fn, ...)
        if not unlocked() then return false, "lockdown" end
        if type(fn) ~= "function" then return false, "absent" end
        local ok, result = pcall(fn, ...)
        if not ok then return false, tostring(result) end
        if result == false then return false, "refused" end
        return true
    end

    function c.bindingKeys(action)
        if type(action) ~= "string" then return nil end
        local context = bindingContext(action)
        local got
        if context ~= nil then
            got = { call(env.GetBindingKey, action, nil, context) }
        else
            got = { call(env.GetBindingKey, action) }
        end
        if not got[1] then return nil end
        local keys = {}
        for i = 2, table.maxn(got) do
            local key = got[i]
            if type(key) == "string" and key ~= "" and not hidden(key) then keys[#keys + 1] = key end
        end
        return keys
    end

    function c.bindingAction(key, forAction)
        if type(key) ~= "string" or key == "" then return nil end
        local context = bindingContext(forAction)
        local ok, action
        if context ~= nil then
            ok, action = call(env.GetBindingAction, key, nil, context)
        else
            ok, action = call(env.GetBindingAction, key)
        end
        if not ok or hidden(action) then return nil end
        if action == nil then return "" end
        if type(action) ~= "string" then return nil end
        return action
    end

    -- S23 (P-KEYS slice B): what the key does with override bindings
    -- counted, the binding that wins when the key is pressed (a click-cast
    -- add-on's override, ours, else the game's own): GetBindingAction(key,
    -- true[, context]). A read only, for the click-casting check line
    -- (UI/ClickCheck.lua). "" for nothing bound, nil when not known.
    -- First guess: the checkOverride argument is not seen in game.
    function c.bindingOverride(key, forAction)
        if type(key) ~= "string" or key == "" then return nil end
        local context = bindingContext(forAction)
        local ok, action
        if context ~= nil then
            ok, action = call(env.GetBindingAction, key, true, context)
        else
            ok, action = call(env.GetBindingAction, key, true)
        end
        if not ok or hidden(action) then return nil end
        if action == nil then return "" end
        if type(action) ~= "string" then return nil end
        return action
    end

    function c.setBindingClick(key, button)
        if type(key) ~= "string" or type(button) ~= "string" then return false, "no key" end
        return bindingCall(env.SetBindingClick, key, button, "LeftButton")
    end

    function c.clearBinding(key, forAction)
        if type(key) ~= "string" then return false, "no key" end
        local context = bindingContext(forAction)
        if context ~= nil then return bindingCall(env.SetBinding, key, nil, context) end
        return bindingCall(env.SetBinding, key)
    end

    function c.saveBindings()
        if not unlocked() then return false, "lockdown" end
        local ok, set = call(env.GetCurrentBindingSet)
        if not ok or type(set) ~= "number" then return false, "the game did not say which binding set is in use" end
        return bindingCall(env.SaveBindings, set)
    end

    local overrideOwner
    function c.overrideBindingClick(key, button)
        if type(key) ~= "string" or type(button) ~= "string" then return false, "no key" end
        if not unlocked() then return false, "lockdown" end
        if not overrideOwner then overrideOwner = newFrame() end
        if not overrideOwner then return false, "no frame" end
        return bindingCall(env.SetOverrideBindingClick, overrideOwner, true, key, button, "LeftButton")
    end

    function c.clearOverrideKeys()
        if not unlocked() then return false, "lockdown" end
        if not overrideOwner then return true end
        return bindingCall(env.ClearOverrideBindings, overrideOwner)
    end

    local MODIFIER_KEYS = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true,
                            LMETA = true, RMETA = true, UNKNOWN = true }
    local function bareModifier(key)
        local ok, ignored = call(env.IsKeyPressIgnoredForBinding, key)
        if ok then return ignored == true end
        return MODIFIER_KEYS[key] == true
    end
    local function chordOf(key)
        local ok, chord = call(env.CreateKeyChordStringUsingMetaKeyState, key)
        if ok and type(chord) == "string" and chord ~= "" and not hidden(chord) then return chord end
        local prefix = ""
        for _, m in ipairs({ { env.IsAltKeyDown, "ALT-" }, { env.IsControlKeyDown, "CTRL-" },
                             { env.IsShiftKeyDown, "SHIFT-" } }) do
            local okM, down = call(m[1])
            if okM and down == true then prefix = prefix .. m[2] end
        end
        return prefix .. key
    end

    function c.keyCapture(spec)
        spec = type(spec) == "table" and spec or {}
        local ok, f = call(env.CreateFrame, "Button", spec.name, env.UIParent)
        if not ok or type(f) ~= "table" then return nil end
        method(f, "SetAllPoints", env.UIParent)
        method(f, "SetFrameStrata", "FULLSCREEN_DIALOG")
        method(f, "EnableMouse", true)
        local okT, label = method(f, "CreateFontString", nil, "OVERLAY", "GameFontNormalLarge")
        if not okT then label = nil end
        if label then method(label, "SetPoint", "CENTER", f, "CENTER", 0, 0) end
        method(f, "Hide")
        local h, waiting, onKey, onCancel = {}, false, nil, nil
        local function finish()
            waiting = false
            method(f, "EnableKeyboard", false)
            method(f, "Hide")
        end
        method(f, "SetScript", "OnKeyDown", function(_, key)
            if not waiting or type(key) ~= "string" or hidden(key) then return end
            if key == "ESCAPE" then
                local cancel = onCancel
                finish()
                if type(cancel) == "function" then pcall(cancel) end
                return
            end
            if bareModifier(key) then return end
            local chord, take = chordOf(key), onKey
            finish()
            if type(take) == "function" then pcall(take, chord) end
        end)
        function h.start(text, keyFn, cancelFn)
            onKey, onCancel, waiting = keyFn, cancelFn, true
            if label then method(label, "SetText", type(text) == "string" and text or "") end
            method(f, "EnableKeyboard", true)
            method(f, "SetPropagateKeyboardInput", false)
            method(f, "Show")
            return true
        end
        function h.stop() finish() end
        function h.open() return waiting end
        return h
    end
    -- Lead section 410: Z-Flow's settings as the game's own rows, under
    -- Options > AddOns. One entry for the add-on, one under it for each
    -- topic; each setting is a checkbox, slider or dropdown the game builds,
    -- so look, spacing, scrolling, search and Defaults are the game's.
    --
    -- NOT CONFIRMED ON THIS CLIENT. No add-on installed on 16001 and no copy
    -- of the client's interface source uses these calls; every installed
    -- add-on registers a canvas (Questie's QuestieOptionsEngine.lua,
    -- ForeverDungeonJournal's OptionsPanel.lua, Ace3's AceConfigDialog-3.0).
    -- The names and argument orders below are the ones of the game's
    -- Settings API as later clients have it, so every one is looked for
    -- before anything is registered, and the answer is nil (the caller keeps
    -- its own window) when one is missing. RegisterProxySetting has had two
    -- argument orders; a setting that is never shown is registered first to
    -- learn which one this client reads, and nil is the answer when neither
    -- reads back. The add-on's entry is added to the list last, so a client
    -- that fails part way shows no empty entry.
    --
    --   c.optionsNative(spec) -> h | nil   (show)
    --   spec = { title, name, rows = { row, ... },
    --            topics = { { id, name, rows = { row, ... } }, ... } }
    --   row = { kind = "header", text }
    --       | { kind = "button", label, text, tip, run = fn }
    --       | { kind = "toggle" | "number" | "choice", key, label, tip,
    --           default, get = fn() -> value, set = fn(value),
    --           can = fn() -> true when it may be changed now,
    --           tags = { word, ... }, min, max, step (number),
    --           choices = { { value, label }, ... } (choice) }
    --   h.open(topicId or nil) -> true when the game's Options was asked to
    --     open at that topic's entry (the add-on's own entry for nil)
    --   h.count() -> how many rows the game took
    --   h.order() -> "new" | "old": the argument order that read back
    function c.optionsNative(spec)
        spec = type(spec) == "table" and spec or {}
        local S = env.Settings
        if type(S) ~= "table" then return nil end
        local NEED = { "RegisterVerticalLayoutCategory", "RegisterVerticalLayoutSubcategory",
            "RegisterAddOnCategory", "RegisterProxySetting", "OpenToCategory", "CreateSlider",
            "CreateSliderOptions", "CreateControlTextContainer" }
        for i = 1, #NEED do
            if type(S[NEED[i]]) ~= "function" then return nil end
        end
        local checkbox = S.CreateCheckbox or S.CreateCheckBox
        local dropdown = S.CreateDropdown or S.CreateDropDown
        if type(checkbox) ~= "function" or type(dropdown) ~= "function" then return nil end
        local title = type(spec.title) == "string" and spec.title or "Add-on"
        local prefix = (type(spec.name) == "string" and spec.name or "AddOn") .. "_"
        local okP, parent, parentLayout = call(S.RegisterVerticalLayoutCategory, title)
        if not okP or type(parent) ~= "table" then return nil end

        local VT = type(S.VarType) == "table" and S.VarType or {}
        local function varType(v)
            if type(v) == "boolean" then return VT.Boolean or "boolean" end
            if type(v) == "number" then return VT.Number or "number" end
            return VT.String or "string"
        end
        local order = "new"
        local function proxy(cat, variable, default, label, get, set)
            local ok, setting
            if order == "new" then
                ok, setting = call(S.RegisterProxySetting, cat, variable, varType(default), label, default, get, set)
            else
                ok, setting = call(S.RegisterProxySetting, cat, variable, {}, varType(default), label, default, get, set)
            end
            if ok and type(setting) == "table" then return setting end
            return nil
        end
        local function readsBack(setting)
            if not setting then return false end
            local ok, v = method(setting, "GetValue")
            return ok and v == true
        end
        local function yes() return true end
        local function nothing() end
        if not readsBack(proxy(parent, prefix .. "probe", false, title, yes, nothing)) then
            order = "old"
            if not readsBack(proxy(parent, prefix .. "probe2", false, title, yes, nothing)) then return nil end
        end

        local made = 0
        local function add(layout, init)
            if type(layout) ~= "table" or type(init) ~= "table" then return false end
            return (method(layout, "AddInitializer", init)) == true
        end
        local function control(cat, r, setting)
            if r.kind == "toggle" then return call(checkbox, cat, setting, r.tip) end
            if r.kind == "number" then
                local okO, opts = call(S.CreateSliderOptions, r.min, r.max, r.step)
                if not okO or type(opts) ~= "table" then return false end
                local M = env.MinimalSliderWithSteppersMixin
                if type(M) == "table" and type(M.Label) == "table" and M.Label.Right ~= nil then
                    method(opts, "SetLabelFormatter", M.Label.Right)
                end
                return call(S.CreateSlider, cat, setting, opts, r.tip)
            end
            if r.kind == "choice" then
                local function options()
                    local okC, box = call(S.CreateControlTextContainer)
                    if not okC or type(box) ~= "table" then return {} end
                    for _, choice in ipairs(type(r.choices) == "table" and r.choices or {}) do
                        method(box, "Add", choice.value, choice.label)
                    end
                    local okD, data = method(box, "GetData")
                    if okD and type(data) == "table" then return data end
                    return {}
                end
                return call(dropdown, cat, setting, options, r.tip)
            end
            return false
        end
        local function rowsInto(cat, layout, rows)
            for _, r in ipairs(type(rows) == "table" and rows or {}) do
                if type(r) ~= "table" then
                    -- not a row
                elseif r.kind == "header" then
                    local ok, init = call(env.CreateSettingsListSectionHeaderInitializer, r.text)
                    if ok then add(layout, init) end
                elseif r.kind == "button" then
                    local run = r.run
                    local ok, init = call(env.CreateSettingsButtonInitializer, r.label, r.text, function()
                        if type(run) == "function" then pcall(run) end
                    end, r.tip, true)
                    if ok and add(layout, init) then made = made + 1 end
                elseif type(r.key) == "string" and type(r.get) == "function" and type(r.set) == "function" then
                    local get, set = r.get, r.set
                    local setting = proxy(cat, prefix .. r.key, r.default, r.label, function()
                        local ok, v = pcall(get)
                        if ok and v ~= nil then return v end
                        return r.default
                    end, function(v)
                        if hidden(v) then return end
                        pcall(set, v)
                    end)
                    if setting then
                        local ok, init = control(cat, r, setting)
                        if ok and type(init) == "table" then
                            made = made + 1
                            local can = r.can
                            if type(can) == "function" then
                                method(init, "AddModifyPredicate", function()
                                    local okC, may = pcall(can)
                                    return okC and may == true
                                end)
                            end
                            if type(r.tags) == "table" and #r.tags > 0 then
                                method(init, "AddSearchTags", unpack(r.tags))
                            end
                        end
                    end
                end
            end
        end

        local byId = {}
        rowsInto(parent, parentLayout, spec.rows)
        for _, topic in ipairs(type(spec.topics) == "table" and spec.topics or {}) do
            if type(topic) == "table" then
                local ok, sub, layout = call(S.RegisterVerticalLayoutSubcategory, parent, tostring(topic.name))
                if ok and type(sub) == "table" then
                    if topic.id ~= nil then byId[topic.id] = sub end
                    rowsInto(sub, layout, topic.rows)
                end
            end
        end
        if made == 0 then return nil end
        call(S.RegisterAddOnCategory, parent)

        local h = {}
        function h.open(topicId)
            local cat = topicId ~= nil and byId[topicId] or parent
            local id = cat
            local okI, got = method(cat, "GetID")
            if okI and got ~= nil then id = got end
            return (call(S.OpenToCategory, id)) == true
        end
        function h.count() return made end
        function h.order() return order end
        return h
    end

    -- ------------------------------------------------------------ end N57

    -- ------------------------------------------------------------ N67
    -- Other add-ons' data, read at runtime only (research items 16 and 26).
    -- Nothing is written to them, and nothing of theirs is copied into this
    -- add-on's files or saved data: reading an installed add-on's tables
    -- while the game runs copies none of its code or database. A missing
    -- add-on, a shape not as expected, or a read that raises is nil.
    local function unitNumber(v)
        return type(v) == "number" and v == v and v >= 0 and v <= 1
    end

    -- GatherMate2's nodes on one map (a uiMapID), or nil:
    --   { { kind, x, y, node } }  kind: one of GATHERMATE_KINDS; x, y 0..1;
    --                             node: its name, nil when not said
    -- Read through GatherMate2's global object GatherMate2: the methods
    -- GetNodesForZone(map, kind) (an iterator of coord, nodeId),
    -- DecodeLoc(coord) -> x, y and GetNameForNode(kind, nodeId) -> name.
    -- First guesses from GatherMate2's public source as the research note
    -- names it; not seen in game on 16001. At most GATHERMATE_NODES_MAX
    -- rows. A map with none, GatherMate2 there: an empty list.
    local GATHERMATE_KINDS = { "Mining", "Herb Gathering", "Fishing", "Treasure" }
    local GATHERMATE_NODES_MAX = 500
    function c.gatherMateNodes(map)
        if type(map) ~= "number" then return nil end
        local gm = env.GatherMate2
        if type(gm) ~= "table" then return nil end
        local out, any = {}, false
        local ok = pcall(function()
            for _, kind in ipairs(GATHERMATE_KINDS) do
                local okI, iter, state, init = method(gm, "GetNodesForZone", map, kind)
                if okI and type(iter) == "function" then
                    any = true
                    for coord, nodeId in iter, state, init do
                        if #out >= GATHERMATE_NODES_MAX then return end
                        local okL, x, y = method(gm, "DecodeLoc", coord)
                        if okL and unitNumber(x) and unitNumber(y) then
                            local row = { kind = kind, x = x, y = y }
                            local okN, name = method(gm, "GetNameForNode", kind, nodeId)
                            if okN and type(name) == "string" and name ~= "" then row.node = name end
                            out[#out + 1] = row
                        end
                    end
                end
            end
        end)
        if not ok or not any then return nil end
        return out
    end

    -- This character's attunements as Attune keeps them, or nil:
    --   { { id, name, percent } }  percent 0..100, nil when not known
    -- Read from Attune's globals: Attune_Data.attunes (rows with ID and
    -- NAME) and its saved data Attune_DB.toons["<name>-<realm>"].attuned[ID].
    -- The character's key is made here only to look the row up; it is never
    -- handed out. First guesses from Attune (wow-forever @6f488c1,
    -- AttuneData.lua) as the research note names it; not seen in game.
    -- At most ATTUNE_ROWS_MAX rows.
    local ATTUNE_ROWS_MAX = 60
    function c.attuneProgress()
        local data, db = env.Attune_Data, env.Attune_DB
        if type(data) ~= "table" or type(db) ~= "table" then return nil end
        local ok, out = pcall(function()
            local list, toons = data.attunes, db.toons
            if type(list) ~= "table" or type(toons) ~= "table" then return nil end
            local attuned
            local okN, name = call(env.UnitName, "player")
            local okR, realm = call(env.GetRealmName)
            if okN and okR and type(name) == "string" and type(realm) == "string" then
                local toon = toons[name .. "-" .. realm]
                if type(toon) == "table" and type(toon.attuned) == "table" then attuned = toon.attuned end
            end
            local rows = {}
            for _, a in ipairs(list) do
                if #rows >= ATTUNE_ROWS_MAX then break end
                if type(a) == "table" and type(a.ID) == "number" and type(a.NAME) == "string" and a.NAME ~= "" then
                    local row = { id = a.ID, name = a.NAME }
                    local p = attuned and attuned[a.ID]
                    if type(p) == "number" and p == p and p >= 0 and p <= 100 then row.percent = p end
                    rows[#rows + 1] = row
                end
            end
            return rows
        end)
        if not ok or type(out) ~= "table" then return nil end
        return out
    end
    -- ------------------------------------------------------------ end N67
    do
    -- --------------------------------------------- macro icon window (N72)
    -- Lead section 248 item 4. The icon window of the macro editor is the
    -- icon selector popup MacroPopupFrame, made by Blizzard_MacroUI (load
    -- on demand: the caller asks only after that add-on loaded). Each time
    -- it opens it makes a fresh icon data provider (popup.iconDataProvider,
    -- of IconDataProviderMixin) and its grid reads the icons through it, by
    -- index; a click selects through the popup's own callback, which reads
    -- the icon of that index through the same provider. So a list is shown
    -- by answering the provider's GetNumIcons, GetIconByIndex and
    -- GetIndexOfIcon from it and redrawing the popup (popup:Update, else
    -- the selector's UpdateSelections): the click still selects through the
    -- normal editor. The hook pattern is that of LargerMacroIconSelection
    -- (GPL-3), reused with its notice; no code and no data copied. Names
    -- read from warcraft.wiki.gg and Plexy's list: IconSelectorPopupFrame
    -- TemplateMixin, IconDataProviderMixin, GetMacroIcons. First guesses, not
    -- seen in game on 16001: Needs game test (taint of the provider fields,
    -- the redraw call, the box placement).
    --
    --   c.macroPopup() -> handle | nil, missing names (in a fixed order)
    --   handle.shown() -> true while the window is on the screen
    --   handle.count() / handle.icon(i) -> the full list of the provider the
    --       window made, even while a list is shown; nil before it opened
    --   handle.show(list) -> shows only those icons; nil: the full list again.
    --       false when the window has made no provider
    --   handle.onShow(fn) / handle.onHide(fn) -> the last fn given is told;
    --       one HookScript each, the window's own scripts stay
    --   handle.addBox{ onText(text), onFilter(kind) } -> box | nil, made once:
    --       a plain search edit box and three plain buttons (All, Spells,
    --       Items), never a secure template. box.setText(s), box.hint(s),
    --       box.show(on)
    local MACRO_FILTERS = { { "all", "All" }, { "spells", "Spells" }, { "items", "Items" } }
    local macroHandle

    local function field(obj, key)
        local ok, v = pcall(function() return obj[key] end)
        if ok then return v end
        return nil
    end

    function c.macroPopup()
        local missing = {}
        local popup = env.MacroPopupFrame
        if type(popup) ~= "table" then missing[#missing + 1] = "MacroPopupFrame" end
        if type(env.IconSelectorPopupFrameTemplateMixin) ~= "table" then
            missing[#missing + 1] = "IconSelectorPopupFrameTemplateMixin"
        end
        if type(env.IconDataProviderMixin) ~= "table" then missing[#missing + 1] = "IconDataProviderMixin" end
        if type(env.GetMacroIcons) ~= "function" then missing[#missing + 1] = "GetMacroIcons" end
        local selector = type(popup) == "table" and field(popup, "IconSelector") or nil
        if type(selector) ~= "table" then missing[#missing + 1] = "MacroPopupFrame.IconSelector" end
        if #missing > 0 then return nil, missing end
        if macroHandle and macroHandle.popup == popup then return macroHandle.h end

        local h = {}
        local saved          -- { p, raw = { three fields }, num, at, index }
        local showFn, hideFn, hooked = nil, nil, {}
        local box

        local function provider()
            local p = field(popup, "iconDataProvider")
            if type(p) ~= "table" then return nil end
            return p
        end
        local function redraw()
            if not method(popup, "Update") then method(selector, "UpdateSelections") end
        end
        -- The provider's own calls while a list is shown over it.
        local function own(p)
            if saved and saved.p == p then return saved.num, saved.at end
            return field(p, "GetNumIcons"), field(p, "GetIconByIndex")
        end

        function h.shown()
            local ok, on = method(popup, "IsShown")
            return ok and on == true
        end
        function h.count()
            local p = provider()
            if not p then return nil end
            local num = own(p)
            local ok, n = call(num, p)
            if ok and type(n) == "number" and not hidden(n) then return n end
            return nil
        end
        function h.icon(i)
            local p = provider()
            if not p then return nil end
            local _, at = own(p)
            local ok, icon = call(at, p, i)
            if not ok or hidden(icon) then return nil end
            if type(icon) == "number" or type(icon) == "string" then return icon end
            return nil
        end
        function h.show(list)
            local p = provider()
            if not p then return false end
            if saved and saved.p ~= p then saved = nil end
            if list == nil then
                if saved then
                    local raw = saved.raw
                    local ok = pcall(function()
                        rawset(p, "GetNumIcons", raw[1])
                        rawset(p, "GetIconByIndex", raw[2])
                        rawset(p, "GetIndexOfIcon", raw[3])
                    end)
                    saved = nil
                    if not ok then return false end
                end
                redraw()
                return true
            end
            if type(list) ~= "table" then return false end
            local shown, index = {}, {}
            for i = 1, #list do
                shown[i] = list[i]
                if index[list[i]] == nil then index[list[i]] = i end
            end
            if not saved then
                local okRaw, raw = pcall(function()
                    return { rawget(p, "GetNumIcons"), rawget(p, "GetIconByIndex"), rawget(p, "GetIndexOfIcon") }
                end)
                if not okRaw then return false end
                saved = { p = p, raw = raw, num = field(p, "GetNumIcons"), at = field(p, "GetIconByIndex") }
            end
            local ok = pcall(function()
                rawset(p, "GetNumIcons", function() return #shown end)
                rawset(p, "GetIconByIndex", function(_, i) return shown[i] end)
                rawset(p, "GetIndexOfIcon", function(_, icon) return index[icon] end)
            end)
            if not ok then return false end
            redraw()
            return true
        end

        local function hook(script, tell)
            if hooked[script] then return end
            hooked[script] = true
            method(popup, "HookScript", script, tell)
        end
        function h.onShow(fn)
            showFn = type(fn) == "function" and fn or nil
            hook("OnShow", function() if showFn then pcall(showFn) end end)
        end
        function h.onHide(fn)
            hideFn = type(fn) == "function" and fn or nil
            hook("OnHide", function() if hideFn then pcall(hideFn) end end)
        end

        function h.addBox(spec)
            if box then return box end
            if type(spec) ~= "table" then return nil end
            local onText, onFilter = spec.onText, spec.onFilter
            local okE, edit = call(env.CreateFrame, "EditBox", nil, popup, "SearchBoxTemplate")
            if not okE or edit == nil then return nil end
            method(edit, "SetSize", 180, 20)
            method(edit, "SetPoint", "TOPLEFT", popup, "BOTTOMLEFT", 16, -2)
            method(edit, "SetAutoFocus", false)
            local okO, old = method(edit, "GetScript", "OnTextChanged")
            if not okO or type(old) ~= "function" then old = nil end
            method(edit, "SetScript", "OnTextChanged", function(self, ...)
                if old then pcall(old, self, ...) end
                local okT, typed = method(self, "GetText")
                if type(onText) == "function" and okT and type(typed) == "string" and not hidden(typed) then
                    pcall(onText, typed)
                end
            end)
            local okH, hint = method(edit, "CreateFontString", nil, "OVERLAY", "GameFontHighlightSmall")
            if not okH then hint = nil end
            if hint ~= nil then method(hint, "SetPoint", "TOPLEFT", edit, "BOTTOMLEFT", 0, -2) end
            local buttons, prev = {}, edit
            for i = 1, #MACRO_FILTERS do
                local kind, label = MACRO_FILTERS[i][1], MACRO_FILTERS[i][2]
                local okB, b = call(env.CreateFrame, "Button", nil, popup, "UIPanelButtonTemplate")
                if okB and b ~= nil then
                    method(b, "SetSize", 60, 20)
                    method(b, "SetPoint", "LEFT", prev, "RIGHT", 4, 0)
                    method(b, "SetText", label)
                    method(b, "SetScript", "OnClick", function()
                        if type(onFilter) == "function" then pcall(onFilter, kind) end
                    end)
                    buttons[#buttons + 1] = b
                    prev = b
                end
            end
            local b = {}
            function b.setText(s) method(edit, "SetText", type(s) == "string" and s or "") end
            function b.hint(s)
                if hint ~= nil then method(hint, "SetText", type(s) == "string" and s or "") end
            end
            function b.show(on)
                local how = on and "Show" or "Hide"
                method(edit, how)
                if hint ~= nil then method(hint, how) end
                for i = 1, #buttons do method(buttons[i], how) end
            end
            box = b
            return b
        end

        macroHandle = { popup = popup, h = h }
        return h
    end

    -- The player's spells as { name, icon } rows, for the macro icon search
    -- (N72): C_SpellBook (skill lines, then items of the player bank) where
    -- the client has it, else the older tab calls GetNumSpellTabs,
    -- GetSpellTabInfo, GetSpellBookItemName and GetSpellBookItemTexture
    -- (book "spell"). nil when neither is there or a read raised. A row
    -- without a name or an icon is left out. First guesses, not seen in
    -- game on 16001.
    local function iconOk(icon)
        if hidden(icon) then return false end
        return (type(icon) == "number" and icon > 0) or (type(icon) == "string" and icon ~= "")
    end
    local function nameOk(name)
        return type(name) == "string" and name ~= "" and not hidden(name)
    end

    function c.spellbookIcons()
        local book, enum = env.C_SpellBook, env.Enum
        local bank = type(enum) == "table" and type(enum.SpellBookSpellBank) == "table"
            and enum.SpellBookSpellBank.Player or nil
        if type(book) == "table" and type(book.GetNumSpellBookSkillLines) == "function" and bank ~= nil then
            local ok, lines = call(book.GetNumSpellBookSkillLines)
            if not ok or type(lines) ~= "number" or hidden(lines) then return nil end
            local out = {}
            for l = 1, lines do
                local okL, line = call(book.GetSpellBookSkillLineInfo, l)
                if not okL or type(line) ~= "table" then return nil end
                local from, n = field(line, "itemIndexOffset"), field(line, "numSpellBookItems")
                if type(from) ~= "number" or type(n) ~= "number" then return nil end
                for i = from + 1, from + n do
                    local okI, item = call(book.GetSpellBookItemInfo, i, bank)
                    if not okI then return nil end
                    if type(item) == "table" then
                        local name, icon = field(item, "name"), field(item, "iconID")
                        if nameOk(name) and iconOk(icon) then out[#out + 1] = { name = name, icon = icon } end
                    end
                end
            end
            return out
        end
        if type(env.GetNumSpellTabs) ~= "function" then return nil end
        local ok, tabs = call(env.GetNumSpellTabs)
        if not ok or type(tabs) ~= "number" or hidden(tabs) then return nil end
        local out = {}
        for t = 1, tabs do
            local okT, _, _, from, n = call(env.GetSpellTabInfo, t)
            if not okT or type(from) ~= "number" or type(n) ~= "number" then return nil end
            for i = from + 1, from + n do
                local okN, name = call(env.GetSpellBookItemName, i, "spell")
                local okI, icon = call(env.GetSpellBookItemTexture, i, "spell")
                if not okN or not okI then return nil end
                if nameOk(name) and iconOk(icon) then out[#out + 1] = { name = name, icon = icon } end
            end
        end
        return out
    end
    -- --------------------------------------------- end macro icon window
    end

    -- PRIEST-3 (P-SELFBUFF): c.playerDebuffs() -> { [name] = secondsLeft or
    --   true } or nil: every debuff on you, by name (Weakened Soul), read as
    --   playerBuffs with the filter "HARMFUL". nil when not known or a read
    --   raised. A first guess from the API pages (API_C_UnitAuras.
    --   GetAuraDataByIndex, API_UnitDebuff), not seen in game.
    function c.playerDebuffs()
        local ok, got = pcall(aurasOf, "player", "HARMFUL", env.UnitDebuff)
        if ok and type(got) == "table" then return got end
        return nil
    end

    -- S12 care key (P-KEYS slice A): c.unitCare(unit) -> nil
    --   | { exists = false } | { exists = true, friend, isSelf, dead, hurt }
    --   One unit (your target, a party member) as the care key needs it.
    --   exists UnitExists(unit); friend UnitIsFriend("player", unit); isSelf
    --   UnitIsUnit(unit, "player"); dead UnitIsDead(unit); hurt as c.pet():
    --   UnitHealth below UnitHealthMax when both are plain, else
    --   UnitHealthPercent (above 1: on a scale of 100). Each true, false, or
    --   nil when not known; a yes or no only, no amount is kept or handed
    --   on. nil when unit is not a name or whether it exists is not known.
    --   A first guess: none of these reads was seen in game for this use.
    function c.unitCare(unit)
        if type(unit) ~= "string" or unit == "" then return nil end
        local exists = yesNo(call(env.UnitExists, unit))
        if exists == nil then return nil end
        if not exists then return { exists = false } end
        local out = { exists = true }
        out.friend = yesNo(call(env.UnitIsFriend, "player", unit))
        out.isSelf = yesNo(call(env.UnitIsUnit, unit, "player"))
        out.dead = yesNo(call(env.UnitIsDead, unit))
        local okNow, now = call(env.UnitHealth, unit)
        local okMost, most = call(env.UnitHealthMax, unit)
        if okNow and okMost and plainNumber(now) and plainNumber(most) and most > 0 then
            out.hurt = now < most
        else
            local okShare, share = call(env.UnitHealthPercent, unit)
            if okShare and plainNumber(share) then
                if share > 1 then out.hurt = share < 100 elseif share < 1 then out.hurt = true end
            end
        end
        return out
    end
    -- S15 click slots and S29 move handle (P-KEYS slice C). First guesses,
    -- none seen in game: CreateFrame with SecureActionButtonTemplate on a
    -- plain holder frame, RegisterForClicks("AnyUp", "AnyDown"), and the
    -- holder moved by StartMoving / StopMovingOrSizing from a grip.
    --
    -- c.clickRow(spec) -> handle or nil. spec = { name, count, size, gap }.
    -- A hidden holder frame `name` on the screen with `count` secure buttons
    -- name1..nameN on it, each hidden until it holds something. Each button
    -- casts what it holds only on the player click on it; nothing here
    -- clicks, binds, registers a state driver or casts. Made only when
    -- InCombatLockdown answers a plain false; nil otherwise, with count
    -- below 1, or when CreateFrame fails. Slot i is button i; slot 0 is the
    -- holder.
    --   h.set(i, attr, value) -> true, or false and "absent" (no slot i),
    --                            "lockdown" (anything but a plain false from
    --                            InCombatLockdown: the frame is not touched)
    --                            or "refused" (SetAttribute failed).
    --   h.get(i, attr)        -> what button i holds for attr, or nil.
    --   h.show(i, on)         -> as set, for showing slot i (0: the row).
    --   h.isShown(i)          -> true or false.
    --   h.icon(i, texture)    -> true, or false with no texture or no slot.
    --   h.place(point)        -> as set; point = { point, relativePoint, x, y }
    --                            against the screen.
    function c.clickRow(spec)
        if type(spec) ~= "table" or type(spec.name) ~= "string" or spec.name == "" then return nil end
        local count = spec.count
        if type(count) ~= "number" or count < 1 or count % 1 ~= 0 then return nil end
        local function unlocked()
            local okLock, locked = call(env.InCombatLockdown)
            return okLock and locked == false
        end
        if not unlocked() then return nil end
        local size, gap = 32, 4
        if type(spec.size) == "number" and spec.size > 0 then size = spec.size end
        if type(spec.gap) == "number" and spec.gap >= 0 then gap = spec.gap end
        local okH, holder = call(env.CreateFrame, "Frame", spec.name, env.UIParent)
        if not okH or holder == nil then return nil end
        method(holder, "Hide")
        method(holder, "SetSize", count * size + (count - 1) * gap, size)
        method(holder, "SetFrameStrata", "MEDIUM")
        method(holder, "SetClampedToScreen", true)
        method(holder, "SetMovable", true)
        local buttons, icons = {}, {}
        for i = 1, count do
            local okB, b = call(env.CreateFrame, "Button", spec.name .. i, holder, "SecureActionButtonTemplate")
            if not okB or b == nil then return nil end
            method(b, "Hide")
            method(b, "SetSize", size, size)
            method(b, "SetPoint", "LEFT", holder, "LEFT", (i - 1) * (size + gap), 0)
            method(b, "RegisterForClicks", "AnyUp", "AnyDown")
            local okT, tex = method(b, "CreateTexture", nil, "ARTWORK")
            if okT and type(tex) == "table" then
                method(tex, "SetAllPoints", b)
                icons[i] = tex
            end
            method(b, "SetHighlightTexture", "Interface\\Buttons\\ButtonHilight-Square")
            buttons[i] = b
        end
        local function frameOf(i)
            if i == 0 then return holder end
            return buttons[i]
        end
        local h = {}
        function h.set(i, attr, value)
            local b = buttons[i]
            if b == nil then return false, "absent" end
            if not unlocked() then return false, "lockdown" end
            if not method(b, "SetAttribute", attr, value) then return false, "refused" end
            return true
        end
        function h.get(i, attr)
            local b = buttons[i]
            if b == nil then return nil end
            local okGet, v = method(b, "GetAttribute", attr)
            if not okGet then return nil end
            return v
        end
        function h.show(i, on)
            local f = frameOf(i)
            if f == nil then return false, "absent" end
            if not unlocked() then return false, "lockdown" end
            local called
            if on == true then called = method(f, "Show") else called = method(f, "Hide") end
            if not called then return false, "refused" end
            return true
        end
        function h.isShown(i)
            local f = frameOf(i)
            if f == nil then return false end
            local okS, shown = method(f, "IsShown")
            return okS and shown == true
        end
        function h.icon(i, texture)
            local tex = icons[i]
            if tex == nil or texture == nil then return false end
            return method(tex, "SetTexture", texture) == true
        end
        function h.place(point)
            if type(point) ~= "table" then return false, "refused" end
            if not unlocked() then return false, "lockdown" end
            method(holder, "ClearAllPoints")
            if not method(holder, "SetPoint", point[1], env.UIParent, point[2], point[3], point[4]) then
                return false, "refused"
            end
            return true
        end
        return h
    end

    -- Flow and self buttons (Rotation/FlowButton.lua). Three helpers on a
    -- button clickRow made; each answers nil when there is no frame by
    -- that name. Not seen in game.
    --
    -- c.buttonFace(spec) -> handle or nil. spec = { button }. A plain face
    -- drawn with colour only, no art path (lead section 297 item 5): a dark
    -- backing under the icon, and over it a dark panel with a "?" shown
    -- while the button holds nothing or no icon was read.
    --   h.empty(on) -> true, or false and "refused".
    -- First guess: CreateTexture with a sub level as its fourth argument.
    function c.buttonFace(spec)
        if type(spec) ~= "table" then return nil end
        local b = guideFrame(spec.button)
        if b == nil then return nil end
        local okB, back = method(b, "CreateTexture", nil, "BACKGROUND")
        if okB and type(back) == "table" then
            method(back, "SetAllPoints", b)
            if not method(back, "SetColorTexture", 0.1, 0.1, 0.1, 0.8) then
                method(back, "SetTexture", 0.1, 0.1, 0.1, 0.8)
            end
        end
        local okP, panel = method(b, "CreateTexture", nil, "OVERLAY", nil, -1)
        if not okP or type(panel) ~= "table" then return nil end
        method(panel, "SetAllPoints", b)
        if not method(panel, "SetColorTexture", 0.15, 0.15, 0.15, 1) then
            method(panel, "SetTexture", 0.15, 0.15, 0.15, 1)
        end
        local okM, mark = method(b, "CreateFontString", nil, "OVERLAY", "GameFontNormalSmall")
        if not okM or type(mark) ~= "table" then mark = nil end
        if mark ~= nil then
            method(mark, "SetPoint", "CENTER", b, "CENTER", 0, 0)
            method(mark, "SetText", "?")
        end
        local h = {}
        function h.empty(on)
            local called
            if on == true then called = method(panel, "Show") else called = method(panel, "Hide") end
            if mark ~= nil then
                if on == true then method(mark, "Show") else method(mark, "Hide") end
            end
            if not called then return false, "refused" end
            return true
        end
        return h
    end

    -- Lead section 305 item 1: no add-on file calls this now. The Flow and
    -- self buttons move by moveHandle; a drag on a secure button that acts
    -- on the press down would also cast. Kept in place (shared file).
    -- c.ctrlDrag(spec) -> true or nil. spec = { target, button, onMoved }.
    -- A left-button drag on the button named spec.button moves the frame
    -- named spec.target, only when IsControlKeyDown answers true and
    -- InCombatLockdown a plain false as the drag starts. Let go as
    -- moveHandle does (SC-3): a drag that ends in a fight waits for
    -- PLAYER_REGEN_ENABLED; the client layout cache is not written and
    -- onMoved({ point, relativePoint, x, y }) is called. Set up only while
    -- the lock is a plain false.
    -- First guess: RegisterForDrag and the OnDragStart / OnDragStop scripts
    -- on a SecureActionButtonTemplate button, and IsControlKeyDown.
    function c.ctrlDrag(spec)
        if type(spec) ~= "table" then return nil end
        local target = guideFrame(spec.target)
        local b = guideFrame(spec.button)
        if target == nil or b == nil then return nil end
        local function unlocked()
            local okLock, locked = call(env.InCombatLockdown)
            return okLock and locked == false
        end
        local function ctrl()
            local okC, down = call(env.IsControlKeyDown)
            return okC and down == true
        end
        if not unlocked() then return nil end
        if not method(b, "RegisterForDrag", "LeftButton") then return nil end
        local dragging = false
        method(b, "SetScript", "OnDragStart", function()
            if not unlocked() or not ctrl() then return end
            dragging = true
            method(target, "StartMoving")
        end)
        local waitStop
        local onStop
        onStop = function()
            if not dragging then return end
            if not unlocked() then
                if waitStop == nil then
                    waitStop = c.listen("PLAYER_REGEN_ENABLED", function()
                        if not unlocked() then return end
                        local cancel = waitStop
                        waitStop = nil
                        if type(cancel) == "function" then cancel() end
                        onStop()
                    end)
                end
                return
            end
            dragging = false
            method(target, "StopMovingOrSizing")
            method(target, "SetUserPlaced", false)
            local okP, a, _, r, x, y = method(target, "GetPoint", 1)
            if not okP or type(a) ~= "string" or type(x) ~= "number" or type(y) ~= "number" then return end
            if type(r) ~= "string" then r = a end
            if type(spec.onMoved) == "function" then pcall(spec.onMoved, { a, r, x, y }) end
        end
        method(b, "SetScript", "OnDragStop", onStop)
        return true
    end

    -- c.hoverTip(spec) -> true or nil. spec = { frame, text }. Pointing at
    -- the frame named spec.frame shows text() as one line in the game
    -- tooltip; leaving it hides the tooltip. A text() that raises, or gives
    -- no text, shows nothing.
    -- First guess: GameTooltip SetOwner(frame, "ANCHOR_RIGHT"), SetText,
    -- Show and Hide, hooked with HookScript OnEnter / OnLeave so the
    -- template scripts stay.
    function c.hoverTip(spec)
        if type(spec) ~= "table" or type(spec.text) ~= "function" then return nil end
        local f = guideFrame(spec.frame)
        local tip = guideFrame("GameTooltip")
        if f == nil or tip == nil then return nil end
        local hooked = method(f, "HookScript", "OnEnter", function()
            local okT, text = pcall(spec.text)
            if not okT or type(text) ~= "string" or text == "" then return end
            method(tip, "SetOwner", f, "ANCHOR_RIGHT")
            method(tip, "SetText", text)
            method(tip, "Show")
        end)
        if not hooked then return nil end
        method(f, "HookScript", "OnLeave", function() method(tip, "Hide") end)
        return true
    end

    -- c.moveHandle(spec) -> handle or nil. spec = { target, width, height,
    -- onMoved }. A grip on the left edge of the frame named target (nil
    -- when there is no such frame). Dragging it moves that frame, only when
    -- InCombatLockdown answers a plain false as the drag starts; let go,
    -- the client layout cache is not written (SetUserPlaced(false)) and
    -- onMoved({ point, relativePoint, x, y }) is called. An onMoved that
    -- raises does not escape. The add-on keeps the place in its own saved
    -- settings; no other file is written.
    --   h.show(on) -> true, or false and "lockdown" or "refused".
    function c.moveHandle(spec)
        if type(spec) ~= "table" then return nil end
        local target = guideFrame(spec.target)
        if target == nil then return nil end
        local function unlocked()
            local okLock, locked = call(env.InCombatLockdown)
            return okLock and locked == false
        end
        local okG, grip = call(env.CreateFrame, "Frame", nil, target)
        if not okG or grip == nil then return nil end
        local width, height = 10, 32
        if type(spec.width) == "number" and spec.width > 0 then width = spec.width end
        if type(spec.height) == "number" and spec.height > 0 then height = spec.height end
        method(grip, "SetSize", width, height)
        method(grip, "SetPoint", "RIGHT", target, "LEFT", -2, 0)
        local okT, tex = method(grip, "CreateTexture", nil, "BACKGROUND")
        if okT and type(tex) == "table" then
            method(tex, "SetAllPoints", grip)
            method(tex, "SetColorTexture", 1, 0.82, 0, 0.6)
        end
        method(grip, "EnableMouse", true)
        method(grip, "RegisterForDrag", "LeftButton")
        local dragging = false
        method(grip, "SetScript", "OnDragStart", function()
            if not unlocked() then return end
            dragging = true
            method(target, "StartMoving")
        end)
        -- SC-3: a drag that ends while the lock is on does not stop the
        -- protected frame then; it waits for PLAYER_REGEN_ENABLED and stops
        -- it once the lock answers a plain false.
        local waitStop
        local onStop
        onStop = function()
            if not dragging then return end
            if not unlocked() then
                if waitStop == nil then
                    waitStop = c.listen("PLAYER_REGEN_ENABLED", function()
                        if not unlocked() then return end
                        local cancel = waitStop
                        waitStop = nil
                        if type(cancel) == "function" then cancel() end
                        onStop()
                    end)
                end
                return
            end
            dragging = false
            method(target, "StopMovingOrSizing")
            method(target, "SetUserPlaced", false)
            local okP, a, _, r, x, y = method(target, "GetPoint", 1)
            if not okP or type(a) ~= "string" or type(x) ~= "number" or type(y) ~= "number" then return end
            if type(r) ~= "string" then r = a end
            if type(spec.onMoved) == "function" then pcall(spec.onMoved, { a, r, x, y }) end
        end
        method(grip, "SetScript", "OnDragStop", onStop)
        local h = {}
        function h.show(on)
            if not unlocked() then return false, "lockdown" end
            local called
            if on == true then called = method(grip, "Show") else called = method(grip, "Hide") end
            if not called then return false, "refused" end
            return true
        end
        return h
    end

    -- N2 corpse key (P-KEYS slice D): c.targetCorpse() -> nil
    --   | { exists = false } | { exists = true, dead, player, lootable, needs }
    --   The corpse you target as the rotation key needs it. exists
    --   UnitExists("target"); dead UnitIsDead; player UnitIsPlayer; lootable
    --   CanLootUnit(UnitGUID("target")), its first answer; needs the
    --   profession the target's tooltip (C_TooltipInfo.GetUnit("target"))
    --   names: "Skinnable" is Skinning, "Requires <name>" is that name. Each
    --   true, false, or nil when not known; nil when whether the target
    --   exists is not known. Only the target is asked about.
    --   A first guess: none of these reads was seen in game for this use.
    function c.targetCorpse()
        local exists = yesNo(call(env.UnitExists, "target"))
        if exists == nil then return nil end
        if not exists then return { exists = false } end
        local out = { exists = true }
        out.dead = yesNo(call(env.UnitIsDead, "target"))
        out.player = yesNo(call(env.UnitIsPlayer, "target"))
        local guid = text(call(env.UnitGUID, "target"))
        if guid then out.lootable = yesNo(call(env.CanLootUnit, guid)) end
        local tips = env.C_TooltipInfo
        if type(tips) == "table" then
            local okTip, tip = call(tips.GetUnit, "target")
            if okTip and type(tip) == "table" and type(tip.lines) == "table" then
                for _, line in ipairs(tip.lines) do
                    local left = type(line) == "table" and text(true, line.leftText)
                    if left == "Skinnable" then
                        out.needs = "Skinning"
                        break
                    end
                    local named = left and string.match(left, "^Requires (%a+)$")
                    if named then
                        out.needs = named
                        break
                    end
                end
            end
        end
        return out
    end



    -- G16: c.weaponSkills() -> { [skill line name] = true } or nil: every
    --   skill line you know (headers left out), by the name the client
    --   gives, for Gear/WeaponSkill.lua to find the weapon skills in.
    --   GetNumSkillLines, then GetSkillLineInfo(i) for each. nil when the
    --   client has no such read, gives no count, or any read raised: never
    --   a guess. First guesses, not seen in game on 16001; both names are
    --   in Diag.NAMES and the capture's skillLines field counts the lines.
    function c.weaponSkills()
        local okN, n = call(env.GetNumSkillLines)
        if not okN or type(n) ~= "number" or hidden(n) or n ~= n or n < 0 then return nil end
        local out = {}
        for i = 1, math.floor(n) do
            local ok, name, header = call(env.GetSkillLineInfo, i)
            if not ok then return nil end
            if not header and type(name) == "string" and not hidden(name) and name ~= "" then
                out[name] = true
            end
        end
        return out
    end

    -- Lead section 337 item 2 (P-INV G6): c.skillRanks() -> { [skill line
    --   name] = { rank, max } } or nil: GetNumSkillLines, then
    --   GetSkillLineInfo(i) (name, header, _, rank, _, _, max), headers left
    --   out. nil when there is no such read or any read raised. First guess,
    --   not seen in game.
    function c.skillRanks()
        local okN, n = call(env.GetNumSkillLines)
        if not okN or type(n) ~= "number" or hidden(n) or n ~= n or n < 0 then return nil end
        local out = {}
        for i = 1, math.floor(n) do
            local ok, name, header, _, rank, _, _, max = call(env.GetSkillLineInfo, i)
            if not ok then return nil end
            if not header and type(name) == "string" and not hidden(name) and name ~= "" then
                local row = {}
                if type(rank) == "number" and not hidden(rank) then row.rank = rank end
                if type(max) == "number" and not hidden(max) then row.max = max end
                out[name] = row
            end
        end
        return out
    end

    -- G60: NPC words read aloud (UI/NpcSpeech.lua). Text-to-speech plays on
    --   the player's own speakers: an output like print, not a game action,
    --   so no combat lockdown or protected-call concern. Every name here is
    --   a first guess, none seen in game on 16001 (CLIENT-NAMES-16001.txt
    --   never asked them); all are in Diag.NAMES so a normal login records
    --   which exist. Each call is pcall'd; absent or raising gives nil/false.
    --
    -- c.speech() -> { voices = { { voiceID, name }, ... } } or nil: nil when
    --   C_VoiceChat.GetTtsVoices is absent, raises or gives no table. An
    --   empty voices list means the call is there but this computer has none.
    local function voiceChat()
        local vc = env.C_VoiceChat
        if type(vc) ~= "table" then return nil end
        return vc
    end

    -- Enum.VoiceTtsDestination.LocalPlayback when it is a readable number,
    -- else nil: the one source of the speech destination, never guessed.
    local function localDestination()
        local enum = env.Enum
        if type(enum) ~= "table" or type(enum.VoiceTtsDestination) ~= "table" then return nil end
        local v = enum.VoiceTtsDestination.LocalPlayback
        if type(v) ~= "number" or hidden(v) then return nil end
        return v
    end

    function c.speech()
        local vc = voiceChat()
        if not vc then return nil end
        local ok, list = call(vc.GetTtsVoices)
        if not ok or type(list) ~= "table" then return nil end
        local voices = {}
        for _, v in ipairs(list) do
            if type(v) == "table" and type(v.voiceID) == "number" and not hidden(v.voiceID) then
                local one = { voiceID = v.voiceID }
                if type(v.name) == "string" and not hidden(v.name) then one.name = v.name end
                voices[#voices + 1] = one
            end
        end
        -- Lead sections 270 and 274: localPlayback is true only with
        -- Enum.VoiceTtsDestination.LocalPlayback a number. The
        -- TextToSpeech_Speak helper alone does not count: its destination on
        -- this client is unseen. Otherwise false, and the feature is not offered.
        return { voices = voices, localPlayback = localDestination() ~= nil }
    end

    -- c.speak(text, voice) -> true, or false and why. Refuses with "no local
    --   playback destination" whenever Enum.VoiceTtsDestination.LocalPlayback
    --   is not a number, helper or not (never a guessed number; lead section
    --   274). With it known: the game's own helper TextToSpeech_Speak(text,
    --   voice) when it is there, else C_VoiceChat.SpeakText(voiceID, text,
    --   destination, rate, volume) - the retail order, a first guess for
    --   16001 - rate 0, volume 100.
    function c.speak(text, voice)
        if type(text) ~= "string" or text == "" then return false, "no text" end
        local dest = localDestination()
        if dest == nil then return false, "no local playback destination" end
        local helper = env.TextToSpeech_Speak
        if type(helper) == "function" then
            local ok, err = call(helper, text, voice)
            if ok then return true end
            return false, tostring(err)
        end
        local vc = voiceChat()
        if not vc or type(vc.SpeakText) ~= "function" then return false, "no text-to-speech call" end
        if type(voice) ~= "table" or type(voice.voiceID) ~= "number" then return false, "no voice" end
        local ok, err = call(vc.SpeakText, voice.voiceID, text, dest, 0, 100)
        if ok then return true end
        return false, tostring(err)
    end

    -- c.stopSpeech() -> true, or false when C_VoiceChat.StopSpeakingText is
    --   absent or raised.
    function c.stopSpeech()
        local vc = voiceChat()
        if not vc then return false end
        local ok = call(vc.StopSpeakingText)
        return ok == true
    end

    -- c.npcText(kind) -> the words of the open NPC window, or nil (absent,
    --   raised, or empty: not read yet). kind: "gossip" (C_GossipInfo.GetText,
    --   else GetGossipText), "greeting" (GetGreetingText), "detail"
    --   (GetQuestText, then GetObjectiveText after a space), "progress"
    --   (GetProgressText), "reward" (GetRewardText). First guesses.
    local NPC_TEXT = { greeting = "GetGreetingText", progress = "GetProgressText", reward = "GetRewardText" }

    local function words(fn)
        local ok, v = call(fn)
        if not ok or type(v) ~= "string" or hidden(v) or v == "" then return nil end
        return v
    end

    function c.npcText(kind)
        if kind == "gossip" then
            local gi = env.C_GossipInfo
            if type(gi) == "table" and type(gi.GetText) == "function" then return words(gi.GetText) end
            return words(env.GetGossipText)
        end
        if kind == "detail" then
            local story = words(env.GetQuestText)
            if not story then return nil end
            local goal = words(env.GetObjectiveText)
            if goal then return story .. " " .. goal end
            return story
        end
        local name = NPC_TEXT[kind]
        if not name then return nil end
        return words(env[name])
    end

    -- c.npcSex() -> "male", "female", or nil (absent, raised, hidden, or
    --   neither) for the NPC whose window is open: UnitSex("npc"), 2 a man,
    --   3 a woman. P-QOL, read by UI/NpcSpeech.lua for its voice. First guess.
    function c.npcSex()
        if type(env.UnitSex) ~= "function" then return nil end
        local ok, v = call(env.UnitSex, "npc")
        if not ok or hidden(v) then return nil end
        if v == 2 then return "male" end
        if v == 3 then return "female" end
        return nil
    end

    -- N39 (P-KEYS slice E): your target's name, for the no-auto-attack
    -- list; nil with no target or when the client does not say.
    -- UnitName("target"), a first guess for this use: not seen in game on
    -- 16001.
    function c.targetName()
        return text(call(env.UnitName, "target"))
    end

    -- N40 (P-KEYS slice E): the spell your target is casting or channelling
    -- (UnitCastingInfo("target"), else UnitChannelInfo("target")); false
    -- when both answered and it casts nothing; nil when either could not
    -- be asked or answered something but a plain name. First guesses for
    -- this use: not seen in game on 16001.
    function c.targetCast()
        local ok, name = call(env.UnitCastingInfo, "target")
        local cast = text(ok, name)
        if cast then return cast end
        local okCh, chName = call(env.UnitChannelInfo, "target")
        local channel = text(okCh, chName)
        if channel then return channel end
        if (ok and name ~= nil) or (okCh and chName ~= nil) then return nil end
        if ok and okCh then return false end
        return nil
    end

    -- G51 (UI/PlateQuests.lua): a quest mark over an enemy's nameplate.
    -- LOOK ONLY: nothing clicks, targets or casts; no frame is secure or
    -- takes the mouse. Only nameplate units ("nameplateN") are asked about.
    --   c.plateCreature(unit) -> npc id or nil: the creature id in the
    --     unit's GUID ("Creature-0-server-instance-zone-npcId-spawn"; a
    --     "Vehicle-" GUID the same). A player, a pet, a hidden or odd GUID:
    --     nil, never a guess.
    --   c.plateQuestMark(unit) -> h | nil: a small text above that unit's
    --     plate, one frame per plate frame, its own (never the threat
    --     label). nil: no plate unit, no plate on screen, no frames.
    --     h.show(on), h.text(s), h.color(r, g, b)
    -- FIRST GUESSES, not seen in game on 16001. UnitGUID on a nameplate
    -- unit and the GUID's field order are from warcraft.wiki.gg (API
    -- UnitGUID, GUID page: Creature-0-[serverID]-[instanceID]-[zoneUID]-
    -- [ID]-[spawnUID]); legacy Flow read nameplate units the same way
    -- (Modules/QuestMarks.lua). C_NamePlate.GetNamePlateForUnit,
    -- CreateFrame, UnitGUID and STANDARD_TEXT_FONT are in Diag.NAMES.
    do
        local MARK_RAISE, MARK_FONT = 2, 12
        local CREATURE_KINDS = { Creature = true, Vehicle = true }

        local function isPlate(unit)
            return type(unit) == "string" and unit:find("^nameplate%d+$") ~= nil
        end

        function c.plateCreature(unit)
            if not isPlate(unit) then return nil end
            local ok, id = call(env.UnitGUID, unit)
            if not ok or id == nil or hidden(id) or type(id) ~= "string" then return nil end
            local kind, npc = id:match("^(%a+)%-[^-]*%-[^-]*%-[^-]*%-[^-]*%-(%d+)%-")
            if not CREATURE_KINDS[kind] then return nil end
            local n = tonumber(npc)
            if type(n) ~= "number" or n <= 0 then return nil end
            return n
        end

        -- Made frames by plate frame; weak keys, as the threat labels.
        local made = setmetatable({}, { __mode = "k" })

        local function makeMark(plate)
            local ok, f = call(env.CreateFrame, "Frame", nil, plate)
            if not ok or f == nil then return nil end
            method(f, "Hide")
            method(f, "SetSize", 1, MARK_FONT)
            method(f, "SetPoint", "BOTTOM", plate, "TOP", 0, MARK_RAISE)
            method(f, "EnableMouse", false)
            local okL, level = method(plate, "GetFrameLevel")
            if okL and type(level) == "number" and not hidden(level) then method(f, "SetFrameLevel", level + 10) end
            local okText, fs = method(f, "CreateFontString", nil, "OVERLAY", "GameFontNormal")
            if not okText then fs = nil end
            if fs ~= nil then
                local font = env.STANDARD_TEXT_FONT
                if type(font) ~= "string" or font == "" then font = "Fonts\\FRIZQT__.TTF" end
                method(fs, "SetFont", font, MARK_FONT, "OUTLINE")
                method(fs, "SetPoint", "BOTTOM", f, "BOTTOM", 0, 0)
            end
            return { frame = f, text = fs }
        end

        function c.plateQuestMark(unit)
            if not isPlate(unit) then return nil end
            local group = env.C_NamePlate
            if type(group) ~= "table" then return nil end
            local okP, plate = call(group.GetNamePlateForUnit, unit)
            if not okP or type(plate) ~= "table" then return nil end
            local m = made[plate]
            if m == nil then
                m = makeMark(plate)
                if m == nil then return nil end
                made[plate] = m
            end
            local f, fs = m.frame, m.text
            local h = {}
            function h.show(on) method(f, on and "Show" or "Hide") end
            function h.text(s)
                if fs ~= nil and type(s) == "string" then method(fs, "SetText", s) end
            end
            function h.color(r, g, b)
                if fs ~= nil and type(r) == "number" and type(g) == "number" and type(b) == "number" then
                    method(fs, "SetTextColor", r, g, b)
                end
            end
            return h
        end
    end
    -- N68 (UI/Alerts.lua): c.playAlert() -> true | nil, why. The one alert
    --   sound: PlaySound(SOUNDKIT.RAID_WARNING). why: "noCall" (no
    --   PlaySound, or the game names no such sound as a number: no number is guessed),
    --   "raised". Sound only; nothing in the game changes. A first guess
    --   from the API pages (API_PlaySound, SOUNDKIT), not heard in game.
    function c.playAlert()
        local kit = env.SOUNDKIT
        local id
        if type(kit) == "table" then id = kit.RAID_WARNING end
        if type(env.PlaySound) ~= "function" or type(id) ~= "number" then return nil, "noCall" end
        local ok = call(env.PlaySound, id)
        if not ok then return nil, "raised" end
        return true
    end
    -- G14 (lead sections 226, 229, 236): the quest reward choice and a mark
    -- on its button (Gear/RewardMark.lua). Both only read or draw a texture
    -- of ours: nothing takes a reward or clicks a button. New reads, added
    -- at the end. First guesses, none seen in game on 16001, each name in
    -- Diag.NAMES so a capture says which exist: GetNumQuestChoices,
    -- GetQuestItemLink("choice", i), the reward buttons
    -- QuestInfoRewardsFrameQuestInfoItem<i> (else the older QuestRewardItem<i>),
    -- the atlas "bags-greenarrow" (else the pet battle "strong" badge), as
    -- markMerchantButtons draws its marks.
    -- RM-1 (lead section 275): also a first guess, unseen: choice i is
    -- reward button i. If the game lays the buttons out in another order
    -- (or a button is not the choice its number says), the mark lands on
    -- the WRONG button. Diag.NAMES only says a button exists, not which
    -- choice it shows; a capture must answer that (the capture question).
    --   c.questChoices() -> { { index, link } ... }, or nil when the count
    --     cannot be read. link is nil for a choice the game has not given
    --     yet (the item not loaded).
    --   c.markRewardChoice(index) -> true when that choice's button carries
    --     the mark; nil when no button was found. Every other mark is
    --     hidden; index nil hides them all. kind "coin" (G14, section 393:
    --     nothing is an upgrade, this sells for the most) draws the gold
    --     coin icon instead of the arrow.
    -- In a do block: make.client is near Lua 5.1's 200 locals.
    do
        local REWARD_BUTTONS = 10
        function c.questChoices()
            local ok, n = call(env.GetNumQuestChoices)
            if not ok or hidden(n) or type(n) ~= "number" or n ~= n or n < 0 then return nil end
            local out = {}
            for i = 1, math.min(math.floor(n), REWARD_BUTTONS) do
                local okL, link = call(env.GetQuestItemLink, "choice", i)
                if not okL or hidden(link) or type(link) ~= "string" or link == "" then link = nil end
                out[#out + 1] = { index = i, link = link }
            end
            return out
        end

        local rewardBadges = {}
        local function rewardBadge(i)
            local b
            for _, name in ipairs({ "QuestInfoRewardsFrameQuestInfoItem" .. i, "QuestRewardItem" .. i }) do
                local okB, found = pcall(function() return env[name] end)
                if okB and type(found) == "table" then
                    b = found
                    break
                end
            end
            if b == nil then return nil end -- not kept: it may come later
            local known = rewardBadges[b]
            if known ~= nil then return known or nil end
            local okT, t = method(b, "CreateTexture", nil, "OVERLAY", nil, 7)
            if not okT or t == nil then
                rewardBadges[b] = false
                return nil
            end
            method(t, "SetSize", 18, 18)
            method(t, "SetPoint", "TOPLEFT", b, "TOPLEFT", -2, 2)
            local okA, set = method(t, "SetAtlas", "bags-greenarrow")
            if not okA or set == false then
                method(t, "SetTexture", "Interface\\PetBattles\\BattleBar-AbilityBadge-Strong")
            end
            method(t, "Hide")
            rewardBadges[b] = t
            return t
        end
        local function rewardLook(t, kind)
            if kind == "coin" then
                method(t, "SetTexture", "Interface\\MoneyFrame\\UI-GoldIcon")
                return
            end
            local okA, set = method(t, "SetAtlas", "bags-greenarrow")
            if not okA or set == false then
                method(t, "SetTexture", "Interface\\PetBattles\\BattleBar-AbilityBadge-Strong")
            end
        end
        function c.markRewardChoice(index, kind)
            local shown = nil
            for i = 1, REWARD_BUTTONS do
                local t = rewardBadge(i)
                if t then
                    if i == index then
                        rewardLook(t, kind)
                        method(t, "Show")
                        shown = true
                    else
                        method(t, "Hide")
                    end
                end
            end
            return shown
        end
    end

    -- S21 (lead section 275): the Need or Greed value on a loot roll's item
    -- (Gear/RollHint.lua). A first guess, not seen in game on 16001: the
    -- roll frame's item picture is its IconFrame field (legacy Flow's
    -- Modules/Gear/RollHint.lua IconHost read it on this client); without
    -- one the roll frame itself holds the value. The roll frame is found as
    -- onLootRoll finds it (rollFrame, F4). The names are in Diag.NAMES
    -- (GroupLootFrame1, GroupLootFrame1.IconFrame).
    --   c.rollValue(rollID, text, r, g, b) -> true when that roll's frame
    --     carries the text (no text, or "": hidden); nil when no frame shows
    --     that roll, or one of ours could not be made there.
    -- The text sits on a frame of ours made as a child of the item picture,
    -- one per roll frame, reused; it takes no clicks. Nothing of the game's
    -- frame is called or written, and nothing rolls.
    -- In a do block: make.client is near Lua 5.1's 200 locals.
    do
        local rollValues = {}   -- roll frame -> { holder, text }, or false
        local function rollValueMark(frame)
            local known = rollValues[frame]
            if known ~= nil then return known or nil end
            local host = frame
            local okI, icon = pcall(function() return frame.IconFrame end)
            if okI and type(icon) == "table" then host = icon end
            local okF, holder = call(env.CreateFrame, "Frame", nil, host)
            if not okF or type(holder) ~= "table" then
                rollValues[frame] = false
                return nil
            end
            local okT, fs = method(holder, "CreateFontString", nil, "OVERLAY", "GameFontNormalSmall")
            if not okT or type(fs) ~= "table" then
                rollValues[frame] = false
                return nil
            end
            method(holder, "SetAllPoints", host)
            method(holder, "EnableMouse", false)
            method(fs, "SetPoint", "TOPLEFT", holder, "TOPLEFT", 2, -2)
            local m = { holder = holder, text = fs }
            rollValues[frame] = m
            return m
        end
        function c.rollValue(rollID, s, r, g, b)
            if type(rollID) ~= "number" or hidden(rollID) then return nil end
            local frame = rollFrame(rollID)
            if frame == nil then return nil end
            local m = rollValueMark(frame)
            if m == nil then return nil end
            if type(s) ~= "string" or s == "" then
                method(m.holder, "Hide")
                return true
            end
            method(m.text, "SetText", s)
            if type(r) == "number" and type(g) == "number" and type(b) == "number" then
                method(m.text, "SetTextColor", r, g, b)
            end
            method(m.holder, "Show")
            return true
        end
    end

    -- S19 (P-SETS branch 2, Gear/SetIcons.lua): a movable row of small
    -- picture buttons, one per saved set, or nil when the client cannot
    -- make a frame. The row is c.panel's frame (moved by a drag on its
    -- edge, h.onMoved told where it stands), with the buttons on it.
    --   spec = { name = global frame name, size = button size in pixels }
    --   h.draw(icons, act): icons = { { key =, texture =, edge = true or
    --       false, tip = { line, ... } } }, at most 12 drawn.
    --       edge true: a gold edge, else a thin dark one. Hover shows the
    --       tip lines on the game tooltip (the first in gold). A left
    --       click asks act(key) under pcall; any other button asks
    --       nothing. The row keeps no state of its own: the next draw
    --       replaces it, and buttons past the icons are hidden.
    --   h.place(point), h.show(on), h.shown(), h.onMoved(fn, failed): as
    --       the panel's.
    -- The row itself acts on nothing: what a click does is act's.
    -- Needs game test: the button layout, RegisterForClicks and the
    -- tooltip owner (GameTooltip:SetOwner, AddLine, Show, Hide).
    function c.iconRow(spec)
        local ICON_ROW_MAX = 12
        local own = {}
        for key, v in pairs(type(spec) == "table" and spec or {}) do own[key] = v end
        own.closable = nil
        local size = tonumber(own.size) or 28
        own.width, own.height = size + 8, size + 8
        local h, f, isOpen = panelFrame(own)
        if h == nil then return nil end
        h.shown = isOpen
        local GAP, PAD = 4, 4
        local buttons = {}

        local function button(i)
            if buttons[i] == nil then
                local ok, b = call(env.CreateFrame, "Button", nil, f)
                if not ok or b == nil then return nil end
                local okE, edge = method(b, "CreateTexture", nil, "BACKGROUND")
                if not okE then edge = nil end
                if edge ~= nil then
                    method(edge, "SetPoint", "TOPLEFT", b, "TOPLEFT", -2, 2)
                    method(edge, "SetPoint", "BOTTOMRIGHT", b, "BOTTOMRIGHT", 2, -2)
                end
                local okT, tex = method(b, "CreateTexture", nil, "ARTWORK")
                if not okT then tex = nil end
                if tex ~= nil then method(tex, "SetAllPoints", b) end
                method(b, "RegisterForClicks", "LeftButtonUp")
                buttons[i] = { frame = b, edge = edge, tex = tex }
            end
            return buttons[i]
        end
        local function colour(tex, r, g, b, a)
            if tex == nil then return end
            if not method(tex, "SetColorTexture", r, g, b, a) then method(tex, "SetTexture", r, g, b, a) end
        end

        function h.draw(icons, act)
            local used = 0
            for _, icon in ipairs(type(icons) == "table" and icons or {}) do
                if used >= ICON_ROW_MAX then break end
                if type(icon) == "table" then
                    used = used + 1
                    local parts = button(used)
                    if parts == nil then break end
                    local b, key = parts.frame, icon.key
                    local tip = {}
                    for i, line in ipairs(type(icon.tip) == "table" and icon.tip or {}) do tip[i] = tostring(line) end
                    if not method(b, "SetSize", size, size) then
                        method(b, "SetWidth", size)
                        method(b, "SetHeight", size)
                    end
                    method(b, "ClearAllPoints")
                    method(b, "SetPoint", "TOPLEFT", f, "TOPLEFT", PAD + (used - 1) * (size + GAP), -PAD)
                    if parts.tex ~= nil then method(parts.tex, "SetTexture", icon.texture) end
                    if icon.edge == true then
                        colour(parts.edge, 1, 0.82, 0, 1)
                    else
                        colour(parts.edge, 0, 0, 0, 0.9)
                    end
                    method(b, "SetScript", "OnClick", function(_, which)
                        if which ~= nil and which ~= "LeftButton" then return end
                        if type(act) == "function" then pcall(act, key) end
                    end)
                    method(b, "SetScript", "OnEnter", function()
                        local gt = env.GameTooltip
                        if gt == nil or #tip == 0 then return end
                        method(gt, "SetOwner", b, "ANCHOR_TOPLEFT")
                        for i, line in ipairs(tip) do
                            if i == 1 then
                                method(gt, "AddLine", line, 1, 0.82, 0)
                            else
                                method(gt, "AddLine", line, 1, 1, 1, true)
                            end
                        end
                        method(gt, "Show")
                    end)
                    method(b, "SetScript", "OnLeave", function()
                        local gt = env.GameTooltip
                        if gt ~= nil then method(gt, "Hide") end
                    end)
                    method(b, "Show")
                end
            end
            for i = used + 1, #buttons do method(buttons[i].frame, "Hide") end
            local count = used
            if count < 1 then count = 1 end
            method(f, "SetWidth", PAD * 2 + count * size + (count - 1) * GAP)
            method(f, "SetHeight", PAD * 2 + size)
        end
        return h
    end

    -- ACTING (S19, lead sections 227 item 4 and 230): puts one item on,
    -- only on the player's own left click on a set icon (Gear/SetIcons.lua
    -- equipSet, the row's act); never from an event, a timer, the tick or
    -- a load. EquipItemByName(item[, slot]) under pcall. item: an item ID
    -- or a link, as the bags list it; slot: an inventory slot 1..19, or nil
    -- for the game's choice. Only when InCombatLockdown answers a plain
    -- false: true, a secret, a raise or no such call asks nothing.
    -- -> true | nil, "combat" | "bad" | "noCall" | "raised". One call, no
    -- retry. first guess: EquipItemByName is in the 16001 name list;
    -- what it does with a link and a slot is not seen in game.
    function c.equipItem(item, slot)
        local okLock, locked = call(env.InCombatLockdown)
        if not okLock or hidden(locked) or locked ~= false then return nil, "combat" end
        if type(item) == "number" then
            if hidden(item) or item ~= item or item < 1 or item >= math.huge or item ~= math.floor(item) then
                return nil, "bad"
            end
        elseif type(item) ~= "string" or hidden(item) or item == "" then
            return nil, "bad"
        end
        if slot ~= nil then
            if type(slot) ~= "number" or slot < 1 or slot > 19 or slot ~= math.floor(slot) then return nil, "bad" end
        end
        local fn = env.EquipItemByName
        if type(fn) ~= "function" then return nil, "noCall" end
        local ok
        if slot == nil then ok = pcall(fn, item) else ok = pcall(fn, item, slot) end
        if not ok then return nil, "raised" end
        return true
    end

    -- S20 vendor marks (lead section 230): the per-role badge on the
    -- merchant's item buttons, as legacy Flow's Modules/Gear/SpecBadge.lua
    -- drew it: per role, a green arrow up (better than what you wear), the
    -- same arrow turned over and red (worse), a short grey bar (about the
    -- same); the chosen role first, the others fainter. Drawn on a frame of
    -- ours made a child of each button: no region of the button is touched
    -- and nothing of the window is called. The page is read as
    -- markMerchantButtons reads it; none on the buyback tab. New, added at
    -- the end. First guesses, none seen in game on 16001: CreateFrame with
    -- a parent, the frame's CreateTexture, Texture SetTexCoord /
    -- SetVertexColor / SetColorTexture / SetAtlas / SetSize, and
    -- the names markMerchantButtons already guesses (MerchantItem<i>ItemButton,
    -- MerchantFrame.page and .selectedTab, MERCHANT_ITEMS_PER_PAGE).
    --   c.markMerchantSpecs(badges) -> how many buttons carry a badge; nil
    --     (every badge hidden) when no merchant window is open or its page
    --     cannot be read. badges: { [the merchant's item number] = { { role,
    --     state = "up" / "down" / "same" } ... } }; {} hides them all.
    do
        local SPEC_BUTTONS, SPEC_ROLES, SPEC_SIZE = 12, 3, 10
        local specFrames = {}
        local function specFrame(i)
            local okB, b = pcall(function() return env["MerchantItem" .. i .. "ItemButton"] end)
            if not okB or type(b) ~= "table" then return nil end -- not kept: it may come later
            local known = specFrames[b]
            if known ~= nil then return known or nil end
            local okF, f = call(env.CreateFrame, "Frame", nil, b)
            if not okF or type(f) ~= "table" then
                specFrames[b] = false
                return nil
            end
            method(f, "SetSize", SPEC_SIZE * SPEC_ROLES + 2 * (SPEC_ROLES - 1), SPEC_SIZE)
            method(f, "SetPoint", "BOTTOMLEFT", b, "BOTTOMLEFT", 1, 1)
            local h = { frame = f, slots = {} }
            for r = 1, SPEC_ROLES do
                local okT, t = method(f, "CreateTexture", nil, "OVERLAY", nil, 7)
                if okT and t ~= nil then
                    method(t, "SetPoint", "BOTTOMLEFT", f, "BOTTOMLEFT", (r - 1) * (SPEC_SIZE + 2), 0)
                    method(t, "Hide")
                    h.slots[r] = t
                end
            end
            method(f, "Hide")
            specFrames[b] = h
            return h
        end
        local function paint(t, state, first)
            local alpha = first and 1 or 0.7
            if state == "same" then
                method(t, "SetTexCoord", 0, 1, 0, 1)
                method(t, "SetSize", SPEC_SIZE - 2, 2)
                method(t, "SetVertexColor", 1, 1, 1, 1)
                method(t, "SetColorTexture", 0.7, 0.7, 0.7, alpha)
                method(t, "Show")
                return
            end
            method(t, "SetSize", SPEC_SIZE, SPEC_SIZE)
            local okA, set = method(t, "SetAtlas", "bags-greenarrow")
            if not okA or set == false then
                if state == "up" then
                    method(t, "SetColorTexture", 0.3, 1, 0.3, alpha)
                else
                    method(t, "SetColorTexture", 1, 0.3, 0.3, alpha)
                end
            elseif state == "up" then
                method(t, "SetTexCoord", 0, 1, 0, 1)
                method(t, "SetVertexColor", 1, 1, 1, alpha)
            else
                method(t, "SetTexCoord", 0, 1, 1, 0)  -- turned over
                method(t, "SetVertexColor", 1, 0.3, 0.3, alpha)
            end
            method(t, "Show")
        end
        function c.markMerchantSpecs(badges)
            badges = type(badges) == "table" and badges or {}
            local frame = env.MerchantFrame
            local okP, page = pcall(function() return frame.page end)
            local okT, tab = pcall(function() return frame.selectedTab end)
            local per = env.MERCHANT_ITEMS_PER_PAGE
            local readable = c.merchantOpen() == true and okP and type(page) == "number" and page >= 1
                and type(per) == "number" and per >= 1
            local buyback = okT and tab ~= nil and tab ~= 1
            local n = 0
            for i = 1, SPEC_BUTTONS do
                local h = specFrame(i)
                if h then
                    local list = nil
                    if readable and not buyback and i <= per then
                        list = badges[(page - 1) * per + i]
                    end
                    local any = false
                    for r = 1, SPEC_ROLES do
                        local t = h.slots[r]
                        local b, state = nil, nil
                        if type(list) == "table" then b = list[r] end
                        if type(b) == "table" then state = b.state end
                        if t ~= nil then
                            if state == "up" or state == "down" or state == "same" then
                                paint(t, state, r == 1)
                                any = true
                            else
                                method(t, "Hide")
                            end
                        end
                    end
                    if any then
                        method(h.frame, "Show")
                        n = n + 1
                    else
                        method(h.frame, "Hide")
                    end
                end
            end
            if not readable then return nil end
            return n
        end
    end
    ---------------------------------------------------------------------
    -- N60a: chat text to copy and this add-on's own links in chat
    -- (UI/Chat.lua). Look only: a line is read or handed on, a click is
    -- heard; nothing is sent, no chat frame's own function is replaced and
    -- no link of the game's own is handled here. Every call is a first
    -- guess, not seen in game on 16001; the names are in Diag.NAMES.
    --
    --   client.chatLines(index, max) -> { text, ... } | nil
    --     The last `max` lines chat window `index` holds, oldest first, as
    --     the game keeps them (colour and link codes still in). At most
    --     CHAT_LINES_MAX (500), which is also what a missing max means.
    --     nil when the window is not there or will not say how many lines
    --     it has. A line the client hides, or that is no text, is left out.
    --     Read from the global ChatFrame<index>: GetNumMessages() and
    --     GetMessageInfo(i) -> text, ... (warcraft.wiki.gg,
    --     ScrollingMessageFrame). That line 1 is the oldest is part of the
    --     first guess.
    --
    --   client.chatFilter(events, fn) -> cancel | nil
    --     fn(text, event, author) for every chat line of the named events
    --     (author: the sender as the game names it, nil when hidden or no
    --     text; N60c) before it
    --     is shown; a text it gives back replaces the line's text, anything
    --     else leaves the line as it was. fn runs under pcall. A text the
    --     client hides (issecretvalue), or that is no text, is handed on
    --     unread. Through ChatFrameUtil.AddMessageEventFilter, the name
    --     Blizzard's 1.60.1 UI source has (WoW/from-plexy/
    --     RESEARCH-chat-prat.md section 3: the older global
    --     ChatFrame_AddMessageEventFilter is nil on this client unless the
    --     player turned the deprecation fallbacks on); the older global is
    --     used where only it exists. The game's contract for a filter:
    --     filter(frame, event, text, ...) -> false to keep the line, then,
    --     when an argument changed, every argument again. nil when the
    --     client has neither name or took no event.
    --
    --   client.onLinkClick(kind, fn) -> cancel | nil
    --     fn(rest) when the player clicks a chat link whose data starts
    --     with kind .. ":"; rest is what follows. Every other link is left
    --     to the game: this only listens after the game's own SetItemRef
    --     (hooksecurefunc, once for every kind), it never replaces it. nil
    --     when the client has no hooksecurefunc or no SetItemRef.
    --
    --   client.pratModule(name) -> true | false | nil
    --     Whether the chat add-on Prat has its module `name` on; nil when
    --     Prat is not there or does not say. Read from Prat's global object
    --     Prat: GetModule(name, true) (or the same on Prat.Addon), then the
    --     module's IsEnabled(). The names are inferred in the research note
    --     (section 4), not read from Prat's source here.
    ---------------------------------------------------------------------
    do
        local CHAT_LINES_MAX = 500

        function c.chatLines(index, max)
            if type(index) ~= "number" or index < 1 or index ~= math.floor(index) then return nil end
            max = math.floor(tonumber(max) or CHAT_LINES_MAX)
            if max < 1 then max = 1 end
            if max > CHAT_LINES_MAX then max = CHAT_LINES_MAX end
            local frame = env["ChatFrame" .. index]
            if type(frame) ~= "table" then return nil end
            local okN, n = method(frame, "GetNumMessages")
            if not okN or hidden(n) or type(n) ~= "number" then return nil end
            local from = n - max + 1
            if from < 1 then from = 1 end
            local out = {}
            for i = from, n do
                local okM, line = method(frame, "GetMessageInfo", i)
                if okM and line ~= nil and not hidden(line) and type(line) == "string" then
                    out[#out + 1] = line
                end
            end
            return out
        end

        function c.chatFilter(events, fn)
            if type(events) ~= "table" or type(fn) ~= "function" then return nil end
            local add, remove = nil, nil
            local util = env.ChatFrameUtil
            if type(util) == "table" then
                local okA, a = pcall(function() return util.AddMessageEventFilter end)
                if okA and type(a) == "function" then
                    add = a
                    local okR, r = pcall(function() return util.RemoveMessageEventFilter end)
                    if okR then remove = r end
                end
            end
            if add == nil then
                add, remove = env.ChatFrame_AddMessageEventFilter, env.ChatFrame_RemoveMessageEventFilter
            end
            if type(add) ~= "function" then return nil end
            local dead = false
            local function filter(_, event, text, author, ...)
                if dead or text == nil then return false end
                if hidden(text) or type(text) ~= "string" then return false end
                -- N60c: the line's author (the game's second argument),
                -- handed on only when it is plain text.
                local who = nil
                if author ~= nil and not hidden(author) and type(author) == "string" then who = author end
                -- N60d: info { guid =, channel = }, each only when plain
                -- text: the game's 12th argument (the GUID) and 4th (the
                -- channel text, "1. General - Zone"). fn's second answer
                -- { channel = } replaces the channel text. First guess.
                local n = select("#", ...)
                local args = { ... }
                local info = {}
                if args[2] ~= nil and not hidden(args[2]) and type(args[2]) == "string" then
                    info.channel = args[2]
                end
                if args[10] ~= nil and not hidden(args[10]) and type(args[10]) == "string" then
                    info.guid = args[10]
                end
                -- N60e: info.line, the game's 11th argument (the line id,
                -- the same for one line in every window), only when a
                -- plain number. fn's second answer { hide = true } hides
                -- the line: the filter answers true, as the game's
                -- contract has it. First guess for 16001.
                if args[9] ~= nil and not hidden(args[9]) and type(args[9]) == "number" then
                    info.line = args[9]
                end
                local ok, new, change = pcall(fn, text, event, who, info)
                if not ok then return false end
                if type(change) == "table" and change.hide == true then return true end
                local channel = nil
                if type(change) == "table" and type(change.channel) == "string" and info.channel ~= nil
                    and change.channel ~= info.channel then
                    channel = change.channel
                end
                if type(new) ~= "string" or new == text then new = nil end
                if new == nil and channel == nil then return false end
                if new == nil then new = text end
                if channel ~= nil then args[2] = channel end
                return false, new, author, unpack(args, 1, n)
            end
            local added = {}
            for _, event in ipairs(events) do
                if type(event) == "string" and event ~= "" and call(add, event, filter) then
                    added[#added + 1] = event
                end
            end
            if #added == 0 then return nil end
            return function()
                dead = true
                for i = 1, #added do call(remove, added[i], filter) end
                added = {}
            end
        end

        local linkHandlers, linkHooked = {}, false
        local function linkClicked(link)
            if link == nil or hidden(link) or type(link) ~= "string" then return end
            for kind, fn in pairs(linkHandlers) do
                if link:sub(1, #kind + 1) == kind .. ":" then
                    -- An error in fn must not reach the click handler of the client.
                    pcall(fn, link:sub(#kind + 2))
                end
            end
        end
        function c.onLinkClick(kind, fn)
            if type(kind) ~= "string" or kind == "" or type(fn) ~= "function" then return nil end
            if not linkHooked then
                if type(env.hooksecurefunc) ~= "function" or type(env.SetItemRef) ~= "function" then return nil end
                if not pcall(env.hooksecurefunc, "SetItemRef", function(link) linkClicked(link) end) then
                    return nil
                end
                linkHooked = true
            end
            linkHandlers[kind] = fn
            return function()
                if linkHandlers[kind] == fn then linkHandlers[kind] = nil end
            end
        end

        function c.pratModule(name)
            if type(name) ~= "string" or name == "" then return nil end
            local prat = env.Prat
            if type(prat) ~= "table" then return nil end
            local okM, mod = method(prat, "GetModule", name, true)
            if not okM or type(mod) ~= "table" then
                local okA, addon = pcall(function() return prat.Addon end)
                if okA and type(addon) == "table" then
                    okM, mod = method(addon, "GetModule", name, true)
                end
            end
            if not okM or type(mod) ~= "table" then return nil end
            local okE, on = method(mod, "IsEnabled")
            if not okE or hidden(on) or type(on) ~= "boolean" then return nil end
            return on
        end
    end

    -- Lead section 303 (Dungeon Quests, Nav/DungeonRead.lua). Your race
    -- number, the third answer of UnitRace("player"): Questie's
    -- requiredRaces sets bit n - 1 for race n. nil when not known (no call,
    -- a failed call, a secret or odd answer). A first guess: not seen in
    -- game on 16001.
    function c.raceId()
        local ok, _, _, id = call(env.UnitRace, "player")
        if not ok or hidden(id) or type(id) ~= "number" then return nil end
        return id
    end

    -- Whether this character handed in quest id: true, false, or nil when
    -- not known. C_QuestLog.IsQuestFlaggedCompleted(id), a first guess: not
    -- seen in game on 16001. Only reads.
    function c.questDone(id)
        if type(id) ~= "number" then return nil end
        local log = env.C_QuestLog
        if type(log) ~= "table" then return nil end
        local ok, done = call(log.IsQuestFlaggedCompleted, id)
        if not ok or hidden(done) or type(done) ~= "boolean" then return nil end
        return done
    end

    -- The window kit's login probe (lead DISPATCH section 297 item 3 and
    -- section 303 item 5). Asks the client, read only, whether each part
    -- the kit would like to use is there. New, added at the end.
    --   c.kitProbe(rows) -> { [row id] = "works" | a short text saying what
    --     the client said, EJ_LOADED = "yes" | "no" | "not known" }
    --     | nil, "combat"
    --   rows: the list in UI/Kit/Parts.lua (KitParts.rows): { id =, kind =
    --     "template" | "global", name =, frameType =, proof = }. A row with
    --     no text id is passed over. With no rows no frame is made at all.
    -- LOOK ONLY. Nothing is shown, no setting is changed, nothing acts and
    -- no add-on is loaded: LoadAddOn and its kin are never called. Asked
    -- only when InCombatLockdown answers a plain false, judged as
    -- c.equipItem judges it: true, a secret, a raise or no such call asks
    -- nothing and makes no frame. Every row is asked under pcall, so one
    -- that raises is kept as its text and the others are still asked. A
    -- text is cut to PROBE_TEXT characters.
    --
    -- EVERY GAME NAME HERE IS A FIRST GUESS, none seen in game on 16001:
    -- the rows' own names and proof fields, and CreateFrame with a parent
    -- and a template, UIParent, Frame Hide / ClearAllPoints / SetParent,
    -- C_AddOns.IsAddOnLoaded and IsAddOnLoaded.
    --
    --   template  pcall(CreateFrame, frameType or "Frame", nil, holder,
    --             name); the frame made is hidden at once. holder is one
    --             unnamed frame of ours per asking, a child of UIParent,
    --             hidden when made and never shown, so nothing made under
    --             it is drawn and no global is made. "works" only when the
    --             frame handed back carries one of the row's proof fields
    --             (a field that template is known by); a frame with none
    --             of them is "made, not confirmed", so a client that hands
    --             back a plain frame for a template it lacks records no
    --             positive. "no frame" when nothing comes back, else the
    --             error text. When the asking is over every frame made,
    --             and the holder, is hidden, taken off its parent and let
    --             go; the client has no call to destroy a frame.
    --   global    looked up in the client's globals along the dotted name:
    --             "works (" .. its Lua type .. ")", or "nil".
    --   EJ_LOADED whether the Encounter Journal add-on is loaded:
    --             C_AddOns.IsAddOnLoaded, else IsAddOnLoaded; "not known"
    --             when neither answers.
    do
        local PROBE_TEXT = 120
        local JOURNAL = "Blizzard_EncounterJournal"

        local function short(v)
            local text = tostring(v)
            if #text > PROBE_TEXT then text = text:sub(1, PROBE_TEXT) end
            return text
        end


        -- One unnamed, hidden holder per asking; nothing is named, so no
        -- global is made. Every frame made to ask with is hidden, taken off
        -- its parent and let go when the asking is over (a frame cannot be
        -- destroyed, so this is all a release can be).
        local function holder()
            local ok, f = call(env.CreateFrame, "Frame", nil, env.UIParent)
            if not ok or type(f) ~= "table" then return nil end
            method(f, "Hide")
            return f
        end

        local function release(made, parent)
            for i = 1, #made do
                method(made[i], "Hide")
                method(made[i], "ClearAllPoints")
                method(made[i], "SetParent", nil)
            end
            if parent ~= nil then
                method(parent, "Hide")
                method(parent, "SetParent", nil)
            end
        end

        -- A frame handed back is the template asked for only when it carries
        -- one of the fields that template is known by (row.proof). A client
        -- that hands back a plain frame for a name it lacks is told apart:
        -- "made, not confirmed". The proof fields are first guesses.
        local function askTemplate(row, parent, made)
            local make = env.CreateFrame
            if type(make) ~= "function" then return "no CreateFrame" end
            if parent == nil then return "no holder frame" end
            local kind = row.frameType
            if type(kind) ~= "string" then kind = "Frame" end
            local ok, f = pcall(make, kind, nil, parent, row.name)
            if not ok then return short(f) end
            if type(f) ~= "table" then return "no frame" end
            made[#made + 1] = f
            method(f, "Hide")
            local proof = row.proof
            if type(proof) == "table" then
                for i = 1, #proof do
                    local okP, v = pcall(function() return f[proof[i]] end)
                    if okP and v ~= nil then return "works" end
                end
            end
            return "made, not confirmed"
        end

        local function askGlobal(row)
            local at = env
            for seg in row.name:gmatch("[^%.]+") do
                if type(at) ~= "table" then return "nil" end
                at = at[seg]
            end
            if at == nil then return "nil" end
            return "works (" .. type(at) .. ")"
        end

        -- The rows are templates and client names only (lead section 308).
        local function ask(row, parent, made)
            if type(row.name) ~= "string" or row.name == "" then return "no name" end
            if row.kind == "template" then return askTemplate(row, parent, made) end
            if row.kind == "global" then return askGlobal(row) end
            return "unknown kind"
        end

        -- Read only: IsAddOnLoaded says, nothing is loaded.
        local function journalLoaded()
            local asks = {}
            local group = env.C_AddOns
            if type(group) == "table" then asks[#asks + 1] = group.IsAddOnLoaded end
            asks[#asks + 1] = env.IsAddOnLoaded
            for i = 1, #asks do
                local ok, loaded = call(asks[i], JOURNAL)
                if ok and not hidden(loaded) then
                    if loaded then return "yes" end
                    return "no"
                end
            end
            return "not known"
        end

        function c.kitProbe(rows)
            local okLock, locked = call(env.InCombatLockdown)
            if not okLock or hidden(locked) or locked ~= false then return nil, "combat" end
            local out = {}
            -- No rows (the journal re-ask): no frame is made at all.
            if type(rows) == "table" and #rows > 0 then
                local made = {}
                local okH, parent = pcall(holder)
                if not okH then parent = nil end
                for i = 1, #rows do
                    local row = rows[i]
                    if type(row) == "table" and type(row.id) == "string" then
                        local ok, text = pcall(ask, row, parent, made)
                        if ok then out[row.id] = text else out[row.id] = short(text) end
                    end
                end
                pcall(release, made, parent)
            end
            local okJ, journal = pcall(journalLoaded)
            if okJ then out.EJ_LOADED = journal else out.EJ_LOADED = "not known" end
            return out
        end
    end

    -- The window kit's drawer (lead sections 287, 291 item 1 and 292): draws
    -- a tree UI/Kit.lua checked (Kit.Window) as one window. New, added at the
    -- end. LOOK ONLY: no secure template and no acting call; a click runs
    -- the part's own function and nothing else.
    --   c.kitWindow(id, tree, extra) -> handle | nil
    --     extra: name (the frame's global name; Escape needs one), point,
    --     width, height, onMoved(point, w, h) after a drag or a resize,
    --     onClose() when the player closes it (the button or Escape),
    --     failed(err) for any error. The build runs under pcall: a raise is
    --     nil, and failed is told. Every function the caller gave runs
    --     under pcall; its error goes to failed, never to the client.
    --     Asked again with an id it has, the window is redrawn and the same
    --     handle comes back.
    --   handle.update(tree) -> true | false   redraws; what was made is used
    --     again and what is left over is hidden.
    --   handle.place(point, width, height) -> true | false, why   moves
    --     and resizes the built window, keeping its frame and border (lead
    --     section 348); point { anchor, screen anchor, x, y } or nil, a size
    --     nil keeps that one; never below the least size; no onMoved.
    --   handle.show(on), handle.shown(), handle.close() (hides it; onClose
    --     is the player's close only)
    --   handle.art() -> { frame = "first" | "fallback", close =, search =,
    --     tab =, button =, check =, input =, scroll =, rowHighlight =,
    --     topicHighlight =, iconBorder =, grip =, gold =, silver =, copper =,
    --     iconMissing = }: for each stock name drawn, whether Kit.look.art's
    --     first choice or the fallback of the look spec (section 2.4) drew.
    --   handle.slot(name) -> the empty holder frame of a footer's slot, or nil
    -- Every size, colour, font and art name is Kit.look's, read at each draw.
    -- A key in Kit.look.unproven is never tried: its fallback is drawn
    -- (section 292: the default until the name is seen on 16001).
    -- Layout: top to bottom. A topic list stands at the left for the rest of
    -- the height and every later part goes in the pane at its right; a
    -- footer stands at the bottom; the last scroll takes the room left.
    -- A choice of more than Kit.look.size.choiceButtons items is one button
    -- that steps to the next item.
    --   c.kitProbe() -> { templates = { [name] = "present" | error text },
    --     textures = { [path] = what GetTexture read back | "unset" | error
    --     text }, globals = { [name] = its type } } | nil, "combat" |
    --     "noFrames" | "noKit"
    --     Asks which of Kit.look.art's names this client has: each template
    --     by making one hidden frame from it on a hidden holder, each
    --     texture path by SetTexture then GetTexture on one hidden texture.
    --     Only when InCombatLockdown answers a plain false (as c.equipItem
    --     judges it). Nothing is shown.
    -- First guesses, none seen in game on 16001. Names Core/Client.lua did
    -- not use before: the templates ButtonFrameTemplate (and its
    -- TitleText and CloseButton fields) and PanelTabButtonTemplate;
    -- SearchBoxTemplate's Instructions field; Frame SetToplevel,
    -- SetMinResize, EnableMouseWheel, SetMotionScriptsWhileDisabled; Button
    -- SetButtonState, LockHighlight, UnlockHighlight, GetFontString,
    -- SetNormalTexture, SetHighlightTexture, SetPushedTexture; CheckButton
    -- SetCheckedTexture; EditBox SetFontObject; ScrollFrame
    -- GetVerticalScroll, SetVerticalScroll, GetVerticalScrollRange and the
    -- handler OnMouseWheel(self, delta); FontString SetWordWrap; Texture
    -- GetTexture and SetTexture(nil); GameTooltip SetHyperlink and
    -- SetOwner(frame, "ANCHOR_NONE"); every Interface\ path in Kit.look.art;
    -- the global ITEM_QUALITY_COLORS (asked for its type only). Used before
    -- here, still not seen: UIPanelCloseButton, UISpecialFrames,
    -- SetResizeBounds, StartSizing, the other templates.
    do
        local kitWindows = {}   -- id -> { handle =, set = fn(extra), drawn = }
        -- What the login probe said of each row of UI/Kit/Parts.lua, and
        -- who is told what each window drew (UI/KitProbe.lua, both).
        local kitSaid = {}
        local kitDrawnFn = nil
        -- Lead section 340: every frame a kit window made, and that window's
        -- id, for the diagnostics line (c.kitFocus). Weak: a frame the
        -- client drops is not kept here.
        local kitOwned = setmetatable({}, { __mode = "k" })
        -- A template-made scroll frame gets a name of ours: the stock scroll
        -- templates of older clients build their bar's name from it.
        local kitScrolls = 0
        -- frame -> the id of the kit window that made it, or nil.
        function c.kitOwner(frame)
            if frame == nil then return nil end
            return kitOwned[frame]
        end
        local NOT_CONFIRMED = "made, not confirmed"
        -- The game's templates the kit asks for, here and nowhere else. A
        -- part with a row in the parts list takes its name from that row;
        -- the four below it were used by this file before the kit and have
        -- no row. First guesses, none seen in game on 16001.
        local KIT_ROW = { frame = "T2", search = "T5", tab = "T7", button = "T16" }
        local KIT_OWN = { close = "UIPanelCloseButton", check = "UICheckButtonTemplate",
            input = "InputBoxTemplate", scroll = "UIPanelScrollFrameTemplate", slider = "OptionsSliderTemplate" }
        -- A template-made slider gets a name of ours: the stock slider
        -- template names its labels from it.
        local kitSliders = 0
        -- The template to ask for a part, or nil when the probe found it
        -- missing: then no create is tried and the plain form draws. A row
        -- not asked yet, one that works and one made but not confirmed are
        -- each still asked for by a protected create.
        local function templateOf(key)
            local id = KIT_ROW[key]
            if id == nil then return KIT_OWN[key] end
            local said = kitSaid[id]
            if type(said) == "string" and said ~= "works" and said:sub(1, 6) ~= "works " and said ~= NOT_CONFIRMED then
                return nil
            end
            local parts = ns.KitParts
            if type(parts) ~= "table" or type(parts.ById) ~= "function" then return nil end
            local row = parts.ById(id)
            if type(row) ~= "table" or type(row.name) ~= "string" then return nil end
            return row.name
        end
        -- rows: { [row id] = what the probe said }. Kept for later draws.
        function c.kitKnown(rows)
            kitSaid = {}
            if type(rows) ~= "table" then return end
            for id, said in pairs(rows) do
                if type(id) == "string" and type(said) == "string" then kitSaid[id] = said end
            end
        end
        -- fn(id, art) after each draw of a window: art[part] = "first" (the
        -- game's own) or "fallback" (the plain form). One listener.
        function c.onKitDrawn(fn)
            if type(fn) == "function" then kitDrawnFn = fn else kitDrawnFn = nil end
        end

        local function kitBuild(id, tree, cb)
            if type(id) ~= "string" or id == "" then error("a kit window needs an id") end
            if type(tree) ~= "table" or tree.kind ~= "window" or type(tree.children) ~= "table" then
                error("a kit window needs a tree from Kit.Window")
            end
            local look, size, color, font, art, unproven, alpha, letters
            local function reread()
                look = ns.Kit.look
                size, color, font, art = look.size, look.color, look.font, look.art
                unproven = type(look.unproven) == "table" and look.unproven or {}
                alpha = type(look.alpha) == "table" and look.alpha or {}
                letters = type(look.coinLetter) == "table" and look.coinLetter or {}
            end
            reread()

            local function fail(err)
                if type(cb.failed) == "function" then pcall(cb.failed, err) end
            end
            -- A function the caller gave: under pcall, its error to failed.
            local function tell(fn, ...)
                if type(fn) ~= "function" then return end
                local ok, err = pcall(fn, ...)
                if not ok then fail(err) end
            end

            local drew = {}
            local function note(key, which)
                if drew[key] ~= "fallback" then drew[key] = which end
            end

            local function sized(obj, w, h)
                if not method(obj, "SetSize", w, h) then
                    method(obj, "SetWidth", w)
                    method(obj, "SetHeight", h)
                end
            end
            local function paint(tex, rgba)
                if tex == nil then return end
                if not method(tex, "SetColorTexture", rgba[1], rgba[2], rgba[3], rgba[4]) then
                    method(tex, "SetTexture", rgba[1], rgba[2], rgba[3], rgba[4])
                end
            end
            local function inked(fs, rgba)
                if fs ~= nil then method(fs, "SetTextColor", rgba[1], rgba[2], rgba[3], rgba[4]) end
            end
            -- True when the client took the picture: a raise, no such call
            -- or a plain false is a no.
            -- A picture is a path, or the file number the game hands out for
            -- an item's icon.
            local function pictured(tex, path)
                if tex == nil then return false end
                if type(path) == "number" then
                    if path ~= path or path <= 0 then return false end
                elseif type(path) ~= "string" or path == "" then
                    return false
                end
                local ok, took = method(tex, "SetTexture", path)
                return ok and took ~= false
            end
            local function able(obj, yes)
                method(obj, yes and "Enable" or "Disable")
            end

            -- What was made is kept and used again. Each thing is known by
            -- what it stands on and a key; the nth asked for under one key
            -- in a draw is the nth made. A draw starts every count at 0 and
            -- at its end hides what was not asked for.
            local pools, on, wired, firstOf = {}, {}, {}, {}
            -- Lead section 340: each scroll's offset before this draw.
            local keeps = {}
            -- The one dropdown list that is open, or nil. Closed by a pick, a
            -- second press on its box, a turn of the wheel, a draw and the
            -- window hiding.
            local openDrop = nil
            local function closeDrop()
                if openDrop ~= nil then method(openDrop, "Hide") end
                openDrop = nil
            end
            local function take(parent, key, make, loose)
                local by = pools[parent]
                if by == nil then
                    by = {}
                    pools[parent] = by
                end
                local slot = by[key]
                if slot == nil then
                    slot = { n = 0, items = {} }
                    by[key] = slot
                end
                local obj = slot.items[slot.n + 1]
                if obj == nil then
                    obj = make()
                    if obj == nil then return nil end
                    slot.items[slot.n + 1] = obj
                    kitOwned[obj] = id
                end
                slot.n = slot.n + 1
                on[obj] = nil
                if not loose then method(obj, "ClearAllPoints") end
                method(obj, "Show")
                return obj
            end
            local function sweepStart()
                for _, by in pairs(pools) do
                    for _, slot in pairs(by) do slot.n = 0 end
                end
            end
            local function sweepEnd()
                for _, by in pairs(pools) do
                    for _, slot in pairs(by) do
                        for i = slot.n + 1, #slot.items do
                            method(slot.items[i], "Hide")
                            on[slot.items[i]] = nil
                        end
                    end
                end
            end

            -- A handler of ours on a thing. The script is set once; what it
            -- runs is looked up at each call, so a thing used again runs
            -- only what its new part gave. keep: the template's own script
            -- of that name still runs first.
            local function hook(obj, script, fn, keep)
                local a = on[obj]
                if a == nil then
                    a = {}
                    on[obj] = a
                end
                a[script] = fn
                local w = wired[obj]
                if w == nil then
                    w = {}
                    wired[obj] = w
                end
                if w[script] then return end
                w[script] = true
                local old
                if keep then
                    local okO, was = method(obj, "GetScript", script)
                    if okO and type(was) == "function" then old = was end
                end
                method(obj, "SetScript", script, function(...)
                    if old then pcall(old, ...) end
                    local now = on[obj]
                    if now == nil or now[script] == nil then return end
                    local ok, err = pcall(now[script], ...)
                    if not ok then fail(err) end
                end)
            end

            -- A frame from the template of the part named key (templateOf),
            -- asked for by a protected create; a template the client lacks
            -- gets the one of the part named alt
            -- (when given), else a plain frame. -> frame, "first" | "fallback"
            local function made(kind, parent, key, alt, named)
                local obj = take(parent, kind .. ":" .. key, function()
                    local first = templateOf(key)
                    if first ~= nil then
                        -- named: a function giving the new frame's name.
                        local frameName1 = nil
                        if type(named) == "function" then frameName1 = named() end
                        local ok, f = call(env.CreateFrame, kind, frameName1, parent, first)
                        if ok and f ~= nil then
                            firstOf[f] = key
                            return f
                        end
                    end
                    local second = nil
                    if alt ~= nil then second = templateOf(alt) end
                    if second ~= nil then
                        local ok, f = call(env.CreateFrame, kind, nil, parent, second)
                        if ok and f ~= nil then
                            firstOf[f] = alt
                            return f
                        end
                    end
                    local ok, f = call(env.CreateFrame, kind, nil, parent)
                    if ok and f ~= nil then return f end
                    return nil
                end)
                if obj == nil then return nil end
                local from = firstOf[obj]
                if from == key then
                    note(key, "first")
                    return obj, "first"
                end
                note(key, "fallback")
                if from ~= nil then
                    note(from, "first")
                    return obj, "alt"
                end
                if alt ~= nil then note(alt, "fallback") end
                return obj, "fallback"
            end
            local function plain(kind, parent, tag, loose)
                return take(parent, kind .. "/" .. tag, function()
                    local ok, f = call(env.CreateFrame, kind, nil, parent)
                    if ok and f ~= nil then return f end
                    return nil
                end, loose)
            end
            local function texture(parent, layer, tag)
                return take(parent, "T/" .. layer .. "/" .. tag, function()
                    local ok, t = method(parent, "CreateTexture", nil, layer)
                    if ok and t ~= nil then return t end
                    return nil
                end)
            end
            -- A line of text in that font, left aligned, on one line.
            local function words(parent, fontName, tag)
                local fs = take(parent, "S/" .. tostring(fontName) .. "/" .. tag, function()
                    local ok, s = method(parent, "CreateFontString", nil, "OVERLAY", fontName)
                    if ok and s ~= nil then return s end
                    return nil
                end)
                if fs == nil then return nil end
                method(fs, "SetWidth", 0)
                method(fs, "SetJustifyH", "LEFT")
                method(fs, "SetWordWrap", false)
                return fs
            end
            local function widthOf(fs, guess)
                local ok, w = method(fs, "GetStringWidth")
                if ok and type(w) == "number" and not hidden(w) and w > 0 then return w end
                return guess
            end
            local function fontOf(button)
                local ok, fs = method(button, "GetFontString")
                if ok and fs ~= nil then return fs end
                return nil
            end

            -- A 1-pixel line along one edge of a frame.
            local function edgeLine(frame, side, rgba, tag)
                local t = texture(frame, "BORDER", tag .. side)
                if t == nil then return end
                if side == "TOP" or side == "BOTTOM" then
                    method(t, "SetPoint", side .. "LEFT", frame, side .. "LEFT", 0, 0)
                    method(t, "SetPoint", side .. "RIGHT", frame, side .. "RIGHT", 0, 0)
                    method(t, "SetHeight", size.edge)
                else
                    method(t, "SetPoint", "TOP" .. side, frame, "TOP" .. side, 0, 0)
                    method(t, "SetPoint", "BOTTOM" .. side, frame, "BOTTOM" .. side, 0, 0)
                    method(t, "SetWidth", size.edge)
                end
                paint(t, rgba)
            end
            local function border(frame)
                edgeLine(frame, "TOP", color.edge, "e")
                edgeLine(frame, "BOTTOM", color.edge, "e")
                edgeLine(frame, "LEFT", color.edge, "e")
                edgeLine(frame, "RIGHT", color.edge, "e")
            end
            local function backing(frame, rgba, tag)
                local t = texture(frame, "BACKGROUND", tag)
                if t == nil then return nil end
                method(t, "SetAllPoints", frame)
                paint(t, rgba)
                return t
            end

            -- The frame itself: made once. The stock frame when its name is
            -- proven and the client has it; else a plain one.
            local parent = env.UIParent
            local name = nil
            if type(cb.name) == "string" and cb.name ~= "" then name = cb.name end
            -- A window given no name gets one of ours, so Escape can close it.
            if name == nil and type(ns.id) == "table" and type(ns.id.framePrefix) == "string" then
                name = ns.id.framePrefix .. "Kit" .. id
            end
            -- Asked before the frame is made: making it takes the name.
            local nameFree = name ~= nil and env[name] == nil
            -- A name another frame holds is not given to ours.
            local frameName = nil
            if nameFree then frameName = name end
            -- The game's own window frame when a protected create makes it
            -- (lead section 297 item 4), else a plain one. Its portrait is
            -- hidden by the game's own call when the client has it.
            local f, stockFrame = nil, false
            local frameTemplate = templateOf("frame")
            if frameTemplate ~= nil then
                local ok, made1 = call(env.CreateFrame, "Frame", frameName, parent, frameTemplate)
                if ok and made1 ~= nil then
                    f, stockFrame = made1, true
                    call(env.ButtonFrameTemplate_HidePortrait, made1)
                end
            end
            if f == nil then
                local ok, made2 = call(env.CreateFrame, "Frame", frameName, parent)
                if not ok or made2 == nil then error("the client made no frame") end
                f = made2
            end
            method(f, "Hide")
            method(f, "SetFrameStrata", "MEDIUM")
            method(f, "SetClampedToScreen", true)
            method(f, "SetToplevel", true)
            method(f, "EnableMouse", true)
            kitOwned[f] = id

            local width, height = tonumber(cb.width) or tree.width, tonumber(cb.height) or tree.height
            local open = false
            local slots = {}
            local body
            local draw
            -- Lead section 340: true while the tree drawn has a topic list;
            -- the header's search then stands over it, at the left.
            local topicsInWindow = false

            local function playerClosed()
                if not open then return end
                open = false
                tell(cb.onClose)
            end
            -- The game also runs OnHide when something the window stands on
            -- is hidden (the whole interface): that is not a close.
            method(f, "SetScript", "OnHide", function()
                local okS, shown = method(f, "IsShown")
                if okS and shown then return end
                playerClosed()
            end)
            if tree.escape == true and nameFree and type(env.UISpecialFrames) == "table" then
                local special, there = env.UISpecialFrames, false
                for i = 1, #special do
                    if special[i] == name then there = true end
                end
                if not there then special[#special + 1] = name end
            elseif tree.escape == true then
                -- Never silent: the caller is told why Escape will not close
                -- this window. The window still opens.
                local why = "the client has no list of windows Escape closes"
                if name == nil then
                    why = "the window has no name"
                elseif not nameFree then
                    why = "another frame holds the name " .. name
                end
                fail("Escape will not close this window: " .. why)
            end

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
            local function tellMoved()
                local okW, w = method(f, "GetWidth")
                local okH, ht = method(f, "GetHeight")
                if okW and okH and type(w) == "number" and type(ht) == "number" and w > 0 and ht > 0 then
                    width, height = w, ht
                end
                local point = standing()
                if point then tell(cb.onMoved, point, width, height) end
            end

            -- The game's tooltip beside a thing, with one text.
            local function tipShow(owner, text)
                local tip = env.GameTooltip
                if tip == nil then return end
                method(tip, "SetOwner", owner, "ANCHOR_RIGHT")
                method(tip, "SetText", text)
                method(tip, "Show")
            end
            local function tipHide(owner)
                local tip = env.GameTooltip
                if tip == nil then return end
                local okO, owned = method(tip, "IsOwned", owner)
                if okO and owned == true then method(tip, "Hide") end
            end
            -- A highlight under the mouse, a tooltip text, and (item) the
            -- game's own item tooltip at the right of the window.
            local function hover(frame, text, item)
                method(frame, "EnableMouse", true)
                local hi = texture(frame, "BACKGROUND", "hover")
                if hi ~= nil then
                    method(hi, "SetAllPoints", frame)
                    if not unproven.rowHighlight and pictured(hi, art.rowHighlight) then
                        method(hi, "SetBlendMode", "ADD")
                        method(hi, "SetAlpha", alpha.rowHighlight or 1)
                        note("rowHighlight", "first")
                    else
                        paint(hi, color.hover)
                        note("rowHighlight", "fallback")
                    end
                    method(hi, "Hide")
                end
                hook(frame, "OnEnter", function()
                    if hi ~= nil then method(hi, "Show") end
                    if item ~= nil then
                        local tip = env.GameTooltip
                        if tip ~= nil then
                            local link = item
                            if type(item) == "number" then link = "item:" .. item end
                            method(tip, "SetOwner", f, "ANCHOR_NONE")
                            method(tip, "ClearAllPoints")
                            method(tip, "SetPoint", "TOPLEFT", f, "TOPRIGHT", size.gapSmall, 0)
                            method(tip, "SetHyperlink", link)
                            method(tip, "Show")
                        end
                    elseif type(text) == "string" and text ~= "" then
                        tipShow(frame, text)
                    end
                end)
                hook(frame, "OnLeave", function()
                    if hi ~= nil then method(hi, "Hide") end
                    if item ~= nil then tipHide(f) else tipHide(frame) end
                end)
            end

            -- A stock button saying text, as wide as its words need (never
            -- under the least width, never over `most`). The caller places
            -- it. -> button, width
            local function button(parent1, text, most, live, onClick, tooltip)
                local b, which = made("Button", parent1, "button")
                if b == nil then return nil, 0 end
                if which ~= "first" then method(b, "SetNormalFontObject", font.label) end
                method(b, "SetText", text)
                local w = size.buttonMin
                local fs = fontOf(b)
                if fs ~= nil then
                    local tw = widthOf(fs, 0) + size.buttonPad
                    if tw > w then w = tw end
                end
                if most ~= nil and w > most then w = most end
                sized(b, w, size.button)
                able(b, live)
                method(b, "SetButtonState", "NORMAL", false)
                hook(b, "OnClick", function()
                    if live then onClick() end
                end)
                if type(tooltip) == "string" and tooltip ~= "" then
                    method(b, "SetMotionScriptsWhileDisabled", true)
                    hook(b, "OnEnter", function() tipShow(b, tooltip) end)
                    hook(b, "OnLeave", function() tipHide(b) end)
                end
                return b, w
            end

            -- Coins as number then coin, largest first. side "RIGHT": the
            -- last coin ends `at` from the right edge; "LEFT": the first
            -- number starts `at` from the left. -> where the coins end.
            local function coins(parent1, list, at, side)
                local from, to, step = 1, #list, 1
                if side == "RIGHT" then from, to, step = #list, 1, -1 end
                local sign = 1
                if side == "RIGHT" then sign = -1 end
                local function mark(i, coin)
                    local t = texture(parent1, "ARTWORK", "coin" .. i)
                    local w = size.coin
                    if t ~= nil and pictured(t, coin.icon) then
                        sized(t, size.coin, size.coin)
                        method(t, "SetPoint", side, parent1, side, sign * at, 0)
                        note(coin.coin, "first")
                    else
                        if t ~= nil then method(t, "Hide") end
                        note(coin.coin, "fallback")
                        local l = words(parent1, font.small, "letter" .. i)
                        if l ~= nil then
                            method(l, "SetPoint", side, parent1, side, sign * at, 0)
                            inked(l, color[coin.coin] or color.text)
                            method(l, "SetText", letters[coin.coin] or "")
                            w = widthOf(l, size.coin)
                        end
                    end
                    at = at + w + size.gapSmall
                end
                local function amount(i, coin)
                    local n = words(parent1, font.small, "amount" .. i)
                    if n == nil then return end
                    method(n, "SetPoint", side, parent1, side, sign * at, 0)
                    inked(n, color.text)
                    method(n, "SetText", tostring(coin.amount))
                    at = at + widthOf(n, size.coin * 2) + size.gapSmall
                end
                for i = from, to, step do
                    if side == "RIGHT" then
                        mark(i, list[i])
                        amount(i, list[i])
                    else
                        amount(i, list[i])
                        mark(i, list[i])
                    end
                end
                return at
            end

            -- A well that scrolls: -> the frame its lines stand on, how wide
            -- a line may be, and whether it scrolls (false: the client made
            -- no scroll frame and the lines stand on the well itself). The
            -- bar's width is kept free whether or not the bar shows.
            local function scrollWell(parent1, x, y, w, h, tag)
                local well = plain("Frame", parent1, "well" .. tag)
                if well == nil then error("the client made no frame for a list") end
                method(well, "SetPoint", "TOPLEFT", parent1, "TOPLEFT", x, -y)
                sized(well, w, h)
                -- Lead section 340: the well is decoration and takes no mouse.
                method(well, "EnableMouse", false)
                backing(well, color.inset, "inset")
                border(well)
                local innerW = w - size.scrollBar - size.gap - size.edge
                local scroll = made("ScrollFrame", well, "scroll", nil, function()
                    if type(ns.id) ~= "table" or type(ns.id.framePrefix) ~= "string" then return nil end
                    kitScrolls = kitScrolls + 1
                    return ns.id.framePrefix .. "KitScroll" .. kitScrolls
                end)
                if scroll == nil then return well, innerW, false end
                method(scroll, "SetPoint", "TOPLEFT", well, "TOPLEFT", size.edge, -size.edge)
                method(scroll, "SetPoint", "BOTTOMRIGHT", well, "BOTTOMRIGHT", -(size.scrollBar + size.gap), size.edge)
                local child = plain("Frame", scroll, "child", true)
                if child == nil then return well, innerW, false end
                method(child, "EnableMouse", false)
                -- Where the player had scrolled, put back once the draw has
                -- sized the child (setting the child may put it at 0).
                local okV, was = method(scroll, "GetVerticalScroll")
                if not okV or type(was) ~= "number" or hidden(was) or was < 0 then was = 0 end
                keeps[#keeps + 1] = { scroll = scroll, child = child, at = was, view = h - 2 * size.edge }
                method(scroll, "SetScrollChild", child)
                method(scroll, "EnableMouseWheel", true)
                hook(scroll, "OnMouseWheel", function(_, delta)
                    if type(delta) ~= "number" or hidden(delta) then return end
                    local okC, cur = method(scroll, "GetVerticalScroll")
                    local okR, range = method(scroll, "GetVerticalScrollRange")
                    if not okC or not okR or type(cur) ~= "number" or type(range) ~= "number" then return end
                    closeDrop()
                    local to = cur - delta * size.wheelLines * size.lineHeight
                    if to > range then to = range end
                    if to < 0 then to = 0 end
                    method(scroll, "SetVerticalScroll", to)
                end)
                return child, innerW, true
            end

            -- One part's frame in a pane: the pane's width, h high, at the
            -- pane's next free line.
            local function box(pane, h, tag)
                local b = plain("Frame", pane.parent, tag)
                if b == nil then error("the client made no frame for a part") end
                method(b, "SetPoint", "TOPLEFT", pane.parent, "TOPLEFT", pane.x, -pane.y)
                sized(b, pane.w, h)
                -- Lead section 340: a part's frame takes no mouse unless the
                -- part asks (a click, a fold, a tooltip with nothing above).
                -- Set at every draw: the frame may be one used before.
                method(b, "EnableMouse", false)
                pane.y = pane.y + h
                return b
            end
            local function stripe(frame, pane)
                pane.rows = pane.rows + 1
                local t = texture(frame, "BACKGROUND", "stripe")
                if t == nil then return end
                if pane.rows % 2 == 0 then
                    method(t, "SetAllPoints", frame)
                    paint(t, color.stripe)
                else
                    method(t, "Hide")
                end
            end

            -- A control at x on its row or line, colW wide at most.
            local CONTROL = {}
            function CONTROL.button(part, on1, x, colW, live)
                local b = button(on1, part.text, colW, live and part.enabled ~= false,
                    function() tell(part.onClick) end, part.tooltip)
                if b ~= nil then method(b, "SetPoint", "LEFT", on1, "LEFT", x, 0) end
                return { b }
            end
            function CONTROL.bind(part, on1, x, colW, live)
                local b = button(on1, part.text, colW, live and part.enabled ~= false, function() tell(part.onClick) end)
                if b == nil then return end
                sized(b, colW, size.button)
                method(b, "SetPoint", "LEFT", on1, "LEFT", x, 0)
                local fs = fontOf(b)
                if part.waiting then
                    inked(fs, color.accent)
                elseif part.bound == nil then
                    inked(fs, color.textDim)
                else
                    inked(fs, color.text)
                end
                return { b }
            end
            function CONTROL.checkbox(part, on1, x, colW, live)
                local okay = live and part.enabled ~= false
                local b, which = made("CheckButton", on1, "check")
                if b == nil then return end
                sized(b, size.check, size.check)
                method(b, "SetPoint", "LEFT", on1, "LEFT", x, 0)
                if which ~= "first" then
                    -- No stock box: a well with an edge, filled when checked.
                    backing(b, color.inset, "inset")
                    border(b)
                    local mark = texture(b, "ARTWORK", "mark")
                    if mark ~= nil then
                        method(mark, "SetPoint", "TOPLEFT", b, "TOPLEFT", size.gapSmall, -size.gapSmall)
                        method(mark, "SetPoint", "BOTTOMRIGHT", b, "BOTTOMRIGHT", -size.gapSmall, size.gapSmall)
                        paint(mark, color.accent)
                        method(b, "SetCheckedTexture", mark)
                    end
                end
                method(b, "SetChecked", part.checked == true)
                able(b, okay)
                hook(b, "OnClick", function()
                    if not okay then return end
                    local okC, now = method(b, "GetChecked")
                    if not okC or hidden(now) then now = not part.checked end
                    tell(part.onToggle, now and true or false)
                end)
                if type(part.label) == "string" and part.label ~= "" and colW > size.check + size.gapSmall then
                    local l = words(on1, font.label, "checkLabel")
                    if l ~= nil then
                        method(l, "SetPoint", "LEFT", b, "RIGHT", size.gapSmall, 0)
                        if okay then inked(l, color.text) else inked(l, color.textOff) end
                        method(l, "SetText", part.label)
                    end
                end
                return { b }
            end
            -- A choice as the game's dropdown: one box showing the item in
            -- use; a press opens the list under it, a press on an item picks
            -- it. The list stands on the window, above the rows, so no row
            -- and no scroll cuts it.
            local function dropdown(part, on1, x, colW, okay)
                local n = #part.items
                local list
                local b = button(on1, part.items[part.selected] or "", colW, okay, function()
                    if list == nil then return end
                    local mine = openDrop == list
                    closeDrop()
                    if mine then return end
                    method(list, "Show")
                    method(list, "Raise")
                    openDrop = list
                end)
                if b == nil then return {} end
                sized(b, colW, size.button)
                method(b, "SetPoint", "LEFT", on1, "LEFT", x, 0)
                local arrow = texture(b, "OVERLAY", "drop")
                if arrow ~= nil then
                    sized(arrow, size.check, size.check)
                    method(arrow, "SetPoint", "RIGHT", b, "RIGHT", -size.gapSmall, 0)
                    if not pictured(arrow, "Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up") then method(arrow, "Hide") end
                end
                list = plain("Frame", f, "drop")
                if list == nil then return { b } end
                method(list, "SetFrameStrata", "DIALOG")
                method(list, "EnableMouse", true)
                method(list, "SetPoint", "TOPLEFT", b, "BOTTOMLEFT", 0, 0)
                sized(list, colW, n * size.button + 2 * size.edge)
                backing(list, color.fill, "fill")
                border(list)
                for i = 1, n do
                    local item = plain("Button", list, "item")
                    if item ~= nil then
                        sized(item, colW - 2 * size.edge, size.button)
                        method(item, "SetPoint", "TOPLEFT", list, "TOPLEFT", size.edge, -(size.edge + (i - 1) * size.button))
                        local over = texture(item, "HIGHLIGHT", "over")
                        if over ~= nil then
                            method(over, "SetAllPoints", item)
                            paint(over, color.hover)
                        end
                        local t = words(item, font.label, "item")
                        if t ~= nil then
                            method(t, "SetPoint", "LEFT", item, "LEFT", size.gapSmall, 0)
                            if i == part.selected then inked(t, color.accent) else inked(t, color.text) end
                            method(t, "SetText", part.items[i])
                        end
                        hook(item, "OnClick", function()
                            closeDrop()
                            if i ~= part.selected then tell(part.onSelect, i) end
                        end)
                    end
                end
                method(list, "Hide")
                return { b }
            end
            -- A number with two limits as the game's slider, the value
            -- beside it. Dragging moves the value shown; onChange is told
            -- once, when the mouse button is let go. -> the slider, or nil
            -- with nothing left showing when the client gives no slider or
            -- one without a slider's calls: the caller draws the stepper.
            -- First guesses, not seen in game: the template name, and the
            -- Slider calls as the page's own slider uses them (sliderRow).
            local function slider(part, on1, x, colW, okay)
                if part.min == nil or part.max == nil or part.max <= part.min then return nil end
                local s, which = made("Slider", on1, "slider", nil, function()
                    if type(ns.id) ~= "table" or type(ns.id.framePrefix) ~= "string" then return nil end
                    kitSliders = kitSliders + 1
                    return ns.id.framePrefix .. "KitSlider" .. kitSliders
                end)
                if s == nil then return nil end
                if which ~= "first" then
                    if not (method(s, "SetOrientation", "HORIZONTAL")
                        and method(s, "SetThumbTexture", "Interface\\Buttons\\WHITE8X8")) then
                        method(s, "Hide")
                        return nil
                    end
                    local track = texture(s, "BACKGROUND", "track")
                    if track ~= nil then
                        method(track, "SetPoint", "LEFT", s, "LEFT", 0, 0)
                        method(track, "SetPoint", "RIGHT", s, "RIGHT", 0, 0)
                        method(track, "SetHeight", size.gapSmall)
                        paint(track, color.edge)
                    end
                    local okT, thumb = method(s, "GetThumbTexture")
                    if okT and thumb ~= nil then
                        sized(thumb, size.gap, size.check)
                        method(thumb, "SetVertexColor", color.accent[1], color.accent[2], color.accent[3], color.accent[4])
                    end
                end
                if not (method(s, "SetMinMaxValues", part.min, part.max) and method(s, "SetValueStep", part.step)
                    and method(s, "SetValue", part.value)) then
                    method(s, "Hide")
                    return nil
                end
                method(s, "SetObeyStepOnDrag", true)
                method(s, "EnableMouse", true)
                local w = colW - size.numberValue
                sized(s, w, size.check)
                method(s, "SetPoint", "LEFT", on1, "LEFT", x, 0)
                able(s, okay)
                local v = words(on1, font.label, "value")
                if v ~= nil then
                    method(v, "SetPoint", "LEFT", on1, "LEFT", x + w, 0)
                    method(v, "SetWidth", size.numberValue)
                    method(v, "SetJustifyH", "CENTER")
                    if okay then inked(v, color.text) else inked(v, color.textOff) end
                    method(v, "SetText", tostring(part.value))
                end
                local pending = part.value
                hook(s, "OnValueChanged", function(_, now)
                    if type(now) ~= "number" or hidden(now) or now ~= now then return end
                    now = part.min + math.floor((now - part.min) / part.step + 0.5) * part.step
                    if now < part.min then now = part.min end
                    if now > part.max then now = part.max end
                    now = math.floor(now * 1000000 + 0.5) / 1000000
                    pending = now
                    if v ~= nil then method(v, "SetText", tostring(now)) end
                end, true)
                hook(s, "OnMouseUp", function()
                    if okay and pending ~= part.value then tell(part.onChange, pending) end
                end, true)
                return s
            end
            function CONTROL.choice(part, on1, x, colW, live)
                local okay = live and part.enabled ~= false
                if part.drop == true then return dropdown(part, on1, x, colW, okay) end
                local n = #part.items
                if n > size.choiceButtons then
                    local b = button(on1, part.items[part.selected] or "", colW, okay, function()
                        tell(part.onSelect, part.selected % n + 1)
                    end)
                    if b ~= nil then
                        sized(b, colW, size.button)
                        method(b, "SetPoint", "LEFT", on1, "LEFT", x, 0)
                    end
                    return { b }
                end
                local each = (colW - (n - 1) * size.gapSmall) / n
                local all = {}
                for i = 1, n do
                    local b = button(on1, part.items[i], each, okay, function()
                        if i ~= part.selected then tell(part.onSelect, i) end
                    end)
                    if b ~= nil then
                        sized(b, each, size.button)
                        method(b, "SetPoint", "LEFT", on1, "LEFT", x + (i - 1) * (each + size.gapSmall), 0)
                        -- The one in use stays in its pushed look.
                        if i == part.selected then method(b, "SetButtonState", "PUSHED", true) end
                        all[#all + 1] = b
                    end
                end
                return all
            end
            function CONTROL.number(part, on1, x, colW, live)
                local okay = live and part.enabled ~= false
                local slid = slider(part, on1, x, colW, okay)
                if slid ~= nil then return { slid } end
                local function stepped(dir)
                    local v = part.value + dir * part.step
                    if part.min ~= nil and v < part.min then v = part.min end
                    if part.max ~= nil and v > part.max then v = part.max end
                    return v
                end
                local down = okay and (part.min == nil or part.value > part.min)
                local up = okay and (part.max == nil or part.value < part.max)
                local minus = button(on1, "-", size.button, down, function() tell(part.onChange, stepped(-1)) end)
                if minus ~= nil then
                    sized(minus, size.button, size.button)
                    method(minus, "SetPoint", "LEFT", on1, "LEFT", x, 0)
                end
                local v = words(on1, font.label, "value")
                if v ~= nil then
                    method(v, "SetPoint", "LEFT", on1, "LEFT", x + size.button, 0)
                    method(v, "SetWidth", size.numberValue)
                    method(v, "SetJustifyH", "CENTER")
                    if okay then inked(v, color.text) else inked(v, color.textOff) end
                    method(v, "SetText", tostring(part.value))
                end
                local plus = button(on1, "+", size.button, up, function() tell(part.onChange, stepped(1)) end)
                if plus ~= nil then
                    sized(plus, size.button, size.button)
                    method(plus, "SetPoint", "LEFT", on1, "LEFT", x + size.button + size.numberValue, 0)
                end
                local all = {}
                if minus ~= nil then all[#all + 1] = minus end
                if plus ~= nil then all[#all + 1] = plus end
                return all
            end
            function CONTROL.text(part, on1, x, colW, live)
                local okay = live and part.enabled ~= false
                local e, which = made("EditBox", on1, "input")
                if e == nil then return end
                sized(e, colW - size.gap, size.button)
                method(e, "SetPoint", "LEFT", on1, "LEFT", x + size.gap, 0)
                if which ~= "first" then
                    method(e, "SetFontObject", font.label)
                    backing(e, color.inset, "inset")
                    border(e)
                end
                method(e, "SetAutoFocus", false)
                local okG, cur = method(e, "GetText")
                if not okG or cur ~= part.text then method(e, "SetText", part.text) end
                able(e, okay)
                hook(e, "OnEnterPressed", function()
                    local okT, typed = method(e, "GetText")
                    method(e, "ClearFocus")
                    if okay and okT and type(typed) == "string" and not hidden(typed) then tell(part.onText, typed) end
                end)
                hook(e, "OnEscapePressed", function()
                    method(e, "SetText", part.text)
                    method(e, "ClearFocus")
                end)
                return { e }
            end

            local DRAW = {}
            local function place(part, pane, last)
                local fn = DRAW[part.kind]
                if fn == nil then return end
                fn(part, pane, last)
                pane.first = false
            end

            function DRAW.header(part, pane)
                local h = box(pane, size.header, "header")
                local search = part.search
                -- Lead section 340: beside a topic list the search stands at
                -- the left, over the list, as the retail Settings window has
                -- it, and the summary starts over the pane at its right.
                local left = topicsInWindow and search ~= nil
                local s = words(h, font.small, "summary")
                if s ~= nil then
                    if left then
                        method(s, "SetPoint", "LEFT", h, "LEFT", size.topicWidth + size.pad, 0)
                    else
                        method(s, "SetPoint", "LEFT", h, "LEFT", 0, 0)
                    end
                    inked(s, color.textDim)
                    method(s, "SetText", part.title)
                end
                edgeLine(h, "BOTTOM", color.divider, "d")
                if search ~= nil then
                    local e, which = made("EditBox", h, "search", "input")
                    if e ~= nil then
                        if left then
                            sized(e, size.topicWidth, size.button)
                            method(e, "SetPoint", "LEFT", h, "LEFT", 0, 0)
                        else
                            sized(e, size.search, size.button)
                            method(e, "SetPoint", "RIGHT", h, "RIGHT", 0, 0)
                        end
                        method(e, "SetAutoFocus", false)
                        local hint
                        if which == "first" then
                            local okI, stock = pcall(function() return e.Instructions end)
                            if okI and type(stock) == "table" then method(stock, "SetText", search.placeholder) end
                        else
                            if which == "fallback" then
                                method(e, "SetFontObject", font.label)
                                backing(e, color.inset, "inset")
                                border(e)
                            end
                            hint = words(e, font.small, "hint")
                            if hint ~= nil then
                                method(hint, "SetPoint", "LEFT", e, "LEFT", size.gapSmall, 0)
                                inked(hint, color.textDim)
                                method(hint, "SetText", search.placeholder)
                                if search.text ~= "" then method(hint, "Hide") end
                            end
                        end
                        local known = search.text
                        local okG, cur = method(e, "GetText")
                        if not okG or cur ~= known then method(e, "SetText", known) end
                        -- Told only what is new: the game also runs this
                        -- when the add-on sets the text.
                        hook(e, "OnTextChanged", function()
                            local okT, typed = method(e, "GetText")
                            if not okT or type(typed) ~= "string" or hidden(typed) then return end
                            if hint ~= nil then
                                if typed == "" then method(hint, "Show") else method(hint, "Hide") end
                            end
                            if typed == known then return end
                            known = typed
                            tell(search.onText, typed)
                        end, true)
                        hook(e, "OnEnterPressed", function() method(e, "ClearFocus") end)
                        hook(e, "OnEscapePressed", function() method(e, "ClearFocus") end)
                    end
                end
                pane.y = pane.y + size.gap
            end

            function DRAW.tabs(part, pane)
                local h = box(pane, size.tab, "tabs")
                local n = #part.items
                local w = size.buttonMin
                if w * n > pane.w then w = math.floor(pane.w / n) end
                for i = 1, n do
                    local b, which = made("Button", h, "tab")
                    if b ~= nil then
                        if which ~= "first" then method(b, "SetNormalFontObject", font.label) end
                        method(b, "SetText", part.items[i])
                        sized(b, w, size.tab)
                        method(b, "SetPoint", "BOTTOMLEFT", h, "BOTTOMLEFT", (i - 1) * w, 0)
                        if which == "first" then
                            if i == part.selected then method(b, "LockHighlight") else method(b, "UnlockHighlight") end
                        else
                            -- The flat tab: the one shown in the accent
                            -- colour over the selected backing.
                            local back = texture(b, "BACKGROUND", "selected")
                            local fs = fontOf(b)
                            if i == part.selected then
                                if back ~= nil then
                                    method(back, "SetAllPoints", b)
                                    paint(back, color.selected)
                                end
                                inked(fs, color.accent)
                            else
                                if back ~= nil then method(back, "Hide") end
                                inked(fs, color.text)
                            end
                        end
                        hook(b, "OnClick", function()
                            if i ~= part.selected then tell(part.onSelect, i) end
                        end)
                    end
                end
                edgeLine(h, "BOTTOM", color.divider, "d")
                pane.y = pane.y + size.gap
            end

            function DRAW.topicList(part, pane)
                local room = pane.h - pane.y
                if room < size.topicRow then room = size.topicRow end
                local child, innerW, scrolls = scrollWell(pane.parent, pane.x, pane.y, size.topicWidth, room, "topics")
                local y = 0
                for i = 1, #part.items do
                    local b = plain("Button", child, "topic")
                    if b ~= nil then
                        sized(b, innerW, size.topicRow)
                        method(b, "SetPoint", "TOPLEFT", child, "TOPLEFT", 0, -y)
                        method(b, "SetNormalFontObject", font.label)
                        method(b, "SetText", part.items[i])
                        local fs = fontOf(b)
                        if fs ~= nil then
                            method(fs, "ClearAllPoints")
                            method(fs, "SetPoint", "LEFT", b, "LEFT", size.gap, 0)
                        end
                        local sel = texture(b, "BACKGROUND", "selected")
                        if i == part.selected then
                            if sel ~= nil then
                                method(sel, "SetAllPoints", b)
                                if not unproven.topicHighlight and pictured(sel, art.topicHighlight) then
                                    method(sel, "SetBlendMode", "ADD")
                                    method(sel, "SetAlpha", alpha.topicHighlight or 1)
                                    note("topicHighlight", "first")
                                else
                                    paint(sel, color.selected)
                                    note("topicHighlight", "fallback")
                                end
                            end
                            inked(fs, color.accent)
                        else
                            if sel ~= nil then method(sel, "Hide") end
                            inked(fs, color.text)
                        end
                        hover(b)
                        hook(b, "OnClick", function()
                            if i ~= part.selected then tell(part.onSelect, i) end
                        end)
                    end
                    y = y + size.topicRow
                end
                if scrolls then sized(child, innerW, math.max(y, 1)) end
                -- Everything after it goes in the pane at its right.
                pane.x = pane.x + size.topicWidth + size.pad
                pane.w = pane.w - size.topicWidth - size.pad
                pane.rows = 0
            end

            function DRAW.section(part, pane)
                if not pane.first then pane.y = pane.y + size.gap end
                -- Lead section 340: a big section is the pane's page heading
                -- (the retail Settings window's category title) in the large
                -- font; the plain form, when the client lacks that font, is
                -- the kit's big font.
                local big = part.big == true
                local hgt = size.section
                if big then hgt = size.pageTitle or size.section end
                local h = box(pane, hgt, "section")
                local s
                if big then
                    s = words(h, font.pageTitle, "pageTitle")
                    if s ~= nil then
                        note("pageTitle", "first")
                    else
                        s = words(h, font.big, "pageTitlePlain")
                        note("pageTitle", "fallback")
                    end
                else
                    s = words(h, font.heading, "heading")
                end
                if s ~= nil then
                    method(s, "SetPoint", "LEFT", h, "LEFT", 0, 0)
                    if big then inked(s, color.text) else inked(s, color.accent) end
                    method(s, "SetText", part.text)
                end
                edgeLine(h, "BOTTOM", color.divider, "d")
                -- A section that folds: a mark at its right, and a click
                -- anywhere on the heading tells the caller the new state.
                local foldMark = type(look.foldMark) == "table" and look.foldMark or {}
                local mark = words(h, font.heading, "fold")
                if mark ~= nil then
                    if part.folded == nil then
                        method(mark, "SetText", "")
                    else
                        method(mark, "SetPoint", "RIGHT", h, "RIGHT", -size.gapSmall, 0)
                        inked(mark, color.textDim)
                        if part.folded then
                            method(mark, "SetText", foldMark.closed or "")
                        else
                            method(mark, "SetText", foldMark.open or "")
                        end
                    end
                end
                if part.folded ~= nil then
                    method(h, "EnableMouse", true)
                    hook(h, "OnMouseUp", function() tell(part.onFold, not part.folded) end)
                end
            end

            -- A list row: an icon, a name, a second line under it, and a
            -- short text at the right. A click tells the caller.
            function DRAW.line(part, pane)
                local hgt = size.lineHeight
                local hasSub = type(part.sub) == "string" and part.sub ~= ""
                if hasSub then hgt = size.rowHeightDesc end
                local h = box(pane, hgt, "listRow")
                stripe(h, pane)
                local left = size.gapSmall
                local holder = plain("Frame", h, "icon")
                if holder ~= nil then
                    local icon = texture(holder, "ARTWORK", "icon")
                    local own = icon ~= nil and part.icon ~= nil and pictured(icon, part.icon)
                    if own then
                        sized(holder, size.icon, size.icon)
                        method(holder, "SetPoint", "LEFT", h, "LEFT", size.gapSmall, 0)
                        method(icon, "SetAllPoints", holder)
                        method(holder, "Show")
                        left = size.gapSmall * 2 + size.icon
                    else
                        method(holder, "Hide")
                    end
                end
                local off = part.enabled == false
                local right = size.gapSmall
                local r = words(h, font.small, "right")
                if r ~= nil then
                    if type(part.right) == "string" and part.right ~= "" then
                        method(r, "SetPoint", "RIGHT", h, "RIGHT", -right, 0)
                        inked(r, color[part.tone or "textDim"] or color.textDim)
                        method(r, "SetText", part.right)
                        right = right + widthOf(r, size.buttonMin) + size.gap
                    else
                        method(r, "SetText", "")
                    end
                end
                local nm = words(h, font.label, "name")
                if nm ~= nil then
                    if hasSub then
                        method(nm, "SetPoint", "TOPLEFT", h, "TOPLEFT", left, -size.gapSmall)
                    else
                        method(nm, "SetPoint", "LEFT", h, "LEFT", left, 0)
                    end
                    method(nm, "SetWidth", math.max(pane.w - left - right, 1))
                    method(nm, "SetJustifyH", "LEFT")
                    if off then inked(nm, color.textOff) else inked(nm, color.text) end
                    local wraps = part.wrap == true and not hasSub
                    -- words() turns wrapping off, and the name is kept from
                    -- draw to draw: set it each time.
                    method(nm, "SetWordWrap", wraps)
                    method(nm, "SetText", part.text)
                    -- Lead section 408: a line that wraps is as tall as its
                    -- text, and the parts under it start below it. A height
                    -- the client does not give leaves the line one row high.
                    if wraps then
                        local okH, textH = method(nm, "GetStringHeight")
                        if okH and type(textH) == "number" and not hidden(textH) and textH > 0 then
                            local tall = math.ceil(textH) + 2 * size.gapSmall
                            if tall > hgt then
                                sized(h, pane.w, tall)
                                pane.y = pane.y + tall - hgt
                            end
                        end
                    end
                end
                local sub = words(h, font.small, "sub")
                if sub ~= nil then
                    if hasSub then
                        method(sub, "SetPoint", "BOTTOMLEFT", h, "BOTTOMLEFT", left, size.gapSmall)
                        method(sub, "SetWidth", math.max(pane.w - left - right, 1))
                        method(sub, "SetJustifyH", "LEFT")
                        if off then inked(sub, color.textOff) else inked(sub, color.textDim) end
                        method(sub, "SetText", part.sub)
                    else
                        method(sub, "SetText", "")
                    end
                end
                hover(h, part.tooltip)
                if not off and type(part.onClick) == "function" then
                    hook(h, "OnMouseUp", function() tell(part.onClick) end)
                end
            end

            function DRAW.row(part, pane)
                local off = part.enabled == false
                local desc = part.description
                if off and type(part.reason) == "string" and part.reason ~= "" then desc = part.reason end
                if desc == "" then desc = nil end
                local hgt = size.rowHeight
                if desc ~= nil then hgt = size.rowHeightDesc end
                local h = box(pane, hgt, "row")
                stripe(h, pane)
                -- A narrow pane (beside a topic list, or a window drawn
                -- small) shares its width: the control takes half at most,
                -- so the label always has room and never lies under it.
                local controlW = math.min(size.controlColumn, math.floor(pane.w / 2))
                local labelW = math.max(pane.w - controlW - size.gap, 1)
                local l = words(h, font.label, "label")
                if l ~= nil then
                    if desc ~= nil then
                        method(l, "SetPoint", "TOPLEFT", h, "TOPLEFT", 0, -size.gapSmall)
                    else
                        method(l, "SetPoint", "LEFT", h, "LEFT", 0, 0)
                    end
                    method(l, "SetWidth", labelW)
                    if off then inked(l, color.textOff) else inked(l, color.text) end
                    method(l, "SetText", part.label)
                end
                if desc ~= nil then
                    local fontName = font.small
                    if off then fontName = font.off end
                    local d = words(h, fontName, "description")
                    if d ~= nil then
                        method(d, "SetPoint", "BOTTOMLEFT", h, "BOTTOMLEFT", 0, size.gapSmall)
                        method(d, "SetWidth", labelW)
                        if off then inked(d, color.textOff) else inked(d, color.textDim) end
                        method(d, "SetText", desc)
                    end
                end
                local tipText = part.tooltip
                if tipText == nil then tipText = part.description end
                local control = part.control
                local frames = nil
                if control ~= nil and CONTROL[control.kind] ~= nil then
                    frames = CONTROL[control.kind](control, h, pane.w - controlW, controlW, not off)
                end
                -- Lead section 340: a row with a control takes no mouse (box
                -- set it off); its control stands two levels above it and
                -- carries the row's tooltip. A row with no control and a
                -- tooltip takes the mouse for the tooltip alone.
                if type(frames) == "table" and #frames > 0 then
                    local okL, level = method(h, "GetFrameLevel")
                    for _, one in ipairs(frames) do
                        if okL and type(level) == "number" and not hidden(level) then
                            method(one, "SetFrameLevel", level + 2)
                        end
                        local own = on[one]
                        if type(tipText) == "string" and tipText ~= "" and (own == nil or own.OnEnter == nil) then
                            hook(one, "OnEnter", function() tipShow(one, tipText) end, true)
                            hook(one, "OnLeave", function() tipHide(one) end, true)
                        end
                    end
                elseif type(tipText) == "string" and tipText ~= "" then
                    hover(h, tipText)
                end
            end

            -- A control standing on its own line.
            local function solo(part, pane)
                local h = box(pane, size.rowHeight, "solo")
                local colW = pane.w
                if part.kind == "bind" then colW = math.min(pane.w, size.controlColumn) end
                CONTROL[part.kind](part, h, 0, colW, true)
            end
            DRAW.button, DRAW.checkbox, DRAW.bind = solo, solo, solo
            function DRAW.choice(part, pane)
                local h = box(pane, size.rowHeight, "solo")
                CONTROL.choice(part, h, 0, math.min(pane.w, size.controlColumn), true)
            end
            function DRAW.number(part, pane)
                local h = box(pane, size.rowHeight, "solo")
                CONTROL.number(part, h, 0, math.min(pane.w, size.controlColumn), true)
            end
            function DRAW.text(part, pane)
                local h = box(pane, size.rowHeight, "solo")
                CONTROL.text(part, h, 0, math.min(pane.w, size.controlColumn), true)
            end

            function DRAW.scroll(part, pane, last)
                local room = pane.h - pane.y
                local hgt = part.height
                -- The list never runs past the pane: it takes the room that
                -- is left, and one line's height when there is none.
                if last or hgt > room then hgt = room end
                if hgt < size.lineHeight then hgt = size.lineHeight end
                local child, innerW, scrolls = scrollWell(pane.parent, pane.x, pane.y, pane.w, hgt, "list")
                local inner = { parent = child, x = 0, y = 0, w = innerW, h = hgt - 2 * size.edge, first = true, rows = 0 }
                for i = 1, #part.children do place(part.children[i], inner, false) end
                if scrolls then sized(child, innerW, math.max(inner.y, 1)) end
                pane.y = pane.y + hgt + size.gap
            end

            function DRAW.itemLine(part, pane)
                local h = box(pane, size.lineHeight, "line")
                stripe(h, pane)
                local holder = plain("Frame", h, "icon")
                if holder ~= nil then
                    sized(holder, size.icon, size.icon)
                    method(holder, "SetPoint", "LEFT", h, "LEFT", size.gapSmall, 0)
                    local ring = texture(holder, "BACKGROUND", "ring")
                    if not unproven.iconBorder and ring ~= nil and pictured(ring, art.iconBorder) then
                        method(ring, "SetAllPoints", holder)
                        note("iconBorder", "first")
                    else
                        if ring ~= nil then method(ring, "Hide") end
                        border(holder)
                        note("iconBorder", "fallback")
                    end
                    local icon = texture(holder, "ARTWORK", "icon")
                    if icon ~= nil then
                        method(icon, "SetAllPoints", holder)
                        local own = part.icon ~= nil and pictured(icon, part.icon)
                        if not own then
                            if pictured(icon, art.iconMissing) then
                                note("iconMissing", "first")
                            else
                                paint(icon, color.inset)
                                note("iconMissing", "fallback")
                            end
                        end
                    end
                end
                -- From the right: the note or the coins, then the count.
                local right = size.gapSmall
                if type(part.note) == "string" and part.note ~= "" then
                    local n = words(h, font.small, "note")
                    if n ~= nil then
                        method(n, "SetPoint", "RIGHT", h, "RIGHT", -right, 0)
                        inked(n, color[part.tone or "textDim"] or color.textDim)
                        method(n, "SetText", part.note)
                        right = right + widthOf(n, size.buttonMin) + size.gap
                    end
                elseif type(part.coins) == "table" and type(part.coins.coins) == "table" then
                    right = coins(h, part.coins.coins, right, "RIGHT") + size.gapSmall
                end
                if type(part.count) == "number" and part.count ~= 1 then
                    local n = words(h, font.small, "count")
                    if n ~= nil then
                        method(n, "SetPoint", "RIGHT", h, "RIGHT", -right, 0)
                        inked(n, color.textDim)
                        method(n, "SetText", "x" .. part.count)
                        right = right + widthOf(n, size.icon) + size.gap
                    end
                end
                local nm = words(h, font.label, "name")
                if nm ~= nil then
                    method(nm, "SetPoint", "LEFT", h, "LEFT", size.gapSmall * 2 + size.icon, 0)
                    method(nm, "SetPoint", "RIGHT", h, "RIGHT", -right, 0)
                    local q = part.color or {}
                    method(nm, "SetTextColor", q.r or color.text[1], q.g or color.text[2], q.b or color.text[3], 1)
                    method(nm, "SetText", part.name)
                end
                hover(h, nil, part.item)
            end

            function DRAW.empty(part, pane)
                local hgt = size.rowHeightDesc + 2 * size.pad
                -- Alone in its list it is centred in all of it.
                if pane.first and pane.h - pane.y > hgt then hgt = pane.h - pane.y end
                local h = box(pane, hgt, "empty")
                local a = words(h, font.big, "what")
                if a ~= nil then
                    method(a, "SetPoint", "BOTTOM", h, "CENTER", 0, size.gapSmall / 2)
                    method(a, "SetJustifyH", "CENTER")
                    inked(a, color.textDim)
                    method(a, "SetText", part.text)
                end
                local b = words(h, font.small, "how")
                if b ~= nil then
                    method(b, "SetPoint", "TOP", h, "CENTER", 0, -size.gapSmall / 2)
                    method(b, "SetJustifyH", "CENTER")
                    inked(b, color.textDim)
                    method(b, "SetText", part.how)
                end
            end

            -- The strip at the bottom: text and coins left; the slot, then
            -- the buttons, from the right.
            local function footer(part, w)
                local h = plain("Frame", body, "footer")
                if h == nil then error("the client made no frame for a part") end
                method(h, "SetPoint", "BOTTOMLEFT", body, "BOTTOMLEFT", 0, 0)
                sized(h, w, size.footer)
                edgeLine(h, "TOP", color.divider, "d")
                local x = 0
                if type(part.text) == "string" and part.text ~= "" then
                    local s = words(h, font.label, "text")
                    if s ~= nil then
                        method(s, "SetPoint", "LEFT", h, "LEFT", 0, 0)
                        inked(s, color.text)
                        method(s, "SetText", part.text)
                        x = widthOf(s, size.buttonMin / 2) + size.gap
                    end
                end
                if type(part.coins) == "table" and type(part.coins.coins) == "table" then
                    coins(h, part.coins.coins, x, "LEFT")
                end
                local right = 0
                if part.slot ~= nil then
                    local holder = plain("Frame", h, "slot")
                    if holder ~= nil then
                        sized(holder, size.buttonMin, size.button)
                        method(holder, "SetPoint", "RIGHT", h, "RIGHT", 0, 0)
                        slots[part.slot] = holder
                        right = size.buttonMin + size.gap
                    end
                end
                for i = #part.buttons, 1, -1 do
                    local one = part.buttons[i]
                    local b, bw = button(h, one.text, nil, one.enabled ~= false, function() tell(one.onClick) end, one.tooltip)
                    if b ~= nil then
                        method(b, "SetPoint", "RIGHT", h, "RIGHT", -right, 0)
                        right = right + bw + size.gap
                    end
                end
            end

            -- The frame's own art, its title, the drag area, the close
            -- button and the grip.
            local function chrome(now)
                -- The stock frame brings its own title text and close button.
                local stockTitle, stockClose = nil, nil
                if stockFrame then
                    local okT, own = pcall(function() return f.TitleText end)
                    if okT and type(own) == "table" then stockTitle = own end
                    if stockTitle == nil then
                        -- Newer frames keep the title in a holder.
                        local okH, held = pcall(function() return f.TitleContainer.TitleText end)
                        if okH and type(held) == "table" then stockTitle = held end
                    end
                    local okC, ownClose = pcall(function() return f.CloseButton end)
                    if okC and type(ownClose) == "table" then stockClose = ownClose end
                end
                if stockFrame then
                    note("frame", "first")
                else
                    note("frame", "fallback")
                    backing(f, color.fill, "fill")
                    border(f)
                    local strip = texture(f, "BORDER", "strip")
                    if strip ~= nil then
                        method(strip, "SetPoint", "TOPLEFT", f, "TOPLEFT", 0, 0)
                        method(strip, "SetPoint", "BOTTOMRIGHT", f, "TOPRIGHT", 0, -size.title)
                        paint(strip, color.inset)
                    end
                    local under = texture(f, "ARTWORK", "under")
                    if under ~= nil then
                        method(under, "SetPoint", "TOPLEFT", f, "TOPLEFT", 0, -size.title)
                        method(under, "SetPoint", "TOPRIGHT", f, "TOPRIGHT", 0, -size.title)
                        method(under, "SetHeight", size.edge)
                        paint(under, color.divider)
                    end
                end
                if stockTitle ~= nil then
                    method(stockTitle, "SetText", now.title)
                else
                    local t = words(f, font.title, "title")
                    if t ~= nil then
                        method(t, "SetPoint", "TOPLEFT", f, "TOPLEFT", size.title, 0)
                        method(t, "SetPoint", "BOTTOMRIGHT", f, "TOPRIGHT", -size.title, -size.title)
                        method(t, "SetJustifyH", "CENTER")
                        inked(t, color.accent)
                        method(t, "SetText", now.title)
                    end
                end

                -- Moved by the title area only.
                method(f, "SetMovable", now.movable == true)
                if now.movable == true then
                    local bar = plain("Frame", f, "bar")
                    if bar ~= nil then
                        method(bar, "SetPoint", "TOPLEFT", f, "TOPLEFT", 0, 0)
                        method(bar, "SetPoint", "BOTTOMRIGHT", f, "TOPRIGHT", -size.title, -size.title)
                        method(bar, "EnableMouse", true)
                        method(bar, "RegisterForDrag", "LeftButton")
                        hook(bar, "OnDragStart", function() method(f, "StartMoving") end)
                        hook(bar, "OnDragStop", function()
                            method(f, "StopMovingOrSizing")
                            -- The client would otherwise keep a moved named
                            -- frame's place itself and put it back there.
                            method(f, "SetUserPlaced", false)
                            tellMoved()
                        end)
                    end
                end

                local function closeClicked()
                    if not open then return end
                    method(f, "Hide")
                    -- OnHide has told it already on a client that runs it.
                    playerClosed()
                end
                if stockClose ~= nil then
                    if now.closable == true then
                        method(stockClose, "Show")
                        hook(stockClose, "OnClick", closeClicked)
                        note("close", "first")
                    else
                        method(stockClose, "Hide")
                    end
                elseif now.closable == true then
                    local b, which = made("Button", f, "close")
                    if b ~= nil then
                        if which ~= "first" then
                            method(b, "SetNormalFontObject", font.label)
                            method(b, "SetText", "x")
                        end
                        sized(b, size.title, size.title)
                        method(b, "SetPoint", "TOPRIGHT", f, "TOPRIGHT", 0, 0)
                        hook(b, "OnClick", closeClicked)
                    end
                end

                method(f, "SetResizable", now.resizable == true)
                if now.resizable == true then
                    local least, leastH = now.minWidth or width, now.minHeight or height
                    if not method(f, "SetResizeBounds", least, leastH) then method(f, "SetMinResize", least, leastH) end
                    local grip = plain("Button", f, "grip")
                    if grip ~= nil then
                        sized(grip, size.grip, size.grip)
                        method(grip, "SetPoint", "BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
                        method(grip, "EnableMouse", true)
                        local corner = texture(grip, "OVERLAY", "corner")
                        local okN = false
                        if not unproven.grip then okN = method(grip, "SetNormalTexture", art.grip) end
                        if okN then
                            if corner ~= nil then method(corner, "Hide") end
                            if not unproven.gripOver then method(grip, "SetHighlightTexture", art.gripOver) end
                            if not unproven.gripDown then method(grip, "SetPushedTexture", art.gripDown) end
                            note("grip", "first")
                        else
                            if corner ~= nil then
                                sized(corner, size.gripCorner, size.gripCorner)
                                method(corner, "SetPoint", "BOTTOMRIGHT", grip, "BOTTOMRIGHT", 0, 0)
                                paint(corner, color.edge)
                            end
                            note("grip", "fallback")
                        end
                        hook(grip, "OnMouseDown", function() method(f, "StartSizing", "BOTTOMRIGHT") end)
                        hook(grip, "OnMouseUp", function()
                            method(f, "StopMovingOrSizing")
                            method(f, "SetUserPlaced", false)
                            tellMoved()
                            -- Laid out again at the new size.
                            local ok, err = pcall(draw, tree)
                            if not ok then fail(err) end
                        end)
                    end
                end
            end

            -- What is drawn: a raise partway still ends the sweep, so no part
            -- of the tree before it is left showing beside the half-drawn
            -- one; the raise then goes on to the caller.
            local function drawParts(now)
                sized(f, width, height)
                chrome(now)
                body = plain("Frame", f, "body")
                if body == nil then error("the client made no frame for the content") end
                method(body, "EnableMouse", false)
                method(body, "SetPoint", "TOPLEFT", f, "TOPLEFT", size.pad, -(size.title + size.pad))
                method(body, "SetPoint", "BOTTOMRIGHT", f, "BOTTOMRIGHT", -size.pad, size.pad)
                local w, h = width - 2 * size.pad, height - size.title - 2 * size.pad
                local kids = now.children
                local lastFlow, hasFooter = 0, false
                topicsInWindow = false
                for i = 1, #kids do
                    if kids[i].kind == "topicList" then topicsInWindow = true end
                end
                for i = 1, #kids do
                    if kids[i].kind == "footer" then
                        footer(kids[i], w)
                        hasFooter = true
                    else
                        lastFlow = i
                    end
                end
                if hasFooter then h = h - size.footer end
                local pane = { parent = body, x = 0, y = 0, w = w, h = h, first = true, rows = 0 }
                for i = 1, #kids do
                    if kids[i].kind ~= "footer" then place(kids[i], pane, i == lastFlow) end
                end
                -- Lead section 408: a window that fits is as tall as what
                -- was just drawn in it: the title bar, the padding, the
                -- parts and the footer. Its width stays.
                if now.fit == true then
                    local want = size.title + 2 * size.pad + pane.y
                    if hasFooter then want = want + size.footer end
                    if want ~= height then
                        height = want
                        sized(f, width, height)
                    end
                end
            end
            draw = function(now)
                reread()
                closeDrop()
                sweepStart()
                slots = {}
                keeps = {}
                local ok, err = pcall(drawParts, now)
                sweepEnd()
                -- Lead section 340: each scroll back where it was, never
                -- past the end of what is drawn now.
                for _, keep in ipairs(keeps) do
                    local okH, childH = method(keep.child, "GetHeight")
                    local most = 0
                    if okH and type(childH) == "number" and not hidden(childH) then most = childH - keep.view end
                    if most < 0 then most = 0 end
                    local to = keep.at
                    if to > most then to = most end
                    method(keep.scroll, "SetVerticalScroll", to)
                end
                -- Lead section 319: which parts were the game's own and
                -- which the plain form, for the diagnostics.
                if kitDrawnFn ~= nil then
                    local art = {}
                    for key, which in pairs(drew) do art[key] = which end
                    pcall(kitDrawnFn, id, art)
                end
                if not ok then error(err, 0) end
            end

            local point = type(cb.point) == "table" and cb.point or tree.point
            if type(point) == "table" then
                method(f, "ClearAllPoints")
                method(f, "SetPoint", point[1], parent, point[2], point[3], point[4])
            end
            -- A first draw that fails does not lose the frame: the window is
            -- kept, the caller is told, and asking again draws on this frame.
            local drawn, drawErr = pcall(draw, tree)

            local h = {}
            function h.update(now)
                if type(now) ~= "table" or now.kind ~= "window" or type(now.children) ~= "table" then return false end
                local ok, err = pcall(draw, now)
                if not ok then
                    fail(err)
                    return false
                end
                tree = now
                return true
            end
            -- Lead section 348: moves and resizes the built window, keeping its
            -- frame and border: point = { anchor, screen anchor, x, y } or nil
            -- (keep the place), width / height numbers above 0 or nil (keep
            -- that one). The size is never below the window's least size. The
            -- parts are drawn again in the new size. No onMoved: the player
            -- did not move it. -> true | false, why
            function h.place(point, w, ht)
                if point ~= nil then
                    if type(point) ~= "table" or type(point[1]) ~= "string" or type(point[2]) ~= "string"
                        or type(point[3]) ~= "number" or type(point[4]) ~= "number" then
                        return false, "a place is anchor, screen anchor, x, y"
                    end
                end
                for _, v in ipairs({ w or 1, ht or 1 }) do
                    if type(v) ~= "number" or v ~= v or v <= 0 or v == math.huge then
                        return false, "a size is a number above 0"
                    end
                end
                if point ~= nil then
                    method(f, "ClearAllPoints")
                    method(f, "SetPoint", point[1], parent, point[2], point[3], point[4])
                end
                if w ~= nil then width = math.max(w, tonumber(tree.minWidth) or 0) end
                if ht ~= nil then height = math.max(ht, tonumber(tree.minHeight) or 0) end
                local ok, err = pcall(draw, tree)
                if not ok then
                    fail(err)
                    return false, "the window could not be drawn in its new size"
                end
                return true
            end
            -- open: shown by show(true) and not since hidden by the add-on
            -- or closed by the player. Only a hide while open is the player's.
            function h.show(shown)
                closeDrop()
                open = shown and true or false
                method(f, open and "Show" or "Hide")
            end
            function h.shown() return open end
            function h.close() h.show(false) end
            function h.art()
                local out = {}
                for key, which in pairs(drew) do out[key] = which end
                return out
            end
            function h.slot(slotName) return slots[slotName] end
            return h, function(extra) cb = extra end, drawn, drawErr
        end

        function c.kitWindow(id, tree, extra)
            local cb = type(extra) == "table" and extra or {}
            local known = nil
            if type(id) == "string" then known = kitWindows[id] end
            if known ~= nil then
                known.set(cb)
                -- update tells failed itself when its draw raises.
                if known.handle.update(tree) then return known.handle end
                if type(tree) ~= "table" or tree.kind ~= "window" then
                    if type(cb.failed) == "function" then pcall(cb.failed, "a kit window needs a tree from Kit.Window") end
                end
                return nil
            end
            local ok, h, set, drawn, drawErr = pcall(kitBuild, id, tree, cb)
            if not ok or h == nil then
                if type(cb.failed) == "function" then pcall(cb.failed, h) end
                return nil
            end
            -- Kept even when its first draw failed, so a later ask makes no
            -- second top frame.
            kitWindows[id] = { handle = h, set = set }
            if not drawn then
                if type(cb.failed) == "function" then pcall(cb.failed, drawErr) end
                return nil
            end
            return h
        end
    end
    -- The settings window (lead sections 285 item 3 and 303 item 2): the
    -- add-on's settings in one window of the kit above. New, added at the
    -- end. No window system of its own and no game call of its own: it
    -- hands the caller's tree to c.kitWindow, so every first guess is the
    -- kit drawer's. LOOK ONLY: a control runs the caller's own function.
    --   c.settingsWindow(spec) -> page | nil
    --     spec: id (the kit window's id), build(rows, act, nav, layout) ->
    --     a Kit.Window tree | nil, reason; optional name, point, width,
    --     height, onMoved, onClose, failed (handed to c.kitWindow as they
    --     are). nil for a spec without id or build.
    --   page.draw(rows, act, nav, layout) -> true | false, reason
    --     builds the tree and draws it; the window is made at the first
    --     draw, hidden. A build that raises goes up to the caller.
    --   page.open() -> true once it is shown; false before any draw
    --   page.hide(), page.shown()
    do
        function c.settingsWindow(spec)
            if type(spec) ~= "table" or type(spec.id) ~= "string" or type(spec.build) ~= "function" then
                return nil
            end
            local extra = { name = spec.name, point = spec.point, width = spec.width, height = spec.height,
                onMoved = spec.onMoved, onClose = spec.onClose, failed = spec.failed }
            local h
            local page = {}
            -- Lead section 340: at most one draw a drawn frame. A draw asked
            -- for after one already ran in this frame is held, and only the
            -- last one held is drawn at the next frame. A tree the same as
            -- the one drawn (functions aside) is not drawn again.
            local drewThisFrame, held, ticking, deferOk, lastSig = false, nil, false, true, nil
            local function signature(v, out, depth)
                local kind = type(v)
                if kind == "table" then
                    if depth > 40 then
                        out[#out + 1] = "~"
                        return
                    end
                    local keys = {}
                    for key, value in pairs(v) do
                        if type(value) ~= "function" then
                            keys[#keys + 1] = { name = type(key) .. ":" .. tostring(key), key = key }
                        end
                    end
                    table.sort(keys, function(a, b) return a.name < b.name end)
                    out[#out + 1] = "{"
                    for _, one in ipairs(keys) do
                        out[#out + 1] = one.name .. "="
                        signature(v[one.key], out, depth + 1)
                        out[#out + 1] = ","
                    end
                    out[#out + 1] = "}"
                elseif kind ~= "function" then
                    out[#out + 1] = kind .. ":" .. tostring(v)
                end
            end
            local function sigOf(tree)
                local out = {}
                signature(tree, out, 0)
                return table.concat(out)
            end
            local function drawNow(tree, sig)
                drewThisFrame = true
                if h.update(tree) ~= true then return false, "the kit could not draw the settings window again" end
                lastSig = sig
                return true
            end
            local function tick()
                drewThisFrame = false
                if held ~= nil then
                    local one = held
                    held = nil
                    drawNow(one.tree, one.sig)
                end
            end
            local function startTicking()
                if ticking then return end
                ticking = true
                c.onFrame(tick)
                local okF, faults = pcall(c.listenFaults)
                if okF and type(faults) == "table" and faults.noTickFrame == true then deferOk = false end
            end
            function page.draw(rows, act, nav, layout)
                local tree, why = spec.build(rows, act, nav, layout)
                if type(tree) ~= "table" then return false, why or "the settings window has no tree" end
                if h == nil then
                    h = c.kitWindow(spec.id, tree, extra)
                    if h == nil then return false, "the kit could not draw the settings window" end
                    h.show(false)
                    lastSig = sigOf(tree)
                    drewThisFrame = true
                    startTicking()
                    return true
                end
                local sig = sigOf(tree)
                if held == nil and sig == lastSig then return true end
                if drewThisFrame and deferOk then
                    held = { tree = tree, sig = sig }
                    return true
                end
                held = nil
                return drawNow(tree, sig)
            end
            function page.open()
                if h == nil then return false, "the settings window was not drawn" end
                h.show(true)
                return true
            end
            function page.hide()
                if h ~= nil then h.show(false) end
            end
            function page.shown() return h ~= nil and h.shown() == true end
            return page
        end
    end
    ---------------------------------------------------------------------
    -- N60b: chat readability (UI/Chat.lua). How a chat window looks:
    -- nothing is sent and no chat frame's own function or script is
    -- replaced. Every call is a first guess, not seen in game on 16001;
    -- the names are in Diag.NAMES. Window i is the global ChatFrame<i>,
    -- its tab ChatFrame<i>Tab (warcraft.wiki.gg, ScrollingMessageFrame,
    -- FontInstance, ScriptObject).
    --
    --   client.chatFont(i) -> size | nil
    --     frame:GetFont() second answer. nil: no window, a raise, hidden.
    --   client.setChatFont(i, size) -> true | nil
    --     frame:SetFont(path, size, flags) with the path and flags the
    --     window has now. For this session only: the game's own saved chat
    --     size is not written.
    --   client.chatFading(i) -> { fading = bool, time = n } | nil
    --     frame:GetFading() and frame:GetTimeVisible().
    --   client.setChatFading(i, fading[, time]) -> true | nil
    --     frame:SetFading(fading), then frame:SetTimeVisible(time) when a
    --     time above 0 is given.
    --   client.chatWheel(i, fn) -> cancel | nil
    --     fn(delta, ctrl, shift) after the game's own wheel step on window
    --     i; it answers "top", "bottom", a number of extra lines in the
    --     wheel's direction (at most 50), or nothing. Through
    --     frame:HookScript("OnMouseWheel"): runs after the game's handler,
    --     never in its place, so the game's own scrolling and its secure
    --     state are untouched. A hook cannot be taken off: cancel makes it
    --     do nothing. IsControlKeyDown / IsShiftKeyDown for the keys.
    --   client.chatTabAlpha(i, alpha | nil) -> true | nil
    --     Holds tab i at least `alpha` against the game's fade:
    --     hooksecurefunc(tab, "SetAlpha") puts it back up after each lower
    --     alpha the game asks. nil lets go and gives the tab the alpha the
    --     game asked last.
    --   client.localTime() -> hour, min, sec | nil
    --     date("*t"), the computer's local time.
    ---------------------------------------------------------------------
    do
        local WHEEL_MOST = 50

        local function chatWindow(i)
            if type(i) ~= "number" or i < 1 or i ~= math.floor(i) then return nil end
            local frame = env["ChatFrame" .. i]
            if type(frame) ~= "table" then return nil end
            return frame
        end

        function c.chatFont(i)
            local ok, _, size = method(chatWindow(i), "GetFont")
            if not ok or hidden(size) or type(size) ~= "number" then return nil end
            return size
        end

        function c.setChatFont(i, size)
            if type(size) ~= "number" or size <= 0 then return nil end
            local frame = chatWindow(i)
            local ok, path, now, flags = method(frame, "GetFont")
            if not ok or hidden(path) or hidden(now) or hidden(flags) or type(path) ~= "string" then return nil end
            if not method(frame, "SetFont", path, size, flags) then return nil end
            return true
        end

        function c.chatFading(i)
            local frame = chatWindow(i)
            local okF, fading = method(frame, "GetFading")
            local okT, time = method(frame, "GetTimeVisible")
            if not okF or not okT or hidden(fading) or hidden(time) or type(time) ~= "number" then return nil end
            return { fading = fading == true, time = time }
        end

        function c.setChatFading(i, fading, time)
            if type(fading) ~= "boolean" then return nil end
            local frame = chatWindow(i)
            if not method(frame, "SetFading", fading) then return nil end
            if type(time) == "number" and time > 0 then
                if not method(frame, "SetTimeVisible", time) then return nil end
            end
            return true
        end

        local function keyDown(fn)
            local ok, down = call(fn)
            if not ok or hidden(down) then return false end
            return down ~= nil and down ~= false and down ~= 0
        end

        local wheels = {}
        function c.chatWheel(i, fn)
            if type(fn) ~= "function" then return nil end
            local frame = chatWindow(i)
            if frame == nil then return nil end
            local w = wheels[i]
            if w == nil or w.frame ~= frame then
                w = { frame = frame }
                local function onWheel(_, delta)
                    local f = w.fn
                    if f == nil or hidden(delta) or type(delta) ~= "number" or delta == 0 then return end
                    local okF, what = pcall(f, delta, keyDown(env.IsControlKeyDown), keyDown(env.IsShiftKeyDown))
                    if not okF then return end
                    if what == "top" then
                        method(frame, "ScrollToTop")
                    elseif what == "bottom" then
                        method(frame, "ScrollToBottom")
                    elseif type(what) == "number" and what >= 1 then
                        local step = "ScrollDown"
                        if delta > 0 then step = "ScrollUp" end
                        local n = math.floor(what)
                        if n > WHEEL_MOST then n = WHEEL_MOST end
                        for _ = 1, n do method(frame, step) end
                    end
                end
                if not method(frame, "HookScript", "OnMouseWheel", onWheel) then return nil end
                wheels[i] = w
            end
            w.fn = fn
            return function()
                if w.fn == fn then w.fn = nil end
            end
        end

        local tabs = {}
        function c.chatTabAlpha(i, alpha)
            if type(i) ~= "number" then return nil end
            local tab = env["ChatFrame" .. i .. "Tab"]
            if type(tab) ~= "table" then return nil end
            local held = tabs[i]
            if held == nil or held.tab ~= tab then
                if type(env.hooksecurefunc) ~= "function" then return nil end
                held = { tab = tab, busy = false }
                local okA, now = method(tab, "GetAlpha")
                if okA and not hidden(now) and type(now) == "number" then held.asked = now end
                local function onAlpha(_, a)
                    if held.busy or hidden(a) or type(a) ~= "number" then return end
                    held.asked = a
                    if held.hold ~= nil and a < held.hold then
                        held.busy = true
                        method(tab, "SetAlpha", held.hold)
                        held.busy = false
                    end
                end
                if not pcall(env.hooksecurefunc, tab, "SetAlpha", onAlpha) then return nil end
                tabs[i] = held
            end
            held.busy = true
            if type(alpha) == "number" then
                held.hold = alpha
                method(tab, "SetAlpha", alpha)
            else
                held.hold = nil
                if held.asked ~= nil then method(tab, "SetAlpha", held.asked) end
            end
            held.busy = false
            return true
        end

        function c.localTime()
            local ok, t = call(env.date, "*t")
            if not ok or hidden(t) or type(t) ~= "table" then return nil end
            local h, m, s = tonumber(t.hour), tonumber(t.min), tonumber(t.sec)
            if h == nil or m == nil or s == nil then return nil end
            return h, m, s
        end
    end
    -- N60c (UI/Chat.lua, chat mentions): c.playerName() -> name | nil.
    --   The player's own name, UnitName("player")'s first answer, without a
    --   realm; nil when not known (no call, a failed call, a secret or
    --   empty answer). A first guess on 16001, not seen in game. Read only.
    do
        function c.playerName()
            local ok, name = call(env.UnitName, "player")
            if not ok or name == nil or hidden(name) or type(name) ~= "string" or name == "" then return nil end
            return name
        end
    end

    -- G38: whether the player is indoors (a cave, a building): true or
    -- false, nil when the client will not say. IsIndoors() answers 1 or nil
    -- in the classic clients; a nil from a call that is there is read as
    -- "not indoors". A first guess: not seen in game on 16001.
    function c.indoors()
        if type(env.IsIndoors) ~= "function" then return nil end
        local ok, v = call(env.IsIndoors)
        if not ok or hidden(v) then return nil end
        if v == true or v == 1 then return true end
        if v == false or v == nil or v == 0 then return false end
        return nil
    end

    -- G47: where a party or raid member is on the map the client picks for
    -- them: { map = uiMapID, x = 0..1, y = 0..1 }, or nil (not a party
    -- unit, another map, an instance, no answer, or a hidden answer).
    -- C_Map.GetBestMapForUnit(unit) and C_Map.GetPlayerMapPosition(map,
    -- unit), the calls the player's own position uses, asked for the unit.
    -- A first guess: not seen in game on 16001. Only party1..4 and
    -- raid1..40 are asked; nothing is sent or shared.
    function c.unitPosition(unit)
        if type(unit) ~= "string" or not PARTY_UNITS[unit] then return nil end
        local okMap, map = mapCall("GetBestMapForUnit", unit)
        if not okMap or hidden(map) or type(map) ~= "number" then return nil end
        local ok, pos = mapCall("GetPlayerMapPosition", map, unit)
        if not ok or hidden(pos) or type(pos) ~= "table" then return nil end
        local okXY, x, y = call(pos.GetXY, pos)
        if not okXY then x, y = pos.x, pos.y end
        if hidden(x) or hidden(y) or type(x) ~= "number" or type(y) ~= "number" then return nil end
        if x ~= x or y ~= y or (x == 0 and y == 0) then return nil end
        if x < 0 or x > 1 or y < 0 or y > 1 then return nil end
        return { map = map, x = x, y = y }
    end

    -- The minimap button (lead DISPATCH sections 340 and 303(g);
    -- UI/MinimapButton.lua): a small round button on the minimap's rim, or
    -- nil and why when the client cannot make it.
    --   spec = { name = global frame name or nil, title = the add-on's title
    --            (its first letter is the plain look's face) }
    --   h.place(x, y)    its middle x right and y up from the minimap's middle
    --   h.show(on)
    --   h.onClick(fn)    fn(button) on a click, button "left" or "right";
    --                    nothing else is done
    --   h.menu(items, pick)  the arrows' menu (menuOpen above) at the
    --                    pointer with these rows; pick(key) is told the row
    --                    chosen. nil or no rows closes this button's menu.
    --   h.onDrag(fn)     fn(dx, dy, done) while dragged with the left button:
    --                    the cursor's offset from the minimap's middle, in the
    --                    minimap's own units; done true once, at the drop
    --   h.tip(lines)     the tooltip lines shown on hover (nil: none)
    -- LOOK: the Blizzard minimap-button look. These texture paths move to
    -- the kit's theme (UI/Kit/Theme.lua) when the kit owner adds a
    -- minimap-button part; until then they are named here only:
    --   border     Interface\Minimap\MiniMap-TrackingBorder
    --   background Interface\Minimap\UI-Minimap-Background
    --   highlight  Interface\Minimap\UI-Minimap-ZoomButton-Highlight
    --   icon       Interface\Icons\INV_Misc_Map_01 (the add-on has no icon file
    --              of its own yet)
    -- A texture that does not set (SetTexture raises or answers false) gives
    -- the plain look instead: a square button with the title's first letter.
    -- First guesses, none seen in game on 16001. Docs (warcraft.wiki.gg):
    -- API CreateFrame ("Button", name, parent); Button RegisterForClicks,
    -- RegisterForDrag; Frame SetScript OnClick, OnDragStart, OnDragStop,
    -- OnUpdate, OnEnter, OnLeave; Region GetCenter, GetEffectiveScale; API
    -- GetCursorPosition (screen pixels, scaled by the effective scale);
    -- GameTooltip SetOwner, AddLine, Show, Hide; TextureBase SetTexture
    -- (returns success on recent clients; nil is taken as set).
    function c.minimapButton(spec)
        spec = type(spec) == "table" and spec or {}
        local map = env.Minimap
        if map == nil then return nil, "no minimap" end
        local ok, b = call(env.CreateFrame, "Button", spec.name, map)
        if not ok or b == nil then return nil, "no frame" end
        local BORDER = "Interface\\Minimap\\MiniMap-TrackingBorder"
        local BACK = "Interface\\Minimap\\UI-Minimap-Background"
        local HIGHLIGHT = "Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight"
        local ICON = "Interface\\Icons\\INV_Misc_Map_01"
        method(b, "Hide")
        method(b, "SetFrameStrata", "MEDIUM")
        method(b, "SetFrameLevel", 8)
        if not method(b, "SetSize", 31, 31) then
            method(b, "SetWidth", 31)
            method(b, "SetHeight", 31)
        end
        method(b, "RegisterForClicks", "LeftButtonUp", "RightButtonUp")
        method(b, "RegisterForDrag", "LeftButton")
        local function texture(layer, path, w, h, x, y)
            local okT, tex = method(b, "CreateTexture", nil, layer)
            if not okT or tex == nil then return nil, false end
            local okS, set = method(tex, "SetTexture", path)
            if not method(tex, "SetSize", w, h) then
                method(tex, "SetWidth", w)
                method(tex, "SetHeight", h)
            end
            method(tex, "SetPoint", "TOPLEFT", b, "TOPLEFT", x, y)
            return tex, okS and set ~= false and not hidden(set)
        end
        local back, okBack = texture("BACKGROUND", BACK, 20, 20, 7, -5)
        local icon, okIcon = texture("ARTWORK", ICON, 17, 17, 7, -6)
        local border, okBorder = texture("OVERLAY", BORDER, 53, 53, 0, 0)
        local okHigh = method(b, "SetHighlightTexture", HIGHLIGHT)
        if not (okBack and okIcon and okBorder and okHigh) then
            -- The plain look: one square face with the title's first letter.
            for _, tex in ipairs({ back, icon, border }) do method(tex, "Hide") end
            local okF, face = method(b, "CreateTexture", nil, "BACKGROUND")
            if okF and face ~= nil then
                method(face, "SetAllPoints", b)
                if not method(face, "SetColorTexture", 0, 0, 0, 0.7) then method(face, "SetTexture", 0, 0, 0, 0.7) end
            end
            local okL, letter = method(b, "CreateFontString", nil, "OVERLAY", "GameFontNormal")
            if okL and letter ~= nil then
                method(letter, "SetPoint", "CENTER", b, "CENTER", 0, 0)
                local title = type(spec.title) == "string" and spec.title or "?"
                method(letter, "SetText", title:sub(1, 1))
            end
        end
        local clickFn, dragFn, lines
        local function cursor()
            local okC, cx, cy = method(map, "GetCenter")
            local okE, scale = method(map, "GetEffectiveScale")
            local okP, px, py = call(env.GetCursorPosition)
            if not (okC and okE and okP) or hidden(cx) or hidden(cy) or hidden(scale) or hidden(px) or hidden(py) then
                return nil
            end
            if type(cx) ~= "number" or type(cy) ~= "number" or type(px) ~= "number" or type(py) ~= "number"
                or type(scale) ~= "number" or scale <= 0 then
                return nil
            end
            return px / scale - cx, py / scale - cy
        end
        local function drag(done)
            if type(dragFn) ~= "function" then return end
            local dx, dy = cursor()
            if dx ~= nil then pcall(dragFn, dx, dy, done) end
        end
        method(b, "SetScript", "OnClick", function(_, button)
            if type(clickFn) == "function" then pcall(clickFn, button == "RightButton" and "right" or "left") end
        end)
        method(b, "SetScript", "OnDragStart", function(self)
            method(self, "SetScript", "OnUpdate", function() drag(false) end)
        end)
        method(b, "SetScript", "OnDragStop", function(self)
            method(self, "SetScript", "OnUpdate", nil)
            drag(true)
        end)
        method(b, "SetScript", "OnEnter", function(self)
            local tip = env.GameTooltip
            if tip == nil or type(lines) ~= "table" then return end
            method(tip, "SetOwner", self, "ANCHOR_LEFT")
            for _, line in ipairs(lines) do method(tip, "AddLine", tostring(line), 1, 1, 1) end
            method(tip, "Show")
        end)
        method(b, "SetScript", "OnLeave", function()
            if env.GameTooltip ~= nil and type(lines) == "table" then method(env.GameTooltip, "Hide") end
        end)
        local h = {}
        function h.place(x, y)
            if type(x) ~= "number" or type(y) ~= "number" or x ~= x or y ~= y then return end
            method(b, "ClearAllPoints")
            method(b, "SetPoint", "CENTER", map, "CENTER", x, y)
        end
        function h.show(on)
            if on then
                method(b, "Show")
            else
                if menu.owner == h then menuClose() end
                method(b, "Hide")
            end
        end
        function h.onClick(fn) clickFn = fn end
        function h.onDrag(fn) dragFn = fn end
        function h.tip(t) lines = type(t) == "table" and t or nil end
        function h.menu(items, pick)
            if type(items) ~= "table" or #items == 0 then
                if menu.owner == h then menuClose() end
                return
            end
            menuOpen(h, b, items, pick, spec.name)
        end
        return h
    end

    -- Lead section 340: one diagnostics line naming the frame under the
    -- mouse, for a window that takes no clicks. New, added at the end.
    --   c.kitFocus() -> line
    --     the frame's name (or "unnamed"), its object type, its frame level,
    --     whether it takes the mouse, whether a kit window made it (and
    --     which), and up to 4 frames it stands on.
    -- First guesses on 16001: GetMouseFocus (the older clients'), else
    -- GetMouseFoci()[1] (the newer clients'); Frame GetName,
    -- GetObjectType, GetParent, GetFrameLevel and IsMouseEnabled.
    do
        local function nameOf(frame)
            local ok, n = method(frame, "GetName")
            if ok and type(n) == "string" and n ~= "" then return n end
            return "unnamed"
        end
        local function typeOf(frame)
            local ok, kind = method(frame, "GetObjectType")
            if ok and type(kind) == "string" and kind ~= "" then return kind end
            return "?"
        end
        function c.kitFocus()
            local focus
            if type(env.GetMouseFocus) == "function" then
                local ok, f = call(env.GetMouseFocus)
                if ok then focus = f end
            elseif type(env.GetMouseFoci) == "function" then
                local ok, list = call(env.GetMouseFoci)
                if ok and type(list) == "table" then focus = list[1] end
            else
                return "focus: the client has neither GetMouseFocus nor GetMouseFoci"
            end
            if focus == nil then return "focus: nothing under the mouse" end
            local parts = { "focus: " .. nameOf(focus) .. " " .. typeOf(focus) }
            local okL, level = method(focus, "GetFrameLevel")
            if okL and type(level) == "number" then parts[#parts + 1] = "level " .. level end
            local okM, mouse = method(focus, "IsMouseEnabled")
            if okM and mouse == true then
                parts[#parts + 1] = "takes the mouse"
            elseif okM and mouse == false then
                parts[#parts + 1] = "no mouse"
            end
            local owner = c.kitOwner(focus)
            if type(owner) == "string" then
                parts[#parts + 1] = "kit " .. owner
            else
                parts[#parts + 1] = "not the kit's"
            end
            local chain, at = {}, focus
            for _ = 1, 4 do
                local okP, up = method(at, "GetParent")
                if not okP or up == nil then break end
                local word = nameOf(up) .. " " .. typeOf(up)
                local upOwner = c.kitOwner(up)
                if type(upOwner) == "string" then word = word .. " (kit)" end
                chain[#chain + 1] = word
                at = up
            end
            if #chain > 0 then parts[#parts + 1] = "on " .. table.concat(chain, " < ") end
            return table.concat(parts, "; ")
        end
    end

    ---------------------------------------------------------------------
    -- N60d: chat part 4 (UI/Chat.lua). All first guesses, not seen in game
    -- on 16001.
    --
    --   client.classOfGuid(guid) -> class file ("MAGE") | nil
    --     GetPlayerInfoByGUID(guid), its second answer (warcraft.wiki.gg,
    --     API GetPlayerInfoByGUID). nil for no call, a failed call, or a
    --     secret or odd answer.
    --   client.chatNameByClass(chatType) -> true | false | nil
    --   client.setChatNameByClass(chatType, on) -> true | nil
    --     The game's own "colour names by class" of one chat kind ("GUILD",
    --     "CHANNEL1"): ChatTypeInfo[chatType].colorNameByClass, set through
    --     SetChatColorNameByClass(chatType, on). The game then colours the
    --     author's name itself, inside its own player link.
    --   client.chatTypeHeader(name) -> text | nil
    --   client.setChatTypeHeader(name, text) -> true | nil
    --     The game's label text of a chat kind, the global CHAT_<name>_GET
    --     ("|Hchannel:GUILD|h[Guild]|h %s: "). A global string write; the
    --     chat frame's own code reads it when it shows a line.
    --   client.editBox() -> { alt =, history = } | nil
    --   client.setEditBox(alt, history) -> true | nil
    --     ChatFrame1EditBox: Get/SetAltArrowKeyMode and Get/SetHistoryLines
    --     (warcraft.wiki.gg, Widget API EditBox). The game's own edit-box
    --     history is used: nothing is hooked.
    ---------------------------------------------------------------------
    do
        function c.classOfGuid(guid)
            if type(guid) ~= "string" or guid == "" then return nil end
            local ok, _, class = call(env.GetPlayerInfoByGUID, guid)
            if not ok or hidden(class) or type(class) ~= "string" or class == "" then return nil end
            return class
        end

        local function typeInfo(chatType)
            if type(chatType) ~= "string" or chatType == "" then return nil end
            local okT, all = pcall(function() return env.ChatTypeInfo end)
            if not okT or type(all) ~= "table" then return nil end
            local okI, info = pcall(function() return all[chatType] end)
            if not okI or type(info) ~= "table" then return nil end
            return info
        end
        function c.chatNameByClass(chatType)
            local info = typeInfo(chatType)
            if info == nil then return nil end
            local okV, v = pcall(function() return info.colorNameByClass end)
            if not okV or hidden(v) then return nil end
            return v == true
        end
        function c.setChatNameByClass(chatType, on)
            if typeInfo(chatType) == nil or type(on) ~= "boolean" then return nil end
            if not call(env.SetChatColorNameByClass, chatType, on) then return nil end
            return true
        end

        function c.chatTypeHeader(name)
            if type(name) ~= "string" or name == "" then return nil end
            local okH, text = pcall(function() return env["CHAT_" .. name .. "_GET"] end)
            if not okH or hidden(text) or type(text) ~= "string" then return nil end
            return text
        end
        function c.setChatTypeHeader(name, text)
            if c.chatTypeHeader(name) == nil or type(text) ~= "string" then return nil end
            local okS = pcall(function() env["CHAT_" .. name .. "_GET"] = text end)
            if not okS then return nil end
            return true
        end

        function c.editBox()
            local box = env.ChatFrame1EditBox
            if type(box) ~= "table" then return nil end
            local okA, alt = method(box, "GetAltArrowKeyMode")
            if not okA or hidden(alt) or type(alt) ~= "boolean" then return nil end
            local out = { alt = alt }
            local okH, n = method(box, "GetHistoryLines")
            if okH and not hidden(n) and type(n) == "number" then out.history = n end
            return out
        end
        function c.setEditBox(alt, history)
            local box = env.ChatFrame1EditBox
            if type(box) ~= "table" or type(alt) ~= "boolean" then return nil end
            if not method(box, "SetAltArrowKeyMode", alt) then return nil end
            if type(history) == "number" then method(box, "SetHistoryLines", history) end
            return true
        end
    end

    -- G48 (P-TRIP): the party route's add-on messages (Nav/PartyRoute.lua),
    -- the add-on's only outward call. First guesses, not tested in game:
    -- C_ChatInfo.RegisterAddonMessagePrefix(prefix) and
    -- C_ChatInfo.SendAddonMessage(prefix, text, channel) answer true (older
    -- builds) or 0 (Enum.SendAddonMessageResult.Success, newer builds) on
    -- success; any other answer, nothing, or a raise is "not sent".
    -- Messages come in through c.listen("CHAT_MSG_ADDON",
    -- fn(prefix, text, channel, sender)).
    --   c.addonPrefix(prefix) -> true | false | nil (no such call)
    --   c.addonSend(prefix, text, channel) -> true | nil, why
    -- Only the "PARTY" channel is ever sent on; any other is refused here.
    function c.addonPrefix(prefix)
        if type(prefix) ~= "string" or prefix == "" or #prefix > 16 then return false end
        local chat = env.C_ChatInfo
        if type(chat) ~= "table" or type(chat.RegisterAddonMessagePrefix) ~= "function" then return nil end
        local ok, r = call(chat.RegisterAddonMessagePrefix, prefix)
        if not ok then return nil end
        return r == true or r == 0
    end

    function c.addonSend(prefix, text, channel)
        if channel ~= "PARTY" then return nil, "only the party channel" end
        if type(prefix) ~= "string" or type(text) ~= "string" then return nil, "nothing to send" end
        if #text > 255 then return nil, "message too long" end
        local chat = env.C_ChatInfo
        if type(chat) ~= "table" or type(chat.SendAddonMessage) ~= "function" then
            return nil, "the client has no C_ChatInfo.SendAddonMessage"
        end
        local ok, r = call(chat.SendAddonMessage, prefix, text, channel)
        if not ok then return nil, "the send raised: " .. tostring(r) end
        if r == true or r == 0 then return true end
        return nil, "the client answered " .. tostring(r)
    end
    -- P-EVIDENCE+ (lead section 252): the minimap tracking list as the
    -- client returns it, for Core/AutoEvidence.lua to save so the gather
    -- key's rules (GK-2/3/4) can be replayed on real data. Look only:
    -- nothing is switched. First guess, not seen in game:
    -- C_Minimap.GetNumTrackingTypes() and C_Minimap.GetTrackingInfo(i),
    -- either a table { name, active, type, spellID } or the values
    -- name, texture, active, category, nested, spellID.
    --   { count = n or nil (not a plain count), entries = { {
    --       form = "table" | "values", kind = the type or category word,
    --       name = the tracking's game name, hasActive = whether an active
    --       answer was given, active = true / false when given and not
    --       secret, hidden = true when it was secret, spellId = n } },
    --     failed = how many entries raised }
    -- nil when the client has no such read. At most 60 entries.
    function c.trackingRaw()
        local M = env.C_Minimap
        if type(M) ~= "table" or type(M.GetNumTrackingTypes) ~= "function"
            or type(M.GetTrackingInfo) ~= "function" then
            return nil
        end
        local out = { entries = {}, failed = 0 }
        local okN, n = call(M.GetNumTrackingTypes)
        if not okN then
            out.failed = 1
            return out
        end
        if hidden(n) or not wholeCount(n) then return out end
        out.count = n
        local function word(v)
            if type(v) ~= "string" or hidden(v) then return nil end
            return v
        end
        for i = 1, math.min(n, 60) do
            local ok, a, _, active, category, _, spellId = call(M.GetTrackingInfo, i)
            if not ok then
                out.failed = out.failed + 1
            else
                local e = { form = "values" }
                local name, on, kind, id = a, active, category, spellId
                if type(a) == "table" then
                    e.form = "table"
                    name, on, kind, id = a.name, a.active, a.type, a.spellID
                end
                e.name, e.kind = word(name), word(kind)
                e.hasActive = on ~= nil
                if on ~= nil then
                    if hidden(on) then
                        e.hidden = true
                    elseif on == true or on == 1 then
                        e.active = true
                    elseif on == false or on == 0 then
                        e.active = false
                    end
                end
                if type(id) == "number" and not hidden(id) then e.spellId = id end
                out.entries[#out.entries + 1] = e
            end
        end
        return out
    end

    -- P-EVIDENCE+ (lead section 262, RB4-2): the classic profession
    -- window's raw answers behind tradeSkillRows' collapsed and filtered,
    -- for Core/AutoEvidence.lua to save when the window opens or changes.
    -- Look only: no header is expanded, no filter set. First guesses, not
    -- seen in game: GetTradeSkillLine, GetNumTradeSkills,
    -- GetTradeSkillInfo(i) (its fourth answer, isExpanded, on header and
    -- subheader rows), GetTradeSkillSubClassFilter(0) and
    -- GetTradeSkillInvSlotFilter(0).
    --   { open = the line has a name, rows = n or nil, headers = n,
    --     expanded = n (true or 1), collapsed = n (false or 0), unknown = n
    --     (anything else, nil included), subClass = word, invSlot = word }
    -- where a filter word is "true", "1", "false", "0", "nil", "secret",
    -- "failed", "absent" or "other". nil when GetTradeSkillLine is not there.
    function c.tradeSkillAnswers()
        if type(env.GetTradeSkillLine) ~= "function" then return nil end
        local function answer(fn)
            if type(fn) ~= "function" then return "absent" end
            local ok, v = call(fn, 0)
            if not ok then return "failed" end
            if v == nil then return "nil" end
            if hidden(v) then return "secret" end
            if v == true then return "true" end
            if v == false then return "false" end
            if v == 1 then return "1" end
            if v == 0 then return "0" end
            return "other"
        end
        local out = { open = false, headers = 0, expanded = 0, collapsed = 0, unknown = 0,
                      subClass = answer(env.GetTradeSkillSubClassFilter),
                      invSlot = answer(env.GetTradeSkillInvSlotFilter) }
        local okLine, name = call(env.GetTradeSkillLine)
        out.open = okLine and type(name) == "string" and not hidden(name) and name ~= "" and name ~= "UNKNOWN"
        local okN, n = call(env.GetNumTradeSkills)
        if not okN or hidden(n) or not wholeCount(n) or n == math.huge then return out end
        out.rows = n
        for i = 1, math.min(n, 500) do
            local okInfo, _, kind, _, expanded = call(env.GetTradeSkillInfo, i)
            if okInfo and not hidden(kind) and (kind == "header" or kind == "subheader") then
                out.headers = out.headers + 1
                if expanded ~= nil and hidden(expanded) then
                    out.unknown = out.unknown + 1
                elseif expanded == true or expanded == 1 then
                    out.expanded = out.expanded + 1
                elseif expanded == false or expanded == 0 then
                    out.collapsed = out.collapsed + 1
                else
                    out.unknown = out.unknown + 1
                end
            end
        end
        return out
    end
    -- Lead section 382 (Nav/ProfFeed.lua): the name of the continent a map
    -- lies on, for "Next time you are in <continent>". C_Map.GetMapInfo up
    -- the parents to the first of Enum.UIMapType.Continent (2 when the enum
    -- is not there). nil when the client will not say; never guessed. A
    -- first guess, not seen in game.
    function c.mapContName(map)
        if type(map) ~= "number" then return nil end
        local kinds = type(env.Enum) == "table" and env.Enum.UIMapType
        local contType = type(kinds) == "table" and tonumber(kinds.Continent) or 2
        for _ = 1, 8 do
            local ok, info = mapCall("GetMapInfo", map)
            if not ok or type(info) ~= "table" then return nil end
            if tonumber(info.mapType) == contType then
                if type(info.name) ~= "string" or hidden(info.name) or info.name == "" then return nil end
                return info.name
            end
            if type(info.parentMapID) ~= "number" or info.parentMapID == 0 then return nil end
            map = info.parentMapID
        end
        return nil
    end

    -- P-QUEST (lead section 354 item 4): whether quest id can be shared
    -- with your group: true, false, or nil when not known.
    -- C_QuestLog.IsPushableQuest(id), a first guess: not seen in game on
    -- 16001. Only reads: no quest is selected in the log and none is shared.
    function c.questShareable(id)
        if type(id) ~= "number" then return nil end
        local log = env.C_QuestLog
        if type(log) ~= "table" then return nil end
        return yesNo(call(log.IsPushableQuest, id))
    end

    -- Lead section 303 (d), the in-dungeon tracker: the name of the instance
    -- you are in, the first answer of GetInstanceInfo(), or nil when not
    -- known (no call, a failed call, a secret or empty answer). Only reads.
    -- A first guess: not seen in game on 16001.
    function c.instanceName()
        local ok, name = call(env.GetInstanceInfo)
        if not ok or hidden(name) or type(name) ~= "string" or name == "" then return nil end
        return name
    end

    -- S32: the words the client shows for where the player stands:
    -- { zone = GetRealZoneText(), sub = GetSubZoneText() }, each a name or
    -- nil; nil when neither is known. Read to name the dock a boat or
    -- zeppelin was taken from and the place it landed. Only reads.
    function c.placeText()
        local zone = text(call(env.GetRealZoneText))
        local sub = text(call(env.GetSubZoneText))
        if zone == nil and sub == nil then return nil end
        return { zone = zone, sub = sub }
    end
    return c
end

ns.client = ns.make.client(_G)
