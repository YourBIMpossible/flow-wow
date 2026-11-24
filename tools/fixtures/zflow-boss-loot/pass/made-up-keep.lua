-- Hand-written for the fixture check, in the form of an instance file. Every
-- number and word here is made up; nothing is taken from another add-on.
root(ROOTS.Instances, {
    expansion(EXPANSION.MADE_UP, {
        inst(9001, {
            zoneTextAreaID = 7001,
            description = "MADE UP PROSE THAT MUST NOT BE WRITTEN",
            groups = {
                n(QUESTS, {
                    q(4001, { groups = { i(900) } }),
                }),
                n(ZONE_DROPS, {
                    i(901),
                }),
                e(501, {
                    creatureID = 601,
                    groups = {
                        i(11),
                        i(12, { timeline = { TIMELINE.ADDED_1_50_0 } }),
                        i(13, { timeline = { TIMELINE.ADDED_1_50_0, TIMELINE.REMOVED_1_55_0 } }),
                        i(14, { timeline = { TIMELINE.ADDED_9_0_0 } }),
                        i(15, { timeline = { "no version here" } }),
                        i(11),
                    },
                }),
                n(602, {
                    groups = { i(21), i(22) },
                }),
                n(603, {}),
                e(502, {
                    crs = { 604, 605 },
                }),
            },
        }),
    }),
})
