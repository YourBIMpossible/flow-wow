-- gear(): what the client says about one item and about what you wear, as
-- the raw tables Gear/Read.lua takes. It only reads, and names no unit but
-- "player". The real client over a hand-built environment (`env` stands in
-- for the game's globals), then the fake.
local _, ns = ...

local HELM, SWORD, DAGGER = "item:100", "item:200", "item:300"
local STR, STA = "ITEM_MOD_STRENGTH_SHORT", "ITEM_MOD_STAMINA_SHORT"

local function boom() error("the client refused") end

-- issecretvalue that refuses nil, as the client's does.
local function strictSecret(env, secret)
    env.issecretvalue = function(v)
        if v == nil then error("issecretvalue: nil") end
        return secret ~= nil and secret(v) or false
    end
end

-- A client that knows the items in `say`:
--   say.stats[link]  the item-stats answer     say.kind[link]  the equip location
--   say.ids[id]      the item id worn in a slot say.links[id]   its link
--   say.dualWield    the dual wield answer
-- `asked` lists every inventory question as "unit:id"; `units` every unit named.
local function gearEnv(say)
    say.stats, say.kind = say.stats or {}, say.kind or {}
    say.ids, say.links = say.ids or {}, say.links or {}
    local env = { asked = {}, units = {} }
    env.C_Item = { GetItemStats = function(link) return say.stats[link] end }
    env.GetItemInfoInstant = function(link)
        return 1, "Armor", "Cloth", say.kind[link], 0, 4, 1
    end
    env.GetInventoryItemID = function(unit, id)
        env.asked[#env.asked + 1] = tostring(unit) .. ":" .. tostring(id)
        env.units[tostring(unit)] = true
        return say.ids[id]
    end
    env.GetInventoryItemLink = function(unit, id)
        env.units[tostring(unit)] = true
        return say.links[id]
    end
    env.CanDualWield = function() return say.dualWield end
    return env
end

local function count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

return {
    -- --------------------------------------------------------- the item
    ["gear() gives the item's equip location and stats as the client says"] = function(t)
        local say = { stats = { [HELM] = { [STR] = 5, [STA] = 7 } }, kind = { [HELM] = "INVTYPE_HEAD" } }
        local g = ns.make.client(gearEnv(say)).gear(HELM)
        t.eq(type(g), "table")
        t.eq(g.kind, "INVTYPE_HEAD")
        t.eq(g.stats, { [STR] = 5, [STA] = 7 })
    end,

    ["gear() hands out a copy of the stats, never the client's own table"] = function(t)
        local raw = { [STR] = 5 }
        local say = { stats = { [HELM] = raw }, kind = { [HELM] = "INVTYPE_HEAD" } }
        local c = ns.make.client(gearEnv(say))
        local g = c.gear(HELM)
        t.ok(g.stats ~= raw, "a table of its own")
        g.stats[STR] = 99
        t.eq(raw[STR], 5)
        t.eq(c.gear(HELM).stats[STR], 5)
    end,

    ["gear() leaves the stats out when the client gives none, never an empty table"] = function(t)
        local say = { kind = { [HELM] = "INVTYPE_HEAD" } }
        local env = gearEnv(say)
        local c = ns.make.client(env)
        t.eq(c.gear(HELM).stats, nil, "no answer")
        t.eq(c.gear(HELM).kind, "INVTYPE_HEAD", "the location is still read")
        say.stats[HELM] = "none"
        t.eq(c.gear(HELM).stats, nil, "an answer that is no table")
        env.C_Item.GetItemStats = boom
        t.eq(c.gear(HELM).stats, nil, "a call that fails")
        say.stats[HELM] = {}
        env.C_Item.GetItemStats = function(link) return say.stats[link] end
        t.eq(c.gear(HELM).stats, {}, "an item the client says has no stats is an empty table")
    end,

    ["gear() uses GetItemStats where the client has no C_Item one, and neither is no stats"] = function(t)
        local say = { stats = { [HELM] = { [STA] = 3 } }, kind = { [HELM] = "INVTYPE_HEAD" } }
        local env = gearEnv(say)
        env.C_Item = nil
        env.GetItemStats = function(link) return say.stats[link] end
        local c = ns.make.client(env)
        t.eq(c.gear(HELM).stats, { [STA] = 3 })
        env.GetItemStats = nil
        t.eq(c.gear(HELM).stats, nil, "no call: not read")
        t.eq(c.gear(HELM).kind, "INVTYPE_HEAD")
    end,

    ["gear() leaves the equip location out when it is not said"] = function(t)
        local say = { stats = { [HELM] = { [STA] = 3 } }, kind = { [HELM] = "" } }
        local env = gearEnv(say)
        local c = ns.make.client(env)
        t.eq(c.gear(HELM).kind, nil, "an empty location")
        say.kind[HELM] = 4
        t.eq(c.gear(HELM).kind, nil, "not a string")
        env.GetItemInfoInstant = boom
        t.eq(c.gear(HELM).kind, nil, "a call that fails")
        env.GetItemInfoInstant = nil
        t.eq(c.gear(HELM).kind, nil, "no call")
        t.eq(c.gear(HELM).stats, { [STA] = 3 }, "the stats are still read")
    end,

    ["gear() with no link reads no item, and still reads what you wear"] = function(t)
        local say = { ids = { [1] = 100 }, links = { [1] = HELM }, kind = { [HELM] = "INVTYPE_HEAD" },
            stats = { [HELM] = { [STA] = 2 } }, dualWield = true }
        local c = ns.make.client(gearEnv(say))
        for _, link in ipairs({ false, "", 100 }) do
            local g = c.gear(link or nil)
            t.eq(g.kind, nil)
            t.eq(g.stats, nil)
            t.eq(g.worn[1], { kind = "INVTYPE_HEAD", stats = { [STA] = 2 } })
            t.eq(g.dualWield, true)
        end
    end,

    -- ------------------------------------------------------------- worn
    ["gear() gives each worn item by its inventory number"] = function(t)
        local say = {
            ids = { [1] = 100, [16] = 200, [17] = 300 },
            links = { [1] = HELM, [16] = SWORD, [17] = DAGGER },
            kind = { [HELM] = "INVTYPE_HEAD", [SWORD] = "INVTYPE_WEAPON", [DAGGER] = "INVTYPE_WEAPON" },
            stats = { [HELM] = { [STA] = 2 }, [SWORD] = { [STR] = 10 }, [DAGGER] = { [STR] = 3 } },
        }
        local worn = ns.make.client(gearEnv(say)).gear(nil).worn
        t.eq(worn[1], { kind = "INVTYPE_HEAD", stats = { [STA] = 2 } })
        t.eq(worn[16], { kind = "INVTYPE_WEAPON", stats = { [STR] = 10 } })
        t.eq(worn[17], { kind = "INVTYPE_WEAPON", stats = { [STR] = 3 } })
    end,

    ["gear() says a slot is empty only when the client gives no item id for it"] = function(t)
        local say = { ids = { [16] = 200 }, links = { [16] = SWORD }, kind = { [SWORD] = "INVTYPE_WEAPON" },
            stats = { [SWORD] = { [STR] = 10 } } }
        local worn = ns.make.client(gearEnv(say)).gear(nil).worn
        t.eq(worn[17], false, "no id for the off hand: read, and empty")
        t.eq(worn[1], false)
        t.eq(type(worn[16]), "table")
        t.eq(count(worn), 17, "all seventeen slots were read")
    end,

    ["SC2: an item whose link is not loaded yet is not read, never an empty slot"] = function(t)
        local say = { ids = { [17] = 300 } }
        local env = gearEnv(say)
        local c = ns.make.client(env)
        local worn = c.gear(nil).worn
        t.eq(worn[17], nil, "an id but no link: absent")
        t.ok(worn[17] ~= false)
        say.links[17] = ""
        t.eq(c.gear(nil).worn[17], nil, "an empty link is no link")
        env.GetInventoryItemLink = boom
        t.eq(c.gear(nil).worn[17], nil, "the link call fails")
        env.GetInventoryItemLink = nil
        t.eq(c.gear(nil).worn[17], nil, "no link call")
        t.eq(c.gear(nil).worn[16], false, "the other slots are as they were")
    end,

    ["gear() reads no slot as empty when the client cannot be asked for item ids"] = function(t)
        local say = { links = { [16] = SWORD } }
        local env = gearEnv(say)
        env.GetInventoryItemID = nil
        local c = ns.make.client(env)
        t.eq(c.gear(nil).worn, {}, "no call: nothing is known, nothing is empty")
        env.GetInventoryItemID = boom
        t.eq(c.gear(nil).worn, {}, "a call that fails")
    end,

    ["gear() does not read a slot whose item id is not a number"] = function(t)
        local say = { ids = { [1] = "100", [2] = true, [3] = false }, links = { [1] = HELM, [2] = HELM, [3] = HELM } }
        local worn = ns.make.client(gearEnv(say)).gear(nil).worn
        t.eq(worn[1], nil)
        t.eq(worn[2], nil)
        t.eq(worn[3], nil, "false is not the client's way of saying empty")
    end,

    ["gear() keeps a worn item whose stats or location were not read, without them"] = function(t)
        local say = { ids = { [1] = 100 }, links = { [1] = HELM } }
        local worn = ns.make.client(gearEnv(say)).gear(nil).worn
        t.eq(worn[1], {}, "worn, with nothing known about it")
    end,

    ["gear() asks about the seventeen compared slots and no other, and names only you"] = function(t)
        local env = gearEnv({})
        ns.make.client(env).gear(nil)
        t.eq(#env.asked, 17)
        local want, got = {}, {}
        for id in pairs(ns.GearRead.SLOT_OF) do want["player:" .. id] = true end
        for i = 1, #env.asked do got[env.asked[i]] = true end
        t.eq(got, want, "the slots Gear/Read.lua names; not the shirt (4), not the tabard (19)")
        t.eq(env.units, { player = true })
    end,

    -- ------------------------------------------------------- dual wield
    ["gear() gives dual wield as true or false, and leaves it out otherwise"] = function(t)
        local say = { dualWield = true }
        local env = gearEnv(say)
        local c = ns.make.client(env)
        t.eq(c.gear(nil).dualWield, true)
        say.dualWield = false
        t.eq(c.gear(nil).dualWield, false)
        for _, odd in ipairs({ 1, 0, "yes" }) do
            say.dualWield = odd
            t.eq(c.gear(nil).dualWield, nil, tostring(odd))
        end
        say.dualWield = nil
        t.eq(c.gear(nil).dualWield, nil, "no answer is not a no")
        env.CanDualWield = boom
        t.eq(c.gear(nil).dualWield, nil, "a call that fails")
        env.CanDualWield = nil
        t.eq(c.gear(nil).dualWield, nil, "no call")
    end,

    -- ---------------------------------------------------- secret values
    ["gear() on a client whose secrecy check refuses nil still reads empty slots and absent answers"] = function(t)
        local say = { ids = { [16] = 200 }, links = { [16] = SWORD }, kind = { [SWORD] = "INVTYPE_WEAPON" },
            stats = { [SWORD] = { [STR] = 10 } } }
        local env = gearEnv(say)
        strictSecret(env)
        local g = ns.make.client(env).gear(HELM)
        t.eq(g.worn[17], false, "empty, not unread")
        t.eq(g.worn[16], { kind = "INVTYPE_WEAPON", stats = { [STR] = 10 } })
        t.eq(g.stats, nil)
        t.eq(g.kind, nil)
        t.eq(g.dualWield, nil)
    end,

    ["gear() treats a secret answer as not read"] = function(t)
        local say = { ids = { [1] = 100, [16] = 200 }, links = { [1] = HELM, [16] = SWORD },
            kind = { [HELM] = "INVTYPE_HEAD", [SWORD] = "INVTYPE_WEAPON" },
            stats = { [HELM] = { [STR] = 5, [STA] = 7 }, [SWORD] = { [STR] = 10 } }, dualWield = true }
        local secret = {}
        local env = gearEnv(say)
        strictSecret(env, function(v) return secret[v] == true end)
        local c = ns.make.client(env)

        secret[7] = true
        t.eq(c.gear(HELM).stats, { [STR] = 5, [STA] = false }, "a secret stat: on the item, not read")
        secret[7] = nil

        secret[say.stats[HELM]] = true
        t.eq(c.gear(HELM).stats, nil, "the whole answer secret")
        secret[say.stats[HELM]] = nil

        secret["INVTYPE_HEAD"] = true
        t.eq(c.gear(HELM).kind, nil)
        secret["INVTYPE_HEAD"] = nil

        secret[200] = true
        t.eq(c.gear(nil).worn[16], nil, "a secret item id: not read, and not empty")
        secret[200] = nil

        secret[SWORD] = true
        t.eq(c.gear(nil).worn[16], nil, "a secret link: not read")
        secret[SWORD] = nil

        secret[true] = true
        t.eq(c.gear(nil).dualWield, nil)
    end,

    -- ------------------------------------------------- with Gear/Read.lua
    ["gear() goes straight into GearRead.Shapes and the scorer (F-006, the off hand)"] = function(t)
        local NEW = "item:400"
        local say = {
            ids = { [16] = 200, [17] = 300 }, links = { [16] = SWORD, [17] = DAGGER },
            kind = { [SWORD] = "INVTYPE_WEAPON", [DAGGER] = "INVTYPE_WEAPON", [NEW] = "INVTYPE_WEAPON" },
            stats = { [SWORD] = { [STR] = 10 }, [DAGGER] = { [STR] = 3 }, [NEW] = { [STR] = 6 } },
            dualWield = true,
        }
        local out = ns.GearRead.Shapes(ns.make.client(gearEnv(say)).gear(NEW))
        t.eq(out.unmapped, {})
        t.eq(out.ignored, {})
        local r = ns.GearScore.Compare(out.candidate, out.equipped, { [STR] = 2 }, out.can)
        t.eq({ r.verdict, r.delta, r.slot }, { "upgrade", 6, "offHand" })
    end,

    ["gear() with an off hand not loaded yet gives no recommendation, not an upgrade for an empty hand"] = function(t)
        local NEW = "item:400"
        local say = {
            ids = { [16] = 200, [17] = 300 }, links = { [16] = SWORD },
            kind = { [SWORD] = "INVTYPE_WEAPON", [NEW] = "INVTYPE_WEAPON" },
            stats = { [SWORD] = { [STR] = 10 }, [NEW] = { [STR] = 6 } },
            dualWield = true,
        }
        local out = ns.GearRead.Shapes(ns.make.client(gearEnv(say)).gear(NEW))
        local r = ns.GearScore.Compare(out.candidate, out.equipped, { [STR] = 2 }, out.can)
        t.eq(r.verdict, "none")
        t.eq(r.reason, ns.GearScore.REASON.worn .. ": offHand")
    end,

    -- --------------------------------------------------------------- fake
    ["fake: gear() knows nothing until told"] = function(t)
        local c = ns.make.fakeClient()
        local g = c.gear(HELM)
        t.eq(g.kind, nil)
        t.eq(g.stats, nil)
        t.eq(g.worn, {})
        t.eq(g.dualWield, nil)
    end,

    ["fake: an item, what is worn and dual wield are set and read back"] = function(t)
        local c = ns.make.fakeClient()
        c.setItem(HELM, { kind = "INVTYPE_HEAD", stats = { [STA] = 4 } })
        c.setItem(SWORD, { kind = "INVTYPE_WEAPON", stats = { [STR] = 10 } })
        c.setWorn(16, SWORD)
        c.setWorn(17, false)
        c.setDualWield(false)
        local g = c.gear(HELM)
        t.eq(g.kind, "INVTYPE_HEAD")
        t.eq(g.stats, { [STA] = 4 })
        t.eq(g.worn, { [16] = { kind = "INVTYPE_WEAPON", stats = { [STR] = 10 } }, [17] = false })
        t.eq(g.dualWield, false)
        c.setWorn(17, nil)
        t.eq(c.gear(HELM).worn[17], nil, "taken back: not read")
        c.setDualWield(nil)
        t.eq(c.gear(HELM).dualWield, nil)
        c.setDualWield("yes")
        t.eq(c.gear(HELM).dualWield, nil, "only a plain true or false is an answer")
        c.setItem(HELM, nil)
        t.eq(c.gear(HELM).kind, nil)
        t.eq(c.gear(HELM).stats, nil)
    end,

    ["fake: a worn link nobody described is worn with nothing known about it"] = function(t)
        local c = ns.make.fakeClient()
        c.setWorn(1, HELM)
        t.eq(c.gear(nil).worn[1], {})
    end,

    ["fake: gear() gives copies, and keeps none of the tables it was set from"] = function(t)
        local c = ns.make.fakeClient()
        local stats = { [STA] = 4 }
        c.setItem(HELM, { kind = "INVTYPE_HEAD", stats = stats })
        c.setWorn(1, HELM)
        stats[STA] = 9
        t.eq(c.gear(HELM).stats[STA], 4)
        local g = c.gear(HELM)
        g.stats[STA] = 1
        g.worn[1].stats[STA] = 1
        g.worn[2] = false
        t.eq(c.gear(HELM).stats[STA], 4)
        t.eq(c.gear(HELM).worn[1].stats[STA], 4)
        t.eq(c.gear(HELM).worn[2], nil)
    end,

    ["fake: its answer goes into GearRead.Shapes like the real client's"] = function(t)
        local c = ns.make.fakeClient()
        c.setItem(HELM, { kind = "INVTYPE_HEAD", stats = { [STA] = 4 } })
        c.setWorn(1, false)
        local out = ns.GearRead.Shapes(c.gear(HELM))
        local r = ns.GearScore.Compare(out.candidate, out.equipped, { [STA] = 1 }, out.can)
        t.eq({ r.verdict, r.delta, r.slot }, { "upgrade", 4, "head" })
    end,
}
