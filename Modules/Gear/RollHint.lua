-- Need or Greed? Flow's verdict on the loot roll window.
--
-- "When loot drops in a dungeon it would be nice to have our upgrade
-- indicators, like in our inventory and at vendors, so I can easily tell if
-- I should roll Need or Greed." (0.35.212)
--
-- The same verdict as the bag icons (Gear/Score.lua: at least +0.5 for your
-- levelling role, and something you can wear): a line on the game's roll
-- window, green "Flow: upgrade +2.1: Need" or grey "Flow: not an upgrade:
-- Greed", and for an upgrade one line in chat too, since the roll window can
-- be gone in a moment. Flow never rolls for you.
--
-- Flow only adds a line of text to the game's window: it doesn't move, show,
-- hide or click anything of it. "Roll hints" in Flow Settings (In a group)
-- turns it off. /flow roll <item link> says the verdict for any item.

local _, ns = ...
local R = {}
ns.rollHint = R

R.MIN_GAIN = 0.5   -- as the bag icons: below this it isn't called an upgrade

function R.On() return not (ns.db.gear and ns.db.gear.rollHints == false) end

-- Pure: the verdict. cmp: ns.gear:Compare's ({ canUse, diffs = { [role] = n } })
-- or nil (not gear, or not loaded). -> { roll = "need" | "greed", text, r, g, b } or nil.
function R.Verdict(cmp, role, minGain)
    if not cmp then return nil end
    if not (cmp.canUse or cmp.needsTraining) then
        return { roll = "greed", text = "you can't wear it: Greed", r = 0.7, g = 0.7, b = 0.7 }
    end
    local gain = cmp.diffs and cmp.diffs[role or "dps"]
    if gain and gain >= (minGain or R.MIN_GAIN) then
        -- (F-005) An upgrade once you train its weapon skill: the bags keep
        -- it for the weapon master, so the roll says Need too.
        local train = (not cmp.canUse) and (" once you train " .. (cmp.skill or "its weapon skill")) or ""
        return { roll = "need", text = string.format("upgrade +%.1f%s: Need", gain, train), gain = gain,
                 needsTraining = not cmp.canUse or nil, r = 0.3, g = 1, b = 0.3 }
    end
    if not cmp.canUse then
        return { roll = "greed", text = "you can't wear it yet: Greed", r = 0.7, g = 0.7, b = 0.7 }
    end
    return { roll = "greed", text = "not an upgrade: Greed", r = 0.7, g = 0.7, b = 0.7 }
end

-- The verdict for an item link, and the comparison it came from (for the
-- spec marks).
function R.Judge(link)
    if not (link and ns.gear and ns.gear.Compare) then return nil end
    local ok, cmp = pcall(ns.gear.Compare, ns.gear, link)
    if not ok then return nil end
    return R.Verdict(cmp, ns.LevelingRole and ns:LevelingRole() or "dps"), cmp
end
function R.For(link) return (R.Judge(link)) end

-- Pure: what becomes of it if it isn't an upgrade (0.35.318: "the major up
-- arrow to tell me if it's an upgrade item or a vendor item"): "need" (an
-- upgrade), "de" (you can disenchant it: the roll offers it), "sell" (it
-- binds when picked up, so no auction; or the vendor pays as well), or
-- "ah" (the auction house, by the same rule as your bags: D.AuctionOrVendor).
--   bop: binds on pickup; canDE: the roll lets you disenchant it;
--   ahPrice, vendorPrice: copper (nil: not known); vendorUnpriced: the setting
function R.Fate(v, bop, canDE, ahPrice, vendorPrice, vendorUnpriced)
    if not v then return nil end
    if v.roll == "need" then return "need" end
    if canDE then return "de" end
    if bop then return "sell" end
    local D = ns.disposition
    local d = D and D.AuctionOrVendor and D.AuctionOrVendor(ahPrice, vendorPrice, "loot", vendorUnpriced, tostring)
    return d and d.action or "sell"
end
R.FATE_WORDS = { sell = "then vendor it", ah = "then the auction house", de = "then disenchant it" }

-- The game's roll windows showing this roll (GroupLootFrame1..4 on this
-- kind of client; a container's children on newer ones).
local function framesFor(rollID)
    local out = {}
    for i = 1, (NUM_GROUP_LOOT_FRAMES or 4) do
        local f = _G["GroupLootFrame" .. i]
        if f and f.rollID == rollID then out[#out + 1] = f end
    end
    local c = _G.GroupLootContainer
    if #out == 0 and c and c.GetChildren then
        for _, f in ipairs({ c:GetChildren() }) do
            if f.rollID == rollID then out[#out + 1] = f end
        end
    end
    return out
end

-- Marks on the roll window's item, as on your bags (0.35.318: "the up arrows
-- for spec upgrades, and the major up arrow ... is not showing up when we're
-- rolling. On the actual rolling icon, are you not able to put those
-- graphics on those images?"). Until now the arrow was a picture of the roll
-- window itself, and the item's picture is a frame of its own, drawn over
-- it: the arrow was under the item. Now they're on a frame of Flow's laid
-- over the item's picture:
--   top left, the big green arrow for an upgrade (and how much better), or
--   what Flow would do with it: the gold coin (vendor), the auctioneer's mark
--   (auction house), DE (disenchant);
--   along the bottom, the spec marks (up, down or the same, per spec).
-- They take no clicks: the item is hovered and the buttons pressed as always.
R.ARROW = 22
-- Pure: does this verdict get the arrow, and its figure ("+2.1").
function R.ArrowFor(v)
    if not (v and v.roll == "need") then return false, "" end
    return true, v.gain and string.format("+%.1f", v.gain) or ""
end
-- The item's picture on the roll window (its own frame), or the window.
function R.IconHost(f)
    if f.IconFrame then return f.IconFrame, "IconFrame" end
    local ic = f.Icon or f.icon
    if ic and ic.GetParent and ic:GetParent() ~= f then return ic:GetParent(), "the icon's frame" end
    return f, "the roll window"
end
local function overlay(f)
    if f.FlowRollMarks then return f.FlowRollMarks end
    local host, which = R.IconHost(f)
    local o = CreateFrame("Frame", nil, host)
    o:SetAllPoints(host)
    o:SetFrameLevel(host:GetFrameLevel() + 10)
    o:EnableMouse(false)
    o.which = which
    o.arrow = o:CreateTexture(nil, "OVERLAY", nil, 2)
    o.arrow:SetSize(R.ARROW, R.ARROW)
    o.arrow:SetPoint("TOPLEFT", -6, 6)
    local ok = o.arrow.SetAtlas and pcall(o.arrow.SetAtlas, o.arrow, "bags-greenarrow")
    if not ok then o.arrow:SetColorTexture(0.2, 1, 0.2, 0.9); o.arrow:SetSize(10, 10) end
    o.gain = o:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    o.gain:SetPoint("LEFT", o.arrow, "RIGHT", -2, 0)
    o.gain:SetTextColor(0.3, 1, 0.3)
    o.coin = o:CreateTexture(nil, "OVERLAY", nil, 2)
    o.coin:SetSize(16, 16)
    o.coin:SetPoint("TOPLEFT", -2, 2)
    o.coin:SetTexture("Interface\\MoneyFrame\\UI-GoldIcon")
    o.ah = o:CreateTexture(nil, "OVERLAY", nil, 2)
    o.ah:SetSize(17, 17)
    o.ah:SetPoint("TOPLEFT", -3, 3)
    o.ahOk = ns.bagIcons and ns.bagIcons.SetAuctionIcon and ns.bagIcons.SetAuctionIcon(o.ah) or false
    o.letters = o:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    o.letters:SetPoint("TOPLEFT", 2, -2)
    o.specs = ns:SpecBadge(o, 11)
    o.specs:SetPoint("BOTTOMRIGHT", -1, 1)
    f.FlowRollMarks = o
    return o
end

-- Paints the marks. v: R.Verdict's; fate: R.Fate's; cmp: the comparison
-- (its diffs per spec), or nil.
function R.Paint(f, v, fate, cmp)
    local o = overlay(f)
    local show, gain = R.ArrowFor(v)
    o.arrow:SetShown(show)
    o.gain:SetText(show and gain or "")
    o.coin:SetShown(fate == "sell")
    o.ah:SetShown(fate == "ah" and o.ahOk)
    local letters = (fate == "de" and "DE") or (fate == "ah" and not o.ahOk and "AH") or ""
    o.letters:SetText(letters)
    if fate == "de" then o.letters:SetTextColor(0.75, 0.5, 1.0) else o.letters:SetTextColor(0.4, 0.8, 1.0) end
    local diffs = ns.gear.MarkDiffs(cmp)
    if diffs then o.specs:Set(diffs) else o.specs:Hide() end
    return o
end

local function mark(f, v, fate, cmp)
    pcall(R.Paint, f, v, fate, cmp)
    if not f.FlowRollHint then
        local t = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        t:SetPoint("BOTTOM", f, "TOP", 0, 2)
        f.FlowRollHint = t
    end
    local words = fate and R.FATE_WORDS[fate]
    f.FlowRollHint:SetText(v and ("Flow: " .. v.text .. (words and (", " .. words) or "")) or "")
    if v then f.FlowRollHint:SetTextColor(v.r, v.g, v.b) end
end

-- What the roll says about the item: binds on pickup? can you disenchant it?
local function rollInfo(rollID)
    if not GetLootRollItemInfo then return nil, nil end
    local ok, _, _, _, _, bop, _, _, canDE = pcall(GetLootRollItemInfo, rollID)
    if not ok then return nil, nil end
    local Safe = ns.api.Safe
    return Safe(bop) and true or false, Safe(canDE) and true or false
end

R.said = {}   -- [rollID] = true: the chat line went out
local function onRoll(rollID)
    if not R.On() or not GetLootRollItemLink then return end
    local link = GetLootRollItemLink(rollID)
    local v, cmp = R.Judge(link)
    local bop, canDE = rollInfo(rollID)
    local D = ns.disposition
    local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local vendor = link and get and select(11, get(link)) or nil
    local fate = R.Fate(v, bop, canDE, D and D.AuctionPrice and D:AuctionPrice(link) or nil, vendor,
        D and D.VendorUnpriced and D.VendorUnpriced())
    local frames = framesFor(rollID)
    for _, f in ipairs(frames) do pcall(mark, f, v, fate, cmp) end
    local o = frames[1] and frames[1].FlowRollMarks
    ns:Log("gear", string.format("loot roll %s: %s -> %s%s; marked %d roll window(s)%s", tostring(rollID), tostring(link),
        v and v.text or "no verdict (not gear, or not loaded yet)", fate and fate ~= "need" and (", " .. fate) or "",
        #frames, o and (" on " .. tostring(o.which)) or ""))
    if v and v.roll == "need" and not R.said[rollID] then
        R.said[rollID] = true
        ns:Print(string.format("%s is an upgrade for you (+%.1f%s): Flow suggests Need. (It never rolls for you.)", tostring(link),
            v.gain or 0, v.needsTraining and (", once you train " .. tostring(cmp and cmp.skill or "its weapon skill")) or ""))
    end
end
ns:On("START_LOOT_ROLL", function(rollID)
    rollID = ns.api.Safe(rollID)
    if not rollID then return end
    -- (The window fills a moment after the event; the item may load later still.)
    for _, wait in ipairs({ 0.1, 1 }) do
        if C_Timer then C_Timer.After(wait, function() pcall(onRoll, rollID) end) end
    end
end)

ns.commands.roll = function(arg)
    local link = (arg or ""):match("(|c.-|h|r)") or (arg or ""):match("(|H.-|h.-|h)")
    if not link then ns:Print("/flow roll <shift-click an item>: is it an upgrade for you (Need) or not (Greed)? Flow only says; it never rolls.") return end
    local v = R.For(link)
    ns:Print(link .. ": " .. (v and v.text or "not gear Flow can judge (or not loaded yet)"))
end

if ns.settings and ns.settings.AddCheck then
    ns.settings:AddCheck({
        group = "group",
        label = "Roll hints: Need or Greed on loot rolls",
        tip = "When a roll comes up, Flow writes on the roll window whether the item is an upgrade for you (Need) or not (Greed), "
            .. "by the same scores as the icons in your bags. It never rolls for you.",
        get = function() return R.On() end,
        set = function(on)
            ns.db.gear = ns.db.gear or {}
            ns.db.gear.rollHints = on and true or false
        end,
    })
end
