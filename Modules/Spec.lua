-- Levelling spec advice. /flow spec shows the recommendation and why.
-- It reminds you when you have unspent talent points.

local _, ns = ...

ns.ROLE_COLOR = { dps = "ff4040", heal = "40ff40", tank = "4090ff" }
ns.ROLE_LABEL = { dps = "DPS", heal = "Heal", tank = "Tank" }

-- Spec icon for a role (from class data), e.g. Retribution for dps.
function ns:RoleIconPath(role)
    local d = self:ClassData()
    local s = d and d.specs and d.specs[role]
    return s and s.icon
end

-- Inline icon for text ("|T...|t"), or the coloured role name if the class
-- has no icon for it.
function ns:RoleIcon(role, size)
    local path = self:RoleIconPath(role)
    if path then return string.format("|T%s:%d:%d:0:0:64:64:5:59:5:59|t", path, size or 14, size or 14) end
    return string.format("|cff%s%s|r", ns.ROLE_COLOR[role] or "ffffff", ns.ROLE_LABEL[role] or role)
end

-- Spec name for a role, e.g. "Retribution" (falls back to DPS/Heal/Tank).
function ns:RoleName(role)
    local d = self:ClassData()
    local s = d and d.specs and d.specs[role]
    return s and s.name or ns.ROLE_LABEL[role]
end

function ns:ClassData()
    local _, class = UnitClass("player")
    return ns:Get("class", class)
end

-- Every spell name a class trains or its rotation casts: { [name] = true }.
-- Used to tell which character old shared data came from (per-character
-- data, Core.lua): a fight with Moonfire in it was a druid's.
function ns:ClassSpellSet(class)
    local set = {}
    for _, s in ipairs(ns:Get("classSpells", class or "") or {}) do
        if s.spell then set[s.spell] = true end
    end
    local rot = ns:Get("rotation", class or "")
    for _, field in ipairs({ "heals", "buffs", "spells" }) do
        for _, s in ipairs(type(rot) == "table" and type(rot[field]) == "table" and rot[field] or {}) do
            if type(s) == "string" then set[s] = true end
        end
    end
    return set
end

-- Pure: the talent tree with the most points: its place (1 = leftmost) and
-- the tree. nil when no points are spent yet or two trees share the most
-- (a tie is no answer: never the leftmost by accident).
function ns.DominantTree(trees)
    local best, at, most, tie = nil, nil, 0, false
    for i, t in ipairs(trees or {}) do
        local p = tonumber(t.points) or 0
        if p > most then
            best, at, most, tie = t, i, p, false
        elseif p == most and p > 0 then
            tie = true
        end
    end
    if not best or tie then return nil end
    return at, best
end

-- Pure: the role whose spec is your talent tree with the most points.
-- specs: class data's { dps = { name = "Retribution" }, ... }; trees:
-- { { name = "Holy", points = 5 }, ... }. nil: no points yet, a tie, or a
-- tree no role is named after (a druid's Feral Combat is cat and bear).
function ns.RoleFromTrees(specs, trees)
    local _, best = ns.DominantTree(trees)
    if not best then return nil end
    for role, s in pairs(specs or {}) do
        if s.name == best.name then return role end
    end
    return nil
end

-- The trees on a class's talent sheet, left to right. WoW: Forever's
-- talents are one sheet (C_Traits) with no tree names, so a tree is named by
-- where it sits.
ns.TALENT_TREES = {
    PALADIN = { "Holy", "Protection", "Retribution" },
    DRUID   = { "Balance", "Feral Combat", "Restoration" },
}

-- Pure: talents from one sheet ({ x, y, rank }, as ns.talents.Read gives
-- them) into { { name, points } } per tree, left to right. nil when the
-- sheet doesn't split into as many trees as `names`.
function ns.TreesFromNodes(nodes, names)
    if not (ns.talents and ns.talents.Arrange) or #(nodes or {}) == 0 then return nil end
    local arranged = ns.talents.Arrange(nodes)
    if #arranged ~= #(names or {}) then return nil end
    local out = {}
    for i, tr in ipairs(arranged) do
        local points = 0
        for _, n in ipairs(tr.nodes) do points = points + (tonumber(n.rank) or 0) end
        out[i] = { name = names[i], points = points }
    end
    return out
end

-- A remembered talent read. A good read (the trees, even with no points
-- spent) is kept until your talents change (Forget). A read that found
-- nothing (at login the game often has no talent loadout yet) is tried
-- again `retry` seconds later instead of being kept for the session: Flow
-- once kept "no talents" until the next /reload.
-- read: () -> trees or nil (nil = the game couldn't say); clock: () -> seconds.
-- Its own functions are passed in, so the tests can run it.
function ns.TalentCache(read, clock, retry)
    local cache = { trees = nil, retryAt = nil }
    function cache:Get()
        if self.trees then return self.trees end
        local now = clock()
        if self.retryAt and now < self.retryAt then return {} end
        local ok, trees = pcall(read)
        if ok and type(trees) == "table" and #trees > 0 then
            self.trees, self.retryAt = trees, nil
            return trees
        end
        self.retryAt = now + (retry or 5)
        return {}
    end
    function cache:Forget() self.trees, self.retryAt = nil, nil end
    return cache
end

-- Your talent trees, read through Flow Talents' reader (ns.talents.Read: the
-- client's talent sheet, C_ClassTalents / C_Traits, or the classic talent
-- API where that's all there is). "Still not suggesting Righteous Fury":
-- Forever has no classic talent API, so Flow saw no talents at all.
local function readTrees()
    local class = UnitClass and select(2, UnitClass("player"))
    local names = ns.TALENT_TREES[class or ""]
    if not (names and ns.talents and ns.talents.Read) then return nil end
    return ns.TreesFromNodes((ns.talents.Read()), names)
end
local talents = ns.TalentCache(readTrees, function() return GetTime() end, 5)
for _, event in ipairs({ "CHARACTER_POINTS_CHANGED", "PLAYER_TALENT_UPDATE", "PLAYER_ENTERING_WORLD",
                         "TRAIT_CONFIG_UPDATED", "TRAIT_NODE_CHANGED" }) do
    ns:On(event, function() talents:Forget() end)
end

-- Your talent trees, { { name, points } } (empty when Flow can't read them yet).
function ns:TalentTrees() return talents:Get() end

-- The talent tree you've put the most points in ("Protection"), or nil (none
-- yet, a tie, unreadable). Your talents as they are, whatever role you chose:
-- for a mechanic that only a talent gives. What Flow plays you as is
-- ns:LevelingRole().
function ns:TalentTree()
    local _, best = ns.DominantTree(self:TalentTrees())
    return best and best.name or nil
end

-- The role your talents say (dps/heal/tank), or nil.
function ns:TalentRole()
    local d = self:ClassData()
    return ns.RoleFromTrees(d and d.specs, self:TalentTrees())
end

-- Pure: the role Flow plays you as, and why. chosen: your own choice (or
-- nil for Auto); talent: the role your talents say (or nil); default: your
-- class's recommended levelling role. Returns role, "chosen" | "talents" |
-- "class".
function ns.ResolveRole(chosen, talent, default)
    if chosen == "dps" or chosen == "heal" or chosen == "tank" then return chosen, "chosen" end
    if talent then return talent, "talents" end
    return default or "dps", "class"
end

-- THE role Flow plays you as: gear, food, fight records, a paladin's seal,
-- blessing and Righteous Fury, a druid's Bear Form. Everything that depends
-- on your role asks this (one answer everywhere): your own choice
-- (Settings, Easy keys, "Your role"; /flow spec dps|heal|tank) beats your
-- talents (the tree with the most points), which beat your class's
-- recommended levelling role. One value: callers pass it straight on.
-- "Why don't we have an option to set your spec?"
local function resolveMine()
    local d = ns:ClassData()
    return ns.ResolveRole(ns.db and ns.db.spec and ns.db.spec.role, ns:TalentRole(),
        d and d.leveling and d.leveling.role)
end
function ns:LevelingRole()
    return (resolveMine())
end

-- Where ns:LevelingRole() came from: "chosen", "talents" or "class".
function ns:RoleSource()
    local _, source = resolveMine()
    return source
end

local function unspentPoints()
    -- (Flow Talents reads the game's own count, whichever talent system the client has.)
    if ns.talents and ns.talents.Unspent then return ns.talents.Unspent() end
    if UnitCharacterPoints then return UnitCharacterPoints("player") or 0 end
    return 0
end

local function describe()
    local d = ns:ClassData()
    if not d then ns:Print("no spec advice for your class yet."); return end
    local rec = d.leveling.role
    ns:Print(string.format("recommended levelling spec: |cff%s%s|r (%s)",
        ns.ROLE_COLOR[rec], d.specs[rec].name, ns.ROLE_LABEL[rec]))
    for _, line in ipairs(d.leveling.why) do print("  - " .. line) end
    local mine, source = ns:LevelingRole(), ns:RoleSource()
    if mine ~= rec and d.specs[mine] then
        print(string.format("  Your role: |cff%s%s|r (%s, %s).", ns.ROLE_COLOR[mine], ns.ROLE_LABEL[mine],
            d.specs[mine].name, source == "chosen" and "your choice" or "your talents"))
    end
    local _, class = UnitClass("player")
    print(ns:Get("talentBuild", class or "")
        and "  Point by point: /flow talents (Flow Talents: what to take now and at each level)."
        or "  /flow talents shows your trees; there's no point-by-point build for your class yet.")
end

ns:OnLoad(function(saved) saved.spec = saved.spec or {} end)
ns:PerCharacter("spec")   -- your role choice; nothing kept from before (it was shared)

ns:On("PLAYER_LOGIN", function()
    if UnitLevel("player") >= 10 and unspentPoints() > 0 then
        ns:Print(string.format("you have %d unspent talent point(s). /flow talents shows what to take.", unspentPoints()))
    end
end)

ns:On("PLAYER_LEVEL_UP", function(level)
    if level == 10 then
        ns:Print("talents unlocked!")
        describe()
    end
end)

ns.commands.spec = function(arg)
    arg = (arg or ""):lower()
    if arg == "dps" or arg == "heal" or arg == "tank" then
        ns.db.spec.role = arg
        ns:Print("role: " .. ns.ROLE_LABEL[arg] .. " (" .. ns:RoleName(arg) .. "), whatever your talents: gear, food, seals...")
    elseif arg == "auto" then
        ns.db.spec.role = nil
        ns:Print("role: automatic (your talents; before talents, the recommended levelling spec)")
    else
        describe()
        print("  Your role: /flow spec dps|heal|tank|auto, or Settings, Easy keys, \"Your role\"")
    end
end

-- /flow talents: this client's talent trees (tab, tier, column, ranks), so
-- the talent plan can be written for Forever's real trees. Also in the
-- diagnostics snapshot.
ns.commands.talents = function()
    if not (GetNumTalentTabs and GetNumTalents and GetTalentInfo) then
        ns:Print("this client has no classic talent API" .. (C_ClassTalents and " (it has C_ClassTalents)" or ""))
        return
    end
    local tabs = GetNumTalentTabs() or 0
    ns:Print(string.format("talents: %d tab(s), %d point(s) to spend", tabs,
        UnitCharacterPoints and UnitCharacterPoints("player") or 0))
    for tab = 1, tabs do
        local name = GetTalentTabInfo and GetTalentTabInfo(tab)
        if type(name) == "number" then name = select(2, GetTalentTabInfo(tab)) end
        print(string.format("  tab %d: %s", tab, tostring(name)))
        for i = 1, GetNumTalents(tab) or 0 do
            local tname, _, tier, column, rank, maxRank = GetTalentInfo(tab, i)
            print(string.format("    %d.%d %s  tier %s col %s  %s/%s", tab, i, tostring(tname),
                tostring(tier), tostring(column), tostring(rank), tostring(maxRank)))
        end
    end
end

-- Modern talents (C_ClassTalents / C_Traits): each node with its position,
-- ranks and spell names. Used by /flow talents when the classic API is gone.
local function dumpTraits()
    local cfg = C_ClassTalents.GetActiveConfigID and C_ClassTalents.GetActiveConfigID()
    if not cfg then ns:Print("talents: no active talent loadout yet (talents may unlock at a later level)") return end
    local info = C_Traits.GetConfigInfo(cfg)
    local unspent = 0
    for _, treeID in ipairs(info and info.treeIDs or {}) do
        local ok, currencies = pcall(C_Traits.GetTreeCurrencyInfo, cfg, treeID, false)
        for _, c in ipairs(ok and currencies or {}) do unspent = unspent + (c.quantity or 0) end
    end
    ns:Print(string.format("talents (modern): config %s, unspent %d", tostring(cfg), unspent))
    local n = 0
    for _, treeID in ipairs(info and info.treeIDs or {}) do
        for _, nodeID in ipairs(C_Traits.GetTreeNodes(treeID) or {}) do
            local node = C_Traits.GetNodeInfo(cfg, nodeID)
            if node and node.ID ~= 0 and (node.maxRanks or 0) > 0 then
                -- What it does (the game's own text, cut short) and which
                -- talents it leads to: for writing a class's talentBuild.
                local names, what = {}, nil
                for _, entryID in ipairs(node.entryIDs or {}) do
                    local e = C_Traits.GetEntryInfo(cfg, entryID)
                    local def = e and e.definitionID and C_Traits.GetDefinitionInfo(e.definitionID)
                    local spell = def and (def.overrideName or (def.spellID and ns.api.SpellInfo(def.spellID)))
                    names[#names + 1] = tostring(spell or ("entry " .. entryID))
                    if not what and def and def.spellID and ns.api.Description then
                        local okD, text = pcall(ns.api.Description, def.spellID)
                        if okD and type(text) == "string" and text ~= "" then what = text:gsub("%s+", " "):sub(1, 150) end
                    end
                end
                local leads = {}
                for _, edge in ipairs(node.visibleEdges or {}) do leads[#leads + 1] = tostring(edge.targetNode) end
                n = n + 1
                if n <= 120 then
                    print(string.format("    node %d at %d,%d  %d/%d  %s%s%s", nodeID, node.posX or 0, node.posY or 0,
                        node.currentRank or 0, node.maxRanks or 0, table.concat(names, " | "),
                        #leads > 0 and ("  -> " .. table.concat(leads, ",")) or "",
                        what and ("  :: " .. what) or ""))
                end
            end
        end
    end
    if n > 120 then print(string.format("    ...and %d more nodes", n - 120)) end
end

local classicTalents = ns.commands.talents
ns.commands.talents = function()
    if not (GetNumTalentTabs and GetTalentInfo) and C_ClassTalents and C_Traits then
        local ok, err = pcall(dumpTraits)
        if not ok then ns:Print("talents: " .. tostring(err)) end
        return
    end
    classicTalents()
end
