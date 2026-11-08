-- Purpose: prove language resolution, the key-preserving lookup and the saved setting.
-- Input: synthetic saved settings, client locales and a fake logger; output: PASS/FAIL.
-- Invariants: German text never changes under Auto on a German client or under "de".
-- Debug: lua tests/test_locale.lua [test_name] from the project root.
local tests = {}
local function equal(actual, expected, why)
    assert(actual == expected, (why or "value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local samples = {
    "Buffs & Taste", "Taste wählen", "Grüße & Chat", "Mouseover-Aktion aktiv",
    "Unbekannter Befehl. /fmb help zeigt die verfügbaren Befehle.",
}
local function load(clientLocale, saved)
    local ns = {db = saved or {}, logged = {}}
    ns.Log = function(_, code) ns.logged[#ns.logged + 1] = code end
    if clientLocale == false then _G.GetLocale = nil
    else _G.GetLocale = function() return clientLocale end end
    assert(loadfile("src/ForeverMouseoverBuff/Locale.lua"))("ForeverMouseoverBuff", ns)
    return ns, ns.Locale, ns.L
end

tests.resolve_follows_the_client_locale_in_auto = function()
    local _, Locale = load("deDE")
    for _, case in ipairs({{"deDE", "de"}, {"enUS", "en"}, {"enGB", "en"}, {"frFR", "en"},
        {"ruRU", "en"}, {"zhCN", "en"}, {"ptBR", "en"}}) do
        equal(Locale.Resolve(nil, case[1]), case[2], "nil setting with " .. case[1])
        equal(Locale.Resolve("auto", case[1]), case[2], "auto setting with " .. case[1])
    end
end

tests.resolve_manual_setting_overrides_the_client_locale = function()
    local _, Locale = load("deDE")
    equal(Locale.Resolve("de", "enUS"), "de")
    equal(Locale.Resolve("en", "deDE"), "en")
    equal(Locale.Resolve("de", nil), "de")
    equal(Locale.Resolve("en", nil), "en")
end

tests.resolve_treats_invalid_settings_as_auto = function()
    local _, Locale = load("deDE")
    for _, bad in ipairs({"EN", "english", "xx", "", 5, true}) do
        equal(Locale.Resolve(bad, "deDE"), "de", "setting " .. tostring(bad) .. " on deDE")
        equal(Locale.Resolve(bad, "enUS"), "en", "setting " .. tostring(bad) .. " on enUS")
    end
    equal(Locale.Resolve({}, "enUS"), "en", "table setting on enUS")
end

tests.resolve_unknown_client_locale_stays_german_and_names_the_reason = function()
    local _, Locale = load("deDE")
    -- ipairs stops at nil, so the absent client locale is checked on its own.
    local language, reason = Locale.Resolve(nil, nil)
    equal(language, "de", "absent client"); equal(reason, "LOCALE_CLIENT_UNKNOWN", "reason for absent client")
    for _, bad in ipairs({"", "de", "deutsch", "DEDE", "de-DE", 7, false}) do
        language, reason = Locale.Resolve(nil, bad)
        equal(language, "de", "client " .. tostring(bad))
        equal(reason, "LOCALE_CLIENT_UNKNOWN", "reason for client " .. tostring(bad))
    end
    local language, reason = Locale.Resolve(nil, "deDE")
    equal(language, "de"); equal(reason, nil, "no reason for a valid client locale")
end

tests.effective_language_reads_the_saved_setting_and_the_client = function()
    local ns, Locale = load("enUS")
    equal(Locale.Effective(), "en", "auto on an English client")
    ns.db.language = "de"
    equal(Locale.Effective(), "de", "manual German on an English client")
    ns.db.language = nil
    _G.GetLocale = function() return "deDE" end
    equal(Locale.Effective(), "de", "auto on a German client")
    ns.db.language = "en"
    equal(Locale.Effective(), "en", "manual English on a German client")
    ns.db = nil
    equal(Locale.Effective(), "de", "before initialization the client decides")
end

tests.effective_without_getlocale_logs_once_and_stays_german = function()
    local ns, Locale = load(false)
    equal(Locale.Effective(), "de")
    equal(Locale.Effective(), "de")
    equal(#ns.logged, 1, "one diagnostic per session")
    equal(ns.logged[1], "LOCALE_CLIENT_UNKNOWN")
    _G.GetLocale = function() return 42 end
    equal(Locale.Effective(), "de", "non-string client locale")
    equal(#ns.logged, 1, "still one diagnostic per session")
end

tests.lookup_returns_the_german_key_unchanged_in_german = function()
    local ns, _, L = load("deDE")
    for _, key in ipairs(samples) do equal(L[key], key, key) end
    ns.db.language = "de"
    for _, key in ipairs(samples) do equal(L[key], key, key .. " with manual de") end
end

tests.lookup_returns_the_key_in_english_until_a_translation_exists = function()
    local _, _, L = load("enUS")
    for _, key in ipairs(samples) do equal(L[key], key, key) end
end

tests.registered_translations_apply_in_english_only = function()
    local ns, Locale, L = load("enUS")
    equal(Locale.Register("en", {["Taste wählen"] = "Choose key"}), true)
    equal(L["Taste wählen"], "Choose key")
    equal(L["Grüße & Chat"], "Grüße & Chat", "untranslated key stays German")
    ns.db.language = "de"
    equal(L["Taste wählen"], "Taste wählen", "German never consults the English table")
    ns.db.language = nil
    _G.GetLocale = function() return "deDE" end
    equal(L["Taste wählen"], "Taste wählen", "auto on deDE never consults the English table")
end

tests.register_rejects_invalid_languages_and_tables = function()
    local _, Locale, L = load("enUS")
    equal(Locale.Register("de", {["Taste wählen"] = "x"}), false, "the default language has no table")
    equal(Locale.Register("fr", {["Taste wählen"] = "x"}), false, "unknown language")
    equal(Locale.Register("en", "not a table"), false)
    equal(Locale.Register("en", {["Taste wählen"] = 5}), false, "non-string value")
    equal(Locale.Register("en", {[5] = "x"}), false, "non-string key")
    equal(L["Taste wählen"], "Taste wählen", "rejected tables leave the lookup untouched")
    equal(Locale.Register("en", {["Taste wählen"] = "Choose key"}), true)
    equal(Locale.Register("en", {["Entfernen"] = "Remove"}), true, "a second table merges")
    equal(L["Taste wählen"], "Choose key"); equal(L["Entfernen"], "Remove")
end

tests.lookup_ignores_non_string_keys_and_never_stores_keys = function()
    local _, _, L = load("enUS")
    equal(L[5], nil); equal(L[true], nil)
    equal(L["Taste wählen"], "Taste wählen")
    equal(rawget(L, "Taste wählen"), nil, "lookups must not cache into the table")
    equal(next(L), nil, "the lookup table itself stays empty")
end

tests.set_accepts_auto_de_en_and_rejects_everything_else = function()
    local ns, Locale = load("enUS")
    equal(Locale.Set("en"), true); equal(ns.db.language, "en")
    equal(Locale.Set("de"), true); equal(ns.db.language, "de")
    equal(Locale.Set("auto"), true); equal(ns.db.language, nil, "auto is stored as absence")
    for _, bad in ipairs({"EN", "english", "", "xx", 5, true}) do
        ns.db.language = "en"
        equal(Locale.Set(bad), false, "set " .. tostring(bad))
        equal(ns.db.language, "en", "rejected value leaves the setting " .. tostring(bad))
    end
    ns.db = nil
    equal(Locale.Set("en"), false, "no database, nothing to store")
end

tests.initialize_drops_invalid_saved_values_and_keeps_valid_ones = function()
    for _, case in ipairs({{"en", "en"}, {"de", "de"}, {nil, nil}, {"auto", nil}, {"EN", nil},
        {"xx", nil}, {5, nil}, {true, nil}}) do
        local ns, Locale = load("enUS", {language = case[1]})
        Locale.Initialize()
        equal(ns.db.language, case[2], "saved " .. tostring(case[1]))
    end
end

tests.options_list_the_three_settings_in_menu_order = function()
    local _, Locale = load("enUS")
    local options = Locale.Options()
    equal(#options, 3)
    equal(options[1].value, "auto"); equal(options[1].label, "Auto")
    equal(options[2].value, "de"); equal(options[2].label, "DE")
    equal(options[3].value, "en"); equal(options[3].label, "EN")
    options[1].label = "changed"
    equal(Locale.Options()[1].label, "Auto", "callers get a detached copy")
end

tests.current_setting_reports_auto_for_absent_or_invalid_values = function()
    local ns, Locale = load("enUS")
    equal(Locale.Setting(), "auto")
    ns.db.language = "en"; equal(Locale.Setting(), "en")
    ns.db.language = "de"; equal(Locale.Setting(), "de")
    ns.db.language = "xx"; equal(Locale.Setting(), "auto")
    ns.db = nil; equal(Locale.Setting(), "auto")
end

local selected = arg and arg[1]
local names, failed = {}, 0
for name in pairs(tests) do if not selected or name == selected then names[#names + 1] = name end end
table.sort(names)
assert(#names > 0, "unknown focused test")
for _, name in ipairs(names) do
    local ok, reason = pcall(tests[name])
    if ok then print("PASS " .. name) else failed = failed + 1; print("FAIL " .. name .. ": " .. tostring(reason)) end
end
print(string.format("%d tests, %d failures", #names, failed))
os.exit(failed == 0 and 0 or 1)
