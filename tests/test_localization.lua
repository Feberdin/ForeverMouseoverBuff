-- Purpose: verify client defaults, saved language choices and translated addon output.
-- Input: synthetic locale APIs and profiles; output: deterministic PASS or assertion.
-- Invariants: no live game data, network, protected actions or global string changes.
-- Debug: lua5.1 tests/test_localization.lua from the repository root.
local ns = {}
GetLocale = function() return "enUS" end
local source = "src/ForeverMouseoverBuff/"
local localization = io.open(source .. "Localization.lua", "r")
if localization then
    localization:close()
    assert(loadfile(source .. "Localization.lua"))("ForeverMouseoverBuff", ns)
end
assert(loadfile(source .. "Core.lua"))("ForeverMouseoverBuff", ns)
assert(ns.Core.ClassOptions()[1].name == "Druid", "English clients must see Druid, not the German class label")
assert(ns.Localization, "shared localization module must be available")
local L = ns.Localization
local saved = {}
L.Initialize(saved)
assert(saved.language == "auto" and L.Locale() == "enUS")
assert(L.Set("deDE"))
assert(saved.language == "deDE" and ns.Core.ClassOptions()[1].name == "Druide")
assert(L.Set("enUS"))
assert(ns.Core.ClassOptions()[1].name == "Druid")
assert(not L.Set("frFR") and saved.language == "enUS", "invalid choices must preserve the preference")
GetLocale = function() return "deDE" end
assert(L.Set("auto") and L.Locale() == "deDE")
GetLocale = function() return "frFR" end
assert(L.Locale() == "enUS", "unsupported clients use English")
L.Initialize({language = false})
assert(L.Locale() == "enUS", "damaged preferences fall back to the client")
GetLocale = function() error("synthetic unavailable locale") end
assert(L.Locale() == "enUS", "unavailable client locale safely uses English")
assert(loadfile(source .. "GreetingCatalog.lua"))("ForeverMouseoverBuff", ns)
assert(loadfile(source .. "Greetings.lua"))("ForeverMouseoverBuff", ns)
local greeting = assert(ns.Greetings.Format({receiverName = "Alyndra", senderName = "Testadin",
    senderClass = "PALADIN", senderRace = "Human", raceToken = "NightElf", sex = 3, buffCount = 4}, 1))
assert(greeting:find("Buffs given", 1, true) and not greeting:find("edle", 1, true), "greeting and count must follow English selection")
assert(ns.Greetings.ValidMessage(greeting), "English formatted greetings must pass the sender/recipient grammar")
-- Both peers recognize either language, independently of their own preference.
assert(L.Set("deDE"))
local german = assert(ns.Greetings.Format({receiverName = "Testa", senderName = "Testadin",
    senderClass = "PALADIN", buffCount = 4}, 1))
assert(ns.Greetings.ValidMessage(greeting) and ns.Greetings.ValidMessage(german))
assert(L.Set("enUS"))
assert(ns.Greetings.ValidMessage(german))
assert(not ns.Greetings.ValidMessage(greeting:gsub("4 Buffs given", "1000000001 Buffs given")))
assert(not ns.Greetings.ValidMessage(greeting:gsub("4 Buffs given", "04 Buffs given")))
local classes = {"PALADIN", "PRIEST", "DRUID", "SHAMAN", "MAGE", "WARLOCK", "WARRIOR", "HUNTER", "ROGUE", "UNKNOWN"}
local races = {"Human", "Dwarf", "NightElf", "Gnome", "Draenei", "Orc", "Scourge", "Undead", "Tauren", "Troll", "BloodElf", "UNKNOWN"}
for _, locale in ipairs({"deDE", "enUS"}) do
    assert(L.Set(locale))
    for _, class in ipairs(classes) do
        for _, race in ipairs(races) do
            for variant = 1, 12 do
                local message = assert(ns.Greetings.Format({receiverName = "Testa", senderName = "Testadin",
                    senderClass = class, senderRace = race, raceToken = race, sex = 3, buffCount = 17}, variant))
                assert(#message <= 255 and ns.Greetings.ValidMessage(message), "localized greeting must fit the chat grammar")
                if locale == "enUS" then
                    assert(not message:find("[äöüÄÖÜß]"), "German greeting remains in English: " .. message)
                end
            end
        end
    end
end
for key, value in pairs(L.English) do
    assert(type(key) == "string" and type(value) == "string" and value ~= "", "catalog entries must be nonempty strings")
    local function placeholders(text)
        local result = {}
        for placeholder in text:gmatch("%%[%.%d]*[sdif]") do result[#result + 1] = placeholder end
        return table.concat(result, ",")
    end
    assert(placeholders(key) == placeholders(value), "format placeholders changed: " .. key)
end
-- Inspect quoted addon literals, ignoring comments and preserving escaped quotes.
-- Every German presentation key must have an explicit English catalog entry.
local toc = assert(io.open(source .. "ForeverMouseoverBuff.toc", "r"))
for filename in toc:lines() do
    if filename:match("%.lua$") and filename ~= "Localization.lua" then
        local file = assert(io.open(source .. filename, "r"))
        local content = file:read("*a"); file:close()
        local index = 1
        while index <= #content do
            local char = content:sub(index, index)
            if content:sub(index, index + 1) == "--" then
                index = (content:find("\n", index, true) or #content) + 1
            elseif char == '"' or char == "'" then
                local start, quote = index, char
                index = index + 1
                while index <= #content do
                    char = content:sub(index, index)
                    if char == "\\" then index = index + 2
                    elseif char == quote then break
                    else index = index + 1 end
                end
                local decode = assert(loadstring("return " .. content:sub(start, index)))
                local value = decode()
                for _, letter in ipairs({"ä", "ö", "ü", "Ä", "Ö", "Ü", "ß"}) do
                    if value:find(letter, 1, true) then
                        assert(L.English[value], "Missing English catalog key in " .. filename .. ": " .. value)
                    end
                end
                index = index + 1
            else index = index + 1 end
        end
    end
end
toc:close()
print("PASS: localization defaults, persistence, validation, dynamic labels and greetings")
