local _, ns = ...

-- Capture coverage (lead section 188). (a) Every function Core/Client.lua
-- offers is listed here once, by kind; each read says whether the diag
-- capture (Diag.Collect and Diag.Reads) asks it. (b) That say is measured,
-- not claimed: every read of a fake client is counted while the capture
-- runs. (c) The reads the merged features use (rotation, target debuffs,
-- form, range, taxi nodes, map corners, quest log) are all asked. (d) What
-- is saved is forms and counts only: no made-up name, place or spell text.
-- Made-up answers only; fake client. Not tested in game. Look only: the
-- capture never asks a show, listen, act or parse function.

local Diag = ns.Diag
local tests = {}

-- Not reads: what each other function of the client is.
local KIND = {
    listen = { "listen", "onFrame", "watchBank", "watchMerchant", "watchTrainer",
               "onSpellLearned", "onItemTooltip", "onLootRoll", "onPrint", "onError", "watchCombatLog",
               "watchSoundDevices", "watchUnitCombat", "watchMoves", "onMerchantRedraw",
               "watchAuctionResults", "onUnitTooltip", "watchAuctionRows", "onSystemMessage" },
    show = { "print", "panel", "minimapPin", "copyBox", "icon", "arrow", "windowButton", "secureButton",
             "optionsPage", "guideLines", "taxiMark", "mapPins", "comboBar", "slotIcon",
             "markMerchantButtons", "rowPanel", "textEntry",
             -- N59: the info bar, and its data broker feed where the library is loaded.
             "infoBar", "broker",
             -- N57: the key-capture overlay on the settings page.
             "keyCapture",
             -- N72 (section 248 item 4): the macro icon window; shows a list on it.
             "macroPopup",
             -- G60: NPC words read aloud on the player's own speakers, and
             -- stopped; an output like print, not a game action.
             "speak", "stopSpeech",
             -- N68: the one alert sound (output only; changes nothing in the game).
             "playAlert",
             -- G14: the mark on the best quest reward choice (Gear/RewardMark.lua).
             "markRewardChoice" },
    tool = { "raw", "peek", "typeOf", "globalNames", "apiPresent", "saved", "savedExists", "savedMadeHere", "slash",
             "slashTaken", "unslash" },
    -- Hands back or runs a sound restart: never asked by the capture.
    -- craftRecipe (lead section 226, acting): one craft on the player click.
    -- stopCraftRepeat (section 234): stops the game repeat; not a craft.
    -- N57 (lead section 249 item 2): the binding writes, each only on the
    -- player's own key press on the settings page, out of combat.
    act = { "restartSound", "soundWays", "craftRecipe", "stopCraftRepeat",
            "setBindingClick", "clearBinding", "saveBindings", "overrideBindingClick", "clearOverrideKeys" },
    -- Reads a chat line handed in, not the client.
    -- lootLine (N55): the item of anyone's loot line, never the looter.
    parse = { "ownLoot", "auctionOutcome", "lootLine" },
}

-- Every read, and whether the capture asks it (true) or not (false).
local READS = {
    now = false, clock = true, clockMs = false, addonLoaded = true, listenFaults = true, uptime = true, inCombat = true,
    money = true, bags = true, bagItems = true, bankOpen = true, bankItems = true, merchantOpen = false,
    merchantItems = false, recipes = true, recipeSchematic = false, tradeSkillSchematic = true, tradeSkillRows = true, trainer = false, faction = false, class = true,
    stealthed = true, target = true, inRange = true, level = false, gear = false, spellCooldown = true,
    spellId = true, spellTexture = false, facing = true, spell = true, position = true, dead = true,
    ghost = true, corpse = true, waypoint = false, mapSize = true, mapCont = false, zone = true,
    combatLockdown = true, version = false, screen = false, questLog = true, questFocus = true,
    questFocusReads = false, questieModule = false, minimap = false, itemInfo = false,
    itemLines = false, itemTexture = false, tracking = false, anyTracking = false, professions = false,
    durability = false, lootWindow = false, windowState = false, form = true, petBattle = false,
    vehicle = false, guid = false, playerGUID = false, petGUID = false, serviceNpc = false,
    merchantRepairs = false, bindLocation = false, hearthCooldown = false, targetRank = false,
    frameRect = false, worldPosition = true, onTaxi = true, realm = false, modifiers = false,
    unitInfo = false, unitBuff = true, mounted = false, questItem = true, itemCount = true,
    itemUse = false, mapCorners = true, globalText = false, plates = false, canAttack = false,
    grouped = false, plateLabel = false, combo = false, comboColor = false, playerBuffs = true,
    targetDebuffs = true, formName = true, currentSpell = true, taxiNodes = true,
    -- Lead section 197: the pet state the rotation reads.
    pet = true,
    -- Lead section 226: the craft bar reads (P-CRAFT); the capture asks none.
    recipeUsable = false, moving = false,
    -- CF-32: a spell's name by id, for your own casts (Rotation/OwnCasts.lua).
    spellName = false,
    -- N13: the buffs you put up yourself (Classes/Paladin.lua auras).
    ownBuffs = false,
    -- PRIEST-3 (P-SELFBUFF): your own debuffs by name (Weakened Soul), read
    -- by the rotation only. Its names (UnitDebuff, C_UnitAuras.
    -- GetAuraDataByIndex) are in Diag.NAMES, which the capture asks.
    playerDebuffs = false,

    -- P-SETS: what is worn, read by the set word only.
    wornLinks = false,
    -- Section 235 item 4: the food read asks it (Rotation/Driver.lua).
    fishingPole = true,
    -- N8: the heal step asks both (Rotation/Driver.lua).
    lowHealth = true, itemCooldown = true,

    -- P-PARTY: your group, a spell's reach to one of them, and the debuff
    -- types on you or one of them; read by the rotation only. Their names
    -- (UnitIsConnected and the rest) are in Diag.NAMES, which the capture asks.
    party = false, reach = false, unitDebuffTypes = false,
    -- N72: the spells for the macro icon search; the capture asks none.
    spellbookIcons = false,

    -- N55 (the boss loot panel): the boss unit and whether you are in an
    -- instance; read by UI/BossLoot.lua only. The names they ask
    -- (IsInInstance, GetInstanceInfo and the rest) are in Diag.NAMES.
    bossUnit = false, instance = false,

    -- N59 (the info bar): read by UI/InfoBar.lua only. The names they ask
    -- (UnitXP, GetWatchedFactionInfo and the rest) are in Diag.NAMES.
    xp = false, watchedFaction = false, gameTime = false, framerate = false, latency = false,

    -- N57: the rotation key's bindings and what a key does; read by the
    -- settings page only. Their names are in Diag.NAMES.
    bindingKeys = false, bindingAction = false,

    -- N67: other add-ons' data at runtime (GatherMate2's nodes, Attune's
    -- progress); read by Nav/AddonSources.lua only. The globals they read
    -- are in Diag.NAMES; the capture keeps only whether each is loaded.
    gatherMateNodes = false, attuneProgress = false,

    -- P-READS (section 260 item 1): the shared reads for the class packs;
    -- the capture asks none. Their names are in Diag.NAMES.
    channel = false, weaponEnchant = false, totems = false, targetBuffs = false,
    buffLength = false, enemiesNear = false, plateCasts = false, creatureType = false,
    plateEnemies = false,
    -- G16: the skill lines you know, for the untrained weapon line and the
    -- weapon master step; the capture asks none. Its names (GetNumSkillLines,
    -- GetSkillLineInfo) are in Diag.NAMES and Diag's skillLines field.
    weaponSkills = false,
    -- G60: whether the client can speak (its voices) and the NPC's words in
    -- an open gossip or quest window; read by UI/NpcSpeech.lua only, the
    -- capture asks none. Their names are in Diag.NAMES.
    speech = false, npcText = false,

    -- G51: the creature on a nameplate and the quest mark over it; read by
    -- UI/PlateQuests.lua only. Their names (UnitGUID, C_NamePlate.
    -- GetNamePlateForUnit, CreateFrame) are in Diag.NAMES.
    plateCreature = false, plateQuestMark = false,

    -- G14: the open quest reward choices; read by Gear/RewardMark.lua only.
    -- Their names (GetNumQuestChoices, GetQuestItemLink and the reward
    -- buttons) are in Diag.NAMES.
    questChoices = false,
}

-- The reads the merged features use (Rotation, Nav and UI/Arrow.lua).
local FEATURE = {
    "class", "currentSpell", "dead", "form", "formName", "inCombat", "inRange", "playerBuffs", "spell",
    "spellCooldown", "spellId", "stealthed", "target", "targetDebuffs", "unitBuff",
    "facing", "itemCount", "mapCorners", "mapSize", "onTaxi", "position", "questFocus", "questItem",
    "questLog", "taxiNodes", "worldPosition", "zone", "corpse", "ghost", "pet",
    "fishingPole", "lowHealth", "itemCooldown",
}

local TEXTS = { "Orgrimmar", "Devotion Aura", "Attack", "Rend", "Bear Form", "Wolves" }

local function holds(v, texts, depth)
    depth = depth or 0
    if depth > 20 then return false end
    if type(v) == "string" then
        for _, text in ipairs(texts) do if v == text then return true end end
        return false
    end
    if type(v) ~= "table" then return false end
    for key, value in pairs(v) do
        if holds(key, texts, depth + 1) or holds(value, texts, depth + 1) then return true end
    end
    return false
end

local function kindOf(name)
    for kind, list in pairs(KIND) do
        for _, n in ipairs(list) do if n == name then return kind end end
    end
    if READS[name] ~= nil then return "read" end
    return nil
end

-- A fake client with a made-up answer for every feature read.
local function start()
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setZone(1, 1411); c.setPosition(1411, 0.5, 0.5); c.setFacing(0)
    c.setMapSize(1411, 1000, 500); c.setMapCont(1411, 1)
    c.setMapCorners(1411, { cont = 1, ox = 1000, oy = 2000, ex = 0, ey = -1000, sx = -500, sy = 0 })
    c.setWorldPosition(1, 500, 1500)
    c.setClass("WARRIOR"); c.setFaction("Horde"); c.setOnTaxi(false)
    c.setStealthed(false); c.setDead(false)
    c.setTarget({ exists = true, name = "Attack", hostile = true })
    c.setSpell(6603, { known = true, usable = true })
    c.setSpellCooldown(61304, false); c.setInRange(6603, true); c.setCurrentSpell(6603, false)
    c.setForm(1); c.setFormName("Bear Form", true); c.setSpellId("Bear Form", 5487)
    c.setPlayerBuffs({ ["Devotion Aura"] = 120, Rend = 5 })
    c.setTargetDebuffs({ Rend = 9 })
    c.setPet({ exists = true, dead = false, inCombat = false, family = "Wolves", happiness = "happy", powerKind = 2 })
    c.setQuestLog({ { id = 303, title = "Wolves", objectives = { { text = "Wolves slain: 0/4" } } } })
    c.setQuestFocus(303, { 303 })
    c.setQuestItem(303, 4000); c.setItemCount(6948, 1)
    c.setLowHealth(false); c.setItemCooldown(6948, 0)
    c.setTaxiNodes({ map = 1411, here = 1, nodes = { { name = "Orgrimmar", x = 0.5, y = 0.5, state = "known" } } })
    local k = ns.Kernel({}, c)
    Diag.Start(k)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    return k, c
end

-- Which reads the capture asks: every read of the client counted while
-- Diag.Collect and Diag.Reads run once each.
local function measured()
    local k, c = start()
    local asked = {}
    for name in pairs(READS) do
        local fn = c[name]
        if type(fn) == "function" then
            c[name] = function(...) asked[name] = true; return fn(...) end
        end
    end
    Diag.Collect(k, "coverage")
    local reads = Diag.Reads(c)
    return asked, reads, k
end

-- ------------------------------------------------------------------ (a)

tests["capture coverage (a): every client function is listed once, by kind"] = function(t)
    local c = ns.make.client({})
    for name, fn in pairs(c) do
        if type(fn) == "function" then t.ok(kindOf(name) ~= nil, "listed: " .. tostring(name)) end
    end
end

tests["capture coverage (a): no listed name is stale or listed twice"] = function(t)
    local c = ns.make.client({})
    local seen = {}
    local function one(name)
        t.ok(type(c[name]) == "function", "a client function: " .. name)
        t.ok(not seen[name], "listed once: " .. name)
        seen[name] = true
    end
    for _, list in pairs(KIND) do for _, name in ipairs(list) do one(name) end end
    for name in pairs(READS) do one(name) end
end

tests["capture coverage (a): every feature read is a listed read"] = function(t)
    for _, name in ipairs(FEATURE) do t.eq(kindOf(name), "read", name) end
end

-- ------------------------------------------------------------------ (b)

tests["capture coverage (b): the list says what the capture asks, measured"] = function(t)
    local asked = measured()
    for name, says in pairs(READS) do
        t.eq(asked[name] == true, says, "asked by the capture: " .. name)
    end
end

tests["capture coverage (b): the capture asks no show, listen, act or parse function"] = function(t)
    local k, c = start()
    local asked = {}
    for _, kind in ipairs({ "show", "listen", "act", "parse" }) do
        for _, name in ipairs(KIND[kind]) do
            local fn = c[name]
            if type(fn) == "function" then
                c[name] = function(...) asked[#asked + 1] = name; return fn(...) end
            end
        end
    end
    Diag.Collect(k, "coverage")
    Diag.Reads(c)
    t.eq(asked, {})
end

-- ------------------------------------------------------------------ (c)

tests["capture coverage (c): every read the merged features use is asked"] = function(t)
    local asked = measured()
    for _, name in ipairs(FEATURE) do
        t.ok(asked[name] == true, "asked: " .. name)
    end
end

tests["capture coverage (c): the reads hold each feature read's answer form"] = function(t)
    local _, reads = measured()
    local a = type(reads) == "table" and reads.answers
    t.ok(type(a) == "table", "reads.answers")
    if type(a) ~= "table" then return end
    for _, name in ipairs(FEATURE) do
        t.ok(a[name] ~= nil, "an answer row: " .. name)
    end
    t.eq(a.class and a.class.n, 1)
    t.eq(a.class and a.class.answers and a.class.answers[1], "string")
    t.eq(a.taxiNodes and a.taxiNodes.answers and a.taxiNodes.answers[1].fields.nodes, "table")
    t.eq(a.playerBuffs and a.playerBuffs.count, 2)
    t.eq(a.targetDebuffs and a.targetDebuffs.count, 1)
    t.eq(a.mapCorners and a.mapCorners[1411] and a.mapCorners[1411].answers[1].fields.ox, "number")
end

tests["capture coverage (c): a read the client lacks is missing, one that raises is failed"] = function(t)
    local _, c = start()
    c.class = nil
    c.questLog = function() error("Wolves") end
    local reads = Diag.Reads(c)
    local a = reads.answers or {}
    t.eq(a.class, "missing")
    t.eq(a.questLog, { failed = true })
end

-- ------------------------------------------------------------------ (d)

tests["capture coverage (d): the saved answers hold no name, place or spell text"] = function(t)
    local _, reads = measured()
    t.ok(type(reads.answers) == "table", "reads.answers")
    t.ok(not holds(reads, TEXTS), "no made-up text kept")
end

tests["capture coverage (d): the reads saved at login carry the answers"] = function(t)
    local _, c = start()
    c.advance(9)
    local list = c.saved(ns.id.accountDB).diag
    list = type(list) == "table" and list.reads or {}
    local last = list[#list]
    t.ok(type(last) == "table" and type(last.reads.answers) == "table", "answers saved")
    t.ok(not holds(last, TEXTS), "no made-up text saved")
end

return tests
