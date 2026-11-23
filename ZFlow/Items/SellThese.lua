-- Sell these (lead section 337 item 1): the sell list's button (UI/SellList.lua)
-- sells the rows the list shows, by bag and slot, on the player's own click
-- only, with the merchant open and out of combat. One stack per frame; a
-- merchant closing, combat or a refused sale stops the run. Each slot is
-- read again just before it is sold, and skipped when it no longer holds
-- the same item and count. Never automatic and never on merchant open: only
-- runner.start sells, and only the button's click calls it.
--
-- A row is sold only when the list sells every one of that item in the
-- bags: a stack can't be split here, so a row the list sells only part of
-- (a goal holds the rest) is left alone, and the button says so when no
-- row is left.
--
--   SellThese.Plan(listing, slots) -> steps, or nil and why
--     listing: SellList.Listing's; slots: client.bagSlots()'s.
--     steps = { { bag, slot, key, count } ... } in bag then slot order.
--     why: SellThese.NOTHING, NOT_KNOWN, NOT_READ or NOT_WHOLE (the
--     button's words when it can't be pressed)
--   SellThese.Tip(why) -> the button's tooltip for that why
--   SellThese.Note(result) -> the player's words after a run:
--     result = { sold = items, skipped = stacks, stopped = why or nil }
--   SellThese.Runner(client, sched, done) -> runner
--     runner.start(steps)  sells steps[1] now, then one each frame;
--                          done(result) once at the end
--     runner.stop(why)     ends the run now (why: "closed", ...)
--     runner.running()     true while a run is on
--
-- Reads and calls (through the injected client):
--   client.merchantOpen(), client.combatLockdown()   before each sale
--   client.bagSlot(bag, slot)                        the slot read again
--   client.sellBagItem(bag, slot) -> true, or nil and why   ACTING: the sale
-- Not tested in game.
local _, ns = ...

local SellThese = ns.SellThese or {}
ns.SellThese = SellThese

SellThese.OWNER = "sellThese"
SellThese.KEY = "sellThese"
SellThese.TEXT = "Sell these"
SellThese.SELLING = "Selling..."
-- The button's words when it can't be pressed: why, said on the button.
SellThese.NOTHING = "Nothing to sell"
SellThese.NOT_KNOWN = "Can't sell yet"
SellThese.NOT_READ = "Bags not read"
SellThese.NOT_WHOLE = "Can't sell whole"
SellThese.TIPS = {
    [SellThese.NOTHING] = "Nothing in your bags is on the sell list.",
    [SellThese.NOT_KNOWN] = "What your goals hold is not known yet, so nothing is offered for sale.",
    [SellThese.NOT_READ] = "Your bags or their items were not read yet. Reopen the merchant window.",
    [SellThese.NOT_WHOLE] = "A goal holds part of each item listed, and a stack can't be split here. Sell those by hand.",
    [SellThese.SELLING] = "Selling the listed items, one stack at a time.",
}
SellThese.TIP = "Sells the items listed above, one stack at a time. You can buy them back on the merchant's Buyback tab."
SellThese.BUYBACK = "Changed your mind? Buy them back on the merchant's Buyback tab."
-- Why a run stopped, in the player's words.
SellThese.WHY = {
    combat = "you are in combat",
    closed = "the merchant window closed",
    noCall = "this game client can't sell items",
    raised = "the game refused the sale",
    bad = "a bag slot could not be read",
}

local function whole(n)
    return type(n) == "number" and n == n and n >= 0 and n < math.huge and n == math.floor(n)
end

local function bySlot(a, b)
    if a.bag ~= b.bag then return a.bag < b.bag end
    return a.slot < b.slot
end

function SellThese.Plan(listing, slots)
    if type(listing) ~= "table" then return nil, SellThese.NOT_READ end
    if listing.unavailable then return nil, SellThese.NOT_KNOWN end
    local list = listing.list
    if type(list) ~= "table" or not list.ok or type(list.rows) ~= "table" then return nil, SellThese.NOT_READ end
    if #list.rows == 0 then
        if (tonumber(listing.notRead) or 0) + (tonumber(list.unread) or 0) > 0 then
            return nil, SellThese.NOT_READ
        end
        return nil, SellThese.NOTHING
    end
    if type(slots) ~= "table" then return nil, SellThese.NOT_READ end
    local byKey, total = {}, {}
    for _, s in ipairs(slots) do
        local key
        if type(s) == "table" then key = ns.Items.Key(s.item) end
        if key ~= nil and whole(s.count) and whole(s.bag) and whole(s.slot) then
            local held = byKey[key] or {}
            byKey[key] = held
            held[#held + 1] = { bag = s.bag, slot = s.slot, key = key, count = s.count }
            total[key] = (total[key] or 0) + s.count
        end
    end
    local steps = {}
    for _, row in ipairs(list.rows) do
        if whole(row.count) and row.count > 0 and total[row.key] == row.count then
            for _, step in ipairs(byKey[row.key]) do steps[#steps + 1] = step end
        end
    end
    if #steps == 0 then return nil, SellThese.NOT_WHOLE end
    table.sort(steps, bySlot)
    return steps
end

function SellThese.Tip(why)
    return SellThese.TIPS[why] or SellThese.TIP
end

local function plural(n, one, many)
    if n == 1 then return n .. " " .. one end
    return n .. " " .. many
end

function SellThese.Note(result)
    if type(result) ~= "table" then result = {} end
    local sold = tonumber(result.sold) or 0
    local skipped = tonumber(result.skipped) or 0
    local text = "Nothing sold"
    if sold > 0 then text = "Sold " .. plural(sold, "item", "items") end
    if result.stopped ~= nil then
        local why = SellThese.WHY[result.stopped] or tostring(result.stopped)
        if sold > 0 then text = text .. ", then stopped: " .. why else text = text .. ": " .. why end
    end
    if skipped > 0 then
        local its = "their bag slots"
        if skipped == 1 then its = "its bag slot" end
        text = text .. "; " .. plural(skipped, "stack", "stacks") .. " skipped, as " .. its .. " changed"
    end
    text = text .. "."
    if sold > 0 then text = text .. " " .. SellThese.BUYBACK end
    return text
end

function SellThese.Runner(client, sched, done)
    local runner = {}
    local run = nil     -- { steps, at, sold, skipped }

    local function finish(stopped)
        if run == nil then return end
        local result = { sold = run.sold, skipped = run.skipped, stopped = stopped }
        run = nil
        sched:off(SellThese.OWNER)
        if type(done) == "function" then done(result) end
    end

    -- One sale, after passing over the slots that changed; the next one a
    -- frame later. The merchant and the combat lock are read before each.
    local function step()
        if run == nil then return end
        if client.merchantOpen() ~= true then return finish("closed") end
        if client.combatLockdown() ~= false then return finish("combat") end
        if type(client.sellBagItem) ~= "function" then return finish("noCall") end
        while run.at <= #run.steps do
            local s = run.steps[run.at]
            run.at = run.at + 1
            local item, count = client.bagSlot(s.bag, s.slot)
            local same = false
            if item then same = ns.Items.Key(item) == s.key and count == s.count end
            if same then
                local ok, why = client.sellBagItem(s.bag, s.slot)
                if not ok then return finish(why or "raised") end
                run.sold = run.sold + s.count
                if run.at > #run.steps then return finish(nil) end
                sched:nextFrame(SellThese.OWNER, step)
                return
            end
            run.skipped = run.skipped + 1
        end
        finish(nil)
    end

    function runner.running() return run ~= nil end
    function runner.start(steps)
        if run ~= nil or type(steps) ~= "table" or #steps == 0 then return false end
        run = { steps = steps, at = 1, sold = 0, skipped = 0 }
        step()
        return true
    end
    function runner.stop(why) finish(why) end
    return runner
end
