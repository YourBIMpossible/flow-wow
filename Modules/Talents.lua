-- Flow Talents: your class's talent trees as the game has them, with Flow's
-- levelling build laid over them: every point in order, the level it comes
-- at, what to take with the points you have now, and where the build ends
-- up. A reference to read beside the game's talent window; Flow never spends
-- a point for you. /flow talents (or the "Spend N talent points" advice).
--
-- A build is a registration, one per class (Classes/<Class>/Data.lua):
--   ns:Register("talentBuild", "DRUID", { name = "Feral (Cat) levelling",
--       role = "dps", trees = { "Balance", "Feral", "Restoration" },
--       order = { { "Ferocity", 5, why = "..." }, ... } })
-- order: talents by their name in the game, with how many points, in the
-- order to take them (one point a level from level 10). A class without a
-- build still gets its trees shown.

local _, ns = ...
local T = {}
ns.talents = T

T.FIRST_LEVEL = 10     -- the level of your first talent point
T.TIER_POINTS = 5      -- points in a tree before its next row opens
T.TREE_GAP = 1500      -- trees sit this far apart on the game's talent sheet
local ROWS = 22        -- most talents in one tree

-------------------------------------------------------------------------------
-- The game's trees
-------------------------------------------------------------------------------

-- The talent sheet (C_ClassTalents / C_Traits, as on WoW: Forever), or nil
-- when this client hasn't got it.
local function readSheet()
    local out = {}
    if C_ClassTalents and C_Traits and C_ClassTalents.GetActiveConfigID then
        local cfg = C_ClassTalents.GetActiveConfigID()
        if not cfg then return out, 0 end
        local info = C_Traits.GetConfigInfo(cfg)
        local unspent = 0
        for _, treeID in ipairs(info and info.treeIDs or {}) do
            local ok, currencies = pcall(C_Traits.GetTreeCurrencyInfo, cfg, treeID, false)
            for _, c in ipairs(ok and currencies or {}) do unspent = unspent + (c.quantity or 0) end
            for _, nodeID in ipairs(C_Traits.GetTreeNodes(treeID) or {}) do
                local node = C_Traits.GetNodeInfo(cfg, nodeID)
                if node and node.ID ~= 0 and (node.maxRanks or 0) > 0 then
                    local entryID = node.entryIDs and node.entryIDs[1]
                    local e = entryID and C_Traits.GetEntryInfo(cfg, entryID)
                    local def = e and e.definitionID and C_Traits.GetDefinitionInfo(e.definitionID)
                    local name = def and (def.overrideName or (def.spellID and ns.api.SpellInfo(def.spellID)))
                    if name then
                        local leads = {}
                        for _, edge in ipairs(node.visibleEdges or {}) do leads[#leads + 1] = edge.targetNode end
                        out[#out + 1] = { id = nodeID, name = name, x = node.posX or 0, y = node.posY or 0,
                                          rank = node.currentRank or 0, max = node.maxRanks, spellID = def.spellID,
                                          leads = leads }
                    end
                end
            end
        end
        return out, unspent
    end
    return nil
end

-- The classic talent API (tabs), or nil when this client hasn't got it.
local function readTabs()
    local out = {}
    if GetNumTalentTabs and GetNumTalents and GetTalentInfo then
        for tab = 1, GetNumTalentTabs() or 0 do
            for i = 1, GetNumTalents(tab) or 0 do
                local name, _, tier, column, rank, maxRank = GetTalentInfo(tab, i)
                if name then
                    out[#out + 1] = { id = tab * 100 + i, name = name, x = (tab - 1) * 10000 + (column or 1) * 600,
                                      y = (tier or 1) * 600, rank = rank or 0, max = maxRank or 1, leads = {} }
                end
            end
        end
        return out, UnitCharacterPoints and UnitCharacterPoints("player") or 0
    end
    return nil
end

-- Pure: the first reader that finds talents; else what the first one that
-- works at all said (no talents: none spent yet, or none loaded), else
-- nothing. A reader that errors or isn't on this client (nil) is passed
-- over: a client can carry an old talent function that answers nothing.
-- readers: { function() -> nodes, unspent }.
function T.ReadWith(readers)
    local firstNodes, firstUnspent
    for _, read in ipairs(readers) do
        local ok, nodes, unspent = pcall(read)
        if ok and type(nodes) == "table" then
            if #nodes > 0 then return nodes, unspent or 0 end
            if not firstNodes then firstNodes, firstUnspent = nodes, unspent end
        end
    end
    return firstNodes or {}, firstUnspent or 0
end

-- Every talent the game shows you: { id, name, x, y, rank, max, spellID,
-- leads = { node ids it leads to } }, and your unspent points. The talent
-- sheet first, then the classic tabs.
function T.Read()
    return T.ReadWith({ readSheet, readTabs })
end

-- Your unspent talent points (0 when the game won't say).
function T.Unspent()
    local ok, _, unspent = pcall(T.Read)
    return ok and unspent or 0
end

-- Sorts talents into trees (left to right on the game's sheet) and rows
-- (top to bottom): each talent gets .tree and .tier; returns { { nodes } }.
function T.Arrange(nodes)
    local sorted = {}
    for _, n in ipairs(nodes) do sorted[#sorted + 1] = n end
    table.sort(sorted, function(a, b) if a.x ~= b.x then return a.x < b.x end return a.y < b.y end)
    local trees, last = {}, nil
    for _, n in ipairs(sorted) do
        if not last or n.x - last > T.TREE_GAP then trees[#trees + 1] = { nodes = {} } end
        last = n.x
        n.tree = #trees
        table.insert(trees[#trees].nodes, n)
    end
    local ys, seen = {}, {}
    for _, n in ipairs(nodes) do
        if not seen[n.y] then seen[n.y] = true; ys[#ys + 1] = n.y end
    end
    table.sort(ys)
    local tierOf = {}
    for i, y in ipairs(ys) do tierOf[y] = i end
    for _, n in ipairs(nodes) do n.tier = tierOf[n.y] end
    for _, tr in ipairs(trees) do
        table.sort(tr.nodes, function(a, b) if a.tier ~= b.tier then return a.tier < b.tier end return a.x < b.x end)
    end
    return trees
end

-------------------------------------------------------------------------------
-- A build: its points in order
-------------------------------------------------------------------------------

function T.Build()
    local _, class = UnitClass("player")
    return ns:Get("talentBuild", class or "")
end

-- One entry per talent point, in order: { name, rank (this point makes it
-- rank N), level (the level that point comes at), why }.
function T.Picks(build)
    local picks, count = {}, {}
    for _, b in ipairs(build and build.order or {}) do
        local name = b[1]
        for _ = 1, b[2] or 1 do
            count[name] = (count[name] or 0) + 1
            picks[#picks + 1] = { name = name, rank = count[name], level = T.FIRST_LEVEL + #picks, why = b.why }
        end
    end
    return picks
end

-- Per talent: { ranks, from, to (levels), why }.
function T.Plan(picks)
    local plan = {}
    for _, p in ipairs(picks) do
        local e = plan[p.name]
        if not e then e = { ranks = 0, from = p.level, why = p.why }; plan[p.name] = e end
        e.ranks, e.to = p.rank, p.level
    end
    return plan
end

-- The build's points you don't have yet, in order (have: { [name] = rank }).
-- The first `points` of them are what to take now; the rest come one a level.
function T.Missing(picks, have)
    local out = {}
    for _, p in ipairs(picks) do
        if (have[p.name] or 0) < p.rank then out[#out + 1] = p end
    end
    return out
end

-- "Improved Wrath x2, Ferocity" from picks.
function T.Names(list)
    local order, n = {}, {}
    for _, p in ipairs(list) do
        if not n[p.name] then order[#order + 1] = p.name end
        n[p.name] = (n[p.name] or 0) + 1
    end
    local bits = {}
    for _, name in ipairs(order) do bits[#bits + 1] = name .. (n[name] > 1 and (" x" .. n[name]) or "") end
    return table.concat(bits, ", ")
end

-- Does the build fit the trees the game shows? A list of what doesn't:
-- a talent the game doesn't have, more points than it takes, a row taken
-- before its tree has enough points in it.
function T.Check(build, nodes)
    local problems, byName, spent = {}, {}, {}
    T.Arrange(nodes)
    for _, n in ipairs(nodes) do byName[n.name] = n end
    for i, p in ipairs(T.Picks(build)) do
        local n = byName[p.name]
        if not n then
            problems[#problems + 1] = "point " .. i .. ": no talent called " .. p.name
        else
            if p.rank > n.max then problems[#problems + 1] = p.name .. ": " .. p.rank .. " points, it takes " .. n.max end
            local need = ((n.tier or 1) - 1) * T.TIER_POINTS
            if (spent[n.tree] or 0) < need then
                problems[#problems + 1] = string.format("point %d: %s needs %d points in its tree first (has %d)",
                    i, p.name, need, spent[n.tree] or 0)
            end
            spent[n.tree] = (spent[n.tree] or 0) + 1
        end
    end
    return problems
end

-- How a talent's row is drawn: "done" (you have all the build wants), "now"
-- (take it with your points), "later" (in the build, further on), "off"
-- (not in the build).
function T.RowState(node, plan, now)
    local e = plan[node.name]
    if not e then return "off" end
    if node.rank >= e.ranks then return "done" end
    if now[node.name] then return "now" end
    return "later"
end

-------------------------------------------------------------------------------
-- Taking the points: "Take these points" in the view spends your unspent
-- points on the build's next picks, after you confirm (a talent can only be
-- taken back with a respec). Out of a fight only.
-------------------------------------------------------------------------------

-- The core, with the game's calls passed in (the tests pass their own):
--   api.purchase(nodeID) -> bool, api.commit() -> bool, api.rollback()
-- list: picks ({ name }), byName: { [name] = node }. Either every pick is
-- taken and saved, or none is: a refused pick or a failed save rolls back
-- what was staged. Returns how many were taken, and what went wrong.
function T.TakeWith(list, byName, api)
    local staged = 0
    for _, p in ipairs(list or {}) do
        local n = byName[p.name]
        if not (n and api.purchase(n.id)) then
            if staged > 0 then api.rollback() end
            return 0, (n and "the game wouldn't take " or "the game has no talent called ") .. p.name
        end
        staged = staged + 1
    end
    if staged == 0 then return 0, "nothing to take" end
    if not api.commit() then
        api.rollback()
        return 0, "the game wouldn't save them"
    end
    return staged
end

-- Can an add-on set talents on this client? (the modern talent system)
function T.CanTake()
    return (C_Traits and C_Traits.PurchaseRank and C_ClassTalents and C_ClassTalents.GetActiveConfigID) and true or false
end

-- Spends them (after the confirmation). Returns taken, problem.
function T.Take(list)
    if InCombatLockdown() then return 0, "not in a fight" end
    if not T.CanTake() then return 0, "this client's talents can't be set by an add-on" end
    local cfg = C_ClassTalents.GetActiveConfigID()
    if not cfg then return 0, "the game hasn't given you talents yet" end
    local byName = {}
    for _, n in ipairs((T.Read())) do byName[n.name] = n end
    local how
    local taken, problem = T.TakeWith(list, byName, {
        purchase = function(id)
            local ok, did = pcall(C_Traits.PurchaseRank, cfg, id)
            return ok and did == true
        end,
        -- Class talents are saved through C_ClassTalents where the client
        -- has it (no saved loadout named: the active one), else C_Traits.
        commit = function()
            if C_ClassTalents.CommitConfig then
                local ok, did = pcall(C_ClassTalents.CommitConfig, nil)
                if ok and did then how = "C_ClassTalents.CommitConfig" return true end
            end
            if C_Traits.CommitConfig then
                local ok, did = pcall(C_Traits.CommitConfig, cfg)
                if ok and did then how = "C_Traits.CommitConfig" return true end
            end
            return false
        end,
        rollback = function() if C_Traits.RollbackConfig then pcall(C_Traits.RollbackConfig, cfg) end end,
    })
    ns:Log("talents", string.format("take %s: %d taken%s%s", T.Names(list), taken,
        how and (" (saved with " .. how .. ")") or "", problem and (", problem: " .. problem) or ""))
    return taken, problem
end

-- The confirmation, then T.Take.
StaticPopupDialogs["FLOW_TALENTS"] = {
    text = "%s", button1 = "Spend them", button2 = "Not now",
    OnAccept = function(_, list)
        local taken, problem = T.Take(list)
        if taken > 0 then ns:Print(string.format("took %d talent point%s: %s.", taken, taken == 1 and "" or "s", T.Names(list)))
        else ns:Print("couldn't take them: " .. tostring(problem) .. ". Spend them in the game's talent window.") end
        T:Refresh()
    end,
    timeout = 0, whileDead = false, hideOnEscape = true, preferredIndex = 3,
}
function T.Ask(list)
    if not (list and #list > 0) then return end
    local dialog = StaticPopup_Show("FLOW_TALENTS", string.format(
        "Spend %d talent point%s on:\n\n|cffffd200%s|r\n\nA talent can only be taken back with a respec.",
        #list, #list == 1 and "" or "s", T.Names(list)))
    if dialog then dialog.data = list end
end

-------------------------------------------------------------------------------
-- The view
-------------------------------------------------------------------------------

local frame
local COLOR = { done = "66ff66", now = "ffd200", later = "ffffff", off = "777777" }

local function rowText(node, plan, state)
    local e = plan[node.name]
    local text = string.format("|cff%s%d/%d  %s|r", COLOR[state], node.rank, node.max, node.name)
    if e and state ~= "done" then
        -- "0/5  Ferocity  5 by level 19": how far the build takes it, and by when.
        text = text .. string.format("  |cff888888%d by level %d|r", e.ranks, e.to)
    elseif not e and node.rank > 0 then
        text = text .. "  |cff888888yours, not in the build|r"
    end
    return text
end

local function showTip(self)
    local node, e = self.node, self.plan
    if not node then return end
    ns.Tip(self, "ANCHOR_RIGHT")
    local shown = false
    if node.spellID and GameTooltip.SetSpellByID then shown = pcall(GameTooltip.SetSpellByID, GameTooltip, node.spellID) end
    if not shown then GameTooltip:AddLine(node.name, 1, 1, 1) end
    GameTooltip:AddLine(" ")
    if e then
        GameTooltip:AddLine(string.format("Flow's build: %d point%s here, from level %d.", e.ranks, e.ranks == 1 and "" or "s", e.from), 1, 0.82, 0)
        if e.why then GameTooltip:AddLine(e.why, 0.8, 0.8, 0.8, true) end
    else
        GameTooltip:AddLine("Not in Flow's build.", 0.6, 0.6, 0.6)
    end
    GameTooltip:Show()
end

local function build()
    local f = CreateFrame("Frame", "FlowTalents", UIParent)
    f:SetSize(786, 470)
    f:SetPoint("CENTER", 0, 40)
    f:SetFrameStrata("DIALOG")
    f:EnableMouse(true)
    f.bg = f:CreateTexture(nil, "BACKGROUND"); f.bg:SetAllPoints(); f.bg:SetColorTexture(0.05, 0.05, 0.08, 0.95)
    f.head = ns.theme:TitleBar(f, "Flow Talents", "Interface\\Icons\\INV_Misc_Book_09")
    ns:MakeMovable(f, {}, true)   -- (Ctrl-drag)
    f.close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    f.close:SetPoint("TOPRIGHT", 2, 2)
    f.close:SetScript("OnClick", function() f:Hide() end)
    local function line(y, font)
        local fs = f:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", 12, y); fs:SetPoint("TOPRIGHT", -12, y)
        fs:SetJustifyH("LEFT"); fs:SetWordWrap(false)
        return fs
    end
    f.what = line(-32, "GameFontNormal")   -- the build and where it ends up
    f.now = line(-52)                      -- what to take now
    f.soon = line(-68)                     -- what comes at your next levels
    -- "Take these points": spends them on the gold talents, after you confirm.
    f.take = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.take:SetSize(150, 22)
    f.take:SetPoint("TOPRIGHT", -34, -46)
    f.take:SetText("Take these points")
    f.take:SetScript("OnClick", function() T.Ask(f.takeList) end)
    f.take:SetScript("OnEnter", function(self)
        ns.Tip(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Take these points", 1, 0.82, 0)
        GameTooltip:AddLine("Spends your unspent points on the gold talents, in the build's order. It asks first: a talent can only be taken back with a respec. Not in a fight.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    f.take:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.take:Hide()
    f.cols = {}
    for c = 1, 3 do
        local col = { rows = {} }
        local x = 12 + (c - 1) * 256
        col.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        col.title:SetPoint("TOPLEFT", x, -92)
        for i = 1, ROWS do
            local r = CreateFrame("Button", nil, f)
            r:SetSize(250, 15)
            r:SetPoint("TOPLEFT", x, -94 - i * 15)
            r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            r.text:SetAllPoints(); r.text:SetJustifyH("LEFT"); r.text:SetWordWrap(false)
            r.hl = r:CreateTexture(nil, "HIGHLIGHT"); r.hl:SetAllPoints(); r.hl:SetColorTexture(1, 1, 1, 0.08)
            r:SetScript("OnEnter", showTip)
            r:SetScript("OnLeave", function() GameTooltip:Hide() end)
            col.rows[i] = r
        end
        f.cols[c] = col
    end
    f.foot = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.foot:SetPoint("BOTTOMLEFT", 12, 10); f.foot:SetPoint("BOTTOMRIGHT", -12, 10)
    f.foot:SetJustifyH("LEFT")
    f.foot:SetText("Gold: take now. White: later in the build. Green: done. Grey: not in it. Hover a talent for what it does; spend points in the game's talent window.")
    tinsert(UISpecialFrames, "FlowTalents")   -- Escape closes it
    f:Hide()
    return f
end

-- Everything the view shows, worked out from the game's trees and the build
-- (the tests pass their own): { what, now, soon, trees = { { title, rows = {
-- { node, state, text, plan } } } } }.
function T.View(nodes, unspent, bld, level)
    local trees = T.Arrange(nodes)
    local picks = T.Picks(bld)
    local plan = T.Plan(picks)
    local have = {}
    for _, n in ipairs(nodes) do have[n.name] = n.rank end
    local missing = T.Missing(picks, have)
    local nowList, now = {}, {}
    for i = 1, math.min(unspent or 0, #missing) do nowList[i] = missing[i]; now[missing[i].name] = true end
    local v = { trees = {}, take = bld and nowList or {} }   -- (take: what "Take these points" spends)
    -- Where the build ends up, tree by tree: "5 / 41 / 5".
    local ends = {}
    for i, tr in ipairs(trees) do
        local total, yours = 0, 0
        local rows = {}
        for _, n in ipairs(tr.nodes) do
            total = total + (plan[n.name] and plan[n.name].ranks or 0)
            yours = yours + n.rank
            local state = T.RowState(n, plan, now)
            rows[#rows + 1] = { node = n, state = state, text = rowText(n, plan, state), plan = plan[n.name] }
        end
        ends[i] = total
        local name = bld and bld.trees and bld.trees[i] or ("Tree " .. i)
        v.trees[i] = { rows = rows, title = bld and string.format("%s  |cff888888%d of %d|r", name, yours, total)
            or string.format("%s  |cff888888%d|r", name, yours) }
    end
    if not bld then
        v.what = "No levelling build written for your class yet: these are your trees as the game has them."
        v.now = (unspent or 0) > 0 and string.format("|cffffd200You have %d point%s to spend.|r", unspent, unspent == 1 and "" or "s") or ""
        v.soon = ""
        return v
    end
    v.what = string.format("%s  |cff888888(%s at level 60)|r", bld.name or "Levelling build", table.concat(ends, " / "))
    if #nowList > 0 then
        v.now = string.format("|cffffd200Take now (%d point%s): %s|r", #nowList, #nowList == 1 and "" or "s", T.Names(nowList))
    elseif (unspent or 0) > 0 then
        v.now = "|cffffd200You have points to spend, and the build is complete: your choice.|r"
    else
        v.now = "No points to spend right now."
    end
    -- The next five points, each at the level it comes.
    local bits = {}
    for i = #nowList + 1, math.min(#missing, #nowList + 5) do
        bits[#bits + 1] = string.format("%d %s", (level or T.FIRST_LEVEL) + (i - #nowList), missing[i].name)
    end
    v.soon = #bits > 0 and ("|cffbbbbbbAt your next levels:|r " .. table.concat(bits, "  |cff666666·|r  ")) or ""
    return v
end

function T:Refresh()
    if not (frame and frame:IsShown()) then return end
    local ok, nodes, unspent = pcall(T.Read)
    if not ok then nodes, unspent = {}, 0 end
    local v = T.View(nodes, unspent, T.Build(), UnitLevel("player"))
    frame.what:SetText(#nodes > 0 and v.what or "The game hasn't given you talents yet (they start at level 10).")
    frame.now:SetText(v.now or "")
    frame.soon:SetText(v.soon or "")
    frame.takeList = v.take
    frame.take:SetShown(#v.take > 0 and T.CanTake())
    frame.take:SetEnabled(not InCombatLockdown())
    for c, col in ipairs(frame.cols) do
        local tr = v.trees[c]
        col.title:SetText(tr and tr.title or "")
        for i, r in ipairs(col.rows) do
            local row = tr and tr.rows[i]
            r.node, r.plan = row and row.node, row and row.plan
            r.text:SetText(row and row.text or "")
            r:SetShown(row ~= nil)
        end
    end
end

function T:Show()
    frame = frame or build()
    frame:Show()
    T:Refresh()
end
T._Frame = function() return frame end   -- (tests)

for _, ev in ipairs({ "TRAIT_CONFIG_UPDATED", "TRAIT_NODE_CHANGED", "PLAYER_TALENT_UPDATE", "CHARACTER_POINTS_CHANGED", "PLAYER_LEVEL_UP" }) do
    ns:On(ev, function() T:Refresh() end)
end

-- /flow talents: the view. /flow talents dump: the game's trees as text
-- (Spec.lua; the diagnostics snapshot keeps it).
local dump = ns.commands.talents
ns.commands.talents = function(arg)
    if (arg or ""):lower() == "dump" then
        if dump then dump() end
        return
    end
    T:Show()
end

ns:Register("help", "talents", { order = 46, title = "Flow Talents", lines = {
    "/flow talents: your talent trees with Flow's levelling build over them: what to take now, what comes at each level, where it ends up.",
    "A reference only: spend your points in the game's talent window. Hover a talent for what it does.",
} })
