# CurseForge submission record and update guide

Recorded on **2026-10-12**. The GitHub repository and v0.7.2 release are public.
CurseForge project **1741880** (`forever-mouseover-buff`) and file **9150370**
(`ForeverMouseoverBuff-0.7.2.zip`, Beta, Forever 1.60.1) have been submitted.
**CurseForge moderation is still pending**; submission is not approval.
The GitHub source link is saved in the project. Ranking stays local.

- [GitHub source](https://github.com/Feberdin/ForeverMouseoverBuff)
- [GitHub v0.7.2](https://github.com/Feberdin/ForeverMouseoverBuff/releases/tag/v0.7.2)
- [CurseForge project](https://www.curseforge.com/wow/addons/forever-mouseover-buff)

The following notes document the inputs and repeatable steps for later updates.

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
- Source: reviewed own-code snapshot with portable CI in
  [Feberdin/ForeverMouseoverBuff](https://github.com/Feberdin/ForeverMouseoverBuff).

## Metadata to select in the author portal

World of Warcraft → Addons; flavor **Forever**; supported game version **1.60.1**.
These labels are visible on the current official
[Forever file listing](https://www.curseforge.com/wow/addons/wow-forever-addons/files/all).
This confirms platform labels, not compatibility certification for this project.

Suggested categories: Buffs & Debuffs; Paladin; Chat & Communication. Confirm
which exact labels are offered in the portal. Do not mark another game flavor as
supported solely to satisfy an uploader.

Keep **Beta** while broader in-game acceptance is ongoing. CurseForge support pages
have differed on when a first beta appears in the app: check the current portal
and moderation result rather than relabeling untested work as a stable release.

## Manual publication sequence

1. Complete source review and applicable publication / privacy review. Record
   which native/in-game checks have actually run; keep the 0.7.2 release marked
   Beta while its broader in-game acceptance is ongoing. Resolve publication blockers
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

After every GitHub push, inspect the CI run for that exact commit; local checks
do not establish remote CI. The v0.7.2 release commit is
`6d97ec832b947aea5516758a14968dba9fc8f97d`; its
[CI run 38304352908](https://github.com/Feberdin/ForeverMouseoverBuff/actions/runs/38304352908)
completed successfully. Subsequent documentation changes require their own CI
check after a push and do not change that historical result.

No credential or automatic publishing action is stored in these templates. Keys,
if a later upload tool needs one, must only come from `CURSEFORGE_API_KEY`, never
from committed files or chat.

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
