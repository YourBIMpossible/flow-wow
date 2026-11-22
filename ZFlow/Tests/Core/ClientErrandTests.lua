-- The reads of the errand stops (F2) on the client: guid(), serviceNpc(),
-- merchantRepairs(), bindLocation() and hearthCooldown(). First the real
-- client over a hand-built environment (env stands in for the globals of
-- the game), then the fake, then HEARTHSTONE_BOUND through the fake to the
-- recorder. Every value is made up by hand. Not tested in game.
local _, ns = ...

local NPC = "Creature-0-1-2-3-54-0"

local function boom() error("the client refused") end

-- An issecretvalue that refuses nil, as the one of the client does.
local function strictSecret(env, secret)
    env.issecretvalue = function(v)
        if v == nil then error("issecretvalue: nil") end
        return secret ~= nil and secret(v) or false
    end
end

-- A window of an npc that is plainly no player.
local function npcEnv(name, guid)
    local env = {
        UnitIsPlayer = function() return false end,
        UnitName = function() return name end,
        UnitGUID = function() return guid end,
    }
    strictSecret(env)
    return env
end

-- A stone in the bags, used at start for duration seconds, at time now.
local function stoneEnv(count, start, duration, now)
    local env = { asked = {} }
    env.GetItemCount = function(id) env.asked[#env.asked + 1] = id return count end
    env.GetItemCooldown = function(id) env.asked[#env.asked + 1] = id return start, duration, 1 end
    env.GetTime = function() return now end
    strictSecret(env)
    return env
end

return {
    ["client guid (errands): the player, the pet and the target, and no other unit"] = function(t)
        local asked = {}
        local env = { UnitGUID = function(unit)
            asked[#asked + 1] = unit
            return "id-" .. unit
        end }
        strictSecret(env)
        local c = ns.make.client(env)
        t.eq(c.guid("player"), "id-player")
        t.eq(c.guid("pet"), "id-pet")
        t.eq(c.guid("target"), "id-target")
        t.eq(c.guid("npc"), nil)
        t.eq(c.guid("party1"), nil)
        t.eq(c.guid("mouseover"), nil)
        t.eq(c.guid(nil), nil)
        t.eq(c.guid(7), nil)
        t.eq(asked, { "player", "pet", "target" }, "no other unit reaches the client")
        t.eq(c.playerGUID(), "id-player")
        t.eq(c.petGUID(), "id-pet")
    end,

    ["client guid (errands): no read, a failed read, a secret or an odd answer is not known"] = function(t)
        t.eq(ns.make.client({}).guid("player"), nil)
        t.eq(ns.make.client({ UnitGUID = boom }).guid("player"), nil)
        t.eq(ns.make.client({ UnitGUID = function() return "" end }).guid("player"), nil)
        t.eq(ns.make.client({ UnitGUID = function() return 12 end }).guid("player"), nil)
        t.eq(ns.make.client({ UnitGUID = function() return nil end }).guid("player"), nil)
        local env = { UnitGUID = function() return "Player-1-0000AAAA" end }
        strictSecret(env, function() return true end)
        t.eq(ns.make.client(env).guid("player"), nil)
    end,

    ["client serviceNpc: the npc whose window is open, by id and by name"] = function(t)
        local asked = {}
        local env = npcEnv("Kaita Deepforge", NPC)
        local name, guid, isPlayer = env.UnitName, env.UnitGUID, env.UnitIsPlayer
        env.UnitName = function(unit) asked[#asked + 1] = unit return name() end
        env.UnitGUID = function(unit) asked[#asked + 1] = unit return guid() end
        env.UnitIsPlayer = function(unit) asked[#asked + 1] = unit return isPlayer() end
        t.eq(ns.make.client(env).serviceNpc(), { guid = NPC, name = "Kaita Deepforge" })
        t.eq(asked, { "npc", "npc", "npc" }, "only the npc of the open window is asked about")
    end,

    ["client serviceNpc: a part not known is left out; neither known is nil"] = function(t)
        t.eq(ns.make.client(npcEnv("Kaita Deepforge", nil)).serviceNpc(), { name = "Kaita Deepforge" })
        t.eq(ns.make.client(npcEnv(nil, NPC)).serviceNpc(), { guid = NPC })
        t.eq(ns.make.client(npcEnv("", "")).serviceNpc(), nil)
        t.eq(ns.make.client(npcEnv(nil, nil)).serviceNpc(), nil)
        t.eq(ns.make.client(npcEnv(5, {})).serviceNpc(), nil)
        local env = npcEnv("Kaita Deepforge", NPC)
        env.UnitGUID = boom
        t.eq(ns.make.client(env).serviceNpc(), { name = "Kaita Deepforge" })
        env = npcEnv("Kaita Deepforge", NPC)
        env.UnitGUID = nil
        t.eq(ns.make.client(env).serviceNpc(), { name = "Kaita Deepforge" })
    end,

    ["client serviceNpc: nil unless the client says plainly it is no player"] = function(t)
        local env = npcEnv("Thrall", "Player-1-0000BBBB")
        env.UnitIsPlayer = function() return true end
        t.eq(ns.make.client(env).serviceNpc(), nil, "a player")
        env.UnitIsPlayer = function() return nil end
        t.eq(ns.make.client(env).serviceNpc(), nil, "the client does not say")
        env.UnitIsPlayer = boom
        t.eq(ns.make.client(env).serviceNpc(), nil, "the read fails")
        env.UnitIsPlayer = nil
        t.eq(ns.make.client(env).serviceNpc(), nil, "no such read")
        t.eq(ns.make.client({}).serviceNpc(), nil, "no client reads at all")
    end,

    ["client serviceNpc: secret answers are not known"] = function(t)
        local env = npcEnv("Kaita Deepforge", NPC)
        strictSecret(env, function(v) return v == NPC end)
        t.eq(ns.make.client(env).serviceNpc(), { name = "Kaita Deepforge" }, "a secret id is left out")
        env = npcEnv("Kaita Deepforge", NPC)
        strictSecret(env, function(v) return v == false end)
        t.eq(ns.make.client(env).serviceNpc(), nil, "a secret player answer is not a plain no")
        env = npcEnv("Kaita Deepforge", NPC)
        strictSecret(env, function(v) return type(v) == "string" end)
        t.eq(ns.make.client(env).serviceNpc(), nil, "both parts secret")
    end,

    ["client merchantRepairs: yes, no, or not known"] = function(t)
        local function with(v)
            local env = { CanMerchantRepair = function() return v end }
            strictSecret(env)
            return ns.make.client(env).merchantRepairs()
        end
        t.eq(with(true), true)
        t.eq(with(1), true)
        t.eq(with(false), false)
        t.eq(with(0), false)
        t.eq(with(nil), nil)
        t.eq(with("yes"), nil)
        t.eq(with(2), nil)
        t.eq(ns.make.client({}).merchantRepairs(), nil)
        t.eq(ns.make.client({ CanMerchantRepair = boom }).merchantRepairs(), nil)
        local env = { CanMerchantRepair = function() return false end }
        strictSecret(env, function() return true end)
        t.eq(ns.make.client(env).merchantRepairs(), nil, "a secret answer is not a no")
    end,

    ["client bindLocation: the name, or not known"] = function(t)
        local function with(v)
            local env = { GetBindLocation = function() return v end }
            strictSecret(env)
            return ns.make.client(env).bindLocation()
        end
        t.eq(with("Goldshire"), "Goldshire")
        t.eq(with(""), nil)
        t.eq(with(nil), nil)
        t.eq(with(12), nil)
        t.eq(ns.make.client({}).bindLocation(), nil)
        t.eq(ns.make.client({ GetBindLocation = boom }).bindLocation(), nil)
        local env = { GetBindLocation = function() return "Goldshire" end }
        strictSecret(env, function() return true end)
        t.eq(ns.make.client(env).bindLocation(), nil)
    end,

    ["client hearthCooldown: the seconds left on the stone the player carries"] = function(t)
        local env = stoneEnv(1, 1000, 3600, 1600)
        t.eq(ns.make.client(env).hearthCooldown(), 3000)
        t.eq(env.asked, { 6948, 6948 }, "the stone is the only item asked about")
        t.eq(ns.make.client(stoneEnv(1, 1000, 3600, 4600)).hearthCooldown(), 0, "just ready")
        t.eq(ns.make.client(stoneEnv(1, 1000, 3600, 9000)).hearthCooldown(), 0, "long ready")
        t.eq(ns.make.client(stoneEnv(1, 0, 0, 1600)).hearthCooldown(), 0, "no cooldown running")
        t.eq(ns.make.client(stoneEnv(2, 0, 0, 1600)).hearthCooldown(), 0)
    end,

    ["client hearthCooldown: no stone is not known, never ready"] = function(t)
        t.eq(ns.make.client(stoneEnv(0, 0, 0, 1600)).hearthCooldown(), nil)
        t.eq(ns.make.client(stoneEnv(nil, 0, 0, 1600)).hearthCooldown(), nil)
        t.eq(ns.make.client(stoneEnv("1", 0, 0, 1600)).hearthCooldown(), nil)
        local env = stoneEnv(1, 0, 0, 1600)
        env.GetItemCount = nil
        t.eq(ns.make.client(env).hearthCooldown(), nil, "the bags cannot be asked")
        env = stoneEnv(1, 0, 0, 1600)
        env.GetItemCount = boom
        t.eq(ns.make.client(env).hearthCooldown(), nil)
    end,

    ["client hearthCooldown: an answer that cannot be read is not known"] = function(t)
        t.eq(ns.make.client({}).hearthCooldown(), nil)
        t.eq(ns.make.client(stoneEnv(1, nil, nil, 1600)).hearthCooldown(), nil)
        t.eq(ns.make.client(stoneEnv(1, 1000, nil, 1600)).hearthCooldown(), nil)
        t.eq(ns.make.client(stoneEnv(1, "a", 3600, 1600)).hearthCooldown(), nil)
        t.eq(ns.make.client(stoneEnv(1, -5, 3600, 1600)).hearthCooldown(), nil)
        t.eq(ns.make.client(stoneEnv(1, 1000, -1, 1600)).hearthCooldown(), nil)
        t.eq(ns.make.client(stoneEnv(1, 1000, 3600, nil)).hearthCooldown(), nil, "the time is not known")
        t.eq(ns.make.client(stoneEnv(1, 1000, 3600, "now")).hearthCooldown(), nil)
        local env = stoneEnv(1, 1000, 3600, 1600)
        env.GetItemCooldown = boom
        t.eq(ns.make.client(env).hearthCooldown(), nil)
        env = stoneEnv(1, 1000, 3600, 1600)
        env.GetTime = nil
        t.eq(ns.make.client(env).hearthCooldown(), nil, "no clock: not 0 in its place")
        env = stoneEnv(1, 1000, 3600, 1600)
        strictSecret(env, function(v) return v == 3600 end)
        t.eq(ns.make.client(env).hearthCooldown(), nil, "a secret duration")
        env = stoneEnv(1, 1000, 3600, 1600)
        strictSecret(env, function(v) return v == 1 end)
        t.eq(ns.make.client(env).hearthCooldown(), nil, "a secret count")
    end,

    ["fake client: the errand reads say nothing until a test sets them"] = function(t)
        local c = ns.make.fakeClient()
        t.eq(c.guid("player"), nil)
        t.eq(c.serviceNpc(), nil)
        t.eq(c.merchantRepairs(), nil)
        t.eq(c.bindLocation(), nil)
        t.eq(c.hearthCooldown(), nil)
    end,

    ["fake client: the errand reads give back what was set"] = function(t)
        local c = ns.make.fakeClient()
        c.setGuid("player", "Player-1-0000AAAA")
        c.setGuid("pet", "Pet-0-1-2")
        c.setGuid("npc", NPC)
        t.eq(c.guid("player"), "Player-1-0000AAAA")
        t.eq(c.playerGUID(), "Player-1-0000AAAA")
        t.eq(c.petGUID(), "Pet-0-1-2")
        t.eq(c.guid("npc"), nil, "as on the client: no other unit")
        c.setGuid("player", nil)
        t.eq(c.guid("player"), nil)

        c.setServiceNpc(NPC, "Kaita Deepforge")
        local npc = c.serviceNpc()
        t.eq(npc, { guid = NPC, name = "Kaita Deepforge" })
        npc.name = "changed"
        t.eq(c.serviceNpc().name, "Kaita Deepforge", "a copy is handed out")
        c.setServiceNpc(nil, "Banker Olivia")
        t.eq(c.serviceNpc(), { name = "Banker Olivia" })
        c.setServiceNpc(nil, nil)
        t.eq(c.serviceNpc(), nil)

        c.setMerchantRepairs(true)
        t.eq(c.merchantRepairs(), true)
        c.setMerchantRepairs(false)
        t.eq(c.merchantRepairs(), false)
        c.setMerchantRepairs(nil)
        t.eq(c.merchantRepairs(), nil)

        c.setBindLocation("Goldshire")
        t.eq(c.bindLocation(), "Goldshire")
        c.setBindLocation("")
        t.eq(c.bindLocation(), nil)

        c.setHearthCooldown(90)
        t.eq(c.hearthCooldown(), 90)
        c.setHearthCooldown(0)
        t.eq(c.hearthCooldown(), 0)
        c.setHearthCooldown(-1)
        t.eq(c.hearthCooldown(), nil)
        c.setHearthCooldown(nil)
        t.eq(c.hearthCooldown(), nil)
    end,

    ["fake client: HEARTHSTONE_BOUND reaches the recorder, which reads the bind place of the fake"] = function(t)
        local c = ns.make.fakeClient()
        c.setSaved(ns.id.accountDB, {})
        c.setSaved(ns.id.charDB, {})
        c.setClock(5000)
        c.setZone(1, 1411)
        c.setPosition(1411, 0.625, 0.5)
        c.setBindLocation("Goldshire")
        local k = ns.Kernel({}, c)
        ns.Diag.Start(k)
        ns.HearthSeen.Declare(k)
        k:Boot()
        c.fire("ADDON_LOADED", ns.id.addon)
        c.fire("PLAYER_LOGIN")
        c.fire("PLAYER_ENTERING_WORLD")
        t.eq(k.store:get("char", ns.Nav.HEARTH_BIND), nil, "nothing before the event")
        c.fire("HEARTHSTONE_BOUND")
        t.eq(k.store:get("char", ns.Nav.HEARTH_BIND),
            { name = "Goldshire", map = 1411, x = 0.625, y = 0.5, seen = 5000 })
        t.eq(k.problems:count(), 0)
    end,
}
