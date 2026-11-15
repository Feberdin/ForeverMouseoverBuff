# 0.10.3 Beta: technical validation and publication scope

## Change and intended result

Ordinary Paladin rank IDs identify Might/Wisdom/Kings independently of optional
global localized names. An actual active, non-offspec normal SPELL book slot
remains learning evidence despite a contradictory public IsSpellKnown(false).
Future/flyout/passive slots and greater/temporary blessings are excluded; missing,
restricted and failed known-state reads remain blocking. Global metadata alone
never creates a learned spell.

In Auto, mana-class recipients receive learned Might as the final alternative
when no level-compatible preferred caster blessing is available. An explicitly
empty class profile remains disabled, manual family choices stay exact, and all
range/usability/combat/aura checks remain active. A lowest learned Might rank can
be offered below its training level, with an explicit client-eligibility notice;
training level is not asserted to be a proven minimum recipient level.

Horde greetings use the sender's race, including equivalent Scourge/Undead tokens
and twelve original Forsaken Paladin wishes. Greetings retain their existing
recipient controls, confirmation rules and length limit. The optional healing
observer skips combat-log subscription when no public unrestricted reader exists;
aura-based buff thanks remain available. No private combat-log API is probed.

## Regression evidence

Set LUA_BIN to a local Lua 5.1 executable. Run from the repository root.

```sh
"$LUA_BIN" tests/test_core.lua low_level_target_gets_lowest_known_rank_without_invented_level_limit
"$LUA_BIN" tests/test_core.lua low_level_caster_without_suitable_caster_blessing_gets_might
"$LUA_BIN" tests/test_api.lua ordinary_might_slot_survives_name_and_known_lookup_disagreement
"$LUA_BIN" tests/test_app.lua real_api_core_and_native_button_contract_select_and_skip_buff
python3 -m unittest discover -s tests -p test_release_package.py -k current_validation_report -v
```

Observed RED before the corresponding implementation: lowest-rank readiness was
false instead of true; a low-level caster received Wisdom19742 instead of
Might19740; the real book label was rejected (`expected true, got false`); the
API/Core/button contract returned NO_KNOWN_SPELL instead of READY_FALLBACK; the
sanitized report was absent from the source-export allowlist. The same focused
checks were GREEN after their minimal changes. These permanent regressions remain.
The CLEU guard includes negative tests for missing readers and restricted readers;
this record does not invent an earlier red run for pre-existing user work.
An additional release-contract test first failed because the exported portable
script omitted the current diagnostics suite; synchronizing that template made
`test_exported_portable_check_covers_current_diagnostics_suite` pass.

## Complete local verification

```sh
LUA_BIN=lua5.1 sh scripts/check-portable.sh
python3 -m unittest discover -s tests -p test_release_package.py -v
python3 -m unittest discover -s tests -p test_issue_templates.py -v
python3 -m unittest discover -s companion/tests -v
PYTHONPATH=service python3 -m unittest discover -s service/tests -v
LUA_BIN=lua5.1 python3 -m unittest discover -s tests -p test_ranking_end_to_end.py -v
LUA_BIN=lua5.1 python3 -m unittest discover -s tests -p test_diagnostics_end_to_end.py -v
node --test service/tests/test_upload_core.cjs service/tests/test_upload_ui.cjs
node --check service/static/app.js
node --check service/static/upload-core.js
node --check service/static/upload.js
python3 -m ruff check scripts/prepare-release.py release/assets/render-launch-0.9.0.py tests/test_release_package.py tests/test_diagnostics_end_to_end.py tests/test_issue_templates.py service companion
python3 -m ruff format --check scripts/prepare-release.py release/assets/render-launch-0.9.0.py tests/test_release_package.py tests/test_diagnostics_end_to_end.py tests/test_issue_templates.py service companion
shellcheck scripts/check-portable.sh
sh -n scripts/check-portable.sh
python3 -m json.tool service/openapi.json
python3 -m json.tool curseforge/metadata.json
python3 scripts/prepare-release.py --version 0.10.3 --output dist/0.10.3
git diff --check
```

All listed local checks passed for the 0.10.3 candidate. All 22 portable Lua suites
passed, including API60/60 and App96/96; Python contracts, Node tests, static checks
and package preparation passed. The portable check also
compiles all addon Lua, validates Bindings.xml and compares the two manifests.
There is no separate configured typecheck; the package generator is the build.
No runtime version bump is evidence of a successful game cast.

## Privacy and publication scope

This is a technical addon update to the existing Feberdin GitHub repository and
CurseForge project1741880, authorized by the owner on 2026-11-15. It introduces no
website/service deployment, new endpoint, automatic upload, tracking, contact
recipient or legal-text change. The existing privacy rationale in the 0.10.2
validation record remains the baseline: bounded local diagnostic codes, optional
reviewed exports, no raw errors/names/chat in diagnostic logs and no new transfer.
This scoped review is not a legal audit or a claim of complete legal compliance.

Local investigation archives, copied live/source snapshots, SavedVariables and raw
logs are excluded from Git and the explicit package allowlist. This public record
contains only synthetic regression evidence, fixed codes and portable commands.
Existing greeting and emote data flows retain their existing controls.

## Remaining acceptance and release work

Real-client casting, recipient greeting delivery and the exact native spellbook
lookup disagreement remain unverified. Offline tests prove the reproduction and
corrected decision/button contract, not a successful server cast. Keep Beta.
Native proprietary WoW/WIM/chat acceptance is separate from portable CI. No push,
CI result, GitHub release, CurseForge upload or moderation result is claimed by
this preparation report; verify the exact pushed commit and artifact hashes before
publication, then record actual platform identifiers separately.

Install the complete reviewed addon package, then /reload outside combat. Use
/fmb auto, /fmb status and /fmb diag. Roll back by reinstalling the previous complete
package and reloading; leave SavedVariables intact.
