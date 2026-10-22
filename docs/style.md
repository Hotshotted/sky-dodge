# Sky Dodge: style guide

Sky Dodge belongs to the same family as Pattern Work (same studio, **Clear Prop Games**): **friendly, chunky, high-contrast,
sunny**. A dark navy interface floats over the bright countryside; gold means money and stars, green means go, red means
trouble. The tokens live in `scripts/Style.gd`, the icons in `scripts/Icons.gd`, the controls in `scripts/UiButton.gd`,
`scripts/UiPanel.gd` and `scripts/IconView.gd`. Change the token, not the call site. This guide is the Pattern Work guide
with the deviations listed at the end.

## Palette

| Role | Token | Hex | Use |
|---|---|---|---|
| Primary | `PRIMARY` | `#3d8bff` | brand blue: selection, info, the propeller hub |
| Primary dark | `PRIMARY_DARK` | `#2459c4` | pressed / lip of blue elements |
| Accent | `ACCENT` | `#ffc933` | coins, stars, rewards, the one thing to look at |
| Accent dark | `ACCENT_DARK` | `#c98a0b` | lip of gold elements |
| Success | `SUCCESS` | `#35c98a` | PLAY, earned, go, a full tank |
| Success dark | `SUCCESS_DARK` | `#1a8a5a` | lip of the primary button, selected / affordable cards |
| Warning | `WARNING` | `#ff9f2e` | streaks, a tank running low |
| Danger | `DANGER` | `#ff5c4d` | a crash, lives, an empty tank |
| Danger dark | `DANGER_DARK` | `#b63227` | lip of red elements |
| Ink | `INK` | `#0a1020` | outlines, deepest dark |
| Surface dark | `SURFACE_DARK` | `#14213d` | cards, sheets, pills on the dark UI |
| Surface dark 2 | `SURFACE_DARK_2` | `#1d3157` | raised or selected dark surface |
| Text / soft / quiet | `TEXT` `TEXT_SOFT` `TEXT_QUIET` | `#ffffff` `#bcd0ec` `#8497b8` | primary, secondary, disabled text |
| Scrim | `SCRIM` | `#060b18` | the shade behind a screen or sheet |

Contrast: `TEXT`, `TEXT_SOFT` and `ACCENT` on `SURFACE_DARK` are at least 4.5:1 (the smoke test checks it). Text on the game
view and on coloured buttons always carries an ink outline (size / 8, at least 4 px). Colour is never the only signal.

## Typography

Both fonts are open-licence (SIL OFL 1.1, licences in `assets/fonts/`): **Fredoka SemiBold** (display: titles, every
number, anything at XL / M size) and **Nunito Bold** (text: labels, one-line descriptions). Sizes: **XL 110**, **M 56**,
**S 30**. A label is at most about four words; a description is one short line.

## Shape, shadow, buttons

Radii **S 14 / M 26 / L 40 / pill 60**. Borders 3 px light line (5 px on primary and gold). Every raised panel has the soft
shadow (`#030814` at 45 %, blur 16, offset 0 x 8) and the highlight across its top half; flat things have neither.

| Style | Look | Used for |
|---|---|---|
| Primary | big, green, XL text and an icon, chunky 10 px lip | PLAY, PLAY AGAIN |
| Gold | like primary, in gold | the one reward (an upgrade you can afford, MAX) |
| Secondary | dark surface, light border, soft shadow | HANGAR, LOGBOOK, buy and equip buttons, slots |
| Card | secondary with a round icon plate, a title, one line and a trailing price | map cards |
| Tab | pill; selected = green fill | the Hangar tabs |
| Ghost | translucent round chip, icon only | back, home, pause |

States: normal, **pressed** (the face squashes 5 px down, a primary into its lip), **released** (a small overshoot bounce),
**disabled** (flat, grey, no shadow or lip; a maxed gold button stays gold), **accent** (selected or affordable: green fill).

## Icons

One vector set drawn in code (`Icons.draw(item, id, centre, radius, colour)`), bold filled silhouettes and thick strokes,
no text, no emoji. Every perk, boost, supply, upgrade and gear item uses its own id (the `glyph` field in `Tuning.gd` is an
icon id); the UI icons are coin, star, clock, play, pause, restart, home, back, speaker, note, lock, check, plane, can, cat,
hangar, logbook, map and a few more. Items sit on a round coloured plate with a dark rim and a shine (`IconView`).

## Spacing and safe areas

Scale 8, 16, 24, 40, 64; gutter 40; one primary element per screen. `Style.safe_top / bottom / left / right` come from the
device (or the page's `env(safe-area-inset-*)` on the web); everything pinned to an edge adds the inset, backgrounds and the
world run edge to edge. Screens are laid out from the view size (`Hud._lay`), never from a fixed 1920 height.

## Motion

`T_FAST` 0.12 s (press / release), `T_BASE` 0.30 s (screen transitions, panels in), `T_SLOW` 0.5 s (celebrations), `STAGGER`
0.05 s. Ease-out-cubic arriving, ease-in-cubic leaving, ease-out-back (1.70) for popups and anything that lands. Forward
navigation slides in from the right, back from the left. Everything can be skipped.

## The studio

**Clear Prop Games**: a bold three-blade propeller (gold blades with an ink outline and a shine, blue hub) over the name in
Fredoka SemiBold. `tools/make_studio_mark.py` draws it (the wordmark as outlines, so no font has to load) into
`assets/studio_mark.svg` and `web/shell.html`; `Logo.gd` draws it in the game (start-up screen and logo intro). The web
loading page (`web/shell.template.html` -> `web/shell.html`, used by the web export) is the same picture: the brand
gradient, the spinning mark and a progress bar, nothing else; the game's own start-up screen continues it without a cut.

## The build stamp

Hidden from players. `?debug` (or `?tune`, or `?perf`) shows the commit and build time, small and faint in the bottom-left
corner, with the active flags under it.

## Deviations from Pattern Work

* The palette is the same; Sky Dodge adds countryside accents (`SKY`, `SKY_DEEP`, `MEADOW`, `BARN_RED`, `HAY`, `CLOUD`) for
  the world behind the interface.
* Its icon set is its own (fuel cans, perks, gear), drawn the same way.
* The game view is portrait 1080 x N (N depends on the device), not 1080 x 1920: screens are anchored to the view.
