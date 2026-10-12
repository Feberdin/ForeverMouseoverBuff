-- Purpose: prove class voices, sender-race accents and bounded UTF-8 templates.
-- Input: synthetic public tokens; output: deterministic PASS/FAIL and exit status.
-- Invariants: no native APIs, names, random state, network or live game access.
-- Debug: lua tests/test_greeting_catalog.lua [test_name] from the project root.
local tests, ns = {}, {}
assert(loadfile("src/ForeverMouseoverBuff/GreetingCatalog.lua"))("ForeverMouseoverBuff", ns)
local Catalog = ns.GreetingCatalog
local classes = {"PALADIN", "PRIEST", "DRUID", "SHAMAN", "MAGE", "WARLOCK", "WARRIOR", "HUNTER", "ROGUE"}
local races = {"Human", "Dwarf", "NightElf", "Gnome", "Draenei", "Orc", "Scourge", "Tauren", "Troll", "BloodElf"}
local paladin = {
    "Das Licht sei mit Euch, %s!",
    "Möge Euch ein heller Funke begleiten, %s!",
    "Gute Wege und einen sicheren Heimweg, %s!",
    "Ein wenig Licht für Euren nächsten Schritt, %s!",
    "Möge dieser Segen Euch Zuversicht schenken, %s!",
    "Für Euch, %s: Licht im Gepäck und Mut im Herzen!",
    "Bleibt behütet, %s, auch auf dunklen Wegen!",
    "Eine helle Stunde und gute Gesellschaft wünsche ich Euch, %s!",
    "Für die Reise: ein Segen und ein freundlicher Gruß, %s!",
    "Möge Euer Weg nach Hause stets beleuchtet sein, %s!",
    "Nehmt diesen Funken Zuversicht mit, %s!",
    "Auf gute Wege und ein Wiedersehen am Herdfeuer, %s!",
}
local function equal(actual, expected, why)
    assert(actual == expected, why or "unexpected catalog value")
end

-- Validate bytes independently of the formatter, including overlong encodings.
local function validUTF8(value)
    local index = 1
    while index <= #value do
        local first = value:byte(index)
        local width = first < 128 and 1 or first < 224 and 2 or first < 240 and 3 or 4
        assert(first < 128 or (first >= 194 and first <= 244), "invalid UTF-8 lead")
        assert(index + width - 1 <= #value, "incomplete UTF-8 sequence")
        for offset = 1, width - 1 do
            local byte = value:byte(index + offset)
            assert(byte >= 128 and byte <= 191, "invalid UTF-8 continuation")
        end
        local second = value:byte(index + 1)
        if first == 224 then assert(second >= 160, "overlong UTF-8") end
        if first == 237 then assert(second <= 159, "UTF-8 surrogate") end
        if first == 240 then assert(second >= 144, "overlong UTF-8") end
        if first == 244 then assert(second <= 143, "UTF-8 outside Unicode") end
        index = index + width
    end
end
local function validTemplate(value)
    equal(type(value), "string", "template must be a string")
    validUTF8(value)
    local literal, placeholders = value:gsub("%%s", "")
    equal(placeholders, 1, "one and only one receiver placeholder")
    assert(not literal:find("%%"), "no other format directives")
    assert(not value:find('[%c|"\\]'), "no chat markup or quote/control injection")
    assert(value:match("[!.]$"), "complete greeting ending")
    local formatted = string.format(value, "Älyndra")
    local message = '[Forever Mouseover Buff] "' .. formatted .. '" - Jörg'
    assert(#message <= 255, "ordinary complete greeting exceeds chat budget")
end
local function eachSelection(callback)
    for _, class in ipairs(classes) do
        callback(class, nil, Catalog.Select(class))
        for _, race in ipairs(races) do callback(class, race, Catalog.Select(class, race)) end
    end
    callback(nil, nil, Catalog.Select())
end

function tests.interface_is_small_and_has_twelve_variants()
    equal(Catalog.COUNT, 12)
    equal(type(Catalog.Select), "function")
    for key in pairs(Catalog) do assert(key == "COUNT" or key == "Select", "no history or game state exports") end
end

function tests.every_class_race_matrix_has_twelve_distinct_valid_templates()
    eachSelection(function(class, race, templates, short)
        equal(#templates, 12, "every selection must have twelve entries")
        local seen, count = {}, 0
        for key, value in pairs(templates) do
            assert(type(key) == "number" and key >= 1 and key <= 12 and key == math.floor(key), "only sequence entries")
            validTemplate(value)
            assert(not seen[value], "twelve genuinely different variants per selection")
            seen[value], count = true, count + 1
        end
        equal(count, 12)
        validTemplate(short)
    end)
end

function tests.paladin_base_keeps_all_twelve_existing_templates_byte_for_byte()
    local templates = Catalog.Select("PALADIN")
    for index = 1, 12 do equal(templates[index], paladin[index], "Paladin regression at variant " .. index) end
end

function tests.paladin_short_form_preserves_the_existing_full_sentence()
    local _, short = Catalog.Select("PALADIN")
    equal(short, "Licht und Segen, %s!", "the established Paladin short form must remain byte-identical")
end

function tests.each_class_has_a_distinct_voice_without_assuming_specialization()
    local themes = {PALADIN = "Licht", PRIEST = "Willen", DRUID = "Natur", SHAMAN = "Elemente",
        MAGE = "arkan", WARLOCK = "Dunkel", WARRIOR = "Mut", HUNTER = "Wildnis", ROGUE = "Geschick"}
    local seen = {}
    for _, class in ipairs(classes) do
        local templates = Catalog.Select(class)
        assert(templates[1]:find(themes[class], 1, true), "first greeting must convey the sender class: " .. class)
        assert(not seen[templates[1]], "different classes must not share the same first greeting")
        seen[templates[1]] = true
    end
end

function tests.racial_accents_change_exactly_two_variants_and_keep_class_short_form()
    for _, class in ipairs(classes) do
        local base, short = Catalog.Select(class)
        for _, race in ipairs(races) do
            local templates, raceShort = Catalog.Select(class, race)
            local changed = 0
            for index = 1, 12 do
                if templates[index] ~= base[index] then
                    assert(index == 6 or index == 12, "only the two documented accent slots vary")
                    changed = changed + 1
                end
            end
            equal(changed, 2, "supported sender race must add two cultural accents")
            equal(raceShort, short, "long-name fallback keeps the sender class, not race decoration")
        end
    end
end

function tests.nature_and_elements_never_fall_back_to_light_or_blessings()
    for _, class in ipairs({"DRUID", "SHAMAN"}) do
        local options = {"UnknownRace"}
        for _, race in ipairs(races) do options[#options + 1] = race end
        for _, race in ipairs(options) do
            local templates, short = Catalog.Select(class, race)
            templates[13] = short
            for _, text in ipairs(templates) do
                assert(not text:lower():find("licht", 1, true), "nature/element greetings must never borrow Light")
                assert(not text:lower():find("segen", 1, true), "nature/element voice has its own short form")
            end
        end
    end
end

function tests.sender_race_accents_match_the_requested_nature_and_element_examples()
    local examples = {{"SHAMAN", "Orc", "Ahnen"}, {"SHAMAN", "Troll", "Geister"},
        {"SHAMAN", "Tauren", "Erde"}, {"DRUID", "NightElf", "Mond"}, {"DRUID", "Tauren", "Wurzeln"}}
    for _, entry in ipairs(examples) do
        local templates = Catalog.Select(entry[1], entry[2])
        assert((templates[6] .. templates[12]):find(entry[3], 1, true), "missing requested race theme")
    end
end

function tests.short_forms_keep_two_maximum_utf8_names_within_the_wire_budget()
    local receiver, sender = string.rep("Ä", 48), string.rep("Ö", 48)
    eachSelection(function(class, race, templates, short)
        validTemplate(short)
        equal(select(2, short:gsub("%%s", "")), 1)
        assert(#short <= 32, "short form must reserve room for two full names and the addon prefix")
        local message = '[Forever Mouseover Buff] "' .. string.format(short, receiver) .. '" - ' .. sender
        assert(#message <= 255, "both 96-byte names survive without truncation")
        assert(message:find(receiver, 1, true) and message:find(sender, 1, true), "preserve both complete identities")
        validUTF8(message)
    end)
end

function tests.unknown_class_is_neutral_and_unknown_race_preserves_class_base()
    local neutral, short = Catalog.Select()
    equal(neutral[1], "Gute Wege, %s!")
    equal(short, "Gute Wege, %s!")
    local invalid = {false, 3, 0/0, {}, function() error("must not invoke supplied callbacks") end, "Unknown", "paladin"}
    for _, value in ipairs(invalid) do
        local actual, actualShort = Catalog.Select(value, "NightElf")
        equal(actualShort, short)
        for index = 1, 12 do equal(actual[index], neutral[index], "unknown sender class is never guessed") end
        for _, class in ipairs(classes) do
            local base, baseShort = Catalog.Select(class)
            actual, actualShort = Catalog.Select(class, value)
            equal(actualShort, baseShort)
            for index = 1, 12 do equal(actual[index], base[index], "unknown race must not change class voice") end
        end
    end
end

function tests.results_are_detached_repeatable_and_do_not_read_user_metatables()
    local input = setmetatable({}, {__index = function() error("input metadata must not execute") end,
        __tostring = function() error("invalid input must not be converted") end})
    Catalog.Select(input, input)
    for _, class in ipairs(classes) do
        local first, short = Catalog.Select(class, "NightElf")
        local original = first[1]
        first[1], first[20] = "overwritten", "extra"
        local second, nextShort = Catalog.Select(class, "NightElf")
        equal(second[1], original, "caller may not mutate catalog data")
        equal(second[20], nil)
        equal(short, nextShort)
        assert(first ~= second, "each selection owns its detached table")
    end
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
