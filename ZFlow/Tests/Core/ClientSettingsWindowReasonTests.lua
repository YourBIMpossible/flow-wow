-- client.settingsWindow (Core/Client.lua and its fake): when the kit cannot
-- draw the window, page.draw answers false AND says why (Twin N2, lead
-- section 330), so the caller can list a problem with a reason.
-- Fails before: page.draw answers a bare false (why is nil).
local _, ns = ...

local K = ns.Kit

local function build()
    return K.Window({ id = "SettingsReason", title = "Settings", children = {} })
end

local tests = {}

tests["settings window: the real client says why it could not draw"] = function(t)
    -- A client with no CreateFrame: the kit draws nothing.
    local c = ns.make.client({ UIParent = {} })
    t.eq(type(c.settingsWindow), "function", "the client answers settingsWindow")
    if type(c.settingsWindow) ~= "function" then return end
    local page = c.settingsWindow({ id = "SettingsReason", build = build })
    t.ok(type(page) == "table", "a page")
    if type(page) ~= "table" then return end
    local ok, why = page.draw({}, nil, nil, {})
    t.eq(ok, false, "not drawn")
    t.ok(type(why) == "string" and why ~= "", "and says why: " .. tostring(why))
    local opened, whyOpen = page.open()
    t.eq(opened, false, "nothing to open")
    t.ok(type(whyOpen) == "string" and whyOpen ~= "", "and says why: " .. tostring(whyOpen))
end

tests["settings window: the fake says why it could not draw, as the real client does"] = function(t)
    local c = ns.make.fakeClient()
    if type(c.settingsWindow) ~= "function" then t.ok(false, "the fake answers settingsWindow") return end
    c.setKitFails(1)
    local page = c.settingsWindow({ id = "SettingsReason", build = build })
    t.ok(type(page) == "table", "a page")
    if type(page) ~= "table" then return end
    local ok, why = page.draw({}, nil, nil, {})
    t.eq(ok, false, "not drawn")
    t.ok(type(why) == "string" and why ~= "", "and says why: " .. tostring(why))
end

return tests
