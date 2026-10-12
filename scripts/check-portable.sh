#!/bin/sh
# Purpose: public addon checks without bundled native WoW or WIM source fixtures.
# Input: source snapshot and LUA_BIN (default lua5.1). Output: failing exit or PASS.
# Invariant: compile/test only; never touch WoW, SavedVariables or the network.
# Debug: LUA_BIN=lua5.1 sh scripts/check-portable.sh; first failing suite is named.
set -eu
project_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)
cd "$project_root"
lua_bin=${LUA_BIN:-lua5.1}
command -v "$lua_bin" >/dev/null || { printf '%s\n' 'ERROR: Lua 5.1 missing. Set LUA_BIN.' >&2; exit 1; }
command -v xmllint >/dev/null || { printf '%s\n' 'ERROR: xmllint missing. Install libxml2 tools.' >&2; exit 1; }
"$lua_bin" -v
# loadfile compiles own source; it cannot run game globals here.
for source_file in src/ForeverMouseoverBuff/*.lua; do
    "$lua_bin" - "$source_file" <<'LUA'
assert(loadfile(arg[1]))
LUA
done
xmllint --nonet --noout src/ForeverMouseoverBuff/Bindings.xml
cmp src/ForeverMouseoverBuff/ForeverMouseoverBuff.toc src/ForeverMouseoverBuff/ForeverMouseoverBuff_Camelot.toc
for suite in core api counter_codec stats spell_link ranking_export greeting_catalog greetings recipient chat_display whisper seal_reminder diagnostics feedback theme menu app; do
    printf 'INFO: portable tests/test_%s.lua\n' "$suite"
    "$lua_bin" "tests/test_$suite.lua"
done
printf '%s\n' 'PASS: seventeen portable Lua suites. Native WoW/WIM/chat contracts and in-game acceptance are separate.'
