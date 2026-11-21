-- What to do with each item in your bags: equip, keep, sell, auction house
-- (AH) or disenchant (DE). Used by the bag icons and the vendor panel.
--
-- Rules are registered and checked in order (lowest `order` first); the
-- first rule that returns a verdict decides. Add your own:
--   ns:Register("disposition", key, { order = n, check = function(item) -> verdict end })
-- item   = { bag, slot, link, id, quality, classID, sellPrice, bound, minLevel, gear = Compare result }
-- verdict = { action = "equip"|"keep"|"sell"|"ah"|"de", reason = "..." }

local _, ns = ...
local D = {}
ns.disposition = D

local ACTION_LABEL = { equip = "Equip", keep = "Keep", sell = "Sell", ah = "Auction house", de = "Disenchant" }
D.LABEL = ACTION_LABEL

-------------------------------------------------------------------------------
-- Bag helpers
-------------------------------------------------------------------------------

local CC = C_Container
local numSlots = (CC and CC.GetContainerNumSlots) or GetContainerNumSlots
local linkOf = (CC and CC.GetContainerItemLink) or GetContainerItemLink

function D:EachBagItem(fn)
    if not numSlots then return end
    for bag = 0, 4 do
        for slot = 1, numSlots(bag) or 0 do
            local link = linkOf(bag, slot)
            if link then fn(bag, slot, link) end
        end
    end
end

-- Is the item in this bag slot soulbound? true/false, or nil if unknown.
function D:IsBound(bag, slot)
    if C_Item and C_Item.IsBound and ItemLocation then
        local ok, r = pcall(C_Item.IsBound, ItemLocation:CreateFromBagAndSlot(bag, slot))
        if ok then return r end
    end
    if CC and CC.GetContainerItemInfo then
        local info = CC.GetContainerItemInfo(bag, slot)
        if info and info.isBound ~= nil then return info.isBound end
    end
    return nil
end

local function itemInfo(link)
    local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local _, _, quality, _, minLevel, _, _, _, equipLoc, _, sellPrice, classID, subclassID = get(link)
    return quality, minLevel, sellPrice, classID, equipLoc, subclassID
end

-- Icons shown in bags for "keep" reasons.
D.ICON_QUEST = "Interface\\GossipFrame\\AvailableQuestIcon"
local PROF_ICON = {
    ["Mining"] = "Interface\\Icons\\Trade_Mining",
    ["Blacksmithing"] = "Interface\\Icons\\Trade_BlackSmithing",
    ["First Aid"] = "Interface\\Icons\\Spell_Holy_SealOfSacrifice",
    ["Cooking"] = "Interface\\Icons\\INV_Misc_Food_15",
    ["Fishing"] = "Interface\\Icons\\Trade_Fishing",
    ["Tailoring"] = "Interface\\Icons\\Trade_Tailoring",
    ["Leatherworking"] = "Interface\\Icons\\Trade_LeatherWorking",
    ["Alchemy"] = "Interface\\Icons\\Trade_Alchemy",
    ["Engineering"] = "Interface\\Icons\\Trade_Engineering",
    ["Enchanting"] = "Interface\\Icons\\Trade_Engraving",
    ["Herbalism"] = "Interface\\Icons\\Trade_Herbalism",
    ["Skinning"] = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01",
}
D.PROF_ICON = PROF_ICON

-- Trade goods (item class 7) subclass -> professions that use that kind of material.
local MATERIAL = {
    [1] = { "Engineering" }, [2] = { "Engineering" }, [3] = { "Engineering" },
    [5] = { "First Aid", "Tailoring" },
    [6] = { "Leatherworking" },
    [7] = { "Mining", "Blacksmithing", "Engineering" },
    [8] = { "Cooking" },
    [9] = { "Alchemy" },
    [12] = { "Enchanting" },
}
local MATERIAL_NAME = { [1] = "parts", [2] = "explosives", [3] = "devices", [5] = "cloth",
    [6] = "leather", [7] = "metal & stone", [8] = "meat", [9] = "herbs", [12] = "enchanting materials" }

-- Bag slot holding an item (first match), for tooltips.
function D:FindInBags(link)
    local id = tonumber(link:match("item:(%d+)"))
    local found
    self:EachBagItem(function(bag, slot, l)
        if not found and (l == link or tonumber(l:match("item:(%d+)")) == id) then found = { bag, slot, l } end
    end)
    if found then return found[1], found[2], found[3] end
end

-- Market price from an auction addon if one is installed (Auctionator), else nil.
function D:AuctionPrice(link)
    if Auctionator and Auctionator.API and Auctionator.API.v1 and Auctionator.API.v1.GetAuctionPriceByItemLink then
        local ok, p = pcall(Auctionator.API.v1.GetAuctionPriceByItemLink, "Flow", link)
        if ok and type(p) == "number" then return p end
    end
    -- Flow's own prices from the auction houses you've opened (Items/Auction.lua).
    local id = link and tonumber(link:match("item:(%d+)"))
    return id and ns.auction and ns.auction:Price(id) or nil
end

-------------------------------------------------------------------------------
-- Deciding
-------------------------------------------------------------------------------

local cache = {}
function D:Invalidate() wipe(cache) end

function D:Describe(bag, slot, link)
    local quality, minLevel, sellPrice, classID, _, subclassID = itemInfo(link)
    if quality == nil then return nil end  -- not loaded yet
    return {
        bag = bag, slot = slot, link = link, id = tonumber(link:match("item:(%d+)")),
        name = link:match("%[(.-)%]"),
        quality = quality, minLevel = minLevel or 0, sellPrice = sellPrice or 0, classID = classID,
        subclassID = subclassID,
        bound = self:IsBound(bag, slot),
        gear = ns.gear and ns.gear:Compare(link) or nil,
    }
end

-- Pure: a verdict's reasons, for a tooltip (0.35.347). A keep lists every
-- reason ("vendors won't buy it; quest item; for your quest: X"): the ones
-- that only say what kind of thing it is are dropped when a real one stands
-- beside them ("for your quest: X").
D.PLAIN_REASONS = {
    ["vendors won't buy it"] = true, ["quest item"] = true, ["not gear (materials, food, potions...)"] = true,
}
function D.ShortReason(reason)
    if type(reason) ~= "string" or reason == "" then return "" end
    local real, all = {}, {}
    for part in (reason .. "; "):gmatch("(.-); ") do
        if part ~= "" then
            all[#all + 1] = part
            if not D.PLAIN_REASONS[part] then real[#real + 1] = part end
        end
    end
    if #real == 0 then return all[1] or reason end
    return table.concat(real, "; ")
end

-- Rules whose "keep" is a fallback, not a reason worth listing with others.
local GENERIC = { notGear = true, unneededGear = true }
local sorted
local function rules()
    if not sorted then
        sorted = {}
        for key, r in ns:Each("disposition") do sorted[#sorted + 1] = { key = key, r = r } end
        table.sort(sorted, function(a, b) return (a.r.order or 100) < (b.r.order or 100) end)
    end
    return sorted
end

-- A rule that errors fails safe (F-010): the item is kept, not passed on to
-- a later rule that might sell it, and the error goes to the diagnostics
-- log once per rule per session. D.ruleFailed: rule key -> error (tests).
D.ruleFailed = {}
function D.RuleError(key, err)
    if not D.ruleFailed[key] and ns.Log and ns.db and ns.db.diag then
        D.ruleFailed[key] = tostring(err)
        ns:Log("error", "disposition rule '" .. tostring(key) .. "' failed: " .. tostring(err))
    end
    return { action = "keep", reason = "a Flow check failed (" .. tostring(key) .. "), so it's kept" }
end

-- The rules' verdict for a described item (kept under `key` when given;
-- list = the rules to check, all of them by default).
local function verdictFor(item, key, list)
    list = list or rules()
    for idx, e in ipairs(list) do
        local ok, v = pcall(e.r.check, item)
        if not ok then v = D.RuleError(e.key, v) end
        if v then
            v.rule = e.key
            v.item = item
            -- Keeping it: list every reason, not just the first (Linen Cloth
            -- can be for a class quest AND First Aid bandages).
            if v.action == "keep" and v.reason and not GENERIC[e.key] then
                local reasons, seen = { v.reason }, { [v.reason] = true }
                for j = idx + 1, #list do
                    local e2 = list[j]
                    if not GENERIC[e2.key] then
                        local ok2, w = pcall(e2.r.check, item)
                        if ok2 and w and w.action == "keep" and w.reason and not seen[w.reason] then
                            reasons[#reasons + 1] = w.reason
                            seen[w.reason] = true
                            v.icon = v.icon or w.icon
                        end
                    end
                end
                v.reasons = reasons
                v.reason = table.concat(reasons, "; ")
            end
            if key then cache[key] = v end
            return v
        end
    end
    local v = { action = "keep", reason = "no rule matched", item = item }
    if key then cache[key] = v end
    return v
end
-- (Tests: a verdict from a given rule list, nothing cached.)
function D.VerdictFrom(item, list) return verdictFor(item, nil, list) end

-- Verdict for the item in a bag slot (cached per link + bound state).
function D:Decide(bag, slot, link)
    local key = link .. ":" .. bag .. ":" .. slot
    if cache[key] then return cache[key] end
    local item = self:Describe(bag, slot, link)
    if not item then return nil end
    return verdictFor(item, key)
end

-- Verdict for something you don't have in a bag slot: what's in your bank,
-- by item ID (0.35.341: "Linen Cloth says sell, your First Aid is past it,
-- but it doesn't take it back out of my bank"). The same rules; whether it's
-- soulbound isn't known from here (item.bound is nil, item.away is true).
-- nil while the game hasn't loaded the item.
function D:DecideId(id)
    local key = "id:" .. tostring(id)
    if cache[key] then return cache[key] end
    local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local ok, name, link = pcall(get, id)
    if not (ok and type(name) == "string" and type(link) == "string") then return nil end
    local quality, minLevel, sellPrice, classID, _, subclassID = itemInfo(link)
    if quality == nil then return nil end
    return verdictFor({
        link = link, id = id, name = name, away = true,
        quality = quality, minLevel = minLevel or 0, sellPrice = sellPrice or 0, classID = classID, subclassID = subclassID,
        gear = ns.gear and ns.gear:Compare(link) or nil,
    }, key)
end

-- Let Flow sell something you once bought back (0.35.341: "it says you
-- bought it back before, so now Flow thinks I want to keep it forever, and
-- that's not true"). True when it was on the list.
function D.Forget(id)
    local never = ns.db.sell and ns.db.sell.never
    local was = never and id and never[id] and true or false
    if was then never[id] = nil end
    -- (And a "keep" of your own: Flow's rules decide again.)
    if D.Choice(id) == "keep" then D.SetChoice(id, nil); was = true end
    if was then D:Invalidate() end
    return was
end

for _, ev in ipairs({ "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_LEVEL_UP",
                      "EQUIPMENT_SETS_CHANGED", "SKILL_LINES_CHANGED" }) do
    ns:On(ev, function() D:Invalidate() end)
end

ns:OnLoad(function(saved)
    saved.sell = saved.sell or {}
    saved.sell.never = saved.sell.never or {}
end)
-- Items you bought back: per character. The old shared list goes to the
-- character loaded when it was parked; other characters start their own
-- (F-013: one character's buybacks aren't an alt's).
ns:PerCharacter("sell.never", { once = true, adopt = function(old) return old end })

-- Your own choice for an item (0.35.343): "sell" or "keep", whatever Flow's
-- rules say. "Should we have a way to set 'sell this item', just like we
-- have for 'bank it'?" Set and undone in Flow Banker (To sell, To bank).
ns:OnLoad(function(saved)
    saved.sell = saved.sell or {}
    saved.sell.mine = saved.sell.mine or {}
end)
ns:PerCharacter("sell.mine")
function D.Choice(id)
    local mine = ns.db.sell and ns.db.sell.mine
    return mine and id and mine[id] or nil
end
-- what: "sell", "keep", or nil for Flow's own choice. True when it changed.
function D.SetChoice(id, what)
    if not id or (what ~= nil and what ~= "sell" and what ~= "keep") then return false end
    ns.db.sell.mine = ns.db.sell.mine or {}
    if ns.db.sell.mine[id] == what then return false end
    ns.db.sell.mine[id] = what
    D:Invalidate()
    if ns.bagIcons and ns.bagIcons.MarkDirty then ns.bagIcons.MarkDirty() end
    return true
end
-- Every sell or keep choice of yours, and every buy-back, forgotten: Flow
-- decides again (0.35.348). -> how many there were.
function D.ResetChoices()
    local n = 0
    for _, list in ipairs({ ns.db.sell and ns.db.sell.mine or {}, ns.db.sell and ns.db.sell.never or {} }) do
        for _ in pairs(list) do n = n + 1 end
        wipe(list)
    end
    D:Invalidate()
    if ns.bagIcons and ns.bagIcons.MarkDirty then ns.bagIcons.MarkDirty() end
    return n
end
-- Pure: the verdict your choice gives, or nil (no choice, or one that can't
-- be: a vendor won't buy the thing).
function D.ChoiceVerdict(mine, sellPrice, quality)
    if mine == "keep" then return { action = "keep", reason = "you chose to keep it" } end
    if mine == "sell" and ((sellPrice or 0) > 0 or quality == 0) then return { action = "sell", reason = "you chose to sell it" } end
    return nil
end

-------------------------------------------------------------------------------
-- Built-in rules
-------------------------------------------------------------------------------

local function reg(key, order, check) ns:Register("disposition", key, { order = order, check = check }) end

-- Your own choice comes first.
reg("yourChoice", 0.5, function(i)
    return D.ChoiceVerdict(D.Choice(i.id), i.sellPrice, i.quality)
end)

-- You bought it back after Flow sold it once: never sell it again.
reg("neverSell", 1, function(i)
    if ns.db.sell.never[i.id] then return { action = "keep", reason = "you bought it back before" } end
end)

reg("unsellable", 2, function(i)
    if i.sellPrice <= 0 and i.quality ~= 0 then return { action = "keep", reason = "vendors won't buy it" } end
end)

-- Profession tools (Mining Pick, Blacksmith Hammer, Skinning Knife, fishing
-- poles...): kept while you have or plan that profession, whatever their
-- gear score says (several are weapons on paper).
local TOOLS = {
    [2901] = "Mining", [5956] = "Blacksmithing", [6219] = "Engineering", [7005] = "Skinning",
    [6256] = "Fishing", [6365] = "Fishing", [6366] = "Fishing", [6367] = "Fishing", [12225] = "Fishing",
    [19022] = "Fishing", [19970] = "Fishing", [12709] = "Skinning", [19901] = "Skinning",
    -- Enchanting rods (each recipe wants its own rod, so all are kept) and
    -- the Gyromatic Micro-Adjustor.
    [6218] = "Enchanting", [6339] = "Enchanting", [11130] = "Enchanting", [11145] = "Enchanting",
    [16207] = "Enchanting", [10498] = "Engineering",
}
local TOOL_NAMES = { { "Mining Pick", "Mining" }, { "Blacksmith Hammer", "Blacksmithing" },
    { "Skinning Knife", "Skinning" }, { "Fishing Pole", "Fishing" }, { "Arclight Spanner", "Engineering" },
    { "Runed Copper Rod", "Enchanting" }, { "Runed Silver Rod", "Enchanting" }, { "Runed Golden Rod", "Enchanting" },
    { "Runed Truesilver Rod", "Enchanting" }, { "Runed Arcanite Rod", "Enchanting" }, { "Gyromatic Micro-Adjustor", "Engineering" } }
-- Another profession's tools a profession also needs: engineers work
-- with a Blacksmith Hammer.
local TOOL_ALSO = { Blacksmithing = { "Engineering" } }
D.TOOLS = TOOLS

-- Which profession a tool is for (by item ID, else by name), or nil.
function D:ToolProfession(id, name)
    local prof = TOOLS[id]
    if not prof and name then
        for _, t in ipairs(TOOL_NAMES) do if name:find(t[1], 1, true) then return t[2] end end
    end
    return prof
end

-- Do you carry (or wear) a tool for this profession? Any version of it:
-- Forever's tools can have other item IDs than the classic ones.
function D:HasTool(prof)
    local found = false
    self:EachBagItem(function(_, _, link)
        if not found and self:ToolProfession(tonumber(link:match("item:(%d+)")), link:match("%[(.-)%]")) == prof then found = true end
    end)
    for slot = 16, 18 do
        local link = not found and GetInventoryItemLink("player", slot)
        if link and self:ToolProfession(tonumber(link:match("item:(%d+)")), link:match("%[(.-)%]")) == prof then found = true end
    end
    return found
end

reg("professionTool", 3, function(i)
    local own = D:ToolProfession(i.id, i.name)
    if not own then return nil end
    local plan = ns:ProfessionPlan() or {}
    for _, prof in ipairs({ own, unpack(TOOL_ALSO[own] or {}) }) do
        local planned = false
        for _, p in ipairs(plan) do if p.name == prof then planned = true end end
        if ns.api.Skill(prof) or planned then
            return { action = "keep", icon = PROF_ICON[prof], reason = "tool for " .. prof }
        end
    end
end)

-- Quest items (classID 12).
reg("quest", 5, function(i)
    if i.classID == 12 then return { action = "keep", reason = "quest item", icon = D.ICON_QUEST } end
end)

-- Needed by a quest you're on, or one coming up within a few levels.
reg("questNeeds", 6, function(i)
    local need = ns.quests and ns.quests.QuestItems and ns.quests:QuestItems()[i.id]
    if need then
        return { action = "keep", icon = D.ICON_QUEST,
            reason = need.inLog and ("for your quest: " .. (need.quest or "?"))
                or string.format("for an upcoming quest: %s (level %d)", need.quest or "?", need.level or 0) }
    end
end)

-- Class data: items to hold for class quests, e.g. Linen Cloth for Redemption.
reg("classKeep", 7, function(i)
    local d = ns:ClassData()
    local k = d and d.keepItems and d.keepItems[i.id]
    if k and (not k.untilLevel or UnitLevel("player") < k.untilLevel) then
        return { action = "keep", reason = k.why, icon = D.ICON_QUEST }
    end
end)

-- A material your skill has moved past (0.35.262). "I have Linen Cloth,
-- which says to keep for First Aid, but I'm past that and on the wool: it
-- should tell me to auction or vendor it." A levelling guide's step says the
-- skill range it's made in (use = { from, to }); once you're at the end of
-- every step that takes the item, that profession no longer wants it.
-- Pure: is this step behind you? (No range given: when it goes grey.)
function D.StepPast(step, rank)
    local to = (step.use and step.use[2]) or step.grey
    return to ~= nil and (rank or 0) >= to
end
-- Pure: the recipe that used to take the item, when every step of the guide
-- that takes it is behind you; nil while one still wants it, or none does.
function D.OutgrownBy(itemId, rank, guide)
    local last
    for _, step in ipairs((guide and guide.steps) or {}) do
        if step.mats and step.mats[itemId] then
            if not D.StepPast(step, rank) then return nil end
            last = step.recipe
        end
    end
    return last
end

-- Materials your professions use: exact recipes once you've opened that
-- profession's window, otherwise by kind of material.
reg("professionMaterial", 25, function(i)
    i.outgrown = nil
    -- Every profession you have that uses it (recipes you've seen in a
    -- profession window, Flow's levelling guides, then by kind of material).
    local found, order, planned = {}, {}, {}
    for _, p in ipairs(ns:ProfessionPlan() or {}) do planned[p.name] = true end
    local function add(prof, what)
        -- Professions you have, and ones in your plan you haven't learned yet.
        if not (ns.api.Skill(prof) or planned[prof]) or found[prof] then return end
        local past = D.OutgrownBy(i.id, ns.api.Skill(prof) or 0, ns:Get("profGuide", prof))
        if past then
            i.outgrown = i.outgrown or {}
            i.outgrown[prof] = past
            return
        end
        found[prof] = what or true
        order[#order + 1] = prof
    end
    for prof, recipe in pairs(ns.reagents and ns.reagents:UsedBy(i.id) or {}) do
        add(prof, type(recipe) == "string" and recipe or nil)
    end
    for prof, g in ns:Each("profGuide") do
        for _, step in ipairs(g.steps or {}) do
            if step.mats and step.mats[i.id] then add(prof, step.recipe) end
        end
    end
    if i.classID == 7 and MATERIAL[i.subclassID] then
        for _, prof in ipairs(MATERIAL[i.subclassID]) do add(prof, MATERIAL_NAME[i.subclassID]) end
    end
    if #order == 0 then return nil end
    local parts = {}
    for _, prof in ipairs(order) do
        local what = found[prof]
        parts[#parts + 1] = "for " .. prof .. (type(what) == "string" and (": " .. what) or "")
    end
    return { action = "keep", icon = PROF_ICON[order[1]], reason = table.concat(parts, "; ") }
end)


-------------------------------------------------------------------------------
-- Leaner bags (0.35.176): "I want to keep my bags as empty as possible, just
-- what I need to quest and handle current professions, the rest can go."
-- Three rules that came out of going through one druid's 40 slots:
--   * the auction house only on a price Flow has seen, that beats the vendor
--     after the house's cut and the listing fee; without one, the vendor
--   * ammunition a class can't shoot
--   * spell reagents that belong to other classes
-------------------------------------------------------------------------------

-- Is the auction house worth it? Only on a price Flow has seen (ahPrice, per
-- item), and only when what's left after the house's cut and the listing fee
-- is at least twice the vendor's price and a silver more. "If it fails on
-- the AH the listing fee can eat the profit: before we know, just vendor."
--   The cut is 5%. The fee (lost when it doesn't sell) is taken as 30% of
--   the vendor price, classic's rate for a day's listing; not checked on
--   WoW: Forever, where Flow can't read auction prices yet anyway.
D.AH_CUT, D.AH_FEE = 0.05, 0.30
function D.WorthAuction(ahPrice, vendorPrice)
    if type(ahPrice) ~= "number" or ahPrice <= 0 then return false end
    vendorPrice = vendorPrice or 0
    local net = ahPrice * (1 - D.AH_CUT) - vendorPrice * D.AH_FEE
    return net >= vendorPrice * 2 and net - vendorPrice >= 100
end

-- With no price known: the vendor (the default), or hold it for the auction
-- house as Flow used to ("Sell what has no auction price", Flow Settings).
function D.VendorUnpriced() return not (ns.db.sell and ns.db.sell.vendorUnpriced == false) end

-- The verdict for something tradeable that could go to the auction house:
-- there on a price that's worth it, else to the vendor (or held, by the
-- setting). what: "crafting material none of your professions use"...
--   -> verdict. ahCandidate marks what the price scan should look up.
function D.AuctionOrVendor(ahPrice, vendorPrice, what, vendorUnpriced, money)
    if D.WorthAuction(ahPrice, vendorPrice) then
        return { action = "ah", ahCandidate = true,
                 reason = string.format("%s; about %s each at the auction house", what, (money or ns.Money)(math.floor(ahPrice))) }
    end
    if ahPrice then
        return { action = "sell", ahCandidate = true,
                 reason = what .. "; the auction house wouldn't pay enough more than a vendor" }
    end
    if vendorUnpriced then
        return { action = "sell", ahCandidate = true,
                 reason = what .. "; no auction price known, so to a vendor" }
    end
    return { action = "ah", ahCandidate = true, reason = what .. "; check the auction house before vendoring" }
end

local function auctionOrVendor(i, what)
    -- It kept coming back unsold until the deposits ate the gain (Posting.lua):
    -- to the vendor, and the reason says so.
    local P = ns.posting
    local id = i.link and tonumber(i.link:match("item:(%d+)"))
    if P and P.GaveUp and id then
        local gave, why = P.GaveUp(id)
        if gave then return { action = "sell", reason = what .. "; " .. why .. ": to a vendor" } end
    end
    return D.AuctionOrVendor(D:AuctionPrice(i.link), i.sellPrice, what, D.VendorUnpriced(),
        ns.auction and ns.auction.Money or nil)
end

-- Ammunition (arrows, bullets) for a class that can't shoot it.
D.SHOOTS = { HUNTER = true, WARRIOR = true, ROGUE = true }
function D.AmmoIsUseless(classID, class) return classID == 6 and not D.SHOOTS[class or ""] end
reg("ammoNotYours", 23, function(i)
    local _, class = UnitClass("player")
    if D.AmmoIsUseless(i.classID, class) and i.sellPrice > 0 then
        return { action = "sell", reason = "ammunition your class can't shoot" }
    end
end)

-- Spell reagents, by the classes whose spells use them (by name: Forever's
-- item numbers can differ). Add more: ns:Register("classReagent", name, { CLASS = true }).
for name, classes in pairs({
    ["Light Feather"] = { MAGE = true, PRIEST = true },           -- Slow Fall, Levitate
    ["Rune of Teleportation"] = { MAGE = true },
    ["Rune of Portals"] = { MAGE = true },
    ["Arcane Powder"] = { MAGE = true },
    ["Holy Candle"] = { PRIEST = true },
    ["Sacred Candle"] = { PRIEST = true },
    ["Ankh"] = { SHAMAN = true },
    ["Symbol of Divinity"] = { PALADIN = true },
    ["Flash Powder"] = { ROGUE = true },
    ["Maple Seed"] = { DRUID = true }, ["Stranglethorn Seed"] = { DRUID = true }, ["Ashwood Seed"] = { DRUID = true },
    ["Hornbeam Seed"] = { DRUID = true }, ["Ironwood Seed"] = { DRUID = true },
    ["Wild Berries"] = { DRUID = true }, ["Wild Thornroot"] = { DRUID = true },
}) do ns:Register("classReagent", name, classes) end

-- Pure: is it a spell reagent of other classes only? (nil: not a reagent Flow knows.)
function D.ReagentOfOthers(name, class, classesOf)
    local classes = classesOf(name)
    if not classes then return nil end
    return not classes[class or ""]
end
-- (After the profession rules, so a reagent one of your recipes uses stays.)
reg("otherClassReagent", 26, function(i)
    local _, class = UnitClass("player")
    if i.sellPrice > 0 and D.ReagentOfOthers(i.name, class, function(n) return ns:Get("classReagent", n) end) then
        return { action = "sell", reason = "a spell reagent for other classes" }
    end
end)

-- Flow Settings, "Loot and selling".
if ns.settings and ns.settings.AddCheck then
    ns.settings:AddCheck({
        group = "loot",
        label = "Sell what has no auction price",
        note = "(off: hold green items for the auction house)",
        tip = "Green gear you have no use for goes to the auction house only when Flow has seen a "
            .. "price there that beats the vendor after the house's cut and the listing fee (a listing that doesn't "
            .. "sell costs you the fee). With no price known they're sold to a vendor. Off: they're held with the "
            .. "auction house mark until you've looked, as Flow used to do. Crafting materials always go to the auction house, "
            .. "never a vendor.",
        get = function() return D.VendorUnpriced() end,
        set = function(on) ns.db.sell.vendorUnpriced = on and true or false; D:Invalidate() end,
    })
end

-- Crafting materials (trade goods) that none of your professions, learned
-- or planned, use, or that your skill is past: the auction house, never a
-- vendor. "I don't want this to sell any professional materials. That should
-- all go on the auction house." With a price Flow has seen, the reason gives
-- it; one that keeps coming back unsold says so, and still isn't vendored.
-- Quest and class-quest needs were checked before this.
-- Pure: "your First Aid is past it (Heavy Linen Bandage)".
function D.OutgrownText(outgrown)
    local parts = {}
    for prof, recipe in pairs(outgrown or {}) do parts[#parts + 1] = string.format("your %s is past it (%s)", prof, recipe) end
    table.sort(parts)
    return #parts > 0 and table.concat(parts, "; ") or nil
end
-- Pure: the verdict for such a material. what: why no profession of yours
-- wants it; ahPrice: Flow's price each (nil: none seen); unsold: why it
-- keeps coming back from the auction house (nil: it doesn't).
function D.MaterialVerdict(what, ahPrice, unsold, money)
    local reason = what .. "; materials go to the auction house, never a vendor"
    if type(ahPrice) == "number" and ahPrice > 0 then
        reason = string.format("%s; about %s each at the auction house", what, (money or ns.Money)(math.floor(ahPrice)))
    end
    if unsold then reason = reason .. " (" .. unsold .. ")" end
    return { action = "ah", ahCandidate = true, reason = reason }
end
reg("unusedMaterial", 27, function(i)
    if i.classID ~= 7 then return nil end
    local what = D.OutgrownText(i.outgrown) or "crafting material none of your professions use"
    local unsold
    local P = ns.posting
    if P and P.GaveUp and i.id then
        local gave, why = P.GaveUp(i.id)
        if gave then unsold = why end
    end
    return D.MaterialVerdict(what, D:AuctionPrice(i.link), unsold, ns.auction and ns.auction.Money or nil)
end)

-- Gear you should wear now.
reg("equip", 10, function(i)
    local g = i.gear
    if not (g and g.canUse) then return nil end
    local role = ns:LevelingRole()
    if g.diffs[role] >= 0.5 and i.minLevel <= UnitLevel("player") then
        return { action = "equip", reason = string.format("+%d %s", g.diffs[role] + 0.5, ns.ROLE_LABEL[role]) }
    end
end)

-- Part of a gear set.
reg("inSet", 15, function(i)
    local sets = ns.gear and ns.gear.sets
    local roles = sets and sets:RolesContaining(i.link) or {}
    -- Only a set you keep counts ("Keep set for" on your bags, KeepSets.lua).
    if ns.keepSets then roles = ns.keepSets.KeptOf(roles, ns.keepSets.Keeps) end
    if #roles > 0 then
        local names = {}
        for _, r in ipairs(roles) do names[#names + 1] = ns:RoleName(r) end
        return { action = "keep", reason = "in your " .. table.concat(names, " / ") .. " set" }
    end
end)

-- Grey items: always junk.
reg("junk", 20, function(i)
    if i.quality == 0 then return { action = "sell", reason = "junk" } end
end)

-------------------------------------------------------------------------------
-- Food and drink you've outgrown: when you carry at least KEEP_BETTER of a
-- better tier of the same kind (food, or drink) for your level, the weaker
-- kind is sold. Tiers go by the level the item needs (Tough Jerky 5, Haunch
-- of Meat 15...): a step of 5+ levels is a better tier.
-------------------------------------------------------------------------------
local KEEP_BETTER, TIER_STEP = 10, 5
local function consumableKind(id)
    local spell = C_Item and C_Item.GetItemSpell and C_Item.GetItemSpell(id)
    if not spell and GetItemSpell then spell = GetItemSpell(id) end
    if type(spell) ~= "string" then return nil end
    if spell:find("Drink") then return "drink" end
    if spell:find("Food") then return "food" end
end
D.ConsumableKind = consumableKind
-- What you carry, per kind: { food = { {id, level, count}... }, drink = ... }
local carried, carriedFor
local function carriedConsumables()
    local level = UnitLevel("player")
    if carried and carriedFor == level and next(cache) ~= nil then return carried end
    carried, carriedFor = { food = {}, drink = {} }, level
    local seen = {}
    D:EachBagItem(function(bag, slot, link)
        local id = tonumber(link:match("item:(%d+)"))
        if id and not seen[id] then
            seen[id] = true
            local kind = consumableKind(id)
            if kind then
                local minLevel = select(5, ((C_Item and C_Item.GetItemInfo) or GetItemInfo)(link)) or 0
                table.insert(carried[kind], { id = id, level = minLevel, count = ns.api.Count(id) })
            end
        end
    end)
    return carried
end
-- The best tier you carry enough of, for a kind: its level, or nil.
function D:BestConsumableTier(kind)
    local best
    for _, e in ipairs(carriedConsumables()[kind] or {}) do
        if e.level <= UnitLevel("player") and e.count >= KEEP_BETTER and (not best or e.level > best) then best = e.level end
    end
    return best
end
reg("outgrownConsumable", 22, function(i)
    if i.classID ~= 0 or not i.id then return nil end
    local kind = consumableKind(i.id)
    if not kind then return nil end
    local best = D:BestConsumableTier(kind)
    if best and (i.minLevel or 0) + TIER_STEP <= best then
        return { action = "sell", reason = string.format("outgrown: you carry %d+ better %s", KEEP_BETTER, kind) }
    end
end)

-- Only another class can use it (0.35.270). "I have a ton of these mage
-- scrolls and nothing says what to do with them." Their tooltip does:
-- "Classes: Mage". Something that isn't gear, that names classes and not
-- yours, is no use to you: the auction house when the price there is worth
-- it (a Mage will want it), else a vendor.
-- Pure: the classes a tooltip names ("Classes: Mage, Warlock"), or nil.
function D.ClassesOf(lines)
    for _, l in ipairs(lines or {}) do
        local list = type(l.left) == "string" and l.left:match("^Classes: (.+)$")
        if list then
            local out = {}
            for name in list:gmatch("[^,]+") do out[#out + 1] = (name:gsub("^%s+", ""):gsub("%s+$", "")) end
            return out
        end
    end
    return nil
end
-- Pure: is your class one of them? (nil list: anyone can use it.)
function D.ForYourClass(classes, mine)
    if not classes then return true end
    for _, c in ipairs(classes) do if c == mine then return true end end
    return false
end
reg("otherClassItem", 29, function(i)
    if i.gear or not i.link or not (ns.gear and ns.gear.TooltipLines) then return nil end
    local ok, lines = pcall(ns.gear.TooltipLines, ns.gear, i.link)
    local classes = ok and D.ClassesOf(lines) or nil
    local mine = UnitClass("player")
    if D.ForYourClass(classes, mine) then return nil end
    local what = "only a " .. table.concat(classes, " or ") .. " can use it"
    if (i.sellPrice or 0) <= 0 then return { action = "keep", reason = what .. ", and vendors won't take it" } end
    if i.bound then return { action = "sell", reason = what } end
    return auctionOrVendor(i, what)
end)

-- A recipe (0.35.302): "I have a tailoring and a leatherworking pattern and
-- it doesn't tell me what to do with them." A recipe for a profession you
-- don't have is no use to you: the auction house when it's worth it there,
-- else a vendor. For one of yours: learn it now, keep it until your skill
-- reaches what it asks, or let it go when you already know it.
D.RECIPE_PROF = { [1] = "Leatherworking", [2] = "Tailoring", [3] = "Engineering", [4] = "Blacksmithing", [5] = "Cooking",
                  [6] = "Alchemy", [7] = "First Aid", [8] = "Enchanting", [9] = "Fishing", [10] = "Jewelcrafting", [11] = "Inscription" }
-- Pure: what a recipe is to you. prof: its profession; rank: your skill in it
-- (nil: you don't have it); lines: its tooltip; known: the game's "Already known".
--   -> "other" (not your profession) | "known" | "later", skill | "learn"
function D.RecipeAdvice(prof, rank, lines, known)
    if not prof then return nil end
    if not rank then return "other" end
    local need
    for _, l in ipairs(lines or {}) do
        if type(l.left) == "string" then
            if known and l.left == known then return "known" end
            need = need or tonumber(l.left:match("^Requires " .. prof .. " %((%d+)%)"))
        end
    end
    if need and rank > 0 and rank < need then return "later", need end
    return "learn", need
end
reg("recipe", 29.5, function(i)
    local prof = i.classID == 9 and D.RECIPE_PROF[i.subclassID or -1] or nil
    if not prof then return nil end
    local rank = ns.api.Skill and ns.api.Skill(prof) or nil
    local lines
    if i.link and ns.gear and ns.gear.TooltipLines then
        local ok, l = pcall(ns.gear.TooltipLines, ns.gear, i.link)
        lines = ok and l or nil
    end
    local what, need = D.RecipeAdvice(prof, rank, lines, _G.ITEM_SPELL_KNOWN)
    if what == "learn" then
        return { action = "keep", reason = string.format("a %s recipe you can learn: right-click it", prof) }
    elseif what == "later" then
        return { action = "keep", reason = string.format("a %s recipe: learn it at %s %d (you have %d)", prof, prof, need, rank) }
    end
    local why = what == "known" and string.format("a %s recipe you already know", prof)
        or string.format("a %s recipe, and you don't have %s", prof, prof)
    if (i.sellPrice or 0) <= 0 and i.bound then return { action = "keep", reason = why .. ", and vendors won't take it" } end
    if i.bound then return { action = "sell", reason = why } end
    return auctionOrVendor(i, why)
end)

-- A bag in your bags (0.35.262): worth putting on when it's bigger than one
-- you wear (or a bag slot is empty); else it's a spare taking a slot.
-- Pure: how many slots a bag's tooltip says ("8 Slot Bag").
function D.BagSize(lines)
    for _, l in ipairs(lines or {}) do
        local n = type(l.left) == "string" and l.left:match("(%d+) Slot")
        if n then return tonumber(n) end
    end
    return nil
end
-- Pure: "wear" (bigger than your smallest, or a slot is empty: worn sizes
-- with 0 for an empty slot), else "spare".
function D.SpareBag(size, worn)
    if not size then return nil end
    for _, w in ipairs(worn or {}) do
        if w < size then return "wear" end
    end
    return "spare"
end
function D.WornBags()
    local out = {}
    for bag = 1, 4 do out[#out + 1] = (numSlots and numSlots(bag)) or 0 end
    return out
end
reg("spareBag", 28, function(i)
    if i.classID ~= 1 or not i.link or not (ns.gear and ns.gear.TooltipLines) then return nil end
    local ok, lines = pcall(ns.gear.TooltipLines, ns.gear, i.link)
    local size = ok and D.BagSize(lines) or nil
    local what = D.SpareBag(size, D.WornBags())
    if what == "wear" then
        return { action = "keep", reason = string.format("a %d-slot bag, bigger than one you wear (or a bag slot is empty): put it on", size) }
    elseif what == "spare" and (i.sellPrice or 0) > 0 then
        return { action = "sell", reason = string.format("spare %d-slot bag: every bag you wear is as big or bigger", size) }
    end
end)

-- Non-gear: trade goods, reagents, consumables, recipes, bags, gems... keep.
-- (PLACEHOLDER: sell trade goods none of your professions use.)
reg("notGear", 30, function(i)
    if not i.gear then return { action = "keep", reason = "not gear (materials, food, potions...)" } end
end)

-- An upgrade once you train its weapon skill (a sword before you've learned
-- Swords): keep it; the route plans the weapon master.
reg("needsTraining", 35, function(i)
    local g = i.gear
    if not (g and g.needsTraining) then return nil end
    local main = ns:LevelingRole()
    if (g.diffs and g.diffs[main] or 0) >= 0.5 then
        return { action = "keep", reason = "upgrade once you train " .. (g.skill or "its weapon skill") .. " (weapon master)" }
    end
end)

-- Upgrade later, or better for another role.
reg("laterOrOtherRole", 40, function(i)
    local g = i.gear
    if not g.canUse then return nil end
    local main = ns:LevelingRole()
    if g.diffs[main] >= 0.5 then return { action = "keep", reason = "upgrade at level " .. i.minLevel } end
    -- Another spec, when you keep its set ("Keep set for" on your bags).
    for _, role in ipairs(ns.gear.ROLES) do
        local kept = ns.keepSets and ns.keepSets.Keeps(role)
        if ns.keepSets == nil then kept = ns.db.gear.keepOffspec end
        if role ~= main and kept and g.diffs[role] >= 0.5 then
            return { action = "keep", reason = "better for " .. ns:RoleName(role) }
        end
    end
end)

-- Pure: true when the class data has stat weights for at least one role, so
-- Flow can tell better gear from worse (F-001).
function D.ClassScored(d)
    if not (d and type(d.weights) == "table") then return false end
    for _, w in pairs(d.weights) do
        if type(w) == "table" and next(w) ~= nil then return true end
    end
    return false
end

-- Pure: gear your class can wear (or train for) but Flow can't score for
-- your class is kept, never sold as "not better" (every score would be 0).
function D.UnscoredGearVerdict(gear, scored)
    if scored or not gear then return nil end
    if gear.canUse or gear.needsTraining then
        return { action = "keep", reason = "Flow can't score gear for your class yet, so it's kept: decide yourself" }
    end
end

reg("unscoredClass", 45, function(i)
    return D.UnscoredGearVerdict(i.gear, D.ClassScored(ns:ClassData()))
end)

-- Unneeded gear: disenchant if you can, auction if it's worth more there,
-- otherwise vendor.
reg("unneededGear", 50, function(i)
    if ns.api.Skill("Enchanting") and i.quality >= 2 then
        return { action = "de", reason = "you can disenchant it" }
    end
    if i.bound == false and i.quality >= 3 and not D:AuctionPrice(i.link) then
        -- Rare or better, tradeable, and no price known: never to a vendor
        -- unseen (a blue drop can be worth far more than its vendor price).
        return { action = "ah", ahCandidate = true, reason = "tradeable rare gear: check the auction house before vendoring" }
    end
    if i.bound == false and i.quality >= 2 then
        return auctionOrVendor(i, "tradeable gear that's no better than yours for any role")
    end
    return { action = "sell", reason = "not better than your gear for any role" }
end)

-------------------------------------------------------------------------------
-- Inventory: your bags as Flow sees them (/flow inventory, and saved with
-- the diagnostics at every /reload). One line an item, its stacks added up:
-- what Flow would do with it, why, which rule said so, what a vendor pays,
-- and what the auction house asked when Flow last looked. For going through
-- the bags with a reason for every slot ("keep my bags as empty as possible:
-- just what I need to quest and for my professions, the rest can go").
-------------------------------------------------------------------------------
local QUALITY = { [0] = "grey", [1] = "white", [2] = "green", [3] = "blue", [4] = "purple", [5] = "orange" }
local ACTION_ORDER = { sell = 1, ah = 2, de = 3, equip = 4, keep = 5 }
local ACTION_SHORT = { sell = "SELL", ah = "AH", de = "DE", equip = "EQUIP", keep = "KEEP" }

-- Pure: one row an item and verdict, from the slots.
--   slots: { { id, name, count, action, reason, rule, sell, quality, bound, kind, ah } }
-- Sorted: what leaves first (sell, auction, disenchant), then equip, then
-- keep; by name within each.
function D.InventoryRows(slots)
    local byKey, rows = {}, {}
    for _, s in ipairs(slots) do
        local key = tostring(s.id) .. ":" .. tostring(s.action) .. ":" .. tostring(s.rule)
        local r = byKey[key]
        if not r then
            r = { id = s.id, name = s.name, action = s.action, reason = s.reason, rule = s.rule, sell = s.sell,
                  quality = s.quality, bound = s.bound, kind = s.kind, ah = s.ah, count = 0, stacks = 0 }
            byKey[key] = r
            rows[#rows + 1] = r
        end
        r.count = r.count + (s.count or 1)
        r.stacks = r.stacks + 1
    end
    table.sort(rows, function(a, b)
        local ao, bo = ACTION_ORDER[a.action] or 9, ACTION_ORDER[b.action] or 9
        if ao ~= bo then return ao < bo end
        return tostring(a.name) < tostring(b.name)
    end)
    return rows
end

-- Pure: one row as text. money(copper) -> "1s 20c".
function D.InventoryLine(r, money)
    money = money or ns.Money
    local bits = { QUALITY[r.quality or 1] or "?" }
    if r.kind and r.kind ~= "" then bits[#bits + 1] = r.kind end
    if r.bound then bits[#bits + 1] = "soulbound" end
    bits[#bits + 1] = (r.sell or 0) > 0 and ("vendor " .. money(r.sell) .. " each") or "no vendor price"
    if r.ah then bits[#bits + 1] = "auction " .. money(r.ah) .. " each" end
    return string.format("%-5s %3d x %s [%s] in %d slot%s (%s): %s {%s}", ACTION_SHORT[r.action] or tostring(r.action),
        r.count, tostring(r.name), tostring(r.id), r.stacks, r.stacks == 1 and "" or "s", table.concat(bits, ", "),
        tostring(r.reason), tostring(r.rule or "no rule"))
end

-- Pure: the heading: slots used, and how many Flow would empty.
function D.InventorySummary(rows, used, total)
    local n = { sell = 0, ah = 0, de = 0 }
    local value = 0
    for _, r in ipairs(rows) do
        if n[r.action] then n[r.action] = n[r.action] + r.stacks end
        if r.action == "sell" then value = value + (r.sell or 0) * r.count end
    end
    return string.format("%d of %d bag slots used; Flow would empty %d (sell %d, auction house %d, disenchant %d)",
        used or 0, total or 0, n.sell + n.ah + n.de, n.sell, n.ah, n.de), value
end

local function stackOf(bag, slot)
    if CC and CC.GetContainerItemInfo then
        local info = CC.GetContainerItemInfo(bag, slot)
        return info and info.stackCount or 1
    end
    local _, count = GetContainerItemInfo(bag, slot)
    return count or 1
end

-- The bags, read now: rows, slots used, slots in all.
function D:Inventory()
    local slots, used, total = {}, 0, 0
    local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    for bag = 0, 4 do total = total + ((numSlots and numSlots(bag)) or 0) end
    self:EachBagItem(function(bag, slot, link)
        used = used + 1
        local v = self:Decide(bag, slot, link)
        local item = v and v.item
        local kind
        if get then
            local ok, _, _, _, _, _, itemType, subType = pcall(get, link)
            if ok and itemType then kind = (subType and subType ~= "" and subType ~= itemType) and (itemType .. ": " .. subType) or itemType end
        end
        slots[#slots + 1] = {
            id = tonumber(link:match("item:(%d+)")), name = link:match("%[(.-)%]"), count = stackOf(bag, slot),
            action = v and v.action or "?", reason = v and v.reason or "not loaded yet", rule = v and v.rule,
            sell = item and item.sellPrice, quality = item and item.quality, bound = item and item.bound, kind = kind,
            ah = self:AuctionPrice(link),
        }
    end)
    return D.InventoryRows(slots), used, total
end

ns.commands.inventory = function()
    local rows, used, total = D:Inventory()
    local money = ns.Money
    local head, value = D.InventorySummary(rows, used, total)
    ns:Print("inventory: " .. head .. (value > 0 and (", " .. money(value) .. " at a vendor") or ""))
    for _, r in ipairs(rows) do print("  " .. D.InventoryLine(r, money)) end
    -- What the game says the things Flow can't place are for (their "Use:" line),
    -- so a rule can be written for them from the game's own words.
    local said = {}
    D:EachBagItem(function(bag, slot, link)
        local name = link:match("%[(.-)%]")
        if not name or said[name] then return end
        local okV, v = pcall(D.Decide, D, bag, slot, link)
        if not (okV and type(v) == "table" and v.rule == "notGear") then return end
        local okL, lines = pcall(ns.gear.TooltipLines, ns.gear, link)
        for _, l in ipairs(okL and lines or {}) do
            if type(l.left) == "string" and l.left:find("^Use:") then
                said[name] = true
                print(string.format("  what it's for, in the game's words: %s: %s", name, l.left:sub(1, 160)))
                break
            end
        end
        -- No "Use:" line (the scrolls): everything its tooltip says, so it can be read.
        if not said[name] then
            said[name] = true
            local parts = {}
            for n, l in ipairs(okL and lines or {}) do
                if n > 1 and n <= 8 and type(l.left) == "string" and l.left ~= "" then parts[#parts + 1] = l.left:sub(1, 120) end
            end
            if #parts > 0 then print(string.format("  what its tooltip says: %s: %s", name, table.concat(parts, " | "))) end
        end
    end)
    -- Which auction house this client has (Flow's price scan needs the classic one).
    print(string.format("  auction house: classic search %s, newer one %s; Flow knows a price for %d item(s) here",
        (QueryAuctionItems and GetAuctionItemInfo) and "yes" or "no", C_AuctionHouse and "yes" or "no",
        ns.auction and ns.auction.Known and ns.auction:Known() or 0))
end
ns.commands.inv = ns.commands.inventory

ns:Register("help", "inventory", { order = 44, title = "Inventory", lines = {
    "/flow inventory: every item in your bags with what Flow would do (sell, auction house, keep) and why. It's saved with the diagnostics.",
} })
