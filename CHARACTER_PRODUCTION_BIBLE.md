> **2026-10-21 character art update:** The 35 non-lead heroes, recruits and town characters now use a shared anime-inspired pixel rendering direction in the current in-engine action atlases. Original four-view identities and class designs remain the source. Arun, Mei and Amara keep their approved sprites. The other 35 high-resolution portraits retain their illustrated rendering, so portrait/sprite pairing is the next art consistency review. See [generation notes](asset_sources/full_cast/pixel_turnarounds/GENERATION_NOTES.md).

The 35 revised turnarounds are integrated through `tools/build_full_cast.py`; the generated source masters live beside the preserved original painted masters. All 38 runtime atlases still expose idle, walk, attack, hit, cast and dodge actions in four directions. The shared articulated rig remains in use. Review the actual full-body directions and class cues in `qa/full-cast/all-38-sprites.png`; the three lead designs were not modified.

# Character production contract — AV-2

Every playable hero requires a matching illustrated portrait, four distinct directions, idle/walk/basic attack/hit/cast/dodge states, readable class silhouette and production integration. The target is detailed painted source art with 128px runtime cells, stable (64,116) feet and 0.60 world scale. Keep face/hair/skin/weapon/costume identity across directions and portrait. Class design must survive the normal gameplay camera.

Current eight technical packages: c01 Arun, c02 Leila, c03 Rafael, c04 Mei, c05 Hana, c07 Amara, n01 Sera, n02 Ilyen. Three new heroes join under the existing recruitment rules at stage 1, so they are selectable in the first town. They can be deployed through the normal party screen; no test-only character system exists.

Each package has 116 used action/direction frames. Sixteen atlases hold 1656 used frames including three costume variants and five enemy/boss packages. Poses are articulated from original four-view art; frame variation and bounds are checked, but this is not individually hand-painted animation. Do not count distinct frame hashes as proof of excellent motion.

Leila/Rafael/Hana have default and lantern-festival outfits, each with a complete action atlas and matching alternate portrait. Festival gear is unlocked by the market rune chest or music practice and selected at the tailor/party wardrobe. Appearance uses existing save flags and never changes armor stats. Remaining heroes do not yet have alternate outfits.

Acceptance: verify roster selection/deployment, each actual action, default/alternate portrait and sprite agreement, animation recovery, resource references, save/load, mobile readability and scene contrast. Next authored-motion work is shield anticipation, bow draw/release and sword follow-through. Thirty remaining packages follow FULL_CAST_ROLLOUT_PLAN.md.
