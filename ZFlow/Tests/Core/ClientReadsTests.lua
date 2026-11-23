-- The client reads added for the profession step and the rotation reader:
-- merchant rows with a field the client did not give (PF1), trainer(),
-- faction(), the profession's name in recipes(), spellCooldown() and
-- class(). No game client is involved: `env` stands in for its globals.
local _, ns = ...

local LEATHER = "|cffffffff|Hitem:2318:0:0:0:0:0:0:0|h[Light Leather]|h|r"
local GCD = 61304

local function boom() error("the client refused") end

-- An environment with frames, so events can be fired at the client.
local function frameEnv()
    local env = { frames = {} }
    function env.CreateFrame()
        local f = { scripts = {}, events = {} }
        function f:SetScript(name, fn) self.scripts[name] = fn end
        function f:RegisterEvent(event) self.events[event] = true end
        function f:UnregisterEvent(event) self.events[event] = nil end
        env.frames[#env.frames + 1] = f
        return f
    end
    function env.fire(event, ...)
        for _, f in ipairs(env.frames) do
            if f.events[event] then f.scripts.OnEvent(f, event, ...) end
        end
    end
    return env
end

-- The client as it is in game: asked about nil, issecretvalue raises.
local function strictSecret(env, secret)
    env.issecretvalue = function(v)
        if v == nil then error("issecretvalue: nil") end
        return secret ~= nil and secret(v) or false
    end
end

-- A merchant selling `rows` through the bare globals, its window open.
local function openMerchant(rows)
    local env = frameEnv()
    env.GetMerchantNumItems = function() return #rows end
    env.GetMerchantItemLink = function(index) return rows[index].link end
    env.GetMerchantItemInfo = function(index)
        local row = rows[index]
        return "name", 1, row.price, row.stack, -1, true, true, row.other and true or false
    end
    local c = ns.make.client(env)
    c.watchMerchant()
    env.fire("MERCHANT_SHOW")
    return c, env
end

-- A trainer window: who = { name =, player =, line = }.
local function trainerEnv(who)
    local env = frameEnv()
    env.asked = {}
    env.UnitName = function(unit)
        env.asked[#env.asked + 1] = unit
        return unit == "npc" and who.name or nil
    end
    env.UnitIsPlayer = function(unit)
        env.asked[#env.asked + 1] = unit
        if unit ~= "npc" then return nil end
        return who.player
    end
    env.GetTrainerServiceSkillLine = function(index) return index == 1 and who.line or nil end
    return env
end

-- A profession window with no recipes; `base` is GetBaseProfessionInfo's answer.
local function recipeEnv(base)
    local env = frameEnv()
    env.C_TradeSkillUI = {
        IsTradeSkillReady = function() return true end,
        IsDataSourceChanging = function() return false end,
        GetBaseProfessionInfo = function() return base end,
        GetAllRecipeIDs = function() return {} end,
        GetRecipeInfo = function() return nil end,
    }
    return env
end

-- Spell cooldowns through the table answer: rows[id] = { startTime =, duration =, isOnGCD = }.
local function tableCooldowns(rows)
    local env = frameEnv()
    env.C_Spell = { GetSpellCooldown = function(id) return rows[id] end }
    return env
end

-- Spell cooldowns through the bare global: rows[id] = { start, duration }.
local function bareCooldowns(rows)
    local env = frameEnv()
    env.GetSpellCooldown = function(id)
        local r = rows[id]
        if not r then return nil end
        return r[1], r[2], 1
    end
    return env
end

return {
    -- ---------------------------------------------------------------- PF1
    ["PF1: an uncached link loses its own item only, never the merchant reading"] = function(t)
        local c, env = openMerchant({
            { link = nil, price = 60, stack = 1 },
            { link = LEATHER, price = 50, stack = 5 },
        })
        strictSecret(env)
        t.eq(c.merchantItems(), {
            { index = 1, price = 60, stack = 1, other = false },
            { index = 2, item = LEATHER, price = 50, stack = 5, other = false },
        })
    end,

    ["PF1: a price or stack the bare answer leaves out is left out of its row"] = function(t)
        local c, env = openMerchant({
            { link = LEATHER, price = nil, stack = nil },
            { link = "item:2320", price = 50, stack = 5 },
        })
        strictSecret(env)
        t.eq(c.merchantItems(), {
            { index = 1, item = LEATHER, other = false },
            { index = 2, item = "item:2320", price = 50, stack = 5, other = false },
        })
    end,

    ["PF1: the table answer may leave out the price, the stack or the whole item"] = function(t)
        local c, env = openMerchant({
            { link = LEATHER, price = 1, stack = 1 },
            { link = "item:2320", price = 1, stack = 1 },
            { link = "item:2321", price = 1, stack = 1 },
        })
        strictSecret(env)
        env.C_MerchantFrame = { GetItemInfo = function(index)
            if index == 1 then return { hasExtendedCost = false } end
            if index == 2 then return nil end
            return { price = 10, stackCount = 1, hasExtendedCost = true }
        end }
        t.eq(c.merchantItems(), {
            { index = 1, item = LEATHER, other = false },
            { index = 2, item = "item:2320" },
            { index = 3, item = "item:2321", price = 10, stack = 1, other = true },
        })
    end,

    ["PF1: a value the client does mark secret still voids the reading"] = function(t)
        local c, env = openMerchant({ { link = LEATHER, price = 60, stack = 1 } })
        strictSecret(env, function(v) return v == LEATHER end)
        t.eq(c.merchantItems(), nil, "a secret link")
        strictSecret(env, function(v) return v == 60 end)
        t.eq(c.merchantItems(), nil, "a secret price")
        strictSecret(env)
        t.eq(c.merchantItems(), { { index = 1, item = LEATHER, price = 60, stack = 1, other = false } })
    end,

    -- ----------------------------------------------------------------- C1
    ["C1: trainer() is nil when the window is closed or not known"] = function(t)
        local env = trainerEnv({ name = "Bena Winterhoof", player = false, line = "Alchemy" })
        local c = ns.make.client(env)
        c.watchTrainer()
        t.eq(c.trainer(), nil, "no event and no frame: not known")
        env.fire("TRAINER_SHOW")
        t.eq(c.trainer(), { profession = "Alchemy", npc = "Bena Winterhoof" })
        env.fire("TRAINER_CLOSED")
        t.eq(c.trainer(), nil, "closed")
        t.eq(env.frames[1].events.TRAINER_SHOW, true)
        t.eq(env.frames[1].events.TRAINER_CLOSED, true)
    end,

    ["C1: trainer() is nil for a player, and when the client will not say"] = function(t)
        local who = { name = "Someone", player = true, line = "Alchemy" }
        local env = trainerEnv(who)
        local c = ns.make.client(env)
        c.watchTrainer()
        env.fire("TRAINER_SHOW")
        t.eq(c.trainer(), nil, "a player")
        who.player = nil
        t.eq(c.trainer(), nil, "player or not: not said")
        who.player = false
        t.eq(c.trainer(), { profession = "Alchemy", npc = "Someone" })
        env.UnitIsPlayer = boom
        t.eq(c.trainer(), nil, "the call fails")
        env.UnitIsPlayer = nil
        t.eq(c.trainer(), nil, "the call is missing")
    end,

    ["C1: trainer() needs the npc's name; the profession may be left out"] = function(t)
        local who = { name = "Bena Winterhoof", player = false, line = nil }
        local env = trainerEnv(who)
        local c = ns.make.client(env)
        c.watchTrainer()
        env.fire("TRAINER_SHOW")
        t.eq(c.trainer(), { npc = "Bena Winterhoof" }, "no skill line: a trainer with no profession said")
        who.line = ""
        t.eq(c.trainer(), { npc = "Bena Winterhoof" }, "an empty line is not a profession")
        who.line = 7
        t.eq(c.trainer(), { npc = "Bena Winterhoof" }, "a number is not a profession name")
        env.GetTrainerServiceSkillLine = boom
        t.eq(c.trainer(), { npc = "Bena Winterhoof" }, "the line call fails")
        env.GetTrainerServiceSkillLine = nil
        t.eq(c.trainer(), { npc = "Bena Winterhoof" }, "the line call is missing")
        who.name = nil
        t.eq(c.trainer(), nil, "no name")
        who.name = ""
        t.eq(c.trainer(), nil, "an empty name")
        env.UnitName = boom
        t.eq(c.trainer(), nil, "the name call fails")
    end,

    ["C1: before any event the trainer window's own frame is the first guess"] = function(t)
        local env = trainerEnv({ name = "Bena Winterhoof", player = false, line = "Alchemy" })
        env.ClassTrainerFrame = { IsShown = function() return env.shown end }
        local c = ns.make.client(env)
        env.shown = true
        t.eq(c.trainer(), { profession = "Alchemy", npc = "Bena Winterhoof" })
        env.shown = false
        t.eq(c.trainer(), nil)
        env.ClassTrainerFrame = { IsShown = boom }
        t.eq(c.trainer(), nil)
    end,

    ["C1: trainer() asks about no unit but the npc"] = function(t)
        local env = trainerEnv({ name = "Bena Winterhoof", player = false, line = "Alchemy" })
        local c = ns.make.client(env)
        c.watchTrainer()
        env.fire("TRAINER_SHOW")
        c.trainer()
        t.ok(#env.asked > 0, "the client was asked")
        for _, unit in ipairs(env.asked) do t.eq(unit, "npc") end
    end,

    -- ----------------------------------------------------------------- C2
    ["C2: faction() is Horde or Alliance, and nil on any other answer"] = function(t)
        local env = frameEnv()
        local asked = {}
        env.UnitFactionGroup = function(unit)
            asked[#asked + 1] = unit
            return env.group, "localised"
        end
        local c = ns.make.client(env)
        env.group = "Horde"
        t.eq(c.faction(), "Horde")
        env.group = "Alliance"
        t.eq(c.faction(), "Alliance")
        env.group = "Neutral"
        t.eq(c.faction(), nil, "an answer that is neither")
        env.group = nil
        t.eq(c.faction(), nil, "no answer")
        env.group = 1
        t.eq(c.faction(), nil, "a number")
        for _, unit in ipairs(asked) do t.eq(unit, "player") end
        env.UnitFactionGroup = boom
        t.eq(c.faction(), nil, "the call fails")
        env.UnitFactionGroup = nil
        t.eq(c.faction(), nil, "the call is missing")
    end,

    -- ----------------------------------------------------------------- C3
    ["C3: recipes() carries the profession's name when the client gives a string"] = function(t)
        local base = { professionID = 164, skillLevel = 104, maxSkillLevel = 150, professionName = "Blacksmithing" }
        local c = ns.make.client(recipeEnv(base))
        t.eq(c.recipes(), { profession = 164, skill = 104, max = 150, name = "Blacksmithing", recipes = {} })
    end,

    ["C3: with no name string the field is absent and the reading is unchanged"] = function(t)
        local base = { professionID = 164, skillLevel = 104, maxSkillLevel = 150 }
        local c = ns.make.client(recipeEnv(base))
        local plain = { profession = 164, skill = 104, max = 150, recipes = {} }
        t.eq(c.recipes(), plain, "no name given")
        base.professionName = 164
        t.eq(c.recipes(), plain, "a number is not a name")
        base.professionName = false
        t.eq(c.recipes(), plain, "false is not a name")
    end,

    -- ----------------------------------------------------------------- C4
    ["C4: a secret trainer name gives nil; a secret skill line leaves the profession out"] = function(t)
        local env = trainerEnv({ name = "Bena Winterhoof", player = false, line = "Alchemy" })
        local c = ns.make.client(env)
        c.watchTrainer()
        env.fire("TRAINER_SHOW")
        strictSecret(env, function(v) return v == "Bena Winterhoof" end)
        t.eq(c.trainer(), nil, "a secret name")
        strictSecret(env, function(v) return v == "Alchemy" end)
        t.eq(c.trainer(), { npc = "Bena Winterhoof" }, "a secret skill line")
        strictSecret(env, function(v) return v == false end)
        t.eq(c.trainer(), nil, "player or not is secret")
        strictSecret(env)
        t.eq(c.trainer(), { profession = "Alchemy", npc = "Bena Winterhoof" })
    end,

    ["C4: a secret faction, class or profession name gives nil"] = function(t)
        local env = recipeEnv({ professionID = 164, skillLevel = 104, maxSkillLevel = 150, professionName = "Blacksmithing" })
        env.UnitFactionGroup = function() return "Horde" end
        env.UnitClass = function() return "Druid", "DRUID", 11 end
        local c = ns.make.client(env)
        strictSecret(env, function(v) return type(v) == "string" end)
        t.eq(c.faction(), nil)
        t.eq(c.class(), nil)
        t.eq(c.recipes(), { profession = 164, skill = 104, max = 150, recipes = {} }, "the name alone is left out")
        strictSecret(env)
        t.eq(c.faction(), "Horde")
        t.eq(c.class(), "DRUID")
        t.eq(c.recipes().name, "Blacksmithing")
    end,

    ["C4: a secret cooldown start or length is not known, never ready"] = function(t)
        local env = tableCooldowns({ [8921] = { startTime = 100, duration = 30, isOnGCD = false } })
        local c = ns.make.client(env)
        strictSecret(env, function(v) return v == 30 end)
        t.eq(c.spellCooldown(8921), nil, "a secret length")
        strictSecret(env, function(v) return v == 100 end)
        t.eq(c.spellCooldown(8921), nil, "a secret start")
        strictSecret(env, function(v) return type(v) == "table" end)
        t.eq(c.spellCooldown(8921), nil, "a secret answer")
        strictSecret(env)
        t.eq(c.spellCooldown(8921), true)
    end,

    -- ----------------------------------------------------------------- C5
    ["C5a: a spell on its own cooldown is true"] = function(t)
        local c = ns.make.client(tableCooldowns({ [8921] = { startTime = 100, duration = 30, isOnGCD = false } }))
        t.eq(c.spellCooldown(8921), true)
        local bare = ns.make.client(bareCooldowns({ [8921] = { 90, 30 }, [GCD] = { 100, 1.5 } }))
        t.eq(bare.spellCooldown(8921), true, "the bare answer, not the global cooldown's times")
        bare = ns.make.client(bareCooldowns({ [8921] = { 90, 30 }, [GCD] = { 0, 0 } }))
        t.eq(bare.spellCooldown(8921), true, "the bare answer, no global cooldown running")
    end,

    ["C5b: a ready spell is false"] = function(t)
        local c = ns.make.client(tableCooldowns({ [5176] = { startTime = 0, duration = 0, isOnGCD = false } }))
        t.eq(c.spellCooldown(5176), false)
        local bare = ns.make.client(bareCooldowns({ [5176] = { 0, 0 } }))
        t.eq(bare.spellCooldown(5176), false, "the bare answer")
    end,

    ["C5c: the global cooldown alone is not a cooldown"] = function(t)
        local c = ns.make.client(tableCooldowns({ [5176] = { startTime = 100, duration = 1.5, isOnGCD = true } }))
        t.eq(c.spellCooldown(5176), false, "the client marks it the global cooldown")
        local bare = ns.make.client(bareCooldowns({ [5176] = { 100, 1.5 }, [GCD] = { 100, 1.5 } }))
        t.eq(bare.spellCooldown(5176), false, "the same start and length as the global cooldown")
        local unmarked = ns.make.client(tableCooldowns({
            [5176] = { startTime = 100, duration = 1.5 },
            [GCD] = { startTime = 100, duration = 1.5 },
        }))
        t.eq(unmarked.spellCooldown(5176), false, "no mark: compared with the global cooldown")
    end,

    ["C5d: no spell, a missing call or an odd answer is not known"] = function(t)
        local env = tableCooldowns({ [8921] = { startTime = 100, duration = 30, isOnGCD = false } })
        local c = ns.make.client(env)
        t.eq(c.spellCooldown(nil), nil, "no id")
        t.eq(c.spellCooldown("8921"), nil, "a name is not an id")
        t.eq(c.spellCooldown(1), nil, "the client has no such spell")
        env.C_Spell.GetSpellCooldown = function() return { startTime = "soon", duration = 30 } end
        t.eq(c.spellCooldown(8921), nil, "a start that is not a number")
        env.C_Spell.GetSpellCooldown = function() return { startTime = 100 } end
        t.eq(c.spellCooldown(8921), nil, "no length")
        env.C_Spell.GetSpellCooldown = boom
        t.eq(c.spellCooldown(8921), nil, "the call fails")
        env.C_Spell = nil
        t.eq(c.spellCooldown(8921), nil, "no call at all")
        local bare = ns.make.client(bareCooldowns({ [8921] = { 90, 30 } }))
        t.eq(bare.spellCooldown(8921), nil, "running, and the global cooldown cannot be read: not known")
        t.eq(bare.spellCooldown(5176), nil, "the bare call has no such spell")
    end,

    -- ----------------------------------------------------------------- C6
    ["C6: class() is the class token, or nil when not known"] = function(t)
        local env = frameEnv()
        local asked = {}
        env.UnitClass = function(unit)
            asked[#asked + 1] = unit
            return "Druide", env.token, 11
        end
        local c = ns.make.client(env)
        env.token = "DRUID"
        t.eq(c.class(), "DRUID", "the second answer, not the localised name")
        env.token = nil
        t.eq(c.class(), nil, "no token")
        env.token = ""
        t.eq(c.class(), nil, "an empty token")
        env.token = 11
        t.eq(c.class(), nil, "a number")
        for _, unit in ipairs(asked) do t.eq(unit, "player") end
        env.UnitClass = boom
        t.eq(c.class(), nil, "the call fails")
        env.UnitClass = nil
        t.eq(c.class(), nil, "the call is missing")
    end,

    -- --------------------------------------------------------------- fake
    -- ------------------------------------------------------------ stealth
    ["stealthed() is true or false as the client says, and nil when it does not say"] = function(t)
        local env = frameEnv()
        local c = ns.make.client(env)
        t.eq(c.stealthed(), nil, "no call: not known")
        local answer = true
        env.IsStealthed = function() return answer end
        t.eq(c.stealthed(), true)
        answer = false
        t.eq(c.stealthed(), false)
        answer = nil
        t.eq(c.stealthed(), nil, "no answer is not 'not stealthed'")
        answer = 1
        t.eq(c.stealthed(), nil, "a number is not an answer")
        answer = "yes"
        t.eq(c.stealthed(), nil, "a string is not an answer")
        answer = true
        strictSecret(env, function(v) return v == true end)
        t.eq(c.stealthed(), nil, "a secret answer")
        strictSecret(env)
        t.eq(c.stealthed(), true)
        env.IsStealthed = boom
        t.eq(c.stealthed(), nil, "the call fails")
    end,

    ["stealthed() asks the client about nothing but you"] = function(t)
        local env = frameEnv()
        local args
        env.IsStealthed = function(...)
            args = select("#", ...)
            return false
        end
        t.eq(ns.make.client(env).stealthed(), false)
        t.eq(args, 0, "no unit is named")
    end,

    -- ---------------------------------------------------------------- CR2
    ["CR2: a cooldown that is waiting to start is not known, never ready"] = function(t)
        local rows = { [5215] = { startTime = 0, duration = 0, isOnGCD = false, isEnabled = false } }
        local c = ns.make.client(tableCooldowns(rows))
        t.eq(c.spellCooldown(5215), nil, "waiting, start 0: not ready")
        rows[5215] = { startTime = 100, duration = 10, isOnGCD = false, isEnabled = false }
        t.eq(c.spellCooldown(5215), nil, "waiting with times")
        rows[5215] = { startTime = 0, duration = 0, isOnGCD = false, isEnabled = true }
        t.eq(c.spellCooldown(5215), false, "enabled and no times: ready")
        rows[5215] = { startTime = 100, duration = 10, isOnGCD = false, isEnabled = true }
        t.eq(c.spellCooldown(5215), true, "enabled and running")
        rows[5215] = { startTime = 0, duration = 0, isOnGCD = false, isEnabled = "no" }
        t.eq(c.spellCooldown(5215), false, "an odd mark is no mark")

        local mark = 0
        local env = frameEnv()
        env.GetSpellCooldown = function(id)
            if id ~= 5215 then return 0, 0, 1 end
            return 0, 0, mark
        end
        local bare = ns.make.client(env)
        t.eq(bare.spellCooldown(5215), nil, "the bare answer, enabled 0")
        mark = false
        t.eq(bare.spellCooldown(5215), nil, "the bare answer, enabled false")
        mark = 1
        t.eq(bare.spellCooldown(5215), false, "the bare answer, enabled 1")
        mark = true
        t.eq(bare.spellCooldown(5215), false, "the bare answer, enabled true")
        mark = nil
        t.eq(bare.spellCooldown(5215), false, "no mark given: as before")
    end,

    ["CR2: a secret enabled mark is no mark"] = function(t)
        local env = tableCooldowns({
            [5215] = { startTime = 100, duration = 10, isOnGCD = false, isEnabled = false },
            [GCD] = { startTime = 0, duration = 0 },
        })
        local c = ns.make.client(env)
        strictSecret(env, function(v) return v == false end)
        t.eq(c.spellCooldown(5215), true, "isOnGCD and isEnabled both secret: the times decide")
    end,

    ["fake: stealthed() is nil until set"] = function(t)
        local c = ns.make.fakeClient()
        t.eq(c.stealthed(), nil)
        c.setStealthed(true)
        t.eq(c.stealthed(), true)
        c.setStealthed(false)
        t.eq(c.stealthed(), false)
        c.setStealthed(nil)
        t.eq(c.stealthed(), nil)
    end,

    ["fake: trainer, faction, class and spell cooldown are nil until set"] = function(t)
        local c = ns.make.fakeClient()
        t.eq(c.trainer(), nil)
        t.eq(c.faction(), nil)
        t.eq(c.class(), nil)
        t.eq(c.spellCooldown(8921), nil)
        t.eq(c.spellCooldown("8921"), nil)
        c.setTrainer({ profession = "Alchemy", npc = "Bena Winterhoof" })
        c.setFaction("Horde")
        c.setClass("DRUID")
        c.setSpellCooldown(8921, true)
        c.setSpellCooldown(5176, false)
        t.eq(c.trainer(), { profession = "Alchemy", npc = "Bena Winterhoof" })
        t.eq(c.faction(), "Horde")
        t.eq(c.class(), "DRUID")
        t.eq(c.spellCooldown(8921), true)
        t.eq(c.spellCooldown(5176), false)
        t.eq(c.spellCooldown(1), nil, "a spell never set is not known")
        c.setTrainer(nil)
        c.setSpellCooldown(8921, nil)
        t.eq(c.trainer(), nil)
        t.eq(c.spellCooldown(8921), nil)
    end,

    ["fake: trainer() hands out a copy, and recipes() passes the name through"] = function(t)
        local c = ns.make.fakeClient()
        c.setTrainer({ npc = "Bena Winterhoof" })
        c.trainer().npc = "changed"
        t.eq(c.trainer(), { npc = "Bena Winterhoof" })
        c.setRecipes({ profession = 164, skill = 1, max = 75, recipes = {} })
        t.eq(c.recipes(), { profession = 164, skill = 1, max = 75, recipes = {} }, "no name set: none given")
        c.setRecipes({ profession = 164, name = "Blacksmithing", skill = 1, max = 75, recipes = {} })
        t.eq(c.recipes().name, "Blacksmithing")
    end,

    -- Section 227 (P-GOALS-RECIPE) ---------------------------------------
    ["recipeSchematic(): the product, the yield and the required basic mats"] = function(t)
        local env = frameEnv()
        local answer = {
            outputItemID = 2996, quantityMin = 1,
            reagentSlotSchematics = {
                { reagentType = 1, required = true, quantityRequired = 2, reagents = { { itemID = 2589 } } },
                { reagentType = 0, required = false, quantityRequired = 1, reagents = { { itemID = 4340 } } },
                { reagentType = 1, quantityRequired = 1, reagents = { { itemID = 2320 }, { itemID = 2321 } } },
            },
        }
        local asked
        env.C_TradeSkillUI = { GetRecipeSchematic = function(id, recraft) asked = { id, recraft }; return answer end }
        local c = ns.make.client(env)
        t.eq(c.recipeSchematic(2963), { makes = 2996, yield = 1, mats = { [2589] = 2, [2320] = 1 } },
            "the optional slot is left out; a slot names its first reagent")
        t.eq(asked, { 2963, false }, "asked for the recipe, not a recraft")
        answer.quantityMin = nil
        t.eq(c.recipeSchematic(2963).yield, 1, "no yield given: one a craft")
    end,

    ["recipeSchematic(): nil when the client can't say"] = function(t)
        local env = frameEnv()
        local answer
        env.C_TradeSkillUI = { GetRecipeSchematic = function() return answer end }
        local c = ns.make.client(env)
        t.eq(c.recipeSchematic("2963"), nil, "an id that is no number")
        t.eq(c.recipeSchematic(2963), nil, "no answer")
        answer = { quantityMin = 1, reagentSlotSchematics = {} }
        t.eq(c.recipeSchematic(2963), nil, "no product")
        answer = { outputItemID = 2996, quantityMin = 1,
                   reagentSlotSchematics = { { reagentType = 1, quantityRequired = 2, reagents = {} } } }
        t.eq(c.recipeSchematic(2963), nil, "a required slot with no reagent: never a shorter list")
        answer = { outputItemID = 2996, quantityMin = 0, reagentSlotSchematics = {} }
        t.eq(c.recipeSchematic(2963), nil, "a yield below 1")
        env.C_TradeSkillUI.GetRecipeSchematic = boom
        t.eq(c.recipeSchematic(2963), nil, "the read raised")
        env.C_TradeSkillUI = nil
        t.eq(c.recipeSchematic(2963), nil, "no trade skill API")
    end,

    ["fake: recipeSchematic() hands out a copy"] = function(t)
        local c = ns.make.fakeClient()
        t.eq(c.recipeSchematic(2963), nil, "none set")
        c.setRecipeSchematic(2963, { makes = 2996, yield = 1, mats = { [2589] = 2 } })
        c.recipeSchematic(2963).mats[2589] = 9
        t.eq(c.recipeSchematic(2963), { makes = 2996, yield = 1, mats = { [2589] = 2 } })
    end,

    -- Section 231 item 1 ---------------------------------------------------
    ["tradeSkillSchematic(): the classic reads give the schematic when GetRecipeSchematic is missing"] = function(t)
        local env = frameEnv()
        env.C_TradeSkillUI = {}
        local links = { [2] = "|cffffffff|Hitem:2996::::::::|h[Bolt of Linen Cloth]|h|r" }
        local reagents = { [2] = {
            { link = "|cffffffff|Hitem:2589::::::::|h[Linen Cloth]|h|r", need = 2 },
            { link = "|cffffffff|Hitem:2320::::::::|h[Coarse Thread]|h|r", need = 1 },
        } }
        function env.GetTradeSkillInfo() return "Bolt of Linen Cloth", "optimal", 0, true end
        function env.GetTradeSkillItemLink(i) return links[i] end
        function env.GetTradeSkillNumMade() return 1, 1 end
        function env.GetTradeSkillNumReagents(i) return reagents[i] and #reagents[i] or 0 end
        function env.GetTradeSkillReagentItemLink(i, r) return reagents[i][r].link end
        function env.GetTradeSkillReagentInfo(i, r)
            return "name", "texture", reagents[i][r].need, 40
        end
        local c = ns.make.client(env)
        t.eq(c.recipeSchematic(2963), nil, "no GetRecipeSchematic: the first read says nothing")
        t.eq(c.tradeSkillSchematic(2), { name = "Bolt of Linen Cloth", difficulty = "optimal", makes = 2996,
            yield = 1, mats = { [2589] = 2, [2320] = 1 } },
            "the fallback names the recipe, its difficulty, the product, the yield and the mats")
        env.GetTradeSkillNumMade = function() return 2, 3 end
        t.eq(c.tradeSkillSchematic(2).yield, 2, "the least a craft makes")
        env.GetTradeSkillNumMade = nil
        t.eq(c.tradeSkillSchematic(2).yield, 1, "no NumMade read: one a craft")
    end,

    ["tradeSkillSchematic(): nil when the client can't say"] = function(t)
        local env = frameEnv()
        local c = ns.make.client(env)
        t.eq(c.tradeSkillSchematic(2), nil, "no classic reads")
        t.eq(c.tradeSkillSchematic(0), nil, "no row 0")
        t.eq(c.tradeSkillSchematic("2"), nil, "an index that is no number")
        local link = "|cffffffff|Hitem:2996::::::::|h[Bolt]|h|r"
        local need, kind = 2, "easy"
        function env.GetTradeSkillInfo() return "Bolt", kind, 0, true end
        function env.GetTradeSkillItemLink() return link end
        function env.GetTradeSkillNumReagents() return 1 end
        function env.GetTradeSkillReagentItemLink() return "|cffffffff|Hitem:2589::::::::|h[Linen]|h|r" end
        function env.GetTradeSkillReagentInfo() return "Linen", nil, need, 0 end
        t.eq(c.tradeSkillSchematic(2), { name = "Bolt", difficulty = "easy", makes = 2996, yield = 1,
            mats = { [2589] = 2 } }, "all read")
        env.GetTradeSkillNumReagents = function() return 0 end
        t.eq(c.tradeSkillSchematic(2), nil, "RF-4: no reagents read")
        env.GetTradeSkillNumReagents = function() return 1 end
        kind = "header"
        t.eq(c.tradeSkillSchematic(2), nil, "RF-2: a header row is no recipe")
        kind = "subheader"
        t.eq(c.tradeSkillSchematic(2), nil, "RF-2: nor a subheader row")
        kind = nil
        t.eq(c.tradeSkillSchematic(2), nil, "a row of no kind")
        kind = "easy"
        env.GetTradeSkillItemLink = function() error("link read failed") end
        t.eq(c.tradeSkillSchematic(2), nil, "the product read failed")
        env.GetTradeSkillItemLink = function() return 7 end
        t.eq(c.tradeSkillSchematic(2), nil, "a product link that is no string")
    end,

    -- Section 238 (RF-1, RF-3). Fails before: both answers were nil, so the
    -- recipe was not saved at all (Flow kept it).
    ["tradeSkillSchematic(): an enchant keeps its reagents; a reagent not read yet says partial"] = function(t)
        local env = frameEnv()
        local c = ns.make.client(env)
        local BOLT = "|cffffffff|Hitem:2996::::::::|h[Bolt]|h|r"
        local LINEN = "|cffffffff|Hitem:2589::::::::|h[Linen]|h|r"
        local link, reagent, need = "|cffffd000|Henchant:7418|h[Enchant Bracer]|h|r", LINEN, 2
        function env.GetTradeSkillInfo() return "Enchant Bracer", "optimal", 0, true end
        function env.GetTradeSkillItemLink() return link end
        function env.GetTradeSkillNumReagents() return 1 end
        function env.GetTradeSkillReagentItemLink() return reagent end
        function env.GetTradeSkillReagentInfo() return "Linen", nil, need, 0 end
        t.eq(c.tradeSkillSchematic(2), { name = "Enchant Bracer", difficulty = "optimal", yield = 1,
            mats = { [2589] = 2 } }, "RF-1: no product item, the reagents kept")
        link, need = BOLT, nil
        t.eq(c.tradeSkillSchematic(2), { name = "Enchant Bracer", difficulty = "optimal", makes = 2996, yield = 1,
            mats = {}, partial = true }, "RF-3: a reagent count not read: kept, said partial")
        need, reagent = 2, nil
        t.eq(c.tradeSkillSchematic(2).partial, true, "RF-3: a reagent item not read: partial")
        reagent, link = LINEN, nil
        t.eq(c.tradeSkillSchematic(2), { name = "Enchant Bracer", difficulty = "optimal", yield = 1,
            mats = { [2589] = 2 }, partial = true }, "no product link yet: no product, partial")
        link = BOLT
        t.eq(c.tradeSkillSchematic(2).partial, nil, "all read again: not partial")
    end,

    -- Section 233 (GR2-1) ---------------------------------------------------
    ["tradeSkillRows(): the classic window's recipe rows, headers left out"] = function(t)
        local env = frameEnv()
        local info = {
            { "Cloth", "header" },
            { "Bolt of Linen Cloth", "trivial" },
            { "Brown Linen Robe", "optimal" },
        }
        function env.GetTradeSkillLine() return "Tailoring", 50, 75 end
        function env.GetNumTradeSkills() return #info end
        function env.GetTradeSkillInfo(i) return info[i][1], info[i][2], 0, true end
        local c = ns.make.client(env)
        t.eq(c.tradeSkillRows(), { name = "Tailoring", skill = 50, max = 75, rows = {
            { index = 2, name = "Bolt of Linen Cloth", difficulty = "trivial" },
            { index = 3, name = "Brown Linen Robe", difficulty = "optimal" } } },
            "section 238 RF-2: each row keeps its difficulty")
        info[3][1] = nil
        t.eq(c.tradeSkillRows(), nil, "a row with no name: never a shorter list")
        info[3][1] = "Brown Linen Robe"
        env.GetTradeSkillLine = function() return "UNKNOWN", 0, 0 end
        t.eq(c.tradeSkillRows(), nil, "no window open")
    end,

    ["tradeSkillRows(): nil when the client can't say"] = function(t)
        local env = frameEnv()
        local c = ns.make.client(env)
        t.eq(c.tradeSkillRows(), nil, "no classic reads")
        function env.GetTradeSkillLine() return "Tailoring", 50, 75 end
        function env.GetNumTradeSkills() return 0 end
        t.eq(c.tradeSkillRows(), nil, "no rows: no window")
        env.GetNumTradeSkills = function() return 1 end
        function env.GetTradeSkillInfo() return "Bolt", nil end
        t.eq(c.tradeSkillRows(), nil, "a row of no kind")
    end,

    ["tradeSkillRows(): the fake gives a copy"] = function(t)
        local c = ns.make.fakeClient()
        t.eq(c.tradeSkillRows(), nil, "none set")
        c.setTradeSkillRows({ name = "Tailoring", rows = { { index = 2, name = "Bolt" } } })
        c.tradeSkillRows().rows[1].name = "x"
        t.eq(c.tradeSkillRows(), { name = "Tailoring", rows = { { index = 2, name = "Bolt" } } })
    end,

    ["tradeSkillSchematic(): the fake gives a copy"] = function(t)
        local c = ns.make.fakeClient()
        t.eq(c.tradeSkillSchematic(2), nil, "none set")
        c.setTradeSkillSchematic(2, { makes = 2996, yield = 1, mats = { [2589] = 2 } })
        c.tradeSkillSchematic(2).mats[2589] = 9
        t.eq(c.tradeSkillSchematic(2), { makes = 2996, yield = 1, mats = { [2589] = 2 } })
        c.setTradeSkillSchematic(3, { name = "Enchant", difficulty = "easy", yield = 1, mats = {}, partial = true })
        t.eq(c.tradeSkillSchematic(3), { name = "Enchant", difficulty = "easy", yield = 1, mats = {}, partial = true },
            "section 238: name, difficulty and partial too")
    end,

    -- Section 235 item 4 ---------------------------------------------------
    ["fishingPole(): the main hand's class and subclass say it"] = function(t)
        local env = frameEnv()
        local held = { [6256] = { 2, 20 }, [25] = { 2, 7 } }
        local id = 6256
        local asked
        function env.GetInventoryItemID(unit, slot) asked = { unit, slot } return id end
        env.C_Item = { GetItemInfoInstant = function(item)
            local r = held[item]
            if not r then return nil end
            return item, "Weapon", "x", "INVTYPE_2HWEAPON", 0, r[1], r[2]
        end }
        local c = ns.make.client(env)
        t.eq(c.fishingPole(), true, "weapon 2, subclass 20")
        t.eq(asked, { "player", 16 }, "the main hand")
        id = 25
        t.eq(c.fishingPole(), false, "a sword")
        id = nil
        t.eq(c.fishingPole(), false, "nothing in the main hand")
        id = 7777
        t.eq(c.fishingPole(), nil, "a class not read: not known, never false")
        id = "6256"
        t.eq(c.fishingPole(), nil, "an id that is no number")
        env.GetInventoryItemID = function() error("no") end
        t.eq(c.fishingPole(), nil, "a failed call")
        env.GetInventoryItemID = nil
        t.eq(c.fishingPole(), nil, "no such read")
    end,

    ["fishingPole(): the fake is not known until set"] = function(t)
        local c = ns.make.fakeClient()
        t.eq(c.fishingPole(), nil)
        c.setFishingPole(true)
        t.eq(c.fishingPole(), true)
        c.setFishingPole(false)
        t.eq(c.fishingPole(), false)
        c.setFishingPole(nil)
        t.eq(c.fishingPole(), nil)
    end,
}
