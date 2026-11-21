-- Lane W2 self-tests: quests, routes, dungeons, party, navigation state.
-- Same harness as Modules/Tests.lua (ns:Register("test", ...), t:ok / t:eq /
-- t:near); Flow's own logic on made-up inputs, saved data put back.

local _, ns = ...

-- A need kind only these tests use (never on a step): answers by its argument.
local function testNeedKind()
    if not ns:Get("need", "w2test") then
        ns:Register("need", "w2test", {
            met = function(arg)
                if arg == "err" then error("check broke") end
                if arg == "nil" then return nil end
                return arg == "yes"
            end,
        })
    end
end

-------------------------------------------------------------------------------
-- F-025: a need Flow can't check is never met.
-------------------------------------------------------------------------------

ns:Register("test", "needs: an unknown need or a failing check is not met, and the step says why", function(t)
    local N = ns.nav
    testNeedKind()
    local s, why = N.NeedState("nosuchkind:Teleport")
    t:eq(s, "unknown", "a kind nobody registered: unknown")
    t:ok(why ~= nil, "with a reason")
    t:eq(N.NeedMet("nosuchkind:Teleport"), false, "and not met")
    t:eq((N.NeedState("w2test:err")), "unknown", "a check that errors: unknown")
    t:eq(N.NeedMet("w2test:err"), false, "and not met")
    t:eq((N.NeedState("w2test:nil")), "unknown", "a check that can't tell (nil): unknown")
    t:eq((N.NeedState("w2test:yes")), "yes", "a check that says yes: met")
    t:eq((N.NeedState("w2test:no")), "no", "a check that says no: not met")
    t:eq(N.NeedMet("not a token"), false, "not even a token: not met")
    -- Through ResolveNeeds, with Flow's own NeedState: held, with the reason.
    local g = { key = "w2:port", needs = { "w2test:err" } }
    N.ResolveNeeds({ g }, nil, function(tok) return (tok:gsub("^%w+:", "")) end)
    t:ok(g.blockedBy ~= nil, "a hard need Flow can't check holds the step")
    t:ok(g.blockedBy and g.blockedBy:find("couldn't check", 1, true) ~= nil, "and the reason says Flow couldn't check it")
    t:eq(g.blockedShort, "can't check err", "short reason for the lock")
    local soft = { key = "w2:soft", needs = { { "w2test:nil", soft = true } } }
    N.ResolveNeeds({ soft }, nil, nil)
    t:eq(soft.blockedBy, nil, "a soft need still only orders, unknown or not")
    -- A provider on the route still orders an unknown need, never blocks it.
    local p = { key = "w2:prov", provides = { "w2test:nil" } }
    local h = { key = "w2:hard", needs = { "w2test:nil" } }
    N.ResolveNeeds({ p, h }, nil, nil)
    t:eq(h.deps and h.deps[1], "w2:prov", "unknown with a provider on the route: after it")
    t:eq(h.blockedBy, nil, "not blocked while the provider is on the route")
end)

ns:Register("test", "needs: a spell need wants the spell known, not just its name resolving", function(t)
    local N = ns.nav
    t:eq(N.SpellNeedMet("Teleport: Moonglade", { Wrath = true }, nil), false, "spellbook read, spell not in it: not met")
    t:eq(N.SpellNeedMet("Wrath", { Wrath = true }, nil), true, "in the spellbook: met")
    t:eq(N.SpellNeedMet("Teleport: Moonglade", { Wrath = true }, false), false, "the game says not known: not met")
    t:eq(N.SpellNeedMet("Aquatic Form", { Wrath = true }, true), true, "the game says known (a passive the spellbook list skips): met")
    t:eq(N.SpellNeedMet("Teleport: Moonglade", {}, nil), nil, "spellbook not read and the game can't be asked: unknown")
    t:eq(N.SpellNeedMet("Teleport: Moonglade", nil, nil), nil, "no spellbook at all: unknown")
end)

ns:Register("test", "route: a soft need's step hidden or across the sea holds nothing", function(t)
    local N = ns.nav
    local quest = { key = "9201:done", text = "Turn in: Teacher" }
    local train = { key = "train:class", text = "Class training", deps = { "9201:done" }, softDeps = { ["9201:done"] = true } }
    local hard = { key = "x:hard", text = "Hard", deps = { "9201:done" } }
    local kept, held = N.HoldForHidden({ train, hard }, { quest })
    local keptKeys, heldKeys = {}, {}
    for _, g in ipairs(kept) do keptKeys[g.key] = true end
    for _, g in ipairs(held) do heldKeys[g.key] = true end
    t:ok(keptKeys["train:class"], "hidden: a soft dep doesn't hold training")
    t:ok(heldKeys["x:hard"], "hidden: a hard dep holds")
    local function away(g) return g.key == "9201:done" and 2 or nil end
    local function words() return "across the sea", "away" end
    local k2, h2 = N.HoldForAway({ quest, train, hard }, away, words)
    local k2Keys, h2Keys = {}, {}
    for _, g in ipairs(k2) do k2Keys[g.key] = true end
    for _, g in ipairs(h2) do h2Keys[g.key] = true end
    t:ok(k2Keys["train:class"], "away: a soft dep doesn't hold training")
    t:ok(h2Keys["x:hard"], "away: a hard dep holds")
end)
