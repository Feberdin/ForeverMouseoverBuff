-- Purpose: native Sanctum settings, a short introduction and deliberate key setup.
-- Input: initialized preferences and detached Stats/Diagnostic snapshots.
-- Output: ordinary UI frames and deliberate calls to the existing command API.
-- Invariants: no cast or HTTP; key changes require explicit input outside combat.
-- Debug: /fmb opens the menu; lua tests/test_menu.lua checks navigation and actions.
local _, ns = ...
local unpackValues = unpack or table.unpack
local Menu = {pages = {}, navigation = {}, controls = {}, current = "buffs"}
ns.Menu = Menu
local modeNames = {auto = "Automatisch", might = "Macht", wisdom = "Weisheit", kings = "Könige"}
local function paladin() return ns:CasterClass() == "PALADIN" end
local views = {
    {id = "buffs", name = "Buffs & Taste"},
    {id = "priorities", name = "Klassen-Priorität"},
    {id = "messages", name = "Grüße & Chat"},
    {id = "sounds", name = "Töne"},
    {id = "stats", name = "Meine Statistik"},
    {id = "diagnostics", name = "Diagnose"},
    {id = "help", name = "Hilfe & Feedback"},
}

-- Presentation helpers keep coordinates local to each page. All setting changes
-- use App methods, so existing validation and combat deferral stay in charge.
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

-- Capture consumes both press and release. In particular, choosing an already
-- bound key must not let its key-up reach the buff router while this dialog is open.
-- Example: SHIFT down, F6 down, SHIFT up, F6 up still selects SHIFT-F6 once.
function Menu.CancelBinding(message)
    Menu.pendingKey, Menu.pendingInput = nil, nil
    if Menu.capture then
        Menu.capture:EnableKeyboard(false)
        Menu.capture:Hide()
    end
    if message and Menu.bindingNotice then Menu.bindingNotice:SetText(message) end
end
local function acceptKey(key)
    if not ns.Keybinding then
        Menu.captureMessage:SetText("Tastenmodul fehlt. Vollständiges Addon installieren und /reload ausführen.")
        return
    end
    local ok, message = ns.Keybinding.Assign(key)
    if ok then Menu.CancelBinding(message); Menu.Refresh()
    else Menu.captureMessage:SetText(message) end
end
local function inputDown(input)
    if input == "ESCAPE" then Menu.CancelBinding("Tastenwahl abgebrochen."); return end
    if not ns.Keybinding then return end
    local key = ns.Keybinding.FromInput(input)
    if key then Menu.pendingInput, Menu.pendingKey = input, key end
end
local function inputUp(input)
    if Menu.pendingInput ~= input then return end
    local key = Menu.pendingKey
    Menu.pendingInput, Menu.pendingKey = nil, nil
    acceptKey(key)
end
local function buildCapture(page)
    local capture = CreateFrame("Frame", nil, page)
    Menu.capture = capture
    capture:SetSize(588, 438); capture:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
    capture:SetFrameLevel(page:GetFrameLevel() + 20)
    ns.Theme.Rect(capture, 0, 0, 588, 438, ns.Theme.colors.bg)
    text(capture, "Deine Taste für AutoBuff", 16, 22, 556, 38, 23, ns.Theme.colors.gold)
    text(capture, "Jetzt die gewünschte Taste drücken und loslassen.\nAuch mit Umschalt, Strg, Alt oder Cmd kombinierbar.", 16, 84, 556, 54, 15)
    text(capture, "Maustaste oder Mausrad: Maus über dieses Feld bewegen.\nLinke und rechte Maustaste bleiben für die normale Bedienung frei.\nEine neue Taste ersetzt deine bisherigen Buff-Tasten.\nAndere belegte Tasten werden nicht überschrieben.", 16, 155, 556, 75, 12, ns.Theme.colors.muted)
    Menu.captureMessage = text(capture, "", 16, 248, 556, 78, 14, ns.Theme.colors.gold)
    Menu.captureCancel = ns.Theme.Button(capture, "Abbrechen (Escape)", 16, 359, 250, 36,
        function() Menu.CancelBinding("Tastenwahl abgebrochen.") end)
    capture:EnableMouse(true); capture:EnableMouseWheel(true)
    capture:SetPropagateKeyboardInput(false)
    capture:SetScript("OnKeyDown", function(_, key) inputDown(key) end)
    capture:SetScript("OnKeyUp", function(_, key) inputUp(key) end)
    capture:SetScript("OnMouseDown", function(_, key) inputDown(key) end)
    capture:SetScript("OnMouseUp", function(_, key) inputUp(key) end)
    capture:SetScript("OnMouseWheel", function(_, delta)
        if delta == 0 or not ns.Keybinding then return end
        acceptKey(ns.Keybinding.FromInput(delta > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN"))
    end)
    capture:SetScript("OnHide", function(self)
        self:EnableKeyboard(false)
        Menu.pendingInput, Menu.pendingKey = nil, nil
    end)
    capture:Hide()
end
function Menu.BeginBinding()
    Menu.Show()
    Menu.Select("buffs")
    if ns.API.Locked() then
        Menu.bindingNotice:SetText("Tastenwahl erst nach dem Kampf möglich.")
        return
    end
    Menu.captureMessage:SetText("Warte auf deine Taste …")
    Menu.capture:Show()
    Menu.capture:EnableKeyboard(true)
end

local function buildBuffs(page)
    heading(page, paladin() and "Segen und Heilung. Eine Taste." or "Deine Klassenbuffs. Eine Taste.",
        paladin() and "Für Paladine: Mouseover auswählen, Taste drücken und loslassen.\nAußerhalb des Kampfes im Stehen: unter 50 % Heilung, sonst Segen."
        or "Mouseover auswählen, Taste drücken und loslassen.\nGelernte direkte Buffs deiner Klasse; nur außerhalb des Kampfes.")
    -- Reserve three short lines for the reason and its concrete recovery step.
    card(page, 78, 82)
    text(page, "AKTUELLER STATUS", 16, 90, 550, 16, 10, ns.Theme.colors.muted)
    Menu.status = text(page, "", 16, 110, 550, 44, 12)
    card(page, 168, 102)
    text(page, "DEINE BUFF-TASTE", 16, 179, 220, 15, 10, ns.Theme.colors.muted)
    Menu.binding = text(page, "", 16, 201, 256, 24, 16, ns.Theme.colors.gold)
    Menu.bindingChoose = ns.Theme.Button(page, "Taste wählen", 284, 184, 155, 34, Menu.BeginBinding)
    Menu.bindingClear = ns.Theme.Button(page, "Entfernen", 449, 184, 123, 34, function()
        if ns.Keybinding then
            local _, message = ns.Keybinding.Clear()
            Menu.bindingNotice:SetText(message); Menu.Refresh()
        end
    end)
    Menu.bindingNotice = text(page, "Optional: WoW-Tastaturbelegung → Forever Mouseover Buff", 16, 234, 556, 28, 11, ns.Theme.colors.muted)
    text(page, "BUFFAUSWAHL AUSSERHALB DES KAMPFES", 0, 285, 588, 18, 10, ns.Theme.colors.muted)
    Menu.modeButtons = {}
    for index, row in ipairs(ns.Core.BuffModes(ns:CasterClass())) do
        local choice = row[1]
        Menu.modeButtons[choice] = action(page, row[2], (index - 1) * 150, 310, 138, choice)
    end
    Menu.controls.enabled = ns.Theme.Toggle(page, "Mouseover-Aktion aktiv", "Gelernte Klassenbuffs für andere freundliche Spieler.", 0, 356, 588,
        function() ns:Command(ns.db.enabled and "off" or "on") end)
    Menu.combat = text(page, "", 0, 421, 588, 16, 10, ns.Theme.colors.muted)
    buildCapture(page)
end

-- A single short page introduces the actual workflow. It shares the menu window
-- so Escape, feedback and the normal navigation never create stacked dialogs.
local function buildIntroduction(page)
    heading(page, "Willkommen bei AutoBuff.", "Forever Mouseover Buff – in drei Schritten startklar.\nDie Einführung findest du später unter Hilfe oder /fmb intro.")
    card(page, 78, 90)
    text(page, "1   Deine Buff-Taste wählen", 16, 90, 550, 26, 18, ns.Theme.colors.gold)
    Menu.introBindingStatus = text(page, "", 16, 120, 550, 20, 14, ns.Theme.colors.gold)
    text(page, "Die Taste wählst du selbst. Zum Einrichten oder Ändern unten klicken.", 16, 144, 550, 20, 12)
    -- The shared key has two OOC actions; explain the healing gate explicitly
    -- and reserve four lines so the combat exception remains readable too.
    card(page, 180, 112)
    text(page, "2   Maus über einen freundlichen Spieler", 16, 190, 550, 24, 17, ns.Theme.colors.gold)
    text(page, paladin() and "Dieselbe Taste: Segen oder Heilung – nur auf deinen Tastendruck.\nAußerhalb des Kampfes im Stehen, Ziel unter 50 %: Lichtblitz.\nWenn Lichtblitz nicht nutzbar ist: Heiliges Licht.\nIm eigenen Kampf sind Buffs zum PvP-Schutz gesperrt."
        or "Deine gelernten Klassenbuffs – nur auf deinen Tastendruck.\nGleichartige vorhandene Buffs bleiben erhalten.\nIm Kampf gesperrt. Auto wählt sichere Routinebuffs.\nWasserwandeln und Magieänderungen bewusst im Menü wählen.", 16, 220, 550, 64, 12)
    card(page, 304, 70)
    text(page, "3   Grüße nach deinem Geschmack", 16, 312, 550, 24, 17, ns.Theme.colors.gold)
    text(page, paladin() and "Standard: Grüße an, eigene Kopien verborgen. „Grüße & Chat“: ändern.\nAlle Klassen können dort den Empfang ausschalten."
        or "Alle Klassen können FMB-Grüße empfangen und automatisch danken.\nDas Senden persönlicher Segensgrüße gehört zum Paladin-Modul.", 16, 340, 550, 32, 12)
    Menu.introBinding = ns.Theme.Button(page, "Taste einrichten", 0, 388, 185, 38, Menu.BeginBinding)
    Menu.introMessages = ns.Theme.Button(page, "Grüße einstellen", 197, 388, 185, 38, function() Menu.Select("messages") end)
    Menu.introDone = ns.Theme.Button(page, "Los geht’s", 394, 388, 194, 38, function() Menu.Select("buffs") end)
end

-- Priority editing always starts with Core's detached active list. For example,
-- disabling Kings in {kings, wisdom, might} submits {wisdom, might}; re-enabling
-- it appends Kings. Reordering cannot edit another class or arm a spell.
local allFamilies = {"kings", "wisdom", "might"}
local function enable(button, enabled)
    if enabled then button:Enable() else button:Disable() end
end
local function savePriorities(priorities)
    Menu.priorityError = nil
    if not ns:SetClassPriorities(Menu.priorityClass, priorities) then
        Menu.priorityError = "Änderung nicht übernommen. Unter Diagnose den Status prüfen."
    end
    Menu.Refresh()
end
local function changePriority(family, direction)
    local priorities = ns.Core.GetPriorities(ns.db.classPriorities, Menu.priorityClass)
    if not priorities then return end
    local position
    for index, current in ipairs(priorities) do
        if current == family then position = index; break end
    end
    if direction == 0 then
        if position then table.remove(priorities, position)
        else priorities[#priorities + 1] = family end
    else
        local destination = position and position + direction
        if not destination or destination < 1 or destination > #priorities then return end
        priorities[position], priorities[destination] = priorities[destination], priorities[position]
    end
    savePriorities(priorities)
end
local function refreshPriorities()
    if not paladin() then
        Menu.priorityStatus:SetText("Diese Zielklassen-Prioritäten gehören zum Paladin-Modul.\nDeine eigenen Klassenbuffs wählst du unter „Buffs & Taste“.")
        for _, button in pairs(Menu.classButtons) do enable(button, false) end
        for _, row in ipairs(Menu.priorityRows) do
            row.label:SetText("Paladin-Segen")
            enable(row.active, false); enable(row.up, false); enable(row.down, false)
        end
        enable(Menu.priorityReset, false)
        return
    end
    local priorities = ns.Core.GetPriorities(ns.db.classPriorities, Menu.priorityClass)
    local order, active = {}, {}
    for _, family in ipairs(priorities or {}) do
        order[#order + 1] = family; active[family] = true
    end
    -- Always keep disabled choices visible below the active ordered list.
    for _, family in ipairs(allFamilies) do
        if not active[family] then order[#order + 1] = family end
    end
    for token, button in pairs(Menu.classButtons) do
        button:SetSelected(token == Menu.priorityClass)
    end
    for index, row in ipairs(Menu.priorityRows) do
        local family = order[index]
        row.family = family
        row.label:SetText((active[family] and (index .. ". ") or "– ") .. modeNames[family])
        row.active:SetText(active[family] and "AN" or "AUS")
        row.active:SetSelected(active[family] == true)
        enable(row.active, priorities ~= nil)
        enable(row.up, priorities ~= nil and active[family] and index > 1)
        enable(row.down, priorities ~= nil and active[family] and index < #priorities)
    end
    local note = priorities and (#priorities == 0 and "Kein Segen aktiviert – diese Klasse wird im Auto-Modus ausgelassen."
        or "Aktive Segen werden von oben nach unten geprüft; ausgeschaltete übersprungen.")
        or "Ungültige Priorität. Standard für diese Klasse wiederherstellen;\nbei beschädigten Gesamtdaten: /fmb priorities reset (alle Klassen)."
    Menu.priorityStatus:SetText(Menu.priorityError or note)
    Menu.priorityStatus:SetTextColor(unpackValues((Menu.priorityError or not priorities)
        and ns.Theme.colors.gold or ns.Theme.colors.muted))
end

-- All nine classes remain visible; no dropdown or role guessing is required.
-- Small independent buttons give every family an explicit on/off and order action.
local function buildPriorities(page)
    heading(page, "Segen nach Klasse priorisieren.", "Gilt im Auto-Modus außerhalb des Kampfes. Klasse wählen,\nSegen aktivieren und die Reihenfolge mit Hoch / Runter ändern.")
    Menu.classButtons, Menu.priorityRows = {}, {}
    Menu.priorityClass = "DRUID"
    for index, option in ipairs(ns.Core.ClassOptions()) do
        local token = option.token
        local x, y = ((index - 1) % 3) * 198, 78 + math.floor((index - 1) / 3) * 33
        Menu.classButtons[token] = ns.Theme.Button(page, option.name, x, y, 190, 28, function()
            Menu.priorityClass, Menu.priorityError = token, nil
            Menu.Refresh()
        end)
    end
    Menu.priorityStatus = text(page, "", 0, 178, 588, 31, 11, ns.Theme.colors.muted)
    for index = 1, 3 do
        local row, y = {}, 212 + (index - 1) * 47
        card(page, y, 40)
        row.label = text(page, "", 14, y + 10, 265, 24, 15)
        row.active = ns.Theme.Button(page, "", 292, y + 4, 70, 32,
            function() changePriority(row.family, 0) end)
        row.up = ns.Theme.Button(page, "Hoch", 374, y + 4, 94, 32,
            function() changePriority(row.family, -1) end)
        row.down = ns.Theme.Button(page, "Runter", 480, y + 4, 94, 32,
            function() changePriority(row.family, 1) end)
        Menu.priorityRows[index] = row
    end
    Menu.priorityReset = ns.Theme.Button(page, "Standard wiederherstellen", 0, 358, 256, 32, function()
        Menu.priorityError = nil
        if not ns:ResetClassPriorities(Menu.priorityClass) then
            Menu.priorityError = "Standard nicht übernommen. /fmb priorities reset\nsetzt alle Klassen zurück."
        end
        Menu.Refresh()
    end)
    text(page, "Eigene vorhandene Segen bleiben erhalten. Weitere fehlende Segen\nkönnen von anderen Paladinen ergänzt werden.", 0, 400, 588, 36, 12, ns.Theme.colors.muted)
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
    toggle(page, "Für Buffs und Heilung danken", "AN: /danke für Buffs. Bei wirksamer Heilung nur Spielern außerhalb der Gruppe danken. Ohne Zielwechsel, mit Spam-Sperre.", 312, "autoThanks", "thanks")
    text(page, "Standard: Danken AN. Unbekannte oder geschützte Buffgeber\nwerden ausgelassen. /fmb thanks off schaltet es sofort aus.", 0, 397, 588, 38, 12, ns.Theme.colors.muted)
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
    heading(page, "Paladin-Segen zählen.", "Zähler und Ranking erfassen ausschließlich Paladin-Segen. Andere Klassen können normal buffen.")
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
    Menu.introReplay = ns.Theme.Button(page, "Einführung erneut ansehen", 0, 228, 320, 34, function() Menu.ShowIntroduction() end)
    text(page, "Taste wählen: „Buffs & Taste“ oder /fmb bind.", 0, 271, 588, 24, 12, ns.Theme.colors.muted)
    text(page, "02   Freundlichen Spieler mit der Maus wählen", 0, 306, 588, 25, 15)
    text(page, "Dieselbe Taste wirkt deinen Klassenbuff – drücken und loslassen.", 32, 333, 550, 24, 12, ns.Theme.colors.muted)
    text(page, "03   Wenn etwas nicht klappt", 0, 376, 588, 25, 15)
    text(page, "Unter „Diagnose“ den Status prüfen oder eine Meldung vorbereiten.", 32, 403, 550, 30, 12, ns.Theme.colors.muted)
end

-- Construction is lazy: no hidden UI work during login or spell processing.
-- Pages reuse ordinary frames; opening or selecting a tab cannot arm a spell.
local function build()
    local theme = ns.Theme
    local panel = theme.Window("ForeverMouseoverBuffPanel", "", 840, 620)
    ns.panel = panel
    panel:SetScript("OnHide", function() Menu.CancelBinding() end)
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
        Menu.navigation[id] = theme.Button(panel, view.name, 20, 140 + (index - 1) * 47, 171, 40,
            function() Menu.Select(id) end)
        local page = CreateFrame("Frame", nil, panel)
        page:SetSize(588, 438); page:SetPoint("TOPLEFT", panel, "TOPLEFT", 228, -137)
        Menu.pages[id] = page
    end
    local intro = CreateFrame("Frame", nil, panel)
    intro:SetSize(588, 438); intro:SetPoint("TOPLEFT", panel, "TOPLEFT", 228, -137)
    Menu.pages.intro = intro
    theme.Rect(panel, 20, 493, 171, 63, theme.colors.panel)
    text(panel, "FÜR ALLE KLASSEN", 32, 504, 151, 16, 10, theme.colors.gold)
    text(panel, "Grüße empfangen oder\nausblenden – du entscheidest.", 32, 526, 151, 29, 10, theme.colors.muted)
    theme.Rect(panel, 20, 575, 798, 1, theme.colors.edge)
    text(panel, "v" .. ns.VERSION .. "  ·  Feberdin", 22, 590, 206, 17, 10, theme.colors.muted)
    text(panel, "Einstellungen direkt übernommen · Datei beim nächsten /reload", 254, 589, 563, 21, 10, theme.colors.muted)
    buildBuffs(Menu.pages.buffs)
    buildPriorities(Menu.pages.priorities)
    buildMessages(Menu.pages.messages)
    buildSounds(Menu.pages.sounds)
    buildStats(Menu.pages.stats)
    buildDiagnostics(Menu.pages.diagnostics)
    buildHelp(Menu.pages.help)
    buildIntroduction(intro)
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
    enable(ns.rankingButton, paladin())
    enable(ns.uploadHelpButton, paladin())
    local locked = ns.API.Locked()
    enable(Menu.bindingChoose, not locked)
    -- Native UPDATE_BINDINGS refreshes this status too, so external WoW changes
    -- and deliberate key setup never leave the introduction claiming readiness.
    local key = ns:BindingKey()
    Menu.introBindingStatus:SetText(key and ("Deine Buff-Taste: " .. ns:BindingLabel())
        or "Keine Buff-Taste belegt – bitte jetzt einrichten!")
    Menu.introBinding:SetText(key and "Taste ändern" or "Jetzt Taste einrichten")
    Menu.introDone:SetText(key and "Los geht’s" or "Später einrichten")
    enable(Menu.introBinding, not locked)
    enable(Menu.bindingClear, not locked and ns:BindingKey() ~= nil)
    if locked and Menu.capture:IsShown() then Menu.CancelBinding("Tastenwahl wegen Kampfbeginn abgebrochen.") end
    local decision = ns.decision
    Menu.status:SetText(decision and decision.text or "Status wird beim nächsten Mouseover geprüft.")
    local color = decision and decision.ready and ns.Theme.colors.mint or ns.Theme.colors.gold
    Menu.status:SetTextColor(unpackValues(color))
    Menu.combat:SetText(not paladin() and "Im Kampf: Klassenbuffs gesperrt. Schamanen benötigen passende Reagenzien."
        or ns.combatDirty and "Kampfbelegung: Änderung wird nach dem Kampf übernommen."
        or "Im eigenen Kampf: Buffs zum PvP-Schutz gesperrt.")
    if Menu.current == "priorities" then refreshPriorities()
    elseif Menu.current == "stats" then refreshStats()
    elseif Menu.current == "diagnostics" then refreshDiagnostics() end
end
function Menu.Select(view)
    if not Menu.pages[view] then return false end
    Menu.CancelBinding()
    Menu.current = view
    for id, page in pairs(Menu.pages) do
        if id == view then page:Show() else page:Hide() end
        if Menu.navigation[id] then Menu.navigation[id]:SetSelected(id == view) end
    end
    Menu.Refresh()
    return true
end
function Menu.ShowIntroduction()
    Menu.Show()
    Menu.Select("intro")
    -- Remember display only after construction succeeds. Closing is a valid skip;
    -- /fmb intro always reopens this same help page without resetting preferences.
    ns.db.introductionSeen = true
    ns.db.introductionVersion = ns.INTRODUCTION_VERSION
    ns.introductionPending = nil
end
function Menu.Show()
    if ns.HideFeedbackPanelForMenu then ns:HideFeedbackPanelForMenu() end
    if not ns.panel then build() end
    ns.panel:Show()
    Menu.Select(Menu.current)
end
