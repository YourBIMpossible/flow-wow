local _, ns = ...

-- Tests for parity row E-03 (ZFlow/Gear/BagBadge.lua): a gear item in the
-- bags carries, for each role, its letter with a mark: better than what is
-- worn, worse, or the same. A role whose answer is not known gets nothing,
-- never "same". Look only. Fake client and made-up items, as
-- Tests/Gear/BagBadge.lua; not tested in game.
--
-- The numbers (worn helm: 2 Stamina, 2 Strength):
--   dps  (Strength 1, Stamina 0.35): worn 2.7
--   tank (Stamina 1, Strength 0.6):  worn 3.2
--   STRONG (10 Strength): dps 10, tank 6: better for both
--   WEAK   (1 Stamina):   dps 0.35, tank 1: worse for both
--   SHARP  (4 Strength):  dps 4 (better), tank 2.4 (worse)
--   TWIN   (2 Stamina, 2 Strength): the same for both
--
-- Red before the code: BB.Way and BB.Piece are absent and Marks badges
-- upgrades only, with a bare letter.

local tests = {}
local function BB() return ns.GearBagBadge end

local STA, STR = "ITEM_MOD_STAMINA_SHORT", "ITEM_MOD_STRENGTH_SHORT"
local WORN, STRONG, WEAK, SHARP, TWIN, PLATE = "item:21", "item:22", "item:23", "item:24", "item:25", "item:26"

local function packs()
    return { WARRIOR = {
        weights = {
            dps = { evidence = "first guess", values = { [STR] = 1, [STA] = 0.35 } },
            tank = { evidence = "first guess", values = { [STA] = 1, [STR] = 0.6 } },
        },
        proficiency = { evidence = "first guess", [4] = { [0] = true, [1] = true, [2] = true, [3] = true } },
    } }
end

local function helm(stats, unmet)
    return { kind = "INVTYPE_HEAD", stats = stats, classID = 4, subclassID = 3, minLevel = 1, unmet = unmet or {} }
end

-- worn: false leaves the head slot unread.
local function client(worn)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    c.setClass("WARRIOR")
    c.setLevel(10)
    c.setDualWield(false)
    c.setItem(WORN, helm({ [STA] = 2, [STR] = 2 }))
    c.setItem(STRONG, helm({ [STR] = 10 }))
    c.setItem(WEAK, helm({ [STA] = 1 }))
    c.setItem(SHARP, helm({ [STR] = 4 }))
    c.setItem(TWIN, helm({ [STA] = 2, [STR] = 2 }))
    c.setItem(PLATE, helm({ [STR] = 30 }, { "Plate" }))
    if worn ~= false then c.setWorn(1, WORN) end
    return c
end

local function bags(...)
    local out = {}
    for i, link in ipairs({ ... }) do out[i] = { bag = 0, slot = i, item = link, count = 1 } end
    return out
end

local function has(t)
    if type(BB().Way) == "function" and type(BB().Piece) == "function" then return true end
    t.ok(false, "GearBagBadge.Way and GearBagBadge.Piece")
    return false
end

tests["bag arrows: up, down or same from the scorer's answer; not known is nothing"] = function(t)
    if not has(t) then return end
    t.eq(BB().Way({ verdict = "upgrade", delta = 3 }), "up")
    t.eq(BB().Way({ verdict = "worse", delta = -3 }), "down")
    t.eq(BB().Way({ verdict = "same", delta = 0 }), "same")
    t.eq(BB().Way({ verdict = "upgrade", delta = 0.01 }), "same", "a gain that prints as 0.0 is the same")
    t.eq(BB().Way({ verdict = "worse", delta = -0.01 }), "same")
    t.eq(BB().Way({ verdict = "none", reason = "what you wear in that slot is not known" }), nil)
    t.eq(BB().Way({ verdict = "upgrade" }), nil, "no number: not known")
    t.eq(BB().Way({ verdict = "upgrade", delta = math.huge }), nil)
    t.eq(BB().Way({ delta = 3 }), nil)
    t.eq(BB().Way(nil), nil)
end

tests["bag arrows: a piece is the role's letter, its mark and its colour"] = function(t)
    if not has(t) then return end
    t.eq(BB().SIGN, { up = "+", down = "-", same = "=" })
    t.eq(BB().Piece("dps", "up"), "|c" .. BB().COLOUR.up .. "D+|r")
    t.eq(BB().Piece("tank", "down"), "|c" .. BB().COLOUR.down .. "T-|r")
    t.eq(BB().Piece("heal", "same"), "|c" .. BB().COLOUR.same .. "H=|r")
    t.eq(BB().Piece("other", "up"), "|c" .. BB().COLOUR.up .. "O+|r", "a role with no letter: its first")
    t.eq(BB().Piece("dps", nil), "", "not known: nothing")
    t.eq(BB().Piece("dps", "sideways"), "")
    for _, way in ipairs({ "up", "down", "same" }) do
        t.ok(type(BB().COLOUR[way]) == "string" and #BB().COLOUR[way] == 8, way .. " colour")
    end
    t.ok(BB().COLOUR.up ~= BB().COLOUR.down and BB().COLOUR.down ~= BB().COLOUR.same)
end

tests["bag arrows: no role chosen - every role, each with its own mark"] = function(t)
    if not has(t) then return end
    local c = client()
    c.setBagItems(bags(STRONG, WEAK, SHARP, TWIN))
    local P = BB().Piece
    t.eq(BB().Marks(c, packs(), ""), {
        { bag = 0, slot = 1, text = P("dps", "up") .. P("tank", "up") },
        { bag = 0, slot = 2, text = P("dps", "down") .. P("tank", "down") },
        { bag = 0, slot = 3, text = P("dps", "up") .. P("tank", "down") },
        { bag = 0, slot = 4, text = P("dps", "same") .. P("tank", "same") },
    })
end

tests["bag arrows: a chosen role shows only its own"] = function(t)
    if not has(t) then return end
    local c = client()
    c.setBagItems(bags(SHARP))
    t.eq(BB().Marks(c, packs(), "tank"), { { bag = 0, slot = 1, text = BB().Piece("tank", "down") } })
    t.eq(BB().Marks(c, packs(), "dps"), { { bag = 0, slot = 1, text = BB().Piece("dps", "up") } })
end

tests["bag arrows: nothing when it is not known - unread item, unread worn slot, no weights"] = function(t)
    if not has(t) then return end
    local c = client()
    c.setBagItems(bags("item:99", PLATE))
    t.eq(BB().Marks(c, packs(), ""), {}, "an item not read, and one you cannot use")
    local bare = client(false)
    bare.setBagItems(bags(STRONG, TWIN))
    t.eq(BB().Marks(bare, packs(), ""), {}, "what you wear there was not read: never same")
    local noWeights = client()
    noWeights.setBagItems(bags(STRONG))
    t.eq(BB().Marks(noWeights, { WARRIOR = { proficiency = packs().WARRIOR.proficiency } }, ""), {},
        "no stat weights: no role to mark")
    t.eq(BB().Marks(noWeights, {}, ""), {}, "no class pack")
end

tests["bag arrows: the module draws them and off draws none; nothing is equipped"] = function(t)
    if not has(t) then return end
    local c = client()
    c.setBagItems(bags(WEAK, STRONG))
    local k = ns.Kernel({}, c)
    BB().Declare(k, packs())
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    local P = BB().Piece
    t.eq(c.bagMarks(), {
        { bag = 0, slot = 1, text = P("dps", "down") },
        { bag = 0, slot = 2, text = P("dps", "up") },
    }, "no role chosen, no tank sign: dps only")
    t.eq(k.settings:set(BB().SETTING, false), true)
    c.fire("BAG_UPDATE_DELAYED")
    t.eq(c.bagMarks(), {})
    t.eq(c.equipCalls, 0, "nothing equipped")
    t.eq(k.problems:count(), 0, "no problems")
end

return tests
