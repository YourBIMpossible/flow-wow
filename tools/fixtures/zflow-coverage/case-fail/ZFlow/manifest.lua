-- Fixture manifest. A comment naming "Core/Old.lua" is not a manifest line.
return {
    interface = 16001,
    files = {
        "core/a.lua",
        { "Core/Fake.lua", dev = true },
    },
}
