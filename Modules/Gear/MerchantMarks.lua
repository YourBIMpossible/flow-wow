-- Upgrade marks on a vendor's items: "when I go to an item vendor it should
-- show me if the items are upgrades (same as inventory, per spec)".
--
-- Each piece of gear a vendor sells gets the same spec badge as your bag
-- slots and quest rewards (Gear/SpecBadge.lua): one small icon per spec with
-- a green arrow up (better than what that spec wears), a red one down
-- (worse) or a grey dash (the same). Gear you can't use gets none. When
-- something for sale is better for the spec you're levelling as, Flow says
-- so once in chat, with the price.
--
-- Flow only adds a badge to the vendor's own item buttons (a child frame)
-- and reads what's for sale; it calls nothing of the vendor window's. The
-- page follows the window through a secure hook (hooksecurefunc), which
-- doesn't taint.

local _, ns = ...
local G = ns.gear
local MM = {}
ns.merchantMarks = MM

MM.BUTTONS = 12   -- item buttons a vendor page can have (10 for sale, 12 for buyback)

-------------------------------------------------------------------------------
-- Pure parts
-------------------------------------------------------------------------------

-- The vendor's item number behind button i of a page.
function MM.Index(page, perPage, i)
    return ((page or 1) - 1) * (perPage or 10) + i
end

-- What to put on a button: the score differences per spec, or nil for no
-- badge (not gear, not loaded yet, or gear you can't use even once you
-- train a weapon skill: F-005).
function MM.Diffs(cmp)
    return G.MarkDiffs(cmp)
end

-- Is it an upgrade for the spec you level as? The gain, or nil.
function MM.UpgradeFor(cmp, role)
    local d = MM.Diffs(cmp)
    local gain = d and d[role]
    if gain and ns.SpecTrend(gain) == "up" then return gain end
    return nil
end

-- "for sale here, better for you: [Item] (+3 DPS, 2s 40c)": the line said
-- once a vendor. ups: { { link, gain, price, afford } }.
function MM.Line(ups, roleLabel, money)
    if #ups == 0 then return nil end
    local bits = {}
    for _, u in ipairs(ups) do
        bits[#bits + 1] = string.format("%s (+%d %s%s%s)", u.link, u.gain + 0.5, roleLabel or "",
            u.price and (", " .. money(u.price)) or "", (u.price and u.afford == false) and ", more than you have" or "")
    end
    return "for sale here, better than what you wear: " .. table.concat(bits, "; ")
end

-------------------------------------------------------------------------------
-- The vendor window
-------------------------------------------------------------------------------

local function button(i) return _G["MerchantItem" .. i .. "ItemButton"] end

local function badgeFor(b)
    if b.flowSpecs then return b.flowSpecs end
    local anchor = b.icon or b.Icon or _G[(b:GetName() or "") .. "IconTexture"] or b
    local badge = ns:SpecBadge(b, 10)
    badge:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", 1, 1)
    b.flowSpecs = badge
    return badge
end

local function hideAll()
    for i = 1, MM.BUTTONS do
        local b = button(i)
        if b and b.flowSpecs then b.flowSpecs:Hide() end
    end
end

-- What one vendor item costs (copper), or nil.
local function priceOf(index)
    if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
        local ok, info = pcall(C_MerchantFrame.GetItemInfo, index)
        if ok and type(info) == "table" then return info.price end
    end
    if GetMerchantItemInfo then
        local ok, _, _, price = pcall(GetMerchantItemInfo, index)
        if ok and type(price) == "number" then return price end
    end
end

local said = {}        -- [item link] = true: already told this session
local retried = false
MM.marked = 0          -- (diagnostics, tests)

local function update()
    if not (MerchantFrame and MerchantFrame:IsShown() and GetMerchantItemLink) then return end
    if ns.db.gear and ns.db.gear.enabled == false then hideAll() return end
    -- The buyback tab shows other items on the same buttons: no badges there.
    if (MerchantFrame.selectedTab or 1) ~= 1 then hideAll() return end
    local perPage = MERCHANT_ITEMS_PER_PAGE or 10
    local page = MerchantFrame.page or 1
    local total = GetMerchantNumItems and GetMerchantNumItems() or 0
    local role = ns:LevelingRole()
    local money = GetMoney and GetMoney() or 0
    local missing, marked, ups = false, 0, {}
    for i = 1, MM.BUTTONS do
        local b = button(i)
        if b then
            local index = MM.Index(page, perPage, i)
            local link = (i <= perPage and index <= total) and GetMerchantItemLink(index) or nil
            local cmp = link and G:Compare(link)
            -- (Not loaded yet reads as "not gear": looked at again in a moment.)
            if link and not cmp then missing = true end
            local diffs = MM.Diffs(cmp)
            if diffs then
                badgeFor(b):Set(diffs)
                marked = marked + 1
                local gain = MM.UpgradeFor(cmp, role)
                if gain and not said[link] then
                    said[link] = true
                    local price = priceOf(index)
                    ups[#ups + 1] = { link = link, gain = gain, price = price, afford = price and price <= money }
                end
            elseif b.flowSpecs then
                b.flowSpecs:Hide()
            end
        end
    end
    MM.marked = marked
    local line = MM.Line(ups, ns.ROLE_LABEL and ns.ROLE_LABEL[role] or role, ns.Money)
    if line then ns:Print(line) end
    if missing and not retried then
        retried = true
        C_Timer.After(0.5, function() pcall(update) end)
    end
end

local function schedule()
    retried = false
    C_Timer.After(0, function() pcall(update) end)
end
MM._update = update   -- (tests)

ns:On("MERCHANT_SHOW", schedule)
ns:On("MERCHANT_UPDATE", schedule)
ns:On("MERCHANT_CLOSED", hideAll)
-- A new page, or the buyback tab: the window draws itself again.
if type(MerchantFrame_Update) == "function" then hooksecurefunc("MerchantFrame_Update", schedule) end
-- You put something on: what's better than it changes.
ns:On("PLAYER_EQUIPMENT_CHANGED", function()
    if MerchantFrame and MerchantFrame:IsShown() then schedule() end
end)
-- (Where the window has no such function to hook: its page buttons.)
local hookedPages = false
ns:On("MERCHANT_SHOW", function()
    if hookedPages then return end
    hookedPages = true
    for _, name in ipairs({ "MerchantNextPageButton", "MerchantPrevPageButton", "MerchantFrameTab1", "MerchantFrameTab2" }) do
        local b = _G[name]
        if b and b.HookScript then pcall(b.HookScript, b, "OnClick", schedule) end
    end
end)
