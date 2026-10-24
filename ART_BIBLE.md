> **2026-10-21 art pass:** All 35 non-lead characters have unified warm anime pixel-art turnarounds: expressive readable faces, bold clean contours, controlled colors, stepped fabric and metal highlights. Original four-view identity and costume concepts feed the existing 128px rig. Arun, Mei and Amara retain their approved lead sprite designs. The 35 matching high-resolution dialogue portraits retain their existing illustration pass; portrait-to-sprite cohesion remains to review. See [generation notes](asset_sources/full_cast/pixel_turnarounds/GENERATION_NOTES.md) and [current progress](PROGRESS.md). This style pass does not claim every costume ornament is pixel-identical across views.
>
> **Current status:** All 35 remaining cast turnarounds are now integrated as 128px in-game animations under the established AV-2 rig. The three opening heroes keep their approved sprite designs. The 35 dialogue portraits and face crops remain their existing illustrated sources; portrait rendering alignment is the next visual consistency task.

# ASTRAL VEIL art direction — AV-2 detailed actor pass

Admission date: 2026-10-14. Keep existing gameplay and campaign; this updates visual production requirements.

## Reference and camera

Teal/ivory/brass sanctuary materials, plum astral energy and amber lamp pools define the first region. Readable top-down action remains the camera model, with 1.25 gameplay zoom, stable ground anchors and unchanged combat warning footprints. Detailed painted source art replaces overly quantized hero pixels. Do not upscale a 64px sheet and describe it as higher source detail.

## Actor density and identities

Eight heroes now use 128px cells, unquantized source normalization, six articulated animation states and linear filtering. Their 1536×1536 atlases pack down/left on the left half and right/up on the right half; actor atlases remain at most 2048px per dimension (new hero sheets are 1536px). World draw scale is 0.60, anchor (64,116); body detail is larger than the previous 64px/0.9 treatment. Four directions must agree on head size, costume, weapon side and feet. Animation uses separated body/limb/weapon rigs; dedicated hand-authored motion remains a quality task.

Leila: navy braids, ivory/brass shield armor and teal tabard. Rafael: ash-blond hair, plum arcblade coat, brass rune brace. Hana: black bob, cream/moss archer coat, terracotta scarf and camera pouch. New portraits preserve these identities. Festival outfits change garment shapes and layers; their portraits switch with the selected costume. Arun/Mei/Amara/Sera/Ilyen are rebuilt from their original masters at the new density.

## Environments and scene composition

Hearthwell now covers 3200×1000 world units with a second market district, continuous walkable central road, twelve interactions, two roaming residents and peripheral landmarks. The older square is 800×500 artwork; the new district is 1200×750 artwork drawn across its 1600×1000 half. Keep architecture collision on the perimeter and central combat/navigation space calm. Bake shadows consistently down-right; local lantern glows supplement them. Some old pixel props remain below the new painted hero finish.

## Effects and story

Four original signature effect rows show amber blade crescents, violet/cyan astral nova, teal/gold aegis and celestial fracture. Each has anticipation/release/peak/fade cels with transparent packing margins. An isolated canvas material feathers local cell alpha to prevent rectangular haze; it never affects HUD/text. Preserve old poison green and frost blue effects; do not apply one purple nova to every class. Gameplay footprints remain authoritative. Cap presentation draws at 64 and use eight small fragments per signature effect.

Skyfall uses original cinematic illustration, slow image pan, letterboxing and existing dialogue controls. NPC conversations move the world camera toward the speaker. This is an illustrated in-game cutscene, with no voiced or full-motion cinema claim.

## Budget and acceptance

Runtime reference inventory is 52 PNGs / 148.166458 MiB RGBA8-equivalent. The 160 MiB inventory ceiling and 32 MiB Web PCK ceiling explicitly fund higher-density sheets for eight heroes, three complete costume variants, matching portraits, market art and cutscene. Full decoded inventory is not measured resident/peak memory. Actor texture caches evict identities no longer needed by the party/map; alternate costume textures load on use. Physical-device memory/frame-rate measurement remains open.

Eight technical hero packages are integrated; thirty remain on the old renderer. Four ordinary families and Warden retain their previous pixel packages; six later bosses and eight later maps require further work. No whole-game visual-completion claim is made. Native contracts plus actual exported UI/combat/cutscene captures are required for admission. Source masters and exact prompts live in asset_sources/living_city; rebuild with tools/build_living_city_art.py.
