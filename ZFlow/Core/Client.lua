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

    -- Section 231 item 1: the fallback for recipeSchematic when the client
    -- has no C_TradeSkillUI.GetRecipeSchematic (not in CLIENT-NAMES-16001).
    -- The classic reads of the open trade skill window, by row index, not
    -- recipe id: GetTradeSkillItemLink(index) for the product,
    -- GetTradeSkillNumMade(index) for the yield (its least; none given: one),
    -- GetTradeSkillNumReagents(index), then for each reagent
    -- GetTradeSkillReagentItemLink(index, r) for the item and the third answer
    -- of GetTradeSkillReagentInfo(index, r) for how many a craft takes.
    -- The same answer as recipeSchematic: { makes =, yield =, mats = }.
    -- Anything that can't be read makes the whole answer nil: never a
    -- shorter list. First guesses, not seen in game. Items/RecipeBook.lua
    -- calls it for each row of tradeSkillRows (section 233, GR2-1).
    function c.tradeSkillSchematic(index)
        if not wholeCount(index) or index < 1 or index == math.huge then return nil end
        local function itemOf(ok, link)
            if not ok or type(link) ~= "string" or hidden(link) then return nil end
            local id = tonumber(link:match("item:(%d+)"))
            if not id or id <= 0 then return nil end
            return id
        end
        local function count(n, least)
            return wholeCount(n) and n < math.huge and n >= least
        end
        local makes = itemOf(call(env.GetTradeSkillItemLink, index))
        if not makes then return nil end
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
            local okInfo, _, _, need = call(env.GetTradeSkillReagentInfo, index, r)
            if not item or not okInfo or not count(need, 1) then return nil end
            mats[item] = (mats[item] or 0) + need
        end
        return { makes = makes, yield = yield, mats = mats }
    end

    -- Section 233 (GR2-1): the rows of the classic trade skill window, for
    -- when C_TradeSkillUI can't be read. GetTradeSkillLine() for the
    -- profession's name, skill and max ("UNKNOWN" or no name: no window),
    -- GetNumTradeSkills() rows (0: no window), and GetTradeSkillInfo(i) for
    -- each row's name and kind; "header" and "subheader" rows are left out.
    -- Every other row is a recipe the player has learned. Only what the
    -- window shows: a collapsed header hides its rows.
    --   { name =, skill =, max =, rows = { { index = i, name = } } }
    -- Anything that can't be read makes the whole answer nil: never a
    -- shorter list. First guesses, not seen in game.
    function c.tradeSkillRows()
        local okLine, name, skill, max = call(env.GetTradeSkillLine)
        if not okLine or type(name) ~= "string" or hidden(name) or name == "" or name == "UNKNOWN" then
            return nil
        end
        local okN, n = call(env.GetNumTradeSkills)
        if not okN or not wholeCount(n) or n < 1 or n == math.huge then return nil end
        local rows = {}
        for i = 1, n do
            local okInfo, rowName, kind = call(env.GetTradeSkillInfo, i)
            if not okInfo or type(kind) ~= "string" or hidden(kind) then return nil end
            if kind ~= "header" and kind ~= "subheader" then
                if type(rowName) ~= "string" or hidden(rowName) or rowName == "" then return nil end
                rows[#rows + 1] = { index = i, name = rowName }
            end
        end
        local out = { name = name, rows = rows }
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
    --   client.onLootRoll(fn) -> cancel;  fn(rollID, link, show);  show(text, r, g, b)
    -- show puts one short text above that roll's frame, on a frame of ours
    -- made as a child of it, so it hides with it; one per roll frame, reused.
    -- Nothing of the game's frame is called or written, and nothing rolls.
    -- When the roll frame cannot be found, show prints the link and the text
    -- once instead. No link, or a secret one: fn is not told.
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
        local function show(s, r, g, b)
            if type(s) ~= "string" or s == "" then return end
            local frame = rollFrame(rollID)
            local m = frame and rollMark(frame) or nil
            if not m then
                if not printed then
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

    -- GT-1. Is any minimap tracking on (Flow's X.AnyTracked)? true / false;
    -- nil when it cant be told. First guess; not seen in game.
    function c.anyTracking()
        local M = env.C_Minimap
        if type(M) == "table" then
            local okN, n = call(M.GetNumTrackingTypes)
            if okN and type(n) == "number" and not hidden(n) then
                for i = 1, n do
                    local ok, a, _, active = call(M.GetTrackingInfo, i)
                    if ok then
                        local on = active
                        if type(a) == "table" then on = a.active end
                        if on == true and not hidden(on) then return true end
                    end
                end
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
    --   { name =, quality =, sellPrice =, classID =, subclassID = }
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
        local ok, name, _, quality, _, _, _, _, _, _, _, price, class, subclass = call(fn, item)
        local out = {}
        out.name = text(ok, name)
        out.quality = whole(ok, quality)
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
            local b = { checks = {}, buttons = {}, labels = {}, edits = {}, n = {} }
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

        function h.draw(rows, act)
            local b = build()
            if not b then return false end
            for _, kind in ipairs({ "checks", "buttons", "labels", "edits" }) do
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
                    elseif r.kind == "number" then
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
    return c
end

ns.client = ns.make.client(_G)
