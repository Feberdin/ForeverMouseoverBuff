# CurseForge submission preparation

Checked against official CurseForge pages on **2026-10-12**. This folder prepares
a reviewable submission; no project, remote or public ranking is created by it.

## Is GitHub required?

No. The official author workflow creates a project and uploads a ZIP directly.
A source repository is an optional project link. GitHub is useful for history,
issues and CI, but does not have to precede the first manual upload.

Sources: [Creating and Submitting a Project](https://support.curseforge.com/support/solutions/articles/9000197241-creating-and-submitting-a-project)
and [Project Submission Guide and Tips](https://support.curseforge.com/support/solutions/articles/9000199552-project-submission-guide-and-tips).

## Prepared inputs

- Project name and summary: `metadata.json`.
- Main English project description: `description-en.md`; the submission guide
  requires English titles/descriptions. `description-de.md` is supplementary.
- License: MIT, already used for the original project; full text in `LICENSE`.
- Changelog: `CHANGELOG.md`.
- Original icon: `release/assets/project-icon.png`, 400×400 PNG; vector source
  beside it. The guideline requires a square PNG at least 400×400 and an original
  graphic, not a generic game logo. Upload this avatar separately from addon files.
- Description banner: `release/assets/curseforge-banner.png`, 800×300 PNG. The
  observed editor requires a width below 850 pixels. The full 1600×600 banner
  and 1280×640 GitHub Social Preview remain separate source assets.
- Brand guide: `BRANDING.md`; the owner-provided knight is preserved unchanged.
- Installable package: `ForeverMouseoverBuff-0.7.2.zip`, containing one addon
  directory with its runtime files and license. It excludes the web prototype,
  companion, tests, user data and native game/WIM files.
- Source: reviewed own-code snapshot with portable CI; proposed repository name
  `Feberdin/ForeverMouseoverBuff`. Verify name availability and ownership first.

## Metadata to select in the author portal

World of Warcraft → Addons; flavor **Forever**; supported game version **1.60.1**.
These labels are visible on the current official
[Forever file listing](https://www.curseforge.com/wow/addons/wow-forever-addons/files/all).
This confirms platform labels, not compatibility certification for this project.

Suggested categories: Buffs & Debuffs; Paladin; Chat & Communication. Confirm
which exact labels are offered in the portal. Do not mark another game flavor as
supported solely to satisfy an uploader.

Start with **Beta** while in-game acceptance is pending. CurseForge support pages
have differed on when a first beta appears in the app: check the current portal
and moderation result rather than relabeling untested work as a stable release.

## Manual publication sequence

1. Complete source review and applicable publication / privacy review. Record
   which native/in-game checks have actually run; keep the 0.7.2 release marked
   Beta while its in-game acceptance is pending. Resolve publication blockers
   before a public listing.
2. Sign into the intended CurseForge author account, choose a distinct project
   name and paste the reviewed English metadata and description.
3. Upload the original icon, choose MIT and appropriate categories.
4. Select Forever / 1.60.1 and upload the installable ZIP, not the source ZIP.
5. Add changelog, release type and optional WIM relation only if available and
   desired; WIM is not a required dependency.
6. Submit for moderation. Verify acceptance, displayed description, downloadable
   ZIP contents and flavor selection. A local ZIP is not an approved publication.
7. Record the actual project ID/URL. Add source/issues links only after a real
   repository exists. Never substitute another project's ID.

A GitHub-first route can initialize the reviewed source directory locally and
later push it to the confirmed Feberdin repository. After every push inspect the
CI run for that exact commit; do not assume local checks establish remote CI.
No `git remote`, token, CurseForge project ID or automatic publishing action is
configured in these templates. Keys, if a later upload tool needs one, must only
come from `CURSEFORGE_API_KEY`, never from committed files or chat.

## Boundaries to keep visible

The receiver switch works for every class. Buff mechanics/ranking support
Paladins only. The UI/greetings primarily target German. Ranking is optional,
self-reported and not tamper-proof; there is no public endpoint in this release.
The schema-2 local counters use twenty fixed 32-bit values, Base64 and an unkeyed
SHA-256 checksum. This is encoding with a corruption check, not encryption,
authentication or anti-cheat. Valid older counters migrate; damaged records are
preserved and statistic updates pause while buffing remains available. The event
export stays readable and separate from counter storage. Do not advertise
verified ranks, server integration or unsupported classes.
