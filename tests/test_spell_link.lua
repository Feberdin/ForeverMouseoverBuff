-- Purpose: native spell-link validation and graceful fallback on API restrictions.
-- Input: synthetic native API results; output: deterministic PASS/FAIL.
-- Invariants: no real game process, network, chat, secrets, or player identities.
-- Debug: lua tests/test_spell_link.lua [test_name]. Production link formatting
-- is never mocked: only C_Spell.GetSpellLink and public-value guards are boundaries.
local tests = {}
local plain = "|Hspell:19740|h[Segen der Macht]|h"
local colored = "|cff71d5ff|Hspell:19740:0|h[Segen der Macht]|h|r"
local function equal(actual, expected, context)
    if actual ~= expected then
        error((context or "unexpected value") .. ": expected " .. tostring(expected)
            .. ", got " .. tostring(actual), 2)
    end
end
local function fixture()
    local f = {calls = 0, result = colored}
    f.secret = setmetatable({}, {__tostring = function() error("secret printed") end})
    f.opaque = setmetatable({}, {__index = function() error("opaque indexed") end})
    f.env = setmetatable({}, {__index = _G})
    f.env.issecretvalue = function(value) return rawequal(value, f.secret) end
    f.env.canaccesstable = function(value) return not rawequal(value, f.opaque) end
    f.env.C_Spell = {GetSpellLink = function(id, ...)
        equal(id, 19740); equal(select("#", ...), 0, "do not add guessed glyph arguments")
        f.calls = f.calls + 1
        if f.throw then error("sensitive native error must never escape") end
        return f.result
    end}
    f.ns = {}
    local path = "src/ForeverMouseoverBuff/SpellLink.lua"
    local chunk
    if setfenv then chunk = assert(loadfile(path)); setfenv(chunk, f.env)
    else chunk = assert(loadfile(path, "t", f.env)) end
    chunk("ForeverMouseoverBuff", f.ns)
    f.api = f.ns.SpellLink
    return f
end

function tests.native_link_is_returned_byte_for_byte_for_the_requested_spell()
    local f = fixture()
    local link, code = f.api.Get(19740)
    equal(link, colored, "retain the exact native link, including original color")
    equal(code, nil); equal(f.calls, 1)
    f.result = plain
    equal(f.api.Get(19740), plain)
end

function tests.bare_colored_and_optional_numeric_glyph_forms_are_valid()
    local f = fixture()
    for _, link in ipairs({plain, colored,
        "|cFF71D5FF|Hspell:19740:12345|h[Segen der Macht (Rang 1)]|h|r"}) do
        equal(f.api.Valid(link, 19740), true)
        equal(f.api.Valid(link), true)
        equal(f.api.ID(link), 19740)
    end
end

function tests.other_link_types_extra_escapes_suffixes_and_malformed_fields_are_rejected()
    local f = fixture()
    for _, link in ipairs({
        "|Hitem:19740|h[Item]|h", "|Hplayer:Name|h[Name]|h",
        "before " .. plain, plain .. " after", colored .. "|r", plain .. plain,
        "|Hspell:19740|h[|cffff0000Bad]|h", "|Hspell:19740|h[|Ticon:0|t]|h",
        "|Hspell:19740|h[bad\nline]|h", "|Hspell:19740|h[]|h",
        "|Hspell:19740|hNo brackets|h", "|Hspell:19740::0|h[Bad]|h",
        "|Hspell:19740:1:2|h[Unknown extra field]|h", "|Hspell:19740:abc|h[Bad]|h",
        "|Hspell:19740:-1|h[Bad]|h", "|Hspell:0|h[Bad]|h",
        "|Hspell:-1|h[Bad]|h", "|Hspell:019740|h[Bad]|h",
        "|Hspell:1000000001|h[Bad]|h", "|Hspell:19740:1000000001|h[Bad]|h",
        "|cffffff|Hspell:19740|h[Bad color]|h|r", "|cff71d5ff" .. plain,
        plain .. "|r", "|cnNORMAL_FONT_COLOR:" .. plain .. "|r",
        "|Hspell:19740|h[" .. string.rep("x", 1100) .. "]|h"
    }) do
        equal(f.api.Valid(link), false, "malformed or non-spell link rejected")
        equal(f.api.ID(link), nil)
    end
end

function tests.mismatched_native_spell_id_is_not_trusted()
    local f = fixture()
    f.result = "|cff71d5ff|Hspell:20217|h[Segen der Könige]|h|r"
    local link, code = f.api.Get(19740)
    equal(link, nil); equal(code, "SPELL_LINK_MISMATCH")
    equal(f.api.Valid(f.result, 19740), false)
    equal(f.api.Valid(f.result, 20217), true)
end

function tests.invalid_ids_never_reach_the_native_api()
    local f = fixture()
    for _, id in ipairs({0, -1, 1.5, math.huge, 0 / 0, 1000000001, "19740", {}, f.secret}) do
        local link, code = f.api.Get(id)
        equal(link, nil); equal(code, "SPELL_LINK_INVALID_ID")
        equal(f.api.Valid(plain, id), false)
    end
    local link, code = f.api.Get(nil)
    equal(link, nil); equal(code, "SPELL_LINK_INVALID_ID"); equal(f.calls, 0)
end

function tests.missing_unknown_and_throwing_native_api_fall_back_to_fixed_codes()
    local f = fixture()
    f.result = nil
    local link, code = f.api.Get(19740)
    equal(link, nil); equal(code, "SPELL_LINK_UNAVAILABLE")
    f.throw = true
    link, code = f.api.Get(19740)
    equal(link, nil); equal(code, "SPELL_LINK_API_FAILED")
    f.env.C_Spell = nil
    link, code = f.api.Get(19740)
    equal(link, nil); equal(code, "SPELL_LINK_API_UNAVAILABLE")
end

function tests.secret_and_opaque_api_values_never_get_parsed_or_exposed()
    local f = fixture()
    f.result = f.secret
    local link, code = f.api.Get(19740)
    equal(link, nil); equal(code, "SPELL_LINK_RESTRICTED")
    equal(f.api.Valid(f.secret), false); equal(f.api.ID(f.secret), nil)
    for _, namespace in ipairs({f.secret, f.opaque, {GetSpellLink = f.secret},
        {GetSpellLink = "invalid"}, "invalid"}) do
        f.env.C_Spell = namespace
        link, code = f.api.Get(19740)
        equal(link, nil); equal(code, "SPELL_LINK_API_UNAVAILABLE")
    end
    f.env.issecretvalue = nil
    equal(f.api.Valid(plain), false); equal(f.api.ID(plain), nil)
end

function tests.public_malformed_native_results_fall_back_without_constructing_a_link()
    local f = fixture()
    for _, value in ipairs({false, 123, {}, "Segen der Macht", plain .. " trailing"}) do
        f.result = value
        local link, code = f.api.Get(19740)
        equal(link, nil); equal(code, "SPELL_LINK_INVALID")
    end
end

local requested, names = arg and arg[1], {}
for name in pairs(tests) do if not requested or name == requested then names[#names + 1] = name end end
table.sort(names)
assert(#names > 0, "unknown test name")
local failures = 0
for _, name in ipairs(names) do
    local ok, reason = pcall(tests[name])
    if ok then print("PASS " .. name)
    else failures = failures + 1; io.stderr:write("FAIL " .. name .. ": " .. tostring(reason) .. "\n") end
end
print(string.format("RESULT %d/%d passed", #names - failures, #names))
os.exit(failures == 0 and 0 or 1)
