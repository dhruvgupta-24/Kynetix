# Kynetix UI/UX Principles

> **Status:** Binding rulebook for every Kynetix screen, sheet, widget and web build.
> **Audience:** Developers, designers and AI coding agents working on `kynetix_ui`.
> **Relationship to other docs:** `docs/DESIGN_SYSTEM.md` defines *what exists* (tokens, components, motion API). This file defines *how to use it and what good looks like*. Where the two disagree, see Section 18 (Open conflicts), which lists every tension and the decision it needs. Until a decision is recorded, the stricter rule wins.
> **Enforcement:** Every UI pull request passes the Review Gate (Section 17) before merge.

Each rule follows the same shape: **Rule**, **Why**, **How to apply**. Examples use Kynetix's own world: meals, macros, sets, reps, the rest timer and Kyno, the AI coach.

---

## 1. Core principles

### 1.1 The app must never look AI-generated or templated
- **Rule:** No screen may look like the output of a prompt such as "make a modern fitness app". Every visual decision is deliberate and grounded in what the user is doing right now (logging a meal, finishing a set, reading a trend).
- **Why:** Templated UI signals that nobody thought about the user. It also ages instantly and erodes trust in the numbers we show.
- **How to apply:** Before committing a screen, ask "could this have come from a generic generator?" If yes, redesign it. Banned tropes are listed in 1.2.

### 1.2 Banned patterns
- **Backgrounds and glows:** purple, violet or cyan-to-purple gradient backgrounds; multi-stop neon mesh glows; random floating blur blobs or orbs behind cards; particle canvases; floating geometric shapes. (See Section 18 for how this interacts with `KAurora` and `KGradient.train`.)
- **Containers:** frosted glass as the *default* card style; very large radii (24px+) on small data elements like a macro chip or a set row; pill shapes on every interactive element; repeated identical 3- or 4-card grids; decorative "bento" tiles packing unrelated features; tilted or skewed cards; cards floating over photos with fake shadows.
- **Text:** gradient-filled headlines; glowing text or text-shadow halos; wide uppercase tracking on reading text.
- **Imagery:** AI-generated people, glowing brains or robot faces for Kyno, holographic dumbbells, meaningless 3D shapes, fake screenshots of charts that do not exist in the app.
- **Social proof:** invented testimonials, invented user counts ("50,000 lifters trust Kynetix"), fake star ratings, fake awards, fake "people logging right now" tickers.
- **Motion gimmicks:** cursor or finger-following glows, magnetic buttons, scroll hijacking, parallax everywhere, animation that adds delay to a logging flow.
- **Marketing filler:** see 13.2.
- **Generator badges:** no "Made with AI" or platform watermarks anywhere, including the web build.

### 1.3 Design methodology (nine principles)
1. **Strong hierarchy:** every screen has one unambiguous focal point (today's calories left, the current set, Kyno's answer) with clearly subordinate secondary information.
2. **Intentional composition:** elements are placed with purpose and deliberate visual weight, like a well-set page, not dropped into a default grid.
3. **Content decides layout:** the shape of the data (a meal's macro split, a set table, a weekly trend) determines the layout. No cookie-cutter templates.
4. **Clear communication:** the user never has to guess what a number means or what to do next. "1,240 kcal left" beats "1,240".
5. **Characterful typography:** hierarchy comes from weight, scale, tabular figures and contrast, never from gradient text or animated type.
6. **Purposeful whitespace:** space isolates the key figure and gives the eye a path.
7. **Controlled rhythm:** dense zones (set table, macro breakdown) alternate with calm ones. Spacing is varied on purpose, not mechanically uniform.
8. **Restrained motion:** animation gives functional feedback or orients a transition. It never performs for its own sake (Section 6).
9. **Honest storytelling:** progress is told with the user's real data (their PRs, their streak, their protein trend), never with invented numbers.

### 1.4 Design intent
- **One memorable thing: the numbers.** Calories, protein, carbs, fat, weight lifted, reps and rest time are shown large, in tabular figures, and are the first thing the eye lands on. Everything around them stays quiet.
- **Calm, not busy.** One screen does one job. If a screen needs scrolling just to explain itself, split it.
- **Looks good in both themes.** Dark mode is not inverted light mode. Each theme is tuned separately (Section 4).

### 1.5 Do not overcorrect
- **Simple is excellent.** A clean typographic section beats an over-engineered layout.
- **Cards are fine when justified.** If grouping a meal's three macro figures in one panel improves clarity, use a card. The ban is on lazy, repetitive card grids that replace information architecture.
- **Restraint beats novelty.** Distinctiveness comes from precision, hierarchy, whitespace and real content, not gimmicks.

---

## 2. Visual hierarchy and layout

### 2.1 The five mandatory questions
Answer these before building any screen, sheet or dialog:
1. **What does the user notice first?** (e.g. calories left today; the weight and reps of the current set; Kyno's direct answer.)
2. **What supports it?** (e.g. macro split, last session's numbers for this exercise, the meal's time.)
3. **What is the one action?** (e.g. "Log meal", "Complete set", "Ask Kyno".)
4. **What can be de-emphasised or collapsed?** (e.g. micronutrients, per-ingredient breakdown, older set history.)
5. **Where does the eye go next?** (e.g. from the completed set to the rest timer to the next set.)

### 2.2 Hierarchy violations
- Never put three or four headlines of identical size on one screen.
- Never give a secondary button the same weight as the primary.
- Never scatter identical cards across a screen with no anchor element.
- Never give equal emphasis to an active alert (sync failed, set not saved) and static metadata (date created).

### 2.3 Alternatives to generic card grids
A container exists **only** when enclosing information improves comprehension or separates task boundaries. Pick the best representation:
1. **Editorial typography:** hierarchy with scale, hairlines and whitespace, no boxes (e.g. a day summary).
2. **Data table:** rows and columns with a fixed header for set number, weight, reps, RPE.
3. **Split comparison:** side by side, e.g. this week vs last week protein, or today's lift vs last session.
4. **Interactive calculator:** compact and immediate, e.g. the barbell plate calculator.
5. **Sequential timeline:** chronological progress, e.g. warm-up, working sets, cool-down; or breakfast to dinner.
6. **Inline stat strip:** a horizontal metadata strip under a header without heavy borders (P / C / F under a meal name).
7. **Process diagram:** a simple 2D diagram when explaining how something works (e.g. how Kyno estimates a meal).
8. **Callout statement:** one prominent sentence, e.g. "You hit your protein target 5 of 7 days."
9. **Definition list:** two-column key and value for exercise details (primary muscle, equipment, tempo).
10. **Slide-out drawer or sheet:** inspect history without leaving the screen (an exercise's past sessions).
11. **Expandable rows:** a set or meal row that reveals its detail in place instead of navigating away.

### 2.4 Navigation depth and structure
- **Rule:** Bottom tabs are always visible, each with icon **and** word. Nothing important lives only under a "More" or profile tab.
- **Rule:** Two levels deep at most. Any task starts from a tab and finishes within two screens. Example: Workout → Bench press → (log set / see history / swap exercise).
- **Why:** Deep navigation loses users mid-task, especially between sets with a raised heart rate and sweaty hands.
- **How to apply:** If a flow needs a third level, use a sheet or an expandable row instead of another pushed route.

### 2.5 Show 3 to 5 things, not 20
- **Rule:** Lists lead with the most relevant few items ("Today's meals", "Next exercise") and offer "Show all". Detail screens show the essentials; everything else sits behind "More details".
- **Why:** Glanceability. A gym-goer checks the app for a few seconds at a time.
- **How to apply:** For each list, decide the default sort that puts what matters today first.

### 2.6 Responsive layout
- **Phones (360 to 480 wide):** single column, primary action pinned at the bottom in thumb reach, collapsible filters, large glanceable numbers (22sp or larger) readable in a bright gym.
- **Tablets and foldables (768 to 1024):** deliberate two-column layouts (list and detail), not a stretched phone screen.
- **Large screens and web:** content is centred with a max width so rows do not stretch absurdly.
- **No horizontal overflow** at any width. Wide content (a long set table) scrolls inside its own container with a visible cue.
- **Keyboard never hides the active input.** The focused field scrolls into view when the soft keyboard opens (meal quantity, weight, reps).
- Mobile is a designed experience, not a collapsed desktop page.

---

## 3. Typography

### 3.1 Roles
1. **Display (personality):** screen titles and hero statements. A characterful grotesque with strong verticals (Kynetix: Bricolage Grotesque via `KText.display/h1/h2`).
2. **UI and body:** labels, navigation, body copy, status messages. High x-height, open apertures, and distinct `1`, `l`, `I` (Kynetix: Inter).
3. **Numbers (the heroes):** tabular lining figures so columns align in set tables, macro rows and timers (`KText.numDisplay/numMedium/numSmall`). A rest timer counting down must not jitter horizontally.

### 3.2 Scale (mobile reference)
| Level | Size | Weight | Line height | Tracking | Use |
|---|---|---|---|---|---|
| Section title | 24 to 26 | 600 | 1.25 | -0.015em | Screen headers |
| Subsection | 18 to 20 | 600 | 1.30 | -0.01em | Panel titles, exercise names |
| Hero figure | 28 to 36 | 500 to 700 | 1.10 | tabular | Calories left, current weight × reps, rest timer |
| Body | 16 to 17 | 400 | 1.5 | 0 | Explanations, Kyno's replies |
| Compact / data | 13 to 14 | 400 to 500 | 1.4 | 0 | Table cells, form labels, metadata |
| Caption / badge | 12 to 13 | 600 | 1.2 | +0.02em | Status badges, timestamps |

### 3.3 Rules
- **Numbers are heroes.** Key figures (kcal left, protein grams, weight × reps, rest seconds) are the most prominent element on their screen.
- **Minimum sizes:** body text 16 to 17sp, secondary 15sp, nothing below 13sp.
- **Large text support:** the app stays usable at the phone's largest font size (up to 200%). Layouts wrap; nothing is clipped, and no number is truncated mid-figure. Never clamp text scaling or shrink-to-fit a label to make it fit.
- **Line height:** at least 1.4 for Latin text; at least 1.6 for Devanagari if Hindi UI text is shown.
- **Two scripts (if Hindi is supported):** the typeface must have matching Latin and Devanagari designs and tabular figures (candidates: Mukta, Hind, or a Latin face paired with Noto Sans Devanagari). Choose by testing real screens in both languages. Hinglish food names ("rajma chawal") are Latin script and need no special handling.
- **Sentence case everywhere.** No all-caps labels, status badges included ("Saved", not "SAVED"). Never set full sentences or long headings in capitals.
- **Solid text colour only.** No gradient-filled text.
- **Fonts are bundled.** All fonts ship with the app. No runtime downloads from Google's font servers: it leaks the user's IP, slows first paint and breaks offline. With the `google_fonts` package, bundle the files under `assets/` and disable runtime fetching.

---

## 4. Colour and theming

### 4.1 Theme choice
- **Rule:** Three options: **Auto (follow phone)**, **Light**, **Dark**. Default is Auto. Set per user, stored locally, applied instantly.
- **Why:** Users train at 6 am in a dark room and log lunch in daylight. They expect the phone setting to be respected.
- **How to apply:** Restore the stored choice before the first frame so the app never flashes the wrong theme. A theme change is a local display preference (Section 9.1): it applies immediately and never waits on the network.

### 4.2 Dark theme: true black
- **Canvas is real black (`#000000`)**, no near-black substitute. It saves battery on OLED and gives the deepest contrast.
- **Elevation is shown by surface steps and hairlines, never by shadows.** Shadows are invisible on black. Reference steps from the source system: surface `#161616` (cards, sheets), raised `#222222` (inputs, pressed rows, menus), border `#2E2E2E`.
- **Text is warm off-white, not pure white,** to avoid glare on black. Reference: primary `#F2EFE9`, secondary `#B8B2A7`, tertiary `#8E887E`.
- **Accents are lifted** (lighter, less saturated) so they read on black, and text placed on an accent fill is dark when the fill is light.

### 4.3 Light theme: warm white
- **Never pure white as the page background.** Use a warm white canvas (reference `#FAF7F1`), slightly lighter raised surfaces (reference `#FFFDF8`), a muted fill for input backgrounds and table headers (reference `#F1ECE2`) and a warm hairline (reference `#E2DACC`).
- **Text is near-black warm charcoal** (reference primary `#1A1714`, secondary `#57514A`, tertiary `#6E675D`).
- **Accents are deepened** so they meet contrast on warm white.

### 4.4 Light/dark parity
- **Dark is not inverted light.** Each theme is tuned by hand: its own accent values, its own surface steps, its own elevation method.
- **Every meaning exists in both themes.** Fuel (ember), protein (jade), training (violet) and Kyno colours each need a light-theme and a dark-theme value that pass contrast in that theme.
- **Brand assets have a variant per theme** (logo, splash background, app icon foreground if needed).
- **Charts and images are checked in both themes before merge.** Chart colours come from tokens.
- **System chrome follows the theme:** status bar and navigation bar icon brightness, splash screen, notifications and any home-screen widget. Hard-coding light status-bar icons breaks the light theme.
- **Hard-coded colours fail review.** All colour comes from tokens.

### 4.5 Colour discipline
- **No decorative colour.** Every accent has a functional meaning: calories are ember, protein is jade, training is violet. Do not use a meaning colour for something unrelated.
- **Danger red is reserved** for failures, destructive actions and genuine alerts (a set that failed to save). It is never decoration.
- **Success green is reserved** for confirmed outcomes (saved, completed).
- **Warning amber** is for stale or pending states (showing data from earlier, waiting to upload).

### 4.6 Contrast targets
- **Body text meets 7:1 (WCAG AAA) in both themes.** All other text meets at least 4.5:1; large text (24px, or bold 19px) at least 3:1.
- **Essential UI parts and active borders** (input outline, selected chip, focus ring) at least 3:1.
- **Tertiary text is never used for anything the user must act on.**
- **Measure contrast against the composited background,** including any aurora, gradient or translucent panel underneath.

### 4.7 Status is never colour alone
- **Rule:** Every status combines colour + word + icon or shape ("Not saved" with a warning icon; "PR" with a trophy icon and the word).
- **Why:** Colour-blind users, bright sunlight and greyscale modes all defeat colour-only signals.
- **How to apply:** If you remove all colour from the screen, every status must still be readable.

---

## 5. Components and actions

### 5.1 Action hierarchy
- **Primary:** solid fill, clear label, exactly **one per screen**. Full width, at the bottom within thumb reach, at least **56dp** tall.
- **Secondary:** outlined or plain text button. Never the same visual weight as primary.
- **Tertiary / utility:** text link or icon button with a visible label.
- **Destructive:** clearly marked in danger colour, with a text label, reserved for irreversible operations.
- **At most 3 visible actions on any screen.**
- **Shape:** buttons look deliberate and tactile. Do not make every interactive element a pill; reserve pills for chips and filters (consistent with `KRadius` hierarchy: larger containers get larger radii).

### 5.2 Specific button labels
Every label states the exact outcome. Generic labels are banned.

| Banned | Use instead | Where |
|---|---|---|
| "Get started" | "Set my calorie target" | Onboarding |
| "Learn more" | "See protein breakdown" | Nutrition insight |
| "Discover" | "Browse exercises" | Exercise picker |
| "Try now" | "Ask Kyno" | Coach entry point |
| "Submit" | "Log meal" | Add meal |
| "Save" | "Finish workout" | Workout session |
| "Update" | "Update today's weight" | Profile / body stats |
| "Click here" | Describe the destination | Anywhere |

### 5.3 Cards and surfaces
- Large containers get larger radii, small data elements get small radii. Never use 24px+ radius on a set row or macro chip.
- Glass panels (`KGlass`) are a rare accent, never the default card, never inside list items.
- In dark theme, separate surfaces with surface steps and hairlines, not shadows (4.2).

---

## 6. Motion

### 6.1 Purpose
- **Rule:** Motion communicates hierarchy, state change, continuity and tactile feedback. It never distracts or slows the user down.
- **Rule:** Motion decorates state; it never *is* the state. With all animation off, every screen ends in the same correct state.
- **Why:** A user mid-workout cannot wait for a flourish to finish before logging the next set.

### 6.2 Timing budgets
| Kind | Budget | Notes |
|---|---|---|
| Micro-interaction (press, focus, toggle) | 100 to 150ms | Standard ease |
| Panel transition (sheet, drawer, dialog) | 180 to 220ms | Ease-out |
| Data refresh (list updates, numbers changing) | ~150ms cross-fade | No spatial sliding |
| Interaction feedback overall | 150 to 200ms | Anything in a logging flow stays within this |

Longer durations (route transitions, ring fills, a celebration) are allowed only where the user is not waiting to act. See Section 18 for alignment with `KMotion`.

### 6.3 Micro-interactions
- **Press:** a subtle press response with instant colour settling (`Pressable` squash).
- **Field validation:** on blur, the field border moves to danger colour with a helpful message directly below.
- **Row highlight:** a gentle background tint on press, with no layout shift.
- **Upload state:** a non-blocking badge transition, e.g. "Saved on phone" → "Uploading" → "Saved".

### 6.4 Reduced motion
- Respect the system reduce-motion setting fully.
- Skeleton shimmer becomes a static muted fill.
- Route and sheet transitions become instant or a cross-fade under 100ms.
- Smooth scrolling becomes instant jumps.
- Endless loops (ambient effects, pulses) do not start.
- Haptics and sound still fire, so feedback survives on other channels.

### 6.5 Elimination test
For every animation ask: "Could it be removed without losing meaning or usability?" If yes, remove it.

---

## 7. Feedback and states

### 7.1 Loading: skeletons vs spinners
| Use a **skeleton** (layout-preserving) | Use a **spinner or progress bar** (action-bound) |
|---|---|
| First load of a tab or screen | A button submission in flight (spinner inside the button) |
| Meal list, workout history, exercise list | Uploading a meal photo (determinate percentage) |
| Dashboard rings and stat cards | Kyno analysing a meal photo or a long question |
| Charts | Background upload of saved logs |
| Profile and body stats | A destructive operation executing |

### 7.2 Skeleton rules
- **Geometric fidelity:** a skeleton matches the size, padding and radius of what will replace it. Nothing jumps when data arrives.
- **No fake content:** skeletons are abstract blocks. They **never** show fake numbers ("1,850 kcal", "80 kg") or placeholder food or exercise names that could be mistaken for the user's real data.
- **Restrained animation:** slow, subtle opacity wave (about 0.6 to 1.0 over 1.5s). No fast strobing glows. Static under reduced motion.

### 7.3 Spinner and progress rules
- **Attached to the trigger:** the spinner replaces the icon or label inside the button the user tapped, and that button is disabled to prevent double submission (no duplicate meal logs).
- **Determinate when measurable:** uploads and downloads show a percentage.
- **Indeterminate only for short work** (under about 3 seconds) or background indicators.
- **Timeout escape:** if a spinner runs 15 seconds with no response, stop it, re-enable the button, and show an actionable error with "Try again".

### 7.4 Errors
- **Say what failed and what the user can do next.** Example: "Couldn't refresh today's meals. Showing what was saved at 10:45. [Try again]".
- **Never show a raw stack trace, exception text or the framework's default error screen.** Use a branded error state (`KErrorCard`) with a recovery action.
- **A failure never disappears silently.** It is shown as a visible banner, snackbar or inline message.

### 7.5 Empty states and "not found"
- An empty state explains why it is empty in plain words and offers the next action ("No meals logged today. [Log breakfast]").
- A missing item (deleted workout, broken deep link) shows a branded recovery screen with direct buttons back to useful places (e.g. "Go to Today", "Open workout history"), never a blank screen.

### 7.6 Haptics and sound
- Give haptic (and, respecting system settings, sound) feedback on save and on errors, so the user knows an action worked without reading the screen. This matters between sets.
- Fire once, on the commit frame (see `KHaptics` in the design system).

### 7.7 Forgiving actions
- **Undo over "Are you sure?"** Deleting a set, a meal or a food item shows a 5-second Undo bar instead of a confirmation dialog.
- **Confirm only what is irreversible or consequential**, and state it concretely ("Delete all workout history? This can't be undone."). Destructive actions are never icon-only and have explicit text labels.

---

## 8. Forms and input

- **Labels are always visible and attached to their input** (exposed to screen readers as the field's label).
- **Errors are tied to the field:** shown directly beneath, announced to assistive tech, and never conveyed by colour alone.
- **Validate on blur with a helpful message,** not on every keystroke and not only on submit. "Enter reps between 1 and 100" beats "Invalid".
- **Nothing must be typed by hand that could be picked:** steppers for weight and reps, recent foods, repeat-last-set. Typed fields accept the keyboard's voice typing.
- **Search is the main way to find anything.** Food and exercise search sits at the top of its screen, accepts English, Hinglish and Hindi spellings ("roti", "chapati", "phulka"), and has a microphone button.
- **The active field is never hidden by the keyboard** (2.6).
- **No hidden gestures.** Every action has a visible control. Swipe, long-press and double-tap are shortcuts only, never the only way (e.g. swipe to delete a set also exists as a visible menu action).

---

## 9. Saving, offline and honesty about state

Gyms often have poor signal. Logging must feel instant without ever lying about what has been saved.

### 9.1 Three categories of action
| Category | Examples | UI behaviour | On failure |
|---|---|---|---|
| **A. Display preference** (local, instant) | Theme, sort order, chart range, marking a tip as read | Change immediately | Revert quietly with a short notice if it needed the server |
| **B. User log** (saved on the phone first) | Logging a set, a meal, body weight, water | Show immediately, written to local storage at once, marked "Saved on phone" until uploaded | Keep it locally, retry automatically, show a visible error with "Try again" if it keeps failing |
| **C. Account and money** (server must confirm) | Subscription purchase, changing email or password, deleting the account, connecting an external account | Spinner on the button, button disabled, no optimistic success | Show the real reason; never fake success |

### 9.2 The lifecycle for categories A and B
1. User acts.
2. UI updates within one frame and announces the change to screen readers.
3. (B only) The change is saved locally with a unique id so retries never create duplicates.
4. Upload is attempted, with backoff.
5. Server confirms: badge moves to "Saved".
6. Server rejects: the local change is rolled back and the user is told why.
7. No connection: the item stays queued with a "Saved on phone" badge and retries when online. If the server has a newer conflicting version, apply the defined rule and ask the user only when a real choice is needed.

### 9.3 Zero false success
> **Invariant:** The UI never shows "Saved", "Done" or a success state while the upload has failed or not yet happened. A locally queued item says so ("Saved on phone, will upload when internet is back").

### 9.4 Plain words about state
No jargon in the UI: never "sync", "outbox", "queued", "pending reconciliation". Say "Saved on phone, will upload when internet is back".

---

## 10. Accessibility

### 10.1 Foundations (WCAG 2.1 AA minimum, AAA for body text)
- Contrast targets in 4.6.
- Status never colour alone (4.7).
- **Touch targets at least 48dp**, primary actions 56dp, with at least 8dp between targets.
- Large text up to 200% (3.3).
- Reduced motion (6.4).

### 10.2 Semantics and structure
- One clear screen title exposed as a heading; headings follow a logical order. Visual size is a style choice, not a semantic one.
- Every icon-only control has a descriptive semantic label ("Delete set 3", "Start rest timer"), not "button" or the icon name.
- Decorative images and ornaments are excluded from semantics; content images have descriptive labels ("Paneer tikka, about 250 g").
- Focus order follows reading order. Sheets and dialogs keep focus inside while open and return it to the control that opened them on close.
- On web and tablets with keyboards, everything is reachable with Tab, Shift+Tab, Enter, Space and Esc, with a clearly visible focus ring (never removed without an equally visible replacement).

### 10.3 Icon-only controls and tooltips
1. Accessible name is mandatory on every icon button.
2. Hover does not exist on touch. Critical actions (log meal, complete set, finish workout) never rely on a tooltip for discoverability; show a text label or offer long-press help.
3. Text buttons do not get tooltips that repeat their label.
4. Destructive actions are never icon-only.
5. Where tooltips exist (web), they appear on hover and keyboard focus after about 300ms and never cover a key number or input.

### 10.4 Announcing changes
- Changes that are only visible get announced politely: "Set logged", "Rest finished", "Meal saved on phone", "12 foods found".
- Critical failures (could not save, connection lost) are announced assertively.
- Loading regions are announced as busy with a description ("Loading today's meals") and cleared when done.

---

## 11. Sign-in, onboarding and trust

### 11.1 Auth surfaces that must exist and be branded
Sign in, create account, forgot password, reset password, verify email (code or link), and an access-denied / session-expired screen. Each uses the design tokens and theme, has one primary action, explains errors in plain words and offers a way forward. None may show a framework default screen.

### 11.2 Daily unlock
- After the first sign-in, offer fingerprint or face unlock so the user never types a password daily.
- A context switch such as auth → app uses one calm transition (`kFadeThroughRoute`), not a flourish.

### 11.3 Onboarding
- Onboarding asks only what is needed to set targets, one question per screen, with specific button labels ("Set my calorie target", not "Next" or "Get started").
- Every step respects the tap budget and the one-primary-action rule.
- Do not inflate onboarding with invented social proof or fake stats.

### 11.4 Consent and permissions
- Any consent or permission prompt (notifications, analytics, health data, connecting an external account) gives **"Decline" equal visual weight to "Allow"**. Non-essential tracking stays off until the user opts in, and the choice can be changed later from settings.
- **No session replay** tools (screen or keystroke recording) in any build.
- **Sensitive inputs stay out of analytics:** body weight, measurements, meal contents and anything typed to Kyno are never sent to telemetry.

---

## 12. Kyno (AI coach) UX

### 12.1 Kyno proposes, the user decides
- **Rule:** Kyno never changes the user's data on its own. Calorie targets, macro goals, workout plans and logged meals change only after the user confirms.
- **Why:** An AI that silently edits your plan or logs a wrong meal destroys trust in every number in the app.
- **How to apply:** Kyno's suggestions appear as a proposal with the concrete change stated ("Raise protein target from 120 g to 140 g?") and a one-tap confirm. Confirming an AI suggestion takes **one tap**.

### 12.2 Estimates are marked as estimates
- **Rule:** An AI-estimated value (e.g. macros from a meal photo or a typed description like "2 roti, dal, paneer sabzi") is shown as an estimate until the user confirms or edits it. It is never displayed as if measured.
- **How to apply:** Label it ("Kyno's estimate"), show what it was based on, and let the user adjust portions before logging.

### 12.3 Evidence over inference
- When Kyno makes a claim about the user's history ("You've missed protein 4 days this week"), it is grounded in the user's actual logs and can be traced back to them (tap to see the days).
- Kyno never invents numbers, history or achievements.

### 12.4 Waiting for Kyno
- Long AI work (analysing a photo, a long answer) uses action-bound progress, not a skeleton of fake text. Shaped message placeholders (`KMessageShimmer`) must not contain fake words or numbers.
- Apply the 15-second timeout escape (7.3) with "Try again".
- If Kyno fails, say so plainly and keep the user's question so they don't retype it.

### 12.5 Visual identity for Kyno
- No glowing brains, robot faces or holographic imagery.
- Do not label things "AI-powered" or "Smart" as filler. Explain what Kyno actually does ("Kyno estimated this from your photo").

---

## 13. Copy and voice

### 13.1 Voice
Human, concise, specific, like a knowledgeable training partner. Write about real things: roti, dal, paneer, sets, reps, rest, protein grams. Focus on outcomes: "Log a repeat meal in two taps."

### 13.2 Prohibitions
1. **No buzzwords:** "blazing fast", "bleeding edge", "next-generation", "revolutionary", "seamless", "powerful", "cutting-edge", "transform your fitness", "unlock your potential", "supercharge", "built for the future".
2. **No em dashes** in user-facing copy. Use commas, full stops, colons, parentheses or restructure.
3. **No unsupported superlatives:** never "The #1 fitness app in India" without verifiable proof.
4. **No jargon** about system state (9.4).
5. **Sentence case** everywhere (3.3).

### 13.3 Stripped-down test
Every piece of copy must still make sense and be useful with all styling, icons and layout removed.

### 13.4 No fake proof, no fake numbers
- Never invent testimonials, user names, user counts, ratings or awards, in the app, store listing or website.
- Never show fabricated metrics or counters. Animated counting (`KAnimatedCount`) is allowed only when it counts to a real value and lands on that value with motion off.
- If a social proof section cannot be backed by real data, remove it.

### 13.5 No placeholder content in release builds
No lorem ipsum, "John Doe", "Test meal", "Sample exercise", "Coming soon" (unless a real scheduled feature), TODO or FIXME text, broken image icons or framework starter text. Developer test data must never reach a production account.

---

## 14. Imagery and assets

- Every image communicates something concrete: a real exercise demonstration, a real food, the real app UI.
- Approved: official brand assets (light and dark variants), exercise media, real product screenshots, simple 2D diagrams.
- Banned: AI-generated people, futuristic gyms, abstract 3D blobs, fake dashboards.
- App store and website screenshots show the real app.

---

## 15. Perceived performance

- **Local response within one frame:** taps on log, complete-set and toggles reflect immediately (Section 9).
- **Tap-to-feedback under 200ms** on a representative mid-range Android phone.
- **No layout jump when data arrives** (skeleton fidelity, reserved image sizes).
- **Images are sized** for display (decode at display size) and use efficient formats.
- **Heavy screens and libraries load lazily** (charts, large media), so the first screen appears fast.
- **No heavy 3D or decorative runtimes** for effects.
- **Zero runtime errors in release:** no uncaught exceptions, no layout overflow warnings, no failed asset loads. Test on the release build, not debug.

### 15.1 Tap budget
Targets measured from the relevant tab. Validate them on real devices and record the actual counts.

| Task | Max taps |
|---|---|
| Complete the current set (during a session) | 1 |
| Start or skip the rest timer | 1 |
| Log a recent or repeat meal | 2 |
| Confirm a Kyno suggestion | 1 |
| See today's calories and protein left | 0 (visible on Today) |
| Log a new meal by search | 3 |
| Undo the last delete | 1 |

### 15.2 Web build hygiene (Flutter web)
- Browser tab title is the real product name and page, never the package name or "Flutter Demo".
- Branded favicon set and web manifest with theme colours; no framework default icons.
- Branded not-found and error pages with recovery buttons.

---

## 16. Optional surfaces

- **Home-screen widget (Android):** if built, it shows today's essentials (calories and protein left, next workout) and one direct action, and follows the active theme.

---

## 17. Review gate

### 17.1 Required evidence
Every screen pull request includes screenshots in **light and dark** theme, plus one at the **largest system font size**. If Hindi UI is supported, add Hindi screenshots too.

### 17.2 Automatic failures
A screen fails review if:
- it has more than one primary button;
- a key task exceeds the tap budget;
- any text is below the minimum size;
- any status relies on colour alone;
- it contains hard-coded colours;
- it shows a success state that hasn't really happened.

### 17.3 Checklist (answer every item)
1. **Template check:** could this have come from a generic AI prompt?
2. **Gradient check:** does it lean on purple or blue gradients for decoration?
3. **Shape check:** unnecessary pills or oversized radii on small elements?
4. **Card check:** generic cards everywhere instead of a fitting layout (2.3)?
5. **Copy specificity:** vague language or hollow claims?
6. **Buzzwords:** any from 13.2?
7. **Social proof:** anything invented?
8. **Metric integrity:** fake numbers, fake counters, fake skeleton values?
9. **Imagery:** generic AI imagery or 3D blobs?
10. **Hierarchy:** is the focal point obvious at a glance?
11. **Primary action:** exactly one, clearly distinct?
12. **Purpose:** does every section earn its place?
13. **Typography:** intentional roles, tabular numbers, sentence case?
14. **Rhythm:** is spacing intentional and varied?
15. **Composition:** distinctive without being chaotic?
16. **Motion:** functional and within budget?
17. **Motion elimination:** could any animation be removed without loss?
18. **Mobile intentionality:** designed for a phone, not collapsed?
19. **Static usability:** does it work with all animation off?
20. **Real product feel:** does it feel like a real tool for real training, not a concept shot?
21. **Theme parity:** checked and tuned in both light and dark?
22. **Accessibility:** labels, contrast, 48dp targets, 200% text, announcements?

If any answer reveals a generic pattern or an unverified claim, fix it before merge.

---

## 18. Open conflicts with `DESIGN_SYSTEM.md`

These are places where the current design system ("Ember Night") contradicts the principles above. Each needs an explicit decision recorded in `DESIGN_SYSTEM.md`. Until then, apply the stricter rule.

| Topic | DESIGN_SYSTEM.md today | Principle here | Decision needed |
|---|---|---|---|
| Training colour | `KGradient.train` is violet → cyan | 1.2 bans purple/violet and cyan-to-purple gradients as decoration | Keep violet as a meaning colour but use it as a solid, or justify the gradient as data encoding only |
| Ambient aurora | `KAurora` living background on every tab | 1.2 bans ambient glows and blobs; 4.2 requires a real black canvas in dark | Limit or remove the aurora; at minimum the dark canvas must stay true black and text contrast must be measured over it |
| Shadows and glow | `KShadow.card`, `KShadow.glow` | 4.2: dark elevation by surface steps and hairlines only | Drop shadows in dark theme; decide whether glow survives at all |
| Glass | `KGlass`, glass dock | 1.2 bans glass as default styling | Keep only as a rare accent (already "sparingly") |
| Gradient text | `KGradientText` | 3.3 bans gradient-filled text | Retire or restrict to non-reading decorative marks |
| Touch targets | 44px minimum | 10.1: 48dp, primary 56dp | Raise to 48dp |
| Motion durations | `standard 280`, `emphasized 460`, `slow 720` | 6.2: interaction feedback 150 to 200ms, panels 180 to 220ms | Restrict long durations to non-blocking moments (routes, ring fills, celebrations) |
| Light theme | Not defined (dark only) | Section 4 requires hand-tuned light and dark | Add a full light token set for every meaning colour |
| Fonts | `google_fonts` package | 3.3: fonts bundled, no runtime fetch | Bundle font files and disable runtime fetching |
| System chrome | Status/nav bar icons fixed to light | 4.4: follows active theme | Drive from theme brightness |
