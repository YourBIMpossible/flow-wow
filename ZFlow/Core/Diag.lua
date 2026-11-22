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
--
-- Snapshots are also taken at login and when the bank, a vendor, a trainer,
-- a profession window or the flight map opens. The newest KEEP are kept.
local _, ns = ...

local Diag = {}
ns.Diag = Diag

local KEEP = 12
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
}

local function plain(v)
    local t = type(v)
    return t == "number" or t == "string" or t == "boolean"
end

-- What a call answered, as plain saveable data: ok, how many values, their
-- types, and the values that are numbers, strings or booleans. A table
-- answer is listed by key, one level deep (plain values kept, others by type).
local function shape(ok, ...)
    local n = select("#", ...)
    local row = { ok = ok and true or false, n = n, types = {}, values = {} }
    for i = 1, n do
        local v = select(i, ...)
        row.types[i] = type(v)
        if plain(v) then
            row.values["v" .. i] = v
        elseif type(v) == "table" then
            local keys = {}
            for key, value in pairs(v) do
                keys[tostring(key)] = plain(value) and value or type(value)
            end
            row.values["v" .. i] = keys
        end
    end
    return row
end
Diag.Shape = shape

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
        timing.realm = okRealm and realm or nil
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
        end
    end)
    local windows = { BANKFRAME_OPENED = "bank", MERCHANT_SHOW = "vendor", TRAINER_SHOW = "trainer",
        TRADE_SKILL_SHOW = "profession", CRAFT_SHOW = "craft", TAXIMAP_OPENED = "flight" }
    for event, why in pairs(windows) do
        client.listen(event, function() snapshot(why) end)
    end

    -- Other files add a word of their own after the slash command here:
    -- commands[word] = function(rest) end, rest lower-cased and trimmed.
    local commands = {}

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
