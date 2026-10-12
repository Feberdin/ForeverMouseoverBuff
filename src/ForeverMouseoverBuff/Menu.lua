-- Purpose: the native Sanctum settings menu with six readable, focused pages.
-- Input: initialized preferences and detached Stats/Diagnostic snapshots.
-- Output: ordinary UI frames and deliberate calls to the existing command API.
-- Invariants: no cast, binding change, HTTP request or fabricated counter/rank.
-- Debug: /fmb opens the menu; lua tests/test_menu.lua checks navigation and actions.
local _, ns = ...
local unpackValues = unpack or table.unpack
local Menu = {pages = {}, navigation = {}, controls = {}, current = "buffs"}
ns.Menu = Menu
local modeNames = {auto = "Automatisch", might = "Macht", wisdom = "Weisheit", kings = "Könige"}
local views = {
    {id = "buffs", name = "Buffs & Taste"},
    {id = "messages", name = "Grüße & Chat"},
    {id = "sounds", name = "Töne"},
    {id = "stats", name = "Meine Statistik"},
    {id = "diagnostics", name = "Diagnose"},
    {id = "help", name = "Hilfe & Feedback"},
}

-- Presentation helpers keep coordinates local to each page. All setting changes
-- use App.Command, so the existing validation and combat deferral stay in charge.
local function text(parent, value, x, y, width, height, size, color)
    return ns.Theme.Text(parent, value, x, y, width, height, size or 13, color or ns.Theme.colors.text)
end
local function card(parent, y, height)
    ns.Theme.Rect(parent, 0, y, 588, height, ns.Theme.colors.panel)
    ns.Theme.Rect(parent, 0, y, 2, height, ns.Theme.colors.edge)
end
local function heading(page, title, subtitle)
    text(page, title, 0, 0, 588, 32, 23)
    text(page, subtitle, 0, 37, 588, 35, 12, ns.Theme.colors.muted)
end
local function toggle(parent, label, description, y, key, command)
    local button = ns.Theme.Toggle(parent, label, description, 0, y, 588, function()
        ns:Command(command .. (ns.db[key] and " off" or " on"))
    end)
    Menu.controls[key] = button
    return button
end
local function action(parent, label, x, y, width, command)
    return ns.Theme.Button(parent, label, x, y, width, 34, function() ns:Command(command) end)
end

local function buildBuffs(page)
    heading(page, "Deine Segen. Eine Taste.", "Für Paladine: Mouseover auswählen, Taste drücken und loslassen.\nDas Addon wählt einen passenden gelernten Segen.")
    card(page, 78, 76)
    text(page, "AKTUELLER STATUS", 16, 90, 550, 16, 10, ns.Theme.colors.muted)
    Menu.status = text(page, "", 16, 113, 550, 33, 14)
    card(page, 168, 64)
    text(page, "DEINE BUFF-TASTE", 16, 179, 220, 15, 10, ns.Theme.colors.muted)
    Menu.binding = text(page, "", 16, 199, 190, 23, 18, ns.Theme.colors.gold)
    text(page, "Ändern: WoW-Optionen → Tastaturbelegung\n→ Forever Mouseover Buff", 240, 183, 332, 36, 12, ns.Theme.colors.muted)
    text(page, "AUSWAHL AUSSERHALB DES KAMPFES", 0, 249, 588, 18, 10, ns.Theme.colors.muted)
    Menu.modeButtons = {}
    for index, mode in ipairs({"auto", "might", "wisdom", "kings"}) do
        local choice = mode
        Menu.modeButtons[choice] = action(page, modeNames[choice], (index - 1) * 150, 278, 138, choice)
    end
    Menu.controls.enabled = ns.Theme.Toggle(page, "Mouseover-Buffs aktiv", "Gelernte Segen für andere freundliche Spieler.", 0, 332, 588,
        function() ns:Command(ns.db.enabled and "off" or "on") end)
    Menu.combat = text(page, "", 0, 404, 588, 32, 12, ns.Theme.colors.muted)
end

local function buildMessages(page)
    heading(page, "Ein Gruß, der zu dir passt.", "Versand, Empfang und Anzeige lassen sich unabhängig voneinander einstellen.")
    toggle(page, "Automatische Grüße senden", "Nach bestätigtem Buff. AUS: keine automatischen Nachrichten versenden.", 78, "whisper", "whisper")
    ns.receiveButton = toggle(page, "Segensgrüße empfangen", "Für alle Klassen: automatische FMB-Grüße erlauben.", 156, "receiveWhispers", "receive")
    -- Preserve the saved positive display preference, but present quiet mode as
    -- an enabled default. Sending and receiving remain separate decisions.
    ns.outgoingButton = ns.Theme.Toggle(page, "Eigene Grüße verbergen",
        "Keine eigenen FMB-Grüße im Chat oder WIM; keine Popups oder WIM-Töne.", 0, 234, 588,
        function() ns:Command(ns.db.showOutgoingWhispers and "outgoing off" or "outgoing on") end)
    card(page, 322, 111)
    text(page, "Dein Chat bleibt deine Entscheidung", 16, 337, 550, 24, 15, ns.Theme.colors.gold)
    text(page, "Standard: Senden AN, eigene Grüße verbergen AN.\nPersönliche Whisper bleiben sichtbar. Empfänger mit FMB können\nautomatische Grüße selbst ausschalten – für jede Klasse.", 16, 368, 550, 55, 12, ns.Theme.colors.muted)
end

local function buildSounds(page)
    heading(page, "Hinweise, die du hören kannst.", "Zwei getrennte Schalter. Lautstärke und Wiedergabe richten sich nach den WoW-Soundoptionen.")
    toggle(page, "Hinweiston beim Buffen", "Wenn ein Tastendruck keinen Buff auslösen kann; begrenzt auf alle 2 Sekunden.", 78, "sound", "sound")
    toggle(page, "Siegel-Ablaufton", "Ein kurzer Ton nach dem beobachteten natürlichen Ende deines Siegels.", 156, "sealSound", "seal")
    action(page, "Hinweiston testen", 0, 239, 210, "soundtest")
    card(page, 301, 128)
    text(page, "Wann ertönt der Siegelton?", 16, 316, 550, 24, 15, ns.Theme.colors.gold)
    text(page, "Der Ablauf muss zuvor sicher beobachtet worden sein. Beim\nEinloggen, bei unlesbaren Auren oder bloßem Wechsel des Siegels\nist deshalb kein Ton garantiert. Ein Testton wird nur durch\ndeinen Klick auf „Hinweiston testen“ angefordert.", 16, 349, 550, 71, 12, ns.Theme.colors.muted)
end

local function buildStats(page)
    heading(page, "Jeder Segen zählt.", "Deine lokal erfassten FMB-Segen. Community-Zähler sind unbestätigt und kein offizielles Ranking.")
    card(page, 78, 85)
    Menu.total = text(page, "", 16, 88, 550, 40, 31, ns.Theme.colors.mint)
    Menu.statsNote = text(page, "Erfolgreiche Segen für andere Spieler", 16, 136, 550, 19, 12, ns.Theme.colors.muted)
    Menu.familyLabels, Menu.familyBars = {}, {}
    for index, family in ipairs({"might", "wisdom", "kings"}) do
        local y = 185 + (index - 1) * 45
        Menu.familyLabels[family] = text(page, modeNames[family], 0, y, 580, 20, 13)
        ns.Theme.Rect(page, 0, y + 26, 588, 3, ns.Theme.colors.row)
        Menu.familyBars[family] = ns.Theme.Rect(page, 0, y + 26, 1, 3, ns.Theme.colors.mint)
    end
    ns.rankingButton = toggle(page, "Ranking-Export bereitstellen", "Nur lokal vorbereiten. Ein Upload braucht einen separaten, bewussten Schritt.", 325, "rankingEnabled", "ranking")
    ns.uploadHelpButton = action(page, "Upload-Anleitung", 0, 400, 182, "ranking help")
    text(page, "Kein automatischer Upload aus dem Spiel.", 198, 407, 385, 28, 12, ns.Theme.colors.muted)
end

local function buildDiagnostics(page)
    heading(page, "Ein klarer Blick auf den Status.", "Lokale technische Codes ohne Spielernamen oder Whisper-Inhalte. Keine automatische Übertragung.")
    card(page, 78, 77)
    Menu.diagnosticCounts = text(page, "", 16, 91, 550, 26, 16, ns.Theme.colors.mint)
    Menu.diagnosticStorage = text(page, "", 16, 125, 550, 19, 12, ns.Theme.colors.muted)
    Menu.client = text(page, "", 0, 174, 588, 20, 12, ns.Theme.colors.muted)
    card(page, 207, 102)
    text(page, "LETZTE EREIGNISSE", 16, 219, 550, 18, 10, ns.Theme.colors.muted)
    Menu.events = text(page, "", 16, 244, 550, 60, 12)
    toggle(page, "Debug-Protokoll", "Zusätzliche Diagnose aktivieren; anschließend wieder ausschalten.", 323, "debug", "debug")
    action(page, "Protokoll im Chat", 0, 402, 185, "diag")
    text(page, "/reload oder Ausloggen speichert die Datei.", 199, 409, 387, 26, 11, ns.Theme.colors.muted)
end

local function buildHelp(page)
    heading(page, "Gemeinsam besser buffen.", "Hilfe direkt hier – Fehler, Wünsche und Ideen mit wenigen Schritten an Feberdin melden.")
    card(page, 78, 133)
    text(page, "Deine Rückmeldung zählt", 16, 92, 550, 25, 17, ns.Theme.colors.gold)
    text(page, "Bericht und technische Angaben erst prüfen. Danach den Link\nkopieren und die Meldung selbst auf GitHub absenden.", 16, 124, 550, 39, 12, ns.Theme.colors.muted)
    ns.feedbackButton = ns.Theme.Button(page, "Feedback & Hilfe auf GitHub", 16, 170, 357, 31,
        function() ns:ShowFeedbackPanel() end)
    text(page, "01   Taste einmal zuweisen", 0, 236, 588, 25, 15)
    text(page, "WoW-Optionen → Tastaturbelegung → Forever Mouseover Buff.", 32, 263, 550, 24, 12, ns.Theme.colors.muted)
    text(page, "02   Freundlichen Spieler mit der Maus wählen", 0, 306, 588, 25, 15)
    text(page, "Zum Wirken die Buff-Taste drücken und loslassen.", 32, 333, 550, 24, 12, ns.Theme.colors.muted)
    text(page, "03   Wenn etwas nicht klappt", 0, 376, 588, 25, 15)
    text(page, "Unter „Diagnose“ den Status prüfen oder eine Meldung vorbereiten.", 32, 403, 550, 30, 12, ns.Theme.colors.muted)
end

-- Construction is lazy: no hidden UI work during login or spell processing.
-- Pages reuse ordinary frames; opening or selecting a tab cannot arm a spell.
local function build()
    local theme = ns.Theme
    local panel = theme.Window("ForeverMouseoverBuffPanel", "", 840, 620)
    ns.panel = panel
    theme.Icon(panel, theme.Path("ProjectIcon"), 24, 22, 68, 68)
    text(panel, "FOREVER", 108, 24, 525, 20, 12, theme.colors.gold)
    text(panel, "Mouseover Buff", 106, 48, 580, 34, 27)
    text(panel, "Ein Segen. Ein Gruß. Gemeinsam durch Azeroth.", 108, 89, 580, 23, 12, theme.colors.muted)
    theme.Icon(panel, theme.Path("FeberdinKnight"), 734, 27, 50, 50)
    text(panel, "FEBERDIN", 720, 83, 78, 18, 10, theme.colors.gold)
    theme.Rect(panel, 20, 118, 798, 1, theme.colors.edge)
    theme.Rect(panel, 208, 138, 1, 410, theme.colors.edge)
    for index, view in ipairs(views) do
        local id = view.id
        Menu.navigation[id] = theme.Button(panel, view.name, 20, 140 + (index - 1) * 51, 171, 42,
            function() Menu.Select(id) end)
        local page = CreateFrame("Frame", nil, panel)
        page:SetSize(588, 438); page:SetPoint("TOPLEFT", panel, "TOPLEFT", 228, -137)
        Menu.pages[id] = page
    end
    theme.Rect(panel, 20, 493, 171, 63, theme.colors.panel)
    text(panel, "FÜR ALLE KLASSEN", 32, 504, 151, 16, 10, theme.colors.gold)
    text(panel, "Grüße empfangen oder\nausblenden – du entscheidest.", 32, 526, 151, 29, 10, theme.colors.muted)
    theme.Rect(panel, 20, 575, 798, 1, theme.colors.edge)
    text(panel, "v" .. ns.VERSION .. "  ·  Feberdin", 22, 590, 206, 17, 10, theme.colors.muted)
    text(panel, "Einstellungen direkt übernommen · Datei beim nächsten /reload", 254, 589, 563, 21, 10, theme.colors.muted)
    buildBuffs(Menu.pages.buffs)
    buildMessages(Menu.pages.messages)
    buildSounds(Menu.pages.sounds)
    buildStats(Menu.pages.stats)
    buildDiagnostics(Menu.pages.diagnostics)
    buildHelp(Menu.pages.help)
end

local function refreshStats()
    local summary = ns.Stats and ns.Stats.Summary()
    if not summary or summary.available == false then
        Menu.total:SetText("Statistik nicht verfügbar")
        Menu.statsNote:SetText("Zählerspeicher unverändert erhalten. Unter Diagnose den Status prüfen.")
        for _, family in ipairs({"might", "wisdom", "kings"}) do
            Menu.familyLabels[family]:SetText(modeNames[family] .. "  –")
            Menu.familyBars[family]:Hide()
        end
        return
    end
    Menu.total:SetText(tostring(summary.total))
    Menu.statsNote:SetText("Erfolgreiche Segen für andere Spieler · lokal, unbestätigt")
    for _, family in ipairs({"might", "wisdom", "kings"}) do
        local value = summary.families[family]
        Menu.familyLabels[family]:SetText(modeNames[family] .. "  ·  " .. tostring(value))
        local bar = Menu.familyBars[family]
        if value > 0 and summary.total > 0 then
            bar:SetWidth(588 * value / summary.total); bar:Show()
        else bar:Hide() end
    end
end
local function refreshDiagnostics()
    local snapshot = ns:DiagnosticSnapshot()
    Menu.diagnosticCounts:SetText(snapshot.attempts .. " Versuche    ·    " .. snapshot.confirmed .. " bestätigt    ·    " .. snapshot.failed .. " fehlgeschlagen")
    Menu.diagnosticStorage:SetText(snapshot.storageAvailable and "Protokoll lokal bereit" or "Protokoll nur im Arbeitsspeicher – Datei nicht verfügbar")
    local client = snapshot.status or {}
    Menu.client:SetText("Client " .. tostring(client.clientVersion or "unbekannt") .. "  ·  Build " .. tostring(client.clientBuild or "unbekannt"))
    local lines = {}
    for index = math.max(1, #snapshot.events - 3), #snapshot.events do
        local event = snapshot.events[index]
        lines[#lines + 1] = "[" .. event.severity .. "] " .. event.code
    end
    Menu.events:SetText(#lines > 0 and table.concat(lines, "\n") or "Noch keine Diagnoseereignisse in dieser Sitzung.")
end

-- Refresh runs with the existing App refresh cycle. Costly detached summaries
-- are read only on their visible page, never while the menu is closed.
function Menu.Refresh()
    if not ns.panel or not ns.panel:IsShown() then return end
    for key, button in pairs(Menu.controls) do button:SetValue(ns.db[key] == true) end
    ns.outgoingButton:SetValue(ns.db.showOutgoingWhispers ~= true)
    for mode, button in pairs(Menu.modeButtons) do button:SetSelected(ns.db.mode == mode) end
    Menu.binding:SetText(ns:BindingLabel())
    local decision = ns.decision
    Menu.status:SetText(decision and decision.text or "Status wird beim nächsten Mouseover geprüft.")
    local color = decision and decision.ready and ns.Theme.colors.mint or ns.Theme.colors.gold
    Menu.status:SetTextColor(unpackValues(color))
    Menu.combat:SetText(ns.combatDirty and "Kampfbelegung: Änderung wird nach dem Kampf übernommen."
        or "Im Kampf: dieselbe Taste wirkt Könige, sobald gelernt. Die automatische Prüfung vorhandener Segen pausiert.")
    if Menu.current == "stats" then refreshStats()
    elseif Menu.current == "diagnostics" then refreshDiagnostics() end
end
function Menu.Select(view)
    if not Menu.pages[view] then return false end
    Menu.current = view
    for id, page in pairs(Menu.pages) do
        if id == view then page:Show() else page:Hide() end
        Menu.navigation[id]:SetSelected(id == view)
    end
    Menu.Refresh()
    return true
end
function Menu.Show()
    if ns.HideFeedbackPanelForMenu then ns:HideFeedbackPanelForMenu() end
    if not ns.panel then build() end
    ns.panel:Show()
    Menu.Select(Menu.current)
end
