# Fincas design system

Source of truth: the FI logo (`assets/splash/splash.png`): warm near-black `#252117` with white serif lettering.
Code: `lib/theme/fincas_tokens.dart` (tokens), `lib/theme/fincas_theme.dart` (Material theme),
`lib/widgets/fincas_widgets.dart` (components). Screens use these; they never use raw hex values.

## Principles
Refined, minimal, warm, confident. Editorial in brand moments, plain and practical in operations.
No gradients, no heavy shadows, no decoration for its own sake. Color is used for meaning: ink for the main
action, espresso for emphasis and links, status colors only for status.

## Color tokens (`FincasColors`)
| Token | Value | Use |
|---|---|---|
| `ink` / `actionPrimary` | `#252117` | Main action, text, the logo background |
| `inkPressed` | `#3A3528` | Pressed state of the main action |
| `espresso` / `focus` | `#5A3A36` | Emphasis, links, entry actions, focus ring |
| `background` | `#F8F6F1` | Page (warm ivory) |
| `backgroundAlt` | `#F1EDE5` | Secondary background |
| `surface` / `surfaceElevated` | `#FFFFFF` | Cards, fields, sheets, dialogs (separated by border, not shadow) |
| `sand` / `divider` | `#E8E1D7` | Tonal fills, dividers, neutral badges |
| `sandStrong` / `border` | `#DDD5C8` | Decorative borders (cards) |
| `borderStrong` | `#8F8878` | Input outlines (3:1 against surfaces) |
| `textPrimary` | `#252117` | Primary text |
| `textSecondary` | `#5C574B` | Secondary text |
| `textMuted` | `#6F695C` | Captions, hints |
| `caramel` = `warning` / `caramelBg` | `#9A4F18` / `#F8E7D4` | Pending and in-review status (badges and notices) |
| `accent` = `espresso` / `accentBg` | `#5A3A36` / `#EDE4E0` | Interface accent: Nuevo pedido button |
| `sage` = `success` / `sageBg` | `#4E6B38` / `#E4ECDA` | Done, paid, positive |
| `error` (terracotta) / `errorBg` | `#A63A2B` / `#F6E1DD` | Owed, blocked, errors |
| `disabledBg` / `disabledText` | `#ECE8E0` / `#9A9486` | Disabled controls |

Contrast (WCAG): ink on ivory 14.9:1, white on ink 16.1:1, secondary 6.7:1, muted 5.1:1 (the first guess `#7A7467`
was 4.3:1 and was replaced), espresso 9.3:1, error 6.0:1, success 5.9:1, warning on its tint 6.0:1.
`test/theme/fincas_tokens_test.dart` fails the build if any text pair drops below 4.5:1 or an outline below 3:1.

Warm accents: caramel, sage and terracotta exist as status colors (badges and notices: pending, done, owed), each with
one meaning. The interface accent is espresso (`accent`, soft tint `accentBg`). On the Pedidos tab color is deliberately
rare: only the **Pendientes** filter (a muted espresso, `accentMuted` `#7A5650`, when selected) and the **Nuevo pedido** button (espresso) carry color. Everything else stays ink, ivory and sand. Do not color a control without a reason.
Both creation actions stay visible: "Nuevo pedido" is the main one, "Pre-venta" is a lighter secondary button.

## Typography (`FincasText`)
Two roles. **Serif (Fraunces, bundled in `assets/fonts`, SIL OFL)** only for brand moments: the wordmark and the
large screen title. **Roboto** for everything operational. Sizes scale with the system text size; no fixed heights.
| Style | Font | Size / line | Weight |
|---|---|---|---|
| `displayLarge` | Fraunces | 36 / 1.15, tracking -0.5 | 600 |
| `screenTitle` | Fraunces | 28 / 1.2, tracking -0.3 | 600 |
| `sectionTitle` | Roboto | 18 / 1.3 | 600 |
| `body` | Roboto | 16 / 1.5 | 400 |
| `bodySecondary` | Roboto | 14 / 1.45 | 400 |
| `label` | Roboto | 14 / 1.3, tracking 0.1 | 500 |
| `button` | Roboto | 16 / 1.25, tracking 0.2 | 600 |
| `metadata` | Roboto | 13 / 1.35 | 400 |
| `caption` | Roboto | 12 / 1.35 | 400 |

## Spacing, radii, icons
Scale `xs 4, s 8, m 12, l 16, xl 24, xxl 32, xxxl 48`. Screen horizontal padding 24, between sections 32, card padding
16, between fields 12, button height 52 (minimum touch target 48). Radii: badge 8, button/field 12, card/dialog 16,
logo `0.24 x size`. Icons 20 or 24.

## Components (`fincas_widgets.dart`)
`FincasPrimaryButton`, `FincasSecondaryButton`, `FincasTextButton`, `FincasCard`, `FincasBusinessCard`,
`FincasStatusBadge`, `FincasSectionHeader`, `FincasBrandMark`, `FincasLoader`, `FincasMessageState`
(empty, status and error states). Text fields, dialogs, snack bars and progress indicators are styled by the theme,
so plain `TextField`, `AlertDialog` and `SnackBar` already follow the system.

States: default, pressed (ripple), disabled (`disabledBg`/`disabledText`), loading (spinner replaces the label and
the button is disabled; one loader per screen), focused (espresso 2px outline on fields), error (error outline and
message). One primary button per screen; secondary for supporting actions; text button for back or skip.

## Accessibility rules
Text contrast at least 4.5:1, outlines 3:1. Touch targets at least 48pt. Every tappable card and button has a
semantic label in Spanish; headers are marked as headers; loaders are live regions. Layouts never use fixed
heights, so they hold at 2x text size on a 320pt screen (see `test/widgets`). With large text the business card
moves its "Entrar" action under the details.

## Using it
New or migrated screens use the tokens and components. Do not add `Colors.*` or hex values; add a token instead.
The app-wide theme already replaced the blue seed, but about 400 hardcoded `Colors.*` remain in screens that have not
been migrated; they will look mixed until they are.

## Status
Redesigned: splash and launch background (now exactly `#252117`), sign-in and onboarding, "Tus negocios".
Not yet migrated: orders, products, clients, settings, team and request screens, the main screen top bar.
