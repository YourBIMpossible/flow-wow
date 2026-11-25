local _, ns = ...

-- E-49 end to end: the whole add-on on a fake client; at a merchant,
-- `<slash> buyback` shows each price short ("1.36g"). Made-up items; not
-- tested in game.

local tests = {}

tests["money short: the buyback list through the add-on's boot reads short"] = function(t)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {}); c.setSaved(ns.id.charDB, {})
    ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(2, 10)
    c.setMoney(500000)
    c.setReturnable({
        { index = 1, name = "Bent Sword", price = 13552, count = 1 },
        { index = 2, name = "Old Shield", price = 552, count = 1 },
    })
    c.setMerchantOpen(true)
    local from = #(c.printed or {})
    c.slashes[ns.id.slash](ns.Buyback.WORD)
    local out = {}
    for i = from + 1, #(c.printed or {}) do out[#out + 1] = tostring(c.printed[i]) end
    t.eq(out[2], "1. Bent Sword: 1.36g to buy back", "gold reads short")
    t.eq(out[3], "2. Old Shield: 5.52s to buy back", "silver reads short")
end

return tests
