local _, ns = ...

-- Tests for ZFlow/Gear/RollHint.lua (S21): the hint on a loot roll. It says
-- upgrade, no upgrade or unknown, and never rolls.
--
-- The loot-roll hook is not in Core/Client.lua yet (a CLIENT NEED). The fake
-- client is given it by hand here, in the shape asked for:
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

return tests
