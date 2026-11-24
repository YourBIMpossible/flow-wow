local _, ns = ...
-- Sell these waits for the bag (lead section 450, ITEMS lane): a sale is
-- counted only once the slot sold has emptied or changed, and the next
-- stack is not sent before that. A stack that has not left the bags within
-- SellThese.WAIT seconds is given up on: not counted, said in the note, and
-- the run goes on. The predecessor's Modules/Items/Vendor.lua waited the
-- same way (sent, waiting, gave up, skipped, sold).
-- The runner alone, on a hand-made client and scheduler: the sale call here
-- only records, and the test empties the slot when "the game" is done.
-- Made-up items and slots. Not tested in game.
--
-- Fails before the change: the runner counted a sale as soon as the sale
-- call returned and sent the next stack one frame later.
local tests = {}
local SellThese = ns.SellThese

local FANG, SCRAP = 97, 2934

-- -> client, sched, world. world.bags[bag .. ":" .. slot] = { item, count };
-- world.sent = the slots the sale call was made for, in order.
local function world()
    local w = { bags = {}, sent = {}, open = true, combat = false, t = 100 }
    local client = {}
    function client.merchantOpen() return w.open end
    function client.combatLockdown() return w.combat end
    function client.now() return w.t end
    function client.bagSlot(bag, slot)
        local row = w.bags[bag .. ":" .. slot]
        if row == nil then return nil end
        return row.item, row.count
    end
    function client.sellBagItem(bag, slot)
        w.sent[#w.sent + 1] = bag .. ":" .. slot
        return true
    end
    local sched = {}
    function sched:nextFrame(_, fn) w.job = fn end
    function sched:off() w.job = nil end
    -- One frame, dt seconds later.
    function w.frame(dt)
        w.t = w.t + (dt or 0.02)
        local fn = w.job
        w.job = nil
        if fn then fn() end
    end
    return client, sched, w
end

local function steps(w)
    w.bags["0:1"] = { item = FANG, count = 3 }
    w.bags["0:4"] = { item = SCRAP, count = 2 }
    return {
        { bag = 0, slot = 1, key = ns.Items.Key(FANG), count = 3 },
        { bag = 0, slot = 4, key = ns.Items.Key(SCRAP), count = 2 },
    }
end

tests["sell these wait: the next stack is not sent, and nothing is counted, until the slot sold has emptied"] = function(t)
    local client, sched, w = world()
    local result
    local runner = SellThese.Runner(client, sched, function(r) result = r end)
    t.eq(runner.start(steps(w)), true)
    t.eq(w.sent, { "0:1" }, "the first stack at the click")
    for _ = 1, 5 do w.frame() end
    t.eq(w.sent, { "0:1" }, "the second one waits for the first to leave the bags")
    t.eq(runner.running(), true, "the run is still on")
    t.eq(result, nil, "nothing is said yet")
    w.bags["0:1"] = nil
    w.frame()
    t.eq(w.sent, { "0:1", "0:4" }, "the first has left: the second is sent")
    w.frame()
    t.eq(runner.running(), true, "the last one is waited for too")
    w.bags["0:4"] = nil
    w.frame()
    t.eq(runner.running(), false)
    t.eq(result and { result.sold, result.skipped, result.gaveUp, result.stopped }, { 5, 0, 0, nil })
end

tests["sell these wait: a stack that does not leave in time is given up on, not counted, and the run goes on"] = function(t)
    local client, sched, w = world()
    local result
    local runner = SellThese.Runner(client, sched, function(r) result = r end)
    runner.start(steps(w))
    w.frame(SellThese.WAIT - 0.5)
    t.eq(w.sent, { "0:1" }, "still waiting inside the time allowed")
    w.frame(1)
    t.eq(w.sent, { "0:1", "0:4" }, "past the time allowed: on to the next stack")
    w.bags["0:4"] = nil
    w.frame()
    t.eq(result and { result.sold, result.skipped, result.gaveUp, result.stopped }, { 2, 0, 1, nil },
        "only the stack that left is counted")
end

tests["sell these wait: a slot that changed while waiting counts as sold"] = function(t)
    local client, sched, w = world()
    local result
    local runner = SellThese.Runner(client, sched, function(r) result = r end)
    w.bags["0:1"] = { item = FANG, count = 3 }
    runner.start({ { bag = 0, slot = 1, key = ns.Items.Key(FANG), count = 3 } })
    w.frame()
    t.eq(runner.running(), true)
    -- Something else landed in the slot the fangs left.
    w.bags["0:1"] = { item = SCRAP, count = 1 }
    w.frame()
    t.eq(result and { result.sold, result.gaveUp }, { 3, 0 })
end

tests["sell these wait: the merchant closing while waiting counts the stack only if it has left"] = function(t)
    local client, sched, w = world()
    local result
    local runner = SellThese.Runner(client, sched, function(r) result = r end)
    runner.start(steps(w))
    w.open = false
    w.frame()
    t.eq(result and { result.sold, result.stopped }, { 0, "closed" }, "still in the bags: not counted")
    t.eq(w.sent, { "0:1" })

    local client2, sched2, w2 = world()
    local result2
    local runner2 = SellThese.Runner(client2, sched2, function(r) result2 = r end)
    runner2.start(steps(w2))
    w2.bags["0:1"] = nil
    runner2.stop("closed")
    t.eq(result2 and { result2.sold, result2.stopped }, { 3, "closed" }, "it had left: counted")
end

tests["sell these wait: with no clock, a stack is given up on after a count of frames"] = function(t)
    local client, sched, w = world()
    client.now = nil
    local result
    local runner = SellThese.Runner(client, sched, function(r) result = r end)
    w.bags["0:1"] = { item = FANG, count = 3 }
    runner.start({ { bag = 0, slot = 1, key = ns.Items.Key(FANG), count = 3 } })
    for _ = 1, SellThese.WAIT_FRAMES + 2 do w.frame() end
    t.eq(runner.running(), false, "the run ends")
    t.eq(result and { result.sold, result.gaveUp }, { 0, 1 })
end

tests["sell these wait: the note says how many stacks did not leave the bags"] = function(t)
    t.eq(SellThese.Note({ sold = 2, skipped = 0, gaveUp = 1 }),
        "Sold 2 items; 1 stack did not leave your bags, so it is not counted. " .. SellThese.BUYBACK)
    t.eq(SellThese.Note({ sold = 0, skipped = 0, gaveUp = 2 }),
        "Nothing sold; 2 stacks did not leave your bags, so they are not counted.")
end

return tests
