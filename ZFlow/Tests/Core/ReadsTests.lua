-- The client's reads for Items and Nav (money, bags, bank, zone, position,
-- the combat lock) over a hand-built environment, their mirror in the fake
-- client, and the adapter that feeds Resources.Take. No game client is
-- involved: `env` stands in for its globals.
local _, ns = ...

local LEATHER = "|cffffffff|Hitem:2318:0:0:0:0:0:0:0|h[Light Leather]|h|r"
local BEAR = "item:15234:0:0:0:0:0:588:0"

local function boom() error("the client refused") end

-- An environment with frames (for events) and a C_Container over `bags`:
--   bags[id] = { family = n, size = n, [slot] = { link =, id =, count = } }
local function bagEnv(bags)
    local env = { frames = {}, bags = bags or {} }
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
    env.C_Container = {
        GetContainerNumSlots = function(bag)
            local b = env.bags[bag]
            return b and b.size or 0
        end,
        GetContainerNumFreeSlots = function(bag)
            local b = env.bags[bag]
            if not b then return 0, 0 end
            local used = 0
            for slot = 1, b.size do if b[slot] then used = used + 1 end end
            return b.size - used, b.family
        end,
        GetContainerItemInfo = function(bag, slot)
            local s = env.bags[bag] and env.bags[bag][slot]
            if not s then return nil end
            return { hyperlink = s.link, itemID = s.id, stackCount = s.count }
        end,
    }
    return env
end

-- Gives env a character bank with these tabs, as the client lists them;
-- env.asked is the bank type the list was last asked for.
local function bankTabs(env, tabs)
    env.Enum = env.Enum or {}
    env.Enum.BankType = { Character = 0, Guild = 1, Account = 2 }
    env.C_Bank = { FetchPurchasedBankTabIDs = function(kind)
        env.asked = kind
        return tabs
    end }
end

local function twoBags()
    return {
        [0] = { family = 0, size = 16, { link = LEATHER, id = 2318, count = 4 }, { id = 2318, count = 3 } },
        [2] = { family = 32, size = 12, [5] = { link = BEAR, id = 15234, count = 1 } },
    }
end

-- An environment with a C_Map: the player stands on map 1454 (a city, type
-- 4) inside zone 1411 (type 3) on continent map 1414 (type 2).
local function mapEnv()
    local env = { here = 1454, x = 0.25, y = 0.75, cont = 1 }
    env.C_Map = {
        GetBestMapForUnit = function(unit) return unit == "player" and env.here or nil end,
        GetPlayerMapPosition = function(map, unit)
            if map ~= env.here or unit ~= "player" or not env.x then return nil end
            return { GetXY = function() return env.x, env.y end }
        end,
        GetMapInfo = function(map)
            local infos = {
                [1454] = { mapType = 4, parentMapID = 1411 },
                [1411] = { mapType = 3, parentMapID = 1414 },
                [1414] = { mapType = 2, parentMapID = 0 },
            }
            return infos[map]
        end,
        GetWorldPosFromMapPos = function(map, pos)
            if map ~= env.here or type(pos) ~= "table" then return nil end
            return env.cont, {}
        end,
    }
    return env
end

return {
    ["reads: an environment with nothing in it never errors and knows nothing"] = function(t)
        local c = ns.make.client({})
        t.eq(c.money(), nil)
        t.eq(c.bags(), nil)
        t.eq(c.bagItems(), nil)
        t.eq(c.bankOpen(), nil)
        t.eq(c.bankItems(), nil)
        t.eq(c.position(), nil)
        t.eq(c.zone(), nil)
        t.eq(c.combatLockdown(), nil)
        c.watchBank()
        t.eq(c.bankOpen(), nil, "watching with no frame still knows nothing")
    end,

    ["money: present, missing, erroring, and never a made-up 0"] = function(t)
        local env = { GetMoney = function() return 123456 end }
        local c = ns.make.client(env)
        t.eq(c.money(), 123456)
        env.GetMoney = function() return 0 end
        t.eq(c.money(), 0, "a real 0 is 0")
        env.GetMoney = boom
        t.eq(c.money(), nil)
        env.GetMoney = function() return "lots" end
        t.eq(c.money(), nil, "not a count")
        env.GetMoney = nil
        t.eq(c.money(), nil)
    end,

    ["bags: one row per bag that is there, with its family"] = function(t)
        local env = bagEnv(twoBags())
        local c = ns.make.client(env)
        t.eq(c.bags(), {
            { bag = 0, free = 14, total = 16, family = 0 },
            { bag = 2, free = 11, total = 12, family = 32 },
        })
    end,

    ["bags: a client that gives no family leaves it out, not 0"] = function(t)
        local env = bagEnv(twoBags())
        env.C_Container.GetContainerNumFreeSlots = function() return 5 end
        local rows = ns.make.client(env).bags()
        t.eq(#rows, 2)
        t.eq(rows[1].free, 5)
        t.eq(rows[1].family, nil)
    end,

    ["bags: the bare globals serve when C_Container is not there"] = function(t)
        local env = bagEnv(twoBags())
        local group = env.C_Container
        env.C_Container = nil
        env.GetContainerNumSlots = group.GetContainerNumSlots
        env.GetContainerNumFreeSlots = group.GetContainerNumFreeSlots
        -- the older list form: texture, count, locked, quality, readable,
        -- lootable, link, filtered, noValue, id
        env.GetContainerItemInfo = function(bag, slot)
            local s = env.bags[bag] and env.bags[bag][slot]
            if not s then return nil end
            return "tex", s.count, false, 1, false, false, s.link, false, false, s.id
        end
        local c = ns.make.client(env)
        t.eq(#c.bags(), 2)
        t.eq(c.bagItems(), {
            { item = LEATHER, count = 4 }, { item = 2318, count = 3 }, { item = BEAR, count = 1 },
        })
    end,

    ["bags: NUM_BAG_SLOTS widens the range when the client has it"] = function(t)
        local bags = twoBags()
        bags[5] = { family = 0, size = 4 }
        local env = bagEnv(bags)
        t.eq(#ns.make.client(env).bags(), 2, "bag 5 is past the default range")
        env.NUM_BAG_SLOTS = 5
        t.eq(#ns.make.client(env).bags(), 3)
    end,

    ["bags: a missing or erroring call makes the whole reading unknown"] = function(t)
        local env = bagEnv(twoBags())
        local group = env.C_Container
        local c = ns.make.client(env)

        group.GetContainerNumFreeSlots = nil
        t.eq(c.bags(), nil, "no free-slot call")
        group.GetContainerNumFreeSlots = function(bag)
            if bag == 2 then boom() end
            return 1, 0
        end
        t.eq(c.bags(), nil, "one bag errors: no partial list")

        group.GetContainerNumSlots = boom
        t.eq(c.bags(), nil)
        t.eq(c.bagItems(), nil)
        group.GetContainerNumSlots = nil
        t.eq(c.bags(), nil)
        t.eq(c.bagItems(), nil)
    end,

    ["recipes: the open profession, every recipe, learned or not"] = function(t)
        local ui = {
            IsTradeSkillReady = function() return true end,
            IsDataSourceChanging = function() return false end,
            GetBaseProfessionInfo = function() return { professionID = 164, skillLevel = 104, maxSkillLevel = 150 } end,
            GetAllRecipeIDs = function() return { 11, 12 } end,
            GetRecipeInfo = function(id) return { name = "R" .. id, learned = id == 11 } end,
        }
        local c = ns.make.client({ C_TradeSkillUI = ui })
        t.eq(c.recipes(), { profession = 164, skill = 104, max = 150, recipes = {
            { id = 11, name = "R11", learned = true }, { id = 12, name = "R12", learned = false },
        } })
        ui.GetAllRecipeIDs = function() return {} end
        t.eq(c.recipes().recipes, {}, "settled and empty is known to be empty")
    end,

    ["recipes: unknown while the list is still arriving, or when a call fails"] = function(t)
        local ui = {
            IsTradeSkillReady = function() return true end,
            IsDataSourceChanging = function() return true end,
            GetBaseProfessionInfo = function() return { professionID = 164, skillLevel = 104, maxSkillLevel = 150 } end,
            GetAllRecipeIDs = function() return {} end,
            GetRecipeInfo = function() return { name = "R", learned = true } end,
        }
        local c = ns.make.client({ C_TradeSkillUI = ui })
        t.eq(c.recipes(), nil, "ready but still changing: not an empty profession")
        ui.IsDataSourceChanging = function() return false end
        ui.IsTradeSkillReady = function() return false end
        t.eq(c.recipes(), nil, "not ready")
        ui.IsTradeSkillReady = function() return true end
        ui.GetBaseProfessionInfo = function() return { professionID = 0, skillLevel = 0, maxSkillLevel = 0 } end
        t.eq(c.recipes(), nil, "no profession window")
        ui.GetBaseProfessionInfo = function() return { professionID = 164, skillLevel = 104, maxSkillLevel = 150 } end
        ui.GetAllRecipeIDs = function() return { 1, 2 } end
        ui.GetRecipeInfo = function(id) if id == 2 then boom() end return { name = "R", learned = true } end
        t.eq(c.recipes(), nil, "one recipe errors: no shorter list")
        ui.GetRecipeInfo = function() return { name = "R" } end
        t.eq(c.recipes(), nil, "learned not given")
        ui.IsDataSourceChanging = nil
        t.eq(c.recipes(), nil, "the client cannot say whether it is settled")
        t.eq(ns.make.client({}).recipes(), nil)
    end,

    ["recipes: the fake client gives what the test set, as a copy"] = function(t)
        local c = ns.make.fakeClient()
        t.eq(c.recipes(), nil)
        local rows = { { id = 5, name = "X", learned = true } }
        c.setRecipes({ profession = 164, skill = 1, max = 75, recipes = rows })
        local r = c.recipes()
        r.recipes[1].learned = false
        t.eq(c.recipes(), { profession = 164, skill = 1, max = 75, recipes = { { id = 5, name = "X", learned = true } } })
    end,

    ["spell: known, usable and out of power, each as the client says"] = function(t)
        local env = {
            IsPlayerSpell = function(id) return id == 5176 end,
            C_Spell = { IsSpellUsable = function(id) return false, id == 5176 end },
        }
        local c = ns.make.client(env)
        t.eq(c.spell(5176), { known = true, usable = false, noPower = true })
        t.eq(c.spell(1), { known = false, usable = false, noPower = false })
        t.eq(c.spell("Wrath"), nil, "by id only")
    end,

    ["spell: an answer the client hides or does not give stays unknown"] = function(t)
        local env = {
            IsPlayerSpell = function() return true end,
            C_Spell = { IsSpellUsable = function() return true, false end },
            issecretvalue = function(v) return v == false end,
        }
        local c = ns.make.client(env)
        t.eq(c.spell(7), { known = true, usable = true }, "the hidden one is not read as false")
        env.issecretvalue = boom
        t.eq(c.spell(7), {}, "cannot tell what is hidden: nothing is known")
        env.issecretvalue = nil
        env.C_Spell.IsSpellUsable = function() return 1 end
        t.eq(c.spell(7), { known = true }, "not a true / false")
        env.C_Spell.IsSpellUsable = boom
        env.IsPlayerSpell = nil
        t.eq(c.spell(7), {})
        t.eq(ns.make.client({}).spell(7), {})
    end,

    ["spell: the fake client gives what the test set"] = function(t)
        local c = ns.make.fakeClient()
        t.eq(c.spell(5176), {})
        c.setSpell(5176, { known = true, usable = false, noPower = true })
        t.eq(c.spell(5176), { known = true, usable = false, noPower = true })
        c.setSpell(5176, nil)
        t.eq(c.spell(5176), {})
    end,

    ["bag items: every stack, link first, empty slots skipped"] = function(t)
        local c = ns.make.client(bagEnv(twoBags()))
        t.eq(c.bagItems(), {
            { item = LEATHER, count = 4 }, { item = 2318, count = 3 }, { item = BEAR, count = 1 },
        })
        t.eq(ns.make.client(bagEnv({ [0] = { family = 0, size = 16 } })).bagItems(), {}, "empty bags are known to be empty")
    end,

    ["bag items: one slot that cannot be read makes the reading unknown"] = function(t)
        local env = bagEnv(twoBags())
        local group = env.C_Container
        local info = group.GetContainerItemInfo
        local c = ns.make.client(env)

        group.GetContainerItemInfo = function(bag, slot)
            if bag == 2 and slot == 5 then boom() end
            return info(bag, slot)
        end
        t.eq(c.bagItems(), nil, "an erroring slot is not an empty slot")

        group.GetContainerItemInfo = function(bag, slot)
            local r = info(bag, slot)
            if r then r.stackCount = nil end
            return r
        end
        t.eq(c.bagItems(), nil, "a stack with no count")

        group.GetContainerItemInfo = function(bag, slot)
            local r = info(bag, slot)
            if r then r.hyperlink, r.itemID = nil, nil end
            return r
        end
        t.eq(c.bagItems(), nil, "a stack that is no item")

        group.GetContainerItemInfo = nil
        t.eq(c.bagItems(), nil, "no item call")
    end,

    ["bank: open is known from the bank events once watched"] = function(t)
        local env = bagEnv()
        local c = ns.make.client(env)
        t.eq(c.bankOpen(), nil)
        t.eq(#env.frames, 0, "asking does not start listening")
        c.watchBank()
        c.watchBank()
        t.eq(#env.frames, 1)
        t.eq(env.frames[1].events, { BANKFRAME_OPENED = true, BANKFRAME_CLOSED = true })
        t.eq(c.bankOpen(), nil, "no event seen yet")
        env.fire("BANKFRAME_OPENED")
        t.eq(c.bankOpen(), true)
        env.fire("BANKFRAME_CLOSED")
        t.eq(c.bankOpen(), false)
    end,

    ["bank: before any event the bank frame answers, when the client has one"] = function(t)
        local env = bagEnv()
        local shown = true
        env.BankFrame = { IsShown = function() return shown end }
        local c = ns.make.client(env)
        t.eq(c.bankOpen(), true)
        shown = false
        t.eq(c.bankOpen(), false)
        env.BankFrame = { IsShown = boom }
        t.eq(c.bankOpen(), nil)
        env.BankFrame = {}
        t.eq(c.bankOpen(), nil)
        env.BankFrame = { IsShown = function() return false end }
        c.watchBank()
        env.fire("BANKFRAME_OPENED")
        t.eq(c.bankOpen(), true, "an event beats the frame")
    end,

    ["bank: contents only while the bank is open"] = function(t)
        local env = bagEnv({
            [0] = { family = 0, size = 16, { id = 2318, count = 1 } },
            [-1] = { family = 0, size = 24, { id = 9, count = 9 } },
            [5] = { family = 0, size = 8, { id = 8, count = 8 } },
            [6] = { family = 0, size = 24, { link = LEATHER, id = 2318, count = 20 }, [3] = { id = 2589, count = 7 } },
            [7] = { family = 0, size = 8, { id = 2589, count = 2 } },
            [15] = { family = 0, size = 8, { id = 7, count = 7 } },
        })
        bankTabs(env, { 6, 7 })
        local c = ns.make.client(env)
        c.watchBank()
        t.eq(c.bankItems(), nil, "not known to be open")
        env.fire("BANKFRAME_OPENED")
        t.eq(c.bankItems(), { { item = LEATHER, count = 20 }, { item = 2589, count = 7 }, { item = 2589, count = 2 } },
            "the character's tabs; not the backpack, the keyring (-1), the reagent bag (5) or an account tab (15)")
        t.eq(env.asked, 0, "asked for the character bank's tabs")
        env.fire("BANKFRAME_CLOSED")
        t.eq(c.bankItems(), nil, "closed: nil, not an empty bank")
    end,

    ["bank: a client that will not list its tabs leaves the bank unknown"] = function(t)
        local env = bagEnv({ [6] = { family = 0, size = 4, { id = 1, count = 1 } } })
        env.BankFrame = { IsShown = function() return true end }
        t.eq(ns.make.client(env).bankItems(), nil, "no C_Bank: no guessed container numbers")
        bankTabs(env, { 6 })
        t.eq(ns.make.client(env).bankItems(), { { item = 1, count = 1 } })
        env.C_Bank.FetchPurchasedBankTabIDs = boom
        t.eq(ns.make.client(env).bankItems(), nil, "the list errored")
        env.C_Bank.FetchPurchasedBankTabIDs = function() return { 6, "x" } end
        t.eq(ns.make.client(env).bankItems(), nil, "a list that is not all numbers")
        env.C_Bank.FetchPurchasedBankTabIDs = function() return {} end
        t.eq(ns.make.client(env).bankItems(), {}, "no tab bought: an empty bank, and known")
        env.Enum.BankType = nil
        t.eq(ns.make.client(env).bankItems(), nil, "no name for the character bank")
    end,

    ["bank: an erroring container makes the bank unknown, not smaller"] = function(t)
        local env = bagEnv({ [6] = { family = 0, size = 4, { id = 1, count = 1 } } })
        env.BankFrame = { IsShown = function() return true end }
        bankTabs(env, { 6, 7 })
        local slots = env.C_Container.GetContainerNumSlots
        env.C_Container.GetContainerNumSlots = function(bag)
            if bag == 7 then boom() end
            return slots(bag)
        end
        t.eq(ns.make.client(env).bankItems(), nil)
    end,

    ["position: the map and where the player is on it"] = function(t)
        local env = mapEnv()
        local c = ns.make.client(env)
        t.eq(c.position(), { map = 1454, x = 0.25, y = 0.75 })
        env.C_Map.GetPlayerMapPosition = function() return { x = 0.5, y = 0.125 } end
        t.eq(c.position(), { map = 1454, x = 0.5, y = 0.125 }, "a position with plain x and y")
    end,

    ["position: unknown when any part is missing or errors"] = function(t)
        local env = mapEnv()
        local c = ns.make.client(env)
        env.x = nil
        t.eq(c.position(), nil, "the client gives no position here")
        env.x = 0.25
        env.C_Map.GetPlayerMapPosition = function() return { GetXY = function() return 0 / 0, 0.5 end } end
        t.eq(c.position(), nil, "not a number")
        env.C_Map.GetPlayerMapPosition = boom
        t.eq(c.position(), nil)
        env.C_Map.GetPlayerMapPosition = nil
        t.eq(c.position(), nil)
        env.C_Map.GetBestMapForUnit = boom
        t.eq(c.position(), nil)
        env.C_Map = nil
        t.eq(c.position(), nil)
    end,

    ["zone: continent and zone, the zone found through the map's parents"] = function(t)
        local env = mapEnv()
        local c = ns.make.client(env)
        t.eq(c.zone(), { cont = 1, zone = 1411 }, "a city map belongs to its zone")
        env.here = 1411
        t.eq(c.zone(), { cont = 1, zone = 1411 })
        env.Enum = { UIMapType = { Zone = 4 } }
        env.here = 1454
        t.eq(c.zone(), { cont = 1, zone = 1454 }, "the client's own number for a zone map is used")
    end,

    ["zone: each half stays unknown on its own"] = function(t)
        local env = mapEnv()
        local c = ns.make.client(env)
        local N = ns.Nav

        env.x = nil
        t.eq(c.zone(), { zone = 1411 }, "no position: no continent")
        t.eq(N.ArrowState(c.zone(), { cont = 0, zone = 1411 }), "zone", "an unknown continent is not 'away'")
        env.x = 0.25

        env.C_Map.GetWorldPosFromMapPos = boom
        t.eq(c.zone(), { zone = 1411 })
        env.C_Map.GetWorldPosFromMapPos = nil
        t.eq(c.zone(), { zone = 1411 })

        env.C_Map.GetWorldPosFromMapPos = function() return 1, {} end
        env.C_Map.GetMapInfo = boom
        t.eq(c.zone(), { cont = 1 })
        env.C_Map.GetMapInfo = nil
        t.eq(c.zone(), { cont = 1 })
        env.C_Map.GetMapInfo = function() return { mapType = 6, parentMapID = 0 } end
        t.eq(c.zone(), { cont = 1 }, "no parent that is a zone")

        env.C_Map.GetWorldPosFromMapPos = nil
        t.eq(c.zone(), nil, "neither known")
        env.C_Map.GetBestMapForUnit = nil
        t.eq(c.zone(), nil)
    end,

    ["zone: feeds the arrow's state"] = function(t)
        local N = ns.Nav
        local c = ns.make.client(mapEnv())
        t.eq(N.ArrowState(c.zone(), { cont = 1, zone = 1411 }), "zone")
        t.eq(N.ArrowState(c.zone(), { cont = 1, zone = 1412 }), "away")
        t.eq(N.ArrowState(c.zone(), { cont = 0, zone = 1411 }), "away")
        local fake = ns.make.fakeClient()
        t.eq(fake.zone(), nil)
        fake.setZone(0, 1429)
        t.eq(N.ArrowState(fake.zone(), { cont = 0, zone = 1429 }), "zone")
        t.eq(N.ArrowState(fake.zone(), { cont = 1, zone = 1411 }), "away")
    end,

    ["combat lock: true, false, and unknown when the client has no such call"] = function(t)
        local env = { InCombatLockdown = function() return true end, UnitAffectingCombat = function() return true end }
        local c = ns.make.client(env)
        t.eq(c.combatLockdown(), true)
        env.InCombatLockdown = function() return nil end
        t.eq(c.combatLockdown(), false)
        env.InCombatLockdown = boom
        t.eq(c.combatLockdown(), nil)
        env.InCombatLockdown = nil
        t.eq(c.combatLockdown(), nil, "no fallback to 'fighting'")
        t.eq(c.inCombat(), true, "inCombat is the one that falls back")
    end,

    ["fake: every read starts unknown and gives back what was set"] = function(t)
        local c = ns.make.fakeClient()
        t.eq(c.money(), nil)
        t.eq(c.bags(), nil)
        t.eq(c.bagItems(), nil)
        t.eq(c.bankOpen(), false)
        t.eq(c.bankItems(), nil)
        t.eq(c.position(), nil)
        t.eq(c.zone(), nil)

        c.setMoney(250)
        t.eq(c.money(), 250)
        local rows = { { free = 3, total = 16, family = 0 } }
        c.setBags(rows)
        rows[1].free = 99
        t.eq(c.bags(), { { free = 3, total = 16, family = 0 } }, "a copy went in")
        c.bags()[1].free = 77
        t.eq(c.bags()[1].free, 3, "a copy comes out")
        c.setBagItems({ { item = 2318, count = 4 } })
        t.eq(c.bagItems(), { { item = 2318, count = 4 } })
        c.setPosition(1411, 0.5, 0.25)
        t.eq(c.position(), { map = 1411, x = 0.5, y = 0.25 })
        c.setZone(1, 1411)
        t.eq(c.zone(), { cont = 1, zone = 1411 })
        c.setZone(nil, 1411)
        t.eq(c.zone(), { zone = 1411 })

        c.setMoney(nil); c.setBags(nil); c.setBagItems(nil); c.setPosition(nil); c.setZone(nil, nil)
        t.eq(c.money(), nil)
        t.eq(c.bags(), nil)
        t.eq(c.bagItems(), nil)
        t.eq(c.position(), nil)
        t.eq(c.zone(), nil)
    end,

    ["fake: the bank gives its contents only while open, and fires the events"] = function(t)
        local c = ns.make.fakeClient()
        local seen = {}
        c.listen("BANKFRAME_OPENED", function() seen[#seen + 1] = "open" end)
        c.listen("BANKFRAME_CLOSED", function() seen[#seen + 1] = "closed" end)
        c.setBank({ { item = 2589, count = 40 } })
        t.eq(c.bankItems(), nil)
        c.setBankOpen(true)
        c.setBankOpen(true)
        t.eq(c.bankItems(), { { item = 2589, count = 40 } })
        c.setBankOpen(false)
        t.eq(c.bankItems(), nil)
        t.eq(seen, { "open", "closed" })
        c.setBankOpen(nil)
        t.eq(c.bankOpen(), nil)
        t.eq(#seen, 2, "unknown fires nothing")
    end,

    ["fake: the combat lock follows combat until it is set"] = function(t)
        local c = ns.make.fakeClient()
        t.eq(c.combatLockdown(), false)
        c.setCombat(true)
        t.eq(c.combatLockdown(), true)
        c.setLockdown(false)
        t.eq(c.combatLockdown(), false)
        t.eq(c.inCombat(), true)
        c.setLockdown(nil)
        t.eq(c.combatLockdown(), nil)
    end,

    ["adapter: feeds Resources.Take end to end from the fake client"] = function(t)
        local Resources = ns.Resources
        local c = ns.make.fakeClient({ now = 500 })
        c.setMoney(12345)
        c.setBags({
            { bag = 0, free = 4, total = 16, family = 0 },
            { bag = 1, free = 2, total = 12, family = 0 },
            { bag = 2, free = 10, total = 12, family = 32 },
            { bag = 3, free = 5, total = 8 },
        })
        c.setBagItems({ { item = LEATHER, count = 4 }, { item = 2318, count = 3 }, { item = BEAR, count = 1 } })
        c.setBank({ { item = "item:2589", count = 40 } })
        local read = ns.make.resourceRead(c)

        local snap = Resources.Take(read)
        t.eq(snap.money, 12345)
        t.eq(snap.bags, { [2318] = 7, ["15234:588"] = 1 }, "a link and an ID of one item are one key")
        t.eq(snap.slots, { [0] = { free = 6, total = 28 }, [32] = { free = 10, total = 12 },
            unknown = { free = 5, total = 8 } })
        t.eq(snap.bank, nil)
        t.eq(snap.bankKnown, false, "the bank has not been seen")
        t.eq(snap.bankSeenAt, nil)
        t.eq(snap.takenAt, 500)

        c.setBankOpen(true)
        c.advance(10)
        snap = Resources.Take(read)
        t.eq(snap.bank, { [2589] = 40 })
        t.eq(snap.bankKnown, true)
        t.eq(snap.bankSeenAt, 510)

        c.setBankOpen(false)
        c.setBank({})
        c.advance(90)
        snap = Resources.Take(read)
        t.eq(snap.bank, { [2589] = 40 }, "closed: what was last seen")
        t.eq(snap.bankSeenAt, 510, "and when")
        t.eq(snap.takenAt, 600)

        local grants = Resources.Resolve(snap, {
            { owner = "train", kind = "money", amount = 10000 },
            { owner = "craft", kind = "item", key = 2318, amount = 5 },
            { owner = "cloth", kind = "item", key = 2589, amount = 50, bank = true },
        })
        t.eq(grants:For("train")[1].got, 10000)
        t.eq(grants:For("craft")[1].got, 5)
        t.eq(grants:For("cloth")[1].got, 40)
    end,

    ["adapter: unknown stays unknown all the way into the snapshot"] = function(t)
        local Resources = ns.Resources
        local c = ns.make.fakeClient({ now = 7 })
        local snap = Resources.Take(ns.make.resourceRead(c))
        t.eq(snap.money, nil)
        t.eq(snap.bags, nil)
        t.eq(snap.slots, nil)
        t.eq(snap.bank, nil)
        t.eq(snap.bankKnown, false)
        t.eq(snap.takenAt, 7)

        local grants = Resources.Resolve(snap, { { owner = "train", kind = "money", amount = 100 } })
        local g = grants:For("train")[1]
        t.eq(g.unknown, "money")
        t.eq(g.short, nil, "neither enough nor not enough")
    end,

    ["adapter: a stack with no key makes the items unknown, not fewer"] = function(t)
        local c = ns.make.fakeClient()
        c.setBagItems({ { item = 2318, count = 4 }, { item = "not an item", count = 1 } })
        local read = ns.make.resourceRead(c)
        t.eq(read.items(), nil)
        c.setBagItems({ { item = 2318, count = 4 }, { item = 2318 } })
        t.eq(read.items(), nil, "a stack with no count")
        c.setBagItems({})
        t.eq(read.items(), {}, "empty bags are known")
    end,

    ["adapter: the bank is kept from the last full reading"] = function(t)
        local c = ns.make.fakeClient({ now = 100 })
        local read = ns.make.resourceRead(c)
        t.eq(read.seeBank(), false, "closed")
        local bank, at = read.bank()
        t.eq(bank, nil)
        t.eq(at, nil)

        c.setBank({ { item = 2589, count = 40 } })
        c.setBankOpen(true)
        t.eq(read.seeBank(), true)
        c.advance(5)
        c.setBank({ { item = 2589, count = 40 }, { item = "junk", count = 1 } })
        t.eq(read.seeBank(), false, "open but not readable in full")
        bank, at = read.bank()
        t.eq(bank, { [2589] = 40 }, "the earlier full reading stands")
        t.eq(at, 100)

        c.setBank({ { item = 2589, count = 20 } })
        bank, at = read.bank()
        t.eq(bank, { [2589] = 20 })
        t.eq(at, 105)

        c.setBankOpen(nil)
        c.setBank({})
        bank = read.bank()
        t.eq(bank, { [2589] = 20 }, "open or not is unknown: nothing new is read")
    end,

    ["adapter: the caller's own key function, and a client with no reads"] = function(t)
        local c = ns.make.fakeClient()
        c.setBagItems({ { item = 2318, count = 4 }, { item = 2319, count = 2 } })
        local read = ns.make.resourceRead(c, function(item) return "i" .. item end)
        t.eq(read.items(), { i2318 = 4, i2319 = 2 })

        local bare = ns.make.resourceRead({})
        t.eq(bare.money(), nil)
        t.eq(bare.bags(), nil)
        t.eq(bare.items(), nil)
        t.eq(bare.now(), nil)
        t.eq(bare.seeBank(), false)
        local snap = ns.Resources.Take(ns.make.resourceRead(nil))
        t.eq(snap.money, nil)
        t.eq(snap.bankKnown, false)
    end,

    ["adapter: runs over the real client boundary too"] = function(t)
        local env = bagEnv(twoBags())
        env.bags[6] = { family = 0, size = 4, { id = 2589, count = 9 } }
        bankTabs(env, { 6 })
        env.GetMoney = function() return 42 end
        env.GetTime = function() return 3 end
        local read = ns.make.resourceRead(ns.make.client(env))
        t.eq(env.frames[1].events, { BANKFRAME_OPENED = true, BANKFRAME_CLOSED = true }, "the adapter starts the bank watch")
        local snap = ns.Resources.Take(read)
        t.eq(snap.money, 42)
        t.eq(snap.bags, { [2318] = 7, ["15234:588"] = 1 })
        t.eq(snap.slots, { [0] = { free = 14, total = 16 }, [32] = { free = 11, total = 12 } })
        t.eq(snap.bankKnown, false)
        env.fire("BANKFRAME_OPENED")
        snap = ns.Resources.Take(read)
        t.eq(snap.bank, { [2589] = 9 })
        t.eq(snap.bankSeenAt, 3)
    end,
}
