-- Diagnostic collector for development builds. It writes what this client
-- actually answers into the account saved table under `diag`, so the
-- answers can be read from the saved file after a reload or logout instead
-- of being typed back by hand.
--
-- It only reads. It never buys, sells, casts, moves an item or changes a
-- setting. It runs even when the load guard has paused the addon, because
-- the guard's verdict is one of the things it records; with the dev panel
-- (UI/DevPanel.lua) it is all a paused addon keeps listening with.
--
-- Lua errors the client reports are kept with each snapshot.
--
--   <slash> diag          take a snapshot now and say where it went
--   <slash> diag clear    forget every snapshot
--   <slash> import        read the predecessor's saved data, when the client
--                         has loaded any, and say what an import would leave
--                         behind or change. Nothing is imported or written.
--
-- Snapshots are also taken at login, a few seconds after it (what was not
-- ready at login is by then), and when the bank, a vendor, a trainer, a
-- profession window or the flight map opens; a trainer and a profession
-- window get a second one when the client says their list has arrived. The
-- newest KEEP are kept. Each start also saves `api`: the names inside the
-- client's namespaces, so the next build is written from what is there.
local _, ns = ...

local Diag = {}
ns.Diag = Diag

local KEEP = 40
local SHAPE_KEYS = 60
-- Seconds after login for the "settled" snapshot, and the gap inside which
-- the same window event again takes no second snapshot.
local SETTLE, SAME_WINDOW, LATE = 8, 5, 3
local ERRORS_KEPT = 40

-- Client names whose presence decides how the boundary is written.
Diag.NAMES = {
    "GetBuildInfo", "GetTime", "debugprofilestop", "CreateFrame", "C_Timer.After", "SlashCmdList",
    "C_AddOns.IsAddOnLoaded", "IsAddOnLoaded", "C_AddOns.GetAddOnEnableState", "InCombatLockdown",
    "GetMoney", "NUM_BAG_SLOTS", "NUM_TOTAL_EQUIPPED_BAG_SLOTS", "NUM_BANKBAGSLOTS", "BANK_CONTAINER",
    "REAGENTBANK_CONTAINER", "Enum.BagIndex", "BankFrame",
    "C_Container.GetContainerNumSlots", "GetContainerNumSlots",
    "C_Container.GetContainerNumFreeSlots", "GetContainerNumFreeSlots",
    "C_Container.GetContainerItemInfo", "GetContainerItemInfo",
    "C_Container.GetContainerItemLink", "GetContainerItemLink",
    "GetItemInfo", "C_Item.GetItemInfo", "GetItemCount", "C_Item.GetItemCount", "GetItemInfoInstant",
    "C_Map.GetBestMapForUnit", "C_Map.GetPlayerMapPosition", "C_Map.GetMapInfo",
    "C_Map.GetWorldPosFromMapPos", "Enum.UIMapType", "GetPlayerFacing", "UnitPosition",
    "GetZoneText", "GetSubZoneText", "GetRealZoneText",
    "UnitClass", "UnitLevel", "UnitRace", "UnitFactionGroup", "UnitHealth", "UnitHealthMax",
    "UnitPower", "UnitPowerMax", "UnitPowerType", "UnitMana", "UnitExists", "UnitIsDead",
    "UnitCanAttack", "UnitAffectingCombat", "UnitCastingInfo", "UnitChannelInfo", "CastingInfo",
    "UnitBuff", "UnitDebuff", "UnitAura", "C_UnitAuras.GetAuraDataByIndex", "AuraUtil.ForEachAura",
    "GetShapeshiftForm", "GetNumShapeshiftForms", "GetShapeshiftFormInfo", "IsStealthed",
    "GetSpellInfo", "C_Spell.GetSpellInfo", "GetSpellCooldown", "C_Spell.GetSpellCooldown",
    "IsUsableSpell", "C_Spell.IsSpellUsable", "IsSpellInRange", "IsSpellKnown", "IsPlayerSpell",
    "GetNumSpellTabs", "GetSpellTabInfo", "GetSpellBookItemName", "GetSpellBookItemInfo", "GetSpellName",
    "C_SpellBook.GetNumSpellBookSkillLines", "GetNumTalentTabs", "GetNumTalents", "GetTalentInfo",
    "GetComboPoints", "GetInventoryItemLink", "GetInventoryItemID", "GetWeaponEnchantInfo",
    "SetBinding", "SetBindingClick", "SetOverrideBindingClick", "ClearOverrideBindings", "GetBindingKey",
    "SaveBindings", "GetCurrentBindingSet", "RegisterStateDriver", "SecureCmdOptionParse",
    "GetNumQuestLogEntries", "GetQuestLogTitle", "C_QuestLog.GetNumQuestLogEntries", "C_QuestLog.GetInfo",
    "GetNumQuestLeaderBoards", "GetQuestLogLeaderBoard", "C_QuestLog.GetQuestObjectives",
    "GetNumSkillLines", "GetSkillLineInfo", "GetProfessions", "GetProfessionInfo",
    "GetNumTradeSkills", "GetTradeSkillInfo", "GetTradeSkillLine", "GetTradeSkillNumReagents",
    "GetTradeSkillReagentInfo", "GetTradeSkillItemLink", "GetTradeSkillRecipeLink",
    "C_TradeSkillUI.GetAllRecipeIDs", "GetNumCrafts", "GetCraftInfo",
    "GetNumTrainerServices", "GetTrainerServiceInfo", "GetTrainerServiceCost", "GetTrainerServiceSkillReq",
    "GetMerchantNumItems", "GetMerchantItemInfo", "GetMerchantItemLink", "C_MerchantFrame.GetItemInfo",
    "CanMerchantRepair", "GetRepairAllCost",
    "NumTaxiNodes", "TaxiNodeName", "TaxiNodeGetType", "TaxiNodeCost",
    "C_ChatInfo.RegisterAddonMessagePrefix", "C_ChatInfo.SendAddonMessage", "SendAddonMessage",
    "hooksecurefunc", "GameTooltip", "WorldMapFrame", "Minimap", "UIParent",
    "C_Timer.NewTicker", "GetCVar", "GetLocale", "GetRealmName", "UnitName",
    -- Asked after the first real-client session: that client has the
    -- namespaced calls and lacks most of the bare ones above.
    "GetNormalizedRealmName", "UnitFullName", "issecretvalue", "canaccessvalue",
    "C_SpellBook.GetSpellBookSkillLineInfo", "C_SpellBook.GetSpellBookItemInfo",
    "C_SpellBook.GetSpellBookItemName", "C_SpellBook.IsSpellKnown", "Enum.SpellBookSpellBank",
    "C_Spell.GetSpellName", "C_Spell.IsSpellInRange", "C_Spell.GetSpellTexture",
    "C_QuestLog.GetTitleForLogIndex", "C_QuestLog.GetQuestIDForLogIndex", "C_QuestLog.IsComplete",
    "C_TradeSkillUI.GetRecipeInfo", "C_TradeSkillUI.GetRecipeSchematic", "C_TradeSkillUI.GetBaseProfessionInfo",
    "C_TradeSkillUI.GetChildProfessionInfo", "C_TradeSkillUI.GetProfessionInfoBySkillLineID",
    "C_TradeSkillUI.GetAllProfessionTradeSkillLines", "C_TradeSkillUI.IsTradeSkillReady",
    "C_TradeSkillUI.GetRecipeItemLink", "C_TradeSkillUI.GetTradeSkillLine",
    "C_Traits.GetConfigInfo", "C_ClassTalents.GetActiveConfigID", "C_SpecializationInfo.GetTalentInfo",
    "C_Bank.CanViewBank", "C_Bank.FetchPurchasedBankTabIDs", "C_Bank.FetchNumPurchasedBankTabs",
    "Enum.BankType", "C_PlayerInteractionManager.IsInteractingWithNpcOfType", "Enum.PlayerInteractionType",
    "C_UnitAuras.GetBuffDataByIndex", "C_UnitAuras.GetPlayerAuraBySpellID",
    "C_Item.GetItemInfoInstant", "C_Item.GetItemNameByID", "C_Container.GetBagName",
}

-- Namespaces whose member names are saved once per start, and the patterns
-- of bare global names saved with them.
Diag.NAMESPACES = {
    "C_TradeSkillUI", "C_SpellBook", "C_Spell", "C_QuestLog", "C_Container", "C_Item", "C_MerchantFrame",
    "C_Bank", "C_Traits", "C_ClassTalents", "C_SpecializationInfo", "C_UnitAuras", "C_Map", "C_AddOns",
    "C_Timer", "C_ChatInfo", "C_PlayerInteractionManager", "C_TaxiMap", "C_SkillInfo", "C_PlayerInfo",
    "Enum.BagIndex", "Enum.BankType", "Enum.SpellBookSpellBank", "Enum.PlayerInteractionType",
}
Diag.GLOBALS = { "^C_", "Talent", "Skill", "Trainer", "Craft", "Profession", "Bank", "Realm", "Taxi" }

local function plain(v)
    local t = type(v)
    return t == "number" or t == "string" or t == "boolean"
end

-- What a call answered, as plain saveable data: ok, how many values, their
-- types, and the values that are numbers, strings or booleans. A table
-- answer is listed by key, one level deep (plain values kept, others by
-- type), SHAPE_KEYS keys at most.
local function shape(ok, ...)
    local n = select("#", ...)
    local row = { ok = ok and true or false, n = n, types = {}, values = {} }
    for i = 1, n do
        local v = select(i, ...)
        row.types[i] = type(v)
        if plain(v) then
            row.values["v" .. i] = v
        elseif type(v) == "table" then
            local keys, kept = {}, 0
            for key, value in pairs(v) do
                if kept >= SHAPE_KEYS then break end
                keys[tostring(key)] = plain(value) and value or type(value)
                kept = kept + 1
            end
            row.values["v" .. i] = keys
        end
    end
    return row
end
Diag.Shape = shape

-- { profession, skill, max, total, learned } of a recipes() reading, or nil.
local function recipeCounts(r)
    if type(r) ~= "table" then return nil end
    local learned = 0
    for i = 1, #r.recipes do
        if r.recipes[i].learned then learned = learned + 1 end
    end
    return { profession = r.profession, skill = r.skill, max = r.max, total = #r.recipes, learned = learned }
end

-- The size of the map the player is on, or nil.
local function mapSizeHere(client)
    local at = client.position()
    return at and client.mapSize(at.map) or nil
end

local function ask(client, path, ...)
    return shape(client.raw(path, ...))
end

-- The first bag slot with something in it, by whichever call exists.
local function firstItem(client)
    for bag = 0, 4 do
        local ok, total = client.raw("C_Container.GetContainerNumSlots", bag)
        if not ok then ok, total = client.raw("GetContainerNumSlots", bag) end
        if ok and type(total) == "number" then
            for slot = 1, total do
                local okA, a = client.raw("C_Container.GetContainerItemInfo", bag, slot)
                if not okA then okA, a = client.raw("GetContainerItemInfo", bag, slot) end
                if okA and a ~= nil then return bag, slot end
            end
        end
    end
    return nil
end

local function count(list)
    return type(list) == "table" and #list or nil
end

-- One snapshot. `why` says what asked for it. It calls only the client of
-- the kernel it is handed, so it runs the same over the fake client.
function Diag.Collect(k, why)
    local client = k.client
    local snap = { why = tostring(why), at = client.now(), names = {}, shapes = {}, kernel = {} }

    for i = 1, #Diag.NAMES do
        local name = Diag.NAMES[i]
        snap.names[name] = client.typeOf(name)
    end

    snap.reads = {
        money = client.money(), combatLockdown = client.combatLockdown(), inCombat = client.inCombat(),
        bags = client.bags(), bagStacks = count(client.bagItems()),
        bankOpen = client.bankOpen(), bankStacks = count(client.bankItems()),
        position = client.position(), zone = client.zone(),
        mapSize = mapSizeHere(client),
        recipes = recipeCounts(client.recipes()),
        predecessorLoaded = client.addonLoaded(k.id.predecessor),
        predecessorData = client.savedExists(k.id.predecessorDB),
        selfLoaded = client.addonLoaded(k.id.addon),
    }
    -- Whether each read came back known: a nil above leaves no trace when saved.
    snap.known = {}
    for _, name in ipairs({ "money", "combatLockdown", "bags", "bagStacks", "bankOpen", "bankStacks", "position", "zone" }) do
        snap.known[name] = snap.reads[name] ~= nil
    end

    local S = snap.shapes
    S.build = ask(client, "GetBuildInfo")
    S.locale = ask(client, "GetLocale")
    S.class = ask(client, "UnitClass", "player")
    S.level = ask(client, "UnitLevel", "player")
    S.faction = ask(client, "UnitFactionGroup", "player")
    S.facing = ask(client, "GetPlayerFacing")
    S.form = ask(client, "GetShapeshiftForm")
    S.forms = ask(client, "GetNumShapeshiftForms")
    S.health = ask(client, "UnitHealth", "player")
    S.power = ask(client, "UnitPower", "player")
    S.powerType = ask(client, "UnitPowerType", "player")
    S.spellTabs = ask(client, "GetNumSpellTabs")
    S.spellTab1 = ask(client, "GetSpellTabInfo", 1)
    S.spellBook1 = ask(client, "GetSpellBookItemName", 1, "spell")
    S.spellName1 = ask(client, "GetSpellName", 1, "spell")
    S.talentTabs = ask(client, "GetNumTalentTabs")
    S.talent11 = ask(client, "GetTalentInfo", 1, 1)
    S.skillLines = ask(client, "GetNumSkillLines")
    S.skillLine1 = ask(client, "GetSkillLineInfo", 1)
    S.quests = ask(client, "GetNumQuestLogEntries")
    S.quest1 = ask(client, "GetQuestLogTitle", 1)
    S.bestMap = ask(client, "C_Map.GetBestMapForUnit", "player")
    S.zoneText = ask(client, "GetRealZoneText")
    S.freeSlots0 = ask(client, "C_Container.GetContainerNumFreeSlots", 0)
    S.freeSlots0Old = ask(client, "GetContainerNumFreeSlots", 0)
    S.bindingSet = ask(client, "GetCurrentBindingSet")
    S.selfEnabled = ask(client, "C_AddOns.GetAddOnEnableState", k.id.addon)

    local bag, slot = firstItem(client)
    if bag then
        S.slotInfo = ask(client, "C_Container.GetContainerItemInfo", bag, slot)
        S.slotInfoOld = ask(client, "GetContainerItemInfo", bag, slot)
        S.slotLink = ask(client, "C_Container.GetContainerItemLink", bag, slot)
        S.slotLinkOld = ask(client, "GetContainerItemLink", bag, slot)
        local link = S.slotLink.ok and S.slotLink.values.v1 or (S.slotLinkOld.ok and S.slotLinkOld.values.v1) or nil
        if type(link) == "string" then
            S.itemInfo = ask(client, "GetItemInfo", link)
            S.itemInfoNew = ask(client, "C_Item.GetItemInfo", link)
            S.itemInstant = ask(client, "GetItemInfoInstant", link)
        end
    end

    -- Windows: each of these answers "nothing" while its window is shut.
    S.merchantItems = ask(client, "GetMerchantNumItems")
    S.merchant1 = ask(client, "GetMerchantItemInfo", 1)
    S.merchant1New = ask(client, "C_MerchantFrame.GetItemInfo", 1)
    S.canRepair = ask(client, "CanMerchantRepair")
    S.trainerServices = ask(client, "GetNumTrainerServices")
    S.trainer1 = ask(client, "GetTrainerServiceInfo", 1)
    S.trainer1Cost = ask(client, "GetTrainerServiceCost", 1)
    S.tradeSkills = ask(client, "GetNumTradeSkills")
    S.tradeSkillLine = ask(client, "GetTradeSkillLine")
    S.tradeSkill1 = ask(client, "GetTradeSkillInfo", 1)
    S.tradeSkill2 = ask(client, "GetTradeSkillInfo", 2)
    S.tradeSkill2Reagents = ask(client, "GetTradeSkillNumReagents", 2)
    S.tradeSkill2Reagent1 = ask(client, "GetTradeSkillReagentInfo", 2, 1)
    S.crafts = ask(client, "GetNumCrafts")
    S.taxiNodes = ask(client, "NumTaxiNodes")

    -- The namespaced calls. Arguments here are first guesses: a wrong one
    -- is recorded as an error or an empty answer, which is the finding.
    S.realm = ask(client, "GetRealmName")
    S.realmNormalized = ask(client, "GetNormalizedRealmName")
    S.fullName = ask(client, "UnitFullName", "player")
    -- Health was saved with a type and no value: ask how the client prints
    -- it and whether it calls it a secret.
    local okHealth, health = client.raw("UnitHealth", "player")
    if okHealth and health ~= nil then
        S.healthText = shape(pcall(tostring, health))
        S.healthSecret = ask(client, "issecretvalue", health)
        S.healthIsItself = shape(pcall(function() return health == health end))
    end
    S.healthMax = ask(client, "UnitHealthMax", "player")
    S.questEntries = ask(client, "C_QuestLog.GetNumQuestLogEntries")
    S.questInfo1 = ask(client, "C_QuestLog.GetInfo", 1)
    S.questInfo2 = ask(client, "C_QuestLog.GetInfo", 2)
    local questID = S.questInfo2.ok and type(S.questInfo2.values.v1) == "table" and S.questInfo2.values.v1.questID
    if type(questID) == "number" then
        S.questObjectives = ask(client, "C_QuestLog.GetQuestObjectives", questID)
    end
    S.bookLines = ask(client, "C_SpellBook.GetNumSpellBookSkillLines")
    S.bookLine1 = ask(client, "C_SpellBook.GetSpellBookSkillLineInfo", 1)
    S.bookLine2 = ask(client, "C_SpellBook.GetSpellBookSkillLineInfo", 2)
    S.bookItem1 = ask(client, "C_SpellBook.GetSpellBookItemInfo", 1, 0)
    S.bookItemName1 = ask(client, "C_SpellBook.GetSpellBookItemName", 1, 0)
    local spellID = S.bookItem1.ok and type(S.bookItem1.values.v1) == "table"
        and (S.bookItem1.values.v1.spellID or S.bookItem1.values.v1.actionID)
    if type(spellID) == "number" then
        S.spellInfo = ask(client, "C_Spell.GetSpellInfo", spellID)
        S.spellCooldown = ask(client, "C_Spell.GetSpellCooldown", spellID)
        S.spellUsable = ask(client, "C_Spell.IsSpellUsable", spellID)
        S.spellKnown = ask(client, "IsPlayerSpell", spellID)
    end
    S.spellByName = ask(client, "C_Spell.GetSpellInfo", "Attack")
    S.aura1 = ask(client, "C_UnitAuras.GetAuraDataByIndex", "player", 1, "HELPFUL")
    S.professions = ask(client, "GetProfessions")
    if S.professions.ok and type(S.professions.values.v1) == "number" then
        S.profession1 = ask(client, "GetProfessionInfo", S.professions.values.v1)
    end
    S.tradeLines = ask(client, "C_TradeSkillUI.GetAllProfessionTradeSkillLines")
    S.tradeBase = ask(client, "C_TradeSkillUI.GetBaseProfessionInfo")
    S.tradeChild = ask(client, "C_TradeSkillUI.GetChildProfessionInfo")
    S.tradeReady = ask(client, "C_TradeSkillUI.IsTradeSkillReady")
    local okRecipes, recipes = client.raw("C_TradeSkillUI.GetAllRecipeIDs")
    S.recipeCount = shape(okRecipes, type(recipes) == "table" and #recipes or recipes)
    -- In the game on 16001 the full list was empty with the window open and
    -- ready: ask the other ways the client has of naming what is in it.
    local okShown, shown = client.raw("C_TradeSkillUI.GetFilteredRecipeIDs")
    S.recipeShownCount = shape(okShown, type(shown) == "table" and #shown or shown)
    S.tradeChildren = ask(client, "C_TradeSkillUI.GetChildProfessionInfos")
    S.tradeChildLine = ask(client, "C_TradeSkillUI.GetProfessionChildSkillLineID")
    S.tradeCategories = ask(client, "C_TradeSkillUI.GetCategories")
    S.tradeDataSource = ask(client, "C_TradeSkillUI.IsDataSourceChanging")
    local base = S.tradeBase.ok and type(S.tradeBase.values.v1) == "table" and S.tradeBase.values.v1.professionID
    if type(base) == "number" then
        S.tradeByLine = ask(client, "C_TradeSkillUI.GetProfessionInfoBySkillLineID", base)
    end
    local recipe = okRecipes and type(recipes) == "table" and recipes[1]
    if type(recipe) ~= "number" then recipe = okShown and type(shown) == "table" and shown[1] end
    if type(recipe) == "number" then
        S.recipeInfo = ask(client, "C_TradeSkillUI.GetRecipeInfo", recipe)
        S.recipeSchematic = ask(client, "C_TradeSkillUI.GetRecipeSchematic", recipe, false)
        S.recipeItemLink = ask(client, "C_TradeSkillUI.GetRecipeItemLink", recipe)
        -- What a recipe needs: the first reagent slot and its first reagent.
        local okPlan, plan = client.raw("C_TradeSkillUI.GetRecipeSchematic", recipe, false)
        local slots = okPlan and type(plan) == "table" and plan.reagentSlotSchematics
        local need = type(slots) == "table" and slots[1]
        S.recipeSlotCount = shape(okPlan, type(slots) == "table" and #slots or slots)
        if type(need) == "table" then
            S.recipeSlot1 = shape(true, need)
            local reagents = need.reagents
            if type(reagents) == "table" then S.recipeSlot1Reagent1 = shape(true, reagents[1]) end
        end
    end
    S.trainer1Req = ask(client, "GetTrainerServiceSkillReq", 1)
    S.merchant1Link = ask(client, "GetMerchantItemLink", 1)
    S.taxi1 = ask(client, "TaxiNodeName", 1)
    S.taxi1Type = ask(client, "TaxiNodeGetType", 1)
    S.bankCanView = ask(client, "C_Bank.CanViewBank", 0)
    S.bankTabs = ask(client, "C_Bank.FetchPurchasedBankTabIDs", 0)
    S.activeTalentConfig = ask(client, "C_ClassTalents.GetActiveConfigID")

    local K = snap.kernel
    K.phase, K.paused = k.phase, k.paused and true or false
    K.pauseText = k.pausePanel and k.pausePanel.text or nil
    K.storeOpened = k.store.opened and true or false
    K.blocked = {}
    for scope, reason in pairs(k.store.blocked) do K.blocked[scope] = reason end
    K.problems = {}
    for _, p in ipairs(k.problems:list()) do
        K.problems[#K.problems + 1] = { kind = p.kind, owner = p.owner, text = p.text, count = p.count }
    end
    K.meter = k.meter:report()
    return snap
end

-- The member names of the client's namespaces and the bare global names
-- that matter here, as plain data. Saved once per start.
function Diag.Api(client)
    local api = { namespaces = {}, globals = {} }
    for _, name in ipairs(Diag.NAMESPACES) do
        api.namespaces[name] = client.peek(name) or false
    end
    for _, pattern in ipairs(Diag.GLOBALS) do
        api.globals[pattern] = client.globalNames(pattern)
    end
    return api
end

-- Puts a snapshot in the saved table and trims to the newest KEEP.
function Diag.Save(k, snap)
    local db = k.client.saved(k.id.accountDB)
    if type(db.diag) ~= "table" then db.diag = {} end
    local d = db.diag
    if type(d.snaps) ~= "table" then d.snaps = {} end
    d.snaps[#d.snaps + 1] = snap
    while #d.snaps > KEEP do table.remove(d.snaps, 1) end
    d.count = (tonumber(d.count) or 0) + 1
    return d
end

-- What an import left behind or changed, as lines to print.
--   Diag.ImportReport(result) -> lines, counts
--     result  what Import.FromFlow returned (Import/FromFlow.lua)
--     lines   the counts of dropped, adjusted and malformed entries, then one
--             line for each adjusted value: its key, what Flow had, what was
--             kept and why. Entries left behind for another reason (no row
--             for the key, or a newer key held the same choice) get a line of
--             their own when there are any.
--     counts  { dropped, adjusted, malformed, unknown, superseded, other }
-- The entries are counted from the lists themselves. Pure: it reads only
-- what it is given, and a result that is not one gives a line saying so.
local function shown(v)
    if type(v) == "string" then return '"' .. v .. '"' end
    return tostring(v)
end

function Diag.ImportReport(result)
    local counts = { dropped = 0, adjusted = 0, malformed = 0, unknown = 0, superseded = 0, other = 0 }
    if type(result) ~= "table" then
        return { "import: there is no result to report." }, counts
    end
    if result.ok ~= true then
        return { "import: nothing was read: " .. tostring(result.reason or "no reason given") }, counts
    end

    if type(result.dropped) == "table" then
        for i = 1, #result.dropped do
            local entry = result.dropped[i]
            local why = type(entry) == "table" and entry.why or nil
            if why == "dropped" or why == "malformed" or why == "unknown" or why == "superseded" then
                counts[why] = counts[why] + 1
            else
                counts.other = counts.other + 1
            end
        end
    end
    local adjusted = type(result.adjusted) == "table" and result.adjusted or {}
    counts.adjusted = #adjusted

    local lines = {
        "import: " .. counts.dropped .. " dropped, " .. counts.adjusted .. " adjusted, "
            .. counts.malformed .. " malformed.",
    }
    if counts.unknown + counts.superseded + counts.other > 0 then
        lines[#lines + 1] = "import: also left behind: " .. counts.unknown .. " with no row, "
            .. counts.superseded .. " superseded, " .. counts.other .. " with no category."
    end
    for i = 1, #adjusted do
        local entry = type(adjusted[i]) == "table" and adjusted[i] or {}
        lines[#lines + 1] = "import: adjusted " .. tostring(entry.key) .. ": " .. shown(entry.from)
            .. " to " .. shown(entry.to) .. " (" .. tostring(entry.reason or "no reason given") .. ")"
    end
    return lines, counts
end

-- Starts collecting on kernel k: the timing marks, the window snapshots and
-- the slash command. Returns { timing =, snapshot =, commands = }.
function Diag.Start(k)
    local client, id = k.client, k.id

    local function dataNow()
        return { at = client.now(), accountData = client.savedExists(id.accountDB),
            charData = client.savedExists(id.charDB), phase = k.phase }
    end

    -- Timing marks are kept here until a snapshot is saved: a write to the
    -- saved table before the client has loaded it would be thrown away.
    local timing = { order = {}, fileLoad = dataNow() }

    local function mark(event)
        if timing[event] then return false end
        timing.order[#timing.order + 1] = event
        timing[event] = dataNow()
        return true
    end

    local function snapshot(why)
        local ok, snap = pcall(Diag.Collect, k, why)
        if not ok then
            k.problems:add("diag", "collect", snap)
            return nil
        end
        snap.timing = timing
        return Diag.Save(k, snap)
    end

    -- Lua errors, ours and other addons': kept here, written with each
    -- snapshot. The same text again raises its count; ERRORS_KEPT at most.
    local errors, seen = {}, {}
    timing.errors = errors
    client.onError(function(text)
        local row = seen[text]
        if row then row.count = row.count + 1 return end
        if #errors >= ERRORS_KEPT then return end
        row = { text = text, count = 1, at = client.now(), phase = k.phase,
            ours = text:find(id.addon, 1, true) ~= nil }
        seen[text], errors[#errors + 1] = row, row
    end)

    -- A reload or a character change starts the files again: count the
    -- starts this account has seen, so sessions can be told apart.
    local function session()
        local d = client.saved(id.accountDB)
        if type(d.diag) ~= "table" then d.diag = {} end
        d.diag.starts = (tonumber(d.diag.starts) or 0) + 1
        timing.start = d.diag.starts
        local okName, name = client.raw("UnitName", "player")
        local okRealm, realm = client.raw("GetRealmName")
        timing.character = okName and name or nil
        -- The real client answered an empty realm at login: that is unknown.
        if not (okRealm and type(realm) == "string" and realm ~= "") then
            okRealm, realm = client.raw("GetNormalizedRealmName")
        end
        -- Both were empty in the game on 16001; UnitFullName's second value
        -- had the realm.
        if not (okRealm and type(realm) == "string" and realm ~= "") then
            local okFull, _, own = client.raw("UnitFullName", "player")
            okRealm, realm = okFull, own
        end
        timing.realm = okRealm and type(realm) == "string" and realm ~= "" and realm or nil
        local okApi, api = pcall(Diag.Api, client)
        d.diag.api = okApi and api or nil
    end

    -- One more snapshot SETTLE seconds after login, then stop listening.
    local function settle()
        local waited, cancel = 0, nil
        cancel = client.onFrame(function(elapsed)
            waited = waited + (tonumber(elapsed) or 0)
            if waited < SETTLE then return end
            if cancel then cancel() end
            snapshot("settled")
        end)
    end

    client.listen("ADDON_LOADED", function(name)
        if name == id.addon then mark("ADDON_LOADED") end
    end)
    client.listen("VARIABLES_LOADED", function() mark("VARIABLES_LOADED") end)
    client.listen("PLAYER_LOGIN", function() mark("PLAYER_LOGIN") end)
    client.listen("PLAYER_ENTERING_WORLD", function()
        if mark("PLAYER_ENTERING_WORLD") then
            session()
            snapshot("login")
            settle()
        end
    end)
    -- The bank's own listener goes first, so the bank snapshot sees it open.
    client.watchBank()
    local windows = { BANKFRAME_OPENED = "bank", MERCHANT_SHOW = "vendor", TRAINER_SHOW = "trainer",
        TRADE_SKILL_SHOW = "profession", CRAFT_SHOW = "craft", TAXIMAP_OPENED = "flight" }
    -- A window event that repeats inside SAME_WINDOW seconds is one opening.
    -- `ready` is the client saying the window's list has arrived, which on
    -- the real client is after the window event: one more snapshot then.
    local last, waiting = {}, {}
    local ready = { trainer = "TRAINER_UPDATE", profession = "TRADE_SKILL_LIST_UPDATE" }
    for event, why in pairs(windows) do
        client.listen(event, function()
            local now = client.now()
            if last[why] and type(now) == "number" and now - last[why] < SAME_WINDOW then return end
            last[why] = type(now) == "number" and now or nil
            waiting[why] = ready[why] ~= nil
            snapshot(why)
            -- The recipe list can arrive after the client says it is ready.
            if why == "profession" then
                local waited, cancel = 0, nil
                cancel = client.onFrame(function(elapsed)
                    waited = waited + (tonumber(elapsed) or 0)
                    if waited < LATE then return end
                    if cancel then cancel() end
                    snapshot("profession-late")
                end)
            end
        end)
    end
    for why, event in pairs(ready) do
        client.listen(event, function()
            if not waiting[why] then return end
            waiting[why] = false
            snapshot(why .. "-ready")
        end)
    end

    -- Other files add a word of their own after the slash command here:
    -- commands[word] = function(rest) end, rest lower-cased and trimmed.
    local commands = {}

    -- The import report. The import itself loads after this file, so it is
    -- looked up when the word is typed. The predecessor's tables are read
    -- only when the client already has them: none is created here.
    commands.import = function()
        local Import = ns.Import
        if not (Import and type(Import.FromFlow) == "function") then
            client.print(id.title .. ": the import is not loaded.")
            return
        end
        if not client.savedExists(id.predecessorDB) then
            client.print(id.title .. ": no " .. id.predecessor .. " data is loaded, so there is nothing to read.")
            return
        end
        local charDB = id.predecessor .. "CharDB"
        local ok, result = pcall(Import.FromFlow, client.saved(id.predecessorDB),
            client.savedExists(charDB) and client.saved(charDB) or nil)
        if not ok then
            k.problems:add("diag", "import", result)
            client.print(id.title .. ": the import could not be read.")
            return
        end
        local lines = Diag.ImportReport(result)
        for i = 1, #lines do client.print(id.title .. ": " .. lines[i]) end
    end

    client.slash(id.bindingHeader, id.slash, function(rest)
        local text = tostring(rest):lower()
        local word, more = text:match("^%s*(%S+)%s*(.-)%s*$")
        if word and commands[word] then
            commands[word](more)
        elseif not text:find("^%s*diag") then
            client.print(id.title .. ": " .. (k.paused and "paused" or tostring(k.phase))
                .. ". Type " .. id.slash .. " diag for a diagnostic snapshot.")
        elseif text:find("clear", 1, true) then
            client.saved(id.accountDB).diag = nil
            client.print(id.title .. ": diagnostics cleared.")
        else
            local d = snapshot("asked")
            client.print(id.title .. ": " .. (d and ("snapshot " .. d.count
                .. " kept. Reload or log out to write it to disk.") or "the snapshot failed."))
        end
    end)
    return { timing = timing, snapshot = snapshot, commands = commands }
end

-- The addon's own kernel collects from the moment this file loads.
ns.diag = Diag.Start(ns)
