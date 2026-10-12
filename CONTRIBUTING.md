# Contributing

Keep changes small, readable and independently testable. Do not bundle game files,
other addons, SavedVariables, logs, credentials or screenshots containing players'
private messages. Test participants and names must be synthetic.

1. Describe the expected behavior and acceptance criteria.
2. Write the smallest behavioral test and observe it fail for the intended reason.
3. Implement the minimal fix, run the focused test, then affected suites.
4. Refactor only while green. Keep regression tests.
5. Run `LUA_BIN=lua5.1 sh scripts/check-portable.sh` and the Python checks from the
   README. Record any native/in-game checks that could not be performed.
6. Update documentation, both TOCs, `App.lua` and changelog when changing a release.
7. If a source file is added, explicitly review `scripts/prepare-release.py`'s
   allowlist; unknown files must never silently enter an upload.

Lua code must run on 5.1. Python code targets 3.10+. File headers explain purpose,
inputs/outputs, invariants and debugging. Comments explain intent. Validate at
file, API, game-state and network boundaries; never log content or secret values.

Public CI excludes tests requiring native WoW/WIM source fixtures. Do not replace
those fixtures with unlicensed uploads or claim portable CI proves in-game secure
execution. Add public synthetic unit tests where feasible, and record the separate
native contract/in-game result in release review.

After pushing, verify the CI run belongs to exactly that commit and fix failures
before proceeding. There is no automatic publishing workflow; final reviewed
artifacts are submitted separately after the project/account is configured.
