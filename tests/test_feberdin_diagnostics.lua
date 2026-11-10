-- Purpose: verify local Lua-error capture without installing a global handler.
-- Input: synthetic WoW hooks and errors. Output: deterministic PASS/FAIL.
-- Invariants: saved records contain only codes and sanitized source locations.
-- Debug: lua tests/test_feberdin_diagnostics.lua [test_name].
local tests = {}
local function fixture(options)
    options = options or {}
    local f = {frames = {}, hooks = {}, secret = {}}
    local env = setmetatable({}, {__index = _G})
    env._G = env
    env.FeberdinDiagnostics = {}
    env.SlashCmdList = {}
    env.issecretvalue = function(value)
        if options.brokenSecretGuard then error('guard unavailable') end
        return rawequal(value, f.secret)
    end
    env.hooksecurefunc = function(target, method, callback)
        if type(target) == 'string' then f.hooks[target] = method
        else f.hooks[method] = callback end
    end
    env.seterrorhandler = function() error('must not replace the global error handler') end
    env.CreateFrame = function()
        local frame = {RegisterEvent = function() end}
        function frame:SetScript(_, callback) self.onEvent = callback end
        f.frames[#f.frames + 1] = frame
        return frame
    end
    if options.frame then env.ScriptErrorsFrame = {DisplayMessageInternal = function() end} end
    local chunk = assert(loadfile('src/ForeverMouseoverBuff/FeberdinDiagnostics.lua'))
    setfenv(chunk, env)
    chunk('ForeverMouseoverBuff', {})
    f.api = env.FeberdinDiagnostics.ForeverMouseoverBuff
    f.env = env
    return f
end
function tests.owned_error_boundary_retains_location_without_private_message()
    local f = fixture()
    assert(type(f.api.ObserveError) == 'function', 'addon error boundaries need a sanitized observer')
    f.api.ObserveError('Interface/AddOns/ForeverMouseoverBuff/App.lua:42: synthetic private detail')
    local events = f.api.Status().events
    assert(#events == 1 and events[1].code == 'LUA_ERROR')
    assert(events[1].file == 'App.lua' and events[1].line == 42)
    assert(not f.env.ForeverMouseoverBuffDiagnosticsDB.exportJSON:find('private', 1, true))
end
function tests.external_and_invalid_locations_are_not_retained()
    local f = fixture()
    for _, message in ipairs({'Interface/AddOns/OtherAddon/App.lua:42: foreign',
        'Interface/AddOns/ForeverMouseoverBuff/../App.lua:42: invalid',
        'Interface/AddOns/ForeverMouseoverBuff/App.lua:1000001: invalid', 'unstructured error'}) do
        f.api.ObserveError(message)
    end
    assert(#f.api.Status().events == 0)
end
function tests.blizzard_bracket_and_windows_source_locations_are_supported()
    local f = fixture()
    f.api.ObserveError('[string "@Interface/AddOns/ForeverMouseoverBuff/Core.lua"]:27: details')
    f.api.ObserveError('Interface\\AddOns\\ForeverMouseoverBuff\\API.lua:31: details')
    local events = f.api.Status().events
    assert(events[1].file == 'Core.lua' and events[1].line == 27)
    assert(events[2].file == 'API.lua' and events[2].line == 31)
end
function tests.secret_and_unreadable_errors_fail_closed()
    local f = fixture()
    f.api.ObserveError(f.secret)
    f.api.ObserveError({})
    local broken = fixture({brokenSecretGuard = true})
    broken.api.ObserveError('Interface/AddOns/ForeverMouseoverBuff/App.lua:42: details')
    assert(#f.api.Status().events == 0 and #broken.api.Status().events == 0)
end
function tests.valid_error_ring_is_bounded_and_status_is_detached()
    local f = fixture()
    for index = 1, 105 do
        f.api.ObserveError('Interface/AddOns/ForeverMouseoverBuff/App.lua:' .. index .. ': details')
    end
    local snapshot = f.api.Status()
    assert(#snapshot.events == 100 and snapshot.events[1].line == 6)
    snapshot.events[1].file = 'changed'
    assert(f.api.Status().events[1].file == 'App.lua')
end
function tests.blizzard_frame_hook_uses_the_same_sanitizer()
    local f = fixture({frame = true})
    f.hooks.DisplayMessageInternal({}, 'Interface/AddOns/ForeverMouseoverBuff/App.lua:18: details', 0)
    assert(f.api.Status().events[1].line == 18)
    f.hooks.DisplayMessageInternal({}, f.secret, f.secret)
    assert(#f.api.Status().events == 1)
end
local count = 0
for name, test in pairs(tests) do
    if not arg[1] or arg[1] == name then test(); count = count + 1 end
end
assert(count > 0, 'no matching test')
print('PASS: ' .. count .. ' shared diagnostic capture tests')
