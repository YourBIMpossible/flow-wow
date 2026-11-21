-- Marks on your bag slots (Blizzard bags; other bag addons aren't covered).
-- Two corners, each for one kind of mark (0.35.317: "the icon in the top
-- right for what the type of the item is, and then up in the top left, what
-- it's going to do ... the auctioneer icon, however, is on the right. I think
-- that one should go on the left, and we should make this a generalization"):
--   top left, what Flow will do with it (group "action"):
--     (o) your current route step uses it, the bank (Flow Banker puts it away
--     at your next visit), the gold coin (sell), the auctioneer's mark (the
--     auction house), DE (disenchant)
--   top right, what it is (group "kind"):
--     a quest item "!", a profession's tool or material (its icon)
--   bottom row (gear): one icon per spec, with a mark above: green arrow up =
--     better than that spec's gear, red arrow down = worse, grey dash = same
-- Every mark is a registration, ns:Register("bagMark", key, { group, order,
-- build, wants, paint, x, y }): its group decides its corner (B.CORNER), and
-- in each corner the first mark (lowest order) that wants the item shows. A
-- new mark is a new registration, in the corner its meaning belongs to.
-- The item tooltip says what Flow would do and why.  /flow bags on|off

local _, ns = ...
local D = ns.disposition
local B = {}
ns.bagIcons = B

-- The item your current route step wants you to use (a recipe to learn...).
function B.FocusItem()
    local c = ns.nav and ns.nav.current
    return c and c.goal and c.goal.useItem or nil
end

-- What goes into your bank at your next visit (Flow Banker's own list, so the
-- icon and the Deposit button always agree; your choices in its window count).
-- Pure: the list's rows as a set. rows: { { id } } -> { [itemID] = true }
function B.BankSet(rows)
    local set = {}
    for _, r in ipairs(rows or {}) do
        if type(r) == "table" and r.id then set[r.id] = true end
    end
    return set
end
-- Pure: does this bag item get the bank icon? Never the item your current
-- step uses (that one has the (o) in the same corner).
function B.ToBank(id, set, focus)
    if not (id and set and set[id]) then return false end
    return not (focus and focus == id)
end
B.bankSet = {}
function B.RefreshBankSet()
    local K = ns.banker
    local ok, rows = pcall(function() return K and K.List and K.List() or {} end)
    B.bankSet = B.BankSet(ok and rows or {})
    return B.bankSet
end
B.BANK_TIP = "Flow Banker: goes into your bank at your next visit (Deposit there; change it in the Flow Banker)."

-- Puts the auctioneer's picture on a texture. -> true when the game has one.
B.AH_ATLASES = { "Auctioneer", "auctioneer" }
B.AH_FILE = "Interface\\Minimap\\Tracking\\Auctioneer"
function B.SetAuctionIcon(tex)
    if tex.SetAtlas and C_Texture and C_Texture.GetAtlasInfo then
        for _, name in ipairs(B.AH_ATLASES) do
            if C_Texture.GetAtlasInfo(name) and pcall(tex.SetAtlas, tex, name) then return true end
        end
    end
    tex:SetTexture(B.AH_FILE)
    return tex:GetTexture() ~= nil
end

-------------------------------------------------------------------------------
-- The two corners, and which mark each shows.
-------------------------------------------------------------------------------

-- Where a group's marks sit on the slot (x, y: the usual offset; a mark can
-- give its own, letters sit a little inside the edge).
B.CORNER = {
    action = { point = "TOPLEFT", x = -2, y = 2 },     -- what Flow will do with it
    kind   = { point = "TOPRIGHT", x = -1, y = -1 },   -- what it is
}

-- The marks, by their order (built once: every registration is made as the
-- files load, before any bag is painted).
local markList
function B.MarkList()
    if markList then return markList end
    local list = {}
    for key, def in ns:Each("bagMark") do
        list[#list + 1] = { key = key, group = def.group, order = def.order or 50, wants = def.wants, def = def }
    end
    table.sort(list, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return a.key < b.key
    end)
    markList = list
    return list
end

-- Pure: the mark each corner shows: { [group] = key }. list: marks as
-- B.MarkList gives them ({ key, group, order, wants }), lowest order first;
-- ctx: { v = Flow's decision (D:Decide: action, icon, reason, item), id,
-- focus = your current step uses it, bank = Flow Banker puts it away }.
function B.PickMarks(list, ctx)
    local out = {}
    for _, m in ipairs(list or {}) do
        if B.CORNER[m.group] and not out[m.group] and m.wants then
            local ok, want = pcall(m.wants, ctx)
            if ok and want then out[m.group] = m.key end
        end
    end
    return out
end

-------------------------------------------------------------------------------
-- The marks. Top left, what Flow will do with it (group "action").
-------------------------------------------------------------------------------

local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local function letters(m, text, r, g, b)
    local s = m:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    s:SetText(text)
    s:SetTextColor(r, g, b)
    return s
end
local function icon(m, size)
    local t = m:CreateTexture(nil, "OVERLAY")
    t:SetSize(size or 14, size or 14)
    return t
end

-- Flow's target marker (o) in the route colour: your current step wants you
-- to use this ("Learn Brilliant Smallfish: use the recipe in your bags").
ns:Register("bagMark", "step", { group = "action", order = 10, x = -3, y = 3,
    build = function(m)
        local f = CreateFrame("Frame", nil, m)
        f:SetSize(14, 14)
        f:SetFrameLevel(m:GetFrameLevel() + 2)
        local function disc(sub, inset)
            local t = f:CreateTexture(nil, "OVERLAY", nil, sub)
            t:SetTexture(CIRCLE)
            t:SetPoint("TOPLEFT", inset, -inset); t:SetPoint("BOTTOMRIGHT", -inset, inset)
            return t
        end
        f.edge, f.ring, f.hole, f.dot = disc(1, -1), disc(2, 0), disc(3, 2), disc(4, 4)
        f.edge:SetVertexColor(0, 0, 0, 0.9)
        f.hole:SetVertexColor(0.05, 0.05, 0.08, 1)
        return f
    end,
    wants = function(ctx) return ctx.focus end,
    paint = function(f)
        local c = ns.theme.route
        f.ring:SetVertexColor(c[1], c[2], c[3], 1)
        f.dot:SetVertexColor(c[1], c[2], c[3], 1)
    end })

-- The bank: Flow Banker puts it in at your next visit (0.35.300).
ns:Register("bagMark", "bank", { group = "action", order = 20,
    build = function(m)
        local t = icon(m)
        local okAtlas = t.SetAtlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("Banker")
            and pcall(t.SetAtlas, t, "Banker")
        if not okAtlas then t:SetTexture("Interface\\Icons\\INV_Misc_Bag_10") end
        return t
    end,
    wants = function(ctx) return ctx.bank end })

-- Sell: the gold coin.
ns:Register("bagMark", "sell", { group = "action", order = 30, x = -1, y = 1,
    build = function(m)
        local t = icon(m)
        t:SetTexture("Interface\\MoneyFrame\\UI-GoldIcon")
        return t
    end,
    wants = function(ctx) return ctx.v.action == "sell" end })

-- The auction house: the game's auctioneer mark (0.35.304), or the letters
-- AH on a game without that picture (the mark after it).
ns:Register("bagMark", "ah", { group = "action", order = 40, x = -2, y = 2,
    build = function(m)
        local t = icon(m, 15)
        B.ahPicture = B.SetAuctionIcon(t)
        return t
    end,
    wants = function(ctx) return ctx.v.action == "ah" and B.ahPicture == true end })
ns:Register("bagMark", "ahLetters", { group = "action", order = 41, x = 2, y = -2,
    build = function(m) return letters(m, "AH", 0.4, 0.8, 1.0) end,
    wants = function(ctx) return ctx.v.action == "ah" end })

-- Disenchant.
ns:Register("bagMark", "de", { group = "action", order = 50, x = 2, y = -2,
    build = function(m) return letters(m, "DE", 0.75, 0.5, 1.0) end,
    wants = function(ctx) return ctx.v.action == "de" end })

-------------------------------------------------------------------------------
-- Top right, what it is (group "kind"): a quest item's "!", a profession's
-- icon for its tools and materials (Disposition.lua's icon for the reason
-- it's kept).
-------------------------------------------------------------------------------

ns:Register("bagMark", "what", { group = "kind", order = 10,
    build = function(m) return icon(m) end,
    wants = function(ctx) return ctx.v.icon ~= nil end,
    paint = function(t, ctx) t:SetTexture(ctx.v.icon) end })

-------------------------------------------------------------------------------
-- Painting a slot.
-------------------------------------------------------------------------------

local function marks(button)
    if button.flowMarks then return button.flowMarks end
    local m = CreateFrame("Frame", nil, button)
    m:SetAllPoints()
    m:SetFrameLevel(button:GetFrameLevel() + 5)
    -- Bottom: the spec badge (Gear/SpecBadge.lua): an icon per spec with an
    -- arrow right above it (better / worse / same as that spec's gear).
    m.specs = ns:SpecBadge(m, 10)
    m.specs:SetPoint("BOTTOMRIGHT", -1, 1)
    m.marks = {}
    for _, e in ipairs(B.MarkList()) do
        local c = B.CORNER[e.group]
        local ok, r = pcall(e.def.build, m)
        if c and ok and r then
            r:ClearAllPoints()
            r:SetPoint(c.point, m, c.point, e.def.x or c.x, e.def.y or c.y)
            r:Hide()
            m.marks[e.key] = r
        end
    end
    button.flowMarks = m
    return m
end

local function clear(button)
    local m = button.flowMarks
    if not m then return end
    m.specs:Hide()
    for _, r in pairs(m.marks) do r:Hide() end
end

local function paint(button, bag, slot)
    local link = bag and slot and (C_Container and C_Container.GetContainerItemLink or GetContainerItemLink)(bag, slot)
    if not link or not ns.db.bags.enabled then clear(button) return end
    local v = D:Decide(bag, slot, link)
    if not v then clear(button) return end
    local m = marks(button)
    local id = tonumber(link:match("item:(%d+)"))
    local focusItem = B.FocusItem()
    local ctx = { v = v, id = id, focus = id ~= nil and id == focusItem }
    ctx.bank = v.action == "keep" and B.ToBank(id, B.bankSet, focusItem)
    local list = B.MarkList()
    local pick = B.PickMarks(list, ctx)
    for _, e in ipairs(list) do
        local r = m.marks[e.key]
        if r then
            local on = pick[e.group] == e.key
            if on and e.def.paint then pcall(e.def.paint, r, ctx) end
            r:SetShown(on)
        end
    end
    local diffs = ns.gear.MarkDiffs(v.item.gear)
    if diffs then m.specs:Set(diffs) else m.specs:Hide() end
end

-- Calls fn(button, bag, slot) for every visible Blizzard bag slot button.
local function eachButton(fn)
    local frames = {}
    if ContainerFrameCombinedBags then frames[#frames + 1] = ContainerFrameCombinedBags end
    for i = 1, (NUM_CONTAINER_FRAMES or 13) do
        local f = _G["ContainerFrame" .. i]
        if f then frames[#frames + 1] = f end
    end
    for _, f in ipairs(frames) do
        if f:IsShown() then
            if f.EnumerateValidItems then
                for _, b in f:EnumerateValidItems() do
                    fn(b, b.GetBagID and b:GetBagID() or f:GetID(), b:GetID())
                end
            elseif f.Items then
                for _, b in ipairs(f.Items) do
                    if b:IsShown() then fn(b, b.GetBagID and b:GetBagID() or f:GetID(), b:GetID()) end
                end
            elseif f:GetName() then
                local bag = f:GetID()
                for j = 1, 36 do
                    local b = _G[f:GetName() .. "Item" .. j]
                    if b and b:IsShown() then fn(b, bag, b:GetID()) end
                end
            end
        end
    end
end

local dirty, acc, wasOpen = true, 0, false
local function refresh()
    B.RefreshBankSet()
    eachButton(function(b, bag, slot) pcall(paint, b, bag, slot) end)
end

ns:OnLoad(function(saved)
    saved.bags = saved.bags or {}
    if saved.bags.enabled == nil then saved.bags.enabled = true end
    local driver = CreateFrame("Frame")
    driver:SetScript("OnUpdate", function(_, dt)
        acc = acc + dt
        if acc < 0.3 then return end
        acc = 0
        -- Repaint when bags open, when something changed, and now and then
        -- while open (item info can arrive late).
        local open = (ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsShown())
            or (ContainerFrame1 and ContainerFrame1:IsShown())
        if open and not wasOpen then dirty = true end
        local focus = B.FocusItem()
        if focus ~= B.lastFocus then B.lastFocus = focus; dirty = true end
        wasOpen = open
        if dirty or (open and math.random() < 0.1) then
            dirty = false
            refresh()
        end
    end)
end)

for _, ev in ipairs({ "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_LEVEL_UP",
                      "EQUIPMENT_SETS_CHANGED", "GET_ITEM_INFO_RECEIVED", "BAG_OPEN" }) do
    ns:On(ev, function() dirty = true end)
end

function B.MarkDirty() dirty = true end

ns.commands.bags = function(arg)
    arg = (arg or ""):lower()
    if arg == "on" or arg == "off" then
        ns.db.bags.enabled = (arg == "on")
        dirty = true
        ns:Print("bag icons " .. arg)
    else
        ns:Print("/flow bags on|off. Top left, what Flow will do with it: (o) your current step uses it, the bank icon (goes into your bank at your next visit), "
            .. "the gold coin (sell), the auctioneer's mark (auction house), DE (disenchant). Top right, what it is: a quest item's !, a profession's icon. "
            .. "Bottom: spec icons, green arrow up = better, red down = worse, grey dash = same.")
    end
end

-- Tooltip line for items in your bags: what Flow would do, and why.
local ACTION_COLOR = { equip = "66ff66", keep = "ffd200", sell = "ffbf33", ah = "66ccff", de = "bf80ff" }
ns:Register("itemTip", "disposition", function(tooltip, link)
    if not ns.db.bags.enabled then return end
    local bag, slot, l = D:FindInBags(link)
    if not bag then return end
    local v = D:Decide(bag, slot, l)
    if not v then return end
    local id = tonumber(tostring(l):match("item:(%d+)"))
    local toBank = v.action == "keep" and B.ToBank(id, B.bankSet, B.FocusItem())
    tooltip:AddLine(B.TipLine(D.LABEL[v.action] or v.action, ACTION_COLOR[v.action], v.reason, toBank), 0.9, 0.9, 0.9, true)
    tooltip:Show()
end)

-- Pure: Flow's one line on an item's tooltip (0.35.347: "look at how many
-- Flow tooltips there are, we need to consolidate those"). It was three:
-- which quest it's for, what Flow does with it and every reason, and that it
-- goes to the bank. Now one: what Flow does, where it goes, the reason that
-- matters.
--   Flow: Keep, to your bank at the next visit: for your quest: The Power to Destroy...
function B.TipLine(label, color, reason, toBank)
    local short = D.ShortReason(reason)
    return string.format("Flow: |cff%s%s|r%s%s", color or "ffffff", tostring(label),
        toBank and ", to your bank at the next visit" or "", short ~= "" and (": " .. short) or "")
end
