-- Flow Banker: what to put in the bank, and one button that does it.
--
-- "When I pass through major cities, mention to stop by the bank to deposit
-- things I won't need until later ... a mode to bank suggested items, like
-- Flow Banker. Just make sure it isn't stuff I need right now or soon for
-- crafting." (0.35.200)
--
-- What goes to the bank: things Flow keeps for you but that nothing on your
-- route uses now: profession materials, trade goods you told Flow never to
-- sell. What never goes: quest items, tools, recipes, your
-- hearthstone, food, water, bandages, potions, scrolls and anything to
-- equip; and any material a crafting step on your route asks for (those you
-- need now or soon).
--
--   * At a bank: the Flow Banker window lists them; "Deposit" puts them in,
--     a stack at a time. Nothing moves until you click.
--   * On the route: "Bank: put N stacks away" when a banker is close to the
--     way you're going and there's enough to make it worth the step
--     (B.MIN_STACKS). Its own tick under Route includes.
--   * /flow banker: the list, in chat (also in the diagnostics).
--   * Away from a bank: the window's "In your bank" view lists what Flow saw
--     there last time it was open, and "Auction prices" what Flow last saw at
--     the auction house. A "Flow Banker" tab on your bags opens it (0.35.203).
--
--   * "To sell" (0.35.341): what the Flow Seller takes at the next vendor or
--     auction house, and what's in your bank that Flow would now sell (a
--     material your skill has moved past): "Take out" at a bank brings those
--     to your bags, and the seller does the rest.
--
-- Not built yet: fetching things back as a step before the crafting that
-- needs them (the profession plan already reads what's in your bank).

local _, ns = ...
local B = {}
ns.banker = B

B.MIN_STACKS = 4    -- a bank step on the route is worth it from this many stacks
B.ROWS = 14         -- lines in the window
B.NOTE_GAP = 8      -- between the words at the top and the first line under them
B.STEP = 0.25       -- seconds between two stacks going in

-- The rules that mark something Flow keeps for later (Disposition.lua).
B.LATER_RULES = { professionMaterial = true, neverSell = true }
-- Kinds that stay with you whatever the rule says.
local function stays(kind)
    kind = kind or ""
    return kind:find("^Quest") ~= nil or kind:find("^Consumable") ~= nil or kind:find("^Weapon") ~= nil
        or kind:find("^Armor") ~= nil or kind:find("^Container") ~= nil or kind:find("^Key") ~= nil
        -- (A recipe stays too: Flow only has you buy one when you can nearly
        -- learn it, and a banked one read as "not bought" (0.35.203).)
        or kind:find("^Recipe") ~= nil
end

-- Pure: bank this row of the inventory? row: D.InventoryRows' ({ id, name,
-- action, rule, kind, count, stacks }); needed: { [itemID] = true } for what
-- a step on your route uses. -> true / false, and why.
-- rules: your own choices, { [itemID] = "bank" | "carry" } (Flow sets the
-- default, you can change it: click an item in the window, 0.35.216).
-- waits: { [itemID] = quest title } for quest items whose quest's next step
-- is on another continent (QuestBags.lua, 0.35.344).
function B.Banks(row, needed, rules, waits)
    if type(row) ~= "table" or row.action ~= "keep" then return false, "not something Flow keeps" end
    local mine = rules and row.id and rules[row.id]
    if mine == "carry" then return false, "you chose to carry it" end
    if mine == "bank" then return true, "you chose to bank it" end
    if needed and row.id and needed[row.id] then return false, "a step on your route uses it" end
    -- Quest things (0.35.344). Nothing to do with it on this continent: the
    -- bank holds it as well as your bags. A leftover that waits for a quest
    -- you don't have: the same. What a quest in your log asks for stays with
    -- you, whatever kind of thing it is (Earthroot for Gathering the Cure
    -- was on its way to the bank the day before the hand-in).
    if waits and row.id and waits[row.id] then return true, "its quest (" .. tostring(waits[row.id]) .. ") continues on another continent" end
    if row.rule == "leftover" then return true, "it waits for a quest you don't have yet" end
    if type(row.reason) == "string" and row.reason:find("for your quest", 1, true) then return false, "your quest needs it" end
    if stays(row.kind) then return false, "you carry it" end
    if B.LATER_RULES[row.rule or ""] then return true, "kept for later" end
    local kind = row.kind or ""
    if kind:find("^Trade Goods") then return true, "kept for later" end
    return false, "you carry it"
end

-- Pure: the rows to bank, biggest first.
function B.Pick(rows, needed, rules, waits)
    local out = {}
    for _, r in ipairs(rows or {}) do
        if B.Banks(r, needed, rules, waits) then out[#out + 1] = r end
    end
    table.sort(out, function(a, b)
        if (a.stacks or 0) ~= (b.stacks or 0) then return (a.stacks or 0) > (b.stacks or 0) end
        return tostring(a.name) < tostring(b.name)
    end)
    return out
end
function B.Stacks(rows)
    local n = 0
    for _, r in ipairs(rows or {}) do n = n + (r.stacks or 1) end
    return n
end

-- Pure: item IDs the steps ask for. goals: steps with .reagents, either
-- { [itemID] = count } or a list of { id = itemID }.
function B.NeededBy(goals)
    local out = {}
    for _, g in ipairs(goals or {}) do
        if type(g.reagents) == "table" then
            for k, v in pairs(g.reagents) do
                if type(k) == "number" and type(v) == "number" and k > 100 then out[k] = true
                elseif type(v) == "table" and v.id then out[v.id] = true end
            end
        end
        if g.useItem then out[g.useItem] = true end
        -- (What a step has you take out of the bank isn't put back.)
        for id in pairs(type(g.fetch) == "table" and g.fetch or {}) do out[id] = true end
    end
    return out
end

-- What a step on your route needs now (route, locked and hidden steps alike).
function B.Needed()
    local N = ns.nav
    if not N then return {} end
    local all = {}
    for _, list in ipairs({ N:Goals() or {}, N.blockedGoals or {}, N.hiddenGoals or {} }) do
        for _, g in ipairs(list) do all[#all + 1] = g end
    end
    local out = B.NeededBy(all)
    -- And what a quest Flow can lead you through here uses (0.35.348): the
    -- same list that takes a thing out of the bank keeps it out, so nothing
    -- is taken out and put back.
    for id in pairs(ns.questBags and ns.questBags.Needs() or {}) do out[id] = true end
    return out
end

-- Pure: things Flow would both take out of the bank and put back in (there
-- must be none: "it tries to deposit the same things that it just withdrew").
-- take: the Take out rows; put: the rows to put away. -> { itemID }
function B.Thrash(take, put)
    local out, putting = {}, {}
    for _, r in ipairs(put or {}) do if r.id then putting[r.id] = true end end
    for _, r in ipairs(take or {}) do if r.id and putting[r.id] then out[#out + 1] = r.id end end
    table.sort(out)
    return out
end

-- Your own banking choices (saved for all your characters).
function B.Rules()
    ns.db.banker.rules = ns.db.banker.rules or {}
    return ns.db.banker.rules
end
-- Pure: the next choice for an item on a click. banks: it goes to the bank
-- now; mine: your choice so far (nil: Flow's). Left click flips it; a right
-- click (reset) goes back to Flow's own.
function B.NextRule(banks, mine, reset)
    if reset then return nil end
    if mine then return (mine == "bank") and "carry" or "bank" end
    return banks and "carry" or "bank"
end
-- Pure: every item Flow keeps, for the window: what goes to the bank first,
-- then what stays with you, each by name. -> { { id, name, count, bank,
-- why, mine } }
function B.PutCells(rows, needed, rules, waits)
    local out = {}
    for _, r in ipairs(rows or {}) do
        if type(r) == "table" and r.action == "keep" and r.id then
            local bank, why = B.Banks(r, needed, rules, waits)
            out[#out + 1] = { id = r.id, name = r.name, count = r.count or 1, bank = bank and true or false, why = why,
                              mine = rules and rules[r.id] or nil,
                              -- (Why Flow keeps it at all, and by which rule: the tooltip says.)
                              reason = r.reason, rule = r.rule, sell = r.sell, quality = r.quality }
        end
    end
    table.sort(out, function(a, b)
        if a.bank ~= b.bank then return a.bank end
        return tostring(a.name) < tostring(b.name)
    end)
    return out
end

-- One move, not two (0.35.351). "It tries to deposit the same things that it
-- just withdrew ... make it so that it can't get into these situations."
-- Whatever Flow's reasons say, once it has moved a thing one way it doesn't
-- offer to move it back until you've changed continent (the one thing that
-- really changes what a quest thing is for) or reloaded. Your own choice for
-- a thing is never held back.
--   moved: { [itemID] = { dir = "in" | "out", cont } }   -> may it go `dir` now?
B.moved = {}
function B.Settled(moved, id, dir, cont)
    local m = moved and id and moved[id]
    if not m or m.dir == dir then return true end
    return m.cont ~= cont
end
local function contNow()
    local p = ns.nav and ns.nav.PlayerPos and ns.nav:PlayerPos()
    if p and p.cont ~= nil then B.lastCont = p.cont end
    return B.lastCont or "?"
end
-- Pure: rows without the ones Flow just moved the other way (your own choices stay).
function B.Unmoved(rows, moved, dir, cont, rules)
    local out = {}
    for _, r in ipairs(rows or {}) do
        local mine = r.mine or (rules and r.id and rules[r.id] ~= nil)
        if mine or B.Settled(moved, r.id, dir, cont) then out[#out + 1] = r end
    end
    return out
end

-- The list right now: rows to bank.
function B.List()
    local D = ns.disposition
    if not (D and D.Inventory) then return {} end
    local ok, rows = pcall(D.Inventory, D)
    if not ok then return {} end
    local list = B.Pick(rows, B.Needed(), B.Rules(), ns.questBags and ns.questBags.Waits() or nil)
    return B.Unmoved(list, B.moved, "in", contNow(), B.Rules())
end

-------------------------------------------------------------------------------
-- To sell (0.35.341)
-------------------------------------------------------------------------------
-- "It should also have a To sell, and that's the one the Flow Seller will
-- take care of ... Linen Cloth says sell, your First Aid is past it, but it
-- doesn't take it back out of my bank. The bank needs to show that it's
-- going to withdraw those and at the next vendor sell them."
B.LEAVES = { sell = "vendor", ah = "auction house", de = "disenchant", quest = "your quest", route = "your route" }

-- Pure: what steps on your route have you take out of the bank:
-- { [itemID] = the step's words }. goals: steps with .fetch = { [itemID] = n }.
function B.FetchBy(goals)
    local out = {}
    for _, g in ipairs(goals or {}) do
        for id in pairs(type(g.fetch) == "table" and g.fetch or {}) do
            out[id] = out[id] or tostring(g.text or g.title or "a step on your route")
        end
    end
    return out
end
function B.RouteFetch()
    local N = ns.nav
    if not (N and N.Goals) then return {} end
    return B.FetchBy(N:Goals() or {})
end
-- Pure: is anything in the take-out list needed now (a step, a quest), not just for sale?
function B.TakeUrgent(rows)
    for _, r in ipairs(rows or {}) do
        if r.action == "route" or r.action == "quest" then return true end
    end
    return false
end
-- (Never taken out by Flow: gear and quest items. Whether one is soulbound
-- can't be told while it lies in the bank.)
B.NOT_OUT = { [2] = true, [4] = true, [12] = true }

-- Pure: what's in your bags that leaves at a vendor or the auction house.
-- rows: D.Inventory's. -> { { id, name, count, action, reason } }, as sorted.
-- And, after those, what you keep by your own choice (0.35.345): "I was
-- clicking on the things in To sell and they disappeared, and now I can't get
-- them back." A thing you told Flow to keep, or once bought back, stays in
-- this list, marked "Kept", so the same click that took it out puts it back.
B.KEPT_RULES = { yourChoice = "your choice", neverSell = "you bought it back" }
function B.SellRows(rows)
    local out, kept = {}, {}
    for _, r in ipairs(rows or {}) do
        if type(r) == "table" and r.action ~= "quest" and r.action ~= "route" and B.LEAVES[r.action or ""] then
            out[#out + 1] = { id = r.id, name = r.name, count = r.count or 1, stacks = r.stacks or 1, action = r.action, reason = r.reason,
                              mine = r.rule == "yourChoice" or nil, sell = r.sell, quality = r.quality }
        elseif type(r) == "table" and r.action == "keep" and B.KEPT_RULES[r.rule or ""] then
            kept[#kept + 1] = { id = r.id, name = r.name, count = r.count or 1, stacks = r.stacks or 1, action = "keep", kept = true,
                                reason = B.KEPT_RULES[r.rule], mine = r.rule == "yourChoice" or nil, bought = r.rule == "neverSell" or nil,
                                sell = r.sell, quality = r.quality }
        end
    end
    for _, r in ipairs(kept) do out[#out + 1] = r end
    return out
end

-- Pure: every sell or keep choice you've made, as rows (things you carry or
-- not), by name. mine: { [itemID] = "sell" | "keep" }; never: { [itemID] =
-- true } (bought back).
function B.ChoiceRows(mine, never, name)
    local out, seen = {}, {}
    for id, what in pairs(mine or {}) do
        if type(id) == "number" and (what == "sell" or what == "keep") then
            seen[id] = true
            out[#out + 1] = { id = id, name = (name and name(id)) or ("item " .. id), count = 0, mine = true, listed = true,
                              kept = what == "keep" or nil, action = what == "keep" and "keep" or "sell",
                              reason = what == "keep" and "your choice" or "you chose to sell it" }
        end
    end
    for id in pairs(never or {}) do
        if type(id) == "number" and not seen[id] then
            out[#out + 1] = { id = id, name = (name and name(id)) or ("item " .. id), count = 0, listed = true, kept = true, bought = true,
                              action = "keep", reason = "you bought it back" }
        end
    end
    table.sort(out, function(a, b)
        if (a.kept and 1 or 0) ~= (b.kept and 1 or 0) then return not a.kept end
        if a.name ~= b.name then return a.name < b.name end
        return a.id < b.id
    end)
    return out
end

-- Pure: what's in your bank that Flow would sell now, by name.
--   items: { [itemID] = count }; decide(id) -> { action, reason, item = {
--   classID, name } } or nil (not loaded); rules: your choices ("bank": it
--   stays there).
--   quest(id) -> the title of a quest of yours that can use it here, or nil
--   (0.35.344): what you banked for a quest comes back out when the quest
--   can go on.
--   route(id) -> the words of a step on your route that has you take it out
--   ("Get from your bank: 5 Mild Spices"), or nil (0.35.353): the step's
--   things are in the same list, so Take out does the step.
function B.TakeOutRows(items, decide, rules, quest, route)
    local out = {}
    for id, count in pairs(items or {}) do
        if type(id) == "number" and type(count) == "number" and count > 0 and not (rules and rules[id] == "bank") then
            local v = decide(id)
            local item = type(v) == "table" and v.item or nil
            local title = quest and quest(id) or nil
            local step = route and route(id) or nil
            if step then
                out[#out + 1] = { id = id, name = (item and item.name) or ("item " .. id), count = count, action = "route", reason = step, bank = true }
            elseif title then
                out[#out + 1] = { id = id, name = (item and item.name) or ("item " .. id), count = count, action = "quest", reason = title, bank = true }
            elseif item and (v.action == "sell" or v.action == "ah") and not B.NOT_OUT[item.classID or 0] then
                out[#out + 1] = { id = id, name = item.name or ("item " .. id), count = count, action = v.action, reason = v.reason, bank = true,
                                  mine = v.rule == "yourChoice" or nil }
            end
        end
    end
    table.sort(out, function(a, b)
        if tostring(a.name) ~= tostring(b.name) then return tostring(a.name) < tostring(b.name) end
        return a.id < b.id
    end)
    return out
end

-- Right now (remembered a few seconds: it asks every rule about each thing in the bank).
local takeMemo = { at = -100, rows = {} }
local function takeOutReset() takeMemo.at = -100 end
function B.TakeOut(fresh)
    local now = GetTime()
    if not fresh and now - takeMemo.at < 10 then return takeMemo.rows end
    local D = ns.disposition
    local rows = {}
    if D and D.DecideId then
        local fetch = B.RouteFetch()
        rows = B.TakeOutRows(ns.db.bank and ns.db.bank.items, function(id)
            local ok, v = pcall(D.DecideId, D, id)
            return ok and v or nil
        end, B.Rules(), ns.questBags and ns.questBags.NeededHere or nil, function(id) return fetch[id] end)
        rows = B.Unmoved(rows, B.moved, "out", contNow(), nil)
    end
    takeMemo.at, takeMemo.rows = now, rows
    return rows
end

-- Pure: the "To sell" view's words: the line above, and the lines.
function B.SellLines(bags, bank, atBank)
    local out = {}
    local function line(r, where)
        local count = (r.count or 1) > 0 and ((r.count or 1) .. " x ") or ""
        if r.kept then
            return string.format("|cff999999Kept:|r %s%s  |cff999999(%s)|r", count, tostring(r.name), tostring(r.reason or "your choice"))
        end
        if r.mine then where = where .. "|cffffd100Your choice:|r " end
        return string.format("%s%s%s  |cff999999(%s: %s)|r", where, count, tostring(r.name), B.LEAVES[r.action] or tostring(r.action),
            tostring(r.reason or "no reason given"))
    end
    local nBags, nKept = 0, 0
    for _, r in ipairs(bags or {}) do
        out[#out + 1] = line(r, "")
        if r.kept then nKept = nKept + 1 else nBags = nBags + 1 end
    end
    for _, r in ipairs(bank or {}) do out[#out + 1] = line(r, "|cff66ccffIn your bank:|r ") end
    local nBank = #(bank or {})
    if nBags + nBank == 0 then
        if nKept > 0 then return string.format("Nothing to sell now. %d thing(s) you keep by your own choice are listed: click one to sell it after all.", nKept), out end
        return "Nothing to sell: Flow keeps everything in your bags and your bank.", out
    end
    local note = string.format("%d thing(s) in your bags the Flow Seller takes at the next vendor or auction house.", nBags)
    if nBank > 0 then
        note = note .. string.format(" %d more in your bank to take out (to sell, or for a quest here): %s", nBank,
            atBank and "Take out brings them to your bags." or "at a bank, Take out brings them to your bags.")
    end
    return note, out
end

-- Pure: how many of the bank's slots to take out with `free` bag slots left.
function B.TakeCount(slots, free)
    if free == nil then return slots or 0 end
    return math.max(0, math.min(slots or 0, free))
end

-------------------------------------------------------------------------------
-- Depositing (at an open bank)
-------------------------------------------------------------------------------
local bankOpen = false
local useItem = (C_Container and C_Container.UseContainerItem) or UseContainerItem

function B.AtBank() return bankOpen end

-- Auto-cleanup: after a deposit, the game's Clean Up on the bank, then on
-- your bags. The tick is in the window's header (on).
local function sortBank() return (C_Container and C_Container.SortBankBags) or _G.SortBankBags end
local function sortBags() return (C_Container and C_Container.SortBags) or _G.SortBags end
function B.AutoCleanup() return ns.db.banker.autoCleanup ~= false end
function B.CanCleanup() return sortBank() ~= nil or sortBags() ~= nil end
-- Pure: run it? moved: stacks just deposited.
function B.ShouldCleanup(moved, on, canSort, atBank, inCombat)
    return (moved or 0) > 0 and on ~= false and canSort and atBank and not inCombat
end
function B:Cleanup(moved)
    if not B.ShouldCleanup(moved, B.AutoCleanup(), B.CanCleanup(), B.AtBank(), InCombatLockdown()) then return false end
    local bank, bags = sortBank(), sortBags()
    local ok, err = true, nil
    if bank then ok, err = pcall(bank) end
    -- (The bags a moment later: the game does one tidy-up at a time.)
    if bags then C_Timer.After(1.5, function() if not InCombatLockdown() then pcall(bags) end end) end
    ns:Log("bank", ok and string.format("cleaned up after putting %d stack(s) away", moved) or ("bank cleanup failed: " .. tostring(err)))
    return true
end

-- Puts the listed items into the bank, one stack every B.STEP seconds.
-- Stops when the bank closes or a fight starts.
function B:Deposit()
    if not bankOpen or not useItem or InCombatLockdown() then return 0 end
    local want = {}
    for _, r in ipairs(B.List()) do if r.id then want[r.id] = true end end
    local slots = {}
    local cont = contNow()
    ns.disposition:EachBagItem(function(bag, slot, link)
        local id = tonumber(link:match("item:(%d+)"))
        if id and want[id] then
            slots[#slots + 1] = { bag, slot }
            B.moved[id] = { dir = "in", cont = cont }
        end
    end)
    for i, s in ipairs(slots) do
        C_Timer.After((i - 1) * B.STEP, function()
            if bankOpen and not InCombatLockdown() then pcall(useItem, s[1], s[2]) end
        end)
    end
    if #slots > 0 then
        ns:Print(string.format("Flow Banker: putting %d stack(s) in the bank.", #slots))
        C_Timer.After(#slots * B.STEP + 0.5, function()
            if B.frame and B.frame:IsShown() then B:Fill() end
            B:Cleanup(#slots)
        end)
    end
    return #slots
end

-- Takes what Flow would sell out of the bank, a stack every B.STEP seconds,
-- as far as your bags have room. The Flow Seller sells it at the next vendor.
function B:Withdraw()
    if not bankOpen or not useItem or InCombatLockdown() then return 0 end
    local want = {}
    for _, r in ipairs(B.TakeOut(true)) do want[r.id] = true end
    local SP = ns.skillPlan
    local okS, slots = pcall(SP.BankSlotsWith, want)
    if not okS or type(slots) ~= "table" then return 0 end
    local free = ns.export and ns.export.BagsFree and ns.export.BagsFree() or nil
    local n = B.TakeCount(#slots, free)
    local cont = contNow()
    for i = 1, n do
        local s = slots[i]
        if s[3] then B.moved[s[3]] = { dir = "out", cont = cont } end
        C_Timer.After((i - 1) * B.STEP, function()
            if bankOpen and not InCombatLockdown() then pcall(useItem, s[1], s[2]) end
        end)
    end
    if n > 0 then
        ns:Print(string.format("Flow Banker: taking %d stack(s) out to sell%s.", n,
            n < #slots and string.format(" (%d more when your bags have room)", #slots - n) or ""))
        ns:Log("bank", string.format("took %d of %d stack(s) out to sell", n, #slots))
        C_Timer.After(n * B.STEP + 0.8, function()
            takeMemo.at = -100
            if ns.disposition then ns.disposition:Invalidate() end
            if B.frame and B.frame:IsShown() then B:Fill() end
        end)
    elseif #slots > 0 then
        ns:Print("Flow Banker: your bags are full, so nothing was taken out.")
    end
    return n
end

-------------------------------------------------------------------------------
-- The window
-------------------------------------------------------------------------------
local function build()
    local f = CreateFrame("Frame", "FlowBanker", UIParent)
    f:SetSize(330, 124 + B.ROWS * 15)   -- (0.35.221: 14 more, so two lines of words fit above the grid)
    f:SetFrameStrata("DIALOG")
    f:SetPoint("LEFT", UIParent, "LEFT", 380, 60)
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.bg:SetColorTexture(0.05, 0.05, 0.08, 0.94)
    f.head = ns.theme:TitleBar(f, "Flow Banker", "Interface\\Icons\\INV_Misc_Bag_10")
    -- Auto-cleanup, as in the Flow Seller's header: after a deposit the game's
    -- own tidy-up runs on the bank and your bags (0.35.217).
    f.clean = CreateFrame("CheckButton", nil, f.head, "UICheckButtonTemplate")
    f.clean:SetSize(20, 20)
    f.clean:SetPoint("RIGHT", f.head, "RIGHT", -24, 0)
    f.clean.label = f.head:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.clean.label:SetPoint("RIGHT", f.clean, "LEFT", 0, 0)
    f.clean.label:SetText("Auto-cleanup")
    f.clean:SetChecked(B.AutoCleanup())
    f.clean:SetScript("OnClick", function(self)
        ns.db.banker.autoCleanup = self:GetChecked() and true or false
        ns:Print("clean up the bank and your bags after a deposit " .. (B.AutoCleanup() and "on" or "off"))
    end)
    f.clean:SetScript("OnEnter", function(self)
        ns.Tip(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Auto-cleanup", 1, 1, 1)
        GameTooltip:AddLine(B.CanCleanup() and "After Deposit, Flow tidies your bank and your bags with the game's own Clean Up (the broom)."
            or "This client has no Clean Up for the bank or bags, so there's nothing for Flow to run.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    f.clean:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f:EnableMouse(true)
    -- Ctrl-drag moves it, like Flow's other windows; where you put it is kept.
    local p = ns.db.banker.point
    if p then f:ClearAllPoints(); f:SetPoint(p[1], UIParent, p[2], p[3], p[4]) end
    ns:MakeMovable(f, setmetatable({}, { __newindex = function(_, key, v)
        if key == "point" then ns.db.banker.point = v end end }), true)
    tinsert(UISpecialFrames, "FlowBanker")
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    close:SetScript("OnClick", function() f:Hide() end)   -- (our own: the game's handler can't close an add-on window in a fight)
    f.note = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    -- The three views, as words under the title: the one showing is gold.
    f.tabs = {}
    for i, v in ipairs(B.VIEWS) do
        local tb = CreateFrame("Button", nil, f)
        tb.text = tb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        tb.text:SetPoint("LEFT")
        tb.text:SetText(v.label)
        -- Each as wide as its words, one after the other (four fit since 0.35.341).
        tb:SetSize(math.max(30, (tb.text:GetStringWidth() or 60)), 16)
        if i == 1 then tb:SetPoint("TOPLEFT", 8, -27) else tb:SetPoint("LEFT", f.tabs[B.VIEWS[i - 1].key], "RIGHT", B.TAB_GAP, 0) end
        tb:SetScript("OnClick", function() B:Show(v.key) end)
        f.tabs[v.key] = tb
    end
    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(_, delta) B:Scroll(delta) end)
    f.note:SetPoint("TOPLEFT", 10, -50)
    f.note:SetPoint("TOPRIGHT", -10, -50)
    f.note:SetJustifyH("LEFT")
    f.rows = {}
    for i = 1, B.ROWS do
        local r = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        -- Under the words above, however many lines they take (0.35.238: a
        -- two-line note ran into the first row), with B.NOTE_GAP between.
        local gap = -B.NOTE_GAP - (i - 1) * 15
        r:SetPoint("TOPLEFT", f.note, "BOTTOMLEFT", 0, gap)
        r:SetPoint("TOPRIGHT", f.note, "BOTTOMRIGHT", 0, gap)
        r:SetJustifyH("LEFT")
        r:SetWordWrap(false)
        f.rows[i] = r
        -- A line of "Auction prices" opens that item's chart (Flow Prices, 0.35.301).
        local rb = CreateFrame("Button", nil, f)
        rb:SetPoint("TOPLEFT", r, "TOPLEFT", 0, 1); rb:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", 0, -1)
        rb.hl = rb:CreateTexture(nil, "HIGHLIGHT")
        rb.hl:SetAllPoints(); rb.hl:SetColorTexture(1, 1, 1, 0.08)
        rb:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        rb:SetScript("OnClick", function(self, button) B:RowClick(self, button) end)
        rb:SetScript("OnEnter", function(self)
            if not self.id then return end
            ns.Tip(self, "ANCHOR_RIGHT")
            for n, l in ipairs(B.RowTip(B.view, self.row)) do
                if n == 1 then GameTooltip:AddLine(l, 1, 1, 1, true) else GameTooltip:AddLine(l, 0.7, 0.7, 0.7, true) end
            end
            GameTooltip:Show()
        end)
        rb:SetScript("OnLeave", function() GameTooltip:Hide() end)
        rb:Hide()
        f.rowButtons = f.rowButtons or {}
        f.rowButtons[i] = rb
    end
    -- "Auction prices": a small search, by any part of the name (0.35.221).
    f.search = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    f.search:SetSize(120, 18)
    f.search:SetPoint("BOTTOMRIGHT", -12, 10)
    f.search:SetAutoFocus(false)
    f.search:SetMaxLetters(30)
    f.search.label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.search.label:SetPoint("RIGHT", f.search, "LEFT", -8, 0)
    f.search.label:SetText("Search:")
    f.search:SetScript("OnTextChanged", function(self) B.SetFilter(self:GetText()) end)
    f.search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    f.search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    -- "To bank": the things in your bags, or every choice you've made (also
    -- for things you don't carry now).
    f.all = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.all:SetSize(110, 22)
    f.all:SetPoint("BOTTOMLEFT", 10, 8)
    f.all:SetScript("OnClick", function()
        if B.view == "sell" then B:ResetSell() return end
        B.allRules = not B.allRules
        B.offset = 0
        B:Fill()
    end)
    f.go = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.go:SetSize(120, 22)
    -- On the right, "All my choices" on the left (0.35.269: in the middle it
    -- lay over that button's end).
    f.go:SetPoint("BOTTOMRIGHT", -10, 8)
    f.go:SetText("Deposit")
    f.go:SetScript("OnClick", function() B:GoClick() end)
    f:Hide()
    return f
end

-- The window's views. "put": what to put away (the Deposit button). "bank":
-- what Flow saw in your bank when it was last open, readable anywhere.
-- "prices": what Flow last saw at the auction house.
B.TAB_GAP = 12
B.VIEWS = {
    { key = "put", label = "To bank" },   -- (was "To put away" until 0.35.221)
    { key = "sell", label = "To sell" },
    { key = "bank", label = "In your bank" },
    { key = "prices", label = "Auction prices" },
}
B.view, B.offset = "put", 0

-- Pure: "just now", "25 min ago", "3 h ago", "2 days ago".
function B.Ago(seconds)
    seconds = tonumber(seconds)
    if not seconds or seconds < 0 then return "some time ago" end
    if seconds < 90 then return "just now" end
    if seconds < 5400 then return math.floor(seconds / 60 + 0.5) .. " min ago" end
    if seconds < 129600 then return math.floor(seconds / 3600 + 0.5) .. " h ago" end
    return math.floor(seconds / 86400 + 0.5) .. " days ago"
end

local function nameOf(id)
    local ok, name = pcall(function() return ns.api.ItemInfo and ns.api.ItemInfo(id) end)
    if ok and type(name) == "string" and name ~= "" then return name end
    -- (Not loaded yet: ask the game for it, the next fill has the name.)
    if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
    return nil
end

-- Pure: the bank's rows, by name. items: { [itemID] = count }; name(id) ->
-- its name or nil. -> { { id, name, count } }.
function B.BankRows(items, name)
    local out = {}
    for id, c in pairs(items or {}) do
        if type(id) == "number" and type(c) == "number" and c > 0 then
            out[#out + 1] = { id = id, name = (name and name(id)) or ("item " .. id), count = c }
        end
    end
    table.sort(out, function(a, b)
        if a.name ~= b.name then return a.name < b.name end
        return a.id < b.id
    end)
    return out
end

-- Pure: the auction prices' rows, by name. prices: { [itemID] = { price, at } }.
function B.PriceRows(prices, name)
    local out = {}
    for id, e in pairs(prices or {}) do
        if type(id) == "number" and type(e) == "table" and tonumber(e.price) then
            out[#out + 1] = { id = id, name = (name and name(id)) or ("item " .. id), price = e.price, at = e.at }
        end
    end
    table.sort(out, function(a, b)
        if a.name ~= b.name then return a.name < b.name end
        return a.id < b.id
    end)
    return out
end

-- Pure: the lines for a window of `rows` lines over `n` things, starting
-- after `offset`: first and last index shown, and how many are below.
function B.Window(n, offset, rows)
    local maxOff = math.max(0, n - rows)
    offset = math.max(0, math.min(offset or 0, maxOff))
    local last = math.min(n, offset + rows)
    return offset + 1, last, n - last, offset
end

-- The search box's text changed: the list narrows to it.
function B.SetFilter(text)
    B.filter = text or ""
    B.offset = 0
    B:Fill()
end

-- Pure: the rows whose name holds `text` (any part, any case); no text: all.
function B.Filter(rows, text)
    text = type(text) == "string" and text:lower():gsub("^%s+", ""):gsub("%s+$", "") or ""
    if text == "" then return rows end
    local out = {}
    for _, r in ipairs(rows or {}) do
        if type(r.name) == "string" and r.name:lower():find(text, 1, true) then out[#out + 1] = r end
    end
    return out
end

-- What a view shows now: the line above the list, and its lines of text.
function B.ViewLines(view)
    local now = time()
    B.lineIds, B.lineRows = nil, nil   -- (lines to click: auction prices (Flow Prices) and To sell (keep it))
    if view == "bank" then
        local bank = ns.db.bank or {}
        local rows = B.BankRows(bank.items, nameOf)
        local out = {}
        for _, r in ipairs(rows) do out[#out + 1] = string.format("%d x %s", r.count, r.name) end
        if not bank.seenAt then
            return "Flow hasn't seen inside your bank yet. Open it once and Flow remembers what's there.", out
        end
        return string.format("%d thing(s) in your bank, as Flow saw it %s:", #rows, B.Ago(now - bank.seenAt)), out
    elseif view == "prices" then
        local AH = ns.auction
        local prices = {}
        if AH and AH.Prices then
            local ok, p = pcall(AH.Prices, AH)
            if ok and type(p) == "table" then prices = p end
        end
        local all = B.PriceRows(prices, nameOf)
        local rows = B.Filter(all, B.filter)
        B.lineIds = {}
        for i, r in ipairs(rows) do B.lineIds[i] = r.id end
        local out = {}
        for _, r in ipairs(rows) do
            out[#out + 1] = string.format("%s  |cffffd100%s|r each  |cff999999(%s)|r", r.name, AH.Money(r.price), B.Ago(now - (r.at or 0)))
        end
        if #all == 0 then
            return "No auction prices yet: Flow reads them when you open the auction house.", out
        end
        if #rows < #all then
            return string.format("%d of %d item(s) with \"%s\" in the name (the cheapest buyout Flow last saw):", #rows, #all, tostring(B.filter)), out
        end
        return string.format("The cheapest buyout Flow last saw, for %d item(s). Search below.", #rows), out
    elseif view == "sell" then
        local D = ns.disposition
        local okR, rows = pcall(D.Inventory, D)
        local bank = B.TakeOut()
        B.takeCount = #bank
        local bags = B.SellRows(okR and rows or {})

        -- Each line can be clicked: keep it instead (or undo your own "sell").
        B.lineIds, B.lineRows = {}, {}
        for _, list in ipairs({ bags, bank }) do
            for _, r in ipairs(list) do
                B.lineIds[#B.lineIds + 1] = r.id
                B.lineRows[#B.lineRows + 1] = r
            end
        end
        local note, out = B.SellLines(bags, bank, bankOpen)
        if #out > 0 then note = note .. " Click a line to flip it (sell or keep); right-click: Flow's own choice." end
        return note, out
    end
    local list = B.List()
    local out = {}
    for _, r in ipairs(list) do
        out[#out + 1] = string.format("%d x %s  |cff999999(%s)|r", r.count or 1, tostring(r.name), tostring(r.reason or ""))
    end
    if #list == 0 then return "Nothing to put away: what's in your bags you carry or need soon.", out end
    return string.format("%d stack(s) Flow keeps for later and nothing on your route uses now:", B.Stacks(list)), out
end

-------------------------------------------------------------------------------
-- "In your bank", drawn as the bank looks: a grid of slots, read only
-------------------------------------------------------------------------------
-- "Flow Banker ... to look like it does when I'm at the actual bank, just
-- read-only" (0.35.215). Each slot in the bank's own order, with its icon
-- and count; empty slots stay empty squares. Hover a slot for the item.
-- Nothing can be moved from here: it's a picture of what Flow last saw.
-- (A bank Flow saw before 0.35.215 has no slot order kept: its things are
-- shown by name, without the empty slots, until you open the bank again.)
B.COLS, B.GRID_ROWS, B.CELL = 8, 6, 34

-- Pure: the grid's cells. layout: the bank slot by slot ({ id, count } or
-- false); without one, items ({ [id] = count }) by name. -> { { id, count }
-- or false }, and whether it's the bank's own order.
function B.Cells(layout, items, name)
    if type(layout) == "table" and #layout > 0 then
        local out = {}
        for i, s in ipairs(layout) do
            out[i] = (type(s) == "table" and s[1]) and { id = s[1], count = s[2] or 1 } or false
        end
        return out, true
    end
    local out = {}
    for _, r in ipairs(B.BankRows(items, name)) do out[#out + 1] = { id = r.id, count = r.count } end
    return out, false
end

-- Pure: which cells show. n cells, scrolled down `offset` rows.
--   -> first cell, the offset in range, rows below the last one shown
function B.GridWindow(n, offset, cols, rows)
    local total = math.ceil((n or 0) / cols)
    local maxOff = math.max(0, total - rows)
    offset = math.max(0, math.min(offset or 0, maxOff))
    return offset * cols + 1, offset, maxOff - offset
end

local function makeCell(f, i)
    local c = CreateFrame("Frame", nil, f)
    c:SetSize(B.CELL - 2, B.CELL - 2)
    local col, row = (i - 1) % B.COLS, math.floor((i - 1) / B.COLS)
    c:SetPoint("TOPLEFT", 14 + col * B.CELL, -82 - row * B.CELL)
    c.edge = c:CreateTexture(nil, "BACKGROUND", nil, 1)
    c.edge:SetPoint("TOPLEFT", -1, 1); c.edge:SetPoint("BOTTOMRIGHT", 1, -1)
    c.edge:SetColorTexture(0.3, 0.3, 0.33, 0.9)
    c.back = c:CreateTexture(nil, "BACKGROUND", nil, 2)
    c.back:SetAllPoints()
    c.back:SetColorTexture(0.08, 0.08, 0.1, 1)
    c.icon = c:CreateTexture(nil, "ARTWORK")
    c.icon:SetAllPoints()
    c.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    c.count = c:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    c.count:SetPoint("BOTTOMRIGHT", -1, 1)
    c:EnableMouse(true)
    c:SetScript("OnEnter", function(self)
        if not self.id then return end
        ns.Tip(self, "ANCHOR_RIGHT")
        -- (This cell says what Flow does with the thing itself: the item's own
        -- Flow lines would say it a second and third time.)
        ns.tipQuiet = self.cell and self or nil
        if GameTooltip.SetItemByID then GameTooltip:SetItemByID(self.id) end
        GameTooltip:AddLine(" ")
        local cell = self.cell
        if cell then
            for _, l in ipairs(B.CellTip(cell)) do GameTooltip:AddLine(l.text, l.r, l.g, l.b, true) end
        else
            GameTooltip:AddLine("In your bank, as Flow last saw it. Go to a bank to take it out.", 0.6, 0.6, 0.6, true)
        end
        GameTooltip:Show()
    end)
    c:SetScript("OnLeave", function(self) if ns.tipQuiet == self then ns.tipQuiet = nil end; GameTooltip:Hide() end)
    c:SetScript("OnHide", function(self) if ns.tipQuiet == self then ns.tipQuiet = nil end end)
    c:SetScript("OnMouseUp", function(self, button) B:CellClick(self, button) end)
    c:Hide()
    return c
end

-- Pure: every choice you've made, as cells (things you carry or not): to
-- the bank first, then by name.
function B.RuleCells(rules, name)
    local out = {}
    for id, rule in pairs(rules or {}) do
        if type(id) == "number" and (rule == "bank" or rule == "carry") then
            out[#out + 1] = { id = id, name = (name and name(id)) or ("item " .. id), count = 0, bank = rule == "bank", mine = rule,
                              why = rule == "bank" and "you chose to bank it" or "you chose to carry it" }
        end
    end
    table.sort(out, function(a, b)
        if a.bank ~= b.bank then return a.bank end
        if a.name ~= b.name then return a.name < b.name end
        return a.id < b.id
    end)
    return out
end

-- A cell of the "to put away" view: green edge = goes to the bank, grey and
-- dimmed = stays with you, gold = your own choice. (nil: a plain bank slot.)
function B.StyleCell(c, cell)
    if not cell then
        c.edge:SetColorTexture(0.3, 0.3, 0.33, 0.9)
        c.icon:SetDesaturated(false)
        c.icon:SetAlpha(1)
        return
    end
    if cell.mine then c.edge:SetColorTexture(1, 0.82, 0.1, 1)
    elseif cell.bank then c.edge:SetColorTexture(0.2, 0.9, 0.3, 1)
    else c.edge:SetColorTexture(0.3, 0.3, 0.33, 0.9) end
    c.icon:SetDesaturated(not cell.bank)
    c.icon:SetAlpha(cell.bank and 1 or 0.6)
end
-- Pure: a cell's tooltip, three lines at most (0.35.347; it was five, under
-- three more of Flow's on the item itself): where it goes and why, why Flow
-- keeps it, and the clicks. -> { { text, r, g, b } }
function B.CellTip(cell)
    local out = {}
    if type(cell) ~= "table" then return out end
    local why = cell.mine and "your choice" or tostring(cell.why or "Flow's choice")
    out[#out + 1] = { text = (cell.bank and "Goes to the bank: " or "Stays with you: ") .. why .. ".",
                      r = cell.bank and 0.2 or 0.8, g = cell.bank and 0.9 or 0.8, b = cell.bank and 0.3 or 0.8 }
    local short = ns.disposition.ShortReason(cell.reason)
    if short ~= "" then out[#out + 1] = { text = "Flow keeps it: " .. short .. ".", r = 1, g = 0.82, b = 0 } end
    local clicks = "Click: " .. (cell.bank and "keep it with you" or "put it in the bank") .. ". Right-click: Flow's choice."
    if cell.rule == "neverSell" or cell.rule == "yourChoice" then clicks = clicks .. " Alt-click: Flow may sell it again." end
    if cell.id and ((cell.sell or 0) > 0 or cell.quality == 0) then clicks = clicks .. " Shift-click: sell it." end
    out[#out + 1] = { text = clicks, r = 0.6, g = 0.6, b = 0.6 }
    return out
end
-- Pure: why Flow keeps the thing in a cell (the longer form; /flow banker).
function B.WhyLines(cell)
    local out = {}
    if cell and cell.reason and cell.reason ~= "" then out[#out + 1] = "Flow keeps it: " .. tostring(cell.reason) .. "." end
    if cell and cell.rule == "neverSell" then
        out[#out + 1] = "You bought it back from a vendor once, so Flow never sells it. Alt-click: let Flow sell it again."
    elseif cell and cell.rule == "yourChoice" then
        out[#out + 1] = "Alt-click: Flow's own choice again."
    end
    if cell and cell.id and ((cell.sell or 0) > 0 or cell.quality == 0) then
        out[#out + 1] = "Shift-click: sell it at the next vendor (your choice; undo it in To sell)."
    end
    return out
end
-- A click on a cell of that view: bank it or carry it; right-click: Flow's own choice.
-- Alt-click on something you once bought back: Flow may sell it again.
function B:CellClick(c, button, alt, shift)
    local cell = c and c.cell
    if not cell then return false end
    if alt == nil then alt = IsAltKeyDown and IsAltKeyDown() or false end
    if shift == nil then shift = IsShiftKeyDown and IsShiftKeyDown() or false end
    -- Shift-click: sell it (your choice), when a vendor buys it.
    if shift and not alt then
        if not ((cell.sell or 0) > 0 or cell.quality == 0) then
            if not c.quiet then ns:Print(tostring(cell.name) .. ": vendors won't buy it, so there's nothing to choose.") end
            return false
        end
        if not ns.disposition.SetChoice(cell.id, "sell") then return false end
        if not c.quiet then ns:Print(tostring(cell.name) .. ": the Flow Seller sells it at the next vendor (your choice; undo it in To sell).") end
        B:Fill()
        return true
    end
    if alt then
        if (cell.rule ~= "neverSell" and cell.rule ~= "yourChoice") or not ns.disposition.Forget(cell.id) then return false end
        if not c.quiet then ns:Print(tostring(cell.name) .. ": Flow may sell it again (it goes by its usual rules now).") end   -- (quiet: the self-test)
        if ns.bagIcons and ns.bagIcons.MarkDirty then ns.bagIcons.MarkDirty() end
        B:Fill()
        return true
    end
    B.Rules()[cell.id] = B.NextRule(cell.bank, cell.mine, button == "RightButton")
    if ns.nav and ns.nav.RequestCollect then ns.nav.RequestCollect("banking choice") end
    if ns.bagIcons and ns.bagIcons.MarkDirty then ns.bagIcons.MarkDirty() end   -- (the bank icons on your bags follow)
    B:Fill()
    return true
end

-- Fills (or hides) the grid. -> the line above it, when it shows.
function B:FillGrid(show)
    local f = B.frame
    if not f then return nil end
    f.cells = f.cells or {}
    if not show then
        for _, c in ipairs(f.cells) do c:Hide() end
        return nil
    end
    local bank = ns.db.bank or {}
    local cells, own
    if show == "put" then
        -- What Flow keeps in your bags: to the bank (green) or with you (grey).
        local D = ns.disposition
        local okR, rows = pcall(D.Inventory, D)
        cells = B.allRules and B.RuleCells(B.Rules(), nameOf) or B.PutCells(okR and rows or {}, B.Needed(), B.Rules(), ns.questBags and ns.questBags.Waits() or nil)
    else
        cells, own = B.Cells(bank.layout, bank.items, nameOf)
    end
    local first, offset, below = B.GridWindow(#cells, B.offset, B.COLS, B.GRID_ROWS)
    B.offset = offset
    local used = 0
    for _, s in ipairs(cells) do if s then used = used + 1 end end
    for i = 1, B.COLS * B.GRID_ROWS do
        local c = f.cells[i] or makeCell(f, i)
        f.cells[i] = c
        local s = cells[first + i - 1]
        if s == nil then
            c:Hide()
        else
            c.id = s and s.id or nil
            c.cell = (show == "put") and s or nil
            B.StyleCell(c, c.cell)
            if s then
                c.icon:SetTexture((ns.api.ItemIcon and ns.api.ItemIcon(s.id))
                    or (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(s.id))
                    or "Interface\\Icons\\INV_Misc_QuestionMark")
                c.icon:Show()
                c.count:SetText((s.count or 1) > 1 and s.count or "")
            else
                c.icon:Hide()
                c.count:SetText("")
            end
            c:Show()
        end
    end
    if show == "put" then
        local n = 0
        for _, s in ipairs(cells) do if s.bank then n = n + 1 end end
        if B.allRules then
            return string.format("Every choice you've made (%d), also for things not in your bags. Click to flip one, right-click to drop it.%s", #cells,
                (below > 0 or offset > 0) and " Scroll for more." or "")
        end
        return string.format("Green: to the bank (%d). Grey: stays with you. Click one to change it; right-click: Flow's own choice.%s", n,
            (below > 0 or offset > 0) and " Scroll for more." or "")
    end
    if not bank.seenAt then return "Flow hasn't seen inside your bank yet. Open it once and Flow remembers what's there." end
    return string.format("Your bank as Flow saw it %s: %d slot(s) used%s.%s", B.Ago(time() - bank.seenAt), used,
        own and string.format(" of %d", #cells) or "", (below > 0 or offset > 0) and " Scroll for more." or "")
end

function B:Fill()
    local f = B.frame
    if not f then return end
    local note, lines = B.ViewLines(B.view)
    -- The bank is a grid of slots, not a list (FillGrid, above).
    local gridView = B.view == "bank" or B.view == "put"
    local grid = B:FillGrid(gridView and B.view or nil)
    local putCount = B.view == "put" and #lines or 0
    if gridView then note, lines = grid or note, {} end
    f.note:SetText(note)
    local first, last, below = 1, 0, 0
    if not gridView then
        local offset
        first, last, below, offset = B.Window(#lines, B.offset, B.ROWS)
        B.offset = offset
    end
    for i = 1, B.ROWS do
        local at = first + i - 1
        local text = at <= last and lines[at] or ""
        if i == B.ROWS and below > 0 then
            text = string.format("|cff999999... and %d more (scroll)|r", below + 1)
        end
        f.rows[i]:SetText(text)
        local rb = f.rowButtons and f.rowButtons[i]
        if rb then
            rb.id = (B.lineIds and at <= last and not (i == B.ROWS and below > 0)) and B.lineIds[at] or nil
            rb.row = rb.id and B.lineRows and B.lineRows[at] or nil
            rb:SetShown(rb.id ~= nil)
        end
    end
    for key, tb in pairs(f.tabs) do
        if key == B.view then tb.text:SetTextColor(1, 0.82, 0) else tb.text:SetTextColor(0.6, 0.6, 0.6) end
    end
    f.all:SetShown(B.view == "put" or B.view == "sell")
    -- To sell: one button back to Flow's own choices (0.35.348: "All my
    -- choices" there read as "keep everything"; "a button that just lets me
    -- go back to Flow's own choice").
    if B.view == "sell" then
        f.all:SetText("Reset to Flow's")
        f.all:SetEnabled(B.ChoiceCount() > 0)
    else
        f.all:SetText(B.allRules and "In my bags" or "All my choices")
        f.all:SetEnabled(true)
    end
    f.search:SetShown(B.view == "prices")
    f.search.label:SetShown(B.view == "prices")
    f.go:SetShown(B.view == "put" or (B.view == "sell" and (B.takeCount or 0) > 0))
    if B.view == "sell" then
        f.go:SetEnabled(bankOpen and (B.takeCount or 0) > 0)
        f.go:SetText(bankOpen and "Take out" or "At a bank")
    else
        f.go:SetEnabled(bankOpen and putCount > 0)
        f.go:SetText(bankOpen and "Deposit" or "At a bank")
    end
end

-- How many sell or keep choices (and buy-backs) you've made.
function B.ChoiceCount()
    local n = 0
    for _ in pairs(ns.db.sell and ns.db.sell.mine or {}) do n = n + 1 end
    for _ in pairs(ns.db.sell and ns.db.sell.never or {}) do n = n + 1 end
    return n
end
-- "Flow's choices" (To sell): every sell or keep choice of yours is dropped,
-- and Flow decides what sells again. quiet: no chat line (the self-test).
function B:ResetSell(quiet)
    local n = ns.disposition.ResetChoices()
    takeOutReset()
    if not quiet then
        ns:Print(n > 0 and string.format("Flow Banker: %d sell or keep choice(s) of yours dropped. Flow decides what sells again.", n)
            or "Flow Banker: you had no sell or keep choices of your own.")
    end
    B:Fill()
    return n
end

-- The button at the bottom right: Deposit ("To bank") or Take out ("To sell").
function B:GoClick()
    if B.view == "sell" then return B:Withdraw() end
    return B:Deposit()
end

-- A click on a line of "Auction prices": that item's price chart.
-- A click on a line of "To sell": keep it instead; on one you chose to sell,
-- or a right-click: Flow's own choice again.
function B:RowClick(rb, button)
    if not (rb and rb.id) then return false end
    if B.view == "sell" then
        local row = rb.row or {}
        local D = ns.disposition
        local reset = button == "RightButton"
        local want = B.NextSellChoice(row.kept, reset)
        -- (A thing no vendor buys can't be sold: back to Flow's own choice.)
        if want == "sell" and not row.listed and not ((row.sell or 0) > 0 or row.quality == 0) then want = nil end
        local changed = false
        if row.bought then changed = D.Forget(rb.id) end   -- (a buy-back is undone either way)
        changed = D.SetChoice(rb.id, want) or changed
        takeOutReset()
        B:Fill()
        return changed
    end
    if not ns.priceChart then return false end
    return ns.priceChart:Show(rb.id)
end
-- Pure: your choice after a click on a "To sell" line. mine: it's there by
-- your own choice. Left: keep it (a thing you chose to sell: undo that).
function B.NextSellChoice(kept, reset)
    if reset then return nil end
    return kept and "sell" or "keep"
end
-- Pure: a line's tooltip.
function B.RowTip(view, row)
    if view ~= "sell" then return { "Click: its price over time (Flow Prices)" } end
    if row and row.kept then
        return { row.bought and "Kept: you bought it back once." or "Kept: your choice.", "Click: sell it after all.", "Right-click: Flow's own choice." }
    end
    if row and row.mine then
        return { "Sold: your choice.", "Click: keep it instead.", "Right-click: Flow's own choice." }
    end
    return { "Flow sells it.", "Click: keep it (it stays in this list, marked Kept).", "Right-click: Flow's own choice." }
end

function B:Scroll(delta)
    -- (The bank's grid moves a row of slots a notch; the lists three lines.)
    B.offset = math.max(0, (B.offset or 0) - (delta or 0) * ((B.view == "bank" or B.view == "put") and 1 or 3))
    B:Fill()
end

-- Opens the window on a view ("put" when none is named).
function B:Show(view)
    B.frame = B.frame or build()
    local known = false
    for _, v in ipairs(B.VIEWS) do if v.key == view then known = true end end
    B.view, B.offset = known and view or "put", 0
    B:Fill()
    B.frame:Show()
end
function B:Open() B:Show("put") end
-- The tab on your bags: at a bank, what to put away; anywhere else, what's
-- in your bank. A second click closes it.
function B:Toggle()
    if B.frame and B.frame:IsShown() then B.frame:Hide() return end
    B:Show(bankOpen and "put" or "bank")
end
function B._Frame() return B.frame end

ns:Register("gameButton", "bags", {
    order = 50,
    frames = { "ContainerFrameCombinedBags", "ContainerFrame1" },
    label = "Flow Banker",
    tip = "What's in your bank (as Flow last saw it), what to put away at the next bank, and the auction prices Flow last saw.",
    isOpen = function() return B.frame and B.frame:IsShown() end,
    click = function() B:Toggle() end,
})

-- And on the bank's own window (0.35.270), beside the one on your bags.
ns:Register("gameButton", "bank", {
    order = 50,
    frames = { "BankFrame" },
    label = "Flow Banker",
    tip = "What to put away here, what's in your bank, and the auction prices Flow last saw.",
    isOpen = function() return B.frame and B.frame:IsShown() end,
    click = function() B:Toggle() end,
})

ns:On("BANKFRAME_OPENED", function()
    bankOpen = true
    if ns.db.banker.off then return end
    -- (Shown only when there's something to put away, or to take out and sell.)
    takeMemo.at = -100
    -- What your route's step or a quest needs out of the bank comes first:
    -- the window opens on it, Take out one click away (0.35.353).
    local take = B.TakeOut()
    if B.TakeUrgent(take) then B:Show("sell")
    elseif #B.List() > 0 then B:Open()
    elseif #take > 0 then B:Show("sell") end
end)
ns:On("BANKFRAME_CLOSED", function()
    bankOpen = false
    -- (The list of what to put away closes with the bank; a look at what's in
    -- the bank or at prices stays.)
    if B.frame and B.frame:IsShown() then
        if B.view == "put" then B.frame:Hide() else B:Fill() end   -- ("To sell" stays: its list holds anywhere)
    end
end)
ns:OnLoad(function(saved) saved.banker = saved.banker or {} end)

-------------------------------------------------------------------------------
-- On the route: a bank step when one is on your way and it's worth it
-------------------------------------------------------------------------------
-- Pure: worth a step? stacks to put away; free: bag slots left (nil: unknown).
function B.WorthAStop(stacks, free, min)
    if (stacks or 0) >= (min or B.MIN_STACKS) then return true end
    return (stacks or 0) > 0 and ns.BagsNearlyFull(free)
end

-- Pure: the step's words.
function B.StepText(stacks, out)
    if (out or 0) <= 0 then return string.format("Bank: put %d stack(s) away", stacks or 0) end
    if (stacks or 0) <= 0 then return string.format("Bank: take %d thing(s) out to sell", out) end
    return string.format("Bank: put %d stack(s) away, take %d thing(s) out to sell", stacks, out)
end

local cache = { at = 0, goals = nil }
ns:Register("navGoal", "banker", {
    collect = function()
        if ns.db.banker.off then return nil end
        local now = GetTime()
        if now - cache.at < 5 then return cache.goals end
        cache.at, cache.goals = now, nil
        local S = ns.services
        if not (S and S.All) or bankOpen then return nil end
        local stacks = B.Stacks(B.List())
        local free = ns.export and ns.export.BagsFree and ns.export.BagsFree() or nil
        -- (What to take out and sell counts towards a stop being worth it.)
        local okT, take = pcall(B.TakeOut)
        local out = okT and #take or 0
        if not B.WorthAStop(stacks + out, free) then return nil end
        local ok, bankers = pcall(S.All, S, "bank", 6)
        if not ok or #bankers == 0 then return nil end
        local points = {}
        for _, b in ipairs(bankers) do points[#points + 1] = { map = b.map, x = b.x, y = b.y } end
        cache.goals = { {
            key = "bank", kind = "merchant", optional = true, weight = 1, points = points,
            title = "Flow Banker", text = B.StepText(stacks, out),
            details = { "Things Flow keeps for later that nothing on your route uses now. At the banker, Flow Banker lists them: one click puts them in.",
                        out > 0 and "And things in your bank Flow would sell now (a material your skill has moved past): To sell, Take out. The Flow Seller sells them at the next vendor." or nil,
                        "Only on the route while a bank is close to the way you're going." },
        } }
        return cache.goals
    end,
})
ns:Register("routeKind", "banker", { order = 62, default = true,
    label = "The bank (when you pass one with things to put away)", short = "bank",
    tip = "A step at a banker that's close to your way, when your bags hold a few stacks Flow keeps for later and nothing on your route needs now.",
    match = function(g) return g.provider == "banker" end })

-- /flow banker: the list (on|off: the window and the step).
function B.Lines()
    local list = B.List()
    local out = { string.format("Flow Banker: %d stack(s) to put away%s", B.Stacks(list), ns.db.banker.off and " (off)" or "") }
    -- The bank as the game reports it, container by container (which hold things).
    local parts = {}
    for _, part in ipairs((ns.db.bank and ns.db.bank.parts) or {}) do
        parts[#parts + 1] = string.format("%s: %d of %d", tostring(part.bag), part.used or 0, part.slots or 0)
    end
    if #parts > 0 then out[#out + 1] = "  bank containers (used of slots): " .. table.concat(parts, ", ") end
    for _, r in ipairs(list) do
        out[#out + 1] = string.format("%d x %s [%s] in %d slot(s): %s", r.count or 1, tostring(r.name), tostring(r.id), r.stacks or 1, tostring(r.reason))
    end
    local okT, take = pcall(B.TakeOut, true)
    out[#out + 1] = string.format("  in your bank, to take out and sell: %s", okT and tostring(#take) or ("failed: " .. tostring(take)))
    for _, r in ipairs(okT and take or {}) do
        out[#out + 1] = string.format("  %d x %s [%s]: %s (%s)", r.count or 1, tostring(r.name), tostring(r.id), tostring(r.action), tostring(r.reason))
    end
    local never = {}
    for id in pairs((ns.db.sell and ns.db.sell.never) or {}) do never[#never + 1] = tostring(id) end
    table.sort(never)
    local okP, put = pcall(B.List)
    local thrash = B.Thrash(okT and take or {}, okP and put or {})
    local parked, moved = {}, {}
    for id, pk in pairs(ns.db.banker.parked or {}) do parked[#parked + 1] = string.format("%s (%s, continent %s)", tostring(id), tostring(pk.title), tostring(pk.cont)) end
    for id, m in pairs(B.moved) do moved[#moved + 1] = tostring(id) .. " " .. tostring(m.dir) end
    table.sort(parked); table.sort(moved)
    out[#out + 1] = "  parked for a quest across the sea: " .. (#parked > 0 and table.concat(parked, ", ") or "none")
    out[#out + 1] = "  moved by Flow this session: " .. (#moved > 0 and table.concat(moved, ", ") or "none")
    out[#out + 1] = "  taken out and put back (must be none): " .. (#thrash > 0 and table.concat(thrash, ", ") or "none")
    out[#out + 1] = "  bought back once, never sold (Alt-click one in To bank to undo): " .. (#never > 0 and table.concat(never, ", ") or "none")
    local mine = {}
    for id, what in pairs((ns.db.sell and ns.db.sell.mine) or {}) do mine[#mine + 1] = tostring(id) .. " " .. tostring(what) end
    table.sort(mine)
    out[#out + 1] = "  your own sell or keep choices: " .. (#mine > 0 and table.concat(mine, ", ") or "none")
    return out
end
ns.commands.banker = function(arg)
    arg = (arg or ""):lower()
    if arg == "on" or arg == "off" then
        ns.db.banker.off = (arg == "off") or nil
        ns:Print("Flow Banker " .. arg)
        return
    end
    if arg == "show" then B:Open() return end
    if arg == "bank" or arg == "prices" or arg == "sell" then B:Show(arg) return end
    for i, l in ipairs(B.Lines()) do if i == 1 then ns:Print(l) else print("  " .. l) end end
    print("  /flow banker show (the window)   /flow banker bank (what's in your bank)   /flow banker sell   /flow banker prices   /flow banker on|off")
end
ns:Register("help", "banker", { order = 58, title = "Flow Banker", lines = {
    "At a bank, Flow Banker lists what you won't need soon (materials kept for later that no step on your route uses) and deposits it at a click.",
    "Away from a bank, its \"In your bank\" view lists what was there when you last opened it, and \"Auction prices\" what Flow last saw at the auction house. The Flow Banker tab on your bags opens it.",
    "\"To sell\" lists what the Flow Seller takes at the next vendor or auction house, and what's in your bank that Flow would now sell: at a bank, Take out brings those to your bags.",
    "In \"To bank\", hover a thing for why Flow keeps it. Alt-click one you once bought back to let Flow sell it again.",
    "Your own choice: Shift-click a thing in \"To bank\" to sell it; click a line of \"To sell\" to keep it. Alt-click (To bank) or a click on your own line (To sell) goes back to Flow's choice.",
    "/flow banker: the list. /flow banker show | bank | sell | prices. /flow banker on|off.",
} })
