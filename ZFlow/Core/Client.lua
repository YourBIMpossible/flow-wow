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
            local ok, name, rank, category = call(env.GetTrainerServiceInfo, i)
            if not ok or (category ~= nil and hidden(category)) then return nil, trainerFilter() end
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
    -- LEARNED_SPELL_IN_TAB (spellID, ...); the name is the first answer of
    -- GetSpellInfo(spellID), the rank GetSpellSubtext(spellID) where the
    -- client has it, else GetSpellInfo's second answer when that is text.
    -- A spell with no readable name tells nobody; a rank not read is left
    -- out. First guesses, not seen in game on 16001. fn's errors stay here.
    local learnedListeners, learnedWatched = {}, false
    local function spellLearned(id)
        if type(id) ~= "number" or hidden(id) then return end
        local ok, name, oldRank = call(env.GetSpellInfo, id)
        name = text(ok, name)
        if not name then return end
        local rank = text(call(env.GetSpellSubtext, id)) or text(ok, oldRank)
        for _, fn in ipairs({ unpack(learnedListeners) }) do
            pcall(fn, { id = id, name = name, rank = rank })
        end
    end
    function c.onSpellLearned(fn)
        if type(fn) ~= "function" then return nil end
        if not learnedWatched then
            learnedWatched = true
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
    local function speedOf(s)
        local word = env.SPEED
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
    local function hookTooltip()
        if tooltipHooked then return true end
        local tip = env.GameTooltip
        if type(tip) == "table" and type(tip.HookScript) == "function" then
            local okHas, has = call(tip.HasScript, tip, "OnTooltipSetItem")
            if okHas and has == true and call(tip.HookScript, tip, "OnTooltipSetItem", tooltipFilled) then
                tooltipHooked = true
                return true
            end
        end
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
    --
    --   client.onLootRoll(fn) -> cancel;  fn(rollID, link, show);  show(text, r, g, b)
    -- show puts one short text above that roll's frame, on a frame of ours
    -- made as a child of it, so it hides with it; one per roll frame, reused.
    -- Nothing of the game's frame is called or written, and nothing rolls.
    -- When the roll frame cannot be found, show prints the link and the text
    -- once instead. No link, or a secret one: fn is not told.
    local rollListeners, rollWatched = {}, false
    local rollMarks = {}      -- roll frame -> { holder, text, rollID }
    local function rollFrame(rollID)
        for i = 1, 4 do
            local f = env["GroupLootFrame" .. i]
            if type(f) == "table" then
                local ok, id = pcall(function() return f.rollID end)
                if ok and id ~= nil and not hidden(id) and id == rollID then return f end
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
    function c.panel(spec)
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
    local function questFlag(fn, id)
        local ok, v = call(fn, id)
        if not ok or hidden(v) then return nil end
        if v == true then return true end
        if v == false then return false end
        return nil
    end
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

    -- A module of the installed Questie by name, or nil: Questie is not
    -- there, or its loader gave none. Asked of Questie at runtime through
    -- its own loader (QuestieLoader:ImportModule); nothing of Questie is
    -- copied into this addon or changed. A first guess: not seen in game.
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
            local kind, id = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-%x+$")
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

    -- One movable icon, or nil when the client cannot make a frame. First
    -- guess, not seen in game (WOW-ROTATION-ICON).
    --   spec = { name = global frame name or nil, size = n }
    --   h.setTexture(tex) -> true when the client took it. tex is what
    --                   spellTexture gave (a file id or a path); nil clears
    --                   the picture and answers false.
    --   h.place(point), h.show(on), h.onMoved(fn, failed): as the panel's.
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
    -- c.windowButton(frameName, spec) -> h, or nil. A plain button on one
    -- of the game's own windows. spec = { name, text, tip, point = { anchor,
    -- relAnchor, x, y } }. nil, and nothing is made, when the window is not
    -- there, when the client does not say plainly that the window is not
    -- protected, or when the client does not say plainly that the player
    -- is out of combat. The button is an ordinary Button: no secure
    -- template, no attribute, no action. It only tells its caller.
    --   h.onClick(fn, failed)  fn() on a left click; failed(err) is told the
    --                          error of an fn that failed.
    --   h.show(on)
    -- First guesses, none seen in game: IsProtected on the window frame,
    -- the UIPanelButtonTemplate look, GameTooltip for the tip.
    function c.windowButton(frameName, spec)
        if type(frameName) ~= "string" or frameName == "" or type(spec) ~= "table" then return nil end
        local frame = env[frameName]
        if type(frame) ~= "table" then return nil end
        local okP, protected = method(frame, "IsProtected")
        if not okP or hidden(protected) or protected ~= false then return nil end
        if c.inCombat() ~= false then return nil end

        local name = spec.name
        if type(name) ~= "string" or name == "" or env[name] ~= nil then name = nil end
        local ok, b = call(env.CreateFrame, "Button", name, frame, "UIPanelButtonTemplate")
        if not ok or b == nil then
            ok, b = call(env.CreateFrame, "Button", name, frame)
            if ok and b ~= nil then method(b, "SetNormalFontObject", "GameFontNormalSmall") end
        end
        if not ok or b == nil then return nil end

        local label = type(spec.text) == "string" and spec.text or ""
        method(b, "Hide")
        method(b, "SetText", label)
        local width = 24 + 7 * #label
        if not method(b, "SetSize", width, 22) then
            method(b, "SetWidth", width)
            method(b, "SetHeight", 22)
        end
        local p = type(spec.point) == "table" and spec.point or {}
        method(b, "SetPoint", type(p[1]) == "string" and p[1] or "TOPRIGHT", frame,
            type(p[2]) == "string" and p[2] or "TOPRIGHT", tonumber(p[3]) or 0, tonumber(p[4]) or 0)
        method(b, "RegisterForClicks", "LeftButtonUp")

        local h, clicked, clickFailed = {}, nil, nil
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
        return h
    end

    ---------------------------------------------------------------------
    -- F6, the rotation helper: its reads and its one secure frame, kept
    -- together. All first guesses: not seen in game on 16001.
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
        local okN, n = call(env.GetItemCount, HEARTHSTONE)
        if not okN or n == nil or hidden(n) or type(n) ~= "number" or n < 1 then return nil end
        local ok, start, duration = call(env.GetItemCooldown, HEARTHSTONE)
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

    -- Calls fn with the values of each combat-log event, in the client's
    -- own order: COMBAT_LOG_EVENT_UNFILTERED, read with
    -- CombatLogGetCurrentEventInfo(). Answers true when the feed was taken;
    -- nil when the client has no such read or did not take the event (fn
    -- is then never called). A read that fails does not call fn that
    -- time. A secret value is handed over as nil, never as it is. It only
    -- reads: the log is not filtered, cleared or written to.
    local logBuf = {}
    function c.watchCombatLog(fn)
        if type(fn) ~= "function" or type(env.CombatLogGetCurrentEventInfo) ~= "function" then return nil end
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
            pass(pcall(env.CombatLogGetCurrentEventInfo))
        end)
        if unregistered["COMBAT_LOG_EVENT_UNFILTERED"] then
            cancel()
            return nil
        end
        return true
    end

    return c
end

ns.client = ns.make.client(_G)
