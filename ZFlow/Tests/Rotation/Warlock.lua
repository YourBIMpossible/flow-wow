local _, ns = ...

-- The Warlock pack, N58 (lead section 241): the armor, the demon and the
-- curse you cast or choose are the ones asked for; nothing kept, the old
-- rules; Soul Shards read as none hold back a summon that needs one, and
-- never change the demon you keep. Pure: ns.Choose on snapshots made here.

local ALL = {
    "Demon Skin", "Demon Armor", "Summon Imp", "Summon Voidwalker", "Summon Succubus", "Summon Felhunter",
    "Curse of Agony", "Curse of Weakness", "Curse of Tongues", "Corruption", "Immolate", "Shadow Bolt", "Shoot",
}

-- Out of a fight, no target, armor up, the pet as given.
local function snap(over, knows)
    local s = { role = "dps", hostile = false, inCombat = false, dead = false, spells = {},
                buffs = { ["Demon Armor"] = true }, pet = { exists = true, dead = false },
                targetDebuffs = {}, current = { Shoot = false } }
    for _, name in ipairs(knows or ALL) do s.spells[name] = { known = true, onCooldown = false, inRange = true } end
    for k, v in pairs(over or {}) do s[k] = v end
    return s
end

local function advice(over, knows)
    local r = ns.Choose(snap(over, knows), ns.Packs.WARLOCK)
    return r and r.spell or nil, r
end

local DEAD = { exists = true, dead = true }
local FIGHT = { hostile = true, inCombat = true }
local function fight(over)
    local out = { hostile = true, inCombat = true }
    for k, v in pairs(over or {}) do out[k] = v end
    return out
end
local function idleDead(over)
    local out = { pet = DEAD }
    for k, v in pairs(over or {}) do out[k] = v end
    return out
end

local function rowsByKey()
    local by = {}
    for _, row in ipairs(ns.Packs.WARLOCK.options.sticky or {}) do by[row.key] = row end
    return by
end

return {
    ["warlock pack passes PackCheck"] = function(t)
        local ok, problems = ns.PackCheck(ns.Packs.WARLOCK)
        t.eq(table.concat(problems, "; "), "", "no problems")
        t.ok(ok, "ok")
    end,

    ["warlock N58: the armor, demon and curse rows"] = function(t)
        local by = rowsByKey()
        t.eq(by.armor and by.armor.prefix, "", "armor: no prefix")
        t.eq(by.armor and by.armor.only, { ["Demon Armor"] = true, ["Demon Skin"] = true }, "armor: the pack's armors")
        t.eq(by.armor and by.armor.word, "armor")
        t.eq(by.demon and by.demon.prefix, "Summon ")
        t.eq(by.demon and by.demon.only, { ["Summon Imp"] = true, ["Summon Voidwalker"] = true,
                                          ["Summon Succubus"] = true, ["Summon Felhunter"] = true },
             "demon: the pack's summons only (a mount's Summon is not a demon)")
        t.eq(by.demon and by.demon.word, "demon")
        t.eq(by.curse and by.curse.prefix, "Curse of ")
        t.eq(by.curse and by.curse.only, { ["Curse of Agony"] = true, ["Curse of Weakness"] = true,
                                          ["Curse of Tongues"] = true }, "curse: the pack's curses")
        t.eq(by.curse and by.curse.word, "curse")
        t.eq(by.curse and by.curse.fightOnly, nil, "a curse cast is kept for the role")
        for _, row in pairs(by) do
            for _, name in ipairs(row.names) do
                t.ok(ns.Packs.WARLOCK.spells[name] ~= nil, name .. " is in the spell list")
                t.ok(row.only[name], name .. " is in its row's set")
            end
        end
        t.eq(ns.Packs.WARLOCK.options.conjure, { { spell = "Soul Shard", items = { 6265 } } },
             "the shard count, through the shared bag count read")
    end,

    ["warlock N58: armor: the kept one; nothing kept or not known, the old rule"] = function(t)
        t.eq(advice({ buffs = {} }), "Demon Armor", "nothing kept: the first known")
        t.eq(advice({ buffs = {}, chosen = { armor = "Demon Skin" } }), "Demon Skin", "kept: Demon Skin")
        t.eq(advice({ buffs = {}, chosen = { armorSet = "Demon Skin" } }), "Demon Skin", "the word's choice")
        local knows = {}
        for _, name in ipairs(ALL) do if name ~= "Demon Skin" then knows[#knows + 1] = name end end
        t.eq(advice({ buffs = {}, chosen = { armor = "Demon Skin" } }, knows), "Demon Armor", "kept, not known: the old rule")
        t.eq(advice({ chosen = { armor = "Demon Skin" } }), nil, "an armor up: nothing")
    end,

    ["warlock N58: demon: the kept one; nothing kept or not known, the old rule"] = function(t)
        t.eq(advice(idleDead()), "Summon Voidwalker", "nothing kept: the voidwalker, as before")
        t.eq(advice(idleDead({ chosen = { demon = "Summon Felhunter" } })), "Summon Felhunter", "kept: the felhunter")
        t.eq(advice(idleDead({ chosen = { demonSet = "Summon Succubus", demon = "Summon Felhunter" } })),
             "Summon Succubus", "the word's choice first")
        t.eq(advice({ pet = { exists = false }, chosen = { demon = "Summon Imp" } }), "Summon Imp", "no pet: the kept imp")
        local knows = {}
        for _, name in ipairs(ALL) do if name ~= "Summon Felhunter" then knows[#knows + 1] = name end end
        t.eq(advice(idleDead({ chosen = { demon = "Summon Felhunter" } }), knows), "Summon Voidwalker",
             "kept, not known: the old rule")
        t.eq(advice({ chosen = { demon = "Summon Felhunter" } }), nil, "the pet alive: nothing")
        t.ok(advice(fight({ pet = DEAD, chosen = { demon = "Summon Felhunter" } })) ~= "Summon Felhunter",
             "in a fight: no summoning")
    end,

    ["warlock N58: no Soul Shard: no summon that needs one, the imp said so; the kept demon stays"] = function(t)
        local kept = { demon = "Summon Felhunter" }
        local spell, r = advice(idleDead({ chosen = kept, conjured = { ["Soul Shard"] = 0 } }))
        t.eq(spell, "Summon Imp", "no shard: the imp")
        t.ok(r and tostring(r.reason):find("(no Soul Shard)", 1, true), "said why: " .. tostring(r and r.reason))
        t.eq(advice(idleDead({ chosen = kept, conjured = { ["Soul Shard"] = 2 } })), "Summon Felhunter",
             "shards back: the kept felhunter again")
        t.eq(advice(idleDead({ chosen = kept })), "Summon Felhunter", "shards not read: the kept one, as before")
        t.eq(advice(idleDead({ conjured = { ["Soul Shard"] = 0 } })), "Summon Imp", "nothing kept, no shard: the imp")
        local spell2, r2 = advice(idleDead({ chosen = { demon = "Summon Imp" }, conjured = { ["Soul Shard"] = 0 } }))
        t.eq(spell2, "Summon Imp", "the imp needs no shard")
        t.ok(r2 and not tostring(r2.reason):find("Soul Shard", 1, true), "and nothing said about shards")
        local knows = {}
        for _, name in ipairs(ALL) do if name ~= "Summon Imp" then knows[#knows + 1] = name end end
        t.eq(advice(idleDead({ chosen = kept, conjured = { ["Soul Shard"] = 0 } }), knows), nil,
             "no shard and no imp: no summon")
        t.eq(kept.demon, "Summon Felhunter", "the snapshot's kept demon is not touched")
        local by = rowsByKey()
        t.eq(by.demon.pick(snap(idleDead({ chosen = kept, conjured = { ["Soul Shard"] = 0 } }))), "Summon Imp",
             "PC-1: the imp asked for is the pick, so a cast of it is not kept")
        t.eq(by.demon.pick(snap(idleDead({ chosen = kept }))), "Summon Felhunter", "else the kept one")
    end,

    ["warlock N58: curse: with none of yours on the target, the kept one; else the old rule"] = function(t)
        t.eq(advice(FIGHT), "Curse of Agony", "nothing kept: Curse of Agony, as before")
        t.eq(advice(fight({ chosen = { curse = "Curse of Weakness" } })), "Curse of Weakness", "kept: Weakness")
        t.eq(advice(fight({ chosen = { curseSet = "Curse of Tongues", curse = "Curse of Weakness" } })),
             "Curse of Tongues", "the word's choice first")
        t.eq(advice(fight({ chosen = { curse = "Curse of Weakness" }, targetDebuffs = { ["Curse of Weakness"] = 20 } })),
             "Corruption", "the kept curse on: the next dot")
        t.eq(advice(fight({ targetDebuffs = { ["Curse of Recklessness"] = 20 } })), "Corruption",
             "a curse of yours this pack does not list is on: no curse over it")
        local unread = snap(FIGHT)
        unread.targetDebuffs = nil
        local r = ns.Choose(unread, ns.Packs.WARLOCK)
        t.eq(r and r.spell, "Shadow Bolt", "your debuffs not read: no curse, no dot")
        local knows = {}
        for _, name in ipairs(ALL) do if name ~= "Curse of Weakness" then knows[#knows + 1] = name end end
        t.eq(advice(fight({ chosen = { curse = "Curse of Weakness" } }), knows), "Curse of Agony",
             "kept, not known: Curse of Agony")
        t.eq(rowsByKey().curse.pick(snap(fight({ chosen = { curse = "Curse of Weakness" } }))), "Curse of Weakness",
             "PC-1: the pick is the kept curse")
    end,
}
