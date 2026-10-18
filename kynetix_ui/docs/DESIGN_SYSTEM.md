# Kynetix Design System: "Carbon & Paper"

One import (`lib/config/app_theme.dart`) gives you tokens, motion, surfaces, transitions and animated primitives. The rules here sit alongside `docs/UI_UX_PRINCIPLES.md`; when they conflict, the stricter rule wins.

## Concept
Kynetix is a coach for Indian gym-goers who track roti, dal, paneer and their lifts.
- **Carbon** (dark) is true black `#000`, with clear surface steps (`#0E0E10` surface, `#161618` card, `#232326` raised) and hairlines.
- **Paper** (light) is warm white `#F6F2EA` with pure-white cards, so cards lift off the page, plus soft warm shadows.

**Each world has one accent** (v6, 2026-10-17). It tints that world's hero surface, its dock tab and its ambient light, so the three tabs never blur together. It is a wash and a rule, not a paint job: one tinted hero per screen.

| World | Accent | Where it shows | Tokens |
|---|---|---|---|
| Nutrition (Fuel) | ember | fuel label wash + rule, the + button, "again" pills | `KColor.fuel` / `ember`, `KGradient.fuel` |
| Protein / success | mint | protein numbers and bars, food-plan card | `KColor.green` |
| Train | violet | today's hero wash, the Start button | `KColor.train` / `violet` |
| Kyno (the coach) | cyan | Kyno's eyes and name, its tab, its light | `KColor.kyno` / `cyan`, `KGradient.kyno` |
| Neutral actions | **ink** | KButton, selected chips, switches | `KColor.ink` / `KColor.onInk` |

- `KColor.tabAccent(i)` gives the dock accent; `KColor.tint(accent)` gives a hero wash over the card colour.
- Secondary buttons, chips and switches stay **ink**. Green still means protein or success only.
- Colour is never the only signal: pair it with an icon, a word or a shape.

## Theming (both themes are first-class)
- **Which palette is active:** `KThemeController.instance` holds System / Light / Dark and persists it, and `KThemeScope` applies it. `KColor.*`, `KText.*`, `KGradient.*` and `KShadow.*` are **getters** that read the active `KPalette`.
- **Never freeze a theme value.** Don't put a theme value in a `const` expression, a `static final`, a top-level `final`, a `late final` State field, or a constructor default. Read it in `build`, or use a getter. For a nullable parameter: `final Color? _c; Color get c => _c ?? KColor.green;`.
- **Hairlines and overlays:** use `KColor.fg.withValues(alpha: …)`. That is white on Carbon and ink on Paper. **Never use `Colors.white.withValues` or `Colors.black.withValues` for overlays.**
- **When `Colors.white` is still right:** only for text or icons on a saturated fill (ember, violet or danger). On a fill whose colour depends on the palette, use `KColor.onAccent` (accent fills) or `KColor.onInk` (ink fills).
- **Branching:** `KColor.isDark` is for the rare value that must differ between themes, such as a shadow strength or an image.
- **Tuning:** light-mode accents are already deepened in the palette. Check that tinted fills (`color.withValues(alpha: 0.1–0.18)`) read well on paper.

## Tokens
- **Surfaces:**
  - `bg` is the page and is painted by the aurora.
  - `surface`: sheets and bars.
  - `card`: cards.
  - `cardHigh`: raised, pressed, or a placeholder.
  - `border` and `divider`.
- **Text:** `textPrimary`, `textSecondary`, `textMuted`, `textDisabled`, plus `onAccent` and `onInk`.
- **Type:** **Geist only**, bundled offline (`KText.family`).
  - `display/h1/h2` are heavy with tight negative tracking.
  - `h3/body/bodyMedium/caption/label`.
  - Numbers use `numDisplay/numMedium/numSmall`, which have tabular figures.
  - Use `KText.x.copyWith(...)`. In a raw `TextStyle`, add `fontFamily: KText.family`.
  - **Sentence case.** No new ALL-CAPS labels, and no `letterSpacing` wider than 1.0. Keep existing uppercase strings that tests pin.
- **Spacing:** `KSpacing.*`. Scrollable tab roots end with `KSpacing.dockClearance`.
- **Radius follows hierarchy:** `KRadius.xs 6` tags, `sm 10` chips, inputs and the fuel label, `md 14` objects in a list, `lg 18` standalone objects (a meal card, a product), `xl 24` sheets and the dock, `pill` buttons. Don't give everything the same curve.
- **Shadow:**
  - `KShadow.card` is empty on Carbon and soft on Paper.
  - `KShadow.glow(color)` is only for the single hero element. Prefer none on Carbon.

## Motion (`KMotion`)
- **Durations:** `instant 90 · quick 160 · standard 280 · emphasized 460 · slow 720`. Things the user waits on stay at quick to standard.
- **Curves:** `emphasizedCurve` is the default. Also `decelerate`, `accelerate`, `overshoot` and `spring`.
- **Gating:**
  - Wrap every duration in `KMotion.of(context, d)`.
  - Endless loops only run when `KMotion.ambientAllowed(context)` is true.
- **Entrances:** one `KReveal` / `kStagger` entrance per screen.
- **Haptics:** use `KHaptics.select/commit/success/reject/milestone`, once, on the commit frame.
- **Press:** wrap custom tap targets in `Pressable(semanticLabel: …)`.
- **Routes:**
  - Default is the shared-axis Z transition.
  - `kRiseRoute` for editors.
  - `kFadeThroughRoute` for context switches.

## Icon language (`lib/ui/k_icons.dart`)
- **No emoji as UI icons.** Not on meal sections, workout types, greetings, records, quick-add items or status lines. Emoji stored in data (e.g. `QuickAddItem.emoji`, `MealSection.emoji`) stay for compatibility but are never rendered.
- One family: Material *outlined* glyphs, at `KIcons.sm 16 / md 20 / lg 24`. Use the semantic constants (`KIcons.calories`, `KIcons.scan`, `KIcons.record`…) and lookups: `KIcons.meal(section)`, `KIcons.mealTime(section)`, `KIcons.workout(type)`, `KIcons.split(name)`, `KIcons.muscle(group)`, `KIcons.food(name)`.
- Push and pull are drawn as direction of force (↑ press away, ↓ pull in).
- `KIcon` renders at the scale, neutral and decorative unless labelled.
- **Kyno's mark** is `KynoMark`: a monochrome ink disc with a lowercase "k" knocked out (or a hairline ring when `outlined`), used where Kyno is an action (Describe it, dock icon). The way into Kyno is `KAskKyno`, a plain ink pill. No gradient rims.
- **Kyno's character** is `KynoAvatar` (`lib/widgets/kyno_avatar.dart`): a small drawn robot (ink shell, dark visor, cyan eyes, antenna). Moods: idle (breathes, blinks, glances), listening (looks at the composer), thinking (eyes up, antenna pulses), talking (mouth moves), happy, concerned (brows), celebrate (flex). Ambient motion only under `KMotion.ambientAllowed`; small repeated faces (chat bylines) pass `ambient: false`.

## Editorial layout (fewer containers)
- Group with type, space and hairlines (`KHairline`). Cards are for objects: a meal, a session, a product, today's fuel label.
- Numbers keyed by colour use `KDotStat` / `KDotStats` ("● 201 kcal  ● 3 g protein"), not tinted pills. `KChip` is now a quiet hairline tag (no fill); colour shows only in its dot or icon.
- Choices in sheets are `KOptionRow`s separated by hairlines, not stacked cards with tinted icon tiles.
- Secondary actions are `KTextAction` (underlined ink text, 48dp).
- Empty states are a sentence and an action; `KEmptyState` shows one outlined glyph, no illustration.
- Middle dots are for genuinely inline metadata only; prefer layout or a sentence.

## The fuel label (the one memorable element)
- `FuelLabel` (in `dashboard_screen.dart`, shared with the day screen) sets the day like the nutrition panel on a pack: a heavy ink rule, one big statement ("2,181 kcal to go"), one flat ember bar with quarter ticks, eaten and target figures, then protein on its own ruled line with a thin mint bar. No rings, no glow.
- Totals are integers built from what the rows print: `displayKcal(log)` / `displayProtein(log)` sum each entry's rounded value, so a meal row, its section total and the dashboard always agree, and eaten + to go = target.
- Use `thousands()` from `k_format.dart` for kcal ("2,181").

## Camera surfaces
- The barcode scanner is dark in both themes (camera UI): it reads `KPalette.dark` directly, sets light status-bar icons, and uses its own ink pill for "Type the code".

## Components
- **Surfaces:**
  - `KPage(tone:)`: a pushed screen with an aurora background.
  - Tab roots use a transparent Scaffold.
  - `KCard`: the card.
  - `KGlass`: near-opaque chrome surface (top sheen and hairline). It is cheap, so use it freely for docks and composers. Real backdrop blur is opt-in with `frosted: true`, and should never sit over scrolling content or inside list items.
- **Buttons:**
  - `KButton`: an ink pill, 56dp, with a loading state.
  - `KButton(outlined: true)`: secondary.
  - `KButton(color:)`: for a semantic action, such as a destructive one with `KColor.danger`.
- **Animated data:** `KRing`, `KBar`, `KAnimatedCount`.
- **States:** `KShimmer*`, `KEmptyState`, `KErrorCard`, `KSuccessBanner`.
- **Small pieces:** `KChip` (quiet tag), `KSectionTitle` (sentence case), `KSheetHeader`, `KDragHandle`, `KGlowDot`, `showKSheet`.
- **Editorial:** `KHairline`, `KDotStat`, `KDotStats`, `KOptionRow`, `KTextAction`, `KAskKyno`, `KDot`, `KIcon`, `KynoMark`.
- **Dock:** every tab shows icon and word; the indicator slides between equal tabs and takes the active world's accent (ember, violet, cyan); the + action is an ember disc.

## Rules
1. No raw hex colours in screens. Use tokens. `Colors.white` is allowed only on saturated fills.
2. Motion decorates state. The end state must be correct with animations off.
3. Touch targets are at least 48dp. Icon-only targets have a semantic label.
4. Use `RepaintBoundary` around expensive or continuously animating painters.
5. Use `ValueNotifier` for ticking values, not `setState` on big trees.
6. Every screen must look intentional in **both** Carbon and Paper. Check both.
