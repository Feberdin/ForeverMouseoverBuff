# CurseForge submission record and update guide

Historical record from **2026-10-12**. The GitHub repository and v0.7.2 release are public.
CurseForge project **1741880** (`forever-mouseover-buff`) and file **9150370**
(`ForeverMouseoverBuff-0.7.2.zip`, Beta, Forever 1.60.1) have been submitted.
**At that recorded date, CurseForge moderation was pending**; this historical
record does not establish the current moderation state.
The GitHub source link is saved in the project. Ranking stays local.

- [GitHub source](https://github.com/Feberdin/ForeverMouseoverBuff)
- [GitHub v0.7.2](https://github.com/Feberdin/ForeverMouseoverBuff/releases/tag/v0.7.2)
- [CurseForge project](https://www.curseforge.com/wow/addons/forever-mouseover-buff)

The following notes document the inputs and repeatable steps for later updates.

## Authorized update: 0.9.0 Beta

On **2026-10-31**, the owner explicitly requested completion for WoW Forever and
publication on CurseForge with new product images. Publish the update to the
existing project **1741880** (`forever-mouseover-buff`); no new project is needed.
The update adds a short introduction and deliberate key setup inside the addon.

Local installation in the active Forever AddOns directory is complete: 26 files,
version 0.9.0, Interface 16001, runtime bytes matched to the reviewed source.
The installed client is 1.60.1.70685. SavedVariables were not modified. File
installation does not establish successful loading or real input delivery in WoW.

Keep the authorized publication marked **Beta** while live acceptance remains
open: keyboard/mouse bindings, modifier combinations, occupied-key rejection,
Escape/window/combat cancellation, account/character persistence and introduction
re-opening. The local evidence is in `docs/release-polish-validation.md`.

Final release images, source commit, exact-commit CI and package hashes must be
checked before upload. This preparation record does not claim a completed upload,
moderation approval or stable-release acceptance. Record the actual file ID,
release URL, download hash and platform status after publication; populate the
public release URL only after the release exists; see the dated publication record below.

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
- New 0.9.0 launch series: `release/assets/launch-{hero,intro,keybinding}-0.9.0.png`,
  each 1600×900 and below 2 MiB. Provenance and reproduction: `release/assets/launch-0.9.0.md`.
  The interface images are code-derived previews, not in-game screenshots.
- Legacy description banner: `release/assets/curseforge-banner.png`, 800×300 PNG. The
  observed editor requires a width below 850 pixels. The full 1600×600 banner
  and 1280×640 GitHub Social Preview remain separate source assets.
- Brand guide: `BRANDING.md`; the owner-provided knight is preserved unchanged.
- Prepared installable package: `ForeverMouseoverBuff-0.9.0.zip`, containing one addon
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
   which native/in-game checks have actually run; keep the candidate marked
   Beta while its broader in-game acceptance is ongoing. Resolve publication blockers
   before a public listing.
2. Sign into the intended CurseForge author account, open existing project
   **1741880** and update the reviewed English description and release images.
3. Upload the original icon, choose MIT and appropriate categories.
4. Select Forever / 1.60.1 and upload the installable ZIP, not the source ZIP.
5. Add changelog, release type and optional WIM relation only if available and
   desired; WIM is not a required dependency.
6. Submit for moderation. Verify acceptance, displayed description, downloadable
   ZIP contents and flavor selection. A local ZIP is not an approved publication.
7. Record the new file ID and its actual download/status under project **1741880**.
   Preserve the existing source/issues links and verify the downloaded ZIP hash.

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

## Publication record — 2026-10-31

- Release source: commit `98c2b663173b5083274ce0808d9e596cad30e2a1`, tag `v0.9.0`.
- GitHub prerelease and both ZIPs are public: [0.9.0 Beta](https://github.com/Feberdin/ForeverMouseoverBuff/releases/tag/v0.9.0).
- Exact-source CI passed for [main](https://github.com/Feberdin/ForeverMouseoverBuff/actions/runs/41207149498) and [tag](https://github.com/Feberdin/ForeverMouseoverBuff/actions/runs/41207149531).
- CurseForge file **9384236**, **Beta**, **Forever 1.60.1**, uploaded successfully.
  Status at this check: **Under Review**. Automatic publication after moderation is enabled.
  This record does not claim moderation approval; the public main file still showed 0.8.0.
- The English/German description and [three-image gallery](https://www.curseforge.com/wow/addons/forever-mouseover-buff/gallery) are publicly visible.
- The new CDN ZIP was downloaded and matched the reviewed package byte for byte.
  Addon SHA-256: `81c6397f9f39d2e3ba309a7e1c0b81d83e2864f6c8a8c857d7c0206a4a5e0004`.
- Source ZIP SHA-256: `9e705feda31798789d15758b23207f7a5fba9b98c2f2fd92cb5e2c4f4d3ade91`.
  Published ZIPs remain bound to the release commit above; this later publication record does not replace them.

The three image URLs at tag `v0.9.0` were fetched and matched their local files.

Check timestamp: `2026-10-31T13:54:09+00:00`.

### Moderation update — 2026-10-31T13:56:23+00:00

CurseForge now shows file **9384236** as **Approved**. The public
[0.9.0 Beta file page](https://www.curseforge.com/wow/addons/forever-mouseover-buff/files/9384236) is accessible and identifies the new version
as the **Main File** for Forever 1.60.1. Publication is complete. The Beta label
continues to reflect the remaining real-client acceptance described above.
