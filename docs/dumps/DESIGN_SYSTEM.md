# HULI-KAMOTE design system (phone app + officer dashboard)

Written 2026-11-01 for the officer evaluation. One set of rules for both screens, so the phone and the laptop feel like one product.

**Honest scope.** Mobbin could not be browsed from the build environment, so no Mobbin screen was copied or checked against. The rules below are the published guidance that Mobbin-style pattern libraries are built from: Nielsen's 10 usability heuristics, WCAG 2.1 AA, Material 3, and the 44/48 px touch-target rules from Apple and Google. If the evaluation form uses other wording, map it to the "Principle" column.

## 1. Principles and where they show

| Principle | Phone app | Officer dashboard |
|---|---|---|
| **See what is going on** (status visibility) | Skeleton rows while loading, "Appeal sent" chip + timeline, offline banner with saved copy | Overview numbers, "N waiting" badges, skeleton rows, "3 left" in a review batch |
| **Plain words** (match the real world) | "Can appeal", "Seen by the camera"; no jargon | "False alarm", "Confirm violation", "Plate sharpened"; the old "True Positive / GAN enhanced / pop quiz" labels are gone |
| **Never a dead end** (error recovery) | Every failure maps to a sentence and a way out (Try again, Change connection) | `ErrorPanel` with "Try again" on every list; a failed save keeps the ticket and says so; one failing number does not hide the others |
| **Prevent mistakes** | Appeal reason needed, one appeal per ticket, field errors under the field after the first try | "False alarm" is blocked once the plate is edited; "Discard" is a quiet text button; confirm is the only filled button |
| **Recognise, don't remember** | Quick-reason chips, labelled icons | Menu grouped Monitor / Review / Records, the four-step "How it works" cards, tooltips on the collapsed menu |
| **One look** (consistency) | `lib/core/ui` tokens, `AppButton`, `StatusChip`, `EmptyState`, `ErrorState` | `Fx` tokens, `FxCard`, `StatusPill`, `EmptyState`, plus `lib/core/ui/page_parts.dart` (`PageHeader`, `StatTile`, `ErrorPanel`, `SkeletonRows`) |
| **Reachable by everyone** (accessibility) | 48 dp tap targets, status = icon + text (never colour alone), screen-reader labels, light and dark | Same rule for status pills, `Semantics` on menu/tiles, 48 px menu rows, keyboard focus, Enter signs in |
| **Few things at a time** (hierarchy) | One title, one primary button per screen | Overview: four numbers, then the path, then the latest; the Inbox shows one batch list, the review shows one ticket |

## 2. Tokens

- Spacing scale 4 / 8 / 12 / 16 / 24 / 32. Nothing else.
- Radius 12 for cards, 8 for chips and fields, pill for status.
- Minimum tap target 48 (phone `minTap`, dashboard menu rows).
- Status colours: success green, warning amber, danger red, accent blue. Always paired with an icon and a word.
- Plates are always set in a monospace face (`Fx.plate`) so letters and digits cannot be confused (O/0, I/1).
- Dates read as "9 min ago", "yesterday", then the date (`ago()` in `page_parts.dart`, `format.dart` on the phone).

## 3. The four states every list has

Loading (skeleton rows, not a spinner) → Empty (what it means and what to do next) → Error (plain sentence + Try again) → Loaded. A fifth, **Offline**, exists on the phone: the last good copy is shown with a banner.

## 4. Where the code is

- Phone: `hulikamote_app/lib/core/ui/` (tokens, theme, widgets), screens in `lib/features/*`.
- Dashboard: `hulikamote_dashboard/lib/features/forensic/presentation/widgets/fx.dart` (tokens + widgets), `lib/core/ui/page_parts.dart`, the shell in `lib/core/shell/app_shell.dart`, new `lib/features/overview/`.
- Pictures of every screen: run `SHOTS_DIR=<folder> flutter test test/visual/...` in each app. The images are not kept in git.

## 5. What was checked, and what was not

Checked: widget tests for every state above (phone 114, dashboard officer pages and menu 27), the screenshots were looked at by the author after each change, the Flutter analyzer is clean on the touched files.

Not checked: a real phone or APK, the dashboard's own Lexend font (the screenshot test draws Roboto; Lexend is a little wider), a screen reader, contrast measured with a tool, and any user test. A short SUS questionnaire with the officer would be the first real measurement.

## 6. If the officer view becomes the real dashboard

1. Replace the demo sign-in with real accounts and roles; hide pages on the server, not only in the menu (`OfficerMode` is a view switch, not security).
2. Keep the Overview as the landing page; add a "needs attention" sort (oldest waiting first) and a daily count.
3. Inbox: keyboard shortcuts (C confirm, F false alarm, J/K next/previous) and an undo for a decision.
4. Add Filipino copy next to English; the sentences are short on purpose.
5. Measure contrast of every status colour on both themes and fix any below 4.5:1 for text.
6. Log who confirmed which ticket and when (audit trail) and show it in the ticket.
