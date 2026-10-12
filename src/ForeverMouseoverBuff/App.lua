-- Purpose: automatic OOC blessings, a fixed learned Kings combat binding, and feedback.
-- Input: public API snapshots, /fmb, Blizzard key bindings and UI events.
-- Output: status, throttled feedback, native key-up casts, confirmed whispers and seal reminders.
-- Invariants: no hover/timer casts, key replacement, self fallback or dynamic combat selection.
-- Debug: /fmb diag; /fmb debug on; /fmb status. Structured local logs flush on reload/logout.
local _, ns = ...
ns.VERSION = "0.7.5"
local binding = "CLICK ForeverMouseoverBuffButton:LeftButton"
local modes = {auto = "Auto", might = "Macht", wisdom = "Weisheit", kings = "Könige"}
local elapsed = 0
local feedbackInterval = 2
BINDING_HEADER_FOREVERMOUSEOVERBUFF = "Forever Mouseover Buff"
_G["BINDING_NAME_" .. binding] = "Mouseover buffen: Auto / im Kampf Könige"

local function say(text)
    if DEFAULT_CHAT_FRAME and type(DEFAULT_CHAT_FRAME.AddMessage) == "function" then
        DEFAULT_CHAT_FRAME:AddMessage("|cff70c9ffFMB|r " .. text)
    end
end
local function safeString(value)
    if type(issecretvalue) == "function" then
        local ok, restricted = pcall(issecretvalue, value)
        if not ok or restricted ~= false then return nil end
    end
    if type(value) == "string" and #value <= 300 then return value end
end
local function blocked(code, text) return {ready = false, code = code, text = text} end

-- Only fixed reason codes and small counters are retained. No names, GUIDs,
-- messages or native exception text enter SavedVariables through this ledger.
local function diagnosticCode(value)
    return ns.DiagnosticLog and ns.DiagnosticLog.IsCode(value) or false
end
local function now()
    if type(GetTime) ~= "function" or type(issecretvalue) ~= "function" then return nil end
    local ok, value = pcall(GetTime)
    if not ok then return nil end
    local checked, restricted = pcall(issecretvalue, value)
    if checked and restricted == false and type(value) == "number"
        and value == value and value >= 0 and value < math.huge then return value end
end

-- Sound is requested only by explicit input or a matching failed cast event.
-- Keep the native sound channel/volume; acceptance is not proof of audibility.
function ns:PlayFeedbackSound()
    local soundID = type(SOUNDKIT) == "table" and SOUNDKIT.RAID_WARNING
    local accepted = false
    if type(PlaySound) == "function" and type(issecretvalue) == "function" then
        local checked, restricted = pcall(issecretvalue, soundID)
        if checked and restricted == false and type(soundID) == "number"
            and soundID > 0 and soundID < 2147483647 and soundID == math.floor(soundID) then
            local ok, result = pcall(PlaySound, soundID)
            if ok then
                local readable, secret = pcall(issecretvalue, result)
                accepted = readable and secret == false and result == true
            end
        end
    end
    self:Log(accepted and "SOUND_REQUESTED" or "SOUND_FAILED")
    if not accepted and not self.soundFailureReported then
        self.soundFailureReported = true
        say("Hinweiston konnte nicht bestätigt werden. Text bleibt aktiv; /fmb soundtest und WoW-Soundoptionen prüfen.")
    end
    return accepted
end

-- Reuse the freshly computed explanation, without reading a target or touching
-- protected action attributes. Changed reasons show immediately; tones have a
-- shared two-second limit. Without a readable clock, sound runs only once.
-- Example: NO_TARGET → OUT_OF_RANGE in 0.5 s shows both reasons but plays one tone.
function ns:Feedback(decision)
    local stamp = now()
    if not stamp then self:Log("FEEDBACK_CLOCK_UNAVAILABLE") end
    local textDue = self.lastFeedbackCode ~= decision.code
        or (stamp and (not self.lastFeedbackAt or stamp < self.lastFeedbackAt
            or stamp - self.lastFeedbackAt >= feedbackInterval))
    if textDue then
        self.lastFeedbackCode, self.lastFeedbackAt = decision.code, stamp
        local message = "Kein Buff: " .. decision.text
        say(message)
        local shown = false
        if UIErrorsFrame and type(UIErrorsFrame.AddMessage) == "function" then
            shown = pcall(UIErrorsFrame.AddMessage, UIErrorsFrame, "FMB – " .. message, 1, 0.8, 0.2)
        end
        if not shown then self:Log("FEEDBACK_UI_UNAVAILABLE") end
    end
    if not self.db.sound then return end
    local soundDue
    if stamp then
        soundDue = not self.lastFeedbackSoundAt or stamp < self.lastFeedbackSoundAt
            or stamp - self.lastFeedbackSoundAt >= feedbackInterval
    else
        soundDue = not self.soundWithoutClock
        self.soundWithoutClock = true
    end
    if soundDue then
        self.lastFeedbackSoundAt = stamp
        self:PlayFeedbackSound()
    end
end

local function combatFeedback(self)
    self:Log("PLAYER_IN_COMBAT")
    self:Feedback(blocked("PLAYER_IN_COMBAT", "Im Kampf gesperrt. Bitte außerhalb des Kampfes erneut drücken."))
end

function ns:InitializeDiagnostics()
    self.diagnosticFallback = {version = self.VERSION, schema = 2, events = {}, codes = {},
        status = {}, attempts = 0, confirmed = 0, failed = 0, storageAvailable = false}
    if self.DiagnosticLog then self.DiagnosticLog.Initialize(self.db, self.VERSION) end
    local snapshot = self:DiagnosticSnapshot()
    self.logs, self.lastCode = snapshot.codes, snapshot.codes[#snapshot.codes]
end

-- Diagnostics are an observer only. A damaged/inaccessible imported diagnostic
-- table must not participate in cast counters, UI string operations or arithmetic.
function ns:DiagnosticSnapshot()
    if self.DiagnosticLog then return self.DiagnosticLog.Snapshot() end
    return self.diagnosticFallback or {version = self.VERSION, events = {}, codes = {}, status = {},
        attempts = 0, confirmed = 0, failed = 0, storageAvailable = false}
end
function ns:IncrementDiagnostic(key)
    if self.DiagnosticLog then return self.DiagnosticLog.Increment(key) end
    local fallback = self.diagnosticFallback
    if fallback and (key == "attempts" or key == "confirmed" or key == "failed") then
        fallback[key] = math.min(1000000000, fallback[key] + 1)
    end
end

-- Client information is static for a session and contains only numeric version
-- tokens. Cache the API result once; polling the buff preview needs no API read.
function ns:CaptureDiagnosticClient()
    self.diagnosticClient = {}
    if not self.API or type(self.API.Client) ~= "function" then return end
    local ok, client = pcall(self.API.Client)
    if not ok or type(issecretvalue) ~= "function" or type(canaccesstable) ~= "function" then return end
    local checked, secret = pcall(issecretvalue, client)
    if not checked or secret ~= false or type(client) ~= "table" then return end
    local accessed, access = pcall(canaccesstable, client)
    local public, restricted = pcall(issecretvalue, access)
    if not accessed or not public or restricted ~= false or access ~= true then return end
    self.diagnosticClient = {version = rawget(client, "version"), build = rawget(client, "build"),
        interface = rawget(client, "interface")}
end
function ns:RefreshDiagnosticStatus()
    if not self.DiagnosticLog then return end
    local client = self.diagnosticClient or {}
    self.DiagnosticLog.UpdateStatus({enabled = self.db.enabled, debug = self.db.debug,
        sound = self.db.sound, whisper = self.db.whisper, receiveWhispers = self.db.receiveWhispers,
        showOutgoingWhispers = self.db.showOutgoingWhispers, sealSound = self.db.sealSound,
        rankingEnabled = self.db.rankingEnabled, buttonReady = self.button ~= nil, routerReady = self.router ~= nil,
        clientVersion = client.version, clientBuild = client.build, clientInterface = client.interface})
end

function ns:Log(code)
    code = self.DiagnosticLog and self.DiagnosticLog.Normalize(code) or "DIAGNOSTIC_INVALID"
    -- During a preview, collect a bounded signature first. Repeated API errors
    -- may alternate codes, so adjacent-code deduplication alone would still spam.
    if self.previewCodes then
        if not self.previewSeen[code] and #self.previewCodes < 39 then
            self.previewCodes[#self.previewCodes + 1] = code
            self.previewSeen[code] = true
        end
        return
    end
    if self.lastCode == code then return end
    self.lastCode = code
    if self.DiagnosticLog then
        self.DiagnosticLog.Record(code)
        self.logs = self.DiagnosticLog.Snapshot().codes
    else
        self.logs = self.logs or {}
        self.logs[#self.logs + 1] = code
        if #self.logs > 40 then table.remove(self.logs, 1) end
    end
    if self.db and self.db.debug then say("DEBUG " .. code) end
end

function ns:BindingKey()
    if type(GetBindingKey) ~= "function" then return nil end
    local ok, key = pcall(GetBindingKey, binding)
    key = ok and safeString(key)
    if key and key ~= "" then return key end
end

function ns:BindingLabel()
    return self:BindingKey() or "Noch keine Taste – WoW-Tastaturbelegung öffnen"
end

-- The protected router keeps the original binding name. Its combat branch is
-- fixed BEFORE combat; the OOC child still uses an exact spell ID and Blizzard's
-- native OOC guard. No rank strings, restricted snippets or user keys are edited.
function ns:RefreshCombatAction()
    if self.API.Locked() then self.combatDirty = true; return false end
    if not self.router then return false end
    local spell, reason
    if self.db.enabled and type(self.API.CombatBlessing) == "function" then
        local ok, value, code = pcall(self.API.CombatBlessing)
        if ok then spell, reason = value, code end
    end
    local name = type(spell) == "table" and safeString(spell.spellName)
    if not name or name == "" or name:find("[%c|;/%[%]]") or spell.spellID ~= 20217 then spell = nil end
    if self.API.Locked() then self.combatDirty = true; return false end
    self.combatSpell = spell
    self.combatReason = diagnosticCode(reason) and reason or "COMBAT_SPELL_UNAVAILABLE"
    self.combatEnabled, self.combatDirty = self.db.enabled, false
    local lines = {}
    if self.combatEnabled then
        if spell then lines[#lines + 1] = "/cast [combat,@mouseover,help,nodead] " .. name end
        lines[#lines + 1] = "/click [nocombat] ForeverMouseoverBuffAutoButton LeftButton"
    end
    self.router:SetAttribute("*type1", "macro")
    self.router:SetAttribute("*macrotext1", table.concat(lines, "\n"))
    self:Log(self.combatEnabled and self.combatReason or "DISABLED")
    return true
end

function ns:CombatDecision()
    if not self.combatEnabled then return blocked("DISABLED", "Ausgeschaltet. Änderungen der Kampfbelegung gelten erst nach dem Kampf.") end
    if not self.combatSpell then
        if self.combatReason == "COMBAT_SPELL_NOT_LEARNED" then
            return blocked(self.combatReason, "Im Kampf ist Segen der Könige vorgesehen, aber noch nicht gelernt.")
        end
        return blocked("COMBAT_SPELL_UNAVAILABLE", "Könige konnte vor dem Kampf nicht vorbereitet werden. Nach dem Kampf /fmb status prüfen.")
    end
    return {ready = true, code = "COMBAT_FIXED_READY", spellID = 20217,
        text = "Im Kampf: Könige auf ein lebendes freundliches Mouseover-Ziel. Keine Prüfung vorhandener Segen."
            .. (self.combatDirty and " Änderungen gelten nach dem Kampf." or "")}
end

-- A displayed recommendation is never an armed action. The full context is read
-- again on each deliberate click, so a changed mouseover cannot reuse old data.
function ns:Decision()
    if not self.button or not self.router then return blocked("BUTTON_UNAVAILABLE", "Blizzards Buff-Schaltfläche fehlt. /fmb status prüfen.") end
    if self.API.Locked() then return self:CombatDecision() end
    if not self.db.enabled then return blocked("DISABLED", "Ausgeschaltet. Mit /fmb on wieder aktivieren.") end
    if not self:BindingKey() then
        return blocked("NO_BINDING", "Buff-Taste fehlt: WoW-Tastaturbelegung → Forever Mouseover Buff. Drüberfahren allein wirkt keinen Zauber.")
    end
    local ok, context = pcall(self.API.ReadContext, self.db.mode)
    if not ok then return blocked("CONTEXT_ERROR", "Spielerdaten konnten nicht gelesen werden. /fmb status prüfen.") end
    local good, decision = pcall(self.Core.Decide, context)
    if not good or type(decision) ~= "table" then
        return blocked("DECISION_ERROR", "Buff-Auswahl fehlgeschlagen. /fmb status prüfen.")
    end
    return decision
end

function ns:Refresh()
    if not self.initialized then return end
    self.previewCodes, self.previewSeen = {}, {}
    self.decision = self:Decision()
    local codes = self.previewCodes
    self.previewCodes, self.previewSeen = nil, nil
    codes[#codes + 1] = self.decision.code
    local signature = table.concat(codes, ",")
    if signature ~= self.lastPreviewSignature then
        self.lastPreviewSignature = signature
        for _, code in ipairs(codes) do self:Log(code) end
    end
    -- Keep the latest explanation separately: logging alternating READY_FALLBACK
    -- and its reason on every poll would fill the bounded history in seconds.
    if self.DiagnosticLog then self.DiagnosticLog.SetFallback(self.decision.fallbackReason) end
    self:RefreshDiagnosticStatus()
    if self.Menu then self.Menu.Refresh() end
end

local function clearAction(button)
    button:SetAttribute("type1", nil)
    button:SetAttribute("spell1", nil)
    button:SetAttribute("*type1", nil)
    button:SetAttribute("*spell1", nil)
end

function ns:TrackAttempt(spellID)
    self:IncrementDiagnostic("attempts")
    self.pendingCast = {spellID = spellID, started = now()}
    if self.Whisper then self.Whisper.Begin(spellID) end
    self:Log("CAST_REQUESTED")
end

-- The macro's native [combat] condition decides which action can actually run.
-- This callback observes input only; it never edits a protected combat action.
function ns:RouterPreClick(_, mouseButton, down)
    if mouseButton ~= "LeftButton" or down then return end
    self.routerStartedInCombat = self.API.Locked()
    local diagnostics = self:DiagnosticSnapshot()
    self.routerResultsBefore = diagnostics.confirmed + diagnostics.failed
    if not self.routerStartedInCombat then return end
    local decision = self:CombatDecision()
    self.decision = decision
    self:Log(decision.code)
    if decision.ready then self:TrackAttempt(decision.spellID)
    else self:Feedback(decision) end
end

function ns:RouterPostClick(_, mouseButton, down)
    if mouseButton ~= "LeftButton" or down or self.routerStartedInCombat or not self.API.Locked() then return end
    local diagnostics = self:DiagnosticSnapshot()
    if diagnostics.confirmed + diagnostics.failed ~= self.routerResultsBefore then return end
    -- Combat may begin before the macro picks a branch. With no prepared Kings
    -- action the native macro then does nothing, which still deserves feedback.
    local decision = self:CombatDecision()
    if not decision.ready then self:Feedback(decision) end
end

function ns:PreClick(button, mouseButton, down)
    self.preparedClick = false
    if self.API.Locked() then
        if mouseButton == "LeftButton" and not down then combatFeedback(self) end
        return
    end
    clearAction(button)
    if mouseButton ~= "LeftButton" or down then return end
    local decision = self:Decision()
    self.decision = decision
    self:Log(decision.code)
    if not decision.ready then self:Feedback(decision); return end
    if self.API.Locked() then combatFeedback(self); return end
    -- CLICK bindings keep physical Alt/Ctrl/Shift modifiers. Wildcard attributes
    -- let the same mouseover action work for Alt+B and extra mouse buttons alike.
    button:SetAttribute("*spell1", decision.spellID)
    button:SetAttribute("*type1", "spell")
    self:TrackAttempt(decision.spellID)
    self.preparedClick = true
end

-- The native action might fail (range, GCD, or a combat transition). A request
-- counts as confirmed only after a matching public player event within 5 seconds.
-- Cast GUIDs are deliberately ignored; events do not trigger another action.
function ns:ObserveCast(event, unit, spellID)
    local pending = self.pendingCast
    if not pending then return end
    local stamp = now()
    if not stamp or not pending.started or stamp - pending.started > 5
        or stamp < pending.started then self.pendingCast = nil; return end
    unit = safeString(unit)
    if unit ~= "player" or type(issecretvalue) ~= "function" then return end
    local checked, restricted = pcall(issecretvalue, spellID)
    if not checked or restricted ~= false or type(spellID) ~= "number"
        or spellID ~= pending.spellID then return end
    self.pendingCast = nil
    local success = event == "UNIT_SPELLCAST_SUCCEEDED"
    local key = success and "confirmed" or "failed"
    self:IncrementDiagnostic(key)
    self:Log(success and "CAST_CONFIRMED" or "CAST_FAILED")
    if not success then
        self:Feedback(blocked("CAST_FAILED", "Der Buff ist fehlgeschlagen oder wurde unterbrochen. WoW-Fehlermeldung beachten und erneut versuchen."))
    end
end

function ns:PostClick(button)
    local prepared = self.preparedClick
    self.preparedClick = false
    if self.API.Locked() then
        -- A synchronous cast event may already have confirmed or reported this
        -- request. Do not turn that result into a second combat failure notice.
        if prepared and self.pendingCast then combatFeedback(self) end
        return
    end
    clearAction(button)
    self:Refresh()
end

-- Native InsecureActionButtonTemplate contains the OOC guard in its OnClick.
-- It is intentionally NOT replaced or hooked, and needs no dynamic secure snippets.
-- The 1px noninteractive button remains shown so the standard CLICK key binding
-- can address it; actual mouse clicks remain free for the world/player frames.
function ns:CreateActionButton()
    if self.API.Locked() then return false end
    if type(C_Macro) ~= "table" or type(C_Macro.RunMacroText) ~= "function" then
        self:Log("MACRO_API_UNAVAILABLE"); return false
    end
    local ok, button = pcall(CreateFrame, "Button", "ForeverMouseoverBuffAutoButton", UIParent, "InsecureActionButtonTemplate")
    if not ok or not button then self:Log("BUTTON_UNAVAILABLE"); return false end
    self.button = button
    button:SetSize(1, 1)
    button:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
    button:SetAlpha(0)
    button:EnableMouse(false)
    button:RegisterForClicks("AnyUp")
    button:SetAttribute("useOnKeyDown", false)
    button:SetAttribute("pressAndHoldAction", false)
    button:SetAttribute("unit", "mouseover")
    button:SetAttribute("checkselfcast", false)
    button:SetAttribute("checkfocuscast", false)
    clearAction(button)
    button:SetScript("PreClick", function(self, key, down) ns:PreClick(self, key, down) end)
    button:SetScript("PostClick", function(self) ns:PostClick(self) end)
    local good, router = pcall(CreateFrame, "Button", "ForeverMouseoverBuffButton", UIParent, "SecureActionButtonTemplate")
    if not good or not router then self.button = nil; self:Log("BUTTON_UNAVAILABLE"); return false end
    self.router = router
    router:SetSize(1, 1)
    router:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
    router:SetAlpha(0)
    router:EnableMouse(false)
    router:RegisterForClicks("AnyUp")
    router:SetAttribute("useOnKeyDown", false)
    router:SetAttribute("pressAndHoldAction", false)
    -- Do not set a router unit: Blizzard would skip the whole macro when that
    -- unit is absent, swallowing the child's useful NO_TARGET feedback as well.
    -- The combat macro and the OOC child each pin their own mouseover target.
    router:SetAttribute("checkselfcast", false)
    router:SetAttribute("checkfocuscast", false)
    router:SetScript("PreClick", function(self, key, down) ns:RouterPreClick(self, key, down) end)
    router:SetScript("PostClick", function(self, key, down) ns:RouterPostClick(self, key, down) end)
    self:RefreshCombatAction()
    return true
end

-- Presentation is isolated from casting and saved preferences. Commands return to
-- the selected Sanctum page, so changing a switch never loses the user's place.
function ns:ShowPanel()
    if not self.Menu then
        say("Menüdateien fehlen. Vollständiges Addonpaket installieren und /reload ausführen.")
        return
    end
    self.Menu.Show()
    self:Refresh()
end

function ns:Help()
    say("WoW-Optionen → Tastaturbelegung → Forever Mouseover Buff: freie Taste für Mouseover-Spieler buffen vergeben. Das Addon belegt keine Taste selbst.")
    say("Maus über einen befreundeten Spieler halten, Taste drücken und loslassen. Solange du selbst außerhalb des Kampfes bist, darf das Ziel auch kämpfen. Ein vorhandener gleichartiger Segen bleibt erhalten; Auto wählt eine hilfreiche Alternative. Auf Reittieren ist die Auto-Auswahl gesperrt.")
    say("Im Kampf: dieselbe Taste wirkt ausschließlich Segen der Könige, sobald gelernt. Keine Klassen-, Rang- oder Buffprüfung; eigene Segen können ersetzt werden. An/Aus-Änderungen gelten erst nach dem Kampf.")
    say("Auto: Krieger/Schurken Macht → Könige; Magier/Priester/Hexenmeister Weisheit → Könige; Jäger/Hybride Könige → Weisheit. Eigene nützliche Segen bleiben stehen. Nur gelernte Ränge bis zur Zielstufe.")
    say("/fmb auto | might | wisdom | kings wählt den Modus; /fmb on | off schaltet ein/aus. /fmb debug on, /fmb status, danach /fmb debug off für Fehlerdiagnose.")
    say("Gesperrte Buff-Taste: Erklärung im Bild und Chat, Hinweiston höchstens alle 2 Sekunden. /fmb sound on | off schaltet den Ton; /fmb soundtest prüft ihn.")
    say('Bestätigter Segen: zwölf wechselnde Grüße passend zu deiner Klasse und deinem Volk, mit Empfängername und passender Volksanrede. Bei unbekannter Klasse bleibt der Text neutral. /fmb whisper on | off schaltet ihn. Bei unklaren oder geschützten Empfängerdaten wird nichts gesendet.')
    say("Empfänger aller Klassen: /fmb receive off blendet automatische Addongrüße aus und lehnt neue Anfragen anderer FMB-Installationen ab. /fmb receive on erlaubt sie wieder. Eigene gesendete Grüße bleiben separat mit /fmb whisper on | off schaltbar. Der Addonname erscheint mit installiertem Addon goldfarben.")
    say("Eigene automatische Grüße im normalen Chat sind standardmäßig verborgen. /fmb outgoing on | off zeigt oder verbirgt sie; Versand und Empfangsschalter bleiben unabhängig. WIM zeigt sie nach seinen eigenen Einstellungen.")
    say("/fmb stats zeigt lokale, unbestätigte Buff-Zähler. /fmb ranking on | off stellt neue Ereignisse für einen freiwilligen Upload bereit; Standard aus. /fmb ranking help erklärt Dateiexport und Upload. Keine Empfänger werden exportiert.")
    say("/fmb diag zeigt das lokale Diagnoseprotokoll mit den letzten Ereignissen. Es enthält nur feste Codes und öffentliche Versions-/Schalterwerte. Erst /reload oder ausloggen schreibt es für eine Dateiauswertung auf die Festplatte.")
    say("/fmb feedback: Fehler, Wünsche oder Features mit Vorschau für GitHub vorbereiten. Technische Angaben sind freiwillig. Link markieren, mit Cmd/Strg+C kopieren und im Browser prüfen und absenden.")
    say("Siegel-Ablauf: ein kurzer Ton nach beobachtetem natürlichem Ende. /fmb seal on | off schaltet ihn unabhängig vom Buff-Hinweiston.")
end

function ns:Diagnostics()
    local diagnostic = self:DiagnosticSnapshot()
    local client = diagnostic.status
    return "Forever Mouseover Buff " .. self.VERSION .. " | Client " .. tostring(client.clientVersion or "unbekannt")
        .. " / " .. tostring(client.clientBuild or "unbekannt") .. " / " .. tostring(client.clientInterface or "unbekannt")
        .. "\nTaste: " .. self:BindingLabel() .. " | Modus: " .. modes[self.db.mode]
        .. " | Aktiv: " .. tostring(self.db.enabled) .. "\nStatus: " .. (self.decision and self.decision.text or "Noch nicht geprüft")
        .. "\nHinweiston: " .. (self.db.sound and "an" or "aus") .. " | Test: /fmb soundtest"
        .. " | Erfolgswhisper: " .. (self.db.whisper and "an" or "aus")
        .. " | Empfangene Grüße: " .. (self.db.receiveWhispers and "an" or "aus")
        .. " | Eigene Grüße im Chat: " .. (self.db.showOutgoingWhispers and "an" or "aus")
        .. " | Ranking-Export: " .. (self.db.rankingEnabled and "an (unbestätigt)" or "aus")
        .. " | Siegelton: " .. (self.db.sealSound and "an" or "aus")
        .. "\nKampf: " .. (self.combatSpell and "Könige vorbereitet" or "Könige nicht vorbereitet")
        .. (self.combatDirty and " | Änderung nach dem Kampf" or "")
        .. "\nCodes: " .. table.concat(self.logs or {}, ", ")
        .. "\nBuff-Versuche: " .. diagnostic.attempts .. " | Bestätigte Zauberereignisse: "
        .. diagnostic.confirmed .. " | Fehlgeschlagen: " .. diagnostic.failed
        .. "\nStrukturiertes Protokoll: /fmb diag. Datei wird erst bei /reload oder Ausloggen aktualisiert."
end

function ns:DiagnosticReport()
    self:RefreshDiagnosticStatus()
    local diagnostic = self:DiagnosticSnapshot()
    local lines = {"Diagnoseprotokoll " .. self.VERSION .. " | " .. #diagnostic.events .. "/64 Ereignisse | "
        .. (diagnostic.storageAvailable and "lokal bereit" or "nur im Arbeitsspeicher – Datei nicht beschreibbar"),
        "Versuche: " .. diagnostic.attempts .. " | Bestätigt: " .. diagnostic.confirmed .. " | Fehlgeschlagen: " .. diagnostic.failed}
    for index = math.max(1, #diagnostic.events - 4), #diagnostic.events do
        local event = diagnostic.events[index]
        lines[#lines + 1] = "#" .. event.sequence .. " [" .. event.severity .. "/" .. event.origin .. "] " .. event.code
    end
    lines[#lines + 1] = "Für direkte Dateiauswertung: /reload oder ausloggen. Vorher liegt das aktuelle Protokoll nur im Spielspeicher; keine automatische Übertragung."
    return table.concat(lines, "\n")
end

function ns:Command(command)
    if not self.initialized then self:Initialize() end
    command = (safeString(command) or ""):match("^%s*(.-)%s*$"):lower()
    if modes[command] then self.db.mode = command
    elseif command == "on" or command == "off" then
        self.db.enabled = command == "on"
        if not self:RefreshCombatAction() and self.API.Locked() then
            say("Die Kampfbelegung bleibt bis Kampfende unverändert; diese Einstellung gilt nach dem Kampf.")
        end
    elseif command == "debug on" or command == "debug off" then
        self.db.debug = command == "debug on"; say("Debug " .. (self.db.debug and "an" or "aus") .. ".")
    elseif command == "sound on" or command == "sound off" then
        self.db.sound = command == "sound on"
        say("Hinweiston " .. (self.db.sound and "an" or "aus") .. ".")
    elseif command == "whisper on" or command == "whisper off" then
        self.db.whisper = command == "whisper on"
        say("Erfolgswhisper " .. (self.db.whisper and "an" or "aus") .. ".")
    elseif command == "receive on" or command == "receive off" then
        self.db.receiveWhispers = command == "receive on"
        -- Existing callbacks read this setting live; do not add another WIM wrapper.
        say("Empfangene Addon-Segensgrüße " .. (self.db.receiveWhispers and "an" or "aus") .. ". Eigene gesendete Grüße bleiben unverändert.")
    elseif command == "outgoing on" or command == "outgoing off" then
        self.db.showOutgoingWhispers = command == "outgoing on"
        say("Eigene Grüße im Chat " .. (self.db.showOutgoingWhispers and "an" or "aus")
            .. ". Versand und WIM-Einstellungen bleiben unverändert.")
    elseif command == "seal on" or command == "seal off" then
        self.db.sealSound = command == "seal on"
        if self.SealReminder then self.SealReminder.Check() end
        say("Siegel-Ablaufton " .. (self.db.sealSound and "an" or "aus") .. ".")
    elseif command == "soundtest" then
        if not self.db.sound then say("Hinweiston ist aus. Mit /fmb sound on aktivieren.")
        elseif self:PlayFeedbackSound() then say("Testton angefordert. Falls unhörbar: WoW-Soundoptionen prüfen.") end
        return
    elseif command == "ranking help" then
        say("Community-Ranking: freiwillig und unbestätigt. Lokale Dateien sind veränderbar; Verschlüsselung wäre kein Echtheitsnachweis.")
        say("1. /fmb ranking on aktiviert neue Exportereignisse. 2. /reload oder ausloggen speichert die Datei.")
        say("3. Mit Companion export eine reine Ranking-JSON-Datei erzeugen (Anleitung im Paket). 4. Auf der Ranking-Seite Zugang und JSON auswählen, Vorschau prüfen und Upload ausdrücklich bestätigen.")
        say("Das Addon stellt keine Webverbindung her. Ohne eingerichtete Ranking-Seite gibt es keinen Online-Rang. /fmb ranking off beendet neue Exporte; laufenden Companion für sofortigen Uploadstopp beenden.")
        return
    elseif command == "ranking on" or command == "ranking off" then
        if not self.RankingExport or not self.RankingExport.SetEnabled(command == "ranking on") then
            say("Ranking-Export nicht verfügbar. /fmb status zeigt den Diagnosecode."); return
        end
        if self.db.rankingEnabled then
            say("Ranking-Export an (Community, unbestätigt). Neue Buff-Ereignisse werden lokal bereitgestellt. Upload nur über den separat eingerichteten Companion oder bewusst auf der Ranking-Seite. /reload speichert die Datei; /fmb ranking help erklärt den Ablauf.")
        else
            say("Ranking-Export aus; lokale Warteschlange geleert. Für sofortigen Uploadstopp den Companion stoppen; /reload speichert den Schalter in die Datei. Bereits hochgeladene Daten mit Companion leave löschen.")
        end
        self:Refresh()
        return
    elseif command == "stats" then
        if self.Stats then
            local summary = self.Stats.Summary()
            if summary.available == false then
                say("Buff-Statistik nicht verfügbar: Der Zählerspeicher ist beschädigt oder nicht lesbar. Er wurde unverändert erhalten. Vor einer Wiederherstellung die SavedVariables sichern; /fmb status zeigt Diagnosecodes.")
                return
            end
            say("Buff-Statistik (lokal, unbestätigt): " .. summary.total .. " Segen für andere Spieler.")
            say("Macht: " .. summary.families.might .. " | Weisheit: " .. summary.families.wisdom
                .. " | Könige: " .. summary.families.kings .. ". Erfasst werden erfolgreiche FMB-Klicks ab diesem Update.")
        else say("Statistik fehlt. Vollständiges Addonpaket installieren und neu laden.") end
        return
    elseif command == "feedback" or command == "feedback bug" or command == "feedback wish" or command == "feedback feature" then
        if type(self.ShowFeedbackPanel) == "function" then self:ShowFeedbackPanel(command:match("^feedback (%a+)$"))
        else say("Feedback-Menü fehlt. Vollständiges Addonpaket installieren und /reload ausführen.") end
        return
    elseif command == "diag" then say(self:DiagnosticReport()); return
    elseif command == "help" then self:Help(); return
    elseif command == "status" then self:Refresh(); say(self:Diagnostics()); return
    elseif command ~= "" then say("Unbekannter Befehl. /fmb help zeigt die verfügbaren Befehle."); return end
    self:ShowPanel()
end

function ns:Initialize()
    if self.initialized then return end
    if type(ForeverMouseoverBuffDB) ~= "table" then ForeverMouseoverBuffDB = {} end
    self.db = ForeverMouseoverBuffDB
    if type(self.db.mode) ~= "string" or not modes[self.db.mode] then self.db.mode = "auto" end
    if type(self.db.enabled) ~= "boolean" then self.db.enabled = true end
    self.db.debug = self.db.debug == true
    if type(self.db.sound) ~= "boolean" then self.db.sound = true end
    if type(self.db.whisper) ~= "boolean" then self.db.whisper = true end
    if type(self.db.sealSound) ~= "boolean" then self.db.sealSound = true end
    if type(self.db.receiveWhispers) ~= "boolean" then self.db.receiveWhispers = true end
    if type(self.db.showOutgoingWhispers) ~= "boolean" then self.db.showOutgoingWhispers = false end
    self.db.schema = 8
    self:InitializeDiagnostics()
    self:CaptureDiagnosticClient()
    self.initialized = true
    -- Validate/migrate counters before new casts or export initialization. An
    -- integrity failure preserves the imported record; it never implies zero.
    if self.Stats and type(self.Stats.Initialize) == "function" then
        local ok, ready = pcall(self.Stats.Initialize)
        if not ok then self:Log("STATS_INITIALIZE_FAILED") end
        if not ok or ready ~= true then
            say("Zählerspeicher nicht verfügbar; die vorhandenen Daten bleiben erhalten. /fmb stats zeigt Hinweise. Buffen bleibt möglich, neue Statistikpunkte werden erst nach einer erfolgreichen Prüfung gespeichert.")
        end
    end
    -- Recipient controls also initialize for non-paladins and disabled buffing.
    if self.Recipient then self.Recipient.Initialize() end
    if self.Chat then self.Chat.Initialize() end
    if self.RankingExport then self.RankingExport.Initialize() end
    self.API.RefreshSpellbook()
    self:CreateActionButton()
    self:ShowPanel()
    if self.SealReminder then self.SealReminder.Check() end
end

-- Polling is bounded to 4Hz for the visible suggestion and passive seal monitor.
function ns:Tick(delta)
    if not self.initialized or type(delta) ~= "number" then return end
    elapsed = elapsed + delta
    if elapsed >= 0.25 then
        elapsed = 0
        if self.Recipient then self.Recipient.Tick() end
        self:Refresh()
        if self.SealReminder then self.SealReminder.Check() end
    end
end

function ns:OnEvent(event, unit, second, third, fourth)
    if event == "PLAYER_LOGIN" then self:Initialize(); return end
    if not self.initialized then return end
    if event == "CHAT_MSG_ADDON" then
        if self.Recipient then self.Recipient.OnMessage(unit, second, third, fourth) end
        return
    end
    if event == "ADDON_LOADED" then
        if safeString(unit) == "WIM" and self.Chat then self.Chat.Initialize() end
        return
    end
    if event == "UNIT_AURA" then
        if safeString(unit) == "player" and self.SealReminder then self.SealReminder.Check() end
        return
    end
    if event == "UNIT_SPELLCAST_SENT" then
        if self.Whisper then self.Whisper.Sent(unit, second, third, fourth) end
        return
    end
    if event == "UNIT_SPELLCAST_SUCCEEDED" or event == "UNIT_SPELLCAST_FAILED"
        or event == "UNIT_SPELLCAST_INTERRUPTED" then
        if self.Whisper then self.Whisper.Complete(event, unit, second, third) end
        self:ObserveCast(event, unit, third)
        return
    end
    if event == "SPELLS_CHANGED" or event == "PLAYER_LEVEL_UP" or event == "PLAYER_ENTERING_WORLD" then
        self.API.RefreshSpellbook()
        self:RefreshCombatAction()
        if event == "PLAYER_ENTERING_WORLD" and self.SealReminder then self.SealReminder.Check() end
    elseif event == "PLAYER_REGEN_ENABLED" and not self.API.Locked() then
        if not self.button then self:CreateActionButton() end
        -- Combat can begin between PreClick and PostClick. Clear that interrupted
        -- preparation as soon as safe, without invoking the native action handler.
        if self.button then clearAction(self.button) end
        self:RefreshCombatAction()
    end
    self:Refresh()
end

local frame = CreateFrame("Frame")
for _, event in ipairs({"PLAYER_LOGIN", "CHAT_MSG_ADDON", "ADDON_LOADED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
    "PLAYER_ENTERING_WORLD", "UPDATE_MOUSEOVER_UNIT", "SPELLS_CHANGED", "PLAYER_LEVEL_UP", "UPDATE_BINDINGS", "UNIT_AURA",
    "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED"}) do
    local ok = pcall(frame.RegisterEvent, frame, event)
    if not ok then ns:Log("EVENT_UNAVAILABLE") end
end
frame:SetScript("OnEvent", function(_, event, ...) ns:OnEvent(event, ...) end)
frame:SetScript("OnUpdate", function(_, delta) ns:Tick(delta) end)
SLASH_FOREVERMOUSEOVERBUFF1 = "/fmb"
SlashCmdList.FOREVERMOUSEOVERBUFF = function(command) ns:Command(command) end
