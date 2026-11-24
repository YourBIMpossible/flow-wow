# Third-party material

Flow is licensed under the GPLv3 (`LICENSE`). This file lists everything in the repository that
was made from someone else's work, with its licence notice. Anything not listed here is Flow's own.

## AllTheThings (MIT)

- **What is used:** which items each dungeon and raid boss can drop, as numbers only: instance id,
  area id, encounter id, creature id, item id. No name, description, comment or code.
- **Where:** `ZFlow/Nav/BossLootData.lua`, a generated file. Its header records the AllTheThings
  commit it was made from.
- **How it is made:** `tools/zflow-boss-loot.ps1 -Att <local checkout>` reads the instance files
  under `.contrib/.db/forever/dungeons & raids/` of a local checkout. The checkout itself is never
  committed here.
- **Source:** https://github.com/ATTWoWAddon/AllTheThings

Licence notice, as the MIT licence requires:

```
MIT License

Copyright (c) 2026 AllTheThings WoW Addon

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Not used

Read at runtime only when the player has them installed, never copied here: Questie and QuestieDB.
Never read and never copied: DungeonJournal and other "All Rights Reserved" journal add-ons, the
AtlasLoot forks, Wowhead and the Forever data sites.
