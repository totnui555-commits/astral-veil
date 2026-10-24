> **Current, 2026-10-18:** all 38 playable hero packages are integrated at AV-2 resolution; see `ROYAL_SUMMONING_AND_RELAY.md` and `qa/visual-standard-audit.json` for the current scope and limitations. Tactics sits below the party cards at (20,260); Relay feedback sits below the boss banner at (270,96). The new court and safe forest are playable. Remaining late bosses/environments are not certified complete. Prior counts below are historical.

# Current checkpoint — 2026-10-14

The current activity/wardrobe/cutscene layouts are specified in UI_PREMIUM_PASS.md. Music accepts Space on desktop or the on-screen button, uses a 2.4-second cycle and the bracketed timing window. NPC shots target the interacted NPC instance. Shared brass/teal typography remains; developer-facing activity keys must not appear as headings.

Earlier baseline below is historical and superseded where this checkpoint differs.

---

# ASTRAL VEIL — fantasy interface style guide

The interface uses nocturne leather, engraved brass and verdigris inlay. The visual slice combines this restrained material language with the original illustrated Arun, Mei and Amara portraits. The interface must make combat, dialogue and real inventory actions easier to read; ornament belongs at edges and never behind body text.

## Palette and typography

| Role | Color | Use |
| --- | --- | --- |
| Nocturne ink | `#081318` | Recesses and bar tracks |
| Deep verdigris | `#10262A` | Panel material |
| Ivory | `#F0EADB` | Primary text |
| Old gold | `#D9C396` | Screen titles, values and focus outlines |
| Sea glass | `#78D3BA` | Selection, magic and successful status |
| Sage grey | `#9EAFAA` | Secondary text |
| Ember coral | `#ED947E` | Damage and failure |

English display titles use Noto Serif. Body text uses Noto Sans with Noto Sans Thai and DejaVu fallback. Thai display titles retain the same size and gold hierarchy through Noto Sans Thai fallback. Body text is 16–18 reference pixels; explanatory card text is 14–15; dates and incidental counters may use 11–13. Do not use the small incidental size for actions, dialogue or combat resources.

## Screen geometry

The existing reference canvas remains 1152 × 648 with Godot `canvas_items` stretching. The menu shell occupies `(48, 32, 1056, 584)`, leaving a visible margin around the running scene. Its engraved nine-slice frame has 24-pixel content margins. The header uses a 34-pixel rune emblem, 25-pixel title, real currency balance and close action. Horizontal dividers use muted brass.

Controls created through `VeilUI.button` have a 56-pixel minimum height. At the verified 960 × 540 landscape browser size this corresponds to approximately 47 physical pixels. Larger roster rows use 68 pixels; inventory rows use 60. This keeps the principal action targets above 44 physical pixels at that size. Smaller screens require an additional responsive layout pass and are not certified by this rule alone.

Spacing follows an 8/12/16/24 system. Dense detail panes scroll rather than shrinking body text. Scroll containers follow keyboard focus, disable horizontal scrolling, and retain vertical access to allocation, equipment, crafting and save controls.

## Components

| Component | Integration | Rule |
| --- | --- | --- |
| Main engraved frame | `VeilUI.panel_style()` | Original 128 × 128 nine-slice; corners remain unscaled |
| Inset card | `VeilUI.card_style()` | Recessed material, simple inlay, 16-pixel padding |
| Button | `VeilUI.button_style(state)` | Original 128 × 64 material; normal/hover/pressed/selected/disabled states |
| Focus | Button theme | Two-pixel gold outline, independent from color-only hover |
| Screen heading | `VeilUI.heading()` | Serif English title with Thai font fallback |
| Illustrated face | `VeilUI.portrait()` | Shared atlas crop; linear filtering for the three upgraded heroes |
| Framed portrait | `VeilUI.framed_portrait()` | Original engraved portrait frame |
| Category emblem | `VeilUI.emblem()` | 64 × 64 original pictogram; class/material meaning rather than decoration alone |
| Bars | `VeilUI.bar()` | Solid high-contrast resource fill on an ink track |
| Slider thumb | HSlider theme | Original brass/sea-glass diamond, replacing the engine thumb |

Button text retains localized action names. Disabled buttons remain visibly distinct and cannot issue gameplay actions. Selection adds bright inlay and a verdigris surface; party deployment also retains its textual star. Inventory rarity colors augment the written rarity label rather than replacing it.

## Party and status screen

The selected hero illustration is the left focal point. Name, class and combat role remain adjacent to that matching portrait. A separate middle roster contains face crops, names, classes, recruited state and current party markers. The right pane contains actual level, XP, unspent points, derived statistics, six allocation controls, skill rank/upgrade, respec, three deployment actions and equipped items. The details scroll vertically; no gameplay actions have been replaced with display-only mockups.

The illustrated trio uses `PortraitLibrary.full_texture` in the showcase and `PortraitLibrary.texture` for face crops. Both share the same imported atlas. The other 35 portraits retain the existing pixel presentation and nearest filtering. Those characters are explicitly outside the illustrated portrait scope of this slice.

## Inventory, saves and utility menus

Inventory filters use a wrapping flow container with a selected state. Item rows have a category emblem, localized name, rarity tint and actual owned quantity or shop price. The detail pane gives the name and emblem a distinct header, then the actual description, modifiers and buy/equip/use/sell actions. Changing a filter selects a visible item rather than leaving the detail pane on an item outside that filter.

Save cards use the astral-ring emblem, slot identity, current map, leader level, recorded play time, reunion count and saved date. Load/save controls remain disabled while the existing asynchronous browser save is pending. Empty slots are visually subdued. The backup editor preserves actual export/import behavior.

Journal and crafting entries use inset cards. Map travel, difficulty selection, audio sliders, pause navigation, camp, credits, ending and defeat share the same themed controls. All text remains driven by the existing Thai/English content; this overhaul does not replace localized strings with decorative English labels.

## Assets and performance

`tools/build_fantasy_ui.py` reproducibly draws the original material borders and pictograms in `game/art/vertical/ui/`. It uses a deterministic seed only for subtle surface grain. No commercial reference assets or mixed asset packs are included. Twenty small PNGs provide all interface materials, buttons, category emblems and the slider thumb. Borders use Godot `StyleBoxTexture` nine-slicing and textures are cached once by `VeilUI`.

Illustrated crops use atlas views, not duplicated full-size textures. Body font resources are shared. Canvas gameplay remains compatible with the existing GL Compatibility renderer and web export. Interface art does not add a post-processing dependency.

## Verification and remaining limits

The actual production main scene opens all twelve menu types and resumes gameplay after closing them in `qa/menu-visual-ui-flow.log`: 42 checks, zero failures, and a clean runtime after fixing the icon-width API. Final integrated browser captures and the visual slice regression results belong in `PROGRESS.md`; an initial headless menu-open test alone is not evidence that every screen is readable.

Remaining visual work includes premium portraits for the other 35 characters, individually illustrated item art instead of category emblems, portrait expressions, responsive narrow/portrait layouts, and full controller navigation through every menu. The current guide establishes an integrated style for the vertical slice; it does not claim the whole game is visually finished.


## 2026-10-23 enforced UI hierarchy

- Surfaces: outer panel `#0b1924fc`, card `#142633fa`; one restrained edge and shadow. Brass identifies headings; mint identifies selection. Central dividers carry one diamond inlay. Avoid nested engraved frames around every control.
- Readable battle text: objective 17 logical px, hero name 16, action caption 15; use solid dark plates for labels over terrain. Obscured HUD fades only to 78%, preserving legibility. The existing 1152×648 canvas is validated at 1152×648 and 960×540 landscape.
- Action meaning: warm sword = attack; orange hammer = heavy guard break; turquoise flame = skill; gold star = ultimate; violet boot = dodge; red potion = heal; open hand = interact. Source is one cached, lossless 1774×887 4×2 atlas, about 6 MiB RGBA8, 2.18 MiB PNG. Original generation receipt: `asset_sources/ux_refresh/provenance.json`.
- States: numeric cooldown with readiness arc, explicit low-mana caption, ultimate percentage before readiness and “Ready!”/“พร้อมใช้” at full charge. Desktop displays actual J/K/Q/R/Space/H/E legends; touch hides them. Interactive hero cards show a transparent hover/focus outline, preserving portrait visibility.
- Menus: persistent party/inventory/journal/map/save/settings tabs, selected-state color, a fixed close action. Party deployment and wardrobe precede secondary stat controls. Stable roster order puts deployed heroes first; the selected row scrolls into view. Zero attribute points has a visible explanation.
- Opening: title buttons belong to one vertical container; no overlapping absolute-positioned secondary actions. Dialogue uses 20px body text, large continuation button and touch-specific hint.
- Keep measured limits explicit: physical-device multitouch, notch safe areas, portrait/ultrawide layouts, low-memory mobile frame times and full accessibility review remain open. See `docs/UX_REFRESH_PROOF.md`.
