-- S3 slices 2 and 3 (lead section 181, Plexy RESEARCH-posting.md):
--   slice 2  the auction advice on an item tooltip, setting auction.postAdvice
--   slice 3  sold and expired counts from CHAT_MSG_SYSTEM, through the
--            client.onSystemMessage and client.auctionOutcome reads; a count
--            is a floor ("at least"): the line is not seen in every fight
-- Advice only: nothing posts, cancels, buys or moves items. Fake client and a
-- hand-built environment only; not tested in game. The game texts below are
-- made up for the tests, not the game's own.
local _, ns = ...

local Po, AL = ns.Posting, ns.AuctionLog
local tests = {}
local HOUR = 3600
local REALM = "Old Blanchy-Horde"
local SOLD, EXPIRED = "Sold: %s.", "%s did not sell."
local GOLD = { r = 1, g = 0.82, b = 0 }

local INFO = {
    [2589] = { name = "Linen Cloth", quality = 1, sellPrice = 13, classID = 7 },
    [858] = { name = "Lesser Healing Potion", quality = 1, sellPrice = 20, classID = 0 },
    [4306] = { name = "Silk Cloth", quality = 1, sellPrice = 150, classID = 7 },
    [2592] = { name = "Wool Cloth", quality = 1, sellPrice = 33, classID = 7 },
    [3001] = { name = "Same Name", quality = 1, sellPrice = 10, classID = 7 },
    [3002] = { name = "Same Name", quality = 1, sellPrice = 10, classID = 7 },
}
local PRICES = {
    [2589] = { h = { 500, 400, 1000, 300 } },
    [858] = { h = { 1000, 120 } },
    [2592] = { h = { 1000, 900 } },
    [3001] = { h = { 1000, 900 } },
    [3002] = { h = { 1000, 900 } },
}

local function copy(t)
    if type(t) ~= "table" then return t end
    local out = {}
    for key, v in pairs(t) do out[key] = copy(v) end
    return out
end

-- opts.log: AuctionLog is declared too; opts.texts = false: no game texts.
local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    c.setRealm("Old Blanchy")
    c.setFaction("Horde")
    c.setClock(1000 + HOUR)
    c.setItemInfo(INFO)
    c.setBagItems({ { item = 2589, count = 20 }, { item = 858, count = 5 }, { item = 4306, count = 3 } })
    if opts.texts ~= false then
        c.setGlobalText("ERR_AUCTION_SOLD_S", SOLD)
        c.setGlobalText("ERR_AUCTION_EXPIRED_S", EXPIRED)
    end
    local k = ns.Kernel({}, c)
    local d = ns.Diag.Start(k)
    if opts.log then AL.Declare(k, d) end
    local api = Po.Declare(k, d)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    k.store:set("account", AL.PATH .. "." .. REALM, copy(PRICES))
    return k, c, api
end

local function line(text) return { text = text, r = GOLD.r, g = GOLD.g, b = GOLD.b } end

local function unsold(k) return k.store:get("char", Po.UNSOLD) end

-- A hand-built game: CreateFrame, and send(event, ...) to play one event.
local function realEnv()
    local env = { frames = {} }
    function env.CreateFrame()
        local f = { scripts = {}, events = {} }
        function f:SetScript(script, fn) self.scripts[script] = fn end
        function f:RegisterEvent(name) self.events[name] = true end
        function f:UnregisterEvent(name) self.events[name] = nil end
        env.frames[#env.frames + 1] = f
        return f
    end
    local function send(name, ...)
        for _, f in ipairs(env.frames) do
            if f.events[name] and f.scripts.OnEvent then f.scripts.OnEvent(f, name, ...) end
        end
    end
    return env, send
end

-- ------------------------------------------------------------ slice 2, pure

tests["slice 2: the tooltip advice line, in the auction colour"] = function(t)
    local row = { id = 2589, each = 200, seen = 300, seenAt = 1000 }
    t.eq({ Po.TipLine(row, 1000 + HOUR) }, { "Auction: ask 2s each (1s under 3s, seen 1 h ago)", 1, 0.82, 0 })
    t.eq(Po.TipLine(row), "Auction: ask 2s each (1s under 3s)", "no time: no age")
    t.eq(Po.TipLine(row, 999), "Auction: ask 2s each (1s under 3s)", "a time before the look: no age")
    t.eq(Po.TipLine(row, 1000 + HOUR, 2), "Auction: ask 2s each (1s under 3s, seen 1 h ago) (unsold at least 2x)")
    t.eq(Po.TipLine(row, 1000 + HOUR, 0), "Auction: ask 2s each (1s under 3s, seen 1 h ago)", "none unsold: nothing said")
    t.eq(Po.TipLine(nil, 1000), nil)
    t.eq(Po.TipLine({ id = 1 }, 1000), nil, "no price: no line")
end

tests["slice 2: the setting and its names"] = function(t)
    t.eq(Po.SETTING, "auction.postAdvice")
    t.eq(Po.UNSOLD, "learned.auction.unsold")
    t.ok(type(Po.TIP_CACHE) == "number" and Po.TIP_CACHE > 0 and Po.TIP_CACHE <= 60, "a short cache")
end

-- ---------------------------------------------------------- slice 2, module

tests["slice 2: a listed item gets the advice on its tooltip"] = function(t)
    local k, c = start()
    t.eq(k.settings:get(Po.SETTING), true, "on by default")
    t.eq(c.showItemTooltip(2589), { line("Auction: ask 2s each (1s under 3s, seen 1 h ago)") })
end

tests["slice 2: an unlisted, an unpriced or an absent item gets no line"] = function(t)
    local _, c = start()
    t.eq(c.showItemTooltip(858), {}, "priced, but not worth the auction house")
    t.eq(c.showItemTooltip(4306), {}, "in the bags, no price seen")
    t.eq(c.showItemTooltip(2592), {}, "priced, not in the bags")
    t.eq(c.showItemTooltip(nil), {})
end

tests["slice 2: with the setting off there is no line"] = function(t)
    local k, c = start()
    t.eq(k.settings:set(Po.SETTING, false), true)
    t.eq(c.showItemTooltip(2589), {})
    t.eq(k.settings:set(Po.SETTING, true), true)
    t.eq(#c.showItemTooltip(2589), 1, "on again")
end

tests["slice 2: the list is made once for a run of tooltips, again after the cache"] = function(t)
    local _, c, api = start()
    c.showItemTooltip(2589)
    c.showItemTooltip(858)
    c.showItemTooltip(2589)
    t.eq(api.tipBuilds(), 1, "one build for three tooltips")
    c.setBagItems({})
    t.eq(#c.showItemTooltip(2589), 1, "inside the cache the list stands")
    c.setClock(1000 + HOUR + Po.TIP_CACHE + 1)
    t.eq(c.showItemTooltip(2589), {}, "after the cache the bags are read again")
    t.eq(api.tipBuilds(), 2)
end

tests["slice 2: no advice line says the addon posts, buys or cancels"] = function(t)
    local _, c = start()
    local shown = c.showItemTooltip(2589)
    t.eq(#shown, 1)
    for _, l in ipairs(shown) do
        local low = l.text:lower()
        t.ok(not low:find("will post", 1, true) and not low:find("buy", 1, true)
            and not low:find("cancel", 1, true), l.text)
    end
end

-- ------------------------------------------------------- slice 3, the client

tests["slice 3: the real client reads sold and expired from the game texts"] = function(t)
    local env = realEnv()
    env.ERR_AUCTION_SOLD_S = SOLD
    env.ERR_AUCTION_EXPIRED_S = EXPIRED
    local c = ns.make.client(env)
    t.eq({ c.auctionOutcome("Sold: Linen Cloth.") }, { "sold", "Linen Cloth" })
    t.eq({ c.auctionOutcome("Linen Cloth did not sell.") }, { "expired", "Linen Cloth" })
    t.eq(c.auctionOutcome("You feel rested."), nil)
    t.eq(c.auctionOutcome(""), nil)
    t.eq(c.auctionOutcome(7), nil)
    t.eq(c.globalText("ERR_AUCTION_SOLD_S"), SOLD)
    t.eq(c.globalText("NOT_A_TEXT"), nil)
end

tests["slice 3: the numbered form, and a name with pattern characters"] = function(t)
    local env = realEnv()
    env.ERR_AUCTION_SOLD_S = "%1$s: sold (100%)."
    env.ERR_AUCTION_EXPIRED_S = "Back [%1$s]"
    local c = ns.make.client(env)
    local name = "Gnomish [X%]-Ray (Mk. 2)+*?^$"
    t.eq({ c.auctionOutcome(name .. ": sold (100%).") }, { "sold", name })
    t.eq({ c.auctionOutcome("Back [" .. name .. "]") }, { "expired", name })
    t.eq(c.auctionOutcome(name .. ": sold (100x)."), nil, "the text must match whole")
end

tests["slice 3: a client without the texts, or with odd ones, answers nil"] = function(t)
    local env = realEnv()
    local c = ns.make.client(env)
    t.eq(c.auctionOutcome("Sold: Linen Cloth."), nil)
    t.eq(c.globalText("ERR_AUCTION_SOLD_S"), nil)
    env.ERR_AUCTION_SOLD_S = 5
    env.ERR_AUCTION_EXPIRED_S = ""
    t.eq(c.globalText("ERR_AUCTION_SOLD_S"), nil, "not a string")
    t.eq(c.globalText("ERR_AUCTION_EXPIRED_S"), nil, "empty")
    t.eq(c.auctionOutcome("Sold: Linen Cloth."), nil)
    env.ERR_AUCTION_SOLD_S = "%s sold %d"
    t.eq(c.auctionOutcome("Linen Cloth sold 3"), nil, "a text with a count is not the one read")
end

tests["slice 3: a hidden text or line is not read"] = function(t)
    local env, send = realEnv()
    env.ERR_AUCTION_SOLD_S = SOLD
    env.issecretvalue = function(v) return v == "SECRET" end
    local c = ns.make.client(env)
    local got = {}
    local cancel = c.onSystemMessage(function(text) got[#got + 1] = text end)
    t.eq(type(cancel), "function")
    send("CHAT_MSG_SYSTEM", "SECRET")
    send("CHAT_MSG_SYSTEM", 42)
    send("CHAT_MSG_SYSTEM", "Sold: Linen Cloth.")
    t.eq(got, { "Sold: Linen Cloth." }, "a hidden or non-text line is dropped before the listener")
    t.eq(c.auctionOutcome("SECRET"), nil)
    env.ERR_AUCTION_SOLD_S = "SECRET"
    t.eq(c.globalText("ERR_AUCTION_SOLD_S"), nil, "a hidden text is not known")
    cancel()
    send("CHAT_MSG_SYSTEM", "Sold: Linen Cloth.")
    t.eq(#got, 1, "taken back")
end

tests["slice 3: a real listener that raises does not stop the others"] = function(t)
    local env, send = realEnv()
    local c = ns.make.client(env)
    local got = {}
    c.onSystemMessage(function() error("listener boom") end)
    c.onSystemMessage(function(text) got[#got + 1] = text end)
    t.ok(pcall(send, "CHAT_MSG_SYSTEM", "one"), "the event does not raise")
    t.eq(got, { "one" })
    t.eq(c.onSystemMessage("not a function"), nil)
end

tests["slice 3: the fake client plays system lines and the texts"] = function(t)
    local c = ns.make.fakeClient()
    t.eq(c.globalText("ERR_AUCTION_SOLD_S"), nil)
    t.eq(c.auctionOutcome("Sold: Linen Cloth."), nil, "no texts set")
    c.setGlobalText("ERR_AUCTION_SOLD_S", SOLD)
    c.setGlobalText("ERR_AUCTION_EXPIRED_S", EXPIRED)
    t.eq(c.globalText("ERR_AUCTION_SOLD_S"), SOLD)
    t.eq({ c.auctionOutcome("Sold: A (b) %c.") }, { "sold", "A (b) %c" })
    t.eq({ c.auctionOutcome("Linen Cloth did not sell.") }, { "expired", "Linen Cloth" })
    local got = {}
    c.onSystemMessage(function() error("listener boom") end)
    local cancel = c.onSystemMessage(function(text) got[#got + 1] = text end)
    t.ok(pcall(c.systemMessage, "one"), "a listener error stays in the fake")
    c.systemMessage(42)
    t.eq(got, { "one" }, "a non-text line is dropped")
    cancel()
    c.systemMessage("two")
    t.eq(got, { "one" })
end

-- ----------------------------------------------------------- slice 3, counts

tests["slice 3: a sale clears the unsold count, as legacy did"] = function(t)
    t.eq(Po.Note(nil, "expired"), { expired = 1, sold = 0 })
    t.eq(Po.Note({ expired = 1, sold = 0 }, "expired"), { expired = 2, sold = 0 })
    t.eq(Po.Note({ expired = 3, sold = 1 }, "sold"), { expired = 0, sold = 2 })
    t.eq(Po.Note({ expired = 3, sold = 1 }, "other"), nil, "not an outcome: nothing to save")
    t.eq(Po.Note("odd", "sold"), { expired = 0, sold = 1 })
end

tests["slice 3: expired lines are counted and shown as a floor"] = function(t)
    local k, c = start()
    c.systemMessage("Linen Cloth did not sell.")
    c.systemMessage("Linen Cloth did not sell.")
    t.eq(unsold(k), { [2589] = { expired = 2, sold = 0 } })
    t.eq(c.showItemTooltip(2589),
        { line("Auction: ask 2s each (1s under 3s, seen 1 h ago) (unsold at least 2x)") })
    local before = #c.printed
    c.slashes[ns.id.slash]("auctions")
    t.eq(c.printed[before + 2], "20 x Linen Cloth: ask 2s each (seen 3s, 1 h ago; a vendor pays 13c; "
        .. "about +35s 40c over vendoring, the deposit not counted) (unsold at least 2x)")
end

tests["slice 3: a sale resets the count"] = function(t)
    local k, c = start()
    c.systemMessage("Linen Cloth did not sell.")
    c.systemMessage("Sold: Linen Cloth.")
    t.eq(unsold(k), { [2589] = { expired = 0, sold = 1 } })
    t.eq(c.showItemTooltip(2589), { line("Auction: ask 2s each (1s under 3s, seen 1 h ago)") })
end

tests["slice 3: an item gone from the bags is found by its seen price"] = function(t)
    local k, c = start()
    c.systemMessage("Wool Cloth did not sell.")
    t.eq(unsold(k), { [2592] = { expired = 1, sold = 0 } })
end

tests["slice 3: a name that matches nothing, or two things, is not saved"] = function(t)
    local k, c = start()
    c.systemMessage("Mystery Thing did not sell.")
    c.systemMessage("Same Name did not sell.")
    c.systemMessage("You feel rested.")
    t.eq(unsold(k), nil)
end

tests["slice 3: without the game texts nothing is counted"] = function(t)
    local k, c = start({ texts = false })
    c.systemMessage("Linen Cloth did not sell.")
    t.eq(unsold(k), nil)
end

-- ---------------------------------------------------------------- the probe

tests["slice 3: auction probe names the two game texts"] = function(t)
    local seen = {}
    for _, name in ipairs(AL.PROBE) do seen[name] = true end
    t.ok(seen.ERR_AUCTION_SOLD_S and seen.ERR_AUCTION_EXPIRED_S, "both in the probe")
    local _, c = start({ log = true, texts = false })
    c.setGlobalText("ERR_AUCTION_SOLD_S", SOLD)
    local before = #c.printed
    c.slashes[ns.id.slash]("auction probe")
    t.eq(c.printed[before + 1], ns.id.title .. ": auction probe: has ERR_AUCTION_SOLD_S")
    t.ok(tostring(c.printed[before + 2]):find("ERR_AUCTION_EXPIRED_S", 1, true) ~= nil, "the other is lacking")
end

return tests
