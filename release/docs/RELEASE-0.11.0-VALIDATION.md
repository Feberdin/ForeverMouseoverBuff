# 0.11.0 Beta localization validation

Purpose: record reproducible tests and release boundaries for German/English text.
Input: synthetic locale, saved preference, UI and greeting fixtures. Output: local
checks and a reviewed package. No live identities, credentials or messages are used.
Invariant: this release excludes the preexisting uncommitted seal timer changes.
Debug: run the commands below from the repository root; inspect the first failure.

## Acceptance and implementation

The existing per-character SavedVariables table stores `language=auto|deDE|enUS`.
Auto uses German only for `GetLocale()==deDE`, and English for English, unsupported
or unavailable client locales. Missing/damaged preferences reset to Auto; invalid
commands preserve the current choice. Help & Feedback has three language buttons;
`/fmb language auto|deDE|enUS` also changes the preference. Open menu and feedback
labels refresh immediately, including toggle text and badges.

`Localization.lua` is the central explicit translation catalog. It translates
addon-owned UI, chat/help, diagnostic prose and greeting templates. It does not
replace global string functions, game API identifiers, spell names/links, slash
command tokens, diagnostic codes or peer protocol tokens. Both greeting counter
languages are recognized regardless of the recipient's selected language.

The new module loads first in both TOCs and is explicitly included in the release
script's addon allowlist. The new regression suite is in the portable runner and
source-export allowlist. This validation record is included in the source export,
as required by CONTRIBUTING.md. No extra runtime dependency is introduced.

## Observed red → green

| Regression test | Exact red command | Observed behavioral failure |
| --- | --- | --- |
| `tests/test_localization.lua` initial default | `lua tests/test_localization.lua` | English client displayed `Druide` instead of `Druid`. This ran before the localization implementation. |
| Same suite, English peer grammar | `/tmp/lua-5.1.5/src/lua tests/test_localization.lua` | English formatted greeting did not pass sender/recipient recognition. Added English counter grammar alongside German/legacy grammar. |
| `tests/test_app.lua`, `language_client_default_saved_override_and_live_menu_switch` | `/tmp/lua-5.1.5/src/lua tests/test_app.lua language` | EN→DE left toggle metadata `Buff alert sound: on` rather than `Hinweiston beim Buffen: an`. Retain catalog keys and refresh toggle state on language changes. |
| Same app regression, ASCII labels | `/tmp/lua-5.1.5/src/lua tests/test_app.lua language` | English still displayed `Siegel-Ablaufton: on` rather than `Seal expiry sound: on`. Added seal/debug/upload labels to the central catalog. |

The focused green commands are `/tmp/lua-5.1.5/src/lua tests/test_localization.lua`
and `/tmp/lua-5.1.5/src/lua tests/test_app.lua language`: both exit 0, the app
regression reports one test and zero failures. Assertions remain enabled.
The suite also checks persistence, unsupported/failing locale APIs, invalid
preferences, exact format-placeholder order, German catalog coverage, open
feedback switching, English sound acknowledgements and class help. It exercises
2,880 greeting combinations (two languages, ten classes, twelve races, twelve
variants), including cross-language recognition and malformed counter rejection.

Lua 5.1 was built locally from the official 5.1.5 source because this machine's
`lua` is 5.5 and Homebrew does not provide the requested `lua@5.1` formula. The
missing interpreter attempt was an environment issue, not counted as a red test.
CI installs distro `lua5.1`; substitute that executable for the local path below.

## Full local checks

All commands below completed successfully in the isolated localization worktree:

```sh
LUA_BIN=/tmp/lua-5.1.5/src/lua sh scripts/check-portable.sh
python3 -m unittest discover -s tests -p test_release_package.py -v
python3 -m unittest discover -s tests -p test_issue_templates.py -v
python3 -m unittest discover -s companion/tests -v
PYTHONPATH=service python3 -m unittest discover -s service/tests -v
LUA_BIN=/tmp/lua-5.1.5/src/lua python3 -m unittest discover -s tests -p test_ranking_end_to_end.py -v
LUA_BIN=/tmp/lua-5.1.5/src/lua python3 -m unittest discover -s tests -p test_diagnostics_end_to_end.py -v
node --test service/tests/test_upload_core.cjs service/tests/test_upload_ui.cjs
node --check service/static/app.js
node --check service/static/upload-core.js
node --check service/static/upload.js
ruff check scripts/prepare-release.py release/assets/render-launch-0.9.0.py tests/test_release_package.py tests/test_diagnostics_end_to_end.py tests/test_issue_templates.py service companion
ruff format --check scripts/prepare-release.py release/assets/render-launch-0.9.0.py tests/test_release_package.py tests/test_diagnostics_end_to_end.py tests/test_issue_templates.py service companion
shellcheck scripts/check-portable.sh
sh -n scripts/check-portable.sh
python3 -m json.tool service/openapi.json
python3 -m json.tool curseforge/metadata.json
git diff --check
python3 scripts/prepare-release.py --version 0.11.0 --output /private/tmp/fmb-localization-reviewed-0.11.0
```

Results: 23 portable Lua suites, including 97 app tests and zero app failures;
24 package tests; eight issue-form tests; 51 companion tests; 15 service tests;
one ranking and one diagnostics end-to-end test; 14 browser-contract tests.
Ruff reports all checks passed and 23 files already formatted. Shell syntax,
shellcheck, JavaScript syntax and JSON validation pass. Packaging creates addon
and redistributable-source ZIPs using explicit reviewed allowlists. There is no
separate Lua typecheck or application compiler configured; portable execution,
syntax checks and release packaging are the applicable checks/build.

## Privacy delta and remaining client checks

The narrow source review found only the local language enum in existing storage.
There is no new endpoint, account, tracking, SDK, external resource, identity
field or automatic upload. Existing optional ranking/report paths and in-game
messaging remain unchanged. No legal exception or general platform compliance
claim follows from this technical review. The unrelated dirty seal timer/aura
work is excluded from this release and remains preserved in the original checkout.

Native WoW/WIM/chat fixture tests and live in-game behavior were not executed in
this isolated source worktree: proprietary native fixtures/client interaction are
separate from portable CI. Remaining acceptance: inspect each language in the
actual client, reload to verify persistence, switch while settings/feedback are
open, confirm English and German greetings between peers, inspect long localized
text for clipping, and verify normal spell/binding safety. Native localized spell
names may differ from the addon's chosen display language by design.

No credentials or network access are needed for these checks. `/fmb language`
shows saved/effective language; `/fmb debug on`, `/fmb status` and `/fmb diag`
provide existing fixed local diagnostic codes; turn debug off afterward. Missing
translations should be reported with the visible label and selected language,
without player chat or SavedVariables containing private data.

Final commit-specific CI, exact artifact digest, CurseForge acceptance and actual
uploaded-file verification belong to the publication receipt after commit. This
record does not claim those actions already occurred.
