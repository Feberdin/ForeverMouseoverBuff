-- Purpose: let players prepare and review a GitHub report from the addon menu.
-- Input: deliberate button/slash actions and the IssueFeedback public projection.
-- Output: an optional technical preview and a selectable, fixed-destination URL.
-- Invariants: no HTTP, clipboard access, automatic submission or saved draft data.
-- Debug: /fmb feedback; missing modules show a recovery message, never raw errors.
local _, ns = ...
local kinds = {bug = "Fehler melden", wish = "Wunsch äußern", feature = "Feature vorschlagen"}
local descriptions = {
    bug = "Etwas funktioniert nicht? Beschreibe auf GitHub die Schritte und das erwartete Ergebnis.",
    wish = "Was könnte angenehmer werden? Teile deinen Wunsch für eine bestehende Funktion.",
    feature = "Eine neue Idee? Erkläre, welches Problem sie löst und wem sie hilft.",
}

local function text(parent, value, x, y, width, height, font)
    local item = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
    item:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    item:SetSize(width, height)
    item:SetJustifyH("LEFT"); item:SetJustifyV("TOP"); item:SetText(value)
    return item
end

local function button(parent, value, x, y, width, action)
    local item = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    item:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    item:SetSize(width, 28); item:SetText(value); item:SetScript("OnClick", action)
    return item
end

-- The preview is regenerated with the URL, so withdrawing the local opt-in
-- removes both together. A previous draft is never stored in SavedVariables.
function ns:UpdateFeedbackReport()
    local snapshot
    if self.feedbackIncludeTechnical then
        self:RefreshDiagnosticStatus()
        snapshot = self:DiagnosticSnapshot()
        snapshot.mode = self.db.mode
    end
    local report
    if self.IssueFeedback and type(self.IssueFeedback.Build) == "function" then
        report = self.IssueFeedback.Build(self.feedbackKind, snapshot, self.feedbackIncludeTechnical)
    end
    self.feedbackTechnicalButton:SetText(self.feedbackIncludeTechnical
        and "Technische Angaben: AN" or "Technische Angaben: AUS")
    for kind, item in pairs(self.feedbackKindButtons) do
        item:SetText((kind == self.feedbackKind and "|cffffd479" or "|cffb6bfc5") .. kinds[kind] .. "|r")
    end
    self.feedbackDescription:SetText(descriptions[self.feedbackKind])
    self.feedbackURLValue = report and report.url or ""
    self.feedbackURL:SetText(self.feedbackURLValue)
    self.feedbackURL:ClearFocus()
    self.feedbackPreview:SetText(report and report.preview
        or "Meldelink nicht verfügbar. Bitte das vollständige Addonpaket neu installieren und /reload ausführen. Hilfe: github.com/Feberdin/ForeverMouseoverBuff")
    if report then self.feedbackSelectButton:Enable() else self.feedbackSelectButton:Disable() end
end

-- This is an ordinary, unprotected window. Opening it must not reconfigure the
-- buff button or acquire keyboard focus while the player is moving.
function ns:ShowFeedbackPanel(kind)
    if not kinds[kind] then kind = "bug" end
    if not self.feedbackPanel then
        local panel = CreateFrame("Frame", "ForeverMouseoverBuffFeedbackPanel", UIParent, "BasicFrameTemplateWithInset")
        self.feedbackPanel = panel
        panel:SetSize(650, 590); panel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        panel:SetFrameStrata("DIALOG"); panel:SetClampedToScreen(true)
        panel:SetMovable(true); panel:EnableMouse(true); panel:RegisterForDrag("LeftButton")
        panel:SetScript("OnDragStart", function(self) self:StartMoving() end)
        panel:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
        if panel.TitleText then panel.TitleText:SetText("FMB · Feedback & Hilfe") end
        if type(UISpecialFrames) == "table" then UISpecialFrames[#UISpecialFrames + 1] = "ForeverMouseoverBuffFeedbackPanel" end
        text(panel, "|cffffd479FOREVER MOUSEOVER BUFF|r", 22, -43, 600, 25, "GameFontNormalLarge")
        text(panel, "Deine Idee macht das Addon besser.", 22, -74, 600, 24)
        self.feedbackKindButtons = {}
        for index, choice in ipairs({"bug", "wish", "feature"}) do
            local selected = choice
            self.feedbackKindButtons[choice] = button(panel, kinds[choice], 22 + (index - 1) * 204, -109, 198,
                function() ns.feedbackKind = selected; ns:UpdateFeedbackReport() end)
        end
        self.feedbackDescription = text(panel, "", 22, -149, 606, 42)
        self.feedbackTechnicalButton = button(panel, "", 22, -198, 244, function()
            ns.feedbackIncludeTechnical = not ns.feedbackIncludeTechnical
            ns:UpdateFeedbackReport()
        end)
        text(panel, "Freiwillig · Version, Schalter und feste Diagnosecodes", 278, -200, 347, 32, "GameFontHighlightSmall")
        text(panel, "VORSCHAU DER TECHNISCHEN ANGABEN", 22, -244, 605, 22, "GameFontNormalSmall")
        self.feedbackPreview = text(panel, "", 22, -273, 605, 173, "GameFontHighlightSmall")
        text(panel, "Keine Spielernamen, Whisper, Zähler oder vollständigen Logs. Beim Öffnen des Links erhält GitHub die ausgewählten Angaben. Erst mit dem Absenden wird dein Issue öffentlich. GitHub-Konto erforderlich.",
            22, -451, 605, 44, "GameFontHighlightSmall")
        self.feedbackURL = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
        self.feedbackURL:SetSize(594, 26); self.feedbackURL:SetPoint("TOPLEFT", panel, "TOPLEFT", 28, -503)
        self.feedbackURL:SetAutoFocus(false); self.feedbackURL:SetMultiLine(false)
        self.feedbackURL:SetMaxLetters(8192)
        self.feedbackURL:SetScript("OnEscapePressed", function(self) self:ClearFocus(); panel:Hide() end)
        self.feedbackURL:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
        -- A copy-only URL avoids a changed address contradicting the preview.
        self.feedbackURL:SetScript("OnTextChanged", function(self, userInput)
            if userInput then self:SetText(ns.feedbackURLValue or "") end
        end)
        panel:SetScript("OnHide", function() ns.feedbackURL:ClearFocus() end)
        self.feedbackSelectButton = button(panel, "Link markieren", 22, -545, 156, function()
            ns.feedbackURL:SetFocus(); ns.feedbackURL:HighlightText()
        end)
        text(panel, "1. Cmd/Strg+C    2. Im Browser öffnen    3. Prüfen & senden", 192, -549, 436, 30, "GameFontHighlightSmall")
    end
    self.feedbackKind, self.feedbackIncludeTechnical = kind, false
    self:UpdateFeedbackReport()
    self.feedbackPanel:Show()
end
