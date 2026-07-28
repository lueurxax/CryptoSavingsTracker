# CryptoSavingsTracker Design System

A design system for **CryptoSavingsTracker** — a cross‑platform crypto savings goal tracker. The repo (github.com/lueurxax/CryptoSavingsTracker) ships native apps on iOS 18+, macOS 15.5+, Android (~90%) and visionOS (planned); this design system captures the visual foundations governed in `docs/design/visual-tokens.v1.json` and the iOS/Android theme layers.

> Pet project that wants to look like a polished production finance app. Calm, trustworthy, accessibility‑first (WCAG AA).

---

## Sources

| Source | Path (in upstream repo) |
|---|---|
| Token manifest | `docs/design/visual-tokens.v1.json` |
| Visual system doc | `docs/VISUAL_SYSTEM_UNIFICATION.md` |
| Goal Dashboard spec | `docs/GOAL_DASHBOARD.md` |
| iOS colors | `ios/CryptoSavingsTracker/Utilities/AccessibleColors.swift` |
| iOS component tokens | `ios/CryptoSavingsTracker/Utilities/VisualComponentTokens.swift` |
| Android colors | `android/app/src/main/java/com/xax/CryptoSavingsTracker/presentation/theme/Color.kt` |
| Copy dictionary | `docs/copy/FINANCIAL_COPY_DICTIONARY.md` |

All sources pulled from `lueurxax/CryptoSavingsTracker@main`. No Figma file was provided.

---

## Index

- `colors_and_type.css` — CSS variables for colors, typography, spacing, radii, elevation, motion
- `preview/` — design‑system preview cards (Type, Colors, Spacing, Components, Brand)
- `assets/` — logo and brand marks (SVG placeholders — app icon source is `.icon` bundle, not exportable)
- `ui_kits/ios/` — iOS/SwiftUI‑style HTML recreation (iPhone frame)
- `SKILL.md` — agent skill manifest

---

## Content Fundamentals

Tone is **plain, precise, consequence‑aware** — never playful, never crypto‑bro. The copy is written as a calm financial assistant.

- **Second person ("you")** — "You're on track to reach your goal"
- **Sentence case** throughout — titles, buttons, section headers
- **ISO 8601 dates** (`YYYY-MM-DD`) in docs; human short dates (`Mar 15`) in UI
- **No emoji in code or doc headers** (strict). A limited badge set (✅ ❌ 🔄 ⚠️ 📋 🗄️) is allowed in *content only*
- **Numbers are tabular** — prices/amounts use `tabular-nums` so digits align in lists
- **Non‑color status cues required** — every status also has an icon + text, never color alone (WCAG)
- **Active, verb‑led CTAs** — "Log contribution", "Plan this month", "Retry data sync", "Refresh forecast"
- **Stale/error language is reassuring, not alarming** — "Budget saved, not applied to this month yet", "Goals changed, review this plan", "Unable to save this goal right now. Please try again."
- **Status chips** are explicit: `On Track`, `At Risk`, `Off Track` — never `🟢`/`🔴`

Voice examples from the app:
- Primary CTAs: *Log contribution* · *Plan this month* · *Add first asset* · *Rebalance allocations*
- Empty state: *No forecast available — Add more transactions to generate forecast predictions*
- Stale state: *Goals changed, review this plan*
- Error recovery: *Retry data sync* · *Refresh snapshot*

---

## Visual Foundations

**Personality:** calm, finance‑trustworthy, native‑first. Both platforms use their native surface language — iOS `.regularMaterial` over system backgrounds; Android solid neutral surfaces — and the design system explicitly calls this out as an *approved variant* rather than trying to unify it. The visual system is governed, with CI gates that forbid raw color/shadow literals in code.

### Color
- Primary blue (`#0066CC` Android / `#007ACC` iOS) is the single interactive accent. Used on primary buttons, links, focus rings, primary chart line.
- Status semantics carry real weight: success = green (`#00875A`), warning = orange (`#B84D00`, darkened from `#CC6600` for AA contrast), error = red (`#CC0000`).
- All status colors have paired backgrounds at 10% opacity light / 18% dark.
- Chart palette is 10 colors chosen for WCAG AA foreground on white and colorblind distinguishability.
- **No decorative gradients in finance‑critical flows.** Gradients may appear only on non‑critical chrome (shimmer skeletons use a neutral gray gradient).

### Typography
- **SF Pro on Apple, Roboto on Android.** Web fallback uses the system stack. No custom brand font.
- iOS Dynamic Type scale: LargeTitle 34 / Title 28 / Headline 17 / Body 17 / Footnote 13 / Caption 12.
- Tabular numerics for all amounts.
- Headings use slight negative letter‑spacing (`-0.01em` → `-0.02em`).

### Surfaces & Backgrounds
- **Calm surfaces** are default for finance content. iOS uses `.regularMaterial` (blurred translucent); Android uses solid `#FFFFFF` / `#1E1E1E`.
- Full‑bleed imagery is not used. No repeating patterns. No hand‑drawn illustrations.
- Backgrounds are plain neutrals: `#FAFAFA` light, `#121212` dark.

### Corner Radii
- Settings rows: **10px**
- Planning cards & rows: **12px**
- Dashboard summary cards: **12px**
- Dashboard hero cards: **16px**
- Pills / badges: fully rounded

### Elevation / Shadows
Three tiers from the token manifest:
- `card` → 2dp
- `raised` → 4dp
- `modal` → 16dp
- Standard rows use `none` with a 1px stroke separator (`rgba(60,60,67,0.18)`).
- **No per‑component shadow recipes** — shadows must come from the token set (enforced by `no_ad_hoc_shadow_literals` lint rule).

### Borders
- 1pt stroke on card edges (`--surface-stroke`).
- Row separators are subtle hairlines, not full borders.
- Focus indicator is a 2px ring in `#0052F5`.

### Motion
- Press feedback: **100–150ms**, single‑axis, no multi‑axis bounce in finance rows.
- Loading → ready transitions: **150–250ms**, opacity/position only.
- Sheet/modal: platform‑native (iOS sheet, Android bottom‑sheet). No custom spring overrides on release‑blocking flows.
- **Reduced Motion collapses all transitions to instant.**

### Hover / Press States
- Hover: subtle neutral `#F2F2F2` background (desktop only).
- Press: 1dp elevation drop on cards (`raised → card`), no color shift on the surface itself.
- Primary button press: opacity 0.85, no scale change.

### Transparency & Blur
- iOS `.regularMaterial` is the signature look for finance cards.
- Status backgrounds are 10% (light) / 18% (dark) tint, never solid.
- No decorative glass; modal scrims are `rgba(0,0,0,0.32)`.

### Layout Rules
- Tab bar fixed on iPhone; sidebar split view on iPad/macOS; bottom nav on Android.
- `next_action` CTA always above the fold on Goal Dashboard.
- Dashboard module order is fixed across platforms: `goal_snapshot → next_action → forecast_risk → contribution_activity → allocation_health → utilities`.
- Minimum touch targets: 44×44pt iOS / 48×48dp Android.

### Imagery Vibe
There is effectively no stock imagery. Product leans on data visualization (charts, progress rings, sparklines) as the primary visual payload.

---

## Iconography

- **SF Symbols on iOS**, **Material Symbols / androidx.compose.material.icons on Android.** These are built‑in platform icon fonts — not redistributable as assets.
- **Emoji are used intentionally as goal avatars** — users pick an emoji for each goal (🏖️, 🚗, 🏠, 💍). An `EmojiPickerView` exists at `Views/Components/EmojiPickerView.swift`. Everywhere else emoji are forbidden.
- No custom icon font; no sprite sheet; no bundled PNG icons in the Apple/Android targets.
- **Web/design‑system substitute:** Lucide (`https://unpkg.com/lucide@latest`) — same outline stroke weight (2px) as SF Symbols default and Material Symbols `Outlined`. **Flagged substitution** — not used in the real apps.

Usage rules:
- Status chips always pair icon + text (`checkmark.circle.fill` + "On Track", `exclamationmark.triangle.fill` + "At Risk", `xmark.octagon.fill` + "Off Track").
- Quick action buttons use filled glyphs (`plus.circle.fill`, `arrow.down.circle.fill`, `pencil.circle.fill`).
- Info/secondary actions use outline glyphs.

---

## Caveats / Substitutions

- **No Figma provided** — all tokens reverse‑engineered from the code + token manifest.
- **SF Pro / Roboto** not redistributable; the web system uses the native system font stack and falls back to sans‑serif. No font files bundled.
- **SF Symbols / Material Symbols** not bundled; Lucide used as nearest web equivalent.
- **App icon** is a `.icon` bundle (Xcode 26 composed icon) that can't be trivially rendered outside Xcode — a placeholder wordmark is shipped in `assets/logo.svg`.
- The app has **no marketing website**; only the iOS/macOS/Android product surface is recreated.

---

## What's in this design system

| Folder | What's there |
|---|---|
| `colors_and_type.css` | Every token as a CSS variable |
| `preview/` | Design‑system cards (HTML) |
| `assets/` | Logos and brand marks |
| `ui_kits/ios/` | Interactive iPhone mock of the Goal Dashboard, Planning, and Goals List |
| `SKILL.md` | Agent‑skill manifest for reuse in Claude Code |
