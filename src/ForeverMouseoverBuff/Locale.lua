-- Purpose: resolve the interface language and map German source keys to translated text.
-- Input: the per-character setting (absent, "de" or "en"), the client locale, translation tables.
-- Output: ns.L lookups that return the German key unchanged unless English is active.
-- Invariants: German output never changes; an unknown client locale resolves to German once logged.
-- Debug: /fmb lang shows the setting; tests/test_locale.lua covers every resolution path.
local _, ns = ...
local Locale = {}
ns.Locale = Locale
local DEFAULT = "de"
local LANGUAGES = {de = true, en = true}
local OPTIONS = {{value = "auto", label = "Auto"}, {value = "de", label = "DE"}, {value = "en", label = "EN"}}
local translations = {en = {}}
local clientReported = false

-- A client locale is a four-letter code such as deDE or enUS. Anything else counts
-- as unknown and resolves to German, the language the addon was written in.
local function clientLanguage(clientLocale)
    if type(clientLocale) ~= "string" or not clientLocale:match("^%l%l%u%u$") then return nil end
    if clientLocale:sub(1, 2) == "de" then return "de" end
    return "en"
end
local function savedSetting()
    local db = ns.db
    if type(db) ~= "table" then return nil end
    local value = db.language
    if LANGUAGES[value] then return value end
    return nil
end
local function clientLocale()
    if type(GetLocale) ~= "function" then return nil end
    local ok, value = pcall(GetLocale)
    if ok then return value end
    return nil
end

-- Pure: a manual setting wins; Auto follows the client; invalid input means Auto.
-- The second result names the diagnostic reason when the client locale is unusable.
function Locale.Resolve(setting, locale)
    if LANGUAGES[setting] then return setting end
    local language = clientLanguage(locale)
    if not language then return DEFAULT, "LOCALE_CLIENT_UNKNOWN" end
    return language
end
function Locale.Effective()
    local language, reason = Locale.Resolve(savedSetting(), clientLocale())
    if reason and not clientReported then
        clientReported = true
        if type(ns.Log) == "function" then ns:Log(reason) end
    end
    return language
end
function Locale.Setting() return savedSetting() or "auto" end
function Locale.Options()
    local copy = {}
    for index, option in ipairs(OPTIONS) do copy[index] = {value = option.value, label = option.label} end
    return copy
end

-- Saved writes stay explicit: "auto" is stored as absence, like other FMB defaults.
function Locale.Set(value)
    if type(ns.db) ~= "table" then return false end
    if value == "auto" then ns.db.language = nil; return true end
    if LANGUAGES[value] then ns.db.language = value; return true end
    return false
end
function Locale.Initialize()
    if type(ns.db) ~= "table" then return end
    if not LANGUAGES[ns.db.language] then ns.db.language = nil end
end

-- Translation tables are validated completely before any entry is merged, so a
-- malformed file can never leave a half-registered language behind.
function Locale.Register(language, entries)
    if language == DEFAULT or not LANGUAGES[language] or type(entries) ~= "table" then return false end
    for key, text in pairs(entries) do
        if type(key) ~= "string" or type(text) ~= "string" then return false end
    end
    local target = translations[language]
    for key, text in pairs(entries) do target[key] = text end
    return true
end

-- The lookup never caches: the table stays empty, and every access resolves the
-- language live, so a switch applies to the next message without a reload.
ns.L = setmetatable({}, {
    __index = function(_, key)
        if type(key) ~= "string" then return nil end
        local language = Locale.Effective()
        if language == DEFAULT then return key end
        return translations[language][key] or key
    end,
    __newindex = function() error("ns.L is read-only; use Locale.Register") end,
})
