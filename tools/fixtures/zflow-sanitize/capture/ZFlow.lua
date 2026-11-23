
ZFlowDB = {
["schema"] = 1,
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
},
},
},
["learned"] = {
["prices"] = {
["vendor"] = {
[2589] = {
["value"] = 13,
["basis"] = "vendor",
["source"] = "merchant",
},
},
["auction"] = {
["Mossvale-Alliance"] = {
[2589] = {
["value"] = 120,
["basis"] = "seen",
["source"] = "auction",
},
},
},
["auctionHistory"] = {
["Cinder-Reach-Horde"] = {
[2589] = {
["h"] = {
1700000000, -- [1]
115, -- [2]
},
},
},
},
},
["fights"] = {
["deaths"] = {
"3|Aldwynne|DRUID|12|Elwynn Forest|died after 20 s fighting Brannoch (level 14, you 12) || low health", -- [1]
},
},
},
["imports"] = {
{
["source"] = "Flow",
["sourceVersion"] = "2.4",
["dropped"] = {
{
["key"] = "ah.prices.Cinder-Reach - Horde",
["why"] = "shape",
["reason"] = "not a price table",
}, -- [1]
},
["adjusted"] = {
{
["key"] = "ah.prices.cinder reach - Alliance",
["from"] = {
["Mossvale"] = 3,
},
["to"] = {
["value"] = 3,
},
["reason"] = "kept the price of Mossvale",
}, -- [1]
},
}, -- [1]
},
["diag"] = {
["starts"] = 7,
["count"] = 31,
["names"] = {
["build"] = "1.16.1 (7777)",
["names"] = {
["GetMoney"] = "function",
},
},
["api"] = {
["namespaces"] = {
["C_Map"] = false,
},
["globals"] = {
["Realm"] = {
"Mossvale_Settings", -- [1]
},
},
},
["snaps"] = {
{
["why"] = "login",
["at"] = 12.5,
["reads"] = {
["money"] = 987654,
["position"] = {
["x"] = 0.4321,
["y"] = 0.8765,
["map"] = 1411,
},
},
["shapes"] = {
["realm"] = {
["ok"] = true,
["n"] = 1,
["types"] = {
"string", -- [1]
},
["values"] = {
["v1"] = "Mossvale",
},
},
["fullName"] = {
["ok"] = true,
["n"] = 2,
["types"] = {
"string", -- [1]
"string", -- [2]
},
["values"] = {
["v1"] = "Aldwynne",
["v2"] = "Mossvale",
},
},
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
{
["kind"] = "diag",
["owner"] = "kernel",
["text"] = "whisper from Brannoch not read",
["count"] = 1,
}, -- [1]
},
},
["timing"] = {
["order"] = {
"ADDON_LOADED", -- [1]
},
["fileLoad"] = {
["at"] = 5.5,
["accountData"] = false,
["charData"] = false,
["phase"] = "loading",
},
["ADDON_LOADED"] = {
["at"] = 5.75,
["accountData"] = true,
["charData"] = true,
["phase"] = "loading",
},
["start"] = 6,
["character"] = "Aldwynne",
["realm"] = "Mossvale",
["errors"] = {
{
["text"] = "Interface/AddOns/Other/x.lua:3: Aldwynne-Mossvale has no guild",
["count"] = 2,
["at"] = 14.25,
["phase"] = "started",
["ours"] = false,
}, -- [1]
},
},
}, -- [1]
},
},
}
