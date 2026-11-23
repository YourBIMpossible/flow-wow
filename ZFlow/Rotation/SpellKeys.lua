local _, ns = ...

-- P-KEYS slice E: N39 auto attack at the pull, N26 the game-placed spell
-- notice and N27 the spells list (Bar, Key or Skip per spell).
--
-- N39 (Modules/Rotation/Engine.lua:837-869): with an enemy targeted out of
--   a fight, not swinging yet, the chooser's engage step suggests starting
--   the attack and Rotation/Driver.lua puts Attack on the rotation key (a
--   spell, never a macro: section 246), out of combat lockdown only. The
--   swing read on (the current spell) takes it off again. The setting
--   rotation.autoAttack turns it off; the no-auto-attack list (enemy
--   names, kept in Flow's own saved data) is never given it. The old
--   add-on started the swing through a STARTATTACK binding; Flow writes no
--   binding, so in a fight (lockdown) the key cannot be changed to start
--   it, and the old press count (two presses, then give up) is not kept:
--   the press is not seen. The old badge on the icon is not drawn here.
-- N26 (Modules/AutoPush.lua:1-8, :97): SPELL_PUSHED_TO_ACTIONBAR (spell id,
--   slot) is said in chat, with the bar the slot is on, and kept in a list
--   of the last 40 (per character). A notice only: nothing is put on or
--   taken off a bar, and the old bar markers over the game's buttons are
--   not drawn. The event's arguments are a first guess from the old file.
-- N27 (Modules/NewSpell.lua:545; Rotation/Compat.lua:502): per spell of
--   your rotation, Key (the default: the rotation key may hold it), Bar
--   (shown, kept off the key: you press it from your bars) or Skip (never
--   suggested, kept off the key). Kept per character in Flow's own saved
--   data; the setting rotation.spellsList turns obeying it off. The old
--   Bar placed the spell on a bar and the old Key bound it: both write to
--   the game (a bar, a binding) and are not done here.
--
-- Slash words: spells [bar|key|skip <spell>], attack [never | forget
-- <enemy>|all], autoplace [forget]. Each is the player's own press.

local SK = {}
ns.SpellKeys = SK

SK.NAME = "spellKeys"
SK.ATTACK = "rotation.autoAttack"
SK.LIST = "rotation.spellsList"
SK.PLACED = "rotation.placedNotice"
SK.CHOICES_PATH = "rotation.spellChoices"
SK.NO_ATTACK_PATH = "rotation.noAutoAttack"
SK.PLACED_PATH = "rotation.placedSpells"
SK.PLACED_MAX = 40
-- First guess (name and arguments, from the old file); Core/Diag.lua marks
-- it in the capture timing when it fires.
SK.EVENT = "SPELL_PUSHED_TO_ACTIONBAR"
SK.WORDS = { spells = "spells", attack = "attack", placed = "autoplace" }
SK.HELP = {
    spells = "your rotation's spells and their choice; spells bar|key|skip <spell> to set one",
    attack = "the enemies never given auto attack; attack never adds your target, attack forget <name>|all",
    autoplace = "spells the game put on your bars; autoplace forget to clear the list",
}

-- The old add-on's map of a slot to its bar (AutoPush.lua BAR_OF_SLOT).
SK.BARS = {
    { first = 1, last = 12, name = "Action Bar 1" },
    { first = 25, last = 36, name = "Right Bar" },
    { first = 37, last = 48, name = "Right Bar 2" },
    { first = 49, last = 60, name = "Bottom Right Bar" },
    { first = 61, last = 72, name = "Bottom Left Bar" },
}

local CHOICE = { bar = "bar", key = "key", skip = "skip" }

-- Pure -----------------------------------------------------------------

-- The prefs the spells list and the auto attack row give.
--   input { autoAttack = bool, listOff = bool, choices = { [spell] = choice } }
--   -> choose { autoAttack, skip, bar }, plan { skip }
-- The chooser never suggests a Skip spell; the key plan holds neither a
-- Skip nor a Bar spell. With the list off no choice is obeyed.
function SK.Prefs(input)
    if type(input) ~= "table" then input = {} end
    local skip, bar, off = {}, {}, {}
    if input.listOff ~= true and type(input.choices) == "table" then
        for spell, choice in pairs(input.choices) do
            if type(spell) == "string" and choice == "skip" then
                skip[spell], off[spell] = true, true
            elseif type(spell) == "string" and choice == "bar" then
                bar[spell], off[spell] = true, true
            end
        end
    end
    return { autoAttack = input.autoAttack ~= false, skip = skip, bar = bar }, { skip = off }
end

-- Set one spell's choice. Key is the default, so it clears the row.
-- -> true | false, reason
function SK.Set(choices, spell, word)
    if type(choices) ~= "table" then return false, "no list" end
    if type(spell) ~= "string" or spell == "" then return false, "no spell named" end
    local choice = CHOICE[string.lower(tostring(word or ""))]
    if not choice then return false, "not a choice: bar, key or skip" end
    if choice == "key" then choices[spell] = nil else choices[spell] = choice end
    return true
end

-- The bar a slot is on and its place on that bar, or nil when the old map
-- does not name it (a paged slot, or not a number).
function SK.BarOf(slot)
    if type(slot) ~= "number" then return nil end
    for _, bar in ipairs(SK.BARS) do
        if slot >= bar.first and slot <= bar.last then return bar.name, slot - bar.first + 1 end
    end
    return nil
end

-- The line said when the game puts a spell on a bar.
function SK.Notice(name, id, slot)
    local spell = name
    if type(spell) ~= "string" or spell == "" then spell = "spell " .. tostring(id) end
    local bar, n = SK.BarOf(slot)
    if bar then return string.format("the game put %s on %s, slot %d", spell, bar, n) end
    if type(slot) == "number" then return string.format("the game put %s on your bars, slot %d", spell, slot) end
    return string.format("the game put %s on your bars", spell)
end

-- Keep a row { id, slot } at the end of list, the oldest dropped past max.
function SK.Remember(list, row, max)
    if type(list) ~= "table" or type(row) ~= "table" or type(row.id) ~= "number" then return end
    list[#list + 1] = { id = row.id, slot = row.slot }
    max = type(max) == "number" and max or SK.PLACED_MAX
    while #list > max do table.remove(list, 1) end
end

-- The module -------------------------------------------------------------

local function ask(client, name, ...)
    if type(client) ~= "table" or type(client[name]) ~= "function" then return nil end
    local ok, v = pcall(client[name], ...)
    if ok then return v end
    return nil
end

local function clear(t)
    if type(t) ~= "table" then return end
    for key in pairs(t) do t[key] = nil end
end

function SK.Declare(k, diag)
    local api = {}
    local state = { choices = {}, noAttack = {}, placed = {} }
    local client

    local function say(text)
        if client then client.print(ns.id.title .. ": " .. text) end
    end

    -- Each tick's input for Rotation/Driver.lua.
    function api.input(settings)
        if type(settings) ~= "table" or type(settings.get) ~= "function" then return nil end
        return {
            autoAttack = settings:get(SK.ATTACK) ~= false,
            listOff = settings:get(SK.LIST) == false,
            choices = state.choices,
            noAttack = state.noAttack,
        }
    end

    -- Your class's rotation spells, a to z.
    local function packSpells()
        local class = ask(client, "class")
        local packs = ns.Packs
        local pack = type(class) == "string" and type(packs) == "table" and packs[class]
        if type(pack) ~= "table" or not ns.RotationReader then return {} end
        return ns.RotationReader.SpellNames(pack)
    end

    local function named(spell)
        local want = string.lower(spell)
        for _, name in ipairs(packSpells()) do
            if string.lower(name) == want then return name end
        end
        return nil
    end

    local function spells(rest)
        local word, spell = tostring(rest or ""):match("^%s*(%S*)%s*(.-)%s*$")
        if word ~= "" then
            local name = spell ~= "" and named(spell)
            if not name then
                say(string.format("%s is not a spell in your rotation.", spell ~= "" and spell or "(none)"))
                return
            end
            local ok, why = SK.Set(state.choices, name, word)
            if not ok then
                say(tostring(why))
                return
            end
        end
        local list = packSpells()
        if #list == 0 then
            say("no rotation for your class.")
            return
        end
        say("your spells list (bar: off the key; skip: never suggested):")
        for _, name in ipairs(list) do say("  " .. name .. ": " .. (state.choices[name] or "key")) end
    end

    local function attack(rest)
        local word, name = tostring(rest or ""):match("^%s*(%S*)%s*(.-)%s*$")
        if word == "never" then
            local enemy = ask(client, "targetName")
            if type(enemy) ~= "string" or enemy == "" then
                say("target the enemy first.")
                return
            end
            state.noAttack[enemy] = true
            say(enemy .. " will not be given auto attack.")
            return
        end
        if word == "forget" then
            -- The slash text may come lowercased: the name is matched in any case.
            if name == "all" then clear(state.noAttack) end
            local want = string.lower(name)
            for enemy in pairs(state.noAttack) do
                if string.lower(enemy) == want then state.noAttack[enemy] = nil end
            end
            say("forgot " .. (name ~= "" and name or "(none)") .. ".")
            return
        end
        local names = {}
        for enemy in pairs(state.noAttack) do names[#names + 1] = enemy end
        table.sort(names)
        say("never given auto attack: " .. (#names > 0 and table.concat(names, ", ") or "none"))
    end

    local function placed(rest)
        if tostring(rest or ""):match("^%s*forget%s*$") then
            for i = #state.placed, 1, -1 do state.placed[i] = nil end
            say("forgot the spells the game put on your bars.")
            return
        end
        if #state.placed == 0 then
            say("the game has put no spell on your bars.")
            return
        end
        for _, row in ipairs(state.placed) do
            say(SK.Notice(ask(client, "spellName", row.id), row.id, row.slot))
        end
    end

    -- N26: the game put a spell on a bar. Said and kept; nothing acts.
    local function pushed(ctx, spellId, slot)
        if ctx.settings:get(SK.PLACED) == false or type(spellId) ~= "number" then return end
        if type(slot) ~= "number" then slot = nil end
        SK.Remember(state.placed, { id = spellId, slot = slot }, SK.PLACED_MAX)
        say(SK.Notice(ask(client, "spellName", spellId), spellId, slot))
    end

    k:Module({
        name = SK.NAME,
        needs = { "client", "store", "bus" },
        settings = { {
            key = SK.ATTACK, scope = "account", type = "bool", default = true,
            label = "The key starts auto attack at the pull",
            help = "Out of a fight, with an enemy targeted and you not swinging yet, the rotation key holds Attack until the swing is on. Not in a fight. Enemies you name with the attack word are never given it.",
            group = "combat.rotation", synonyms = { "auto attack", "attack", "pull", "swing", "melee", "easy key" },
        }, {
            key = SK.LIST, scope = "char", type = "bool", default = true,
            label = "Obey your spells list: Bar, Key or Skip",
            help = "Per spell of your rotation: Key may go on the rotation key, Bar is shown but kept off the key, Skip is never suggested. Set them with the spells word; kept in Flow's own saved data.",
            group = "combat.spells", synonyms = { "spells list", "bar", "key", "skip", "spells", "easy key" },
        }, {
            key = SK.PLACED, scope = "char", type = "bool", default = true,
            label = "Say when the game puts a spell on your bars",
            help = "A line in chat naming the spell and the bar and slot the game put it on, kept in a list of the last 40. It moves nothing on your bars.",
            group = "combat.spells", synonyms = { "auto place", "new spell", "action bar", "bars", "placed", "notice" },
        } },
        provides = { Input = api.input },
        start = function(ctx)
            client = ctx.client
            local store = ctx.store or k.store
            local okC, choices = pcall(store.table, store, "char", SK.CHOICES_PATH)
            if okC and type(choices) == "table" then state.choices = choices else state.choices = {} end
            local okN, never = pcall(store.table, store, "char", SK.NO_ATTACK_PATH)
            if okN and type(never) == "table" then state.noAttack = never else state.noAttack = {} end
            local okP, list = pcall(store.table, store, "char", SK.PLACED_PATH)
            if okP and type(list) == "table" then state.placed = list else state.placed = {} end
            ctx.bus:on(SK.NAME, SK.EVENT, function(spellId, slot) pushed(ctx, spellId, slot) end)
        end,
        stop = function() state = { choices = {}, noAttack = {}, placed = {} } end,
    })

    if diag and type(diag.commands) == "table" then
        diag.commands[SK.WORDS.spells] = spells
        diag.commands[SK.WORDS.attack] = attack
        diag.commands[SK.WORDS.placed] = placed
        if type(diag.help) == "table" then
            for word, text in pairs(SK.HELP) do diag.help[word] = text end
        end
    end

    return api
end

ns.spellKeys = SK.Declare(ns, ns.diag)
