
ZFlowDB = {
["layout"] = {
["arrowIntroSeen"] = true,
["arrows"] = {
["mode"] = "separate",
["points"] = {
["quest"] = {
"CENTER", -- [1]
"CENTER", -- [2]
200, -- [3]
100, -- [4]
},
["prof"] = {
"CENTER", -- [1]
"CENTER", -- [2]
-300, -- [3]
-200, -- [4]
},
},
},
},
["diag"] = {
["starts"] = 7,
["sellGrey"] = {
["item"] = "Cracked Bone",
["rule"] = "not read",
["why"] = "price not read yet",
["counts"] = "to sell 0, kept 1, not sold 1, not read 0",
},
["count"] = 31,
["kitProbe"] = {
["at"] = 12.5,
["interface"] = "1.16.1 (7777)",
["rows"] = {
["T2"] = "works",
["T5"] = "Couldn't find inherited node: SearchBoxTemplate",
["G2"] = "nil",
["G6"] = "works (table)",
["X9"] = "made, not confirmed",
["EJ_LOADED"] = "no",
},
},
["names"] = {
["build"] = "1.16.1 (7777)",
["names"] = {
["GetMoney"] = "function",
["GetContainerNumSlots"] = "nil",
},
},
["api"] = {
["namespaces"] = {
["C_Map"] = false,
},
["globals"] = {
},
},
["snaps"] = {
{
["why"] = "login",
["at"] = 12.5,
["reads"] = {
["money"] = 987654,
["bags"] = 4,
["bagStacks"] = 61,
["position"] = {
["x"] = 0.4321,
["y"] = 0.8765,
["map"] = 1411,
},
},
["shapes"] = {
["build"] = {
["ok"] = true,
["n"] = 2,
["types"] = {
"string", -- [1]
"string", -- [2]
},
["values"] = {
["v1"] = "1.16.1",
["v2"] = "7777",
},
},
},
["kernel"] = {
["phase"] = "started",
["paused"] = false,
["problems"] = {
},
},
["timing"] = {
["start"] = 6,
["character"] = "Aldric",
["realm"] = "Testrealm",
["errors"] = {
{
["text"] = "Interface/AddOns/ZFlow/Core/Diag.lua:333: attempt to compare a secret number value",
["count"] = 3,
["at"] = 14,
["phase"] = "started",
["ours"] = true,
}, -- [1]
},
},
}, -- [1]
{
["why"] = "vendor",
["at"] = 80,
["reads"] = {
["money"] = 987111,
},
["shapes"] = {
["health"] = {
["ok"] = false,
["n"] = 1,
["types"] = {
"string", -- [1]
},
["values"] = {
["v1"] = "not a function",
},
},
["spellTabs"] = {
["ok"] = false,
["n"] = 1,
["types"] = {
"string", -- [1]
},
["values"] = {
["v1"] = "bad argument #1 to \"GetNumSpellTabs\"",
},
},
["level"] = {
["ok"] = true,
["n"] = 1,
["types"] = {
"number", -- [1]
},
["values"] = {
["v1"] = 23,
},
},
},
["kernel"] = {
["phase"] = "started",
["paused"] = true,
["pauseText"] = "Saved data is from a newer build.",
["problems"] = {
{
["kind"] = "diag",
["owner"] = "collect",
["text"] = "boom at line 5",
["count"] = 2,
}, -- [1]
},
},
["timing"] = {
["start"] = 6,
["character"] = "Aldric",
["realm"] = "Testrealm",
["errors"] = {
{
["text"] = "Interface/AddOns/ZFlow/Core/Diag.lua:333: attempt to compare a secret number value",
["count"] = 4,
["at"] = 14,
["phase"] = "started",
["ours"] = true,
}, -- [1]
{
["text"] = "Interface/AddOns/OtherAddon/Main.lua:10: nil value",
["count"] = 1,
["at"] = 70,
["phase"] = "started",
["ours"] = false,
}, -- [2]
},
},
}, -- [2]
{
["why"] = "login",
["at"] = 9,
["reads"] = {
["money"] = 555444,
},
["shapes"] = {
},
["kernel"] = {
["phase"] = "booted",
["paused"] = false,
["problems"] = {
},
},
["timing"] = {
["start"] = 7,
["character"] = "Brenna",
["realm"] = "Testrealm",
["errors"] = {
},
},
}, -- [3]
},
},
}
