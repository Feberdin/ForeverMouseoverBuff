# Forever Mouseover Buff

![Forever Mouseover Buff: golden cursor and the original Feberdin knight logo](release/assets/brand-banner.png)

**[Deutsch](README.de.md)** · [Quickstart](#-start-in-a-minute) · [Message controls](#-three-separate-message-controls) · [Changelog](CHANGELOG.md)

**A useful blessing. A personal greeting. A quieter chat.**

Choose a learned Paladin blessing for the friendly player under your mouse.
Other classes can install Forever Mouseover Buff simply to decline its automatic
greetings.

**0.7.2 Beta · WoW Forever 1.60.1 · Interface 16001**  
The interface and greetings are primarily German. In-game acceptance of this
release is still pending; automated checks do not replace a running-client test.

## 🛡️ What it does

- **Mouseover blessings:** outside your own combat, choose a useful learned
  Blessing of Might, Wisdom or Kings from the supported class presets.
- **Respect existing buffs:** selection uses readable target information and
  preserves existing blessings. When essential information is unclear or
  protected, it stops with a reason.
- **Combat binding:** once learned, Kings is available on the same mouseover key
  during your combat. This is a fixed binding, without dynamic buff selection.
- **Helpful feedback:** a blocked attempt gives a short explanation and an
  optional sound. A separate cue can announce an observed natural seal expiry.
- **Personal greetings:** after a confirmed FMB buff, send a rotating German
  greeting with appropriate class/race language and the actual spell link when
  available.

**Every cast requires a real keypress.** Hovering alone never casts a spell.
Buff selection and statistics currently support **Paladins only**. Receiver-only
use works for **every class**; the other greeting styles do not add their spells.

![Hover a player, press and release a key, cast a blessing. Greetings are optional.](release/assets/how-it-works.png)

## 🚀 Start in a minute

1. Install the addon in your active Forever `Interface/AddOns` folder. For a
   manual ZIP installation, check that the folder contains
   `ForeverMouseoverBuff/ForeverMouseoverBuff.toc`.
2. Restart WoW after first installation. An update normally needs `/reload`.
3. Enter `/fmb` to open the controls.
4. Paladins: assign a free key under **Key Bindings → Forever Mouseover Buff**.
   Hover a friendly player, then press and release that key.
5. Only want to decline greetings? Enter `/fmb receive off`. No buff binding is
   needed, and your character can be any class.

Use `/fmb auto` for automatic selection outside combat, or choose `/fmb might`,
`/fmb wisdom` or `/fmb kings`. `/fmb on` and `/fmb off` control buff functionality.

## 💬 Three separate message controls

| What you want | Command | What changes |
| --- | --- | --- |
| Stop sending automatic greetings | `/fmb whisper off` | Your outgoing greeting messages |
| Decline automatic FMB greetings | `/fmb receive off` | Greetings addressed to you |
| Hide your own greetings in normal chat | `/fmb outgoing off` | Your local chat display only |

Replace `off` with `on` to restore that setting. All three are independent.
Your own greetings are hidden from ordinary chat by default.

Normal personal whispers stay unaffected. WIM is optional. Its own conversation
settings still determine whether outgoing greetings open a window or enter its
history. The receiver switch recognizes compatible, marked FMB greetings, rather
than every addon or older unmarked message.

## 🔔 Sounds you control

- `/fmb sound on` or `/fmb sound off`: feedback for blocked buff attempts.
- `/fmb soundtest`: check the feedback tone while it is enabled.
- `/fmb seal on` or `/fmb seal off`: the separate seal-expiry reminder.

The seal cue follows an observed natural expiry. It does not sound simply because
you log in without an active seal.

## 📊 Local counts and optional ranking experiments

`/fmb stats` shows local, unverified counts of successful FMB buffs. Version 0.7.1
stores the twenty supported spell counters as binary data encoded in Base64,
with a SHA-256 checksum. Valid older counters migrate automatically. Damaged or
unreadable records stay unchanged; statistic updates pause while buffing remains
available.

**This is encoding with a corruption check, not encryption or anti-cheat.** A
file owner can create another payload and matching checksum. Counts remain
community/self-reported and cannot prove genuine casts.

Ranking export is **off by default**. `/fmb ranking on` starts collecting optional
export events; `/fmb ranking help` explains the separate companion and local test
workflow. The event export remains readable. No recipients or chat contents are
exported. The addon makes no web requests, and **no public ranking service is
provided**. Buffing requires neither companion nor service.

## 🎯 Outside-combat selection

| Friendly target | First choice | Alternative |
| --- | --- | --- |
| Warrior or Rogue | Might | Kings |
| Mage, Priest or Warlock | Wisdom | Kings |
| Hunter, Paladin, Shaman or Druid | Kings | Wisdom |

These are class presets, not talent or role detection. An existing same-family
blessing is conservatively preserved; a useful own blessing stays in place.
The addon does not calculate whether another player's talents make a buff stronger.
Missing or protected target data can prevent selection. During your own combat,
the key uses fixed learned Kings without this automatic selection.

## 🧭 Local diagnostics

`/fmb diag` shows the current diagnostic status and latest five events. FMB keeps
a bounded local log of fixed codes, severity, module, optional public timestamps,
cast-attempt counts and a small settings/client-version snapshot. It never records
player names, GUIDs, whisper text or raw API errors. The log is active without chat
spam; `/fmb debug on` only adds local chat output.

WoW writes SavedVariables to disk on `/reload` or logout. The separate local reader
can inspect that saved snapshot without starting the ranking service or uploading
anything. It cannot read live game memory. An old file is not a live health check.

## ❓ Common questions

**Can I buff a player who is fighting?**  
Yes, their combat state alone does not prevent it. Selection still needs usable
target information. Your own combat switches the binding to learned Kings.

**What should I include in a bug report?**  
Use `/fmb status`, `/fmb help` and temporarily `/fmb debug on`. Share your version,
client build, reproduction steps and fixed diagnostic code.
Turn logging back off with `/fmb debug off`. Never share complete SavedVariables,
private whispers, tokens or access backups. Preserve damaged statistics before
attempting recovery; do not reset them just to hide an error.

**Do I need WIM, a companion or an account?**  
No. The addon can buff and manage greetings on its own. WIM is optional. The
Python companion and local web service are separate ranking experiments and are
not included in the installable addon ZIP.

**Why is there no online rank?**  
No public ranking endpoint is provided. See the [companion guide](companion/README.md)
and [local service guide](service/README.md) only if you want to run the experiment.
`/fmb ranking off` clears queued export events; stop a running companion immediately
and reload/logout to write the changed export setting to disk.

## 🧰 Support and contribution

A useful report includes the addon version, Forever build, expected result,
reproduction steps and the fixed code from `/fmb status`. Use a synthetic example
whenever possible. Never attach complete SavedVariables or private conversations.
See [Contributing](CONTRIBUTING.md) and [Security](SECURITY.md).

Read the [diagnostic protocol and reader commands](DIAGNOSTICS.md) for local troubleshooting.

## Develop and test

Requirements: Lua 5.1, Python 3.10+, `xmllint`; optional Node.js, Ruff and ShellCheck
for developer checks. There are no addon or Python runtime dependencies.

```sh
LUA_BIN=lua5.1 sh scripts/check-portable.sh
python3 -m unittest discover -s tests -p test_release_package.py -v
python3 -m unittest discover -s companion/tests -v
PYTHONPATH=service python3 -m unittest discover -s service/tests -v
LUA_BIN=lua5.1 python3 -m unittest discover -s tests -p test_ranking_end_to_end.py -v
LUA_BIN=lua5.1 python3 -m unittest discover -s tests -p test_diagnostics_end_to_end.py -v
node --test service/tests/test_upload_core.cjs service/tests/test_upload_ui.cjs
mkdir -p dist
python3 scripts/prepare-release.py --version 0.7.2 --output dist/review-0.7.2
```

The public CI runs the portable tests. Proprietary native WoW UI and third-party
WIM source fixtures are intentionally excluded. Their three local contract suites
(native action, WIM integration, chat integration) therefore are **not reproduced
by public CI**; full in-game acceptance remains a separate release check.

The reviewed source snapshot is intended for a future repository named
`Feberdin/ForeverMouseoverBuff`; this does not claim that a remote already exists.
No credentials or publishing jobs are configured. See
[submission preparation](curseforge/submission.md), [contributing](CONTRIBUTING.md)
and [security notes](SECURITY.md).

## License

Original project code: [MIT](LICENSE). The Feberdin knight is the shared author
identity; see the [brand guide](BRANDING.md).
WoW, spell names and trademarks remain with their respective owners. This is an
independent addon and not an official Blizzard or CurseForge product.
