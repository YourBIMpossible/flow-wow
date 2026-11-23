local _, ns = ...
-- Settings export and import as data (row N70, research item 12), on the
-- whole add-on loaded on a fake client, through its entry points: the slash
-- words (export settings, import settings) and the settings page's row
-- button. The player pastes through the fake's text entry, reads the
-- preview in the share window and presses its buttons. Per lead section
-- 236: an export read on one add-on and imported on another (a reload,
-- another character); garbage, an unknown key, a wrong type, an
-- out-of-range number, a too-long text; combat and a lock that is not read;
-- a store read that raises, then recovers; the preview is what the confirm
-- applies. Offline: the fake client's frames, not the game's. Made-up names.
local tests = {}

local NAMES = { name = "Zarkon", realm = "Stormrage", guild = "Knights of Zar" }

local function boot(opts)
    opts = opts or {}
    local c = ns.make.fakeClient({ env = {
        UnitName = function() return NAMES.name end,
        GetRealmName = function() return NAMES.realm end,
        GetGuildInfo = function() return NAMES.guild end,
        GetBuildInfo = function() return "1.16.1", "7777" end,
    } })
    c.setSaved(ns.id.accountDB, opts.account or {})
    c.setSaved(ns.id.charDB, opts.char or {})
    c.setVersion("0.1.0")
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

local function slash(c, rest) c.slashes[ns.id.slash](rest) end

local function window(c)
    for _, p in ipairs(c.rowPanels or {}) do
        if type(p.spec) == "table" and p.spec.name == ns.id.framePrefix .. "Share" then return p end
    end
    return nil
end

local function exportBox(c)
    for _, b in ipairs(c.copyBoxes or {}) do
        if type(b.spec) == "table" and b.spec.name == ns.id.framePrefix .. "ShareExport" then return b end
    end
    return nil
end

local function rowOf(p, key)
    for _, r in ipairs(p and p.rows or {}) do
        if r.key == key then return r end
    end
    return nil
end

local function hasInfo(p, text)
    for _, r in ipairs(p and p.rows or {}) do
        if r.kind == "info" and tostring(r.text):find(text, 1, true) then return true end
    end
    return false
end

local function printedHas(c, text)
    for _, line in ipairs(c.printed or {}) do
        if tostring(line):find(text, 1, true) then return true end
    end
    return false
end

local function ready(t, addon)
    local ok = type(addon.SettingsShare) == "table" and type(addon.settingsShare) == "table"
    t.ok(ok, "the add-on has the settings share module")
    return ok
end

-- The player exports with the slash words and reads the copy box.
local function exported(c)
    slash(c, "export settings")
    local b = exportBox(c)
    if not b or b.shown ~= true then return nil end
    return b.text
end

-- The player pastes text into the import box and presses Enter.
local function paste(c, text)
    slash(c, "import settings")
    local e = c.textEntries[#c.textEntries]
    if not e or e.shown ~= true then return false end
    return e.type(text)
end

-- Every plain value the add-on's settings hold now.
local function values(addon)
    local out = {}
    for row in addon.settings:each() do
        if row.type == "bool" or row.type == "number" or row.type == "choice" then
            out[row.key] = addon.settings:get(row.key)
        end
    end
    return out
end

-- The first row of a type the player can set now, not the share row itself.
local function pick(addon, kind, scope, skip)
    for row in addon.settings:each() do
        if row.type == kind and row.key ~= addon.SettingsShare.SETTING and row.key ~= skip
            and (scope == nil or row.scope == scope) and addon.settings:available(row.key)
            and (kind ~= "choice" or #row.choices >= 2) then
            return row
        end
    end
    return nil
end

local function otherChoice(row, now)
    for _, v in ipairs(row.choices) do
        if v ~= now then return v end
    end
    return nil
end

-- Entry points -----------------------------------------------------------------

-- Fails before: no UI/SettingsShare.lua: "export settings" falls to the
-- character export, "import settings" to the Flow report, no settings row.
tests["settings share: export settings, import settings and the settings row's button reach it; bare export is unchanged"] = function(t)
    local c, addon = boot()
    if not ready(t, addon) then return end
    local S = addon.SettingsShare

    local text = exported(c)
    t.ok(type(text) == "string" and text:sub(1, #S.HEADER) == S.HEADER, "export settings shows the text in the copy box")

    t.eq(paste(c, text), true, "import settings asks for the text in the text entry")
    local p = window(c)
    t.ok(p ~= nil and p.shown() == true, "the share window shows the preview")

    for _, word in ipairs({ "export", "import", "backup", "share", "profile", "copy" }) do
        local found = addon.SettingsPage.Search(addon, word)
        local hit = false
        for _, e in ipairs(found and found.results or {}) do
            if e.key == S.SETTING then hit = true end
        end
        t.ok(hit, "the settings search finds the row by: " .. word)
    end
    if p then p.close() end
    slash(c, "settings export")
    local row
    for _, r in ipairs(c.optionsRows() or {}) do
        if r.key == S.SETTING then row = r end
    end
    t.ok(row ~= nil, "the row is on the settings page")
    if row then
        t.eq({ row.kind, row.value, row.topic }, { "choice", "all", "advanced" }, "a choice, all, under Advanced")
        t.eq({ row.jumpKind, row.jump }, { "open", S.SETTING }, "with its own button")
        t.eq(c.optionsNav("open", row.jump), true)
        t.eq(window(c) and window(c).shown(), true, "the button opens the share window")
    end

    -- The character export (S25) still answers the bare word.
    local before = #c.printed
    slash(c, "export")
    local said = false
    for i = before + 1, #c.printed do
        if tostring(c.printed[i]):find("export: ", 1, true) and tostring(c.printed[i]):find("lines", 1, true) then said = true end
    end
    t.ok(said, "bare export still makes the character's lines")
end

-- Round trip (section 236: a reload, another character) -------------------------

-- Fails before: no module, no export.
tests["settings share 236: an export from one add-on imported on another gives the same values"] = function(t)
    local c, addon = boot()
    if not ready(t, addon) then return end
    local P = addon.SettingsPage
    local bool = pick(addon, "bool", "account")
    local charBool = pick(addon, "bool", "char")
    local num = pick(addon, "number")
    local choice = pick(addon, "choice")
    t.ok(bool and charBool and num and choice, "a row of each kind to change")
    if not (bool and charBool and num and choice) then return end
    t.eq(P.Set(addon, bool.key, not addon.settings:get(bool.key)), true)
    t.eq(P.Set(addon, charBool.key, not addon.settings:get(charBool.key)), true)
    local n = num.max
    if n == nil or n == addon.settings:get(num.key) then n = num.min end
    if n == nil then n = addon.settings:get(num.key) + 1 end
    t.eq(P.Set(addon, num.key, n), true)
    t.eq(P.Set(addon, choice.key, otherChoice(choice, addon.settings:get(choice.key))), true)
    local want = values(addon)
    local text = exported(c)
    t.ok(type(text) == "string", "the first add-on exports")
    if not text then return end

    -- Another character on a fresh add-on (nothing saved yet).
    local c2, other = boot()
    t.ok(values(other)[bool.key] ~= want[bool.key], "the second add-on starts elsewhere")
    t.eq(paste(c2, text), true)
    local p = window(c2)
    t.ok(p ~= nil and rowOf(p, "confirm") ~= nil and rowOf(p, "confirm").enabled ~= false, "the preview offers to apply")
    t.eq(values(other)[bool.key] == want[bool.key], false, "nothing is set before the confirm")
    t.eq(p and p.press("confirm"), true)
    t.eq(values(other), want, "every value is the same as on the first add-on")
    t.eq(exported(c2), text, "and its own export is the same text")
end

-- Bad input (section 236) ------------------------------------------------------

-- Fails before: no module.
tests["settings share 236: garbage, an unknown key, a wrong type, an out-of-range number and a too-long text"] = function(t)
    local c, addon = boot()
    if not ready(t, addon) then return end
    local S = addon.SettingsShare
    local start = values(addon)

    t.eq(paste(c, "hello there, this is not it"), true)
    t.eq(addon.settingsShare.preview(), nil, "garbage makes no preview")
    t.ok(hasInfo(window(c), S.NOT_EXPORT), "and says it is not an export")

    t.eq(paste(c, S.HEADER .. ";" .. string.rep("x", S.MAX_BYTES)), true)
    t.eq(addon.settingsShare.preview(), nil, "a too-long text is not read")
    t.ok(hasInfo(window(c), S.TOO_LONG), "and says it is too long")

    t.eq(paste(c, S.HEADER .. ";END:3"), true)
    t.eq(addon.settingsShare.preview(), nil, "a text whose count does not match is not read")
    t.ok(hasInfo(window(c), S.CUT_SHORT))

    local bool = pick(addon, "bool")
    local bool2 = pick(addon, "bool", nil, bool and bool.key)
    local num
    for row in addon.settings:each() do
        if row.type == "number" and row.max ~= nil and num == nil and addon.settings:available(row.key) then num = row end
    end
    t.ok(bool and bool2 and num, "rows to name")
    if not (bool and bool2 and num) then return end
    local flip = addon.settings:get(bool2.key) and "0" or "1"
    local text = table.concat({
        S.HEADER,
        "account:no.such.setting=bool:1",
        bool.scope .. ":" .. bool.key .. "=num:5",
        num.scope .. ":" .. num.key .. "=num:" .. tostring(num.max + 1),
        bool2.scope .. ":" .. bool2.key .. "=bool:" .. flip,
        "account:return(os.exit)",
        "END:5",
    }, ";")
    t.eq(paste(c, text), true)
    local plan = addon.settingsShare.preview()
    t.ok(plan ~= nil, "a good header and count make a preview")
    if not plan then return end
    t.eq(#plan.changes, 1, "one will change")
    t.eq(plan.changes[1] and plan.changes[1].key, bool2.key)
    t.eq(#plan.skipped, 4, "four skipped, each with its reason")
    local whys = {}
    for _, s in ipairs(plan.skipped) do whys[#whys + 1] = s.why end
    table.sort(whys)
    local wantWhys = { S.UNKNOWN, S.BAD_PART, "above the highest value allowed (" .. num.max .. ")", S.WRONG_TYPE .. "on or off" }
    table.sort(wantWhys)
    t.eq(whys, wantWhys)
    t.ok(hasInfo(window(c), "1 will change, 4 skipped"), "the preview counts both")
    t.eq(values(addon), start, "nothing changed before the confirm")
    t.eq(window(c).press("cancel"), true)
    t.eq(addon.settingsShare.preview(), nil, "cancel drops the preview")
    t.eq(values(addon), start, "and nothing changed")
end

-- Combat (section 236) ---------------------------------------------------------

-- Fails before: no module.
tests["settings share 236: import is refused in combat and while the lock is not read"] = function(t)
    local c, addon = boot()
    if not ready(t, addon) then return end
    local S = addon.SettingsShare
    local start = values(addon)
    local text = exported(c)
    local bool = pick(addon, "bool")
    if not (text and bool) then t.ok(false, "an export and a row") return end
    local flip = addon.settings:get(bool.key) and "0" or "1"
    local one = S.HEADER .. ";" .. bool.scope .. ":" .. bool.key .. "=bool:" .. flip .. ";END:1"

    c.setLockdown(true)
    t.eq(paste(c, one), false, "in combat no text entry is offered")
    t.ok(printedHas(c, S.LOCKED), "and it says why")
    c.setLockdown(nil)
    t.eq(paste(c, one), false, "with the lock not read, none either")
    t.ok(printedHas(c, S.LOCK_UNKNOWN))
    t.eq(addon.settingsShare.importText(one), nil, "the import itself refuses too")

    c.setLockdown(false)
    t.eq(paste(c, one), true)
    t.eq(#addon.settingsShare.preview().changes, 1)
    c.setLockdown(true)
    t.eq(window(c).press("confirm"), true)
    t.eq(values(addon), start, "a confirm in combat changes nothing")
    t.ok(addon.settingsShare.preview() ~= nil, "and the preview stays")
    c.setLockdown(nil)
    t.eq(window(c).press("confirm"), true)
    t.eq(values(addon), start, "nor while the lock is not read")
    c.setLockdown(false)
    t.eq(window(c).press("confirm"), true)
    t.eq(addon.settings:get(bool.key), flip == "1", "out of combat it applies")
end

-- A read that raises, then recovers (section 236) ---------------------------------

-- Fails before: no module.
tests["settings share 236: a store read that raises during export leaves the setting out, then the next export is whole"] = function(t)
    local c, addon = boot()
    if not ready(t, addon) then return end
    local whole = exported(c)
    t.ok(type(whole) == "string", "a whole export first")
    local real = addon.store.get
    local bad = pick(addon, "bool")
    addon.store.get = function(self, scope, path)
        if bad and path == "settings." .. bad.key then error("made-up read failure") end
        return real(self, scope, path)
    end
    local ran, part = pcall(exported, c)
    addon.store.get = real
    t.eq(ran, true, "the export does not raise")
    t.ok(type(part) == "string" and bad ~= nil and not part:find(":" .. bad.key .. "=", 1, true),
        "the setting that could not be read is left out")
    t.ok(printedHas(c, "1 could not be read"), "and the player is told")
    t.ok(#addon.problems:list(addon.SettingsShare.NAME) >= 1, "kept as a problem")
    t.eq(exported(c), whole, "the next export is whole again")
end

-- The preview is what the confirm applies (section 236) ---------------------------

-- Fails before: no module.
tests["settings share 236: the preview lists exactly what the confirm applies"] = function(t)
    local c, addon = boot()
    if not ready(t, addon) then return end
    local c1, first = boot()
    local P = first.SettingsPage
    local a, b = pick(first, "bool"), pick(first, "number")
    if not (a and b) then t.ok(false, "rows") return end
    P.Set(first, a.key, not first.settings:get(a.key))
    local n = b.min
    if n == nil or n == first.settings:get(b.key) then n = b.max end
    P.Set(first, b.key, n)
    local text = exported(c1)
    local before = values(addon)
    t.eq(paste(c, text), true)
    local plan = addon.settingsShare.preview()
    t.ok(plan ~= nil and #plan.changes == 2, "two will change")
    if not plan then return end
    for _, ch in ipairs(plan.changes) do
        t.ok(hasInfo(window(c), ch.label), "the preview names " .. ch.key)
    end
    t.eq(values(addon), before, "nothing before the confirm")
    t.eq(window(c).press("confirm"), true)
    local after = values(addon)
    local changed = {}
    for key, v in pairs(after) do
        if before[key] ~= v then changed[key] = v end
    end
    local planned = {}
    for _, ch in ipairs(plan.changes) do planned[ch.key] = ch.to end
    t.eq(changed, planned, "what changed is exactly what the preview listed")
end

-- Privacy ------------------------------------------------------------------------

-- Fails before: no module.
tests["settings share privacy: names and GUIDs seeded in saved data never reach the export"] = function(t)
    local guid = "Player-4444-0ABCDEF1"
    local c, addon = boot({
        account = { learned = { places = { npcs = { { name = NAMES.name, realm = NAMES.realm } } } },
                    imports = { { source = NAMES.guild, who = guid } } },
        char = { state = { gearSets = { { name = NAMES.name .. " tank", items = { 1000 } } },
                           ownChoice = { seal = NAMES.realm } },
                 settings = { goals = { { name = NAMES.guild, guid = guid } } } },
    })
    if not ready(t, addon) then return end
    local S = addon.SettingsShare
    local text = exported(c)
    t.ok(type(text) == "string", "an export")
    if not text then return end
    for _, word in ipairs({ NAMES.name, NAMES.realm, "Knights", "Player-", "0ABCDEF1" }) do
        t.eq(text:find(word, 1, true), nil, word .. " is not in the export")
    end
    local odd = 0
    for part in text:gmatch("[^;]+") do
        if part ~= S.HEADER and not part:find("^END:%d+$")
            and not part:find("^%a+:[%w%._]+=%a+:[%w%._%%%-]*$") then odd = odd + 1 end
    end
    t.eq(odd, 0, "every part is the header, a setting or the end")
end

return tests
