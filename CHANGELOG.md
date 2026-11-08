# Changelog

## Unreleased — Deterministic texture order

- Give every stacked Sanctum rect an explicit sublevel (window layers, button
  border and fill, toggle row and indicator, card edge strip, statistic bars,
  feedback link row). WoW leaves the draw order of same-layer, same-sublevel
  textures unspecified; in game this showed as buttons that were solid gold,
  framed or invisible depending on the reload. Colors and geometry unchanged.
- Add a theme contract test that records sublevels, observed failing before
  the change.

## 0.9.3 Beta — Heal and buff with the same key

- Outside your own combat, a deliberate FMB keypress heals a friendly mouseover
  strictly below 50% health while you are standing still. Prefer learned, usable
  Flash of Light; otherwise use learned, usable Holy Light, with spell-specific
  range checks. WoW remains authoritative for cast failures such as line of sight.
- While moving, or at exactly 50% health or above, retain the usual blessing
  selection. Combat keeps the fixed learned Kings action.
- Keep healing separate from buff greetings, buff statistics and ranking counts.
  Preserve the improved first-use key setup and actionable status guidance.

Prepared locally after automated verification. In-game healing, combat
transitions and recipient delivery remain separate acceptance checks.
This entry does not claim publication.

## 0.9.2 Beta — Actionable buff guidance

- Explain blocked selections with a concrete recovery step: move closer, choose a
  living friendly player, learn a blessing, select Auto, or reload missing data.
- Link missing-key guidance directly to `/fmb bind`; a learned combat Kings
  action no longer appears ready when no buff key is assigned. Binding reads
  during combat never inspect targets or edit protected actions.
- Leave generic unusable spells to WoW's authoritative reason; do not guess mana
  loss, cooldowns or line of sight. Existing fixed diagnostic codes remain intact.
- Reserve three lines for cause and recovery in the status card. Feedback stays
  on deliberate input with the existing repeat limit; previews add no chat spam.
- Add ten permanent Core/App/Menu regressions, observed failing before the fix.

- Include the shared `FeberdinDiagnostics.lua` runtime module in reviewed source
  and addon packages, before Core in both manifests. A permanent regression test
  covers the previously blocked packaging path.
- Keep shared diagnostics local and bounded to 100 entries: fixed codes plus
  validated own Lua filenames and line numbers; no raw errors, player names or
  chat. Use `/fmbdiag status`, `clear`, `on` or `off` to inspect and control it.
  This module performs no network requests or uploads.

Prepared locally after automated validation; no publication or in-game
acceptance is claimed.

## 0.9.1 Beta — Clear first-use key setup

- Returning characters without a buff key see the improved introduction once,
  including when the earlier introduction was already marked as seen.
- Show the actual binding status, an explicit **Jetzt Taste einrichten** action,
  and an honest **Später einrichten** skip until a key is assigned. Configured
  users retain their keys and keep the menu closed on later logins.
- Defer automatic introduction during login combat and disable its key setup
  button during combat. Deliberate capture, occupied-key protection and all
  existing preferences remain intact.
- Add six permanent App/Menu regressions for migration, first use, persistence,
  live binding status and combat safety.

Installed locally after automated validation; no publication or in-game
acceptance is claimed.

## 0.9.0 Beta — Introduction and in-addon key setup

- Show a short introduction once per character after the update; reopen it with
  `/fmb intro`. Explain deliberate mouseover buffing, combat Kings and greetings.
- Add direct key setup on **Buffs & Taste** and through `/fmb bind`, including
  keyboard modifiers, the middle mouse button, buttons 4/5 and the mouse wheel.
- Preserve other actions: reject occupied keys and save deliberate changes in
  WoW's current account-wide or character-specific binding set. Removing a
  binding affects only FMB keys; no default key is installed.
- Cancel capture with Escape, window close or combat entry. Keep the native
  CLICK action and combat behavior; setup never casts a spell.
- Keep previously shown introductions closed on later logins, including after
  skipping them, while retaining accessible
  help, class priorities and all existing saved preferences.

Prepared locally as a Beta candidate. In-game key delivery, combat transitions
and recipient delivery remain separate release acceptance checks. This changelog
records the prepared changes, not a publication or an in-game test result.

## 0.8.0 Beta — Priorities for each recipient class

- Add a class-priority page with all nine recipient classes, ordered Might,
  Wisdom and Kings choices, per-family switches and per-class default restore.
- Use the saved list on both preview and the fresh deliberate buff key press.
  An empty list disables only that recipient class in automatic mode.
- Druids now default to Kings → Wisdom → Might: when other paladins already
  supply Kings and Wisdom, select learned and level-appropriate Might.
- Preserve any own permanent blessing in Auto, including one excluded from the
  list. Previously, an own blessing outside the default class list could be
  replaced. This closes that gap and prevents accidental replacement after edits.
- Keep fixed manual modes and the preconfigured combat Kings action independent.
- Validate preferences before saving; add CLASS_DISABLED / INVALID_PRIORITIES
  diagnostics and an explicit `/fmb priorities reset` recovery command.

Automated tests cover the selection, persistence, native input boundary and menu
geometry. Live gameplay and recipient delivery remain separate acceptance checks.

## 0.7.6 Beta — Quiet outgoing greetings

- Keep **Send automatic greetings** and **Hide my greetings** independently
  switchable in Greetings & Chat; both default to ON. Turning sending off stops
  automatic messages without disabling buffs or changing recipient preferences.
- Extend hidden outgoing greetings to WIM: no popup, sound or history entry for
  the exact recent automatic echo. Personal whispers keep WIM's normal behavior.
- Preserve existing saved display preferences and all incoming opt-out controls.
- Add portable outgoing-display regression tests and verify the integration
  against locally pinned native WIM handlers. No new message content is logged.

## 0.7.5 Beta — Feedback window navigation

- Fix main-menu text and buttons drawing through the feedback dialog: only one
  FMB window is visible at a time.
- Closing feedback or pressing Escape returns to the previous page when opened
  from the menu. Directly opened feedback leaves the menu closed.
- Main-menu commands and quick reopen/close sequences cancel stale return work;
  copy focus is released when the dialog hides.
- Ten permanent window-lifecycle regression/edge-case tests, including both
  Escape sweep orders and inherited parent visibility. No buff or ranking changes.

## 0.7.4 — 2026-10-12 — Beta

- Replace the old Blizzard-style settings panel with the native Sanctum menu:
  dark teal surfaces, gold selection states, mint switches and original logos.
- Separate buffs/key help, greetings, sounds, local statistics, diagnostics and
  feedback into six pages, preserving the selected page when settings change.
- Display real local counters and recent diagnosis only on their visible pages.
- Match the GitHub feedback dialog to the theme, keeping optional data sharing
  and deliberate copy/review behavior.
- Ship two compact runtime TGA logos and fit windows to the available UI size.

Existing preferences and casting behavior are preserved. Automated contracts and
an offline replay of real Lua geometry are checked; native font metrics and
interaction still require an in-game check after reload. The separately scheduled
low-level rank investigation is not part of this interface update.

## 0.7.3 — 2026-10-12 — Beta

- Add an in-game **Feedback & Hilfe** dialog and `/fmb feedback` with bug,
  improvement and feature categories, a selectable GitHub URL and exact preview.
- Keep technical details off for each newly opened report. Optional details are
  limited to checked public versions, settings and five known diagnostic codes.
  No names, whispers, counters, arbitrary errors or full logs are included.
- Add German GitHub forms with the Feberdin knight, focused questions and labels.
- Reports remain manual: opening the copied URL sends its fields to GitHub;
  the player reviews and submits in their browser. No token or addon HTTP call.

Automated Lua, UI-boundary and packaging checks cover this change. Native UI
layout and clipboard behavior still require an in-game check after reload.
The Sanctum design mockup is separate; this update adds the reporting dialog
and its menu entry. Casting and existing preferences are unchanged.

## 0.7.2 — 2026-10-12 — Beta

- Add a bounded local diagnostic ledger with fixed codes, severity, module,
  optional public timestamps, counters and a small client/settings snapshot.
- Add `/fmb diag` and a read-only local companion reader with human/JSON output;
  neither requires the ranking service or uploads data. Saved snapshots become
  available after WoW writes them on reload/logout.
- Preserve supported legacy diagnostic counters/codes and bound repeated events.
  No player names, GUIDs, whisper contents or raw API errors enter the ledger.
- Add the original Feberdin knight to the reusable avatar/banner family and
  expand English/German project guides. Artwork stays outside the addon ZIP.

Automated checks and the local reader do not establish in-game acceptance.
No public ranking endpoint is enabled by this Beta.

## 0.7.1 — 2026-10-12 — Beta

- Store twenty supported spell counters as fixed 32-bit binary values in a
  Base64 payload with a SHA-256 checksum, replacing the plain decimal counter
  fields (storage schema 2).
- Migrate valid known counters from schema 1 automatically without resetting
  existing history. Leave an invalid record unchanged and stop statistic updates
  instead of silently accepting, repairing or clearing it.
- Explain unavailable statistics with a fixed diagnostic code while allowing
  normal buffing to continue.

The checksum detects corrupt or inconsistent storage; it is unkeyed and can be
recomputed. This is not encryption, authentication, anti-cheat or proof of genuine
casts. Optional ranking events remain a separate readable export, and rankings
remain self-reported. The ranking service stays local. In-game acceptance of this
Beta is still pending.

## 0.7.0 — 2026-10-12

- Hide your own automatic FMB greetings from ordinary chat by default; use
  `/fmb outgoing on|off` to change only this display preference.
- Let WIM retain its ordinary outgoing conversation behavior.
- Keep sender, recipient and local outgoing display preferences independent.
- Make receiver-only use clear for every class, including classes without buffs.
- Prepare a minimal ranking JSON export and deliberate local browser upload flow.
- Prepare an allowlisted source export, addon ZIP, English/German project text,
  original project icon and portable CI for review before publication.

Rankings remain self-reported and editable client-side, not server-verified.
Only Paladin blessings are supported for actual casting and ranking. The public
ranking service, GitHub remote and CurseForge listing are not activated by this
release preparation. In-game acceptance must be recorded separately.

## 0.6.1 — 2026-10-12

- Add appropriate greeting language for nine sender classes and racial variants.
- Use neutral language for unknown classes and class-appropriate short fallbacks.

## 0.6.0 — 2026-10-11

- Add local unverified buff counts, native spell links and opt-in event export.
- Add a local community-ranking prototype and a separate explicit-use companion.
