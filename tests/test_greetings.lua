-- Purpose: prove deterministic personal greetings, grammar and the 255-byte chat boundary.
-- Input: synthetic public names/race/sex; output: PASS/FAIL and an exit status.
-- Invariants: no game API, random generator, real identity, chat or network access.
-- Debug: lua tests/test_greetings.lua [test_name] from the project directory.
local tests = {}
local ns = {}
assert(loadfile("src/ForeverMouseoverBuff/GreetingCatalog.lua"))("ForeverMouseoverBuff", ns)
assert(loadfile("src/ForeverMouseoverBuff/Greetings.lua"))("ForeverMouseoverBuff", ns)
assert(loadfile("src/ForeverMouseoverBuff/SpellLink.lua"))("ForeverMouseoverBuff", ns)
_G.issecretvalue = function() return false end
local Greetings = ns.Greetings
local function equal(actual, expected, reason)
    assert(actual == expected, reason or "unexpected greeting result")
end
local function profile()
    return {receiverName = "Alyndra", senderName = "Paladin", senderClass = "PALADIN"}
end
local function rejected(input, variant, expected)
    local message, code = Greetings.Format(input, variant)
    equal(message, nil, "invalid input must never produce a message")
    equal(code, expected, "wrong fixed rejection code")
end

function tests.public_interface_exposes_twelve_variants_and_one_formatter()
    equal(Greetings.COUNT, 12)
    equal(type(Greetings.Format), "function")
end

function tests.first_neutral_variant_matches_the_integration_contract_exactly()
    equal(Greetings.Format(profile(), 1), '[Forever Mouseover Buff] "Das Licht sei mit Euch, Alyndra!" - Paladin')
end

function tests.all_twelve_variants_are_distinct_complete_personal_and_bounded()
    local seen = {}
    for variant = 1, Greetings.COUNT do
        local message, code = Greetings.Format(profile(), variant)
        equal(code, nil, "valid greeting must not return an error")
        assert(type(message) == "string" and #message <= 255, "chat byte limit")
        assert(message:match('^%[Forever Mouseover Buff%] ".+[!%.]" %- Paladin$'), "complete quoted sentence and author")
        assert(message:find("Alyndra", 1, true), "receiver must be addressed")
        assert(not seen[message], "every variant must use different wording")
        seen[message] = true
    end
end

function tests.every_supported_race_has_correct_male_and_female_address()
    local cases = {
        Human = {"edler Mensch", "edle Menschenfrau"},
        Dwarf = {"edler Zwerg", "edle Zwergin"},
        NightElf = {"edler Nachtelf", "edle Nachtelfe"},
        Gnome = {"edler Gnom", "edle Gnomin"},
        Draenei = {"edler Draenei", "edle Draenei"},
        Orc = {"edler Orc", "edle Orcin"},
        Scourge = {"edler Untoter", "edle Untote"},
        Tauren = {"edler Taure", "edle Taurin"},
        Troll = {"edler Troll", "edle Trollin"},
        BloodElf = {"edler Blutelf", "edle Blutelfe"},
    }
    for race, addresses in pairs(cases) do
        for sex = 2, 3 do
            local input = profile()
            input.raceToken, input.sex = race, sex
            local expected = '[Forever Mouseover Buff] "Das Licht sei mit Euch, ' .. addresses[sex - 1] .. ' Alyndra!" - Paladin'
            equal(Greetings.Format(input, 1), expected, "correct race/sex address: " .. race)
            for variant = 1, Greetings.COUNT do
                local message = Greetings.Format(input, variant)
                assert(message:find(addresses[sex - 1] .. " Alyndra", 1, true), "address must remain grammatical in each variant")
                assert(#message <= 255, "each race and variant stays within chat limit")
            end
        end
    end
end

function tests.missing_unknown_or_invalid_optional_facts_use_neutral_names()
    local cases = {
        {}, {raceToken = "NightElf"}, {sex = 3},
        {raceToken = "UnknownRace", sex = 2}, {raceToken = "nightelf", sex = 3},
        {raceToken = "NightElf", sex = 1}, {raceToken = "NightElf", sex = 0},
        {raceToken = "NightElf", sex = "3"}, {raceToken = "NightElf", sex = 0/0},
        {raceToken = {}, sex = 3}, {raceToken = "NightElf", sex = {}},
    }
    for _, facts in ipairs(cases) do
        local input = profile()
        input.raceToken, input.sex = facts.raceToken, facts.sex
        for variant = 1, Greetings.COUNT do
            equal(Greetings.Format(input, variant), Greetings.Format(profile(), variant), "unknown metadata must not guess gender/race")
        end
    end
end

function tests.umlauts_unicode_spaces_and_hyphens_are_preserved_without_normalization()
    local input = {receiverName = "Älyndra Mond-Grün", senderName = "Jörg Weiß", senderClass = "PALADIN"}
    equal(Greetings.Format(input, 1), '[Forever Mouseover Buff] "Das Licht sei mit Euch, Älyndra Mond-Grün!" - Jörg Weiß')
end

function tests.invalid_required_names_and_markup_never_produce_a_message()
    local invalid = {"", " Leading", "Trailing ", "Trailing-", "123Name", "Name1", "Name\nOther", "Name\tOther",
        "Name|cffff0000", 'Name"', "Name;", "Name%", "Name/", "Name[", "Name_", "https://bad", string.rep("A", 97),
        false, 12, {}, "\255", "\192\175"}
    for _, value in ipairs(invalid) do
        local input = profile(); input.receiverName = value
        rejected(input, 1, "GREETING_INVALID_RECEIVER")
        input = profile(); input.senderName = value
        rejected(input, 1, "GREETING_INVALID_SENDER")
    end
    local input = profile(); input.receiverName = nil
    rejected(input, 1, "GREETING_INVALID_RECEIVER")
    input = profile(); input.senderName = nil
    rejected(input, 1, "GREETING_INVALID_SENDER")
end

function tests.invalid_profile_or_variant_returns_a_fixed_code()
    for _, value in ipairs({false, 1, "profile"}) do rejected(value, 1, "GREETING_INVALID_PROFILE") end
    rejected(nil, 1, "GREETING_INVALID_PROFILE")
    for _, variant in ipairs({0, 13, -1, 1.5, "1", false, {}, 0/0, math.huge}) do
        rejected(profile(), variant, "GREETING_INVALID_VARIANT")
    end
    rejected(profile(), nil, "GREETING_INVALID_VARIANT")
end

function tests.long_valid_names_get_a_complete_short_greeting_without_byte_truncation()
    -- 48 two-byte umlauts each exercise the actual UTF-8 chat boundary.
    local receiver, sender = string.rep("Ä", 48), string.rep("Ö", 48)
    local input = {receiverName = receiver, senderName = sender, senderClass = "PALADIN", raceToken = "Human", sex = 3}
    for variant = 1, Greetings.COUNT do
        local message, code = Greetings.Format(input, variant)
        equal(code, nil)
        assert(type(message) == "string" and #message <= 255, "long valid names must not exceed 255 bytes")
        assert(message:find(receiver, 1, true) and message:find(sender, 1, true), "both full names survive")
        assert(message:match('^%[Forever Mouseover Buff%] ".+[!%.]" %- '), "fallback remains a complete quoted sentence")
    end
    equal(Greetings.Format(input, 6), '[Forever Mouseover Buff] "Licht und Segen, ' .. receiver .. '!" - ' .. sender,
        "an overlong detailed variant uses the documented short sentence")
end

function tests.format_is_repeatable_and_does_not_read_metatables_or_mutate_input()
    local input = profile()
    setmetatable(input, {__index = function() error("optional metadata must not invoke metatables") end,
        __newindex = function() error("formatter may not mutate its input") end})
    for variant = 1, Greetings.COUNT do
        equal(Greetings.Format(input, variant), Greetings.Format(input, variant))
    end
    equal(input.receiverName, "Alyndra")
    equal(input.senderName, "Paladin")
    for key in pairs(Greetings) do assert(key == "COUNT" or key == "Format" or key == "PREFIX" or key == "COLOR_PREFIX" or key == "PlainMessage" or key == "ValidMessage", "no names or history may persist in module") end
end


function tests.addon_identity_is_plain_on_wire_and_only_known_local_color_is_reversible()
    equal(Greetings.PREFIX, "[Forever Mouseover Buff] ")
    equal(Greetings.COLOR_PREFIX, "|cffffd36b[Forever Mouseover Buff]|r ")
    local message = Greetings.Format(profile(), 1)
    assert(not message:find("|", 1, true), "wire text must not contain arbitrary color escapes")
    local colored = Greetings.COLOR_PREFIX .. message:sub(#Greetings.PREFIX + 1)
    equal(Greetings.PlainMessage(colored), message)
    equal(Greetings.PlainMessage(message), message)
    equal(Greetings.PlainMessage("Manual |cffff0000text|r"), "Manual |cffff0000text|r")
    equal(Greetings.PlainMessage(false), false)
end


function tests.confirmed_count_and_exact_buff_link_follow_sender_name()
    local input = profile()
    input.buffCount = 42
    input.spellLink = "|cff71d5ff|Hspell:20217|h[Segen der Könige]|h|r"
    equal(Greetings.Format(input, 1), '[Forever Mouseover Buff] "Das Licht sei mit Euch, Alyndra!" - Paladin [lokal: 42 Buffs] ' .. input.spellLink)
end
function tests.extended_messages_are_validated_without_allowing_foreign_markup()
    local input = profile(); input.buffCount = 42
    input.spellLink = "|cff71d5ff|Hspell:20217|h[Segen der Könige]|h|r"
    local message = Greetings.Format(input, 1)
    assert(Greetings.ValidMessage(message, 20217))
    assert(not Greetings.ValidMessage(message, 19740), "link ID must belong to the actual cast")
    assert(not Greetings.ValidMessage(message .. "|Hplayer:Other|h[Other]|h"))
    assert(not Greetings.ValidMessage(message:gsub("Hspell:", "Hitem:")))
    assert(Greetings.ValidMessage(Greetings.Format(profile(), 1)), "old recipients can still recognize plain greetings")
end
function tests.invalid_statistics_or_links_never_enter_greetings()
    for _, value in ipairs({-1, 1.5, 0/0, math.huge, 1000000001, "42", false, {}}) do
        local input = profile(); input.buffCount = value
        local result = Greetings.Format(input, 1)
        equal(result, nil, "invalid count must not be presented")
    end
    local input = profile(); input.spellLink = "|Hitem:42|h[Item]|h"
    equal(Greetings.Format(input, 1), nil)
end
function tests.extreme_names_keep_complete_identity_when_optional_details_do_not_fit()
    local input = {receiverName = string.rep("Ä",48), senderName = string.rep("Ö",48), buffCount = 1000000000,
        spellLink = "|cff71d5ff|Hspell:20217|h[Segen der Könige]|h|r"}
    local message, code = Greetings.Format(input, 8)
    assert(type(message) == "string" and #message <= 255)
    assert(message:find(input.receiverName, 1, true) and message:find(input.senderName, 1, true))
    equal(code, "GREETING_DETAILS_OMITTED")
    assert(Greetings.ValidMessage(message))
end

-- Sender class controls the voice; recipient race controls only the address.
function tests.shaman_and_druid_greetings_never_use_paladin_light_even_when_shortened()
    for _, senderClass in ipairs({"SHAMAN", "DRUID"}) do
        for _, length in ipairs({7, 48}) do
            for variant = 1, Greetings.COUNT do
                local input = {senderClass = senderClass, senderRace = "Tauren",
                    receiverName = string.rep("Ä",length), senderName = string.rep("Ö",length),
                    buffCount = 42, spellLink = "|cff71d5ff|Hspell:20217|h[Testbuff]|h|r"}
                local message = assert(Greetings.Format(input,variant))
                assert(not message:find("Licht",1,true), senderClass .. " must not invoke paladin light")
                assert(message:find(input.receiverName,1,true) and message:find(input.senderName,1,true))
                assert(#message <= 255 and Greetings.ValidMessage(message,20217))
            end
        end
    end
end
function tests.unknown_sender_class_is_neutral_even_when_sender_is_named_paladin()
    for _, value in ipairs({false, {}, 17, "UNKNOWN", "paladin", "PALADIN|bad"}) do
        local input = profile(); input.senderClass = value
        for variant = 1, Greetings.COUNT do
            local message = assert(Greetings.Format(input,variant))
            assert(not message:find("Licht",1,true), "unknown class must not guess from sender name")
        end
    end
    local input = profile(); input.senderClass = nil
    assert(not Greetings.Format(input,1):find("Licht",1,true))
end
function tests.sender_race_changes_voice_without_replacing_recipient_race_address()
    local input = profile()
    input.senderClass, input.raceToken, input.sex = "SHAMAN", "NightElf", 3
    local changed = 0
    for variant = 1, Greetings.COUNT do
        input.senderRace = "Orc"; local first = assert(Greetings.Format(input,variant))
        input.senderRace = "Tauren"; local second = assert(Greetings.Format(input,variant))
        if first ~= second then changed = changed + 1 end
        assert(first:find("edle Nachtelfe Alyndra",1,true) and second:find("edle Nachtelfe Alyndra",1,true))
        assert(not first:find("Licht",1,true) and not second:find("Licht",1,true))
    end
    assert(changed >= 2, "at least two variants should reflect the sender's known race")
end

local selected = {}
for name in pairs(tests) do if not arg[1] or arg[1] == name then selected[#selected + 1] = name end end
assert(#selected > 0, "unknown test filter")
table.sort(selected)
local failed = 0
for _, name in ipairs(selected) do
    local ok, failure = pcall(tests[name])
    if ok then print("PASS " .. name)
    else failed = failed + 1; print("FAIL " .. name .. ": " .. failure) end
end
print(string.format("Greetings: %d passed, %d failed", #selected - failed, failed))
if failed > 0 then os.exit(1) end
