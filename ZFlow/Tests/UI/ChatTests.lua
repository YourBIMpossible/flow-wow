-- Chat links and chat text as plain text (N60a, UI/Chat.lua): the pure
-- part. Chat.Wrap finds the links a player typed and wraps each in this
-- add-on's own hyperlink; Chat.Plain turns a chat line into what a player
-- wants to paste. Made-up lines only; no client, no kernel.
-- Fails before: UI/Chat.lua is absent (ns.Chat is nil).
local _, ns = ...

local Chat = ns.Chat

local ITEM = "|cff1eff00|Hitem:2589::::::::10:::::|h[Linen Cloth]|h|r"
local PLAYER = "|Hplayer:Thrall-Realm:123:WHISPER|h[Thrall]|h"

local function has(t)
    local ok = type(Chat) == "table" and type(Chat.Wrap) == "function" and type(Chat.IsUrl) == "function"
        and type(Chat.Plain) == "function" and type(Chat.Prefix) == "function"
    t.ok(ok, "ns.Chat answers Wrap, IsUrl, Plain and Prefix")
    return ok
end

local function prefix() return Chat.Prefix(ns.id) end

-- The link this add-on writes for one address.
local function L(url)
    return "|H" .. prefix() .. ":" .. url .. "|h[" .. url .. "]|h"
end

return {
    ["chat links: the link is this add-on's own kind, named from the identity table"] = function(t)
        if not has(t) then return end
        t.eq(prefix(), "addon:" .. ns.id.addon .. ":url")
        t.eq(Chat.Link("http://example.com", prefix()), L("http://example.com"))
    end,

    ["chat links: what is an address"] = function(t)
        if not has(t) then return end
        for _, url in ipairs({
            "http://example.com", "https://example.com/a?b=c#d", "HTTPS://Example.com",
            "www.example.org", "www.example.pizza/menu", "wowhead.com/item=19019", "discord.gg/abcDEF",
            "twitch.tv", "10.0.0.5:8080", "192.168.1.20:27015/status", "sub.domain.example.net:8080/path",
        }) do
            t.eq(Chat.IsUrl(url), true, url)
        end
    end,

    ["chat links: what is not an address"] = function(t)
        if not has(t) then return end
        for _, word in ipairs({
            "hello", "e.g", "etc.", "v1.2.3", "1.5/2", "10.0.0.5", "999.1.1.1:80", "10.0.0.5:99999",
            "name@example.com", "Mr.Smith", "lol.what", "and/or", "http://", "a..b.com", "notes.txt", "www.",
            "www.example", "3.5k", "",
        }) do
            t.eq(Chat.IsUrl(word), false, word)
        end
        t.eq(Chat.IsUrl(nil), false)
        t.eq(Chat.IsUrl(7), false)
    end,

    ["chat links: an address in a line is wrapped, the rest of the line is as it was"] = function(t)
        if not has(t) then return end
        local text, n = Chat.Wrap("see http://example.com now", prefix())
        t.eq(text, "see " .. L("http://example.com") .. " now")
        t.eq(n, 1)
        text, n = Chat.Wrap("  two  spaces   wowhead.com/item=19019  ", prefix())
        t.eq(text, "  two  spaces   " .. L("wowhead.com/item=19019") .. "  ")
        t.eq(n, 1)
    end,

    ["chat links: the punctuation after an address is not part of it"] = function(t)
        if not has(t) then return end
        t.eq((Chat.Wrap("go to www.example.org.", prefix())), "go to " .. L("www.example.org") .. ".")
        t.eq((Chat.Wrap("(https://example.com/a),", prefix())), "(" .. L("https://example.com/a") .. "),")
        t.eq((Chat.Wrap("is it example.com?", prefix())), "is it " .. L("example.com") .. "?")
        t.eq((Chat.Wrap("\"twitch.tv/name\"!", prefix())), "\"" .. L("twitch.tv/name") .. "\"!")
        t.eq((Chat.Wrap("https://en.example.org/wiki/Foo_(bar)", prefix())), L("https://en.example.org/wiki/Foo_(bar)"),
            "a bracket the address opened stays in it")
    end,

    ["chat links: several addresses in one line are each wrapped"] = function(t)
        if not has(t) then return end
        local text, n = Chat.Wrap("a http://one.example.com b www.two.org, c 10.1.2.3:80", prefix())
        t.eq(text, "a " .. L("http://one.example.com") .. " b " .. L("www.two.org") .. ", c " .. L("10.1.2.3:80"))
        t.eq(n, 3)
    end,

    ["chat links: nothing inside a link that is already there is touched"] = function(t)
        if not has(t) then return end
        local other = "|Hurl:http://example.com|h[http://example.com]|h"
        local text, n = Chat.Wrap(other, prefix())
        t.eq(text, other, "another add-on's link")
        t.eq(n, 0)
        local once = Chat.Wrap("see www.example.org and example.com/x", prefix())
        local twice, again = Chat.Wrap(once, prefix())
        t.eq(twice, once, "a line wrapped once is not wrapped again")
        t.eq(again, 0)
    end,

    ["chat links: an item link and a player link are the same bytes afterwards"] = function(t)
        if not has(t) then return end
        local text, n = Chat.Wrap("wts " .. ITEM, prefix())
        t.eq(text, "wts " .. ITEM)
        t.eq(n, 0)
        text, n = Chat.Wrap("wts " .. ITEM .. " see wowhead.com/item=2589 " .. ITEM, prefix())
        t.eq(text, "wts " .. ITEM .. " see " .. L("wowhead.com/item=2589") .. " " .. ITEM)
        t.eq(n, 1)
        text, n = Chat.Wrap(PLAYER .. " says hi, mail bob@example.com", prefix())
        t.eq(text, PLAYER .. " says hi, mail bob@example.com")
        t.eq(n, 0)
    end,

    ["chat links: colour and picture codes around an address are kept"] = function(t)
        if not has(t) then return end
        t.eq((Chat.Wrap("|cff00ff00www.example.org|r", prefix())), "|cff00ff00" .. L("www.example.org") .. "|r")
        local picture = "|TInterface\\Icons\\site.example.org:16|t"
        t.eq((Chat.Wrap(picture .. " www.example.org", prefix())), picture .. " " .. L("www.example.org"))
        t.eq((Chat.Wrap("a||b www.example.org", prefix())), "a||b " .. L("www.example.org"))
        local open = "|Hfoo www.example.org"
        t.eq((Chat.Wrap(open, prefix())), open, "a link that never closes is left alone")
        t.eq((Chat.Wrap("www.example.org |", prefix())), L("www.example.org") .. " |")
    end,

    ["chat links: what is not text, and text with no address, comes back as given"] = function(t)
        if not has(t) then return end
        local text, n = Chat.Wrap(nil, prefix())
        t.eq(text, nil)
        t.eq(n, 0)
        text, n = Chat.Wrap("", prefix())
        t.eq(text, "")
        t.eq(n, 0)
        text, n = Chat.Wrap("no address here. none at all", prefix())
        t.eq(text, "no address here. none at all")
        t.eq(n, 0)
    end,

    ["chat plain: colours and pictures go, a link reads as the text it shows"] = function(t)
        if not has(t) then return end
        t.eq(Chat.Plain("|cff1eff00green|r text"), "green text")
        t.eq(Chat.Plain("wts " .. ITEM .. " 5s"), "wts [Linen Cloth] 5s")
        t.eq(Chat.Plain(PLAYER .. ": hello |A:atlas:16:16|a"), "[Thrall]: hello ")
        t.eq(Chat.Plain("|TInterface\\Icons\\x:16|t hi"), " hi")
        t.eq(Chat.Plain("plain line"), "plain line")
        t.eq(Chat.Plain(nil), "")
    end,

    ["chat plain: a doubled bar is one bar, and what follows it is text"] = function(t)
        if not has(t) then return end
        t.eq(Chat.Plain("a||b"), "a|b")
        t.eq(Chat.Plain("||cff00ff00"), "|cff00ff00")
        t.eq(Chat.Plain("one|ntwo"), "one\ntwo")
    end,

    ["chat plain: this add-on's own link reads as the address alone"] = function(t)
        if not has(t) then return end
        local line = Chat.Wrap("see www.example.org now", prefix())
        t.eq(Chat.Plain(line, prefix()), "see www.example.org now")
    end,
}
