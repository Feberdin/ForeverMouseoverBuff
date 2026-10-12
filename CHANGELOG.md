# Changelog

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
