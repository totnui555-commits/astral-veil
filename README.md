# ASTRAL VEIL: The Summoned Thirty

An original top-down fantasy party Action RPG built with **Godot 4.7.2**, GDScript, and the Compatibility renderer. Thai and English interfaces are included.

## Play from source

1. Clone or download this repository.
2. Install Godot 4.7.2 (standard edition).
3. Import `game/project.godot`, allow asset import to finish, and press **F6/F5** to run the scene/project.

The repository includes the editable game, character/environment art, audio, story data, and native regression scripts. Generated engine caches, personal saves, credentials, large QA galleries, historical checkpoints, and compiled downloads are excluded.

## Controls

WASD/arrows move; J attack; K heavy attack; Q skill; R ultimate; Space dodge; E interact; Tab or 1–3 switch hero; H potion.
C opens party, I inventory, L journal, M map, F tactics, and Escape pauses.
Touch controls are available on touch devices and can be enabled in Settings.

## Current content

- A royal summoning opening, safe forest arrival, and Hearthwell town.
- Three-act progression, twelve campaign maps, seven bosses, and two ending choices.
- Party switching, tactical pause/relay mechanics, equipment, crafting, item drops, quests, save/load, wardrobe, and optional activities.
- Illustrated portraits, four-direction character animation packages, and the latest combat/menu UI work.

This is a work in progress. Automated campaign completion is not a claim of finished production quality or human-tested combat enjoyment. Physical mobile performance, simultaneous touch input, wider screen layouts, and remaining art/encounter polish still need review.

## Verification

Native suites live in `game/tests/`. For example, with Godot available on PATH:

```sh
godot --headless --path game --script res://tests/ui_flow_test.gd
godot --headless --path game --script res://tests/combat_test.gd
```

Export presets are included in `game/export_presets.cfg`; install matching Godot export templates before exporting. Web exports must be served over HTTP.

## Art and attribution

See `ART_BIBLE.md`, `CHARACTER_PRODUCTION_BIBLE.md`, `UI_STYLE_GUIDE.md`, and `THIRD_PARTY_NOTICES.txt`. Font license notices are included with the fonts. Original game art includes AI-assisted generated assets; do not assume this public repository grants reuse rights beyond any explicitly supplied licenses.

## Hosted version

The existing hosted game is https://astral-veil-action-rpg.traisorn-th.chatgpt.site .
It may require owner access and may lag this repository. Publishing source on GitHub does not automatically deploy a playable website.
