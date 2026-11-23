local _, ns = ...
-- The info bar end to end (N59, lead section 243), on the whole add-on
-- loaded on a fake client. It is shown by default (lead section 294) and
-- off once the player turns it off (OFF below is that saved choice); it
-- shows four metrics, each updated from its own game event; a read the
-- client does not answer shows as not available; hover gives the details,
-- a click opens the settings page only. Per lead section 236: data arriving
-- late, unavailable reads, a reload in the middle, a setting changed while
-- shown, and a read that fails then recovers. Offline: the fake client
-- bar, not the game frame. Not tested in game. Made-up values only.
local tests = {}

local NEW_READS = { "xp", "watchedFaction", "gameTime", "framerate", "latency" }
local OWN_EVENTS = { "PLAYER_MONEY", "PLAYER_XP_UPDATE", "UPDATE_EXHAUSTION", "UPDATE_FACTION" }

-- opts: account, char (saved tables), before(c), count (wrap the new reads
-- to count each call in c.counted).
local function boot(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, opts.account or {})
    c.setSaved(ns.id.charDB, opts.char or {})
    c.setScreen(1024, 768)
    if opts.count then
        c.counted = {}
        for _, name in ipairs(NEW_READS) do
            local fn = c[name]
            if type(fn) == "function" then
                c[name] = function(...)
                    c.counted[name] = (c.counted[name] or 0) + 1
                    return fn(...)
                end
            end
        end
    end
    if opts.before then opts.before(c) end
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

local function reload(c, before)
    return boot({ account = c.saved(ns.id.accountDB), char = c.saved(ns.id.charDB), before = before })
end

local function bar(c) return type(c.infoBars) == "table" and c.infoBars[1] or nil end

local function text(c)
    local b = bar(c)
    return b and b.shown and b.text or nil
end

local function has(list, x)
    for _, v in ipairs(list or {}) do if v == x then return true end end
    return false
end

local function values(c)
    c.setMoney(12345)
    c.setBags({ { bag = 0, free = 4, total = 16 }, { bag = 1, free = 8, total = 20 } })
    c.setDurability({ [1] = { cur = 50, max = 100 } })
    c.setXp({ cur = 450, max = 1000, rested = 200 })
end

local function on(addon, key, value) return addon.settings:set(key, value) end

-- The saved choice of a player who turned the bar off.
local function off(metrics) return { settings = { infoBar = { shown = false, metrics = metrics } } } end

tests["info bar: turned off it shows nothing; turned on, the four default metrics"] = function(t)
    local c, addon = boot({ before = values, account = off() })
    t.eq(text(c), nil, "off as saved")
    t.ok(on(addon, "infoBar.shown", true), "the setting is there")
    t.eq(text(c), "1g 23s 45c  |  Bags 12  |  Dur 50%  |  XP 45%")
end

tests["info bar: a hidden bar reads nothing and listens to nothing of its own"] = function(t)
    local c, addon = boot({ before = values, count = true,
        account = off("gold xp rep clock fps latency hearth") })
    c.advance(30, 60)
    for _, name in ipairs(NEW_READS) do t.eq(c.counted[name], nil, name .. " not read") end
    for _, ev in ipairs(OWN_EVENTS) do t.ok(not has(c.events(), ev), ev .. " not listened to") end
    on(addon, "infoBar.shown", true)
    t.ok(has(c.events(), "PLAYER_XP_UPDATE"), "listened to once shown")
    on(addon, "infoBar.shown", false)
    for _, ev in ipairs(OWN_EVENTS) do t.ok(not has(c.events(), ev), ev .. " let go once hidden") end
    local before = c.counted.gameTime or 0
    c.advance(30, 60)
    t.eq(c.counted.gameTime or 0, before, "no slow timer once hidden")
    t.eq(bar(c).shown, false)
end

tests["info bar: each metric updates from its own event, not from a timer"] = function(t)
    local c, addon = boot({ before = values, count = true })
    on(addon, "infoBar.shown", true)
    local xpReads = c.counted.xp or 0
    c.advance(30, 60)
    t.eq(c.counted.xp or 0, xpReads, "experience is not polled")
    c.setMoney(7)
    c.fire("PLAYER_MONEY")
    t.eq(text(c), "7c  |  Bags 12  |  Dur 50%  |  XP 45%")
    c.setXp({ cur = 900, max = 1000, rested = 0 })
    c.fire("PLAYER_XP_UPDATE", "player")
    t.eq(text(c), "7c  |  Bags 12  |  Dur 50%  |  XP 90%")
    c.setBags({ { bag = 0, free = 1, total = 16 } })
    c.fire("BAG_UPDATE_DELAYED")
    t.eq(text(c), "7c  |  Bags 1  |  Dur 50%  |  XP 90%")
    c.setDurability({ [1] = { cur = 10, max = 100 } })
    c.fire("UPDATE_INVENTORY_DURABILITY")
    t.eq(text(c), "7c  |  Bags 1  |  Dur 10%  |  XP 90%")
end

tests["info bar: the clock and frame rate on a slow timer only while shown"] = function(t)
    local c, addon = boot({ account = { settings = { infoBar = { shown = true, metrics = "clock fps" } } } })
    c.setGameTime(14, 5)
    c.setFramerate(60)
    t.eq(text(c), "Clock n/a  |  FPS n/a", "not yet read")
    c.advance(5, 20)
    t.eq(text(c), "14:05  |  60 fps")
    c.setGameTime(14, 6)
    c.advance(5, 20)
    t.eq(text(c), "14:06  |  60 fps")
    on(addon, "infoBar.metrics", "gold")
    c.setGameTime(15, 0)
    c.advance(5, 20)
    t.ok(text(c) ~= nil and not text(c):find("15:00"), "no clock read once it is not chosen")
end

tests["info bar: a metric the client does not answer is not available, never zero"] = function(t)
    local c = boot({ account = { settings = { infoBar = { shown = true,
        metrics = "gold bags durability xp rep clock hearth fps latency" } } } })
    c.advance(5, 20)
    t.eq(text(c), "Gold n/a  |  Bags n/a  |  Dur n/a  |  XP n/a  |  Rep n/a  |  Clock n/a  |  Hearth n/a"
        .. "  |  FPS n/a  |  Latency n/a")
end

-- Section 236: data arriving late, and a read that fails then recovers.
tests["info bar: experience read late, and reputation that fails then recovers"] = function(t)
    local c = boot({ account = { settings = { infoBar = { shown = true, metrics = "xp rep" } } } })
    t.eq(text(c), "XP n/a  |  Rep n/a")
    c.setXp({ cur = 100, max = 400, rested = 0 })
    c.fire("PLAYER_XP_UPDATE", "player")
    t.eq(text(c), "XP 25%  |  Rep n/a")
    c.setWatchedFaction(false)
    c.fire("UPDATE_FACTION")
    t.eq(text(c), "XP 25%  |  Rep none")
    c.setWatchedFaction({ name = "Test Faction", standing = 4, label = "Neutral", min = 0, max = 3000, value = 1500 })
    c.fire("UPDATE_FACTION")
    t.eq(text(c), "XP 25%  |  Neutral 50%")
    c.setWatchedFaction(nil)
    c.fire("UPDATE_FACTION")
    t.eq(text(c), "XP 25%  |  Rep n/a", "unknown again: not the old value")
end

-- Section 236: a reload in the middle keeps place, size, layout and choice.
tests["info bar: a reload keeps the place, size, layout, look and metrics"] = function(t)
    local c, addon = boot({ before = values })
    on(addon, "infoBar.shown", true)
    on(addon, "infoBar.layout", "box")
    on(addon, "infoBar.metrics", "xp gold")
    on(addon, "infoBar.fontSize", 16)
    on(addon, "infoBar.opacity", 25)
    bar(c).drag({ "TOP", "TOP", 10, -40 })
    bar(c).resize(180, 50)
    local c2 = reload(c, values)
    local b = bar(c2)
    t.ok(b ~= nil and b.shown, "shown after the reload")
    if not b then return end
    t.eq(b.text, "XP 45%\n1g 23s 45c")
    t.eq(b.point, { "TOP", "TOP", 10, -40 })
    t.eq({ b.width, b.height }, { 180, 50 })
    t.eq(b.fontSize, 16)
    t.eq(b.alpha, 0.25)
end

tests["info bar: a setting changed while shown takes effect at once"] = function(t)
    local c, addon = boot({ before = values })
    on(addon, "infoBar.shown", true)
    on(addon, "infoBar.fontSize", 20)
    t.eq(bar(c).fontSize, 20)
    on(addon, "infoBar.opacity", 0)
    t.eq(bar(c).alpha, 0)
    on(addon, "infoBar.layout", "box")
    t.eq(text(c), "1g 23s 45c\nBags 12\nDur 50%\nXP 45%")
    on(addon, "infoBar.metrics", "bags")
    t.eq(text(c), "Bags 12")
end

tests["info bar: locked, it is neither moved nor resized"] = function(t)
    local c, addon = boot({ before = values })
    on(addon, "infoBar.shown", true)
    on(addon, "infoBar.locked", true)
    bar(c).drag({ "CENTER", "CENTER", 1, 1 })
    bar(c).resize(500, 90)
    local saved = addon.settings:get("infoBar.place")
    t.ok(type(saved) ~= "table" or saved.point == nil, "no place kept")
    on(addon, "infoBar.locked", false)
    bar(c).drag({ "CENTER", "CENTER", 1, 1 })
    t.eq(addon.settings:get("infoBar.place").point, { "CENTER", "CENTER", 1, 1 })
end

tests["info bar: hover gives the details, a click opens the settings page only"] = function(t)
    local c, addon = boot({ before = values })
    on(addon, "infoBar.shown", true)
    local b = bar(c)
    b.hover(true)
    t.eq(b.tipLines, { "Gold: 1g 23s 45c", "Free bag slots: 12 of 36", "Durability: 50% on the most worn item",
        "Experience: 450 / 1000 (45%), rested 200", ns.InfoBar.CLICK })
    b.hover(false)
    t.eq(b.tipLines, nil)
    local opened = c.optionsOpened()
    b.click("LeftButton")
    t.eq(c.optionsOpened(), opened + 1, "the settings page opened")
    -- Lead section 246: no Z-Flow button is given type macro.
    for _, sb in ipairs(c.secureButtons or {}) do
        t.ok(sb.attrs.type ~= "macro", "no secure button of type macro")
    end
end

tests["info bar: no frame from the client, no fault and nothing shown"] = function(t)
    local c, addon = boot({ before = function(x) values(x); x.setFrames(false) end })
    t.ok(on(addon, "infoBar.shown", true), "the setting still takes")
    t.eq(bar(c), nil)
    c.fire("PLAYER_MONEY")
    local faults = 0
    for _, p in ipairs(addon.problems:list()) do
        if p.kind == "infoBar" or p.owner == "infoBar" then faults = faults + 1 end
    end
    t.eq(faults, 0, "no fault")
end

return tests
