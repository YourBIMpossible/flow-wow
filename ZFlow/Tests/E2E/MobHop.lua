local _, ns = ...
-- Nav/MobHop.lua through its real entry, on the whole add-on loaded on a
-- fake client: the "mobHop" module reads a kill target's spawns from the
-- player's Questie, groups them on the player's map and orders the groups
-- nearest first. Made-up npc, map and spots. Not tested in game.
local tests = {}

local MAP, NPC = 9001, 4242

local function boot(questie)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    c.setPosition(MAP, 0, 0)
    c.setMapSize(MAP, 1000, 1000)
    if questie then
        c.setQuestieModule("QuestieDB", {
            QueryNPCSingle = function(id, key)
                if id == NPC and key == "spawns" then
                    return { [12] = { { 50, 50 }, { 10, 10 }, { 12, 10 } } }
                end
                return nil
            end,
        })
        c.setQuestieModule("ZoneDB", { GetUiMapIdByAreaId = function(_, area) return ({ [12] = MAP })[area] end })
    end
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

tests["mob hop: a kill target's groups on the player's map, nearest first"] = function(t)
    local _, addon = boot(true)
    local out = addon.use("mobHop").Plan(NPC)
    t.eq(type(out), "table")
    t.eq(#out, 2)
    t.eq(out[1].n, 2)
    t.ok(math.abs(out[1].x - 0.11) < 1e-6, "the near group first")
    t.ok(math.abs(out[1].leg - 148.66) < 0.01, "yards to it")
end

tests["mob hop: no Questie gives no plan and says why"] = function(t)
    local _, addon = boot(false)
    local out, why = addon.use("mobHop").Plan(NPC)
    t.eq(out, nil)
    t.eq(why, "no questie")
end

return tests
