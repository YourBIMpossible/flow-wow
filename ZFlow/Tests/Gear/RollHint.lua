local _, ns = ...

-- Tests for ZFlow/Gear/RollHint.lua (S21): the hint on a loot roll. It says
-- upgrade, no upgrade or unknown, and never rolls.
--
-- The fake client has the loot-roll hook (F4); the tests replace it with a
-- hand-made one so each test controls its own rolls, in the same shape:
--   c.onLootRoll(fn) -> cancel     fn(rollId, link, show); show(text, r, g, b)
-- c.roll(rollId, link) plays the game offering a roll and returns what was shown.

local R = ns.GearRollHint
local tests = {}

local STA = "ITEM_MOD_STAMINA_SHORT"
local HELM, BETTER, WORSE, PLATE, POTION, UNREAD = "item:1", "item:2", "item:3", "item:4", "item:5", "item:6"

local function packs()
    return { DRUID = {
        weights = {
            dps = { evidence = "first guess", values = { [STA] = 1 } },
            tank = { evidence = "first guess", values = { ITEM_MOD_STRENGTH_SHORT = 1 } },
        },
        proficiency = { evidence = "first guess", [4] = { [2] = true } },
    } }
end

local function client(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    c.setClass("DRUID")
    c.setItem(HELM, { kind = "INVTYPE_HEAD", stats = { [STA] = 4 } })
    c.setItem(BETTER, { kind = "INVTYPE_HEAD", stats = { [STA] = 9 } })
    c.setItem(WORSE, { kind = "INVTYPE_HEAD", stats = { [STA] = 1 } })
    c.setItem(PLATE, { kind = "INVTYPE_HEAD", stats = { [STA] = 40 } })
    c.setItem(POTION, { stats = {} })
    c.setItem(UNREAD, { kind = "INVTYPE_HEAD", stats = { [STA] = 9 } })
    c.setWorn(1, HELM)
    c.unmet = { [HELM] = {}, [BETTER] = {}, [WORSE] = {}, [PLATE] = { "Plate" }, [POTION] = {} }
    local gear = c.gear
    c.gear = function(link)
        local g = gear(link)
        if c.unmet[link] ~= nil then g.unmet = c.unmet[link] end
        return g
    end
    c.hooks, c.cancelled = {}, 0
    if opts.hook ~= false then
        c.onLootRoll = function(fn)
            c.hooks[#c.hooks + 1] = fn
            return function()
                c.cancelled = c.cancelled + 1
                for i = #c.hooks, 1, -1 do
                    if c.hooks[i] == fn then table.remove(c.hooks, i) end
                end
            end
        end
    else
        c.onLootRoll = nil   -- a client that offers no roll hook
    end
    c.roll = function(rollId, link)
        local shown = {}
        for i = 1, #c.hooks do
            c.hooks[i](rollId, link, function(text, r, g, b)
                shown[#shown + 1] = { text = text, r = r, g = g, b = b }
            end)
        end
        return shown
    end
    return c
end

local function start(c)
    local k = ns.Kernel({}, c)
    local api = R.Declare(k, packs())
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return k, api
end

-- Hint -----------------------------------------------------------------------

tests["roll hint: an upgrade says so, and for which role"] = function(t)
    local hint = R.Hint(client(), packs(), BETTER)
    t.eq(hint.text, "Upgrade")
    t.eq(hint.tone, "good")
    t.eq(hint.lines, { "Upgrade for your head piece (+5, dps)" })
end

tests["roll hint: the same or worse is no upgrade"] = function(t)
    local hint = R.Hint(client(), packs(), WORSE)
    t.eq(hint.text, "No upgrade")
    t.eq(hint.tone, "none")
    hint = R.Hint(client(), packs(), HELM)
    t.eq(hint.text, "No upgrade", "the same as what you wear")
end

tests["roll hint G15: a weapon that is no upgrade, with its speed read, is still no upgrade"] = function(t)
    local WORN_STAFF, WORSE_STAFF = "item:7", "item:8"
    local c = client()
    c.setItem(WORN_STAFF, { kind = "INVTYPE_2HWEAPON", stats = { [STA] = 4 } })
    c.setItem(WORSE_STAFF, { kind = "INVTYPE_2HWEAPON", stats = { [STA] = 1 } })
    c.setWorn(16, WORN_STAFF)
    c.setWorn(17, false)   -- the off hand is read and empty, so the verdict is a real one
    c.unmet[WORSE_STAFF] = {}
    local gear = c.gear
    c.gear = function(link)
        local g = gear(link)
        if link == WORSE_STAFF then g.speed = 3.6 end
        return g
    end
    local hint = R.Hint(c, packs(), WORSE_STAFF)
    t.eq(hint.text, "No upgrade", "the speed line is not a no-verdict")
    local speedSeen = false
    for i = 1, #hint.lines do
        if string.find(hint.lines[i], "^Speed 3%.60 %(slow%)") then speedSeen = true end
    end
    t.eq(speedSeen, true, "the speed line is among the lines behind the word")
end

tests["roll hint: gear you cannot use is no upgrade, and says why"] = function(t)
    local hint = R.Hint(client(), packs(), PLATE)
    t.eq(hint.text, "No upgrade")
    t.eq(hint.lines, { "Can't use: " .. ns.GearUsable.REASON.unmet .. ": Plate" })
end

tests["roll hint: no verdict is unknown, never an upgrade and never a no"] = function(t)
    local hint = R.Hint(client(), packs(), UNREAD)
    t.eq(hint.text, "Unknown")
    t.eq(hint.tone, "none")
    t.eq(#hint.lines, 1)
    t.ok(hint.lines[1]:find("^No verdict: "), hint.lines[1])
    local c = client()
    c.setWorn(1, nil)
    t.eq(R.Hint(c, packs(), BETTER).text, "Unknown", "what you wear was not read")
end

tests["roll hint: what is not gear gets no hint"] = function(t)
    t.eq(R.Hint(client(), packs(), POTION), nil)
    t.eq(R.Hint(client(), packs(), "item:999"), nil)
    t.eq(R.Hint(client(), packs(), nil), nil)
    t.eq(R.Hint(nil, packs(), BETTER), nil)
end

-- Advice (S21, lead section 275): Need or Greed -------------------------------

-- Every read the verdict needs: class, level, the worn head, both hands
-- read empty, the weapon skills.
local function adviceClient()
    local c = client()
    c.setLevel(10)
    c.setWorn(16, false)
    c.setWorn(17, false)
    c.setWeaponSkills({})
    return c
end

tests["roll advice: an upgrade for the chosen role is Need, with that role"] = function(t)
    local a = R.Advice(adviceClient(), packs(), BETTER, "dps")
    t.eq(a and a.word, "need")
    t.eq(a and a.text, "Need: upgrade for dps")
    t.eq(a and a.value, "Need +5")
end

tests["roll advice: usable but no upgrade for the chosen role is Greed"] = function(t)
    local a = R.Advice(adviceClient(), packs(), BETTER, "tank")
    t.eq(a and a.text, "Greed", "the same for a tank")
    t.eq(a and a.word, "greed")
    a = R.Advice(adviceClient(), packs(), WORSE, "dps")
    t.eq(a and a.text, "Greed")
    t.eq(a and a.value, "Greed")
end

tests["roll advice: no role chosen, an upgrade for any role is Need for that role"] = function(t)
    local a = R.Advice(adviceClient(), packs(), BETTER, nil)
    t.eq(a and a.text, "Need: upgrade for dps")
    a = R.Advice(adviceClient(), packs(), BETTER, "healer")
    t.eq(a and a.text, "Need: upgrade for dps", "a role the pack has no weights for counts as none")
end

tests["roll advice: gear you cannot use is Greed (can't use)"] = function(t)
    local a = R.Advice(adviceClient(), packs(), PLATE, "dps")
    t.eq(a and a.text, "Greed (can't use)")
    t.eq(a and a.word, "greed")
end

tests["roll advice: no verdict gives no advice, never a guess"] = function(t)
    t.eq(R.Advice(adviceClient(), packs(), UNREAD, "dps"), nil, "the game's marks not read")
    local c = adviceClient()
    c.setWorn(1, nil)
    t.eq(R.Advice(c, packs(), BETTER, "dps"), nil, "what you wear was not read")
    t.eq(R.Advice(adviceClient(), packs(), POTION, "dps"), nil, "not gear")
    t.eq(R.Advice(adviceClient(), packs(), nil, "dps"), nil)
    t.eq(R.Advice(nil, packs(), BETTER, "dps"), nil)
end

tests["roll advice: the hint words on the roll frame are unchanged"] = function(t)
    local c = adviceClient()
    t.eq(R.Hint(c, packs(), BETTER).text, "Upgrade")
    t.eq(R.Hint(c, packs(), WORSE).text, "No upgrade")
end

-- The module ------------------------------------------------------------------

tests["roll hint: a roll on an upgrade shows the hint on that roll"] = function(t)
    local c = client()
    local k = start(c)
    t.eq(k:ModuleState(R.NAME), "started")
    local shown = c.roll(7, BETTER)
    t.eq(#shown, 1)
    t.eq(shown[1].text, "Upgrade")
    t.eq({ shown[1].r, shown[1].g, shown[1].b }, ns.GearTooltipModule.COLOUR.good)
    shown = c.roll(8, WORSE)
    t.eq(shown[1].text, "No upgrade")
    shown = c.roll(9, UNREAD)
    t.eq(shown[1].text, "Unknown")
end

tests["roll hint: a roll on something that is not gear shows nothing"] = function(t)
    local c = client()
    start(c)
    t.eq(c.roll(7, POTION), {})
    t.eq(c.roll(8, nil), {})
end

tests["roll hint: the setting is on by default, and off shows nothing"] = function(t)
    local c = client()
    local k = start(c)
    t.eq(R.SETTING, "gear.rollHint")
    t.eq(k.settings:get(R.SETTING), true)
    t.eq(k.settings:set(R.SETTING, false), true)
    t.eq(c.roll(7, BETTER), {})
    t.eq(k.settings:set(R.SETTING, true), true)
    t.eq(#c.roll(7, BETTER), 1)
end

tests["roll hint: on a client with no roll hook it starts, hooks nothing and says so"] = function(t)
    local c = client({ hook = false })
    local k, api = start(c)
    t.eq(k:ModuleState(R.NAME), "started")
    t.eq(api.hooked(), false)
    local with = client()
    local _, apiWith = start(with)
    t.eq(apiWith.hooked(), true)
end

tests["roll hint: an error while working a hint out shows nothing and is counted"] = function(t)
    local c = client()
    local k, api = start(c)
    c.gear = function() error("the read broke") end
    t.eq(c.roll(7, BETTER), {})
    t.eq(api.errors(), 1)
    t.eq(k:ModuleState(R.NAME), "started")
    t.eq(k.problems:count("gear"), 1)
end

tests["roll hint: switched off by the kernel, the hook is given back"] = function(t)
    local c = client()
    local k = start(c)
    t.eq(k:SwitchOff(R.NAME, "test"), true)
    t.eq(c.cancelled, 1)
    t.eq(c.roll(7, BETTER), {})
end

tests["roll hint: it never rolls, passes or confirms for you"] = function(t)
    local c = client()
    local calls = 0
    for _, name in ipairs({ "RollOnLoot", "ConfirmLootRoll", "ConfirmLootSlot", "LootSlot", "EquipItemByName" }) do
        c[name] = function() calls = calls + 1 end
    end
    start(c)
    c.roll(7, BETTER)
    c.roll(8, WORSE)
    c.roll(9, PLATE)
    t.eq(calls, 0)
end

tests["roll advice: Greed says what it sells for, when the price is read (S21 fate)"] = function(t)
    local c = adviceClient()
    c.setItemInfo({ [3] = { sellPrice = 2540 }, [4] = { sellPrice = 0 } })
    local a = R.Advice(c, packs(), WORSE, "dps")
    t.eq(a and a.text, "Greed: sells for 25s 40c")
    t.eq(a and a.sells, 2540)
    t.eq(a and a.value, "Greed", "the roll frame word is unchanged")
    a = R.Advice(c, packs(), PLATE, "dps")
    t.eq(a and a.text, "Greed (can't use)", "nothing to a vendor: no price")
    a = R.Advice(c, packs(), BETTER, "dps")
    t.eq(a and a.sells, nil, "Need never carries a price")
end

return tests
