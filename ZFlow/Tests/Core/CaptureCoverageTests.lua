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
               "watchAuctionResults", "onUnitTooltip", "watchAuctionRows", "onSystemMessage",
               -- G4: the bag window's redraw (Items/BagMarks.lua).
               "onBagRedraw",
               -- N60a: the chat filter and the link click (UI/Chat.lua).
               "chatFilter", "onLinkClick" },
    show = { "print", "panel", "minimapPin", "copyBox", "icon", "arrow", "windowButton", "secureButton",
             "optionsPage", "guideLines", "taxiMark", "mapPins", "mapClick", "comboBar", "slotIcon",
             "markMerchantButtons", "rowPanel", "textEntry",
             -- G4: the marks on bag slots (Items/BagMarks.lua).
             "markBagKinds",
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
             "markRewardChoice",
             -- G14 bag badge: the role letters on bag upgrades (Gear/BagBadge.lua).
             "markBagSlots",
             -- S21: the Need or Greed value on a loot roll's item (Gear/RollHint.lua).
             "rollValue",
             -- S19 (P-SETS branch 2): the set icon row; a click asks only
             -- what the caller's act does.
             "iconRow",
             -- S20: the per-role badges on the merchant's item buttons.
             "markMerchantSpecs",
             -- FLOW-PARITY D-06: the glow on the bar button holding the suggested spell.
             "barGlow" },
    tool = { "raw", "peek", "typeOf", "globalNames", "apiPresent", "saved", "savedExists", "savedMadeHere", "slash",
             "slashTaken", "unslash" },
    -- Hands back or runs a sound restart: never asked by the capture.
    -- craftRecipe (lead section 226, acting): one craft on the player click.
    -- stopCraftRepeat (section 234): stops the game repeat; not a craft.
    -- N57 (lead section 249 item 2): the binding writes, each only on the
    -- player's own key press on the settings page, out of combat.
    act = { "restartSound", "soundWays", "craftRecipe", "stopCraftRepeat",
            "setBindingClick", "clearBinding", "saveBindings", "overrideBindingClick", "clearOverrideKeys",
            -- S19 (P-SETS branch 2): one piece put on, only on the player's
            -- own click on a set icon, out of combat.
            "equipItem",
            -- G59 (lead section 226, ACTS): the game option writes, each on
            -- the player own choice only.
            "setGameSetting", "setCombatLogFile" },
    -- Reads a chat line handed in, not the client.
    -- lootLine (N55): the item of anyone's loot line, never the looter.
    parse = { "ownLoot", "auctionOutcome", "lootLine" },
}
-- S15 click slots and S29 move handle (P-KEYS slice C): a row of secure
-- buttons, each cast only on the player click, and the grip that moves it.
KIND.show[#KIND.show + 1] = "clickRow"
-- G34: the hover-to-bind covers on the action buttons; binds nothing.
KIND.show[#KIND.show + 1] = "bindHover"
-- G34: one of the game's binding commands put on a key, only from the
-- hover-to-bind mode's Save (UI/HoverBind.lua).
KIND.act[#KIND.act + 1] = "setBinding"
KIND.show[#KIND.show + 1] = "moveHandle"
-- Lead sections 297, 303 and 308: asks whether each part of the window
-- kit's list is there, on hidden frames; run once per login by
-- UI/KitProbe.lua, never by the capture.
KIND.tool[#KIND.tool + 1] = "kitProbe"
-- The window kit's drawer (lead sections 287, 291 and 303): one window
-- from a checked tree; a click runs the part's own function.
KIND.show[#KIND.show + 1] = "kitWindow"
-- Lead sections 319 and 322: the probe's answers handed to the drawer, and
-- the listener told what each window drew. Neither asks the game anything.
KIND.tool[#KIND.tool + 1] = "kitKnown"
KIND.listen[#KIND.listen + 1] = "onKitDrawn"
-- The settings in one kit window (lead section 285 item 3): it hands the
-- caller's tree to kitWindow and asks the game nothing.
KIND.show[#KIND.show + 1] = "settingsWindow"
-- Lead section 410: the settings as the game's own rows in its Options.
KIND.show[#KIND.show + 1] = "optionsNative"

-- Section 285 item 2b: the face, Ctrl-drag and hover tip of the Flow and
-- self buttons (Rotation/FlowButton.lua).
KIND.show[#KIND.show + 1] = "buttonFace"
KIND.show[#KIND.show + 1] = "ctrlDrag"
KIND.show[#KIND.show + 1] = "hoverTip"
-- Lead DISPATCH section 340: the minimap button; a click opens the
-- settings page only.
KIND.show[#KIND.show + 1] = "minimapButton"

-- Lead section 340: the diagnostics line naming the frame under the mouse,
-- and which kit window made a frame; asked by the settings word only.
KIND.tool[#KIND.tool + 1] = "kitFocus"
KIND.tool[#KIND.tool + 1] = "kitOwner"

-- N60b: chat readability (UI/Chat.lua). How a chat window looks (text
-- size, fading, the tab held up) and the wheel hook after the game's own.
KIND.show[#KIND.show + 1] = "setChatFont"
KIND.show[#KIND.show + 1] = "setChatFading"
KIND.show[#KIND.show + 1] = "chatTabAlpha"
KIND.listen[#KIND.listen + 1] = "chatWheel"
-- N60d: chat part 4 (UI/Chat.lua). The game's class colour option of a
-- chat kind, its chat labels and the edit box's arrow keys and history.
KIND.show[#KIND.show + 1] = "setChatNameByClass"
KIND.show[#KIND.show + 1] = "setChatTypeHeader"
KIND.show[#KIND.show + 1] = "setEditBox"
-- R4, R5 (lead section 387): the route beside the quest log and on the
-- world map (UI/RouteList.lua, UI/MapRoute.lua). showMap opens the world
-- map on a zone, only on the player's own click on a route row.
KIND.show[#KIND.show + 1] = "routePins"
KIND.show[#KIND.show + 1] = "mapCard"
KIND.show[#KIND.show + 1] = "showMap"

-- Every read, and whether the capture asks it (true) or not (false).
local READS = {
    now = false, clock = true, clockMs = false, addonLoaded = true, listenFaults = true, uptime = true, inCombat = true,
    money = true, bags = true, bagItems = true, bankOpen = true, bankItems = true, merchantOpen = false,
    merchantItems = false, returnableItems = false, recipes = true, recipeSchematic = false, tradeSkillSchematic = true, tradeSkillRows = true, tradeSkillTools = true, trainer = false, faction = false, class = true,
    stealthed = true, target = true, inRange = true, level = false, gear = false, spellCooldown = true,
    spellId = true, spellTexture = false, facing = true, spell = true, position = true, dead = true,
    ghost = true, corpse = true, waypoint = false, mapSize = true, mapCont = false, mapName = false, zone = true,
    combatLockdown = true, version = false, screen = false, questLog = true, questFocus = true,
    questFocusReads = false, questieModule = false, minimap = false, itemInfo = false,
    itemLines = false, itemTexture = false, tracking = false, anyTracking = false, professions = false,
    durability = false, lootWindow = false, windowState = false, form = true, petBattle = false,
    vehicle = false, guid = false, playerGUID = false, petGUID = false, serviceNpc = false,
    merchantRepairs = false, repairCost = false, bindLocation = false, hearthCooldown = false, targetRank = false,
    frameRect = false, worldPosition = true, onTaxi = true, realm = false, modifiers = false,
    unitInfo = false, unitBuff = true, mounted = false, questItem = true, itemCount = true,
    itemUse = false, mapCorners = true, globalText = false, plates = false, canAttack = false,
    grouped = false, plateLabel = false, combo = false, comboColor = false, playerBuffs = true,
    targetDebuffs = true, formName = true, currentSpell = true, taxiNodes = true,
    -- R4, R5: where the quest log frame stands, and a map's own name and levels.
    questLogFrame = false, mapInfo = false,
    -- Lead section 197: the pet state the rotation reads.
    pet = true,
    -- Lead section 226: the craft bar reads (P-CRAFT); the capture asks none.
    recipeUsable = false, moving = false,
    -- G58: the party invite line reads the friends list; the capture asks none.
    isFriend = false,
    -- G40: the arrow's time to arrive reads the speed; the capture asks none.
    speed = false,
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
    -- S12 (P-KEYS slice A): a friend for the care key; the capture asks none.
    unitCare = false,
    -- N2 (P-KEYS slice D): the corpse you target; the capture asks it not.
    -- N20 reads tradeSkillTools, listed above (N24).
    targetCorpse = false,

    -- N55 (the boss loot panel): the boss unit and whether you are in an
    -- instance; read by UI/BossLoot.lua only. The names they ask
    -- (IsInInstance, GetInstanceInfo and the rest) are in Diag.NAMES.
    bossUnit = false, instance = false,
    -- G59: a game setting by name and the combat log file, read by
    -- UI/GameOptions.lua only, on the player choice. The names they ask
    -- (C_CVar.GetCVar, GetCVar, LoggingCombat) are in Diag.NAMES.
    gameSetting = false, combatLogFile = false,

    -- N59 (the info bar): read by UI/InfoBar.lua only. The names they ask
    -- (UnitXP, GetWatchedFactionInfo and the rest) are in Diag.NAMES.
    xp = false, watchedFaction = false, gameTime = false, framerate = false, latency = false,

    -- N57: the rotation key's bindings and what a key does; read by the
    -- settings page only. Their names are in Diag.NAMES.
    bindingKeys = false, bindingAction = false,
    -- S23 (P-KEYS slice B): what a key does with override bindings counted;
    -- read by the click-casting check line (UI/ClickCheck.lua) only.
    bindingOverride = false,

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
    -- Lead section 337 item 2: skill ranks for the skill boosters (first
    -- guess); the same skill line reads, none in the capture.
    skillRanks = false,
    -- G60: whether the client can speak (its voices) and the NPC's words in
    -- an open gossip or quest window; read by UI/NpcSpeech.lua only, the
    -- capture asks none. Their names are in Diag.NAMES.
    speech = false, npcText = false,
    -- P-QOL: the NPC's sex for the voice; read by UI/NpcSpeech.lua only.
    npcSex = false,
    -- N39 and N40 (P-KEYS slice E): the target's name (the no-auto-attack
    -- list) and the spell it casts (the stop-a-cast advice); read by the
    -- rotation only, the capture asks neither. Their names (UnitName,
    -- UnitCastingInfo, UnitChannelInfo) are in Diag.NAMES.
    targetName = false, targetCast = false,

    -- G51: the creature on a nameplate and the quest mark over it; read by
    -- UI/PlateQuests.lua only. Their names (UnitGUID, C_NamePlate.
    -- GetNamePlateForUnit, CreateFrame) are in Diag.NAMES.
    plateCreature = false, plateQuestMark = false,

    -- G14: the open quest reward choices; read by Gear/RewardMark.lua only.
    -- Their names (GetNumQuestChoices, GetQuestItemLink and the reward
    -- buttons) are in Diag.NAMES.
    questChoices = false,

    -- N60a: a chat window's lines, read by UI/Chat.lua only, on the player's
    -- own ask; and whether a Prat module is on, which the capture asks so a
    -- login records it. Their names (ChatFrame1.GetNumMessages, Prat.
    -- GetModule and the rest) are in Diag.NAMES.
    chatLines = false, pratModule = true,
    -- N60b: a chat window's text size and fading, and the local clock for
    -- the chat timestamps; read by UI/Chat.lua only. Their names
    -- (ChatFrame1.GetFont, date and the rest) are in Diag.NAMES.
    chatFont = false, chatFading = false, localTime = false,
    -- Lead section 303: race number and quests handed in; read by
    -- Nav/DungeonRead.lua only. Their names (UnitRace,
    -- C_QuestLog.IsQuestFlaggedCompleted) are in Diag.NAMES.
    raceId = false, questDone = false,
    -- N60c: the player's own name for chat mentions; read by UI/Chat.lua
    -- only. Its name (UnitName) is in Diag.NAMES.
    playerName = false,
    -- N60d: a GUID's class, a chat kind's class colour option and label,
    -- and the edit box; read by UI/Chat.lua only. Their names
    -- (GetPlayerInfoByGUID, ChatTypeInfo and the rest) are in Diag.NAMES.
    classOfGuid = false, chatNameByClass = false, chatTypeHeader = false, editBox = false,

    -- G38 and G47: indoors and a party member's position; read by
    -- Nav/Trails.lua and Nav/Follow.lua only. Their names (IsIndoors,
    -- C_Map.GetBestMapForUnit, C_Map.GetPlayerMapPosition) are in Diag.NAMES.
    indoors = false, unitPosition = false,
    -- Lead section 303 (d): the instance name, read by UI/DungeonTracker.lua
    -- only. Its name (GetInstanceInfo) is in Diag.NAMES.
    instanceName = false,
}
-- Lead section 337 item 1: the bag stacks with their bag and slot, and one
-- slot read again before it is sold; read by Items/SellThese.lua only, on
-- the player click. The capture asks neither.
-- Lead DISPATCH 426: the dungeon journal, asked by the Bosses tab and the diag word.
READS.journalBoss = false
READS.bagSlots = false
READS.bagSlot = false
-- P-QUEST (lead section 354 item 4): whether a quest can be shared; read by
-- Nav/QuestAdvice.lua only. Its name (C_QuestLog.IsPushableQuest) is in
-- Diag.NAMES. The capture does not ask it.
READS.questShareable = false
-- Lead section 337 item 1 (ACTING): one bag slot sold to the open merchant,
-- only on the player click on Sell these, out of combat. Never the capture.
KIND.act[#KIND.act + 1] = "sellBagItem"
-- Lead section 382: a map's continent name; read by Nav/ProfFeed.lua only.
-- Its name (C_Map.GetMapInfo, Enum.UIMapType) is in Diag.NAMES.
READS.mapContName = false
-- Lead section 404 item 2: seconds left on a spell's cooldown, the same
-- client calls as spellCooldown. The capture does not ask it.
READS.spellCooldownLeft = false
-- G50 (ACTING): one quest offered to the group, only on the player's own
-- share word (Nav/QuestShare.lua). Never the capture.
KIND.act[#KIND.act + 1] = "shareQuest"

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

-- SD-1: the first guesses the corpse and tools reads lean on (N2, N20:
-- c.targetCorpse, c.tradeSkillTools) are saved in the snapshot's names
-- table, so a normal login records which exist.
tests["capture coverage (a): the corpse and tools first guesses are in Diag.NAMES"] = function(t)
    local listed = {}
    for _, name in ipairs(ns.Diag.NAMES) do listed[name] = true end
    for _, name in ipairs({ "CanLootUnit", "GetTradeSkillTools", "C_TooltipInfo.GetUnit" }) do
        t.ok(listed[name], "in Diag.NAMES: " .. name)
    end
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

-- G48 (P-TRIP, ACTING): the party route's add-on messages; the prefix is
-- taken at login, a send goes on the party channel only, on the player's
-- own route share or route ask (or an answer to a party member's ask).
-- Never the capture.
KIND.act[#KIND.act + 1] = "addonPrefix"
KIND.act[#KIND.act + 1] = "addonSend"

-- P-EVIDENCE+ (lead sections 252 and 262, RB4-2): the raw tracking list and
-- the profession window's header and filter answers, read by
-- Core/AutoEvidence.lua at login, on MINIMAP_UPDATE_TRACKING and when the
-- profession window opens or changes; never by the capture.
READS.trackingRaw = false
READS.tradeSkillAnswers = false
-- Lead section 404 item 4 (G25): what holds you, read by the rotation
-- driver for break free. Its names are in Diag.NAMES. The capture does not
-- ask it.
READS.heldBy = false

-- Section 401: the close-enemy reads, read by the rotation only
-- (Rotation/Driver.lua); never by the capture.
READS.targetClose = false
READS.hitOnYouAge = false


-- S32: the zone and sub-zone words behind client.placeText, read by
-- Nav/Crossings.lua to name a dock; never by the capture.
READS.placeText = false

-- G14 probe (RM-1): the reward buttons' numbers and kinds; read by
-- Gear/RewardMark.lua only, when a quest's rewards are open (saved in
-- account diag.rewardButtons). Their names are in Diag.NAMES.
READS.rewardButtons = false

-- G47 (lead section 397 item 15): who leads the group; read by
-- Nav/FollowAdvice.lua only. Its name (UnitIsGroupLeader) is in Diag.NAMES.
READS.groupLeader = false

return tests
