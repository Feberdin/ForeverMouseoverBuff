# ✨ Forever Mouseover Buff

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

---

An independent **MIT-licensed** project. Not affiliated with Blizzard or
CurseForge. WoW names and trademarks belong to their respective owners.
