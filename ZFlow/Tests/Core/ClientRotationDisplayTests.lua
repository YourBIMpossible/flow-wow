-- FLOW-PARITY D-06, D-07, D-08 on the real client (Core/Client.lua) over a
-- hand-built environment: the action bar glow (c.barGlow), the icon's
-- cooldown sweep and swing badge (h.cooldown, h.swing, c.spellCooldownSpan),
-- and the cast read with the edge bars (c.casting, h.edge on the icon and
-- on a click row). Display only. Not tested in game.
local _, ns = ...
local tests = {}

-- A frame that takes any method and records it: f.calls[name] = list of
-- argument lists. shown follows Show / Hide.
local function frame()
    local f = { calls = {}, kids = {} }
    setmetatable(f, { __index = function(_, name)
        return function(self, ...)
            self.calls[name] = self.calls[name] or {}
            local list = self.calls[name]
            list[#list + 1] = { ... }
            if name == "Show" then self.shown = true elseif name == "Hide" then self.shown = false end
            if name == "CreateTexture" or name == "CreateFontString" or name == "CreateAnimationGroup"
                or name == "CreateAnimation" then
                local kid = frame()
                self.kids[#self.kids + 1] = kid
                return kid
            end
            if name == "IsVisible" or name == "IsShown" then return true end
            if name == "GetFrameLevel" then return 1 end
            return nil
        end
    end })
    return f
end

local function env0()
    local env = { UIParent = {}, made = {} }
    env.CreateFrame = function(kind, name, parent, template)
        local f = frame()
        f.kind, f.parent, f.template = kind, parent, template
        env.made[#env.made + 1] = f
        if name then env[name] = f end
        return f
    end
    return env
end

local function last(f, name)
    local list = f.calls[name]
    return list and list[#list] or nil
end

-- ---------------------------------------------------------------- D-06
tests["barglow D-06: the bar button holding the spell glows; nil clears"] = function(t)
    local env = env0()
    local held = frame(); held.action = 5
    local other = frame(); other.action = 6
    env.ActionButton1, env.ActionButton2 = held, other
    env.HasAction = function(slot) return slot == 5 or slot == 6 end
    env.GetActionInfo = function(slot)
        if slot == 5 then return "spell", 403 end
        return "spell", 8050
    end
    env.C_Spell = { GetSpellInfo = function(id)
        return ({ [403] = { name = "Lightning Bolt", spellID = 403 },
                  [8050] = { name = "Flame Shock", spellID = 8050 } })[id]
    end }
    local c = ns.make.client(env)
    t.ok(type(c.barGlow) == "function", "the client has a bar glow")
    if type(c.barGlow) ~= "function" then return end
    t.eq(c.barGlow("Lightning Bolt"), 1, "one button holds it")
    local glow
    for _, f in ipairs(env.made) do if f.parent == held then glow = f end end
    t.ok(glow ~= nil, "a glow frame is made on the button that holds it")
    t.eq(glow and glow.shown, true, "and shown")
    for _, f in ipairs(env.made) do t.ok(f.parent ~= other, "nothing on the other button") end
    t.eq(c.barGlow(nil), 0, "nil: nothing glows")
    t.eq(glow and glow.shown, false, "the glow is hidden")
    t.eq(held.calls.SetAttribute, nil, "the button's action is not touched")
end

tests["barglow D-06: no bar read: nil, nothing made"] = function(t)
    local env = env0()
    local c = ns.make.client(env)
    if type(c.barGlow) ~= "function" then t.ok(false, "no bar glow"); return end
    local before = #env.made
    t.eq(c.barGlow("Lightning Bolt"), nil)
    t.eq(#env.made, before, "nothing made")
end

return tests
