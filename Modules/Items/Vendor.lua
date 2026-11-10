-- Vendor drawer: next to the merchant window.
--   [x] Sell all junk      every grey item, however many (on by default)
--   Also vendor (up to 12) gear and items with a lower Flow score than what
--                          you have for every role and gear set, not needed
--                          for a quest, not worth the auction house, not for
--                          disenchanting or crafting (see Disposition.lua).
--                          Each has its own Sell button.
--   Sell All               junk first, then up to 12 of the proposed items,
--                          so the proposed ones are the last sold and stay in
--                          the merchant's 12-slot buyback tab.
--   Sold this visit        each with "Buy back"; buying back teaches Flow to
--                          never sell that item again.
-- Buttons grey out when there's nothing left, and the drawer folds away when
-- there's nothing to sell or buy back, leaving the normal vendor window.

local _, ns = ...
local D = ns.disposition
local V = {}
ns.vendor = V

local BATCH = 12
local panel
local sold = {}         -- this visit: { { link, id, price } } (non-junk, can be bought back)
local junkSold = 0

local CC = C_Container
local function stackCount(bag, slot)
    if CC and CC.GetContainerItemInfo then
        local info = CC.GetContainerItemInfo(bag, slot)
        return info and info.stackCount or 1, info and info.isLocked
    end
    local _, count, locked = GetContainerItemInfo(bag, slot)
    return count or 1, locked
end
local useItem = (CC and CC.UseContainerItem) or UseContainerItem

local function money(c)
    return GetCoinTextureString and GetCoinTextureString(math.floor(c)) or tostring(c)
end

-- junk = all grey items; proposed = other items Flow would vendor (best value first).
function V:Candidates()
    local junk, proposed, ah, de = {}, {}, 0, 0
    D:EachBagItem(function(bag, slot, link)
        local v = D:Decide(bag, slot, link)
        if not v then return end
        if v.action == "ah" then ah = ah + 1 elseif v.action == "de" then de = de + 1 end
        if v.action == "sell" and v.item.sellPrice > 0 then
            local count, locked = stackCount(bag, slot)
            if not locked then
                local e = { bag = bag, slot = slot, link = link, id = v.item.id,
                            price = v.item.sellPrice * count, reason = v.reason,
                            diffs = v.item.gear and v.item.gear.canUse and v.item.gear.diffs or nil }
                if v.item.quality == 0 then junk[#junk + 1] = e else proposed[#proposed + 1] = e end
            end
        end
    end)
    table.sort(proposed, function(a, b) return a.price > b.price end)
    return junk, proposed, ah, de
end

local function buybackIndex(link)
    local id = tonumber(link:match("item:(%d+)"))
    for i = (GetNumBuybackItems and GetNumBuybackItems() or 0), 1, -1 do
        local l = GetBuybackItemLink and GetBuybackItemLink(i)
        if l and (l == link or tonumber(l:match("item:(%d+)")) == id) then return i end
    end
end

-- The vendor is open from MERCHANT_SHOW until MERCHANT_CLOSED. (Checking the
-- vendor window itself failed: it is shown just AFTER the event, so the
-- drawer never appeared.)
local merchantOpen = false
local function canSell() return merchantOpen end

local function sellOne(e)
    if not canSell() then return end
    useItem(e.bag, e.slot)
    sold[#sold + 1] = { link = e.link, id = e.id, price = e.price }
    while #sold > BATCH do table.remove(sold, 1) end  -- older ones left the buyback tab
end

-------------------------------------------------------------------------------
-- Drawer UI
-------------------------------------------------------------------------------

local ROW_H = 22

local function makeRow(parent)
    local r = CreateFrame("Frame", nil, parent)
    r:SetSize(316, 20)
    r:EnableMouse(true)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(18, 18)
    r.icon:SetPoint("LEFT")
    r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.name:SetPoint("LEFT", r.icon, "RIGHT", 4, 0)
    r.name:SetWidth(150)
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    r.price = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.price:SetPoint("RIGHT", -74, 0)
    r.btn = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
    r.btn:SetSize(68, 18)
    r.btn:SetPoint("RIGHT")
    r.btn:GetFontString():SetFontObject("GameFontHighlightSmall")
    -- Gear: the same spec badge as in your bags (Gear/SpecBadge.lua).
    r.specs = ns:SpecBadge(r, 9)
    r.specs:SetPoint("LEFT", r, "LEFT", 176, 0)
    r:SetScript("OnEnter", function(self)
        if not self.link then return end
        ns.Tip(self, "ANCHOR_LEFT")
        GameTooltip:SetHyperlink(self.link)
        if self.reason then GameTooltip:AddLine("Flow: " .. self.reason, 1, 0.82, 0.25, true) end
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return r
end

local function build()
    local f = CreateFrame("Frame", "FlowVendorPanel", UIParent)
    f:SetWidth(400)   -- (room in the header for Auto-sell and Auto-cleanup)
    f:SetFrameStrata("HIGH")
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.bg:SetColorTexture(0.05, 0.05, 0.08, 0.94)
    -- Flow's title bar (Theme.lua), the same as the Flow Tracker's and Flow
    -- Router's: a coin for the seller. It opens and closes the drawer. It stays
    -- on screen at every vendor, collapsed when there's nothing to sell, so you
    -- can see it's working ("0 items to sell") and open it to check.
    f.head = ns.theme:TitleBar(f, "Flow Seller", "Interface\\Icons\\INV_Misc_Coin_01", "Button")
    f.title = f.head.text
    f.head.pm = f.head:CreateTexture(nil, "ARTWORK")
    f.head.pm:SetSize(16, 16); f.head.pm:SetPoint("RIGHT", -8, 0)
    f.head.hl = f.head:CreateTexture(nil, "HIGHLIGHT"); f.head.hl:SetAllPoints(); f.head.hl:SetColorTexture(1, 1, 1, 0.06)
    f.head:SetScript("OnClick", function() V.visitCollapsed = not f.collapsed; V:Refresh() end)
    -- Auto-sell on/off, right in the header (also in Options > AddOns > Flow).
    f.auto = CreateFrame("CheckButton", nil, f.head, "UICheckButtonTemplate")
    f.auto:SetSize(20, 20)
    f.auto:SetPoint("RIGHT", f.head.pm, "LEFT", -6, 0)
    f.auto.label = f.head:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.auto.label:SetPoint("RIGHT", f.auto, "LEFT", 0, 0)
    f.auto.label:SetText("Auto-sell")
    f.auto:SetChecked(ns.db.sell.autoAll == true)
    f.auto:SetScript("OnClick", function(self)
        ns.db.sell.autoAll = self:GetChecked() and true or false
        ns:Print("auto-sell at vendors " .. (ns.db.sell.autoAll and "on" or "off") .. " (grey junk: " .. (ns.db.sell.autoJunk and "on" or "off") .. ")")
    end)
    f.auto:SetScript("OnEnter", function(self)
        ns.Tip(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Auto-sell", 1, 1, 1)
        GameTooltip:AddLine("When you open a vendor, sell what Flow marks to sell (up to 12, so you can buy any back). Grey junk has its own switch in Options.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    f.auto:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- Auto-cleanup on/off, beside it: the game's Clean Up Bags after auto-sell.
    f.clean = CreateFrame("CheckButton", nil, f.head, "UICheckButtonTemplate")
    f.clean:SetSize(20, 20)
    f.clean:SetPoint("RIGHT", f.auto.label, "LEFT", -8, 0)
    f.clean.label = f.head:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.clean.label:SetPoint("RIGHT", f.clean, "LEFT", 0, 0)
    f.clean.label:SetText("Auto-cleanup")
    f.clean:SetChecked(ns.db.sell.autoCleanup ~= false)
    f.clean:SetScript("OnClick", function(self)
        ns.db.sell.autoCleanup = self:GetChecked() and true or false
        ns:Print("clean up bags after auto-sell " .. (ns.db.sell.autoCleanup and "on" or "off"))
    end)
    f.clean:SetScript("OnEnter", function(self)
        ns.Tip(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Auto-cleanup", 1, 1, 1)
        GameTooltip:AddLine(V.CanCleanup() and "After auto-sell sells something, Flow tidies your bags with the game's Clean Up Bags (the broom on your bags)."
            or "This client has no Clean Up Bags, so there's nothing for Flow to run.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    f.clean:SetScript("OnLeave", function() GameTooltip:Hide() end)

    f.junk = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    f.junk:SetSize(22, 22)
    f.junk:SetPoint("TOPLEFT", 8, -28)
    f.junkLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.junkLabel:SetPoint("LEFT", f.junk, "RIGHT", 2, 0)
    f.junk:SetScript("OnClick", function(self)
        ns.db.sell.junkAll = self:GetChecked() and true or false
        V:Refresh()
    end)
    f.junk:SetScript("OnEnter", function(self)
        ns.Tip(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Sells every grey item with Sell All, not just 12.", 1, 1, 1, true)
        GameTooltip:AddLine("Junk is sold first, so your proposed items are the ones that stay in the buyback tab.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    f.junk:SetScript("OnLeave", function() GameTooltip:Hide() end)

    f.propHeader = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.propHeader:SetJustifyH("LEFT")
    f.propHeader:SetWidth(320)
    f.soldHeader = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.soldHeader:SetJustifyH("LEFT")
    f.soldHeader:SetWidth(320)
    f.footer = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.footer:SetJustifyH("LEFT")
    f.footer:SetWidth(320)

    f.propRows, f.soldRows = {}, {}
    for i = 1, BATCH do f.propRows[i] = makeRow(f); f.soldRows[i] = makeRow(f) end

    f.sellAll = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.sellAll:SetSize(230, 24)
    f.sellAll:SetPoint("BOTTOMLEFT", 10, 10)
    f.sellAll:SetScript("OnClick", function() V:SellAll() end)
    f.close = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.close:SetSize(80, 24)
    f.close:SetPoint("BOTTOMRIGHT", -10, 10)
    f.close:SetText("Close")
    f.close:SetScript("OnClick", function() f:Hide() end)
    f:Hide()
    return f
end

function V:Refresh()
    if not panel or not canSell() then return end
    local junk, proposed, ah, de = self:Candidates()
    local f = panel

    -- Collapsed (just the header) when there's nothing to sell or buy back,
    -- unless you opened it this visit; open otherwise unless you closed it.
    local nothing = #junk == 0 and #proposed == 0 and #sold == 0
    local collapsed = V.visitCollapsed
    if collapsed == nil then collapsed = nothing end
    f.collapsed = collapsed
    local nSell = (ns.db.sell.junkAll ~= false and #junk or 0) + #proposed
    f.title:SetText(string.format("Flow Seller  |cff%s%d item%s to sell|r", nSell > 0 and "ffffff" or "888888",
        nSell, nSell == 1 and "" or "s"))
    f.head.pm:SetTexture(collapsed and "Interface\\Buttons\\UI-PlusButton-Up" or "Interface\\Buttons\\UI-MinusButton-Up")
    f.auto:SetChecked(ns.db.sell.autoAll == true)
    f.clean:SetChecked(ns.db.sell.autoCleanup ~= false)
    f.clean:SetEnabled(V.CanCleanup())
    local parts = { f.junk, f.junkLabel, f.propHeader, f.soldHeader, f.footer, f.sellAll, f.close }
    for _, r in ipairs(f.propRows) do parts[#parts + 1] = r end
    for _, r in ipairs(f.soldRows) do parts[#parts + 1] = r end
    if collapsed then
        for _, p in ipairs(parts) do p:Hide() end
        f:SetHeight(ns.theme.TITLE_H)   -- just the title bar
        f:Show()
        return
    end
    for _, p in ipairs({ f.junk, f.junkLabel, f.propHeader, f.soldHeader, f.footer, f.sellAll, f.close }) do p:Show() end
    f:Show()

    local junkValue = 0
    for _, e in ipairs(junk) do junkValue = junkValue + e.price end
    local junkOn = ns.db.sell.junkAll ~= false
    f.junk:SetChecked(junkOn)
    f.junk:SetEnabled(#junk > 0)
    f.junkLabel:SetText(#junk > 0 and string.format("Sell all junk: %d item(s), %s", #junk, money(junkValue))
        or ("|cff888888No junk left|r" .. (junkSold > 0 and string.format(" |cff888888(%d grey item%s sold this visit)|r",
            junkSold, junkSold == 1 and "" or "s") or "")))

    local y = -58
    f.propHeader:ClearAllPoints()
    f.propHeader:SetPoint("TOPLEFT", 10, y)
    f.propHeader:SetText(#proposed > 0
        and string.format("Also vendor (%d%s): lower Flow score than your gear for every role and set; not needed for quests, AH, DE or crafting",
            math.min(BATCH, #proposed), #proposed > BATCH and (" of " .. #proposed) or "")
        or "|cff888888Nothing else to vendor.|r")
    y = y - (f.propHeader:GetStringHeight() + 6)

    local batchValue = junkOn and junkValue or 0
    for i = 1, BATCH do
        local r, e = f.propRows[i], proposed[i]
        if e then
            r:ClearAllPoints(); r:SetPoint("TOPLEFT", 10, y); y = y - ROW_H
            r.link, r.reason = e.link, e.reason
            -- C_Item.GetItemIcon wants an item location, not a link: use the by-ID call.
            local id = e.link and tonumber(e.link:match("item:(%d+)"))
            local get = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
            r.icon:SetTexture(get and id and get(id) or nil)
            r.name:SetText(e.link)
            if e.diffs then r.specs:Set(e.diffs) else r.specs:Hide() end
            r.price:SetText(money(e.price))
            r.btn:SetText("Sell")
            r.btn:Show()
            r.btn:SetScript("OnClick", function() sellOne(e); C_Timer.After(0.3, function() V:Refresh() end) end)
            r:Show()
            batchValue = batchValue + e.price
        else
            r:Hide()
        end
    end

    -- Sold this visit (can still be bought back).
    if #sold > 0 then
        y = y - 6
        f.soldHeader:ClearAllPoints()
        f.soldHeader:SetPoint("TOPLEFT", 10, y)
        f.soldHeader:SetText("Sold this visit (buy back from the vendor's buyback tab):")
        f.soldHeader:Show()
        y = y - 16
    else
        f.soldHeader:Hide()
    end
    for i = 1, BATCH do
        local r, e = f.soldRows[i], sold[#sold - i + 1]   -- newest first
        if e then
            r:ClearAllPoints(); r:SetPoint("TOPLEFT", 10, y); y = y - ROW_H
            r.link, r.reason = e.link, nil
            -- C_Item.GetItemIcon wants an item location, not a link: use the by-ID call.
            local id = e.link and tonumber(e.link:match("item:(%d+)"))
            local get = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
            r.icon:SetTexture(get and id and get(id) or nil)
            r.name:SetText(e.link)
            if e.diffs then r.specs:Set(e.diffs) else r.specs:Hide() end
            r.price:SetText(money(e.price))
            r.btn:SetText("Buy back")
            r.btn:SetScript("OnClick", function()
                local idx = buybackIndex(e.link)
                if not idx then ns:Print("that item is no longer in the buyback tab") return end
                BuybackItem(idx)
                if e.id then ns.db.sell.never[e.id] = true end
                for k, s in ipairs(sold) do if s == e then table.remove(sold, k) break end end
                D:Invalidate()
                ns:Print(e.link .. " bought back. Flow won't sell it again.")
                C_Timer.After(0.3, function() V:Refresh() end)
            end)
            r:Show()
        else
            r:Hide()
        end
    end

    local kept = {}
    if ah > 0 then kept[#kept + 1] = ah .. " for the auction house" end
    if de > 0 then kept[#kept + 1] = de .. " to disenchant" end
    y = y - 6
    f.footer:ClearAllPoints()
    f.footer:SetPoint("TOPLEFT", 10, y)
    f.footer:SetText((#kept > 0 and ("Kept: " .. table.concat(kept, ", ") .. ". ") or "") .. "Hover an item to see why.")
    y = y - (f.footer:GetStringHeight() + 44)
    f:SetHeight(-y)

    local anything = (junkOn and #junk > 0) or #proposed > 0
    f.sellAll:SetEnabled(anything)
    -- Say what it sells: how many items, and for how much (the coin icons alone
    -- read like a count).
    nSell = (junkOn and #junk or 0) + math.min(BATCH, #proposed)
    f.sellAll:SetText(anything and string.format("Sell %d item%s for %s", nSell, nSell == 1 and "" or "s", money(batchValue))
        or "Nothing to sell")
end

-- Sell every grey item right away (no confirmation), when you open a vendor.
-- Setting: "Auto-sell junk at vendors" in /flow setup (on by default).
function V:SellJunk()
    if not canSell() then return end
    local junk = self:Candidates()
    local value = 0
    for _, e in ipairs(junk) do
        useItem(e.bag, e.slot)
        junkSold = junkSold + 1
        value = value + e.price
    end
    if #junk > 0 then
        ns:Print(string.format("sold %d junk item(s) for %s", #junk, money(value)))
        D:Invalidate()
    end
    return #junk
end

-------------------------------------------------------------------------------
-- Auto-cleanup: after auto-sell sold something, the game's Clean Up Bags
-- (the broom on your bags) tidies them, once the sales have gone through.
-- Checkbox "Auto-cleanup" in the Flow Seller's header (on).
-------------------------------------------------------------------------------

local function sortBags() return (C_Container and C_Container.SortBags) or _G.SortBags end
function V.CanCleanup() return sortBags() ~= nil end

function V.ShouldCleanup(sold, on, canSort, inCombat)
    return (sold or 0) > 0 and on ~= false and canSort and not inCombat
end

function V:Cleanup(sold)
    if not V.ShouldCleanup(sold, ns.db.sell.autoCleanup, V.CanCleanup(), InCombatLockdown()) then return end
    -- A moment later: the sold items leave your bags first.
    C_Timer.After(1, function()
        if InCombatLockdown() then return end
        local ok, err = pcall(sortBags())
        ns:Log("sell", ok and string.format("cleaned up bags after selling %d item(s)", sold) or ("bag cleanup failed: " .. tostring(err)))
    end)
end

-- Junk first (all of it, if ticked), then up to 12 proposed items. Runs from
-- a click (some clients require a real click to sell).
function V:SellAll()
    if not canSell() then return end
    local junk, proposed = self:Candidates()
    local count = 0
    if ns.db.sell.junkAll ~= false then
        for _, e in ipairs(junk) do useItem(e.bag, e.slot); junkSold = junkSold + 1; count = count + 1 end
    end
    for i = 1, math.min(BATCH, #proposed) do sellOne(proposed[i]); count = count + 1 end
    V:Cleanup(count)   -- (Auto-cleanup after this sale too)
    D:Invalidate()
    C_Timer.After(0.4, function() V:Refresh() end)
end

-- The panel, built the first time it's needed (a vendor, or the tests).
function V:Panel()
    panel = panel or build()
    return panel
end

-------------------------------------------------------------------------------
-- Auto-repair
-------------------------------------------------------------------------------

-- At a vendor who repairs: repair everything, if you can afford it
-- (Options: "Auto-repair at vendors").
function V:AutoRepair()
    if not (CanMerchantRepair and CanMerchantRepair() and GetRepairAllCost and RepairAllItems) then return end
    local cost, can = GetRepairAllCost()
    cost = tonumber(cost) or 0
    if cost <= 0 then return end
    if not can or (GetMoney and GetMoney() < cost) then
        ns:Print("can't afford to repair your gear here (" .. money(cost) .. ")")
        return
    end
    RepairAllItems()
    ns:Print("repaired your gear for " .. money(cost))
end

ns:On("MERCHANT_SHOW", function()
    merchantOpen = true
    if ns.db.sell.autoRepair ~= false then V:AutoRepair() end
    if not ns.db.sell.enabled then return end
    V:Panel()
    wipe(sold); junkSold = 0
    V.visitCollapsed = nil  -- each visit starts open if there's something to sell, else collapsed
    D:Invalidate()
    -- Next frame, once the vendor window is on screen to anchor to.
    C_Timer.After(0, function()
        if not merchantOpen then return end
        panel:ClearAllPoints()
        panel:SetPoint("TOPLEFT", MerchantFrame, "TOPRIGHT", 4, 0)
        local sold = 0
        if ns.db.sell.autoJunk then sold = sold + (V:SellJunk() or 0) end
        if ns.db.sell.autoAll then sold = sold + (V:SellProposed() or 0) end
        V:Cleanup(sold)   -- Auto-cleanup: tidy your bags after auto-sell
        V:Refresh()
    end)
end)

-- Auto-sell (Options: "Auto-sell everything Flow marks to sell"): the
-- non-junk items Flow says you don't need, as soon as you open a vendor.
-- At most 12 a visit, the vendor's buyback tab: anything sold by mistake can
-- be bought back there (the drawer lists them with "Buy back"), and buying
-- it back tells Flow never to sell that item again. More than 12: the rest
-- go on the next visit.
function V:SellProposed()
    if not canSell() then return end
    local _, proposed = self:Candidates()
    local n, value = math.min(BATCH, #proposed), 0
    for i = 1, n do
        sellOne(proposed[i])
        value = value + proposed[i].price
    end
    if n > 0 then
        D:Invalidate()
        ns:Print(string.format("sold %d item(s) you don't need for %s%s. Wrong one? Buy it back in the Flow Seller: Flow won't sell it again.",
            n, money(value), #proposed > n and string.format(" (%d more next visit)", #proposed - n) or ""))
    end
    return n
end

ns:On("MERCHANT_CLOSED", function()
    merchantOpen = false
    if panel then panel:Hide() end
end)
ns:On("BAG_UPDATE_DELAYED", function()
    if panel and canSell() then D:Invalidate(); V:Refresh() end
end)

ns:OnLoad(function(saved)
    if saved.sell.enabled == nil then saved.sell.enabled = true end
    if saved.sell.junkAll == nil then saved.sell.junkAll = true end
    if saved.sell.autoJunk == nil then saved.sell.autoJunk = true end
    -- Auto-sell the rest of Flow's "sell" items too (you asked for it).
    if saved.sell.autoAll == nil then saved.sell.autoAll = true end
    if saved.sell.autoRepair == nil then saved.sell.autoRepair = true end
end)

ns:Register("setupItem", "autoRepair", {
    order = 17, label = "Auto-repair at vendors",
    why = "Repairs all your gear when you open a vendor who repairs, if you have the gold (Flow says what it cost).",
    isOn = function() return ns.db.sell.autoRepair ~= false end,
    set = function(on) ns.db.sell.autoRepair = on end,
    suggested = true, default = true, isNew = true,
})

ns:Register("setupItem", "autoAll", {
    order = 16, label = "Auto-sell everything Flow marks to sell",
    why = "At a vendor, also sells the gear, food and other items Flow says you don't need (up to 12 a visit, so you can buy any back; Flow then never sells it again).",
    isOn = function() return ns.db.sell.autoAll == true end,
    set = function(on) ns.db.sell.autoAll = on end,
    suggested = true, default = false, isNew = true,
})

ns:Register("setupItem", "autoJunk", {
    order = 15, label = "Auto-sell junk at vendors",
    why = "Sells every grey item as soon as you open a vendor, with no confirmation.",
    isOn = function() return ns.db.sell.autoJunk == true end,
    set = function(on) ns.db.sell.autoJunk = on end,
    suggested = true, default = false,
})

ns.commands.sell = function(arg)
    arg = (arg or ""):lower()
    if arg == "on" or arg == "off" then
        ns.db.sell.enabled = (arg == "on")
        ns:Print("Flow Seller " .. arg)
    elseif arg == "forget" then
        wipe(ns.db.sell.never)
        D:Invalidate()
        ns:Print("forgot your never-sell list")
    else
        local n = 0
        for _ in pairs(ns.db.sell.never) do n = n + 1 end
        ns:Print(string.format("Flow Seller %s; %d item(s) on your never-sell list. /flow sell on|off|forget",
            ns.db.sell.enabled and "on" or "off", n))
    end
end

-------------------------------------------------------------------------------
-- Merchant stop on the route, only when it's worth it:
--   what Flow would sell is worth at least ~5 silver per character level, or
--   your bags are nearly full (3 or fewer free slots) and there's something
--   to sell.
-- It's an optional stop, so the planner only keeps it when a merchant is
-- roughly on your way (and drops it otherwise). Merchants come from the ones
-- you've visited (Flow remembers where) and the innkeepers it knows.
-------------------------------------------------------------------------------

local function freeBagSlots()
    local free = 0
    local fn = (CC and CC.GetContainerNumFreeSlots) or GetContainerNumFreeSlots
    if not fn then return 99 end
    for bag = 0, 4 do
        local n, bagType = fn(bag)
        if (bagType or 0) == 0 then free = free + (n or 0) end
    end
    return free
end

ns:Register("navGoal", "merchant", {
    collect = function()
        if not (ns.db.sell and ns.db.sell.enabled) then return nil end
        local junk, proposed = V:Candidates()
        local count, value = #junk + #proposed, 0
        for _, e in ipairs(junk) do value = value + e.price end
        for _, e in ipairs(proposed) do value = value + e.price end
        if count == 0 then return nil end
        local free = freeBagSlots()
        local worth = value >= UnitLevel("player") * 500 or free <= 3
        if not worth then return nil end
        local points = {}
        for name, spot in pairs(ns.db.places or {}) do
            if spot.kind == "vendor" then points[#points + 1] = { map = spot.map, x = spot.x, y = spot.y } end
        end
        for _, inn in ns:Each("innkeeper") do
            for _, pt in ipairs(ns.places:Points(inn.name)) do points[#points + 1] = pt end
        end
        if #points == 0 then return nil end
        -- Bags full (1 slot or none): loot is being lost, so it's a real stop,
        -- planned even with a detour. Otherwise only when you pass a merchant.
        local full = free <= 1
        return { {
            key = "merchant", optional = not full or nil, weight = full and 0.8 or 1.2, points = points,
            title = "Merchant",
            text = string.format("%sSell %d item(s) (%s) at a merchant", full and "Bags full: " or "", count, money(value)),
            details = { free <= 3 and string.format("Your bags are nearly full (%d free).", free)
                            or "Enough to sell to be worth a short detour.",
                        full and "Full bags lose loot: planned even if it's a detour."
                            or "Only planned when a merchant is roughly on your way (passing a town)." },
        } }
    end,
})

ns:On("MERCHANT_CLOSED", function() if ns.nav then ns.nav:Collect() end end)
