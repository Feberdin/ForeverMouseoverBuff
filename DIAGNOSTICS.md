# Local diagnostic protocol

Since 0.7.2, Forever Mouseover Buff keeps a bounded diagnostic ledger for local
troubleshooting. The addon and the separate reader make no web requests for this
feature. The ranking service and participant registration are not required.

## In the game

- `/fmb diag`: storage status, counters and the latest five structured events.
- `/fmb status`: broader addon/client/binding status.
- `/fmb debug on` / `/fmb debug off`: optional local chat output. The bounded
  saved log works with debug chat disabled.

After an update, reload once to load the new addon. Reproduce the problem at
a safe moment, then perform another `/reload` or log out normally. WoW then writes the saved file. Reading it before that returns the
previous snapshot, not live game memory. A crash can leave recent events unsaved.
Neither the addon nor the reader forces a reload.

## Read the saved snapshot locally

Requirements: the source package and Python 3.10+. No third-party Python libraries.
Find the character's `ForeverMouseoverBuff.lua` under the active client's
`WTF/Account/.../SavedVariables` directory. Choose the `.lua` file, not its backup.
Replace the example path with that exact file; paths with spaces need quotes.

```sh
python3 companion/companion.py diagnostics --saved-variables "/path/to/ForeverMouseoverBuff.lua"
python3 companion/companion.py diagnostics --saved-variables "/path/to/ForeverMouseoverBuff.lua" --json
```

The second command is suitable for a local assistant or script. It reads only,
never executes Lua, never modifies SavedVariables and never invokes ranking sync.
Do not upload the whole SavedVariables file. The reader's normalized output is a
small diagnostic projection; other saved fields are ignored.

## Schema 2

The addon owns `ForeverMouseoverBuffDB.diagnostics`:

| Field | Meaning / bound |
| --- | --- |
| `schema`, `version` | Format 2 and strict numeric addon version |
| `events` | At most 64 records in chronological sequence |
| `events[].sequence` | Bounded increasing diagnostic sequence, not a buff count |
| `events[].code` | Explicit fixed-code allowlist |
| `events[].severity` | `INFO`, `WARN` or `ERROR`, derived from that code |
| `events[].origin` | Fixed addon module name, derived from that code |
| `events[].timestamp` | Optional public server Unix seconds; omitted if unavailable |
| `codes` | At most 40 legacy transition codes for compatibility |
| `attempts`, `confirmed`, `failed` | Diagnostic lifecycle counts, each at most one billion |
| `status` | Allowlisted booleans plus strict client version/build/interface |
| `fallbackReason` | Optional fixed code for the available fallback |

Status flags cover enabled/debug/sound, three independent greeting switches,
seal sound, ranking opt-in and button/router readiness. Key binding names,
player names, GUIDs, recipients, messages, spells' protected values and raw API
errors are absent. This is an FMB diagnostic log, not a collector for all WoW or
third-party addon errors. Diagnostic counters are not the community ranking.

Consecutive duplicate codes are coalesced. Alternating repetitions of the same
code are limited to one structured event per two seconds. If the monotonic clock
cannot be read, a code is recorded at most once per session. The oldest records
are removed at the ring limit, so this is recent diagnostic history, not a full
audit trail. `DIAGNOSTIC_STARTED` marks a new initialized session.

Recognized legacy codes/counters migrate into this bounded format. Unsupported or
unreadable diagnostic storage stays untouched; an in-memory status remains
available and buffing can continue. Unknown diagnostic text is never persisted.
The reader recognizes the older format and labels it as legacy.

## Interpreting a result

A successful reader exit means the snapshot was read and normalized. Inspect its
version, warnings and event severity; it does not mean the addon had no errors.
A `CAST_REQUESTED` is only an attempt. A correlated public success event produces
`CAST_CONFIRMED`; that still does not prove the target aura or server-verified rank.

Missing timestamps mean the clock was unavailable, not that the event happened
at time zero. A stale file needs a new user-initiated reload/logout. An old version
in the file may be from before the addon update was loaded.

For a reader error, use the fixed error code and the next-step hint. Check the
selected client/character, file permissions and whether WoW is currently writing.
Do not repair Lua by hand, reset counters or disclose private data to bypass it.

## Reproduce the automated checks

```sh
lua5.1 tests/test_diagnostics.lua
lua5.1 tests/test_app.lua
python3 -m unittest discover -s companion/tests -p test_diagnostics.py -v
LUA_BIN=lua5.1 python3 -m unittest discover -s tests -p test_diagnostics_end_to_end.py -v
```

Tests use synthetic state and files. Running-client acceptance remains separate;
this protocol cannot observe unsaved game memory or guarantee every beta API works.
