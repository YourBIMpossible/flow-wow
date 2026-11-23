-- UI/KitProbe.lua (lead section 292): the stock names the window kit would
-- like to use are asked once per login, out of combat, and what the client
-- said is kept in the saved diagnostics (the account table's diag.kitProbe),
-- where tools\zflow-read-diag.ps1 prints it. Through the real entry point
-- (KitProbe.Start on a kernel, the login events) over the fake client.
-- Fails before the module: ns.KitProbe is nil, so every test fails its
-- first check ("ns.KitProbe answers Start", got nil).
local _, ns = ...

local ANSWER = { templates = { SearchBoxTemplate = "present", BasicFrameTemplateWithInset = "no such template" },
    textures = { ["Interface\\MoneyFrame\\UI-GoldIcon"] = "unset" }, globals = { ITEM_QUALITY_COLORS = "table" } }

-- opts.combat: in combat at login. opts.raises: the probe raises.
-- opts.noProbe: a client with no such read.
local function start(t, opts)
    opts = opts or {}
    local P = ns.KitProbe
    local ok = type(P) == "table" and type(P.Start) == "function"
    t.ok(ok, "ns.KitProbe answers Start")
    if not ok then return nil end
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setKitProbe(ANSWER)
    local asked = { n = 0 }
    local plain = c.kitProbe
    function c.kitProbe()
        asked.n = asked.n + 1
        if opts.raises then error("probe-broke") end
        return plain()
    end
    if opts.noProbe then c.kitProbe = nil end
    if opts.combat then c.setCombat(true) end
    local k = ns.Kernel({}, c)
    ns.Diag.Start(k)
    P.Start(k)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return c, asked, k
end

local function kept(c)
    local diag = c.saved(ns.id.accountDB).diag
    if type(diag) ~= "table" then return nil end
    return diag.kitProbe
end

return {
    ["kit probe: asked once at login, and the answer is in the saved diagnostics"] = function(t)
        local c, asked, k = start(t)
        if c == nil then return end
        t.eq(asked.n, 1, "asked once")
        local row = kept(c)
        t.ok(type(row) == "table", "diag.kitProbe is saved")
        if type(row) ~= "table" then return end
        t.eq(row.result, ANSWER)
        t.eq(row.at, c.uptime())
        t.eq(type(row.build), "string", "with the client build it was read on")
        t.eq(row.reason, nil)
        c.fire("PLAYER_ENTERING_WORLD")
        c.setCombat(true)
        c.setCombat(false)
        t.eq(asked.n, 1, "a zone change or a later fight does not ask again")
        t.eq(k.problems:count("kitProbe"), 0, "no problem")
    end,

    ["kit probe: in combat at login it waits, and asks when the fight ends"] = function(t)
        local c, asked = start(t, { combat = true })
        if c == nil then return end
        t.eq(kept(c), nil, "nothing saved in combat")
        c.setCombat(false)
        local row = kept(c)
        t.ok(type(row) == "table", "saved once out of combat")
        if type(row) ~= "table" then return end
        t.eq(row.result, ANSWER)
        local n = asked.n
        c.setCombat(true)
        c.setCombat(false)
        t.eq(asked.n, n, "and not again after the next fight")
    end,

    ["kit probe: a probe that raises is kept as text and a problem, and not asked again"] = function(t)
        local c, asked, k = start(t, { raises = true })
        if c == nil then return end
        local row = kept(c)
        t.ok(type(row) == "table", "a row is saved")
        if type(row) ~= "table" then return end
        t.eq(row.result, nil)
        t.ok(type(row.reason) == "string" and row.reason:find("probe-broke", 1, true) ~= nil,
            "what it raised: " .. tostring(row.reason))
        t.eq(k.problems:count("kitProbe"), 1, "one problem")
        c.fire("PLAYER_ENTERING_WORLD")
        t.eq(asked.n, 1)
    end,

    ["kit probe: a client that cannot make frames, or has no such read, says so and stops"] = function(t)
        local c, asked = start(t)
        if c == nil then return end
        local c2 = start(t, { noProbe = true })
        t.eq(kept(c2), nil, "no read: nothing saved, nothing raised")
        local c3 = ns.make.fakeClient()
        c3.setSaved(ns.id.accountDB, {})
        c3.setKitProbe(nil, "noFrames")
        local k3 = ns.Kernel({}, c3)
        ns.KitProbe.Start(k3)
        k3:Boot()
        c3.fire("PLAYER_ENTERING_WORLD")
        local row = kept(c3)
        t.ok(type(row) == "table" and row.reason == "noFrames" and row.result == nil, "the reason is kept")
        t.eq(asked.n, 1)
    end,
}
