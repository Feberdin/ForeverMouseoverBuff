-- Purpose: thank a readable friendly player for newly received classic buffs.
-- Input: complete public player HELPFUL aura snapshots, clock, saved on/off switch.
-- Output: one named native THANK request; fixed diagnostic codes, no stored identities.
-- Invariants: no target/attack/cast/key changes; unknown/restricted data fails closed.
-- Debug: /fmb thanks on|off; /fmb status; LastCode contains no native exception text.
local _, ns = ...
local Thanks = {}
ns.AutoThanks = Thanks
local previous, pending, cooldowns, lastRequest, lastClock
local MAX_AURAS, BUNDLE_SECONDS, CASTER_SECONDS, GLOBAL_SECONDS = 128, 2, 60, 5

-- A finite allowlist excludes heals, item procs, hostile spells and automatic
-- short-lived class effects. Include classic ranks, raid variants and thorns;
-- new Forever-only spell IDs deliberately need an explicit reviewed addition.
local allowed = {}
for _, ids in ipairs({
    {19740,19834,19835,19836,19837,19838,25782,25916}, -- Might
    {19742,19850,19852,19853,19854,25894,25918}, -- Wisdom
    {20217,25898,20911,20912,20913,20914,25899}, -- Kings, Sanctuary
    {1243,1244,1245,2791,10937,10938,21562,21564}, -- Fortitude
    {1459,1460,1461,10156,10157,23028}, -- Intellect
    {1126,5232,6756,5234,8907,9884,9885,21849,21850}, -- Mark/Gift
    {976,10957,10958,27683,14752,14818,14819,27841,27681}, -- Priest protection/spirit
    {467,782,1075,8914,9756,9910}, -- Thorns
    {1008,8455,10169,10170,604,8450,8451,10173,10174}, -- Mage magic buffs
    {546,131,15107,15111,15112}, -- Water breathing/walking, wild protection
}) do for _, id in ipairs(ids) do allowed[id] = true end end

-- Check secrecy before comparing, indexing or string processing native results.
-- Every API can throw; drop its exception rather than retaining private text.
local function public(value)
    if type(issecretvalue) ~= "function" then return false end
    local ok, secret = pcall(issecretvalue, value)
    return ok and secret == false
end
local function readable(value)
    if not public(value) or type(value) ~= "table" or type(canaccesstable) ~= "function" then return false end
    local ok, access = pcall(canaccesstable, value)
    return ok and public(access) and access == true
end
local function field(value, key)
    if not readable(value) then return nil end
    local result = rawget(value, key)
    if public(result) then return result end
end
local function invoke(fn, ...)
    if not public(fn) or type(fn) ~= "function" then return nil end
    local ok, first, second = pcall(fn, ...)
    if ok and public(first) and public(second) then return first, second end
end
local function finite(value)
    return public(value) and type(value) == "number" and value == value and value >= 0 and value < math.huge
end
local function text(value)
    return public(value) and type(value) == "string" and #value > 0 and #value <= 150
        and not value:find("[%c%s|/;%[%]]")
end
local function code(value)
    if Thanks.LastCode == value then return end
    Thanks.LastCode = value
    -- Logging is optional and guarded. A diagnostic failure never logs itself.
    if type(ns.Log) == "function" then pcall(ns.Log, ns, value) end
end
local function clock()
    local stamp = invoke(GetTime)
    if not finite(stamp) then Thanks.Reset(); code("THANKS_CLOCK_UNAVAILABLE"); return nil end
    if lastClock and stamp < lastClock then
        Thanks.Reset(); lastRequest, cooldowns = nil, {}; code("THANKS_CLOCK_RESET")
    end
    lastClock = stamp
    return stamp
end

-- Unit tokens are resolved now, never again after the two-second bundle delay:
-- party/target/nameplate tokens may point at somebody else by then. Keep only
-- the validated full name and GUID in memory, never SavedVariables or logs.
local function caster(unit)
    if not text(unit) then return nil, "unknown" end
    local isPlayer = invoke(UnitIsPlayer, unit)
    local isSelf = invoke(UnitIsUnit, unit, "player")
    local assist = invoke(UnitCanAssist, "player", unit)
    if isPlayer == false or isSelf == true or assist == false then return nil, "ignored" end
    if isPlayer ~= true or isSelf ~= false or assist ~= true then return nil, "unknown" end
    local guid, selfGUID = invoke(UnitGUID, unit), invoke(UnitGUID, "player")
    if not text(guid) or not text(selfGUID) or guid == selfGUID then return nil, "unknown" end
    local name, realm = invoke(UnitName, unit)
    if not text(name) then return nil, "unknown" end
    if realm ~= nil and realm ~= "" then
        if not text(realm) then return nil, "unknown" end
        name = name .. "-" .. realm
    end
    return guid, name
end

-- A complete scan is the transaction boundary: a partial/secret snapshot never
-- becomes a baseline and cannot turn existing buffs into apparently new ones.
local function scan()
    if not public(C_Secrets) then return nil end
    if C_Secrets ~= nil and invoke(field(C_Secrets, "ShouldAurasBeSecret")) ~= false then return nil end
    local getter = field(C_UnitAuras, "GetAuraDataByIndex")
    if type(getter) ~= "function" then return nil end
    local snapshot = {}
    for index = 1, MAX_AURAS + 1 do
        local ok, aura = pcall(getter, "player", index, "HELPFUL")
        if not ok or not public(aura) then return nil end
        if aura == nil then return snapshot end
        if index > MAX_AURAS or not readable(aura) then return nil end
        local id, expiry = field(aura, "spellId"), field(aura, "expirationTime")
        if not finite(id) or id ~= math.floor(id) then return nil end
        if allowed[id] then
            -- Missing timing/caster is not evidence of a new external buff.
            local guid, name = caster(field(aura, "sourceUnit"))
            -- If an allowed caster is temporarily unreadable, abandon the whole
            -- observation. Recovery is a silent baseline, never a new buff.
            if not guid and name == "unknown" then return nil end
            if guid and not finite(expiry) then return nil end
            if guid then
                snapshot[id .. ":" .. guid] = {guid = guid, name = name, expiry = expiry}
            end
        end
    end
end
function Thanks.Reset()
    previous, pending = nil, {}
    cooldowns = cooldowns or {}
end
function Thanks.Check()
    if not ns.db or ns.db.autoThanks ~= true then Thanks.Reset(); return end
    local stamp = clock()
    if not stamp then return end
    local current = scan()
    if not current then Thanks.Reset(); code("THANKS_AURAS_UNKNOWN"); return end
    if previous then
        local queued = 0
        for _ in pairs(pending) do queued = queued + 1 end
        for key, buff in pairs(current) do
            local old = previous[key]
            if (not old or old.expiry ~= buff.expiry) and not pending[buff.guid]
                and (not cooldowns[buff.guid] or stamp - cooldowns[buff.guid] >= CASTER_SECONDS)
                and queued < 16 then
                pending[buff.guid] = {name = buff.name, due = stamp + BUNDLE_SECONDS, expires = stamp + 20}
                queued = queued + 1
            end
        end
    end
    previous = current
end

-- Only a native social emote is requested: no macro, target switch, attack stop
-- or protected action. A void return confirms only that Lua accepted the call,
-- not that the server delivered it. Errors are never retried for this buff.
function Thanks.Tick()
    if not ns.db or ns.db.autoThanks ~= true then Thanks.Reset(); return end
    local stamp = clock()
    if not stamp then return end
    for guid, last in pairs(cooldowns) do if stamp - last >= CASTER_SECONDS then cooldowns[guid] = nil end end
    local selected, request
    for guid, item in pairs(pending) do
        if stamp > item.expires then pending[guid] = nil
        elseif stamp >= item.due and (not request or item.due < request.due
            or (item.due == request.due and guid < selected)) then selected, request = guid, item end
    end
    if not request or (lastRequest and stamp - lastRequest < GLOBAL_SECONDS) then return end
    pending[selected], cooldowns[selected], lastRequest = nil, stamp, stamp
    -- Forever's extracted native slash handler uses PerformEmote(token, name).
    -- Prefer it; legacy DoEmote is used only when the native function is absent.
    -- Never retry another API after rejection: acceptance can be ambiguous.
    local emote, native = field(C_ChatInfo, "PerformEmote"), true
    if type(emote) ~= "function" then
        emote, native = public(DoEmote) and DoEmote or nil, false
    end
    if type(emote) ~= "function" then code("THANKS_EMOTE_UNAVAILABLE"); return end
    local ok, restricted = pcall(emote, "THANK", request.name)
    if not ok then code("THANKS_EMOTE_FAILED")
    elseif native and (not public(restricted) or (restricted ~= nil and restricted ~= false)) then
        code("THANKS_EMOTE_RESTRICTED")
    else code("THANKS_REQUESTED") end
end
Thanks.Reset()
