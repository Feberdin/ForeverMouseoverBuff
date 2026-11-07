-- Purpose: bounded local diagnostics shared by explicitly owned Feberdin addons.
-- Input: addon lifecycle and sanitized error location; output: separate SavedVariables.
-- Invariants: no names, chat, stack, locals or raw errors are retained; 100 records maximum.
-- Debug: /fcodiag status (or /fdiag<addon> status); disk updates on reload/logout only.
local addon, namespace = ...
local aliases = { FeberdinCharacterOverlay = 'fco', FeberdinQuestMarker = 'fqm',
  HardcoreRankGuard = 'hrg', RXPSafeTarget = 'rxp', ForeverGearAdvisor = 'fga',
  ForeverRankGuard = 'frg', ForeverMouseoverBuff = 'fmb', FeberdinFamilie = 'ff', ImYOURhealer = 'iyh',
  PallyPower = 'fpp', HealBot = 'fhb', WhatsTraining = 'fwt' }
if not aliases[addon] then return end
local variable = addon .. 'DiagnosticsDB'
local state = { schema = 1, enabled = false, sequence = 0, events = {} }
local codes = { READY = true, LUA_ERROR = true, DEBUG_TICK = true, HOOK_UNAVAILABLE = true, CAPTURE_FAILED = true }
local hooked = false
local frameHooked = false
local fallbackHooked = false
local captureHooked = false

-- JSON needs no general serializer: all strings below come from fixed vocabulary
-- or restricted source filenames. Never pass arbitrary event payloads to this API.
local function save()
  local rows = {}
  for _, event in ipairs(state.events) do
    rows[#rows + 1] = string.format('{"code":"%s","file":"%s","line":%d,"sequence":%d}',
      event.code, event.file, event.line, event.sequence)
  end
  state.exportJSON = string.format('{"schema":1,"addon":"%s","enabled":%s,"events":[%s]}',
    addon, tostring(state.enabled), table.concat(rows, ','))
  _G[variable] = state
end
local function cleanLocation(file, line)
  if type(file) ~= 'string' or #file > 80 or not file:match('^[%w_%-]+%.lua$') then return '', 0 end
  if type(line) ~= 'number' or line < 0 or line > 1000000 or line ~= math.floor(line) then return '', 0 end
  return file, line
end
local function record(code, file, line)
  if not codes[code] or (code == 'DEBUG_TICK' and not state.enabled) then return end
  file, line = cleanLocation(file, line)
  state.sequence = (state.sequence % 1000000000) + 1
  state.events[#state.events + 1] = { code = code, file = file, line = line, sequence = state.sequence }
  if #state.events > 100 then table.remove(state.events, 1) end
  save()
end

-- Extract only an error's initial source location belonging to this addon.
-- Example: Interface/AddOns/<own>/Core.lua:42: private text -> Core.lua, 42.
local function observe(message)
  if type(message) ~= 'string' then return end
  if type(issecretvalue) == 'function' and issecretvalue(message) then return end
  local normalized = message:sub(1, 512):gsub('\\', '/')
  local owner, file, line = normalized:match('^Interface/AddOns/([%w_%-]+)/([%w_%-]+%.lua):(%d+):')
  if not owner then owner, file, line = normalized:match('^%[string "@?Interface/AddOns/([%w_%-]+)/([%w_%-]+%.lua)"%]:(%d+):') end
  if owner == addon then record('LUA_ERROR', file, tonumber(line)) end
end
local function attach()
  if frameHooked or type(hooksecurefunc) ~= 'function' then return end
  if type(ScriptErrorsFrame) == 'table' and type(ScriptErrorsFrame.DisplayMessageInternal) == 'function' then
    hooksecurefunc(ScriptErrorsFrame, 'DisplayMessageInternal', function(_, message, messageType) if messageType == 0 then observe(message) end end)
    hooked = true
    frameHooked = true
  elseif not fallbackHooked and type(CallErrorHandler) == 'function' then
    hooksecurefunc('CallErrorHandler', function(message) if not frameHooked then observe(message) end end)
    fallbackHooked = true
  end
end

-- Expose only sanitized detached state. Callers cannot mutate the stored ring.
FeberdinDiagnostics = FeberdinDiagnostics or {}
FeberdinDiagnostics[addon] = {
  Record = record,
  Status = function()
    local result = { enabled = state.enabled, hooked = hooked,
      hookMode = frameHooked and 'blizzard-frame' or fallbackHooked and 'call-error-handler' or 'unavailable', events = {} }
    for _, event in ipairs(state.events) do
      result.events[#result.events + 1] = { code = event.code, file = event.file, line = event.line, sequence = event.sequence }
    end
    return result
  end,
}
local slashKey = 'FEBERDINDIAG_' .. aliases[addon]:upper()
_G['SLASH_' .. slashKey .. '1'] = '/' .. aliases[addon] .. 'diag'
SlashCmdList[slashKey] = function(command)
  command = type(command) == 'string' and command:lower():match('^%s*(.-)%s*$') or ''
  if command == 'on' then state.enabled = true; record('DEBUG_TICK')
  elseif command == 'off' then state.enabled = false; save()
  elseif command == 'clear' then state.events = {}; save() end
  if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
    DEFAULT_CHAT_FRAME:AddMessage(addon .. ' Diagnose: debug=' .. tostring(state.enabled) ..
      ', hook=' .. (frameHooked and 'blizzard-frame' or fallbackHooked and 'partial-call-error-handler' or 'unavailable') .. ', Eintraege=' .. #state.events ..
      '. Befehle: on / off / status / clear. Datei wird erst bei /reload oder Logout aktualisiert.')
  end
end
local frame = CreateFrame('Frame')
frame:RegisterEvent('ADDON_LOADED')
frame:RegisterEvent('PLAYER_LOGOUT')
frame:RegisterEvent('PLAYER_ENTERING_WORLD')
frame:SetScript('OnEvent', function(_, event, name)
  if event == 'ADDON_LOADED' and name == addon then
    local saved = _G[variable]
    local pending = state.events
    state.events = {}
    if type(saved) == 'table' and saved.schema == 1 then
      state.enabled = saved.enabled == true
      if type(saved.events) == 'table' then
        -- Rebuild old entries through validation; unknown saved fields disappear.
        for index = math.max(1, #saved.events - 99), math.min(#saved.events, 10000) do
          local item = saved.events[index]
          if type(item) == 'table' and codes[item.code] then record(item.code, item.file, item.line) end
        end
      end
    end
    for _, item in ipairs(pending) do record(item.code, item.file, item.line) end
    attach()
    -- The overlay catches collector failures with pcall, before Blizzard sees them.
    -- Observe that explicit own boundary too, retaining only a fixed category.
    if addon == 'FeberdinCharacterOverlay' and not captureHooked
      and type(namespace) == 'table' and type(namespace.Core) == 'table'
      and type(namespace.Core.CaptureDiagnostic) == 'function' and type(hooksecurefunc) == 'function' then
      hooksecurefunc(namespace.Core, 'CaptureDiagnostic', function() record('CAPTURE_FAILED') end)
      captureHooked = true
    end
    record('READY')
    if not hooked then record('HOOK_UNAVAILABLE') end
  elseif event == 'ADDON_LOADED' then attach()
  elseif event == 'PLAYER_ENTERING_WORLD' then record('DEBUG_TICK')
  elseif event == 'PLAYER_LOGOUT' then save() end
end)
attach()
