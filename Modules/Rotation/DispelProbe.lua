-- /flow dispelprobe: can this client tell us a debuff's type (Magic, Curse,
-- Poison, Disease) for a group member, and does that still work in a fight?
-- A Decursive-style cure bar only works if the answer is yes in combat.
--   /flow dispelprobe          read everyone now and print what the game gave back
--   /flow dispelprobe combat   do the same 4 seconds after the next fight starts
-- Each run is kept in the saved diagnostics (ns.db.dispelProbe) so it can be
-- read after a /reload. Nothing here touches secure frames or casts.

local _, ns = ...
local P = {}
ns.dispelProbe = P

-- A value as text: "SECRET" when the game hides it (reading it would error).
function P.Describe(v)
    if v == nil then return "nil" end
    if issecretvalue and issecretvalue(v) then return "SECRET" end
    if v == "" then return "(empty)" end
    return tostring(v)
end

local function try(fn, ...)
    local ok, a = pcall(fn, ...)
    if ok then return a end
    return nil
end

-- What the game says about one unit's harmful auras.
-- Returns lines (text) and counts { auras, typed, hidden }.
function P.Unit(unit)
    local lines, count = {}, { auras = 0, typed = 0, hidden = 0 }
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then
        lines[1] = "  no C_UnitAuras.GetAuraDataByIndex on this client"
        return lines, count
    end
    for i = 1, 40 do
        local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, "HARMFUL")
        if not ok then lines[#lines + 1] = "  aura read failed (blocked from addons)"; count.failed = true; break end
        if not a then break end
        count.auras = count.auras + 1
        local kind = try(function() return a.dispelName end)
        local name = try(function() return a.name end)
        local k = P.Describe(kind)
        if k == "SECRET" then count.hidden = count.hidden + 1
        elseif k ~= "nil" and k ~= "(empty)" then count.typed = count.typed + 1 end
        if count.auras <= 6 then
            lines[#lines + 1] = string.format("  debuff %d: name=%s type=%s", i, P.Describe(name), k)
        end
    end
    return lines, count
end

local function unitList()
    local list = { "player" }
    if IsInRaid and IsInRaid() then
        for i = 1, 40 do list[#list + 1] = "raid" .. i end
    else
        for i = 1, 4 do list[#list + 1] = "party" .. i end
    end
    list[#list + 1] = "target"
    return list
end

function P.Run()
    local inFight = InCombatLockdown() and true or false
    local out = {
        string.format("dispel probe: in a fight=%s, client hides some values=%s",
            tostring(inFight), tostring(issecretvalue ~= nil)),
    }
    local api = {}
    for _, f in ipairs({ "GetAuraDataByIndex", "GetUnitAuras", "GetAuraDispelTypeColor", "GetAuraDataBySpellName" }) do
        api[#api + 1] = f .. "=" .. tostring(C_UnitAuras ~= nil and C_UnitAuras[f] ~= nil)
    end
    out[#out + 1] = "  C_UnitAuras: " .. table.concat(api, " ")
    local seen, total = 0, { auras = 0, typed = 0, hidden = 0 }
    for _, unit in ipairs(unitList()) do
        if UnitExists and UnitExists(unit) then
            seen = seen + 1
            local lines, c = P.Unit(unit)
            total.auras, total.typed, total.hidden = total.auras + c.auras, total.typed + c.typed, total.hidden + c.hidden
            if c.auras > 0 or c.failed then
                out[#out + 1] = string.format("%s (%s): %d debuffs, %d typed, %d hidden", unit,
                    P.Describe(try(UnitName, unit)), c.auras, c.typed, c.hidden)
                for _, l in ipairs(lines) do out[#out + 1] = l end
            end
        end
    end
    out[#out + 1] = string.format("units checked %d, debuffs %d, types readable %d, types hidden %d%s",
        seen, total.auras, total.typed, total.hidden,
        total.auras == 0 and "  (no debuffs on anyone: try again while someone has one)" or "")
    for _, l in ipairs(out) do ns:Print(l) end
    if ns.db then
        ns.db.dispelProbe = ns.db.dispelProbe or {}
        ns.db.dispelProbe[inFight and "fight" or "calm"] = out
    end
    return out
end

local armed = false
ns:On("PLAYER_REGEN_DISABLED", function()
    if not armed then return end
    armed = false
    if C_Timer and C_Timer.After then C_Timer.After(4, P.Run) end
end)

ns.commands.dispelprobe = function(arg)
    if (arg or ""):lower() == "combat" then
        armed = true
        ns:Print("dispel probe: will read your group 4 seconds into the next fight (have someone take a debuff).")
        return
    end
    P.Run()
end

ns:Register("test", "dispelprobe: describes hidden and missing values, reads a unit without error", function(t)
    t:eq(P.Describe(nil), "nil", "nothing is nil")
    t:eq(P.Describe(""), "(empty)", "an empty type is labelled")
    t:eq(P.Describe("Magic"), "Magic", "a type is shown as is")
    local ok, lines, count = pcall(P.Unit, "player")
    t:ok(ok, "reading yourself does not error")
    t:ok(ok and type(lines) == "table" and type(count) == "table", "gives lines and counts")
end)
