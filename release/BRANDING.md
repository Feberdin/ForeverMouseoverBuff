# Feberdin addon identity

The original gold/red knight and FEBERDIN wordmark are the common author identity
for Feberdin's own addons. Each addon retains its own functional symbol; the
knight connects the family. Do not redraw, recolor, stretch or remove the wordmark.

## Assets

| Asset | Size | Placement |
| --- | --- | --- |
| `release/assets/feberdin-knight.png` | 4903 × 4258, transparent | Unchanged master for all own addons |
| `release/assets/project-icon.png` | 400 × 400 | CurseForge project avatar, symbol plus knight |
| `release/assets/brand-banner.png` | 1600 × 600 | README and description header |
| `release/assets/curseforge-banner.png` | 800 × 300 | CurseForge description (editor requires width below 850 px) |
| `release/assets/social-preview.png` | 1280 × 640, under 1 MB | GitHub repository Social Preview |
| `release/assets/how-it-works.png` | 1600 × 420 | Three-step illustrated usage guide |

Matching SVG sources are included for the five layouts. They contain the original
knight as an embedded PNG where needed, with no external resources or scripts.
This preserves its exact appearance. The illustrations are branding/instructions,
not screenshots or proof of in-game functionality.

## Reuse for another own addon

1. Keep the unchanged master knight and its aspect ratio.
2. Replace the functional symbol and product name, retaining the knight placement.
3. Use the shared dark green `#0D2427`, pale gold `#E7C87F` and mint `#91C6B3`.
   The knight retains its original red and gold colors.
4. Keep the square avatar's knight at the lower right, with clear space around it.
   Headers place it before the Feberdin author line. Never crop its wordmark.
5. Export a 400 × 400 PNG avatar and 1280 × 640 social preview. Inspect small sizes.
6. Describe the actual supported behavior and current release status. Do not use
   fabricated approval, download-count or passing-CI badges.
7. For adaptations of another author's addon, retain their name, license and
   attribution; this family identity does not claim ownership of upstream work.

The software license does not imply endorsement or grant rights to present a
third-party project as an official Feberdin project. Do not claim trademark
registration. The logo was supplied by the project owner for this identity.

## Platform checklist

GitHub: embed the banner with a relative path in the root README; upload the
social preview separately in repository settings once the repository exists.
Suggested topics: `wow-addon`, `wow-forever`, `paladin`, `mouseover`, `lua`, `buffs`.
Suggested About text: "Mouseover Paladin blessings, personal greetings and
recipient controls for every class. Built for WoW Forever."

CurseForge: English description first, German second; use **Buffs & Debuffs**,
**Paladin**, **Chat & Communication**. Upload the avatar through the project form.
Insert any descriptive image using an actual uploaded asset URL, never an invented
GitHub/CDN address. Source/Issues links are separate from file downloads.

The prepared descriptions remain Beta; there is no public ranking endpoint.

## Provenance and checks

The PNG master is byte-identical to the owner-supplied original. SHA-256:
`44d1e9c89f581ae4e6d195e089a3b0903e4acea1cec7609e15be77957a57ba47`.

The other graphics extend the original cursor SVG design with the unmodified
knight. Validate XML, check PNG dimensions/byte size, and inspect desktop and
small-size rendering after every edit. No AI redraw of the knight was used.

References: [GitHub images](https://docs.github.com/en/get-started/writing-on-github/getting-started-with-writing-and-formatting-on-github/basic-writing-and-formatting-syntax),
[GitHub social preview](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/customizing-your-repositorys-social-media-preview),
[CurseForge moderation](https://support.curseforge.com/support/solutions/articles/9000197279-moderation-policies).
