-- The window kit's login probe (lead section 292). The stock art the kit
-- would like to draw with (Kit.look.art: templates and texture paths) has
-- not been seen on this client, so the kit draws its fallbacks. This asks
-- the client once per login which of those names it has
-- (client.kitProbe, Core/Client.lua) and keeps the answer in the saved
-- diagnostics, where tools\zflow-read-diag.ps1 prints it:
--
--   <account saved table>.diag.kitProbe = {
--       at = uptime, build = the client build ("1.60.1 (16001)"),
--       result = { templates = { [name] = "present" | error text },
--                  textures = { [path] = what was read back | "unset" | error text },
--                  globals = { [name] = its type } },
--       reason = why there is no result ("noFrames", "noKit", or the error
--                text of a probe that raised) }
--
-- Once per login or reload: at the first PLAYER_ENTERING_WORLD. In combat
-- then, it waits and asks when the fight ends (PLAYER_REGEN_ENABLED), not
-- at the next login. Each answer replaces the one saved before. The probe
-- runs under pcall; one that raises is kept as its text and as a problem,
-- and is not asked again this login. LOOK ONLY: nothing is shown.
--
--   KitProbe.Start(k) -> { done = fn -> true once it has asked }
local _, ns = ...

local P = ns.KitProbe or {}
ns.KitProbe = P

P.KIND = "kitProbe"

local function save(k, result, reason)
    local client = k.client
    local db = client.saved(k.id.accountDB)
    if type(db) ~= "table" then return end
    if type(db.diag) ~= "table" then db.diag = {} end
    local build
    if type(ns.Diag) == "table" and type(ns.Diag.BuildKey) == "function" then build = ns.Diag.BuildKey(client) end
    db.diag.kitProbe = { at = client.uptime(), build = build, result = result, reason = reason }
end

function P.Start(k)
    local client = k.client
    local done, cancel = false, nil

    local function try()
        if done then return end
        if type(client.kitProbe) ~= "function" then
            done = true
            return
        end
        local ok, result, reason = pcall(client.kitProbe)
        if ok and result == nil and reason == "combat" then
            -- Not in a fight: asked again when this one ends.
            if cancel == nil then cancel = client.listen("PLAYER_REGEN_ENABLED", try) end
            return
        end
        done = true
        if cancel ~= nil then
            cancel()
            cancel = nil
        end
        if not ok then
            reason = tostring(result)
            result = nil
            k.problems:add(P.KIND, "probe", reason)
        elseif type(result) ~= "table" then
            result = nil
            reason = tostring(reason)
        else
            reason = nil
        end
        local okSave, err = pcall(save, k, result, reason)
        if not okSave then k.problems:add(P.KIND, "save", err) end
    end

    client.listen("PLAYER_ENTERING_WORLD", try)
    return { done = function() return done end }
end

-- The addon's own: asked at this login.
ns.kitProbe = P.Start(ns)
