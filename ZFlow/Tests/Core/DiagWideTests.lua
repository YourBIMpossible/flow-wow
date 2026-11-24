-- Diag wide (DISPATCH sections 185 and 186): (a) every client name Core/Client.lua
-- reads is in the diag name list, so a missing one is never "not asked";
-- (b) once per login, after the world loads, the SHAPE of the reads the
-- lead and Lazy listed is saved: field names, types and counts only, never
-- a value, a name or any text. Fake client only; not tested in game.
local _, ns = ...

local Diag = ns.Diag

local function has(list, name)
    for i = 1, #(list or {}) do
        if list[i] == name then return true end
    end
    return false
end

-- Does any string inside v (keys of `fields` aside) equal one of `texts`?
local function holds(v, texts, depth)
    depth = depth or 0
    if depth > 20 then return false end
    if type(v) == "string" then
        for _, text in ipairs(texts) do
            if v == text then return true end
        end
        return false
    end
    if type(v) ~= "table" then return false end
    for key, value in pairs(v) do
        if type(key) == "string" then
            for _, text in ipairs(texts) do
                if key == text then return true end
            end
        end
        if holds(value, texts, depth + 1) then return true end
    end
    return false
end

-- The texts a real client would answer that must never be saved.
local TEXTS = { "Orgrimmar", "Devotion Aura", "Attack", "Interface\\Icons\\Bear", "boom" }

local function env()
    local auras = { { name = "Devotion Aura", expirationTime = 120, spellId = 465, sourceUnit = "player" },
        { name = "Devotion Aura", expirationTime = 0 }, { name = "Devotion Aura", expirationTime = 5 } }
    return {
        GetBuildInfo = function() return "1.16.1", "7777" end,
        CreateVector2D = function(x, y) return { x = x, y = y } end,
        C_TaxiMap = { GetTaxiNodesForMap = function(map)
            if map ~= 1414 then return {} end
            return { { name = "Orgrimmar", nodeID = 23, position = { x = 0.5, y = 0.5 } } }
        end },
        C_Map = { GetWorldPosFromMapPos = function(map, at) return map, { x = at.x * 100, y = at.y * 50 } end },
        C_UnitAuras = { GetAuraDataByIndex = function(unit, i, filter)
            if unit ~= "player" or filter ~= "HELPFUL" then return nil end
            return auras[i]
        end },
        C_Spell = {
            GetSpellCooldown = function() return { startTime = 0, duration = 0, isOnGCD = false, modRate = 1 } end,
            IsCurrentSpell = function() return false end,
            GetSpellInfo = function() return { name = "Attack", spellID = 6603, iconID = 135 } end,
        },
        GetShapeshiftForm = function() return 0 end,
        GetNumShapeshiftForms = function() return 2 end,
        GetShapeshiftFormInfo = function() return "Interface\\Icons\\Bear", false, true, 5487 end,
        IsCurrentSpell = function() return nil end,
        C_NamePlate = { GetNamePlates = function() return { {}, {} } end },
    }
end

local function start(e, saved)
    local c = ns.make.fakeClient({ env = e or env() })
    c.setSaved(ns.id.accountDB, saved or {})
    local k = ns.Kernel({}, c)
    Diag.Start(k)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return k, c
end

local function savedReads(c)
    local d = c.saved(ns.id.accountDB).diag
    return type(d) == "table" and d.reads or nil
end

local tests = {}

-- (a) --------------------------------------------------------------------

-- Every name Core/Client.lua read at 7ea3b50 that the list did not hold,
-- found from Client.lua itself (env.X, env.X.Y, a local alias of a client
-- namespace, container("X"), mapCall("X"), lookup("X")), and the names the
-- lead named in sections 185 and 186 that Client.lua does not read yet.
local WIDE = {
    "C_AddOns", "C_AddOns.GetAddOnMetadata", "C_AuctionHouse", "C_AuctionHouse.GetCommoditySearchResultInfo",
    "C_AuctionHouse.GetItemSearchResultInfo", "C_Bank", "C_CVar", "C_CVar.GetCVar", "C_Container",
    "C_DeathInfo", "C_DeathInfo.GetCorpseMapPosition", "C_Item", "C_Item.GetItemSpell", "C_Item.GetItemStats",
    "C_Map", "C_Map.GetUserWaypoint", "C_Map.HasUserWaypoint", "C_MerchantFrame", "C_Minimap",
    "C_Minimap.GetViewRadius", "C_NamePlate", "C_NamePlate.GetNamePlateForUnit", "C_PetBattles",
    "C_PetBattles.IsInBattle", "C_QuestLog", "C_QuestLog.GetLogIndexForQuestID", "C_QuestLog.IsFailed",
    "C_Spell", "C_Spell.GetSpellSubtext", "C_Spell.IsCurrentSpell", "C_SpellBook", "C_SuperTrack",
    "C_TooltipInfo", "C_TooltipInfo.GetHyperlink", "C_TradeSkillUI", "C_TradeSkillUI.IsDataSourceChanging",
    "C_UnitAuras", "CanDualWield", "ClassTrainerFrame", "CombatLogGetCurrentEventInfo", "ConsoleExec",
    "CreateVector2D", "Enum", "GetAddOnMetadata", "GetBindLocation", "GetCursorPosition",
    "GetInventoryItemDurability", "GetItemCooldown", "GetItemSpell", "GetItemStats", "GetLootRollItemLink",
    "GetLootSlotInfo", "GetLootSlotLink", "GetLootSourceInfo", "GetMinimapShape", "GetNumLootItems",
    "GetNumQuestWatches", "GetQuestIndexForWatch", "GetQuestLogIndexByID", "GetQuestLogSpecialItemInfo",
    "GetSpellSubtext", "GetSpellTexture", "GetSuperTrackedQuestID", "GetTrainerServiceLevelReq",
    "GetTrainerServiceSkillLine", "GetTrainerServiceTypeFilter", "GroupLootContainer",
    "InterfaceOptionsFrame_OpenToCategory", "InterfaceOptions_AddCategory", "IsAltKeyDown", "IsCurrentSpell",
    "IsInGroup", "IsMounted", "IsShiftKeyDown", "LOOT_ITEM_SELF", "LOOT_ITEM_SELF_MULTIPLE",
    "MERCHANT_ITEMS_PER_PAGE", "MerchantFrame", "MerchantFrame_Update", "NUM_GROUP_LOOT_FRAMES",
    "PowerBarColor", "Questie.db", "QuestieLoader", "SPEED", "STANDARD_TEXT_FONT", "Settings",
    "Sound_GameSystem_RestartSoundSystem", "TooltipDataProcessor", "UISpecialFrames", "UnitClassification",
    "UnitDetailedThreatSituation", "UnitGUID", "UnitGroupRolesAssigned", "UnitInVehicle", "UnitIsDeadOrGhost",
    "UnitIsFriend", "UnitIsGhost", "UnitIsPlayer", "UnitIsUnit", "UnitOnTaxi", "geterrorhandler",
    "hash_SlashCmdList", "print", "seterrorhandler", "time",
    "C_TaxiMap", "C_TaxiMap.GetTaxiNodesForMap", "GetTaxiNodesForMap", "UnitThreatSituation",
    "C_NamePlate.GetNamePlates",
    "Settings.RegisterVerticalLayoutCategory", "Settings.RegisterVerticalLayoutSubcategory",
    "Settings.RegisterProxySetting", "Settings.CreateCheckbox", "Settings.CreateCheckBox",
    "Settings.CreateSlider", "Settings.CreateSliderOptions", "Settings.CreateDropdown",
    "Settings.CreateDropDown", "Settings.CreateControlTextContainer",
    "CreateSettingsButtonInitializer", "CreateSettingsListSectionHeaderInitializer",
}

tests["diag wide (a): every name Client.lua reads is in the name list"] = function(t)
    for _, name in ipairs(WIDE) do t.ok(has(Diag.NAMES, name), name) end
end

tests["diag wide (a): the names the lead and Lazy named are listed"] = function(t)
    for _, name in ipairs({ "C_TaxiMap", "C_NamePlate", "UnitThreatSituation", "UnitDetailedThreatSituation",
        "UnitOnTaxi", "GetBindLocation", "C_Spell.IsCurrentSpell", "C_Spell.GetSpellInfo", "GetShapeshiftFormInfo",
        "GetNumShapeshiftForms", "issecretvalue", "GetSpellInfo" }) do
        t.ok(has(Diag.NAMES, name), name)
    end
end

tests["diag wide (a): no name is listed twice"] = function(t)
    local seen = {}
    for _, name in ipairs(Diag.NAMES) do
        t.ok(not seen[name], "once: " .. name)
        seen[name] = true
    end
end

tests["diag wide (a): a listed name the client lacks is saved as nil, not left out"] = function(t)
    local _, c = start()
    local names = c.saved(ns.id.accountDB).diag.names.names
    t.eq(names["UnitThreatSituation"], "nil")
    t.eq(names["C_TaxiMap.GetTaxiNodesForMap"], "function")
    t.eq(names["C_NamePlate"], "table")
end

-- (b) Form ----------------------------------------------------------------

tests["diag wide (b): a form is a type, never a value"] = function(t)
    t.eq(Diag.Form(nil), "nil")
    t.eq(Diag.Form(42), "number")
    t.eq(Diag.Form("Orgrimmar"), "string")
    t.eq(Diag.Form(true), "boolean")
    t.eq(Diag.Form(function() end), "function")
end

tests["diag wide (b): a table's form is its count, its field names and their types"] = function(t)
    local f = Diag.Form({ { name = "Orgrimmar", nodeID = 23 }, { name = "Crossroads" },
        name = "Attack", spellID = 6603, ["two words"] = 1, [false] = "x" })
    t.eq(f.type, "table")
    t.eq(f.count, 2, "the array part")
    t.eq(f.keys, 6, "every key counted")
    t.eq(f.fields, { name = "string", spellID = "number" }, "only names that read as field names")
    t.eq(f.first, { type = "table", count = 0, keys = 2, fields = { name = "string", nodeID = "number" } },
        "the first entry, one level down")
    t.eq(holds(f, TEXTS), false, "no text kept")
end

tests["diag wide (b): a form stops at two levels and at the key limit"] = function(t)
    local deep = Diag.Form({ { { { name = "Orgrimmar" } } } })
    t.eq(deep.first.first, nil, "two levels at most")
    local wide = {}
    for i = 1, 200 do wide["f" .. i] = i end
    local f = Diag.Form(wide)
    t.eq(f.keys, 200)
    local n = 0
    for _ in pairs(f.fields) do n = n + 1 end
    t.ok(n <= Diag.SHAPE_KEYS, "fields kept to the limit: " .. n)
end

tests["diag wide (b): a secret value is the type secret, and is not looked into"] = function(t)
    local function secret(v) return v == 77 end
    t.eq(Diag.Form(77, secret), "secret")
    local f = Diag.Form({ expirationTime = 77, duration = 5 }, secret)
    t.eq(f.fields, { expirationTime = "secret", duration = "number" })
    local hidden = { name = "Devotion Aura" }
    t.eq(Diag.Form(hidden, function(v) return v == hidden end), "secret")
end

-- (b) Reads ---------------------------------------------------------------

tests["diag wide (b): the reads say each call's shape"] = function(t)
    local c = ns.make.fakeClient({ env = env() })
    local R = Diag.Reads(c)
    t.eq(Diag.CONTINENTS, { 1414, 1415 })
    t.eq(R.taxi[1414].exists, "function")
    t.eq(R.taxi[1414].path, "C_TaxiMap.GetTaxiNodesForMap")
    t.eq(R.taxi[1414].ok, true)
    t.eq(R.taxi[1414].answers[1].count, 1)
    t.eq(R.taxi[1414].answers[1].first.fields, { name = "string", nodeID = "number", position = "table" })
    t.eq(R.taxi[1415].answers[1].count, 0)
    t.eq(R.worldPos[1414].answers[1], "number")
    t.eq(R.worldPos[1414].answers[2].fields, { x = "number", y = "number" })
    t.eq(R.aura.answers[1].fields, { name = "string", expirationTime = "number", spellId = "number",
        sourceUnit = "string" })
    t.eq(R.auraCount, 3, "rows until nil")
    t.eq(R.gcd.answers[1].fields, { startTime = "number", duration = "number", isOnGCD = "boolean",
        modRate = "number" })
    t.eq(R.form.answers, { "number" })
    t.eq(R.forms.answers, { "number" })
    t.eq(#R.formInfo, 2, "one for each form")
    t.eq(R.formInfo[1].answers, { "string", "boolean", "boolean", "number" })
    t.eq(R.current.n, 1)
    t.eq(R.current.answers, { "nil" })
    t.eq(R.currentNew.answers, { "boolean" })
    t.eq(R.spellInfo.answers[1].fields, { name = "string", spellID = "number", iconID = "number" })
    t.eq(R.secretFn, "nil")
    t.eq(R.nameplates, { exists = "function", ok = true, count = 2 })
    t.eq(holds(R, TEXTS), false, "no name, spell name, icon path or other text is kept")
end

tests["diag wide (b): the bare taxi call is asked when the namespaced one is missing"] = function(t)
    local e = env()
    e.GetTaxiNodesForMap, e.C_TaxiMap = e.C_TaxiMap.GetTaxiNodesForMap, nil
    local R = Diag.Reads(ns.make.fakeClient({ env = e }))
    t.eq(R.taxi[1414].path, "GetTaxiNodesForMap")
    t.eq(R.taxi[1414].answers[1].count, 1)
end

tests["diag wide (b): a missing name is said missing; nothing raises"] = function(t)
    local ok, R = pcall(Diag.Reads, ns.make.fakeClient({ env = {} }))
    t.ok(ok, "does not raise: " .. tostring(R))
    if not ok then return end
    t.eq(R.taxi[1414], { path = "C_TaxiMap.GetTaxiNodesForMap", exists = "nil", ok = false })
    t.eq(R.worldPos[1414].ok, false)
    t.eq(R.aura, { path = "C_UnitAuras.GetAuraDataByIndex", exists = "nil", ok = false })
    t.eq(R.auraCount, nil)
    t.eq(R.formInfo, {})
    t.eq(R.nameplates, { exists = "nil", ok = false })
    t.eq(R.secretFn, "nil")
end

tests["diag wide (b): a call that raises is ok false, and its error text is not kept"] = function(t)
    local e = env()
    e.GetShapeshiftForm = function() error("boom") end
    e.GetNumShapeshiftForms = function() error("boom") end
    e.C_UnitAuras.GetAuraDataByIndex = function() error("boom") end
    local R = Diag.Reads(ns.make.fakeClient({ env = e }))
    t.eq(R.form, { path = "GetShapeshiftForm", exists = "function", ok = false })
    t.eq(R.formInfo, {}, "no form count, no form rows")
    t.eq(R.auraCount, 0)
    t.eq(holds(R, TEXTS), false)
end

tests["diag wide (b): a secret answer is saved as secret"] = function(t)
    local e = env()
    e.issecretvalue = function(v) return v == 120 end
    local R = Diag.Reads(ns.make.fakeClient({ env = e }))
    t.eq(R.aura.answers[1].fields.expirationTime, "secret")
    t.eq(R.secretFn, "function")
end

-- (b) Saved once per login ----------------------------------------------

tests["diag wide (b): saved once, after the world has loaded and settled"] = function(t)
    local _, c = start()
    t.eq(savedReads(c), nil, "not at the login event itself")
    c.advance(9)
    local reads = savedReads(c)
    t.ok(type(reads) == "table" and #reads == 1, "one record once settled")
    if type(reads) ~= "table" or #reads ~= 1 then return end
    t.eq(reads[1].build, "1.16.1 (7777)")
    t.eq(reads[1].reads.auraCount, 3)
    c.fire("PLAYER_ENTERING_WORLD")
    c.advance(20)
    t.eq(#savedReads(c), 1, "a zone change after it adds none")
end

tests["diag wide (b): a new login adds one, and the newest KEEP are kept"] = function(t)
    local _, c = start()
    c.advance(9)
    local _, c2 = start(nil, c.saved(ns.id.accountDB))
    c2.advance(9)
    t.eq(#savedReads(c2), 2)
    local k3 = start(nil, c2.saved(ns.id.accountDB))
    for _ = 1, 3 * Diag.KEEP do Diag.SaveReads(k3, { auraCount = 1 }) end
    local d = k3.client.saved(ns.id.accountDB).diag
    t.eq(#d.reads, Diag.KEEP)
end

tests["diag wide (b): reads that raise cost a problem, not the login"] = function(t)
    local k, c = start()
    local real = Diag.Reads
    Diag.Reads = function() error("reads broke") end
    local ok, err = pcall(c.advance, 9)
    Diag.Reads = real
    t.ok(ok, "no error out of the frame: " .. tostring(err))
    t.eq(savedReads(c), nil)
    t.ok(k.problems:count("diag") >= 1, "kept as a diag problem")
end

return tests
