-- Purpose: assign a consciously chosen key to the existing native buff button.
-- Input: keyboard/mouse chords; output: native binding changes and UI messages.
-- Invariants: no default keys, casts, combat writes or replacement of other actions.
-- Debug: /fmb bind; lua tests/test_keybinding.lua exercises native failure recovery.
local _, ns = ...
local Keybinding = {}
ns.Keybinding = Keybinding
local action = "CLICK ForeverMouseoverBuffButton:LeftButton"
local modifiers = {"ALT", "CTRL", "SHIFT", "META"}
local modifierReaders = {"IsAltKeyDown", "IsControlKeyDown", "IsShiftKeyDown", "IsMetaKeyDown"}
local reserved = {ESCAPE = true, UNKNOWN = true, BUTTON1 = true, BUTTON2 = true,
    LALT = true, RALT = true, LCTRL = true, RCTRL = true, LSHIFT = true, RSHIFT = true,
    LMETA = true, RMETA = true, ALT = true, CTRL = true, SHIFT = true, META = true}
local mouseNames = {LeftButton = "BUTTON1", RightButton = "BUTTON2", MiddleButton = "BUTTON3"}
local apiFailure = "Tastenbelegung nicht verfügbar. WoW-Tastaturbelegung prüfen und /reload ausführen."

-- Native APIs may expose protected data. Check readability before comparisons,
-- then accept short key tokens only; API errors never become chat/log contents.
local function readable(value)
    if type(issecretvalue) ~= "function" then return true end
    local ok, secret = pcall(issecretvalue, value)
    return ok and secret == false
end
local function cleanString(value)
    return readable(value) and type(value) == "string" and #value <= 100
        and not value:find("[%c%s|]")
end
local function singleCharacter(key)
    -- Lua 5.1 counts UTF-8 bytes. A German Ö must remain one keyboard key rather
    -- than being rejected for having two bytes; native SetBinding validates it.
    return #key == 1 or key:match("^[\194-\223][\128-\191]$")
        or key:match("^[\224-\239][\128-\191][\128-\191]$")
        or key:match("^[\240-\244][\128-\191][\128-\191][\128-\191]$")
end
local function normalize(value)
    if not cleanString(value) or value == "" then return nil end
    local key = value:upper()
    local selected = {}
    -- Prefixes are canonicalized so SHIFT-CTRL-F6 and CTRL-SHIFT-F6 refer to the
    -- same native chord. A single '-' remains a valid punctuation key.
    while true do
        local prefix, rest = key:match("^(%u+)%-(.+)$")
        if prefix ~= "ALT" and prefix ~= "CTRL" and prefix ~= "SHIFT" and prefix ~= "META" then break end
        if selected[prefix] then return nil end
        selected[prefix], key = true, rest
    end
    if key == "" or reserved[key] or (not singleCharacter(key) and not key:match("^[A-Z0-9]+$")) then return nil end
    local button = key:match("^BUTTON(%d+)$")
    if button and (tonumber(button) < 3 or tonumber(button) > 31) then return nil end
    local chord = {}
    for _, modifier in ipairs(modifiers) do
        if selected[modifier] then chord[#chord + 1] = modifier end
    end
    chord[#chord + 1] = key
    return table.concat(chord, "-")
end
local function locked()
    if not ns.API or type(ns.API.Locked) ~= "function" then return true end
    local ok, value = pcall(ns.API.Locked)
    return not ok or not readable(value) or value ~= false
end
local function getAction(key, overrides)
    local ok, value = pcall(GetBindingAction, key, overrides)
    if not ok or not readable(value) or type(value) ~= "string" then return nil end
    return value
end

-- Read the full native list, including keys beyond the two shown by WoW's UI.
-- Returned lists are detached; opening the setup UI never mutates bindings.
function Keybinding.CurrentKeys()
    if type(GetBindingKey) ~= "function" then return nil, apiFailure end
    local result = {pcall(GetBindingKey, action)}
    if not result[1] then return nil, apiFailure end
    local keys = {}
    for index = 2, #result do
        local key = result[index]
        if not cleanString(key) or key == "" then return nil, apiFailure end
        keys[#keys + 1] = key
    end
    return keys
end

-- This follows native BindingUtil's ALT/CTRL/SHIFT/META order and ignores bare
-- modifiers plus the two primary mouse buttons. Example: Ctrl+Button5 becomes
-- CTRL-BUTTON5. Escape is handled by the UI as cancellation, never as a key.
function Keybinding.FromInput(input)
    if not cleanString(input) then return nil end
    local key = normalize(mouseNames[input] or input)
    if not key then return nil end
    local chord = {}
    for index, modifier in ipairs(modifiers) do
        local reader = _G[modifierReaders[index]]
        if type(reader) == "function" then
            local ok, down = pcall(reader)
            if not ok or not readable(down) then return nil end
            if down then chord[#chord + 1] = modifier end
        end
    end
    chord[#chord + 1] = key
    return normalize(table.concat(chord, "-"))
end

-- Validate every native dependency and the currently active save scope before
-- the first write. Account/character scope is preserved, never silently switched.
local function prepare()
    if locked() then return nil, "Im Kampf kann die Buff-Taste nicht geändert werden. Nach dem Kampf erneut versuchen." end
    for _, name in ipairs({"GetBindingKey", "GetBindingAction", "SetBinding", "SaveBindings", "GetCurrentBindingSet"}) do
        if type(_G[name]) ~= "function" then return nil, apiFailure end
    end
    local ok, scope = pcall(GetCurrentBindingSet)
    if not ok or not readable(scope) or (scope ~= 1 and scope ~= 2) then return nil, apiFailure end
    local keys, message = Keybinding.CurrentKeys()
    if not keys then return nil, message end
    for _, key in ipairs(keys) do
        if getAction(key, false) ~= action then return nil, apiFailure end
    end
    return {keys = keys, scope = scope, changes = {}}
end
local function write(key, command)
    if locked() then return false end
    local ok, result = pcall(SetBinding, key, command)
    if not ok or not readable(result) or (result ~= true and result ~= 1) then return false end
    return getAction(key, false) == (command or "")
end
local function save(scope)
    if locked() then return false end
    local ok, result = pcall(SaveBindings, scope)
    -- Native SaveBindings may return nothing. An explicit false or exception is
    -- a failure; the client has no API for rereading the on-disk binding file.
    return ok and readable(result) and result ~= false
end

-- Keep a small undo ledger of only our touched keys. A native call can throw
-- after changing memory, so record before writing. Never LoadBindings: that
-- would also discard unrelated edits made in WoW's own settings window.
local function change(transaction, key, command, previous)
    transaction.changes[#transaction.changes + 1] = {key = key, previous = previous}
    return write(key, command)
end
local function rollback(transaction, saveAttempted)
    local restored = true
    for index = #transaction.changes, 1, -1 do
        local entry = transaction.changes[index]
        if not write(entry.key, entry.previous) then restored = false end
    end
    if saveAttempted and not save(transaction.scope) then restored = false end
    if not restored then
        return false, "Tastenbelegung nicht sicher wiederhergestellt. Vor dem Buffen die WoW-Tastaturbelegung prüfen."
    end
    return false, "Buff-Taste konnte nicht gespeichert werden; vorherige Belegung wiederhergestellt. WoW-Tastaturbelegung prüfen und erneut versuchen."
end
local function commit(transaction)
    if not save(transaction.scope) then return rollback(transaction, true) end
    return true
end

-- A new key replaces this addon's existing keys only after ownership checks.
-- A collision is rejected, including an active override from another addon.
-- Selecting an already-owned key is a no-op and retains secondary assignments.
function Keybinding.Assign(input)
    local key = normalize(input)
    if not key then return false, "Ungültige Taste. Eine Tastaturtaste, mittlere/zusätzliche Maustaste oder das Mausrad wählen." end
    local transaction, message = prepare()
    if not transaction then return false, message end
    local previous, effective = getAction(key, false), getAction(key, true)
    if previous == nil or effective == nil then return false, apiFailure end
    if (previous ~= "" and previous ~= action) or (effective ~= "" and effective ~= action) then
        return false, "Diese Taste ist bereits belegt. Eine freie Taste wählen oder die Belegung zuerst in den WoW-Optionen ändern."
    end
    if previous == action then return true, "Diese Taste ist bereits deine Buff-Taste." end
    if not change(transaction, key, action, nil) then return rollback(transaction, false) end
    for _, oldKey in ipairs(transaction.keys) do
        if not change(transaction, oldKey, nil, action) then return rollback(transaction, false) end
    end
    local success, failure = commit(transaction)
    if not success then return false, failure end
    return true, "Buff-Taste gespeichert: " .. key .. "."
end

-- Clearing is an explicit separate UI action. Other commands and their keys
-- remain untouched, and an already-empty list requires no native save call.
function Keybinding.Clear()
    local transaction, message = prepare()
    if not transaction then return false, message end
    if #transaction.keys == 0 then return true, "Keine Buff-Taste zu entfernen." end
    for _, key in ipairs(transaction.keys) do
        if not change(transaction, key, nil, action) then return rollback(transaction, false) end
    end
    local success, failure = commit(transaction)
    if not success then return false, failure end
    return true, "Buff-Taste entfernt. Mit „Taste wählen“ kannst du eine neue zuweisen."
end
